#!/usr/bin/env python3
"""W0-3/2 IR Apply Inhabitant v0.

One checkable instance of the frozen #139 contract.
Consumes a 7B envelope. Does not re-evaluate 6C-M / 7A / 7B.
Does not run Enum_F, Search, authorization, or can-run-plan.

CandidateId(P') = canonical(P').
pi_R : E_sem(P) -> E_sem(P') is bijective.
HB* is the transitive semantic relation, not raw edges.
P' = P means canonical(P') = canonical(P).
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

import record_storage_rewrite as rew

APPLY_SCHEMA = "s2c2.storage_apply.v1"
REWRITE_SCHEMA = rew.REWRITE_SCHEMA
AUTH_SCHEMA = rew.AUTH_SCHEMA
DECISION_SCHEMA = rew.DECISION_SCHEMA
WITNESS_SCHEMA = "s2c2.apply_legality_witness.v1"
ACTION_V01 = rew.ACTION_V01
LICENSE_KIND_V01 = rew.LICENSE_KIND_V01
SELECTED_S0 = rew.SELECTED_S0
SELECTED_S1 = rew.SELECTED_S1
OBJECT_2 = rew.OBJECT_2
OBJECT_3 = rew.OBJECT_3
SEQUENCE_V01 = rew.SEQUENCE_V01
TRANSFORMATION_V01 = rew.TRANSFORMATION_V01
MACHINERY = ("evict", "transfer")
FORBIDDEN = ("prefetch", "preserve", "rematerialize", "evict", "transfer", "restore")
ALLOWED_OTHER = ("compute", "load")
EMITTED_REASONS = (
    "decision.unknown-reason",
    "rewrite.identity-mismatch",
    "rewrite.sequence-mismatch",
    "rewrite.duplicate-envelope",
    "rewrite.license-no",
)


def _ops(program: dict) -> list[dict]:
    found = []
    for block in program.get("blocks") or []:
        found.extend(block.get("ops") or [])
    return found


def _semantic_ids(program: dict) -> list[str]:
    return [
        op["op-id"]
        for op in _ops(program)
        if op.get("op") not in MACHINERY
    ]


def direct_edges(program: dict) -> list[tuple[str, str]]:
    if "hb" in program:
        return [(pair[0], pair[1]) for pair in program["hb"]]
    edges = []
    for block in program.get("blocks") or []:
        ids = [op["op-id"] for op in block.get("ops") or []]
        edges.extend(zip(ids, ids[1:]))
    return edges


def canonical_program(program: dict, edges: list[tuple[str, str]] | None = None) -> str:
    if edges is None:
        edges = direct_edges(program)
    body = {
        "blocks": [
            {
                "ops": [
                    {"name": op["name"], "op": op["op"], "op-id": op["op-id"]}
                    for op in block.get("ops") or []
                ]
            }
            for block in program.get("blocks") or []
        ],
        "capacity": program.get("capacity"),
        "hb": sorted([list(pair) for pair in edges]),
        "working-set": program.get("working-set"),
    }
    return json.dumps(body, separators=(",", ":"), sort_keys=True)


def programs_equal(left: dict, right: dict) -> bool:
    return canonical_program(left) == canonical_program(right)


def find_regions(program: dict) -> list[dict]:
    capacity = program.get("capacity")
    working_set = program.get("working-set")
    if capacity != 2 or isinstance(capacity, bool):
        return []
    if (
        not isinstance(working_set, int)
        or isinstance(working_set, bool)
        or working_set <= 2
    ):
        return []
    regions = []
    for block_index, block in enumerate(program.get("blocks") or []):
        ops = block.get("ops") or []
        store_at = [i for i, op in enumerate(ops) if op.get("op") == "store"]
        if len(store_at) < 3:
            continue
        for start, mid, end in zip(store_at, store_at[1:], store_at[2:]):
            window = ops[start : end + 1]
            if _window_rejected(window):
                continue
            stores = [op for op in window if op.get("op") == "store"]
            if len(stores) != 3:
                continue
            k1, k2, evicted = stores
            if not _named(k1) or not _named(k2) or not _named(evicted):
                continue
            regions.append(
                {
                    "block": block_index,
                    "i": start,
                    "j": end,
                    "k1": k1["name"],
                    "k2": k2["name"],
                    "e": evicted["name"],
                    "e-id": evicted["op-id"],
                }
            )
    return regions


def _named(op: dict) -> bool:
    return isinstance(op.get("name"), str) and isinstance(op.get("op-id"), str)


def _window_rejected(window: list[dict]) -> bool:
    for op in window:
        kind = op.get("op")
        if kind == "store":
            continue
        if kind in FORBIDDEN or kind not in ALLOWED_OTHER:
            return True
    return False


def realization_identity(program: dict, region: dict) -> tuple[str, str, str, str] | None:
    """Read-only on (P, R). Does not read a plan."""
    del program
    if region is None:
        return None
    selected = "keep{{{k1},{k2}}}|evict{{{e}}}|rematerialize{{}}".format(
        k1=region["k1"], k2=region["k2"], e=region["e"]
    )
    return (selected, OBJECT_2, ACTION_V01, LICENSE_KIND_V01)


def _sequence_matches(sequence, region: dict) -> bool:
    if isinstance(sequence, (list, tuple)) and all(isinstance(step, str) for step in sequence):
        return tuple(sequence) == SEQUENCE_V01
    if isinstance(sequence, (list, tuple)) and all(isinstance(step, dict) for step in sequence):
        got = [(step.get("step"), step.get("name")) for step in sequence]
        expect = [
            ("KEEP", region["k1"]),
            ("KEEP", region["k2"]),
            ("EVICT", region["e"]),
            ("TRANSFER", region["e"]),
            ("RESTORE", region["e"]),
        ]
        return got == expect
    return False


def _map_store(node: str, store_id: str, restore_id: str) -> str:
    return restore_id if node == store_id else node


def transform_edges(
    edges: list[tuple[str, str]],
    store_id: str,
    evict_id: str,
    transfer_id: str,
    restore_id: str,
    induced: list,
) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for src, dst in edges:
        if dst == store_id and src != store_id:
            out.append((src, evict_id))
        elif src == store_id and dst != store_id:
            out.append((restore_id, dst))
        elif src != store_id and dst != store_id:
            out.append((src, dst))
    out.append((evict_id, transfer_id))
    out.append((transfer_id, restore_id))
    for pair in induced:
        out.append(
            (
                _map_store(pair[0], store_id, restore_id),
                _map_store(pair[1], store_id, restore_id),
            )
        )
    return out


def _op_ids_unique(program: dict) -> bool:
    ids = [op.get("op-id") for op in _ops(program)]
    if any(not isinstance(item, str) or item == "" for item in ids):
        return False
    return len(ids) == len(set(ids))


def construct_candidate(program: dict, region: dict) -> dict:
    store_id = region["e-id"]
    evict_id = store_id + ".evict"
    transfer_id = store_id + ".transfer"
    restore_id = store_id + ".restore"
    blocks = []
    for block_index, block in enumerate(program.get("blocks") or []):
        ops = []
        for op in block.get("ops") or []:
            if block_index == region["block"] and op.get("op-id") == store_id:
                ops.append({"op": "evict", "name": region["e"], "op-id": evict_id})
                ops.append({"op": "transfer", "name": region["e"], "op-id": transfer_id})
                ops.append({"op": "restore", "name": region["e"], "op-id": restore_id})
            else:
                ops.append({"op": op["op"], "name": op["name"], "op-id": op["op-id"]})
        blocks.append({"ops": ops})
    edges = transform_edges(
        direct_edges(program),
        store_id,
        evict_id,
        transfer_id,
        restore_id,
        program.get("induced-hb") or [],
    )
    return {
        "blocks": blocks,
        "capacity": program.get("capacity"),
        "working-set": program.get("working-set"),
        "hb": [[src, dst] for src, dst in edges],
    }


def _reach(nodes: list[str], edges: list[tuple[str, str]]) -> set[tuple[str, str]]:
    succ: dict[str, set[str]] = {node: set() for node in nodes}
    for src, dst in edges:
        if src in succ and dst in succ and src != dst:
            succ[src].add(dst)
    pairs: set[tuple[str, str]] = set()
    for src in nodes:
        seen: set[str] = set()
        stack = list(succ[src])
        while stack:
            node = stack.pop()
            if node in seen:
                continue
            seen.add(node)
            pairs.add((src, node))
            stack.extend(succ[node])
    return pairs


def semantic_hb_pairs(program: dict, edges: list[tuple[str, str]] | None = None) -> set[tuple[str, str]]:
    if edges is None:
        edges = [(pair[0], pair[1]) for pair in program.get("hb") or []]
        if "hb" not in program:
            edges = direct_edges(program)
    nodes = [op["op-id"] for op in _ops(program)]
    semantic = set(_semantic_ids(program))
    return {
        (src, dst)
        for src, dst in _reach(nodes, edges)
        if src in semantic and dst in semantic
    }


def pi_map(program: dict, region: dict) -> dict[str, str]:
    restore_id = region["e-id"] + ".restore"
    mapping = {}
    for op_id in _semantic_ids(program):
        mapping[op_id] = restore_id if op_id == region["e-id"] else op_id
    return mapping


def projection_holds(source: dict, candidate: dict, region: dict) -> bool:
    mapping = pi_map(source, region)
    image = set(mapping.values())
    target_sem = set(_semantic_ids(candidate))
    if set(mapping) != set(_semantic_ids(source)):
        return False
    if len(mapping) != len(image):
        return False
    if image != target_sem:
        return False
    source_pairs = semantic_hb_pairs(source, direct_edges(source))
    mapped = {(mapping[src], mapping[dst]) for src, dst in source_pairs}
    return mapped == semantic_hb_pairs(candidate)


def witness_bound(witness, candidate_id: str, device: str, candidate: dict) -> bool:
    if not isinstance(witness, dict):
        return False
    if witness.get("schema") != WITNESS_SCHEMA:
        return False
    if witness.get("candidate-id") != candidate_id:
        return False
    if witness.get("device") != device:
        return False
    if witness.get("legal") != "yes":
        return False
    claimed = witness.get("hb")
    if not isinstance(claimed, list):
        return False
    got = {(pair[0], pair[1]) for pair in claimed}
    return got == semantic_hb_pairs(candidate)


def candidate_id_for(program: dict) -> str | None:
    regions = find_regions(program)
    if len(regions) != 1:
        return None
    return canonical_program(construct_candidate(program, regions[0]))


def bound_witness(program: dict, device: str = "D0", *, legal: str = "yes") -> dict:
    regions = find_regions(program)
    candidate = construct_candidate(program, regions[0])
    pairs = sorted(
        [list(pair) for pair in semantic_hb_pairs(candidate)]
    )
    return {
        "schema": WITNESS_SCHEMA,
        "candidate-id": canonical_program(candidate),
        "device": device,
        "legal": legal,
        "hb": pairs,
    }


def _identity_of(envelope: dict) -> dict:
    ident = envelope.get("identity") if isinstance(envelope, dict) else None
    if not isinstance(ident, dict):
        ident = {}
    return {
        "selected": ident.get("selected", ""),
        "object": ident.get("object", ""),
        "action": ident.get("action", ""),
        "license-kind": ident.get("license-kind", ""),
    }


def _well_formed_plan(plan) -> bool:
    if not isinstance(plan, dict):
        return False
    if plan.get("schema") != DECISION_SCHEMA:
        return False
    if plan.get("subject") != "rewrite-plan":
        return False
    if plan.get("result") not in ("yes", "no"):
        return False
    if not isinstance(plan.get("reasons"), list):
        return False
    return True


def _apply_result(
    *,
    identity: dict,
    plan: dict,
    match: str,
    applied: str,
    reasons: list[str],
    program: dict,
) -> dict:
    return {
        "schema": APPLY_SCHEMA,
        "source-schema": REWRITE_SCHEMA,
        "identity": identity,
        "rewrite-plan": plan,
        "match": match,
        "applied": applied,
        "rewrite-path": "yes" if applied == "yes" else "no",
        "can-run-plan": "no",
        "reasons": reasons,
        "program": program,
    }


def _empty_plan(reasons: list[str]) -> dict:
    return {
        "schema": DECISION_SCHEMA,
        "subject": "rewrite-plan",
        "result": "no",
        "reasons": list(reasons),
    }


def evaluate_apply(
    envelopes: list[dict],
    program: dict,
    *,
    device: str = "D0",
    witness=None,
) -> dict:
    original = copy.deepcopy(program)

    def finish(
        reasons: list[str],
        *,
        match: str,
        applied: str,
        plan: dict,
        identity: dict,
        result_program: dict,
    ) -> dict:
        return _apply_result(
            identity=identity,
            plan=plan,
            match=match,
            applied=applied,
            reasons=reasons,
            program=result_program,
        )

    def reject(reasons: list[str], identity: dict | None = None, plan: dict | None = None) -> dict:
        return finish(
            reasons,
            match="no",
            applied="no",
            plan=plan if plan is not None else _empty_plan(reasons),
            identity=identity if identity is not None else _identity_of({}),
            result_program=copy.deepcopy(original),
        )

    if not isinstance(envelopes, list) or len(envelopes) == 0:
        return reject(["decision.unknown-reason"])
    if len(envelopes) > 1:
        return reject(["rewrite.duplicate-envelope"])
    envelope = envelopes[0]
    if not isinstance(envelope, dict):
        return reject(["decision.unknown-reason"])
    identity = _identity_of(envelope)
    if envelope.get("schema") != REWRITE_SCHEMA:
        return reject(["decision.unknown-reason"], identity)
    if envelope.get("source-schema") != AUTH_SCHEMA:
        return reject(["decision.unknown-reason"], identity)
    plan = envelope.get("rewrite-plan")
    if not _well_formed_plan(plan):
        return reject(["decision.unknown-reason"], identity)
    plan = copy.deepcopy(plan)
    if plan["result"] != "yes":
        return reject(list(plan["reasons"]), identity, plan)
    if envelope.get("transformation") != TRANSFORMATION_V01:
        return reject(["decision.unknown-reason"], identity, plan)
    regions = find_regions(original)
    if len(regions) != 1:
        return reject([], identity, plan)
    region = regions[0]
    realized = realization_identity(original, region)
    plan_tuple = (
        identity["selected"],
        identity["object"],
        identity["action"],
        identity["license-kind"],
    )
    if realized != plan_tuple:
        return reject(["rewrite.identity-mismatch"], identity, plan)
    if not _sequence_matches(envelope.get("sequence"), region):
        return reject(["rewrite.sequence-mismatch"], identity, plan)

    candidate = construct_candidate(original, region)
    if not _op_ids_unique(candidate):
        return finish(
            [],
            match="yes",
            applied="no",
            plan=plan,
            identity=identity,
            result_program=copy.deepcopy(original),
        )
    candidate_id = canonical_program(candidate)
    if candidate_id == canonical_program(original):
        return finish(
            [],
            match="yes",
            applied="no",
            plan=plan,
            identity=identity,
            result_program=copy.deepcopy(original),
        )
    if not projection_holds(original, candidate, region):
        return finish(
            [],
            match="yes",
            applied="no",
            plan=plan,
            identity=identity,
            result_program=copy.deepcopy(original),
        )
    if not witness_bound(witness, candidate_id, device, candidate):
        return finish(
            [],
            match="yes",
            applied="no",
            plan=plan,
            identity=identity,
            result_program=copy.deepcopy(original),
        )
    return finish(
        [],
        match="yes",
        applied="yes",
        plan=plan,
        identity=identity,
        result_program=candidate,
    )


def _stores(names: list[str], prefix: str = "id") -> list[dict]:
    return [
        {"op": "store", "name": name, "op-id": f"{prefix}{name}"}
        for name in names
    ]


def _program(
    blocks: list[list[dict]],
    *,
    capacity: int = 2,
    working_set: int = 3,
    hb=None,
    induced=None,
) -> dict:
    program: dict = {
        "blocks": [{"ops": ops} for ops in blocks],
        "capacity": capacity,
        "working-set": working_set,
    }
    if hb is not None:
        program["hb"] = hb
    if induced is not None:
        program["induced-hb"] = induced
    return program


def _plan(
    *,
    selected: str = SELECTED_S0,
    obj: str = OBJECT_2,
    action: str = ACTION_V01,
    license_kind: str = LICENSE_KIND_V01,
    result: str = "yes",
    reasons: list[str] | None = None,
    sequence=None,
    source_schema: str = AUTH_SCHEMA,
    plan: dict | None = None,
    transformation: str | None = None,
) -> dict:
    if reasons is None:
        reasons = ["rewrite.plan-closed"] if result == "yes" else ["rewrite.license-no"]
    if sequence is None and result == "yes":
        sequence = list(SEQUENCE_V01)
    if sequence is None:
        sequence = "n/a"
    if transformation is None:
        transformation = TRANSFORMATION_V01 if result == "yes" else "n/a"
    return {
        "schema": REWRITE_SCHEMA,
        "source-schema": source_schema,
        "identity": {
            "selected": selected,
            "object": obj,
            "action": action,
            "license-kind": license_kind,
        },
        "rewrite-plan": plan
        if plan is not None
        else {
            "schema": DECISION_SCHEMA,
            "subject": "rewrite-plan",
            "result": result,
            "reasons": list(reasons),
        },
        "sequence": sequence,
        "transformation": transformation,
        "applied": "no",
        "rewrite-path": "no",
        "can-run-plan": "no",
    }


def _happy_program() -> dict:
    return _program([_stores(["0", "1", "2"])])


def _cases() -> list[tuple[str, list[dict], dict, dict]]:
    happy = _happy_program()
    sparse = _program(
        [_stores(["0", "1", "2"])],
        hb=[["id0", "id1"]],
        induced=[["id0", "id2"]],
    )
    return [
        ("plan-missing", [], happy, {}),
        ("plan-no", [_plan(result="no")], happy, {"witness": bound_witness(happy)}),
        ("apply-yes", [_plan()], happy, {"witness": bound_witness(happy)}),
        (
            "identity-selected",
            [_plan(selected=SELECTED_S1)],
            happy,
            {"witness": bound_witness(happy)},
        ),
        (
            "identity-object",
            [_plan(obj=OBJECT_3)],
            happy,
            {"witness": bound_witness(happy)},
        ),
        (
            "identity-prose-o2",
            [_plan(obj="O2")],
            happy,
            {"witness": bound_witness(happy)},
        ),
        (
            "identity-action",
            [_plan(action="schedule-rewrite")],
            happy,
            {"witness": bound_witness(happy)},
        ),
        (
            "identity-kind",
            [_plan(license_kind="other-kind")],
            happy,
            {"witness": bound_witness(happy)},
        ),
        (
            "sequence-reorder",
            [_plan(sequence=["KEEP", "RESTORE", "EVICT", "TRANSFER"])],
            happy,
            {"witness": bound_witness(happy)},
        ),
        (
            "sequence-prefetch",
            [_plan(sequence=["PREFETCH", "KEEP", "EVICT", "RESTORE"])],
            happy,
            {"witness": bound_witness(happy)},
        ),
        (
            "ir-extra-store",
            [_plan()],
            _program([_stores(["0", "1", "2", "3"])]),
            {},
        ),
        (
            "ir-missing-store",
            [_plan()],
            _program([_stores(["0", "1"])]),
            {},
        ),
        (
            "ir-unknown-op",
            [_plan()],
            _program(
                [
                    [
                        {"op": "store", "name": "0", "op-id": "id0"},
                        {"op": "prefetch", "name": "p", "op-id": "idp"},
                        {"op": "store", "name": "1", "op-id": "id1"},
                        {"op": "store", "name": "2", "op-id": "id2"},
                    ]
                ]
            ),
            {},
        ),
        ("duplicate-envelope", [_plan(), _plan()], happy, {}),
        (
            "malformed-plan",
            [_plan(plan={"result": "yes"})],
            happy,
            {},
        ),
        (
            "source-schema-mismatch",
            [_plan(source_schema="s2c2.nope.v1")],
            happy,
            {},
        ),
        (
            "transformation-mismatch",
            [_plan(transformation="something-else")],
            happy,
            {"witness": bound_witness(happy)},
        ),
        (
            "postcondition-hb",
            [_plan()],
            sparse,
            {"witness": bound_witness(sparse)},
        ),
        (
            "postcondition-legal",
            [_plan()],
            happy,
            {"witness": bound_witness(happy, legal="no")},
        ),
        ("witness-missing", [_plan()], happy, {"witness": None}),
        (
            "witness-wrong-id",
            [_plan()],
            happy,
            {
                "witness": {
                    **bound_witness(happy),
                    "candidate-id": canonical_program(happy),
                }
            },
        ),
        (
            "witness-wrong-device",
            [_plan()],
            happy,
            {"witness": bound_witness(happy, device="D2"), "device": "D0"},
        ),
        (
            "multi-region",
            [_plan()],
            _program([_stores(["0", "1", "2"], "a"), _stores(["0", "1", "2"], "b")]),
            {},
        ),
        (
            "capacity-other",
            [_plan()],
            _program([_stores(["0", "1", "2"])], capacity=4, working_set=5),
            {},
        ),
        (
            "cross-block",
            [_plan()],
            _program([_stores(["0", "1"]), _stores(["2"])]),
            {},
        ),
        (
            "keep-order",
            [_plan()],
            _program([_stores(["1", "0", "2"])]),
            {},
        ),
        (
            "collide-evict",
            [_plan()],
            _collision_program("evict"),
            {"witness": bound_witness(_collision_program("evict"))},
        ),
        (
            "collide-transfer",
            [_plan()],
            _collision_program("transfer"),
            {"witness": bound_witness(_collision_program("transfer"))},
        ),
        (
            "collide-restore",
            [_plan()],
            _collision_program("restore"),
            {"witness": bound_witness(_collision_program("restore"))},
        ),
    ]


def _collision_program(suffix: str) -> dict:
    # A second block keeps the W0-3/2 window unique. The colliding
    # op is machinery so it stays outside E_sem; set-based projection
    # can still accept the candidate.
    kind = "evict" if suffix == "restore" else suffix
    return _program(
        [
            _stores(["0", "1", "2"]),
            [{"op": kind, "name": "old", "op-id": "id2." + suffix}],
        ]
    )


def _validate() -> None:
    names = [name for name, _, _, _ in _cases()]
    expect = [
        "plan-missing",
        "plan-no",
        "apply-yes",
        "identity-selected",
        "identity-object",
        "identity-prose-o2",
        "identity-action",
        "identity-kind",
        "sequence-reorder",
        "sequence-prefetch",
        "ir-extra-store",
        "ir-missing-store",
        "ir-unknown-op",
        "duplicate-envelope",
        "malformed-plan",
        "source-schema-mismatch",
        "transformation-mismatch",
        "postcondition-hb",
        "postcondition-legal",
        "witness-missing",
        "witness-wrong-id",
        "witness-wrong-device",
        "multi-region",
        "capacity-other",
        "cross-block",
        "keep-order",
        "collide-evict",
        "collide-transfer",
        "collide-restore",
    ]
    if names != expect:
        raise RuntimeError(names)
    happy = _happy_program()
    region = find_regions(happy)[0]
    realized = realization_identity(happy, region)
    if realized != (SELECTED_S0, OBJECT_2, ACTION_V01, LICENSE_KIND_V01):
        raise RuntimeError(realized)
    if realized[1] != "2":
        raise RuntimeError("object canonical")
    again = construct_candidate(happy, region)
    if canonical_program(again) != canonical_program(construct_candidate(happy, region)):
        raise RuntimeError("not deterministic")
    if programs_equal(happy, again):
        raise RuntimeError("identity transform")
    if not programs_equal(happy, copy.deepcopy(happy)):
        raise RuntimeError("canonical equality")
    if not projection_holds(happy, again, region):
        raise RuntimeError("happy projection")
    if not _op_ids_unique(again):
        raise RuntimeError("happy ids")
    for suffix in ("evict", "transfer", "restore"):
        collided = _collision_program(suffix)
        collided_region = find_regions(collided)
        if len(collided_region) != 1:
            raise RuntimeError(suffix)
        collided_candidate = construct_candidate(collided, collided_region[0])
        if _op_ids_unique(collided_candidate):
            raise RuntimeError(f"collision missed {suffix}")
        if not projection_holds(collided, collided_candidate, collided_region[0]):
            raise RuntimeError(f"projection hid {suffix}")
    image = set(pi_map(happy, region).values())
    if image != set(_semantic_ids(again)):
        raise RuntimeError("not bijective")
    if any(op["op"] in MACHINERY and op["op-id"] in image for op in _ops(again)):
        raise RuntimeError("machinery in E_sem")
    extra = copy.deepcopy(again)
    extra["blocks"][0]["ops"].append({"op": "compute", "name": "z", "op-id": "extra"})
    if projection_holds(happy, extra, region):
        raise RuntimeError("extra semantic event accepted")
    for name, envelopes, program, kwargs in _cases():
        before = copy.deepcopy(program)
        before_env = copy.deepcopy(envelopes)
        bag = evaluate_apply(envelopes, program, **kwargs)
        if program != before or envelopes != before_env:
            raise RuntimeError(f"mutated {name}")
        if bag["schema"] != APPLY_SCHEMA or bag["source-schema"] != REWRITE_SCHEMA:
            raise RuntimeError(name)
        if bag["can-run-plan"] != "no":
            raise RuntimeError(name)
        if bag["match"] == "no" and bag["applied"] == "yes":
            raise RuntimeError(f"match-no applied-yes {name}")
        if bag["applied"] == "yes" and bag["match"] != "yes":
            raise RuntimeError(name)
        if bag["rewrite-path"] != bag["applied"]:
            raise RuntimeError(f"path mirror {name}")
        if bag["applied"] == "no" and not programs_equal(bag["program"], program):
            raise RuntimeError(f"program changed {name}")
        if bag["applied"] == "yes" and programs_equal(bag["program"], program):
            raise RuntimeError(f"applied without change {name}")
        for token in bag["reasons"]:
            if token.startswith("rewrite.apply"):
                raise RuntimeError(token)
            if token not in EMITTED_REASONS:
                raise RuntimeError(f"{name} {token}")
        blob = json.dumps(bag)
        if "Enum_F" in blob or "can-run-plan\": \"yes\"" in blob:
            raise RuntimeError(name)
        if name == "apply-yes":
            kinds = [op["op"] for op in _ops(bag["program"])]
            if kinds != ["store", "store", "evict", "transfer", "restore"]:
                raise RuntimeError(kinds)
            if bag["rewrite-plan"]["result"] != "yes":
                raise RuntimeError(name)
            if bag["identity"]["object"] != "2":
                raise RuntimeError(name)
            if canonical_program(bag["program"]) != candidate_id_for(program):
                raise RuntimeError("candidate-id")
        if name in (
            "plan-missing",
            "malformed-plan",
            "source-schema-mismatch",
            "transformation-mismatch",
        ):
            if bag["reasons"] != ["decision.unknown-reason"] or bag["match"] != "no":
                raise RuntimeError(name)
        if name == "plan-no":
            if bag["reasons"] != ["rewrite.license-no"] or bag["applied"] != "no":
                raise RuntimeError(name)
        if name == "duplicate-envelope":
            if bag["reasons"] != ["rewrite.duplicate-envelope"]:
                raise RuntimeError(name)
        if name in (
            "identity-selected",
            "identity-object",
            "identity-prose-o2",
            "identity-action",
            "identity-kind",
            "keep-order",
        ):
            if bag["reasons"] != ["rewrite.identity-mismatch"] or bag["match"] != "no":
                raise RuntimeError(name)
        if name in ("sequence-reorder", "sequence-prefetch"):
            if bag["reasons"] != ["rewrite.sequence-mismatch"]:
                raise RuntimeError(name)
        if name in (
            "ir-extra-store",
            "ir-missing-store",
            "ir-unknown-op",
            "multi-region",
            "capacity-other",
            "cross-block",
        ):
            if bag["match"] != "no" or bag["reasons"] != [] or bag["applied"] != "no":
                raise RuntimeError(name)
        if name == "capacity-other" and bag["identity"]["object"] != OBJECT_2:
            raise RuntimeError("stringified capacity")
        if name in (
            "postcondition-hb",
            "postcondition-legal",
            "witness-missing",
            "witness-wrong-id",
            "witness-wrong-device",
            "collide-evict",
            "collide-transfer",
            "collide-restore",
        ):
            if bag["match"] != "yes" or bag["applied"] != "no" or bag["reasons"] != []:
                raise RuntimeError(name)


def print_contract() -> int:
    _validate()
    print("apply-inhabitant gate=check")
    print(f"schema {APPLY_SCHEMA}")
    print(f"source-schema {REWRITE_SCHEMA}")
    print("pattern W0-3/2")
    print("object-canonical 2")
    print("prose-O2-ne-object yes")
    print("candidate-id canonical-text")
    print("hash-is-candidate-id no")
    print("pi-bijective yes")
    print("hb-star not-raw-edges yes")
    print("enum-f no")
    print("search no")
    print("authorization-reopened no")
    print("can-run-plan no")
    print("rewrite-path-mirrors-applied yes")
    print("match-yes-applied-no allowed")
    print("match-no-applied-yes forbidden")
    print("decision-subject-rewrite-applicable no")
    print(f"apply-matrix-cases {len(_cases())}")
    print("host-side-decision-contract yes")
    print("compiler-e2e no")
    print("f-storage-schedule-not-inhabited yes")
    print("generic-rewrite-engine no")
    happy = _happy_program()
    example = evaluate_apply([_plan()], happy, witness=bound_witness(happy))
    print("example-applied " + example["applied"])
    print("example-match " + example["match"])
    print("example-rewrite-path " + example["rewrite-path"])
    print("example-can-run-plan " + example["can-run-plan"])
    print("example " + json.dumps(example, separators=(",", ":"), sort_keys=True))
    print("cost=unchanged")
    return 0


def print_matrix() -> int:
    _validate()
    print("apply-matrix gate=check")
    print(f"apply-matrix-cases {len(_cases())}")
    print("match-no-applied-yes forbidden")
    for name, envelopes, program, kwargs in _cases():
        bag = evaluate_apply(envelopes, program, **kwargs)
        reasons = ",".join(bag["reasons"]) if bag["reasons"] else "none"
        print(f"app-case {name}")
        print(f"app-match {bag['match']}")
        print(f"app-applied {bag['applied']}")
        print(f"app-rewrite-path {bag['rewrite-path']}")
        print(f"app-can-run-plan {bag['can-run-plan']}")
        print(f"app-reasons {reasons}")
    print("can-run-plan no")
    print("enum-f no")
    print("cost=unchanged")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="S2C2 W0-3/2 Apply Inhabitant v0")
    parser.add_argument("--print-apply-contract", action="store_true")
    parser.add_argument("--print-apply-matrix", action="store_true")
    args = parser.parse_args(argv)
    flags = (args.print_apply_contract, args.print_apply_matrix)
    if sum(bool(flag) for flag in flags) != 1:
        print(
            "record_storage_apply: choose one of "
            "--print-apply-contract "
            "--print-apply-matrix",
            file=sys.stderr,
        )
        return 2
    if args.print_apply_contract:
        return print_contract()
    return print_matrix()


if __name__ == "__main__":
    sys.exit(main())
