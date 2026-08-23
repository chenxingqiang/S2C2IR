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


def collect_gpu() -> dict[str, str]:
    q = (
        "name,memory.total,driver_version,clocks.current.sm,"
        "clocks.current.memory,pstate,power.limit,cuda_version"
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
        # Older drivers may reject cuda_version.
        q2 = (
            "name,memory.total,driver_version,clocks.current.sm,"
            "clocks.current.memory,pstate,power.limit"
        )
        raw = run_cmd(
            [
                "nvidia-smi",
                f"--query-gpu={q2}",
                "--format=csv,noheader,nounits",
            ]
        )
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
    parts = [p.strip() for p in raw.split(",")]
    if len(parts) >= 8:
        meta.update(
            {
                "gpu_model": parts[0],
                "gpu_memory": parts[1],
                "driver_version": parts[2],
                "clock_state": f"pstate={parts[5]} sm={parts[3]} mem={parts[4]}",
                "power_mode": f"limit_w={parts[6]}",
                "cuda_runtime": parts[7],
            }
        )
    return meta


def print_schema(fmt: str) -> int:
    if fmt == "csv":
        print(",".join(FIELDS))
    else:
        for name in FIELDS:
            print(name)
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
    p.add_argument("--format", choices=("jsonl", "csv"), default="jsonl")
    p.add_argument("--sweep", metavar="BIN")
    p.add_argument("--out", type=Path)
    p.add_argument("--analyze", type=Path)
    p.add_argument("--warmup", type=int, default=5)
    p.add_argument("--reps", type=int, default=21)
    p.add_argument("--git-commit")
    args = p.parse_args()
    if args.print_schema:
        return print_schema(args.format)
    if args.analyze:
        return analyze(args.analyze)
    if args.sweep:
        if not args.out:
            print("record_v3: --out required with --sweep", file=sys.stderr)
            return 1
        return sweep(args.sweep, args.out, args.warmup, args.reps, git_commit(args.git_commit))
    print("record_v3: use --print-schema, --sweep, or --analyze", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
