#!/usr/bin/env python3
"""Require record_capacity.RESTORE_SRC_FIELDS.

The restore source fields stay object, space, kind.
Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent


def print_q23_caprsrc() -> int:
    try:
        sys.path.insert(0, str(_RUNTIME))
        import record_capacity

        fields = record_capacity.RESTORE_SRC_FIELDS
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        print("q23-caprsrc no")
        return 1
    if fields != ("object", "space", "kind"):
        print("q23-caprsrc no")
        return 1
    print("q23-caprsrc gate=query")
    for name in fields:
        print("restore-src-field " + name)
    print("q23-caprsrc yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q23-caprsrc"]:
        print(
            "record_q23_caprsrc: choose --print-q23-caprsrc",
            file=sys.stderr,
        )
        return 2
    return print_q23_caprsrc()


if __name__ == "__main__":
    sys.exit(main())
