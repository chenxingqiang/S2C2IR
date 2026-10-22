#!/usr/bin/env python3
"""Require measured storage cost v1 to stay distinct from evidence.

record_evidence.V1_SCHEMA stays s2c2.measured_storage_cost.v1 and
record_evidence.SCHEMA stays s2c2.evidence.v1. Query only. No semantic
cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_MEASURED = "s2c2.measured_storage_cost.v1"
_EVIDENCE = "s2c2.evidence.v1"


def _no() -> int:
    print("q09-evv1 no")
    return 1


def print_q09_evv1() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_evidence

        measured = record_evidence.V1_SCHEMA
        evidence = record_evidence.SCHEMA
    except Exception:
        return _no()
    if (
        type(measured) is not str
        or type(evidence) is not str
        or measured != _MEASURED
        or measured == evidence
        or evidence != _EVIDENCE
    ):
        return _no()
    print("q09-evv1 gate=query")
    print("measured-schema " + record_evidence.V1_SCHEMA)
    print("evidence-schema " + record_evidence.SCHEMA)
    print("q09-evv1 yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q09-evv1"]:
        print(
            "record_q09_evv1: choose --print-q09-evv1",
            file=sys.stderr,
        )
        return 2
    return print_q09_evv1()


if __name__ == "__main__":
    sys.exit(main())
