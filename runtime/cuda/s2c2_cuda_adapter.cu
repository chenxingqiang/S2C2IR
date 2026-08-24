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

// Grid-stride block reduce. Memory-bound stand-in; not a Cost op.
__global__ void reduceKernel(const float *x, float *partial, int n) {
  __shared__ float s[256];
  float v = 0.f;
  for (int j = blockIdx.x * blockDim.x + threadIdx.x; j < n;
       j += blockDim.x * gridDim.x)
    v += x[j];
  s[threadIdx.x] = v;
  __syncthreads();
  for (int stride = 128; stride > 0; stride >>= 1) {
    if (threadIdx.x < stride)
      s[threadIdx.x] += s[threadIdx.x + stride];
    __syncthreads();
  }
  if (threadIdx.x == 0)
    partial[blockIdx.x] = s[0];
}

#define S2C2_TILE 16

// Tiled GEMM stand-in. N is the matrix dimension.
__global__ void matmulKernel(const float *a, const float *b, float *c, int n) {
  __shared__ float as[S2C2_TILE][S2C2_TILE];
  __shared__ float bs[S2C2_TILE][S2C2_TILE];
  int row = blockIdx.y * S2C2_TILE + threadIdx.y;
  int col = blockIdx.x * S2C2_TILE + threadIdx.x;
  float acc = 0.f;
  for (int t = 0; t < n; t += S2C2_TILE) {
    as[threadIdx.y][threadIdx.x] =
        (row < n && t + threadIdx.x < n) ? a[row * n + t + threadIdx.x] : 0.f;
    bs[threadIdx.y][threadIdx.x] =
        (t + threadIdx.y < n && col < n) ? b[(t + threadIdx.y) * n + col] : 0.f;
    __syncthreads();
    for (int k = 0; k < S2C2_TILE; ++k)
      acc += as[threadIdx.y][k] * bs[k][threadIdx.x];
    __syncthreads();
  }
  if (row < n && col < n)
    c[row * n + col] = acc;
}

static void reduceLaunch(float *x, float *partial, int n, cudaStream_t stream) {
  int block = 256;
  int grid = 256;
  reduceKernel<<<grid, block, 0, stream>>>(x, partial, n);
  reduceKernel<<<1, block, 0, stream>>>(partial, x, grid);
}

