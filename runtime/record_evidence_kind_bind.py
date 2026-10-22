#!/usr/bin/env python3
"""Bind the evidence kind, record, and database schema strings.

record_decision.EVIDENCE_KIND_SCHEMA, EVIDENCE_RECORD_SCHEMA, and
record_evidence.SCHEMA stay three different strings:
s2c2.evidence_kind.v1, s2c2.evidence_record.v1, and s2c2.evidence.v1.
Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

_KIND = "s2c2.evidence_kind.v1"
_RECORD = "s2c2.evidence_record.v1"
_EVIDENCE = "s2c2.evidence.v1"


def _no() -> int:
    print("evidence-kind-bind no")
    return 1


def print_evidence_kind_bind() -> int:
    try:
        import record_decision
        import record_evidence
    except ImportError:
        return _no()
    try:
        kind = record_decision.EVIDENCE_KIND_SCHEMA
        record = record_decision.EVIDENCE_RECORD_SCHEMA
        evidence = record_evidence.SCHEMA
    except AttributeError:
        return _no()
    if (
        type(kind) is not str
        or type(record) is not str
        or type(evidence) is not str
    ):
        return _no()
    if (kind, record, evidence) != (_KIND, _RECORD, _EVIDENCE):
        return _no()
    if len({kind, record, evidence}) != 3:
        return _no()
    print("evidence-kind-bind gate=query")
    print("kind-schema " + record_decision.EVIDENCE_KIND_SCHEMA)
    print("record-schema " + record_decision.EVIDENCE_RECORD_SCHEMA)
    print("evidence-schema " + record_evidence.SCHEMA)
    print("evidence-kind-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Evidence kind, record, and database schema bind",
        add_help=False,
        allow_abbrev=False,
    )
    parser.add_argument("--print-evidence-kind-bind", action="store_true")
    try:
        args, extra = parser.parse_known_args(argv)
    except SystemExit as exc:
        code = exc.code
        return code if isinstance(code, int) else 2
    if extra or not args.print_evidence_kind_bind:
        print(
            "record_evidence_kind_bind: choose --print-evidence-kind-bind",
            file=sys.stderr,
        )
        return 2
    return print_evidence_kind_bind()


if __name__ == "__main__":
    sys.exit(main())
