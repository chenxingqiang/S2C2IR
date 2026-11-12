#!/usr/bin/env python3
"""Require the CUDA capability sync arms.

Query only. Loads runtime/cuda/record_v3.py and requires CAP_SYNC_ARMS
to stay cap-event-sync, cap-stream-sync, and cap-device-sync. This does
not add a predicate, device, dialect, backend, or semantic cut. Does
not call run_analyzer. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_SYNC_ARMS = ("cap-event-sync", "cap-stream-sync", "cap-device-sync")


def _load_record_v3():
    """Load runtime/cuda/record_v3.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_q59_csync", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def print_q59_csync() -> int:
    try:
        module = _load_record_v3()
        arms = module.CAP_SYNC_ARMS
    except (
        AttributeError,
        ImportError,
        OSError,
        RuntimeError,
        SyntaxError,
        TypeError,
        ValueError,
    ):
        print("q59-csync no")
        return 1
    if arms != _SYNC_ARMS:
        print("q59-csync no")
        return 1
    print("q59-csync gate=query")
    for arm in arms:
        print(f"sync-arm {arm}")
    print("q59-csync yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q59-csync"]:
        print(
            "record_q59_csync: choose --print-q59-csync",
            file=sys.stderr,
        )
        return 2
    return print_q59_csync()


if __name__ == "__main__":
    sys.exit(main())
