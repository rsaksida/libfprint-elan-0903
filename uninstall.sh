#!/bin/bash
# Go back to the stock libfprint. Prints enrolled with the patched library do
# not work with the stock one, so this user's prints are removed too. Prints of
# other users are not: run fprintd-delete for them before uninstalling.
set -eu

PREFIX=/opt/libfprint-elan0903
DROPIN=/etc/systemd/system/fprintd.service.d/elan-0903.conf

fprintd-delete "$(id -un)" || true
sudo rm -f "$DROPIN"
sudo systemctl daemon-reload
sudo systemctl stop fprintd || true
sudo rm -rf "$PREFIX"
echo "Stock libfprint restored."
