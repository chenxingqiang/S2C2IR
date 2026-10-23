#!/usr/bin/env python3
"""Require record_storage_apply.EMITTED_REASONS in fixed order.

Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent

_EMITTED_REASONS = (
    "decision.unknown-reason",
    "rewrite.identity-mismatch",
    "rewrite.sequence-mismatch",
    "rewrite.duplicate-envelope",
    "rewrite.license-no",
)


def _no() -> int:
    print("q04-emit no")
    return 1


def print_q04_emit() -> int:
    try:
        sys.path.insert(0, str(_RUNTIME))
        import record_storage_apply as apply
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        return _no()
    reasons = getattr(apply, "EMITTED_REASONS", None)
    if type(reasons) is not tuple or reasons != _EMITTED_REASONS:
        return _no()
    print("q04-emit gate=query")
    for token in reasons:
        print("emitted " + token)
    print("q04-emit yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q04-emit"]:
        print(
            "record_q04_emit: choose --print-q04-emit",
            file=sys.stderr,
        )
        return 2
    return print_q04_emit()


if __name__ == "__main__":
    sys.exit(main())
