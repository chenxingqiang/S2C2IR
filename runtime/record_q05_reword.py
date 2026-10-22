#!/usr/bin/env python3
"""Print the six rewrite reason tokens as rewrite-token lines.

Query only. The tuple is record_storage_rewrite.REWRITE_REASON_TOKENS,
which stays the six rewrite reason tokens. This does not add a device,
predicate, dialect, backend, or semantic cut, and does not call
run_analyzer. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent

_REQUIRED = (
    "rewrite.license-no",
    "rewrite.identity-mismatch",
    "rewrite.sequence-mismatch",
    "rewrite.duplicate-envelope",
    "rewrite.duplicate-sequence",
    "rewrite.plan-closed",
)


def print_q05_reword() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_storage_rewrite

        tokens = record_storage_rewrite.REWRITE_REASON_TOKENS
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        print("q05-reword no")
        return 1
    if tokens != _REQUIRED:
        print("q05-reword no")
        return 1
    print("q05-reword gate=query")
    for token in tokens:
        print(f"rewrite-token {token}")
    print("q05-reword yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q05-reword"]:
        print(
            "record_q05_reword: choose --print-q05-reword",
            file=sys.stderr,
        )
        return 2
    return print_q05_reword()


if __name__ == "__main__":
    sys.exit(main())
