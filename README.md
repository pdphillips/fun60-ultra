# FUN60 Ultra

Unofficial Omarchy Quattro plugin for a MonsGeek FUN60 Ultra (HE/TMR). It is a thin Linux-side surface: a bar widget, a settings panel, and a small hidraw helper. It is **not** the official MonsGeek driver and is **not** affiliated with or supported by MonsGeek.

Official Windows/web software covers remapping, per-key RGB, DKS, macros, calibration, and firmware. This plugin does not. v1 only exposes connection state, global actuation, Rapid Trigger, Snap Key (when the opcode is known), and local profile JSON.

## Install

```sh
omarchy plugin add https://github.com/pdphillips/fun60-ultra.git --enable
```

Plugins run unsandboxed inside `omarchy-shell`. Read this repo before enabling.

Place the widget:

```sh
omarchy bar move pdphillips.fun60-ultra --section right
```

## udev (required for HID writes)

The plugin never installs udev rules and never asks for sudo. Copy the example yourself:

```sh
sudo cp helper/99-fun60-ultra.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

Unplug and replug the keyboard or 2.4G dongle. The panel’s **Copy udev rule** button copies the same text.

## What this plugin can and cannot do

| | Official MonsGeek (web/desktop) | This plugin |
|---|---|---|
| Platform | Windows; web driver expects WebUSB / a local `iot_driver` | Linux Omarchy shell |
| Actuation 0.1–3.4 mm | Yes | Yes, if HID protocol matches **and** `iot_driver` is on `PATH` |
| Rapid Trigger | Yes | Same as actuation |
| Snap Key / SOCD | Yes | Shown; writes disabled until the SET opcode is confirmed |
| DKS, RGB, macros, firmware | Yes | **Not in v1** |
| Cloud backup / accounts | Yes | Never |

**Open official web driver** launches Chromium/Brave (else `xdg-open`) at https://app.monsgeek.com (also https://web.monsgeek.com). That site is not claimed to work on Linux.

## Device detection

Default match: USB HID **VID `0x3151`** (MonsGeek/Akko), any PID. Observed identities:

- `3151:502B` — 2.4G wireless keyboard / dongle (FUN60-class name string)
- `3151:5030` — wired “MonsGeek Keyboard” (same VID; also used by M1 V5 HE)

Confirm on your machine with `lsusb`. The helper prefers a hidraw node that answers `GET_USB_VERSION` (`0x8F`), else a dongle that answers `0xF7`, else the first match.

```sh
lsusb | grep -i 3151
python3 helper/fun60.py status
```

Add another VID:PID in `~/.config/omarchy/fun60-ultra/devices.json` (mode 0600):

```json
{ "extra": ["145f:5030"] }
```

Link mode is inferred from bus and known dongle/BT PIDs (`0x503A`/`0x5038`/`0x5037` = 2.4G, `0x5027`/`0x4012` = Bluetooth). Battery is read from dongle `GET_DONGLE_STATUS` (`0xF7`) when that query works.

## Helper

`helper/fun60.py` prints one JSON object and exits. Timeout 1.8s. Exit `2` if no device, `3` if a write opcode is unknown.

```
python3 helper/fun60.py status
python3 helper/fun60.py get-actuation
python3 helper/fun60.py set-actuation --mm 1.5
python3 helper/fun60.py rt --on|--off [--mm 0.3]
python3 helper/fun60.py snap --on|--off
python3 helper/fun60.py profile-save --name default --actuation 1.5 --rt on --rt-mm 0.3 --snap off
python3 helper/fun60.py profile-load --name default
python3 helper/fun60.py udev-rule
```

Reads use documented RY5088 HID feature reports (`0x8F`, `0xE5`, `0xF7`) via hidraw ioctls. **Writes are not invented.** If [echtzeit-solutions/monsgeek-akko-linux](https://github.com/echtzeit-solutions/monsgeek-akko-linux) `iot_driver` is on `PATH`, actuation and Rapid Trigger wrap that CLI. Otherwise those controls stay disabled with `requires helper / unknown opcode`. Snap Key writes always report unknown opcode in v1.

Local profiles: `~/.config/omarchy/fun60-ultra/<name>.json`, directory `0700`, files `0600`.

## Validate / enable (from a checkout)

```sh
omarchy plugin validate .
omarchy plugin add https://github.com/pdphillips/fun60-ultra.git --enable
omarchy-shell shell rescanPlugins
```

## Security

Omarchy plugins are unsandboxed in the long-lived shell process. This helper only talks to hidraw nodes for VID `0x3151` (plus optional `devices.json` extras). It does not flash firmware, does not send secrets, and does not talk to the network.

## Credits

Protocol notes come from community work on MonsGeek/Akko HID, especially [echtzeit-solutions/monsgeek-akko-linux](https://github.com/echtzeit-solutions/monsgeek-akko-linux) (RY5088 feature reports) and [Automata02/fun60-keymap](https://github.com/Automata02/fun60-keymap) (FUN60 keymap/cloud-backup observations). This repo does not vendor those trees.

MonsGeek, FUN60 Ultra, and related marks belong to their owners.

## Remove

```sh
omarchy plugin remove pdphillips.fun60-ultra
```

Optional: `sudo rm /etc/udev/rules.d/99-fun60-ultra.rules` and reload udev.
