#!/usr/bin/env python3
"""Require CUDA PIPE_FIELDS to stay the sixteen pipe field names.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
The tuple stays N, k, tiles, r_tile, T_copy_us, T_compute_us,
T_d1_us, T_d2_us, T_d3_us, T_d4_us, speedup_d2, speedup_d3,
speedup_d4, ideal, T_ideal_pipe_us, sat_d4_over_d2.
Does not call run_analyzer. Does not add a predicate, device, dialect,
backend, or semantic cut. Query only. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_PIPE_FIELDS = (
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
_FLAG = "--print-q75-pfl"


def _load(path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_q75_pfl", path
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q75-pfl no")
    return 1


def print_q75_pfl() -> int:
    try:
        fields = _load(_RECORD).PIPE_FIELDS
    except (Exception, SystemExit):
        return _no()
    if type(fields) is not tuple or fields != _PIPE_FIELDS:
        return _no()
    print("q75-pfl gate=query")
    for name in fields:
        print(f"pipe-field {name}")
    print("q75-pfl yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q75_pfl: choose --print-q75-pfl",
            file=sys.stderr,
        )
        return 2
    return print_q75_pfl()


if __name__ == "__main__":
    sys.exit(main())
