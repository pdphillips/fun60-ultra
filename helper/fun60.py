#!/usr/bin/env python3
"""FUN60 Ultra userspace helper. JSON on stdout, one object per run. Timeout < 2s."""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

VID_DEFAULT = 0x3151
DONGLE_PIDS = {0x503A, 0x5038, 0x5037, 0x502B}
BT_PIDS = {0x5027, 0x4012}
BUS_USB, BUS_BT = 3, 5
PROFILE_DIR = Path.home() / ".config/omarchy/fun60-ultra"
DEVICES_FILE = PROFILE_DIR / "devices.json"
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
UDEV_RULE = """# MonsGeek FUN60 Ultra / Akko vendor HID (VID 0x3151)
ACTION=="add|change", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3151", MODE="0660", GROUP="input", TAG+="uaccess"
ACTION=="add|change", SUBSYSTEM=="usb", ATTRS{idVendor}=="3151", MODE="0664", TAG+="uaccess"
ACTION=="add|change", SUBSYSTEM=="hidraw", KERNELS=="0005:3151:*", MODE="0660", GROUP="input", TAG+="uaccess"
"""

HIDIOCSFEATURE = lambda n: 0xC0004806 | (n << 16)
HIDIOCGFEATURE = lambda n: 0xC0004807 | (n << 16)


def emit(obj: dict, code: int = 0) -> None:
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()
    raise SystemExit(code)


def fail(msg: str, code: int = 1, **extra) -> None:
    emit({"ok": False, "error": msg, **extra}, code)


def alarm(_sig, _frm) -> None:
    fail("timeout", 1)


