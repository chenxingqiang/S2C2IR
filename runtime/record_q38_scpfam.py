#!/usr/bin/env python3
"""Require the evidence scope-mismatch family and its displays.

Imports record_decision inside the query. SCOPE_FAMILY stays
evidence.scope-mismatch. SCOPE_DISPLAYS stays unknown-scope,
replica-scope-mismatch, and destination-scope-mismatch. Query only.
Does not call run_analyzer. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_SCOPE_FAMILY = "evidence.scope-mismatch"
_SCOPE_DISPLAYS = (
    "unknown-scope",
    "replica-scope-mismatch",
    "destination-scope-mismatch",
)


def print_q38_scpfam() -> int:
    try:
        if str(_RUNTIME) not in sys.path:
            sys.path.insert(0, str(_RUNTIME))
        import record_decision

        family = record_decision.SCOPE_FAMILY
        displays = record_decision.SCOPE_DISPLAYS
    except (ImportError, AttributeError):
        print("q38-scpfam no")
        return 1
    if family != _SCOPE_FAMILY or displays != _SCOPE_DISPLAYS:
        print("q38-scpfam no")
        return 1
    print("q38-scpfam gate=query")
    print(f"scope-family {family}")
    for display in displays:
        print(f"scope-display {display}")
    print("q38-scpfam yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q38-scpfam"]:
        print(
            "record_q38_scpfam: choose --print-q38-scpfam",
            file=sys.stderr,
        )
        return 2
    return print_q38_scpfam()


if __name__ == "__main__":
    sys.exit(main())
