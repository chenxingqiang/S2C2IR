#!/usr/bin/env python3
"""Require the Ascend pair tuple to stay the three Phase 3B pairs.

Loads runtime/ascend/record_ascend.py with importlib. PAIRS must
stay ("C||HtoD", "C||C", "HtoD||DtoH") and length 3. Query only.
No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RUNTIME = Path(__file__).resolve().parent
_ASCEND_PY = _RUNTIME / "ascend" / "record_ascend.py"
_REQUIRED = ("C||HtoD", "C||C", "HtoD||DtoH")


def _load_record_ascend() -> ModuleType:
    spec = importlib.util.spec_from_file_location("record_ascend", _ASCEND_PY)
    if spec is None or spec.loader is None:
        raise ImportError("record_ascend")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("ascend-pairs-bind no")
    return 1


def print_ascend_pairs_bind() -> int:
    try:
        record_ascend = _load_record_ascend()
        pairs = record_ascend.PAIRS
        if pairs != _REQUIRED or len(pairs) != 3:
            return _no()
    except (Exception, SystemExit):
        return _no()
    print("ascend-pairs-bind gate=query")
    for pair in record_ascend.PAIRS:
        print(f"pair {pair}")
    print("ascend-pairs-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-ascend-pairs-bind"]:
        print(
            "record_ascend_pairs_bind: choose --print-ascend-pairs-bind",
            file=sys.stderr,
        )
        return 2
    return print_ascend_pairs_bind()


if __name__ == "__main__":
    sys.exit(main())
