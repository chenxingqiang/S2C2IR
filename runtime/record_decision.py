#!/usr/bin/env python3
"""Stage A Evidence Algebra / Decision Model contract.

Occupancy kinds are not 6B Evidence DB identity E.
Decision is subject + result + typed reasons.
Reason tokens are closed namespaces; authorization.* is empty.
EvidenceRecord adds identity, provenance, and canonical≠display.
Query only. rewrite-license=no. Do not FileCheck microseconds.
"""

from __future__ import annotations

import argparse
import json
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
    "decision.duplicate-identity",
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


SELECTED_S0 = "keep{0,1}|evict{2}|rematerialize{}"
SELECTED_S1 = "keep{1,2}|evict{0}|rematerialize{}"
USABLE_KINDS = ("source-data", "restore-ordering")

CANONICAL_FROM_DISPLAY = {
    "unknown-witness": "evidence.unknown-witness",
    "unknown-scope": "evidence.unknown-scope",
    "replica-scope-mismatch": "evidence.replica-scope-mismatch",
    "destination-scope-mismatch": "evidence.destination-scope-mismatch",
    "no-source-replica": "evidence.no-source-replica",
    "no-validity-witness": "evidence.no-validity-witness",
    "no-ordering-witness": "evidence.no-ordering-witness",
    "no-invalidation-witness": "evidence.no-invalidation-witness",
    "interval-does-not-cover": "evidence.interval-does-not-cover",
    "not-before-consumer": "evidence.not-before-consumer",
    "witnessed-unmutated-cover": "evidence.witnessed-unmutated-cover",
    "witnessed-before-consumer": "evidence.witnessed-before-consumer",
    "witnessed-drop-stale": "evidence.witnessed-drop-stale",
}

SCOPE_FAMILY = "evidence.scope-mismatch"
SCOPE_DISPLAYS = (
    "unknown-scope",
    "replica-scope-mismatch",
    "destination-scope-mismatch",
)


def _family_for_display(display: str) -> str:
    if display in SCOPE_DISPLAYS:
        return SCOPE_FAMILY
    return "n/a"


def evidence_record(
    *,
    kind: str,
    obj: str,
    applicability: str,
    display: str,
    witness: str,
    scope: str,
    provenance: str,
    selected: str = SELECTED_S0,
) -> dict:
    canonical = CANONICAL_FROM_DISPLAY[display]
    if canonical == SCOPE_FAMILY:
        raise RuntimeError("scope-mismatch is family, not canonical")
    if canonical == display:
        raise RuntimeError("canonical must differ from display")
    return {
        "schema": "s2c2.evidence_record.v1",
        "identity": {
            "selected": selected,
            "kind": kind,
            "object": obj,
        },
        "kind": kind,
        "object": obj,
        "witness": witness,
        "scope": scope,
        "applicability": applicability,
        "provenance": provenance,
        "reason": {
            "canonical": canonical,
            "display": display,
            "family": _family_for_display(display),
        },
    }


def derive_usable_decision(
    records: list[dict],
    selected: str,
    obj: str,
) -> dict:
    """Decision.subject=usable for one (selected, object) scope.

    Consumes 0 or 1 record per (selected, kind, object). Duplicate
    identity is safe no, not last-writer-wins. dest-invalidation is
    ignored for the predicate, but still counted for uniqueness.
    """
    scoped = [
        r
        for r in records
        if r["identity"]["selected"] == selected and r["identity"]["object"] == obj
    ]
    by_kind: dict[str, dict] = {}
    for rec in scoped:
        kind = rec["kind"]
        ident = (rec["identity"]["selected"], kind, rec["identity"]["object"])
        if ident[0] != selected or ident[2] != obj or ident[1] != kind:
            raise RuntimeError("identity fields disagree with record")
        if kind in by_kind:
            return {
                "schema": "s2c2.decision.v1",
                "subject": "usable",
                "result": "no",
                "reasons": ["decision.duplicate-identity"],
            }
        by_kind[kind] = rec
    sd = by_kind.get("source-data")
    ro = by_kind.get("restore-ordering")
    if sd is None or ro is None:
        return {
            "schema": "s2c2.decision.v1",
            "subject": "usable",
            "result": "no",
            "reasons": ["predicate.missing-input"],
        }
    if sd["applicability"] == "n/a" and ro["applicability"] == "n/a":
        return {
            "schema": "s2c2.decision.v1",
            "subject": "usable",
            "result": "n/a",
            "reasons": [],
        }
    if sd["applicability"] == "yes" and ro["applicability"] == "yes":
        return {
            "schema": "s2c2.decision.v1",
            "subject": "usable",
            "result": "yes",
            "reasons": [
                "predicate.source-data-present",
                "predicate.restore-ordering-present",
            ],
        }
    reasons: list[str] = []
    for rec in (sd, ro):
        if rec["applicability"] != "yes":
            canonical = rec["reason"]["canonical"]
            if canonical == SCOPE_FAMILY:
                raise RuntimeError("family token in Decision.reasons")
            reasons.append(canonical)
    if not reasons:
        reasons = ["predicate.missing-input"]
    return {
        "schema": "s2c2.decision.v1",
        "subject": "usable",
        "result": "no",
        "reasons": reasons,
    }


