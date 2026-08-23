//===- s2c2_cuda_adapter.cu - timed Pilot stand-ins on CUDA ---------------===//
//
// Realizes frozen Pilot shapes A/B/C for M = (gpu-async, default, gpu).
// Does not parse IR or recompute Score_3.
//
// Build:  nvcc -O2 -std=c++17 s2c2_cuda_adapter.cu -o s2c2-cuda-run
// Run:    ./s2c2-cuda-run --func=all --n=16777216
//
//===----------------------------------------------------------------------===//

#include "AdapterContract.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#include <cuda_runtime.h>

using s2c2::cuda_adapter::kDevice;
using s2c2::cuda_adapter::kMap;
using s2c2::cuda_adapter::kPilotCount;
using s2c2::cuda_adapter::kPilots;
using s2c2::cuda_adapter::kSched;

#define CUDA_OK(expr)                                                          \
  do {                                                                         \
    cudaError_t err__ = (expr);                                                \
    if (err__ != cudaSuccess) {                                                \
      std::fprintf(stderr, "cuda error %s:%d: %s\n", __FILE__, __LINE__,       \
                   cudaGetErrorString(err__));                                 \
      std::exit(2);                                                            \
    }                                                                          \
  } while (0)

__global__ void siluKernel(float *x, int n) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) {
    float v = x[i];
    x[i] = v / (1.f + expf(-v));
  }
}

static void siluLaunch(float *x, int n, cudaStream_t stream, int k) {
  int block = 256;
  int grid = (n + block - 1) / block;
  for (int i = 0; i < k; ++i)
    siluKernel<<<grid, block, 0, stream>>>(x, n);
}

static void siluHost(float *x, int n, int k) {
  for (int r = 0; r < k; ++r) {
    for (int i = 0; i < n; ++i) {
      float v = x[i];
      x[i] = v / (1.f + expf(-v));
    }
  }
}

static void fillHost(float *x, int n, int seed) {
  for (int i = 0; i < n; ++i)
    x[i] = 0.001f * static_cast<float>((i + seed) % 1000);
}

static double medianUs(std::vector<float> &samples) {
  std::sort(samples.begin(), samples.end());
  return samples[samples.size() / 2];
}

enum class Workload { A, B, C };

// Matched-workload overlap probe. Not a Pilot func and not Score_3.
// Remaining work on seq and ovl: 1×HtoD(H) + k×SiLU(D), D ≠ H.
enum class MatchedArm { Off, Seq, Ovl, Copy, Compute };

static Workload parseWork(const char *name) {
  if (std::strcmp(name, "a") == 0 ||
      std::strcmp(name, "pilot_a_ssd_hbm_compute") == 0)
    return Workload::A;
  if (std::strcmp(name, "b") == 0 ||
      std::strcmp(name, "pilot_b_compute_par_comm") == 0)
    return Workload::B;
  if (std::strcmp(name, "c") == 0 ||
      std::strcmp(name, "pilot_c_pipeline_three_stage") == 0)
    return Workload::C;
  std::fprintf(stderr, "s2c2-cuda-run: unknown func %s\n", name);
  std::exit(1);
}

static const s2c2::cuda_adapter::PilotBind &bindOf(Workload w) {
  return kPilots[static_cast<int>(w)];
}

struct GpuBuf {
  float *ssd = nullptr; // pinned host
  float *hbm = nullptr; // device
  float *scratch = nullptr;
  int n = 0;
  cudaStream_t s0 = nullptr;
  cudaStream_t s1 = nullptr;
  cudaEvent_t ev = nullptr;
  cudaEvent_t start = nullptr;
  cudaEvent_t stop = nullptr;

  void alloc(int n_) {
    n = n_;
    CUDA_OK(cudaHostAlloc(&ssd, sizeof(float) * n, cudaHostAllocDefault));
    CUDA_OK(cudaMalloc(&hbm, sizeof(float) * n));
    CUDA_OK(cudaMalloc(&scratch, sizeof(float) * n));
    CUDA_OK(cudaStreamCreate(&s0));
    CUDA_OK(cudaStreamCreate(&s1));
    CUDA_OK(cudaEventCreate(&ev));
    CUDA_OK(cudaEventCreate(&start));
    CUDA_OK(cudaEventCreate(&stop));
    fillHost(ssd, n, 1);
  }

