#!/usr/bin/env python3
"""Require record_hw_ledger.LEDGER_KIND in fixed order.

The kind tuple must stay catalog, overlay, campaign, program.
Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent

_LEDGER_KIND = ("catalog", "overlay", "campaign", "program")


def _no() -> int:
    print("q12-ledkind no")
    return 1


def print_q12_ledkind() -> int:
    try:
        sys.path.insert(0, str(_RUNTIME))
        import record_hw_ledger

        kind = record_hw_ledger.LEDGER_KIND
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        return _no()
    if type(kind) is not tuple or kind != _LEDGER_KIND:
        return _no()
    print("q12-ledkind gate=query")
    for item in kind:
        print("ledger-kind " + item)
    print("q12-ledkind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q12-ledkind"]:
        print(
            "record_q12_ledkind: choose --print-q12-ledkind",
            file=sys.stderr,
        )
        return 2
    return print_q12_ledkind()


if __name__ == "__main__":
    sys.exit(main())
