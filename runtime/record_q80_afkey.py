#!/usr/bin/env python3
"""Require Ascend FORBIDDEN_KEYS to stay the six host tokens.

Loads runtime/ascend/record_ascend.py with importlib from Path(__file__).
The tuple must stay the four vendor prefixes followed by the two host
tokens, and its length must stay 6. Prints the four vendor prefixes,
the count, and has-localhost yes. Query only. Does not call
run_analyzer. Does not add a predicate, device, dialect, backend, or
semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RECORD = Path(__file__).resolve().parent / "ascend" / "record_ascend.py"
_FORBIDDEN = (
    "acl_",
    "davinci_",
    "cube_",
    "vectorcore_",
    "password",
    "localhost",
)
_PREFIXES = ("acl_", "davinci_", "cube_", "vectorcore_")
_FLAG = "--print-q80-afkey"


def load_record_ascend() -> ModuleType:
    """Load runtime/ascend/record_ascend.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_ascend_record_q80_afkey", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-ascend-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q80-afkey no")
    return 1


def print_q80_afkey() -> int:
    try:
        keys = load_record_ascend().FORBIDDEN_KEYS
        prefixes = tuple(
            key for key in keys if isinstance(key, str) and key.endswith("_")
        )
    except (Exception, SystemExit):
        return _no()
    if (
        type(keys) is not tuple
        or len(keys) != 6
        or keys != _FORBIDDEN
        or prefixes != _PREFIXES
        or "localhost" not in keys
    ):
        return _no()
    print("q80-afkey gate=query")
    for prefix in prefixes:
        print(f"forbidden-prefix {prefix}")
    print(f"forbidden-key-count {len(keys)}")
    print("has-localhost yes")
    print("q80-afkey yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q80_afkey: choose --print-q80-afkey",
            file=sys.stderr,
        )
        return 2
    return print_q80_afkey()


if __name__ == "__main__":
    sys.exit(main())
