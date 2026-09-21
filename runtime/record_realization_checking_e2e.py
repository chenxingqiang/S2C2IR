#!/usr/bin/env python3
"""Baseline E2E Integration v0 — compose frozen hosts only.

Evidence records → Profile → Legality → Claim → Check(r, L).
Does not reimplement result mapping. Does not change Profile,
Legality, or Checking semantics. Not sufficient, not can-run-plan,
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
import record_realization_checking as chk
import record_realization_legality as legal


def _rec(*, kind: str, applicability: str) -> dict:
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
        provenance="catalog",
    )


def _claim(kinds: list[str], device: str | None = None) -> dict:
    return {
        "schema": chk.CLAIM_SCHEMA,
        "identity": {"target": "cuda", "device": device or capa.DEVICE_4090},
        "claimed-kinds": kinds,
    }


def run_e2e(records: list[dict], claim: dict) -> dict:
    """Compose frozen hosts. Mapping lives only in check_realization."""
    ident = claim.get("identity") if isinstance(claim.get("identity"), dict) else {}
    target = ident.get("target", "cuda")
    device = ident.get("device", capa.DEVICE_4090)
    # Case C uses a mismatched claim device; Profile/Legality stay on the
    # fixture device so L is well-formed and Check reports identity-mismatch.
    profile = prof.derive_capability_profile(records, "cuda", capa.DEVICE_4090)
    legality = legal.derive_realization_legality(profile)
    checking = chk.check_realization(claim, legality)
    again = chk.check_realization(claim, legality)
    if checking != again:
        raise RuntimeError("e2e-not-deterministic")
    return {
        "profile": profile,
        "legality": legality,
        "claim": claim,
        "checking": checking,
        "pipeline-target": target,
        "pipeline-device": device,
    }


def _cases() -> list[tuple[str, list[dict], dict]]:
    pair_yes = _rec(kind="concurrent-pair", applicability="yes")
    pair_no = _rec(kind="concurrent-pair", applicability="no")
    dma_yes = _rec(kind="staged-dma", applicability="yes")
    claimed = ["staged-dma", "concurrent-pair"]
    return [
        ("legal-claim", [pair_yes], _claim(claimed)),
        ("unsatisfied-claim", [pair_no, dma_yes], _claim(claimed)),
        (
            "identity-mismatch",
            [pair_yes],
            _claim(["concurrent-pair"], device="sm80:a100"),
        ),
    ]


def _validate() -> None:
    names = [n for n, _, _ in _cases()]
    expect = ["legal-claim", "unsatisfied-claim", "identity-mismatch"]
    if names != expect:
        raise RuntimeError(names)
    for name, records, claim in _cases():
        bag = run_e2e(records, claim)
        profile = bag["profile"]
        legality = bag["legality"]
        checking = bag["checking"]
        if profile["schema"] != prof.PROFILE_SCHEMA:
            raise RuntimeError(name)
        if legality["schema"] != legal.LEGALITY_SCHEMA:
            raise RuntimeError(name)
        if legality["source-schema"] != prof.PROFILE_SCHEMA:
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
        if name == "legal-claim":
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
        if name == "unsatisfied-claim":
            if checking["status"] != "ok":
                raise RuntimeError(name)
            if checking["findings"] != [
                {
                    "kind": "concurrent-pair",
                    "result": "violate",
                    "constraint": "forbidden",
                },
                {
                    "kind": "staged-dma",
                    "result": "satisfy",
                    "constraint": "allowed",
                },
            ]:
                raise RuntimeError(name)
        if name == "identity-mismatch":
            if checking["status"] != "contract-error":
                raise RuntimeError(name)
            if checking["error"] != "identity-mismatch":
                raise RuntimeError(name)
            if checking["findings"] != []:
                raise RuntimeError(name)


def print_contract() -> int:
    _validate()
    print("realization-checking-e2e gate=query")
    print("e2e-type integration-reproducibility")
    print("semantic-expansion none")
    print("e2e-chain evidence-predicate-profile-legality-claim-checking")
    print("e2e-uses-frozen-hosts yes")
    print("e2e-reimplements-mapping no")
    print("e2e-eq-check-v0 yes")
    print("unclaimed-kind-ne-violation yes")
    print("contract-error-ne-result yes")
    print("can-run-plan no")
    print("sufficiency-evaluation n/a")
    print("rewrite-license no")
    print("rewrite-path no")
    print("capability-schedule-ne-god-object yes")
    print("generic-schema-validator n/a")
    print("e2e-matrix-cases 3")
    print("note six-c-m-sufficient-parked")
    print("note sufficient-decision-not-emitted")
    print("note applicable-semantics-frozen")
    print("note rewrite=no")
    print("cost=unchanged")
    example = run_e2e(
        [_rec(kind="concurrent-pair", applicability="yes")],
        _claim(["staged-dma", "concurrent-pair"]),
    )
    print(
        "example "
        + json.dumps(example["checking"], separators=(",", ":"), sort_keys=True)
    )
    return 0


def print_matrix() -> int:
    _validate()
    print("realization-checking-e2e-matrix gate=query")
    print("e2e-eq-check-v0 yes")
    print("unclaimed-kind-ne-violation yes")
    print("e2e-matrix-cases 3")
    for name, records, claim in _cases():
        bag = run_e2e(records, claim)
        checking = bag["checking"]
        print(f"e2e-case {name}")
        print(f"e2e-status {checking['status']}")
        print(
            "e2e-profile "
            f"schema={bag['profile']['schema']} "
            f"target={bag['profile']['target']} "
            f"device={bag['profile']['device']}"
        )
        print(
            "e2e-legality "
            f"schema={bag['legality']['schema']} "
            f"source-schema={bag['legality']['source-schema']}"
        )
        claimed = ",".join(claim.get("claimed-kinds") or [])
        print(f"e2e-claim claimed-kinds={claimed or 'none'}")
        if checking["status"] == "contract-error":
            print(f"e2e-error {checking['error']}")
            print("e2e-findings-count 0")
        else:
            print(f"e2e-findings-count {len(checking['findings'])}")
            for finding in checking["findings"]:
                print(
                    "e2e-finding "
                    f"kind={finding['kind']} "
                    f"result={finding['result']} "
                    f"constraint={finding['constraint']}"
                )
        print(f"e2e-sufficiency-evaluation {checking['sufficiency-evaluation']}")
        print(f"e2e-can-run-plan {checking['can-run-plan']}")
        print(f"e2e-rewrite-license {checking['rewrite-license']}")
        print(f"e2e-rewrite-path {checking['rewrite-path']}")
    print("rewrite-license no")
    print("can-run-plan no")
    print("note sufficient-decision-not-emitted")
    print("cost=unchanged")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Realization Checking E2E")
    p.add_argument("--print-realization-checking-e2e-contract", action="store_true")
    p.add_argument("--print-realization-checking-e2e-matrix", action="store_true")
    args = p.parse_args(argv)
    flags = (
        args.print_realization_checking_e2e_contract,
        args.print_realization_checking_e2e_matrix,
    )
    if sum(bool(x) for x in flags) != 1:
        print(
            "record_realization_checking_e2e: choose one of "
            "--print-realization-checking-e2e-contract "
            "--print-realization-checking-e2e-matrix",
            file=sys.stderr,
        )
        return 2
    if args.print_realization_checking_e2e_contract:
        return print_contract()
    return print_matrix()


if __name__ == "__main__":
    sys.exit(main())
