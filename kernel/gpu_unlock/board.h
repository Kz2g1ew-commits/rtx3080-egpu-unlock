/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef GPU_UNLOCK_BOARD_H
#define GPU_UNLOCK_BOARD_H

#ifdef __KERNEL__
#include <linux/stddef.h>
#else
#include <stddef.h>
#endif

/* GA102 RTX 3080 10GB (non-LHR). The LHR (0x2216) and 12GB (0x220a) parts
 * are different PCI devices and are not targeted. */
#define GU_RTX_3080 0x2206
/* Config-space dword 0 (device << 16 | vendor) of a card that still answers. */
#define GU_PCI_IDENTITY 0x220610deu

/*
 * Boards whose ROM FWSEC and unlock were checked, as subsystem vendor:device.
 * Other RTX 3080 boards are refused before any firmware or MMIO.
 */
struct gu_board {
	unsigned short subsystem_vendor, subsystem_device;
	const char *name;
};

static const struct gu_board gu_boards[] = {
	/* MSI, verified on Windows/UEFI by rough2515-hub/rtx3080-unlock-public. */
	{ 0x1462, 0x3890, "MSI RTX 3080 10GB" },
	/* ZOTAC, VBIOS 94.02.42.00.ae, USB4 eGPU: this fork's test board. */
	{ 0x19da, 0x3612, "ZOTAC RTX 3080 10GB" },
};

static inline const struct gu_board *gu_board_find(unsigned short vendor,
						   unsigned short device)
{
	unsigned int i;

	for (i = 0; i < sizeof(gu_boards) / sizeof(gu_boards[0]); i++)
		if (gu_boards[i].subsystem_vendor == vendor &&
		    gu_boards[i].subsystem_device == device)
			return &gu_boards[i];
	return NULL;
}

#endif
