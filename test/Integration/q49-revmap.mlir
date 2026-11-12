// Measured-storage revision map from record_evidence.REVISION_FROM_NAME.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_q49_revmap.py --print-q49-revmap | FileCheck %s --check-prefix=Q49 --implicit-check-not=can-run-plan=yes
// Q49: q49-revmap gate=query
// Q49: revision storage-measured-v1.jsonl fixture-v1
// Q49: revision storage-measured-v1-4090.jsonl 5a-pipeline-4090
// Q49: revision storage-measured-v1-910b.jsonl 5a-pipeline-910b
// Q49: revision storage-measured-v1-hierarchy-4090.jsonl 5b-hierarchy-4090
// Q49: revision storage-measured-v1-hierarchy-910b.jsonl 5b-hierarchy-910b
// Q49: revision storage-measured-v1-ntile-4090.jsonl 5c-ntile-4090
// Q49: revision storage-measured-v1-ntile-910b.jsonl 5c-ntile-910b
// Q49: revision storage-measured-v1-loop-4090.jsonl 5d-loop-4090
// Q49: revision storage-measured-v1-loop-910b.jsonl 5d-loop-910b
// Q49: q49-revmap yes
// Q49: can-run-plan no
