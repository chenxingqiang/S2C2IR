#!/usr/bin/env python3
"""Semantic Baseline v1 — replay frozen Decision hosts on main.

Composes EA-1 / 6C-M / 7A / 7B / legacy RCE+XID.
#139 is merged. The apply host may exist. This replay does not
execute it. Query only. Do not FileCheck microseconds.
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


_REPO = _RUNTIME.parent
_FROZEN_APPLY_SCHEDULE = _REPO / "lib/Analysis/S2C2Capability/S2C2CapabilitySchedule.cpp"


def _pin_critical() -> None:
    suf_cases = dict(suf._cases())
    usable_and = suf.evaluate_sufficiency(
        suf_cases["usable-and-applicable-ne-sufficient"]
    )
    if usable_and["decision"]["result"] != "no":
        raise RuntimeError("usable-and-applicable-ne-sufficient")
    if usable_and["decision"]["subject"] != "sufficient":
        raise RuntimeError("suf-subject")

    auth_cases = dict(auth._cases())
    policy_missing = auth.evaluate_authorization(
        auth_cases["sufficient-yes-policy-missing"]
    )
    if policy_missing["authorized"]["result"] != "no":
        raise RuntimeError("sufficient-yes-policy-missing")
    license_missing = auth.evaluate_authorization(
        auth_cases["authorized-yes-license-missing"]
    )
    if license_missing["authorized"]["result"] != "yes":
        raise RuntimeError("authorized-yes")
    if license_missing["rewrite-license"]["result"] != "no":
        raise RuntimeError("license-missing")
    for token in auth.AUTHORIZATION_REASON_TOKENS:
        if not token.startswith("authorization."):
            raise RuntimeError(token)

    for name, inputs, kwargs in rew._cases():
        if name != "rewrite-plan-yes":
            continue
        bag = rew.evaluate_rewrite(inputs, **kwargs)
        if bag["rewrite-plan"]["result"] != "yes":
            raise RuntimeError("rewrite-plan-yes")
        if bag["applied"] != "no":
            raise RuntimeError("applied")
        if bag["rewrite-path"] != "no":
            raise RuntimeError("rewrite-path")
        if bag["can-run-plan"] != "no":
            raise RuntimeError("can-run-plan")


def _guard_execution() -> None:
    apply_host = (_RUNTIME / "record_storage_apply.py").resolve()
    for path in _REPO.rglob("*storage_apply*"):
        if ".git" in path.parts or "__pycache__" in path.parts:
            continue
        if path.resolve() == apply_host:
            continue
        raise RuntimeError(f"apply-artifact {path}")
    for path in _REPO.rglob("*StorageApply*"):
        if ".git" in path.parts:
            continue
        raise RuntimeError(f"apply-artifact {path}")
    for path in (_REPO / "lib").rglob("*.cpp"):
        text = path.read_text(errors="replace")
        if "applySchedule" not in text:
            continue
        if path.resolve() != _FROZEN_APPLY_SCHEDULE.resolve():
            raise RuntimeError(f"applySchedule-leak {path}")
    for path in _RUNTIME.glob("record_*.py"):
        if path.name == "record_semantic_baseline.py":
            continue
        text = path.read_text()
        if 'can-run-plan": "yes"' in text or "can-run-plan=yes" in text:
            raise RuntimeError(f"can-run-plan-yes {path.name}")
        if path.name == "record_storage_apply.py":
            continue
        if 'applied": "yes"' in text or "applied=yes" in text:
            raise RuntimeError(f"applied-yes {path.name}")
        if 'rewrite-path": "yes"' in text or "rewrite-path=yes" in text:
            raise RuntimeError(f"rewrite-path-yes {path.name}")
        if "construct P'" in text:
            raise RuntimeError(f"construct-p {path.name}")
    for path in (_REPO / "include").rglob("*"):
        if path.is_file() and "F_storage_schedule" in path.name:
            raise RuntimeError(f"f-storage-schedule {path}")


def _validate() -> dict:
    ea1._validate_reason_vocab()
    ea1._validate_algebra()
    suf._validate()
    auth._validate()
    rew._validate()
    e2e._validate()
    xid._validate()
    _pin_critical()
    _guard_execution()

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

    return {
        "ea-1": "usable",
        "6c-m": 16,
        "7a": 20,
        "7b": 18,
        "legacy-rce": "pass",
        "legacy-xid": "pass",
        "apply-contract": "merged",
        "apply-host": "present-not-replayed",
        "ir-mutation-by-replay": "none",
    }


def print_contract() -> int:
    _validate()
    print("semantic-baseline-v1 gate=query")
    print("checkpoint verification-only")
    print("semantic-expansion none")
    print("main-merge 136")
    print("main-merge 137")
    print("main-merge 138")
    print("main-merge 139")
    print("apply-host present")
    print("baseline-replay-executes-apply no")
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
    print("apply-contract merged")
    print("apply-contract-on-main yes")
    print("ir-mutation-by-replay none")
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
    print("note apply-contract-merged")
    print("note baseline-does-not-execute-apply")
    print("pin usable-and-applicable-ne-sufficient yes")
    print("pin sufficient-yes-policy-missing authorized=no")
    print("pin authorized-yes-license-missing rewrite-license=no")
    print("pin rewrite-plan-yes applied=no")
    print("guard baseline-skips-apply-host yes")
    print("guard applySchedule frozen-capability-schedule-only")
    print("result PASS")
    print("Semantic Baseline v1 = PASS")
    print("cost=unchanged")
    return 0


def print_summary() -> int:
    _validate()
    print("semantic-baseline-v1-summary gate=query")
    print("EA-1")
    print("  producer = record_decision.py")
    print("  subject  = usable")
    print("6C-M")
    print("  producer = record_sufficiency.py")
    print("  subject  = sufficient")
    print("  cases    = 16/16")
    print("7A")
    print("  producer = record_authorization.py")
    print("  subjects = authorized + rewrite-license")
    print("  cases    = 20/20")
    print("7B")
    print("  producer = record_storage_rewrite.py")
    print("  subject  = rewrite-plan")
    print("  cases    = 18/18")
    print("Apply")
    print("  producer = record_storage_apply.py")
    print("  status   = not-replayed")
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
    print("layer apply-contract result=merged")
    print("layer apply-host present replay=no")
    print("layer ir-mutation-by-replay result=none")
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
    print("result PASS")
    print("Semantic Baseline v1 = PASS")
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
