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
import threading
import time
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_apply_scenario as scenario
import record_mlir_carrier as carrier
import record_scenario_corpus as corpus
import record_storage_apply as apply


class SpineRefusal(Exception):
    def __init__(self, code: str) -> None:
        self.code = code
        super().__init__(code)


def project(text: str, opt_argv: tuple[str, ...] = ()) -> dict:
    if opt_argv:
        raise SpineRefusal("opt-bypass")
    return carrier.extract(text)


_UNSET = object()


def integrate(
    text: str,
    opt_argv: tuple[str, ...] = (),
    apply_fn=None,
    *,
    envelope=_UNSET,
    witness=_UNSET,
) -> dict:
    """Carrier text to the existing host.

    Without `envelope` and `witness` this is the acceptance driver. It
    supplies the acceptance 7B envelope and builds a legal witness from
    the extracted program. Neither comes from the caller, so
    a successful apply on that path is acceptance evidence. It is not
    an authorization of an arbitrary program.

    A caller-supplied `envelope` or `witness` is passed to the host
    unchanged, including `None` and a `legal=no` witness. The driver
    does not replace a caller's refusal.
    """
    program = project(text, opt_argv)
    if len(apply.find_regions(program)) != 1:
        raise SpineRefusal("no-region")
    if envelope is _UNSET:
        envelope = scenario.rewrite_plan()
    if witness is _UNSET:
        witness = apply.bound_witness(program, device=scenario.DEVICE)
    fn = apply.evaluate_apply if apply_fn is None else apply_fn
    return fn([envelope], program, device=scenario.DEVICE, witness=witness)


def check_caller_supplied() -> None:
    """A caller's missing or illegal witness, or a closed plan, stays a refusal."""
    text = carrier.render(scenario.source_program())
    extracted = project(text)

    missing = integrate(text, witness=None)
    if missing["match"] != "yes" or missing["applied"] != "no":
        raise RuntimeError("caller-witness-missing")

    illegal = integrate(
        text,
        witness=apply.bound_witness(extracted, device=scenario.DEVICE, legal="no"),
    )
    if illegal["match"] != "yes" or illegal["applied"] != "no":
        raise RuntimeError("caller-witness-illegal")

    wrong = integrate(
        text, witness=apply.bound_witness(extracted, device="D2")
    )
    if wrong["match"] != "yes" or wrong["applied"] != "no":
        raise RuntimeError("caller-witness-device")

    closed = copy.deepcopy(scenario.rewrite_plan())
    closed["rewrite-plan"]["result"] = "no"
    closed["rewrite-plan"]["reasons"] = ["rewrite.license-no"]
    refused = integrate(text, envelope=closed)
    if refused["match"] != "no" or refused["applied"] != "no":
        raise RuntimeError("caller-plan-closed")

    for bag in (missing, illegal, wrong, refused):
        if bag["can-run-plan"] != "no" or bag["rewrite-path"] != "no":
            raise RuntimeError("caller-boundary")
        if apply.canonical_program(bag["program"]) != apply.canonical_program(extracted):
            raise RuntimeError("caller-source-mutated")


