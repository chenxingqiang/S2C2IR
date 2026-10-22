#!/usr/bin/env python3
"""Require the four profile constraint statuses.

Reads record_capability_profile.CONSTRAINT_STATUSES. Does not edit
the profile module or add statuses. No semantic cut.
can-run-plan stays no. Query only. Do not FileCheck microseconds.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))


def print_profile_status_bind() -> int:
    try:
        import record_capability_profile as prof

        statuses = prof.CONSTRAINT_STATUSES
        if (
            prof.CONSTRAINT_STATUSES
            != ("allowed", "forbidden", "not-applicable", "unproven")
            or len(prof.CONSTRAINT_STATUSES) != 4
        ):
            print("profile-status-bind no")
            return 1
    except (AttributeError, ImportError, TypeError, OSError, SyntaxError):
        print("profile-status-bind no")
        return 1
    print("gate=query")
    for status in statuses:
        print(f"constraint {status}")
    print("profile-status-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-profile-status-bind"]:
        print(
            "record_profile_status_bind: choose --print-profile-status-bind",
            file=sys.stderr,
        )
        return 2
    return print_profile_status_bind()


if __name__ == "__main__":
    sys.exit(main())
