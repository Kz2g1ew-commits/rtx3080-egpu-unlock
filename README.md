# RTX 3080 eGPU unlock (Linux)

**English** | [한국어](README.ko.md)

> **Status: experimental.** One successful boot on a single ZOTAC RTX 3080 10GB (2026-10-19). Other boards, long-term stability and games are untested.

A fork of [Zagitta/gpu-unlock](https://github.com/Zagitta/gpu-unlock) (RTX 3090, Linux kernel module) for an **RTX 3080 10GB in a USB4/Thunderbolt eGPU enclosure**. Before the NVIDIA driver binds the card, it runs FWSEC → V67 → the speed selectors (SS0 `0x88888888`, SS1 `0x8`) → FLR, which lifts GeForce's **half-rate limit on FP16/BF16-input, FP32-accumulate tensor math**. No NVIDIA driver file is modified, and nothing is written to flash or eFuses: the card returns to stock when it loses power.

## Prior work

| Project | What it is |
| --- | --- |
| [Zagitta/gpu-unlock](https://github.com/Zagitta/gpu-unlock) | The base of this fork. RTX 3090, runs from the Linux initramfs |
| [rough2515-hub/rtx3080-unlock-public](https://github.com/rough2515-hub/rtx3080-unlock-public) | Same core on an MSI RTX 3080 10GB (`1462:3890`) via Windows/UEFI. GEMM: FP16 +79 %, BF16 +86 % |
| [IHaBiS02/ga107-unlock](https://github.com/IHaBiS02/ga107-unlock) | Port to a laptop GA107. Useful first-failure analysis (FWSEC DMEM alignment, held BAR) |
| [WildFlash1st/cmp90hx-unlock](https://github.com/WildFlash1st/cmp90hx-unlock) | Origin of the V67 payload (CMP 90HX) |

## Differences from upstream

- **Target card**: only `10de:2206` (RTX 3080 10GB, non-LHR), and only boards in the list in `kernel/gpu_unlock/board.h` (subsystem IDs). Other boards are skipped before any firmware request or MMIO. The PCI ID re-checks during the firmware steps and after FLR use the 3080 ID.
- **When it runs**: upstream scans PCI once from the initramfs. A USB4 eGPU appears only after boltd authorizes it, seconds into boot, so the card is not there yet. This fork runs from a modprobe `install` hook for `nvidia` (`egpu/gpu-unlock-gate`) instead.
  - Every path that loads nvidia goes through the hook: nvidia-smi, CUDA, prime-run, and `nvidia_drm`/`nvidia_uvm` pulling it in as a dependency.
  - Requirement: `nvidia` must not be autoloaded (`blacklist nvidia` in modprobe.d), so the card stays unbound after it appears.
  - One attempt per plug-in. When the card leaves the bus a udev rule clears the marker, so the next plug-in tries again.
- The unlock core (FWSEC, Booter, V67, FLR, checks and failure handling) is unchanged from upstream.

## Test environment

| Item | Value |
| --- | --- |
| Card | ZOTAC RTX 3080 10GB, `10de:2206`, subsystem `19da:3612`, VBIOS `94.02.42.00.ae` |
| Link | AOOSTAR AG02 (ASMedia 246x), USB4 40 Gb/s (2 lanes × 20 Gb/s); card BAR0 16 MiB / BAR1 256 MiB (no ReBAR) |
| Host | Lenovo Legion Go (Ryzen Z1 Extreme) |
| OS | CachyOS (rolling), KDE Plasma 6.8.0 Wayland (KWin 6.8.0), bolt 0.9.11, kmod 34.2 |
| Kernel | `6.18.55-2-cachyos-lts` (run), `7.2.9-2-cachyos-deckify` (build only). Both GCC-built; module built with GCC 16.2.1 |
| NVIDIA | Open kernel module 615.78.08 (`linux-cachyos-lts-nvidia-open`), `nvidia-utils` 615.78.08, `linux-firmware-nvidia` 20260916. Unlock assets generated from 610.43.03, as upstream |
| Measurement | PyTorch 2.14.1+cu130 (CUDA 13.0, cuDNN 9.24.0), ComfyUI. Unlock build/generator scripts on Python 3.14.8 |
| Power | 250 W, SM max 1800 MHz (set with nvidia-smi at boot) |

rough2515's MSI board has VBIOS `94.02.59.00.aa`; this card has `94.02.42.00.ae`. FWSEC is read from the card's ROM and its format and fuse version are checked, so a mismatch is refused before anything runs.

Boot order here: once boltd authorizes the dock, the card appears on PCI and udev starts a power-limit service. That service's `nvidia-smi` is the first nvidia load, and the gate runs the unlock just before it. The service uses `timeout 3 nvidia-smi`, so its first attempt can be cut off while it waits for the unlock. The gate ignores that signal and finishes; on the service's retry the marker is already set and nvidia loads at once.

## Verified

**Real run (2026-10-19, environment above, 250 W limit)**

- During boot the gate ran the unlock before nvidia. FWSEC from the card ROM and the V67 step passed, SS0 went `0x55717001` → `0x88888888` and SS1 `0x6` → `0x8`, and both survived the FLR. nvidia 615.78.08 then initialized with no errors or Xid, and the external display works. Log: [research/first-run-2026-10-19.log](research/first-run-2026-10-19.log)
- GEMM: BF16 (FP32 accumulate) 1.65x, FP16 (FP32 accumulate) 1.67–1.69x, TF32 1.62x. FP32 unchanged. Numerical error identical to before. At the 250 W cap the tensor runs drop to 1425–1515 MHz. Details: [bench/gemm-results.md](bench/gemm-results.md)
- ComfyUI Anima (bf16): sampling 1.36x, whole image −16 %. Details: [bench/comfyui-anima.md](bench/comfyui-anima.md)

**Build and mocked tests**

- Builds without warnings on CachyOS `6.18.55-2-cachyos-lts` and `7.2.9-2-cachyos-deckify` (GCC)
- Firmware: the 610.43.03 inputs pinned by upstream download, pass SHA-256 and generate the five assets
- Mocked tests: the component tests in `tests/` pass, including a full unlock against mocked hardware with the real generated assets, plus a new test that skips boards outside the list
- `modprobe -n -v` shows the install hook running when `nvidia`, `nvidia_uvm`, `nvidia_drm` or `nvidia_modeset` is loaded

## Usage

```sh
make inputs INPUTS=$PWD/build/inputs                          # download NVIDIA inputs + SHA-256 check
make firmware INPUTS=$PWD/build/inputs ASSETS=$PWD/build/assets
egpu/build.sh                                                 # .ko for every kernel with headers
tools/egpu-preflight.sh                                       # read-only state check
sudo egpu/install.sh                                          # install (starts with ENABLE=0)
```

Enable: set `ENABLE=1` in `/etc/gpu-unlock-egpu.conf`.
Disable for one boot: add `gpu_unlock.egpu=0` to the kernel command line in the boot menu's edit screen.
Remove: `sudo egpu/uninstall.sh`.

`packaging/`, `debian/` and `make install-arch|deb|rpm` are upstream's initramfs flow and will not find an eGPU. Do not use them.

### Making an attempt

1. Save your work and power off the PC. **Power off the eGPU dock too.** The card must really lose power; the module refuses a card any driver has used since power on (`card already initialised since power on`).
2. Power on the dock, then the PC. The unlock runs right before the first nvidia load during boot.
3. Check the result:

```sh
journalctl -b -t gpu-unlock-gate
journalctl -k -b -g gpu_unlock
```

If it failed, do not retry in the same power cycle. Power off both PC and dock, then boot with `ENABLE=0`.

### Benchmark

```sh
python -I bench/gemm.py --label off -o bench/results/off.json   # before
python -I bench/gemm.py --label on  -o bench/results/on.json    # after
python -I bench/gemm.py --compare bench/results/off.json bench/results/on.json
```

Run with a Python that has CUDA PyTorch. It measures FP32, TF32 and FP16/BF16 (FP32 accumulate) GEMM at 4096 and 8192 and records clock, power and temperature through nvidia-smi.

## Risks and limits

- Experimental code. A failure can hang the GPU; if the firmware does not halt, the DMA buffers are deliberately kept. Powering off both PC and dock clears it.
- A USB4 link drop during the firmware steps ends in the same state. Make sure the link is stable first.
- The whole SS0 field is set to the full-rate value; the meaning of every per-operation bit is not known.
- Sustained load, games and long-term stability are untested. With a power limit the real gain can be below the benchmark.
- The self-built module is unsigned and taints the kernel (`E`). It will not load with `module.sig_enforce` or lockdown enabled.

## License

The kernel module and scripts are GPL-2.0-only, as upstream. NVIDIA binaries are under their own licenses; they are not in the repository and are generated at build time. See `licenses/` and `firmware/NOTICE.md`. Upstream's original README is in [README.upstream.md](README.upstream.md).
