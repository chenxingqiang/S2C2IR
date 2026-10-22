#!/usr/bin/env python3
"""Require LICENSE_KIND_V01 on the three storage hosts.

record_authorization, record_storage_rewrite, and record_storage_apply
must each expose LICENSE_KIND_V01 as the same string
storage-capacity-rewrite. Query only. No semantic cut.
can-run-plan stays no. Do not print rewrite-license=yes.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

_KIND = "storage-capacity-rewrite"


def _no() -> int:
    print("license-kind-bind no")
    return 1


def print_license_kind_bind() -> int:
    try:
        import record_authorization as auth
        import record_storage_rewrite as rew
        import record_storage_apply as apply
    except ImportError:
        return _no()
    try:
        auth_kind = auth.LICENSE_KIND_V01
        rew_kind = rew.LICENSE_KIND_V01
        apply_kind = apply.LICENSE_KIND_V01
    except AttributeError:
        return _no()
    if (
        type(auth_kind) is not str
        or type(rew_kind) is not str
        or type(apply_kind) is not str
    ):
        return _no()
    if (auth_kind, rew_kind, apply_kind) != (_KIND, _KIND, _KIND):
        return _no()
    # The printed kind is the live constant, not a second copy of _KIND.
    print("license-kind-bind gate=query")
    print("license-kind " + auth.LICENSE_KIND_V01)
    print("license-kind-bind yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-license-kind-bind"]:
        print(
            "record_license_kind_bind: choose --print-license-kind-bind",
            file=sys.stderr,
        )
        return 2
    return print_license_kind_bind()


if __name__ == "__main__":
    sys.exit(main())
