#!/usr/bin/env python3
"""7B Storage Rewrite Plan — RewritePlanner.

Decision.subject=rewrite-plan.
rewrite-license ≠ rewrite-plan ≠ rewrite-path. Query only.
Unique sequence KEEP → EVICT → TRANSFER → RESTORE.
applied=no. rewrite-path=no.
Do not FileCheck microseconds. Do not expand
S2C2CapabilitySchedule.cpp. Do not edit
record_authorization.py or record_sufficiency.py.
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_authorization as auth

DECISION_SCHEMA = "s2c2.decision.v1"
REWRITE_SCHEMA = "s2c2.storage_rewrite.v1"
AUTH_SCHEMA = auth.AUTH_SCHEMA
SEQUENCE_SUBJECT = "rewrite-sequence"
SEQUENCE_V01 = ("KEEP", "EVICT", "TRANSFER", "RESTORE")
TRANSFORMATION_V01 = "keep-evict-transfer-restore"
ACTION_V01 = auth.ACTION_V01
LICENSE_KIND_V01 = auth.LICENSE_KIND_V01
REWRITE_REASON_TOKENS = (
    "rewrite.license-no",
    "rewrite.identity-mismatch",
    "rewrite.sequence-mismatch",
    "rewrite.duplicate-envelope",
    "rewrite.duplicate-sequence",
    "rewrite.plan-closed",
)
SELECTED_S0 = auth.SELECTED_S0
SELECTED_S1 = auth.SELECTED_S1
OBJECT_2 = auth.OBJECT_2
OBJECT_3 = auth.OBJECT_3


def _decision(result: str, reasons: list[str]) -> dict:
    return {
        "schema": DECISION_SCHEMA,
        "subject": "rewrite-plan",
        "result": result,
        "reasons": reasons,
    }


def _canonical_inputs(
    envelopes: list[dict],
    sequences: list[dict],
    extras_first_seen: list[dict],
) -> list[dict]:
    items = []
    for _ in envelopes:
        items.append({"subject": "authorization", "result": "present"})
    for rec in sequences:
        items.append(
            {
                "subject": SEQUENCE_SUBJECT,
                "result": rec.get("result", "absent"),
            }
        )
    for extra in extras_first_seen:
        items.append(
            {"subject": extra["subject"], "result": extra.get("result", "absent")}
        )
    return items


def _envelope(
    *,
    plan: dict,
    canonical_inputs: list[dict],
    selected: str,
    obj: str,
    action: str,
    license_kind: str,
    sequence,
) -> dict:
    named = TRANSFORMATION_V01 if plan["result"] == "yes" else "n/a"
    seq = list(SEQUENCE_V01) if plan["result"] == "yes" else "n/a"
    if sequence is not None and plan["result"] == "yes":
        seq = list(sequence)
    return {
        "schema": REWRITE_SCHEMA,
        "source-schema": AUTH_SCHEMA,
        "identity": {
            "selected": selected,
            "object": obj,
            "action": action,
            "license-kind": license_kind,
        },
        "inputs": canonical_inputs,
        "rewrite-plan": plan,
        "sequence": seq,
        "transformation": named,
        "applied": "no",
        "can-run-plan": "no",
        "rewrite-path": "no",
    }


def _auth_scope3(bag: dict) -> tuple[str, str, str] | None:
    ident = bag.get("identity")
    if not isinstance(ident, dict):
        return None
    selected = ident.get("selected")
    obj = ident.get("object")
    action = ident.get("action")
    if selected is None or obj is None or action is None:
        return None
    return (selected, obj, action)


def _ident4(ident) -> tuple[str, str, str, str] | None:
    if not isinstance(ident, dict):
        return None
    selected = ident.get("selected")
    obj = ident.get("object")
    action = ident.get("action")
    kind = ident.get("license-kind")
    if selected is None or obj is None or action is None or kind is None:
        return None
    return (selected, obj, action, kind)


def _license_scope4(bag: dict) -> tuple[str, str, str, str] | None:
    return _ident4(bag.get("license-identity"))


def _well_formed_decision(rec, subject: str) -> bool:
    if not isinstance(rec, dict):
        return False
    if rec.get("schema") != DECISION_SCHEMA:
        return False
    if rec.get("subject") != subject:
        return False
    if rec.get("result") not in ("yes", "no"):
        return False
    return True


def _as_sequence(rec: dict) -> tuple[str, ...] | None:
    raw = rec.get("sequence")
    if not isinstance(raw, (list, tuple)):
        return None
    if not all(isinstance(step, str) for step in raw):
        return None
    return tuple(raw)


def evaluate_rewrite(
    inputs: list[dict],
    *,
    selected: str = SELECTED_S0,
    obj: str = OBJECT_2,
    action: str = ACTION_V01,
    license_kind: str = LICENSE_KIND_V01,
) -> dict:
    """rewrite-plan over (selected, object, action, license-kind)."""
    expect3 = (selected, obj, action)
    expect4 = (selected, obj, action, license_kind)
    envelopes: list[dict] = []
    sequences: list[dict] = []
    extras_first: list[dict] = []
    extras_seen: set[str] = set()

    def emit(plan: dict, sequence=None) -> dict:
        return _envelope(
            plan=plan,
            canonical_inputs=_canonical_inputs(envelopes, sequences, extras_first),
            selected=selected,
            obj=obj,
            action=action,
            license_kind=license_kind,
            sequence=sequence,
        )

    for rec in inputs:
        schema = rec.get("schema")
        subject = rec.get("subject")
        if schema == AUTH_SCHEMA:
            envelopes.append(rec)
            continue
        if subject == SEQUENCE_SUBJECT:
            sequences.append(rec)
            continue
        if not subject:
            return emit(_decision("no", ["decision.unknown-reason"]))
        if subject not in extras_seen:
            extras_seen.add(subject)
            extras_first.append(rec)

    if len(envelopes) == 0:
        return emit(_decision("no", ["predicate.missing-input"]))
    if len(envelopes) > 1:
        return emit(_decision("no", ["rewrite.duplicate-envelope"]))
    if len(sequences) > 1:
        return emit(_decision("no", ["rewrite.duplicate-sequence"]))

    bag = envelopes[0]
    if bag.get("schema") != AUTH_SCHEMA:
        return emit(_decision("no", ["decision.unknown-reason"]))
    if bag.get("source-schema") != DECISION_SCHEMA:
        return emit(_decision("no", ["decision.unknown-reason"]))
    authorized = bag.get("authorized")
    license_decision = bag.get("rewrite-license")
    if not _well_formed_decision(authorized, "authorized"):
        return emit(_decision("no", ["decision.unknown-reason"]))
    if not _well_formed_decision(license_decision, "rewrite-license"):
        return emit(_decision("no", ["decision.unknown-reason"]))
    if license_decision["result"] == "yes" and authorized["result"] != "yes":
        return emit(_decision("no", ["decision.unknown-reason"]))
    if _auth_scope3(bag) != expect3:
        return emit(_decision("no", ["rewrite.identity-mismatch"]))
    if license_decision["result"] != "yes":
        return emit(_decision("no", ["rewrite.license-no"]))
    license_scope = _license_scope4(bag)
    if license_scope != expect4:
        return emit(_decision("no", ["rewrite.identity-mismatch"]))
    if "identity" in license_decision:
        claimed_license = _ident4(license_decision.get("identity"))
        if claimed_license is None:
            return emit(_decision("no", ["decision.unknown-reason"]))
        if claimed_license != license_scope or claimed_license != expect4:
            return emit(_decision("no", ["rewrite.identity-mismatch"]))

    claimed = None
    if sequences:
        claimed = _as_sequence(sequences[0])
        if claimed is None or claimed != SEQUENCE_V01:
            return emit(_decision("no", ["rewrite.sequence-mismatch"]))
    return emit(_decision("yes", ["rewrite.plan-closed"]), SEQUENCE_V01)


def _licensed() -> dict:
    return auth.evaluate_authorization(auth._all_required() + [auth._license("yes")])


def _license_missing() -> dict:
    return auth.evaluate_authorization(auth._all_required())


def _license_no() -> dict:
    return auth.evaluate_authorization(auth._all_required() + [auth._license("no")])


def _authorized_no() -> dict:
    return auth.evaluate_authorization(
        [
            auth._sufficient("no"),
            auth._policy(),
            auth._provenance(),
            auth._action(),
            auth._license("yes"),
        ]
    )


def _sequence(steps: tuple[str, ...] = SEQUENCE_V01) -> dict:
    return {
        "subject": SEQUENCE_SUBJECT,
        "result": "yes",
        "sequence": list(steps),
    }


def _tamper(bag: dict, **fields) -> dict:
    out = copy.deepcopy(bag)
    out.update(fields)
    return out


def _malformed_authorized() -> dict:
    bag = _tamper(_licensed())
    bag["authorized"]["result"] = "no"
    return bag


def _malformed_rewrite_license() -> dict:
    bag = _tamper(_licensed())
    bag["rewrite-license"] = {"result": "yes"}
    return bag


def _source_schema_mismatch() -> dict:
    return _tamper(_licensed(), **{"source-schema": "s2c2.nope.v1"})


def _license_identity_drift() -> dict:
    bag = _tamper(_licensed())
    bag["rewrite-license"]["identity"] = {
        "selected": SELECTED_S1,
        "object": OBJECT_2,
        "action": ACTION_V01,
        "license-kind": LICENSE_KIND_V01,
    }
    return bag


def _cases() -> list[tuple[str, list[dict], dict]]:
    licensed = _licensed()
    return [
        ("license-missing", [_license_missing()], {}),
        ("license-no", [_license_no()], {}),
        ("authorized-no", [_authorized_no()], {}),
        ("rewrite-plan-yes", [licensed], {}),
        ("matching-sequence", [licensed, _sequence()], {}),
        (
            "selected-mismatch",
            [licensed],
            {"selected": SELECTED_S1},
        ),
        ("object-mismatch", [licensed], {"obj": OBJECT_3}),
        (
            "action-mismatch",
            [licensed],
            {"action": "schedule-rewrite"},
        ),
        (
            "license-kind-mismatch",
            [licensed],
            {"license_kind": "other-kind"},
        ),
        (
            "wrong-sequence",
            [licensed, _sequence(("PREFETCH", "PRESERVE"))],
            {},
        ),
        (
            "duplicate-sequence",
            [licensed, _sequence(), _sequence()],
            {},
        ),
        ("duplicate-envelope", [licensed, licensed], {}),
        ("unknown-schema", [{"schema": "s2c2.nope.v1"}], {}),
        (
            "extras-ignored",
            [licensed, {"subject": "cost-rank", "result": "yes"}],
            {},
        ),
        ("malformed-authorized", [_malformed_authorized()], {}),
        ("malformed-rewrite-license", [_malformed_rewrite_license()], {}),
        ("source-schema-mismatch", [_source_schema_mismatch()], {}),
        ("license-identity-drift", [_license_identity_drift()], {}),
    ]


def _validate() -> None:
    names = [n for n, _, _ in _cases()]
    expect = [
        "license-missing",
        "license-no",
        "authorized-no",
        "rewrite-plan-yes",
        "matching-sequence",
        "selected-mismatch",
        "object-mismatch",
        "action-mismatch",
        "license-kind-mismatch",
        "wrong-sequence",
        "duplicate-sequence",
        "duplicate-envelope",
        "unknown-schema",
        "extras-ignored",
        "malformed-authorized",
        "malformed-rewrite-license",
        "source-schema-mismatch",
        "license-identity-drift",
    ]
    if names != expect:
        raise RuntimeError(names)
    if len(names) != 18:
        raise RuntimeError(len(names))
    for token in REWRITE_REASON_TOKENS:
        if not token.startswith("rewrite."):
            raise RuntimeError(token)
    for token in (
        "decision.plan-closed",
        "authorization.plan-closed",
    ):
        if token in REWRITE_REASON_TOKENS:
            raise RuntimeError(f"must not reopen {token}")
    emitted: set[str] = set()
    for name, inputs, kwargs in _cases():
        bag = evaluate_rewrite(inputs, **kwargs)
        if bag["schema"] != REWRITE_SCHEMA:
            raise RuntimeError(name)
        ident = bag["identity"]
        if ident["action"] != kwargs.get("action", ACTION_V01):
            raise RuntimeError(name)
        if bag["can-run-plan"] != "no" or bag["rewrite-path"] != "no":
            raise RuntimeError(name)
        if bag["applied"] != "no":
            raise RuntimeError(name)
        plan = bag["rewrite-plan"]
        if plan["subject"] != "rewrite-plan":
            raise RuntimeError(name)
        if plan["result"] not in ("yes", "no"):
            raise RuntimeError(name)
        if plan["result"] == "yes" and bag["rewrite-path"] == "yes":
            raise RuntimeError(f"plan without path freeze: {name}")
        for token in plan["reasons"]:
            if token.startswith("rewrite.") and token not in REWRITE_REASON_TOKENS:
                raise RuntimeError(f"{name} unknown rewrite token {token}")
            emitted.add(token)
        if name in ("license-missing", "license-no", "authorized-no"):
            if plan["reasons"] != ["rewrite.license-no"]:
                raise RuntimeError(name)
            if bag["sequence"] != "n/a" or bag["transformation"] != "n/a":
                raise RuntimeError(name)
        if name in ("rewrite-plan-yes", "matching-sequence", "extras-ignored"):
            if plan["result"] != "yes":
                raise RuntimeError(name)
            if plan["reasons"] != ["rewrite.plan-closed"]:
                raise RuntimeError(name)
            if bag["sequence"] != list(SEQUENCE_V01):
                raise RuntimeError(name)
            if bag["transformation"] != TRANSFORMATION_V01:
                raise RuntimeError(name)
            if bag["applied"] != "no" or bag["rewrite-path"] != "no":
                raise RuntimeError(name)
        if name == "extras-ignored":
            extras = [i for i in bag["inputs"] if i["subject"] == "cost-rank"]
            if extras != [{"subject": "cost-rank", "result": "yes"}]:
                raise RuntimeError(name)
        if name in (
            "selected-mismatch",
            "object-mismatch",
            "action-mismatch",
            "license-kind-mismatch",
        ):
            if plan["reasons"] != ["rewrite.identity-mismatch"]:
                raise RuntimeError(name)
        if name == "wrong-sequence":
            if plan["reasons"] != ["rewrite.sequence-mismatch"]:
                raise RuntimeError(name)
        if name == "duplicate-sequence":
            if plan["reasons"] != ["rewrite.duplicate-sequence"]:
                raise RuntimeError(name)
            if [i["subject"] for i in bag["inputs"]].count(SEQUENCE_SUBJECT) != 2:
                raise RuntimeError(name)
        if name == "duplicate-envelope":
            if plan["reasons"] != ["rewrite.duplicate-envelope"]:
                raise RuntimeError(name)
        if name == "unknown-schema":
            if plan["reasons"] != ["decision.unknown-reason"]:
                raise RuntimeError(name)
        if name == "matching-sequence":
            if [i["subject"] for i in bag["inputs"]].count(SEQUENCE_SUBJECT) != 1:
                raise RuntimeError(name)
        if name in (
            "malformed-authorized",
            "malformed-rewrite-license",
            "source-schema-mismatch",
        ):
            if plan["result"] != "no":
                raise RuntimeError(name)
            if plan["reasons"] != ["decision.unknown-reason"]:
                raise RuntimeError(name)
        if name == "license-identity-drift":
            if plan["reasons"] != ["rewrite.identity-mismatch"]:
                raise RuntimeError(name)
        if name == "malformed-authorized":
            rec = inputs[0]
            if rec["authorized"]["schema"] != DECISION_SCHEMA:
                raise RuntimeError(name)
            if rec["authorized"]["result"] != "no":
                raise RuntimeError(name)
            if rec["rewrite-license"]["result"] != "yes":
                raise RuntimeError(name)
        if name == "malformed-rewrite-license":
            rec = inputs[0]
            if rec["rewrite-license"] != {"result": "yes"}:
                raise RuntimeError(name)
        if name == "source-schema-mismatch":
            if inputs[0]["schema"] != AUTH_SCHEMA:
                raise RuntimeError(name)
            if inputs[0]["source-schema"] == DECISION_SCHEMA:
                raise RuntimeError(name)
    for token in (
        "rewrite.plan-closed",
        "rewrite.identity-mismatch",
        "rewrite.duplicate-sequence",
        "rewrite.duplicate-envelope",
        "rewrite.sequence-mismatch",
        "rewrite.license-no",
    ):
        if token not in emitted:
            raise RuntimeError(f"matrix did not emit {token}")
    if "decision.plan-closed" in emitted:
        raise RuntimeError("success path reopened decision.*")


def print_contract() -> int:
    _validate()
    print("rewrite-planner gate=query")
    print(f"schema {REWRITE_SCHEMA}")
    print(f"decision-schema {DECISION_SCHEMA}")
    print("decision-subject rewrite-plan")
    print("rewrite-identity selected-object-action-license-kind")
    print(f"action {ACTION_V01}")
    print(f"license-kind {LICENSE_KIND_V01}")
    print("sequence KEEP,EVICT,TRANSFER,RESTORE")
    print("rewrite-license-ne-rewrite-plan yes")
    print("rewrite-plan-ne-rewrite-path yes")
    print("rewrite-plan-yes-ne-rewrite-path yes")
    print("rewrite-plan-yes-ne-applied yes")
    print("rewrite-plan-yes-ne-can-run-plan yes")
    print("sequence-input-not-ignored-extra yes")
    print("duplicate-sequence-safe-no yes")
    print("duplicate-envelope-safe-no yes")
    print("envelope-decision-contract yes")
    print("source-schema-consumed s2c2.decision.v1")
    print("license-identity-eq-rewrite-license-identity yes")
    print("rewrite-namespace v0.1")
    print("ea-1-authorization-tokens none")
    print("authorization-namespace frozen")
    print("host-side-decision-contract yes")
    print("compiler-e2e no")
    print("can-run-plan no")
    print("rewrite-path no")
    print("applied no")
    print("capability-schedule-ne-god-object yes")
    print("f-storage-schedule-not-inhabited yes")
    print("generic-schema-validator n/a")
    print("rewrite-matrix-cases 18")
    print("required-input authorization")
    print(f"sequence-input {SEQUENCE_SUBJECT}")
    for token in REWRITE_REASON_TOKENS:
        print(f"token {token}")
    print("note six-c-m-frozen")
    print("note seven-a-frozen")
    print("note seven-b-opened")
    print("note seven-b-applied-closed")
    print("note f-storage-schedule-not-inhabited")
    print("note rewrite=no")
    print("cost=unchanged")
    example = evaluate_rewrite([_licensed()])
    print("example " + json.dumps(example, separators=(",", ":"), sort_keys=True))
    return 0


def print_matrix() -> int:
    _validate()
    print("rewrite-matrix gate=query")
    print("decision-subject rewrite-plan")
    print("rewrite-license-ne-rewrite-plan yes")
    print("rewrite-plan-ne-rewrite-path yes")
    print("rewrite-matrix-cases 18")
    for name, inputs, kwargs in _cases():
        bag = evaluate_rewrite(inputs, **kwargs)
        plan = bag["rewrite-plan"]
        print(f"rew-case {name}")
        print(
            "rew-scope "
            f"selected={bag['identity']['selected']} "
            f"object={bag['identity']['object']} "
            f"action={bag['identity']['action']} "
            f"license-kind={bag['identity']['license-kind']}"
        )
        envelope_subjects = ",".join(i["subject"] for i in bag["inputs"]) or "none"
        print(f"rew-envelope-inputs {envelope_subjects}")
        plan_reasons = ",".join(plan["reasons"]) if plan["reasons"] else "none"
        print(
            "rew-plan "
            f"subject={plan['subject']} "
            f"result={plan['result']} "
            f"reasons={plan_reasons}"
        )
        seq = bag["sequence"]
        if isinstance(seq, list):
            seq = ",".join(seq)
        print(f"rew-sequence {seq}")
        print(f"rew-transformation {bag['transformation']}")
        print(f"rew-applied {bag['applied']}")
        print(f"rew-can-run-plan {bag['can-run-plan']}")
        print(f"rew-rewrite-path {bag['rewrite-path']}")
    print("can-run-plan no")
    print("rewrite-path no")
    print("applied no")
    print("note seven-b-applied-closed")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Storage Rewrite Plan (7B)")
    p.add_argument("--print-rewrite-contract", action="store_true")
    p.add_argument("--print-rewrite-matrix", action="store_true")
    args = p.parse_args(argv)
    flags = (args.print_rewrite_contract, args.print_rewrite_matrix)
    if sum(bool(x) for x in flags) != 1:
        print(
            "record_storage_rewrite: choose one of "
            "--print-rewrite-contract "
            "--print-rewrite-matrix",
            file=sys.stderr,
        )
        return 2
    if args.print_rewrite_contract:
        return print_contract()
    return print_matrix()


if __name__ == "__main__":
    sys.exit(main())
