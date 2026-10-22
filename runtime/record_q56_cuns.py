#!/usr/bin/env python3
"""Require runtime/cuda/record_v3.NS to stay the CUDA N table.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
Query only. Does not call run_analyzer. Does not add a predicate,
device, dialect, backend, or semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_NS = (4194304, 16777216, 67108864)
_FLAG = "--print-q56-cuns"


def load_record_v3():
    """Load runtime/cuda/record_v3.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_ns", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def print_q56_cuns() -> int:
    try:
        mod = load_record_v3()
        ns = getattr(mod, "NS", None)
    except (
        OSError,
        RuntimeError,
        ValueError,
        ImportError,
        SyntaxError,
        AttributeError,
        TypeError,
    ):
        print("q56-cuns no")
        return 1
    if ns != _NS:
        print("q56-cuns no")
        return 1
    print("q56-cuns gate=query")
    for n in ns:
        print(f"cuda-n {n}")
    print("q56-cuns yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q56_cuns: choose --print-q56-cuns",
            file=sys.stderr,
        )
        return 2
    return print_q56_cuns()


if __name__ == "__main__":
    sys.exit(main())
