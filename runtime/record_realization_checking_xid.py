#!/usr/bin/env python3
"""Cross-identity Checking E2E v0 — compose frozen hosts only.

Replay Check(r, L) on frozen cuda / ascend / cpu identities.
Does not reimplement result mapping. Does not change Profile,
Legality, or Checking semantics. Does not invent npu/cim
catalog cells. Not sufficient, not can-run-plan, not
authorization, not rewrite. Do not expand
S2C2CapabilitySchedule.cpp. Query only. Do not FileCheck
microseconds.
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
import record_realization_checking as chk
import record_realization_legality as legal


def _rec(*, target: str, device: str, kind: str, applicability: str) -> dict:
    canonical = (
        "capability.present"
        if applicability == "yes"
        else "capability.not-applicable"
    )
    display = {
        "yes": "catalog-present",
        "no": "catalog-no",
        "n/a": "catalog-n/a",
    }[applicability]
    return capa.capability_record(
        target=target,
        device=device,
        kind=kind,
        applicability=applicability,
        canonical=canonical,
        display=display,
        provenance="catalog",
    )


def _claim(target: str, device: str, kinds: list[str]) -> dict:
    return {
        "schema": chk.CLAIM_SCHEMA,
        "identity": {"target": target, "device": device},
        "claimed-kinds": kinds,
    }


def run_xid(
    records: list[dict],
    target: str,
    device: str,
    claim: dict,
) -> dict:
    """Compose frozen hosts. Mapping lives only in check_realization."""
    profile = prof.derive_capability_profile(records, target, device)
    legality = legal.derive_realization_legality(profile)
    checking = chk.check_realization(claim, legality)
    again = chk.check_realization(claim, legality)
    if checking != again:
        raise RuntimeError("xid-not-deterministic")
    return {
        "profile": profile,
        "legality": legality,
        "claim": claim,
        "checking": checking,
    }


def _cases() -> list[tuple[str, list[dict], str, str, dict]]:
    claimed = ["staged-dma", "concurrent-pair"]
    cuda_pair = _rec(
        target="cuda",
        device=capa.DEVICE_4090,
        kind="concurrent-pair",
        applicability="yes",
    )
    ascend_dma = _rec(
        target="ascend",
        device=capa.DEVICE_910B,
        kind="staged-dma",
        applicability="yes",
    )
    cpu_pair_na = _rec(
        target="cpu",
        device=capa.DEVICE_HOST,
        kind="concurrent-pair",
        applicability="n/a",
    )
    return [
        (
            "cuda-legal",
            [cuda_pair],
            "cuda",
            capa.DEVICE_4090,
            _claim("cuda", capa.DEVICE_4090, claimed),
        ),
        (
            "ascend-dma",
            [ascend_dma],
            "ascend",
            capa.DEVICE_910B,
            _claim("ascend", capa.DEVICE_910B, claimed),
        ),
        (
            "cpu-na",
            [cpu_pair_na],
            "cpu",
            capa.DEVICE_HOST,
            _claim("cpu", capa.DEVICE_HOST, ["concurrent-pair"]),
        ),
        (
            "cross-target",
            [ascend_dma],
            "ascend",
            capa.DEVICE_910B,
            _claim("cuda", capa.DEVICE_4090, ["concurrent-pair"]),
        ),
    ]


def _validate() -> None:
    names = [n for n, *_ in _cases()]
    expect = ["cuda-legal", "ascend-dma", "cpu-na", "cross-target"]
    if names != expect:
        raise RuntimeError(names)
    for name, records, target, device, claim in _cases():
        bag = run_xid(records, target, device, claim)
        profile = bag["profile"]
        legality = bag["legality"]
        checking = bag["checking"]
        if profile["schema"] != prof.PROFILE_SCHEMA:
            raise RuntimeError(name)
        if profile["target"] != target or profile["device"] != device:
            raise RuntimeError(name)
        if legality["schema"] != legal.LEGALITY_SCHEMA:
            raise RuntimeError(name)
        if legality["identity"] != {"target": target, "device": device}:
            raise RuntimeError(name)
        direct = chk.check_realization(claim, legality)
        if checking != direct:
            raise RuntimeError(name)
        if checking["can-run-plan"] != "no":
            raise RuntimeError(name)
        if checking["sufficiency-evaluation"] != "n/a":
            raise RuntimeError(name)
        if checking["rewrite-license"] != "no" or checking["rewrite-path"] != "no":
            raise RuntimeError(name)
        if "all-satisfy" in checking or "overall" in checking:
            raise RuntimeError(name)
        if "sufficient" in checking:
            raise RuntimeError(name)
        kinds_in_findings = [f["kind"] for f in checking["findings"]]
        if "named-nonblocking" in kinds_in_findings:
            raise RuntimeError(name)
        if name == "cuda-legal":
            if checking["status"] != "ok":
                raise RuntimeError(name)
            if checking["findings"] != [
                {
                    "kind": "concurrent-pair",
                    "result": "satisfy",
                    "constraint": "allowed",
                },
                {
                    "kind": "staged-dma",
                    "result": "unproven",
                    "constraint": "unproven",
                },
            ]:
                raise RuntimeError(name)
        if name == "ascend-dma":
            if checking["status"] != "ok":
                raise RuntimeError(name)
            if checking["identity"] != {
                "target": "ascend",
                "device": capa.DEVICE_910B,
            }:
                raise RuntimeError(name)
            if checking["findings"] != [
                {
                    "kind": "concurrent-pair",
                    "result": "unproven",
                    "constraint": "unproven",
                },
                {
                    "kind": "staged-dma",
                    "result": "satisfy",
                    "constraint": "allowed",
                },
            ]:
                raise RuntimeError(name)
        if name == "cpu-na":
            if checking["status"] != "ok":
                raise RuntimeError(name)
            if checking["identity"] != {"target": "cpu", "device": capa.DEVICE_HOST}:
                raise RuntimeError(name)
            if checking["findings"] != [
                {
                    "kind": "concurrent-pair",
                    "result": "violate",
                    "constraint": "not-applicable",
                },
            ]:
                raise RuntimeError(name)
        if name == "cross-target":
            if claim["identity"]["target"] != "cuda":
                raise RuntimeError(name)
            if checking["status"] != "contract-error":
                raise RuntimeError(name)
            if checking["error"] != "identity-mismatch":
                raise RuntimeError(name)
            if checking["findings"] != []:
                raise RuntimeError(name)


def print_contract() -> int:
    _validate()
    print("realization-checking-xid gate=query")
    print("xid-type integration-reproducibility")
    print("semantic-expansion none")
    print("xid-chain evidence-profile-legality-claim-checking")
    print("xid-uses-frozen-hosts yes")
    print("xid-reimplements-mapping no")
    print("xid-eq-check-v0 yes")
    print("xid-identities cuda,ascend,cpu")
    print("xid-invents-npu-cim no")
    print("unclaimed-kind-ne-violation yes")
    print("contract-error-ne-result yes")
    print("can-run-plan no")
    print("sufficiency-evaluation n/a")
    print("rewrite-license no")
    print("rewrite-path no")
    print("capability-schedule-ne-god-object yes")
    print("generic-schema-validator n/a")
    print("xid-matrix-cases 4")
    print("note six-c-m-sufficient-parked")
    print("note sufficient-decision-not-emitted")
    print("note applicable-semantics-frozen")
    print("note rewrite=no")
    print("cost=unchanged")
    example = run_xid(
        [
            _rec(
                target="ascend",
                device=capa.DEVICE_910B,
                kind="staged-dma",
                applicability="yes",
            )
        ],
        "ascend",
        capa.DEVICE_910B,
        _claim("ascend", capa.DEVICE_910B, ["staged-dma", "concurrent-pair"]),
    )
    print(
        "example "
        + json.dumps(example["checking"], separators=(",", ":"), sort_keys=True)
    )
    return 0


def print_matrix() -> int:
    _validate()
    print("realization-checking-xid-matrix gate=query")
    print("xid-eq-check-v0 yes")
    print("unclaimed-kind-ne-violation yes")
    print("xid-invents-npu-cim no")
    print("xid-matrix-cases 4")
    for name, records, target, device, claim in _cases():
        bag = run_xid(records, target, device, claim)
        checking = bag["checking"]
        print(f"xid-case {name}")
        print(f"xid-status {checking['status']}")
        print(
            "xid-profile "
            f"schema={bag['profile']['schema']} "
            f"target={bag['profile']['target']} "
            f"device={bag['profile']['device']}"
        )
        print(
            "xid-legality "
            f"schema={bag['legality']['schema']} "
            f"source-schema={bag['legality']['source-schema']}"
        )
        claimed = ",".join(claim.get("claimed-kinds") or [])
        ident = claim.get("identity") if isinstance(claim.get("identity"), dict) else {}
        print(f"xid-claim claimed-kinds={claimed or 'none'}")
        print(
            "xid-claim-identity "
            f"target={ident.get('target') or 'none'} "
            f"device={ident.get('device') or 'none'}"
        )
        if checking["status"] == "contract-error":
            print(f"xid-error {checking['error']}")
            print("xid-findings-count 0")
        else:
            print(f"xid-findings-count {len(checking['findings'])}")
            for finding in checking["findings"]:
                print(
                    "xid-finding "
                    f"kind={finding['kind']} "
                    f"result={finding['result']} "
                    f"constraint={finding['constraint']}"
                )
        print(f"xid-sufficiency-evaluation {checking['sufficiency-evaluation']}")
        print(f"xid-can-run-plan {checking['can-run-plan']}")
        print(f"xid-rewrite-license {checking['rewrite-license']}")
        print(f"xid-rewrite-path {checking['rewrite-path']}")
    print("rewrite-license no")
    print("can-run-plan no")
    print("note sufficient-decision-not-emitted")
    print("cost=unchanged")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Realization Checking XID")
    p.add_argument("--print-realization-checking-xid-contract", action="store_true")
    p.add_argument("--print-realization-checking-xid-matrix", action="store_true")
    args = p.parse_args(argv)
    flags = (
        args.print_realization_checking_xid_contract,
        args.print_realization_checking_xid_matrix,
    )
    if sum(bool(x) for x in flags) != 1:
        print(
            "record_realization_checking_xid: choose one of "
            "--print-realization-checking-xid-contract "
            "--print-realization-checking-xid-matrix",
            file=sys.stderr,
        )
        return 2
    if args.print_realization_checking_xid_contract:
        return print_contract()
    return print_matrix()


if __name__ == "__main__":
    sys.exit(main())
