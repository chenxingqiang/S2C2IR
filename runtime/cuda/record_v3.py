#!/usr/bin/env python3
"""V3 measurement recorder. Does not change adapter semantics or Cost."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

FIELDS = [
    "git_commit",
    "timestamp",
    "gpu_model",
    "gpu_memory",
    "driver_version",
    "cuda_runtime",
    "nvcc_version",
    "clock_state",
    "power_mode",
    "case",
    "N",
    "k",
    "provisioned",
    "warmup",
    "reps",
    "statistic",
    "latency_us",
    "score3",
]

CASES = (
    ("a", "pilot_a_ssd_hbm_compute", 130),
    ("b", "pilot_b_compute_par_comm", 128),
    ("c", "pilot_c_pipeline_three_stage", 163),
)
NS = (4194304, 16777216, 67108864)
KS = (1, 8)
PROVS = (0, 1)
MATCHED_KS = (1, 8, 32, 64)
MATCHED_ARMS = ("matched-seq", "matched-ovl", "matched-copy", "matched-compute")
MATCHED_FUNCS = set(MATCHED_ARMS)
CAP_PAIR_ARMS = (
    "cap-htod",
    "cap-dtoh",
    "cap-htod-dtoh-seq",
    "cap-htod-dtoh-event",
    "cap-htod-dtoh-par",
    "cap-htod-htod-par",
    "cap-dtoh-dtoh-par",
    "cap-compute",
    "cap-compute-htod",
    "cap-compute-dtoh",
    "cap-compute-compute",
)
CAP_SYNC_ARMS = ("cap-event-sync", "cap-stream-sync", "cap-device-sync")
CAP_SIZE_BYTES = (
    1024,
    4 * 1024,
    16 * 1024,
    64 * 1024,
    1024 * 1024,
    4 * 1024 * 1024,
    16 * 1024 * 1024,
    64 * 1024 * 1024,
    256 * 1024 * 1024,
)
CAP_MATMUL_DIMS = (256, 512, 1024)
CAP_K = 32
PHASE_R = (0.01, 0.03, 0.1, 0.3, 1.0, 3.0, 10.0, 30.0)
PHASE_K_MAX = 4096
PHASE_ARMS = ("phase-seq", "phase-ovl", "phase-copy", "phase-compute")
PHASE_FUNCS = set(PHASE_ARMS)
PIPE_TILES = 8
PIPE_TILES_SET = (4, 8, 16, 32)
PIPE_DEPTHS = (1, 2, 3, 4)
PIPE_TILES_CASE_RE = re.compile(r"^pipe-t(\d+)-(copy|compute|d[1-4])$")
PIPE_ARMS = (
    "pipe-copy",
    "pipe-compute",
    "pipe-d1",
    "pipe-d2",
    "pipe-d3",
    "pipe-d4",
)
PIPE_FUNCS = set(PIPE_ARMS)
VAL_ARMS = (
    "val-copy-named",
    "val-compute-named",
    "val-seq-named",
    "val-ovl-named",
    "val-copy-default",
    "val-compute-default",
    "val-seq-default",
    "val-ovl-default",
)
VAL_FUNCS = set(VAL_ARMS)
VAL_FIELDS = (
    "N",
    "k",
    "stream",
    "r",
    "T_copy_us",
    "T_compute_us",
    "T_seq_us",
    "T_ovl_us",
    "ovl_over_max",
    "ovl_over_sum",
    "verdict",
    "extra_hb",
)
VAL_MEM_ARMS = (
    "val-htod-pinned",
    "val-htod-pageable",
    "val-dtoh-pinned",
    "val-dtoh-pageable",
    "val-compute-mem",
    "val-ovl-htod-pin",
    "val-ovl-htod-page",
    "val-ovl-dtoh-pin",
    "val-ovl-dtoh-page",
)
VAL_MEM_FUNCS = set(VAL_MEM_ARMS)
VAL_MEM_PAIRS = (
    ("C||HtoD", "val-htod-pinned", "val-htod-pageable",
     "val-ovl-htod-pin", "val-ovl-htod-page"),
    ("C||DtoH", "val-dtoh-pinned", "val-dtoh-pageable",
     "val-ovl-dtoh-pin", "val-ovl-dtoh-page"),
)
VAL_MEM_FIELDS = (
    "N",
    "k",
    "pair",
    "residency",
    "r",
    "T_copy_us",
    "T_compute_us",
    "T_ovl_us",
    "ovl_over_max",
    "ovl_over_sum",
    "verdict",
    "extra_hb",
)
VAL_CC_ARMS = (
    "val-cc-silu",
    "val-cc-matmul",
    "val-cc-seq",
    "val-cc-ovl",
    "val-cc-silu-silu",
)
VAL_CC_FUNCS = set(VAL_CC_ARMS)
VAL_CC_DIM = 1024
VAL_CC_FIELDS = (
    "N",
    "k",
    "dim",
    "r",
    "T_silu_us",
    "T_matmul_us",
    "T_seq_us",
    "T_ovl_us",
    "T_silu_silu_us",
    "ovl_over_max",
    "ovl_over_sum",
    "mixed_verdict",
    "ss_over_max",
    "ss_over_sum",
    "same_verdict",
    "pair_relation",
    "observed_constraint",
)
VAL_ASYNC_ARMS = (
    "val-async-copy",
    "val-async-compute",
    "val-async-life-sync",
    "val-async-life-async",
    "val-async-hb",
)
VAL_ASYNC_FUNCS = set(VAL_ASYNC_ARMS)
VAL_ASYNC_FIELDS = (
    "N",
    "k",
    "r",
    "T_copy_us",
    "T_compute_us",
    "T_life_sync_us",
    "T_life_async_us",
    "T_hb_us",
    "sync_over_async",
    "hb_over_async",
    "extra_hb",
)
PIPE_FIELDS = (
    "N",
    "k",
    "tiles",
    "r_tile",
    "T_copy_us",
    "T_compute_us",
    "T_d1_us",
    "T_d2_us",
    "T_d3_us",
    "T_d4_us",
    "speedup_d2",
    "speedup_d3",
    "speedup_d4",
    "ideal",
    "T_ideal_pipe_us",
    "sat_d4_over_d2",
)
PHASE_FIELDS = (
    "N",
    "k",
    "r_target",
    "r_achieved",
    "T_seq_us",
    "T_ovl_us",
    "T_copy_us",
    "T_compute_us",
    "ovl_over_max",
    "ovl_over_sum",
    "hidden_frac",
    "dominance",
    "overlap",
)
CAP_FUNCS = set(CAP_PAIR_ARMS) | set(CAP_SYNC_ARMS) | {
    "cap-reduction",
    "cap-matmul",
}
CAP_PAIRS = (
    ("HtoD||DtoH", "cap-htod", "cap-dtoh", "cap-htod-dtoh-par"),
    ("HtoD||HtoD", "cap-htod", "cap-htod", "cap-htod-htod-par"),
    ("DtoH||DtoH", "cap-dtoh", "cap-dtoh", "cap-dtoh-dtoh-par"),
    ("C||HtoD", "cap-compute", "cap-htod", "cap-compute-htod"),
    ("C||DtoH", "cap-compute", "cap-dtoh", "cap-compute-dtoh"),
    ("C||C", "cap-compute", "cap-compute", "cap-compute-compute"),
)
CAL_FIELDS = (
    "N",
    "k",
    "T_seq_us",
    "T_ovl_us",
    "T_copy_us",
    "T_compute_us",
    "ratio",
    "gain_us",
    "ideal_us",
    "hidden_frac",
    "seq_over_sum",
    "ovl_over_max",
)
LINE_RE = re.compile(
    r"s2c2-cuda-adapter func=(?P<func>\S+) .* n=(?P<n>\d+) "
    r"provisioned=(?P<prov>\d+) k=(?P<k>\d+) score3_total=(?P<score>\d+) "
    r"latency_us=(?P<us>[0-9.]+)"
)
FUNC_TO_CASE = {func: (cid, score) for cid, func, score in CASES}


def unavailable() -> str:
    return "unavailable"


def run_cmd(args: list[str]) -> str:
    try:
        out = subprocess.check_output(args, stderr=subprocess.DEVNULL, text=True)
        return out.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def git_commit(explicit: str | None) -> str:
    if explicit:
        return explicit
    env = os.environ.get("S2C2_GIT_COMMIT")
    if env:
        return env
    out = run_cmd(["git", "rev-parse", "HEAD"])
    return out or unavailable()


def nvcc_version() -> str:
    out = run_cmd(["nvcc", "--version"])
    if not out:
        return unavailable()
    for line in out.splitlines():
        if "release" in line.lower():
            return " ".join(line.split())
    return out.splitlines()[-1]


RUNTIME_RE = re.compile(r"cuda_runtime_version=(\S+)")


def run_cmd_all(args: list[str]) -> str:
    try:
        proc = subprocess.run(
            args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )
        return (proc.stdout or "").strip()
    except OSError:
        return ""


def cuda_runtime_from_bin(bin_path: str) -> str:
    """Loaded libcudart via cudaRuntimeGetVersion. Not nvidia-smi / nvcc."""
    out = run_cmd_all([bin_path, "--print-meta"])
    m = RUNTIME_RE.search(out)
    if not m:
        return unavailable()
    return m.group(1)


def collect_gpu() -> dict[str, str]:
    q = (
        "name,memory.total,driver_version,clocks.current.sm,"
        "clocks.current.memory,pstate,power.limit"
    )
    raw = run_cmd(
        [
            "nvidia-smi",
            f"--query-gpu={q}",
            "--format=csv,noheader,nounits",
        ]
    )
    meta = {
        "gpu_model": unavailable(),
        "gpu_memory": unavailable(),
        "driver_version": unavailable(),
        "cuda_runtime": unavailable(),
        "clock_state": unavailable(),
        "power_mode": unavailable(),
    }
    if not raw:
        return meta
    parts = [p.strip() for p in raw.split(",")]
    if len(parts) >= 7:
        meta.update(
            {
                "gpu_model": parts[0],
                "gpu_memory": parts[1],
                "driver_version": parts[2],
                "clock_state": f"pstate={parts[5]} sm={parts[3]} mem={parts[4]}",
                "power_mode": f"limit_w={parts[6]}",
            }
        )
    return meta


def print_schema(fmt: str) -> int:
    if fmt == "csv":
        print(",".join(FIELDS))
    else:
        for name in FIELDS:
            print(name)
        print("source driver_version=nvidia-smi")
        print("source nvcc_version=nvcc")
        print("source cuda_runtime=cudaRuntimeGetVersion")
        print("v3=not-claimed")
    return 0


def base_record(commit: str, gpu: dict[str, str], warmup: int, reps: int) -> dict[str, Any]:
    rec = {k: unavailable() for k in FIELDS}
    rec.update(gpu)
    rec["git_commit"] = commit
    rec["timestamp"] = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    rec["nvcc_version"] = nvcc_version()
    rec["warmup"] = warmup
    rec["reps"] = reps
    rec["statistic"] = "median"
    return rec


def parse_adapter_line(line: str) -> dict[str, Any] | None:
    m = LINE_RE.search(line)
    if not m:
        return None
    func = m.group("func")
    if func not in FUNC_TO_CASE:
        return None
    case, score = FUNC_TO_CASE[func]
    return {
        "case": case,
        "N": int(m.group("n")),
        "k": int(m.group("k")),
        "provisioned": int(m.group("prov")),
        "score3": int(m.group("score")),
        "latency_us": float(m.group("us")),
        "expected_score3": score,
    }


def parse_pipe_line(line: str) -> dict[str, Any] | None:
    m = LINE_RE.search(line)
    if not m:
        return None
    func = m.group("func")
    if func not in PIPE_FUNCS:
        return None
    return {
        "case": func,
        "N": int(m.group("n")),
        "k": int(m.group("k")),
        "provisioned": 1,
        "score3": "",
        "latency_us": float(m.group("us")),
    }


def parse_phase_line(line: str) -> dict[str, Any] | None:
    m = LINE_RE.search(line)
    if not m:
        return None
    func = m.group("func")
    if func not in PHASE_FUNCS:
        return None
    return {
        "case": func,
        "N": int(m.group("n")),
        "k": int(m.group("k")),
        "provisioned": 1,
        "score3": "",
        "latency_us": float(m.group("us")),
    }


def parse_cap_line(line: str) -> dict[str, Any] | None:
    m = LINE_RE.search(line)
    if not m:
        return None
    func = m.group("func")
    if func not in CAP_FUNCS:
        return None
    return {
        "case": func,
        "N": int(m.group("n")),
        "k": int(m.group("k")),
        "provisioned": 1,
        "score3": "",
        "latency_us": float(m.group("us")),
    }


def parse_matched_line(line: str) -> dict[str, Any] | None:
    m = LINE_RE.search(line)
    if not m:
        return None
    func = m.group("func")
    if func not in MATCHED_FUNCS:
        return None
    return {
        "case": func,
        "N": int(m.group("n")),
        "k": int(m.group("k")),
        "provisioned": 1,
        "score3": "",
        "latency_us": float(m.group("us")),
    }


def print_pipe_schema() -> int:
    print("pipe-arm d1 d2 d3 d4 copy compute")
    print("pair C||HtoD")
    print("tiles 8")
    print("depth 1=seq 2=double 3=triple 4=quad")
    print("score3 not-applicable")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def print_pipe_tiles_schema() -> int:
    print("pipe-tiles-arm t4 t8 t16 t32")
    print("pair C||HtoD")
    print("tiles 4 8 16 32")
    print("depth 1=seq 2=double 3=triple 4=quad")
    print("score3 not-applicable")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def print_cuda_val_schema() -> int:
    print("cuda-val v1")
    print("pair C||HtoD")
    print("stream named-nonblocking legacy-default")
    print("acceptance HB-subset")
    print("extra-hb none|legacy-default")
    print("score3 not-applicable")
    print("semantics unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def parse_val_line(line: str) -> dict[str, Any] | None:
    m = LINE_RE.search(line)
    if not m:
        return None
    func = m.group("func")
    if func not in VAL_FUNCS:
        return None
    return {
        "case": func,
        "N": int(m.group("n")),
        "k": int(m.group("k")),
        "provisioned": 1,
        "score3": "",
        "latency_us": float(m.group("us")),
    }


def _collect_val_rows(
    text: str, gpu: dict[str, str], warmup: int, reps: int, commit: str
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line in text.splitlines():
        parsed = parse_val_line(line)
        if not parsed:
            continue
        rec = base_record(commit, gpu, warmup, reps)
        rec["case"] = parsed["case"]
        rec["N"] = parsed["N"]
        rec["k"] = parsed["k"]
        rec["provisioned"] = parsed["provisioned"]
        rec["score3"] = parsed["score3"]
        rec["latency_us"] = parsed["latency_us"]
        rows.append({key: rec[key] for key in FIELDS})
    return rows


def cuda_val_sweep(bin_path: str, out_prefix: Path, warmup: int, reps: int,
                   commit: str) -> int:
    gpu = collect_gpu()
    gpu["cuda_runtime"] = cuda_runtime_from_bin(bin_path)
    rows: list[dict[str, Any]] = []
    try:
        for n in NS:
            print(f"=== cuda-val calibrate n={n} ===", file=sys.stderr)
            text = _run_adapter(
                bin_path,
                ["--cuda-val=copy-named", f"--n={n}", "--k=1"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            copy_rows = _collect_val_rows(text, gpu, warmup, reps, commit)
            text = _run_adapter(
                bin_path,
                ["--cuda-val=compute-named", f"--n={n}", "--k=1"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            unit_rows = _collect_val_rows(text, gpu, warmup, reps, commit)
            if len(copy_rows) != 1 or len(unit_rows) != 1:
                print("record_v3: cuda-val calibrate expected 2 rows",
                      file=sys.stderr)
                return 4
            k = choose_phase_k(
                1.0,
                float(copy_rows[0]["latency_us"]),
                float(unit_rows[0]["latency_us"]),
            )
            print(f"=== cuda-val p0 n={n} k={k} ===", file=sys.stderr)
            text = _run_adapter(
                bin_path,
                ["--cuda-val=p0", f"--n={n}", f"--k={k}"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            got = _collect_val_rows(text, gpu, warmup, reps, commit)
            if {r["case"] for r in got} != set(VAL_ARMS):
                print(
                    f"record_v3: expected 8 val arms, got {[r['case'] for r in got]}",
                    file=sys.stderr,
                )
                return 4
            rows.extend(got)
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"record_v3: cuda-val run failed: {exc}", file=sys.stderr)
        return 2
    write_outputs(rows, out_prefix)
    print(
        f"record_v3 wrote {out_prefix.with_suffix('.jsonl')} "
        f"count={len(rows)} cuda-val v3=not-claimed"
    )
    return 0


def cuda_val_slices(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for n in NS:
        slice_rows = [r for r in rows if int(r["N"]) == n]
        by_case = {r["case"]: r for r in slice_rows}
        for stream, extra in (("named", "none"), ("default", "legacy-default")):
            need = [f"val-{kind}-{stream}" for kind in ("copy", "compute", "seq", "ovl")]
            if any(key not in by_case for key in need):
                continue
            copy = float(by_case[f"val-copy-{stream}"]["latency_us"])
            compute = float(by_case[f"val-compute-{stream}"]["latency_us"])
            seq = float(by_case[f"val-seq-{stream}"]["latency_us"])
            ovl = float(by_case[f"val-ovl-{stream}"]["latency_us"])
            pmax = _safe_div(ovl, max(copy, compute))
            psum = _safe_div(ovl, copy + compute)
            out.append(
                {
                    "N": n,
                    "k": int(by_case[f"val-ovl-{stream}"]["k"]),
                    "stream": stream,
                    "r": _safe_div(compute, copy),
                    "T_copy_us": copy,
                    "T_compute_us": compute,
                    "T_seq_us": seq,
                    "T_ovl_us": ovl,
                    "ovl_over_max": pmax,
                    "ovl_over_sum": psum,
                    "verdict": _verdict(pmax, psum),
                    "extra_hb": extra,
                }
            )
    return out


def analyze_cuda_val(jsonl: Path, out: Path | None = None) -> int:
    rows = [
        json.loads(line)
        for line in jsonl.read_text(encoding="utf-8").splitlines()
        if line
    ]
    slices = cuda_val_slices(rows)
    print(
        "v3-cuda-val v1 pair=C||HtoD acceptance=HB-subset "
        "semantics=unchanged v3=not-claimed cost=unchanged"
    )
    print(
        "slice\tN\tstream\tk\tr\tcopy\tcompute\tseq\tovl\t"
        "ovl/max\tovl/sum\tverdict\textra_hb"
    )
    for s in slices:
        print(
            f"slice\t{s['N']}\t{s['stream']}\t{s['k']}\t{s['r']:.3f}\t"
            f"{s['T_copy_us']:.1f}\t{s['T_compute_us']:.1f}\t"
            f"{s['T_seq_us']:.1f}\t{s['T_ovl_us']:.1f}\t"
            f"{s['ovl_over_max']:.3f}\t{s['ovl_over_sum']:.3f}\t"
            f"{s['verdict']}\t{s['extra_hb']}"
        )
    hits = 0
    for n in NS:
        named = next((s for s in slices if s["N"] == n and s["stream"] == "named"), None)
        default = next(
            (s for s in slices if s["N"] == n and s["stream"] == "default"), None
        )
        if not named or not default:
            continue
        if named["verdict"] == "parallel" and default["verdict"] == "serial":
            hits += 1
            print(
                f"counterexample\tN={n}\tnamed=parallel\tdefault=serial\t"
                "extra-hb=legacy-default"
            )
    print(
        f"summary slices={len(slices)} counterexamples={hits} "
        "depth-star=not-a-law semantics=unchanged v3=not-claimed cost=unchanged"
    )
    if out:
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=VAL_FIELDS)
            w.writeheader()
            for s in slices:
                w.writerow(
                    {
                        "N": s["N"],
                        "k": s["k"],
                        "stream": s["stream"],
                        "r": f"{s['r']:.3f}",
                        "T_copy_us": f"{s['T_copy_us']:.1f}",
                        "T_compute_us": f"{s['T_compute_us']:.1f}",
                        "T_seq_us": f"{s['T_seq_us']:.1f}",
                        "T_ovl_us": f"{s['T_ovl_us']:.1f}",
                        "ovl_over_max": f"{s['ovl_over_max']:.3f}",
                        "ovl_over_sum": f"{s['ovl_over_sum']:.3f}",
                        "verdict": s["verdict"],
                        "extra_hb": s["extra_hb"],
                    }
                )
        print(f"record_v3 wrote {out} count={len(slices)} cuda-val v3=not-claimed")
    return 0


def print_cuda_val_mem_schema() -> int:
    print("cuda-val-mem v2")
    print("pair C||HtoD C||DtoH")
    print("host pinned pageable")
    print("stream named-nonblocking")
    print("acceptance storage-comm")
    print("extra-hb none|pageable-host")
    print("score3 not-applicable")
    print("semantics unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def parse_val_mem_line(line: str) -> dict[str, Any] | None:
    m = LINE_RE.search(line)
    if not m:
        return None
    func = m.group("func")
    if func not in VAL_MEM_FUNCS:
        return None
    return {
        "case": func,
        "N": int(m.group("n")),
        "k": int(m.group("k")),
        "provisioned": 1,
        "score3": "",
        "latency_us": float(m.group("us")),
    }


def _collect_val_mem_rows(
    text: str, gpu: dict[str, str], warmup: int, reps: int, commit: str
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line in text.splitlines():
        parsed = parse_val_mem_line(line)
        if not parsed:
            continue
        rec = base_record(commit, gpu, warmup, reps)
        rec["case"] = parsed["case"]
        rec["N"] = parsed["N"]
        rec["k"] = parsed["k"]
        rec["provisioned"] = parsed["provisioned"]
        rec["score3"] = parsed["score3"]
        rec["latency_us"] = parsed["latency_us"]
        rows.append({key: rec[key] for key in FIELDS})
    return rows


def cuda_val_mem_sweep(bin_path: str, out_prefix: Path, warmup: int, reps: int,
                       commit: str) -> int:
    gpu = collect_gpu()
    gpu["cuda_runtime"] = cuda_runtime_from_bin(bin_path)
    rows: list[dict[str, Any]] = []
    try:
        for n in NS:
            print(f"=== cuda-val-mem calibrate n={n} ===", file=sys.stderr)
            text = _run_adapter(
                bin_path,
                ["--cuda-val-mem=htod-pinned", f"--n={n}", "--k=1"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            copy_rows = _collect_val_mem_rows(text, gpu, warmup, reps, commit)
            text = _run_adapter(
                bin_path,
                ["--cuda-val-mem=compute", f"--n={n}", "--k=1"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            unit_rows = _collect_val_mem_rows(text, gpu, warmup, reps, commit)
            if len(copy_rows) != 1 or len(unit_rows) != 1:
                print("record_v3: cuda-val-mem calibrate expected 2 rows",
                      file=sys.stderr)
                return 4
            k = choose_phase_k(
                1.0,
                float(copy_rows[0]["latency_us"]),
                float(unit_rows[0]["latency_us"]),
            )
            print(f"=== cuda-val-mem p0 n={n} k={k} ===", file=sys.stderr)
            text = _run_adapter(
                bin_path,
                ["--cuda-val-mem=p0", f"--n={n}", f"--k={k}"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            got = _collect_val_mem_rows(text, gpu, warmup, reps, commit)
            if {r["case"] for r in got} != set(VAL_MEM_ARMS):
                print(
                    f"record_v3: expected 9 val-mem arms, got "
                    f"{[r['case'] for r in got]}",
                    file=sys.stderr,
                )
                return 4
            rows.extend(got)
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"record_v3: cuda-val-mem run failed: {exc}", file=sys.stderr)
        return 2
    write_outputs(rows, out_prefix)
    print(
        f"record_v3 wrote {out_prefix.with_suffix('.jsonl')} "
        f"count={len(rows)} cuda-val-mem v3=not-claimed"
    )
    return 0


def cuda_val_mem_slices(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for n in NS:
        slice_rows = [r for r in rows if int(r["N"]) == n]
        by_case = {r["case"]: r for r in slice_rows}
        compute_row = by_case.get("val-compute-mem")
        if not compute_row:
            continue
        compute = float(compute_row["latency_us"])
        k = int(compute_row["k"])
        for pair, pin_copy, page_copy, pin_ovl, page_ovl in VAL_MEM_PAIRS:
            for residency, copy_key, ovl_key, extra in (
                ("pinned", pin_copy, pin_ovl, "none"),
                ("pageable", page_copy, page_ovl, "pageable-host"),
            ):
                if copy_key not in by_case or ovl_key not in by_case:
                    continue
                copy = float(by_case[copy_key]["latency_us"])
                ovl = float(by_case[ovl_key]["latency_us"])
                pmax = _safe_div(ovl, max(copy, compute))
                psum = _safe_div(ovl, copy + compute)
                verdict = _verdict(pmax, psum)
                # extra_hb is observed serialization, not a CUDA HB graph.
                # Pageable + mixed with ovl/max <= 1.15 is still max-like;
                # the #55 gray zone is r-unbalance, not extra HB.
                if residency == "pageable" and verdict == "serial":
                    extra_hb = extra
                else:
                    extra_hb = "none"
                out.append(
                    {
                        "N": n,
                        "k": k,
                        "pair": pair,
                        "residency": residency,
                        "r": _safe_div(compute, copy),
                        "T_copy_us": copy,
                        "T_compute_us": compute,
                        "T_ovl_us": ovl,
                        "ovl_over_max": pmax,
                        "ovl_over_sum": psum,
                        "verdict": verdict,
                        "extra_hb": extra_hb,
                    }
                )
    return out


def analyze_cuda_val_mem(jsonl: Path, out: Path | None = None) -> int:
    rows = [
        json.loads(line)
        for line in jsonl.read_text(encoding="utf-8").splitlines()
        if line
    ]
    slices = cuda_val_mem_slices(rows)
    print(
        "v3-cuda-val-mem v2 pair=C||HtoD,C||DtoH acceptance=storage-comm "
        "semantics=unchanged v3=not-claimed cost=unchanged"
    )
    print(
        "slice\tN\tpair\tresidency\tk\tr\tcopy\tcompute\tovl\t"
        "ovl/max\tovl/sum\tverdict\textra_hb"
    )
    for s in slices:
        print(
            f"slice\t{s['N']}\t{s['pair']}\t{s['residency']}\t{s['k']}\t"
            f"{s['r']:.3f}\t{s['T_copy_us']:.1f}\t{s['T_compute_us']:.1f}\t"
            f"{s['T_ovl_us']:.1f}\t{s['ovl_over_max']:.3f}\t"
            f"{s['ovl_over_sum']:.3f}\t{s['verdict']}\t{s['extra_hb']}"
        )
    hits = 0
    unbalanced = 0
    bw_only = 0
    for n in NS:
        by_case = {r["case"]: r for r in rows if int(r["N"]) == n}
        for pair, pin_copy, page_copy, _pin_ovl, _page_ovl in VAL_MEM_PAIRS:
            pin_row = by_case.get(pin_copy)
            page_row = by_case.get(page_copy)
            if pin_row and page_row:
                pin_t = float(pin_row["latency_us"])
                page_t = float(page_row["latency_us"])
                ratio = _safe_div(page_t, pin_t)
                print(
                    f"bandwidth\tN={n}\tpair={pair.split('||')[-1]}\t"
                    f"page/pin={ratio:.3f}"
                )
        for pair, _c0, _c1, _o0, _o1 in VAL_MEM_PAIRS:
            pinned = next(
                (s for s in slices
                 if s["N"] == n and s["pair"] == pair and s["residency"] == "pinned"),
                None,
            )
            pageable = next(
                (s for s in slices
                 if s["N"] == n and s["pair"] == pair
                 and s["residency"] == "pageable"),
                None,
            )
            if not pinned or not pageable:
                continue
            # Storage x Comm extra-HB requires a serial flip, not a
            # mixed gray zone from r-unbalanced pageable copies.
            if pinned["verdict"] == "parallel" and pageable["verdict"] == "serial":
                hits += 1
                print(
                    f"counterexample\tN={n}\tpair={pair}\t"
                    f"pinned=parallel\tpageable=serial\t"
                    "extra-hb=pageable-host"
                )
            elif (
                pinned["verdict"] == "parallel"
                and pageable["verdict"] == "mixed"
                and pageable["ovl_over_max"] <= 1.15
            ):
                unbalanced += 1
                print(
                    f"max-like-unbalanced\tN={n}\tpair={pair}\t"
                    f"pinned=parallel\tpageable=mixed\t"
                    "extra-hb=none"
                )
            elif pageable["T_copy_us"] > pinned["T_copy_us"]:
                bw_only += 1
                print(
                    f"bandwidth-only\tN={n}\tpair={pair}\t"
                    f"pinned={pinned['verdict']}\t"
                    f"pageable={pageable['verdict']}"
                )
    print(
        f"summary slices={len(slices)} counterexamples={hits} "
        f"max-like-unbalanced={unbalanced} bandwidth-only={bw_only} "
        "semantics=unchanged v3=not-claimed cost=unchanged"
    )
    if out:
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=VAL_MEM_FIELDS)
            w.writeheader()
            for s in slices:
                w.writerow(
                    {
                        "N": s["N"],
                        "k": s["k"],
                        "pair": s["pair"],
                        "residency": s["residency"],
                        "r": f"{s['r']:.3f}",
                        "T_copy_us": f"{s['T_copy_us']:.1f}",
                        "T_compute_us": f"{s['T_compute_us']:.1f}",
                        "T_ovl_us": f"{s['T_ovl_us']:.1f}",
                        "ovl_over_max": f"{s['ovl_over_max']:.3f}",
                        "ovl_over_sum": f"{s['ovl_over_sum']:.3f}",
                        "verdict": s["verdict"],
                        "extra_hb": s["extra_hb"],
                    }
                )
        print(
            f"record_v3 wrote {out} count={len(slices)} "
            "cuda-val-mem v3=not-claimed"
        )
    return 0


def print_cuda_val_cc_schema() -> int:
    print("cuda-val-cc p0")
    print("pair C_light||C_heavy")
    print("C_light kxSiLU")
    print("C_heavy mxGEMM")
    print("dim 1024")
    print("stream named-nonblocking")
    print("acceptance compute-resource")
    print("pair-relation parallel|serial|mixed")
    print("observed-constraint none|resource_contention")
    print("extra-hb not-applicable")
    print("no-overlap-not-hb")
    print("score3 not-applicable")
    print("semantics unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def parse_val_cc_line(line: str) -> dict[str, Any] | None:
    m = LINE_RE.search(line)
    if not m:
        return None
    func = m.group("func")
    if func not in VAL_CC_FUNCS:
        return None
    return {
        "case": func,
        "N": int(m.group("n")),
        "k": int(m.group("k")),
        "provisioned": 1,
        "score3": "",
        "latency_us": float(m.group("us")),
    }


def _collect_val_cc_rows(
    text: str, gpu: dict[str, str], warmup: int, reps: int, commit: str
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line in text.splitlines():
        parsed = parse_val_cc_line(line)
        if not parsed:
            continue
        rec = base_record(commit, gpu, warmup, reps)
        rec["case"] = parsed["case"]
        rec["N"] = parsed["N"]
        rec["k"] = parsed["k"]
        rec["provisioned"] = parsed["provisioned"]
        rec["score3"] = parsed["score3"]
        rec["latency_us"] = parsed["latency_us"]
        rows.append({key: rec[key] for key in FIELDS})
    return rows


def _choose_val_cc_km(t_silu_unit: float, t_gemm_unit: float) -> tuple[int, int]:
    if t_silu_unit <= t_gemm_unit:
        return choose_phase_k(1.0, t_gemm_unit, t_silu_unit), 1
    return 1, choose_phase_k(1.0, t_silu_unit, t_gemm_unit)


def cuda_val_cc_sweep(bin_path: str, out_prefix: Path, warmup: int, reps: int,
                      commit: str) -> int:
    gpu = collect_gpu()
    gpu["cuda_runtime"] = cuda_runtime_from_bin(bin_path)
    rows: list[dict[str, Any]] = []
    try:
        for n in NS:
            print(f"=== cuda-val-cc calibrate n={n} ===", file=sys.stderr)
            text = _run_adapter(
                bin_path,
                ["--cuda-val-cc=silu", f"--n={n}", "--k=1", "--m=1"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            silu_rows = _collect_val_cc_rows(text, gpu, warmup, reps, commit)
            text = _run_adapter(
                bin_path,
                ["--cuda-val-cc=matmul", f"--n={n}", "--k=1", "--m=1"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            gemm_rows = _collect_val_cc_rows(text, gpu, warmup, reps, commit)
            if len(silu_rows) != 1 or len(gemm_rows) != 1:
                print("record_v3: cuda-val-cc calibrate expected 2 rows",
                      file=sys.stderr)
                return 4
            k, m = _choose_val_cc_km(
                float(silu_rows[0]["latency_us"]),
                float(gemm_rows[0]["latency_us"]),
            )
            print(f"=== cuda-val-cc p0 n={n} k={k} m={m} ===", file=sys.stderr)
            text = _run_adapter(
                bin_path,
                ["--cuda-val-cc=p0", f"--n={n}", f"--k={k}", f"--m={m}"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            got = _collect_val_cc_rows(text, gpu, warmup, reps, commit)
            if {r["case"] for r in got} != set(VAL_CC_ARMS):
                print(
                    f"record_v3: expected 5 val-cc arms, got "
                    f"{[r['case'] for r in got]}",
                    file=sys.stderr,
                )
                return 4
            rows.extend(got)
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"record_v3: cuda-val-cc run failed: {exc}", file=sys.stderr)
        return 2
    write_outputs(rows, out_prefix)
    print(
        f"record_v3 wrote {out_prefix.with_suffix('.jsonl')} "
        f"count={len(rows)} cuda-val-cc v3=not-claimed"
    )
    return 0


def cuda_val_cc_slices(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for n in NS:
        slice_rows = [r for r in rows if int(r["N"]) == n]
        by_case = {r["case"]: r for r in slice_rows}
        need = (
            "val-cc-silu",
            "val-cc-matmul",
            "val-cc-seq",
            "val-cc-ovl",
            "val-cc-silu-silu",
        )
        if any(key not in by_case for key in need):
            continue
        silu = float(by_case["val-cc-silu"]["latency_us"])
        matmul = float(by_case["val-cc-matmul"]["latency_us"])
        seq = float(by_case["val-cc-seq"]["latency_us"])
        ovl = float(by_case["val-cc-ovl"]["latency_us"])
        ss = float(by_case["val-cc-silu-silu"]["latency_us"])
        k = int(by_case["val-cc-silu"]["k"])
        pmax = _safe_div(ovl, max(silu, matmul))
        psum = _safe_div(ovl, silu + matmul)
        smax = _safe_div(ss, silu)
        ssum = _safe_div(ss, 2.0 * silu)
        mixed = _verdict(pmax, psum)
        same = _verdict(smax, ssum)
        # pair_relation is Capability. observed_constraint is not extra HB:
        # T_ovl ≈ T_seq on named streams is resource contention, not
        # HB_CUDA ⊃ HB_S^2C^2 (#60 reserved extra_hb=legacy-default).
        constraint = "resource_contention" if mixed == "serial" else "none"
        out.append(
            {
                "N": n,
                "k": k,
                "dim": VAL_CC_DIM,
                "r": _safe_div(silu, matmul),
                "T_silu_us": silu,
                "T_matmul_us": matmul,
                "T_seq_us": seq,
                "T_ovl_us": ovl,
                "T_silu_silu_us": ss,
                "ovl_over_max": pmax,
                "ovl_over_sum": psum,
                "mixed_verdict": mixed,
                "ss_over_max": smax,
                "ss_over_sum": ssum,
                "same_verdict": same,
                "pair_relation": mixed,
                "observed_constraint": constraint,
            }
        )
    return out


def analyze_cuda_val_cc(jsonl: Path, out: Path | None = None) -> int:
    rows = [
        json.loads(line)
        for line in jsonl.read_text(encoding="utf-8").splitlines()
        if line
    ]
    slices = cuda_val_cc_slices(rows)
    print(
        "v3-cuda-val-cc p0 pair=C_light||C_heavy acceptance=compute-resource "
        "semantics=unchanged v3=not-claimed cost=unchanged"
    )
    print(
        "slice\tN\tk\tdim\tr\tsilu\tmatmul\tseq\tovl\tsilu_silu\t"
        "ovl/max\tovl/sum\tmixed\tss/max\tss/sum\tsame\t"
        "pair_relation\tobserved_constraint"
    )
    serial_hits = 0
    kind_specific = 0
    still_serial = 0
    unexpected = 0
    for s in slices:
        print(
            f"slice\t{s['N']}\t{s['k']}\t{s['dim']}\t{s['r']:.3f}\t"
            f"{s['T_silu_us']:.1f}\t{s['T_matmul_us']:.1f}\t"
            f"{s['T_seq_us']:.1f}\t{s['T_ovl_us']:.1f}\t"
            f"{s['T_silu_silu_us']:.1f}\t{s['ovl_over_max']:.3f}\t"
            f"{s['ovl_over_sum']:.3f}\t{s['mixed_verdict']}\t"
            f"{s['ss_over_max']:.3f}\t{s['ss_over_sum']:.3f}\t"
            f"{s['same_verdict']}\t{s['pair_relation']}\t"
            f"{s['observed_constraint']}"
        )
        print(
            f"control\tN={s['N']}\tsame-kind={s['same_verdict']}"
        )
        print(
            f"mixed\tN={s['N']}\tsilu||matmul={s['mixed_verdict']}\t"
            f"pair-relation={s['pair_relation']}\t"
            f"observed-constraint={s['observed_constraint']}"
        )
        if s["same_verdict"] == "parallel":
            unexpected += 1
            print(
                f"unexpected-same-kind-overlap\tN={s['N']}\t"
                f"same={s['same_verdict']}"
            )
        elif s["same_verdict"] == "serial" and s["mixed_verdict"] == "parallel":
            kind_specific += 1
            print(
                f"kind-specific\tN={s['N']}\tsame=serial\tmixed=parallel"
            )
        elif s["same_verdict"] == "serial" and s["mixed_verdict"] == "serial":
            still_serial += 1
            serial_hits += 1
            print(
                f"still-serial\tN={s['N']}\tsame=serial\tmixed=serial\t"
                "observed-constraint=resource_contention"
            )
        elif s["mixed_verdict"] == "serial":
            serial_hits += 1
    print(
        f"summary slices={len(slices)} resource-contention={serial_hits} "
        f"kind-specific={kind_specific} still-serial={still_serial} "
        f"unexpected-same-kind={unexpected} "
        "no-overlap-not-hb "
        "semantics=unchanged v3=not-claimed cost=unchanged"
    )
    if out:
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=VAL_CC_FIELDS)
            w.writeheader()
            for s in slices:
                w.writerow(
                    {
                        "N": s["N"],
                        "k": s["k"],
                        "dim": s["dim"],
                        "r": f"{s['r']:.3f}",
                        "T_silu_us": f"{s['T_silu_us']:.1f}",
                        "T_matmul_us": f"{s['T_matmul_us']:.1f}",
                        "T_seq_us": f"{s['T_seq_us']:.1f}",
                        "T_ovl_us": f"{s['T_ovl_us']:.1f}",
                        "T_silu_silu_us": f"{s['T_silu_silu_us']:.1f}",
                        "ovl_over_max": f"{s['ovl_over_max']:.3f}",
                        "ovl_over_sum": f"{s['ovl_over_sum']:.3f}",
                        "mixed_verdict": s["mixed_verdict"],
                        "ss_over_max": f"{s['ss_over_max']:.3f}",
                        "ss_over_sum": f"{s['ss_over_sum']:.3f}",
                        "same_verdict": s["same_verdict"],
                        "pair_relation": s["pair_relation"],
                        "observed_constraint": s["observed_constraint"],
                    }
                )
        print(
            f"record_v3 wrote {out} count={len(slices)} "
            "cuda-val-cc v3=not-claimed"
        )
    return 0


def print_cuda_val_async_schema() -> int:
    print("cuda-val-async v2p1")
    print("chain materialize->write->event->wait->read->release")
    print("alloc cudaMalloc cudaMallocAsync")
    print("wait cudaStreamWaitEvent")
    print("extra-hb none|sync-alloc")
    print("score3 not-applicable")
    print("semantics unchanged")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def parse_val_async_line(line: str) -> dict[str, Any] | None:
    m = LINE_RE.search(line)
    if not m:
        return None
    func = m.group("func")
    if func not in VAL_ASYNC_FUNCS:
        return None
    return {
        "case": func,
        "N": int(m.group("n")),
        "k": int(m.group("k")),
        "provisioned": 1,
        "score3": "",
        "latency_us": float(m.group("us")),
    }


def _collect_val_async_rows(
    text: str, gpu: dict[str, str], warmup: int, reps: int, commit: str
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line in text.splitlines():
        parsed = parse_val_async_line(line)
        if not parsed:
            continue
        rec = base_record(commit, gpu, warmup, reps)
        rec["case"] = parsed["case"]
        rec["N"] = parsed["N"]
        rec["k"] = parsed["k"]
        rec["provisioned"] = parsed["provisioned"]
        rec["score3"] = parsed["score3"]
        rec["latency_us"] = parsed["latency_us"]
        rows.append({key: rec[key] for key in FIELDS})
    return rows


def cuda_val_async_sweep(bin_path: str, out_prefix: Path, warmup: int,
                         reps: int, commit: str) -> int:
    gpu = collect_gpu()
    gpu["cuda_runtime"] = cuda_runtime_from_bin(bin_path)
    rows: list[dict[str, Any]] = []
    try:
        for n in NS:
            print(f"=== cuda-val-async calibrate n={n} ===", file=sys.stderr)
            text = _run_adapter(
                bin_path,
                ["--cuda-val-async=copy", f"--n={n}", "--k=1"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            copy_rows = _collect_val_async_rows(text, gpu, warmup, reps, commit)
            text = _run_adapter(
                bin_path,
                ["--cuda-val-async=compute", f"--n={n}", "--k=1"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            unit_rows = _collect_val_async_rows(text, gpu, warmup, reps, commit)
            if len(copy_rows) != 1 or len(unit_rows) != 1:
                print("record_v3: cuda-val-async calibrate expected 2 rows",
                      file=sys.stderr)
                return 4
            k = choose_phase_k(
                1.0,
                float(copy_rows[0]["latency_us"]),
                float(unit_rows[0]["latency_us"]),
            )
            print(f"=== cuda-val-async p0 n={n} k={k} ===", file=sys.stderr)
            text = _run_adapter(
                bin_path,
                ["--cuda-val-async=p0", f"--n={n}", f"--k={k}"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            got = _collect_val_async_rows(text, gpu, warmup, reps, commit)
            if {r["case"] for r in got} != set(VAL_ASYNC_ARMS):
                print(
                    f"record_v3: expected 5 val-async arms, got "
                    f"{[r['case'] for r in got]}",
                    file=sys.stderr,
                )
                return 4
            rows.extend(got)
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"record_v3: cuda-val-async run failed: {exc}", file=sys.stderr)
        return 2
    write_outputs(rows, out_prefix)
    print(
        f"record_v3 wrote {out_prefix.with_suffix('.jsonl')} "
        f"count={len(rows)} cuda-val-async v3=not-claimed"
    )
    return 0


def cuda_val_async_slices(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for n in NS:
        by_case = {r["case"]: r for r in rows if int(r["N"]) == n}
        need = list(VAL_ASYNC_ARMS)
        if any(key not in by_case for key in need):
            continue
        copy = float(by_case["val-async-copy"]["latency_us"])
        compute = float(by_case["val-async-compute"]["latency_us"])
        life_sync = float(by_case["val-async-life-sync"]["latency_us"])
        life_async = float(by_case["val-async-life-async"]["latency_us"])
        hb = float(by_case["val-async-hb"]["latency_us"])
        sync_over = _safe_div(life_sync, life_async)
        hb_over = _safe_div(hb, life_async)
        extra = "sync-alloc" if sync_over >= 1.15 else "none"
        out.append(
            {
                "N": n,
                "k": int(by_case["val-async-hb"]["k"]),
                "r": _safe_div(compute, copy),
                "T_copy_us": copy,
                "T_compute_us": compute,
                "T_life_sync_us": life_sync,
                "T_life_async_us": life_async,
                "T_hb_us": hb,
                "sync_over_async": sync_over,
                "hb_over_async": hb_over,
                "extra_hb": extra,
            }
        )
    return out


def analyze_cuda_val_async(jsonl: Path, out: Path | None = None) -> int:
    rows = [
        json.loads(line)
        for line in jsonl.read_text(encoding="utf-8").splitlines()
        if line
    ]
    slices = cuda_val_async_slices(rows)
    print(
        "v3-cuda-val-async v2p1 chain=materialize-write-event-wait-read-release "
        "semantics=unchanged v3=not-claimed cost=unchanged"
    )
    print(
        "slice\tN\tk\tr\tcopy\tcompute\tlife_sync\tlife_async\thb\t"
        "sync/async\thb/async\textra_hb"
    )
    hits = 0
    for s in slices:
        print(
            f"slice\t{s['N']}\t{s['k']}\t{s['r']:.3f}\t"
            f"{s['T_copy_us']:.1f}\t{s['T_compute_us']:.1f}\t"
            f"{s['T_life_sync_us']:.1f}\t{s['T_life_async_us']:.1f}\t"
            f"{s['T_hb_us']:.1f}\t{s['sync_over_async']:.3f}\t"
            f"{s['hb_over_async']:.3f}\t{s['extra_hb']}"
        )
        if s["extra_hb"] == "sync-alloc":
            hits += 1
            print(
                f"counterexample\tN={s['N']}\t"
                f"sync/async={s['sync_over_async']:.3f}\t"
                "extra-hb=sync-alloc"
            )
    print(
        f"summary slices={len(slices)} counterexamples={hits} "
        "semantics=unchanged v3=not-claimed cost=unchanged"
    )
    if out:
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=VAL_ASYNC_FIELDS)
            w.writeheader()
            for s in slices:
                w.writerow(
                    {
                        "N": s["N"],
                        "k": s["k"],
                        "r": f"{s['r']:.3f}",
                        "T_copy_us": f"{s['T_copy_us']:.1f}",
                        "T_compute_us": f"{s['T_compute_us']:.1f}",
                        "T_life_sync_us": f"{s['T_life_sync_us']:.1f}",
                        "T_life_async_us": f"{s['T_life_async_us']:.1f}",
                        "T_hb_us": f"{s['T_hb_us']:.1f}",
                        "sync_over_async": f"{s['sync_over_async']:.3f}",
                        "hb_over_async": f"{s['hb_over_async']:.3f}",
                        "extra_hb": s["extra_hb"],
                    }
                )
        print(
            f"record_v3 wrote {out} count={len(slices)} "
            "cuda-val-async v3=not-claimed"
        )
    return 0


def print_phase_schema() -> int:
    print("phase-arm seq ovl copy compute")
    print("axis r=T_compute/T_copy")
    print("axis size=N")
    print("pair C||HtoD")
    print("score3 not-applicable")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def print_cap_schema() -> int:
    print("cap-arm pairs sync size intensity")
    print("score3 not-applicable")
    print("source driver_version=nvidia-smi")
    print("source nvcc_version=nvcc")
    print("source cuda_runtime=cudaRuntimeGetVersion")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def print_matched_schema() -> int:
    print("matched-arm seq ovl copy compute")
    print("remaining-work 1xHtoD+kxSiLU")
    print("score3 not-applicable")
    print("source driver_version=nvidia-smi")
    print("source nvcc_version=nvcc")
    print("source cuda_runtime=cudaRuntimeGetVersion")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def write_outputs(rows: list[dict[str, Any]], out_prefix: Path) -> None:
    out_prefix.parent.mkdir(parents=True, exist_ok=True)
    jsonl = out_prefix.with_suffix(".jsonl")
    csv_path = out_prefix.with_suffix(".csv")
    with jsonl.open("w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, sort_keys=False) + "\n")
    with csv_path.open("w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)


def sweep(bin_path: str, out_prefix: Path, warmup: int, reps: int, commit: str) -> int:
    gpu = collect_gpu()
    gpu["cuda_runtime"] = cuda_runtime_from_bin(bin_path)
    rows: list[dict[str, Any]] = []
    for n in NS:
        for k in KS:
            for prov in PROVS:
                args = [
                    bin_path,
                    "--func=all",
                    "--device=gpu",
                    f"--n={n}",
                    f"--k={k}",
                    f"--warmup={warmup}",
                    f"--reps={reps}",
                ]
                if prov:
                    args.append("--provisioned")
                print(f"=== n={n} k={k} provisioned={prov} ===", file=sys.stderr)
                try:
                    proc = subprocess.run(
                        args, check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
                    )
                    text = proc.stdout
                except (OSError, subprocess.CalledProcessError) as exc:
                    print(f"record_v3: run failed: {exc}", file=sys.stderr)
                    return 2
                print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
                found = 0
                for line in text.splitlines():
                    parsed = parse_adapter_line(line)
                    if not parsed:
                        continue
                    if parsed["expected_score3"] != parsed["score3"]:
                        print("record_v3: score3 mismatch", file=sys.stderr)
                        return 3
                    rec = base_record(commit, gpu, warmup, reps)
                    rec["case"] = parsed["case"]
                    rec["N"] = parsed["N"]
                    rec["k"] = parsed["k"]
                    rec["provisioned"] = parsed["provisioned"]
                    rec["score3"] = parsed["score3"]
                    rec["latency_us"] = parsed["latency_us"]
                    rows.append({k: rec[k] for k in FIELDS})
                    found += 1
                if found != 3:
                    print(f"record_v3: expected 3 points, got {found}", file=sys.stderr)
                    return 4
    if len(rows) != 36:
        print(f"record_v3: expected 36 rows, got {len(rows)}", file=sys.stderr)
        return 5
    write_outputs(rows, out_prefix)
    print(f"record_v3 wrote {out_prefix.with_suffix('.jsonl')} count=36 v3=not-claimed")
    return 0


def rankdata(vals: list[float]) -> list[float]:
    order = sorted(range(len(vals)), key=lambda i: vals[i])
    ranks = [0.0] * len(vals)
    i = 0
    while i < len(vals):
        j = i
        while j + 1 < len(vals) and vals[order[j + 1]] == vals[order[i]]:
            j += 1
        avg = (i + j) / 2.0 + 1.0
        for k in range(i, j + 1):
            ranks[order[k]] = avg
        i = j + 1
    return ranks


def spearman(xs: list[float], ys: list[float]) -> float:
    rx, ry = rankdata(xs), rankdata(ys)
    n = len(xs)
    mx, my = sum(rx) / n, sum(ry) / n
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    dx = sum((a - mx) ** 2 for a in rx)
    dy = sum((b - my) ** 2 for b in ry)
    if dx == 0 or dy == 0:
        return float("nan")
    return num / (dx * dy) ** 0.5


def matched_sweep(bin_path: str, out_prefix: Path, warmup: int, reps: int,
                  commit: str) -> int:
    gpu = collect_gpu()
    gpu["cuda_runtime"] = cuda_runtime_from_bin(bin_path)
    rows: list[dict[str, Any]] = []
    for n in NS:
        for k in MATCHED_KS:
            args = [
                bin_path,
                "--matched=all",
                "--device=gpu",
                f"--n={n}",
                f"--k={k}",
                f"--warmup={warmup}",
                f"--reps={reps}",
            ]
            print(f"=== matched n={n} k={k} ===", file=sys.stderr)
            try:
                proc = subprocess.run(
                    args, check=True, text=True,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT
                )
                text = proc.stdout
            except (OSError, subprocess.CalledProcessError) as exc:
                print(f"record_v3: matched run failed: {exc}", file=sys.stderr)
                return 2
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            found = 0
            for line in text.splitlines():
                parsed = parse_matched_line(line)
                if not parsed:
                    continue
                rec = base_record(commit, gpu, warmup, reps)
                rec["case"] = parsed["case"]
                rec["N"] = parsed["N"]
                rec["k"] = parsed["k"]
                rec["provisioned"] = parsed["provisioned"]
                rec["score3"] = parsed["score3"]
                rec["latency_us"] = parsed["latency_us"]
                rows.append({key: rec[key] for key in FIELDS})
                found += 1
            if found != 4:
                print(f"record_v3: expected 4 matched arms, got {found}",
                      file=sys.stderr)
                return 4
    if len(rows) != 48:
        print(f"record_v3: expected 48 matched rows, got {len(rows)}",
              file=sys.stderr)
        return 5
    write_outputs(rows, out_prefix)
    print(f"record_v3 wrote {out_prefix.with_suffix('.jsonl')} "
          f"count=48 matched v3=not-claimed")
    return 0


def _safe_div(num: float, den: float) -> float:
    if den == 0:
        return float("nan")
    return num / den


def matched_slices(rows: list[dict[str, Any]]) -> list[dict[str, float | int]]:
    out: list[dict[str, float | int]] = []
    for n in NS:
        for k in MATCHED_KS:
            slice_rows = [r for r in rows if r["N"] == n and r["k"] == k]
            by_case = {r["case"]: r for r in slice_rows}
            if not MATCHED_FUNCS.issubset(by_case):
                continue
            seq = float(by_case["matched-seq"]["latency_us"])
            ovl = float(by_case["matched-ovl"]["latency_us"])
            copy = float(by_case["matched-copy"]["latency_us"])
            compute = float(by_case["matched-compute"]["latency_us"])
            out.append(
                {
                    "N": n,
                    "k": k,
                    "T_seq_us": seq,
                    "T_ovl_us": ovl,
                    "T_copy_us": copy,
                    "T_compute_us": compute,
                    "ratio": _safe_div(compute, copy),
                    "gain_us": seq - ovl,
                    "ideal_us": min(copy, compute),
                    "hidden_frac": _safe_div(seq - ovl, min(copy, compute)),
                    "seq_over_sum": _safe_div(seq, copy + compute),
                    "ovl_over_max": _safe_div(ovl, max(copy, compute)),
                }
            )
    return out


def print_calibration_schema() -> int:
    print(",".join(CAL_FIELDS))
    print("map (N,k)->(T_copy,T_compute,T_seq,T_ovl,hidden_frac)")
    print("overlap-semantics direction-validated")
    print("score3 not-validated")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def calibrate(jsonl: Path, out: Path | None) -> int:
    rows = [json.loads(line) for line in jsonl.read_text(encoding="utf-8").splitlines() if line]
    slices = matched_slices(rows)
    print("v3-calibration v3=not-claimed cost=unchanged")
    print("\t".join(CAL_FIELDS))
    for s in slices:
        print(
            f"{s['N']}\t{s['k']}\t{s['T_seq_us']:.1f}\t{s['T_ovl_us']:.1f}\t"
            f"{s['T_copy_us']:.1f}\t{s['T_compute_us']:.1f}\t{s['ratio']:.3f}\t"
            f"{s['gain_us']:.1f}\t{s['ideal_us']:.1f}\t{s['hidden_frac']:.3f}\t"
            f"{s['seq_over_sum']:.3f}\t{s['ovl_over_max']:.3f}"
        )
    if slices:
        hiddens = [float(s["hidden_frac"]) for s in slices if s["hidden_frac"] == s["hidden_frac"]]
        mean = sum(hiddens) / len(hiddens) if hiddens else float("nan")
        print(f"summary slices={len(slices)} mean_hidden_frac={mean:.3f} "
              f"overlap-semantics=direction-validated score3=not-validated "
              f"v3=not-claimed")
    if out:
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=CAL_FIELDS)
            w.writeheader()
            for s in slices:
                row = {
                    "N": s["N"],
                    "k": s["k"],
                    "T_seq_us": f"{s['T_seq_us']:.1f}",
                    "T_ovl_us": f"{s['T_ovl_us']:.1f}",
                    "T_copy_us": f"{s['T_copy_us']:.1f}",
                    "T_compute_us": f"{s['T_compute_us']:.1f}",
                    "ratio": f"{s['ratio']:.3f}",
                    "gain_us": f"{s['gain_us']:.1f}",
                    "ideal_us": f"{s['ideal_us']:.1f}",
                    "hidden_frac": f"{s['hidden_frac']:.3f}",
                    "seq_over_sum": f"{s['seq_over_sum']:.3f}",
                    "ovl_over_max": f"{s['ovl_over_max']:.3f}",
                }
                w.writerow(row)
        print(f"record_v3 wrote {out} count={len(slices)} calibration v3=not-claimed")
    return 0


def load_ratio_rows(path: Path) -> list[dict[str, float | int]]:
    if path.suffix == ".csv":
        with path.open(encoding="utf-8", newline="") as fh:
            raw = list(csv.DictReader(fh))
        rows: list[dict[str, float | int]] = []
        for r in raw:
            rows.append(
                {
                    "N": int(r["N"]),
                    "k": int(r["k"]),
                    "ratio": float(r["ratio"]),
                    "hidden_frac": float(r["hidden_frac"]),
                }
            )
        return rows
    recs = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]
    return matched_slices(recs)


def print_ratio_schema() -> int:
    print("axis r=T_compute/T_copy")
    print("metric hidden_frac")
    print("outlier hidden_frac>1 measurement-noise")
    print("v3=not-claimed")
    print("cost=unchanged")
    return 0


def analyze_ratio(path: Path) -> int:
    rows = load_ratio_rows(path)
    if not rows:
        print("record_v3: no ratio rows", file=sys.stderr)
        return 6
    print("v3-ratio v3=not-claimed cost=unchanged")
    print("slice\tN\tk\tratio\thidden_frac\tflag")
    outliers = []
    clean = []
    for s in rows:
        hf = float(s["hidden_frac"])
        flag = "measurement-noise" if hf > 1.0 else "ok"
        if hf > 1.0:
            outliers.append(s)
        else:
            clean.append(s)
        print(f"slice\t{s['N']}\t{s['k']}\t{float(s['ratio']):.3f}\t{hf:.3f}\t{flag}")

    def rho_of(group: list[dict[str, float | int]]) -> float:
        if len(group) < 2:
            return float("nan")
        return spearman([float(s["ratio"]) for s in group],
                        [float(s["hidden_frac"]) for s in group])

    wc = [s for s in clean if 0.2 < float(s["ratio"]) < 4.0]
    ordered = sorted(clean, key=lambda s: float(s["ratio"]))
    inversions = 0
    for a, b in zip(ordered, ordered[1:]):
        if float(b["hidden_frac"]) + 1e-9 < float(a["hidden_frac"]):
            inversions += 1
    rho_all = rho_of(rows)
    rho_clean = rho_of(clean)
    rho_wc = rho_of(wc)
    if rho_wc != rho_wc or abs(rho_wc) < 0.3:
        verdict = "not-stable"
    elif rho_wc >= 0.7 and inversions == 0:
        verdict = "stable"
    else:
        verdict = "partial"
    print(
        f"summary slices={len(rows)} outliers={len(outliers)} "
        f"rho_all={rho_all:.3f} rho_clean={rho_clean:.3f} "
        f"rho_wellcond={rho_wc:.3f} inversions={inversions} "
        f"f(r)={verdict} v3=not-claimed"
    )
    return 0


def analyze_matched(jsonl: Path) -> int:
    rows = [json.loads(line) for line in jsonl.read_text(encoding="utf-8").splitlines() if line]
    print("v3-matched v3=not-claimed cost=unchanged")
    print("slice\tN\tk\tseq\tovl\tcopy\tcompute\tratio\tgain\tideal\thidden\t"
          "seq_over_sum\tovl_over_max")
    hiddens = []
    for n in NS:
        for k in MATCHED_KS:
            slice_rows = [r for r in rows if r["N"] == n and r["k"] == k]
            by_case = {r["case"]: r for r in slice_rows}
            if not MATCHED_FUNCS.issubset(by_case):
                # Allow a fixture with a subset of N/k as long as each
                # present slice is complete.
                if not slice_rows:
                    continue
                print(f"record_v3: incomplete matched slice N={n} k={k}",
                      file=sys.stderr)
                return 6
            seq = float(by_case["matched-seq"]["latency_us"])
            ovl = float(by_case["matched-ovl"]["latency_us"])
            copy = float(by_case["matched-copy"]["latency_us"])
            compute = float(by_case["matched-compute"]["latency_us"])
            ratio = _safe_div(compute, copy)
            gain = seq - ovl
            ideal = min(copy, compute)
            hidden = _safe_div(gain, ideal)
            hiddens.append(hidden)
            print(
                f"slice\t{n}\t{k}\t{seq:.1f}\t{ovl:.1f}\t{copy:.1f}\t"
                f"{compute:.1f}\t{ratio:.3f}\t{gain:.1f}\t{ideal:.1f}\t"
                f"{hidden:.3f}\t{_safe_div(seq, copy + compute):.3f}\t"
                f"{_safe_div(ovl, max(copy, compute)):.3f}"
            )
    if hiddens:
        finite = [h for h in hiddens if h == h]
        mean = sum(finite) / len(finite) if finite else float("nan")
        print(f"summary slices={len(hiddens)} mean_hidden_frac={mean:.3f} "
              f"v3=not-claimed")
    return 0


def analyze(jsonl: Path) -> int:
    rows = [json.loads(line) for line in jsonl.read_text(encoding="utf-8").splitlines() if line]
    print("v3-analysis v3=not-claimed")
    print("slice\tN\tk\tprov\tlat_a\tlat_b\tlat_c\tcost_rank\tlat_rank\trho\tpairs")
    rhos = []
    pair_hits = 0
    pair_tot = 0
    for n in NS:
        for k in KS:
            for prov in PROVS:
                slice_rows = [
                    r for r in rows if r["N"] == n and r["k"] == k and r["provisioned"] == prov
                ]
                by_case = {r["case"]: r for r in slice_rows}
                if set(by_case) != {"a", "b", "c"}:
                    print(f"record_v3: incomplete slice N={n} k={k} p={prov}", file=sys.stderr)
                    return 6
                lat = [by_case[c]["latency_us"] for c in "abc"]
                score = [by_case[c]["score3"] for c in "abc"]
                # lower is better
                cost_order = "".join(sorted("abc", key=lambda c: by_case[c]["score3"]))
                lat_order = "".join(sorted("abc", key=lambda c: by_case[c]["latency_us"]))
                rho = spearman(score, lat)
                rhos.append(rho)
                pairs = []
                for x, y in (("b", "a"), ("a", "c"), ("b", "c")):
                    cost_lt = by_case[x]["score3"] < by_case[y]["score3"]
                    lat_lt = by_case[x]["latency_us"] < by_case[y]["latency_us"]
                    ok = cost_lt == lat_lt
                    pair_tot += 1
                    pair_hits += int(ok)
                    pairs.append(f"{x}{y}={'Y' if ok else 'N'}")
                print(
                    f"slice\t{n}\t{k}\t{prov}\t{lat[0]:.1f}\t{lat[1]:.1f}\t"
                    f"{lat[2]:.1f}\t{cost_order}\t{lat_order}\t{rho:.3f}\t"
                    + ",".join(pairs)
                )
    if rhos:
        finite = [r for r in rhos if r == r]
        mean = sum(finite) / len(finite) if finite else float("nan")
        print(f"summary slices={len(rhos)} mean_rho={mean:.3f} "
              f"pairwise={pair_hits}/{pair_tot} v3=not-claimed")
    return 0


def _run_adapter(bin_path: str, extra: list[str], warmup: int, reps: int) -> str:
    args = [
        bin_path,
        "--device=gpu",
        f"--warmup={warmup}",
        f"--reps={reps}",
        *extra,
    ]
    proc = subprocess.run(
        args, check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    return proc.stdout or ""


def _collect_cap_rows(
    text: str, gpu: dict[str, str], warmup: int, reps: int, commit: str
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line in text.splitlines():
        parsed = parse_cap_line(line)
        if not parsed:
            continue
        rec = base_record(commit, gpu, warmup, reps)
        rec["case"] = parsed["case"]
        rec["N"] = parsed["N"]
        rec["k"] = parsed["k"]
        rec["provisioned"] = parsed["provisioned"]
        rec["score3"] = parsed["score3"]
        rec["latency_us"] = parsed["latency_us"]
        rows.append({key: rec[key] for key in FIELDS})
    return rows


def cap_sweep(bin_path: str, out_prefix: Path, warmup: int, reps: int,
              commit: str) -> int:
    gpu = collect_gpu()
    gpu["cuda_runtime"] = cuda_runtime_from_bin(bin_path)
    rows: list[dict[str, Any]] = []
    try:
        for n in NS:
            print(f"=== cap pairs n={n} k={CAP_K} ===", file=sys.stderr)
            text = _run_adapter(
                bin_path,
                [f"--cap=pairs", f"--n={n}", f"--k={CAP_K}"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            got = _collect_cap_rows(text, gpu, warmup, reps, commit)
            if len(got) != len(CAP_PAIR_ARMS):
                print(
                    f"record_v3: expected {len(CAP_PAIR_ARMS)} pair arms, "
                    f"got {len(got)}",
                    file=sys.stderr,
                )
                return 4
            rows.extend(got)
        for nbytes in CAP_SIZE_BYTES:
            n = nbytes // 4
            print(f"=== cap size bytes={nbytes} n={n} ===", file=sys.stderr)
            for arm in ("htod", "dtoh"):
                text = _run_adapter(
                    bin_path,
                    [f"--cap={arm}", f"--n={n}", "--k=1"],
                    warmup,
                    reps,
                )
                print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
                got = _collect_cap_rows(text, gpu, warmup, reps, commit)
                if len(got) != 1:
                    print(f"record_v3: expected 1 size arm, got {len(got)}",
                          file=sys.stderr)
                    return 4
                rows.extend(got)
        print("=== cap sync ===", file=sys.stderr)
        text = _run_adapter(
            bin_path, ["--cap=sync", "--n=256", "--k=1"], warmup, reps
        )
        print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
        got = _collect_cap_rows(text, gpu, warmup, reps, commit)
        if len(got) != len(CAP_SYNC_ARMS):
            print(
                f"record_v3: expected {len(CAP_SYNC_ARMS)} sync arms, "
                f"got {len(got)}",
                file=sys.stderr,
            )
            return 4
        rows.extend(got)
        for n in NS:
            print(f"=== cap reduction n={n} ===", file=sys.stderr)
            text = _run_adapter(
                bin_path, ["--cap=reduction", f"--n={n}", "--k=1"], warmup, reps
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            got = _collect_cap_rows(text, gpu, warmup, reps, commit)
            if len(got) != 1:
                print(f"record_v3: expected 1 reduction, got {len(got)}",
                      file=sys.stderr)
                return 4
            rows.extend(got)
        for dim in CAP_MATMUL_DIMS:
            print(f"=== cap matmul dim={dim} ===", file=sys.stderr)
            text = _run_adapter(
                bin_path, ["--cap=matmul", f"--n={dim}", "--k=1"], warmup, reps
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            got = _collect_cap_rows(text, gpu, warmup, reps, commit)
            if len(got) != 1:
                print(f"record_v3: expected 1 matmul, got {len(got)}",
                      file=sys.stderr)
                return 4
            rows.extend(got)
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"record_v3: cap run failed: {exc}", file=sys.stderr)
        return 2
    expected = (
        len(NS) * len(CAP_PAIR_ARMS)
        + len(CAP_SIZE_BYTES) * 2
        + len(CAP_SYNC_ARMS)
        + len(NS)
        + len(CAP_MATMUL_DIMS)
    )
    if len(rows) != expected:
        print(f"record_v3: expected {expected} cap rows, got {len(rows)}",
              file=sys.stderr)
        return 5
    write_outputs(rows, out_prefix)
    print(
        f"record_v3 wrote {out_prefix.with_suffix('.jsonl')} "
        f"count={len(rows)} cap v3=not-claimed"
    )
    return 0


def _verdict(par_over_max: float, par_over_sum: float) -> str:
    if par_over_sum >= 0.90:
        return "serial"
    if par_over_max <= 1.15 and par_over_sum <= 0.75:
        return "parallel"
    return "mixed"


def _fit_launch_bw(points: list[tuple[float, float]]) -> tuple[float, float]:
    """Least squares T_us = a + b * bytes. Returns (T_launch_us, BW_GBps)."""
    if len(points) < 2:
        return float("nan"), float("nan")
    n = float(len(points))
    sx = sum(b for b, _ in points)
    sy = sum(t for _, t in points)
    sxx = sum(b * b for b, _ in points)
    sxy = sum(b * t for b, t in points)
    den = n * sxx - sx * sx
    if den == 0:
        return float("nan"), float("nan")
    b = (n * sxy - sx * sy) / den
    a = (sy - b * sx) / n
    bw = 0.001 / b if b > 0 else float("nan")
    return a, bw


def analyze_cap(jsonl: Path) -> int:
    rows = [
        json.loads(line)
        for line in jsonl.read_text(encoding="utf-8").splitlines()
        if line
    ]
    print("v3-cap v3=not-claimed cost=unchanged")
    print("pair\tname\tN\tA\tB\tpar\tpar/max\tpar/sum\tverdict")
    for n in NS:
        slice_rows = [
            r
            for r in rows
            if r["N"] == n and str(r["case"]).startswith("cap-") and r["k"] == CAP_K
        ]
        by_case = {r["case"]: r for r in slice_rows}
        for name, a_key, b_key, p_key in CAP_PAIRS:
            if a_key not in by_case or b_key not in by_case or p_key not in by_case:
                continue
            a = float(by_case[a_key]["latency_us"])
            b = float(by_case[b_key]["latency_us"])
            par = float(by_case[p_key]["latency_us"])
            pmax = _safe_div(par, max(a, b))
            psum = _safe_div(par, a + b)
            print(
                f"pair\t{name}\t{n}\t{a:.1f}\t{b:.1f}\t{par:.1f}\t"
                f"{pmax:.3f}\t{psum:.3f}\t{_verdict(pmax, psum)}"
            )
        if "cap-htod-dtoh-seq" in by_case and "cap-htod-dtoh-par" in by_case:
            seq = float(by_case["cap-htod-dtoh-seq"]["latency_us"])
            par = float(by_case["cap-htod-dtoh-par"]["latency_us"])
            print(
                f"bidir\tHtoD||DtoH\t{n}\tseq={seq:.1f}\tpar={par:.1f}\t"
                f"par/seq={_safe_div(par, seq):.3f}"
            )
        if "cap-htod-dtoh-seq" in by_case and "cap-htod-dtoh-event" in by_case:
            seq = float(by_case["cap-htod-dtoh-seq"]["latency_us"])
            ev = float(by_case["cap-htod-dtoh-event"]["latency_us"])
            print(
                f"event-path\t{n}\tseq={seq:.1f}\tevent={ev:.1f}\t"
                f"delta={ev - seq:.1f}"
            )

    print("size\tdir\tbytes\tN\tT_us\tGB/s")
    size_ns = {nbytes // 4: nbytes for nbytes in CAP_SIZE_BYTES}
    htod_fit: list[tuple[float, float]] = []
    dtoh_fit: list[tuple[float, float]] = []
    for r in rows:
        if r["case"] not in ("cap-htod", "cap-dtoh"):
            continue
        n = int(r["N"])
        if n not in size_ns:
            continue
        # Pair-matrix copies also use 4M/16M/64M; keep size-curve
        # rows as k=1 and matrix rows as k=CAP_K.
        if int(r["k"]) != 1:
            continue
        nbytes = size_ns[n]
        t = float(r["latency_us"])
        gbs = _safe_div(nbytes, t) * 1e-3
        print(f"size\t{r['case'][4:]}\t{nbytes}\t{n}\t{t:.1f}\t{gbs:.2f}")
        if nbytes >= 1024 * 1024:
            if r["case"] == "cap-htod":
                htod_fit.append((float(nbytes), t))
            else:
                dtoh_fit.append((float(nbytes), t))
    a_h, bw_h = _fit_launch_bw(htod_fit)
    a_d, bw_d = _fit_launch_bw(dtoh_fit)
    print(f"fit\thtod\tT_launch={a_h:.2f}\tBW_GBps={bw_h:.2f}")
    print(f"fit\tdtoh\tT_launch={a_d:.2f}\tBW_GBps={bw_d:.2f}")

    print("sync\tarm\tT_us")
    for r in rows:
        if r["case"] in CAP_SYNC_ARMS:
            print(f"sync\t{r['case']}\t{float(r['latency_us']):.3f}")

    print("intensity\tkind\tN\tT_us")
    for r in rows:
        if r["case"] in ("cap-reduction", "cap-matmul"):
            print(
                f"intensity\t{r['case'][4:]}\t{r['N']}\t"
                f"{float(r['latency_us']):.1f}"
            )
        if r["case"] == "cap-compute" and int(r["k"]) == CAP_K:
            print(
                f"intensity\telementwise\t{r['N']}\t"
                f"{float(r['latency_us']):.1f}"
            )
    print("v3-cap summary v3=not-claimed cost=unchanged")
    return 0


def choose_phase_k(r_target: float, t_copy: float, t_unit: float) -> int:
    if t_unit <= 0:
        return 1
    k = int(round(r_target * t_copy / t_unit))
    return max(1, min(k, PHASE_K_MAX))


def _collect_phase_rows(
    text: str, gpu: dict[str, str], warmup: int, reps: int, commit: str
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line in text.splitlines():
        parsed = parse_phase_line(line)
        if not parsed:
            continue
        rec = base_record(commit, gpu, warmup, reps)
        rec["case"] = parsed["case"]
        rec["N"] = parsed["N"]
        rec["k"] = parsed["k"]
        rec["provisioned"] = parsed["provisioned"]
        rec["score3"] = parsed["score3"]
        rec["latency_us"] = parsed["latency_us"]
        rows.append({key: rec[key] for key in FIELDS})
    return rows


def phase_sweep(bin_path: str, out_prefix: Path, warmup: int, reps: int,
                commit: str) -> int:
    gpu = collect_gpu()
    gpu["cuda_runtime"] = cuda_runtime_from_bin(bin_path)
    rows: list[dict[str, Any]] = []
    try:
        for n in NS:
            print(f"=== phase calibrate n={n} ===", file=sys.stderr)
            text = _run_adapter(
                bin_path, ["--phase=copy", f"--n={n}", "--k=1"], warmup, reps
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            copy_rows = _collect_phase_rows(text, gpu, warmup, reps, commit)
            if len(copy_rows) != 1:
                print(f"record_v3: expected 1 phase-copy, got {len(copy_rows)}",
                      file=sys.stderr)
                return 4
            rows.extend(copy_rows)
            t_copy = float(copy_rows[0]["latency_us"])
            text = _run_adapter(
                bin_path, ["--phase=compute", f"--n={n}", "--k=1"], warmup, reps
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            unit_rows = _collect_phase_rows(text, gpu, warmup, reps, commit)
            if len(unit_rows) != 1:
                print(f"record_v3: expected 1 phase-compute k=1, got {len(unit_rows)}",
                      file=sys.stderr)
                return 4
            t_unit = float(unit_rows[0]["latency_us"])
            planned: dict[int, list[float]] = {}
            for r in PHASE_R:
                k = choose_phase_k(r, t_copy, t_unit)
                planned.setdefault(k, []).append(r)
            for k in sorted(planned):
                print(
                    f"=== phase slice n={n} k={k} r_target={planned[k]} ===",
                    file=sys.stderr,
                )
                text = _run_adapter(
                    bin_path,
                    ["--phase=slice", f"--n={n}", f"--k={k}"],
                    warmup,
                    reps,
                )
                print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
                got = _collect_phase_rows(text, gpu, warmup, reps, commit)
                if k == 1:
                    # k=1 compute was already measured as T_unit; slice
                    # still emits compute/seq/ovl. Keep all three.
                    pass
                if {r["case"] for r in got} != {
                    "phase-seq",
                    "phase-ovl",
                    "phase-compute",
                }:
                    print(
                        f"record_v3: expected phase slice arms, got "
                        f"{[r['case'] for r in got]}",
                        file=sys.stderr,
                    )
                    return 4
                rows.extend(got)
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"record_v3: phase run failed: {exc}", file=sys.stderr)
        return 2
    write_outputs(rows, out_prefix)
    print(
        f"record_v3 wrote {out_prefix.with_suffix('.jsonl')} "
        f"count={len(rows)} phase v3=not-claimed"
    )
    return 0


def _dominance(r: float) -> str:
    if r < 0.3:
        return "copy-dominated"
    if r > 3.0:
        return "compute-dominated"
    return "balanced"


def _phase_overlap(pmax: float, psum: float) -> str:
    hid = pmax <= 1.15
    near_sum = psum >= 0.90
    if hid and not near_sum:
        return "parallel"
    if near_sum and not hid:
        return "serial"
    if hid and near_sum:
        return "underdetermined"
    return "mixed"


def phase_slices(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    copies = {
        int(r["N"]): float(r["latency_us"])
        for r in rows
        if r["case"] == "phase-copy"
    }
    units = {
        int(r["N"]): float(r["latency_us"])
        for r in rows
        if r["case"] == "phase-compute" and int(r["k"]) == 1
    }
    by_nk: dict[tuple[int, int], dict[str, dict[str, Any]]] = {}
    for r in rows:
        if r["case"] not in ("phase-seq", "phase-ovl", "phase-compute"):
            continue
        key = (int(r["N"]), int(r["k"]))
        by_nk.setdefault(key, {})[r["case"]] = r
    for (n, k), by_case in sorted(by_nk.items()):
        if n not in copies:
            continue
        if not {"phase-seq", "phase-ovl", "phase-compute"}.issubset(by_case):
            continue
        copy = copies[n]
        compute = float(by_case["phase-compute"]["latency_us"])
        seq = float(by_case["phase-seq"]["latency_us"])
        ovl = float(by_case["phase-ovl"]["latency_us"])
        r_hat = _safe_div(compute, copy)
        planned = []
        if n in units:
            for rt in PHASE_R:
                if choose_phase_k(rt, copy, units[n]) == k:
                    planned.append(rt)
        nearest = planned[0] if planned else min(
            PHASE_R, key=lambda t: abs(t - r_hat)
        )
        pmax = _safe_div(ovl, max(copy, compute))
        psum = _safe_div(ovl, copy + compute)
        out.append(
            {
                "N": n,
                "k": k,
                "r_target": nearest,
                "r_achieved": r_hat,
                "T_seq_us": seq,
                "T_ovl_us": ovl,
                "T_copy_us": copy,
                "T_compute_us": compute,
                "ovl_over_max": pmax,
                "ovl_over_sum": psum,
                "hidden_frac": _safe_div(seq - ovl, min(copy, compute)),
                "dominance": _dominance(r_hat),
                "overlap": _phase_overlap(pmax, psum),
            }
        )
    return out


def analyze_phase(jsonl: Path, out: Path | None = None) -> int:
    rows = [
        json.loads(line)
        for line in jsonl.read_text(encoding="utf-8").splitlines()
        if line
    ]
    slices = phase_slices(rows)
    print("v3-phase v3=not-claimed cost=unchanged pair=C||HtoD")
    print(
        "slice\tN\tk\tr_target\tr\tcopy\tcompute\tseq\tovl\t"
        "ovl/max\tovl/sum\thidden\tdominance\toverlap"
    )
    for s in slices:
        print(
            f"slice\t{s['N']}\t{s['k']}\t{s['r_target']}\t"
            f"{s['r_achieved']:.3f}\t{s['T_copy_us']:.1f}\t"
            f"{s['T_compute_us']:.1f}\t{s['T_seq_us']:.1f}\t"
            f"{s['T_ovl_us']:.1f}\t{s['ovl_over_max']:.3f}\t"
            f"{s['ovl_over_sum']:.3f}\t{s['hidden_frac']:.3f}\t"
            f"{s['dominance']}\t{s['overlap']}"
        )
    if slices:
        by_dom: dict[str, int] = {}
        by_ovl: dict[str, int] = {}
        for s in slices:
            by_dom[s["dominance"]] = by_dom.get(s["dominance"], 0) + 1
            by_ovl[s["overlap"]] = by_ovl.get(s["overlap"], 0) + 1
        print(
            f"summary slices={len(slices)} "
            f"dominance={by_dom} overlap={by_ovl} "
            f"v3=not-claimed cost=unchanged"
        )
    if out:
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=PHASE_FIELDS)
            w.writeheader()
            for s in slices:
                w.writerow(
                    {
                        "N": s["N"],
                        "k": s["k"],
                        "r_target": s["r_target"],
                        "r_achieved": f"{s['r_achieved']:.3f}",
                        "T_seq_us": f"{s['T_seq_us']:.1f}",
                        "T_ovl_us": f"{s['T_ovl_us']:.1f}",
                        "T_copy_us": f"{s['T_copy_us']:.1f}",
                        "T_compute_us": f"{s['T_compute_us']:.1f}",
                        "ovl_over_max": f"{s['ovl_over_max']:.3f}",
                        "ovl_over_sum": f"{s['ovl_over_sum']:.3f}",
                        "hidden_frac": f"{s['hidden_frac']:.3f}",
                        "dominance": s["dominance"],
                        "overlap": s["overlap"],
                    }
                )
        print(f"record_v3 wrote {out} count={len(slices)} phase v3=not-claimed")
    return 0


def _collect_pipe_rows(
    text: str, gpu: dict[str, str], warmup: int, reps: int, commit: str
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line in text.splitlines():
        parsed = parse_pipe_line(line)
        if not parsed:
            continue
        rec = base_record(commit, gpu, warmup, reps)
        rec["case"] = parsed["case"]
        rec["N"] = parsed["N"]
        rec["k"] = parsed["k"]
        rec["provisioned"] = parsed["provisioned"]
        rec["score3"] = parsed["score3"]
        rec["latency_us"] = parsed["latency_us"]
        rows.append({key: rec[key] for key in FIELDS})
    return rows


def pipe_sweep(bin_path: str, out_prefix: Path, warmup: int, reps: int,
               commit: str) -> int:
    gpu = collect_gpu()
    gpu["cuda_runtime"] = cuda_runtime_from_bin(bin_path)
    rows: list[dict[str, Any]] = []
    try:
        for n in NS:
            if n % PIPE_TILES != 0:
                print(f"record_v3: N={n} not divisible by tiles", file=sys.stderr)
                return 4
            print(f"=== pipe calibrate n={n} tiles={PIPE_TILES} ===", file=sys.stderr)
            text = _run_adapter(
                bin_path,
                ["--pipe=copy", f"--n={n}", "--k=1", f"--tiles={PIPE_TILES}"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            copy_rows = _collect_pipe_rows(text, gpu, warmup, reps, commit)
            if len(copy_rows) != 1:
                print(f"record_v3: expected 1 pipe-copy, got {len(copy_rows)}",
                      file=sys.stderr)
                return 4
            rows.extend(copy_rows)
            text = _run_adapter(
                bin_path,
                ["--pipe=compute", f"--n={n}", "--k=1", f"--tiles={PIPE_TILES}"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            unit_rows = _collect_pipe_rows(text, gpu, warmup, reps, commit)
            if len(unit_rows) != 1:
                print(f"record_v3: expected 1 pipe-compute, got {len(unit_rows)}",
                      file=sys.stderr)
                return 4
            t_copy = float(copy_rows[0]["latency_us"])
            t_unit = float(unit_rows[0]["latency_us"])
            k = choose_phase_k(1.0, t_copy, t_unit)
            print(f"=== pipe depths n={n} k={k} ===", file=sys.stderr)
            text = _run_adapter(
                bin_path,
                ["--pipe=depths", f"--n={n}", f"--k={k}", f"--tiles={PIPE_TILES}"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            got = _collect_pipe_rows(text, gpu, warmup, reps, commit)
            if {r["case"] for r in got} != {
                "pipe-d1",
                "pipe-d2",
                "pipe-d3",
                "pipe-d4",
            }:
                print(f"record_v3: expected 4 depths, got {[r['case'] for r in got]}",
                      file=sys.stderr)
                return 4
            rows.extend(got)
            # Re-measure compute at chosen k so analysis has T_compute(k).
            text = _run_adapter(
                bin_path,
                ["--pipe=compute", f"--n={n}", f"--k={k}", f"--tiles={PIPE_TILES}"],
                warmup,
                reps,
            )
            print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
            kcomp = _collect_pipe_rows(text, gpu, warmup, reps, commit)
            if len(kcomp) != 1:
                print("record_v3: expected 1 pipe-compute at k", file=sys.stderr)
                return 4
            rows.extend(kcomp)
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"record_v3: pipe run failed: {exc}", file=sys.stderr)
        return 2
    write_outputs(rows, out_prefix)
    print(
        f"record_v3 wrote {out_prefix.with_suffix('.jsonl')} "
        f"count={len(rows)} pipe v3=not-claimed"
    )
    return 0


def pipe_slices(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for n in NS:
        slice_rows = [r for r in rows if int(r["N"]) == n]
        by_case: dict[str, list[dict[str, Any]]] = {}
        for r in slice_rows:
            by_case.setdefault(r["case"], []).append(r)
        if "pipe-copy" not in by_case or "pipe-d1" not in by_case:
            continue
        copy = float(by_case["pipe-copy"][0]["latency_us"])
        depths = {}
        k_used = int(by_case["pipe-d1"][0]["k"])
        for d in PIPE_DEPTHS:
            key = f"pipe-d{d}"
            if key not in by_case:
                depths = {}
                break
            depths[d] = float(by_case[key][0]["latency_us"])
        if len(depths) != 4:
            continue
        compute = None
        for r in by_case.get("pipe-compute", []):
            if int(r["k"]) == k_used:
                compute = float(r["latency_us"])
        if compute is None and by_case.get("pipe-compute"):
            compute = float(by_case["pipe-compute"][-1]["latency_us"])
        if compute is None:
            continue
        t1 = depths[1]
        out.append(
            {
                "N": n,
                "k": k_used,
                "tiles": PIPE_TILES,
                "r_tile": _safe_div(compute, copy),
                "T_copy_us": copy,
                "T_compute_us": compute,
                "T_d1_us": depths[1],
                "T_d2_us": depths[2],
                "T_d3_us": depths[3],
                "T_d4_us": depths[4],
                "speedup_d2": _safe_div(t1, depths[2]),
                "speedup_d3": _safe_div(t1, depths[3]),
                "speedup_d4": _safe_div(t1, depths[4]),
                "ideal": _safe_div(copy + compute, max(copy, compute)),
                "T_ideal_pipe_us": copy + compute + (PIPE_TILES - 1) * max(copy, compute),
                "sat_d4_over_d2": _safe_div(depths[4], depths[2]),
            }
        )
    return out


def analyze_pipe(jsonl: Path, out: Path | None = None) -> int:
    rows = [
        json.loads(line)
        for line in jsonl.read_text(encoding="utf-8").splitlines()
        if line
    ]
    slices = pipe_slices(rows)
    print("v3-pipe v3=not-claimed cost=unchanged pair=C||HtoD tiles=8")
    print(
        "slice\tN\tk\tr\tcopy\tcompute\td1\td2\td3\td4\t"
        "sp2\tsp3\tsp4\tideal\tTideal\tsat"
    )
    for s in slices:
        print(
            f"slice\t{s['N']}\t{s['k']}\t{s['r_tile']:.3f}\t"
            f"{s['T_copy_us']:.1f}\t{s['T_compute_us']:.1f}\t"
            f"{s['T_d1_us']:.1f}\t{s['T_d2_us']:.1f}\t"
            f"{s['T_d3_us']:.1f}\t{s['T_d4_us']:.1f}\t"
            f"{s['speedup_d2']:.3f}\t{s['speedup_d3']:.3f}\t"
            f"{s['speedup_d4']:.3f}\t{s['ideal']:.3f}\t"
            f"{s['T_ideal_pipe_us']:.1f}\t{s['sat_d4_over_d2']:.3f}"
        )
    if slices:
        sats = [float(s["sat_d4_over_d2"]) for s in slices]
        mean_sat = sum(sats) / len(sats)
        print(
            f"summary slices={len(slices)} mean_sat_d4/d2={mean_sat:.3f} "
            f"v3=not-claimed cost=unchanged"
        )
    if out:
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=PIPE_FIELDS)
            w.writeheader()
            for s in slices:
                w.writerow(
                    {
                        "N": s["N"],
                        "k": s["k"],
                        "tiles": s["tiles"],
                        "r_tile": f"{s['r_tile']:.3f}",
                        "T_copy_us": f"{s['T_copy_us']:.1f}",
                        "T_compute_us": f"{s['T_compute_us']:.1f}",
                        "T_d1_us": f"{s['T_d1_us']:.1f}",
                        "T_d2_us": f"{s['T_d2_us']:.1f}",
                        "T_d3_us": f"{s['T_d3_us']:.1f}",
                        "T_d4_us": f"{s['T_d4_us']:.1f}",
                        "speedup_d2": f"{s['speedup_d2']:.3f}",
                        "speedup_d3": f"{s['speedup_d3']:.3f}",
                        "speedup_d4": f"{s['speedup_d4']:.3f}",
                        "ideal": f"{s['ideal']:.3f}",
                        "T_ideal_pipe_us": f"{s['T_ideal_pipe_us']:.1f}",
                        "sat_d4_over_d2": f"{s['sat_d4_over_d2']:.3f}",
                    }
                )
        print(f"record_v3 wrote {out} count={len(slices)} pipe v3=not-claimed")
    return 0


def _retag_pipe_tiles(
    rows: list[dict[str, Any]], tiles: int
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for r in rows:
        rec = dict(r)
        raw = str(rec["case"])
        if not raw.startswith("pipe-"):
            print(f"record_v3: unexpected pipe case {raw}", file=sys.stderr)
            continue
        rec["case"] = f"pipe-t{tiles}-{raw[len('pipe-'):]}"
        out.append(rec)
    return out


def pipe_tiles_sweep(bin_path: str, out_prefix: Path, warmup: int, reps: int,
                     commit: str) -> int:
    gpu = collect_gpu()
    gpu["cuda_runtime"] = cuda_runtime_from_bin(bin_path)
    rows: list[dict[str, Any]] = []
    try:
        for n in NS:
            for tiles in PIPE_TILES_SET:
                if n % tiles != 0:
                    print(
                        f"record_v3: N={n} not divisible by tiles={tiles}",
                        file=sys.stderr,
                    )
                    return 4
                print(
                    f"=== pipe-tiles calibrate n={n} tiles={tiles} ===",
                    file=sys.stderr,
                )
                text = _run_adapter(
                    bin_path,
                    ["--pipe=copy", f"--n={n}", "--k=1", f"--tiles={tiles}"],
                    warmup,
                    reps,
                )
                print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
                copy_rows = _retag_pipe_tiles(
                    _collect_pipe_rows(text, gpu, warmup, reps, commit), tiles
                )
                if len(copy_rows) != 1:
                    print(
                        f"record_v3: expected 1 pipe-t{tiles}-copy, "
                        f"got {len(copy_rows)}",
                        file=sys.stderr,
                    )
                    return 4
                rows.extend(copy_rows)
                text = _run_adapter(
                    bin_path,
                    ["--pipe=compute", f"--n={n}", "--k=1", f"--tiles={tiles}"],
                    warmup,
                    reps,
                )
                print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
                unit_rows = _collect_pipe_rows(text, gpu, warmup, reps, commit)
                if len(unit_rows) != 1:
                    print(
                        f"record_v3: expected 1 pipe-compute unit, "
                        f"got {len(unit_rows)}",
                        file=sys.stderr,
                    )
                    return 4
                t_copy = float(copy_rows[0]["latency_us"])
                t_unit = float(unit_rows[0]["latency_us"])
                k = choose_phase_k(1.0, t_copy, t_unit)
                print(
                    f"=== pipe-tiles depths n={n} tiles={tiles} k={k} ===",
                    file=sys.stderr,
                )
                text = _run_adapter(
                    bin_path,
                    ["--pipe=depths", f"--n={n}", f"--k={k}", f"--tiles={tiles}"],
                    warmup,
                    reps,
                )
                print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
                got = _retag_pipe_tiles(
                    _collect_pipe_rows(text, gpu, warmup, reps, commit), tiles
                )
                expect = {f"pipe-t{tiles}-d{d}" for d in PIPE_DEPTHS}
                if {r["case"] for r in got} != expect:
                    print(
                        f"record_v3: expected 4 depths, got {[r['case'] for r in got]}",
                        file=sys.stderr,
                    )
                    return 4
                rows.extend(got)
                text = _run_adapter(
                    bin_path,
                    ["--pipe=compute", f"--n={n}", f"--k={k}", f"--tiles={tiles}"],
                    warmup,
                    reps,
                )
                print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
                kcomp = _retag_pipe_tiles(
                    _collect_pipe_rows(text, gpu, warmup, reps, commit), tiles
                )
                if len(kcomp) != 1:
                    print(
                        "record_v3: expected 1 pipe-compute at k",
                        file=sys.stderr,
                    )
                    return 4
                rows.extend(kcomp)
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"record_v3: pipe-tiles run failed: {exc}", file=sys.stderr)
        return 2
    write_outputs(rows, out_prefix)
    print(
        f"record_v3 wrote {out_prefix.with_suffix('.jsonl')} "
        f"count={len(rows)} pipe-tiles v3=not-claimed"
    )
    return 0


def _tiles_arm(case: str) -> tuple[int, str] | None:
    m = PIPE_TILES_CASE_RE.match(case)
    if not m:
        return None
    return int(m.group(1)), m.group(2)


def pipe_tiles_slices(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    groups: dict[tuple[int, int], dict[str, list[dict[str, Any]]]] = {}
    for r in rows:
        parsed = _tiles_arm(str(r["case"]))
        if not parsed:
            continue
        tiles, arm = parsed
        groups.setdefault((int(r["N"]), tiles), {}).setdefault(arm, []).append(r)
    out: list[dict[str, Any]] = []
    for n in NS:
        for tiles in PIPE_TILES_SET:
            by_arm = groups.get((n, tiles), {})
            if "copy" not in by_arm or "d1" not in by_arm:
                continue
            copy = float(by_arm["copy"][0]["latency_us"])
            depths: dict[int, float] = {}
            k_used = int(by_arm["d1"][0]["k"])
            for d in PIPE_DEPTHS:
                key = f"d{d}"
                if key not in by_arm:
                    depths = {}
                    break
                depths[d] = float(by_arm[key][0]["latency_us"])
            if len(depths) != 4:
                continue
            compute = None
            for r in by_arm.get("compute", []):
                if int(r["k"]) == k_used:
                    compute = float(r["latency_us"])
            if compute is None and by_arm.get("compute"):
                compute = float(by_arm["compute"][-1]["latency_us"])
            if compute is None:
                continue
            t1 = depths[1]
            out.append(
                {
                    "N": n,
                    "k": k_used,
                    "tiles": tiles,
                    "r_tile": _safe_div(compute, copy),
                    "T_copy_us": copy,
                    "T_compute_us": compute,
                    "T_d1_us": depths[1],
                    "T_d2_us": depths[2],
                    "T_d3_us": depths[3],
                    "T_d4_us": depths[4],
                    "speedup_d2": _safe_div(t1, depths[2]),
                    "speedup_d3": _safe_div(t1, depths[3]),
                    "speedup_d4": _safe_div(t1, depths[4]),
                    "ideal": _safe_div(copy + compute, max(copy, compute)),
                    "T_ideal_pipe_us": copy + compute + (tiles - 1) * max(copy, compute),
                    "sat_d4_over_d2": _safe_div(depths[4], depths[2]),
                }
            )
    return out


def analyze_pipe_tiles(jsonl: Path, out: Path | None = None) -> int:
    rows = [
        json.loads(line)
        for line in jsonl.read_text(encoding="utf-8").splitlines()
        if line
    ]
    slices = pipe_tiles_slices(rows)
    print("v3-pipe-tiles v3=not-claimed cost=unchanged pair=C||HtoD tiles=4,8,16,32")
    print(
        "slice\tN\ttiles\tk\tr\tcopy\tcompute\td1\td2\td3\td4\t"
        "sp2\tsp3\tsp4\tideal\tTideal\tsat"
    )
    for s in slices:
        print(
            f"slice\t{s['N']}\t{s['tiles']}\t{s['k']}\t{s['r_tile']:.3f}\t"
            f"{s['T_copy_us']:.1f}\t{s['T_compute_us']:.1f}\t"
            f"{s['T_d1_us']:.1f}\t{s['T_d2_us']:.1f}\t"
            f"{s['T_d3_us']:.1f}\t{s['T_d4_us']:.1f}\t"
            f"{s['speedup_d2']:.3f}\t{s['speedup_d3']:.3f}\t"
            f"{s['speedup_d4']:.3f}\t{s['ideal']:.3f}\t"
            f"{s['T_ideal_pipe_us']:.1f}\t{s['sat_d4_over_d2']:.3f}"
        )
    if slices:
        sats = [float(s["sat_d4_over_d2"]) for s in slices]
        mean_sat = sum(sats) / len(sats)
        print(
            f"summary slices={len(slices)} mean_sat_d4/d2={mean_sat:.3f} "
            f"v3=not-claimed cost=unchanged"
        )
        for tiles in PIPE_TILES_SET:
            group = [s for s in slices if int(s["tiles"]) == tiles]
            if not group:
                continue
            gsat = sum(float(s["sat_d4_over_d2"]) for s in group) / len(group)
            gsp = sum(float(s["speedup_d2"]) for s in group) / len(group)
            gideal = sum(float(s["ideal"]) for s in group) / len(group)
            print(
                f"by-tiles tiles={tiles} n={len(group)} "
                f"mean_sp2={gsp:.3f} mean_ideal={gideal:.3f} "
                f"mean_sat={gsat:.3f}"
            )
    if out:
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=PIPE_FIELDS)
            w.writeheader()
            for s in slices:
                w.writerow(
                    {
                        "N": s["N"],
                        "k": s["k"],
                        "tiles": s["tiles"],
                        "r_tile": f"{s['r_tile']:.3f}",
                        "T_copy_us": f"{s['T_copy_us']:.1f}",
                        "T_compute_us": f"{s['T_compute_us']:.1f}",
                        "T_d1_us": f"{s['T_d1_us']:.1f}",
                        "T_d2_us": f"{s['T_d2_us']:.1f}",
                        "T_d3_us": f"{s['T_d3_us']:.1f}",
                        "T_d4_us": f"{s['T_d4_us']:.1f}",
                        "speedup_d2": f"{s['speedup_d2']:.3f}",
                        "speedup_d3": f"{s['speedup_d3']:.3f}",
                        "speedup_d4": f"{s['speedup_d4']:.3f}",
                        "ideal": f"{s['ideal']:.3f}",
                        "T_ideal_pipe_us": f"{s['T_ideal_pipe_us']:.1f}",
                        "sat_d4_over_d2": f"{s['sat_d4_over_d2']:.3f}",
                    }
                )
        print(f"record_v3 wrote {out} count={len(slices)} pipe-tiles v3=not-claimed")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="V3 metadata recorder")
    p.add_argument("--print-schema", action="store_true")
    p.add_argument("--print-matched-schema", action="store_true")
    p.add_argument("--print-calibration-schema", action="store_true")
    p.add_argument("--print-ratio-schema", action="store_true")
    p.add_argument("--print-cap-schema", action="store_true")
    p.add_argument("--print-phase-schema", action="store_true")
    p.add_argument("--print-pipe-schema", action="store_true")
    p.add_argument("--print-pipe-tiles-schema", action="store_true")
    p.add_argument("--print-cuda-val-schema", action="store_true")
    p.add_argument("--print-cuda-val-mem-schema", action="store_true")
    p.add_argument("--print-cuda-val-cc-schema", action="store_true")
    p.add_argument("--print-cuda-val-async-schema", action="store_true")
    p.add_argument("--cuda-val-sweep", metavar="BIN")
    p.add_argument("--cuda-val-mem-sweep", metavar="BIN")
    p.add_argument("--cuda-val-cc-sweep", metavar="BIN")
    p.add_argument("--cuda-val-async-sweep", metavar="BIN")
    p.add_argument("--format", choices=("jsonl", "csv"), default="jsonl")
    p.add_argument("--sweep", metavar="BIN")
    p.add_argument("--matched-sweep", metavar="BIN")
    p.add_argument("--cap-sweep", metavar="BIN")
    p.add_argument("--phase-sweep", metavar="BIN")
    p.add_argument("--pipe-sweep", metavar="BIN")
    p.add_argument("--pipe-tiles-sweep", metavar="BIN")
    p.add_argument("--out", type=Path)
    p.add_argument("--analyze", type=Path)
    p.add_argument("--analyze-matched", type=Path)
    p.add_argument("--analyze-cap", type=Path)
    p.add_argument("--analyze-phase", type=Path)
    p.add_argument("--analyze-pipe", type=Path)
    p.add_argument("--analyze-pipe-tiles", type=Path)
    p.add_argument("--analyze-cuda-val", type=Path)
    p.add_argument("--analyze-cuda-val-mem", type=Path)
    p.add_argument("--analyze-cuda-val-cc", type=Path)
    p.add_argument("--analyze-cuda-val-async", type=Path)
    p.add_argument("--calibrate", type=Path)
    p.add_argument("--analyze-ratio", type=Path)
    p.add_argument("--warmup", type=int, default=5)
    p.add_argument("--reps", type=int, default=21)
    p.add_argument("--git-commit")
    args = p.parse_args()
    if args.print_schema:
        return print_schema(args.format)
    if args.print_matched_schema:
        return print_matched_schema()
    if args.print_calibration_schema:
        return print_calibration_schema()
    if args.print_ratio_schema:
        return print_ratio_schema()
    if args.print_cap_schema:
        return print_cap_schema()
    if args.print_phase_schema:
        return print_phase_schema()
    if args.print_pipe_schema:
        return print_pipe_schema()
    if args.print_pipe_tiles_schema:
        return print_pipe_tiles_schema()
    if args.print_cuda_val_schema:
        return print_cuda_val_schema()
    if args.print_cuda_val_mem_schema:
        return print_cuda_val_mem_schema()
    if args.print_cuda_val_cc_schema:
        return print_cuda_val_cc_schema()
    if args.print_cuda_val_async_schema:
        return print_cuda_val_async_schema()
    if args.analyze:
        return analyze(args.analyze)
    if args.analyze_matched:
        return analyze_matched(args.analyze_matched)
    if args.calibrate:
        return calibrate(args.calibrate, args.out)
    if args.analyze_ratio:
        return analyze_ratio(args.analyze_ratio)
    if args.analyze_cap:
        return analyze_cap(args.analyze_cap)
    if args.analyze_phase:
        return analyze_phase(args.analyze_phase, args.out)
    if args.analyze_pipe:
        return analyze_pipe(args.analyze_pipe, args.out)
    if args.analyze_pipe_tiles:
        return analyze_pipe_tiles(args.analyze_pipe_tiles, args.out)
    if args.analyze_cuda_val:
        return analyze_cuda_val(args.analyze_cuda_val, args.out)
    if args.analyze_cuda_val_mem:
        return analyze_cuda_val_mem(args.analyze_cuda_val_mem, args.out)
    if args.analyze_cuda_val_cc:
        return analyze_cuda_val_cc(args.analyze_cuda_val_cc, args.out)
    if args.analyze_cuda_val_async:
        return analyze_cuda_val_async(args.analyze_cuda_val_async, args.out)
    if args.sweep:
        if not args.out:
            print("record_v3: --out required with --sweep", file=sys.stderr)
            return 1
        return sweep(args.sweep, args.out, args.warmup, args.reps, git_commit(args.git_commit))
    if args.matched_sweep:
        if not args.out:
            print("record_v3: --out required with --matched-sweep", file=sys.stderr)
            return 1
        return matched_sweep(
            args.matched_sweep, args.out, args.warmup, args.reps,
            git_commit(args.git_commit)
        )
    if args.cap_sweep:
        if not args.out:
            print("record_v3: --out required with --cap-sweep", file=sys.stderr)
            return 1
        return cap_sweep(
            args.cap_sweep, args.out, args.warmup, args.reps,
            git_commit(args.git_commit)
        )
    if args.phase_sweep:
        if not args.out:
            print("record_v3: --out required with --phase-sweep", file=sys.stderr)
            return 1
        return phase_sweep(
            args.phase_sweep, args.out, args.warmup, args.reps,
            git_commit(args.git_commit)
        )
    if args.pipe_sweep:
        if not args.out:
            print("record_v3: --out required with --pipe-sweep", file=sys.stderr)
            return 1
        return pipe_sweep(
            args.pipe_sweep, args.out, args.warmup, args.reps,
            git_commit(args.git_commit)
        )
    if args.pipe_tiles_sweep:
        if not args.out:
            print("record_v3: --out required with --pipe-tiles-sweep", file=sys.stderr)
            return 1
        return pipe_tiles_sweep(
            args.pipe_tiles_sweep, args.out, args.warmup, args.reps,
            git_commit(args.git_commit)
        )
    if args.cuda_val_sweep:
        if not args.out:
            print("record_v3: --out required with --cuda-val-sweep", file=sys.stderr)
            return 1
        return cuda_val_sweep(
            args.cuda_val_sweep, args.out, args.warmup, args.reps,
            git_commit(args.git_commit)
        )
    if args.cuda_val_mem_sweep:
        if not args.out:
            print("record_v3: --out required with --cuda-val-mem-sweep",
                  file=sys.stderr)
            return 1
        return cuda_val_mem_sweep(
            args.cuda_val_mem_sweep, args.out, args.warmup, args.reps,
            git_commit(args.git_commit)
        )
    if args.cuda_val_cc_sweep:
        if not args.out:
            print("record_v3: --out required with --cuda-val-cc-sweep",
                  file=sys.stderr)
            return 1
        return cuda_val_cc_sweep(
            args.cuda_val_cc_sweep, args.out, args.warmup, args.reps,
            git_commit(args.git_commit)
        )
    if args.cuda_val_async_sweep:
        if not args.out:
            print("record_v3: --out required with --cuda-val-async-sweep",
                  file=sys.stderr)
            return 1
        return cuda_val_async_sweep(
            args.cuda_val_async_sweep, args.out, args.warmup, args.reps,
            git_commit(args.git_commit)
        )
    print("record_v3: use --print-schema, --print-matched-schema, "
          "--print-calibration-schema, --print-ratio-schema, "
          "--print-cap-schema, --print-phase-schema, --print-pipe-schema, "
          "--print-pipe-tiles-schema, --print-cuda-val-schema, "
          "--print-cuda-val-mem-schema, --print-cuda-val-cc-schema, --print-cuda-val-async-schema, --sweep, "
          "--matched-sweep, --cap-sweep, --phase-sweep, --pipe-sweep, "
          "--pipe-tiles-sweep, --cuda-val-sweep, --cuda-val-mem-sweep, "
          "--cuda-val-cc-sweep, --cuda-val-async-sweep, --analyze, "
          "--analyze-matched, --analyze-cap, --analyze-phase, --analyze-pipe, "
          "--analyze-pipe-tiles, --analyze-cuda-val, --analyze-cuda-val-mem, "
          "--analyze-cuda-val-cc, --analyze-cuda-val-async, --calibrate, "
          "or --analyze-ratio",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
