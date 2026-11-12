#!/usr/bin/env python3
"""Require CUDA and Ascend CAP_SCHEMA_CONFIDENCE to stay the four names.

Loads runtime/cuda/record_v3.py and runtime/ascend/record_ascend.py
by file path. Both tuples must equal
("measured", "inferred", "arm_specific", "unknown") in that order.
Does not call run_analyzer. Does not add a predicate, device, dialect,
backend, or semantic cut. Query only. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RUNTIME = Path(__file__).resolve().parent
_CUDA = _RUNTIME / "cuda" / "record_v3.py"
_ASCEND = _RUNTIME / "ascend" / "record_ascend.py"
_CONFIDENCE = ("measured", "inferred", "arm_specific", "unknown")
_FLAG = "--print-q54-cacnf"


def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q54-cacnf no")
    return 1


def print_q54_cacnf() -> int:
    try:
        cuda = _load(_CUDA, "s2c2_cuda_q54_cacnf")
        ascend = _load(_ASCEND, "s2c2_ascend_q54_cacnf")
        cuda_confidence = cuda.CAP_SCHEMA_CONFIDENCE
        ascend_confidence = ascend.CAP_SCHEMA_CONFIDENCE
    except (Exception, SystemExit):
        return _no()
    if (
        type(cuda_confidence) is not tuple
        or type(ascend_confidence) is not tuple
        or cuda_confidence != _CONFIDENCE
        or ascend_confidence != _CONFIDENCE
    ):
        return _no()
    print("q54-cacnf gate=query")
    for name in cuda_confidence:
        print(f"cap-confidence {name}")
    print("q54-cacnf yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q54_cacnf: choose --print-q54-cacnf",
            file=sys.stderr,
        )
        return 2
    return print_q54_cacnf()


if __name__ == "__main__":
    sys.exit(main())
