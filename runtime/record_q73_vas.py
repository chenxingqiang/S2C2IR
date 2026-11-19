#!/usr/bin/env python3
"""Require CUDA VAL_ASYNC_ARMS to stay the five val-async arms.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
VAL_ASYNC_ARMS must stay ("val-async-copy", "val-async-compute",
"val-async-life-sync", "val-async-life-async", "val-async-hb").
Query only. Does not edit record_v3. Does not add a predicate, device,
dialect, backend, or semantic cut. Does not call run_analyzer.
can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_VAL_ASYNC_ARMS = (
    "val-async-copy",
    "val-async-compute",
    "val-async-life-sync",
    "val-async-life-async",
    "val-async-hb",
)


def load_record_v3():
    """Load runtime/cuda/record_v3.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_q73_vas", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def print_q73_vas() -> int:
    try:
        module = load_record_v3()
        arms = module.VAL_ASYNC_ARMS
    except (Exception, SystemExit):
        print("q73-vas no")
        return 1
    if arms != _VAL_ASYNC_ARMS:
        print("q73-vas no")
        return 1
    print("q73-vas gate=query")
    for arm in arms:
        print(f"async-arm {arm}")
    print("q73-vas yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q73-vas"]:
        print(
            "record_q73_vas: choose --print-q73-vas",
            file=sys.stderr,
        )
        return 2
    return print_q73_vas()


if __name__ == "__main__":
    sys.exit(main())