def _algebra_cases() -> list[tuple[str, list[dict]]]:
    yes_src = evidence_record(
        kind="source-data",
        obj="2",
        applicability="yes",
        display="witnessed-unmutated-cover",
        witness="spec-unmutated-cover",
        scope="occupancy-live",
        provenance="spec",
    )
    yes_ord = evidence_record(
        kind="restore-ordering",
        obj="2",
        applicability="yes",
        display="witnessed-before-consumer",
        witness="spec-before-consumer",
        scope="occupancy-live",
        provenance="spec",
    )
    yes_inv = evidence_record(
        kind="dest-invalidation",
        obj="2",
        applicability="yes",
        display="witnessed-drop-stale",
        witness="spec-drop-stale",
        scope="occupancy-live",
        provenance="spec",
    )
    unknown_scope_src = evidence_record(
        kind="source-data",
        obj="2",
        applicability="no",
        display="unknown-scope",
        witness="spec-unmutated-cover",
        scope="unknown",
        provenance="occupancy-query",
    )
    replica_src = evidence_record(
        kind="source-data",
        obj="2",
        applicability="no",
        display="replica-scope-mismatch",
        witness="spec-unmutated-cover",
        scope="occupancy-live",
        provenance="occupancy-query",
    )
    dest_mismatch = evidence_record(
        kind="dest-invalidation",
        obj="2",
        applicability="no",
        display="destination-scope-mismatch",
        witness="spec-drop-stale",
        scope="occupancy-live",
        provenance="occupancy-query",
    )
    unknown_witness_src = evidence_record(
        kind="source-data",
        obj="2",
        applicability="no",
        display="unknown-witness",
        witness="unknown",
        scope="occupancy-live",
        provenance="unknown",
    )
    no_ord = evidence_record(
        kind="restore-ordering",
        obj="2",
        applicability="no",
        display="no-ordering-witness",
        witness="n/a",
        scope="n/a",
        provenance="occupancy-query",
    )
    na_src = evidence_record(
        kind="source-data",
        obj="n/a",
        applicability="n/a",
        display="no-source-replica",
        witness="n/a",
        scope="n/a",
        provenance="occupancy-query",
        selected="n/a",
    )
    na_ord = evidence_record(
        kind="restore-ordering",
        obj="n/a",
        applicability="n/a",
        display="no-source-replica",
        witness="n/a",
        scope="n/a",
        provenance="occupancy-query",
        selected="n/a",
    )
    # n/a records still need a display token; no-source-replica is the
    # frozen 6C unused-path string. applicability=n/a so derivation
    # does not consume that canonical.
    s1_src_yes = evidence_record(
        kind="source-data",
        obj="2",
        applicability="yes",
        display="witnessed-unmutated-cover",
        witness="spec-unmutated-cover",
        scope="occupancy-live",
        provenance="spec",
        selected=SELECTED_S1,
    )
    s1_ord_yes = evidence_record(
        kind="restore-ordering",
        obj="2",
        applicability="yes",
        display="witnessed-before-consumer",
        witness="spec-before-consumer",
        scope="occupancy-live",
        provenance="spec",
        selected=SELECTED_S1,
    )
    obj3_src_yes = evidence_record(
        kind="source-data",
        obj="3",
        applicability="yes",
        display="witnessed-unmutated-cover",
        witness="spec-unmutated-cover",
        scope="occupancy-live",
        provenance="spec",
    )
    obj3_ord_yes = evidence_record(
        kind="restore-ordering",
        obj="3",
        applicability="yes",
        display="witnessed-before-consumer",
        witness="spec-before-consumer",
        scope="occupancy-live",
        provenance="spec",
    )
    dup_src_no = evidence_record(
        kind="source-data",
        obj="2",
        applicability="no",
        display="unknown-scope",
        witness="spec-unmutated-cover",
        scope="unknown",
        provenance="occupancy-query",
    )
    return [
        ("dest-inv-yes-usable-yes", [yes_src, yes_ord, yes_inv], SELECTED_S0, "2"),
        ("source-unknown-scope", [unknown_scope_src, no_ord], SELECTED_S0, "2"),
        ("replica-scope-mismatch", [replica_src, no_ord], SELECTED_S0, "2"),
        (
            "dest-scope-mismatch-usable-yes",
            [yes_src, yes_ord, dest_mismatch],
            SELECTED_S0,
            "2",
        ),
        ("missing-ordering", [yes_src], SELECTED_S0, "2"),
        ("unknown-witness", [unknown_witness_src, no_ord], SELECTED_S0, "2"),
        ("both-n/a", [na_src, na_ord], "n/a", "n/a"),
        (
            "ignore-other-selected",
            [yes_src, s1_src_yes, s1_ord_yes],
            SELECTED_S0,
            "2",
        ),
        (
            "ignore-other-object",
            [yes_src, obj3_src_yes, obj3_ord_yes],
            SELECTED_S0,
            "2",
        ),
        (
            "duplicate-identity",
            [dup_src_no, yes_src, yes_ord],
            SELECTED_S0,
            "2",
        ),
    ]


