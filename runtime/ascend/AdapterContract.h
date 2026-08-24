//===- AdapterContract.h - Ascend capability adapter (no ACL) ---*- C++ -*-===//
//
// Semantic workload contracts for the three Phase 3B pairs.
// Not Pilot Score_3. Not a CUDA SiLU / GEMM port.
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_RUNTIME_ASCEND_ADAPTER_CONTRACT_H
#define S2C2_RUNTIME_ASCEND_ADAPTER_CONTRACT_H

namespace s2c2 {
namespace ascend_adapter {

inline constexpr const char *kSched = "npu-async";
inline constexpr const char *kMap = "default";
inline constexpr const char *kDevice = "npu";
inline constexpr const char *kSync = "named-nonblocking";
inline constexpr const char *kHardwareId = "ascend910b:ascend";

struct WorkloadContract {
  const char *id;
  const char *role;
  const char *semantic;
};

inline constexpr WorkloadContract kWorkloads[] = {
    {"compute", "compute", "elemwise"},
    {"htod", "transfer", "host_to_device"},
    {"dtoh", "transfer", "device_to_host"},
};

inline constexpr int kWorkloadCount = 3;

struct PairContract {
  const char *id;
  const char *pair;
  const char *left;
  const char *right;
};

inline constexpr PairContract kPairs[] = {
    {"R1", "C||HtoD", "compute", "htod"},
    {"R2", "C||C", "compute", "compute"},
    {"R3", "HtoD||DtoH", "htod", "dtoh"},
};

inline constexpr int kPairCount = 3;

inline constexpr const char *kSchemaFields[] = {
    "schema_version",
    "record_kind",
    "hardware_id",
    "compute_domain",
    "transfer_domain",
    "direction",
    "source_memory_class",
    "destination_memory_class",
    "pair",
    "pair_relation",
    "regime",
    "size_range",
    "synchronization",
    "pipeline_depth_evidence",
    "observed_constraint",
    "confidence",
    "note",
    "evidence_refs",
    "v3",
    "cost",
    "semantics",
};

inline constexpr int kSchemaFieldCount = 21;

// Same slack as runtime/cuda/record_v3.py _verdict. Not a Cost axiom.
inline const char *classifyPair(double parOverMax, double parOverSum) {
  if (parOverSum >= 0.90)
    return "serial";
  if (parOverMax <= 1.15 && parOverSum <= 0.75)
    return "parallel";
  return "mixed";
}

inline const char *inferConstraint(const char *pair, const char *relation) {
  if (relation[0] != 's') // not serial
    return "none";
  if (pair[0] == 'C' && pair[1] == '|' && pair[2] == '|' && pair[3] == 'C' &&
      pair[4] == '\0')
    return "resource_contention";
  return "copy_engine_contention";
}

} // namespace ascend_adapter
} // namespace s2c2

#endif
