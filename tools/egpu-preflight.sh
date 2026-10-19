#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Read-only state check for the eGPU unlock. Reads sysfs, modinfo and the
# installed files only: no firmware, no MMIO, no module load. nvidia-smi is
# queried only when nvidia is already loaded, so the card is never warmed here.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
fwdir=/usr/lib/firmware/gpu-unlock/610.43.03
ok=1
say() { printf '%-22s %s\n' "$1" "$2"; }
bad() { say "$1" "NO: $2"; ok=0; }

say kernel "$(uname -r)"
say tainted "$(cat /proc/sys/kernel/tainted)"

gpu=
for dev in /sys/bus/pci/devices/*; do
	[ "$(cat "$dev/vendor")" = 0x10de ] && [ "$(cat "$dev/device")" = 0x2206 ] && gpu=$dev && break
done
if [ -z "$gpu" ]; then
	bad gpu "no 10de:2206 on PCI (eGPU attached and authorized?)"
	command -v boltctl >/dev/null && boltctl list 2>/dev/null | grep -E '^ |status|authorized' | head -8
else
	bdf=${gpu##*/}
	sv=$(cat "$gpu/subsystem_vendor"); sd=$(cat "$gpu/subsystem_device")
	sub=$(printf '%04x:%04x' "$sv" "$sd")
	say gpu "$bdf"
	say subsystem "$sub"
	if grep -qiE "\{ *0x${sub%%:*}, *0x${sub##*:}," "$root/kernel/gpu_unlock/board.h"; then
		say board "in verified list"
	else
		bad board "$sub not in kernel/gpu_unlock/board.h"
	fi
	if [ -e "$gpu/driver" ]; then
		drv=$(basename "$(readlink "$gpu/driver")")
		bad driver "bound to $drv: card is warm, power cycle the dock before an attempt"
	else
		say driver "unbound"
	fi
	say power_state "$(cat "$gpu/power_state" 2>/dev/null || echo ?)"
	say link "$(cat "$gpu/current_link_speed") x$(cat "$gpu/current_link_width") (max $(cat "$gpu/max_link_speed") x$(cat "$gpu/max_link_width"))"
	say iommu_group "$(basename "$(readlink "$gpu/iommu_group" 2>/dev/null)" 2>/dev/null)"
	# BAR sizes from the resource table: start end flags per line.
	i=0
	while read -r start end _; do
		if [ "$i" -le 5 ] && [ "$start" != 0x0000000000000000 ]; then
			size=$(( end - start + 1 ))
			[ "$size" -ge 1048576 ] && say "bar$i" "$(( size >> 20 )) MiB" || say "bar$i" "$size bytes"
		fi
		i=$((i + 1))
	done <"$gpu/resource"
	# Thunderbolt/USB4 tunnels mark the path as removable/external.
	say removable "$(cat "$gpu/removable" 2>/dev/null || echo ?)"
	if [ -r "/proc/driver/nvidia/gpus/$bdf/information" ]; then
		say vbios "$(sed -n 's/^Video BIOS:[[:space:]]*//p' "/proc/driver/nvidia/gpus/$bdf/information")"
	else
		say vbios "unknown (needs nvidia; read it once, then power cycle the dock)"
	fi
fi

if modinfo -F version gpu_unlock >/dev/null 2>&1; then
	say module "$(modinfo -F filename gpu_unlock) $(modinfo -F version gpu_unlock)"
else
	bad module "gpu_unlock not installed for $(uname -r)"
fi
missing=
for f in booter_load_ga102.bin gsp_ga10x.bin gsp_boot_ga102.bin gsp_boot_desc_ga102.bin v67-ga102-610.43.03.bin; do
	[ -s "$fwdir/$f" ] || missing="$missing $f"
done
[ -z "$missing" ] && say firmware "$fwdir" || bad firmware "missing:$missing"
[ -x /usr/local/libexec/gpu-unlock-gate ] && say gate installed || bad gate "not installed"
enable=0
[ -r /etc/gpu-unlock-egpu.conf ] && enable=$(sed -n 's/^ENABLE=//p' /etc/gpu-unlock-egpu.conf)
say enabled "${enable:-0}"
grep -qw 'gpu_unlock.egpu=0' /proc/cmdline && say cmdline "gpu_unlock.egpu=0 (disabled this boot)"
[ -d /sys/module/gpu_unlock ] && say loaded "gpu_unlock is loaded (pinned after a failure?)"
[ -d /sys/module/nvidia ] && say nvidia "loaded" || say nvidia "not loaded"

[ "$ok" = 1 ] && echo "preflight: ready" || echo "preflight: not ready"
