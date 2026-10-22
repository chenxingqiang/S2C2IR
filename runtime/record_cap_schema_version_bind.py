#!/usr/bin/env python3
"""Bind the CUDA and Ascend capability schema version and fields.

Query only. Both recorders load by file path. CAP_SCHEMA_VERSION
must be "1" on each side, and the CAP_SCHEMA_FIELDS tuples must be
equal and length 21. No semantic cut. v3 stays not-claimed.
can-run-plan stays no.
"""

from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_RUNTIME = Path(__file__).resolve().parent
_CUDA = _RUNTIME / "cuda" / "record_v3.py"
_ASCEND = _RUNTIME / "ascend" / "record_ascend.py"
_VERSION = "1"
_FIELD_COUNT = 21


def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _bound(cuda: ModuleType, ascend: ModuleType) -> tuple[str, int] | None:
    """Version and field count when both schemas match the bind."""
    version = cuda.CAP_SCHEMA_VERSION
    ascend_version = ascend.CAP_SCHEMA_VERSION
    fields = cuda.CAP_SCHEMA_FIELDS
    ascend_fields = ascend.CAP_SCHEMA_FIELDS
    if type(version) is not str or type(ascend_version) is not str:
        return None
    if version != _VERSION or ascend_version != _VERSION:
        return None
    if type(fields) is not tuple or type(ascend_fields) is not tuple:
        return None
    if fields != ascend_fields:
        return None
    count = len(fields)
    if count != _FIELD_COUNT or len(ascend_fields) != _FIELD_COUNT:
        return None
    return version, count


def _no() -> int:
    print("cap-schema-version-bind no")
    return 1


def print_cap_schema_version_bind() -> int:
    try:
        cuda = _load(_CUDA, "s2c2_cuda_cap_schema_version")
        ascend = _load(_ASCEND, "s2c2_ascend_cap_schema_version")
        bound = _bound(cuda, ascend)
    except (Exception, SystemExit):
        return _no()
    if bound is None:
        return _no()
    version, count = bound
    sys.stdout.write(
        "cap-schema-version-bind gate=query\n"
        f"cap-schema-version {version}\n"
        f"cap-schema-fields {count}\n"
        "cap-schema-version-bind yes\n"
        "can-run-plan no\n"
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="CUDA and Ascend capability schema version bind",
        add_help=False,
        allow_abbrev=False,
    )
    parser.add_argument("--print-cap-schema-version-bind", action="store_true")
    try:
        args, extra = parser.parse_known_args(argv)
    except SystemExit:
        return 2
    if extra or not args.print_cap_schema_version_bind:
        print(
            "record_cap_schema_version_bind: choose --print-cap-schema-version-bind",
            file=sys.stderr,
        )
        return 2
    return print_cap_schema_version_bind()


if __name__ == "__main__":
    sys.exit(main())
