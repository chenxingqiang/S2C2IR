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
CONTEND_ARMS = ("contend-one", "contend-seq", "contend-par", "contend-par-split")
CONTEND_FUNCS = set(CONTEND_ARMS)
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


def parse_contend_line(line: str) -> dict[str, Any] | None:
    m = LINE_RE.search(line)
    if not m:
        return None
    func = m.group("func")
    if func not in CONTEND_FUNCS:
        return None
    return {
        "case": func,
        "N": int(m.group("n")),
        "k": 1,
        "provisioned": 1,
        "score3": "",
        "latency_us": float(m.group("us")),
    }


def print_contend_schema() -> int:
    print("contend-arm one seq par par-split")
    print("remaining-work 2xHtoD")
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


def contend_sweep(bin_path: str, out_prefix: Path, warmup: int, reps: int,
                  commit: str) -> int:
    gpu = collect_gpu()
    gpu["cuda_runtime"] = cuda_runtime_from_bin(bin_path)
    rows: list[dict[str, Any]] = []
    for n in NS:
        args = [
            bin_path,
            "--contend=all",
            "--device=gpu",
            f"--n={n}",
            f"--warmup={warmup}",
            f"--reps={reps}",
        ]
        print(f"=== contend n={n} ===", file=sys.stderr)
        try:
            proc = subprocess.run(
                args, check=True, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT
            )
            text = proc.stdout
        except (OSError, subprocess.CalledProcessError) as exc:
            print(f"record_v3: contend run failed: {exc}", file=sys.stderr)
            return 2
        print(text, end="" if text.endswith("\n") else "\n", file=sys.stderr)
        found = 0
        for line in text.splitlines():
            parsed = parse_contend_line(line)
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
            print(f"record_v3: expected 4 contend arms, got {found}",
                  file=sys.stderr)
            return 4
    if len(rows) != 12:
        print(f"record_v3: expected 12 contend rows, got {len(rows)}",
              file=sys.stderr)
        return 5
    write_outputs(rows, out_prefix)
    print(f"record_v3 wrote {out_prefix.with_suffix('.jsonl')} "
          f"count=12 contend v3=not-claimed")
    return 0


def analyze_contend(jsonl: Path) -> int:
    rows = [json.loads(line) for line in jsonl.read_text(encoding="utf-8").splitlines() if line]
    print("v3-contend v3=not-claimed cost=unchanged")
    print("slice\tN\tone\tseq\tpar\tpar_split\tseq_over_2one\tpar_over_seq\t"
          "par_over_one\tserialize\tsplit_over_one")
    serials = []
    for n in NS:
        slice_rows = [r for r in rows if r["N"] == n]
        by_case = {r["case"]: r for r in slice_rows}
        if not CONTEND_FUNCS.issubset(by_case):
            if not slice_rows:
                continue
            print(f"record_v3: incomplete contend slice N={n}", file=sys.stderr)
            return 6
        one = float(by_case["contend-one"]["latency_us"])
        seq = float(by_case["contend-seq"]["latency_us"])
        par = float(by_case["contend-par"]["latency_us"])
        split = float(by_case["contend-par-split"]["latency_us"])
        serialize = _safe_div(par - one, one)
        serials.append(serialize)
        print(
            f"slice\t{n}\t{one:.1f}\t{seq:.1f}\t{par:.1f}\t{split:.1f}\t"
            f"{_safe_div(seq, 2 * one):.3f}\t{_safe_div(par, seq):.3f}\t"
            f"{_safe_div(par, one):.3f}\t{serialize:.3f}\t"
            f"{_safe_div(split, one):.3f}"
        )
    if serials:
        finite = [s for s in serials if s == s]
        mean = sum(finite) / len(finite) if finite else float("nan")
        print(f"summary slices={len(serials)} mean_serialize_frac={mean:.3f} "
              f"v3=not-claimed")
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


def main() -> int:
    p = argparse.ArgumentParser(description="V3 metadata recorder")
    p.add_argument("--print-schema", action="store_true")
    p.add_argument("--print-matched-schema", action="store_true")
    p.add_argument("--print-calibration-schema", action="store_true")
    p.add_argument("--print-ratio-schema", action="store_true")
    p.add_argument("--print-contend-schema", action="store_true")
    p.add_argument("--format", choices=("jsonl", "csv"), default="jsonl")
    p.add_argument("--sweep", metavar="BIN")
    p.add_argument("--matched-sweep", metavar="BIN")
    p.add_argument("--contend-sweep", metavar="BIN")
    p.add_argument("--out", type=Path)
    p.add_argument("--analyze", type=Path)
    p.add_argument("--analyze-matched", type=Path)
    p.add_argument("--calibrate", type=Path)
    p.add_argument("--analyze-ratio", type=Path)
    p.add_argument("--analyze-contend", type=Path)
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
    if args.print_contend_schema:
        return print_contend_schema()
    if args.analyze:
        return analyze(args.analyze)
    if args.analyze_matched:
        return analyze_matched(args.analyze_matched)
    if args.calibrate:
        return calibrate(args.calibrate, args.out)
    if args.analyze_ratio:
        return analyze_ratio(args.analyze_ratio)
    if args.analyze_contend:
        return analyze_contend(args.analyze_contend)
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
    if args.contend_sweep:
        if not args.out:
            print("record_v3: --out required with --contend-sweep", file=sys.stderr)
            return 1
        return contend_sweep(
            args.contend_sweep, args.out, args.warmup, args.reps,
            git_commit(args.git_commit)
        )
    print("record_v3: use --print-schema, --print-matched-schema, "
          "--print-calibration-schema, --print-ratio-schema, "
          "--print-contend-schema, --sweep, --matched-sweep, --contend-sweep, "
          "--analyze, --analyze-matched, --analyze-contend, "
          "--calibrate, or --analyze-ratio",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
