#!/usr/bin/env bash
# Replay the host contract and matrix printers. Python 3 only; no LLVM.
#
# These checks do not include `check-s2c2`. A pass here does not change
# the semantic baseline or `can-run-plan`, and does not open a cut.
#
# Usage: scripts/check-host.sh [--log DIR]
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

LOG_DIR=""
if [[ "${1:-}" == "--log" ]]; then
  LOG_DIR="${2:?--log needs a directory}"
  mkdir -p "${LOG_DIR}"
fi

PY="${PYTHON:-python3}"
pass=0
fail=0
failed=()
tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

run() {
  local name="$1"
  shift
  if "$@" >"${tmp}" 2>&1; then
    pass=$((pass + 1))
    echo "PASS  ${name}"
  else
    fail=$((fail + 1))
    failed+=("${name}")
    echo "FAIL  ${name}"
    tail -20 "${tmp}"
  fi
  if [[ -n "${LOG_DIR}" ]]; then
    cp "${tmp}" "${LOG_DIR}/${name//[^A-Za-z0-9._-]/_}.out"
  fi
}

run baseline-summary "${PY}" runtime/record_semantic_baseline.py --print-semantic-baseline-summary
run baseline-contract "${PY}" runtime/record_semantic_baseline.py --print-semantic-baseline-contract
run apply-scenario "${PY}" runtime/record_apply_scenario.py --print-apply-scenario
run apply-contract "${PY}" runtime/record_storage_apply.py --print-apply-contract
run apply-matrix "${PY}" runtime/record_storage_apply.py --print-apply-matrix
run carrier-extract "${PY}" runtime/record_mlir_carrier.py --print-carrier-extract
run compiler-spine "${PY}" runtime/record_compiler_spine.py --print-compiler-spine
run goal-alignment "${PY}" runtime/record_goal_alignment.py --print-goal-alignment
run scenario-corpus "${PY}" runtime/record_scenario_corpus.py --print-scenario-corpus

run sufficiency-contract "${PY}" runtime/record_sufficiency.py --print-sufficiency-contract
run sufficiency-matrix "${PY}" runtime/record_sufficiency.py --print-sufficiency-matrix
run authorization-contract "${PY}" runtime/record_authorization.py --print-authorization-contract
run authorization-matrix "${PY}" runtime/record_authorization.py --print-authorization-matrix
run rewrite-contract "${PY}" runtime/record_storage_rewrite.py --print-rewrite-contract
run rewrite-matrix "${PY}" runtime/record_storage_rewrite.py --print-rewrite-matrix

run legality-contract "${PY}" runtime/record_realization_legality.py --print-realization-legality-contract
run legality-matrix "${PY}" runtime/record_realization_legality.py --print-realization-legality-matrix
run checking-contract "${PY}" runtime/record_realization_checking.py --print-realization-checking-contract
run checking-matrix "${PY}" runtime/record_realization_checking.py --print-realization-checking-matrix
run checking-e2e-contract "${PY}" runtime/record_realization_checking_e2e.py --print-realization-checking-e2e-contract
run checking-e2e-matrix "${PY}" runtime/record_realization_checking_e2e.py --print-realization-checking-e2e-matrix
run checking-xid-contract "${PY}" runtime/record_realization_checking_xid.py --print-realization-checking-xid-contract
run checking-xid-matrix "${PY}" runtime/record_realization_checking_xid.py --print-realization-checking-xid-matrix

run profile-contract "${PY}" runtime/record_capability_profile.py --print-capability-profile-contract
run profile-matrix "${PY}" runtime/record_capability_profile.py --print-capability-profile-matrix
run applicability-contract "${PY}" runtime/record_capability_applicability.py --print-capability-applicability-contract
run applicability-matrix "${PY}" runtime/record_capability_applicability.py --print-capability-applicability-matrix
run occupancy-contract "${PY}" runtime/record_occupancy_capability.py --print-occupancy-capability-report-contract
run occupancy-matrix "${PY}" runtime/record_occupancy_capability.py --print-occupancy-capability-report-matrix

run decision-contract "${PY}" runtime/record_decision.py --print-evidence-decision-contract
run decision-reason-vocab "${PY}" runtime/record_decision.py --print-evidence-reason-vocab
run algebra-contract "${PY}" runtime/record_decision.py --print-evidence-algebra-contract
run algebra-matrix "${PY}" runtime/record_decision.py --print-evidence-algebra-matrix

run hw-ledger-contract "${PY}" runtime/record_hw_ledger.py --print-hw-ledger-contract
run hw-ledger-check "${PY}" runtime/record_hw_ledger.py --check-hw-ledger
run evidence-db-contract "${PY}" runtime/record_evidence.py --print-evidence-db-contract
run evidence-stable-baseline "${PY}" runtime/record_evidence.py --print-stable-baseline-contract
run evidence-db-check "${PY}" runtime/record_evidence.py --check-evidence-db

for flag in \
  --print-storage-capacity-contract \
  --print-capacity-plan-contract \
  --print-capacity-plan-query-contract \
  --print-capacity-policy-contract \
  --print-measured-capacity-contract \
  --print-capacity-license-contract \
  --print-capacity-restore-contract \
  --print-capacity-predicate-contract \
  --print-capacity-sourcedata-contract \
  --print-capacity-ordering-contract \
  --print-capacity-invalidation-contract
do
  run "capacity${flag}" "${PY}" runtime/record_capacity.py "${flag}"
done

run ascend-schema-identity "${PY}" runtime/ascend/record_ascend.py --check-schema-identity
run ascend-schema "${PY}" runtime/ascend/record_ascend.py --print-cap-schema-v1
run cuda-schema "${PY}" runtime/cuda/record_v3.py --print-schema

echo "----"
echo "PASS ${pass} FAIL ${fail}"
if (( fail > 0 )); then
  printf 'failed: %s\n' "${failed[*]}"
  exit 1
fi
