#!/usr/bin/env python3
"""Require CUDA and Ascend capability relations to stay the same tuple.

Loads runtime/cuda/record_v3.py and runtime/ascend/record_ascend.py
by file path. Both CAP_SCHEMA_RELATION tuples must be
("serial", "parallel", "mixed", "underdetermined") in that order.
Query only. Does not edit either recorder. No semantic cut.
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
_RELATION = ("serial", "parallel", "mixed", "underdetermined")


def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q51-carel no")
    return 1


def print_q51_carel() -> int:
    try:
        cuda = _load(_CUDA, "s2c2_q51_cuda_cap_relation")
        ascend = _load(_ASCEND, "s2c2_q51_ascend_cap_relation")
        cuda_relation = cuda.CAP_SCHEMA_RELATION
        ascend_relation = ascend.CAP_SCHEMA_RELATION
    except (Exception, SystemExit):
        return _no()
    if type(cuda_relation) is not tuple or type(ascend_relation) is not tuple:
        return _no()
    if cuda_relation != ascend_relation or cuda_relation != _RELATION:
        return _no()
    print("q51-carel gate=query")
    for relation in cuda_relation:
        print(f"cap-relation {relation}")
    print("q51-carel yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q51-carel"]:
        print(
            "record_q51_carel: choose --print-q51-carel",
            file=sys.stderr,
        )
        return 2
    return print_q51_carel()


if __name__ == "__main__":
    sys.exit(main())
