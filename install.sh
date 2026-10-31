#!/bin/bash
# Build the patched libfprint and make fprintd use it. System packages are not
# changed. Requires systemd. Run as your normal user; it asks for sudo where
# needed. See the README for build dependencies.
set -eu

UPSTREAM=https://gitlab.freedesktop.org/libfprint/libfprint.git
TAG=v1.94.100
COMMIT=80a4b5ec612892c5c056c48dddaa561452cf37ec
PREFIX=/opt/libfprint-elan0903
DROPIN=/etc/systemd/system/fprintd.service.d/elan-0903.conf

HERE="$(dirname "$(readlink -f "$0")")"
WORK="$HERE/build"

found=
for dev in /sys/bus/usb/devices/*; do
    if [ "$(cat "$dev/idVendor" 2> /dev/null)" = 04f3 ] &&
       [ "$(cat "$dev/idProduct" 2> /dev/null)" = 0903 ]; then
        found=1
    fi
done
if [ -z "$found" ]; then
    echo "No 04f3:0903 sensor found. This patch only changes that sensor." >&2
    exit 1
fi

rm -rf "$WORK"
git clone --quiet --depth 1 --branch "$TAG" "$UPSTREAM" "$WORK/libfprint"
if [ "$(git -C "$WORK/libfprint" rev-parse HEAD)" != "$COMMIT" ]; then
    echo "Upstream tag $TAG is not the expected commit $COMMIT." >&2
    exit 1
fi
git -C "$WORK/libfprint" apply "$HERE/patches/elan-0903-press-sensor.patch"

# Upstream's tests/meson.build fails to configure without introspection.
meson setup "$WORK/out" "$WORK/libfprint" --prefix="$PREFIX" --libdir=lib --buildtype=release \
    -Ddrivers=elan -Dintrospection=true -Dgtk-examples=false -Ddoc=false \
    -Dinstalled-tests=false -Dudev_rules=disabled -Dudev_hwdb=disabled
ninja -C "$WORK/out"

sudo rm -rf "$PREFIX"
sudo meson install --no-rebuild -C "$WORK/out"

sudo mkdir -p "$(dirname "$DROPIN")"
printf '[Service]\nEnvironment=LD_LIBRARY_PATH=%s/lib\n' "$PREFIX" | sudo tee "$DROPIN" > /dev/null
if command -v restorecon > /dev/null; then
    sudo restorecon -R "$PREFIX" "$(dirname "$DROPIN")"
fi
sudo systemctl daemon-reload
sudo systemctl stop fprintd || true
sudo systemctl start fprintd

PID="$(systemctl show -p MainPID --value fprintd)"
if ! sudo grep -q "$PREFIX" "/proc/$PID/maps"; then
    echo "fprintd did not load the patched library. Undo with ./uninstall.sh" >&2
    exit 1
fi

echo
echo "fprintd is running the patched library. Now enroll a finger:"
echo "  fprintd-delete \"\$USER\""
echo "  fprintd-enroll -f right-index-finger"
echo "  fprintd-verify"
