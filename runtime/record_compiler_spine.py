#!/usr/bin/env python3
"""Compiler spine handoff for the carrier text.

s2c2-opt has no carrier dialect. This driver refuses to let an
opt flag produce the ApplyResult, then calls extract and the
existing evaluate_apply. It does not lower, and it does not
copy the host.
"""

from __future__ import annotations

import argparse
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


def integrate(text: str, opt_argv: tuple[str, ...] = (), apply_fn=None) -> dict:
    if opt_argv:
        raise SpineRefusal("opt-bypass")
    program = carrier.extract(text)
    envelope = scenario.rewrite_plan()
    witness = apply.bound_witness(program, device=scenario.DEVICE)
    fn = apply.evaluate_apply if apply_fn is None else apply_fn
    return fn([envelope], program, device=scenario.DEVICE, witness=witness)


def _validate() -> dict:
    text = carrier.render(scenario.source_program())
    bag = integrate(text)
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
    return {"match": bag["match"], "applied": bag["applied"]}


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
