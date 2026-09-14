#!/usr/bin/env python3
"""Stage A Evidence Algebra / Decision Model contract.

Occupancy kinds are not 6B Evidence DB identity E.
Decision is subject + result + typed reasons, not a giant
sufficient AND, and not an implicit sufficient=false.
Query only. rewrite-license=no. Do not FileCheck microseconds.
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


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Evidence / Decision (Stage A)")
    p.add_argument("--print-evidence-decision-contract", action="store_true")
    args = p.parse_args(argv)
    if not args.print_evidence_decision_contract:
        print(
            "record_decision: choose --print-evidence-decision-contract",
            file=sys.stderr,
        )
        return 2
    return print_evidence_decision_contract()


if __name__ == "__main__":
    sys.exit(main())
