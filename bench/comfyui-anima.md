# ComfyUI Anima: before / after the unlock

The same workflow is run before and after the unlock and compared by
ComfyUI's own timings. The diffusion model runs in bf16, the path the unlock
targets. The text encoder (fp16) and the VAE are part of the total too.

## Setup

- GPU: ZOTAC RTX 3080 10GB (`19da:3612`), AOOSTAR AG02 over USB4, 250 W / max 1800 MHz SM
- Model: `anima-aesthetic-v1.1` (weights bf16, `manual cast: None`), text encoder
  `qwen_3_06b_base` (fp16), WanVAE
- Sampler: 30 steps, DCW/SMC Auto ('Cosmos / Wan'), dynamic VRAM loading
- Same workflow (resolution, steps, sampler) before and after; resolution and
  sampler names were not in the log. Seeds were not fixed and differ between
  runs. With the resolution and step count fixed the seed does not change the
  amount of work, so the timings compare, but the images are not pairwise
  identical and image output was not compared.

## Before (unlock off) — 2026-10-19

| Run | Sampling 30 steps | it/s | Prompt total |
| ---: | ---: | ---: | ---: |
| 1 (cold: model load, output dir created) | 00:21 | 1.38 | 29.84 s |
| 2 | 00:21 | 1.39 | 27.12 s |
| 3 | 00:22 | 1.35 | 28.26 s |
| 4 | 00:21 | 1.38 | 27.73 s |

Warm runs 2–4: sampling 1.35–1.39 it/s (mean 1.373), total 27.12–28.26 s
(mean 27.70 s). Run 1 includes first-load costs and is not compared.

## After (unlock on) — 2026-10-19

Same workflow, ComfyUI restarted after the unlocked boot.

| Run | Sampling 30 steps | it/s | Prompt total |
| ---: | ---: | ---: | ---: |
| 1 (cold: model and VAE load) | 00:15 | 1.93 | 27.78 s |
| 2 | 00:15 | 1.92 | 22.58 s |
| 3 | 00:16 | 1.81 | 23.76 s |
| 4 | 00:15 | 1.88 | 23.47 s |

## Comparison (warm runs 2–4)

| | Before | After | Change |
| --- | ---: | ---: | ---: |
| Sampling speed | 1.373 it/s | 1.870 it/s | 1.36x |
| Sampling time (30 / it/s) | 21.85 s | 16.04 s | −5.8 s (−27 %) |
| Prompt total | 27.70 s | 23.27 s | −4.4 s (−16 %), 1.19x |
| Total minus sampling | 5.85 s | 7.23 s | +1.4 s |

The diffusion model (bf16) gains 1.36x, less than the 1.65x GEMM gain:
sampling also runs attention and other non-GEMM work, and the card is at the
250 W cap. The text encoder, VAE and saving are barely affected, so the whole
prompt gains 1.19x. The non-sampling part grew by 1.4 s; with three samples
this is not explained and could be run-to-run noise (TE/VAE staging).
