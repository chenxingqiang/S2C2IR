#!/usr/bin/env python3
"""Require runtime/ascend/record_ascend._NTILE_TAILS to stay the four tails.

Loads runtime/ascend/record_ascend.py with importlib from Path(__file__).
The tuple must stay the prefetch and preserve rows in that order.
Does not call run_analyzer. Does not add a predicate, device, dialect,
backend, or semantic cut. Query only. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RECORD = Path(__file__).resolve().parent / "ascend" / "record_ascend.py"
_NTILE_TAILS = (
    "PREFETCH|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER",
    "PREFETCH|TRANSFER//PRESERVE|TRANSFER//TRANSFER|TRANSFER",
    "PRESERVE|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER",
    "PRESERVE|TRANSFER//PRESERVE|TRANSFER//TRANSFER|TRANSFER",
)
_FLAG = "--print-q84-ntail"


def _load_record_ascend() -> ModuleType:
    """Load runtime/ascend/record_ascend.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_ascend_q84_ntail", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-ascend-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def print_q84_ntail() -> int:
    try:
        mod = _load_record_ascend()
        tails = mod._NTILE_TAILS
    except (Exception, SystemExit):
        print("q84-ntail no")
        return 1
    if type(tails) is not tuple or tails != _NTILE_TAILS:
        print("q84-ntail no")
        return 1
    print("q84-ntail gate=query")
    for text in tails:
        print(f"ntile-tail {text}")
    print("q84-ntail yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q84_ntail: choose --print-q84-ntail",
            file=sys.stderr,
        )
        return 2
    return print_q84_ntail()


if __name__ == "__main__":
    sys.exit(main())
