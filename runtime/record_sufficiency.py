#!/usr/bin/env python3
"""6C-M Sufficiency Decision — SufficiencyEvaluator.

Decision.subject=sufficient is a named Decision, not a
printer AND of usable/applicable. Query only.
rewrite-license=no. can-run-plan=no. authorization=n/a.
Do not FileCheck microseconds. Do not expand
S2C2CapabilitySchedule.cpp.
"""

from __future__ import annotations

import argparse
import json
import sys

DECISION_SCHEMA = "s2c2.decision.v1"
SUFFICIENCY_SCHEMA = "s2c2.sufficiency.v1"
REQUIRED = (
    "usable",
    "restore-ordering",
    "dest-invalidation",
    "capacity-legal",
)
IGNORED_EXTRA = ("applicable", "authorized")
RESULTS = ("yes", "no", "n/a")
SELECTED_S0 = "keep{0,1}|evict{2}|rematerialize{}"
OBJECT_2 = "2"


def _decision(result: str, reasons: list[str]) -> dict:
    return {
        "schema": DECISION_SCHEMA,
        "subject": "sufficient",
        "result": result,
        "reasons": reasons,
    }


def _envelope(
    decision: dict,
    inputs: list[dict],
    *,
    selected: str = SELECTED_S0,
    obj: str = OBJECT_2,
) -> dict:
    return {
        "schema": SUFFICIENCY_SCHEMA,
        "source-schema": DECISION_SCHEMA,
        "identity": {"selected": selected, "object": obj},
        "inputs": [{"subject": i["subject"], "result": i.get("result", "absent")} for i in inputs],
        "decision": decision,
        "sufficiency-evaluation": "evaluated",
        "can-run-plan": "no",
        "authorization": "n/a",
        "rewrite-license": "no",
        "rewrite-path": "no",
    }


def evaluate_sufficiency(inputs: list[dict]) -> dict:
    """Decision.subject=sufficient over independent required inputs.

    Does not AND usable with applicable. Extra subjects are
    ignored. Duplicate subject is safe no.
    """
    by: dict[str, dict] = {}
    for rec in inputs:
        subject = rec.get("subject")
        if not subject:
            return _envelope(_decision("no", ["decision.unknown-reason"]), inputs)
        if subject in by:
            return _envelope(_decision("no", ["decision.duplicate-identity"]), inputs)
        by[subject] = rec

    reasons: list[str] = []
    all_yes = True
    missing = False
    for req in REQUIRED:
        rec = by.get(req)
        if rec is None:
            all_yes = False
            missing = True
            continue
        result = rec.get("result")
        if result == "yes":
            continue
        all_yes = False
        if result == "no":
            reasons.append(f"predicate.{req}-no")
        elif result == "n/a":
            reasons.append(f"predicate.{req}-n/a")
        else:
            reasons.append("decision.unknown-reason")
    if missing:
        reasons.append("predicate.missing-input")
    if all_yes:
        return _envelope(_decision("yes", ["decision.sufficient-closed"]), inputs)
    return _envelope(_decision("no", reasons), inputs)


def _inp(subject: str, result: str) -> dict:
    return {"subject": subject, "result": result}


def _all_yes() -> list[dict]:
    return [_inp(req, "yes") for req in REQUIRED]


def _cases() -> list[tuple[str, list[dict]]]:
    yes = {req: _inp(req, "yes") for req in REQUIRED}
    return [
        ("all-required-yes", _all_yes()),
        (
            "dest-inv-historic",
            [yes["usable"], yes["restore-ordering"], yes["dest-invalidation"]],
        ),
        (
            "usable-and-applicable-ne-sufficient",
            [_inp("usable", "yes"), _inp("applicable", "yes")],
        ),
        (
            "usable-no",
            [_inp("usable", "no")]
            + [yes[r] for r in REQUIRED if r != "usable"],
        ),
        (
            "restore-ordering-no",
            [_inp("restore-ordering", "no")]
            + [yes[r] for r in REQUIRED if r != "restore-ordering"],
        ),
        (
            "dest-invalidation-no",
            [_inp("dest-invalidation", "no")]
            + [yes[r] for r in REQUIRED if r != "dest-invalidation"],
        ),
        (
            "capacity-legal-no",
            [_inp("capacity-legal", "no")]
            + [yes[r] for r in REQUIRED if r != "capacity-legal"],
        ),
        (
            "dest-invalidation-n/a",
            [_inp("dest-invalidation", "n/a")]
            + [yes[r] for r in REQUIRED if r != "dest-invalidation"],
        ),
        (
            "missing-usable",
            [yes[r] for r in REQUIRED if r != "usable"],
        ),
        (
            "ignore-applicable-extra",
            _all_yes() + [_inp("applicable", "no")],
        ),
        (
            "duplicate-usable",
            [_inp("usable", "yes"), _inp("usable", "no")]
            + [yes[r] for r in REQUIRED if r != "usable"],
        ),
        (
            "ignore-authorized-extra",
            _all_yes() + [_inp("authorized", "yes")],
        ),
    ]