def extra_ids() -> set[tuple[int, int | None]]:
    out: set[tuple[int, int | None]] = {(VID_DEFAULT, None)}
    if not DEVICES_FILE.is_file():
        return out
    try:
        data = json.loads(DEVICES_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return out
    for item in data.get("extra") or []:
        try:
            vid_s, pid_s = str(item).replace("0x", "").split(":", 1)
            out.add((int(vid_s, 16), int(pid_s, 16)))
        except (ValueError, TypeError):
            continue
    return out


def hid_id(uevent: str) -> tuple[int, int, int] | None:
    for line in uevent.splitlines():
        if line.startswith("HID_ID="):
            parts = line.split("=", 1)[1].split(":")
            if len(parts) == 3:
                return tuple(int(p, 16) for p in parts)  # type: ignore[return-value]
    return None


def hid_name(uevent: str) -> str:
    for line in uevent.splitlines():
        if line.startswith("HID_NAME="):
            return line.split("=", 1)[1].strip()
    return ""


def allowed(bus: int, vid: int, pid: int) -> bool:
    for av, ap in extra_ids():
        if vid == av and (ap is None or ap == pid):
            return True
    return False


def classify(bus: int, pid: int, name: str) -> str:
    n = name.lower()
    if bus == BUS_BT or pid in BT_PIDS:
        return "bt"
    if pid in DONGLE_PIDS or "dongle" in n or "receiver" in n or "2.4" in n:
        return "2.4g"
    if bus == BUS_USB:
        return "wired"
    return "none"


def enumerate_hid() -> list[dict]:
    root = Path("/sys/class/hidraw")
    if not root.is_dir():
        return []
    found = []
    for node in sorted(root.iterdir()):
        uevent_path = node / "device" / "uevent"
        try:
            text = uevent_path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        hid = hid_id(text)
        if not hid:
            continue
        bus, vid, pid = hid
        if not allowed(bus, vid, pid):
            continue
        name = hid_name(text)
        found.append({
            "path": f"/dev/{node.name}",
            "bus": bus,
            "vid": vid,
            "pid": pid,
            "name": name,
            "link": classify(bus, pid, name),
        })
    # Prefer vendor config nodes: keep order, callers try ioctl until 0x8F echoes.
    return found


def pack(cmd: int, params: bytes = b"") -> bytearray:
    buf = bytearray(64)
    buf[1] = cmd & 0xFF
    buf[2:2 + len(params)] = params[:6]
    buf[8] = 255 - (sum(buf[1:8]) & 255)
    return buf


def feature(fd: int, buf: bytearray, write: bool) -> bytearray | None:
    import fcntl
    op = HIDIOCSFEATURE(64) if write else HIDIOCGFEATURE(64)
    try:
        fcntl.ioctl(fd, op, buf, True)
        return buf
    except OSError:
        return None


def query(path: str, cmd: int, params: bytes = b"", expect_echo: bool = True) -> bytes | None:
    try:
        fd = os.open(path, os.O_RDWR)
    except OSError:
        return None
    try:
        for _ in range(3):
            sent = pack(cmd, params)
            if feature(fd, sent, True) is None:
                return None
            time.sleep(0.06)
            got = bytearray(64)
            resp = feature(fd, got, False)
            if resp is None:
                continue
            if not expect_echo or resp[1] == cmd:
                return bytes(resp)
        return None
    finally:
        os.close(fd)


def probe(dev: dict) -> dict:
    info = {
        "protocol": "unknown",
        "writeSupported": False,
        "writeVia": None,
        "actuationMm": None,
        "rtOn": None,
        "rtTravelMm": None,
        "snapOn": None,
        "battery": None,
        "charging": False,
        "hidOk": False,
        "profileIndex": None,
    }
    path = dev["path"]
    if dev["link"] == "2.4g":
        f7 = query(path, 0xF7, expect_echo=False)
        if f7:
            info["hidOk"] = True
            batt = f7[2]
            if 0 < batt <= 100:
                info["battery"] = batt
            info["charging"] = bool(f7[4])
    echo = query(path, 0x8F)
    if echo and echo[1] == 0x8F:
        info["protocol"] = "ry5088"
        info["hidOk"] = True
        mag = query(path, 0xE5, bytes([0x00, 0x00, 0x00]), expect_echo=False)
        if mag:
            raw = mag[1] | (mag[2] << 8)
            prec = 100 if raw > 40 else 10
            mm = round(raw / prec, 2)
            if 0.1 <= mm <= 3.4:
                info["actuationMm"] = mm
        mode = query(path, 0xE5, bytes([0x07, 0x00, 0x00]), expect_echo=False)
        if mode:
            b = mode[1]
            info["rtOn"] = bool(b & 0x80)
            info["snapOn"] = (b & 0x07) == 7
        rt = query(path, 0xE5, bytes([0x02, 0x00, 0x00]), expect_echo=False)
        if rt:
            raw = rt[1] | (rt[2] << 8)
            prec = 100 if raw > 20 else 10
            mm = round(raw / prec, 2)
            if 0.01 <= mm <= 2.0:
                info["rtTravelMm"] = mm
        prof = query(path, 0x84)
        if prof and prof[1] == 0x84:
            info["profileIndex"] = int(prof[2])
    if shutil.which("iot_driver"):
        info["writeSupported"] = True
        info["writeVia"] = "iot_driver"
    return info


def pick_device() -> dict | None:
    devices = enumerate_hid()
    if not devices:
        return None
    for d in devices:
        echo = query(d["path"], 0x8F)
        if echo and echo[1] == 0x8F:
            return d
    for d in devices:
        if d["link"] == "2.4g":
            f7 = query(d["path"], 0xF7, expect_echo=False)
            if f7:
                return d
    return devices[0]


def hex_id(n: int | None) -> str | None:
    return None if n is None else f"0x{n:04X}"


def status_obj(dev: dict | None, extras: dict | None = None) -> dict:
    extras = extras or {}
    if not dev:
        return {
            "ok": False,
            "connected": False,
            "link": "none",
            "vid": hex_id(VID_DEFAULT),
            "pid": None,
            "path": None,
            "name": "",
            "battery": None,
            "charging": False,
            "protocol": "none",
            "writeSupported": False,
            "writeVia": None,
            "actuationMm": None,
            "rtOn": None,
            "rtTravelMm": None,
            "snapOn": None,
            "error": "no device",
            **extras,
        }
    return {
        "ok": True,
        "connected": True,
        "link": dev["link"],
        "vid": hex_id(dev["vid"]),
        "pid": hex_id(dev["pid"]),
        "path": dev["path"],
        "name": dev.get("name") or "",
        **extras,
    }


def wrap_iot(args: list[str]) -> subprocess.CompletedProcess[str] | None:
    exe = shutil.which("iot_driver")
    if not exe:
        return None
    try:
        return subprocess.run([exe, *args], capture_output=True, text=True, timeout=1.5)
    except (OSError, subprocess.TimeoutExpired):
        return subprocess.CompletedProcess(args, 1, "", "iot_driver failed")


def need_device() -> tuple[dict, dict]:
    dev = pick_device()
    if not dev:
        fail("no device", 2, connected=False, link="none")
    probed = probe(dev)
    return dev, probed


def clamp_mm(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, round(value, 2)))


def profile_path(name: str) -> Path:
    if not NAME_RE.match(name):
        fail("invalid profile name")
    return PROFILE_DIR / f"{name}.json"


def write_profile(path: Path, data: dict) -> None:
    PROFILE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    tmp.replace(path)
    os.chmod(path, 0o600)


def cmd_status(_args: argparse.Namespace) -> None:
    dev = pick_device()
    if not dev:
        fail("no device", 2, connected=False, link="none", vid=hex_id(VID_DEFAULT))
    probed = probe(dev)
    emit(status_obj(dev, probed))


