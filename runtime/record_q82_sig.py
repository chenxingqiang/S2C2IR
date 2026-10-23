#!/usr/bin/env python3
"""Require Ascend measured-storage signatures S0 and S1 to stay distinct.

Loads runtime/ascend/record_ascend.py with importlib from Path(__file__).
_SIG_S0 must stay the PREFETCH signature and _SIG_S1 the PRESERVE
signature, and the two must differ. Does not call run_analyzer. Does not
add a predicate, device, dialect, backend, or semantic cut. Query only.
can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RECORD = Path(__file__).resolve().parent / "ascend" / "record_ascend.py"
_SIG_S0 = "MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER"
_SIG_S1 = "MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE|TRANSFER"
_FLAG = "--print-q82-sig"


def _load(path: Path) -> ModuleType:
    """Load runtime/ascend/record_ascend.py without running its CLI."""
    spec = importlib.util.spec_from_file_location("s2c2_ascend_q82_sig", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("record-ascend-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q82-sig no")
    return 1


def print_q82_sig() -> int:
    try:
        record = _load(_RECORD)
        sig_s0 = record._SIG_S0
        sig_s1 = record._SIG_S1
    except (Exception, SystemExit):
        return _no()
    if type(sig_s0) is not str or sig_s0 != _SIG_S0:
        return _no()
    if type(sig_s1) is not str or sig_s1 != _SIG_S1:
        return _no()
    if sig_s0 == sig_s1:
        return _no()
    print("q82-sig gate=query")
    print(f"sig-s0 {sig_s0}")
    print(f"sig-s1 {sig_s1}")
    print("q82-sig yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q82_sig: choose --print-q82-sig",
            file=sys.stderr,
        )
        return 2
    return print_q82_sig()


if __name__ == "__main__":
    sys.exit(main())
