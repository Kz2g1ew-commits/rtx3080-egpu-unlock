# SPDX-License-Identifier: GPL-2.0-only
"""Tensor GEMM throughput before/after the unlock, with PyTorch.

Run with any Python that has CUDA PyTorch, e.g. the local ComfyUI venv:
    python -I bench/gemm.py --label off  -o bench/results/off.json
    python -I bench/gemm.py --label on   -o bench/results/on.json
    python -I bench/gemm.py --compare bench/results/off.json bench/results/on.json

FP16/BF16 here accumulate in FP32 (cuBLAS default), the path the unlock
targets. Clock, power and temperature are sampled with nvidia-smi so a
throttled run is visible next to its number. GPU load only; no setting changes.
"""
import argparse
import json
import os
import statistics
import subprocess
import sys
import time


def smi():
    fields = "clocks.sm,power.draw,temperature.gpu,clocks_event_reasons.active"
    try:
        out = subprocess.run(["nvidia-smi", f"--query-gpu={fields}",
                              "--format=csv,noheader,nounits"],
                             capture_output=True, text=True, timeout=5).stdout
        sm, power, temp, reasons = [v.strip() for v in out.splitlines()[0].split(",")]
        return {"sm_mhz": float(sm), "power_w": float(power), "temp_c": float(temp),
                "throttle": reasons}
    except (OSError, ValueError, IndexError, subprocess.SubprocessError):
        return None


def run_case(torch, name, dtype, tf32, n, warmup_s, samples):
    torch.backends.cuda.matmul.allow_tf32 = tf32
    torch.backends.cuda.matmul.allow_fp16_reduced_precision_reduction = False
    torch.backends.cuda.matmul.allow_bf16_reduced_precision_reduction = False
    gen = torch.Generator(device="cuda").manual_seed(0)
    a = torch.randn(n, n, device="cuda", dtype=torch.float32, generator=gen).to(dtype)
    b = torch.randn(n, n, device="cuda", dtype=torch.float32, generator=gen).to(dtype)
    end = time.monotonic() + warmup_s
    while time.monotonic() < end:
        c = a @ b
    torch.cuda.synchronize()
    times = []
    for _ in range(samples):
        start, stop = torch.cuda.Event(enable_timing=True), torch.cuda.Event(enable_timing=True)
        start.record()
        c = a @ b
        stop.record()
        stop.synchronize()
        times.append(start.elapsed_time(stop))
    state = smi()
    # Spot check a corner block against FP64 of the same (rounded) inputs.
    k = 64
    ref = a[:k].double() @ b[:, :k].double()
    err = ((c[:k, :k].double() - ref).abs().max() / ref.abs().max()).item()
    median = statistics.median(times)
    return {"name": name, "n": n, "samples": samples, "median_ms": median,
            "min_ms": min(times), "max_ms": max(times),
            "tflops": 2 * n ** 3 / (median * 1e-3) / 1e12,
            "rel_err": err, "smi": state}


def bench(args):
    import torch
    if not torch.cuda.is_available():
        sys.exit("CUDA not available")
    props = torch.cuda.get_device_properties(0)
    cases = [("fp32", torch.float32, False), ("tf32", torch.float32, True),
             ("fp16_fp32acc", torch.float16, False), ("bf16_fp32acc", torch.bfloat16, False)]
    results = []
    for n in args.sizes:
        for name, dtype, tf32 in cases:
            r = run_case(torch, name, dtype, tf32, n, args.warmup, args.samples)
            results.append(r)
            s = r["smi"] or {}
            print(f"{name:13} n={n:5} {r['tflops']:8.2f} TFLOPS  err={r['rel_err']:.1e}  "
                  f"sm={s.get('sm_mhz', '?')}MHz {s.get('power_w', '?')}W {s.get('temp_c', '?')}C")
    data = {"label": args.label, "time": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "gpu": props.name, "sm_count": props.multi_processor_count,
            "torch": torch.__version__, "cuda": torch.version.cuda,
            "cudnn": torch.backends.cudnn.version(), "results": results}
    if args.output:
        os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
        with open(args.output, "w") as f:
            json.dump(data, f, indent=2)
        print(f"wrote {args.output}")


def compare(before, after):
    a = {(r["name"], r["n"]): r for r in json.load(open(before))["results"]}
    b = {(r["name"], r["n"]): r for r in json.load(open(after))["results"]}
    for key in sorted(a.keys() & b.keys()):
        x, y = a[key]["tflops"], b[key]["tflops"]
        print(f"{key[0]:13} n={key[1]:5} {x:8.2f} -> {y:8.2f} TFLOPS  {y / x:5.3f}x")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--label", default="unlabeled")
    p.add_argument("-o", "--output")
    p.add_argument("--sizes", type=int, nargs="+", default=[4096, 8192])
    p.add_argument("--warmup", type=float, default=2.0)
    p.add_argument("--samples", type=int, default=30)
    p.add_argument("--compare", nargs=2, metavar=("BEFORE", "AFTER"))
    args = p.parse_args()
    if args.compare:
        compare(*args.compare)
    else:
        bench(args)


if __name__ == "__main__":
    main()
