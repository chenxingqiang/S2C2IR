#!/usr/bin/env python3
"""Acceptance scenario w0-3-2-storage-capacity-001.

Replays the producers already on main:
authorization → 7B rewrite-plan → W0-3/2 apply.
Pins canonical(P), canonical(P'), and ApplyResult.

Contract-level and host-level evidence only.
Not an LLVM/MLIR compiler integration. Not s2c2-opt.
Not hardware execution. Not a performance claim.
Not a new semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_authorization as auth
import record_storage_apply as apply
import record_storage_rewrite as rew

SCENARIO_ID = "w0-3-2-storage-capacity-001"
DEVICE = "D0"
CANONICAL_P = (
    '{"blocks":[{"ops":[{"name":"0","op":"store","op-id":"id0"},'
    '{"name":"1","op":"store","op-id":"id1"},'
    '{"name":"2","op":"store","op-id":"id2"}]}],'
    '"capacity":2,"hb":[["id0","id1"],["id1","id2"]],"working-set":3}'
)
CANONICAL_P_PRIME = (
    '{"blocks":[{"ops":[{"name":"0","op":"store","op-id":"id0"},'
    '{"name":"1","op":"store","op-id":"id1"},'
    '{"name":"2","op":"evict","op-id":"id2.evict"},'
    '{"name":"2","op":"transfer","op-id":"id2.transfer"},'
    '{"name":"2","op":"restore","op-id":"id2.restore"}]}],'
    '"capacity":2,"hb":[["id0","id1"],["id1","id2.evict"],'
    '["id2.evict","id2.transfer"],["id2.transfer","id2.restore"]],'
    '"working-set":3}'
)


def _sha256(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def source_program() -> dict:
    return apply._program([apply._stores(["0", "1", "2"])])


def rewrite_plan() -> dict:
    licensed = auth.evaluate_authorization(auth._all_required() + [auth._license("yes")])
    return rew.evaluate_rewrite([licensed])


def _witness(program: dict, mode: str):
    if mode == "bound":
        return apply.bound_witness(program, device=DEVICE)
    if mode == "missing":
        return None
    if mode == "wrong-device":
        return apply.bound_witness(program, device="D2")
    raise RuntimeError(mode)


def observe(name: str, program: dict, mode: str) -> dict:
    source = copy.deepcopy(program)
    envelope = copy.deepcopy(rewrite_plan())
    before = apply.canonical_program(source)
    before_env = json.dumps(envelope, sort_keys=True)
    bag = apply.evaluate_apply(
        [envelope],
        source,
        device=DEVICE,
        witness=_witness(source, mode),
    )
    return {
        "name": name,
        "match": bag["match"],
        "applied": bag["applied"],
        "rewrite-path": bag["rewrite-path"],
        "can-run-plan": bag["can-run-plan"],
        "reasons": list(bag["reasons"]),
        "canonical-source": before,
        "canonical-result": apply.canonical_program(bag["program"]),
        "source-unchanged": apply.canonical_program(source) == before and source == program,
        "envelope-unchanged": json.dumps(envelope, sort_keys=True) == before_env,
    }


def _scenes() -> list[dict]:
    hb = apply._program(
        [apply._stores(["0", "1", "2"])],
        hb=[["id0", "id1"]],
        induced=[["id0", "id2"]],
    )
    return [
        observe("success", source_program(), "bound"),
        observe(
            "identity-mismatch",
            apply._program([apply._stores(["1", "0", "2"])]),
            "bound",
        ),
        observe(
            "multiple-region",
            apply._program(
                [
                    apply._stores(["0", "1", "2"], "a"),
                    apply._stores(["0", "1", "2"], "b"),
                ]
            ),
            "bound",
        ),
        observe("hb-mismatch", hb, "bound"),
        observe("witness-missing", source_program(), "missing"),
        observe("wrong-device", source_program(), "wrong-device"),
        observe("opid-collision", apply._collision_program("evict"), "bound"),
    ]


def _expect_failure(row: dict, *, match: str, reasons: list[str]) -> None:
    if row["match"] != match or row["applied"] != "no":
        raise RuntimeError(row["name"])
    if row["rewrite-path"] != "no" or row["can-run-plan"] != "no":
        raise RuntimeError(row["name"])
    if row["reasons"] != reasons:
        raise RuntimeError(row["name"])
    if not row["source-unchanged"] or not row["envelope-unchanged"]:
        raise RuntimeError(row["name"])
    if row["canonical-result"] != row["canonical-source"]:
        raise RuntimeError(row["name"])


def _validate() -> dict:
    plan = rewrite_plan()
    if plan["rewrite-plan"]["result"] != "yes":
        raise RuntimeError("plan")
    if plan["rewrite-plan"]["reasons"] != ["rewrite.plan-closed"]:
        raise RuntimeError("plan-reasons")
    if plan["identity"] != {
        "selected": apply.SELECTED_S0,
        "object": apply.OBJECT_2,
        "action": apply.ACTION_V01,
        "license-kind": apply.LICENSE_KIND_V01,
    }:
        raise RuntimeError("plan-identity")
    if plan["sequence"] != list(apply.SEQUENCE_V01):
        raise RuntimeError("plan-sequence")
    if plan["transformation"] != apply.TRANSFORMATION_V01:
        raise RuntimeError("plan-transformation")
    if plan["applied"] != "no" or plan["rewrite-path"] != "no" or plan["can-run-plan"] != "no":
        raise RuntimeError("plan-boundary")

    program = source_program()
    if apply.canonical_program(program) != CANONICAL_P:
        raise RuntimeError("canonical-P")
    rows = {row["name"]: row for row in _scenes()}
    success = rows["success"]
    if success["canonical-source"] != CANONICAL_P:
        raise RuntimeError("success-source")
    if success["canonical-result"] != CANONICAL_P_PRIME:
        raise RuntimeError("canonical-P-prime")
    if success["match"] != "yes" or success["applied"] != "yes":
        raise RuntimeError("success")
    if success["rewrite-path"] != "yes" or success["can-run-plan"] != "no":
        raise RuntimeError("success-boundary")
    if success["reasons"] != []:
        raise RuntimeError("success-reasons")
    if not success["source-unchanged"] or not success["envelope-unchanged"]:
        raise RuntimeError("success-mutation")
    if apply.candidate_id_for(program) != CANONICAL_P_PRIME:
        raise RuntimeError("candidate-id")
    witness = apply.bound_witness(program, device=DEVICE)
    if witness["candidate-id"] != CANONICAL_P_PRIME or witness["device"] != DEVICE:
        raise RuntimeError("witness")
    if witness["legal"] != "yes":
        raise RuntimeError("witness-legal")

    _expect_failure(
        rows["identity-mismatch"],
        match="no",
        reasons=["rewrite.identity-mismatch"],
    )
    _expect_failure(rows["multiple-region"], match="no", reasons=[])
    for name in ("hb-mismatch", "witness-missing", "wrong-device", "opid-collision"):
        _expect_failure(rows[name], match="yes", reasons=[])
    return rows


def print_contract() -> int:
    rows = _validate()
    success = rows["success"]
    print("apply-scenario gate=acceptance")
    print(f"scenario-id {SCENARIO_ID}")
    print("evidence-scope contract-level-e2e")
    print("evidence-scope host-inhabitant")
    print("compiler-e2e no")
    print("s2c2-opt no")
    print("hardware-execution no")
    print("performance-claim no")
    print("generic-rewrite no")
    print("enum-f no")
    print("search no")
    print("authorization-reopened no")
    print("semantic-cut no")
    print("can-run-plan no")
    print("scenario-match " + success["match"])
    print("scenario-applied " + success["applied"])
    print("scenario-rewrite-path " + success["rewrite-path"])
    print("scenario-can-run-plan " + success["can-run-plan"])
    print("candidate-id-is-canonical yes")
    print("source-unchanged yes")
    print("envelope-unchanged yes")
    print("canonical-p-sha256 " + _sha256(CANONICAL_P))
    print("canonical-p-prime-sha256 " + _sha256(CANONICAL_P_PRIME))
    for name in (
        "identity-mismatch",
        "multiple-region",
        "hb-mismatch",
        "witness-missing",
        "wrong-device",
        "opid-collision",
    ):
        row = rows[name]
        reasons = ",".join(row["reasons"]) if row["reasons"] else "none"
        print(
            f"failure {name} match={row['match']} "
            f"applied={row['applied']} reasons={reasons}"
        )
    print("real-semantic-gap none")
    print("next-cut no")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="W0-3/2 acceptance scenario")
    parser.add_argument("--print-apply-scenario", action="store_true")
    args = parser.parse_args(argv)
    if not args.print_apply_scenario:
        print(
            "record_apply_scenario: choose --print-apply-scenario",
            file=sys.stderr,
        )
        return 2
    return print_contract()


if __name__ == "__main__":
    sys.exit(main())
