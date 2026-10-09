#!/usr/bin/env python3
"""Compiler spine handoff for the carrier text.

s2c2-opt has no carrier dialect. This driver refuses to let an
opt flag produce the ApplyResult, then calls extract and the
existing evaluate_apply. It does not lower, and it does not
copy the host.
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
import record_mlir_carrier as carrier
import record_storage_apply as apply


class SpineRefusal(Exception):
    def __init__(self, code: str) -> None:
        self.code = code
        super().__init__(code)


def project(text: str, opt_argv: tuple[str, ...] = ()) -> dict:
    if opt_argv:
        raise SpineRefusal("opt-bypass")
    return carrier.extract(text)


def integrate(text: str, opt_argv: tuple[str, ...] = (), apply_fn=None) -> dict:
    program = project(text, opt_argv)
    if len(apply.find_regions(program)) != 1:
        raise SpineRefusal("no-region")
    envelope = scenario.rewrite_plan()
    witness = apply.bound_witness(program, device=scenario.DEVICE)
    fn = apply.evaluate_apply if apply_fn is None else apply_fn
    return fn([envelope], program, device=scenario.DEVICE, witness=witness)


def _restore_induced(program: dict, extracted: dict) -> dict:
    handed = copy.deepcopy(extracted)
    if "induced-hb" in program:
        handed["induced-hb"] = copy.deepcopy(program["induced-hb"])
    return handed


def replay_matrix() -> int:
    """Text round-trip, then the case's own evaluate_apply arguments.

    This does not build a witness. A case the host rejects stays a
    host rejection. can-run-plan stays no on every row.
    """
    count = 0
    for name, envelopes, program, kwargs in apply._cases():
        extracted = project(carrier.render(program))
        if "induced-hb" in extracted:
            raise RuntimeError("spine-induced-" + name)
        handed = _restore_induced(program, extracted)
        direct = apply.evaluate_apply(
            copy.deepcopy(envelopes),
            copy.deepcopy(program),
            **copy.deepcopy(kwargs),
        )
        via = apply.evaluate_apply(
            copy.deepcopy(envelopes),
            handed,
            **copy.deepcopy(kwargs),
        )
        for key in ("match", "applied", "rewrite-path", "can-run-plan", "reasons"):
            if via[key] != direct[key]:
                raise RuntimeError("spine-matrix-" + name)
        if apply.canonical_program(via["program"]) != apply.canonical_program(
            direct["program"]
        ):
            raise RuntimeError("spine-matrix-program-" + name)
        if via["can-run-plan"] != "no":
            raise RuntimeError("spine-matrix-plan-" + name)
        count += 1
    if count != 29:
        raise RuntimeError("spine-matrix-count")
    return count


def _refuse_region(text: str, apply_fn, calls: list[str], code: str) -> None:
    try:
        integrate(text, apply_fn=apply_fn)
    except SpineRefusal as refusal:
        if refusal.code != "no-region":
            raise RuntimeError(code) from refusal
    else:
        raise RuntimeError(code)
    if calls:
        raise RuntimeError(code + "-called-apply")


def _validate() -> dict:
    text = carrier.render(scenario.source_program())
    watched = {"n": 0}

    def _watch(envelopes, program, **kwargs):
        watched["n"] += 1
        return apply.evaluate_apply(envelopes, program, **kwargs)

    bag = integrate(text, apply_fn=_watch)
    if watched["n"] != 1:
        raise RuntimeError("spine-apply-not-called")
    if apply.canonical_program(bag["program"]) != scenario.CANONICAL_P_PRIME:
        raise RuntimeError("spine-prime")
    if bag["match"] != "yes" or bag["applied"] != "yes":
        raise RuntimeError("spine-success")
    if bag["can-run-plan"] != "no" or bag["rewrite-path"] != bag["applied"]:
        raise RuntimeError("spine-boundary")
    if bag["reasons"] != []:
        raise RuntimeError("spine-reasons")
    direct = scenario.observe("success", scenario.source_program(), "bound")
    if apply.canonical_program(bag["program"]) != direct["canonical-result"]:
        raise RuntimeError("spine-scenario")

    calls: list[str] = []

    def _forbid(*_args, **_kwargs):
        calls.append("apply")
        raise RuntimeError("opt called apply")

    try:
        integrate(text, ("--s2c2-evidence-bounded-schedule",), apply_fn=_forbid)
    except SpineRefusal as refusal:
        if refusal.code != "opt-bypass":
            raise RuntimeError(refusal.code) from refusal
    else:
        raise RuntimeError("opt-bypass-missing")
    if calls:
        raise RuntimeError("opt-bypass-called-apply")

    try:
        integrate(
            text.replace('op_id = "id2"', "op = \"store\""),
            apply_fn=_forbid,
        )
    except carrier.ExtractRefusal:
        pass
    else:
        raise RuntimeError("extract-refusal-missing")
    if calls:
        raise RuntimeError("extract-called-apply")

    other = copy.deepcopy(scenario.source_program())
    other["capacity"] = 1
    _refuse_region(carrier.render(other), _forbid, calls, "no-region-capacity")
    thin = copy.deepcopy(scenario.source_program())
    thin["working-set"] = 2
    _refuse_region(carrier.render(thin), _forbid, calls, "no-region-working-set")
    by_name = {
        name: program for name, _envelopes, program, _kwargs in apply._cases()
    }
    if len(apply.find_regions(by_name["ir-extra-store"])) < 2:
        raise RuntimeError("spine-two-region-fixture")
    _refuse_region(
        carrier.render(by_name["ir-extra-store"]),
        _forbid,
        calls,
        "no-region-two",
    )
    if apply.find_regions(by_name["ir-missing-store"]):
        raise RuntimeError("spine-short-fixture")
    _refuse_region(
        carrier.render(by_name["ir-missing-store"]),
        _forbid,
        calls,
        "no-region-short",
    )
    try:
        integrate("not-carrier", ("--s2c2-lower",), apply_fn=_forbid)
    except SpineRefusal as refusal:
        if refusal.code != "opt-bypass":
            raise RuntimeError("opt-before-extract") from refusal
    else:
        raise RuntimeError("opt-before-extract")
    if calls:
        raise RuntimeError("opt-before-extract-called-apply")
    matrix = replay_matrix()

    renamed = copy.deepcopy(scenario.source_program())
    renamed["blocks"][0]["ops"][0]["name"] = "9"
    mismatch = integrate(carrier.render(renamed))
    if mismatch["match"] != "no" or mismatch["applied"] != "no":
        raise RuntimeError("spine-mismatch")
    if mismatch["can-run-plan"] != "no" or mismatch["rewrite-path"] != "no":
        raise RuntimeError("spine-mismatch-boundary")
    if apply.canonical_program(mismatch["program"]) != apply.canonical_program(renamed):
        raise RuntimeError("spine-mismatch-mutated")
    return {
        "match": bag["match"],
        "applied": bag["applied"],
        "matrix": matrix,
    }


def print_contract() -> int:
    summary = _validate()
    print("compiler-spine gate=handoff")
    print("pipeline carrier-text extract evaluate-apply")
    print("s2c2-opt-invoked no")
    print("s2c2-opt-bypass no")
    print("s2c2-opt-has-carrier-dialect no")
    print("tablegen no")
    print("lowering no")
    print("evaluate-apply unchanged")
    print("authorization existing")
    print("rewrite-plan existing")
    print("compiler-e2e no")
    print("can-run-plan no")
    print("semantic-cut no")
    print("next-cut no")
    print("spine-match " + summary["match"])
    print("spine-applied " + summary["applied"])
    print("opt-bypass refusal apply-not-called")
    print("extract-refusal apply-not-called")
    print("no-region refusal apply-not-called")
    print("other-program match no")
    print("other-program applied no")
    print("apply-called yes")
    print("host-matrix-through-spine " + str(summary["matrix"]))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Carrier spine handoff")
    parser.add_argument("--print-compiler-spine", action="store_true")
    args = parser.parse_args(argv)
    if not args.print_compiler_spine:
        print(
            "record_compiler_spine: choose --print-compiler-spine",
            file=sys.stderr,
        )
        return 2
    return print_contract()


if __name__ == "__main__":
    sys.exit(main())
