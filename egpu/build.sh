#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build gpu_unlock.ko for every installed kernel that has headers, as a normal
# user, into build/module/<kernel>/. install.sh copies these; it never builds.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
built=0
for kdir in /usr/lib/modules/*/build; do
	[ -e "$kdir/Makefile" ] || continue
	kver=$(basename "$(dirname "$kdir")")
	out=$root/build/module/$kver
	rm -rf "$out"
	mkdir -p "$out"
	cp "$root"/kernel/gpu_unlock/*.[ch] "$root"/kernel/gpu_unlock/Kbuild "$out"/
	# Kbuild treats any non-empty LLVM (even 0) as "use clang": pass it only
	# for a clang-built kernel.
	llvm=()
	grep -q '^CONFIG_CC_IS_CLANG=y' "$kdir/.config" 2>/dev/null && llvm=(LLVM=1)
	make -s -C "$kdir" M="$out" "${llvm[@]}" modules
	modinfo -F vermagic "$out/gpu_unlock.ko" | grep -q "^$kver " || {
		echo "vermagic mismatch for $kver" >&2
		exit 1
	}
	echo "built $out/gpu_unlock.ko"
	built=$((built + 1))
done
[ "$built" -gt 0 ] || { echo "no kernel headers found" >&2; exit 1; }
