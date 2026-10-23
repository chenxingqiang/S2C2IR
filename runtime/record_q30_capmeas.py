#!/usr/bin/env python3
"""Require the measured-capacity field names.

record_capacity.MEAS_CAP_FIELDS must be schema, profile, workload_class,
candidate_identity, measured_time_us, repetitions, correctness, source,
measured, and note, in that order. Query only. No semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_MEAS_CAP_FIELDS = (
    "schema",
    "profile",
    "workload_class",
    "candidate_identity",
    "measured_time_us",
    "repetitions",
    "correctness",
    "source",
    "measured",
    "note",
)


def _no() -> int:
    print("q30-capmeas no")
    return 1


def print_q30_capmeas() -> int:
    try:
        sys.path.insert(0, str(_RUNTIME))
        import record_capacity
    except (AttributeError, ImportError, OSError, SyntaxError, TypeError, ValueError):
        return _no()
    fields = getattr(record_capacity, "MEAS_CAP_FIELDS", None)
    if fields != _MEAS_CAP_FIELDS:
        return _no()
    print("q30-capmeas gate=query")
    for field in fields:
        print("meas-field " + field)
    print("q30-capmeas yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q30-capmeas"]:
        print(
            "record_q30_capmeas: choose --print-q30-capmeas",
            file=sys.stderr,
        )
        return 2
    return print_q30_capmeas()


if __name__ == "__main__":
    sys.exit(main())