def _validate_algebra() -> None:
    _validate_reason_vocab()
    canons = set(CANONICAL_FROM_DISPLAY.values())
    if SCOPE_FAMILY in canons:
        raise RuntimeError("scope-mismatch must not be canonical")
    if len(canons) != len(CANONICAL_FROM_DISPLAY):
        raise RuntimeError("display→canonical must be injective")
    for display, canonical in CANONICAL_FROM_DISPLAY.items():
        if canonical == display:
            raise RuntimeError(display)
        if not canonical.startswith("evidence."):
            raise RuntimeError(canonical)
    seen = []
    for name, records, selected, obj in _algebra_cases():
        decision = derive_usable_decision(records, selected, obj)
        if decision["subject"] != "usable":
            raise RuntimeError(name)
        if SCOPE_FAMILY in decision["reasons"]:
            raise RuntimeError(f"family in reasons: {name}")
        for rec in records:
            if rec["reason"]["canonical"] == rec["reason"]["display"]:
                raise RuntimeError(name)
            if rec["reason"]["canonical"] == SCOPE_FAMILY:
                raise RuntimeError(name)
        dest_canons = {
            r["reason"]["canonical"]
            for r in records
            if r["kind"] == "dest-invalidation"
            and r["identity"]["selected"] == selected
            and r["identity"]["object"] == obj
        }
        if dest_canons & set(decision["reasons"]):
            raise RuntimeError(f"dest-invalidation in usable reasons: {name}")
        seen.append((name, decision["result"], tuple(decision["reasons"])))
    expect = {
        "dest-inv-yes-usable-yes": (
            "yes",
            (
                "predicate.source-data-present",
                "predicate.restore-ordering-present",
            ),
        ),
        "source-unknown-scope": (
            "no",
            ("evidence.unknown-scope", "evidence.no-ordering-witness"),
        ),
        "replica-scope-mismatch": (
            "no",
            (
                "evidence.replica-scope-mismatch",
                "evidence.no-ordering-witness",
            ),
        ),
        "dest-scope-mismatch-usable-yes": (
            "yes",
            (
                "predicate.source-data-present",
                "predicate.restore-ordering-present",
            ),
        ),
        "missing-ordering": ("no", ("predicate.missing-input",)),
        "unknown-witness": (
            "no",
            ("evidence.unknown-witness", "evidence.no-ordering-witness"),
        ),
        "both-n/a": ("n/a", ()),
        "ignore-other-selected": ("no", ("predicate.missing-input",)),
        "ignore-other-object": ("no", ("predicate.missing-input",)),
        "duplicate-identity": ("no", ("decision.duplicate-identity",)),
    }
    got = {name: (result, reasons) for name, result, reasons in seen}
    if got != expect:
        raise RuntimeError(f"algebra matrix drift: {got}")


