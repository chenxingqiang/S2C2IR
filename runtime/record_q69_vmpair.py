#!/usr/bin/env python3
"""Require the CUDA validation memory pairs to stay the two VAL_MEM_PAIRS.

Loads runtime/cuda/record_v3.py by file path from Path(__file__).
VAL_MEM_PAIRS must equal the HtoD and DtoH rows, including their copy
and overlap arms. Prints only the pair names. Does not call
run_analyzer. Does not edit runtime/cuda/record_v3.py. Does not add a
predicate, device, dialect, backend, or semantic cut. Query only.
can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RUNTIME = Path(__file__).resolve().parent
_CUDA = _RUNTIME / "cuda" / "record_v3.py"
_VAL_MEM_PAIRS = (
    (
        "C||HtoD",
        "val-htod-pinned",
        "val-htod-pageable",
        "val-ovl-htod-pin",
        "val-ovl-htod-page",
    ),
    (
        "C||DtoH",
        "val-dtoh-pinned",
        "val-dtoh-pageable",
        "val-ovl-dtoh-pin",
        "val-ovl-dtoh-page",
    ),
)
_FLAG = "--print-q69-vmpair"


def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q69-vmpair no")
    return 1


def print_q69_vmpair() -> int:
    try:
        cuda = _load(_CUDA, "s2c2_cuda_q69_vmpair")
        pairs = cuda.VAL_MEM_PAIRS
    except (Exception, SystemExit):
        return _no()
    if type(pairs) is not tuple or pairs != _VAL_MEM_PAIRS:
        return _no()
    print("q69-vmpair gate=query")
    for row in pairs:
        print(f"mem-pair {row[0]}")
    print("q69-vmpair yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q69_vmpair: choose --print-q69-vmpair",
            file=sys.stderr,
        )
        return 2
    return print_q69_vmpair()


if __name__ == "__main__":
    sys.exit(main())
