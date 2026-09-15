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
    if canonical not in CAPABILITY_REASON_TOKENS:
        raise RuntimeError(canonical)
    return {
        "schema": "s2c2.capability_applicability.v1",
        "identity": {"target": target, "device": device, "kind": kind},
        "target": target,
        "device": device,
        "kind": kind,
        "applicability": applicability,
        "provenance": provenance,
        "occupancy_usable": occupancy_usable,
        "reason": {"canonical": canonical, "display": display},
    }


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
    scoped = [
        r
        for r in records
        if r["identity"]["target"] == target and r["identity"]["device"] == device
    ]
    seen: dict[tuple[str, str, str], dict] = {}
    for rec in scoped:
        ident = rec["identity"]
        if (
            ident["target"] != rec["target"]
            or ident["device"] != rec["device"]
            or ident["kind"] != rec["kind"]
        ):
            return _applicable_no("decision.identity-mismatch")
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
    }
    got = {}
    for name, records, target, device, kind in _cases():
        d = derive_applicable_decision(records, target, device, kind)
        if d["subject"] != "applicable":
            raise RuntimeError(name)
        if "sufficient" in d["reasons"] or d["subject"] == "sufficient":
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
    print("applicable-ne-usable yes")
    print("applicable-ne-sufficient yes")
    for name, records, target, device, kind in _cases():
        d = derive_applicable_decision(records, target, device, kind)
        print(f"capa-case {name}")
        print(f"capa-scope target={target} device={device} kind={kind}")
        for rec in records:
            ident = rec["identity"]
            print(
                "capa-record "
                f"target={ident['target']} "
                f"device={ident['device']} "
                f"kind={ident['kind']} "
                f"payload-kind={rec['kind']} "
                f"applicability={rec['applicability']} "
                f"provenance={rec['provenance']} "
                f"occupancy_usable={rec['occupancy_usable']} "
                f"canonical={rec['reason']['canonical']}"
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
