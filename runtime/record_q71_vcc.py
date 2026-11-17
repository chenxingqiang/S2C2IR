#!/usr/bin/env python3
"""Require runtime/cuda/record_v3 val-cc arms and dim.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
Query only. Does not call run_analyzer. Does not add a predicate,
device, dialect, backend, or semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_ARMS = (
    "val-cc-silu",
    "val-cc-matmul",
    "val-cc-seq",
    "val-cc-ovl",
    "val-cc-silu-silu",
)
_DIM = 1024
_FLAG = "--print-q71-vcc"


def load_record_v3():
    """Load runtime/cuda/record_v3.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_vcc", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def print_q71_vcc() -> int:
    try:
        mod = load_record_v3()
        arms = getattr(mod, "VAL_CC_ARMS", None)
        dim = getattr(mod, "VAL_CC_DIM", None)
    except (
        OSError,
        RuntimeError,
        ValueError,
        ImportError,
        SyntaxError,
        AttributeError,
        TypeError,
    ):
        print("q71-vcc no")
        return 1
    if arms != _ARMS or dim != _DIM:
        print("q71-vcc no")
        return 1
    print("q71-vcc gate=query")
    for arm in arms:
        print(f"cc-arm {arm}")
    print(f"cc-dim {dim}")
    print("q71-vcc yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q71_vcc: choose --print-q71-vcc",
            file=sys.stderr,
        )
        return 2
    return print_q71_vcc()


if __name__ == "__main__":
    sys.exit(main())
