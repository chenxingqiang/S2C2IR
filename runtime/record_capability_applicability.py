#!/usr/bin/env python3
"""Capability / Applicability contract (evidence-backed).

Decision.subject=applicable. Not usable, not sufficient, not a
rewrite license. Do not expand S2C2CapabilitySchedule.cpp.
Query only. Do not FileCheck microseconds.
"""

from __future__ import annotations

import argparse
import json
import sys

TARGETS = ("cpu", "cuda", "rocm", "sycl", "ascend", "npu", "cim")
KINDS = ("concurrent-pair", "named-nonblocking", "staged-dma")
APPLICABILITY_VALUES = ("yes", "no", "n/a")
PROVENANCE_VALUES = ("catalog", "occupancy-query", "unknown")
OCCUPANCY_USABLE_VALUES = ("yes", "no", "n/a")
CAPABILITY_REASON_TOKENS = (
    "capability.present",
    "capability.missing-evidence",
    "capability.not-applicable",
    "capability.unknown-target",
    "capability.unknown-kind",
)
DEVICE_4090 = "sm89:rtx4090"
DEVICE_910B = "ascend910b"
DEVICE_HOST = "host"
SCHEMA = "s2c2.capability_applicability.v1"


def _applicable_no(reason: str) -> dict:
    return {
        "schema": "s2c2.decision.v1",
        "subject": "applicable",
        "result": "no",
        "reasons": [reason],
    }


def capability_record(
    *,
    target: str,
    device: str,
    kind: str,
    applicability: str,
    canonical: str,
    display: str,
    provenance: str,
    occupancy_usable: str = "n/a",
) -> dict:
    if target not in TARGETS:
        raise RuntimeError(target)
    if kind not in KINDS:
        raise RuntimeError(kind)
    if applicability not in APPLICABILITY_VALUES:
        raise RuntimeError(applicability)
    if provenance not in PROVENANCE_VALUES:
        raise RuntimeError(provenance)
    if occupancy_usable not in OCCUPANCY_USABLE_VALUES:
        raise RuntimeError(occupancy_usable)
    if canonical not in CAPABILITY_REASON_TOKENS:
        raise RuntimeError(canonical)
    return {
        "schema": SCHEMA,
        "identity": {"target": target, "device": device, "kind": kind},
        "target": target,
        "device": device,
        "kind": kind,
        "applicability": applicability,
        "provenance": provenance,
        "occupancy_usable": occupancy_usable,
        "reason": {"canonical": canonical, "display": display},
    }


def _scope_pair(rec: object) -> tuple[str, str] | None:
    if not isinstance(rec, dict):
        return None
    ident = rec.get("identity")
    if not isinstance(ident, dict):
        return None
    t, d = ident.get("target"), ident.get("device")
    if not isinstance(t, str) or not isinstance(d, str):
        return None
    return t, d


def raw_record_error(rec: object) -> str | None:
    """Typed reason if rec is not a well-formed applicability record.

    Constructor-built records already pass. Derive re-checks raw
    bags so a mutated payload cannot skip the closed schema.
    Does not invent capability tokens.
    """
    if not isinstance(rec, dict):
        return "decision.unknown-reason"
    if rec.get("schema") != SCHEMA:
        return "decision.unknown-reason"
    ident = rec.get("identity")
    if not isinstance(ident, dict):
        return "decision.identity-mismatch"
    for key in ("target", "device", "kind"):
        if key not in ident or key not in rec:
            return "decision.identity-mismatch"
        if ident[key] != rec[key]:
            return "decision.identity-mismatch"
    if rec["target"] not in TARGETS:
        return "capability.unknown-target"
    if rec["kind"] not in KINDS:
        return "capability.unknown-kind"
    if rec.get("applicability") not in APPLICABILITY_VALUES:
        return "decision.unknown-reason"
    if rec.get("occupancy_usable") not in OCCUPANCY_USABLE_VALUES:
        return "decision.unknown-reason"
    if rec.get("provenance") not in PROVENANCE_VALUES:
        return "capability.missing-evidence"
    reason = rec.get("reason")
    if not isinstance(reason, dict) or reason.get("canonical") not in CAPABILITY_REASON_TOKENS:
        return "decision.unknown-reason"
    return None


