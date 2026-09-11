#!/usr/bin/env python3
"""Phase 6C Capacity-aware Residency (6C-B–L frozen, 6C-M sufficient design).

Host witness for the sufficient query/proof contract.
sufficient ≠ usable ∧ dest-invalidation. restore-target is
defined, not classified. Still sufficient=no. The gate is
still no. Do not FileCheck microseconds.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

SCHEMA = "s2c2.capacity.v1"
PLAN_SCHEMA = "s2c2.capacity_plan.v1"
RESTORE_LEGAL = "TRANSFER,REMATERIALIZE"

SPEC_FIELDS = (
    "schema",
    "workload_class",
    "space",
    "capacity_tiles",
    "residencies",
    "note",
)
OPTIONAL_SPEC_FIELDS = (
    "restore_sources",
    "source_data",
    "restore_order",
    "dest_invalidation",
)
RESTORE_SRC_FIELDS = ("object", "space", "kind")
SOURCE_DATA_FIELDS = ("object", "replica", "witness", "live", "scope")
RESTORE_ORDER_FIELDS = ("object", "before", "witness", "scope")
DEST_INV_FIELDS = ("object", "destination", "witness", "scope")
SOURCE_WITNESS = "spec-unmutated-cover"
SOURCE_SCOPE = "occupancy-live"
ORDER_WITNESS = "spec-before-consumer"
ORDER_SCOPE = "occupancy-live"
DEST_WITNESS = "spec-drop-stale"
DEST_SCOPE = "occupancy-live"

RES_FIELDS = (
    "id",
    "object",
    "space",
    "size",
    "live",
    "producer",
    "consumer",
    "reuse_distance",
)


def print_contract() -> int:
    print("storage-capacity compiler-driven=yes")
    print("action KEEP|EVICT|REMATERIALIZE")
    print("restore-legal TRANSFER|REMATERIALIZE")
    print("note f-capacity-ne-f-program")
    print("note keep-ne-keep-residency")
    print("note capacity-exceeded-ne-must-evict")
    print("note evict-ne-rewrite")
    print("note transfer-existing-realization")
    print("note first-conflict-only")
    print("note single-evict-or-truncated")
    print("note restore-unspecified")
    print("note selection-ne-legality")
    print("note selection-ne-rewrite-license")
    print("note rewrite=no")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note evidence-db-identity-frozen")
    print("note five-e-not-opened")
    print("note measured-capacity-v1-not-opened")
    print("note not-new-capability-grid")
    print("note not-hardware-campaign")
    print("note stable-baseline")
    print("note six-c-design-this-cut")
    print("note six-c-diagnostics-frozen")
    print("note compiler-emits-f-capacity")
    print("note compiler-ne-rewrite")
    print("note tile-count-occupancy")
    print("note ir-discovery-ne-alias-analysis")
    print("note do-not-filecheck-microseconds")
    print("cost=unchanged")
    return 0


def print_plan_contract() -> int:
    print("capacity-plan compiler-visible=yes")
    print(f"schema {PLAN_SCHEMA}")
    print("selected none")
    print("policy none")
    print("rewrite-license no")
    print("note f-capacity-subseteq-f-residency")
    print("note selected-none")
    print("note policy-none")
    print("note rewrite-license-no")
    print("note compiler-visible-candidate-object")
    print("note six-c-b-diagnostics-frozen")
    print("note six-c-c-candidate-object-this-cut")
    print("note measured-capacity-v1-not-opened")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def print_query_contract() -> int:
    print("capacity-plan-query consumer-api=yes")
    print(f"schema {PLAN_SCHEMA}")
    print("selected none")
    print("policy none")
    print("rewrite-license no")
    print("note not-schedule-pass")
    print("note selected-none")
    print("note policy-none")
    print("note rewrite-license-no")
    print("note consumer-api")
    print("note six-c-b-diagnostics-frozen")
    print("note six-c-c-candidate-object-frozen")
    print("note six-c-d-query-this-cut")
    print("note measured-capacity-v1-not-opened")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def print_policy_contract() -> int:
    print("capacity-policy consumer=query")
    print("policy none|s0|measured-capacity-v1")
    print("s0 first(F_capacity)")
    print("selected-in-f-capacity yes")
    print("rewrite-license no")
    print("note selection-ne-rewrite-license")
    print("note s0-ne-must-evict")
    print("note truncated-ne-select")
    print("note measured-capacity-v1-ranking-only")
    print("note six-c-b-diagnostics-frozen")
    print("note six-c-c-candidate-object-frozen")
    print("note six-c-d-query-frozen")
    print("note six-c-e-selection-frozen")
    print("note six-c-f-measured-ranking-this-cut")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def print_measured_capacity_contract() -> int:
    print("measured-capacity-v1 ranking-only=yes")
    print("schema s2c2.measured_capacity_cost.v1")
    print("match profile,workload_class,candidate_identity")
    print("argmin scoped-measured-intersect-F")
    print("rewrite-license no")
    print("note measured-yes-and-correctness")
    print("note measured-needs-two-records")
    print("note measured-scope-profile-workload-candidate")
    print("note measured-ne-cross-profile")
    print("note measured-ne-cross-workload")
    print("note measured-ne-legality")
    print("note measured-ne-rewrite-license")
    print("note measured-does-not-expand-f")
    print("note measured-does-not-rank-truncated-F")
    print("note duplicate-measured-identity")
    print("note argmin-ties-earliest-F")
    print("note do-not-filecheck-microseconds")
    print("note not-hardware-campaign")
    print("note not-new-evidence-db")
    print("note six-c-e-selection-frozen")
    print("note six-c-f-measured-ranking-this-cut")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def print_license_contract() -> int:
    print("capacity-license gate=query")
    print("schema s2c2.capacity_license.v1")
    print("rewrite-license no")
    print("restore-legal TRANSFER|REMATERIALIZE")
    print("restore unspecified")
    print("rematerialize-empty yes")
    print("note selected-ne-rewrite-license")
    print("note evict-requires-restore")
    print("note restore-unspecified")
    print("note rematerialize-empty-this-stage")
    print("note transfer-existing-realization")
    print("note capability-license-ne-capacity-license")
    print("note measured-ne-rewrite-license")
    print("note six-c-f-measured-ranking-frozen")
    print("note six-c-g-license-gate-this-cut")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def _license_restore(selected: str) -> tuple[str, str]:
    if selected == "none":
        return "n/a", "n/a"
    if "|evict{}|" in selected:
        return "unused", "n/a"
    return "unspecified", "no"


def print_capacity_license(plan: dict[str, Any]) -> None:
    restore, closed = _license_restore(str(plan.get("selected") or "none"))
    print("capacity-license schema=s2c2.capacity_license.v1")
    print(
        f"capacity-license selected={plan['selected']} rewrite-license=no"
    )
    print(
        f"capacity-license restore={restore} "
        "restore-legal=TRANSFER|REMATERIALIZE "
        f"rematerialize-empty=yes evict-closed={closed}"
    )
    print("capacity-license note selected-ne-rewrite-license")
    print("capacity-license note evict-requires-restore")
    print("capacity-license note restore-unspecified")
    print("capacity-license note rematerialize-empty-this-stage")
    print("capacity-license note transfer-existing-realization")
    print("capacity-license note capability-license-ne-capacity-license")
    print("capacity-license note measured-ne-rewrite-license")
    print("capacity-license note six-c-g-license-gate-this-cut")
    print("capacity-license rewrite=no")


def print_restore_contract() -> int:
    print("capacity-restore candidate-semantics=yes")
    print("schema s2c2.capacity_restore.v1")
    print("kind TRANSFER")
    print("restore-legal TRANSFER|REMATERIALIZE")
    print("rewrite-license no")
    print("note restore-ne-identity-string")
    print("note transfer-existing-realization")
    print("note occupancy-ir-ne-restore-source")
    print("note closed-ne-rewrite-license")
    print("note rematerialize-empty-this-stage")
    print("note six-c-g-license-gate-frozen")
    print("note six-c-h-restore-closure-this-cut")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def print_capacity_restore(plan: dict[str, Any]) -> None:
    selected = str(plan.get("selected") or "none")
    sel = None
    if selected != "none":
        for c in plan.get("candidates") or []:
            if c.get("identity") == selected:
                sel = c
                break
    none = sel is None
    evict = list(sel.get("evict") or []) if sel else []
    restores = list(sel.get("restores") or []) if sel else []
    if none or not evict:
        closed = "n/a"
    else:
        all_valid = bool(restores) and len(restores) == len(evict)
        for r in restores:
            all_valid = all_valid and bool(r.get("valid"))
        closed = "yes" if all_valid else "no"
    print("capacity-restore schema=s2c2.capacity_restore.v1")
    print(f"capacity-restore selected={selected} closed={closed}")
    if sel is not None and not evict:
        print("capacity-restore restore=unused")
    if sel is not None and evict:
        for r in restores:
            valid = "yes" if r.get("valid") else "no"
            print(
                f"capacity-restore object={r['object']} kind={r['kind']} "
                f"valid={valid} reason={r['reason']}"
            )
    print("capacity-restore rewrite-license=no")
    print("capacity-restore note restore-ne-identity-string")
    print("capacity-restore note transfer-existing-realization")
    print("capacity-restore note occupancy-ir-ne-restore-source")
    print("capacity-restore note closed-ne-rewrite-license")
    print("capacity-restore note rematerialize-empty-this-stage")
    print("capacity-restore note six-c-g-license-gate-frozen")
    print("capacity-restore note six-c-h-restore-closure-this-cut")
    print("capacity-restore rewrite=no")


def print_predicate_contract() -> int:
    print("capacity-predicate gate=query")
    print("schema s2c2.capacity_predicate.v1")
    print("necessary selected-in-f,enumerated,capacity-proof,evict-closed,restore-kind")
    print("sufficient source-data,restore-ordering,dest-invalidation,rewrite-path")
    print("rewrite-license no")
    print("note necessary-ne-sufficient")
    print("note closed-ne-rewrite-license")
    print("note source-declaration-ne-data-validity")
    print("note restore-source-ne-ordering")
    print("note restore-source-ne-invalidation")
    print("note six-c-g-license-gate-frozen")
    print("note six-c-h-restore-closure-frozen")
    print("note six-c-i-license-predicate-this-cut")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def _source_data_status(sel: dict[str, Any] | None) -> str:
    if sel is None:
        return "n/a"
    evict = list(sel.get("evict") or [])
    if not evict:
        return "n/a"
    restores = list(sel.get("restores") or [])
    all_data = bool(restores) and len(restores) == len(evict)
    for r in restores:
        all_data = all_data and bool(r.get("source_data"))
    return "yes" if all_data else "no"


def print_capacity_predicate(plan: dict[str, Any]) -> None:
    selected = str(plan.get("selected") or "none")
    sel = None
    if selected != "none":
        for c in plan.get("candidates") or []:
            if c.get("identity") == selected:
                sel = c
                break
    in_f = sel is not None
    enumerated = bool(plan.get("enumerated")) and not bool(plan.get("truncated"))
    evict = list(sel.get("evict") or []) if sel else []
    restores = list(sel.get("restores") or []) if sel else []
    if sel is None or not evict:
        closed = "n/a"
    else:
        all_valid = bool(restores) and len(restores) == len(evict)
        for r in restores:
            all_valid = all_valid and bool(r.get("valid"))
        closed = "yes" if all_valid else "no"
    if sel is not None and not evict:
        restore_kind = "unused"
    elif sel is not None:
        restore_kind = "TRANSFER"
    else:
        restore_kind = "n/a"
    if in_f and enumerated:
        capacity_proof = "yes"
    elif in_f:
        capacity_proof = "no"
    else:
        capacity_proof = "n/a"
    if sel is not None and not evict:
        necessary = "n/a"
    elif (
        in_f
        and enumerated
        and closed == "yes"
        and restore_kind == "TRANSFER"
    ):
        necessary = "yes"
    else:
        necessary = "no"
    print("capacity-predicate schema=s2c2.capacity_predicate.v1")
    print(
        f"capacity-predicate selected={selected} necessary={necessary} "
        "sufficient=no rewrite-license=no"
    )
    print(
        f"capacity-predicate selected-in-f={'yes' if in_f else 'no'} "
        f"enumerated={'yes' if enumerated else 'no'} "
        f"capacity-proof={capacity_proof} evict-closed={closed} "
        f"restore-kind={restore_kind}"
    )
    print(
        f"capacity-predicate source-data={_source_data_status(sel)} "
        f"restore-ordering={_restore_ordering_status(sel)} "
        f"dest-invalidation={_dest_invalidation_status(sel)} "
        "rewrite-path=no"
    )
    print("capacity-predicate note necessary-ne-sufficient")
    print("capacity-predicate note closed-ne-rewrite-license")
    print("capacity-predicate note source-declaration-ne-data-validity")
    print("capacity-predicate note restore-source-ne-ordering")
    print("capacity-predicate note restore-source-ne-invalidation")
    print("capacity-predicate note six-c-g-license-gate-frozen")
    print("capacity-predicate note six-c-h-restore-closure-frozen")
    print("capacity-predicate note six-c-i-license-predicate-this-cut")
    print("capacity-predicate rewrite=no")


def print_sourcedata_contract() -> int:
    print("capacity-sourcedata gate=query")
    print("schema s2c2.capacity_sourcedata.v1")
    print("source-declaration-ne-data-validity yes")
    print("replica-exists-ne-data-validity yes")
    print("source-data-ne-usable yes")
    print("token-eq-validity-witness yes")
    print("no-validity-fsm yes")
    print("rewrite-license no")
    print("note replica-exists-ne-data-validity")
    print("note source-declaration-ne-data-validity")
    print("note source-data-ne-usable")
    print("note token-eq-validity-witness")
    print("note no-validity-fsm")
    print("note closed-ne-data-valid")
    print("note unknown-ne-rewrite")
    print("note source-data-ne-sufficient")
    print("note restore-source-ne-ordering")
    print("note restore-source-ne-invalidation")
    print("note six-c-g-license-gate-frozen")
    print("note six-c-h-restore-closure-frozen")
    print("note six-c-i-license-predicate-frozen")
    print("note six-c-j-source-data-this-cut")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def _replica_exists_status(sel: dict[str, Any] | None) -> str:
    if sel is None:
        return "n/a"
    evict = list(sel.get("evict") or [])
    if not evict:
        return "n/a"
    restores = list(sel.get("restores") or [])
    any_ex = False
    all_ex = bool(restores) and len(restores) == len(evict)
    for r in restores:
        exists = bool(r.get("replica_exists"))
        any_ex = any_ex or exists
        all_ex = all_ex and exists
    if all_ex:
        return "yes"
    if any_ex:
        return "mixed"
    return "no"


def _restore_ordering_status(sel: dict[str, Any] | None) -> str:
    if sel is None:
        return "n/a"
    evict = list(sel.get("evict") or [])
    if not evict:
        return "n/a"
    restores = list(sel.get("restores") or [])
    all_ord = bool(restores) and len(restores) == len(evict)
    for r in restores:
        all_ord = all_ord and bool(r.get("restore_ordering"))
    return "yes" if all_ord else "no"


def _usable_status(sel: dict[str, Any] | None) -> str:
    if sel is None:
        return "n/a"
    evict = list(sel.get("evict") or [])
    if not evict:
        return "n/a"
    restores = list(sel.get("restores") or [])
    all_u = bool(restores) and len(restores) == len(evict)
    for r in restores:
        all_u = all_u and bool(r.get("usable"))
    return "yes" if all_u else "no"


def _dest_invalidation_status(sel: dict[str, Any] | None) -> str:
    if sel is None:
        return "n/a"
    evict = list(sel.get("evict") or [])
    if not evict:
        return "n/a"
    restores = list(sel.get("restores") or [])
    all_d = bool(restores) and len(restores) == len(evict)
    for r in restores:
        all_d = all_d and bool(r.get("dest_invalidation"))
    return "yes" if all_d else "no"


def print_capacity_sourcedata(plan: dict[str, Any]) -> None:
    selected = str(plan.get("selected") or "none")
    sel = None
    if selected != "none":
        for c in plan.get("candidates") or []:
            if c.get("identity") == selected:
                sel = c
                break
    status = _source_data_status(sel)
    evict = list(sel.get("evict") or []) if sel else []
    restores = list(sel.get("restores") or []) if sel else []
    print("capacity-sourcedata schema=s2c2.capacity_sourcedata.v1")
    print(
        f"capacity-sourcedata selected={selected} source-data={status} "
        f"replica-exists={_replica_exists_status(sel)} "
        f"usable={_usable_status(sel)}"
    )
    if sel is not None and not evict:
        print("capacity-sourcedata restore=unused")
    if sel is not None and evict:
        for r in restores:
            print(
                f"capacity-sourcedata object={r['object']} "
                f"replica={r.get('replica', 'n/a')} "
                f"witness={r.get('witness', 'n/a')} "
                f"scope={r.get('scope', 'n/a')} "
                f"replica-exists={'yes' if r.get('replica_exists') else 'no'} "
                f"source-data={'yes' if r.get('source_data') else 'no'} "
                f"usable={'yes' if r.get('usable') else 'no'} "
                f"reason={r.get('source_data_reason')}"
            )
    print("capacity-sourcedata rewrite-license=no")
    print("capacity-sourcedata note replica-exists-ne-data-validity")
    print("capacity-sourcedata note source-declaration-ne-data-validity")
    print("capacity-sourcedata note source-data-ne-usable")
    print("capacity-sourcedata note token-eq-validity-witness")
    print("capacity-sourcedata note no-validity-fsm")
    print("capacity-sourcedata note closed-ne-data-valid")
    print("capacity-sourcedata note unknown-ne-rewrite")
    print("capacity-sourcedata note source-data-ne-sufficient")
    print("capacity-sourcedata note restore-source-ne-ordering")
    print("capacity-sourcedata note restore-source-ne-invalidation")
    print("capacity-sourcedata note six-c-g-license-gate-frozen")
    print("capacity-sourcedata note six-c-h-restore-closure-frozen")
    print("capacity-sourcedata note six-c-i-license-predicate-frozen")
    print("capacity-sourcedata note six-c-j-source-data-this-cut")
    print("capacity-sourcedata rewrite=no")


def print_ordering_contract() -> int:
    print("capacity-ordering gate=query")
    print("schema s2c2.capacity_ordering.v1")
    print("source-data-ne-ordering yes")
    print("source-valid-ne-restore-at-point yes")
    print("restore-ordering-ne-usable yes")
    print("rewrite-license no")
    print("note source-data-ne-ordering")
    print("note source-valid-ne-restore-at-point")
    print("note restore-ordering-ne-usable")
    print("note restore-ordering-ne-sufficient")
    print("note dest-invalidation-still-no")
    print("note unknown-ne-rewrite")
    print("note six-c-g-license-gate-frozen")
    print("note six-c-h-restore-closure-frozen")
    print("note six-c-i-license-predicate-frozen")
    print("note six-c-j-source-data-frozen")
    print("note six-c-k-restore-ordering-this-cut")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def print_capacity_ordering(plan: dict[str, Any]) -> None:
    selected = str(plan.get("selected") or "none")
    sel = None
    if selected != "none":
        for c in plan.get("candidates") or []:
            if c.get("identity") == selected:
                sel = c
                break
    evict = list(sel.get("evict") or []) if sel else []
    restores = list(sel.get("restores") or []) if sel else []
    print("capacity-ordering schema=s2c2.capacity_ordering.v1")
    print(
        f"capacity-ordering selected={selected} "
        f"restore-ordering={_restore_ordering_status(sel)} "
        f"usable={_usable_status(sel)}"
    )
    if sel is not None and not evict:
        print("capacity-ordering restore=unused")
    if sel is not None and evict:
        for r in restores:
            print(
                f"capacity-ordering object={r['object']} "
                f"before={r.get('order_before', 'n/a')} "
                f"witness={r.get('order_witness', 'n/a')} "
                f"scope={r.get('order_scope', 'n/a')} "
                f"restore-ordering={'yes' if r.get('restore_ordering') else 'no'} "
                f"usable={'yes' if r.get('usable') else 'no'} "
                f"reason={r.get('restore_ordering_reason')}"
            )
    print("capacity-ordering rewrite-license=no")
    print("capacity-ordering note source-data-ne-ordering")
    print("capacity-ordering note source-valid-ne-restore-at-point")
    print("capacity-ordering note restore-ordering-ne-usable")
    print("capacity-ordering note restore-ordering-ne-sufficient")
    print("capacity-ordering note dest-invalidation-still-no")
    print("capacity-ordering note unknown-ne-rewrite")
    print("capacity-ordering note six-c-g-license-gate-frozen")
    print("capacity-ordering note six-c-h-restore-closure-frozen")
    print("capacity-ordering note six-c-i-license-predicate-frozen")
    print("capacity-ordering note six-c-j-source-data-frozen")
    print("capacity-ordering note six-c-k-restore-ordering-this-cut")
    print("capacity-ordering rewrite=no")


def print_invalidation_contract() -> int:
    print("capacity-invalidation gate=query")
    print("schema s2c2.capacity_invalidation.v1")
    print("usable-ne-dest-invalidation yes")
    print("dest-invalidation-ne-sufficient yes")
    print("dest-invalidation-ne-rewrite-path yes")
    print("rewrite-license no")
    print("note usable-ne-dest-invalidation")
    print("note dest-invalidation-ne-sufficient")
    print("note dest-invalidation-ne-rewrite-path")
    print("note rewrite-path-still-no")
    print("note unknown-ne-rewrite")
    print("note six-c-g-license-gate-frozen")
    print("note six-c-h-restore-closure-frozen")
    print("note six-c-i-license-predicate-frozen")
    print("note six-c-j-source-data-frozen")
    print("note six-c-k-restore-ordering-frozen")
    print("note six-c-l-dest-invalidation-this-cut")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def print_sufficient_contract() -> int:
    print("capacity-sufficient gate=query")
    print("schema s2c2.capacity_sufficient.v1")
    print("usable-eq-source-data-and-restore-ordering yes")
    print("usable-ne-dest-invalidation yes")
    print("dest-invalidation-ne-sufficient yes")
    print("sufficient-eq-usable-and-dest-invalidation-and-restore-target yes")
    print("sufficient-ne-rewrite-license yes")
    print("sufficient-ne-rewrite-path yes")
    print("rewrite-license no")
    print("rewrite-path no")
    print("note usable-ne-dest-invalidation")
    print("note dest-invalidation-ne-sufficient")
    print("note restore-target-ne-rewrite")
    print("note unknown-ne-rewrite")
    print("note six-c-j-source-data-frozen")
    print("note six-c-k-restore-ordering-frozen")
    print("note six-c-l-dest-invalidation-frozen")
    print("note six-c-m-sufficient-design-this-cut")
    print("note restore-target-not-classified-this-cut")
    print("note sufficient-still-no")
    print("note rewrite-path-still-no")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note five-e-not-opened")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def print_capacity_invalidation(plan: dict[str, Any]) -> None:
    selected = str(plan.get("selected") or "none")
    sel = None
    if selected != "none":
        for c in plan.get("candidates") or []:
            if c.get("identity") == selected:
                sel = c
                break
    evict = list(sel.get("evict") or []) if sel else []
    restores = list(sel.get("restores") or []) if sel else []
    print("capacity-invalidation schema=s2c2.capacity_invalidation.v1")
    print(
        f"capacity-invalidation selected={selected} "
        f"dest-invalidation={_dest_invalidation_status(sel)} "
        f"usable={_usable_status(sel)}"
    )
    if sel is not None and not evict:
        print("capacity-invalidation restore=unused")
    if sel is not None and evict:
        for r in restores:
            print(
                f"capacity-invalidation object={r['object']} "
                f"destination={r.get('dest_space', 'n/a')} "
                f"witness={r.get('dest_witness', 'n/a')} "
                f"scope={r.get('dest_scope', 'n/a')} "
                f"dest-invalidation={'yes' if r.get('dest_invalidation') else 'no'} "
                f"usable={'yes' if r.get('usable') else 'no'} "
                f"reason={r.get('dest_invalidation_reason')}"
            )
    print("capacity-invalidation rewrite-license=no")
    print("capacity-invalidation note usable-ne-dest-invalidation")
    print("capacity-invalidation note dest-invalidation-ne-sufficient")
    print("capacity-invalidation note dest-invalidation-ne-rewrite-path")
    print("capacity-invalidation note rewrite-path-still-no")
    print("capacity-invalidation note unknown-ne-rewrite")
    print("capacity-invalidation note six-c-g-license-gate-frozen")
    print("capacity-invalidation note six-c-h-restore-closure-frozen")
    print("capacity-invalidation note six-c-i-license-predicate-frozen")
    print("capacity-invalidation note six-c-j-source-data-frozen")
    print("capacity-invalidation note six-c-k-restore-ordering-frozen")
    print("capacity-invalidation note six-c-l-dest-invalidation-this-cut")
    print("capacity-invalidation rewrite=no")


def capacity_candidate_identity(
    keep: list[str], evict: list[str], rematerialize: list[str] | None = None
) -> str:
    rematerialize = rematerialize or []
    return (
        f"keep{{{','.join(keep)}}}|"
        f"evict{{{','.join(evict)}}}|"
        f"rematerialize{{{','.join(rematerialize)}}}"
    )


def _tile_key(obj: str) -> str:
    if obj.startswith("tile") and obj[4:].isdigit():
        return obj[4:]
    return obj


def _load_spec(path: Path) -> dict[str, Any]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        obj = json.loads(line)
        if isinstance(obj, dict):
            rows.append(obj)
    if len(rows) != 1:
        raise ValueError("capacity spec must be exactly one JSONL row")
    spec = rows[0]
    if spec.get("schema") != SCHEMA:
        raise ValueError("bad schema")
    extra = sorted(set(spec) - set(SPEC_FIELDS) - set(OPTIONAL_SPEC_FIELDS))
    if extra:
        raise ValueError(f"extra keys {extra}")
    missing = [k for k in SPEC_FIELDS if k not in spec]
    if missing:
        raise ValueError(f"missing keys {missing}")
    residencies = spec["residencies"]
    if not isinstance(residencies, list) or not residencies:
        raise ValueError("residencies required")
    for rec in residencies:
        if not isinstance(rec, dict):
            raise ValueError("residency must be an object")
        extra_r = sorted(set(rec) - set(RES_FIELDS))
        if extra_r:
            raise ValueError(f"residency extra keys {extra_r}")
        missing_r = [k for k in RES_FIELDS if k not in rec]
        if missing_r:
            raise ValueError(f"residency missing keys {missing_r}")
        live = rec["live"]
        if (
            not isinstance(live, list)
            or len(live) != 2
            or int(live[0]) >= int(live[1])
        ):
            raise ValueError("live interval must be [start, end)")
        if rec.get("space") != spec["space"]:
            raise ValueError("residency space must match constrained space")
        if int(rec["size"]) <= 0:
            raise ValueError("size must be positive")
    try:
        cap = int(spec["capacity_tiles"])
    except (TypeError, ValueError) as exc:
        raise ValueError("capacity_tiles must be int") from exc
    if cap <= 0:
        raise ValueError("capacity_tiles must be positive")
    occupancy = {_tile_key(str(r["object"])) for r in residencies}
    raw_src = spec.get("restore_sources")
    if raw_src is not None:
        if not isinstance(raw_src, list):
            raise ValueError("restore_sources must be an array")
        seen_src: set[str] = set()
        for rec in raw_src:
            if not isinstance(rec, dict):
                raise ValueError("restore source must be an object")
            extra_s = sorted(set(rec) - set(RESTORE_SRC_FIELDS))
            if extra_s:
                raise ValueError(f"restore_sources extra keys {extra_s}")
            obj_n = rec.get("object")
            if not obj_n:
                raise ValueError("restore source object required")
            oid = _tile_key(str(obj_n))
            if oid not in occupancy:
                raise ValueError("restore source not in occupancy")
            space_s = rec.get("space")
            if space_s not in ("ssd", "host"):
                raise ValueError("restore source space must be ssd or host")
            kind = rec.get("kind", "TRANSFER")
            if kind != "TRANSFER":
                raise ValueError("restore kind must be TRANSFER")
            if oid in seen_src:
                raise ValueError("duplicate restore source")
            seen_src.add(oid)
    raw_data = spec.get("source_data")
    if raw_data is not None:
        if not isinstance(raw_data, list):
            raise ValueError("source_data must be an array")
        seen_data: set[str] = set()
        for rec in raw_data:
            if not isinstance(rec, dict):
                raise ValueError("source_data must be an object")
            extra_d = sorted(set(rec) - set(SOURCE_DATA_FIELDS))
            if extra_d:
                raise ValueError(f"source_data extra keys {extra_d}")
            obj_n = rec.get("object")
            if not obj_n:
                raise ValueError("source_data object required")
            oid = _tile_key(str(obj_n))
            if oid not in occupancy:
                raise ValueError("source_data not in occupancy")
            live = rec.get("live")
            replica = rec.get("replica")
            if replica not in ("ssd", "host"):
                raise ValueError("source_data replica must be ssd or host")
            if not rec.get("witness") or not rec.get("scope"):
                raise ValueError("source_data witness and scope required")
            if (
                not isinstance(live, list)
                or len(live) != 2
                or int(live[0]) >= int(live[1])
            ):
                raise ValueError("source_data live must be [start, end)")
            if oid in seen_data:
                raise ValueError("duplicate source_data")
            seen_data.add(oid)
    raw_order = spec.get("restore_order")
    if raw_order is not None:
        if not isinstance(raw_order, list):
            raise ValueError("restore_order must be an array")
        seen_order: set[str] = set()
        for rec in raw_order:
            if not isinstance(rec, dict):
                raise ValueError("restore_order must be an object")
            extra_o = sorted(set(rec) - set(RESTORE_ORDER_FIELDS))
            if extra_o:
                raise ValueError(f"restore_order extra keys {extra_o}")
            obj_n = rec.get("object")
            if not obj_n:
                raise ValueError("restore_order object required")
            oid = _tile_key(str(obj_n))
            if oid not in occupancy:
                raise ValueError("restore_order not in occupancy")
            if rec.get("before") is None:
                raise ValueError("restore_order before required")
            int(rec["before"])
            if not rec.get("witness") or not rec.get("scope"):
                raise ValueError("restore_order witness and scope required")
            if oid in seen_order:
                raise ValueError("duplicate restore_order")
            seen_order.add(oid)
    raw_dest = spec.get("dest_invalidation")
    if raw_dest is not None:
        if not isinstance(raw_dest, list):
            raise ValueError("dest_invalidation must be an array")
        seen_dest: set[str] = set()
        for rec in raw_dest:
            if not isinstance(rec, dict):
                raise ValueError("dest_invalidation must be an object")
            extra_d = sorted(set(rec) - set(DEST_INV_FIELDS))
            if extra_d:
                raise ValueError(f"dest_invalidation extra keys {extra_d}")
            obj_n = rec.get("object")
            if not obj_n:
                raise ValueError("dest_invalidation object required")
            oid = _tile_key(str(obj_n))
            if oid not in occupancy:
                raise ValueError("dest_invalidation not in occupancy")
            dest = rec.get("destination")
            if dest not in ("hbm", "ssd", "host"):
                raise ValueError("dest_invalidation destination must be hbm|ssd|host")
            if not rec.get("witness") or not rec.get("scope"):
                raise ValueError("dest_invalidation witness and scope required")
            if oid in seen_dest:
                raise ValueError("duplicate dest_invalidation")
            seen_dest.add(oid)
    return spec


def _live_at(residencies: list[dict[str, Any]], t: int) -> list[dict[str, Any]]:
    out = []
    for rec in residencies:
        start, end = int(rec["live"][0]), int(rec["live"][1])
        if start <= t < end:
            out.append(rec)
    return out


def _live_sum(live: list[dict[str, Any]]) -> int:
    return sum(int(r["size"]) for r in live)


def _object_id(rec: dict[str, Any]) -> str:
    return _tile_key(str(rec["object"]))


def _restore_sources(spec: dict[str, Any]) -> dict[str, str]:
    raw = spec.get("restore_sources") or []
    out: dict[str, str] = {}
    for rec in raw:
        out[_tile_key(str(rec["object"]))] = str(rec["space"])
    return out


def _occ_live(spec: dict[str, Any]) -> dict[str, tuple[int, int]]:
    out: dict[str, tuple[int, int]] = {}
    for rec in spec["residencies"]:
        oid = _object_id(rec)
        live = rec["live"]
        out[oid] = (int(live[0]), int(live[1]))
    return out


def _source_data_proofs(spec: dict[str, Any]) -> dict[str, dict[str, Any]]:
    raw = spec.get("source_data") or []
    out: dict[str, dict[str, Any]] = {}
    for rec in raw:
        oid = _tile_key(str(rec["object"]))
        live = rec["live"]
        out[oid] = {
            "replica": str(rec["replica"]),
            "witness": str(rec["witness"]),
            "scope": str(rec["scope"]),
            "start": int(live[0]),
            "end": int(live[1]),
        }
    return out


def _restore_order_proofs(spec: dict[str, Any]) -> dict[str, dict[str, Any]]:
    raw = spec.get("restore_order") or []
    out: dict[str, dict[str, Any]] = {}
    for rec in raw:
        oid = _tile_key(str(rec["object"]))
        out[oid] = {
            "before": int(rec["before"]),
            "witness": str(rec["witness"]),
            "scope": str(rec["scope"]),
        }
    return out


def _dest_inv_proofs(spec: dict[str, Any]) -> dict[str, dict[str, Any]]:
    raw = spec.get("dest_invalidation") or []
    out: dict[str, dict[str, Any]] = {}
    for rec in raw:
        oid = _tile_key(str(rec["object"]))
        out[oid] = {
            "destination": str(rec["destination"]),
            "witness": str(rec["witness"]),
            "scope": str(rec["scope"]),
        }
    return out


def _attach_restores(
    evict: list[str],
    sources: dict[str, str],
    occ_live: dict[str, tuple[int, int]],
    proofs: dict[str, dict[str, Any]],
    order_proofs: dict[str, dict[str, Any]],
    dest_proofs: dict[str, dict[str, Any]],
    occ_space: str,
) -> list[dict[str, Any]]:
    restores = []
    for e in evict:
        replica_exists = e in sources
        replica = sources[e] if replica_exists else "n/a"
        witness = "n/a"
        scope = "n/a"
        source_data = False
        restore_ordering = False
        dest_invalidation = False
        order_before = "n/a"
        order_witness = "n/a"
        order_scope = "n/a"
        dest_space = "n/a"
        dest_witness = "n/a"
        dest_scope = "n/a"
        if not replica_exists:
            source_data_reason = "no-source-replica"
            restore_ordering_reason = "no-source-replica"
            dest_invalidation_reason = "no-source-replica"
        else:
            proof = proofs.get(e)
            if proof is None:
                source_data_reason = "no-validity-witness"
            else:
                witness = proof["witness"]
                scope = proof["scope"]
                if proof["replica"] != replica:
                    source_data_reason = "replica-scope-mismatch"
                elif proof["witness"] != SOURCE_WITNESS:
                    source_data_reason = "unknown-witness"
                elif proof["scope"] != SOURCE_SCOPE:
                    source_data_reason = "unknown-scope"
                else:
                    occ = occ_live.get(e)
                    if (
                        occ is None
                        or proof["start"] > occ[0]
                        or proof["end"] < occ[1]
                    ):
                        source_data_reason = "interval-does-not-cover"
                    else:
                        source_data = True
                        source_data_reason = "witnessed-unmutated-cover"
            order = order_proofs.get(e)
            if order is None:
                restore_ordering_reason = "no-ordering-witness"
            else:
                order_before = str(order["before"])
                order_witness = order["witness"]
                order_scope = order["scope"]
                if order["witness"] != ORDER_WITNESS:
                    restore_ordering_reason = "unknown-witness"
                elif order["scope"] != ORDER_SCOPE:
                    restore_ordering_reason = "unknown-scope"
                else:
                    occ = occ_live.get(e)
                    if occ is None or order["before"] != occ[1]:
                        restore_ordering_reason = "not-before-consumer"
                    else:
                        restore_ordering = True
                        restore_ordering_reason = "witnessed-before-consumer"
            dest = dest_proofs.get(e)
            if dest is None:
                dest_invalidation_reason = "no-invalidation-witness"
            else:
                dest_space = dest["destination"]
                dest_witness = dest["witness"]
                dest_scope = dest["scope"]
                if dest["destination"] != occ_space:
                    dest_invalidation_reason = "destination-scope-mismatch"
                elif dest["witness"] != DEST_WITNESS:
                    dest_invalidation_reason = "unknown-witness"
                elif dest["scope"] != DEST_SCOPE:
                    dest_invalidation_reason = "unknown-scope"
                else:
                    dest_invalidation = True
                    dest_invalidation_reason = "witnessed-drop-stale"
        restores.append(
            {
                "object": e,
                "kind": "TRANSFER",
                "valid": replica_exists,
                "reason": (
                    "has-source-replica" if replica_exists else "no-source-replica"
                ),
                "replica_exists": replica_exists,
                "replica": replica,
                "witness": witness,
                "scope": scope,
                "source_data": source_data,
                "source_data_reason": source_data_reason,
                "restore_ordering": restore_ordering,
                "restore_ordering_reason": restore_ordering_reason,
                "order_before": order_before,
                "order_witness": order_witness,
                "order_scope": order_scope,
                "dest_invalidation": dest_invalidation,
                "dest_invalidation_reason": dest_invalidation_reason,
                "dest_space": dest_space,
                "dest_witness": dest_witness,
                "dest_scope": dest_scope,
                "usable": source_data and restore_ordering,
            }
        )
    return restores


def _enumerate_capacity(spec: dict[str, Any]) -> dict[str, Any]:
    residencies = spec["residencies"]
    cap = int(spec["capacity_tiles"])
    times = sorted({int(r["live"][0]) for r in residencies})
    peak = 0
    t_star: int | None = None
    live_star: list[dict[str, Any]] = []
    for t in times:
        live = _live_at(residencies, t)
        occ = _live_sum(live)
        if occ > peak:
            peak = occ
        if occ > cap and t_star is None:
            t_star = t
            live_star = live
    conflict = t_star is not None
    candidates: list[tuple[str, list[str], list[str]]] = []
    truncated = False
    if not conflict:
        keep = [_object_id(r) for r in sorted(residencies, key=_object_id)]
        candidates.append(("KEEP", keep, []))
    else:
        occ = _live_sum(live_star)
        incoming = max(live_star, key=lambda r: (int(r["live"][0]), _object_id(r)))
        order = [incoming] + sorted(
            [r for r in live_star if r is not incoming],
            key=_object_id,
        )
        for rec in order:
            if occ - int(rec["size"]) > cap:
                truncated = True
                candidates = []
                break
            evict = [_object_id(rec)]
            keep = sorted(_object_id(r) for r in live_star if r is not rec)
            candidates.append(("EVICT", keep, evict))
    objects = {_object_id(r) for r in residencies}
    return {
        "space": spec["space"],
        "capacity": cap,
        "peak": peak,
        "conflict": conflict,
        "truncated": truncated,
        "candidates": candidates,
        "objects": objects,
    }


def _build_capacity_plan(spec: dict[str, Any]) -> dict[str, Any]:
    enum = _enumerate_capacity(spec)
    objects: set[str] = enum["objects"]
    sources = _restore_sources(spec)
    occ_live = _occ_live(spec)
    proofs = _source_data_proofs(spec)
    order_proofs = _restore_order_proofs(spec)
    dest_proofs = _dest_inv_proofs(spec)
    occ_space = str(spec["space"])
    plan_cands = []
    if not enum["truncated"]:
        seen = set()
        for i, (_action, keep, evict) in enumerate(enum["candidates"]):
            rematerialize: list[str] = []
            used = set(keep)
            for k in keep:
                if k not in objects:
                    raise ValueError("keep id not in residency")
            for e in evict:
                if e not in objects:
                    raise ValueError("evict id not in residency")
                if e in used:
                    raise ValueError("keep/evict overlap")
            ident = capacity_candidate_identity(keep, evict, rematerialize)
            if ident in seen:
                raise ValueError("duplicate identity")
            seen.add(ident)
            plan_cands.append(
                {
                    "id": i,
                    "identity": ident,
                    "keep": keep,
                    "evict": evict,
                    "rematerialize": rematerialize,
                    "restores": _attach_restores(
                        evict,
                        sources,
                        occ_live,
                        proofs,
                        order_proofs,
                        dest_proofs,
                        occ_space,
                    ),
                }
            )
    return {
        "schema": PLAN_SCHEMA,
        "space": enum["space"],
        "capacity": enum["capacity"],
        "peak_live": enum["peak"],
        "feasible": bool(plan_cands),
        "enumerated": not enum["truncated"],
        "truncated": enum["truncated"],
        "selected": "none",
        "policy": "none",
        "rewrite": "no",
        "rewrite_license": "no",
        "subseteq_residency": True,
        "candidates": plan_cands,
    }


def analyze_capacity(path: Path) -> int:
    try:
        spec = _load_spec(path)
    except (ValueError, json.JSONDecodeError) as exc:
        print(f"record_capacity: {exc}", file=sys.stderr)
        return 4
    enum = _enumerate_capacity(spec)
    cap = enum["capacity"]
    peak = enum["peak"]
    conflict = enum["conflict"]
    truncated = enum["truncated"]
    candidates = enum["candidates"]
    print("storage-capacity query=f-capacity")
    print(f"storage-capacity space={spec['space']} capacity={cap} peak-live={peak}")
    print(f"storage-capacity capacity-conflict={'yes' if conflict else 'no'}")
    if truncated:
        print("storage-capacity enumerated=no truncated=yes legal=not-enumerated")
        print("storage-capacity candidate-count=0")
    else:
        print(
            "storage-capacity enumerated=yes truncated=no "
            f"legal={len(candidates)}"
        )
        print(f"storage-capacity candidate-count={len(candidates)}")
        for i, (action, keep, evict) in enumerate(candidates):
            keep_s = ",".join(keep)
            if evict:
                evict_s = ",".join(evict)
                print(
                    f"storage-capacity candidate #{i} keep={keep_s} "
                    f"evict={evict_s} action={action} "
                    f"restore-legal={RESTORE_LEGAL} restore=unspecified"
                )
            else:
                print(
                    f"storage-capacity candidate #{i} keep={keep_s} "
                    f"action={action} restore=unspecified"
                )
    print("storage-capacity rewrite=no")
    print("storage-capacity note f-capacity-ne-f-program")
    print("storage-capacity note capacity-exceeded-ne-must-evict")
    print("storage-capacity note evict-ne-rewrite")
    print("storage-capacity note selection-ne-rewrite-license")
    print("storage-capacity note measured-capacity-v1-not-opened")
    print("storage-capacity note six-c-design-this-cut")
    print("storage-capacity note six-c-diagnostics-frozen")
    print("storage-capacity note tile-count-occupancy")
    print("cost=unchanged")
    return 0


def analyze_capacity_plan(path: Path) -> int:
    try:
        spec = _load_spec(path)
        plan = _build_capacity_plan(spec)
    except (ValueError, json.JSONDecodeError) as exc:
        print(f"record_capacity: {exc}", file=sys.stderr)
        return 4
    print(f"capacity-plan schema={plan['schema']}")
    print(
        f"capacity-plan space={plan['space']} capacity={plan['capacity']} "
        f"peak-live={plan['peak_live']}"
    )
    legal = (
        "not-enumerated"
        if plan["truncated"]
        else str(len(plan["candidates"]))
    )
    print(
        f"capacity-plan feasible={'yes' if plan['feasible'] else 'no'} "
        f"enumerated={'yes' if plan['enumerated'] else 'no'} "
        f"truncated={'yes' if plan['truncated'] else 'no'} legal={legal}"
    )
    print("capacity-plan selected=none policy=none rewrite-license=no")
    if not plan["truncated"]:
        for c in plan["candidates"]:
            keep_s = ",".join(c["keep"])
            evict_s = ",".join(c["evict"])
            remat_s = ",".join(c["rematerialize"])
            print(
                f"capacity-plan candidate #{c['id']} identity={c['identity']} "
                f"keep={keep_s} evict={evict_s} rematerialize={remat_s}"
            )
    print("capacity-plan subseteq-residency=yes")
    print("capacity-plan rewrite=no")
    print("capacity-plan note f-capacity-subseteq-f-residency")
    print("capacity-plan note selected-none")
    print("capacity-plan note policy-none")
    print("capacity-plan note rewrite-license-no")
    print("capacity-plan note compiler-visible-candidate-object")
    print("capacity-plan note six-c-b-diagnostics-frozen")
    print("capacity-plan note six-c-c-candidate-object-this-cut")
    print("cost=unchanged")
    return 0


MEAS_CAP_SCHEMA = "s2c2.measured_capacity_cost.v1"
MEAS_CAP_FIELDS = (
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


def apply_capacity_policy(
    plan: dict[str, Any],
    policy: str,
    table_path: Path | None = None,
    profile: str = "",
    workload: str = "",
) -> dict[str, Any]:
    name = (policy or "none").strip().lower()
    if name in ("", "none"):
        return plan
    if plan["truncated"] or not plan["enumerated"]:
        raise ValueError("truncated plan cannot be selected")
    if not plan["candidates"]:
        raise ValueError("empty F_capacity cannot be selected")
    if name == "s0":
        out = dict(plan)
        out["policy"] = "s0"
        out["selected"] = plan["candidates"][0]["identity"]
        return out
    if name in ("measured-capacity-v1", "measured"):
        if table_path is None:
            raise ValueError(
                "--capacity-policy=measured-capacity-v1 requires "
                "--measured-capacity-table"
            )
        if not profile:
            raise ValueError(
                "--capacity-policy=measured-capacity-v1 requires --profile"
            )
        if not workload:
            raise ValueError(
                "--capacity-policy=measured-capacity-v1 requires workload_class"
            )
        return rank_measured_capacity(plan, table_path, profile, workload)
    raise ValueError(f"unknown --capacity-policy={policy}")


def _load_measured_capacity_table(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str]] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        obj = json.loads(line)
        if not isinstance(obj, dict):
            raise ValueError("invalid JSONL")
        extra = sorted(set(obj) - set(MEAS_CAP_FIELDS))
        if extra:
            raise ValueError("extra keys")
        if obj.get("schema") != MEAS_CAP_SCHEMA:
            raise ValueError("bad schema")
        ident = obj.get("candidate_identity")
        if not ident:
            raise ValueError("candidate_identity required")
        if not obj.get("profile") or not obj.get("workload_class"):
            raise ValueError("profile and workload_class required")
        key = (
            str(obj.get("profile") or ""),
            str(obj.get("workload_class") or ""),
            str(ident),
        )
        if key in seen:
            raise ValueError("duplicate-measured-identity")
        seen.add(key)
        rows.append(obj)
    return rows


def rank_measured_capacity(
    plan: dict[str, Any],
    table_path: Path,
    profile: str,
    workload: str,
) -> dict[str, Any]:
    legal = {c["identity"] for c in plan["candidates"]}
    us: dict[str, int] = {}
    for rec in _load_measured_capacity_table(table_path):
        if rec.get("profile") != profile or rec.get("workload_class") != workload:
            continue
        ident = rec["candidate_identity"]
        if ident not in legal:
            continue
        measured = str(rec.get("measured") or "no").lower()
        correctness = int(rec.get("correctness") or 0)
        if measured != "yes" or correctness != 1:
            continue
        if ident in us:
            raise ValueError("duplicate-measured-identity")
        us[ident] = int(rec["measured_time_us"])
    if len(us) < 2:
        raise ValueError("measured-needs-two-records")
    best = None
    argmin: list[dict[str, Any]] = []
    for c in plan["candidates"]:
        ident = c["identity"]
        if ident not in us:
            continue
        t = us[ident]
        if best is None or t < best:
            best = t
            argmin = [c]
        elif t == best:
            argmin.append(c)
    pick = argmin[0]
    out = dict(plan)
    out["policy"] = "measured-capacity-v1"
    out["selected"] = pick["identity"]
    out["_measured_count"] = len(us)
    out["_argmin_size"] = len(argmin)
    out["_coincide_s0"] = pick["identity"] == plan["candidates"][0]["identity"]
    out["_evidence"] = {c["identity"]: c["identity"] in us for c in plan["candidates"]}
    out["_profile"] = profile
    out["_workload"] = workload
    return out


def query_capacity_plan(
    path: Path,
    policy: str = "",
    table_path: Path | None = None,
    profile: str = "",
) -> int:
    try:
        spec = _load_spec(path)
        plan = apply_capacity_policy(
            _build_capacity_plan(spec),
            policy,
            table_path,
            profile,
            str(spec.get("workload_class") or ""),
        )
    except (ValueError, json.JSONDecodeError) as exc:
        print(f"record_capacity: {exc}", file=sys.stderr)
        return 4
    prefix = "capacity-plan-query"
    print(f"{prefix} schema={plan['schema']}")
    print(
        f"{prefix} space={plan['space']} capacity={plan['capacity']} "
        f"peak-live={plan['peak_live']}"
    )
    legal = (
        "not-enumerated"
        if plan["truncated"]
        else str(len(plan["candidates"]))
    )
    print(
        f"{prefix} feasible={'yes' if plan['feasible'] else 'no'} "
        f"enumerated={'yes' if plan['enumerated'] else 'no'} "
        f"truncated={'yes' if plan['truncated'] else 'no'} legal={legal}"
    )
    print(
        f"{prefix} selected={plan['selected']} policy={plan['policy']} "
        "rewrite-license=no"
    )
    if not plan["truncated"]:
        for c in plan["candidates"]:
            print(f"{prefix} candidate #{c['id']} identity={c['identity']}")
    dump = {k: v for k, v in plan.items() if not k.startswith("_")}
    print(f"{prefix} {json.dumps(dump, separators=(',', ':'))}")
    print(f"{prefix} rewrite=no")
    print(f"{prefix} note not-schedule-pass")
    if plan["selected"] == "none":
        print(f"{prefix} note selected-none")
    else:
        print(f"{prefix} note selected-in-f-capacity")
    print(f"{prefix} note rewrite-license-no")
    print(f"{prefix} note consumer-api")
    if plan["policy"] == "s0":
        print(f"{prefix} note s0-ne-must-evict")
        print(
            "capacity-policy name=s0 "
            f"selected={plan['selected']} applicable=yes source=s0 "
            "rewrite=no rewrite-license=no"
        )
        print("capacity-policy note selection-ne-rewrite-license")
        print("capacity-policy note s0-ne-must-evict")
        print(f"{prefix} note measured-capacity-v1-not-opened")
        print(f"{prefix} note six-c-e-selection-this-cut")
    elif plan["policy"] == "measured-capacity-v1":
        print(f"{prefix} note measured-capacity-v1-ranking-only")
        print(f"{prefix} note measured-ne-rewrite-license")
        print(f"{prefix} note do-not-filecheck-microseconds")
        coincide = "yes" if plan["_coincide_s0"] else "no"
        print(
            "capacity-measured ranked="
            f"{plan['selected']} policy=measured-capacity-v1 "
            f"measured-count={plan['_measured_count']} "
            f"argmin-size={plan['_argmin_size']} coincide-s0={coincide} "
            f"profile={plan['_profile']} workload={plan['_workload']} "
            "rewrite=no rewrite-license=no"
        )
        print("capacity-measured note measured-does-not-expand-f")
        print("capacity-measured note measured-scope-profile-workload-candidate")
        print("capacity-measured note measured-ne-cross-profile")
        print("capacity-measured note measured-ne-cross-workload")
        print("capacity-measured note duplicate-measured-identity")
        print("capacity-measured note argmin-ties-earliest-F")
        for c in plan["candidates"]:
            ev = "yes" if plan["_evidence"].get(c["identity"]) else "no"
            print(
                f"capacity-measured-candidate identity={c['identity']} "
                f"evidence={ev}"
            )
        print(
            "capacity-policy name=measured-capacity-v1 "
            f"selected={plan['selected']} applicable=yes "
            "source=measured-capacity-v1 rewrite=no rewrite-license=no"
        )
        print(f"{prefix} note six-c-f-measured-ranking-this-cut")
    else:
        print(f"{prefix} note measured-capacity-v1-not-opened")
        print(f"{prefix} note six-c-d-query-this-cut")
    print_capacity_license(plan)
    print_capacity_restore(plan)
    print_capacity_predicate(plan)
    print_capacity_sourcedata(plan)
    print_capacity_ordering(plan)
    print_capacity_invalidation(plan)
    print("cost=unchanged")
    return 0


def dump_capacity_plan(path: Path) -> int:
    try:
        spec = _load_spec(path)
        plan = _build_capacity_plan(spec)
    except (ValueError, json.JSONDecodeError) as exc:
        print(f"record_capacity: {exc}", file=sys.stderr)
        return 4
    json.dump(plan, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Capacity F (Phase 6C)")
    p.add_argument("--print-storage-capacity-contract", action="store_true")
    p.add_argument("--analyze-storage-capacity", type=Path)
    p.add_argument("--print-capacity-plan-contract", action="store_true")
    p.add_argument("--analyze-capacity-plan", type=Path)
    p.add_argument("--dump-capacity-plan", type=Path)
    p.add_argument("--print-capacity-plan-query-contract", action="store_true")
    p.add_argument("--print-capacity-policy-contract", action="store_true")
    p.add_argument("--print-measured-capacity-contract", action="store_true")
    p.add_argument("--print-capacity-license-contract", action="store_true")
    p.add_argument("--print-capacity-restore-contract", action="store_true")
    p.add_argument("--print-capacity-predicate-contract", action="store_true")
    p.add_argument("--print-capacity-sourcedata-contract", action="store_true")
    p.add_argument("--print-capacity-ordering-contract", action="store_true")
    p.add_argument("--print-capacity-invalidation-contract", action="store_true")
    p.add_argument("--print-capacity-sufficient-contract", action="store_true")
    p.add_argument("--query-capacity-plan", type=Path)
    p.add_argument("--capacity-policy", default="")
    p.add_argument("--measured-capacity-table", type=Path)
    p.add_argument("--profile", default="")
    args = p.parse_args(argv)
    n = sum(
        bool(x)
        for x in (
            args.print_storage_capacity_contract,
            args.analyze_storage_capacity,
            args.print_capacity_plan_contract,
            args.analyze_capacity_plan,
            args.dump_capacity_plan,
            args.print_capacity_plan_query_contract,
            args.print_capacity_policy_contract,
            args.print_measured_capacity_contract,
            args.print_capacity_license_contract,
            args.print_capacity_restore_contract,
            args.print_capacity_predicate_contract,
            args.print_capacity_sourcedata_contract,
            args.print_capacity_ordering_contract,
            args.print_capacity_invalidation_contract,
            args.print_capacity_sufficient_contract,
            args.query_capacity_plan,
        )
    )
    if n != 1:
        print(
            "record_capacity: choose one of "
            "--print-storage-capacity-contract, --analyze-storage-capacity, "
            "--print-capacity-plan-contract, --analyze-capacity-plan, "
            "--dump-capacity-plan, --print-capacity-plan-query-contract, "
            "--print-capacity-policy-contract, "
            "--print-measured-capacity-contract, "
            "--print-capacity-license-contract, "
            "--print-capacity-restore-contract, "
            "--print-capacity-predicate-contract, "
            "--print-capacity-sourcedata-contract, "
            "--print-capacity-ordering-contract, "
            "--print-capacity-invalidation-contract, "
            "--print-capacity-sufficient-contract, --query-capacity-plan",
            file=sys.stderr,
        )
        return 2
    if args.capacity_policy and not args.query_capacity_plan:
        print(
            "record_capacity: --capacity-policy requires --query-capacity-plan",
            file=sys.stderr,
        )
        return 2
    if args.measured_capacity_table and not args.query_capacity_plan:
        print(
            "record_capacity: --measured-capacity-table requires "
            "--query-capacity-plan",
            file=sys.stderr,
        )
        return 2
    if args.profile and not args.query_capacity_plan:
        print(
            "record_capacity: --profile requires --query-capacity-plan",
            file=sys.stderr,
        )
        return 2
    if args.print_storage_capacity_contract:
        return print_contract()
    if args.analyze_storage_capacity:
        return analyze_capacity(args.analyze_storage_capacity)
    if args.print_capacity_plan_contract:
        return print_plan_contract()
    if args.analyze_capacity_plan:
        return analyze_capacity_plan(args.analyze_capacity_plan)
    if args.print_capacity_plan_query_contract:
        return print_query_contract()
    if args.print_capacity_policy_contract:
        return print_policy_contract()
    if args.print_measured_capacity_contract:
        return print_measured_capacity_contract()
    if args.print_capacity_license_contract:
        return print_license_contract()
    if args.print_capacity_restore_contract:
        return print_restore_contract()
    if args.print_capacity_predicate_contract:
        return print_predicate_contract()
    if args.print_capacity_sourcedata_contract:
        return print_sourcedata_contract()
    if args.print_capacity_ordering_contract:
        return print_ordering_contract()
    if args.print_capacity_invalidation_contract:
        return print_invalidation_contract()
    if args.print_capacity_sufficient_contract:
        return print_sufficient_contract()
    if args.query_capacity_plan:
        return query_capacity_plan(
            args.query_capacity_plan,
            args.capacity_policy,
            args.measured_capacity_table,
            args.profile,
        )
    return dump_capacity_plan(args.dump_capacity_plan)


if __name__ == "__main__":
    sys.exit(main())