def print_evidence_algebra_contract() -> int:
    _validate_algebra()
    print("evidence-algebra gate=query")
    print("schema s2c2.evidence_record.v1")
    print("kind-schema s2c2.evidence_kind.v1")
    print("decision-schema s2c2.decision.v1")
    print("er-identity-ne-6b-identity yes")
    print("canonical-ne-display yes")
    print("family-ne-canonical yes")
    print("scope-mismatch-is-family yes")
    print("decision-subject usable")
    print("derive-scope selected-object")
    print("identity-cardinality 0-or-1")
    print("duplicate-identity safe-no")
    print("derive-ignores dest-invalidation")
    print("usable-decision-ne-sufficient-decision yes")
    print("sufficiency-evaluation n/a")
    print("occupancy-printer-reasons-unchanged yes")
    print("capability-schedule-ne-god-object yes")
    print("ad-hoc-reason-forbidden yes")
    for name in (
        "identity",
        "kind",
        "object",
        "witness",
        "scope",
        "applicability",
        "provenance",
        "reason.canonical",
        "reason.display",
        "reason.family",
    ):
        print(f"record-field {name}")
    for name in ("selected", "kind", "object"):
        print(f"identity-field {name}")
    for name in ("spec", "occupancy-query", "unknown"):
        print(f"provenance {name}")
    print("canonical evidence.unknown-scope")
    print("canonical evidence.replica-scope-mismatch")
    print("canonical evidence.destination-scope-mismatch")
    print("map-canonical unknown-scope=evidence.unknown-scope")
    print("map-canonical replica-scope-mismatch=evidence.replica-scope-mismatch")
    print("map-canonical destination-scope-mismatch=evidence.destination-scope-mismatch")
    print("map-family unknown-scope=evidence.scope-mismatch")
    print("map-family replica-scope-mismatch=evidence.scope-mismatch")
    print("map-family destination-scope-mismatch=evidence.scope-mismatch")
    print("rewrite-license no")
    print("rewrite-path no")
    print("note six-c-j-source-data-frozen")
    print("note six-c-k-restore-ordering-frozen")
    print("note six-c-l-dest-invalidation-frozen")
    print("note six-c-m-sufficient-parked")
    print("note authorization-namespace-closed")
    print("note sufficient-decision-not-emitted")
    print("note occupancy-printer-reasons-unchanged")
    print("note family-not-decision-reason")
    print("note last-writer-wins-forbidden")
    print("note live-bytes-not-opened")
    print("note alias-not-opened")
    print("note lifetime-not-opened")
    print("note restore-target-not-classified")
    print("note evidence-db-identity-frozen")
    print("note rewrite=no")
    print("cost=unchanged")
    example = evidence_record(
        kind="source-data",
        obj="2",
        applicability="yes",
        display="witnessed-unmutated-cover",
        witness="spec-unmutated-cover",
        scope="occupancy-live",
        provenance="spec",
    )
    print("example " + json.dumps(example, separators=(",", ":"), sort_keys=True))
    return 0


def print_evidence_algebra_matrix() -> int:
    _validate_algebra()
    print("evidence-algebra-matrix gate=query")
    print("derive-subject usable")
    print("derive-scope selected-object")
    print("identity-cardinality 0-or-1")
    print("duplicate-identity safe-no")
    print("derive-ignores dest-invalidation")
    print("canonical-ne-display yes")
    print("scope-mismatch-is-family yes")
    for name, records, selected, obj in _algebra_cases():
        decision = derive_usable_decision(records, selected, obj)
        print(f"algebra-case {name}")
        print(f"algebra-scope selected={selected} object={obj}")
        for rec in records:
            reason = rec["reason"]
            ident = rec["identity"]
            print(
                "algebra-record "
                f"selected={ident['selected']} "
                f"object={ident['object']} "
                f"kind={rec['kind']} "
                f"applicability={rec['applicability']} "
                f"canonical={reason['canonical']} "
                f"display={reason['display']} "
                f"family={reason['family']} "
                f"provenance={rec['provenance']}"
            )
        reasons = ",".join(decision["reasons"]) if decision["reasons"] else "none"
        print(
            "algebra-decision "
            f"subject={decision['subject']} "
            f"result={decision['result']} "
            f"reasons={reasons}"
        )
    print("rewrite-license no")
    print("rewrite-path no")
    print("note sufficient-decision-not-emitted")
    print("note family-not-decision-reason")
    print("note last-writer-wins-forbidden")
    print("note occupancy-printer-reasons-unchanged")
    print("cost=unchanged")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Evidence / Decision (Stage A)")
    p.add_argument("--print-evidence-decision-contract", action="store_true")
    p.add_argument("--print-evidence-reason-vocab", action="store_true")
    p.add_argument("--print-evidence-algebra-contract", action="store_true")
    p.add_argument("--print-evidence-algebra-matrix", action="store_true")
    args = p.parse_args(argv)
    flags = (
        args.print_evidence_decision_contract,
        args.print_evidence_reason_vocab,
        args.print_evidence_algebra_contract,
        args.print_evidence_algebra_matrix,
    )
    if sum(bool(x) for x in flags) != 1:
        print(
            "record_decision: choose one of "
            "--print-evidence-decision-contract "
            "--print-evidence-reason-vocab "
            "--print-evidence-algebra-contract "
            "--print-evidence-algebra-matrix",
            file=sys.stderr,
        )
        return 2
    if args.print_evidence_decision_contract:
        return print_evidence_decision_contract()
    if args.print_evidence_reason_vocab:
        return print_evidence_reason_vocab()
    if args.print_evidence_algebra_contract:
        return print_evidence_algebra_contract()
    return print_evidence_algebra_matrix()


if __name__ == "__main__":
    sys.exit(main())
