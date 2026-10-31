#!/usr/bin/env python3
"""Require CUDA VAL_MEM_FIELDS to stay the twelve memory-validation fields.

Loads runtime/cuda/record_v3.py with importlib from this file's path.
The tuple stays N, k, pair, residency, r, T_copy_us, T_compute_us,
T_ovl_us, ovl_over_max, ovl_over_sum, verdict, extra_hb.
Does not call run_analyzer. Does not add a predicate, device, dialect,
backend, or semantic cut. Query only. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_VAL_MEM_FIELDS = (
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
_FLAG = "--print-q70-vmfld"


def _load_record_v3() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_q70_vmfld", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def print_q70_vmfld() -> int:
    try:
        fields = _load_record_v3().VAL_MEM_FIELDS
    except (Exception, SystemExit):
        print("q70-vmfld no")
        return 1
    if type(fields) is not tuple or fields != _VAL_MEM_FIELDS:
        print("q70-vmfld no")
        return 1
    print("q70-vmfld gate=query")
    for name in fields:
        print(f"mem-field {name}")
    print("q70-vmfld yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q70_vmfld: choose --print-q70-vmfld",
            file=sys.stderr,
        )
        return 2
    return print_q70_vmfld()


if __name__ == "__main__":
    sys.exit(main())
