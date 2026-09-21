#!/usr/bin/env python3
"""7A Authorization Boundary — AuthorizationEvaluator.

Decision.subject=authorized and Decision.subject=rewrite-license.
sufficient ≠ authorized ≠ rewrite-license. Query only.
Action identity is (selected, object, action). Named action
storage-rewrite is not implemented. rewrite-path=no.
Do not FileCheck microseconds. Do not expand
S2C2CapabilitySchedule.cpp. Do not edit record_sufficiency.py.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_sufficiency as suf

DECISION_SCHEMA = "s2c2.decision.v1"
AUTH_SCHEMA = "s2c2.authorization.v1"
REQUIRED = (
    "sufficient",
    "policy-match",
    "provenance",
    "action-match",
)
POLICY_V01 = "authorization-policy-v0.1"
ACTION_V01 = "storage-rewrite"
LICENSE_KIND_V01 = "storage-capacity-rewrite"
LICENSE_SUBJECT = "rewrite-license"
AUTHORIZATION_REASON_TOKENS = (
    "authorization.sufficient-no",
    "authorization.policy-mismatch",
    "authorization.policy-unknown",
    "authorization.provenance-unknown",
    "authorization.action-mismatch",
    "authorization.authorized-no",
    "authorization.rewrite-license-missing",
    "authorization.rewrite-license-no",
)
SELECTED_S0 = suf.SELECTED_S0
SELECTED_S1 = suf.SELECTED_S1
OBJECT_2 = suf.OBJECT_2
OBJECT_3 = "3"


def _decision(subject: str, result: str, reasons: list[str]) -> dict:
    return {
        "schema": DECISION_SCHEMA,
        "subject": subject,
        "result": result,
        "reasons": reasons,
    }


def _canonical_inputs(
    required_by: dict[str, dict],
    licenses: list[dict],
    extras_first_seen: list[dict],
) -> list[dict]:
    items = []
    for req in REQUIRED:
        rec = required_by.get(req)
        if rec is None:
            continue
        items.append({"subject": req, "result": rec.get("result", "absent")})
    for rec in licenses:
        items.append(
            {"subject": LICENSE_SUBJECT, "result": rec.get("result", "absent")}
        )
    for extra in extras_first_seen:
        items.append(
            {"subject": extra["subject"], "result": extra.get("result", "absent")}
        )
    return items


def _scope2(rec: dict) -> tuple[str, str] | None:
    ident = rec.get("identity")
    if not isinstance(ident, dict):
        return None
    selected = ident.get("selected")
    obj = ident.get("object")
    if selected is None or obj is None:
        return None
    return (selected, obj)


def _scope3(rec: dict) -> tuple[str, str, str] | None:
    pair = _scope2(rec)
    if pair is None:
        return None
    ident = rec.get("identity")
    action = ident.get("action") if isinstance(ident, dict) else None
    if action is None:
        return None
    return (pair[0], pair[1], action)


def _license_scope(rec: dict) -> tuple[str, str, str, str] | None:
    triple = _scope3(rec)
    if triple is None:
        return None
    ident = rec.get("identity")
    kind = ident.get("license-kind") if isinstance(ident, dict) else None
    if kind is None:
        return None
    return (triple[0], triple[1], triple[2], kind)


def _envelope(
    *,
    authorized: dict,
    license_decision: dict,
    canonical_inputs: list[dict],
    selected: str,
    obj: str,
    action: str,
    license_identity: dict | None,
) -> dict:
    return {
        "schema": AUTH_SCHEMA,
        "source-schema": DECISION_SCHEMA,
        "identity": {"selected": selected, "object": obj, "action": action},
        "inputs": canonical_inputs,
        "authorized": authorized,
        "rewrite-license": license_decision,
        "license-identity": license_identity if license_identity is not None else "n/a",
        "can-run-plan": "no",
        "rewrite-path": "no",
        "transformation": "n/a",
    }


def evaluate_authorization(
    inputs: list[dict],
    *,
    selected: str = SELECTED_S0,
    obj: str = OBJECT_2,
    action: str = ACTION_V01,
) -> dict:
    """authorized over (selected, object, action). License is a dedicated input."""
    scope2 = (selected, obj)
    scope3 = (selected, obj, action)
    required_by: dict[str, dict] = {}
    licenses: list[dict] = []
    extras_first: list[dict] = []
    extras_seen: set[str] = set()

    def emit(authorized: dict, license_decision: dict, license_identity=None) -> dict:
        return _envelope(
            authorized=authorized,
            license_decision=license_decision,
            canonical_inputs=_canonical_inputs(required_by, licenses, extras_first),
            selected=selected,
            obj=obj,
            action=action,
            license_identity=license_identity,
        )

    def license_no(reasons: list[str], license_identity=None) -> dict:
        return _decision("rewrite-license", "no", reasons), license_identity

    for rec in inputs:
        subject = rec.get("subject")
        if not subject:
            auth = _decision("authorized", "no", ["decision.unknown-reason"])
            lic, ident = license_no(["authorization.authorized-no"])
            return emit(auth, lic, ident)
        if subject in REQUIRED:
            if subject in required_by:
                auth = _decision("authorized", "no", ["decision.duplicate-identity"])
                lic, ident = license_no(["authorization.authorized-no"])
                return emit(auth, lic, ident)
            required_by[subject] = rec
            continue
        if subject == LICENSE_SUBJECT:
            licenses.append(rec)
            continue
        if subject not in extras_seen:
            extras_seen.add(subject)
            extras_first.append(rec)

    for req in REQUIRED:
        rec = required_by.get(req)
        if rec is None:
            continue
        if req == "sufficient":
            if _scope2(rec) != scope2:
                auth = _decision("authorized", "no", ["decision.identity-mismatch"])
                lic, ident = license_no(["authorization.authorized-no"])
                return emit(auth, lic, ident)
            continue
        if _scope3(rec) != scope3:
            auth = _decision("authorized", "no", ["decision.identity-mismatch"])
            lic, ident = license_no(["authorization.authorized-no"])
            return emit(auth, lic, ident)

    reasons: list[str] = []
    all_yes = True
    missing = False
    for req in REQUIRED:
        rec = required_by.get(req)
        if rec is None:
            all_yes = False
            missing = True
            continue
        result = rec.get("result")
        if req == "sufficient":
            if result == "yes":
                continue
            all_yes = False
            if result == "no":
                reasons.append("authorization.sufficient-no")
            elif result == "n/a":
                reasons.append("authorization.sufficient-no")
            else:
                reasons.append("decision.unknown-reason")
            continue
        if req == "policy-match":
            if result == "yes" and rec.get("policy") == POLICY_V01:
                continue
            all_yes = False
            if result not in ("yes", "no", "n/a"):
                reasons.append("authorization.policy-unknown")
            elif rec.get("policy") != POLICY_V01:
                reasons.append("authorization.policy-mismatch")
            else:
                reasons.append("authorization.policy-mismatch")
            continue
        if req == "provenance":
            if result == "yes" and rec.get("provenance") == "known":
                continue
            all_yes = False
            if rec.get("provenance") == "unknown" or result == "no":
                reasons.append("authorization.provenance-unknown")
            elif result not in ("yes", "no", "n/a"):
                reasons.append("decision.unknown-reason")
            else:
                reasons.append("authorization.provenance-unknown")
            continue
        if req == "action-match":
            if result == "yes" and rec.get("action") == action:
                continue
            all_yes = False
            if result not in ("yes", "no", "n/a"):
                reasons.append("decision.unknown-reason")
            else:
                reasons.append("authorization.action-mismatch")
            continue
    if missing:
        reasons.append("predicate.missing-input")
    if all_yes:
        authorized = _decision("authorized", "yes", ["decision.authorized-closed"])
    else:
        authorized = _decision("authorized", "no", reasons)

    license_identity = None
    if len(licenses) > 1:
        lic, license_identity = license_no(["decision.duplicate-identity"])
        return emit(authorized, lic, license_identity)
    license_rec = licenses[0] if licenses else None
    if authorized["result"] != "yes":
        lic, license_identity = license_no(["authorization.authorized-no"])
        return emit(authorized, lic, license_identity)
    if license_rec is None:
        lic, license_identity = license_no(["authorization.rewrite-license-missing"])
        return emit(authorized, lic, license_identity)
    ident = _license_scope(license_rec)
    expect_lic = (selected, obj, action, LICENSE_KIND_V01)
    if ident != expect_lic:
        lic, license_identity = license_no(["decision.identity-mismatch"])
        return emit(authorized, lic, license_identity)
    license_identity = {
        "selected": selected,
        "object": obj,
        "action": action,
        "license-kind": LICENSE_KIND_V01,
    }
    lic_result = license_rec.get("result")
    if lic_result == "yes":
        lic = _decision(
            "rewrite-license", "yes", ["decision.rewrite-license-closed"]
        )
        return emit(authorized, lic, license_identity)
    if lic_result == "no":
        lic, _ = license_no(["authorization.rewrite-license-no"], license_identity)
        return emit(authorized, lic, license_identity)
    lic, _ = license_no(["decision.unknown-reason"], license_identity)
    return emit(authorized, lic, license_identity)


def _id2(*, selected: str = SELECTED_S0, obj: str = OBJECT_2) -> dict:
    return {"selected": selected, "object": obj}


def _id3(
    *,
    selected: str = SELECTED_S0,
    obj: str = OBJECT_2,
    action: str = ACTION_V01,
) -> dict:
    return {"selected": selected, "object": obj, "action": action}


def _id4(
    *,
    selected: str = SELECTED_S0,
    obj: str = OBJECT_2,
    action: str = ACTION_V01,
    kind: str = LICENSE_KIND_V01,
) -> dict:
    return {
        "selected": selected,
        "object": obj,
        "action": action,
        "license-kind": kind,
    }


def _sufficient(result: str = "yes", **ident) -> dict:
    return {
        "subject": "sufficient",
        "result": result,
        "identity": _id2(**ident),
    }


def _policy(
    result: str = "yes",
    policy: str = POLICY_V01,
    **ident,
) -> dict:
    return {
        "subject": "policy-match",
        "result": result,
        "policy": policy,
        "identity": _id3(**ident),
    }


def _provenance(
    result: str = "yes",
    provenance: str = "known",
    **ident,
) -> dict:
    return {
        "subject": "provenance",
        "result": result,
        "provenance": provenance,
        "identity": _id3(**ident),
    }


def _action(
    result: str = "yes",
    *,
    claimed: str | None = None,
    identity_action: str = ACTION_V01,
    **ident,
) -> dict:
    """identity.action is the target; record.action is the claim."""
    payload = dict(ident)
    payload.setdefault("action", identity_action)
    return {
        "subject": "action-match",
        "result": result,
        "action": ACTION_V01 if claimed is None else claimed,
        "identity": _id3(**payload),
    }


def _license(
    result: str = "yes",
    kind: str = LICENSE_KIND_V01,
    **ident,
) -> dict:
    return {
        "subject": "rewrite-license",
        "result": result,
        "identity": _id4(kind=kind, **ident),
    }


def _all_required() -> list[dict]:
    return [_sufficient(), _policy(), _provenance(), _action()]


def _from_6cm() -> list[dict]:
    bag = suf.evaluate_sufficiency(list(reversed(suf._all_yes())))
    decision = bag["decision"]
    if decision["subject"] != "sufficient" or decision["result"] != "yes":
        raise RuntimeError("6C-M consume fixture drifted")
    return [
        {
            "subject": "sufficient",
            "result": decision["result"],
            "identity": dict(bag["identity"]),
        },
        _policy(),
        _provenance(),
        _action(),
    ]


def _cases() -> list[tuple[str, list[dict]]]:
    return [
        (
            "sufficient-no",
            [_sufficient("no"), _policy(), _provenance(), _action()],
        ),
        (
            "sufficient-yes-policy-missing",
            [_sufficient(), _provenance(), _action()],
        ),
        (
            "wrong-policy",
            [
                _sufficient(),
                _policy(policy="other-policy"),
                _provenance(),
                _action(),
            ],
        ),
        (
            "unknown-policy",
            [
                _sufficient(),
                _policy("unknown"),
                _provenance(),
                _action(),
            ],
        ),
        (
            "action-mismatch",
            [
                _sufficient(),
                _policy(),
                _provenance(),
                _action(result="no", claimed="schedule-rewrite"),
            ],
        ),
        (
            "selected-mismatch",
            [
                _sufficient(selected=SELECTED_S1),
                _policy(),
                _provenance(),
                _action(),
            ],
        ),
        (
            "object-mismatch",
            [
                _sufficient(obj=OBJECT_3),
                _policy(),
                _provenance(),
                _action(),
            ],
        ),
        ("provenance-missing", [_sufficient(), _policy(), _action()]),
        (
            "provenance-unknown",
            [
                _sufficient(),
                _policy(),
                _provenance("no", provenance="unknown"),
                _action(),
            ],
        ),
        (
            "duplicate-identity",
            [_sufficient(), _sufficient("no"), _policy(), _provenance(), _action()],
        ),
        ("authorized-yes-license-missing", _all_required()),
        (
            "rewrite-license-no",
            _all_required() + [_license("no")],
        ),
        (
            "rewrite-license-yes",
            _all_required() + [_license("yes")],
        ),
        (
            "rewrite-license-kind-mismatch",
            _all_required() + [_license("yes", kind="other-kind")],
        ),
        (
            "duplicate-license",
            _all_required()
            + [_license("yes", kind="other-kind"), _license("yes")],
        ),
        ("missing-action-match", [_sufficient(), _policy(), _provenance()]),
        (
            "sufficient-n/a",
            [_sufficient("n/a"), _policy(), _provenance(), _action()],
        ),
        ("shuffled-required", list(reversed(_all_required()))),
        ("consume-6c-m-yes", _from_6cm()),
        (
            "license-yes-but-not-authorized",
            [_sufficient("no"), _policy(), _provenance(), _action(), _license("yes")],
        ),
    ]


def _validate_canonical(name: str, bag: dict) -> None:
    subjects = [i["subject"] for i in bag["inputs"]]
    required_present = [s for s in subjects if s in REQUIRED]
    expect_required = [r for r in REQUIRED if r in set(required_present)]
    if required_present != expect_required:
        raise RuntimeError(f"canonical required: {name}")
    seen_extra = False
    for item in bag["inputs"]:
        if item["subject"] not in REQUIRED:
            seen_extra = True
        elif seen_extra:
            raise RuntimeError(f"required after extra: {name}")


def _validate() -> None:
    names = [n for n, _ in _cases()]
    expect = [
        "sufficient-no",
        "sufficient-yes-policy-missing",
        "wrong-policy",
        "unknown-policy",
        "action-mismatch",
        "selected-mismatch",
        "object-mismatch",
        "provenance-missing",
        "provenance-unknown",
        "duplicate-identity",
        "authorized-yes-license-missing",
        "rewrite-license-no",
        "rewrite-license-yes",
        "rewrite-license-kind-mismatch",
        "duplicate-license",
        "missing-action-match",
        "sufficient-n/a",
        "shuffled-required",
        "consume-6c-m-yes",
        "license-yes-but-not-authorized",
    ]
    if names != expect:
        raise RuntimeError(names)
    if len(names) != 20:
        raise RuntimeError(len(names))
    for name, inputs in _cases():
        bag = evaluate_authorization(inputs)
        if bag["schema"] != AUTH_SCHEMA:
            raise RuntimeError(name)
        if bag["identity"] != {
            "selected": SELECTED_S0,
            "object": OBJECT_2,
            "action": ACTION_V01,
        }:
            raise RuntimeError(name)
        if bag["can-run-plan"] != "no" or bag["rewrite-path"] != "no":
            raise RuntimeError(name)
        if bag["transformation"] != "n/a":
            raise RuntimeError(name)
        _validate_canonical(name, bag)
        auth = bag["authorized"]
        lic = bag["rewrite-license"]
        if auth["subject"] != "authorized" or lic["subject"] != "rewrite-license":
            raise RuntimeError(name)
        if auth["result"] not in ("yes", "no") or lic["result"] not in ("yes", "no"):
            raise RuntimeError(name)
        if auth["result"] != "yes" and lic["result"] == "yes":
            raise RuntimeError(f"license without authorized: {name}")
        for token in auth["reasons"] + lic["reasons"]:
            if token.startswith("authorization.") and token not in AUTHORIZATION_REASON_TOKENS:
                raise RuntimeError(f"{name} unknown authorization token {token}")
        if name == "sufficient-no":
            if auth["reasons"] != ["authorization.sufficient-no"]:
                raise RuntimeError(name)
            if lic["reasons"] != ["authorization.authorized-no"]:
                raise RuntimeError(name)
        if name == "sufficient-yes-policy-missing":
            if auth["result"] != "no":
                raise RuntimeError(name)
            if auth["reasons"] != ["predicate.missing-input"]:
                raise RuntimeError(name)
        if name == "wrong-policy":
            if auth["reasons"] != ["authorization.policy-mismatch"]:
                raise RuntimeError(name)
        if name == "unknown-policy":
            if auth["reasons"] != ["authorization.policy-unknown"]:
                raise RuntimeError(name)
        if name == "action-mismatch":
            rec = next(i for i in inputs if i["subject"] == "action-match")
            if rec["identity"]["action"] != ACTION_V01:
                raise RuntimeError(name)
            if rec["action"] != "schedule-rewrite":
                raise RuntimeError(name)
            if auth["reasons"] != ["authorization.action-mismatch"]:
                raise RuntimeError(name)
        if name in ("selected-mismatch", "object-mismatch"):
            if auth["reasons"] != ["decision.identity-mismatch"]:
                raise RuntimeError(name)
        if name == "provenance-missing":
            if auth["reasons"] != ["predicate.missing-input"]:
                raise RuntimeError(name)
        if name == "provenance-unknown":
            if auth["reasons"] != ["authorization.provenance-unknown"]:
                raise RuntimeError(name)
        if name == "duplicate-identity":
            if auth["reasons"] != ["decision.duplicate-identity"]:
                raise RuntimeError(name)
        if name in (
            "authorized-yes-license-missing",
            "shuffled-required",
            "consume-6c-m-yes",
        ):
            if auth["result"] != "yes":
                raise RuntimeError(name)
            if auth["reasons"] != ["decision.authorized-closed"]:
                raise RuntimeError(name)
            if lic["result"] != "no":
                raise RuntimeError(name)
            if lic["reasons"] != ["authorization.rewrite-license-missing"]:
                raise RuntimeError(name)
        if name == "shuffled-required":
            if [i["subject"] for i in bag["inputs"]] != list(REQUIRED):
                raise RuntimeError(name)
        if name == "rewrite-license-no":
            if auth["result"] != "yes":
                raise RuntimeError(name)
            if lic["reasons"] != ["authorization.rewrite-license-no"]:
                raise RuntimeError(name)
        if name == "rewrite-license-yes":
            if auth["result"] != "yes" or lic["result"] != "yes":
                raise RuntimeError(name)
            if lic["reasons"] != ["decision.rewrite-license-closed"]:
                raise RuntimeError(name)
            if bag["rewrite-path"] != "no" or bag["transformation"] != "n/a":
                raise RuntimeError(name)
            if bag["license-identity"]["license-kind"] != LICENSE_KIND_V01:
                raise RuntimeError(name)
        if name == "rewrite-license-kind-mismatch":
            if auth["result"] != "yes":
                raise RuntimeError(name)
            if lic["result"] != "no":
                raise RuntimeError(name)
            if lic["reasons"] != ["decision.identity-mismatch"]:
                raise RuntimeError(name)
        if name == "duplicate-license":
            if auth["result"] != "yes":
                raise RuntimeError(name)
            if lic["reasons"] != ["decision.duplicate-identity"]:
                raise RuntimeError(name)
            if [i["subject"] for i in bag["inputs"]].count(LICENSE_SUBJECT) != 2:
                raise RuntimeError(name)
        if name == "missing-action-match":
            if auth["reasons"] != ["predicate.missing-input"]:
                raise RuntimeError(name)
        if name == "sufficient-n/a":
            if auth["reasons"] != ["authorization.sufficient-no"]:
                raise RuntimeError(name)
        if name == "license-yes-but-not-authorized":
            if auth["result"] != "no" or lic["result"] != "no":
                raise RuntimeError(name)
            if lic["reasons"] != ["authorization.authorized-no"]:
                raise RuntimeError(name)


def print_contract() -> int:
    _validate()
    print("authorization-evaluator gate=query")
    print(f"schema {AUTH_SCHEMA}")
    print(f"decision-schema {DECISION_SCHEMA}")
    print("decision-subject authorized")
    print("decision-subject rewrite-license")
    print("authorization-identity selected-object-action")
    print("license-identity selected-object-action-license-kind")
    print(f"policy {POLICY_V01}")
    print(f"action {ACTION_V01}")
    print(f"license-kind {LICENSE_KIND_V01}")
    print("sufficient-ne-authorized yes")
    print("authorized-ne-rewrite-license yes")
    print("sufficient-yes-ne-authorized yes")
    print("authorized-yes-ne-rewrite-license yes")
    print("authorized-yes-ne-rewrite-path yes")
    print("rewrite-license-yes-ne-transformation yes")
    print("inputs-canonical-order yes")
    print("duplicate-required-safe-no yes")
    print("duplicate-license-safe-no yes")
    print("license-input-not-ignored-extra yes")
    print("claimed-action-ne-identity-action yes")
    print("authorization-namespace v0.1")
    print("ea-1-authorization-tokens none")
    print("host-side-decision-contract yes")
    print("compiler-e2e no")
    print("can-run-plan no")
    print("rewrite-path no")
    print("transformation n/a")
    print("capability-schedule-ne-god-object yes")
    print("generic-schema-validator n/a")
    print("authorization-matrix-cases 20")
    for req in REQUIRED:
        print(f"required-input {req}")
    print(f"license-input {LICENSE_SUBJECT}")
    for token in AUTHORIZATION_REASON_TOKENS:
        print(f"token {token}")
    print("note six-c-m-frozen")
    print("note seven-a-opened")
    print("note seven-b-rewrite-closed")
    print("note ea-1-still-usable-only")
    print("note six-c-i-sufficient-no-unchanged")
    print("note f-storage-schedule-not-inhabited")
    print("note evidence-db-identity-frozen")
    print("note rewrite=no")
    print("cost=unchanged")
    example = evaluate_authorization(_all_required())
    print("example " + json.dumps(example, separators=(",", ":"), sort_keys=True))
    return 0


def print_matrix() -> int:
    _validate()
    print("authorization-matrix gate=query")
    print("decision-subject authorized")
    print("decision-subject rewrite-license")
    print("sufficient-ne-authorized yes")
    print("authorized-ne-rewrite-license yes")
    print("inputs-canonical-order yes")
    print("authorization-matrix-cases 20")
    for name, inputs in _cases():
        bag = evaluate_authorization(inputs)
        auth = bag["authorized"]
        lic = bag["rewrite-license"]
        print(f"auth-case {name}")
        print(
            "auth-scope "
            f"selected={bag['identity']['selected']} "
            f"object={bag['identity']['object']} "
            f"action={bag['identity']['action']}"
        )
        envelope_subjects = ",".join(i["subject"] for i in bag["inputs"]) or "none"
        print(f"auth-envelope-inputs {envelope_subjects}")
        for req in REQUIRED:
            rec = next((i for i in bag["inputs"] if i["subject"] == req), None)
            result = rec["result"] if rec else "absent"
            print(f"auth-input subject={req} result={result}")
        for extra in bag["inputs"]:
            if extra["subject"] in REQUIRED:
                continue
            print(
                f"auth-extra subject={extra['subject']} result={extra['result']}"
            )
        auth_reasons = ",".join(auth["reasons"]) if auth["reasons"] else "none"
        lic_reasons = ",".join(lic["reasons"]) if lic["reasons"] else "none"
        print(
            "auth-authorized "
            f"subject={auth['subject']} "
            f"result={auth['result']} "
            f"reasons={auth_reasons}"
        )
        print(
            "auth-license "
            f"subject={lic['subject']} "
            f"result={lic['result']} "
            f"reasons={lic_reasons}"
        )
        print(f"auth-can-run-plan {bag['can-run-plan']}")
        print(f"auth-rewrite-path {bag['rewrite-path']}")
        print(f"auth-transformation {bag['transformation']}")
    print("can-run-plan no")
    print("rewrite-path no")
    print("transformation n/a")
    print("note seven-b-rewrite-closed")
    print("note rewrite=no")
    print("cost=unchanged")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 Authorization Boundary (7A)")
    p.add_argument("--print-authorization-contract", action="store_true")
    p.add_argument("--print-authorization-matrix", action="store_true")
    args = p.parse_args(argv)
    flags = (
        args.print_authorization_contract,
        args.print_authorization_matrix,
    )
    if sum(bool(x) for x in flags) != 1:
        print(
            "record_authorization: choose one of "
            "--print-authorization-contract "
            "--print-authorization-matrix",
            file=sys.stderr,
        )
        return 2
    if args.print_authorization_contract:
        return print_contract()
    return print_matrix()


if __name__ == "__main__":
    sys.exit(main())
