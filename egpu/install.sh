#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Install the prebuilt modules (egpu/build.sh), firmware (make firmware) and
# the eGPU gate. Run with sudo. Leaves ENABLE=0 unless a config already exists.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
root=$(cd "$(dirname "$0")/.." && pwd)
assets=${ASSETS:-$root/build/assets}
fwdir=/usr/lib/firmware/gpu-unlock/610.43.03
files="booter_load_ga102.bin gsp_ga10x.bin gsp_boot_ga102.bin gsp_boot_desc_ga102.bin v67-ga102-610.43.03.bin"

for f in $files; do
	[ -s "$assets/$f" ] || { echo "missing $assets/$f (run make firmware)" >&2; exit 1; }
done
# Only kernels that are still installed; a stale build dir is skipped.
installed=0
for mod in "$root"/build/module/*/gpu_unlock.ko; do
	kver=$(basename "$(dirname "$mod")")
	[ -d "/usr/lib/modules/$kver/kernel" ] || continue
	install -Dm644 "$mod" "/usr/lib/modules/$kver/extra/gpu_unlock.ko"
	depmod -a "$kver"
	echo "module: $kver"
	installed=$((installed + 1))
done
[ "$installed" -gt 0 ] || { echo "no built module (run egpu/build.sh)" >&2; exit 1; }

for f in $files; do
	install -Dm644 "$assets/$f" "$fwdir/$f"
done
install -Dm755 "$root/egpu/gpu-unlock-gate" /usr/local/libexec/gpu-unlock-gate
install -Dm644 "$root/egpu/95-gpu-unlock-egpu.conf" /etc/modprobe.d/95-gpu-unlock-egpu.conf
install -Dm644 "$root/egpu/95-gpu-unlock-egpu.rules" /etc/udev/rules.d/95-gpu-unlock-egpu.rules
[ -e /etc/gpu-unlock-egpu.conf ] || install -Dm644 "$root/egpu/gpu-unlock-egpu.conf" /etc/gpu-unlock-egpu.conf
udevadm control --reload
echo "installed; enable with ENABLE=1 in /etc/gpu-unlock-egpu.conf"
