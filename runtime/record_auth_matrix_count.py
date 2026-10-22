#!/usr/bin/env python3
"""Read authorization, sufficiency, and rewrite matrix counts.

The counts are len() of the host case lists. This printer does
not add cases or open a semantic cut. can-run-plan stays no.
"""

from __future__ import annotations

import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_authorization as auth
import record_sufficiency as suf
import record_storage_rewrite as rew


def print_auth_matrix_counts() -> int:
    authorization_cases = len(auth._cases())
    sufficiency_cases = len(suf._cases())
    rewrite_cases = len(rew._cases())
    if authorization_cases != 20 or sufficiency_cases != 16 or rewrite_cases != 18:
        print("auth-matrix-counts no")
        return 1
    print("auth-matrix-counts gate=query")
    print(f"authorization-matrix-cases {authorization_cases}")
    print(f"sufficiency-matrix-cases {sufficiency_cases}")
    print(f"rewrite-matrix-cases {rewrite_cases}")
    print("auth-matrix-counts-bound yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if argv != ["--print-auth-matrix-counts"]:
        print(
            "record_auth_matrix_count: choose --print-auth-matrix-counts",
            file=sys.stderr,
        )
        return 2
    return print_auth_matrix_counts()


if __name__ == "__main__":
    sys.exit(main())
