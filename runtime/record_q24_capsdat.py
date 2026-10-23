#!/usr/bin/env python3
"""Require the capacity source-data field tuple.

Query only. Reads record_capacity.SOURCE_DATA_FIELDS. No semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_FIELDS = ("object", "replica", "witness", "live", "scope")
_FLAG = "--print-q24-capsdat"


def print_q24_capsdat() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_capacity

        fields = record_capacity.SOURCE_DATA_FIELDS
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError):
        print("q24-capsdat no")
        return 1
    if fields != _FIELDS:
        print("q24-capsdat no")
        return 1
    print("q24-capsdat gate=query")
    for field in fields:
        print(f"source-data-field {field}")
    print("q24-capsdat yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q24_capsdat: choose --print-q24-capsdat",
            file=sys.stderr,
        )
        return 2
    return print_q24_capsdat()


if __name__ == "__main__":
    sys.exit(main())