def _validate() -> None:
    names = [n for n, _ in _cases()]
    expect = [
        "all-required-yes",
        "dest-inv-historic",
        "usable-and-applicable-ne-sufficient",
        "usable-no",
        "restore-ordering-no",
        "dest-invalidation-no",
        "capacity-legal-no",
        "dest-invalidation-n/a",
        "missing-usable",
        "ignore-applicable-extra",
        "duplicate-usable",
        "ignore-authorized-extra",
    ]
    if names != expect:
        raise RuntimeError(names)
    if len(names) != 12:
        raise RuntimeError(len(names))
    for name, inputs in _cases():
        bag = evaluate_sufficiency(inputs)
        if bag["schema"] != SUFFICIENCY_SCHEMA:
            raise RuntimeError(name)
        if bag["source-schema"] != DECISION_SCHEMA:
            raise RuntimeError(name)
        if bag["sufficiency-evaluation"] != "evaluated":
            raise RuntimeError(name)
        if bag["can-run-plan"] != "no":
            raise RuntimeError(name)
        if bag["authorization"] != "n/a":
            raise RuntimeError(name)
        if bag["rewrite-license"] != "no" or bag["rewrite-path"] != "no":
            raise RuntimeError(name)
        decision = bag["decision"]
        if decision["schema"] != DECISION_SCHEMA:
            raise RuntimeError(name)
        if decision["subject"] != "sufficient":
            raise RuntimeError(name)
        if decision["result"] not in ("yes", "no"):
            raise RuntimeError(name)
        for token in decision["reasons"]:
            if token.startswith("authorization."):
                raise RuntimeError(name)
        if name == "all-required-yes":
            if decision["result"] != "yes":
                raise RuntimeError(name)
            if decision["reasons"] != ["decision.sufficient-closed"]:
                raise RuntimeError(name)
        if name == "dest-inv-historic":
            if decision["result"] != "no":
                raise RuntimeError(name)
            if decision["reasons"] != ["predicate.missing-input"]:
                raise RuntimeError(name)
        if name == "usable-and-applicable-ne-sufficient":
            if decision["result"] != "no":
                raise RuntimeError(name)
            if decision["reasons"] != ["predicate.missing-input"]:
                raise RuntimeError(name)
        if name == "usable-no":
            if decision["reasons"] != ["predicate.usable-no"]:
                raise RuntimeError(name)
        if name == "restore-ordering-no":
            if decision["reasons"] != ["predicate.restore-ordering-no"]:
                raise RuntimeError(name)
        if name == "dest-invalidation-no":
            if decision["reasons"] != ["predicate.dest-invalidation-no"]:
                raise RuntimeError(name)
        if name == "capacity-legal-no":
            if decision["reasons"] != ["predicate.capacity-legal-no"]:
                raise RuntimeError(name)
        if name == "dest-invalidation-n/a":
            if decision["reasons"] != ["predicate.dest-invalidation-n/a"]:
                raise RuntimeError(name)
        if name == "missing-usable":
            if decision["reasons"] != ["predicate.missing-input"]:
                raise RuntimeError(name)
        if name == "ignore-applicable-extra":
            if decision["result"] != "yes":
                raise RuntimeError(name)
            if decision["reasons"] != ["decision.sufficient-closed"]:
                raise RuntimeError(name)
        if name == "duplicate-usable":
            if decision["reasons"] != ["decision.duplicate-identity"]:
                raise RuntimeError(name)
        if name == "ignore-authorized-extra":
            if decision["result"] != "yes":
                raise RuntimeError(name)
            if bag["authorization"] != "n/a":
                raise RuntimeError(name)
            if any(t.startswith("authorization.") for t in decision["reasons"]):
                raise RuntimeError(name)


