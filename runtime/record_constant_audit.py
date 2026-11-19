#!/usr/bin/env python3
"""Table-driven constant audit for the S2C2IR host stack.

One row per fact previously pinned by the per-constant reader
scripts (record_*_bind.py / record_q*.py), which this module
replaces. Query only. No semantic cut. can-run-plan stays no.
The printer never echoes audited values, only per-key yes/no,
so pinned literals stay out of the lit output.

Row kinds:
  const       (module, attr, expected)          == after list->tuple
  pairs       (module, attr, expected_items)   dict pins insertion order
  len         (module, attr, n)                attr or attr() then len
  ne          (lookup, lookup)                  two lookups differ
  cases_first (module, expected_names)         first column of _cases()
  cases_col   (module, index, expected_col)    one column of _cases()
  ledger      (row_count, hardware_tuple)       load_ledger content
  hdr_str     (relpath, name, expected)        constexpr string in a header
  hdr_int     (relpath, name, expected)         constexpr int in a header
  hdr_float   (relpath, name, expected)         constexpr double in a header
  hdr_list    (relpath, array, expected_tuple) ordered string list
  hdr_rows    (relpath, array, expected_rows)  rows of strings and ints
  tg_ops      (relpath, prefix, expected)      TableGen op mnemonics, in order
  tg_absent   (expected_count,)                goal absent names stay out of ops
  tg_agree    (expected_counts,)               TableGen counts match goal check
"""

from __future__ import annotations

import argparse
import importlib
import importlib.util
import re
import sys
from pathlib import Path

_RUNTIME = Path(__file__).resolve().parent
_ROOT = _RUNTIME.parent
if str(_RUNTIME) not in sys.path:
    sys.path.insert(0, str(_RUNTIME))

_BY_PATH = {
    "record_v3": _RUNTIME / "cuda" / "record_v3.py",
    "record_ascend": _RUNTIME / "ascend" / "record_ascend.py",
}
_MODULES: dict[str, object] = {}

_TG_PREFIXES = ("Stor", "Comp", "Comm", "Sched")


def _module(name: str):
    if name not in _MODULES:
        path = _BY_PATH.get(name)
        if path is None:
            _MODULES[name] = importlib.import_module(name)
        else:
            spec = importlib.util.spec_from_file_location(name, path)
            if spec is None or spec.loader is None:
                raise RuntimeError(name)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            _MODULES[name] = mod
    return _MODULES[name]


def _value(module: str, attr: str):
    value = getattr(_module(module), attr)
    if callable(value):
        value = value()
    return value


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
    raise ValueError("string")


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
                raise ValueError("comment")
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


def _initializer_body(text: str, symbol: str) -> str:
    match = re.search(rf"\b{re.escape(symbol)}\s*\[\s*\]\s*=\s*\{{", text)
    if match is None:
        raise ValueError(symbol)
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
        raise ValueError(symbol)
    return text[start : i - 1]


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
                raise ValueError("rows")
        i += 1
    if depth != 0:
        raise ValueError("rows")
    return rows


_ROW_TOKEN = re.compile(r'"([^"\\]*(?:\\.[^"\\]*)*)"|(-?\d+)')


def _row_tokens(row: str) -> tuple:
    tokens: list[object] = []
    for match in _ROW_TOKEN.finditer(row):
        if match.group(2) is None:
            tokens.append(match.group(1))
        else:
            tokens.append(int(match.group(2)))
    return tuple(tokens)


def _header(relpath: str) -> str:
    return _strip_comments((_ROOT / relpath).read_text(encoding="utf-8"))


def _hdr_str(relpath: str, name: str, expected: str) -> bool:
    found = re.findall(rf'\b{re.escape(name)}\s*=\s*"([^"]*)"', _header(relpath))
    return len(found) == 1 and found[0] == expected


def _hdr_int(relpath: str, name: str, expected: int) -> bool:
    found = re.findall(rf"\b{re.escape(name)}\s*=\s*([+-]?\d+)", _header(relpath))
    return len(found) == 1 and int(found[0]) == expected


def _hdr_float(relpath: str, name: str, expected: float) -> bool:
    found = re.findall(
        rf"\b{re.escape(name)}\s*=\s*([+-]?\d+(?:\.\d+)?)", _header(relpath)
    )
    return len(found) == 1 and float(found[0]) == expected


def _hdr_list(relpath: str, array: str, expected: tuple) -> bool:
    body = _initializer_body(_header(relpath), array)
    found = re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', body)
    return tuple(found) == tuple(expected)


def _hdr_rows(relpath: str, array: str, expected: tuple) -> bool:
    body = _initializer_body(_header(relpath), array)
    rows = _top_level_rows(body)
    return tuple(_row_tokens(row) for row in rows) == tuple(expected)


def _tg_mnemonics(prefix: str) -> set[str]:
    names: set[str] = set()
    for path in sorted((_ROOT / "include" / "s2c2").rglob("*.td")):
        names.update(
            re.findall(rf'{prefix}_Op<"([^"]+)"', path.read_text(encoding="utf-8"))
        )
    return names


def _eval(row: tuple) -> bool:
    kind = row[1]
    if kind == "const":
        _, _, module, attr, expected = row
        value = _value(module, attr)
        if isinstance(value, list):
            value = tuple(value)
        return value == expected
    if kind == "pairs":
        _, _, module, attr, expected = row
        value = _value(module, attr)
        return isinstance(value, dict) and tuple(value.items()) == tuple(expected)
    if kind == "len":
        _, _, module, attr, expected = row
        return len(_value(module, attr)) == expected
    if kind == "ne":
        _, _, first, second = row
        left = _value(*first)
        right = _value(*second)
        return left != right
    if kind == "cases_first":
        _, _, module, expected = row
        cases = _value(module, "_cases")
        return tuple(case[0] for case in cases) == tuple(expected)
    if kind == "cases_col":
        _, _, module, index, expected = row
        cases = _value(module, "_cases")
        return tuple(case[index] for case in cases) == tuple(expected)
    if kind == "ledger":
        _, _, expected_rows, expected_hardware = row
        ledger = _module("record_hw_ledger")
        rows = ledger.load_ledger(ledger._LEDGER_PATH)
        hardware = {row["hardware"] for row in rows}
        return len(rows) == expected_rows and hardware == set(expected_hardware)
    if kind == "hdr_str":
        _, _, relpath, name, expected = row
        return _hdr_str(relpath, name, expected)
    if kind == "hdr_int":
        _, _, relpath, name, expected = row
        return _hdr_int(relpath, name, expected)
    if kind == "hdr_float":
        _, _, relpath, name, expected = row
        return _hdr_float(relpath, name, expected)
    if kind == "hdr_list":
        _, _, relpath, array, expected = row
        return _hdr_list(relpath, array, expected)
    if kind == "hdr_rows":
        _, _, relpath, array, expected = row
        return _hdr_rows(relpath, array, expected)
    if kind == "tg_ops":
        _, _, relpath, prefix, expected = row
        found = re.findall(
            rf'{prefix}_Op<"([^"]+)"',
            (_ROOT / relpath).read_text(encoding="utf-8"),
        )
        return tuple(found) == tuple(expected)
    if kind == "tg_absent":
        _, _, expected_count = row
        absent = _value("record_goal_alignment", "_ABSENT")
        ops: set[str] = set()
        for prefix in _TG_PREFIXES:
            ops |= _tg_mnemonics(prefix)
        return len(absent) == expected_count and all(
            name not in ops for name in absent
        )
    if kind == "tg_agree":
        _, _, expected_counts = row
        checked = _value("record_goal_alignment", "check")
        if not isinstance(checked, dict):
            return False
        for dialect, count in expected_counts:
            found = len(_tg_mnemonics(dialect.capitalize()))
            if found != count or checked.get(dialect) != count:
                return False
        return True
    return False