  void freeAll() {
    cudaEventDestroy(stop);
    cudaEventDestroy(start);
    cudaEventDestroy(ev);
    cudaStreamDestroy(s1);
    cudaStreamDestroy(s0);
    cudaFree(scratch);
    cudaFree(hbm);
    cudaFreeHost(ssd);
  }
};

// A: pack SSD → stream → wait → unpack HBM → compute
static void runA(GpuBuf &b, bool provisioned, int k) {
  if (!provisioned) {
    CUDA_OK(cudaMemcpyAsync(b.hbm, b.ssd, sizeof(float) * b.n,
                            cudaMemcpyHostToDevice, b.s0));
    CUDA_OK(cudaEventRecord(b.ev, b.s0));
    CUDA_OK(cudaEventSynchronize(b.ev));
  }
  siluLaunch(b.hbm, b.n, b.s0, k);
  CUDA_OK(cudaStreamSynchronize(b.s0));
}

// B: Concurrent compute ∥ SSD→HBM. No event between streams.
// provisioned: scratch is already on device; timed body is SiLU ∥ HtoD.
static void runB(GpuBuf &b, bool provisioned, int k) {
  if (!provisioned) {
    CUDA_OK(cudaMemcpyAsync(b.scratch, b.ssd, sizeof(float) * b.n,
                            cudaMemcpyHostToDevice, b.s0));
  }
  siluLaunch(b.scratch, b.n, b.s0, k);
  CUDA_OK(cudaMemcpyAsync(b.hbm, b.ssd, sizeof(float) * b.n,
                          cudaMemcpyHostToDevice, b.s1));
  CUDA_OK(cudaStreamSynchronize(b.s0));
  CUDA_OK(cudaStreamSynchronize(b.s1));
}

// C: StageOrder prefetch → compute → writeback
static void runC(GpuBuf &b, bool provisioned, int k) {
  if (!provisioned) {
    CUDA_OK(cudaMemcpyAsync(b.hbm, b.ssd, sizeof(float) * b.n,
                            cudaMemcpyHostToDevice, b.s0));
    CUDA_OK(cudaEventRecord(b.ev, b.s0));
    CUDA_OK(cudaEventSynchronize(b.ev));
  }
  siluLaunch(b.hbm, b.n, b.s0, k);
  CUDA_OK(cudaEventRecord(b.ev, b.s0));
  CUDA_OK(cudaEventSynchronize(b.ev));
  CUDA_OK(cudaMemcpyAsync(b.ssd, b.hbm, sizeof(float) * b.n,
                          cudaMemcpyDeviceToHost, b.s0));
  CUDA_OK(cudaStreamSynchronize(b.s0));
}

static void provisionGpu(GpuBuf &b, Workload w) {
  CUDA_OK(cudaMemcpyAsync(w == Workload::B ? b.scratch : b.hbm, b.ssd,
                          sizeof(float) * b.n, cudaMemcpyHostToDevice, b.s0));
  CUDA_OK(cudaStreamSynchronize(b.s0));
}

static void provisionMatched(GpuBuf &b) {
  CUDA_OK(cudaMemcpyAsync(b.scratch, b.ssd, sizeof(float) * b.n,
                          cudaMemcpyHostToDevice, b.s0));
  CUDA_OK(cudaStreamSynchronize(b.s0));
}

// seq: HtoD(H) then SiLU×k(D) on one stream.
static void runMatchedSeq(GpuBuf &b, int k) {
  CUDA_OK(cudaMemcpyAsync(b.hbm, b.ssd, sizeof(float) * b.n,
                          cudaMemcpyHostToDevice, b.s0));
  siluLaunch(b.scratch, b.n, b.s0, k);
  CUDA_OK(cudaStreamSynchronize(b.s0));
}

