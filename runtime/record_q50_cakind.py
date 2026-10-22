#!/usr/bin/env python3
"""Require CUDA and Ascend CAP_SCHEMA_KINDS to stay the four kinds.

Loads runtime/cuda/record_v3.py and runtime/ascend/record_ascend.py
by file path. Both tuples must equal ("pair", "depth", "memory", "sync").
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
_KINDS = ("pair", "depth", "memory", "sync")
_FLAG = "--print-q50-cakind"


def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q50-cakind no")
    return 1


def print_q50_cakind() -> int:
    try:
        cuda = _load(_CUDA, "s2c2_cuda_q50_cakind")
        ascend = _load(_ASCEND, "s2c2_ascend_q50_cakind")
        cuda_kinds = cuda.CAP_SCHEMA_KINDS
        ascend_kinds = ascend.CAP_SCHEMA_KINDS
    except (Exception, SystemExit):
        return _no()
    if (
        type(cuda_kinds) is not tuple
        or type(ascend_kinds) is not tuple
        or cuda_kinds != _KINDS
        or ascend_kinds != _KINDS
    ):
        return _no()
    print("q50-cakind gate=query")
    for kind in cuda_kinds:
        print(f"cap-kind {kind}")
    print("q50-cakind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q50_cakind: choose --print-q50-cakind",
            file=sys.stderr,
        )
        return 2
    return print_q50_cakind()


if __name__ == "__main__":
    sys.exit(main())
