//===- s2c2_rocm_adapter.cpp - HIP capability harness -----------*- C++ -*-===//
//
// Times three S²C² pairs on ROCm. Not a compiler backend. Not Cost.
// Workload semantic = elemwise / host_to_device / device_to_host.
//
//   hipcc -O2 -std=c++17 runtime/rocm/s2c2_rocm_adapter.cpp -o s2c2-rocm-run
//
//===----------------------------------------------------------------------===//

#include "AdapterContract.h"

#include <hip/hip_runtime.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

using s2c2::rocm_adapter::classifyPair;
using s2c2::rocm_adapter::inferConstraint;
using s2c2::rocm_adapter::kMap;
using s2c2::rocm_adapter::kSched;
using s2c2::rocm_adapter::kSync;

#define HIP_OK(expr)                                                           \
  do {                                                                         \
    hipError_t _e = (expr);                                                    \
    if (_e != hipSuccess) {                                                    \
      std::fprintf(stderr, "s2c2-rocm-run: HIP %s at %s:%d\n",                 \
                   hipGetErrorString(_e), __FILE__, __LINE__);                 \
      std::exit(1);                                                            \
    }                                                                          \
  } while (0)

__global__ void elemwiseKernel(const float *x, float *y, int n, int k) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i >= n)
    return;
  float v = x[i];
  for (int t = 0; t < k; ++t)
    v = v * 2.f + 1.f;
  y[i] = v;
}

static void elemwiseLaunch(const float *x, float *y, int n, int k,
                           hipStream_t s) {
  int threads = 256;
  int blocks = (n + threads - 1) / threads;
  hipLaunchKernelGGL(elemwiseKernel, dim3(blocks), dim3(threads), 0, s, x, y, n,
                     k);
}

static float hostElemwise(float x, int k) {
  float v = x;
  for (int t = 0; t < k; ++t)
    v = v * 2.f + 1.f;
  return v;
}

static void fillHost(float *p, int n, int seed) {
  for (int i = 0; i < n; ++i)
    p[i] = 0.001f * static_cast<float>(((i + seed) % 1000) + 1);
}

enum class Arm { Compute, HtoD, DtoH, ComputeHtoD, ComputeCompute, HtoDDtoH };

static const char *armName(Arm a) {
  switch (a) {
  case Arm::Compute:
    return "compute";
  case Arm::HtoD:
    return "htod";
  case Arm::DtoH:
    return "dtoh";
  case Arm::ComputeHtoD:
    return "compute-htod";
  case Arm::ComputeCompute:
    return "compute-compute";
  case Arm::HtoDDtoH:
    return "htod-dtoh";
  }
  return "off";
}

static const char *armPair(Arm a) {
  switch (a) {
  case Arm::ComputeHtoD:
    return "C||HtoD";
  case Arm::ComputeCompute:
    return "C||C";
  case Arm::HtoDDtoH:
    return "HtoD||DtoH";
  default:
    return "single";
  }
}

struct Buf {
  float *host0 = nullptr;
  float *host1 = nullptr;
  float *check = nullptr;
  float *dev0 = nullptr;
  float *dev1 = nullptr;
  float *dev2 = nullptr;
  int n = 0;
  hipStream_t s0 = nullptr;
  hipStream_t s1 = nullptr;
  hipEvent_t start = nullptr;
  hipEvent_t stop = nullptr;

  void alloc(int n_) {
    n = n_;
    size_t bytes = sizeof(float) * static_cast<size_t>(n);
    HIP_OK(hipHostMalloc(&host0, bytes));
    HIP_OK(hipHostMalloc(&host1, bytes));
    HIP_OK(hipHostMalloc(&check, bytes));
    HIP_OK(hipMalloc(&dev0, bytes));
    HIP_OK(hipMalloc(&dev1, bytes));
    HIP_OK(hipMalloc(&dev2, bytes));
    HIP_OK(hipStreamCreateWithFlags(&s0, hipStreamNonBlocking));
    HIP_OK(hipStreamCreateWithFlags(&s1, hipStreamNonBlocking));
    HIP_OK(hipEventCreate(&start));
    HIP_OK(hipEventCreate(&stop));
    fillHost(host0, n, 1);
    fillHost(host1, n, 2);
  }

