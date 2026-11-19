// Evidence record fields from record_evidence.RECORD_FIELDS.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Does not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q48_recfld.py --print-q48-recfld | FileCheck %s --check-prefix=Q48 --implicit-check-not=can-run-plan=yes
// Q48: q48-recfld gate=query
// Q48: record-field schema
// Q48: record-field profile
// Q48: record-field workload_signature
// Q48: record-field candidate_signature
// Q48: record-field measurement_status
// Q48: record-field correctness
// Q48: record-field cost
// Q48: record-field scope
// Q48: record-field source
// Q48: record-field measurement_revision
// Q48: record-field recorded_at
// Q48: record-field note
// Q48: q48-recfld yes
// Q48: can-run-plan no
