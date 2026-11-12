#!/usr/bin/env python3
"""Require CUDA VAL_CC_FIELDS to stay the seventeen copy-contention fields.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
The tuple stays N, k, dim, r, T_silu_us, T_matmul_us, T_seq_us,
T_ovl_us, T_silu_silu_us, ovl_over_max, ovl_over_sum, mixed_verdict,
ss_over_max, ss_over_sum, same_verdict, pair_relation, observed_constraint.
Does not call run_analyzer. Does not add a predicate, device, dialect,
backend, or semantic cut. Query only. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_VAL_CC_FIELDS = (
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
_FLAG = "--print-q72-vccf"


def _load_record_v3() -> ModuleType:
    """Load runtime/cuda/record_v3.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_q72_vccf", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def print_q72_vccf() -> int:
    try:
        fields = _load_record_v3().VAL_CC_FIELDS
    except (Exception, SystemExit):
        print("q72-vccf no")
        return 1
    if type(fields) is not tuple or fields != _VAL_CC_FIELDS:
        print("q72-vccf no")
        return 1
    print("q72-vccf gate=query")
    for name in fields:
        print(f"cc-field {name}")
    print("q72-vccf yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q72_vccf: choose --print-q72-vccf",
            file=sys.stderr,
        )
        return 2
    return print_q72_vccf()


if __name__ == "__main__":
    sys.exit(main())
