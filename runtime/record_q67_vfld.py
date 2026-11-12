#!/usr/bin/env python3
"""Require CUDA VAL_FIELDS to stay the validation field names.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
The tuple stays N, k, stream, r, T_copy_us, T_compute_us, T_seq_us,
T_ovl_us, ovl_over_max, ovl_over_sum, verdict, extra_hb.
Query only. Does not add a predicate, device, dialect, backend,
or semantic cut. Does not call run_analyzer. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RUNTIME = Path(__file__).resolve().parent
_RECORD = _RUNTIME / "cuda" / "record_v3.py"
_VAL_FIELDS = (
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
_FLAG = "--print-q67-vfld"


def _load_record_v3() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_q67_vfld", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q67-vfld no")
    return 1


def print_q67_vfld() -> int:
    try:
        module = _load_record_v3()
        fields = module.VAL_FIELDS
    except (Exception, SystemExit):
        return _no()
    if type(fields) is not tuple or fields != _VAL_FIELDS:
        return _no()
    print("q67-vfld gate=query")
    for name in fields:
        print(f"val-field {name}")
    print("q67-vfld yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q67_vfld: choose --print-q67-vfld",
            file=sys.stderr,
        )
        return 2
    return print_q67_vfld()


if __name__ == "__main__":
    sys.exit(main())
