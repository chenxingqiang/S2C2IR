#!/usr/bin/env python3
"""Require the closed evidence reason tokens.

Imports record_decision inside the query. Does not call run_analyzer.
Does not add a predicate, device, dialect, backend, or semantic cut.
Query only. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_EVIDENCE_REASON_TOKENS = (
    "evidence.unknown-witness",
    "evidence.scope-mismatch",
    "evidence.no-source-replica",
    "evidence.no-validity-witness",
    "evidence.no-ordering-witness",
    "evidence.no-invalidation-witness",
    "evidence.interval-does-not-cover",
    "evidence.not-before-consumer",
    "evidence.witnessed-unmutated-cover",
    "evidence.witnessed-before-consumer",
    "evidence.witnessed-drop-stale",
)
_FLAG = "--print-q34-evitok"


def print_q34_evitok() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_decision

        tokens = record_decision.EVIDENCE_REASON_TOKENS
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError):
        print("q34-evitok no")
        return 1
    if tokens != _EVIDENCE_REASON_TOKENS:
        print("q34-evitok no")
        return 1
    print("q34-evitok gate=query")
    for token in tokens:
        print(f"evidence-token {token}")
    print("q34-evitok yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q34_evitok: choose --print-q34-evitok",
            file=sys.stderr,
        )
        return 2
    return print_q34_evitok()


if __name__ == "__main__":
    sys.exit(main())