def derive_applicable_decision(
    records: list[dict],
    target: str,
    device: str,
    kind: str,
) -> dict:
    """Decision.subject=applicable for one (target, device, kind)."""
    if target not in TARGETS:
        return _applicable_no("capability.unknown-target")
    if kind not in KINDS:
        return _applicable_no("capability.unknown-kind")
    scoped: list[dict] = []
    for rec in records:
        pair = _scope_pair(rec)
        if pair != (target, device):
            continue
        err = raw_record_error(rec)
        if err is not None:
            return _applicable_no(err)
        scoped.append(rec)
    seen: dict[tuple[str, str, str], dict] = {}
    for rec in scoped:
        ident = rec["identity"]
        key = (ident["target"], ident["device"], ident["kind"])
        if key in seen:
            return _applicable_no("decision.duplicate-identity")
        seen[key] = rec
    rec = seen.get((target, device, kind))
    if rec is None:
        return _applicable_no("capability.missing-evidence")
    # catalog | occupancy-query may classify; unknown is not evidence.
    if rec.get("provenance") == "unknown":
        return _applicable_no("capability.missing-evidence")
    if rec["applicability"] == "n/a":
        return {
            "schema": "s2c2.decision.v1",
            "subject": "applicable",
            "result": "n/a",
            "reasons": [],
        }
    if rec["applicability"] == "yes":
        return {
            "schema": "s2c2.decision.v1",
            "subject": "applicable",
            "result": "yes",
            "reasons": ["capability.present"],
        }
    return _applicable_no(rec["reason"]["canonical"])


def _cases() -> list[tuple[str, list[dict], str, str, str]]:
    cuda_yes = capability_record(
        target="cuda",
        device=DEVICE_4090,
        kind="concurrent-pair",
        applicability="yes",
        canonical="capability.present",
        display="catalog-pair-present",
        provenance="catalog",
        occupancy_usable="yes",
    )
    cuda_no = capability_record(
        target="cuda",
        device=DEVICE_4090,
        kind="concurrent-pair",
        applicability="no",
        canonical="capability.not-applicable",
        display="catalog-not-applicable",
        provenance="catalog",
        occupancy_usable="yes",
    )
    other_dev = capability_record(
        target="cuda",
        device="sm80:a100",
        kind="concurrent-pair",
        applicability="yes",
        canonical="capability.present",
        display="catalog-pair-present",
        provenance="catalog",
    )
    dup = capability_record(
        target="cuda",
        device=DEVICE_4090,
        kind="concurrent-pair",
        applicability="no",
        canonical="capability.not-applicable",
        display="catalog-not-applicable",
        provenance="catalog",
    )
    mismatch = capability_record(
        target="cuda",
        device=DEVICE_4090,
        kind="concurrent-pair",
        applicability="yes",
        canonical="capability.present",
        display="catalog-pair-present",
        provenance="catalog",
    )
    mismatch = {
        **mismatch,
        "identity": {**mismatch["identity"], "kind": "named-nonblocking"},
    }
    ascend_yes = capability_record(
        target="ascend",
        device=DEVICE_910B,
        kind="staged-dma",
        applicability="yes",
        canonical="capability.present",
        display="catalog-dma-present",
        provenance="catalog",
    )
    cpu_no = capability_record(
        target="cpu",
        device=DEVICE_HOST,
        kind="concurrent-pair",
        applicability="no",
        canonical="capability.not-applicable",
        display="cpu-seq-no-overlap",
        provenance="occupancy-query",
        occupancy_usable="n/a",
    )
    unknown_prov = capability_record(
        target="cuda",
        device=DEVICE_4090,
        kind="concurrent-pair",
        applicability="yes",
        canonical="capability.present",
        display="unknown-provenance-not-evidence",
        provenance="unknown",
        occupancy_usable="yes",
    )
    invalid_schema = {
        **cuda_yes,
        "schema": "s2c2.evidence_record.v1",
    }
    invalid_canonical = {
        **cuda_yes,
        "reason": {
            **cuda_yes["reason"],
            "canonical": "authorization.rewrite",
        },
    }
    invalid_applicability = {
        **cuda_yes,
        "applicability": "maybe",
    }
    invalid_provenance = {
        **cuda_yes,
        "provenance": "invented",
    }
    return [
        ("cuda-pair-present", [cuda_yes], "cuda", DEVICE_4090, "concurrent-pair"),
        ("missing-evidence", [], "cuda", DEVICE_4090, "concurrent-pair"),
        (
            "unknown-provenance",
            [unknown_prov],
            "cuda",
            DEVICE_4090,
            "concurrent-pair",
        ),
        ("unknown-target", [cuda_yes], "invented", DEVICE_4090, "concurrent-pair"),
        ("unknown-kind", [cuda_yes], "cuda", DEVICE_4090, "sufficient"),
        ("usable-ne-applicable", [cuda_no], "cuda", DEVICE_4090, "concurrent-pair"),
        ("dest-inv-ne-applicable", [], "cuda", DEVICE_4090, "concurrent-pair"),
        ("ignore-other-device", [other_dev], "cuda", DEVICE_4090, "concurrent-pair"),
        ("duplicate-identity", [cuda_yes, dup], "cuda", DEVICE_4090, "concurrent-pair"),
        (
            "identity-kind-mismatch",
            [mismatch],
            "cuda",
            DEVICE_4090,
            "concurrent-pair",
        ),
        ("ascend-dma-present", [ascend_yes], "ascend", DEVICE_910B, "staged-dma"),
        ("cpu-pair-not-applicable", [cpu_no], "cpu", DEVICE_HOST, "concurrent-pair"),
        ("invalid-schema", [invalid_schema], "cuda", DEVICE_4090, "concurrent-pair"),
        (
            "invalid-canonical",
            [invalid_canonical],
            "cuda",
            DEVICE_4090,
            "concurrent-pair",
        ),
        (
            "invalid-applicability",
            [invalid_applicability],
            "cuda",
            DEVICE_4090,
            "concurrent-pair",
        ),
        (
            "invalid-provenance",
            [invalid_provenance],
            "cuda",
            DEVICE_4090,
            "concurrent-pair",
        ),
    ]


