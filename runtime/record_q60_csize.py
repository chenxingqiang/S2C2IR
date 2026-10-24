#!/usr/bin/env python3
"""Require the CUDA capability byte sizes to stay the closed ladder.

Loads runtime/cuda/record_v3.py by file path from Path(__file__).
CAP_SIZE_BYTES must be (1024, 4096, 16384, 65536, 1048576, 4194304,
16777216, 67108864, 268435456). Query only. Does not edit the
recorder. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_CAP_SIZE_BYTES = (
    1024,
    4096,
    16384,
    65536,
    1048576,
    4194304,
    16777216,
    67108864,
    268435456,
)


def _load(path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "s2c2_q60_cuda_cap_size", path
    )
    if spec is None or spec.loader is None:
        raise ImportError("record_v3")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q60-csize no")
    return 1


def print_q60_csize() -> int:
    try:
        module = _load(_RECORD)
        sizes = module.CAP_SIZE_BYTES
    except (Exception, SystemExit):
        return _no()
    if type(sizes) is not tuple or sizes != _CAP_SIZE_BYTES:
        return _no()
    if any(type(nbytes) is not int for nbytes in sizes):
        return _no()
    print("q60-csize gate=query")
    for nbytes in sizes:
        print(f"cap-size {nbytes}")
    print("q60-csize yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-q60-csize"]:
        print(
            "record_q60_csize: choose --print-q60-csize",
            file=sys.stderr,
        )
        return 2
    return print_q60_csize()


if __name__ == "__main__":
    sys.exit(main())
