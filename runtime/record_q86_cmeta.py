#!/usr/bin/env python3
"""Require runtime/cuda/record_v3.FIELDS to stay the metadata field list.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
FIELDS is a list. tuple(FIELDS) stays git_commit, timestamp, gpu_model,
gpu_memory, driver_version, cuda_runtime, nvcc_version, clock_state,
power_mode, case, N, k, provisioned, warmup, reps, statistic,
latency_us, score3.
Does not call run_analyzer. Does not add a predicate, device, dialect,
backend, or semantic cut. Query only. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_FIELDS = (
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
)
_FLAG = "--print-q86-cmeta"


def load_record_v3() -> ModuleType:
    """Load runtime/cuda/record_v3.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_cmeta", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def print_q86_cmeta() -> int:
    try:
        fields = load_record_v3().FIELDS
        ok = type(fields) is list and tuple(fields) == _FIELDS
    except (Exception, SystemExit):
        print("q86-cmeta no")
        return 1
    if not ok:
        print("q86-cmeta no")
        return 1
    print("q86-cmeta gate=query")
    for name in fields:
        print(f"meta-field {name}")
    print("q86-cmeta yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q86_cmeta: choose --print-q86-cmeta",
            file=sys.stderr,
        )
        return 2
    return print_q86_cmeta()


if __name__ == "__main__":
    sys.exit(main())
