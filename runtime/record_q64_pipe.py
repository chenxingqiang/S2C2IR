#!/usr/bin/env python3
"""Require the v3 pipe tile and depth constants to stay the query set.

Loads runtime/cuda/record_v3.py with importlib from Path(__file__).
PIPE_TILES must be 8, PIPE_TILES_SET must be (4, 8, 16, 32),
PIPE_DEPTHS must be (1, 2, 3, 4), and 8 must be in PIPE_TILES_SET.
Does not call run_analyzer. Does not add a predicate, device, dialect,
backend, or semantic cut. Query only. can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RECORD = Path(__file__).resolve().parent / "cuda" / "record_v3.py"
_TILES = 8
_TILE_SET = (4, 8, 16, 32)
_DEPTHS = (1, 2, 3, 4)
_FLAG = "--print-q64-pipe"


def _load(path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location("s2c2_cuda_q64_pipe", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("record-v3-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q64-pipe no")
    return 1


def print_q64_pipe() -> int:
    try:
        record = _load(_RECORD)
        tiles = record.PIPE_TILES
        tile_set = record.PIPE_TILES_SET
        depths = record.PIPE_DEPTHS
    except (Exception, SystemExit):
        return _no()
    if type(tiles) is not int or tiles != _TILES:
        return _no()
    if type(tile_set) is not tuple or tile_set != _TILE_SET:
        return _no()
    if type(depths) is not tuple or depths != _DEPTHS:
        return _no()
    if _TILES not in tile_set:
        return _no()
    print("q64-pipe gate=query")
    print(f"pipe-tiles {tiles}")
    for tile in tile_set:
        print(f"pipe-tile-set {tile}")
    for depth in depths:
        print(f"pipe-depth {depth}")
    print("q64-pipe yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q64_pipe: choose --print-q64-pipe",
            file=sys.stderr,
        )
        return 2
    return print_q64_pipe()


if __name__ == "__main__":
    sys.exit(main())