AUDITS = (
    ("action-v01-auth", "const", "record_authorization", "ACTION_V01",
     'storage-rewrite'),
    ("action-v01-rew", "const", "record_storage_rewrite", "ACTION_V01",
     'storage-rewrite'),
    ("action-v01-apply", "const", "record_storage_apply", "ACTION_V01",
     'storage-rewrite'),
    ("license-kind-auth", "const", "record_authorization", "LICENSE_KIND_V01",
     'storage-capacity-rewrite'),
    ("license-kind-rew", "const", "record_storage_rewrite", "LICENSE_KIND_V01",
     'storage-capacity-rewrite'),
    ("license-kind-apply", "const", "record_storage_apply", "LICENSE_KIND_V01",
     'storage-capacity-rewrite'),
    ("object-2-suf", "const", "record_sufficiency", "OBJECT_2",
     '2'),
    ("object-2-auth", "const", "record_authorization", "OBJECT_2",
     '2'),
    ("object-2-rew", "const", "record_storage_rewrite", "OBJECT_2",
     '2'),
    ("object-2-apply", "const", "record_storage_apply", "OBJECT_2",
     '2'),
    ("object-2-occ", "const", "record_occupancy_capability", "OBJECT_2",
     '2'),
    ("object-3-auth", "const", "record_authorization", "OBJECT_3",
     '3'),
    ("object-3-rew", "const", "record_storage_rewrite", "OBJECT_3",
     '3'),
    ("object-3-apply", "const", "record_storage_apply", "OBJECT_3",
     '3'),
    ("selected-s0-suf", "const", "record_sufficiency", "SELECTED_S0",
     'keep{0,1}|evict{2}|rematerialize{}'),
    ("selected-s0-auth", "const", "record_authorization", "SELECTED_S0",
     'keep{0,1}|evict{2}|rematerialize{}'),
    ("selected-s0-rew", "const", "record_storage_rewrite", "SELECTED_S0",
     'keep{0,1}|evict{2}|rematerialize{}'),
    ("selected-s0-apply", "const", "record_storage_apply", "SELECTED_S0",
     'keep{0,1}|evict{2}|rematerialize{}'),
    ("selected-s0-dec", "const", "record_decision", "SELECTED_S0",
     'keep{0,1}|evict{2}|rematerialize{}'),
    ("selected-s1-suf", "const", "record_sufficiency", "SELECTED_S1",
     'keep{1,2}|evict{0}|rematerialize{}'),
    ("selected-s1-auth", "const", "record_authorization", "SELECTED_S1",
     'keep{1,2}|evict{0}|rematerialize{}'),
    ("selected-s1-rew", "const", "record_storage_rewrite", "SELECTED_S1",
     'keep{1,2}|evict{0}|rematerialize{}'),
    ("selected-s1-apply", "const", "record_storage_apply", "SELECTED_S1",
     'keep{1,2}|evict{0}|rematerialize{}'),
    ("selected-s1-dec", "const", "record_decision", "SELECTED_S1",
     'keep{1,2}|evict{0}|rematerialize{}'),
    ("sequence-v01-rew", "const", "record_storage_rewrite", "SEQUENCE_V01",
     ('KEEP', 'EVICT', 'TRANSFER', 'RESTORE')),
    ("sequence-v01-apply", "const", "record_storage_apply", "SEQUENCE_V01",
     ('KEEP', 'EVICT', 'TRANSFER', 'RESTORE')),
    ("transformation-v01-rew", "const", "record_storage_rewrite", "TRANSFORMATION_V01",
     'keep-evict-transfer-restore'),
    ("transformation-v01-apply", "const", "record_storage_apply", "TRANSFORMATION_V01",
     'keep-evict-transfer-restore'),
    ("sequence-subject-rew", "const", "record_storage_rewrite", "SEQUENCE_SUBJECT",
     'rewrite-sequence'),
    ("decision-schema-suf", "const", "record_sufficiency", "DECISION_SCHEMA",
     's2c2.decision.v1'),
    ("decision-schema-auth", "const", "record_authorization", "DECISION_SCHEMA",
     's2c2.decision.v1'),
    ("decision-schema-rew", "const", "record_storage_rewrite", "DECISION_SCHEMA",
     's2c2.decision.v1'),
    ("auth-schema", "const", "record_authorization", "AUTH_SCHEMA",
     's2c2.authorization.v1'),
    ("sufficiency-schema", "const", "record_sufficiency", "SUFFICIENCY_SCHEMA",
     's2c2.sufficiency.v1'),
    ("rewrite-schema", "const", "record_storage_rewrite", "REWRITE_SCHEMA",
     's2c2.storage_rewrite.v1'),
    ("apply-schema", "const", "record_storage_apply", "APPLY_SCHEMA",
     's2c2.storage_apply.v1'),
    ("witness-schema", "const", "record_storage_apply", "WITNESS_SCHEMA",
     's2c2.apply_legality_witness.v1'),
    ("claim-schema", "const", "record_realization_checking", "CLAIM_SCHEMA",
     's2c2.realization_claim.v1'),
    ("checking-schema", "const", "record_realization_checking", "CHECKING_SCHEMA",
     's2c2.realization_checking.v1'),
    ("legality-schema", "const", "record_realization_legality", "LEGALITY_SCHEMA",
     's2c2.realization_legality.v1'),
    ("profile-schema", "const", "record_capability_profile", "PROFILE_SCHEMA",
     's2c2.capability_profile.v1'),
    ("applicability-schema", "const", "record_capability_applicability", "SCHEMA",
     's2c2.capability_applicability.v1'),
    ("report-schema", "const", "record_occupancy_capability", "REPORT_SCHEMA",
     's2c2.occupancy_capability_report.v1'),
    ("evidence-kind-schema", "const", "record_decision", "EVIDENCE_KIND_SCHEMA",
     's2c2.evidence_kind.v1'),
    ("evidence-record-schema", "const", "record_decision", "EVIDENCE_RECORD_SCHEMA",
     's2c2.evidence_record.v1'),
    ("evidence-db-schema", "const", "record_evidence", "SCHEMA",
     's2c2.evidence.v1'),
    ("evidence-v1-schema", "const", "record_evidence", "V1_SCHEMA",
     's2c2.measured_storage_cost.v1'),
    ("evidence-scope", "const", "record_evidence", "SCOPE",
     'candidate-local'),
    ("optimum-schema", "const", "record_optimum_authorization", "SCHEMA",
     's2c2.optimum_authorization.v1'),
    ("optimum-rule", "const", "record_optimum_authorization", "RULE",
     'unique-minimum-cost'),
    ("auth-required", "const", "record_authorization", "REQUIRED",
     ('sufficient', 'policy-match', 'provenance', 'action-match')),
    ("auth-policy-v01", "const", "record_authorization", "POLICY_V01",
     'authorization-policy-v0.1'),
    ("license-subject", "const", "record_authorization", "LICENSE_SUBJECT",
     'rewrite-license'),
    ("auth-reason-tokens", "const", "record_authorization", "AUTHORIZATION_REASON_TOKENS",
     ('authorization.sufficient-no', 'authorization.policy-mismatch', 'authorization.policy-unknown', 'authorization.provenance-unknown', 'authorization.action-mismatch', 'authorization.identity-mismatch', 'authorization.duplicate-license', 'authorization.authorized-no', 'authorization.authorized-closed', 'authorization.rewrite-license-missing', 'authorization.rewrite-license-no', 'authorization.rewrite-license-closed')),
    ("suf-required", "const", "record_sufficiency", "REQUIRED",
     ('usable', 'restore-ordering', 'dest-invalidation', 'capacity-legal')),
    ("suf-ignored-extra", "const", "record_sufficiency", "IGNORED_EXTRA",
     ('applicable', 'authorized')),
    ("suf-results", "const", "record_sufficiency", "RESULTS",
     ('yes', 'no', 'n/a')),
    ("rewrite-reason-tokens", "const", "record_storage_rewrite", "REWRITE_REASON_TOKENS",
     ('rewrite.license-no', 'rewrite.identity-mismatch', 'rewrite.sequence-mismatch', 'rewrite.duplicate-envelope', 'rewrite.duplicate-sequence', 'rewrite.plan-closed')),
    ("apply-emitted-reasons", "const", "record_storage_apply", "EMITTED_REASONS",
     ('decision.unknown-reason', 'rewrite.identity-mismatch', 'rewrite.sequence-mismatch', 'rewrite.duplicate-envelope', 'rewrite.license-no')),
    ("apply-machinery", "const", "record_storage_apply", "MACHINERY",
     ('evict', 'transfer')),
    ("apply-forbidden-ops", "const", "record_storage_apply", "FORBIDDEN",
     ('prefetch', 'preserve', 'rematerialize', 'evict', 'transfer', 'restore')),
    ("apply-allowed-other", "const", "record_storage_apply", "ALLOWED_OTHER",
     ('compute', 'load')),
    ("capa-targets", "const", "record_capability_applicability", "TARGETS",
     ('cpu', 'cuda', 'rocm', 'sycl', 'ascend', 'npu', 'cim')),
    ("capa-kinds", "const", "record_capability_applicability", "KINDS",
     ('concurrent-pair', 'named-nonblocking', 'staged-dma')),
    ("capa-applicability-values", "const", "record_capability_applicability", "APPLICABILITY_VALUES",
     ('yes', 'no', 'n/a')),
    ("capa-provenance-values", "const", "record_capability_applicability", "PROVENANCE_VALUES",
     ('catalog', 'occupancy-query', 'unknown')),
    ("capa-occupancy-usable-values", "const", "record_capability_applicability", "OCCUPANCY_USABLE_VALUES",
     ('yes', 'no', 'n/a')),
    ("capa-reason-tokens", "const", "record_capability_applicability", "CAPABILITY_REASON_TOKENS",
     ('capability.present', 'capability.missing-evidence', 'capability.not-applicable', 'capability.unknown-target', 'capability.unknown-kind')),
    ("device-4090", "const", "record_capability_applicability", "DEVICE_4090",
     'sm89:rtx4090'),
    ("device-910b", "const", "record_capability_applicability", "DEVICE_910B",
     'ascend910b'),
    ("device-host", "const", "record_capability_applicability", "DEVICE_HOST",
     'host'),
    ("profile-constraint-statuses", "const", "record_capability_profile", "CONSTRAINT_STATUSES",
     ('allowed', 'forbidden', 'not-applicable', 'unproven')),
    ("profile-entry-provenance", "const", "record_capability_profile", "ENTRY_PROVENANCE",
     ('catalog', 'occupancy-query', 'unknown', 'missing')),
    ("decision-usable-kinds", "const", "record_decision", "USABLE_KINDS",
     ('source-data', 'restore-ordering')),
    ("evidence-reason-tokens", "const", "record_decision", "EVIDENCE_REASON_TOKENS",
     ('evidence.unknown-witness', 'evidence.scope-mismatch', 'evidence.no-source-replica', 'evidence.no-validity-witness', 'evidence.no-ordering-witness', 'evidence.no-invalidation-witness', 'evidence.interval-does-not-cover', 'evidence.not-before-consumer', 'evidence.witnessed-unmutated-cover', 'evidence.witnessed-before-consumer', 'evidence.witnessed-drop-stale')),
    ("predicate-reason-tokens", "const", "record_decision", "PREDICATE_REASON_TOKENS",
     ('predicate.missing-input', 'predicate.source-data-present', 'predicate.restore-ordering-present')),
    ("decision-reason-tokens", "const", "record_decision", "DECISION_REASON_TOKENS",
     ('decision.subject-required', 'decision.unknown-subject', 'decision.unknown-reason', 'decision.duplicate-identity', 'decision.identity-mismatch')),
    ("occupancy-printer-map", "const", "record_decision", "OCCUPANCY_PRINTER_MAP",
     (('unknown-witness', 'evidence.unknown-witness'), ('unknown-scope', 'evidence.scope-mismatch'), ('replica-scope-mismatch', 'evidence.scope-mismatch'), ('destination-scope-mismatch', 'evidence.scope-mismatch'), ('no-source-replica', 'evidence.no-source-replica'), ('no-validity-witness', 'evidence.no-validity-witness'), ('no-ordering-witness', 'evidence.no-ordering-witness'), ('no-invalidation-witness', 'evidence.no-invalidation-witness'), ('interval-does-not-cover', 'evidence.interval-does-not-cover'), ('not-before-consumer', 'evidence.not-before-consumer'), ('witnessed-unmutated-cover', 'evidence.witnessed-unmutated-cover'), ('witnessed-before-consumer', 'evidence.witnessed-before-consumer'), ('witnessed-drop-stale', 'evidence.witnessed-drop-stale'))),
    ("scope-family", "const", "record_decision", "SCOPE_FAMILY",
     'evidence.scope-mismatch'),
    ("scope-displays", "const", "record_decision", "SCOPE_DISPLAYS",
     ('unknown-scope', 'replica-scope-mismatch', 'destination-scope-mismatch')),
    ("canonical-from-display", "const", "record_decision", "CANONICAL_FROM_DISPLAY",
     {'unknown-witness': 'evidence.unknown-witness', 'unknown-scope': 'evidence.unknown-scope', 'replica-scope-mismatch': 'evidence.replica-scope-mismatch', 'destination-scope-mismatch': 'evidence.destination-scope-mismatch', 'no-source-replica': 'evidence.no-source-replica', 'no-validity-witness': 'evidence.no-validity-witness', 'no-ordering-witness': 'evidence.no-ordering-witness', 'no-invalidation-witness': 'evidence.no-invalidation-witness', 'interval-does-not-cover': 'evidence.interval-does-not-cover', 'not-before-consumer': 'evidence.not-before-consumer', 'witnessed-unmutated-cover': 'evidence.witnessed-unmutated-cover', 'witnessed-before-consumer': 'evidence.witnessed-before-consumer', 'witnessed-drop-stale': 'evidence.witnessed-drop-stale'}),
    ("check-error-tokens", "const", "record_realization_checking", "ERROR_TOKENS",
     ('identity-mismatch', 'unknown-kind', 'malformed-legality', 'invalid-schema')),
    ("check-results", "const", "record_realization_checking", "RESULTS",
     ('satisfy', 'violate', 'unproven')),
    ("evidence-statuses", "const", "record_evidence", "STATUSES",
     ('measured', 'inferred', 'fixture', 'pending', 'invalid')),
    ("evidence-record-fields", "const", "record_evidence", "RECORD_FIELDS",
     ('schema', 'profile', 'workload_signature', 'candidate_signature', 'measurement_status', 'correctness', 'cost', 'scope', 'source', 'measurement_revision', 'recorded_at', 'note')),
    ("restore-legal", "const", "record_capacity", "RESTORE_LEGAL",
     'TRANSFER,REMATERIALIZE'),
    ("cap-schema", "const", "record_capacity", "SCHEMA",
     's2c2.capacity.v1'),
    ("cap-plan-schema", "const", "record_capacity", "PLAN_SCHEMA",
     's2c2.capacity_plan.v1'),
    ("cap-meas-schema", "const", "record_capacity", "MEAS_CAP_SCHEMA",
     's2c2.measured_capacity_cost.v1'),
    ("cap-license-schema", "const", "record_capacity", "LICENSE_SCHEMA",
     's2c2.capacity_license.v1'),
    ("cap-restore-schema", "const", "record_capacity", "RESTORE_SCHEMA",
     's2c2.capacity_restore.v1'),
    ("cap-predicate-schema", "const", "record_capacity", "PREDICATE_SCHEMA",
     's2c2.capacity_predicate.v1'),
    ("cap-sourcedata-schema", "const", "record_capacity", "SOURCEDATA_SCHEMA",
     's2c2.capacity_sourcedata.v1'),
    ("cap-ordering-schema", "const", "record_capacity", "ORDERING_SCHEMA",
     's2c2.capacity_ordering.v1'),
    ("cap-invalidation-schema", "const", "record_capacity", "INVALIDATION_SCHEMA",
     's2c2.capacity_invalidation.v1'),
    ("cap-spec-fields", "const", "record_capacity", "SPEC_FIELDS",
     ('schema', 'workload_class', 'space', 'capacity_tiles', 'residencies', 'note')),
    ("cap-optional-spec-fields", "const", "record_capacity", "OPTIONAL_SPEC_FIELDS",
     ('restore_sources', 'source_data', 'restore_order', 'dest_invalidation')),
    ("cap-restore-src-fields", "const", "record_capacity", "RESTORE_SRC_FIELDS",
     ('object', 'space', 'kind')),
    ("cap-source-data-fields", "const", "record_capacity", "SOURCE_DATA_FIELDS",
     ('object', 'replica', 'witness', 'live', 'scope')),
    ("cap-restore-order-fields", "const", "record_capacity", "RESTORE_ORDER_FIELDS",
     ('object', 'before', 'witness', 'scope')),
    ("cap-dest-inv-fields", "const", "record_capacity", "DEST_INV_FIELDS",
     ('object', 'destination', 'witness', 'scope')),
    ("cap-source-witness", "const", "record_capacity", "SOURCE_WITNESS",
     'spec-unmutated-cover'),
    ("cap-order-witness", "const", "record_capacity", "ORDER_WITNESS",
     'spec-before-consumer'),
    ("cap-dest-witness", "const", "record_capacity", "DEST_WITNESS",
     'spec-drop-stale'),
    ("cap-source-scope", "const", "record_capacity", "SOURCE_SCOPE",
     'occupancy-live'),
    ("cap-order-scope", "const", "record_capacity", "ORDER_SCOPE",
     'occupancy-live'),
    ("cap-dest-scope", "const", "record_capacity", "DEST_SCOPE",
     'occupancy-live'),
    ("cap-res-fields", "const", "record_capacity", "RES_FIELDS",
     ('id', 'object', 'space', 'size', 'live', 'producer', 'consumer', 'reuse_distance')),
    ("cap-meas-fields", "const", "record_capacity", "MEAS_CAP_FIELDS",
     ('schema', 'profile', 'workload_class', 'candidate_identity', 'measured_time_us', 'repetitions', 'correctness', 'source', 'measured', 'note')),
    ("corpus-id", "const", "record_scenario_corpus", "CORPUS_ID",
     'w0-3-2-scenario-corpus-v1'),
    ("corpus-baseline", "const", "record_scenario_corpus", "BASELINE",
     '71a6880dbaaac929bac837af0b7fbcad78708bb4'),
    ("corpus-fingerprint", "const", "record_scenario_corpus", "EXPECTED_FINGERPRINT",
     '52bf4be9680046a725f9f79c7abf2d045efbd7d03b3cb87a355419b67a7a0d00'),
    ("corpus-yes", "const", "record_scenario_corpus", "YES",
     'yes'),
    ("corpus-no", "const", "record_scenario_corpus", "NO",
     'no'),
    ("scenario-id", "const", "record_apply_scenario", "SCENARIO_ID",
     'w0-3-2-storage-capacity-001'),
    ("scenario-device", "const", "record_apply_scenario", "DEVICE",
     'D0'),
    ("ledger-fields", "const", "record_hw_ledger", "LEDGER_FIELDS",
     ('id', 'hardware', 'kind', 'status', 'path', 'tool', 'analyze', 'catalog_role', 'note', 'cost', 'semantics')),
    ("ledger-hardware", "const", "record_hw_ledger", "LEDGER_HARDWARE",
     ('rtx4090', 'ascend910b')),
    ("ledger-kind", "const", "record_hw_ledger", "LEDGER_KIND",
     ('catalog', 'overlay', 'campaign', 'program')),
    ("ledger-status", "const", "record_hw_ledger", "LEDGER_STATUS",
     ('measured', 'device-absent')),
    ("ledger-tool", "const", "record_hw_ledger", "LEDGER_TOOL",
     ('cuda', 'ascend', 'none')),
    ("ledger-role", "const", "record_hw_ledger", "LEDGER_ROLE",
     ('catalog-69', 'overlay', 'compiler-4090', 'campaign', 'pending-program', 'program')),
    ("ledger-forbidden", "const", "record_hw_ledger", "FORBIDDEN",
     ('password',)),
    ("ledger-vendor-prefix", "const", "record_hw_ledger", "VENDOR_KEY_PREFIX",
     ('acl_', 'davinci_', 'cube_', 'vectorcore_')),
    ("goal-absent-tuple", "const", "record_goal_alignment", "_ABSENT",
     ('dispatch', 'prefetch', 'attention', 'attn_tile', 'cim_mvm', 'accum', 'quant', 'hb')),
    ("cuda-cases", "const", "record_v3", "CASES",
     (('a', 'pilot_a_ssd_hbm_compute', 130), ('b', 'pilot_b_compute_par_comm', 128), ('c', 'pilot_c_pipeline_three_stage', 163))),
    ("cuda-cap-schema-version", "const", "record_v3", "CAP_SCHEMA_VERSION",
     '1'),
    ("cuda-cap-schema-kinds", "const", "record_v3", "CAP_SCHEMA_KINDS",
     ('pair', 'depth', 'memory', 'sync')),
    ("cuda-cap-schema-relation", "const", "record_v3", "CAP_SCHEMA_RELATION",
     ('serial', 'parallel', 'mixed', 'underdetermined')),
    ("cuda-cap-schema-regime", "const", "record_v3", "CAP_SCHEMA_REGIME",
     ('bandwidth', 'latency', 'occupancy', 'underdetermined')),
    ("cuda-cap-schema-constraint", "const", "record_v3", "CAP_SCHEMA_CONSTRAINT",
     ('none', 'legacy_default', 'resource_contention', 'allocator_sync', 'copy_engine_contention')),
    ("cuda-cap-schema-confidence", "const", "record_v3", "CAP_SCHEMA_CONFIDENCE",
     ('measured', 'inferred', 'arm_specific', 'unknown')),
    ("cuda-cap-schema-fields", "const", "record_v3", "CAP_SCHEMA_FIELDS",
     ('schema_version', 'record_kind', 'hardware_id', 'compute_domain', 'transfer_domain', 'direction', 'source_memory_class', 'destination_memory_class', 'pair', 'pair_relation', 'regime', 'size_range', 'synchronization', 'pipeline_depth_evidence', 'observed_constraint', 'confidence', 'note', 'evidence_refs', 'v3', 'cost', 'semantics')),
    ("cuda-meta-fields", "const", "record_v3", "FIELDS",
     ('git_commit', 'timestamp', 'gpu_model', 'gpu_memory', 'driver_version', 'cuda_runtime', 'nvcc_version', 'clock_state', 'power_mode', 'case', 'N', 'k', 'provisioned', 'warmup', 'reps', 'statistic', 'latency_us', 'score3')),
    ("cuda-ns", "const", "record_v3", "NS",
     (4194304, 16777216, 67108864)),
    ("cuda-ks", "const", "record_v3", "KS",
     (1, 8)),
    ("cuda-provs", "const", "record_v3", "PROVS",
     (0, 1)),
    ("cuda-matched-ks", "const", "record_v3", "MATCHED_KS",
     (1, 8, 32, 64)),
    ("cuda-matched-arms", "const", "record_v3", "MATCHED_ARMS",
     ('matched-seq', 'matched-ovl', 'matched-copy', 'matched-compute')),
    ("cuda-sync-arms", "const", "record_v3", "CAP_SYNC_ARMS",
     ('cap-event-sync', 'cap-stream-sync', 'cap-device-sync')),
    ("cuda-cap-size-bytes", "const", "record_v3", "CAP_SIZE_BYTES",
     (1024, 4096, 16384, 65536, 1048576, 4194304, 16777216, 67108864, 268435456)),
    ("cuda-matmul-dims", "const", "record_v3", "CAP_MATMUL_DIMS",
     (256, 512, 1024)),
    ("cuda-cap-k", "const", "record_v3", "CAP_K",
     32),
    ("cuda-phase-r", "const", "record_v3", "PHASE_R",
     (0.01, 0.03, 0.1, 0.3, 1.0, 3.0, 10.0, 30.0)),
    ("cuda-phase-k-max", "const", "record_v3", "PHASE_K_MAX",
     4096),
    ("cuda-phase-arms", "const", "record_v3", "PHASE_ARMS",
     ('phase-seq', 'phase-ovl', 'phase-copy', 'phase-compute')),
    ("cuda-pipe-tiles", "const", "record_v3", "PIPE_TILES",
     8),
    ("cuda-pipe-tiles-set", "const", "record_v3", "PIPE_TILES_SET",
     (4, 8, 16, 32)),
    ("cuda-pipe-depths", "const", "record_v3", "PIPE_DEPTHS",
     (1, 2, 3, 4)),
    ("cuda-pipe-arms", "const", "record_v3", "PIPE_ARMS",
     ('pipe-copy', 'pipe-compute', 'pipe-d1', 'pipe-d2', 'pipe-d3', 'pipe-d4')),
    ("cuda-val-arms", "const", "record_v3", "VAL_ARMS",
     ('val-copy-named', 'val-compute-named', 'val-seq-named', 'val-ovl-named', 'val-copy-default', 'val-compute-default', 'val-seq-default', 'val-ovl-default')),
    ("cuda-val-fields", "const", "record_v3", "VAL_FIELDS",
     ('N', 'k', 'stream', 'r', 'T_copy_us', 'T_compute_us', 'T_seq_us', 'T_ovl_us', 'ovl_over_max', 'ovl_over_sum', 'verdict', 'extra_hb')),
    ("cuda-val-mem-arms", "const", "record_v3", "VAL_MEM_ARMS",
     ('val-htod-pinned', 'val-htod-pageable', 'val-dtoh-pinned', 'val-dtoh-pageable', 'val-compute-mem', 'val-ovl-htod-pin', 'val-ovl-htod-page', 'val-ovl-dtoh-pin', 'val-ovl-dtoh-page')),
    ("cuda-val-mem-pairs", "const", "record_v3", "VAL_MEM_PAIRS",
     (('C||HtoD', 'val-htod-pinned', 'val-htod-pageable', 'val-ovl-htod-pin', 'val-ovl-htod-page'), ('C||DtoH', 'val-dtoh-pinned', 'val-dtoh-pageable', 'val-ovl-dtoh-pin', 'val-ovl-dtoh-page'))),
    ("cuda-val-mem-fields", "const", "record_v3", "VAL_MEM_FIELDS",
     ('N', 'k', 'pair', 'residency', 'r', 'T_copy_us', 'T_compute_us', 'T_ovl_us', 'ovl_over_max', 'ovl_over_sum', 'verdict', 'extra_hb')),
    ("cuda-val-cc-arms", "const", "record_v3", "VAL_CC_ARMS",
     ('val-cc-silu', 'val-cc-matmul', 'val-cc-seq', 'val-cc-ovl', 'val-cc-silu-silu')),
    ("cuda-val-cc-dim", "const", "record_v3", "VAL_CC_DIM",
     1024),
    ("cuda-val-cc-fields", "const", "record_v3", "VAL_CC_FIELDS",
     ('N', 'k', 'dim', 'r', 'T_silu_us', 'T_matmul_us', 'T_seq_us', 'T_ovl_us', 'T_silu_silu_us', 'ovl_over_max', 'ovl_over_sum', 'mixed_verdict', 'ss_over_max', 'ss_over_sum', 'same_verdict', 'pair_relation', 'observed_constraint')),
    ("cuda-val-async-arms", "const", "record_v3", "VAL_ASYNC_ARMS",
     ('val-async-copy', 'val-async-compute', 'val-async-life-sync', 'val-async-life-async', 'val-async-hb')),
    ("cuda-val-async-fields", "const", "record_v3", "VAL_ASYNC_FIELDS",
     ('N', 'k', 'r', 'T_copy_us', 'T_compute_us', 'T_life_sync_us', 'T_life_async_us', 'T_hb_us', 'sync_over_async', 'hb_over_async', 'observed_constraint', 'extra_hb')),
    ("cuda-pipe-fields", "const", "record_v3", "PIPE_FIELDS",
     ('N', 'k', 'tiles', 'r_tile', 'T_copy_us', 'T_compute_us', 'T_d1_us', 'T_d2_us', 'T_d3_us', 'T_d4_us', 'speedup_d2', 'speedup_d3', 'speedup_d4', 'ideal', 'T_ideal_pipe_us', 'sat_d4_over_d2')),
    ("cuda-phase-fields", "const", "record_v3", "PHASE_FIELDS",
     ('N', 'k', 'r_target', 'r_achieved', 'T_seq_us', 'T_ovl_us', 'T_copy_us', 'T_compute_us', 'ovl_over_max', 'ovl_over_sum', 'hidden_frac', 'dominance', 'overlap')),
    ("cuda-cal-fields", "const", "record_v3", "CAL_FIELDS",
     ('N', 'k', 'T_seq_us', 'T_ovl_us', 'T_copy_us', 'T_compute_us', 'ratio', 'gain_us', 'ideal_us', 'hidden_frac', 'seq_over_sum', 'ovl_over_max')),
    ("cuda-cap-pairs", "const", "record_v3", "CAP_PAIRS",
     (('HtoD||DtoH', 'cap-htod', 'cap-dtoh', 'cap-htod-dtoh-par'), ('HtoD||HtoD', 'cap-htod', 'cap-htod', 'cap-htod-htod-par'), ('DtoH||DtoH', 'cap-dtoh', 'cap-dtoh', 'cap-dtoh-dtoh-par'), ('C||HtoD', 'cap-compute', 'cap-htod', 'cap-compute-htod'), ('C||DtoH', 'cap-compute', 'cap-dtoh', 'cap-compute-dtoh'), ('C||C', 'cap-compute', 'cap-compute', 'cap-compute-compute'))),
    ("cuda-cap-pair-arms", "const", "record_v3", "CAP_PAIR_ARMS",
     ('cap-htod', 'cap-dtoh', 'cap-htod-dtoh-seq', 'cap-htod-dtoh-event', 'cap-htod-dtoh-par', 'cap-htod-htod-par', 'cap-dtoh-dtoh-par', 'cap-compute', 'cap-compute-htod', 'cap-compute-dtoh', 'cap-compute-compute')),
    ("ascend-pairs", "const", "record_ascend", "PAIRS",
     ('C||HtoD', 'C||C', 'HtoD||DtoH')),
    ("ascend-forbidden-keys", "const", "record_ascend", "FORBIDDEN_KEYS",
     ('acl_', 'davinci_', 'cube_', 'vectorcore_', 'password', 'localhost')),
    ("ascend-seq-slack", "const", "record_ascend", "SEQ_SLACK",
     1.05),
    ("ascend-sig-s0", "const", "record_ascend", "_SIG_S0",
     'MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER'),
    ("ascend-sig-s1", "const", "record_ascend", "_SIG_S1",
     'MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE|TRANSFER'),
    ("ascend-hier-tails", "const", "record_ascend", "_HIER_TAILS",
     ('PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY', 'PREFETCH|TRANSFER|KEEP_RESIDENCY|TRANSFER', 'PREFETCH|TRANSFER|TRANSFER|KEEP_RESIDENCY', 'PREFETCH|TRANSFER|TRANSFER|TRANSFER', 'PRESERVE|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY', 'PRESERVE|TRANSFER|KEEP_RESIDENCY|TRANSFER', 'PRESERVE|TRANSFER|TRANSFER|KEEP_RESIDENCY', 'PRESERVE|TRANSFER|TRANSFER|TRANSFER')),
    ("ascend-ntile-tails", "const", "record_ascend", "_NTILE_TAILS",
     ('PREFETCH|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER', 'PREFETCH|TRANSFER//PRESERVE|TRANSFER//TRANSFER|TRANSFER', 'PRESERVE|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER', 'PRESERVE|TRANSFER//PRESERVE|TRANSFER//TRANSFER|TRANSFER')),
    ("ascend-loop-tails", "const", "record_ascend", "_LOOP_TAILS",
     ('PREFETCH//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE', 'PREFETCH//TRANSFER//TRANSFER|TRANSFER|TRANSFER//MATERIALIZE', 'PRESERVE//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE', 'PRESERVE//TRANSFER//TRANSFER|TRANSFER|TRANSFER//MATERIALIZE')),
    ("ascend-cap-schema-version", "const", "record_ascend", "CAP_SCHEMA_VERSION",
     '1'),
    ("ascend-cap-schema-kinds", "const", "record_ascend", "CAP_SCHEMA_KINDS",
     ('pair', 'depth', 'memory', 'sync')),
    ("ascend-cap-schema-relation", "const", "record_ascend", "CAP_SCHEMA_RELATION",
     ('serial', 'parallel', 'mixed', 'underdetermined')),
    ("ascend-cap-schema-regime", "const", "record_ascend", "CAP_SCHEMA_REGIME",
     ('bandwidth', 'latency', 'occupancy', 'underdetermined')),
    ("ascend-cap-schema-constraint", "const", "record_ascend", "CAP_SCHEMA_CONSTRAINT",
     ('none', 'legacy_default', 'resource_contention', 'allocator_sync', 'copy_engine_contention')),
    ("ascend-cap-schema-confidence", "const", "record_ascend", "CAP_SCHEMA_CONFIDENCE",
     ('measured', 'inferred', 'arm_specific', 'unknown')),
    ("ascend-cap-schema-fields", "const", "record_ascend", "CAP_SCHEMA_FIELDS",
     ('schema_version', 'record_kind', 'hardware_id', 'compute_domain', 'transfer_domain', 'direction', 'source_memory_class', 'destination_memory_class', 'pair', 'pair_relation', 'regime', 'size_range', 'synchronization', 'pipeline_depth_evidence', 'observed_constraint', 'confidence', 'note', 'evidence_refs', 'v3', 'cost', 'semantics')),
    ("check-result-for", "pairs", "record_realization_checking", "_RESULT_FOR",
     (('allowed', 'satisfy'), ('forbidden', 'violate'), ('not-applicable', 'violate'), ('unproven', 'unproven'))),
    ("cuda-analyze-map", "pairs", "record_hw_ledger", "CUDA_ANALYZE",
     (('cap-schema', '--analyze-cap-schema'), ('cap', '--analyze-cap'), ('phase', '--analyze-phase'), ('pipe', '--analyze-pipe'), ('pipe-tiles', '--analyze-pipe-tiles'), ('cuda-val', '--analyze-cuda-val'), ('cuda-val-mem', '--analyze-cuda-val-mem'), ('cuda-val-cc', '--analyze-cuda-val-cc'), ('cuda-val-async', '--analyze-cuda-val-async'), ('matched', '--analyze-matched'), ('ratio', '--analyze-ratio'))),
    ("ascend-analyze-map", "pairs", "record_hw_ledger", "ASCEND_ANALYZE",
     (('cap-schema', '--analyze-cap-schema'), ('mem', '--analyze-mem'), ('cc-phase', '--analyze-cc-phase'), ('cc-size', '--analyze-cc-size'), ('cc-rewrite', '--analyze-cc-rewrite'), ('ssd-mlp-wallclock', '--analyze-ssd-mlp-wallclock'), ('e2e-gain', '--analyze-e2e-gain'))),
    ("evidence-revision-map", "pairs", "record_evidence", "REVISION_FROM_NAME",
     (('storage-measured-v1.jsonl', 'fixture-v1'), ('storage-measured-v1-4090.jsonl', '5a-pipeline-4090'), ('storage-measured-v1-910b.jsonl', '5a-pipeline-910b'), ('storage-measured-v1-hierarchy-4090.jsonl', '5b-hierarchy-4090'), ('storage-measured-v1-hierarchy-910b.jsonl', '5b-hierarchy-910b'), ('storage-measured-v1-ntile-4090.jsonl', '5c-ntile-4090'), ('storage-measured-v1-ntile-910b.jsonl', '5c-ntile-910b'), ('storage-measured-v1-loop-4090.jsonl', '5d-loop-4090'), ('storage-measured-v1-loop-910b.jsonl', '5d-loop-910b'))),
    ("canonical-display-map", "pairs", "record_decision", "CANONICAL_FROM_DISPLAY",
     (('unknown-witness', 'evidence.unknown-witness'), ('unknown-scope', 'evidence.unknown-scope'), ('replica-scope-mismatch', 'evidence.replica-scope-mismatch'), ('destination-scope-mismatch', 'evidence.destination-scope-mismatch'), ('no-source-replica', 'evidence.no-source-replica'), ('no-validity-witness', 'evidence.no-validity-witness'), ('no-ordering-witness', 'evidence.no-ordering-witness'), ('no-invalidation-witness', 'evidence.no-invalidation-witness'), ('interval-does-not-cover', 'evidence.interval-does-not-cover'), ('not-before-consumer', 'evidence.not-before-consumer'), ('witnessed-unmutated-cover', 'evidence.witnessed-unmutated-cover'), ('witnessed-before-consumer', 'evidence.witnessed-before-consumer'), ('witnessed-drop-stale', 'evidence.witnessed-drop-stale'))),
    ("auth-matrix-cases", "len", "record_authorization", "_cases", 20),
    ("suf-matrix-cases", "len", "record_sufficiency", "_cases", 16),
    ("rew-matrix-cases", "len", "record_storage_rewrite", "_cases", 18),
    ("e2e-matrix-cases", "len", "record_realization_checking_e2e", "_cases", 3),
    ("xid-matrix-cases", "len", "record_realization_checking_xid", "_cases", 4),
    ("scenario-p-len", "len", "record_apply_scenario", "CANONICAL_P", 206),
    ("scenario-p-prime-len", "len", "record_apply_scenario", "CANONICAL_P_PRIME", 380),
    ("scenario-programs-differ", "ne",
     ("record_apply_scenario", "CANONICAL_P"),
     ("record_apply_scenario", "CANONICAL_P_PRIME")),
    ("e2e-case-names", "cases_first", "record_realization_checking_e2e",
     ("legal-claim", "unsatisfied-claim", "identity-mismatch")),
    ("xid-case-names", "cases_first", "record_realization_checking_xid",
     ("cuda-legal", "ascend-dma", "cpu-na", "cross-target")),
    ("xid-targets", "cases_col", "record_realization_checking_xid", 2,
     ("cuda", "ascend", "cpu", "ascend")),
    ("ledger-rows", "ledger", 31, ("rtx4090", "ascend910b")),
    ("cuda-header-sched", "hdr_str", "runtime/cuda/AdapterContract.h", "kSched", "gpu-async"),
    ("cuda-header-map", "hdr_str", "runtime/cuda/AdapterContract.h", "kMap", "default"),
    ("cuda-header-device", "hdr_str", "runtime/cuda/AdapterContract.h", "kDevice", "gpu"),
    ("cuda-header-pilot-count", "hdr_int", "runtime/cuda/AdapterContract.h", "kPilotCount", 3),
    ("cuda-header-pilots", "hdr_rows", "runtime/cuda/AdapterContract.h", "kPilots",
     (("a", "pilot_a_ssd_hbm_compute", 130),
      ("b", "pilot_b_compute_par_comm", 128),
      ("c", "pilot_c_pipeline_three_stage", 163))),
    ("ascend-header-sched", "hdr_str", "runtime/ascend/AdapterContract.h", "kSched", "npu-async"),
    ("ascend-header-map", "hdr_str", "runtime/ascend/AdapterContract.h", "kMap", "default"),
    ("ascend-header-device", "hdr_str", "runtime/ascend/AdapterContract.h", "kDevice", "npu"),
    ("ascend-header-sync", "hdr_str", "runtime/ascend/AdapterContract.h", "kSync", "named-nonblocking"),
    ("ascend-header-hardware", "hdr_str", "runtime/ascend/AdapterContract.h", "kHardwareId", "ascend910b:ascend"),
    ("ascend-header-workload-count", "hdr_int", "runtime/ascend/AdapterContract.h", "kWorkloadCount", 3),
    ("ascend-header-pair-count", "hdr_int", "runtime/ascend/AdapterContract.h", "kPairCount", 3),
    ("ascend-header-field-count", "hdr_int", "runtime/ascend/AdapterContract.h", "kSchemaFieldCount", 21),
    ("ascend-header-seq-slack", "hdr_float", "runtime/ascend/AdapterContract.h", "kSeqSlack", 1.05),
    ("ascend-header-schema-fields", "hdr_list", "runtime/ascend/AdapterContract.h", "kSchemaFields",
     ("schema_version", "record_kind", "hardware_id", "compute_domain",
      "transfer_domain", "direction", "source_memory_class",
      "destination_memory_class", "pair", "pair_relation", "regime",
      "size_range", "synchronization", "pipeline_depth_evidence",
      "observed_constraint", "confidence", "note", "evidence_refs",
      "v3", "cost", "semantics")),
    ("ascend-header-workloads", "hdr_rows", "runtime/ascend/AdapterContract.h", "kWorkloads",
     (("compute", "compute", "elemwise"),
      ("htod", "transfer", "host_to_device"),
      ("dtoh", "transfer", "device_to_host"))),
    ("ascend-header-pairs", "hdr_rows", "runtime/ascend/AdapterContract.h", "kPairs",
     (("R1", "C||HtoD", "compute", "htod"),
      ("R2", "C||C", "compute", "compute"),
      ("R3", "HtoD||DtoH", "htod", "dtoh"))),
    ("td-stor-ops", "tg_ops", "include/s2c2/Storage/StorageOps.td", "Stor",
     ("object", "localize", "materialize", "transfer", "alloc", "dealloc", "pack", "unpack")),
    ("td-comp-ops", "tg_ops", "include/s2c2/Compute/ComputeOps.td", "Comp",
     ("matmul", "elemwise", "gated_mlp")),
    ("td-comm-ops", "tg_ops", "include/s2c2/Comm/CommOps.td", "Comm",
     ("copy", "stream", "barrier")),
    ("td-sched-ops", "tg_ops", "include/s2c2/Schedule/ScheduleOps.td", "Sched",
     ("yield", "wait", "task", "concurrent", "overlap", "pipeline", "stage")),
    ("td-sketch-ops-absent", "tg_absent", 8),
    ("td-count-goal-agree", "tg_agree",
     (("stor", 8), ("comp", 3), ("comm", 3), ("sched", 7))),

)

_TOTAL = len(AUDITS)


def print_constant_audit() -> int:
    failed = 0
    print("constant-audit gate=query")
    for row in AUDITS:
        try:
            ok = _eval(row)
        except Exception:
            ok = False
        key = row[0]
        if ok:
            print(f"{key} yes")
        else:
            failed += 1
            print(f"{key} no")
    print(f"constant-audit-total {_TOTAL}")
    print(f"constant-audit-failed {failed}")
    if failed:
        print("constant-audit no")
        return 1
    print("constant-audit yes")
    print("can-run-plan no")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Table-driven constant audit for the host stack.",
        add_help=False,
    )
    parser.add_argument("--print-constant-audit", action="store_true")
    args, extra = parser.parse_known_args(argv)
    if extra or not args.print_constant_audit:
        print(
            "record_constant_audit: choose --print-constant-audit",
            file=sys.stderr,
        )
        return 2
    return print_constant_audit()


if __name__ == "__main__":
    sys.exit(main())