def cmd_get_actuation(_args: argparse.Namespace) -> None:
    dev, probed = need_device()
    mm = probed.get("actuationMm")
    if mm is None:
        fail("unknown opcode", 3, connected=True, hint="requires helper / unknown opcode")
    emit({"ok": True, "mm": mm, **status_obj(dev, probed)})


def cmd_set_actuation(args: argparse.Namespace) -> None:
    mm = clamp_mm(float(args.mm), 0.1, 3.4)
    dev, probed = need_device()
    if not probed.get("writeSupported"):
        fail("unknown opcode", 3, hint="requires helper / unknown opcode", connected=True)
    ran = wrap_iot(["set-actuation", f"{mm:.2f}"])
    if ran is None or ran.returncode != 0:
        fail("unknown opcode", 3, hint="requires helper / unknown opcode")
    emit({"ok": True, "mm": mm, "via": "iot_driver"})


def cmd_rt(args: argparse.Namespace) -> None:
    on = bool(args.on)
    dev, probed = need_device()
    if not probed.get("writeSupported"):
        fail("unknown opcode", 3, hint="requires helper / unknown opcode", connected=True)
    argv = ["set-rt", "on" if on else "off"]
    if on and args.mm is not None:
        argv.append(f"{clamp_mm(float(args.mm), 0.01, 2.0):.2f}")
    ran = wrap_iot(argv)
    if ran is None or ran.returncode != 0:
        fail("unknown opcode", 3, hint="requires helper / unknown opcode")
    emit({"ok": True, "on": on, "via": "iot_driver"})


def cmd_snap(_args: argparse.Namespace) -> None:
    need_device()
    fail("unknown opcode", 3, hint="requires helper / unknown opcode")


def cmd_profile_save(args: argparse.Namespace) -> None:
    path = profile_path(args.name)
    data = {
        "name": args.name,
        "actuationMm": None if args.actuation is None else clamp_mm(float(args.actuation), 0.1, 3.4),
        "rtOn": None if args.rt is None else args.rt == "on",
        "rtTravelMm": None if args.rt_mm is None else clamp_mm(float(args.rt_mm), 0.01, 2.0),
        "snapOn": None if args.snap is None else args.snap == "on",
    }
    write_profile(path, data)
    emit({"ok": True, "name": args.name, "profile": data})


def cmd_profile_load(args: argparse.Namespace) -> None:
    path = profile_path(args.name)
    if not path.is_file():
        fail("profile not found")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        fail("profile unreadable")
    emit({"ok": True, "name": args.name, "profile": data})


def cmd_profile_list(_args: argparse.Namespace) -> None:
    names = []
    if PROFILE_DIR.is_dir():
        names = sorted(p.stem for p in PROFILE_DIR.glob("*.json") if p.name != "devices.json")
    emit({"ok": True, "profiles": names})


def cmd_udev(_args: argparse.Namespace) -> None:
    emit({"ok": True, "rule": UDEV_RULE})


def main() -> None:
    signal.signal(signal.SIGALRM, alarm)
    signal.setitimer(signal.ITIMER_REAL, 1.8)
    p = argparse.ArgumentParser(add_help=True)
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status")
    sub.add_parser("get-actuation")

    sa = sub.add_parser("set-actuation")
    sa.add_argument("--mm", required=True, type=float)

    rt = sub.add_parser("rt")
    g = rt.add_mutually_exclusive_group(required=True)
    g.add_argument("--on", action="store_true")
    g.add_argument("--off", action="store_true")
    rt.add_argument("--mm", type=float, default=None)

    sn = sub.add_parser("snap")
    sg = sn.add_mutually_exclusive_group(required=True)
    sg.add_argument("--on", action="store_true")
    sg.add_argument("--off", action="store_true")

    ps = sub.add_parser("profile-save")
    ps.add_argument("--name", required=True)
    ps.add_argument("--actuation", type=float, default=None)
    ps.add_argument("--rt", choices=("on", "off"), default=None)
    ps.add_argument("--rt-mm", type=float, default=None)
    ps.add_argument("--snap", choices=("on", "off"), default=None)

    pl = sub.add_parser("profile-load")
    pl.add_argument("--name", required=True)
    sub.add_parser("profile-list")
    sub.add_parser("udev-rule")

    args = p.parse_args()
    {
        "status": cmd_status,
        "get-actuation": cmd_get_actuation,
        "set-actuation": cmd_set_actuation,
        "rt": cmd_rt,
        "snap": cmd_snap,
        "profile-save": cmd_profile_save,
        "profile-load": cmd_profile_load,
        "profile-list": cmd_profile_list,
        "udev-rule": cmd_udev,
    }[args.cmd](args)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        emit({"ok": False, "error": "helper failed"}, 1)
