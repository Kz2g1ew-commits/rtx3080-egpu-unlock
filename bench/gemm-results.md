# GEMM throughput: before / after the unlock

`bench/gemm.py` (raw data: `bench/results/off.json`, `on.json`), PyTorch 2.14.1+cu130, square GEMM, 2 s warmup, median of 30
CUDA-event samples. FP16/BF16 accumulate in FP32. Card and host: see the
README's test environment. Limits during both runs: 250 W, SM max 1800 MHz.

## Before (unlock off) — 2026-10-19 18:26

| Case | n | TFLOPS | SM MHz | Power | Temp |
| --- | ---: | ---: | ---: | ---: | ---: |
| FP32 | 4096 | 19.08 | 1500 | 249 W | 66 °C |
| TF32 | 4096 | 28.62 | 1785 | 249 W | 68 °C |
| FP16 / FP32 acc | 4096 | 56.02 | 1755 | 249 W | 69 °C |
| BF16 / FP32 acc | 4096 | 57.55 | 1800 | 249 W | 70 °C |
| FP32 | 8192 | 18.98 | 1395 | 249 W | 73 °C |
| TF32 | 8192 | 29.12 | 1725 | 249 W | 74 °C |
| FP16 / FP32 acc | 8192 | 55.94 | 1770 | 249 W | 74 °C |
| BF16 / FP32 acc | 8192 | 58.97 | 1800 | 250 W | 74 °C |

Every sample reported throttle reason `0x4` (software power cap): the card
sits at the 250 W limit in all cases. After the unlock the tensor cases may be
power bound, so the gain can be smaller than the 1.8x seen at full power.

## After (unlock on) — 2026-10-19 18:36

First unlock on this board succeeded at boot (`research/first-run-2026-10-19.log`).

| Case | n | Before | After | Ratio | SM MHz after | Power | Temp |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| FP32 | 4096 | 19.08 | 19.48 | 1.021x | 1515 | 249 W | 61 °C |
| TF32 | 4096 | 28.62 | 46.55 | 1.627x | 1500 | 250 W | 62 °C |
| FP16 / FP32 acc | 4096 | 56.02 | 93.73 | 1.673x | 1500 | 250 W | 62 °C |
| BF16 / FP32 acc | 4096 | 57.55 | 94.72 | 1.646x | 1515 | 250 W | 63 °C |
| FP32 | 8192 | 18.98 | 18.64 | 0.982x | 1395 | 249 W | 73 °C |
| TF32 | 8192 | 29.12 | 47.08 | 1.617x | 1425 | 249 W | 73 °C |
| FP16 / FP32 acc | 8192 | 55.94 | 94.77 | 1.694x | 1425 | 250 W | 73 °C |
| BF16 / FP32 acc | 8192 | 58.97 | 97.11 | 1.647x | 1470 | 249 W | 74 °C |

- FP16/BF16 with FP32 accumulation: 1.65–1.69x. TF32 also 1.62x (SS1 = 8).
- FP32 is unchanged (within ±2 %), as expected.
- The relative error of every case is identical to the before run.
- Tensor cases now run at 1425–1515 MHz instead of 1755–1800 MHz: still at
  the 250 W cap (`0x4`), so the gain is power bound, not the full 2x.
