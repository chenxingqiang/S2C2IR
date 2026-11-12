#!/usr/bin/env python3
"""Require the closed decision reason tokens.

Imports record_decision inside the query. Does not call run_analyzer.
Does not add a predicate, device, dialect, backend, or semantic cut.
Query only. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_DECISION_REASON_TOKENS = (
    "decision.subject-required",
    "decision.unknown-subject",
    "decision.unknown-reason",
    "decision.duplicate-identity",
    "decision.identity-mismatch",
)
_FLAG = "--print-q36-dectok"


def print_q36_dectok() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_decision

        tokens = record_decision.DECISION_REASON_TOKENS
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError):
        print("q36-dectok no")
        return 1
    if tokens != _DECISION_REASON_TOKENS:
        print("q36-dectok no")
        return 1
    print("q36-dectok gate=query")
    for token in tokens:
        print(f"decision-token {token}")
    print("q36-dectok yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q36_dectok: choose --print-q36-dectok",
            file=sys.stderr,
        )
        return 2
    return print_q36_dectok()


if __name__ == "__main__":
    sys.exit(main())
