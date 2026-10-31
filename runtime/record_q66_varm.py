#!/usr/bin/env python3
"""Require the CUDA validation arm names to stay the eight VAL_ARMS.

Loads runtime/cuda/record_v3.py by file path from Path(__file__).
VAL_ARMS must equal the named and default copy, compute, seq, and
ovl arms in that order. Does not call run_analyzer. Does not edit
runtime/cuda/record_v3.py. Does not add a predicate, device, dialect,
backend, or semantic cut. Query only. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RUNTIME = Path(__file__).resolve().parent
_CUDA = _RUNTIME / "cuda" / "record_v3.py"
_VAL_ARMS = (
    "val-copy-named",
    "val-compute-named",
    "val-seq-named",
    "val-ovl-named",
    "val-copy-default",
    "val-compute-default",
    "val-seq-default",
    "val-ovl-default",
)
_FLAG = "--print-q66-varm"


def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q66-varm no")
    return 1


def print_q66_varm() -> int:
    try:
        cuda = _load(_CUDA, "s2c2_cuda_q66_varm")
        arms = cuda.VAL_ARMS
    except (Exception, SystemExit):
        return _no()
    if type(arms) is not tuple or arms != _VAL_ARMS:
        return _no()
    print("q66-varm gate=query")
    for arm in arms:
        print(f"val-arm {arm}")
    print("q66-varm yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q66_varm: choose --print-q66-varm",
            file=sys.stderr,
        )
        return 2
    return print_q66_varm()


if __name__ == "__main__":
    sys.exit(main())
