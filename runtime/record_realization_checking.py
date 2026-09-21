#!/usr/bin/env python3
"""Realization Checking v0 — Check(r, L) per claimed kinds.

Consumes s2c2.realization_legality.v1 + s2c2.realization_claim.v1.
Findings keep {kind, result, constraint}. Unclaimed kinds are ignored.
Contract errors are not satisfy/violate/unproven. Not sufficient,
not can-run-plan, not authorization, not rewrite.
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
import record_capability_profile as prof
import record_realization_legality as legal

CLAIM_SCHEMA = "s2c2.realization_claim.v1"
CHECKING_SCHEMA = "s2c2.realization_checking.v1"
ERROR_TOKENS = (
    "identity-mismatch",
    "unknown-kind",
    "malformed-legality",
    "invalid-schema",
)
RESULTS = ("satisfy", "violate", "unproven")
_RESULT_FOR = {
    "allowed": "satisfy",
    "forbidden": "violate",
    "not-applicable": "violate",
    "unproven": "unproven",
}


def _closed_fields() -> dict:
    return {
        "sufficiency-evaluation": "n/a",
        "can-run-plan": "no",
        "rewrite-license": "no",
        "rewrite-path": "no",
    }


def _error(token: str) -> dict:
    if token not in ERROR_TOKENS:
        raise RuntimeError(token)
    bag = {
        "schema": CHECKING_SCHEMA,
        "source-schema": legal.LEGALITY_SCHEMA,
        "status": "contract-error",
        "error": token,
        "findings": [],
    }
    bag.update(_closed_fields())
    return bag


def _ok(identity: dict, findings: list[dict]) -> dict:
    bag = {
        "schema": CHECKING_SCHEMA,
        "source-schema": legal.LEGALITY_SCHEMA,
        "status": "ok",
        "identity": identity,
        "findings": findings,
    }
    bag.update(_closed_fields())
    return bag


def _legality_bag(legality: object) -> dict | None:
    """Return kind→constraint if L is a closed well-formed bag, else None."""
    if not isinstance(legality, dict):
        return None
    facts = legality.get("facts")
    if not isinstance(facts, list):
        return None
    ident = legality.get("identity")
    if not isinstance(ident, dict):
        return None
    if ident.get("target") is None or ident.get("device") is None:
        return None
    by_kind: dict[str, str] = {}
    for fact in facts:
        if not isinstance(fact, dict):
            return None
        fident = fact.get("identity") if isinstance(fact.get("identity"), dict) else {}
        kind = fident.get("kind") or fact.get("kind")
        constraint = fact.get("constraint")
        if kind in by_kind:
            return None
        if kind not in capa.KINDS:
            return None
        if constraint not in prof.CONSTRAINT_STATUSES:
            return None
        if fident.get("target") not in (None, ident["target"]):
            return None
        if fident.get("device") not in (None, ident["device"]):
            return None
        by_kind[kind] = constraint
    if tuple(by_kind.keys()) != capa.KINDS:
        return None
    return by_kind


def _canonical_claimed(raw: object) -> list[str] | str:
    """Return canonical kinds, or an error token."""
    if raw is None:
        return []
    if not isinstance(raw, list):
        return "invalid-schema"
    seen: set[str] = set()
    for kind in raw:
        if not isinstance(kind, str) or kind not in capa.KINDS:
            return "unknown-kind"
        seen.add(kind)
    return [kind for kind in capa.KINDS if kind in seen]


def check_realization(claim: object, legality: object) -> dict:
    """Check(r, L). Never AND findings. Never fold errors into results."""
    if not isinstance(legality, dict) or legality.get("schema") != legal.LEGALITY_SCHEMA:
        return _error("invalid-schema")
    if not isinstance(claim, dict) or claim.get("schema") != CLAIM_SCHEMA:
        return _error("invalid-schema")
    by_kind = _legality_bag(legality)
    if by_kind is None:
        return _error("malformed-legality")
    claimed = _canonical_claimed(claim.get("claimed-kinds"))
    if claimed == "invalid-schema":
        return _error("invalid-schema")
    if claimed == "unknown-kind":
        return _error("unknown-kind")
    rident = claim.get("identity")
    lident = legality.get("identity")
    if not isinstance(rident, dict) or not isinstance(lident, dict):
        return _error("invalid-schema")
    if rident.get("target") != lident.get("target") or rident.get("device") != lident.get(
        "device"
    ):
        return _error("identity-mismatch")
    findings = [
        {
            "kind": kind,
            "result": _RESULT_FOR[by_kind[kind]],
            "constraint": by_kind[kind],
        }
        for kind in claimed
    ]
    return _ok({"target": lident["target"], "device": lident["device"]}, findings)


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


def _L(records: list[dict]) -> dict:
    return legal.derive_realization_legality(_profile(records))


def _r(kinds: list[str], device: str | None = None) -> dict:
    return {
        "schema": CLAIM_SCHEMA,
        "identity": {"target": "cuda", "device": device or capa.DEVICE_4090},
        "claimed-kinds": kinds,
    }


def _cases() -> list[tuple[str, dict, dict]]:
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
    all_allowed = _L([pair_yes, nbl_yes, dma_yes])
    pair_forbidden = _L([pair_no, nbl_yes, dma_yes])
    dma_na_bag = _L([dma_na])
    unproven_pair = _L([pair_unknown])
    ident = {"target": "cuda", "device": capa.DEVICE_4090}
    missing_kind_L = {
        "schema": legal.LEGALITY_SCHEMA,
        "identity": ident,
        "facts": [
            {
                "schema": legal.LEGALITY_SCHEMA,
                "identity": {**ident, "kind": "concurrent-pair"},
                "constraint": "allowed",
            }
        ],
    }
    return [
        ("satisfy-from-allowed", _L([pair_yes]), _r(["concurrent-pair"])),
        ("violate-from-forbidden", pair_forbidden, _r(["concurrent-pair"])),
        ("violate-from-na", dma_na_bag, _r(["staged-dma"])),
        ("unproven-from-constraint", unproven_pair, _r(["concurrent-pair"])),
        (
            "mixed-claim",
            _L([pair_yes]),
            _r(["concurrent-pair", "named-nonblocking"]),
        ),
        ("all-claimed-satisfy", all_allowed, _r(list(capa.KINDS))),
        ("empty-claim", all_allowed, _r([])),
        ("unclaimed-forbidden", pair_forbidden, _r(["named-nonblocking"])),
        (
            "claimed-kinds-order",
            all_allowed,
            _r(["staged-dma", "concurrent-pair", "staged-dma"]),
        ),
        (
            "identity-mismatch",
            all_allowed,
            _r(["concurrent-pair"], device="sm80:a100"),
        ),
        ("unknown-kind", all_allowed, _r(["sufficient"])),
        ("malformed-L-missing-kind", missing_kind_L, _r(["concurrent-pair"])),
        ("invalid-schema", {"schema": "nope"}, _r(["concurrent-pair"])),
    ]


def _validate() -> None:
    names = [n for n, _, _ in _cases()]
    expect = [
        "satisfy-from-allowed",
        "violate-from-forbidden",
        "violate-from-na",
        "unproven-from-constraint",
        "mixed-claim",
        "all-claimed-satisfy",
        "empty-claim",
        "unclaimed-forbidden",
        "claimed-kinds-order",
        "identity-mismatch",
        "unknown-kind",
        "malformed-L-missing-kind",
        "invalid-schema",
    ]
    if names != expect:
        raise RuntimeError(names)
    if len(names) != 13:
        raise RuntimeError(len(names))
    for name, legality, claim in _cases():
        bag = check_realization(claim, legality)
        if bag["schema"] != CHECKING_SCHEMA:
            raise RuntimeError(name)
        if bag["source-schema"] != legal.LEGALITY_SCHEMA:
            raise RuntimeError(name)
        if bag["sufficiency-evaluation"] != "n/a":
            raise RuntimeError(name)
        if bag["can-run-plan"] != "no":
            raise RuntimeError(name)
        if bag["rewrite-license"] != "no" or bag["rewrite-path"] != "no":
            raise RuntimeError(name)
        if "all-satisfy" in bag or "overall" in bag or "sufficient" in bag:
            raise RuntimeError(name)
        if bag["status"] == "contract-error":
            if bag["findings"] != []:
                raise RuntimeError(name)
            if bag["error"] not in ERROR_TOKENS:
                raise RuntimeError(name)
            if any(k in bag for k in ("satisfy", "violate")):
                raise RuntimeError(name)
        else:
            if bag["status"] != "ok":
                raise RuntimeError(name)
            if "error" in bag:
                raise RuntimeError(name)
            for finding in bag["findings"]:
                if set(finding) != {"kind", "result", "constraint"}:
                    raise RuntimeError(name)
                if finding["kind"] not in capa.KINDS:
                    raise RuntimeError(name)
                if finding["result"] not in RESULTS:
                    raise RuntimeError(name)
                if finding["constraint"] not in prof.CONSTRAINT_STATUSES:
                    raise RuntimeError(name)
                if finding["result"] != _RESULT_FOR[finding["constraint"]]:
                    raise RuntimeError(name)
            kinds = [f["kind"] for f in bag["findings"]]
            if kinds != [k for k in capa.KINDS if k in kinds]:
                raise RuntimeError(name)
        if name == "satisfy-from-allowed":
            f = bag["findings"]
            if f != [
                {
                    "kind": "concurrent-pair",
                    "result": "satisfy",
                    "constraint": "allowed",
                }
            ]:
                raise RuntimeError(name)
        if name == "violate-from-forbidden":
            if bag["findings"][0] != {
                "kind": "concurrent-pair",
                "result": "violate",
                "constraint": "forbidden",
            }:
                raise RuntimeError(name)
        if name == "violate-from-na":
            if bag["findings"][0] != {
                "kind": "staged-dma",
                "result": "violate",
                "constraint": "not-applicable",
            }:
                raise RuntimeError(name)
        if name == "unproven-from-constraint":
            if bag["findings"][0]["result"] != "unproven":
                raise RuntimeError(name)
            if bag["findings"][0]["constraint"] != "unproven":
                raise RuntimeError(name)
        if name == "mixed-claim":
            if [f["kind"] for f in bag["findings"]] != [
                "concurrent-pair",
                "named-nonblocking",
            ]:
                raise RuntimeError(name)
            if bag["findings"][0]["result"] != "satisfy":
                raise RuntimeError(name)
            if bag["findings"][1]["result"] != "unproven":
                raise RuntimeError(name)
        if name == "all-claimed-satisfy":
            if [f["result"] for f in bag["findings"]] != ["satisfy"] * 3:
                raise RuntimeError(name)
            if bag["can-run-plan"] != "no":
                raise RuntimeError(name)
        if name == "empty-claim":
            if bag["status"] != "ok" or bag["findings"] != []:
                raise RuntimeError(name)
        if name == "unclaimed-forbidden":
            if bag["status"] != "ok":
                raise RuntimeError(name)
            kinds = [f["kind"] for f in bag["findings"]]
            if "concurrent-pair" in kinds:
                raise RuntimeError(name)
            if bag["findings"] != [
                {
                    "kind": "named-nonblocking",
                    "result": "satisfy",
                    "constraint": "allowed",
                }
            ]:
                raise RuntimeError(name)
        if name == "claimed-kinds-order":
            if [f["kind"] for f in bag["findings"]] != [
                "concurrent-pair",
                "staged-dma",
            ]:
                raise RuntimeError(name)
        if name == "identity-mismatch":
            if bag["error"] != "identity-mismatch" or bag["findings"] != []:
                raise RuntimeError(name)
        if name == "unknown-kind":
            if bag["error"] != "unknown-kind" or bag["findings"] != []:
                raise RuntimeError(name)
        if name == "malformed-L-missing-kind":
            if bag["error"] != "malformed-legality" or bag["findings"] != []:
                raise RuntimeError(name)
        if name == "invalid-schema":
            if bag["error"] != "invalid-schema" or bag["findings"] != []:
                raise RuntimeError(name)


def print_contract() -> int:
    _validate()
    print("realization-checking gate=query")
    print(f"schema {CHECKING_SCHEMA}")
    print(f"claim-schema {CLAIM_SCHEMA}")
    print(f"source-schema {legal.LEGALITY_SCHEMA}")
    print("checking-identity target-device")
    print("claimed-kinds-canonical yes")
    print("unclaimed-kind-ne-violation yes")
    print("finding-keeps-constraint yes")
    print("satisfy-ne-can-run-plan yes")
    print("violate-ne-rewrite-path yes")
    print("unproven-ne-forbidden yes")
    print("unproven-ne-missing yes")
    print("all-satisfy-ne-sufficient yes")
    print("no-all-satisfy-field yes")
    print("contract-error-ne-result yes")
    print("checking-ne-authorization yes")
    print("checking-ne-rewrite-license yes")
    print("can-run-plan no")
    print("sufficiency-evaluation n/a")
    print("rewrite-license no")
    print("rewrite-path no")
    print("capability-schedule-ne-god-object yes")
    print("generic-schema-validator n/a")
    print("checking-matrix-cases 13")
    for result in RESULTS:
        print(f"result {result}")
    for err in ERROR_TOKENS:
        print(f"contract-error {err}")
    print("note six-c-m-sufficient-parked")
    print("note sufficient-decision-not-emitted")
    print("note applicable-semantics-frozen")
    print("note kinds-closed")
    print("note rewrite=no")
    print("cost=unchanged")
    example = check_realization(
        _r(list(capa.KINDS)),
        _L(
            [
                _rec(kind="concurrent-pair", applicability="yes"),
                _rec(kind="named-nonblocking", applicability="yes"),
                _rec(kind="staged-dma", applicability="yes"),
            ]
        ),
    )
    print("example " + json.dumps(example, separators=(",", ":"), sort_keys=True))
    return 0


def print_matrix() -> int:
    _validate()
    print("realization-checking-matrix gate=query")
    print("finding-keeps-constraint yes")
    print("unclaimed-kind-ne-violation yes")
    print("all-satisfy-ne-sufficient yes")
    print("checking-matrix-cases 13")
    for name, legality, claim in _cases():
        bag = check_realization(claim, legality)
        print(f"chk-case {name}")
        print(f"chk-status {bag['status']}")
        if bag["status"] == "contract-error":
            print(f"chk-error {bag['error']}")
            print("chk-findings-count 0")
        else:
            print(
                "chk-identity "
                f"target={bag['identity']['target']} "
                f"device={bag['identity']['device']}"
            )
            print(f"chk-findings-count {len(bag['findings'])}")
            for finding in bag["findings"]:
                print(
                    "chk-finding "
                    f"kind={finding['kind']} "
                    f"result={finding['result']} "
                    f"constraint={finding['constraint']}"
                )
        print(f"chk-sufficiency-evaluation {bag['sufficiency-evaluation']}")
        print(f"chk-can-run-plan {bag['can-run-plan']}")
        print(f"chk-rewrite-license {bag['rewrite-license']}")
        print(f"chk-rewrite-path {bag['rewrite-path']}")
    print("rewrite-license no")
    print("rewrite-path no")
    print("can-run-plan no")
    print("note sufficient-decision-not-emitted")
    print("cost=unchanged")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Realization Checking")
    p.add_argument("--print-realization-checking-contract", action="store_true")
    p.add_argument("--print-realization-checking-matrix", action="store_true")
    args = p.parse_args(argv)
    flags = (
        args.print_realization_checking_contract,
        args.print_realization_checking_matrix,
    )
    if sum(bool(x) for x in flags) != 1:
        print(
            "record_realization_checking: choose one of "
            "--print-realization-checking-contract "
            "--print-realization-checking-matrix",
            file=sys.stderr,
        )
        return 2
    if args.print_realization_checking_contract:
        return print_contract()
    return print_matrix()


if __name__ == "__main__":
    sys.exit(main())