static void matmulLaunch(float *a, float *b, float *c, int n,
                         cudaStream_t stream) {
  dim3 block(S2C2_TILE, S2C2_TILE);
  dim3 grid((n + S2C2_TILE - 1) / S2C2_TILE,
            (n + S2C2_TILE - 1) / S2C2_TILE);
  matmulKernel<<<grid, block, 0, stream>>>(a, b, c, n);
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

// 4090 capability matrix. Not a Pilot func and not Score_3.
enum class CapArm {
  Off,
  HtoD,
  DtoH,
  HtoDDtoHSeq,
  HtoDDtoHEvent,
  HtoDDtoHPar,
  HtoDHtoDPar,
  DtoHDtoHPar,
  Compute,
  ComputeHtoD,
  ComputeDtoH,
  ComputeCompute,
  EventSync,
  StreamSync,
  DeviceSync,
  Reduction,
  Matmul
};

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

static const char *phaseFunc(MatchedArm arm) {
  switch (arm) {
  case MatchedArm::Seq:
    return "phase-seq";
  case MatchedArm::Ovl:
    return "phase-ovl";
  case MatchedArm::Copy:
    return "phase-copy";
  case MatchedArm::Compute:
    return "phase-compute";
  case MatchedArm::Off:
    return "phase-off";
  }
  return "phase-off";
}

static void printPhase(MatchedArm arm, const char *dev, int n, int k,
                       double us) {
  std::fprintf(stderr,
               "s2c2-cuda-adapter func=%s sched=%s map=%s device=%s "
               "n=%d provisioned=1 k=%d score3_total=0 latency_us=%.1f\n",
               phaseFunc(arm), kSched, kMap, dev, n, k, us);
}

static std::vector<MatchedArm> parsePhaseList(const char *name) {
  if (std::strcmp(name, "off") == 0)
    return {};
  if (std::strcmp(name, "slice") == 0)
    return {MatchedArm::Seq, MatchedArm::Ovl, MatchedArm::Compute};
  if (std::strcmp(name, "all") == 0)
    return {MatchedArm::Copy, MatchedArm::Seq, MatchedArm::Ovl,
            MatchedArm::Compute};
  if (std::strcmp(name, "seq") == 0)
    return {MatchedArm::Seq};
  if (std::strcmp(name, "ovl") == 0)
    return {MatchedArm::Ovl};
  if (std::strcmp(name, "copy") == 0)
    return {MatchedArm::Copy};
  if (std::strcmp(name, "compute") == 0)
    return {MatchedArm::Compute};
  std::fprintf(stderr, "s2c2-cuda-run: unknown --phase %s\n", name);
  std::exit(1);
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

struct CapBuf {
  float *host0 = nullptr;
  float *host1 = nullptr;
  float *host2 = nullptr;
  float *dev0 = nullptr;
  float *dev1 = nullptr;
  float *dev2 = nullptr;
  int n = 0;
  size_t elems = 0;
  cudaStream_t s0 = nullptr;
  cudaStream_t s1 = nullptr;
  cudaEvent_t ev = nullptr;
  cudaEvent_t start = nullptr;
  cudaEvent_t stop = nullptr;

  void alloc(int n_, bool matmul) {
    n = n_;
    elems = matmul ? static_cast<size_t>(n) * static_cast<size_t>(n)
                   : static_cast<size_t>(n);
    size_t bytes = sizeof(float) * elems;
    CUDA_OK(cudaHostAlloc(&host0, bytes, cudaHostAllocDefault));
    CUDA_OK(cudaHostAlloc(&host1, bytes, cudaHostAllocDefault));
    CUDA_OK(cudaHostAlloc(&host2, bytes, cudaHostAllocDefault));
    CUDA_OK(cudaMalloc(&dev0, bytes));
    CUDA_OK(cudaMalloc(&dev1, bytes));
    CUDA_OK(cudaMalloc(&dev2, bytes));
    CUDA_OK(cudaStreamCreate(&s0));
    CUDA_OK(cudaStreamCreate(&s1));
    CUDA_OK(cudaEventCreate(&ev));
    CUDA_OK(cudaEventCreate(&start));
    CUDA_OK(cudaEventCreate(&stop));
    if (matmul) {
      for (size_t i = 0; i < elems; ++i)
        host0[i] = 0.001f * static_cast<float>((i + 1) % 1000);
    } else {
      fillHost(host0, n, 1);
    }
  }

  void freeAll() {
    cudaEventDestroy(stop);
    cudaEventDestroy(start);
    cudaEventDestroy(ev);
    cudaStreamDestroy(s1);
    cudaStreamDestroy(s0);
    cudaFree(dev2);
    cudaFree(dev1);
    cudaFree(dev0);
    cudaFreeHost(host2);
    cudaFreeHost(host1);
    cudaFreeHost(host0);
  }

  size_t bytes() const { return sizeof(float) * elems; }
};

static const char *capFunc(CapArm arm) {
  switch (arm) {
  case CapArm::HtoD:
    return "cap-htod";
  case CapArm::DtoH:
    return "cap-dtoh";
  case CapArm::HtoDDtoHSeq:
    return "cap-htod-dtoh-seq";
  case CapArm::HtoDDtoHEvent:
    return "cap-htod-dtoh-event";
  case CapArm::HtoDDtoHPar:
    return "cap-htod-dtoh-par";
  case CapArm::HtoDHtoDPar:
    return "cap-htod-htod-par";
  case CapArm::DtoHDtoHPar:
    return "cap-dtoh-dtoh-par";
  case CapArm::Compute:
    return "cap-compute";
  case CapArm::ComputeHtoD:
    return "cap-compute-htod";
  case CapArm::ComputeDtoH:
    return "cap-compute-dtoh";
  case CapArm::ComputeCompute:
    return "cap-compute-compute";
  case CapArm::EventSync:
    return "cap-event-sync";
  case CapArm::StreamSync:
    return "cap-stream-sync";
  case CapArm::DeviceSync:
    return "cap-device-sync";
  case CapArm::Reduction:
    return "cap-reduction";
  case CapArm::Matmul:
    return "cap-matmul";
  case CapArm::Off:
    return "cap-off";
  }
  return "cap-off";
}

static bool capIsSync(CapArm arm) {
  return arm == CapArm::EventSync || arm == CapArm::StreamSync ||
         arm == CapArm::DeviceSync;
}

static bool capIsCompute(CapArm arm) {
  return arm == CapArm::Compute || arm == CapArm::ComputeHtoD ||
         arm == CapArm::ComputeDtoH || arm == CapArm::ComputeCompute ||
         arm == CapArm::Reduction || arm == CapArm::Matmul;
}

static int capInner(CapArm arm, int n) {
  if (capIsSync(arm))
    return 200;
  if (capIsCompute(arm))
    return 1;
  size_t bytes = sizeof(float) * static_cast<size_t>(n);
  if (bytes <= 4 * 1024)
    return 200;
  if (bytes <= 64 * 1024)
    return 50;
  if (bytes <= 1024 * 1024)
    return 10;
  return 1;
}

static void provisionCap(CapBuf &b, CapArm arm) {
  if (arm == CapArm::Matmul) {
    CUDA_OK(cudaMemcpyAsync(b.dev0, b.host0, b.bytes(),
                            cudaMemcpyHostToDevice, b.s0));
    CUDA_OK(cudaMemcpyAsync(b.dev1, b.host0, b.bytes(),
                            cudaMemcpyHostToDevice, b.s0));
    CUDA_OK(cudaStreamSynchronize(b.s0));
    return;
  }
  if (capIsSync(arm) || arm == CapArm::HtoD || arm == CapArm::HtoDHtoDPar)
    return;
  CUDA_OK(cudaMemcpyAsync(b.dev0, b.host0, b.bytes(), cudaMemcpyHostToDevice,
                          b.s0));
  CUDA_OK(cudaMemcpyAsync(b.dev1, b.host0, b.bytes(), cudaMemcpyHostToDevice,
                          b.s0));
  CUDA_OK(cudaStreamSynchronize(b.s0));
}

static void runCap(CapBuf &b, CapArm arm, int k) {
  size_t bytes = b.bytes();
  switch (arm) {
  case CapArm::HtoD:
    CUDA_OK(cudaMemcpyAsync(b.dev0, b.host0, bytes, cudaMemcpyHostToDevice,
                            b.s0));
    CUDA_OK(cudaStreamSynchronize(b.s0));
    break;
  case CapArm::DtoH:
    CUDA_OK(cudaMemcpyAsync(b.host1, b.dev0, bytes, cudaMemcpyDeviceToHost,
                            b.s0));
    CUDA_OK(cudaStreamSynchronize(b.s0));
    break;
  case CapArm::HtoDDtoHSeq:
    CUDA_OK(cudaMemcpyAsync(b.dev0, b.host0, bytes, cudaMemcpyHostToDevice,
                            b.s0));
    CUDA_OK(cudaMemcpyAsync(b.host1, b.dev1, bytes, cudaMemcpyDeviceToHost,
                            b.s0));
    CUDA_OK(cudaStreamSynchronize(b.s0));
    break;
  case CapArm::HtoDDtoHEvent:
    CUDA_OK(cudaMemcpyAsync(b.dev0, b.host0, bytes, cudaMemcpyHostToDevice,
                            b.s0));
    CUDA_OK(cudaEventRecord(b.ev, b.s0));
    CUDA_OK(cudaStreamWaitEvent(b.s1, b.ev, 0));
    CUDA_OK(cudaMemcpyAsync(b.host1, b.dev1, bytes, cudaMemcpyDeviceToHost,
                            b.s1));
    CUDA_OK(cudaStreamSynchronize(b.s1));
    break;
  case CapArm::HtoDDtoHPar:
    CUDA_OK(cudaMemcpyAsync(b.dev0, b.host0, bytes, cudaMemcpyHostToDevice,
                            b.s0));
    CUDA_OK(cudaMemcpyAsync(b.host1, b.dev1, bytes, cudaMemcpyDeviceToHost,
                            b.s1));
    CUDA_OK(cudaStreamSynchronize(b.s0));
    CUDA_OK(cudaStreamSynchronize(b.s1));
    break;
  case CapArm::HtoDHtoDPar:
    CUDA_OK(cudaMemcpyAsync(b.dev0, b.host0, bytes, cudaMemcpyHostToDevice,
                            b.s0));
    CUDA_OK(cudaMemcpyAsync(b.dev1, b.host0, bytes, cudaMemcpyHostToDevice,
                            b.s1));
    CUDA_OK(cudaStreamSynchronize(b.s0));
    CUDA_OK(cudaStreamSynchronize(b.s1));
    break;
  case CapArm::DtoHDtoHPar:
    CUDA_OK(cudaMemcpyAsync(b.host1, b.dev0, bytes, cudaMemcpyDeviceToHost,
                            b.s0));
    CUDA_OK(cudaMemcpyAsync(b.host2, b.dev1, bytes, cudaMemcpyDeviceToHost,
                            b.s1));
    CUDA_OK(cudaStreamSynchronize(b.s0));
    CUDA_OK(cudaStreamSynchronize(b.s1));
    break;
  case CapArm::Compute:
    siluLaunch(b.dev0, b.n, b.s0, k);
    CUDA_OK(cudaStreamSynchronize(b.s0));
    break;
  case CapArm::ComputeHtoD:
    siluLaunch(b.dev1, b.n, b.s0, k);
    CUDA_OK(cudaMemcpyAsync(b.dev0, b.host0, bytes, cudaMemcpyHostToDevice,
                            b.s1));
    CUDA_OK(cudaStreamSynchronize(b.s0));
    CUDA_OK(cudaStreamSynchronize(b.s1));
    break;
  case CapArm::ComputeDtoH:
    siluLaunch(b.dev1, b.n, b.s0, k);
    CUDA_OK(cudaMemcpyAsync(b.host1, b.dev0, bytes, cudaMemcpyDeviceToHost,
                            b.s1));
    CUDA_OK(cudaStreamSynchronize(b.s0));
    CUDA_OK(cudaStreamSynchronize(b.s1));
    break;
  case CapArm::ComputeCompute:
    siluLaunch(b.dev0, b.n, b.s0, k);
    siluLaunch(b.dev1, b.n, b.s1, k);
    CUDA_OK(cudaStreamSynchronize(b.s0));
    CUDA_OK(cudaStreamSynchronize(b.s1));
    break;
  case CapArm::EventSync:
    CUDA_OK(cudaEventRecord(b.ev, b.s0));
    CUDA_OK(cudaEventSynchronize(b.ev));
    break;
  case CapArm::StreamSync:
    CUDA_OK(cudaStreamSynchronize(b.s0));
    break;
  case CapArm::DeviceSync:
    CUDA_OK(cudaDeviceSynchronize());
    break;
  case CapArm::Reduction:
    reduceLaunch(b.dev0, b.dev1, b.n, b.s0);
    CUDA_OK(cudaStreamSynchronize(b.s0));
    break;
  case CapArm::Matmul:
    matmulLaunch(b.dev0, b.dev1, b.dev2, b.n, b.s0);
    CUDA_OK(cudaStreamSynchronize(b.s0));
    break;
  case CapArm::Off:
    break;
  }
}

static void printCap(CapArm arm, const char *dev, int n, int k, double us) {
  std::fprintf(stderr,
               "s2c2-cuda-adapter func=%s sched=%s map=%s device=%s "
               "n=%d provisioned=1 k=%d score3_total=0 latency_us=%.1f\n",
               capFunc(arm), kSched, kMap, dev, n, k, us);
}

static double timeCapArm(CapBuf &b, CapArm arm, int warmup, int reps, int k) {
  int inner = capInner(arm, b.n);
  auto body = [&]() {
    for (int j = 0; j < inner; ++j)
      runCap(b, arm, k);
  };
  for (int i = 0; i < warmup; ++i) {
    provisionCap(b, arm);
    body();
  }
  std::vector<float> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    if (arm == CapArm::Matmul) {
      for (size_t j = 0; j < b.elems; ++j)
        b.host0[j] = 0.001f * static_cast<float>((j + i + 2) % 1000);
    } else if (!capIsSync(arm)) {
      fillHost(b.host0, b.n, i + 2);
    }
    provisionCap(b, arm);
    CUDA_OK(cudaDeviceSynchronize());
    CUDA_OK(cudaEventRecord(b.start));
    body();
    CUDA_OK(cudaEventRecord(b.stop));
    CUDA_OK(cudaEventSynchronize(b.stop));
    float ms = 0.f;
    CUDA_OK(cudaEventElapsedTime(&ms, b.start, b.stop));
    samples.push_back(ms * 1000.f / static_cast<float>(inner));
  }
  return medianUs(samples);
}

static CapArm parseOneCap(const char *name) {
  if (std::strcmp(name, "htod") == 0)
    return CapArm::HtoD;
  if (std::strcmp(name, "dtoh") == 0)
    return CapArm::DtoH;
  if (std::strcmp(name, "htod-dtoh-seq") == 0)
    return CapArm::HtoDDtoHSeq;
  if (std::strcmp(name, "htod-dtoh-event") == 0)
    return CapArm::HtoDDtoHEvent;
  if (std::strcmp(name, "htod-dtoh-par") == 0)
    return CapArm::HtoDDtoHPar;
  if (std::strcmp(name, "htod-htod-par") == 0)
    return CapArm::HtoDHtoDPar;
  if (std::strcmp(name, "dtoh-dtoh-par") == 0)
    return CapArm::DtoHDtoHPar;
  if (std::strcmp(name, "compute") == 0)
    return CapArm::Compute;
  if (std::strcmp(name, "compute-htod") == 0)
    return CapArm::ComputeHtoD;
  if (std::strcmp(name, "compute-dtoh") == 0)
    return CapArm::ComputeDtoH;
  if (std::strcmp(name, "compute-compute") == 0)
    return CapArm::ComputeCompute;
  if (std::strcmp(name, "event-sync") == 0)
    return CapArm::EventSync;
  if (std::strcmp(name, "stream-sync") == 0)
    return CapArm::StreamSync;
  if (std::strcmp(name, "device-sync") == 0)
    return CapArm::DeviceSync;
  if (std::strcmp(name, "reduction") == 0)
    return CapArm::Reduction;
  if (std::strcmp(name, "matmul") == 0)
    return CapArm::Matmul;
  std::fprintf(stderr, "s2c2-cuda-run: unknown --cap %s\n", name);
  std::exit(1);
}

static std::vector<CapArm> parseCapList(const char *name) {
  if (std::strcmp(name, "off") == 0)
    return {};
  if (std::strcmp(name, "pairs") == 0)
    return {CapArm::HtoD,         CapArm::DtoH,          CapArm::HtoDDtoHSeq,
            CapArm::HtoDDtoHEvent, CapArm::HtoDDtoHPar, CapArm::HtoDHtoDPar,
            CapArm::DtoHDtoHPar, CapArm::Compute,       CapArm::ComputeHtoD,
            CapArm::ComputeDtoH, CapArm::ComputeCompute};
  if (std::strcmp(name, "sync") == 0)
    return {CapArm::EventSync, CapArm::StreamSync, CapArm::DeviceSync};
  if (std::strcmp(name, "intensity") == 0)
    return {CapArm::Compute, CapArm::Reduction};
  if (std::strcmp(name, "all") == 0) {
    auto arms = parseCapList("pairs");
    auto sync = parseCapList("sync");
    arms.insert(arms.end(), sync.begin(), sync.end());
    return arms;
  }
  return {parseOneCap(name)};
}

int main(int argc, char **argv) {
  const char *func = "all";
  const char *device = kDevice;
  const char *matchedArg = "off";
  const char *capArg = "off";
  const char *phaseArg = "off";
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
    else if (a.rfind("--cap=", 0) == 0)
      capArg = argv[i] + 6;
    else if (a.rfind("--phase=", 0) == 0)
      phaseArg = argv[i] + 8;
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
                   "s2c2-cuda-run --cap=htod|dtoh|pairs|sync|intensity|all "
                   "--device=gpu --n=N --k=K\n"
                   "s2c2-cuda-run --phase=copy|compute|seq|ovl|slice|all "
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

  std::vector<CapArm> capArms = parseCapList(capArg);
  std::vector<MatchedArm> phaseArms = parsePhaseList(phaseArg);
  bool matchedAll = std::strcmp(matchedArg, "all") == 0;
  MatchedArm matched = parseMatched(matchedArg);
  bool matchedOn = matchedAll || matched != MatchedArm::Off;
  if (!capArms.empty() && matchedOn) {
    std::fprintf(stderr, "s2c2-cuda-run: --cap and --matched cannot combine\n");
    return 1;
  }
  if (!phaseArms.empty() && (matchedOn || !capArms.empty())) {
    std::fprintf(stderr,
                 "s2c2-cuda-run: --phase cannot combine with --matched or --cap\n");
    return 1;
  }
  if (!phaseArms.empty()) {
    if (!gpu) {
      std::fprintf(stderr, "s2c2-cuda-run: --phase is gpu only\n");
      return 1;
    }
    int count = 0;
    CUDA_OK(cudaGetDeviceCount(&count));
    if (count < 1) {
      std::fprintf(stderr, "s2c2-cuda-run: no CUDA device\n");
      return 2;
    }
    GpuBuf b;
    b.alloc(n);
    for (MatchedArm arm : phaseArms) {
      double us = timeMatchedArm(b, arm, warmup, reps, k);
      printPhase(arm, "gpu", n, k, us);
    }
    b.freeAll();
    std::fprintf(stderr, "s2c2-cuda-adapter v3=not-claimed\n");
    return 0;
  }
  if (!capArms.empty()) {
    if (!gpu) {
      std::fprintf(stderr, "s2c2-cuda-run: --cap is gpu only\n");
      return 1;
    }
    int count = 0;
    CUDA_OK(cudaGetDeviceCount(&count));
    if (count < 1) {
      std::fprintf(stderr, "s2c2-cuda-run: no CUDA device\n");
      return 2;
    }
    bool needMatmul = false;
    bool needVec = false;
    for (CapArm arm : capArms) {
      if (arm == CapArm::Matmul)
        needMatmul = true;
      else
        needVec = true;
    }
    if (needVec) {
      CapBuf b;
      b.alloc(n, false);
      for (CapArm arm : capArms) {
        if (arm == CapArm::Matmul)
          continue;
        double us = timeCapArm(b, arm, warmup, reps, k);
        printCap(arm, "gpu", n, k, us);
      }
      b.freeAll();
    }
    if (needMatmul) {
      CapBuf b;
      b.alloc(n, true);
      double us = timeCapArm(b, CapArm::Matmul, warmup, reps, k);
      printCap(CapArm::Matmul, "gpu", n, k, us);
      b.freeAll();
    }
    std::fprintf(stderr, "s2c2-cuda-adapter v3=not-claimed\n");
    return 0;
  }
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
