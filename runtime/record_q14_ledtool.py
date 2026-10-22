#!/usr/bin/env python3
"""Require the hardware ledger tool tuple.

Imports record_hw_ledger.LEDGER_TOOL inside the printer. The tuple
stays ("cuda", "ascend", "none"). Query only. Does not call
run_analyzer. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent


def print_q14_ledtool() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_hw_ledger

        if record_hw_ledger.LEDGER_TOOL != ("cuda", "ascend", "none"):
            print("q14-ledtool no")
            return 1
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        print("q14-ledtool no")
        return 1
    print("q14-ledtool gate=query")
    for tool in record_hw_ledger.LEDGER_TOOL:
        print("ledger-tool " + tool)
    print("q14-ledtool yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q14-ledtool"]:
        print(
            "record_q14_ledtool: choose --print-q14-ledtool",
            file=sys.stderr,
        )
        return 2
    return print_q14_ledtool()


if __name__ == "__main__":
    sys.exit(main())
