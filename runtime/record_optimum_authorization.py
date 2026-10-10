#!/usr/bin/env python3
"""Optimum authorization.

Among legal strategies, the unique minimum cost is the
authorization and the rewrite license. This is the owner rule
for cut 7C. It does not change evaluate_authorization.
It does not map IR to a host program. A missing witness does
not apply. can-run-plan stays no.
"""

from __future__ import annotations

import argparse
import copy
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_apply_scenario as scenario
import record_authorization as auth
import record_storage_apply as apply
import record_storage_rewrite as rew

SCHEMA = "s2c2.optimum_authorization.v1"
RULE = "unique-minimum-cost"


def _refuse(reason: str) -> dict:
    return {
        "schema": SCHEMA,
        "rule": RULE,
        "result": "no",
        "reasons": [reason],
        "strategy-id": "n/a",
        "cost": "n/a",
        "authorization": "n/a",
        "rewrite": "n/a",
        "can-run-plan": "no",
    }


def _parse(strategies):
    if not isinstance(strategies, list):
        return None, "optimum.malformed"
    if len(strategies) == 0:
        return None, "optimum.empty"
    parsed = []
    seen: set[str] = set()
    for item in strategies:
        if not isinstance(item, dict):
            return None, "optimum.malformed"
        sid = item.get("id")
        legal = item.get("legal")
        if not isinstance(sid, str) or sid == "" or legal not in ("yes", "no"):
            return None, "optimum.malformed"
        if sid in seen:
            return None, "optimum.duplicate-id"
        seen.add(sid)
        cost = item.get("cost")
        if legal == "yes" and type(cost) is not int:
            return None, "optimum.cost-missing"
        parsed.append(
            {
                "id": sid,
                "legal": legal,
                "cost": cost if legal == "yes" else None,
                "selected": item.get("selected"),
                "object": item.get("object"),
                "action": item.get("action"),
            }
        )
    return parsed, None


def _identity(entry: dict):
    selected = entry.get("selected")
    obj = entry.get("object")
    action = entry.get("action")
    if not all(isinstance(part, str) and part for part in (selected, obj, action)):
        return None
    return selected, obj, action


def _authorization(entry: dict, selected: str, obj: str, action: str) -> dict:
    return auth._envelope(
        authorized=auth._decision(
            "authorized", "yes", ["authorization.authorized-closed"]
        ),
        license_decision=auth._decision(
            "rewrite-license", "yes", ["authorization.rewrite-license-closed"]
        ),
        canonical_inputs=[
            {
                "subject": "optimum",
                "result": "yes",
                "strategy": entry["id"],
                "cost": entry["cost"],
            }
        ],
        selected=selected,
        obj=obj,
        action=action,
        license_identity={
            "selected": selected,
            "object": obj,
            "action": action,
            "license-kind": auth.LICENSE_KIND_V01,
        },
    )


def authorize_optimum(strategies: list) -> dict:
    """Unique minimum cost among legal strategies authorizes that strategy."""
    parsed, reason = _parse(strategies)
    if reason is not None:
        return _refuse(reason)
    legal = [entry for entry in parsed if entry["legal"] == "yes"]
    if not legal:
        return _refuse("optimum.no-legal")
    best = min(entry["cost"] for entry in legal)
    winners = [entry for entry in legal if entry["cost"] == best]
    if len(winners) != 1:
        return _refuse("optimum.tie")
    winner = winners[0]
    ident = _identity(winner)
    if ident is None:
        return _refuse("optimum.identity-missing")
    selected, obj, action = ident
    envelope = _authorization(winner, selected, obj, action)
    plan = rew.bind_rewrite_plan(
        rew.evaluate_rewrite(
            [envelope],
            selected=selected,
            obj=obj,
            action=action,
        )
    )
    if plan["rewrite-plan"]["result"] != "yes":
        refused = _refuse("optimum.unbound")
        refused["authorization"] = envelope
        refused["rewrite"] = plan
        return refused
    return {
        "schema": SCHEMA,
        "rule": RULE,
        "result": "yes",
        "reasons": ["optimum.selected"],
        "strategy-id": winner["id"],
        "cost": winner["cost"],
        "authorization": envelope,
        "rewrite": plan,
        "can-run-plan": "no",
    }


