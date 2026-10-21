#!/usr/bin/env python3
"""Bind AdapterContract.h kPilots to runtime/cuda/record_v3.CASES.

Query only. The header triples stay (id, func, score3Total). This
does not change the adapter, Cost, or a semantic cut. can-run-plan
stays no.
"""

from __future__ import annotations

import argparse
import importlib.util
import re
import sys
from pathlib import Path
from typing import NamedTuple

_ROOT = Path(__file__).resolve().parents[1]
_HEADER = _ROOT / "runtime" / "cuda" / "AdapterContract.h"
_RECORD = _ROOT / "runtime" / "cuda" / "record_v3.py"
_SCORES = (130, 128, 163)
_PILOTS = re.compile(r"kPilots\[\]\s*=\s*\{(.*?)\};", re.S)
_TRIPLE = re.compile(
    r'\{\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*(-?\d+)\s*\}'
)


class Pilot(NamedTuple):
    id: str
    func: str
    score3Total: int


def parse_kpilots(text: str) -> list[Pilot] | None:
    """Ordered (id, func, score3Total) triples from the kPilots initializer."""
    match = _PILOTS.search(text)
    if match is None:
        return None
    pilots: list[Pilot] = []
    for item in _TRIPLE.finditer(match.group(1)):
        pilots.append(Pilot(item.group(1), item.group(2), int(item.group(3))))
    return pilots


def load_cases() -> tuple:
    spec = importlib.util.spec_from_file_location(
        "s2c2_cuda_record_v3_cases", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    cases = getattr(mod, "CASES", None)
    if not isinstance(cases, tuple):
        raise RuntimeError("record-v3-cases")
    return cases


def header_bound(pilots: list[Pilot] | None, cases: tuple) -> bool:
    """True when the header triples match CASES, including 130, 128, 163."""
    if pilots is None or len(pilots) != 3 or len(cases) != 3:
        return False
    expected: list[Pilot] = []
    for case in cases:
        if type(case) is not tuple or len(case) != 3:
            return False
        cid, func, score = case
        if type(cid) is not str or type(func) is not str or type(score) is not int:
            return False
        expected.append(Pilot(cid, func, score))
    if pilots != expected:
        return False
    scores = tuple(pilot.score3Total for pilot in pilots)
    case_scores = tuple(pilot.score3Total for pilot in expected)
    return scores == _SCORES and case_scores == _SCORES


def print_cuda_pilot_header() -> int:
    try:
        text = _HEADER.read_text(encoding="utf-8")
        pilots = parse_kpilots(text)
        cases = load_cases()
    except (OSError, RuntimeError, ValueError):
        print("cuda-pilot-header no")
        return 1
    if not header_bound(pilots, cases) or pilots is None:
        print("cuda-pilot-header no")
        return 1
    count = len(pilots)
    if count != 3:
        print("cuda-pilot-header no")
        return 1
    sys.stdout.write(
        "cuda-pilot-header gate=query\n"
        f"cuda-pilot-count {count}\n"
        "cuda-pilot-header-bound yes\n"
        "can-run-plan no\n"
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="CUDA pilot header bind",
        add_help=False,
    )
    parser.add_argument("--print-cuda-pilot-header", action="store_true")
    try:
        args, extra = parser.parse_known_args(argv)
    except SystemExit as exc:
        code = exc.code
        return code if isinstance(code, int) else 2
    if extra or not args.print_cuda_pilot_header:
        print(
            "record_cuda_pilot_bind: choose --print-cuda-pilot-header",
            file=sys.stderr,
        )
        return 2
    return print_cuda_pilot_header()


if __name__ == "__main__":
    sys.exit(main())
