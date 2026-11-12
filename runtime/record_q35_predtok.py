#!/usr/bin/env python3
"""Print the three predicate reason tokens as predicate-token lines.

Reads record_decision.PREDICATE_REASON_TOKENS. The tuple must stay
exactly those three host tokens. Query only. Does not add a predicate,
device, dialect, backend, or semantic cut. Does not call run_analyzer.
can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_PREDICATE_REASON_TOKENS = (
    "predicate.missing-input",
    "predicate.source-data-present",
    "predicate.restore-ordering-present",
)


def print_q35_predtok() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_decision

        tokens = record_decision.PREDICATE_REASON_TOKENS
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError):
        print("q35-predtok no")
        return 1
    if tokens != _PREDICATE_REASON_TOKENS:
        print("q35-predtok no")
        return 1
    print("q35-predtok gate=query")
    for token in tokens:
        print(f"predicate-token {token}")
    print("q35-predtok yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q35-predtok"]:
        print(
            "record_q35_predtok: choose --print-q35-predtok",
            file=sys.stderr,
        )
        return 2
    return print_q35_predtok()


if __name__ == "__main__":
    sys.exit(main())
