#!/usr/bin/env python3
"""Check Goal Alignment v1 against the dialect definitions.

The industry report and this tree share a direction. This cut's
delivery is the op set in include/s2c2 plus the W0-3/2 host.
This driver does not change a dialect, the IR, or Apply.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
_DOC = _ROOT / "docs" / "design" / "goal-alignment-v1.md"
_INCLUDE = _ROOT / "include" / "s2c2"

_DIALECT = {
    "Stor": "stor",
    "Comp": "comp",
    "Comm": "comm",
    "Sched": "sched",
}

# Report sketches. They stay out of the dialect until a cut is opened.
_ABSENT = (
    "dispatch",
    "prefetch",
    "attention",
    "attn_tile",
    "cim_mvm",
    "accum",
    "quant",
    "hb",
)


class AlignmentRefusal(Exception):
    def __init__(self, code: str) -> None:
        self.code = code
        super().__init__(code)


def _td_text() -> str:
    parts = []
    for path in sorted(_INCLUDE.rglob("*.td")):
        parts.append(path.read_text(encoding="utf-8"))
    return "\n".join(parts)


def dialect_surface(td: str) -> dict:
    ops: dict[str, set[str]] = {name: set() for name in _DIALECT.values()}
    for prefix, dialect in _DIALECT.items():
        ops[dialect] = set(re.findall(rf'{prefix}_Op<"([^"]+)"', td))

    def cases(def_name: str) -> set[str]:
        match = re.search(
            rf'def {def_name} : I32EnumAttr<[^[]*\[(.*?)\]>',
            td,
            re.S,
        )
        if not match:
            raise AlignmentRefusal(f"missing-enum-{def_name}")
        return set(re.findall(r'I32EnumAttrCase<"[^"]+",\s*\d+,\s*"([^"]+)">', match.group(1)))

    surface = {
        "ops": ops,
        "spaces": cases("Stor_Space"),
        "units": cases("Comp_Unit"),
        "kinds": cases("Comm_Kind"),
        "engines": cases("Comm_Engine"),
        "token": "sched.token" in td or 'Sched_Type<"Token", "token">' in td,
    }
    if not surface["token"]:
        raise AlignmentRefusal("missing-token")
    return surface


def documented_surface(text: str) -> dict:
    match = re.search(
        r"### Ops that exist\n\n```text\n(.*?)```",
        text,
        re.S,
    )
    if not match:
        raise AlignmentRefusal("missing-ops-block")
    block = match.group(1)
    ops: dict[str, set[str]] = {}
    spaces: set[str] = set()
    units: set[str] = set()
    kinds: set[str] = set()
    engines: set[str] = set()
    token = False
    for raw in block.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("!sched.token"):
            token = True
            continue
        if line.startswith("spaces:"):
            spaces = _csv(line.split(":", 1)[1])
            continue
        if line.startswith("optional unit:"):
            units = _csv(line.split(":", 1)[1])
            continue
        if line.startswith("kind:"):
            kinds = _csv(line.split(":", 1)[1])
            continue
        if line.startswith("engine:"):
            engines = _csv(line.split(":", 1)[1])
            continue
        head, _, rest = line.partition(" ")
        rest = rest.strip()
        if head in ("stor", "comp", "comm", "sched") and rest:
            ops[head] = _csv(rest)
            continue
        raise AlignmentRefusal("ops-block-line")
    return {
        "ops": ops,
        "spaces": spaces,
        "units": units,
        "kinds": kinds,
        "engines": engines,
        "token": token,
    }


def _csv(text: str) -> set[str]:
    return {part.strip() for part in text.split(",") if part.strip()}


def check(td: str | None = None, doc: str | None = None) -> dict:
    td_text = _td_text() if td is None else td
    doc_text = _DOC.read_text(encoding="utf-8") if doc is None else doc
    live = dialect_surface(td_text)
    claimed = documented_surface(doc_text)
    if set(claimed["ops"]) != set(live["ops"]):
        raise AlignmentRefusal("dialect-set")
    for dialect, names in live["ops"].items():
        if claimed["ops"][dialect] != names:
            raise AlignmentRefusal(f"ops-{dialect}")
    for key in ("spaces", "units", "kinds", "engines"):
        if claimed[key] != live[key]:
            raise AlignmentRefusal(key)
    if not claimed["token"] or not live["token"]:
        raise AlignmentRefusal("token")
    op_names = {name for names in live["ops"].values() for name in names}
    for absent in _ABSENT:
        if absent in op_names:
            raise AlignmentRefusal(f"sketch-landed-{absent}")
    for sentence in (
        "can-run-plan stays no",
        "next_cut` stays `NOT OPENED",
        "The carrier text and s2c2-opt stay separate.",
        "The apply host is W0-3/2 only.",
    ):
        if sentence not in doc_text:
            raise AlignmentRefusal("delivery-sentence")
    return {
        "stor": len(live["ops"]["stor"]),
        "comp": len(live["ops"]["comp"]),
        "comm": len(live["ops"]["comm"]),
        "sched": len(live["ops"]["sched"]),
    }


def _self_check(td: str, doc: str) -> None:
    bad = doc.replace("gated_mlp", "gated_mlp, attention", 1)
    try:
        check(td, bad)
    except AlignmentRefusal as refusal:
        if refusal.code != "ops-comp":
            raise AlignmentRefusal("self-check") from refusal
    else:
        raise AlignmentRefusal("self-check")


def print_contract() -> int:
    td = _td_text()
    doc = _DOC.read_text(encoding="utf-8")
    _self_check(td, doc)
    counts = check(td, doc)
    print("goal-alignment PASS")
    print("source include/s2c2")
    print("page docs/design/goal-alignment-v1.md")
    print(f"stor-ops {counts['stor']}")
    print(f"comp-ops {counts['comp']}")
    print(f"comm-ops {counts['comm']}")
    print(f"sched-ops {counts['sched']}")
    print("sketch-ops absent")
    print("can-run-plan no")
    print("carrier-separate yes")
    print("host W0-3/2")
    print("next-cut NOT-OPENED")
    print("semantic-cut no")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Goal alignment check")
    parser.add_argument("--print-goal-alignment", action="store_true")
    args = parser.parse_args(argv)
    if not args.print_goal_alignment:
        print(
            "record_goal_alignment: choose --print-goal-alignment",
            file=sys.stderr,
        )
        return 2
    try:
        return print_contract()
    except AlignmentRefusal as refusal:
        print(f"goal-alignment FAIL {refusal.code}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
