#!/usr/bin/env bash
# User-run installer for iot_driver (monsgeek-akko-linux). Never invoke from QML with sudo.
set -euo pipefail

VID="3151"
AUTHOR_PID="502B"
NEEDED_GROUP="input"
PREFIX="${PREFIX:-/usr/local}"
CLONE_DIR="${CLONE_DIR:-$HOME/.cache/monsgeek-akko-linux}"
REPO="https://github.com/echtzeit-solutions/monsgeek-akko-linux.git"
USER_NAME="$(id -un)"

if [[ $EUID -eq 0 ]]; then
  echo "error: refuse to run as root (cargo / make driver must run as the user)" >&2
  echo "run: ./helper/install-iot-driver.sh" >&2
  exit 1
fi

need_sudo() { sudo "$@"; }

case "$CLONE_DIR" in
  ""|"/"|"$HOME"|"$HOME/")
    echo "error: CLONE_DIR is unsafe: ${CLONE_DIR:-<empty>}" >&2
    exit 1
    ;;
esac

echo "==> groups"
if ! getent group "$NEEDED_GROUP" >/dev/null; then
  echo "group $NEEDED_GROUP missing; creating"
  need_sudo groupadd --system "$NEEDED_GROUP"
fi

ADDED_GROUP=0
if id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx "$NEEDED_GROUP"; then
  echo "user $USER_NAME already in $NEEDED_GROUP"
else
  echo "adding $USER_NAME to $NEEDED_GROUP"
  need_sudo usermod -aG "$NEEDED_GROUP" "$USER_NAME"
  ADDED_GROUP=1
  echo "LOGOUT REQUIRED: full graphical logout (not a new terminal)."
  echo "This session cannot open hidraw with the new group yet. Driver install continues."
fi

echo "==> packages"
need_sudo pacman -S --needed --noconfirm base-devel pkgconf hidapi protobuf alsa-lib git

if ! command -v rustc >/dev/null || ! command -v cargo >/dev/null; then
  echo "==> rustup (user install)"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
# shellcheck disable=SC1091
if [[ -f "$HOME/.cargo/env" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.cargo/env"
fi
if ! command -v cargo >/dev/null; then
  echo "error: cargo not on PATH (install rustup or add ~/.cargo/bin)" >&2
  exit 1
fi

echo "==> clone/build driver (user, not root)"
rm -rf "$CLONE_DIR"
git clone --depth 1 "$REPO" "$CLONE_DIR"
(
  cd "$CLONE_DIR"
  make driver
  need_sudo make install SKIP_REFRESH=1 PREFIX="$PREFIX"
)

echo "==> drop clone"
rm -rf "$CLONE_DIR"

echo "==> udev"
need_sudo udevadm control --reload-rules
need_sudo udevadm trigger --subsystem-match=hidraw --subsystem-match=usb || true

export PATH="${PREFIX}/bin:${PATH}"
IOT="${PREFIX}/bin/iot_driver"

echo "==> verify binary"
if [[ ! -x "$IOT" ]]; then
  echo "error: missing $IOT" >&2
  exit 1
fi
if ! command -v iot_driver >/dev/null; then
  echo "error: iot_driver not on PATH (expected $IOT)" >&2
  exit 1
fi
echo "iot_driver: $(command -v iot_driver)"

echo "==> iot_driver info (keyboard optional)"
if iot_driver info; then
  :
else
  echo "warning: iot_driver info failed — binary is installed; no keyboard/dongle, or hidraw not accessible in this session." >&2
  echo "warning: author dongle is USB ${VID}:${AUTHOR_PID}; hidraw path varies (do not assume /dev/hidraw0)." >&2
  echo "warning: plug the device; full graphical logout if you were just added to group ${NEEDED_GROUP}." >&2
fi

echo "==> USB (optional)"
if command -v lsusb >/dev/null; then
  if lsusb | grep -qi "$VID"; then
    echo "USB VID $VID visible (author FUN60 Ultra 2.4G dongle is ${VID}:${AUTHOR_PID}; hidraw path varies, not always hidraw0)"
    lsusb | grep -i "$VID" || true
  else
    echo "warning: no VID $VID device on USB (plug 2.4G dongle or use wired); continuing"
  fi
else
  echo "warning: lsusb not found; skip USB probe"
fi

echo
echo "Done installing. Binary: $IOT"
echo "Still manual:"
if [[ $ADDED_GROUP -eq 1 ]]; then
  echo "  1. Full graphical logout is required (this session cannot use group $NEEDED_GROUP / hidraw yet)"
else
  echo "  1. hidraw should be group $NEEDED_GROUP mode 660; path varies (not always /dev/hidraw0)"
fi
echo "  2. Unplug and replug the 2.4G dongle"
echo "  3. After logout: groups | grep $NEEDED_GROUP"
echo "  4. iot_driver info"
echo "  5. iot_driver tui   OR   iot_driver serve  (then https://app.monsgeek.com)"
echo "  6. omarchy plugin enable pdphillips.fun60-ultra"
