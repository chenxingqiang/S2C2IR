#!/usr/bin/env python3
"""Require CUDA CAP_MATMUL_DIMS and CAP_K to stay the query constants.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
CAP_MATMUL_DIMS must equal (256, 512, 1024) and CAP_K must equal 32.
Query only. Does not call run_analyzer. Does not add a predicate,
device, dialect, backend, or semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_DIMS = (256, 512, 1024)
_CAP_K = 32
_FLAG = "--print-q61-cmat"


def _load_record_v3():
    """Load runtime/cuda/record_v3.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_q61_cmat", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def print_q61_cmat() -> int:
    try:
        module = _load_record_v3()
        dims = module.CAP_MATMUL_DIMS
        cap_k = module.CAP_K
    except (
        AttributeError,
        ImportError,
        OSError,
        RuntimeError,
        SyntaxError,
        TypeError,
        ValueError,
    ):
        print("q61-cmat no")
        return 1
    if dims != _DIMS or cap_k != _CAP_K:
        print("q61-cmat no")
        return 1
    print("q61-cmat gate=query")
    for dim in dims:
        print(f"matmul-dim {dim}")
    print(f"cap-k {cap_k}")
    print("q61-cmat yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q61_cmat: choose --print-q61-cmat",
            file=sys.stderr,
        )
        return 2
    return print_q61_cmat()


if __name__ == "__main__":
    sys.exit(main())
