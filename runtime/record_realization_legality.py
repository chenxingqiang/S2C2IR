#!/usr/bin/env python3
"""Realization Legality v1 — normalize profile constraint facts.

Consumes s2c2.capability_profile.v1 only. Identity=(target, device, kind).
constraint copied, not remapped. Not sufficient, not can-run-plan,
not authorization, not rewrite. Do not expand S2C2CapabilitySchedule.cpp.
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
import record_capability_profile as prof

LEGALITY_SCHEMA = "s2c2.realization_legality.v1"


def _unproven_fact(target: str, device: str, kind: str, reason: str) -> dict:
    return {
        "schema": LEGALITY_SCHEMA,
        "identity": {"target": target, "device": device, "kind": kind},
        "constraint": "unproven",
        "reasons": [reason],
    }


def derive_realization_legality(profile: object) -> dict:
    """Copy profile constraints into per-kind legality facts. Never AND them."""
    if not isinstance(profile, dict) or profile.get("schema") != prof.PROFILE_SCHEMA:
        target = profile.get("target", "cuda") if isinstance(profile, dict) else "cuda"
        device = (
            profile.get("device", capa.DEVICE_4090)
            if isinstance(profile, dict)
            else capa.DEVICE_4090
        )
        facts = [
            _unproven_fact(target, device, kind, "decision.unknown-reason")
            for kind in capa.KINDS
        ]
        return _envelope(target, device, facts)
    target = profile["target"]
    device = profile["device"]
    by_kind = {e["kind"]: e for e in profile.get("capabilities", []) if isinstance(e, dict)}
    facts = []
    for kind in capa.KINDS:
        entry = by_kind.get(kind)
        if entry is None:
            facts.append(_unproven_fact(target, device, kind, "capability.missing-evidence"))
            continue
        constraint = entry.get("constraint")
        if constraint not in prof.CONSTRAINT_STATUSES:
            facts.append(_unproven_fact(target, device, kind, "decision.unknown-reason"))
            continue
        reasons = list(entry.get("reasons") or [])
        facts.append(
            {
                "schema": LEGALITY_SCHEMA,
                "identity": {"target": target, "device": device, "kind": kind},
                "constraint": constraint,
                "reasons": reasons,
            }
        )
    return _envelope(target, device, facts)


def _envelope(target: str, device: str, facts: list[dict]) -> dict:
    return {
        "schema": LEGALITY_SCHEMA,
        "source-schema": prof.PROFILE_SCHEMA,
        "identity": {"target": target, "device": device},
        "facts": facts,
        "sufficiency-evaluation": "n/a",
        "can-run-plan": "no",
        "rewrite-license": "no",
        "rewrite-path": "no",
    }


def _profile(records: list[dict], device: str | None = None) -> dict:
    return prof.derive_capability_profile(
        records, "cuda", device or capa.DEVICE_4090
    )


def _rec(*, kind: str, applicability: str, provenance: str = "catalog") -> dict:
    canonical = (
        "capability.present"
        if applicability == "yes"
        else "capability.not-applicable"
    )
    return capa.capability_record(
        target="cuda",
        device=capa.DEVICE_4090,
        kind=kind,
        applicability=applicability,
        canonical=canonical,
        display="catalog-present" if applicability == "yes" else "catalog-no",
        provenance=provenance,
    )


def _cases() -> list[tuple[str, dict]]:
    pair_yes = _rec(kind="concurrent-pair", applicability="yes")
    nbl_yes = _rec(kind="named-nonblocking", applicability="yes")
    dma_yes = _rec(kind="staged-dma", applicability="yes")
    pair_no = _rec(kind="concurrent-pair", applicability="no")
    dma_na = capa.capability_record(
        target="cuda",
        device=capa.DEVICE_4090,
        kind="staged-dma",
        applicability="n/a",
        canonical="capability.not-applicable",
        display="domain-n-a",
        provenance="catalog",
    )
    pair_unknown = _rec(
        kind="concurrent-pair", applicability="yes", provenance="unknown"
    )
    return [
        ("allowed-from-yes", _profile([pair_yes])),
        ("forbidden-from-no", _profile([pair_no])),
        ("not-applicable-from-na", _profile([dma_na])),
        ("unproven-from-missing", _profile([])),
        ("unproven-from-unknown-provenance", _profile([pair_unknown])),
        ("all-allowed-ne-sufficient", _profile([pair_yes, nbl_yes, dma_yes])),
        ("one-kind-forbidden", _profile([pair_no, nbl_yes, dma_yes])),
        ("mixed-allowed-unproven", _profile([pair_yes])),
    ]


def _by_kind(bag: dict) -> dict[str, dict]:
    return {f["identity"]["kind"]: f for f in bag["facts"]}


def _validate() -> None:
    names = [n for n, _ in _cases()]
    expect = [
        "allowed-from-yes",
        "forbidden-from-no",
        "not-applicable-from-na",
        "unproven-from-missing",
        "unproven-from-unknown-provenance",
        "all-allowed-ne-sufficient",
        "one-kind-forbidden",
        "mixed-allowed-unproven",
    ]
    if names != expect:
        raise RuntimeError(names)
    if len(names) != 8:
        raise RuntimeError(len(names))
    for name, profile in _cases():
        bag = derive_realization_legality(profile)
        if bag["schema"] != LEGALITY_SCHEMA:
            raise RuntimeError(name)
        if bag["source-schema"] != prof.PROFILE_SCHEMA:
            raise RuntimeError(name)
        if bag["sufficiency-evaluation"] != "n/a":
            raise RuntimeError(name)
        if bag["can-run-plan"] != "no":
            raise RuntimeError(name)
        if bag["rewrite-license"] != "no" or bag["rewrite-path"] != "no":
            raise RuntimeError(name)
        kinds = [f["identity"]["kind"] for f in bag["facts"]]
        if kinds != list(capa.KINDS):
            raise RuntimeError(name)
        byk = _by_kind(bag)
        for fact in bag["facts"]:
            if fact["schema"] != LEGALITY_SCHEMA:
                raise RuntimeError(name)
            if fact["constraint"] not in prof.CONSTRAINT_STATUSES:
                raise RuntimeError(name)
            ident = fact["identity"]
            if ident["target"] != profile["target"] or ident["device"] != profile["device"]:
                raise RuntimeError(name)
            for token in fact["reasons"]:
                if token.startswith("authorization."):
                    raise RuntimeError(name)
                if "sufficient" in token:
                    raise RuntimeError(name)
        pkind = {e["kind"]: e for e in profile["capabilities"]}
        for kind in capa.KINDS:
            if byk[kind]["constraint"] != pkind[kind]["constraint"]:
                raise RuntimeError(name)
        if name == "allowed-from-yes":
            if byk["concurrent-pair"]["constraint"] != "allowed":
                raise RuntimeError(name)
        if name == "forbidden-from-no":
            if byk["concurrent-pair"]["constraint"] != "forbidden":
                raise RuntimeError(name)
            if byk["named-nonblocking"]["constraint"] != "unproven":
                raise RuntimeError(name)
        if name == "not-applicable-from-na":
            if byk["staged-dma"]["constraint"] != "not-applicable":
                raise RuntimeError(name)
        if name in ("unproven-from-missing", "unproven-from-unknown-provenance"):
            if byk["concurrent-pair"]["constraint"] != "unproven":
                raise RuntimeError(name)
        if name == "all-allowed-ne-sufficient":
            if any(byk[k]["constraint"] != "allowed" for k in capa.KINDS):
                raise RuntimeError(name)
        if name == "one-kind-forbidden":
            if byk["concurrent-pair"]["constraint"] != "forbidden":
                raise RuntimeError(name)
            if byk["named-nonblocking"]["constraint"] != "allowed":
                raise RuntimeError(name)
            if byk["staged-dma"]["constraint"] != "allowed":
                raise RuntimeError(name)
        if name == "mixed-allowed-unproven":
            if byk["concurrent-pair"]["constraint"] != "allowed":
                raise RuntimeError(name)
            if byk["named-nonblocking"]["constraint"] != "unproven":
                raise RuntimeError(name)
            if byk["staged-dma"]["constraint"] != "unproven":
                raise RuntimeError(name)
    bad = derive_realization_legality(
        {"schema": "nope", "target": "cuda", "device": capa.DEVICE_4090}
    )
    if bad["can-run-plan"] != "no" or bad["sufficiency-evaluation"] != "n/a":
        raise RuntimeError("invalid-schema")
    for fact in bad["facts"]:
        if fact["constraint"] != "unproven":
            raise RuntimeError("invalid-schema")
        if fact["reasons"] != ["decision.unknown-reason"]:
            raise RuntimeError("invalid-schema")
    mutated = _profile([_rec(kind="concurrent-pair", applicability="yes")])
    mutated["capabilities"][0]["constraint"] = "invented"
    invented = derive_realization_legality(mutated)
    if _by_kind(invented)["concurrent-pair"]["constraint"] != "unproven":
        raise RuntimeError("unknown-constraint")
    if _by_kind(invented)["concurrent-pair"]["reasons"] != ["decision.unknown-reason"]:
        raise RuntimeError("unknown-constraint")


def print_contract() -> int:
    _validate()
    print("realization-legality gate=query")
    print(f"schema {LEGALITY_SCHEMA}")
    print(f"source-schema {prof.PROFILE_SCHEMA}")
    print("legality-identity target-device-kind")
    print("constraint-copied yes")
    print("legality-ne-applicable yes")
    print("legality-ne-profile yes")
    print("legality-ne-sufficient yes")
    print("unproven-ne-forbidden yes")
    print("allowed-ne-can-run-plan yes")
    print("all-allowed-ne-sufficient yes")
    print("legality-ne-authorization yes")
    print("legality-ne-rewrite-license yes")
    print("can-run-plan no")
    print("sufficiency-evaluation n/a")
    print("rewrite-license no")
    print("rewrite-path no")
    print("capability-schedule-ne-god-object yes")
    print("generic-schema-validator n/a")
    print("legality-matrix-cases 8")
    for s in prof.CONSTRAINT_STATUSES:
        print(f"constraint {s}")
    print("note six-c-m-sufficient-parked")
    print("note sufficient-decision-not-emitted")
    print("note applicable-semantics-frozen")
    print("note kinds-closed")
    print("note rewrite=no")
    print("cost=unchanged")
    example = derive_realization_legality(
        _profile(
            [
                _rec(kind="concurrent-pair", applicability="yes"),
                _rec(kind="named-nonblocking", applicability="yes"),
                _rec(kind="staged-dma", applicability="yes"),
            ]
        )
    )
    print("example " + json.dumps(example, separators=(",", ":"), sort_keys=True))
    return 0


def print_matrix() -> int:
    _validate()
    print("realization-legality-matrix gate=query")
    print("constraint-copied yes")
    print("all-allowed-ne-sufficient yes")
    print("unproven-ne-forbidden yes")
    print("legality-matrix-cases 8")
    for name, profile in _cases():
        bag = derive_realization_legality(profile)
        print(f"leg-case {name}")
        print(
            "leg-profile "
            f"target={profile['target']} "
            f"device={profile['device']}"
        )
        for entry in profile["capabilities"]:
            print(
                "leg-src "
                f"kind={entry['kind']} "
                f"constraint={entry['constraint']}"
            )
        for fact in bag["facts"]:
            reasons = ",".join(fact["reasons"]) if fact["reasons"] else "none"
            ident = fact["identity"]
            print(
                "leg-fact "
                f"target={ident['target']} "
                f"device={ident['device']} "
                f"kind={ident['kind']} "
                f"constraint={fact['constraint']} "
                f"reasons={reasons}"
            )
        print(f"leg-sufficiency-evaluation {bag['sufficiency-evaluation']}")
        print(f"leg-can-run-plan {bag['can-run-plan']}")
        print(f"leg-rewrite-license {bag['rewrite-license']}")
        print(f"leg-rewrite-path {bag['rewrite-path']}")
    print("rewrite-license no")
    print("rewrite-path no")
    print("can-run-plan no")
    print("note sufficient-decision-not-emitted")
    print("cost=unchanged")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Realization Legality")
    p.add_argument("--print-realization-legality-contract", action="store_true")
    p.add_argument("--print-realization-legality-matrix", action="store_true")
    args = p.parse_args(argv)
    flags = (
        args.print_realization_legality_contract,
        args.print_realization_legality_matrix,
    )
    if sum(bool(x) for x in flags) != 1:
        print(
            "record_realization_legality: choose one of "
            "--print-realization-legality-contract "
            "--print-realization-legality-matrix",
            file=sys.stderr,
        )
        return 2
    if args.print_realization_legality_contract:
        return print_contract()
    return print_matrix()


if __name__ == "__main__":
    sys.exit(main())