def _refused_apply(reasons: list[str]) -> dict:
    return {
        "schema": SCHEMA,
        "result": "no",
        "reasons": list(reasons),
        "match": "no",
        "applied": "no",
        "rewrite-path": "no",
        "can-run-plan": "no",
    }


def apply_optimum(strategies: list, program: dict, *, device: str = "D0", witness=None) -> dict:
    """Apply the plan of the authorized optimum. A missing witness stays unapplied."""
    chosen = authorize_optimum(strategies)
    if chosen["result"] != "yes":
        return _refused_apply(chosen["reasons"])
    return apply.evaluate_apply(
        [chosen["rewrite"]],
        program,
        device=device,
        witness=witness,
    )


def acceptance_strategies() -> list[dict]:
    """Illegal cheaper, one legal optimum, one legal costlier."""
    return [
        {
            "id": "illegal-cheaper",
            "legal": "no",
            "cost": 1,
            "selected": auth.SELECTED_S1,
            "object": auth.OBJECT_2,
            "action": auth.ACTION_V01,
        },
        {
            "id": "capacity-optimum",
            "legal": "yes",
            "cost": 4,
            "selected": auth.SELECTED_S0,
            "object": auth.OBJECT_2,
            "action": auth.ACTION_V01,
        },
        {
            "id": "legal-costlier",
            "legal": "yes",
            "cost": 9,
            "selected": auth.SELECTED_S1,
            "object": auth.OBJECT_2,
            "action": auth.ACTION_V01,
        },
    ]


def _tie_strategies() -> list[dict]:
    rows = acceptance_strategies()
    rows[2]["cost"] = 4
    rows[2]["id"] = "legal-tie"
    return rows


def _validate() -> None:
    raw = acceptance_strategies()
    snapshot = copy.deepcopy(raw)
    chosen = authorize_optimum(raw)
    if raw != snapshot:
        raise RuntimeError("mutated-input")
    if chosen["result"] != "yes" or chosen["reasons"] != ["optimum.selected"]:
        raise RuntimeError("select")
    if chosen["strategy-id"] != "capacity-optimum" or chosen["cost"] != 4:
        raise RuntimeError("winner")
    if chosen["can-run-plan"] != "no":
        raise RuntimeError("run")
    envelope = chosen["authorization"]
    if envelope["authorized"]["result"] != "yes":
        raise RuntimeError("authorized")
    if envelope["rewrite-license"]["result"] != "yes":
        raise RuntimeError("license")
    if envelope["inputs"][0]["subject"] != "optimum":
        raise RuntimeError("source")
    if envelope["can-run-plan"] != "no" or envelope["rewrite-path"] != "no":
        raise RuntimeError("envelope-boundary")
    plan = chosen["rewrite"]
    if plan["rewrite-plan"]["result"] != "yes":
        raise RuntimeError("plan")
    if plan["can-run-plan"] != "no" or plan["applied"] != "no":
        raise RuntimeError("plan-boundary")
    if plan["identity"]["selected"] != auth.SELECTED_S0:
        raise RuntimeError("plan-identity")
    if plan["sequence"] != [
        {"step": "KEEP", "name": "0"},
        {"step": "KEEP", "name": "1"},
        {"step": "EVICT", "name": "2"},
        {"step": "TRANSFER", "name": "2"},
        {"step": "RESTORE", "name": "2"},
    ]:
        raise RuntimeError("bound-sequence")
    unbound = acceptance_strategies()
    unbound[1]["selected"] = "keep{0}|evict{1,2}|rematerialize{}"
    unbound[1]["cost"] = 1
    if authorize_optimum(unbound)["reasons"] != ["optimum.unbound"]:
        raise RuntimeError("unbound")

    if authorize_optimum(_tie_strategies())["reasons"] != ["optimum.tie"]:
        raise RuntimeError("tie")
    only_illegal = [row for row in acceptance_strategies() if row["legal"] == "no"]
    if authorize_optimum(only_illegal)["reasons"] != ["optimum.no-legal"]:
        raise RuntimeError("no-legal")
    if authorize_optimum([])["reasons"] != ["optimum.empty"]:
        raise RuntimeError("empty")
    missing_cost = acceptance_strategies()
    del missing_cost[1]["cost"]
    if authorize_optimum(missing_cost)["reasons"] != ["optimum.cost-missing"]:
        raise RuntimeError("cost")
    boolean_cost = acceptance_strategies()
    boolean_cost[1]["cost"] = True
    if authorize_optimum(boolean_cost)["reasons"] != ["optimum.cost-missing"]:
        raise RuntimeError("bool-cost")
    duplicated = acceptance_strategies()
    duplicated[2]["id"] = duplicated[1]["id"]
    if authorize_optimum(duplicated)["reasons"] != ["optimum.duplicate-id"]:
        raise RuntimeError("duplicate")
    if authorize_optimum("nope")["reasons"] != ["optimum.malformed"]:
        raise RuntimeError("malformed")
    nameless = acceptance_strategies()
    del nameless[1]["selected"]
    if authorize_optimum(nameless)["reasons"] != ["optimum.identity-missing"]:
        raise RuntimeError("identity")

    frozen = auth.evaluate_authorization(
        dict(auth._cases())["sufficient-yes-policy-missing"]
    )
    if frozen["authorized"]["result"] != "no":
        raise RuntimeError("frozen-7a")

    program = scenario.source_program()
    before = copy.deepcopy(program)
    witness = apply.bound_witness(program, device=scenario.DEVICE)
    applied = apply_optimum(
        acceptance_strategies(),
        program,
        device=scenario.DEVICE,
        witness=witness,
    )
    if applied["match"] != "yes" or applied["applied"] != "yes":
        raise RuntimeError("apply")
    if applied["rewrite-path"] != "yes" or applied["can-run-plan"] != "no":
        raise RuntimeError("apply-boundary")
    if program != before:
        raise RuntimeError("program-mutated")
    if apply.canonical_program(applied["program"]) != scenario.CANONICAL_P_PRIME:
        raise RuntimeError("canonical")

    missing = apply_optimum(
        acceptance_strategies(),
        program,
        device=scenario.DEVICE,
        witness=None,
    )
    if missing["match"] != "yes" or missing["applied"] != "no":
        raise RuntimeError("witness")
    if missing["can-run-plan"] != "no":
        raise RuntimeError("witness-run")
    if program != before:
        raise RuntimeError("witness-mutated")

    tied = apply_optimum(_tie_strategies(), program, device=scenario.DEVICE, witness=witness)
    if tied["result"] != "no" or tied["applied"] != "no" or tied["can-run-plan"] != "no":
        raise RuntimeError("tie-apply")


