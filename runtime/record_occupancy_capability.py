#!/usr/bin/env python3
"""Independent occupancy usable + capability applicable report.

Two Decisions, two identities. Not a conjunction, not sufficient,
not a rewrite license. Do not expand S2C2CapabilitySchedule.cpp.
Query only. Do not FileCheck microseconds.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

import record_capability_applicability as capa
import record_decision as occ

REPORT_SCHEMA = "s2c2.occupancy_capability_report.v1"
OBJECT_2 = "2"


def occupancy_capability_report(
    *,
    occupancy_records: list[dict],
    selected: str,
    obj: str,
    capability_records: list[dict],
    target: str,
    device: str,
    kind: str,
) -> dict:
    """Package two independent Decisions. Never AND them."""
    usable = occ.derive_usable_decision(occupancy_records, selected, obj)
    applicable = capa.derive_applicable_decision(
        capability_records, target, device, kind
    )
    if usable["subject"] != "usable":
        raise RuntimeError("usable subject")
    if applicable["subject"] != "applicable":
        raise RuntimeError("applicable subject")
    if usable["subject"] == "sufficient" or applicable["subject"] == "sufficient":
        raise RuntimeError("sufficient subject")
    return {
        "schema": REPORT_SCHEMA,
        "usable-identity": {"selected": selected, "object": obj},
        "applicable-identity": {
            "target": target,
            "device": device,
            "kind": kind,
        },
        "usable": usable,
        "applicable": applicable,
        "sufficiency-evaluation": "n/a",
        "rewrite-license": "no",
        "rewrite-path": "no",
    }


def _occ_rec(
    *,
    kind: str,
    obj: str = OBJECT_2,
    selected: str | None = None,
    applicability: str = "yes",
) -> dict:
    display = {
        "source-data": "witnessed-unmutated-cover",
        "restore-ordering": "witnessed-before-consumer",
        "dest-invalidation": "witnessed-drop-stale",
    }[kind]
    witness = {
        "source-data": "spec-unmutated-cover",
        "restore-ordering": "spec-before-consumer",
        "dest-invalidation": "spec-drop-stale",
    }[kind]
    kwargs = {
        "kind": kind,
        "obj": obj,
        "applicability": applicability,
        "display": display,
        "witness": witness,
        "scope": "occupancy-live",
        "provenance": "spec",
    }
    if selected is not None:
        kwargs["selected"] = selected
    return occ.evidence_record(**kwargs)


def _occupancy_yes(
    *,
    dest_inv: bool,
    selected: str | None = None,
    obj: str = OBJECT_2,
) -> list[dict]:
    recs = [
        _occ_rec(kind="source-data", obj=obj, selected=selected),
        _occ_rec(kind="restore-ordering", obj=obj, selected=selected),
    ]
    if dest_inv:
        recs.append(_occ_rec(kind="dest-invalidation", obj=obj, selected=selected))
    return recs


def _occupancy_missing_ordering() -> list[dict]:
    return [_occ_rec(kind="source-data")]


def _occupancy_identity_mismatch() -> list[dict]:
    rec = _occ_rec(kind="source-data")
    rec = {
        **rec,
        "identity": {**rec["identity"], "kind": "restore-ordering"},
    }
    return [rec]


def _cap(
    *,
    applicability: str,
    occupancy_usable: str,
    device: str | None = None,
) -> dict:
    canonical = (
        "capability.present"
        if applicability == "yes"
        else "capability.not-applicable"
    )
    return capa.capability_record(
        target="cuda",
        device=device or capa.DEVICE_4090,
        kind="concurrent-pair",
        applicability=applicability,
        canonical=canonical,
        display="catalog-pair-present"
        if applicability == "yes"
        else "catalog-not-applicable",
        provenance="catalog",
        occupancy_usable=occupancy_usable,
    )


def _cap_invalid_schema() -> dict:
    rec = _cap(applicability="yes", occupancy_usable="yes")
    return {**rec, "schema": "s2c2.evidence_record.v1"}


def _query() -> tuple[str, str, str, str, str]:
    return (
        occ.SELECTED_S0,
        OBJECT_2,
        "cuda",
        capa.DEVICE_4090,
        "concurrent-pair",
    )


def _cases() -> list[tuple[str, list[dict], list[dict]]]:
    yes_cap = [_cap(applicability="yes", occupancy_usable="yes")]
    no_cap = [_cap(applicability="no", occupancy_usable="yes")]
    occ_yes = _occupancy_yes(dest_inv=False)
    occ_yes_inv = _occupancy_yes(dest_inv=True)
    occ_no = _occupancy_missing_ordering()
    src = _occ_rec(kind="source-data")
    return [
        ("both-yes-ne-sufficient", occ_yes_inv, yes_cap),
        ("usable-yes-applicable-no", occ_yes, no_cap),
        (
            "usable-no-applicable-yes",
            occ_no,
            [_cap(applicability="yes", occupancy_usable="n/a")],
        ),
        ("both-no", occ_no, no_cap),
        ("dest-inv-ne-sufficient", occ_yes_inv, yes_cap),
        (
            "occupancy-field-ne-usable-decision",
            occ_yes,
            [_cap(applicability="yes", occupancy_usable="no")],
        ),
        (
            "ignore-other-selected",
            _occupancy_yes(dest_inv=False, selected=occ.SELECTED_S1),
            yes_cap,
        ),
        (
            "ignore-other-object",
            _occupancy_yes(dest_inv=False, obj="3"),
            yes_cap,
        ),
        (
            "ignore-other-device",
            occ_yes,
            [_cap(applicability="yes", occupancy_usable="yes", device="sm80:a100")],
        ),
        (
            "duplicate-identity",
            [src, {**src}, _occ_rec(kind="restore-ordering")],
            yes_cap + yes_cap,
        ),
        (
            "identity-schema-mismatch",
            _occupancy_identity_mismatch(),
            [_cap_invalid_schema()],
        ),
    ]


def _fmt_reasons(decision: dict) -> str:
    return ",".join(decision["reasons"]) if decision["reasons"] else "none"


def _validate() -> None:
    selected, obj, target, device, kind = _query()
    yes_u = ("predicate.source-data-present", "predicate.restore-ordering-present")
    present = ("capability.present",)
    expect = {
        "both-yes-ne-sufficient": ("yes", yes_u, "yes", present),
        "usable-yes-applicable-no": (
            "yes",
            yes_u,
            "no",
            ("capability.not-applicable",),
        ),
        "usable-no-applicable-yes": (
            "no",
            ("predicate.missing-input",),
            "yes",
            present,
        ),
        "both-no": (
            "no",
            ("predicate.missing-input",),
            "no",
            ("capability.not-applicable",),
        ),
        "dest-inv-ne-sufficient": ("yes", yes_u, "yes", present),
        "occupancy-field-ne-usable-decision": ("yes", yes_u, "yes", present),
        "ignore-other-selected": (
            "no",
            ("predicate.missing-input",),
            "yes",
            present,
        ),
        "ignore-other-object": (
            "no",
            ("predicate.missing-input",),
            "yes",
            present,
        ),
        "ignore-other-device": (
            "yes",
            yes_u,
            "no",
            ("capability.missing-evidence",),
        ),
        "duplicate-identity": (
            "no",
            ("decision.duplicate-identity",),
            "no",
            ("decision.duplicate-identity",),
        ),
        "identity-schema-mismatch": (
            "no",
            ("decision.identity-mismatch",),
            "no",
            ("decision.unknown-reason",),
        ),
    }
    got = {}
    names = [name for name, _, _ in _cases()]
    if names != list(expect):
        raise RuntimeError(f"report case order drift: {names}")
    if len(names) != 11:
        raise RuntimeError(len(names))
    for name, occ_recs, cap_recs in _cases():
        report = occupancy_capability_report(
            occupancy_records=occ_recs,
            selected=selected,
            obj=obj,
            capability_records=cap_recs,
            target=target,
            device=device,
            kind=kind,
        )
        if report["schema"] != REPORT_SCHEMA:
            raise RuntimeError(name)
        if report["schema"] == "s2c2.decision.v1":
            raise RuntimeError(name)
        u, a = report["usable"], report["applicable"]
        if u["subject"] != "usable" or a["subject"] != "applicable":
            raise RuntimeError(name)
        if "sufficient" in (u["subject"], a["subject"], report["schema"]):
            raise RuntimeError(name)
        if report["sufficiency-evaluation"] != "n/a":
            raise RuntimeError(name)
        if report["rewrite-license"] != "no" or report["rewrite-path"] != "no":
            raise RuntimeError(name)
        for token in u["reasons"] + a["reasons"]:
            if token.startswith("authorization."):
                raise RuntimeError(name)
            if "sufficient" in token:
                raise RuntimeError(name)
        if name == "dest-inv-ne-sufficient":
            joined = ",".join(u["reasons"])
            if "dest-invalidation" in joined or "drop-stale" in joined:
                raise RuntimeError(name)
        if name == "occupancy-field-ne-usable-decision":
            if cap_recs[0]["occupancy_usable"] != "no":
                raise RuntimeError(name)
            if u["result"] != "yes":
                raise RuntimeError(name)
        if name == "ignore-other-selected":
            if occ_recs[0]["identity"]["selected"] == selected:
                raise RuntimeError(name)
        if name == "ignore-other-object":
            if occ_recs[0]["identity"]["object"] == obj:
                raise RuntimeError(name)
        if name == "ignore-other-device":
            if cap_recs[0]["device"] == device:
                raise RuntimeError(name)
            if a["reasons"] == list(u["reasons"]):
                raise RuntimeError(name)
        if name == "identity-schema-mismatch":
            ident = occ_recs[0]["identity"]
            if ident["kind"] == occ_recs[0]["kind"]:
                raise RuntimeError(name)
            if cap_recs[0]["schema"] == capa.SCHEMA:
                raise RuntimeError(name)
            if u["reasons"] == a["reasons"]:
                raise RuntimeError(name)
            if "decision.unknown-reason" in u["reasons"]:
                raise RuntimeError(name)
            if "decision.identity-mismatch" in a["reasons"]:
                raise RuntimeError(name)
        uid = report["usable-identity"]
        aid = report["applicable-identity"]
        if set(uid) & set(aid):
            raise RuntimeError(name)
        got[name] = (u["result"], tuple(u["reasons"]), a["result"], tuple(a["reasons"]))
    if got != expect:
        raise RuntimeError(f"occupancy-capability report drift: {got}")


def print_contract() -> int:
    _validate()
    print("occupancy-capability-report gate=query")
    print(f"schema {REPORT_SCHEMA}")
    print("report-ne-decision yes")
    print("usable-identity-ne-applicable-identity yes")
    print("conjunction-ne-sufficient yes")
    print("both-yes-ne-sufficient yes")
    print("decision-subject usable")
    print("decision-subject applicable")
    print("sufficiency-evaluation n/a")
    print("rewrite-license no")
    print("rewrite-path no")
    print("occupancy-usable-field-ne-usable-decision yes")
    print("dest-invalidation-ne-sufficient yes")
    print("both-no cartesian")
    print("ignore-other-selected yes")
    print("ignore-other-object yes")
    print("ignore-other-device yes")
    print("duplicate-identity safe-no")
    print("identity-schema-mismatch no-cross-talk")
    print("report-matrix-cases 11")
    print("applicable-ne-usable yes")
    print("applicable-ne-sufficient yes")
    print("usable-ne-sufficient yes")
    print("capability-schedule-ne-god-object yes")
    print("generic-schema-validator n/a")
    print("note six-c-m-sufficient-parked")
    print("note sufficient-decision-not-emitted")
    print("note authorization-namespace-closed")
    print("note last-writer-wins-forbidden")
    print("note rewrite=no")
    print("cost=unchanged")
    selected, obj, target, device, kind = _query()
    example = occupancy_capability_report(
        occupancy_records=_occupancy_yes(dest_inv=True),
        selected=selected,
        obj=obj,
        capability_records=[_cap(applicability="yes", occupancy_usable="yes")],
        target=target,
        device=device,
        kind=kind,
    )
    print("example " + json.dumps(example, separators=(",", ":"), sort_keys=True))
    return 0


def print_matrix() -> int:
    _validate()
    print("occupancy-capability-report-matrix gate=query")
    print("report-ne-decision yes")
    print("conjunction-ne-sufficient yes")
    print("both-yes-ne-sufficient yes")
    print("usable-identity-ne-applicable-identity yes")
    print("occupancy-usable-field-ne-usable-decision yes")
    print("report-matrix-cases 11")
    selected, obj, target, device, kind = _query()
    for name, occ_recs, cap_recs in _cases():
        report = occupancy_capability_report(
            occupancy_records=occ_recs,
            selected=selected,
            obj=obj,
            capability_records=cap_recs,
            target=target,
            device=device,
            kind=kind,
        )
        u, a = report["usable"], report["applicable"]
        print(f"ocr-case {name}")
        print(
            "ocr-usable-identity "
            f"selected={report['usable-identity']['selected']} "
            f"object={report['usable-identity']['object']}"
        )
        print(
            "ocr-applicable-identity "
            f"target={report['applicable-identity']['target']} "
            f"device={report['applicable-identity']['device']} "
            f"kind={report['applicable-identity']['kind']}"
        )
        for rec in occ_recs:
            ident = rec.get("identity") if isinstance(rec.get("identity"), dict) else {}
            print(
                "ocr-occ-record "
                f"selected={ident.get('selected')} "
                f"object={ident.get('object')} "
                f"kind={ident.get('kind')} "
                f"payload-kind={rec.get('kind')}"
            )
        for rec in cap_recs:
            ident = rec.get("identity") if isinstance(rec.get("identity"), dict) else {}
            print(
                "ocr-cap-record "
                f"schema={rec.get('schema')} "
                f"device={ident.get('device')} "
                f"applicability={rec.get('applicability')} "
                f"occupancy_usable={rec.get('occupancy_usable')} "
                f"provenance={rec.get('provenance')}"
            )
        print(
            "ocr-usable "
            f"subject={u['subject']} "
            f"result={u['result']} "
            f"reasons={_fmt_reasons(u)}"
        )
        print(
            "ocr-applicable "
            f"subject={a['subject']} "
            f"result={a['result']} "
            f"reasons={_fmt_reasons(a)}"
        )
        print(f"ocr-sufficiency-evaluation {report['sufficiency-evaluation']}")
        print(f"ocr-rewrite-license {report['rewrite-license']}")
        print(f"ocr-rewrite-path {report['rewrite-path']}")
    print("rewrite-license no")
    print("rewrite-path no")
    print("note sufficient-decision-not-emitted")
    print("note dest-invalidation-ne-sufficient")
    print("cost=unchanged")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="S2C2 occupancy/capability report")
    p.add_argument("--print-occupancy-capability-report-contract", action="store_true")
    p.add_argument("--print-occupancy-capability-report-matrix", action="store_true")
    args = p.parse_args(argv)
    flags = (
        args.print_occupancy_capability_report_contract,
        args.print_occupancy_capability_report_matrix,
    )
    if sum(bool(x) for x in flags) != 1:
        print(
            "record_occupancy_capability: choose one of "
            "--print-occupancy-capability-report-contract "
            "--print-occupancy-capability-report-matrix",
            file=sys.stderr,
        )
        return 2
    if args.print_occupancy_capability_report_contract:
        return print_contract()
    return print_matrix()


if __name__ == "__main__":
    sys.exit(main())
