#!/usr/bin/env python3
"""Read the nine capacity schema constants and require them to be distinct.

Query only. No semantic cut. can-run-plan stays no.
Does not add capacity predicates.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_capacity

_SCHEMA_NAMES = (
    "SCHEMA",
    "PLAN_SCHEMA",
    "MEAS_CAP_SCHEMA",
    "LICENSE_SCHEMA",
    "RESTORE_SCHEMA",
    "PREDICATE_SCHEMA",
    "SOURCEDATA_SCHEMA",
    "ORDERING_SCHEMA",
    "INVALIDATION_SCHEMA",
)


def nine_schema_constants() -> tuple[str, ...] | None:
    """The nine capacity schema strings, or None when one is not a string."""
    values: list[str] = []
    for name in _SCHEMA_NAMES:
        value = getattr(record_capacity, name, None)
        if type(value) is not str:
            return None
        values.append(value)
    return tuple(values)


def print_cap_nine_schemas() -> int:
    try:
        schemas = nine_schema_constants()
        distinct = record_capacity.cap_schemas_distinct()
    except (AttributeError, TypeError):
        print("cap-nine-schemas no")
        return 1
    if schemas is None or distinct is not True:
        print("cap-nine-schemas no")
        return 1
    count = len(set(schemas))
    if count != len(schemas) or count != 9:
        print("cap-nine-schemas no")
        return 1
    print("cap-nine-schemas gate=query")
    print(f"cap-nine-count {count}")
    print("cap-nine-schemas-distinct yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Read the nine capacity schema constants.",
        add_help=False,
    )
    parser.add_argument("--print-cap-nine-schemas", action="store_true")
    try:
        args, extra = parser.parse_known_args(argv)
    except SystemExit as exc:
        code = exc.code
        return code if isinstance(code, int) else 2
    if extra or not args.print_cap_nine_schemas:
        print(
            "record_capacity_schema_bind: choose --print-cap-nine-schemas",
            file=sys.stderr,
        )
        return 2
    return print_cap_nine_schemas()


if __name__ == "__main__":
    sys.exit(main())
