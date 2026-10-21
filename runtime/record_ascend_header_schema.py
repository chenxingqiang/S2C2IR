#!/usr/bin/env python3
"""Compare the Ascend adapter header with the Python schema.

Reads kSchemaFields and kPairs from runtime/ascend/AdapterContract.h.
Query only. No semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import argparse
import importlib.util
import re
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_HEADER = _RUNTIME / "ascend" / "AdapterContract.h"
_ASCEND_PY = _RUNTIME / "ascend" / "record_ascend.py"

_FIELD_COUNT = 21
_PAIR_COUNT = 3


class _HeaderParseError(ValueError):
    """AdapterContract.h did not yield the two ordered string lists."""


def _load_record_ascend():
    spec = importlib.util.spec_from_file_location("record_ascend", _ASCEND_PY)
    if spec is None or spec.loader is None:
        raise _HeaderParseError("record_ascend")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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


def _initializer_body(text: str, symbol: str) -> str:
    match = re.search(
        rf"\b{re.escape(symbol)}\s*\[\s*\]\s*=\s*\{{",
        text,
    )
    if match is None:
        raise _HeaderParseError(symbol)
    start = match.end()
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
        raise _HeaderParseError(symbol)
    return text[start : i - 1]


def _quoted_strings(body: str) -> list[str]:
    return re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', body)


def parse_k_schema_fields(text: str) -> list[str]:
    """Ordered string list of the kSchemaFields initializer."""
    fields = _quoted_strings(_initializer_body(text, "kSchemaFields"))
    if not fields:
        raise _HeaderParseError("kSchemaFields")
    return fields


def _pair_member_index(text: str) -> int:
    match = re.search(r"\bstruct\s+PairContract\s*\{([^}]*)\}", text, re.S)
    if match is None:
        raise _HeaderParseError("PairContract")
    members = re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*;", match.group(1))
    if "pair" not in members:
        raise _HeaderParseError("pair")
    return members.index("pair")


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


def parse_k_pairs(text: str) -> list[str]:
    """Ordered string list of the kPairs pair column."""
    index = _pair_member_index(text)
    rows = _top_level_rows(_initializer_body(text, "kPairs"))
    if not rows:
        raise _HeaderParseError("kPairs")
    pairs: list[str] = []
    for row in rows:
        strings = _quoted_strings(row)
        if index >= len(strings):
            raise _HeaderParseError("kPairs")
        pairs.append(strings[index])
    return pairs


def _no() -> int:
    print("ascend-header-schema no")
    return 1


def report(header_text: str, record_ascend) -> int:
    """Print the bound query, or the mismatch line."""
    try:
        text = _strip_comments(header_text)
        fields = parse_k_schema_fields(text)
        pairs = parse_k_pairs(text)
        py_fields = tuple(record_ascend.CAP_SCHEMA_FIELDS)
        py_pairs = tuple(record_ascend.PAIRS)
    except (OSError, _HeaderParseError, AttributeError, TypeError):
        return _no()
    if tuple(fields) != py_fields or tuple(pairs) != py_pairs:
        return _no()
    field_count = len(fields)
    pair_count = len(pairs)
    if field_count != _FIELD_COUNT or pair_count != _PAIR_COUNT:
        return _no()
    print("ascend-header-schema gate=query")
    print(f"ascend-header-fields {field_count}")
    print(f"ascend-header-pairs {pair_count}")
    print("ascend-header-schema-bound yes")
    print("can-run-plan no")
    return 0


def print_ascend_header_schema() -> int:
    try:
        header_text = _HEADER.read_text(encoding="utf-8")
        record_ascend = _load_record_ascend()
    except (OSError, _HeaderParseError, AttributeError, ImportError, SyntaxError):
        return _no()
    return report(header_text, record_ascend)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Compare the Ascend adapter header fields and pairs "
            "with the Python schema."
        )
    )
    parser.add_argument("--print-ascend-header-schema", action="store_true")
    args = parser.parse_args(argv)
    if not args.print_ascend_header_schema:
        print(
            "record_ascend_header_schema: choose --print-ascend-header-schema",
            file=sys.stderr,
        )
        return 2
    return print_ascend_header_schema()


if __name__ == "__main__":
    sys.exit(main())
