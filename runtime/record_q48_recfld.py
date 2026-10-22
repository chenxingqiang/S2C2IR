#!/usr/bin/env python3
"""Require evidence RECORD_FIELDS to stay the twelve record field names.

Reads record_evidence.RECORD_FIELDS inside the query. The tuple stays
schema, profile, workload_signature, candidate_signature,
measurement_status, correctness, cost, scope, source,
measurement_revision, recorded_at, note.
Query only. Does not add a predicate, device, dialect, backend,
or semantic cut. Does not call run_analyzer. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_RECORD_FIELDS = (
    "schema",
    "profile",
    "workload_signature",
    "candidate_signature",
    "measurement_status",
    "correctness",
    "cost",
    "scope",
    "source",
    "measurement_revision",
    "recorded_at",
    "note",
)
_FLAG = "--print-q48-recfld"


def print_q48_recfld() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_evidence

        fields = record_evidence.RECORD_FIELDS
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        print("q48-recfld no")
        return 1
    if fields != _RECORD_FIELDS:
        print("q48-recfld no")
        return 1
    print("q48-recfld gate=query")
    for name in fields:
        print(f"record-field {name}")
    print("q48-recfld yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q48_recfld: choose --print-q48-recfld",
            file=sys.stderr,
        )
        return 2
    return print_q48_recfld()


if __name__ == "__main__":
    sys.exit(main())
