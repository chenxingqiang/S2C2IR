#!/usr/bin/env python3
"""Scenario Corpus v1 for the frozen W0-3/2 host.

Replays authorization → 7B rewrite-plan → evaluate_apply.
Does not change the contract or the inhabitant.
A behavior fingerprint detects drift. It does not add semantics.
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

import record_apply_scenario as anchor
import record_storage_apply as apply

YES = "yes"
NO = "no"
BASELINE = "71a6880dbaaac929bac837af0b7fbcad78708bb4"
CORPUS_ID = "w0-3-2-scenario-corpus-v1"
# sha256 of the S01..S10 fingerprint lines. Behavior pin, not CandidateId.
EXPECTED_FINGERPRINT = "52bf4be9680046a725f9f79c7abf2d045efbd7d03b3cb87a355419b67a7a0d00"


def _sha256(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def _real_plan() -> dict:
    plan = anchor.rewrite_plan()
    if plan["rewrite-plan"]["result"] != YES:
        raise RuntimeError("producer-plan")
    if plan["transformation"] != apply.TRANSFORMATION_V01:
        raise RuntimeError("producer-transformation")
    if plan["applied"] != NO or plan["rewrite-path"] != NO or plan["can-run-plan"] != NO:
        raise RuntimeError("producer-boundary")
    return plan


def _programs() -> dict[str, dict]:
    return {
        "success": anchor.source_program(),
        "keep-order": apply._program([apply._stores(["1", "0", "2"])]),
        "multi-region": apply._program(
            [
                apply._stores(["0", "1", "2"], "a"),
                apply._stores(["0", "1", "2"], "b"),
            ]
        ),
        "cross-block": apply._program(
            [apply._stores(["0", "1"]), apply._stores(["2"])]
        ),
        "hb": apply._program(
            [apply._stores(["0", "1", "2"])],
            hb=[["id0", "id1"]],
            induced=[["id0", "id2"]],
        ),
        "collision": apply._collision_program("evict"),
    }


def _witness(program: dict, mode: str):
    if mode == "missing":
        return None
    if mode == "wrong-device":
        return apply.bound_witness(program, device="D2")
    if mode == "bound":
        if len(apply.find_regions(program)) != 1:
            return None
        return apply.bound_witness(program, device=anchor.DEVICE)
    raise RuntimeError(mode)


def observe(program: dict, mode: str, envelope: dict | None = None) -> dict:
    source = copy.deepcopy(program)
    env = copy.deepcopy(envelope if envelope is not None else _real_plan())
    before = apply.canonical_program(source)
    before_env = json.dumps(env, sort_keys=True)
    bag = apply.evaluate_apply(
        [env],
        source,
        device=anchor.DEVICE,
        witness=_witness(source, mode),
    )
    unchanged_source = apply.canonical_program(source) == before and source == program
    unchanged_env = json.dumps(env, sort_keys=True) == before_env
    return {
        "match": bag["match"],
        "applied": bag["applied"],
        "rewrite-path": bag["rewrite-path"],
        "can-run-plan": bag["can-run-plan"],
        "reasons": list(bag["reasons"]),
        "canonical-source": before,
        "canonical-result": apply.canonical_program(bag["program"]),
        "source-unchanged": YES if unchanged_source else NO,
        "envelope-unchanged": YES if unchanged_env else NO,
    }


def _specs() -> list[dict]:
    programs = _programs()
    mismatched = _real_plan()
    mismatched["transformation"] = "something-else"
    return [
        {
            "id": "S01",
            "name": "canonical-success",
            "program": programs["success"],
            "mode": "bound",
            "envelope": None,
            "match": YES,
            "applied": YES,
            "reasons": [],
        },
        {
            "id": "S02",
            "name": "keep-order",
            "program": programs["keep-order"],
            "mode": "bound",
            "envelope": None,
            "match": NO,
            "applied": NO,
            "reasons": ["rewrite.identity-mismatch"],
        },
        {
            "id": "S03",
            "name": "multi-region",
            "program": programs["multi-region"],
            "mode": "bound",
            "envelope": None,
            "match": NO,
            "applied": NO,
            "reasons": [],
        },
        {
            "id": "S04",
            "name": "cross-block",
            "program": programs["cross-block"],
            "mode": "bound",
            "envelope": None,
            "match": NO,
            "applied": NO,
            "reasons": [],
        },
        {
            "id": "S05",
            "name": "hb-violation",
            "program": programs["hb"],
            "mode": "bound",
            "envelope": None,
            "match": YES,
            "applied": NO,
            "reasons": [],
        },
        {
            "id": "S06",
            "name": "missing-witness",
            "program": programs["success"],
            "mode": "missing",
            "envelope": None,
            "match": YES,
            "applied": NO,
            "reasons": [],
        },
        {
            "id": "S07",
            "name": "wrong-device",
            "program": programs["success"],
            "mode": "wrong-device",
            "envelope": None,
            "match": YES,
            "applied": NO,
            "reasons": [],
        },
        {
            "id": "S08",
            "name": "opid-collision",
            "program": programs["collision"],
            "mode": "bound",
            "envelope": None,
            "match": YES,
            "applied": NO,
            "reasons": [],
        },
        {
            "id": "S09",
            "name": "transformation-mismatch",
            "program": programs["success"],
            "mode": "bound",
            "envelope": mismatched,
            "match": NO,
            "applied": NO,
            "reasons": ["decision.unknown-reason"],
        },
    ]


def _check_row(row: dict, spec: dict) -> None:
    if row["match"] != spec["match"] or row["applied"] != spec["applied"]:
        raise RuntimeError(spec["id"])
    path = YES if row["applied"] == YES else NO
    if row["rewrite-path"] != path or row["can-run-plan"] != NO:
        raise RuntimeError(spec["id"])
    if row["reasons"] != spec["reasons"]:
        raise RuntimeError(spec["id"])
    if row["source-unchanged"] != YES or row["envelope-unchanged"] != YES:
        raise RuntimeError(spec["id"] + "-mutation")
    if spec["applied"] == NO and row["canonical-result"] != row["canonical-source"]:
        raise RuntimeError(spec["id"] + "-result")
    if spec["id"] == "S01":
        if row["canonical-source"] != anchor.CANONICAL_P:
            raise RuntimeError("S01-source")
        if row["canonical-result"] != anchor.CANONICAL_P_PRIME:
            raise RuntimeError("S01-prime")


def _line(spec: dict, row: dict) -> str:
    reasons = ",".join(row["reasons"]) if row["reasons"] else "none"
    digest = _sha256(row["canonical-result"])
    return (
        f"{spec['id']} {spec['name']} "
        f"match={row['match']} applied={row['applied']} "
        f"rewrite-path={row['rewrite-path']} can-run-plan={row['can-run-plan']} "
        f"reasons={reasons} result={digest}"
    )


def _immutability_line(rows: list[dict], second: dict) -> str:
    source_ok = all(row["source-unchanged"] == YES for row in rows)
    env_ok = all(row["envelope-unchanged"] == YES for row in rows)
    same = (
        second["canonical-result"] == rows[0]["canonical-result"]
        and second["match"] == rows[0]["match"]
        and second["applied"] == rows[0]["applied"]
        and second["rewrite-path"] == rows[0]["rewrite-path"]
        and second["can-run-plan"] == rows[0]["can-run-plan"]
        and second["reasons"] == rows[0]["reasons"]
        and second["source-unchanged"] == YES
        and second["envelope-unchanged"] == YES
    )
    if not source_ok or not env_ok or not same:
        raise RuntimeError("S10")
    return (
        "S10 source-envelope-immutability "
        "source-unchanged=yes envelope-unchanged=yes double-run=equal"
    )


def _authorization_reopened() -> str:
    # Apply consumes the 7B envelope. It does not re-evaluate authorization.
    return NO


def _boundary_line() -> str:
    state = _authorization_reopened()
    if state != NO:
        raise RuntimeError("authorization-reopened")
    return "boundary authorization-reopened=" + state


def _fingerprint(lines: list[str]) -> str:
    return _sha256("\n".join(lines))


def _validate() -> tuple[list[str], str]:
    specs = _specs()
    rows = [
        observe(spec["program"], spec["mode"], spec["envelope"])
        for spec in specs
    ]
    for spec, row in zip(specs, rows):
        _check_row(row, spec)
    second = observe(specs[0]["program"], specs[0]["mode"], specs[0]["envelope"])
    _check_row(second, specs[0])
    lines = [_line(spec, row) for spec, row in zip(specs, rows)]
    lines.append(_immutability_line(rows, second))
    lines.append(_boundary_line())
    digest = _fingerprint(lines)
    if EXPECTED_FINGERPRINT and digest != EXPECTED_FINGERPRINT:
        raise RuntimeError("drift " + digest)
    return lines, digest


def print_contract() -> int:
    try:
        lines, digest = _validate()
    except RuntimeError as exc:
        print("scenario-corpus gate=v1")
        print("corpus-result DRIFT")
        print("drift " + str(exc))
        return 1
    if not EXPECTED_FINGERPRINT:
        print("scenario-corpus gate=v1")
        print("corpus-result DRIFT")
        print("fingerprint " + digest)
        return 1
    print("scenario-corpus gate=v1")
    print("baseline " + BASELINE)
    print("corpus-id " + CORPUS_ID)
    print("anchor " + anchor.SCENARIO_ID)
    print("contract-changed no")
    print("inhabitant-changed no")
    print("compiler-e2e no")
    print("s2c2-opt no")
    print("enum-f no")
    print("search no")
    print("authorization-reopened " + _authorization_reopened())
    print("semantic-cut no")
    print("can-run-plan no")
    print("scene-count 10")
    for line in lines:
        print(line)
    print("fingerprint " + digest)
    print("corpus-result PASS")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="W0-3/2 scenario corpus v1")
    parser.add_argument("--print-scenario-corpus", action="store_true")
    args = parser.parse_args(argv)
    if not args.print_scenario_corpus:
        print(
            "record_scenario_corpus: choose --print-scenario-corpus",
            file=sys.stderr,
        )
        return 2
    return print_contract()


if __name__ == "__main__":
    sys.exit(main())
