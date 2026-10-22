#!/usr/bin/env python3
"""Bind evidence, predicate, and decision reason tokens off authorization.

The closed collection is the tuple the algebra already checks:
EVIDENCE_REASON_TOKENS + PREDICATE_REASON_TOKENS + DECISION_REASON_TOKENS.
Query only. No semantic cut. can-run-plan stays no.
This printer does not add reason tokens.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

_PREFIXES = ("evidence.", "predicate.", "decision.")


def _no() -> int:
    print("evidence-reason-ns-bind no")
    return 1


def _closed_reason_tokens() -> tuple | None:
    """Evidence/predicate/decision tuple, or EVIDENCE_REASON_TOKENS alone."""
    import record_decision

    names = (
        "EVIDENCE_REASON_TOKENS",
        "PREDICATE_REASON_TOKENS",
        "DECISION_REASON_TOKENS",
    )
    parts: list[tuple] = []
    for name in names:
        if not hasattr(record_decision, name):
            continue
        part = getattr(record_decision, name)
        if type(part) is not tuple:
            return None
        parts.append(part)
    if not parts:
        return None
    tokens: list[str] = []
    for part in parts:
        tokens.extend(part)
    return tuple(tokens)


def _bound(tokens: tuple | None) -> bool:
    if type(tokens) is not tuple or len(tokens) == 0:
        return False
    for token in tokens:
        if type(token) is not str:
            return False
        if token.startswith("authorization"):
            return False
        if not token.startswith(_PREFIXES):
            return False
    return True


def print_evidence_reason_ns_bind() -> int:
    try:
        tokens = _closed_reason_tokens()
    except ImportError:
        return _no()
    if not _bound(tokens):
        return _no()
    count = len(tokens)
    print("evidence-reason-ns-bind gate=query")
    print(f"evidence-reason-count {count}")
    print("evidence-reason-ns-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Evidence reason namespace bind",
        add_help=False,
        allow_abbrev=False,
    )
    parser.add_argument("--print-evidence-reason-ns-bind", action="store_true")
    try:
        args, extra = parser.parse_known_args(argv)
    except SystemExit as exc:
        code = exc.code
        return code if isinstance(code, int) else 2
    if extra or not args.print_evidence_reason_ns_bind:
        print(
            "record_evidence_reason_ns_bind: choose --print-evidence-reason-ns-bind",
            file=sys.stderr,
        )
        return 2
    return print_evidence_reason_ns_bind()


if __name__ == "__main__":
    sys.exit(main())