def print_optimum_authorization() -> int:
    _validate()
    chosen = authorize_optimum(acceptance_strategies())
    program = scenario.source_program()
    applied = apply_optimum(
        acceptance_strategies(),
        program,
        device=scenario.DEVICE,
        witness=apply.bound_witness(program, device=scenario.DEVICE),
    )
    frozen = auth.evaluate_authorization(
        dict(auth._cases())["sufficient-yes-policy-missing"]
    )
    print("optimum-authorization v1")
    print(f"schema {SCHEMA}")
    print(f"rule {RULE}")
    print(f"selected-id {chosen['strategy-id']}")
    print(f"cost {chosen['cost']}")
    print(f"authorized {chosen['authorization']['authorized']['result']}")
    print(f"rewrite-license {chosen['authorization']['rewrite-license']['result']}")
    print(f"rewrite-plan {chosen['rewrite']['rewrite-plan']['result']}")
    print(
        "bound-sequence "
        + ",".join(
            f"{step['step']}:{step['name']}" for step in chosen["rewrite"]["sequence"]
        )
    )
    print("illegal-cheaper-not-selected yes")
    print(f"tie {authorize_optimum(_tie_strategies())['result']}")
    print(
        "no-legal "
        + authorize_optimum(
            [row for row in acceptance_strategies() if row["legal"] == "no"]
        )["result"]
    )
    print(f"frozen-7a-policy-missing {frozen['authorized']['result']}")
    print(f"apply-match {applied['match']}")
    print("apply-can-run-plan " + applied["can-run-plan"])
    print("can-run-plan no")
    print("seven-a-unchanged yes")
    print("next-cut NOT-OPENED")
    print("result PASS")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="S2C2 optimum authorization")
    parser.add_argument("--print-optimum-authorization", action="store_true")
    args = parser.parse_args(argv)
    if not args.print_optimum_authorization:
        print(
            "record_optimum_authorization: choose --print-optimum-authorization",
            file=sys.stderr,
        )
        return 2
    return print_optimum_authorization()


if __name__ == "__main__":
    sys.exit(main())
