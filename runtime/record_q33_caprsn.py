#!/usr/bin/env python3
"""Require the five capability reason tokens to stay in order.

Reads record_capability_applicability.CAPABILITY_REASON_TOKENS. The
tuple stays capability.present, capability.missing-evidence,
capability.not-applicable, capability.unknown-target, and
capability.unknown-kind. Query only. Does not add a predicate,
device, dialect, backend, or semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_CAPABILITY_REASON_TOKENS = (
    "capability.present",
    "capability.missing-evidence",
    "capability.not-applicable",
    "capability.unknown-target",
    "capability.unknown-kind",
)


def print_q33_caprsn() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_capability_applicability

        tokens = record_capability_applicability.CAPABILITY_REASON_TOKENS
    except (ImportError, AttributeError, OSError, SyntaxError):
        print("q33-caprsn no")
        return 1
    if tokens != _CAPABILITY_REASON_TOKENS:
        print("q33-caprsn no")
        return 1
    print("q33-caprsn gate=query")
    for token in tokens:
        print(f"capability-token {token}")
    print("q33-caprsn yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-q33-caprsn"]:
        print(
            "record_q33_caprsn: choose --print-q33-caprsn",
            file=sys.stderr,
        )
        return 2
    return print_q33_caprsn()


if __name__ == "__main__":
    sys.exit(main())
