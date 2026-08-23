// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-schema | FileCheck %s
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-schema --format=csv | FileCheck %s --check-prefix=CSV

// Schema witness only. No device, no microseconds FileCheck.
module {
}

// CHECK: git_commit
// CHECK: timestamp
// CHECK: gpu_model
// CHECK: gpu_memory
// CHECK: driver_version
// CHECK: cuda_runtime
// CHECK: nvcc_version
// CHECK: clock_state
// CHECK: power_mode
// CHECK: case
// CHECK: N
// CHECK: k
// CHECK: provisioned
// CHECK: warmup
// CHECK: reps
// CHECK: statistic
// CHECK: latency_us
// CHECK: score3
// CHECK: source driver_version=nvidia-smi
// CHECK: source nvcc_version=nvcc
// CHECK: source cuda_runtime=cudaRuntimeGetVersion
// CHECK: v3=not-claimed
// CHECK-NOT: password
// CHECK-NOT: ssh

// CSV: git_commit,timestamp,gpu_model,gpu_memory,driver_version,cuda_runtime,nvcc_version,clock_state,power_mode,case,N,k,provisioned,warmup,reps,statistic,latency_us,score3
