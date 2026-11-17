#!/usr/bin/env python3
"""Require the CUDA val memory arms to stay the nine VAL_MEM_ARMS.

Loads runtime/cuda/record_v3.py by file path from Path(__file__).
VAL_MEM_ARMS must equal the pinned and pageable HtoD, DtoH, compute,
and overlap arms in that order. Does not call run_analyzer. Does not
edit runtime/cuda/record_v3.py. Does not add a predicate, device,
dialect, backend, or semantic cut. Query only. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RUNTIME = Path(__file__).resolve().parent
_CUDA = _RUNTIME / "cuda" / "record_v3.py"
_VAL_MEM_ARMS = (
    "val-htod-pinned",
    "val-htod-pageable",
    "val-dtoh-pinned",
    "val-dtoh-pageable",
    "val-compute-mem",
    "val-ovl-htod-pin",
    "val-ovl-htod-page",
    "val-ovl-dtoh-pin",
    "val-ovl-dtoh-page",
)
_FLAG = "--print-q68-vmarm"


def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q68-vmarm no")
    return 1


def print_q68_vmarm() -> int:
    try:
        cuda = _load(_CUDA, "s2c2_cuda_q68_vmarm")
        arms = cuda.VAL_MEM_ARMS
    except (Exception, SystemExit):
        return _no()
    if type(arms) is not tuple or arms != _VAL_MEM_ARMS:
        return _no()
    print("q68-vmarm gate=query")
    for arm in arms:
        print(f"mem-arm {arm}")
    print("q68-vmarm yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q68_vmarm: choose --print-q68-vmarm",
            file=sys.stderr,
        )
        return 2
    return print_q68_vmarm()


if __name__ == "__main__":
    sys.exit(main())
