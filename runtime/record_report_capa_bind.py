#!/usr/bin/env python3
"""Require the occupancy report schema to differ from the applicability schema.

Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_capability_applicability as capa
import record_occupancy_capability as occupancy


def print_report_capa_bind() -> int:
    try:
        report_schema = occupancy.REPORT_SCHEMA
        applicability_schema = capa.SCHEMA
    except AttributeError:
        print("report-capa-bind no")
        return 1
    if (
        not isinstance(report_schema, str)
        or not isinstance(applicability_schema, str)
        or report_schema == applicability_schema
    ):
        print("report-capa-bind no")
        return 1
    print("report-capa-bind gate=query")
    print(f"report-schema {report_schema}")
    print(f"applicability-schema {applicability_schema}")
    print("report-capa-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Require the occupancy report schema to differ "
            "from the applicability schema."
        ),
        add_help=False,
        allow_abbrev=False,
    )
    parser.add_argument("--print-report-capa-bind", action="store_true")
    try:
        args, extra = parser.parse_known_args(argv)
    except SystemExit as exc:
        code = exc.code
        return code if isinstance(code, int) else 2
    if extra or not args.print_report_capa_bind:
        print(
            "record_report_capa_bind: choose --print-report-capa-bind",
            file=sys.stderr,
        )
        return 2
    return print_report_capa_bind()


if __name__ == "__main__":
    sys.exit(main())
