#!/usr/bin/env python3
"""Require the sketch ops to stay out of the TableGen dialects.

Reads include/s2c2. Absent names are record_goal_alignment._ABSENT
when that module exports the tuple, otherwise the sketch list.
Query only. Does not add ops. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
_INCLUDE = _ROOT / "include" / "s2c2"
_GOAL = _ROOT / "runtime" / "record_goal_alignment.py"
_PREFIXES = ("Stor", "Comp", "Comm", "Sched")
_FALLBACK = (
    "dispatch",
    "prefetch",
    "attention",
    "attn_tile",
    "cim_mvm",
    "accum",
    "quant",
)


def absent_tuple() -> tuple[str, ...]:
    """Goal-alignment absent tuple, or the sketch list when it is not exported."""
    if not _GOAL.is_file():
        return _FALLBACK
    spec = importlib.util.spec_from_file_location(
        "s2c2_record_goal_alignment", _GOAL
    )
    if spec is None or spec.loader is None:
        return _FALLBACK
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except (AttributeError, ImportError, OSError, SyntaxError):
        return _FALLBACK
    exported = getattr(module, "_ABSENT", None)
    if (
        type(exported) is tuple
        and len(exported) > 0
        and all(type(name) is str and name != "" for name in exported)
    ):
        return exported
    return _FALLBACK


def read_tablegen() -> str:
    paths = sorted(_INCLUDE.rglob("*.td"))
    if not paths:
        raise OSError("missing-td")
    return "\n".join(path.read_text(encoding="utf-8") for path in paths)


def dialect_op_names(td: str) -> set[str]:
    """Mnemonics of Stor, Comp, Comm, and Sched ops defined in TableGen."""
    names: set[str] = set()
    for prefix in _PREFIXES:
        names.update(re.findall(rf'{prefix}_Op<"([^"]+)"', td))
    return names


def sketches_absent(ops: set[str], names: tuple[str, ...]) -> bool:
    if type(names) is not tuple or len(names) == 0:
        return False
    if type(ops) is not set or len(ops) == 0:
        return False
    return all(type(name) is str and name not in ops for name in names)


def print_td_absent_bind() -> int:
    try:
        ok = sketches_absent(dialect_op_names(read_tablegen()), absent_tuple())
    except (OSError, UnicodeError, re.error):
        ok = False
    if not ok:
        print("td-absent-bind no")
        return 1
    print("td-absent-bind gate=query")
    print("sketch-ops absent")
    print("td-absent-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != ["--print-td-absent-bind"]:
        print(
            "record_td_absent_bind: choose --print-td-absent-bind",
            file=sys.stderr,
        )
        return 2
    return print_td_absent_bind()


if __name__ == "__main__":
    sys.exit(main())
