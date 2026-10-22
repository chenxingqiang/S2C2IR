#!/usr/bin/env python3
"""Require Ascend kPairs rows to match the recorder pair column.

Parses kPairs from runtime/ascend/AdapterContract.h as text. The rows
must stay (R1, C||HtoD, compute, htod), (R2, C||C, compute, compute),
and (R3, HtoD||DtoH, htod, dtoh). Loads runtime/ascend/record_ascend.py
with importlib. PAIRS must stay ("C||HtoD", "C||C", "HtoD||DtoH") and
match that pair column. Query only. Does not call run_analyzer. Does
not add a predicate, device, dialect, backend, or semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path
from types import ModuleType

_RUNTIME = Path(__file__).resolve().parent
_HEADER = _RUNTIME / "ascend" / "AdapterContract.h"
_RECORD = _RUNTIME / "ascend" / "record_ascend.py"
_MEMBERS = ("id", "pair", "left", "right")
_ROWS = (
    ("R1", "C||HtoD", "compute", "htod"),
    ("R2", "C||C", "compute", "compute"),
    ("R3", "HtoD||DtoH", "htod", "dtoh"),
)
_PAIRS = ("C||HtoD", "C||C", "HtoD||DtoH")
_FLAG = "--print-q95-ahpair"
_PAIR_INIT = re.compile(r"\bkPairs\s*\[\s*\]\s*=\s*\{")


class _HeaderParseError(ValueError):
    """AdapterContract.h did not yield the three kPairs rows."""


def _string_end(text: str, open_quote: int) -> int:
    j = open_quote + 1
    n = len(text)
    while j < n:
        if text[j] == "\\":
            j += 2
            continue
        if text[j] == '"':
            return j + 1
        j += 1
    raise _HeaderParseError("string")


def _strip_comments(text: str) -> str:
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        if text.startswith("//", i):
            nl = text.find("\n", i)
            if nl < 0:
                break
            out.append("\n")
            i = nl + 1
            continue
        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end < 0:
                raise _HeaderParseError("comment")
            out.append(" ")
            i = end + 2
            continue
        if text[i] == '"':
            j = _string_end(text, i)
            out.append(text[i:j])
            i = j
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def _initializer_body(text: str) -> str:
    matches = list(_PAIR_INIT.finditer(text))
    if len(matches) != 1:
        raise _HeaderParseError("kPairs")
    start = matches[0].end()
    depth = 1
    i = start
    while i < len(text) and depth:
        if text[i] == '"':
            i = _string_end(text, i)
            continue
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
        i += 1
    if depth != 0:
        raise _HeaderParseError("kPairs")
    return text[start : i - 1]


def _quoted_strings(body: str) -> list[str]:
    return re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', body)


def _pair_members(text: str) -> tuple[str, ...]:
    match = re.search(r"\bstruct\s+PairContract\s*\{([^}]*)\}", text, re.S)
    if match is None:
        raise _HeaderParseError("PairContract")
    members = re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*;", match.group(1))
    return tuple(members)


def _top_level_rows(body: str) -> list[str]:
    rows: list[str] = []
    depth = 0
    start = -1
    i = 0
    while i < len(body):
        if body[i] == '"':
            i = _string_end(body, i)
            continue
        if body[i] == "{":
            if depth == 0:
                start = i + 1
            depth += 1
        elif body[i] == "}":
            depth -= 1
            if depth == 0 and start >= 0:
                rows.append(body[start:i])
                start = -1
            if depth < 0:
                raise _HeaderParseError("kPairs")
        i += 1
    if depth != 0:
        raise _HeaderParseError("kPairs")
    return rows


def parse_k_pairs(text: str) -> tuple[tuple[str, str, str, str], ...]:
    """Ordered (id, pair, left, right) rows from the kPairs initializer."""
    if _pair_members(text) != _MEMBERS:
        raise _HeaderParseError("PairContract")
    body = _initializer_body(text)
    raw_rows = _top_level_rows(body)
    if not raw_rows:
        raise _HeaderParseError("kPairs")
    rows: list[tuple[str, str, str, str]] = []
    for row in raw_rows:
        strings = tuple(_quoted_strings(row))
        if len(strings) != len(_MEMBERS):
            raise _HeaderParseError("kPairs")
        rows.append((strings[0], strings[1], strings[2], strings[3]))
    flat = tuple(part for row in rows for part in row)
    if tuple(_quoted_strings(body)) != flat:
        raise _HeaderParseError("kPairs")
    return tuple(rows)


def _load_record_ascend() -> ModuleType:
    """Load runtime/ascend/record_ascend.py without running its CLI."""
    spec = importlib.util.spec_from_file_location(
        "s2c2_ascend_q95_ahpair", _RECORD
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("record-ascend-load")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _no() -> int:
    print("q95-ahpair no")
    return 1


def print_q95_ahpair() -> int:
    try:
        text = _strip_comments(_HEADER.read_text(encoding="utf-8"))
        rows = parse_k_pairs(text)
        pairs = _load_record_ascend().PAIRS
    except (Exception, SystemExit):
        return _no()
    pair_column = tuple(row[1] for row in rows)
    if (
        rows != _ROWS
        or type(pairs) is not tuple
        or pairs != _PAIRS
        or pairs != pair_column
    ):
        return _no()
    print("q95-ahpair gate=query")
    for row in rows:
        print(f"ascend-pair {row[0]} {row[1]} {row[2]} {row[3]}")
    print("q95-ahpair yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if list(argv) != [_FLAG]:
        print(
            "record_q95_ahpair: choose --print-q95-ahpair",
            file=sys.stderr,
        )
        return 2
    return print_q95_ahpair()


if __name__ == "__main__":
    sys.exit(main())