  void freeAll() {
    hipEventDestroy(stop);
    hipEventDestroy(start);
    hipStreamDestroy(s1);
    hipStreamDestroy(s0);
    hipFree(dev2);
    hipFree(dev1);
    hipFree(dev0);
    hipHostFree(check);
    hipHostFree(host1);
    hipHostFree(host0);
  }

  size_t bytes() const { return sizeof(float) * static_cast<size_t>(n); }
};

static void provision(Buf &b, Arm arm) {
  size_t bytes = b.bytes();
  if (arm == Arm::HtoD)
    return;
  HIP_OK(hipMemcpyAsync(b.dev0, b.host0, bytes, hipMemcpyHostToDevice, b.s0));
  HIP_OK(hipMemcpyAsync(b.dev1, b.host1, bytes, hipMemcpyHostToDevice, b.s0));
  HIP_OK(hipStreamSynchronize(b.s0));
}

static void runArm(Buf &b, Arm arm, int k) {
  size_t bytes = b.bytes();
  switch (arm) {
  case Arm::Compute:
    elemwiseLaunch(b.dev0, b.dev2, b.n, k, b.s0);
    HIP_OK(hipStreamSynchronize(b.s0));
    break;
  case Arm::HtoD:
    HIP_OK(hipMemcpyAsync(b.dev0, b.host0, bytes, hipMemcpyHostToDevice, b.s0));
    HIP_OK(hipStreamSynchronize(b.s0));
    break;
  case Arm::DtoH:
    HIP_OK(hipMemcpyAsync(b.host1, b.dev0, bytes, hipMemcpyDeviceToHost, b.s0));
    HIP_OK(hipStreamSynchronize(b.s0));
    break;
  case Arm::ComputeHtoD:
    elemwiseLaunch(b.dev1, b.dev2, b.n, k, b.s0);
    HIP_OK(hipMemcpyAsync(b.dev0, b.host0, bytes, hipMemcpyHostToDevice, b.s1));
    HIP_OK(hipStreamSynchronize(b.s0));
    HIP_OK(hipStreamSynchronize(b.s1));
    break;
  case Arm::ComputeCompute:
    elemwiseLaunch(b.dev0, b.dev2, b.n, k, b.s0);
    elemwiseLaunch(b.dev1, b.dev1, b.n, k, b.s1);
    HIP_OK(hipStreamSynchronize(b.s0));
    HIP_OK(hipStreamSynchronize(b.s1));
    break;
  case Arm::HtoDDtoH:
    HIP_OK(hipMemcpyAsync(b.dev0, b.host0, bytes, hipMemcpyHostToDevice, b.s0));
    HIP_OK(hipMemcpyAsync(b.host1, b.dev1, bytes, hipMemcpyDeviceToHost, b.s1));
    HIP_OK(hipStreamSynchronize(b.s0));
    HIP_OK(hipStreamSynchronize(b.s1));
    break;
  }
}

static bool closeEnough(float a, float b) {
  float d = std::fabs(a - b);
  return d <= 1e-3f * (1.f + std::fabs(b));
}

static bool checkArm(Buf &b, Arm arm, int k) {
  size_t bytes = b.bytes();
  switch (arm) {
  case Arm::Compute:
    HIP_OK(hipMemcpy(b.check, b.dev2, bytes, hipMemcpyDeviceToHost));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.check[i], hostElemwise(b.host0[i], k)))
        return false;
    }
    return true;
  case Arm::HtoD:
    HIP_OK(hipMemcpy(b.check, b.dev0, bytes, hipMemcpyDeviceToHost));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.check[i], b.host0[i]))
        return false;
    }
    return true;
  case Arm::DtoH:
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.host1[i], b.host0[i]))
        return false;
    }
    return true;
  case Arm::ComputeHtoD:
    HIP_OK(hipMemcpy(b.check, b.dev2, bytes, hipMemcpyDeviceToHost));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.check[i], hostElemwise(b.host1[i], k)))
        return false;
    }
    HIP_OK(hipMemcpy(b.check, b.dev0, bytes, hipMemcpyDeviceToHost));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.check[i], b.host0[i]))
        return false;
    }
    return true;
  case Arm::ComputeCompute:
    HIP_OK(hipMemcpy(b.check, b.dev2, bytes, hipMemcpyDeviceToHost));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.check[i], hostElemwise(b.host0[i], k)))
        return false;
    }
    HIP_OK(hipMemcpy(b.check, b.dev1, bytes, hipMemcpyDeviceToHost));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.check[i], hostElemwise(b.host1[i], k)))
        return false;
    }
    return true;
  case Arm::HtoDDtoH:
    HIP_OK(hipMemcpy(b.check, b.dev0, bytes, hipMemcpyDeviceToHost));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.check[i], b.host0[i]))
        return false;
    }
    HIP_OK(hipMemcpy(b.check, b.dev1, bytes, hipMemcpyDeviceToHost));
    for (int i = 0; i < b.n; ++i) {
      if (!closeEnough(b.host1[i], b.check[i]))
        return false;
    }
    return true;
  }
  return false;
}