def _validate() -> None:
    if len(CAPABILITY_REASON_TOKENS) != len(set(CAPABILITY_REASON_TOKENS)):
        raise RuntimeError("duplicate capability token")
    expect = {
        "cuda-pair-present": ("yes", ("capability.present",)),
        "missing-evidence": ("no", ("capability.missing-evidence",)),
        "unknown-provenance": ("no", ("capability.missing-evidence",)),
        "unknown-target": ("no", ("capability.unknown-target",)),
        "unknown-kind": ("no", ("capability.unknown-kind",)),
        "usable-ne-applicable": ("no", ("capability.not-applicable",)),
        "dest-inv-ne-applicable": ("no", ("capability.missing-evidence",)),
        "ignore-other-device": ("no", ("capability.missing-evidence",)),
        "duplicate-identity": ("no", ("decision.duplicate-identity",)),
        "identity-kind-mismatch": ("no", ("decision.identity-mismatch",)),
        "ascend-dma-present": ("yes", ("capability.present",)),
        "cpu-pair-not-applicable": ("no", ("capability.not-applicable",)),
        "invalid-schema": ("no", ("decision.unknown-reason",)),
        "invalid-canonical": ("no", ("decision.unknown-reason",)),
        "invalid-applicability": ("no", ("decision.unknown-reason",)),
        "invalid-provenance": ("no", ("capability.missing-evidence",)),
    }
    got = {}
    for name, records, target, device, kind in _cases():
        d = derive_applicable_decision(records, target, device, kind)
        if d["subject"] != "applicable":
            raise RuntimeError(name)
        if "authorization." in ",".join(d["reasons"]):
            raise RuntimeError(name)
        if d["subject"] == "usable":
            raise RuntimeError(name)
        got[name] = (d["result"], tuple(d["reasons"]))
    if got != expect:
        raise RuntimeError(f"capability matrix drift: {got}")


