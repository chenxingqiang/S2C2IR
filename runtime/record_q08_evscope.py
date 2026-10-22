#!/usr/bin/env python3
"""Require evidence scope and schema to stay candidate-local and s2c2.evidence.v1.

Imports record_evidence inside the query. SCOPE must be candidate-local.
SCHEMA must be s2c2.evidence.v1. Query only. No semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent

_SCOPE = "candidate-local"
_SCHEMA = "s2c2.evidence.v1"


def _no() -> int:
    print("q08-evscope no")
    return 1


def print_q08_evscope() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_evidence
    except ImportError:
        return _no()
    try:
        scope = record_evidence.SCOPE
        schema = record_evidence.SCHEMA
    except AttributeError:
        return _no()
    if type(scope) is not str or type(schema) is not str:
        return _no()
    if scope != _SCOPE or schema != _SCHEMA:
        return _no()
    # The printed scope and schema are the live constants.
    print("q08-evscope gate=query")
    print("evidence-scope " + record_evidence.SCOPE)
    print("evidence-schema " + record_evidence.SCHEMA)
    print("q08-evscope yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q08-evscope"]:
        print(
            "record_q08_evscope: choose --print-q08-evscope",
            file=sys.stderr,
        )
        return 2
    return print_q08_evscope()


if __name__ == "__main__":
    sys.exit(main())