static double medianUs(std::vector<float> &s) {
  std::sort(s.begin(), s.end());
  return s[s.size() / 2];
}

static double timeArm(Buf &b, Arm arm, int warmup, int reps, int k) {
  auto body = [&]() { runArm(b, arm, k); };
  for (int i = 0; i < warmup; ++i) {
    fillHost(b.host0, b.n, i + 3);
    fillHost(b.host1, b.n, i + 7);
    provision(b, arm);
    body();
  }
  std::vector<float> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    fillHost(b.host0, b.n, i + 11);
    fillHost(b.host1, b.n, i + 19);
    provision(b, arm);
    HIP_OK(hipDeviceSynchronize());
    HIP_OK(hipEventRecord(b.start));
    body();
    HIP_OK(hipEventRecord(b.stop));
    HIP_OK(hipEventSynchronize(b.stop));
    float ms = 0.f;
    HIP_OK(hipEventElapsedTime(&ms, b.start, b.stop));
    samples.push_back(ms * 1000.f);
    if (!checkArm(b, arm, k)) {
      std::fprintf(stderr, "s2c2-rocm-run correctness=0 arm=%s\n",
                   armName(arm));
      std::exit(1);
    }
  }
  return medianUs(samples);
}

static std::string hardwareId() {
  hipDeviceProp_t prop{};
  HIP_OK(hipGetDeviceProperties(&prop, 0));
  std::string arch = prop.gcnArchName;
  if (arch.empty())
    arch = prop.name;
  for (char &c : arch) {
    if (c == ' ' || c == '/')
      c = '-';
  }
  if (arch.empty())
    arch = "amd";
  return arch + ":amd";
}

static void printRecord(const char *pair, const char *relation,
                        const char *constraint, const char *hid) {
  const char *compute = "none";
  const char *transfer = "none";
  const char *direction = "none";
  const char *src = "none";
  const char *dst = "none";
  const char *regime = "underdetermined";
  if (std::strcmp(pair, "C||HtoD") == 0) {
    compute = "rocm_cu";
    transfer = "copy_engine";
    direction = "host_to_device";
    src = "pinned_host";
    dst = "device_memory";
    regime = "bandwidth";
  } else if (std::strcmp(pair, "C||C") == 0) {
    compute = "rocm_cu";
    src = "device_memory";
    dst = "device_memory";
    regime = "occupancy";
  } else if (std::strcmp(pair, "HtoD||DtoH") == 0) {
    transfer = "copy_engine";
    direction = "host_to_device";
    src = "pinned_host";
    dst = "device_memory";
    regime = "bandwidth";
  }
  std::fprintf(stderr,
               "{\"schema_version\":\"1\",\"record_kind\":\"pair\","
               "\"hardware_id\":\"%s\",\"compute_domain\":\"%s\","
               "\"transfer_domain\":\"%s\",\"direction\":\"%s\","
               "\"source_memory_class\":\"%s\","
               "\"destination_memory_class\":\"%s\",\"pair\":\"%s\","
               "\"pair_relation\":\"%s\",\"regime\":\"%s\","
               "\"size_range\":\"n/a\",\"synchronization\":\"%s\","
               "\"pipeline_depth_evidence\":\"n/a\","
               "\"observed_constraint\":\"%s\",\"confidence\":\"measured\","
               "\"note\":\"ROCm pair measurement; topology only\","
               "\"evidence_refs\":\"backend-adapter-rocm.md\","
               "\"v3\":\"not-claimed\",\"cost\":\"unchanged\","
               "\"semantics\":\"unchanged\"}\n",
               hid, compute, transfer, direction, src, dst, pair, relation,
               regime, kSync, constraint);
}

