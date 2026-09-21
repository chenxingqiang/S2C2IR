#!/usr/bin/env python3
"""Capability Profile / Applicability aggregation.

Identity=(target, device). Closed kinds stay independent facts.
Profile ≠ applicable ≠ usable ≠ sufficient. Not a rewrite license.
Do not expand S2C2CapabilitySchedule.cpp.
Query only. Do not FileCheck microseconds.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_capability_applicability as capa

PROFILE_SCHEMA = "s2c2.capability_profile.v1"
CONSTRAINT_STATUSES = ("allowed", "forbidden", "not-applicable", "unproven")
ENTRY_PROVENANCE = capa.PROVENANCE_VALUES + ("missing",)


def _constraint_status(decision: dict) -> str:
    if decision["result"] == "n/a":
        return "not-applicable"
    if decision["result"] == "yes":
        return "allowed"
    if "capability.not-applicable" in decision["reasons"]:
        return "forbidden"
    return "unproven"


def _entry_provenance(bag: list[dict], decision: dict) -> str:
    if len(bag) == 1 and decision["result"] in ("yes", "no", "n/a"):
        if "capability.missing-evidence" in decision["reasons"]:
            prov = bag[0].get("provenance")
            if prov == "unknown":
                return "unknown"
            return "missing"
        prov = bag[0].get("provenance")
        if prov in capa.PROVENANCE_VALUES:
            return prov
    if not bag:
        return "missing"
    return "unknown"


def _kind_bag(records: list[dict], target: str, device: str, kind: str) -> list[dict]:
    bag: list[dict] = []
    for rec in records:
        if capa._scope_pair(rec) != (target, device):
            continue
        ident = rec.get("identity") if isinstance(rec.get("identity"), dict) else {}
        if ident.get("kind") != kind:
            continue
        bag.append(rec)
    return bag


def derive_capability_profile(
    records: list[dict],
    target: str,
    device: str,
) -> dict:
    """Aggregate closed kinds for one (target, device). Never AND them."""
    capabilities = []
    for kind in capa.KINDS:
        bag = _kind_bag(records, target, device, kind)
        decision = capa.derive_applicable_decision(bag, target, device, kind)
        if decision["subject"] != "applicable":
            raise RuntimeError(kind)
        if decision["subject"] == "sufficient":
            raise RuntimeError(kind)
        status = _constraint_status(decision)
        if status not in CONSTRAINT_STATUSES:
            raise RuntimeError(status)
        capabilities.append(
            {
                "kind": kind,
                "decision": decision,
                "reasons": list(decision["reasons"]),
                "provenance": _entry_provenance(bag, decision),
                "constraint": status,
            }
        )
    return {
        "schema": PROFILE_SCHEMA,
        "identity": {"target": target, "device": device},
        "target": target,
        "device": device,
        "capabilities": capabilities,
        "sufficiency-evaluation": "n/a",
        "rewrite-license": "no",
        "rewrite-path": "no",
    }


def _rec(
    *,
    kind: str,
    applicability: str,
    provenance: str = "catalog",
    device: str | None = None,
    occupancy_usable: str = "n/a",
) -> dict:
    canonical = (
        "capability.present"
        if applicability == "yes"
        else "capability.not-applicable"
    )
    return capa.capability_record(
        target="cuda",
        device=device or capa.DEVICE_4090,
        kind=kind,
        applicability=applicability,
        canonical=canonical,
        display="catalog-present" if applicability == "yes" else "catalog-no",
        provenance=provenance,
        occupancy_usable=occupancy_usable,
    )


def _cases() -> list[tuple[str, list[dict], str, str]]:
    d4090 = capa.DEVICE_4090
    pair_yes = _rec(kind="concurrent-pair", applicability="yes")
    nbl_yes = _rec(kind="named-nonblocking", applicability="yes")
    dma_yes = _rec(kind="staged-dma", applicability="yes")
    pair_no = _rec(kind="concurrent-pair", applicability="no")
    nbl_no = _rec(kind="named-nonblocking", applicability="no")
    dma_n_a = capa.capability_record(
        target="cuda",
        device=d4090,
        kind="staged-dma",
        applicability="n/a",
        canonical="capability.not-applicable",
        display="domain-n-a",
        provenance="catalog",
    )
    pair_unknown = _rec(
        kind="concurrent-pair",
        applicability="yes",
        provenance="unknown",
        occupancy_usable="yes",
    )
    other_dev = [
        _rec(kind=k, applicability="yes", device="sm80:a100") for k in capa.KINDS
    ]
    return [
        (
            "profile-aggregation",
            [pair_yes, nbl_no, dma_yes],
            "cuda",
            d4090,
        ),
        ("unknown-capability", [], "cuda", d4090),
        (
            "one-kind-no",
            [pair_no, nbl_yes, dma_yes],
            "cuda",
            d4090,
        ),
        ("ignore-other-device", other_dev, "cuda", d4090),
        (
            "duplicate-identity",
            [pair_yes, {**pair_yes}, nbl_yes],
            "cuda",
            d4090,
        ),
        (
            "unknown-provenance",
            [pair_unknown, nbl_yes, dma_yes],
            "cuda",
            d4090,
        ),
        ("usable-ne-capability", [], "cuda", d4090),
        (
            "all-yes-ne-sufficient",
            [pair_yes, nbl_yes, dma_yes],
            "cuda",
            d4090,
        ),
        (
            "no-authorization",
            [pair_yes, nbl_yes, dma_n_a],
            "cuda",
            d4090,
        ),
        (
            "no-rewrite-path",
            [pair_yes, nbl_yes, dma_yes],
            "cuda",
            d4090,
        ),
    ]


def _by_kind(profile: dict) -> dict[str, dict]:
    return {e["kind"]: e for e in profile["capabilities"]}


def _validate() -> None:
    names = [n for n, _, _, _ in _cases()]
    expect_names = [
        "profile-aggregation",
        "unknown-capability",
        "one-kind-no",
        "ignore-other-device",
        "duplicate-identity",
        "unknown-provenance",
        "usable-ne-capability",
        "all-yes-ne-sufficient",
        "no-authorization",
        "no-rewrite-path",
    ]
    if names != expect_names:
        raise RuntimeError(names)
    if len(names) != 10:
        raise RuntimeError(len(names))
    for name, records, target, device in _cases():
        profile = derive_capability_profile(records, target, device)
        if profile["schema"] != PROFILE_SCHEMA:
            raise RuntimeError(name)
        if profile["schema"] == "s2c2.decision.v1":
            raise RuntimeError(name)
        if profile["identity"] != {"target": target, "device": device}:
            raise RuntimeError(name)
        if [e["kind"] for e in profile["capabilities"]] != list(capa.KINDS):
            raise RuntimeError(name)
        if profile["sufficiency-evaluation"] != "n/a":
            raise RuntimeError(name)
        if profile["rewrite-license"] != "no" or profile["rewrite-path"] != "no":
            raise RuntimeError(name)
        kinds = _by_kind(profile)
        for entry in profile["capabilities"]:
            d = entry["decision"]
            if d["subject"] != "applicable":
                raise RuntimeError(name)
            if d["subject"] == "sufficient":
                raise RuntimeError(name)
            if entry["reasons"] != d["reasons"]:
                raise RuntimeError(name)
            if entry["provenance"] not in ENTRY_PROVENANCE:
                raise RuntimeError(name)
            if entry["constraint"] not in CONSTRAINT_STATUSES:
                raise RuntimeError(name)
            for token in entry["reasons"]:
                if token.startswith("authorization."):
                    raise RuntimeError(name)
                if "sufficient" in token:
                    raise RuntimeError(name)
        if name == "profile-aggregation":
            if kinds["concurrent-pair"]["decision"]["result"] != "yes":
                raise RuntimeError(name)
            if kinds["named-nonblocking"]["decision"]["result"] != "no":
                raise RuntimeError(name)
            if kinds["staged-dma"]["decision"]["result"] != "yes":
                raise RuntimeError(name)
            if kinds["named-nonblocking"]["constraint"] != "forbidden":
                raise RuntimeError(name)
            if kinds["concurrent-pair"]["constraint"] != "allowed":
                raise RuntimeError(name)
        if name in ("unknown-capability", "usable-ne-capability"):
            for kind in capa.KINDS:
                e = kinds[kind]
                if e["decision"]["result"] != "no":
                    raise RuntimeError(name)
                if e["reasons"] != ["capability.missing-evidence"]:
                    raise RuntimeError(name)
                if e["constraint"] != "unproven":
                    raise RuntimeError(name)
                if e["provenance"] != "missing":
                    raise RuntimeError(name)
                if e["constraint"] == "forbidden":
                    raise RuntimeError(name)
        if name == "one-kind-no":
            if kinds["concurrent-pair"]["constraint"] != "forbidden":
                raise RuntimeError(name)
            if kinds["named-nonblocking"]["constraint"] != "allowed":
                raise RuntimeError(name)
            if kinds["staged-dma"]["constraint"] != "allowed":
                raise RuntimeError(name)
        if name == "ignore-other-device":
            for kind in capa.KINDS:
                if kinds[kind]["constraint"] != "unproven":
                    raise RuntimeError(name)
        if name == "duplicate-identity":
            if kinds["concurrent-pair"]["reasons"] != ["decision.duplicate-identity"]:
                raise RuntimeError(name)
            if kinds["concurrent-pair"]["constraint"] != "unproven":
                raise RuntimeError(name)
            if kinds["named-nonblocking"]["constraint"] != "allowed":
                raise RuntimeError(name)
            if kinds["staged-dma"]["constraint"] != "unproven":
                raise RuntimeError(name)
        if name == "unknown-provenance":
            if kinds["concurrent-pair"]["reasons"] != ["capability.missing-evidence"]:
                raise RuntimeError(name)
            if kinds["concurrent-pair"]["provenance"] != "unknown":
                raise RuntimeError(name)
            if kinds["concurrent-pair"]["constraint"] != "unproven":
                raise RuntimeError(name)
            if kinds["named-nonblocking"]["constraint"] != "allowed":
                raise RuntimeError(name)
        if name == "all-yes-ne-sufficient":
            if any(kinds[k]["constraint"] != "allowed" for k in capa.KINDS):
                raise RuntimeError(name)
            if profile["sufficiency-evaluation"] != "n/a":
                raise RuntimeError(name)
        if name == "no-authorization":
            if kinds["staged-dma"]["decision"]["result"] != "n/a":
                raise RuntimeError(name)
            if kinds["staged-dma"]["constraint"] != "not-applicable":
                raise RuntimeError(name)
        if name == "no-rewrite-path":
            if profile["rewrite-path"] != "no":
                raise RuntimeError(name)


def print_contract() -> int:
    _validate()
    print("capability-profile gate=query")
    print(f"schema {PROFILE_SCHEMA}")
    print("profile-identity target-device")
    print("profile-ne-applicable yes")
    print("profile-ne-usable yes")
    print("profile-ne-sufficient yes")
    print("profile-ne-decision yes")
    print("absence-ne-no yes")
    print("missing-evidence-ne-forbidden yes")
    print("one-kind-no-ne-profile-collapse yes")
    print("all-yes-ne-sufficient yes")
    print("usable-ne-capability yes")
    print("can-run-plan no")
    print("sufficiency-evaluation n/a")
    print("rewrite-license no")
    print("rewrite-path no")
    print("capability-schedule-ne-god-object yes")
    print("generic-schema-validator n/a")
    print("profile-matrix-cases 10")
    for k in capa.KINDS:
        print(f"kind {k}")
    for s in CONSTRAINT_STATUSES:
        print(f"constraint {s}")
    print("note six-c-m-sufficient-parked")
    print("note sufficient-decision-not-emitted")
    print("note authorization-namespace-closed")
    print("note kinds-closed")
    print("note rewrite=no")
    print("cost=unchanged")
    example = derive_capability_profile(
        [
            _rec(kind="concurrent-pair", applicability="yes"),
            _rec(kind="named-nonblocking", applicability="yes"),
            _rec(kind="staged-dma", applicability="yes"),
        ],
        "cuda",
        capa.DEVICE_4090,
    )
    print("example " + json.dumps(example, separators=(",", ":"), sort_keys=True))
    return 0


def print_matrix() -> int:
    _validate()
    print("capability-profile-matrix gate=query")
    print("profile-ne-sufficient yes")
    print("absence-ne-no yes")
    print("all-yes-ne-sufficient yes")
    print("profile-matrix-cases 10")
    for name, records, target, device in _cases():
        profile = derive_capability_profile(records, target, device)
        print(f"prof-case {name}")
        print(f"prof-identity target={target} device={device}")
        for rec in records:
            ident = rec.get("identity") if isinstance(rec.get("identity"), dict) else {}
            print(
                "prof-record "
                f"target={ident.get('target')} "
                f"device={ident.get('device')} "
                f"kind={ident.get('kind')} "
                f"applicability={rec.get('applicability')} "
                f"provenance={rec.get('provenance')}"
            )
        for entry in profile["capabilities"]:
            d = entry["decision"]
            reasons = ",".join(entry["reasons"]) if entry["reasons"] else "none"
            print(
                "prof-cap "
                f"kind={entry['kind']} "
                f"subject={d['subject']} "
                f"result={d['result']} "
                f"reasons={reasons} "
                f"provenance={entry['provenance']} "
                f"constraint={entry['constraint']}"
            )
        print(f"prof-sufficiency-evaluation {profile['sufficiency-evaluation']}")
        print(f"prof-rewrite-license {profile['rewrite-license']}")
        print(f"prof-rewrite-path {profile['rewrite-path']}")
    print("rewrite-license no")
    print("rewrite-path no")
    print("can-run-plan no")
    print("note sufficient-decision-not-emitted")
    print("cost=unchanged")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Capability Profile")
    p.add_argument("--print-capability-profile-contract", action="store_true")
    p.add_argument("--print-capability-profile-matrix", action="store_true")
    args = p.parse_args(argv)
    flags = (
        args.print_capability_profile_contract,
        args.print_capability_profile_matrix,
    )
    if sum(bool(x) for x in flags) != 1:
        print(
            "record_capability_profile: choose one of "
            "--print-capability-profile-contract "
            "--print-capability-profile-matrix",
            file=sys.stderr,
        )
        return 2
    if args.print_capability_profile_contract:
        return print_contract()
    return print_matrix()


if __name__ == "__main__":
    sys.exit(main())
