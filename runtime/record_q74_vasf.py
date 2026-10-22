#!/usr/bin/env python3
"""Require CUDA VAL_ASYNC_FIELDS to stay the recorded async field names.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
Query only. Does not call run_analyzer. Does not add a predicate,
device, dialect, backend, or semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_VAL_ASYNC_FIELDS = (
    "N",
    "k",
    "r",
    "T_copy_us",
    "T_compute_us",
    "T_life_sync_us",
    "T_life_async_us",
    "T_hb_us",
    "sync_over_async",
    "hb_over_async",
    "observed_constraint",
    "extra_hb",
)
_FLAG = "--print-q74-vasf"


def _load(path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_q74_vasf", path
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q74-vasf no")
    return 1


def print_q74_vasf() -> int:
    try:
        fields = _load(_RECORD).VAL_ASYNC_FIELDS
    except (Exception, SystemExit):
        return _no()
    if type(fields) is not tuple or fields != _VAL_ASYNC_FIELDS:
        return _no()
    print("q74-vasf gate=query")
    for name in fields:
        print(f"async-field {name}")
    print("q74-vasf yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q74_vasf: choose --print-q74-vasf",
            file=sys.stderr,
        )
        return 2
    return print_q74_vasf()


if __name__ == "__main__":
    sys.exit(main())