def print_contract() -> int:
    _validate()
    print("sufficiency-evaluator gate=query")
    print(f"schema {SUFFICIENCY_SCHEMA}")
    print(f"decision-schema {DECISION_SCHEMA}")
    print("decision-subject sufficient")
    print("decision-has-subject yes")
    print("evaluator-ne-printer-and yes")
    print("usable-ne-sufficient yes")
    print("applicable-ne-sufficient yes")
    print("usable-and-applicable-ne-sufficient yes")
    print("dest-invalidation-ne-sufficient yes")
    print("sufficient-ne-authorized yes")
    print("sufficient-ne-rewrite-license yes")
    print("sufficient-yes-ne-rewrite-license yes")
    print("sufficient-ne-can-run-plan yes")
    print("six-c-i-predicate-ne-six-c-m yes")
    print("ea-1-still-usable-only yes")
    print("sufficiency-evaluation evaluated")
    print("can-run-plan no")
    print("authorization n/a")
    print("rewrite-license no")
    print("rewrite-path no")
    print("capability-schedule-ne-god-object yes")
    print("generic-schema-validator n/a")
    print("sufficiency-matrix-cases 12")
    for req in REQUIRED:
        print(f"required-predicate {req}")
    for extra in IGNORED_EXTRA:
        print(f"ignored-extra {extra}")
    print("note six-c-m-opened")
    print("note seven-a-authorization-closed")
    print("note rewrite-closed")
    print("note ea-1-still-usable-only")
    print("note six-c-i-sufficient-no-unchanged")
    print("note f-storage-schedule-not-inhabited")
    print("note live-bytes-not-opened")
    print("note alias-not-opened")
    print("note lifetime-not-opened")
    print("note evidence-db-identity-frozen")
    print("note default-3g-frozen")
    print("note cost-v04-structural-frozen")
    print("note rewrite=no")
    print("cost=unchanged")
    example = evaluate_sufficiency(_all_yes())
    print("example " + json.dumps(example, separators=(",", ":"), sort_keys=True))
    return 0


def print_matrix() -> int:
    _validate()
    print("sufficiency-matrix gate=query")
    print("decision-subject sufficient")
    print("usable-and-applicable-ne-sufficient yes")
    print("dest-invalidation-ne-sufficient yes")
    print("sufficient-ne-authorized yes")
    print("sufficiency-matrix-cases 12")
    for name, inputs in _cases():
        bag = evaluate_sufficiency(inputs)
        decision = bag["decision"]
        print(f"suf-case {name}")
        for req in REQUIRED:
            rec = next((i for i in inputs if i["subject"] == req), None)
            result = rec["result"] if rec else "absent"
            print(f"suf-input subject={req} result={result}")
        extras = [i for i in inputs if i["subject"] not in REQUIRED]
        for extra in extras:
            print(
                f"suf-extra subject={extra['subject']} result={extra['result']}"
            )
        reasons = ",".join(decision["reasons"]) if decision["reasons"] else "none"
        print(
            "suf-decision "
            f"subject={decision['subject']} "
            f"result={decision['result']} "
            f"reasons={reasons}"
        )
        print(f"suf-sufficiency-evaluation {bag['sufficiency-evaluation']}")
        print(f"suf-can-run-plan {bag['can-run-plan']}")
        print(f"suf-authorization {bag['authorization']}")
        print(f"suf-rewrite-license {bag['rewrite-license']}")
        print(f"suf-rewrite-path {bag['rewrite-path']}")
    print("rewrite-license no")
    print("rewrite-path no")
    print("can-run-plan no")
    print("authorization n/a")
    print("note six-c-m-opened")
    print("note seven-a-authorization-closed")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Sufficiency Decision (6C-M)")
    p.add_argument("--print-sufficiency-contract", action="store_true")
    p.add_argument("--print-sufficiency-matrix", action="store_true")
    args = p.parse_args(argv)
    flags = (
        args.print_sufficiency_contract,
        args.print_sufficiency_matrix,
    )
    if sum(bool(x) for x in flags) != 1:
        print(
            "record_sufficiency: choose one of "
            "--print-sufficiency-contract "
            "--print-sufficiency-matrix",
            file=sys.stderr,
        )
        return 2
    if args.print_sufficiency_contract:
        return print_contract()
    return print_matrix()


if __name__ == "__main__":
    sys.exit(main())
