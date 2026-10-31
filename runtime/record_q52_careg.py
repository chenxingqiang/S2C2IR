#!/usr/bin/env python3
"""Require CUDA and Ascend capability regimes to stay the same tuple.

Loads runtime/cuda/record_v3.py and runtime/ascend/record_ascend.py
by file path. Both CAP_SCHEMA_REGIME tuples must be
("bandwidth", "latency", "occupancy", "underdetermined") in that
order. Query only. Does not edit either recorder. No semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RUNTIME = Path(__file__).resolve().parent
_CUDA = _RUNTIME / "cuda" / "record_v3.py"
_ASCEND = _RUNTIME / "ascend" / "record_ascend.py"
_REGIME = ("bandwidth", "latency", "occupancy", "underdetermined")


def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q52-careg no")
    return 1


def print_q52_careg() -> int:
    try:
        cuda = _load(_CUDA, "s2c2_q52_cuda_cap_regime")
        ascend = _load(_ASCEND, "s2c2_q52_ascend_cap_regime")
        cuda_regime = cuda.CAP_SCHEMA_REGIME
        ascend_regime = ascend.CAP_SCHEMA_REGIME
    except (Exception, SystemExit):
        return _no()
    if type(cuda_regime) is not tuple or type(ascend_regime) is not tuple:
        return _no()
    if cuda_regime != ascend_regime or cuda_regime != _REGIME:
        return _no()
    print("q52-careg gate=query")
    for regime in cuda_regime:
        print(f"cap-regime {regime}")
    print("q52-careg yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q52-careg"]:
        print(
            "record_q52_careg: choose --print-q52-careg",
            file=sys.stderr,
        )
        return 2
    return print_q52_careg()


if __name__ == "__main__":
    sys.exit(main())
