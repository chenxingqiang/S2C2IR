#!/usr/bin/env python3
"""Query the frozen capacity spec field names.

Imports record_capacity inside the printer and requires SPEC_FIELDS to
stay schema, workload_class, space, capacity_tiles, residencies, note.
Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent

_SPEC_FIELDS = (
    "schema",
    "workload_class",
    "space",
    "capacity_tiles",
    "residencies",
    "note",
)


def print_q21_capspec() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_capacity

        if record_capacity.SPEC_FIELDS != _SPEC_FIELDS:
            print("q21-capspec no")
            return 1
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        print("q21-capspec no")
        return 1
    print("q21-capspec gate=query")
    for field in record_capacity.SPEC_FIELDS:
        print("spec-field " + field)
    print("q21-capspec yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q21-capspec"]:
        print(
            "record_q21_capspec: choose --print-q21-capspec",
            file=sys.stderr,
        )
        return 2
    return print_q21_capspec()


if __name__ == "__main__":
    sys.exit(main())
