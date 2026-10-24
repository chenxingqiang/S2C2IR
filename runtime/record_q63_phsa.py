#!/usr/bin/env python3
"""Require CUDA PHASE_ARMS to stay the four phase arms.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
PHASE_ARMS must stay ("phase-seq", "phase-ovl", "phase-copy",
"phase-compute"). Query only. Does not edit record_v3. Does not add a
predicate, device, dialect, backend, or semantic cut. Does not call
run_analyzer. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_PHASE_ARMS = ("phase-seq", "phase-ovl", "phase-copy", "phase-compute")


def load_record_v3():
    """Load runtime/cuda/record_v3.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_q63_phsa", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def print_q63_phsa() -> int:
    try:
        module = load_record_v3()
        arms = module.PHASE_ARMS
    except (Exception, SystemExit):
        print("q63-phsa no")
        return 1
    if type(arms) is not tuple or arms != _PHASE_ARMS:
        print("q63-phsa no")
        return 1
    print("q63-phsa gate=query")
    for arm in arms:
        print(f"phase-arm {arm}")
    print("q63-phsa yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q63-phsa"]:
        print(
            "record_q63_phsa: choose --print-q63-phsa",
            file=sys.stderr,
        )
        return 2
    return print_q63_phsa()


if __name__ == "__main__":
    sys.exit(main())
