# Omarchy plugin for MonsGeek FUN60 Ultra

Status + launcher; writes via community driver.

This is **not official MonsGeek software**. Plugins run **unsandboxed** inside `omarchy-shell`. Read this repo before enabling.

MonsGeek and Akko are trademarks of their owners.

## Credit

HID writes and the Linux protocol implementation come from **[echtzeit-solutions/monsgeek-akko-linux](https://github.com/echtzeit-solutions/monsgeek-akko-linux)** (RongYuan RY5088 userspace driver / `iot_driver`).

This plugin is a thin Omarchy QML shell around detection + that driver. It does not vendor that tree.

## What v1 does

- Bar widget: connection status (click opens the panel)
- Panel: status, local profile JSON, udev rule copy, link to the official web app
- Detect USB HID **3151:502B** (MonsGeek/Akko VID `0x3151`)
- `hidOk` via hidraw (enumerates matching nodes; **never assumes `/dev/hidraw0`**)
- Settings writes **only** when `iot_driver` is installed and on `PATH`

## What v1 does not do

- Firmware flash
- Invent HID protocol / opcodes
- Guaranteed RGB, DKS, or remap in QML
- Official MonsGeek support

## Install (public repo)

```sh
omarchy plugin add https://github.com/pdphillips/fun60-ultra.git --enable
omarchy-shell shell rescanPlugins
```

Place the widget if it is not already on the bar:

```sh
omarchy bar move pdphillips.fun60-ultra --section right
```

### Local copy if `plugin add` is not used

Copy the tree (no symlinks):

```sh
cp -a . ~/.config/omarchy/plugins/pdphillips.fun60-ultra
omarchy plugin validate ~/.config/omarchy/plugins/pdphillips.fun60-ultra
omarchy plugin enable pdphillips.fun60-ultra
```

## Permissions (required)

Without these, the helper times out or reports `hidOk` false.

```sh
sudo usermod -aG input $USER
# log out of the graphical session, not just a new terminal
```

udev: install `helper/99-fun60-ultra.rules` **and/or** the rules from [monsgeek-akko-linux](https://github.com/echtzeit-solutions/monsgeek-akko-linux)
(`sudo make install` of that project drops `/usr/lib/udev/rules.d/99-monsgeek.rules`).

Then unplug/replug the 2.4G dongle. hidraw group should be `input`, mode `660`.

**Never assume `/dev/hidraw0`** — enumerate `3151` nodes. The hidraw path varies.

Example udev install of this plugin’s rule:

```sh
sudo cp helper/99-fun60-ultra.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

## Community driver (required to change actuation / Rapid Trigger / etc.)

```sh
git clone https://github.com/echtzeit-solutions/monsgeek-akko-linux.git
cd monsgeek-akko-linux
# Arch / Omarchy:
sudo pacman -S --needed base-devel pkgconf hidapi protobuf alsa-lib
# rustup if needed
make driver
sudo make install SKIP_REFRESH=1
# installs iot_driver to /usr/local/bin/iot_driver
# source clone can be deleted after install
which iot_driver
iot_driver list
iot_driver info
iot_driver triggers
iot_driver tui
iot_driver serve   # then https://app.monsgeek.com in Chromium/Brave
```

If `iot_driver` is missing, the plugin reports `writeSupported: false` and does not invent packets.

## Verify

```sh
python3 helper/fun60.py status
# expect connected true, vid 0x3151 pid 0x502B, hidOk true
# writeSupported true only if iot_driver is on PATH
```

The helper prints one JSON object to stdout and exits (timeout ~1.8s). It fails closed.

### Author hardware (example — not the only node)

Observed on one FUN60 Ultra, stock firmware:

| | |
|---|---|
| VID/PID | `3151:502B` |
| Type | 2.4G `HidDongle` |
| Name | `MonsGeek 2.4G Wireless Keyboard` |
| hidraw | **varies** (has been `hidraw11`, not always `hidraw0`) |
| `iot_driver info` | Firmware v306, Device ID 2307, Protocol RY5088, stock firmware |

Other `3151:*` hidraw nodes may exist on the same machine. Enumerate; do not hardcode a path.

## Remove

```sh
omarchy plugin remove pdphillips.fun60-ultra
```

Optional: `sudo rm /etc/udev/rules.d/99-fun60-ultra.rules` and reload udev. Uninstalling `iot_driver` is separate (`monsgeek-akko-linux` `make uninstall` if you used that install).
