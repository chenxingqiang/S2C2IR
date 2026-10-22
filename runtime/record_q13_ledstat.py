#!/usr/bin/env python3
"""Require record_hw_ledger.LEDGER_STATUS in fixed order.

The status tuple must stay measured, device-absent.
Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent

_LEDGER_STATUS = ("measured", "device-absent")


def _no() -> int:
    print("q13-ledstat no")
    return 1


def print_q13_ledstat() -> int:
    try:
        sys.path.insert(0, str(_RUNTIME))
        import record_hw_ledger

        status = record_hw_ledger.LEDGER_STATUS
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        return _no()
    if type(status) is not tuple or status != _LEDGER_STATUS:
        return _no()
    print("q13-ledstat gate=query")
    for item in status:
        print("ledger-status " + item)
    print("q13-ledstat yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q13-ledstat"]:
        print(
            "record_q13_ledstat: choose --print-q13-ledstat",
            file=sys.stderr,
        )
        return 2
    return print_q13_ledstat()


if __name__ == "__main__":
    sys.exit(main())