// ovl: SiLU×k(D) ∥ HtoD(H). No event between streams.
static void runMatchedOvl(GpuBuf &b, int k) {
  siluLaunch(b.scratch, b.n, b.s0, k);
  CUDA_OK(cudaMemcpyAsync(b.hbm, b.ssd, sizeof(float) * b.n,
                          cudaMemcpyHostToDevice, b.s1));
  CUDA_OK(cudaStreamSynchronize(b.s0));
  CUDA_OK(cudaStreamSynchronize(b.s1));
}

static void runMatchedCopy(GpuBuf &b) {
  CUDA_OK(cudaMemcpyAsync(b.hbm, b.ssd, sizeof(float) * b.n,
                          cudaMemcpyHostToDevice, b.s0));
  CUDA_OK(cudaStreamSynchronize(b.s0));
}

static void runMatchedCompute(GpuBuf &b, int k) {
  siluLaunch(b.scratch, b.n, b.s0, k);
  CUDA_OK(cudaStreamSynchronize(b.s0));
}

static void runMatched(GpuBuf &b, MatchedArm arm, int k) {
  switch (arm) {
  case MatchedArm::Seq:
    runMatchedSeq(b, k);
    break;
  case MatchedArm::Ovl:
    runMatchedOvl(b, k);
    break;
  case MatchedArm::Copy:
    runMatchedCopy(b);
    break;
  case MatchedArm::Compute:
    runMatchedCompute(b, k);
    break;
  case MatchedArm::Off:
    break;
  }
}

static const char *matchedFunc(MatchedArm arm) {
  switch (arm) {
  case MatchedArm::Seq:
    return "matched-seq";
  case MatchedArm::Ovl:
    return "matched-ovl";
  case MatchedArm::Copy:
    return "matched-copy";
  case MatchedArm::Compute:
    return "matched-compute";
  case MatchedArm::Off:
    return "matched-off";
  }
  return "matched-off";
}

static double timeGpu(Workload w, int n, int warmup, int reps, bool provisioned,
                      int k) {
  GpuBuf b;
  b.alloc(n);
  auto body = [&]() {
    switch (w) {
    case Workload::A:
      runA(b, provisioned, k);
      break;
    case Workload::B:
      runB(b, provisioned, k);
      break;
    case Workload::C:
      runC(b, provisioned, k);
      break;
    }
  };
  for (int i = 0; i < warmup; ++i) {
    if (provisioned)
      provisionGpu(b, w);
    body();
  }
  std::vector<float> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    fillHost(b.ssd, n, i + 2);
    if (provisioned)
      provisionGpu(b, w);
    CUDA_OK(cudaDeviceSynchronize());
    CUDA_OK(cudaEventRecord(b.start));
    body();
    CUDA_OK(cudaEventRecord(b.stop));
    CUDA_OK(cudaEventSynchronize(b.stop));
    float ms = 0.f;
    CUDA_OK(cudaEventElapsedTime(&ms, b.start, b.stop));
    samples.push_back(ms * 1000.f);
  }
  b.freeAll();
  return medianUs(samples);
}

static void runAHost(float *ssd, float *hbm, int n, bool provisioned, int k) {
  if (!provisioned)
    std::memcpy(hbm, ssd, sizeof(float) * n);
  siluHost(hbm, n, k);
}

static void runBHost(float *ssd, float *hbm, float *scratch, int n,
                     bool provisioned, int k) {
  std::thread compute([&]() {
    if (!provisioned)
      std::memcpy(scratch, ssd, sizeof(float) * n);
    siluHost(scratch, n, k);
  });
  std::thread comm([&]() { std::memcpy(hbm, ssd, sizeof(float) * n); });
  compute.join();
  comm.join();
}

static void runCHost(float *ssd, float *hbm, int n, bool provisioned, int k) {
  if (!provisioned)
    std::memcpy(hbm, ssd, sizeof(float) * n);
  siluHost(hbm, n, k);
  std::memcpy(ssd, hbm, sizeof(float) * n);
}

