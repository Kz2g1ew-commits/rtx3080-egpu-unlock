#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Remove everything install.sh put in place. Takes effect for the next nvidia
# load; a card already unlocked stays so until it is powered off.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
rm -f /etc/modprobe.d/95-gpu-unlock-egpu.conf /etc/udev/rules.d/95-gpu-unlock-egpu.rules \
	/usr/local/libexec/gpu-unlock-gate /etc/gpu-unlock-egpu.conf
rm -rf /usr/lib/firmware/gpu-unlock
for mod in /usr/lib/modules/*/extra/gpu_unlock.ko; do
	[ -e "$mod" ] || continue
	kver=$(basename "$(dirname "$(dirname "$mod")")")
	rm -f "$mod"
	depmod -a "$kver"
done
udevadm control --reload
echo "removed"
