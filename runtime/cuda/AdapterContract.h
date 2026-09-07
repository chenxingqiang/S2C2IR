//===- AdapterContract.h - CUDA adapter binding (no CUDA) -------*- C++ -*-===//
//
// Frozen Pilot Score_3 totals for M = (gpu-async, default, gpu).
// Must match test/Pilot/s2c2-pilot-workloads.mlir FileCheck.
// The adapter does not recompute Cost.
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_RUNTIME_CUDA_ADAPTER_CONTRACT_H
#define S2C2_RUNTIME_CUDA_ADAPTER_CONTRACT_H

namespace s2c2 {
namespace cuda_adapter {

inline constexpr const char *kSched = "gpu-async";
inline constexpr const char *kMap = "default";
inline constexpr const char *kDevice = "gpu";

struct PilotBind {
  const char *id;
  const char *func;
  int score3Total;
};

inline constexpr PilotBind kPilots[] = {
    {"a", "pilot_a_ssd_hbm_compute", 130},
    {"b", "pilot_b_compute_par_comm", 128},
    {"c", "pilot_c_pipeline_three_stage", 163},
};

inline constexpr int kPilotCount = 3;

} // namespace cuda_adapter
} // namespace s2c2

#endif
