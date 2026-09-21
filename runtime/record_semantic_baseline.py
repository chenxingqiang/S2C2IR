#!/usr/bin/env python3
"""Semantic Baseline v1 — replay frozen Decision hosts on main.

Composes EA-1 / 6C-M / 7A / 7B / legacy RCE+XID after #136/#137/#138
merged. Does not reimplement evaluators. Does not merge #139.
Does not open an apply inhabitant. Not an IR apply. Query only.
Do not FileCheck microseconds.
"""

from __future__ import annotations

import argparse
import io
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_authorization as auth
import record_decision as ea1
import record_realization_checking_e2e as e2e
import record_realization_checking_xid as xid
import record_storage_rewrite as rew
import record_sufficiency as suf


def _capture(fn) -> str:
    buf = io.StringIO()
    old = sys.stdout
    sys.stdout = buf
    try:
        rc = fn()
    finally:
        sys.stdout = old
    if rc not in (0, None):
        raise RuntimeError(f"printer rc={rc}")
    return buf.getvalue()


def _validate() -> dict:
    ea1._validate_reason_vocab()
    ea1._validate_algebra()
    suf._validate()
    auth._validate()
    rew._validate()
    e2e._validate()
    xid._validate()

    contract = _capture(ea1.print_evidence_decision_contract)
    if "decision-subject usable" not in contract:
        raise RuntimeError("ea-1-subject")
    if "decision-subject sufficient" in contract:
        raise RuntimeError("ea-1-still-usable-only")
    if "rewrite-path no" not in contract:
        raise RuntimeError("ea-1-path")

    if len(suf._cases()) != 16:
        raise RuntimeError("suf-cases")
    if len(auth._cases()) != 20:
        raise RuntimeError("auth-cases")
    if len(rew._cases()) != 18:
        raise RuntimeError("rew-cases")

    apply_host = _RUNTIME / "record_storage_apply.py"
    if apply_host.exists():
        raise RuntimeError("apply-host-present")

    return {
        "ea-1": "usable",
        "6c-m": 16,
        "7a": 20,
        "7b": 18,
        "legacy-rce": "pass",
        "legacy-xid": "pass",
        "apply-contract": "specification-only",
        "ir-mutation": "none",
    }


def print_contract() -> int:
    _validate()
    print("semantic-baseline-v1 gate=query")
    print("checkpoint verification-only")
    print("semantic-expansion none")
    print("main-merge 136")
    print("main-merge 137")
    print("main-merge 138")
    print("main-merge-139 no")
    print("apply-inhabitant closed")
    print("decision-stack usable")
    print("decision-stack sufficient")
    print("decision-stack authorized")
    print("decision-stack rewrite-license")
    print("decision-stack rewrite-plan")
    print("ea-1-subject usable")
    print("ea-1-still-usable-only yes")
    print("sufficiency-matrix-cases 16")
    print("authorization-matrix-cases 20")
    print("rewrite-matrix-cases 18")
    print("legacy-rce pass")
    print("legacy-xid pass")
    print("apply-contract specification-only")
    print("apply-contract-on-main no")
    print("ir-mutation none")
    print("f-storage-schedule none")
    print("producer ea-1 usable")
    print("producer sufficiency sufficient")
    print("producer authorization authorized")
    print("producer authorization rewrite-license")
    print("producer rewrite-planner rewrite-plan")
    print("schema-usable s2c2.decision.v1")
    print("schema-sufficient s2c2.sufficiency.v1")
    print("schema-authorized s2c2.authorization.v1")
    print("schema-rewrite-plan s2c2.storage_rewrite.v1")
    print("source-schema-sufficient s2c2.decision.v1")
    print("source-schema-authorization s2c2.decision.v1")
    print("source-schema-rewrite s2c2.authorization.v1")
    print("identity-usable selected-object")
    print("identity-sufficient selected-object")
    print("identity-authorized selected-object-action")
    print("identity-rewrite-license selected-object-action-license-kind")
    print("identity-rewrite-plan selected-object-action-license-kind")
    print(f"action {auth.ACTION_V01}")
    print(f"license-kind {auth.LICENSE_KIND_V01}")
    print("host-side-decision-contract yes")
    print("compiler-e2e no")
    print("can-run-plan no")
    print("rewrite-path no")
    print("applied no")
    print("rewrite-license-from-ea-1 no")
    print("capability-schedule-ne-god-object yes")
    print("note seven-a-consume-six-c-m")
    print("note seven-b-consume-seven-a")
    print("note apply-not-merged")
    print("note apply-inhabitant-closed")
    print("cost=unchanged")
    return 0


def print_summary() -> int:
    _validate()
    print("semantic-baseline-v1-summary gate=query")
    print("layer EA-1 result=usable producer=record_decision.py schema=s2c2.decision.v1")
    print(
        "layer 6C-M result=sufficient producer=record_sufficiency.py "
        "schema=s2c2.sufficiency.v1 cases=16"
    )
    print(
        "layer 7A result=authorized,rewrite-license "
        "producer=record_authorization.py schema=s2c2.authorization.v1 cases=20"
    )
    print(
        "layer 7B result=rewrite-plan producer=record_storage_rewrite.py "
        "schema=s2c2.storage_rewrite.v1 cases=18"
    )
    print("layer apply-contract result=specification-only merged=no")
    print("layer ir-mutation result=none")
    print("layer f-storage-schedule result=none")
    print("failure-class semantic-vs-execution yes")
    print("can-run-plan no")
    print("rewrite-path no")
    print("applied no")
    print("example-identity-sufficient "
          f"selected={suf.SELECTED_S0} object={suf.OBJECT_2}")
    print(
        "example-identity-authorized "
        f"selected={auth.SELECTED_S0} object={auth.OBJECT_2} "
        f"action={auth.ACTION_V01}"
    )
    print(
        "example-identity-rewrite-plan "
        f"selected={rew.SELECTED_S0} object={rew.OBJECT_2} "
        f"action={rew.ACTION_V01} license-kind={rew.LICENSE_KIND_V01}"
    )
    print("cost=unchanged")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Semantic Baseline v1")
    p.add_argument("--print-semantic-baseline-contract", action="store_true")
    p.add_argument("--print-semantic-baseline-summary", action="store_true")
    args = p.parse_args(argv)
    flags = (
        args.print_semantic_baseline_contract,
        args.print_semantic_baseline_summary,
    )
    if sum(bool(x) for x in flags) != 1:
        print(
            "record_semantic_baseline: choose one of "
            "--print-semantic-baseline-contract "
            "--print-semantic-baseline-summary",
            file=sys.stderr,
        )
        return 2
    if args.print_semantic_baseline_contract:
        return print_contract()
    return print_summary()


if __name__ == "__main__":
    sys.exit(main())