def print_contract() -> int:
    _validate()
    print("capability-applicability gate=query")
    print("schema s2c2.capability_applicability.v1")
    print("decision-schema s2c2.decision.v1")
    print("decision-subject applicable")
    print("applicable-ne-usable yes")
    print("applicable-ne-sufficient yes")
    print("capability-ne-authorization yes")
    print("capability-ne-rewrite yes")
    print("er-identity-ne-6b-identity yes")
    print("cap-identity-ne-occupancy-identity yes")
    print("v3-catalog-ne-applicability-record yes")
    print("capability-schedule-ne-god-object yes")
    print("identity-cardinality 0-or-1")
    print("duplicate-identity safe-no")
    print("identity-kind-agrees yes")
    print("identity-mismatch safe-no")
    print("unknown-provenance missing-evidence")
    print("raw-record-revalidated yes")
    print("invalid-schema unknown-reason")
    print("invalid-canonical unknown-reason")
    print("invalid-applicability unknown-reason")
    print("invalid-provenance missing-evidence")
    print("authorization-canonical-ne-decision-reason yes")
    print("sufficiency-evaluation n/a")
    print("rewrite-license no")
    print("rewrite-path no")
    for t in TARGETS:
        print(f"target {t}")
    for k in KINDS:
        print(f"kind {k}")
    for tok in CAPABILITY_REASON_TOKENS:
        print(f"token {tok}")
    for name in (
        "identity",
        "target",
        "device",
        "kind",
        "applicability",
        "provenance",
        "occupancy_usable",
        "reason.canonical",
        "reason.display",
    ):
        print(f"record-field {name}")
    print("note six-c-m-sufficient-parked")
    print("note sufficient-decision-not-emitted")
    print("note occupancy-usable-ne-applicable")
    print("note dest-invalidation-ne-applicable")
    print("note authorization-namespace-closed")
    print("note last-writer-wins-forbidden")
    print("note rewrite=no")
    print("cost=unchanged")
    example = capability_record(
        target="cuda",
        device=DEVICE_4090,
        kind="concurrent-pair",
        applicability="yes",
        canonical="capability.present",
        display="catalog-pair-present",
        provenance="catalog",
        occupancy_usable="yes",
    )
    print("example " + json.dumps(example, separators=(",", ":"), sort_keys=True))
    return 0


def print_matrix() -> int:
    _validate()
    print("capability-applicability-matrix gate=query")
    print("derive-subject applicable")
    print("derive-scope target-device-kind")
    print("identity-cardinality 0-or-1")
    print("duplicate-identity safe-no")
    print("identity-mismatch safe-no")
    print("unknown-provenance missing-evidence")
    print("raw-record-revalidated yes")
    print("invalid-schema unknown-reason")
    print("invalid-canonical unknown-reason")
    print("invalid-applicability unknown-reason")
    print("invalid-provenance missing-evidence")
    print("authorization-canonical-ne-decision-reason yes")
    print("applicable-ne-usable yes")
    print("applicable-ne-sufficient yes")
    for name, records, target, device, kind in _cases():
        d = derive_applicable_decision(records, target, device, kind)
        print(f"capa-case {name}")
        print(f"capa-scope target={target} device={device} kind={kind}")
        for rec in records:
            ident = rec.get("identity") if isinstance(rec.get("identity"), dict) else {}
            reason = rec.get("reason") if isinstance(rec.get("reason"), dict) else {}
            print(
                "capa-record "
                f"schema={rec.get('schema')} "
                f"target={ident.get('target')} "
                f"device={ident.get('device')} "
                f"kind={ident.get('kind')} "
                f"payload-kind={rec.get('kind')} "
                f"applicability={rec.get('applicability')} "
                f"provenance={rec.get('provenance')} "
                f"occupancy_usable={rec.get('occupancy_usable')} "
                f"canonical={reason.get('canonical')}"
            )
        reasons = ",".join(d["reasons"]) if d["reasons"] else "none"
        print(
            "capa-decision "
            f"subject={d['subject']} "
            f"result={d['result']} "
            f"reasons={reasons}"
        )
    print("rewrite-license no")
    print("rewrite-path no")
    print("note sufficient-decision-not-emitted")
    print("note occupancy-usable-ne-applicable")
    print("note dest-invalidation-ne-applicable")
    print("cost=unchanged")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Capability Applicability")
    p.add_argument("--print-capability-applicability-contract", action="store_true")
    p.add_argument("--print-capability-applicability-matrix", action="store_true")
    args = p.parse_args(argv)
    flags = (
        args.print_capability_applicability_contract,
        args.print_capability_applicability_matrix,
    )
    if sum(bool(x) for x in flags) != 1:
        print(
            "record_capability_applicability: choose one of "
            "--print-capability-applicability-contract "
            "--print-capability-applicability-matrix",
            file=sys.stderr,
        )
        return 2
    if args.print_capability_applicability_contract:
        return print_contract()
    return print_matrix()


if __name__ == "__main__":
    sys.exit(main())
