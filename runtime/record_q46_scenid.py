#!/usr/bin/env python3
"""Require the acceptance scenario id and device.

Imports record_apply_scenario inside the query. SCENARIO_ID stays
w0-3-2-storage-capacity-001 and DEVICE stays D0. Query only. Does
not call run_analyzer. Does not add a predicate, device row, dialect,
backend, or semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_SCENARIO_ID = "w0-3-2-storage-capacity-001"
_DEVICE = "D0"


def print_q46_scenid() -> int:
    try:
        runtime = Path(__file__).resolve().parent
        if str(runtime) not in sys.path:
            sys.path.insert(0, str(runtime))
        import record_apply_scenario

        scenario_id = record_apply_scenario.SCENARIO_ID
        device = record_apply_scenario.DEVICE
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        print("q46-scenid no")
        return 1
    if scenario_id != _SCENARIO_ID or device != _DEVICE:
        print("q46-scenid no")
        return 1
    print("q46-scenid gate=query")
    print(f"scenario-id {scenario_id}")
    print(f"scenario-device {device}")
    print("q46-scenid yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q46-scenid"]:
        print(
            "record_q46_scenid: choose --print-q46-scenid",
            file=sys.stderr,
        )
        return 2
    return print_q46_scenid()


if __name__ == "__main__":
    sys.exit(main())
