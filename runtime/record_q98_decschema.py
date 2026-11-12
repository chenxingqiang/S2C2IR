#!/usr/bin/env python3
"""Require the shared decision schema across three query modules.

Imports record_sufficiency, record_authorization, and
record_storage_rewrite inside the query, after the runtime directory
is on sys.path. Each DECISION_SCHEMA must be s2c2.decision.v1.
Does not call run_analyzer. Does not add a predicate, device,
dialect, backend, or semantic cut. Query only. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_DECISION_SCHEMA = "s2c2.decision.v1"
_FLAG = "--print-q98-decschema"


def print_q98_decschema() -> int:
    runtime = Path(__file__).resolve().parent
    if str(runtime) not in sys.path:
        sys.path.insert(0, str(runtime))
    try:
        import record_sufficiency
        import record_authorization
        import record_storage_rewrite

        schemas = (
            record_sufficiency.DECISION_SCHEMA,
            record_authorization.DECISION_SCHEMA,
            record_storage_rewrite.DECISION_SCHEMA,
        )
    except (
        AttributeError,
        ImportError,
        OSError,
        SyntaxError,
        TypeError,
        ValueError,
    ):
        print("q98-decschema no")
        return 1
    if schemas != (_DECISION_SCHEMA, _DECISION_SCHEMA, _DECISION_SCHEMA):
        print("q98-decschema no")
        return 1
    print("q98-decschema gate=query")
    print("decision-schema " + record_sufficiency.DECISION_SCHEMA)
    print("q98-decschema yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q98_decschema: choose --print-q98-decschema",
            file=sys.stderr,
        )
        return 2
    return print_q98_decschema()


if __name__ == "__main__":
    sys.exit(main())
