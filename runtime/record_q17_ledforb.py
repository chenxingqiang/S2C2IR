#!/usr/bin/env python3
"""Require the hardware ledger forbid tuple to stay one entry.

Imports record_hw_ledger inside the printer. FORBIDDEN stays a
one-element tuple. Prints the count only. Does not call
run_analyzer. Does not add a device. Query only. No semantic
cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent


def _no() -> int:
    print("q17-ledforb no")
    return 1


def print_q17_ledforb() -> int:
    try:
        sys.path.insert(0, str(_RUNTIME))
        import record_hw_ledger

        forbidden = record_hw_ledger.FORBIDDEN
        if forbidden != ("password",) or len(forbidden) != 1:
            return _no()
        count = len(forbidden)
    except (
        AttributeError,
        ImportError,
        OSError,
        SyntaxError,
        TypeError,
        ValueError,
    ):
        return _no()
    print("q17-ledforb gate=query")
    print(f"ledger-forbid-count {count}")
    print("q17-ledforb yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q17-ledforb"]:
        print(
            "usage: record_q17_ledforb.py --print-q17-ledforb",
            file=sys.stderr,
        )
        return 2
    return print_q17_ledforb()


if __name__ == "__main__":
    sys.exit(main())
