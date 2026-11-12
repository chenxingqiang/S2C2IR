#!/usr/bin/env python3
"""Require CUDA PIPE_ARMS to stay the six pipe arms.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
PIPE_ARMS must stay ("pipe-copy", "pipe-compute", "pipe-d1",
"pipe-d2", "pipe-d3", "pipe-d4"). Query only. Does not edit record_v3.
Does not add a predicate, device, dialect, backend, or semantic cut.
Does not call run_analyzer. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_PIPE_ARMS = (
    "pipe-copy",
    "pipe-compute",
    "pipe-d1",
    "pipe-d2",
    "pipe-d3",
    "pipe-d4",
)


def load_record_v3():
    """Load runtime/cuda/record_v3.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_q65_parm", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def print_q65_parm() -> int:
    try:
        module = load_record_v3()
        arms = module.PIPE_ARMS
    except (Exception, SystemExit):
        print("q65-parm no")
        return 1
    if arms != _PIPE_ARMS:
        print("q65-parm no")
        return 1
    print("q65-parm gate=query")
    for arm in arms:
        print(f"pipe-arm {arm}")
    print("q65-parm yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q65-parm"]:
        print(
            "record_q65_parm: choose --print-q65-parm",
            file=sys.stderr,
        )
        return 2
    return print_q65_parm()


if __name__ == "__main__":
    sys.exit(main())