static double timeCpu(Workload w, int n, int warmup, int reps, bool provisioned,
                      int k) {
  std::vector<float> ssd(n), hbm(n), scratch(n);
  fillHost(ssd.data(), n, 1);
  auto body = [&]() {
    switch (w) {
    case Workload::A:
      runAHost(ssd.data(), hbm.data(), n, provisioned, k);
      break;
    case Workload::B:
      runBHost(ssd.data(), hbm.data(), scratch.data(), n, provisioned, k);
      break;
    case Workload::C:
      runCHost(ssd.data(), hbm.data(), n, provisioned, k);
      break;
    }
  };
  auto provision = [&]() {
    if (w == Workload::B)
      std::memcpy(scratch.data(), ssd.data(), sizeof(float) * n);
    else
      std::memcpy(hbm.data(), ssd.data(), sizeof(float) * n);
  };
  for (int i = 0; i < warmup; ++i) {
    if (provisioned)
      provision();
    body();
  }
  std::vector<float> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    fillHost(ssd.data(), n, i + 2);
    if (provisioned)
      provision();
    auto t0 = std::chrono::steady_clock::now();
    body();
    auto t1 = std::chrono::steady_clock::now();
    samples.push_back(std::chrono::duration<float, std::micro>(t1 - t0).count());
  }
  return medianUs(samples);
}

// Loaded libcudart version. Not nvidia-smi "CUDA Version" and not nvcc.
static void printCudaRuntimeVersion() {
  int v = 0;
  cudaError_t err = cudaRuntimeGetVersion(&v);
  if (err != cudaSuccess) {
    std::fprintf(stderr, "s2c2-cuda-adapter cuda_runtime_version=unavailable\n");
    return;
  }
  std::fprintf(stderr, "s2c2-cuda-adapter cuda_runtime_version=%d\n", v);
}

static void printResult(const s2c2::cuda_adapter::PilotBind &p, const char *dev,
                        int n, bool provisioned, int k, double us) {
  std::fprintf(stderr,
               "s2c2-cuda-adapter func=%s sched=%s map=%s device=%s "
               "n=%d provisioned=%d k=%d score3_total=%d latency_us=%.1f\n",
               p.func, kSched, kMap, dev, n, provisioned ? 1 : 0, k,
               p.score3Total, us);
}

// score3_total=0 is a wire placeholder. Matched records store an
// empty score3; they are not a Score_3 case.
static void printMatched(MatchedArm arm, const char *dev, int n, int k,
                         double us) {
  std::fprintf(stderr,
               "s2c2-cuda-adapter func=%s sched=%s map=%s device=%s "
               "n=%d provisioned=1 k=%d score3_total=0 latency_us=%.1f\n",
               matchedFunc(arm), kSched, kMap, dev, n, k, us);
}

static double timeMatchedArm(GpuBuf &b, MatchedArm arm, int warmup, int reps,
                             int k) {
  auto body = [&]() { runMatched(b, arm, k); };
  for (int i = 0; i < warmup; ++i) {
    provisionMatched(b);
    body();
  }
  std::vector<float> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    fillHost(b.ssd, b.n, i + 2);
    provisionMatched(b);
    CUDA_OK(cudaDeviceSynchronize());
    CUDA_OK(cudaEventRecord(b.start));
    body();
    CUDA_OK(cudaEventRecord(b.stop));
    CUDA_OK(cudaEventSynchronize(b.stop));
    float ms = 0.f;
    CUDA_OK(cudaEventElapsedTime(&ms, b.start, b.stop));
    samples.push_back(ms * 1000.f);
  }
  return medianUs(samples);
}

static MatchedArm parseMatched(const char *name) {
  if (std::strcmp(name, "off") == 0)
    return MatchedArm::Off;
  if (std::strcmp(name, "seq") == 0)
    return MatchedArm::Seq;
  if (std::strcmp(name, "ovl") == 0)
    return MatchedArm::Ovl;
  if (std::strcmp(name, "copy") == 0)
    return MatchedArm::Copy;
  if (std::strcmp(name, "compute") == 0)
    return MatchedArm::Compute;
  if (std::strcmp(name, "all") == 0)
    return MatchedArm::Off; // handled as a list in main
  std::fprintf(stderr, "s2c2-cuda-run: unknown --matched %s\n", name);
  std::exit(1);
}