static void usage() {
  std::fprintf(stderr,
               "s2c2-rocm-run --pairs [--n=N] [--k=K] [--warmup=W] [--reps=R]\n"
               "Three pairs only. Do not FileCheck microseconds.\n");
}

int main(int argc, char **argv) {
  int n = 1 << 22;
  int k = 32;
  int warmup = 2;
  int reps = 5;
  bool pairs = false;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a == "--pairs") {
      pairs = true;
    } else if (a.rfind("--n=", 0) == 0) {
      n = std::atoi(argv[i] + 4);
    } else if (a.rfind("--k=", 0) == 0) {
      k = std::atoi(argv[i] + 4);
    } else if (a.rfind("--warmup=", 0) == 0) {
      warmup = std::atoi(argv[i] + 9);
    } else if (a.rfind("--reps=", 0) == 0) {
      reps = std::atoi(argv[i] + 7);
    } else if (a == "--help" || a == "-h") {
      usage();
      return 0;
    } else {
      std::fprintf(stderr, "s2c2-rocm-run: unknown arg %s\n", argv[i]);
      return 1;
    }
  }
  if (!pairs) {
    usage();
    return 1;
  }
  if (n <= 0 || k <= 0) {
    std::fprintf(stderr, "s2c2-rocm-run: n and k must be positive\n");
    return 1;
  }

  std::string hid = hardwareId();
  std::fprintf(stderr,
               "s2c2-rocm-run hardware_id=%s sched=%s map=%s "
               "device=%s sync=%s\n",
               hid.c_str(), kSched, kMap, "gpu", kSync);
  std::fprintf(stderr, "s2c2-rocm-run workload compute=elemwise\n");
  std::fprintf(stderr, "s2c2-rocm-run workload transfer=host_to_device|"
                       "device_to_host\n");
  std::fprintf(stderr,
               "s2c2-rocm-run note workload-semantic-ne-kernel-backend\n");

  Buf b;
  b.alloc(n);
  double tC = timeArm(b, Arm::Compute, warmup, reps, k);
  double tH = timeArm(b, Arm::HtoD, warmup, reps, k);
  double tD = timeArm(b, Arm::DtoH, warmup, reps, k);
  double tR1 = timeArm(b, Arm::ComputeHtoD, warmup, reps, k);
  double tR2 = timeArm(b, Arm::ComputeCompute, warmup, reps, k);
  double tR3 = timeArm(b, Arm::HtoDDtoH, warmup, reps, k);
  b.freeAll();

  struct Cell {
    const char *pair;
    double a, b, par;
  } cells[] = {
      {"C||HtoD", tC, tH, tR1},
      {"C||C", tC, tC, tR2},
      {"HtoD||DtoH", tH, tD, tR3},
  };
  std::fprintf(stderr, "s2c2-rocm-run correctness=1\n");
  std::fprintf(stderr, "s2c2-rocm-run score3=not-applicable cost=unchanged "
                       "semantics=unchanged v3=not-claimed\n");
  for (const auto &c : cells) {
    double mx = c.a > c.b ? c.a : c.b;
    double sum = c.a + c.b;
    double pmax = mx > 0 ? c.par / mx : 0;
    double psum = sum > 0 ? c.par / sum : 0;
    const char *rel = classifyPair(pmax, psum);
    const char *cons = inferConstraint(c.pair, rel);
    std::fprintf(stderr,
                 "s2c2-rocm-run pair=%s pair_relation=%s "
                 "observed_constraint=%s confidence=measured\n",
                 c.pair, rel, cons);
    // Timing is for a later projection. Do not FileCheck microseconds.
    std::fprintf(stderr,
                 "s2c2-rocm-run timing pair=%s a=%.1f b=%.1f par=%.1f "
                 "par_over_max=%.3f par_over_sum=%.3f\n",
                 c.pair, c.a, c.b, c.par, pmax, psum);
    printRecord(c.pair, rel, cons, hid.c_str());
  }
  return 0;
}
