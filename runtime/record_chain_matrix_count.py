#!/usr/bin/env python3
"""Read the e2e and xid matrix counts from their case lists.

Imports the frozen checking E2E and cross-identity hosts and prints
the length of each case list. Does not add cases. No semantic cut.
can-run-plan stays no. Query only. Do not FileCheck microseconds.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_realization_checking_e2e as e2e
import record_realization_checking_xid as xid


def print_chain_matrix_counts() -> int:
    e2e_count = len(e2e._cases())
    xid_count = len(xid._cases())
    if e2e_count != 3 or xid_count != 4:
        print("chain-matrix-counts no")
        return 1
    print("chain-matrix-counts gate=query")
    print(f"e2e-matrix-cases {e2e_count}")
    print(f"xid-matrix-cases {xid_count}")
    print("chain-matrix-counts-bound yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="S2C2 chain matrix counts",
        add_help=False,
    )
    parser.add_argument("--print-chain-matrix-counts", action="store_true")
    args, extra = parser.parse_known_args(argv)
    if extra or not args.print_chain_matrix_counts:
        print(
            "record_chain_matrix_count: choose --print-chain-matrix-counts",
            file=sys.stderr,
        )
        return 2
    return print_chain_matrix_counts()


if __name__ == "__main__":
    sys.exit(main())
