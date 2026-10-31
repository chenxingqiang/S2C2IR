#!/usr/bin/env python3
"""Require runtime/cuda/record_v3.CAP_PAIRS to stay the six pair rows.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
Prints only the first column of each row. Query only. Does not call
run_analyzer. Does not add a predicate, device, dialect, backend, or
semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_CAP_PAIRS = (
    ("HtoD||DtoH", "cap-htod", "cap-dtoh", "cap-htod-dtoh-par"),
    ("HtoD||HtoD", "cap-htod", "cap-htod", "cap-htod-htod-par"),
    ("DtoH||DtoH", "cap-dtoh", "cap-dtoh", "cap-dtoh-dtoh-par"),
    ("C||HtoD", "cap-compute", "cap-htod", "cap-compute-htod"),
    ("C||DtoH", "cap-compute", "cap-dtoh", "cap-compute-dtoh"),
    ("C||C", "cap-compute", "cap-compute", "cap-compute-compute"),
)
_FLAG = "--print-q78-cpair"


def load_record_v3():
    """Load runtime/cuda/record_v3.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_cpair", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def print_q78_cpair() -> int:
    try:
        mod = load_record_v3()
        pairs = getattr(mod, "CAP_PAIRS", None)
    except (
        OSError,
        RuntimeError,
        ValueError,
        ImportError,
        SyntaxError,
        AttributeError,
        TypeError,
    ):
        print("q78-cpair no")
        return 1
    if type(pairs) is not tuple or pairs != _CAP_PAIRS:
        print("q78-cpair no")
        return 1
    print("q78-cpair gate=query")
    for row in pairs:
        print(f"cap-pair {row[0]}")
    print("q78-cpair yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q78_cpair: choose --print-q78-cpair",
            file=sys.stderr,
        )
        return 2
    return print_q78_cpair()


if __name__ == "__main__":
    sys.exit(main())
