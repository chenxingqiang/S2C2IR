#!/usr/bin/env python3
"""Require CUDA and Ascend CAP_SCHEMA_FIELDS to stay the twenty-one names.

Loads runtime/cuda/record_v3.py and runtime/ascend/record_ascend.py
by file path. Both tuples must be equal and equal to the schema field
order. Does not call run_analyzer. Does not add a predicate, device,
dialect, backend, or semantic cut. Query only. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RUNTIME = Path(__file__).resolve().parent
_CUDA = _RUNTIME / "cuda" / "record_v3.py"
_ASCEND = _RUNTIME / "ascend" / "record_ascend.py"
_FIELDS = (
    "schema_version",
    "record_kind",
    "hardware_id",
    "compute_domain",
    "transfer_domain",
    "direction",
    "source_memory_class",
    "destination_memory_class",
    "pair",
    "pair_relation",
    "regime",
    "size_range",
    "synchronization",
    "pipeline_depth_evidence",
    "observed_constraint",
    "confidence",
    "note",
    "evidence_refs",
    "v3",
    "cost",
    "semantics",
)
_FLAG = "--print-q55-cafld"


def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q55-cafld no")
    return 1


def print_q55_cafld() -> int:
    try:
        cuda = _load(_CUDA, "s2c2_cuda_q55_cafld")
        ascend = _load(_ASCEND, "s2c2_ascend_q55_cafld")
        cuda_fields = cuda.CAP_SCHEMA_FIELDS
        ascend_fields = ascend.CAP_SCHEMA_FIELDS
    except (Exception, SystemExit):
        return _no()
    if (
        type(cuda_fields) is not tuple
        or type(ascend_fields) is not tuple
        or cuda_fields != ascend_fields
        or cuda_fields != _FIELDS
    ):
        return _no()
    print("q55-cafld gate=query")
    for name in _FIELDS:
        print(f"cap-field {name}")
    print("q55-cafld yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q55_cafld: choose --print-q55-cafld",
            file=sys.stderr,
        )
        return 2
    return print_q55_cafld()


if __name__ == "__main__":
    sys.exit(main())
