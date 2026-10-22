#!/usr/bin/env python3
"""MLIR Carrier v0 text extract.

Projects the carrier grammar onto the dict evaluate_apply already
consumes. Does not interpret regions, HB*, or witnesses.
Does not modify the host. Does not add a TableGen dialect.
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
import record_storage_apply as apply


class ExtractRefusal(Exception):
    def __init__(self, code: str) -> None:
        self.code = code
        super().__init__(code)


_MODULE_ATTRS = {
    "s2c2.carrier.capacity",
    "s2c2.carrier.working_set",
}
_FACT_ATTRS = {"name", "op", "op_id"}
_HB_ATTRS = {"from", "to"}


def extract(text: str) -> dict:
    tokens = _tokenize(text)
    parser = _Parser(tokens)
    return parser.parse_module()


def _tokenize(text: str) -> list[tuple[str, object]]:
    tokens: list[tuple[str, object]] = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch.isspace():
            i += 1
            continue
        if ch in "{}=,":
            tokens.append((ch, ch))
            i += 1
            continue
        if ch == ":":
            tokens.append((":", ":"))
            i += 1
            continue
        if ch == '"':
            j = i + 1
            buf: list[str] = []
            while j < n and text[j] != '"':
                if text[j] == "\\":
                    raise ExtractRefusal("syntax")
                buf.append(text[j])
                j += 1
            if j >= n:
                raise ExtractRefusal("syntax")
            tokens.append(("str", "".join(buf)))
            i = j + 1
            continue
        if ch == "-" or ch.isdigit():
            j = i
            if text[j] == "-":
                j += 1
            if j >= n or not text[j].isdigit():
                raise ExtractRefusal("syntax")
            while j < n and text[j].isdigit():
                j += 1
            tokens.append(("int", int(text[i:j])))
            i = j
            continue
        if ch.isalpha() or ch == "_" or ch == ".":
            j = i
            while j < n and (text[j].isalnum() or text[j] in "._"):
                j += 1
            tokens.append(("id", text[i:j]))
            i = j
            continue
        raise ExtractRefusal("syntax")
    return tokens


class _Parser:
    def __init__(self, tokens: list[tuple[str, object]]) -> None:
        self.tokens = tokens
        self.i = 0

    def parse_module(self) -> dict:
        if not self._at("id", "module"):
            raise ExtractRefusal("not-one-module")
        self._take()
        attrs: dict[str, tuple] = {}
        if self._at("id", "attributes"):
            self._take()
            attrs = self._attr_dict()
        if not self._at("{"):
            raise ExtractRefusal("syntax")
        self._take()
        blocks: list[dict] = []
        hb_pairs: list[list[str]] = []
        saw_hb = False
        while not self._at("}"):
            if self._at("id", "carrier.block"):
                self._take()
                ops, pairs, saw = self._block()
                blocks.append({"ops": ops})
                hb_pairs.extend(pairs)
                saw_hb = saw_hb or saw
                continue
            if self._at("id", "carrier.fact"):
                raise ExtractRefusal("fact-outside-block")
            if self._at("id", "carrier.hb"):
                raise ExtractRefusal("hb-outside-block")
            raise ExtractRefusal("closed-set")
        self._take()
        if self.i != len(self.tokens):
            raise ExtractRefusal("not-one-module")
        if not blocks:
            raise ExtractRefusal("zero-block")
        program = _module_fields(attrs, blocks, hb_pairs, saw_hb)
        return program

    def _block(self) -> tuple[list[dict], list[list[str]], bool]:
        if not self._at("{"):
            raise ExtractRefusal("syntax")
        self._take()
        ops: list[dict] = []
        pairs: list[list[str]] = []
        saw = False
        while not self._at("}"):
            if self._at("id", "carrier.fact"):
                self._take()
                ops.append(self._fact())
                continue
            if self._at("id", "carrier.hb"):
                self._take()
                pairs.append(self._edge())
                saw = True
                continue
            raise ExtractRefusal("closed-set")
        self._take()
        return ops, pairs, saw

    def _fact(self) -> dict:
        attrs = self._attr_dict()
        self._reject_nested()
        keys = set(attrs)
        if not keys <= _FACT_ATTRS:
            raise ExtractRefusal("closed-set")
        if "name" not in keys:
            raise ExtractRefusal("missing-name")
        if "op" not in keys:
            raise ExtractRefusal("missing-op")
        if "op_id" not in keys:
            raise ExtractRefusal("missing-op-id")
        name, op, op_id = (_string(attrs[key]) for key in ("name", "op", "op_id"))
        return {"name": name, "op": op, "op-id": op_id}

    def _edge(self) -> list[str]:
        attrs = self._attr_dict()
        self._reject_nested()
        keys = set(attrs)
        if not keys <= _HB_ATTRS:
            raise ExtractRefusal("closed-set")
        if "from" not in keys:
            raise ExtractRefusal("missing-hb-from")
        if "to" not in keys:
            raise ExtractRefusal("missing-hb-to")
        return [_string(attrs["from"]), _string(attrs["to"])]

    def _reject_nested(self) -> None:
        if self._at("{"):
            raise ExtractRefusal("nested-region")

    def _attr_dict(self) -> dict[str, tuple]:
        if not self._at("{"):
            raise ExtractRefusal("syntax")
        self._take()
        attrs: dict[str, tuple] = {}
        if self._at("}"):
            self._take()
            return attrs
        while True:
            if not self._at_kind("id"):
                raise ExtractRefusal("syntax")
            key = str(self._take()[1])
            if not self._at("="):
                raise ExtractRefusal("syntax")
            self._take()
            if key in attrs:
                raise ExtractRefusal("syntax")
            attrs[key] = self._value()
            if self._at(","):
                self._take()
                if self._at("}"):
                    self._take()
                    break
                continue
            if self._at("}"):
                self._take()
                break
            raise ExtractRefusal("syntax")
        return attrs

    def _value(self) -> tuple:
        if self._at_kind("str"):
            return ("str", self._take()[1])
        if self._at_kind("int"):
            number = self._take()[1]
            if not self._at(":"):
                raise ExtractRefusal("syntax")
            self._take()
            if not self._at_kind("id"):
                raise ExtractRefusal("syntax")
            return ("int", number, self._take()[1])
        raise ExtractRefusal("syntax")

    def _at(self, kind: str, value: object | None = None) -> bool:
        if self.i >= len(self.tokens):
            return False
        got_kind, got_value = self.tokens[self.i]
        if got_kind != kind:
            return False
        return value is None or got_value == value

    def _at_kind(self, kind: str) -> bool:
        return self.i < len(self.tokens) and self.tokens[self.i][0] == kind

    def _take(self) -> tuple[str, object]:
        if self.i >= len(self.tokens):
            raise ExtractRefusal("syntax")
        token = self.tokens[self.i]
        self.i += 1
        return token


def _string(value: tuple) -> str:
    if value[0] != "str":
        raise ExtractRefusal("syntax")
    return str(value[1])


def _i64(attrs: dict[str, tuple], key: str, missing: str) -> int:
    if key not in attrs:
        raise ExtractRefusal(missing)
    value = attrs[key]
    if value[0] != "int" or value[2] != "i64":
        raise ExtractRefusal("not-i64")
    return int(value[1])


def _module_fields(
    attrs: dict[str, tuple],
    blocks: list[dict],
    hb_pairs: list[list[str]],
    saw_hb: bool,
) -> dict:
    for key in attrs:
        if key not in _MODULE_ATTRS:
            raise ExtractRefusal("closed-set")
    program = {
        "blocks": blocks,
        "capacity": _i64(attrs, "s2c2.carrier.capacity", "missing-capacity"),
        "working-set": _i64(attrs, "s2c2.carrier.working_set", "missing-working-set"),
    }
    if saw_hb:
        program["hb"] = sorted(hb_pairs)
    return program


def _module(body: str, *, capacity: str = "2 : i64", working_set: str = "3 : i64", extra: str = "") -> str:
    attrs = f"s2c2.carrier.capacity = {capacity}, s2c2.carrier.working_set = {working_set}{extra}"
    return f"module attributes {{ {attrs} }} {{ {body} }}"


def _fact(name: str, op: str, op_id: str, *, order: str = "name-op-id") -> str:
    fields = {
        "name-op-id": f'name = "{name}", op = "{op}", op_id = "{op_id}"',
        "id-op-name": f'op_id = "{op_id}", op = "{op}", name = "{name}"',
    }[order]
    return f"carrier.fact {{ {fields} }}"


def _stores(prefix: str = "id") -> str:
    return " ".join(
        _fact(name, "store", f"{prefix}{name}") for name in ("0", "1", "2")
    )


def _hb(pairs: list[tuple[str, str]]) -> str:
    return " ".join(
        f'carrier.hb {{ from = "{src}", to = "{dst}" }}' for src, dst in pairs
    )


def _acceptance_body(*, fact_order: str = "name-op-id", hb_pairs: list[tuple[str, str]] | None = None) -> str:
    if hb_pairs is None:
        hb_pairs = [("id0", "id1"), ("id1", "id2")]
    facts = " ".join(
        _fact(name, "store", f"id{name}", order=fact_order) for name in ("0", "1", "2")
    )
    return f"carrier.block {{ {facts} {_hb(hb_pairs)} }}"


def render(program: dict) -> str:
    """Spell the host fields this carrier is allowed to carry."""
    hb = program.get("hb") or []
    edges = " ".join(
        f'carrier.hb {{ from = "{src}", to = "{dst}" }}' for src, dst in hb
    )
    blocks: list[str] = []
    for index, block in enumerate(program.get("blocks") or []):
        facts = [
            _fact(str(op["name"]), str(op["op"]), str(op["op-id"]))
            for op in block.get("ops") or []
        ]
        parts = facts
        if index == 0 and edges:
            parts = facts + [edges]
        blocks.append("carrier.block { " + " ".join(parts) + " }")
    return _module(
        " ".join(blocks),
        capacity=f"{int(program['capacity'])} : i64",
        working_set=f"{int(program['working-set'])} : i64",
    )


def _spellable(program: dict) -> dict:
    body = {
        "blocks": program["blocks"],
        "capacity": program["capacity"],
        "working-set": program["working-set"],
    }
    if "hb" in program:
        body["hb"] = sorted([list(pair) for pair in program["hb"]])
    return body


def _replay_host_matrix() -> int:
    count = 0
    for name, envelopes, program, kwargs in apply._cases():
        extracted = extract(render(program))
        if "induced-hb" in extracted:
            raise RuntimeError(name)
        if extracted != _spellable(program):
            raise RuntimeError(name)
        handed = copy.deepcopy(extracted)
        if "induced-hb" in program:
            handed["induced-hb"] = copy.deepcopy(program["induced-hb"])
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
                raise RuntimeError(name)
        if apply.canonical_program(via["program"]) != apply.canonical_program(direct["program"]):
            raise RuntimeError(name)
        if via["can-run-plan"] != "no":
            raise RuntimeError(name)
        count += 1
    if count != 29:
        raise RuntimeError(count)
    return count


def _host(program: dict, envelope: dict, *, witness, device: str = "D0") -> dict:
    bag = apply.evaluate_apply(
        [envelope],
        copy.deepcopy(program),
        device=device,
        witness=witness,
    )
    return bag


def _extract_skips_host() -> None:
    """One extract does not enter authorization, apply, or the 7B helpers."""
    import record_authorization as auth

    counters = {
        "authorization": 0,
        "apply": 0,
        "envelope": 0,
        "witness": 0,
        "candidate": 0,
    }
    saved = {
        "authorization": auth.evaluate_authorization,
        "apply": apply.evaluate_apply,
        "envelope": scenario.rewrite_plan,
        "witness": apply.bound_witness,
        "candidate": apply.candidate_id_for,
    }

    def wrap(key: str, fn):
        def wrapped(*args, **kwargs):
            counters[key] += 1
            if kwargs.get("_probe"):
                return None
            return fn(*args, **kwargs)

        return wrapped

    auth.evaluate_authorization = wrap("authorization", saved["authorization"])
    apply.evaluate_apply = wrap("apply", saved["apply"])
    scenario.rewrite_plan = wrap("envelope", saved["envelope"])
    apply.bound_witness = wrap("witness", saved["witness"])
    apply.candidate_id_for = wrap("candidate", saved["candidate"])
    try:
        for key in counters:
            counters[key] = 0
        apply.evaluate_apply(_probe=True)
        if counters["apply"] != 1:
            raise RuntimeError("extract-probe")
        for key in counters:
            counters[key] = 0
        extracted = extract(_module(_acceptance_body()))
    finally:
        auth.evaluate_authorization = saved["authorization"]
        apply.evaluate_apply = saved["apply"]
        scenario.rewrite_plan = saved["envelope"]
        apply.bound_witness = saved["witness"]
        apply.candidate_id_for = saved["candidate"]
    if any(counters.values()):
        raise RuntimeError("extract-called-host")
    if "induced-hb" in extracted:
        raise RuntimeError("extract-induced")


def _validate() -> dict[str, str]:
    _extract_skips_host()
    calls = {"apply": 0}

    def host_once(program: dict, envelope: dict, *, witness, device: str = "D0") -> dict:
        calls["apply"] += 1
        return _host(program, envelope, witness=witness, device=device)

    accepted = extract(_module(_acceptance_body()))
    swapped = extract(
        _module(_acceptance_body(fact_order="id-op-name", hb_pairs=[("id1", "id2"), ("id0", "id1")]))
    )
    if accepted != swapped:
        raise RuntimeError("C02")
    if accepted["hb"] != [["id0", "id1"], ["id1", "id2"]]:
        raise RuntimeError("C01-hb")
    if apply.canonical_program(accepted) != scenario.CANONICAL_P:
        raise RuntimeError("C01-canonical")
    if "induced-hb" in accepted:
        raise RuntimeError("C01-induced")
    facts_fwd = extract(
        _module(
            "carrier.block { "
            + _fact("0", "store", "id0")
            + " "
            + _fact("1", "store", "id1")
            + " }"
        )
    )
    facts_rev = extract(
        _module(
            "carrier.block { "
            + _fact("1", "store", "id1")
            + " "
            + _fact("0", "store", "id0")
            + " }"
        )
    )
    if facts_fwd == facts_rev:
        raise RuntimeError("fact-order")
    if [op["op-id"] for op in facts_fwd["blocks"][0]["ops"]] != ["id0", "id1"]:
        raise RuntimeError("fact-order-kept")
    blocks_fwd = extract(
        _module(
            "carrier.block { "
            + _fact("0", "store", "id0")
            + " } carrier.block { "
            + _fact("1", "store", "id1")
            + " }"
        )
    )
    blocks_rev = extract(
        _module(
            "carrier.block { "
            + _fact("1", "store", "id1")
            + " } carrier.block { "
            + _fact("0", "store", "id0")
            + " }"
        )
    )
    if blocks_fwd == blocks_rev:
        raise RuntimeError("block-order")
    if [block["ops"][0]["op-id"] for block in blocks_fwd["blocks"]] != ["id0", "id1"]:
        raise RuntimeError("block-order-kept")
    if extract(_module(_acceptance_body()).replace("carrier.fact", "\n carrier.fact ")) != accepted:
        raise RuntimeError("whitespace")
    bare = extract(_module("carrier.block { " + _stores() + " }"))
    if "hb" in bare or "induced-hb" in bare:
        raise RuntimeError("absent-hb")
    duplicated = extract(
        _module(
            "carrier.block { "
            + _stores()
            + " "
            + _hb([("id0", "id1"), ("id1", "id2"), ("id0", "id1")])
            + " }"
        )
    )
    if duplicated.get("hb") != [["id0", "id1"], ["id0", "id1"], ["id1", "id2"]]:
        raise RuntimeError("duplicate-hb")
    if "induced-hb" in duplicated:
        raise RuntimeError("duplicate-hb-induced")

    envelope = scenario.rewrite_plan()
    source = scenario.source_program()
    from_carrier = host_once(accepted, envelope, witness=apply.bound_witness(accepted))
    from_source = host_once(source, envelope, witness=apply.bound_witness(source))
    if apply.candidate_id_for(accepted) != scenario.CANONICAL_P_PRIME:
        raise RuntimeError("C03-id")
    if apply.candidate_id_for(accepted) != apply.candidate_id_for(source):
        raise RuntimeError("C03-same-id")
    if apply.canonical_program(from_carrier["program"]) != scenario.CANONICAL_P_PRIME:
        raise RuntimeError("C03-prime")
    for key in ("match", "applied", "rewrite-path", "can-run-plan", "reasons"):
        if from_carrier[key] != from_source[key]:
            raise RuntimeError("C03-result")
    if from_carrier["match"] != "yes" or from_carrier["applied"] != "yes":
        raise RuntimeError("C03-success")
    if from_carrier["can-run-plan"] != "no":
        raise RuntimeError("C03-plan")

    before = calls["apply"]
    _expect_refusal(_module(_acceptance_body().replace(', op_id = "id2"', "")), "missing-op-id")
    _expect_refusal(
        "module attributes { s2c2.carrier.working_set = 3 : i64 } { "
        + _acceptance_body()
        + " }",
        "missing-capacity",
    )
    _expect_refusal(
        _module(_acceptance_body(), extra=', s2c2.carrier.device = "D0"'),
        "closed-set",
    )
    _expect_refusal(
        _module(""),
        "zero-block",
    )
    _expect_refusal("", "not-one-module")
    _expect_refusal(
        _module(_acceptance_body()) + " " + _module(""),
        "not-one-module",
    )
    _expect_refusal(_module(_fact("0", "store", "id0")), "fact-outside-block")
    _expect_refusal(
        _module('carrier.hb { from = "id0", to = "id1" }'),
        "hb-outside-block",
    )
    _expect_refusal(
        _module(_acceptance_body().replace('name = "0", ', "", 1)),
        "missing-name",
    )
    _expect_refusal(
        _module(_acceptance_body().replace('op = "store", ', "", 1)),
        "missing-op",
    )
    _expect_refusal(
        _module('carrier.block { carrier.hb { to = "id1" } }'),
        "missing-hb-from",
    )
    _expect_refusal(
        _module('carrier.block { carrier.hb { from = "id0" } }'),
        "missing-hb-to",
    )
    _expect_refusal(
        "module attributes { s2c2.carrier.capacity = 2 : i64 } { "
        + _acceptance_body()
        + " }",
        "missing-working-set",
    )
    _expect_refusal(
        _module(_acceptance_body(), capacity="2 : i32"),
        "not-i64",
    )
    _expect_refusal(
        _module(_acceptance_body(), working_set="3 : i32"),
        "not-i64",
    )
    _expect_refusal(
        _module(
            'carrier.block { carrier.fact { name = "0", op = "store", '
            'op_id = "id0" } { } }'
        ),
        "nested-region",
    )
    _expect_refusal(
        _module(_acceptance_body(), extra=', s2c2.carrier.router = "E"'),
        "closed-set",
    )
    _expect_refusal(
        _module(_acceptance_body(), extra=', s2c2.carrier.collective = "allreduce"'),
        "closed-set",
    )
    _expect_refusal(
        _module(_acceptance_body(), capacity="1 : i1"),
        "not-i64",
    )
    _expect_refusal(_module(_acceptance_body()) + " @", "syntax")
    _expect_refusal(
        _module(
            'carrier.block { carrier.fact { name = 0 : i64, op = "store", '
            'op_id = "id0" } }'
        ),
        "syntax",
    )
    _expect_refusal(
        _module('carrier.block { carrier.hb { from = 0 : i64, to = "id1" } }'),
        "syntax",
    )
    if calls["apply"] != before:
        raise RuntimeError("refusal-called-apply")

    cap4 = extract(_module(_acceptance_body(), capacity="4 : i64", working_set="5 : i64"))
    _expect_host(host_once(cap4, envelope, witness=None), match="no", reasons=[])
    # working-set 2 and a forbidden op are well-formed carrier text.
    # extract keeps them. The host, not extract, returns match=no.
    ws2 = extract(_module(_acceptance_body(), working_set="2 : i64"))
    if ws2["working-set"] != 2:
        raise RuntimeError("working-set-two")
    ws2_host = host_once(ws2, envelope, witness=None)
    _expect_host(ws2_host, match="no", reasons=[])
    if apply.canonical_program(ws2_host["program"]) != apply.canonical_program(ws2):
        raise RuntimeError("working-set-two-mutated")
    forbidden_text = _module(
        "carrier.block { "
        + _fact("0", "store", "id0")
        + " "
        + _fact("x", "prefetch", "px")
        + " "
        + _fact("1", "store", "id1")
        + " "
        + _fact("2", "store", "id2")
        + " }"
    )
    forbidden = extract(forbidden_text)
    kinds = [op["op"] for op in forbidden["blocks"][0]["ops"]]
    if kinds != ["store", "prefetch", "store", "store"]:
        raise RuntimeError("forbidden-op-kept")
    forbidden_host = host_once(forbidden, envelope, witness=None)
    _expect_host(forbidden_host, match="no", reasons=[])
    if apply.canonical_program(forbidden_host["program"]) != apply.canonical_program(forbidden):
        raise RuntimeError("forbidden-op-mutated")

    def kept_window(kind: str, name: str, op_id: str) -> None:
        extracted = extract(
            _module(
                "carrier.block { "
                + _fact("0", "store", "id0")
                + " "
                + _fact(name, kind, op_id)
                + " "
                + _fact("1", "store", "id1")
                + " "
                + _fact("2", "store", "id2")
                + " "
                + _hb([("id0", op_id), (op_id, "id1"), ("id1", "id2")])
                + " }"
            )
        )
        ops = extracted["blocks"][0]["ops"]
        if [op["op"] for op in ops] != ["store", kind, "store", "store"]:
            raise RuntimeError("window-op-" + kind)
        before = apply.canonical_program(extracted)
        bag = host_once(
            extracted,
            envelope,
            witness=apply.bound_witness(extracted, device=scenario.DEVICE),
        )
        if bag["match"] != "yes" or bag["applied"] != "yes":
            raise RuntimeError("window-op-host-" + kind)
        if bag["can-run-plan"] != "no" or bag["reasons"] != []:
            raise RuntimeError("window-op-boundary-" + kind)
        if apply.canonical_program(extracted) != before:
            raise RuntimeError("window-op-source-" + kind)
        out = [op["op"] for block in bag["program"]["blocks"] for op in block["ops"]]
        if out != ["store", kind, "store", "evict", "transfer", "restore"]:
            raise RuntimeError("window-op-result-" + kind)

    kept_window("compute", "c", "cx")
    kept_window("load", "l", "lx")
    two = extract(
        _module(
            "carrier.block { "
            + _fact("0", "store", "id0")
            + " "
            + _fact("1", "store", "id1")
            + " }"
        )
    )
    _expect_host(host_once(two, envelope, witness=None), match="no", reasons=[])
    twin = extract(
        _module(
            "carrier.block { "
            + _stores("a")
            + " } carrier.block { "
            + _stores("b")
            + " }"
        )
    )
    if len(twin["blocks"]) != 2:
        raise RuntimeError("C10-merge")
    _expect_host(host_once(twin, envelope, witness=None), match="no", reasons=[])

    reordered = apply._plan(sequence=["KEEP", "RESTORE", "EVICT", "TRANSFER"])
    _expect_host(
        host_once(accepted, reordered, witness=apply.bound_witness(accepted)),
        match="no",
        reasons=["rewrite.sequence-mismatch"],
    )
    _expect_host(
        host_once(accepted, envelope, witness=None),
        match="yes",
        reasons=[],
    )
    _expect_host(
        host_once(
            accepted,
            envelope,
            witness=apply.bound_witness(accepted, device="D2"),
            device="D0",
        ),
        match="yes",
        reasons=[],
    )

    partial = extract(_module("carrier.block { " + _stores() + " " + _hb([("id0", "id1")]) + " }"))
    if "induced-hb" in partial:
        raise RuntimeError("C14-extract")
    induced = copy.deepcopy(partial)
    induced["induced-hb"] = [["id0", "id2"]]
    _expect_host(
        host_once(induced, envelope, witness=apply.bound_witness(induced)),
        match="yes",
        reasons=[],
    )
    _expect_refusal(
        _module(_acceptance_body() + " carrier.induced { from = \"id0\", to = \"id2\" }"),
        "closed-set",
    )

    mismatched = apply._plan(obj=apply.OBJECT_3)
    _expect_host(
        host_once(accepted, mismatched, witness=apply.bound_witness(accepted)),
        match="no",
        reasons=["rewrite.identity-mismatch"],
    )
    collided_text = _module(
        "carrier.block { "
        + _stores()
        + " } carrier.block { "
        + _fact("old", "evict", "id2.evict")
        + " }"
    )
    collided = extract(collided_text)
    if collided != apply._collision_program("evict"):
        raise RuntimeError("C16-dict")
    _expect_host(
        host_once(collided, envelope, witness=apply.bound_witness(collided)),
        match="yes",
        reasons=[],
    )
    matrix = _replay_host_matrix()
    return {
        "C01": "canonical-p",
        "C03": from_carrier["match"] + "/" + from_carrier["applied"],
        "matrix": str(matrix),
    }


def _expect_refusal(text: str, code: str) -> None:
    try:
        extract(text)
    except ExtractRefusal as refusal:
        if refusal.code != code:
            raise RuntimeError((code, refusal.code)) from refusal
        return
    raise RuntimeError(code)


def _expect_host(bag: dict, *, match: str, reasons: list[str]) -> None:
    if bag["match"] != match or bag["applied"] != "no":
        raise RuntimeError(bag)
    if bag["reasons"] != reasons:
        raise RuntimeError(bag["reasons"])
    if bag["can-run-plan"] != "no" or bag["rewrite-path"] != "no":
        raise RuntimeError(bag)


def print_contract() -> int:
    summary = _validate()
    print("mlir-carrier gate=extract-v0")
    print("carrier syntax-only")
    host_names = (
        "evaluate_apply",
        "evaluate_authorization",
        "rewrite_plan",
        "bound_witness",
        "candidate_id_for",
    )
    if any(name in extract.__code__.co_names for name in host_names):
        print("carrier-ne-semantic-model no")
        return 1
    print("carrier-skips evaluate_apply")
    print("carrier-skips evaluate_authorization")
    print("carrier-ne-semantic-model yes")
    print("tablegen no")
    print("lowering no")
    print("evaluate-apply unchanged")
    print("compiler-e2e no")
    print("s2c2-opt no")
    print("can-run-plan no")
    print("semantic-cut no")
    print("next-cut no")
    print("extract-calls-authorization no")
    print("extract-calls-evaluate-apply no")
    print("extract-builds-envelope no")
    print("extract-binds-witness no")
    print("extract-computes-candidate-id no")
    print("C01 " + summary["C01"])
    print("C02 same-dict")
    print("C03 " + summary["C03"])
    print("C04 refusal missing-op-id apply-not-called")
    print("C05 refusal missing-capacity apply-not-called")
    print("C06 refusal closed-set apply-not-called")
    print("C07 refusal zero-block apply-not-called")
    print("C08 host match=no applied=no")
    print("C09 host match=no applied=no")
    print("C10 host match=no applied=no blocks-not-merged")
    print("working-set-two extract-ok host-match-no")
    print("forbidden-op extract-ok host-match-no")
    print("window-op compute kept host-applied")
    print("window-op load kept host-applied")
    print("C11 host reasons=rewrite.sequence-mismatch")
    print("C12 host match=yes applied=no")
    print("C13 host match=yes applied=no")
    print("C14 host match=yes applied=no induced-not-extracted")
    print("C15 host reasons=rewrite.identity-mismatch")
    print("C16 host match=yes applied=no")
    print("extract-refusal not-one-module apply-not-called")
    print("extract-refusal fact-outside-block apply-not-called")
    print("extract-refusal hb-outside-block apply-not-called")
    print("extract-refusal missing-name apply-not-called")
    print("extract-refusal missing-op apply-not-called")
    print("extract-refusal missing-hb-from apply-not-called")
    print("extract-refusal missing-hb-to apply-not-called")
    print("extract-refusal missing-working-set apply-not-called")
    print("extract-refusal not-i64 apply-not-called")
    print("extract-refusal nested-region apply-not-called")
    print("extract-refusal router-result closed-set apply-not-called")
    print("fact-order significant")
    print("block-order significant")
    print("whitespace same-dict")
    print("absent-hb key-omitted")
    print("duplicate-hb kept")
    print("extract-refusal non-string-attr syntax apply-not-called")
    print("extract-refusal collective-kind closed-set apply-not-called")
    print("extract-refusal i1 not-i64 apply-not-called")
    print("extract-refusal syntax apply-not-called")
    import record_storage_apply as apply

    count = int(summary["matrix"])
    through = summary["matrix"]
    if count != len(apply._cases()) or str(count) != through:
        print("host-matrix-cases no")
        return 1
    print("host-matrix-cases " + summary["matrix"])
    print("host-matrix-through-carrier " + summary["matrix"])
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="MLIR carrier v0 extract")
    parser.add_argument("--print-carrier-extract", action="store_true")
    args = parser.parse_args(argv)
    if not args.print_carrier_extract:
        print(
            "record_mlir_carrier: choose --print-carrier-extract",
            file=sys.stderr,
        )
        return 2
    return print_contract()


if __name__ == "__main__":
    sys.exit(main())
