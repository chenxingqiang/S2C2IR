// CUDA and Ascend CAP_SCHEMA_FIELDS from the host recorders.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Do not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q55_cafld.py --print-q55-cafld | FileCheck %s --check-prefix=Q55 --implicit-check-not=can-run-plan=yes
// Q55: q55-cafld gate=query
// Q55: cap-field schema_version
// Q55: cap-field record_kind
// Q55: cap-field hardware_id
// Q55: cap-field compute_domain
// Q55: cap-field transfer_domain
// Q55: cap-field direction
// Q55: cap-field source_memory_class
// Q55: cap-field destination_memory_class
// Q55: cap-field pair
// Q55: cap-field pair_relation
// Q55: cap-field regime
// Q55: cap-field size_range
// Q55: cap-field synchronization
// Q55: cap-field pipeline_depth_evidence
// Q55: cap-field observed_constraint
// Q55: cap-field confidence
// Q55: cap-field note
// Q55: cap-field evidence_refs
// Q55: cap-field v3
// Q55: cap-field cost
// Q55: cap-field semantics
// Q55: q55-cafld yes
// Q55: can-run-plan no