int main(int argc, char **argv) {
  const char *func = "all";
  const char *device = kDevice;
  const char *matchedArg = "off";
  int n = 1 << 24;
  int warmup = 5;
  int reps = 21;
  int k = 1;
  bool provisioned = false;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a.rfind("--func=", 0) == 0)
      func = argv[i] + 7;
    else if (a.rfind("--device=", 0) == 0)
      device = argv[i] + 9;
    else if (a.rfind("--n=", 0) == 0)
      n = std::atoi(argv[i] + 4);
    else if (a.rfind("--warmup=", 0) == 0)
      warmup = std::atoi(argv[i] + 9);
    else if (a.rfind("--reps=", 0) == 0)
      reps = std::atoi(argv[i] + 7);
    else if (a.rfind("--k=", 0) == 0)
      k = std::atoi(argv[i] + 4);
    else if (a.rfind("--matched=", 0) == 0)
      matchedArg = argv[i] + 10;
    else if (a == "--provisioned")
      provisioned = true;
    else if (a == "--print-meta") {
      printCudaRuntimeVersion();
      return 0;
    }
    else if (a == "--help" || a == "-h") {
      std::fprintf(stderr,
                   "s2c2-cuda-run --func=all|a|b|c --device=gpu|cpu "
                   "--n=N --k=K --provisioned --warmup=W --reps=R\n"
                   "s2c2-cuda-run --matched=off|seq|ovl|copy|compute|all "
                   "--device=gpu --n=N --k=K\n"
                   "s2c2-cuda-run --print-meta\n");
      return 0;
    } else {
      std::fprintf(stderr, "s2c2-cuda-run: unknown arg %s\n", argv[i]);
      return 1;
    }
  }
  if (n <= 0 || warmup < 0 || reps <= 0 || k <= 0) {
    std::fprintf(stderr, "s2c2-cuda-run: bad numeric arg\n");
    return 1;
  }

  bool gpu = std::strcmp(device, "gpu") == 0;
  bool cpu = std::strcmp(device, "cpu") == 0;
  if (!gpu && !cpu) {
    std::fprintf(stderr, "s2c2-cuda-run: device must be gpu or cpu\n");
    return 1;
  }

  bool matchedAll = std::strcmp(matchedArg, "all") == 0;
  MatchedArm matched = parseMatched(matchedArg);
  if (matchedAll || matched != MatchedArm::Off) {
    if (!gpu) {
      std::fprintf(stderr, "s2c2-cuda-run: --matched is gpu only\n");
      return 1;
    }
    int count = 0;
    CUDA_OK(cudaGetDeviceCount(&count));
    if (count < 1) {
      std::fprintf(stderr, "s2c2-cuda-run: no CUDA device\n");
      return 2;
    }
    std::vector<MatchedArm> arms;
    if (matchedAll) {
      arms = {MatchedArm::Seq, MatchedArm::Ovl, MatchedArm::Copy,
              MatchedArm::Compute};
    } else {
      arms = {matched};
    }
    GpuBuf b;
    b.alloc(n);
    for (MatchedArm arm : arms) {
      double us = timeMatchedArm(b, arm, warmup, reps, k);
      printMatched(arm, "gpu", n, k, us);
    }
    b.freeAll();
    std::fprintf(stderr, "s2c2-cuda-adapter v3=not-claimed\n");
    return 0;
  }

  std::vector<Workload> works;
  if (std::strcmp(func, "all") == 0) {
    works = {Workload::A, Workload::B, Workload::C};
  } else {
    works = {parseWork(func)};
  }

  if (gpu) {
    int count = 0;
    CUDA_OK(cudaGetDeviceCount(&count));
    if (count < 1) {
      std::fprintf(stderr, "s2c2-cuda-run: no CUDA device\n");
      return 2;
    }
  }

  for (Workload w : works) {
    const auto &p = bindOf(w);
    double us = gpu ? timeGpu(w, n, warmup, reps, provisioned, k)
                    : timeCpu(w, n, warmup, reps, provisioned, k);
    printResult(p, gpu ? "gpu" : "cpu", n, provisioned, k, us);
  }
  std::fprintf(stderr, "s2c2-cuda-adapter v3=not-claimed\n");
  return 0;
}
