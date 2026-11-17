#!/usr/bin/env python3
"""Require CUDA record_v3 PHASE_FIELDS to stay the host tuple.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
Query only. Does not edit record_v3. Does not add a predicate,
device, dialect, backend, or semantic cut. Does not call
run_analyzer. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_FLAG = "--print-q76-phf"
_PHASE_FIELDS = (
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


def load_record_v3():
    """Load runtime/cuda/record_v3.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_q76_phf", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def print_q76_phf() -> int:
    try:
        module = load_record_v3()
        fields = module.PHASE_FIELDS
    except (Exception, SystemExit):
        print("q76-phf no")
        return 1
    if fields != _PHASE_FIELDS:
        print("q76-phf no")
        return 1
    print("q76-phf gate=query")
    for name in fields:
        print(f"phase-field {name}")
    print("q76-phf yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q76_phf: choose --print-q76-phf",
            file=sys.stderr,
        )
        return 2
    return print_q76_phf()


if __name__ == "__main__":
    sys.exit(main())
