// CUDA metadata fields from runtime/cuda/record_v3.FIELDS.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Does not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q86_cmeta.py --print-q86-cmeta | FileCheck %s --check-prefix=Q86 --implicit-check-not=can-run-plan=yes
// Q86: q86-cmeta gate=query
// Q86: meta-field git_commit
// Q86: meta-field timestamp
// Q86: meta-field gpu_model
// Q86: meta-field gpu_memory
// Q86: meta-field driver_version
// Q86: meta-field cuda_runtime
// Q86: meta-field nvcc_version
// Q86: meta-field clock_state
// Q86: meta-field power_mode
// Q86: meta-field case
// Q86: meta-field N
// Q86: meta-field k
// Q86: meta-field provisioned
// Q86: meta-field warmup
// Q86: meta-field reps
// Q86: meta-field statistic
// Q86: meta-field latency_us
// Q86: meta-field score3
// Q86: q86-cmeta yes
// Q86: can-run-plan no
