#!/usr/bin/env python3
"""Require the hardware ledger field names to stay the host tuple.

Imports record_hw_ledger.LEDGER_FIELDS inside the query. Does not
call run_analyzer. Does not add a device. Query only. No semantic
cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_LEDGER_FIELDS = (
    "id",
    "hardware",
    "kind",
    "status",
    "path",
    "tool",
    "analyze",
    "catalog_role",
    "note",
    "cost",
    "semantics",
)
_FLAG = "--print-q16-ledfld"


def print_q16_ledfld() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_hw_ledger

        fields = record_hw_ledger.LEDGER_FIELDS
    except (
        AttributeError,
        ImportError,
        OSError,
        SyntaxError,
        TypeError,
        ValueError,
    ):
        print("q16-ledfld no")
        return 1
    if fields != _LEDGER_FIELDS:
        print("q16-ledfld no")
        return 1
    print("q16-ledfld gate=query")
    for name in fields:
        print(f"ledger-field {name}")
    print("q16-ledfld yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q16_ledfld: choose --print-q16-ledfld",
            file=sys.stderr,
        )
        return 2
    return print_q16_ledfld()


if __name__ == "__main__":
    sys.exit(main())
