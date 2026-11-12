#!/usr/bin/env python3
"""Require CUDA and Ascend capability constraints to stay the same tuple.

Loads runtime/cuda/record_v3.py and runtime/ascend/record_ascend.py
by file path. Both CAP_SCHEMA_CONSTRAINT tuples must be
("none", "legacy_default", "resource_contention", "allocator_sync",
"copy_engine_contention") in that order. Query only. Does not call
run_analyzer. Does not edit either recorder. No semantic cut.
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
_CONSTRAINT = (
    "none",
    "legacy_default",
    "resource_contention",
    "allocator_sync",
    "copy_engine_contention",
)


def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q53-cacst no")
    return 1


def print_q53_cacst() -> int:
    try:
        cuda = _load(_CUDA, "s2c2_q53_cuda_cap_constraint")
        ascend = _load(_ASCEND, "s2c2_q53_ascend_cap_constraint")
        cuda_constraint = cuda.CAP_SCHEMA_CONSTRAINT
        ascend_constraint = ascend.CAP_SCHEMA_CONSTRAINT
    except (Exception, SystemExit):
        return _no()
    if type(cuda_constraint) is not tuple or type(ascend_constraint) is not tuple:
        return _no()
    if cuda_constraint != ascend_constraint or cuda_constraint != _CONSTRAINT:
        return _no()
    print("q53-cacst gate=query")
    for name in cuda_constraint:
        print(f"cap-constraint {name}")
    print("q53-cacst yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q53-cacst"]:
        print(
            "record_q53_cacst: choose --print-q53-cacst",
            file=sys.stderr,
        )
        return 2
    return print_q53_cacst()


if __name__ == "__main__":
    sys.exit(main())
