#!/usr/bin/env python3
"""Require MATCHED_KS and MATCHED_ARMS from the CUDA recorder.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
Query only. Does not call run_analyzer. Does not add a predicate,
device, dialect, backend, or semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_MATCHED_KS = (1, 8, 32, 64)
_MATCHED_ARMS = (
    "matched-seq",
    "matched-ovl",
    "matched-copy",
    "matched-compute",
)
_FLAG = "--print-q58-matchd"


def _load(path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_q58_matchd", path
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q58-matchd no")
    return 1


def print_q58_matchd() -> int:
    try:
        mod = _load(_RECORD)
        ks = mod.MATCHED_KS
        arms = mod.MATCHED_ARMS
    except (Exception, SystemExit):
        return _no()
    if ks != _MATCHED_KS or arms != _MATCHED_ARMS:
        return _no()
    print("q58-matchd gate=query")
    for k in ks:
        print(f"matched-k {k}")
    for arm in arms:
        print(f"matched-arm {arm}")
    print("q58-matchd yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q58_matchd: choose --print-q58-matchd",
            file=sys.stderr,
        )
        return 2
    return print_q58_matchd()


if __name__ == "__main__":
    sys.exit(main())
