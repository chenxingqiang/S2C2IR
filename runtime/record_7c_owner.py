#!/usr/bin/env python3
"""Record owner decisions 3A and 5A without opening the cut.

The witness stays external. A missing witness stays unapplied.
The connectivity amendment covers only the IR-to-host-program
mapping. Recording it does not open next_cut.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_ROOT = _RUNTIME.parent
_PROPOSAL = _ROOT / "docs/design/cut-7c-proposal.md"
_ROADMAP = _ROOT / "docs/roadmap.md"
_SPINE = _ROOT / "docs/design/compiler-spine.md"
_BOUNDARY = _ROOT / "docs/design/empirical-semantic-boundary-v1.md"

_PROPOSAL_SENTENCES = (
    "**Answered: 3A.**",
    "The witness stays external.",
    "The orchestrator does not manufacture a witness.",
    "A missing witness stays `applied=no`.",
    "**Answered: 5A.**",
    "the mapping from IR to the W0-3/2 host program",
    "Recording this amendment does not open the cut.",
    "`next_cut` stays `NOT OPENED`",
    "7D, 7E, 7F, and 8A stay NOT OPENED",
    "no new dialect op",
    "carrier stays unregistered in s2c2-opt",
    "can-run-plan stays no",
    "the optimizer still does not call evaluate_apply",
)

_ROADMAP_SENTENCES = (
    "legality witness stays external (3A)",
    "connectivity amendment (5A)",
    "mapping from IR to the W0-3/2 host program",
    "Recording that amendment does not open the cut.",
    "`next_cut` stays `NOT OPENED`.",
    "A missing witness stays `applied=no`.",
    "The orchestrator does not manufacture a witness.",
    "No new dialect op is added.",
    "The carrier stays unregistered in `s2c2-opt`.",
    "`can-run-plan` stays `no`.",
)

_SPINE_SENTENCES = (
    "decision 3 as 3A",
    "decision 5 as 5A",
    "The witness stays external.",
    "The orchestrator does not manufacture a witness.",
    "A missing witness stays `applied=no`.",
    "mapping from IR to the W0-3/2 host program",
    "Recording this amendment does not open the cut.",
    "`next_cut` stays `NOT OPENED`.",
    "No new dialect op is added.",
    "The carrier stays unregistered in `s2c2-opt`.",
    "`can-run-plan` stays `no`.",
    "7D, 7E, 7F, and 8A stay `NOT OPENED`.",
)

_BOUNDARY_SENTENCES = (
    "The witness stays external.",
    "A missing witness stays `applied=no`.",
    "The orchestrator does not manufacture a witness.",
    "No new dialect op is added.",
    "The carrier stays unregistered in `s2c2-opt`.",
    "`can-run-plan` stays `no`.",
    "7D, 7E, 7F, and 8A stay `NOT OPENED`.",
    "Recording this amendment does not open the cut.",
    "`next_cut` stays `NOT OPENED`.",
)

_CLOSED = (
    "Decisions 3 and 5 are open",
    "Needs the owner to confirm",
)


def _text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _flat(text: str) -> str:
    return " ".join(text.split())


def _has_all(text: str, sentences: tuple[str, ...]) -> bool:
    flat = _flat(text)
    return all(sentence in flat for sentence in sentences)


def _compiler_has_no_host(root: Path) -> bool:
    for folder in ("include/s2c2", "lib", "tools"):
        base = root / folder
        if not base.is_dir():
            return False
        for path in base.rglob("*"):
            if path.suffix not in {".cpp", ".h", ".td"}:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            if "evaluate_apply" in text or "record_mlir_carrier" in text:
                return False
    return True


def _missing_witness_unapplied() -> bool:
    if str(_RUNTIME) not in sys.path:
        sys.path.insert(0, str(_RUNTIME))
    import record_apply_scenario as scenario
    import record_optimum_authorization as opt

    costs = opt.costs_from_measured(
        opt._CAPACITY_TABLE, opt._CAPACITY_PROFILE, opt._CAPACITY_WORKLOAD
    )
    plan = opt.load_capacity_plan(opt._CAPACITY_DEST)
    chosen = opt.authorize_capacity(plan, costs)
    program = opt.program_for_selection(chosen["strategy-id"])
    if not isinstance(program, dict):
        return False
    applied = opt.apply_capacity(
        plan,
        costs,
        program,
        device=scenario.DEVICE,
        witness=None,
    )
    return applied.get("applied") == "no"


def _ops_unchanged() -> bool:
    if str(_RUNTIME) not in sys.path:
        sys.path.insert(0, str(_RUNTIME))
    import record_goal_alignment as goal

    counts = goal.check()
    return counts == {"stor": 7, "comp": 3, "comm": 3, "sched": 7}


def print_7c_owner() -> int:
    try:
        proposal = _text(_PROPOSAL)
        roadmap = _text(_ROADMAP)
        spine = _text(_SPINE)
        boundary = _text(_BOUNDARY)
    except OSError:
        print("7c-owner no")
        return 1
    if any(closed in _flat(proposal) for closed in _CLOSED):
        print("7c-owner no")
        return 1
    if not (
        _has_all(proposal, _PROPOSAL_SENTENCES)
        and _has_all(roadmap, _ROADMAP_SENTENCES)
        and _has_all(spine, _SPINE_SENTENCES)
        and _has_all(boundary, _BOUNDARY_SENTENCES)
        and _compiler_has_no_host(_ROOT)
        and _missing_witness_unapplied()
        and _ops_unchanged()
    ):
        print("7c-owner no")
        return 1
    print("7c-owner gate=record")
    print("decision-3 3A")
    print("witness-source external")
    print("witness-missing applied=no")
    print("decision-5 5A")
    print("connectivity-amendment recorded")
    print("amendment-opens-cut no")
    print("next-cut NOT-OPENED")
    print("can-run-plan no")
    print("carrier-in-s2c2-opt no")
    print("ops-added no")
    print("7d-opened no")
    print("7e-opened no")
    print("7f-opened no")
    print("8a-opened no")
    print("7c-owner yes")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-7c-owner"]:
        print(
            "record_7c_owner: choose --print-7c-owner",
            file=sys.stderr,
        )
        return 2
    return print_7c_owner()


if __name__ == "__main__":
    sys.exit(main())
