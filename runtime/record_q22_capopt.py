#!/usr/bin/env python3
"""Require the capacity optional spec fields.

record_capacity.OPTIONAL_SPEC_FIELDS must stay
restore_sources, source_data, restore_order, dest_invalidation.
Query only. No semantic cut. can-run-plan stays no.
Does not add a capacity predicate.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent


def _no() -> int:
    print("q22-capopt no")
    return 1


def print_q22_capopt() -> int:
    sys.path.insert(0, str(_RUNTIME))
    try:
        import record_capacity

        optional = record_capacity.OPTIONAL_SPEC_FIELDS
    except (ImportError, AttributeError):
        return _no()
    if optional != (
        "restore_sources",
        "source_data",
        "restore_order",
        "dest_invalidation",
    ):
        return _no()
    print("q22-capopt gate=query")
    for name in optional:
        print("optional-field " + name)
    print("q22-capopt yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q22-capopt"]:
        print(
            "record_q22_capopt: choose --print-q22-capopt",
            file=sys.stderr,
        )
        return 2
    return print_q22_capopt()


if __name__ == "__main__":
    sys.exit(main())
