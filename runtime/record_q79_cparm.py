#!/usr/bin/env python3
"""Require runtime/cuda/record_v3.CAP_PAIR_ARMS to stay the pair arms.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
Query only. Does not call run_analyzer. Does not add a predicate,
device, dialect, backend, or semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_CAP_PAIR_ARMS = (
    "cap-htod",
    "cap-dtoh",
    "cap-htod-dtoh-seq",
    "cap-htod-dtoh-event",
    "cap-htod-dtoh-par",
    "cap-htod-htod-par",
    "cap-dtoh-dtoh-par",
    "cap-compute",
    "cap-compute-htod",
    "cap-compute-dtoh",
    "cap-compute-compute",
)
_FLAG = "--print-q79-cparm"


def load_record_v3():
    """Load runtime/cuda/record_v3.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_cparm", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def print_q79_cparm() -> int:
    try:
        mod = load_record_v3()
        arms = getattr(mod, "CAP_PAIR_ARMS", None)
    except (
        OSError,
        RuntimeError,
        ValueError,
        ImportError,
        SyntaxError,
        AttributeError,
        TypeError,
    ):
        print("q79-cparm no")
        return 1
    if type(arms) is not tuple or arms != _CAP_PAIR_ARMS:
        print("q79-cparm no")
        return 1
    print("q79-cparm gate=query")
    for name in arms:
        print(f"pair-arm {name}")
    print("q79-cparm yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q79_cparm: choose --print-q79-cparm",
            file=sys.stderr,
        )
        return 2
    return print_q79_cparm()


if __name__ == "__main__":
    sys.exit(main())