def replay_matrix() -> int:
    """Carrier-spellable fields only, then the case's own host arguments.

    `induced-hb` is not copied onto the extracted program. The one
    fixture that has it, postcondition-hb, still matches the host
    call on match and applied. This replay does not build a witness.
    """
    count = 0
    induced_rows: list[str] = []
    for name, envelopes, program, kwargs in apply._cases():
        extracted = project(carrier.render(program))
        if extracted != carrier._spellable(program):
            raise RuntimeError("spine-spellable-" + name)
        if "induced-hb" in extracted:
            raise RuntimeError("spine-induced-in-text-" + name)
        via = apply.evaluate_apply(
            copy.deepcopy(envelopes),
            copy.deepcopy(extracted),
            **copy.deepcopy(kwargs),
        )
        direct = apply.evaluate_apply(
            copy.deepcopy(envelopes),
            copy.deepcopy(program),
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
        if "induced-hb" in program:
            induced_rows.append(name)
            if via["applied"] == "yes" or direct["applied"] != "no":
                raise RuntimeError("spine-induced-fabricated-" + name)
        count += 1
    if count != 29:
        raise RuntimeError("spine-matrix-count")
    if induced_rows != ["postcondition-hb"]:
        raise RuntimeError("spine-induced-rows")
    return count


_CORPUS_KEYS = (
    "match",
    "applied",
    "rewrite-path",
    "can-run-plan",
    "reasons",
    "canonical-result",
    "source-unchanged",
    "envelope-unchanged",
    "authorization-calls",
)


def replay_corpus() -> int:
    """Spellable corpus scenes only. Do not copy `induced-hb`.

    S05's fixture failure depends on that field. Carrier text does
    not contain it. Observing the text does not reproduce the
    fixture's applied=no, and this replay does not paste the
    field back to force the pin.
    """
    specs = corpus._specs()
    spellable = 0
    saw_s05 = False
    for spec in specs:
        extracted = project(carrier.render(spec["program"]))
        if "induced-hb" in extracted:
            raise RuntimeError("spine-corpus-induced-in-text-" + spec["id"])
        if "induced-hb" in spec["program"]:
            if spec["id"] != "S05":
                raise RuntimeError("spine-corpus-induced-id")
            saw_s05 = True
            fixture = corpus.observe(spec["program"], spec["mode"], spec["envelope"])
            plain = corpus.observe(extracted, spec["mode"], spec["envelope"])
            if fixture["applied"] != "no" or fixture["match"] != "yes":
                raise RuntimeError("spine-s05-fixture")
            if plain["applied"] != "yes" or plain["match"] != "yes":
                raise RuntimeError("spine-s05-carrier")
            if plain["can-run-plan"] != "no" or "induced-hb" in plain:
                raise RuntimeError("spine-s05-copied")
            continue
        direct = corpus.observe(spec["program"], spec["mode"], spec["envelope"])
        via = corpus.observe(extracted, spec["mode"], spec["envelope"])
        for key in _CORPUS_KEYS:
            if via[key] != direct[key]:
                raise RuntimeError("spine-corpus-" + spec["id"])
        if via["can-run-plan"] != "no":
            raise RuntimeError("spine-corpus-plan-" + spec["id"])
        spellable += 1
    if not saw_s05 or spellable != 8:
        raise RuntimeError("spine-corpus-count")
    first = specs[0]
    extracted = project(carrier.render(first["program"]))
    second = corpus.observe(extracted, first["mode"], first["envelope"])
    direct_second = corpus.observe(first["program"], first["mode"], first["envelope"])
    for key in _CORPUS_KEYS:
        if second[key] != direct_second[key]:
            raise RuntimeError("spine-corpus-S10")
    return spellable


def check_guard_overlap() -> None:
    """Two guarded host calls overlap in one process. The real
    authorization function must still be the real one afterwards.

    `_apply_guarded` replaces process-global authorization functions
    while the host runs. Overlapping calls must not leave the
    replacement installed.
    """
    import record_authorization as auth

    real_eval = apply.evaluate_apply
    real_auth = auth.evaluate_authorization
    envelope = corpus._real_plan()
    program = corpus._programs()["success"]
    witness = corpus._witness(program, "bound")

    def slow(envelopes, prog, **kwargs):
        time.sleep(0.05)
        return real_eval(envelopes, prog, **kwargs)

    errors: list[str] = []

    def run() -> None:
        try:
            corpus._apply_guarded(
                copy.deepcopy(envelope),
                copy.deepcopy(program),
                copy.deepcopy(witness),
            )
        except BaseException as exc:  # noqa: BLE001
            errors.append(repr(exc))

    apply.evaluate_apply = slow
    try:
        threads = [threading.Thread(target=run) for _ in range(3)]
        for thread in threads:
            thread.start()
            time.sleep(0.01)
        for thread in threads:
            thread.join()
    finally:
        apply.evaluate_apply = real_eval
    if errors:
        raise RuntimeError("guard-overlap-error " + errors[0])
    if auth.evaluate_authorization is not real_auth:
        raise RuntimeError("guard-overlap-poisoned")
    auth.evaluate_authorization(auth._all_required() + [auth._license("yes")])


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
    scenes = replay_corpus()
    check_guard_overlap()
    check_caller_supplied()

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
        "corpus": scenes,
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
    print("induced-hb-copied no")
    print("scenario-corpus-spellable " + str(summary["corpus"]))
    print("S05-fixture applied no")
    print("S05-carrier-only applied yes")
    print("carrier-encodes-induced-hb no")
    print("authorization-guard-overlap restored")
    print("default-path authorization acceptance-fixture")
    print("default-path witness driver-built")
    print("default-path caller-authorized no")
    print("caller-witness-missing applied-no")
    print("caller-witness-illegal applied-no")
    print("caller-witness-wrong-device applied-no")
    print("caller-plan-closed match-no applied-no")
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
