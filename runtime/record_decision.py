#!/usr/bin/env python3
"""Stage A Evidence Algebra / Decision Model contract.

Occupancy kinds are not 6B Evidence DB identity E.
Decision is subject + result + typed reasons.
Reason tokens are closed namespaces (evidence / predicate /
decision); authorization.* is empty. Query only.
rewrite-license=no. Do not FileCheck microseconds.
"""

from __future__ import annotations

import argparse
import sys


def print_evidence_decision_contract() -> int:
    print("evidence-decision gate=query")
    print("schema s2c2.evidence_kind.v1")
    print("decision-schema s2c2.decision.v1")
    print("hb-source-is-semantic-truth yes")
    print("realization-ne-hb-change yes")
    print("unknown-ne-rewrite yes")
    print("evidence-ne-authorization yes")
    print("query-ne-rewrite yes")
    print("source-data-ne-restore-ordering yes")
    print("restore-ordering-ne-dest-invalidation yes")
    print("dest-invalidation-ne-sufficient yes")
    print("sufficient-ne-rewrite-license yes")
    print("evidence-kind-ne-6b-identity yes")
    print("usable-eq-source-data-and-restore-ordering yes")
    print("usable-ne-dest-invalidation yes")
    print("decision-has-subject yes")
    print("decision-subject usable")
    print("decision-result yes")
    print("usable-decision-ne-sufficient-decision yes")
    print("sufficiency-evaluation n/a")
    print("decision-ne-sufficient-and yes")
    print("capability-schedule-ne-god-object yes")
    print("rewrite-license no")
    print("rewrite-path no")
    print("note six-c-j-source-data-frozen")
    print("note six-c-k-restore-ordering-frozen")
    print("note six-c-l-dest-invalidation-frozen")
    print("note six-c-m-sufficient-parked")
    print("note dest-invalidation-is-kind-not-decision")
    print("note sufficient-decision-not-emitted")
    print("note live-bytes-not-opened")
    print("note alias-not-opened")
    print("note lifetime-not-opened")
    print("note restore-target-not-classified")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


EVIDENCE_REASON_TOKENS = (
    "evidence.unknown-witness",
    "evidence.scope-mismatch",
    "evidence.no-source-replica",
    "evidence.no-validity-witness",
    "evidence.no-ordering-witness",
    "evidence.no-invalidation-witness",
    "evidence.interval-does-not-cover",
    "evidence.not-before-consumer",
    "evidence.witnessed-unmutated-cover",
    "evidence.witnessed-before-consumer",
    "evidence.witnessed-drop-stale",
)

PREDICATE_REASON_TOKENS = (
    "predicate.missing-input",
    "predicate.source-data-present",
    "predicate.restore-ordering-present",
)

DECISION_REASON_TOKENS = (
    "decision.subject-required",
    "decision.unknown-subject",
    "decision.unknown-reason",
)

OCCUPANCY_PRINTER_MAP = (
    ("unknown-witness", "evidence.unknown-witness"),
    ("unknown-scope", "evidence.scope-mismatch"),
    ("replica-scope-mismatch", "evidence.scope-mismatch"),
    ("destination-scope-mismatch", "evidence.scope-mismatch"),
    ("no-source-replica", "evidence.no-source-replica"),
    ("no-validity-witness", "evidence.no-validity-witness"),
    ("no-ordering-witness", "evidence.no-ordering-witness"),
    ("no-invalidation-witness", "evidence.no-invalidation-witness"),
    ("interval-does-not-cover", "evidence.interval-does-not-cover"),
    ("not-before-consumer", "evidence.not-before-consumer"),
    ("witnessed-unmutated-cover", "evidence.witnessed-unmutated-cover"),
    ("witnessed-before-consumer", "evidence.witnessed-before-consumer"),
    ("witnessed-drop-stale", "evidence.witnessed-drop-stale"),
)


def _validate_reason_vocab() -> None:
    tokens = (
        EVIDENCE_REASON_TOKENS
        + PREDICATE_REASON_TOKENS
        + DECISION_REASON_TOKENS
    )
    if len(tokens) != len(set(tokens)):
        raise RuntimeError("duplicate reason token")
    for token in tokens:
        ns, _, local = token.partition(".")
        if ns not in ("evidence", "predicate", "decision"):
            raise RuntimeError(f"authorization or unknown namespace: {token}")
        if not local or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-" for c in local):
            raise RuntimeError(f"ill-formed local: {token}")
        if token.startswith("authorization."):
            raise RuntimeError(token)
    mapped = {algebra for _, algebra in OCCUPANCY_PRINTER_MAP}
    missing = mapped - set(EVIDENCE_REASON_TOKENS)
    if missing:
        raise RuntimeError(f"map target not in evidence.*: {sorted(missing)}")


def print_evidence_reason_vocab() -> int:
    _validate_reason_vocab()
    print("evidence-reason-vocab gate=query")
    print("schema s2c2.evidence_kind.v1")
    print("decision-schema s2c2.decision.v1")
    print("reason-grammar namespace.local")
    print("reason-namespace evidence")
    print("reason-namespace predicate")
    print("reason-namespace decision")
    print("reason-namespace authorization")
    print("authorization-tokens none")
    print("decision-subject usable")
    print("decision-has-subject yes")
    print("usable-decision-ne-sufficient-decision yes")
    print("sufficiency-evaluation n/a")
    print("ad-hoc-reason-forbidden yes")
    print("occupancy-printer-reasons-unchanged yes")
    print("capability-schedule-ne-god-object yes")
    for name in (
        "kind",
        "object",
        "witness",
        "scope",
        "applicability",
        "reason",
    ):
        print(f"evidence-field {name}")
    for name in ("subject", "result", "reasons"):
        print(f"decision-field {name}")
    for token in EVIDENCE_REASON_TOKENS:
        print(f"token {token}")
    for token in PREDICATE_REASON_TOKENS:
        print(f"token {token}")
    for token in DECISION_REASON_TOKENS:
        print(f"token {token}")
    for printer, algebra in OCCUPANCY_PRINTER_MAP:
        print(f"map {printer}={algebra}")
    print("rewrite-license no")
    print("rewrite-path no")
    print("note six-c-j-source-data-frozen")
    print("note six-c-k-restore-ordering-frozen")
    print("note six-c-l-dest-invalidation-frozen")
    print("note six-c-m-sufficient-parked")
    print("note authorization-namespace-closed")
    print("note sufficient-decision-not-emitted")
    print("note occupancy-printer-reasons-unchanged")
    print("note live-bytes-not-opened")
    print("note alias-not-opened")
    print("note lifetime-not-opened")
    print("note restore-target-not-classified")
    print("note evidence-db-identity-frozen")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Evidence / Decision (Stage A)")
    p.add_argument("--print-evidence-decision-contract", action="store_true")
    p.add_argument("--print-evidence-reason-vocab", action="store_true")
    args = p.parse_args(argv)
    if args.print_evidence_decision_contract and args.print_evidence_reason_vocab:
        print(
            "record_decision: choose one of "
            "--print-evidence-decision-contract "
            "--print-evidence-reason-vocab",
            file=sys.stderr,
        )
        return 2
    if args.print_evidence_decision_contract:
        return print_evidence_decision_contract()
    if args.print_evidence_reason_vocab:
        return print_evidence_reason_vocab()
    print(
        "record_decision: choose --print-evidence-decision-contract "
        "or --print-evidence-reason-vocab",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
