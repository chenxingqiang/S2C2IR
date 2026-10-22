#!/usr/bin/env python3
"""Compare the occupancy report schema with the sufficiency and checking schemas.

Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_occupancy_capability as occupancy
import record_realization_checking as checking
import record_sufficiency as sufficiency


def _distinct_schemas(schemas: tuple[object, ...]) -> bool:
    """True when the schema ids are three different strings."""
    return (
        len(schemas) == 3
        and all(isinstance(schema, str) for schema in schemas)
        and len(set(schemas)) == 3
    )


def print_report_foreign_schemas() -> int:
    try:
        schemas = (
            occupancy.REPORT_SCHEMA,
            sufficiency.SUFFICIENCY_SCHEMA,
            checking.CHECKING_SCHEMA,
        )
    except AttributeError:
        print("report-foreign-schemas no")
        return 1
    if not _distinct_schemas(schemas):
        print("report-foreign-schemas no")
        return 1
    report_schema, sufficiency_schema, checking_schema = schemas
    print("report-foreign-schemas gate=query")
    print(f"report-schema {report_schema}")
    print(f"sufficiency-schema {sufficiency_schema}")
    print(f"checking-schema {checking_schema}")
    print("report-foreign-schemas-distinct yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Compare the occupancy report schema with the "
            "sufficiency and checking schemas."
        ),
        add_help=False,
        allow_abbrev=False,
    )
    parser.add_argument("--print-report-foreign-schemas", action="store_true")
    try:
        args, extra = parser.parse_known_args(argv)
    except SystemExit as exc:
        code = exc.code
        return code if isinstance(code, int) else 2
    if extra or not args.print_report_foreign_schemas:
        print(
            "record_report_foreign_schema: choose --print-report-foreign-schemas",
            file=sys.stderr,
        )
        return 2
    return print_report_foreign_schemas()


if __name__ == "__main__":
    sys.exit(main())
