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
#include <cmath>
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

enum class PipeArm { Off, Copy, Compute, D1, D2, D3, D4 };

static const int kPipeMaxDepth = 4;

struct PipeBuf {
  float *host = nullptr;
  float *dev[kPipeMaxDepth] = {};
  cudaEvent_t evCopy[kPipeMaxDepth] = {};
  cudaEvent_t evCompute[kPipeMaxDepth] = {};
  cudaStream_t sCopy = nullptr;
  cudaStream_t sCompute = nullptr;
  cudaEvent_t start = nullptr;
  cudaEvent_t stop = nullptr;
  int n = 0;
  int tiles = 0;
  int tileN = 0;

  void alloc(int n_, int tiles_) {
    n = n_;
    tiles = tiles_;
    tileN = n / tiles;
    CUDA_OK(cudaHostAlloc(&host, sizeof(float) * n, cudaHostAllocDefault));
    for (int i = 0; i < kPipeMaxDepth; ++i) {
      CUDA_OK(cudaMalloc(&dev[i], sizeof(float) * tileN));
      CUDA_OK(cudaEventCreate(&evCopy[i]));
      CUDA_OK(cudaEventCreate(&evCompute[i]));
    }
    CUDA_OK(cudaStreamCreate(&sCopy));
    CUDA_OK(cudaStreamCreate(&sCompute));
    CUDA_OK(cudaEventCreate(&start));
    CUDA_OK(cudaEventCreate(&stop));
    fillHost(host, n, 1);
  }

  void freeAll() {
    cudaEventDestroy(stop);
    cudaEventDestroy(start);
    cudaStreamDestroy(sCompute);
    cudaStreamDestroy(sCopy);
    for (int i = 0; i < kPipeMaxDepth; ++i) {
      cudaEventDestroy(evCompute[i]);
      cudaEventDestroy(evCopy[i]);
      cudaFree(dev[i]);
    }
    cudaFreeHost(host);
  }

  size_t tileBytes() const { return sizeof(float) * static_cast<size_t>(tileN); }
};

static const char *pipeFunc(PipeArm arm) {
  switch (arm) {
  case PipeArm::Copy:
    return "pipe-copy";
  case PipeArm::Compute:
    return "pipe-compute";
  case PipeArm::D1:
    return "pipe-d1";
  case PipeArm::D2:
    return "pipe-d2";
  case PipeArm::D3:
    return "pipe-d3";
  case PipeArm::D4:
    return "pipe-d4";
  case PipeArm::Off:
    return "pipe-off";
  }
  return "pipe-off";
}

static int pipeDepthOf(PipeArm arm) {
  switch (arm) {
  case PipeArm::D1:
    return 1;
  case PipeArm::D2:
    return 2;
  case PipeArm::D3:
    return 3;
  case PipeArm::D4:
    return 4;
  default:
    return 0;
  }
}

static void runPipeDepth(PipeBuf &b, int depth, int k) {
  size_t bytes = b.tileBytes();
  for (int i = 0; i < b.tiles; ++i) {
    int slot = i % depth;
    if (i >= depth)
      CUDA_OK(cudaStreamWaitEvent(b.sCopy, b.evCompute[slot], 0));
    CUDA_OK(cudaMemcpyAsync(b.dev[slot], b.host + i * b.tileN, bytes,
                            cudaMemcpyHostToDevice, b.sCopy));
    CUDA_OK(cudaEventRecord(b.evCopy[slot], b.sCopy));
    CUDA_OK(cudaStreamWaitEvent(b.sCompute, b.evCopy[slot], 0));
    siluLaunch(b.dev[slot], b.tileN, b.sCompute, k);
    CUDA_OK(cudaEventRecord(b.evCompute[slot], b.sCompute));
  }
  CUDA_OK(cudaStreamSynchronize(b.sCopy));
  CUDA_OK(cudaStreamSynchronize(b.sCompute));
}

static void runPipe(PipeBuf &b, PipeArm arm, int k) {
  int depth = pipeDepthOf(arm);
  if (depth > 0) {
    runPipeDepth(b, depth, k);
    return;
  }
  if (arm == PipeArm::Copy) {
    CUDA_OK(cudaMemcpyAsync(b.dev[0], b.host, b.tileBytes(),
                            cudaMemcpyHostToDevice, b.sCopy));
    CUDA_OK(cudaStreamSynchronize(b.sCopy));
    return;
  }
  if (arm == PipeArm::Compute) {
    siluLaunch(b.dev[0], b.tileN, b.sCompute, k);
    CUDA_OK(cudaStreamSynchronize(b.sCompute));
  }
}

static void provisionPipeCompute(PipeBuf &b) {
  CUDA_OK(cudaMemcpyAsync(b.dev[0], b.host, b.tileBytes(),
                          cudaMemcpyHostToDevice, b.sCopy));
  CUDA_OK(cudaStreamSynchronize(b.sCopy));
}

static void printPipe(PipeArm arm, const char *dev, int n, int k, double us) {
  std::fprintf(stderr,
               "s2c2-cuda-adapter func=%s sched=%s map=%s device=%s "
               "n=%d provisioned=1 k=%d score3_total=0 latency_us=%.1f\n",
               pipeFunc(arm), kSched, kMap, dev, n, k, us);
}

static double timePipeArm(PipeBuf &b, PipeArm arm, int warmup, int reps,
                          int k) {
  auto body = [&]() { runPipe(b, arm, k); };
  for (int i = 0; i < warmup; ++i) {
    if (arm == PipeArm::Compute)
      provisionPipeCompute(b);
    body();
  }
  std::vector<float> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    fillHost(b.host, b.n, i + 2);
    if (arm == PipeArm::Compute)
      provisionPipeCompute(b);
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

static std::vector<PipeArm> parsePipeList(const char *name) {
  if (std::strcmp(name, "off") == 0)
    return {};
  if (std::strcmp(name, "depths") == 0)
    return {PipeArm::D1, PipeArm::D2, PipeArm::D3, PipeArm::D4};
  if (std::strcmp(name, "all") == 0)
    return {PipeArm::Copy, PipeArm::Compute, PipeArm::D1, PipeArm::D2,
            PipeArm::D3, PipeArm::D4};
  if (std::strcmp(name, "copy") == 0)
    return {PipeArm::Copy};
  if (std::strcmp(name, "compute") == 0)
    return {PipeArm::Compute};
  if (std::strcmp(name, "d1") == 0)
    return {PipeArm::D1};
  if (std::strcmp(name, "d2") == 0)
    return {PipeArm::D2};
  if (std::strcmp(name, "d3") == 0)
    return {PipeArm::D3};
  if (std::strcmp(name, "d4") == 0)
    return {PipeArm::D4};
  std::fprintf(stderr, "s2c2-cuda-run: unknown --pipe %s\n", name);
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

// V1 CUDA validation. Same remaining work as --matched.
// Does not change A/B/C / --matched / --phase / --cap / --pipe bodies.
enum class ValKind { Copy, Compute, Seq, Ovl };
enum class ValStreamKind { Named, Default };

struct ValArm {
  ValKind kind;
  ValStreamKind stream;
};

struct ValBuf {
  float *host = nullptr;
  float *dest = nullptr;
  float *scratch = nullptr;
  float *check = nullptr;
  int n = 0;
  cudaStream_t sCopy = nullptr;
  cudaStream_t sCompute = nullptr;
  cudaEvent_t start = nullptr;
  cudaEvent_t stop = nullptr;
  bool named = false;

  void alloc(int n_, ValStreamKind sk) {
    n = n_;
    named = sk == ValStreamKind::Named;
    CUDA_OK(cudaHostAlloc(&host, sizeof(float) * n, cudaHostAllocDefault));
    CUDA_OK(cudaHostAlloc(&check, sizeof(float) * n, cudaHostAllocDefault));
    CUDA_OK(cudaMalloc(&dest, sizeof(float) * n));
    CUDA_OK(cudaMalloc(&scratch, sizeof(float) * n));
    if (named) {
      CUDA_OK(cudaStreamCreateWithFlags(&sCopy, cudaStreamNonBlocking));
      CUDA_OK(cudaStreamCreateWithFlags(&sCompute, cudaStreamNonBlocking));
    } else {
      sCopy = nullptr;
      sCompute = nullptr;
    }
    CUDA_OK(cudaEventCreate(&start));
    CUDA_OK(cudaEventCreate(&stop));
    fillHost(host, n, 1);
  }

  void freeAll() {
    cudaEventDestroy(stop);
    cudaEventDestroy(start);
    if (named) {
      cudaStreamDestroy(sCompute);
      cudaStreamDestroy(sCopy);
    }
    cudaFree(scratch);
    cudaFree(dest);
    cudaFreeHost(check);
    cudaFreeHost(host);
  }
};

static const char *valFunc(ValArm arm) {
  if (arm.stream == ValStreamKind::Named) {
    if (arm.kind == ValKind::Copy)
      return "val-copy-named";
    if (arm.kind == ValKind::Compute)
      return "val-compute-named";
    if (arm.kind == ValKind::Seq)
      return "val-seq-named";
    return "val-ovl-named";
  }
  if (arm.kind == ValKind::Copy)
    return "val-copy-default";
  if (arm.kind == ValKind::Compute)
    return "val-compute-default";
  if (arm.kind == ValKind::Seq)
    return "val-seq-default";
  return "val-ovl-default";
}

static const char *valExtraHb(ValStreamKind sk) {
  return sk == ValStreamKind::Named ? "none" : "legacy-default";
}

static void provisionVal(ValBuf &b) {
  CUDA_OK(cudaMemcpyAsync(b.scratch, b.host, sizeof(float) * b.n,
                          cudaMemcpyHostToDevice, b.sCopy));
  CUDA_OK(cudaStreamSynchronize(b.sCopy));
}

static void runVal(ValBuf &b, ValArm arm, int k) {
  size_t bytes = sizeof(float) * static_cast<size_t>(b.n);
  switch (arm.kind) {
  case ValKind::Copy:
    CUDA_OK(cudaMemcpyAsync(b.dest, b.host, bytes, cudaMemcpyHostToDevice,
                            b.sCopy));
    CUDA_OK(cudaStreamSynchronize(b.sCopy));
    break;
  case ValKind::Compute:
    siluLaunch(b.scratch, b.n, b.sCompute, k);
    CUDA_OK(cudaStreamSynchronize(b.sCompute));
    break;
  case ValKind::Seq:
    CUDA_OK(cudaMemcpyAsync(b.dest, b.host, bytes, cudaMemcpyHostToDevice,
                            b.sCopy));
    siluLaunch(b.scratch, b.n, b.sCopy, k);
    CUDA_OK(cudaStreamSynchronize(b.sCopy));
    break;
  case ValKind::Ovl:
    siluLaunch(b.scratch, b.n, b.sCompute, k);
    CUDA_OK(cudaMemcpyAsync(b.dest, b.host, bytes, cudaMemcpyHostToDevice,
                            b.sCopy));
    CUDA_OK(cudaStreamSynchronize(b.sCompute));
    CUDA_OK(cudaStreamSynchronize(b.sCopy));
    break;
  }
}

static float hostSilu(float v) { return v / (1.f + expf(-v)); }

static bool valSpotOk(const float *got, int n, int seed, int siluK) {
  int idx[3] = {0, n / 2, n - 1};
  for (int t = 0; t < 3; ++t) {
    int i = idx[t];
    if (i < 0 || i >= n)
      continue;
    float want = 0.001f * static_cast<float>((i + seed) % 1000);
    for (int r = 0; r < siluK; ++r)
      want = hostSilu(want);
    if (fabsf(got[i] - want) > 1e-3f)
      return false;
  }
  return true;
}

static bool checkVal(ValBuf &b, ValArm arm, int seed, int k) {
  size_t bytes = sizeof(float) * static_cast<size_t>(b.n);
  if (arm.kind == ValKind::Copy || arm.kind == ValKind::Seq ||
      arm.kind == ValKind::Ovl) {
    CUDA_OK(cudaMemcpy(b.check, b.dest, bytes, cudaMemcpyDeviceToHost));
    if (!valSpotOk(b.check, b.n, seed, 0))
      return false;
  }
  if (arm.kind == ValKind::Compute || arm.kind == ValKind::Seq ||
      arm.kind == ValKind::Ovl) {
    CUDA_OK(cudaMemcpy(b.check, b.scratch, bytes, cudaMemcpyDeviceToHost));
    if (!valSpotOk(b.check, b.n, seed, k))
      return false;
  }
  return true;
}

static void printVal(ValArm arm, const char *dev, int n, int k, double us) {
  std::fprintf(stderr,
               "s2c2-cuda-adapter func=%s sched=%s map=%s device=%s "
               "n=%d provisioned=1 k=%d score3_total=0 latency_us=%.1f "
               "correct=1 extra_hb=%s\n",
               valFunc(arm), kSched, kMap, dev, n, k, us,
               valExtraHb(arm.stream));
}

static double timeValArm(ValBuf &b, ValArm arm, int warmup, int reps, int k) {
  auto body = [&]() { runVal(b, arm, k); };
  for (int i = 0; i < warmup; ++i) {
    fillHost(b.host, b.n, 1);
    provisionVal(b);
    body();
  }
  std::vector<float> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    int seed = i + 2;
    fillHost(b.host, b.n, seed);
    provisionVal(b);
    CUDA_OK(cudaDeviceSynchronize());
    CUDA_OK(cudaEventRecord(b.start));
    body();
    CUDA_OK(cudaEventRecord(b.stop));
    CUDA_OK(cudaEventSynchronize(b.stop));
    float ms = 0.f;
    CUDA_OK(cudaEventElapsedTime(&ms, b.start, b.stop));
    samples.push_back(ms * 1000.f);
    if (!checkVal(b, arm, seed, k)) {
      std::fprintf(stderr, "s2c2-cuda-run: %s correct=0\n", valFunc(arm));
      std::exit(3);
    }
  }
  return medianUs(samples);
}

static std::vector<ValArm> parseValList(const char *name) {
  auto named = [](ValKind k) {
    return ValArm{k, ValStreamKind::Named};
  };
  auto def = [](ValKind k) {
    return ValArm{k, ValStreamKind::Default};
  };
  if (std::strcmp(name, "off") == 0)
    return {};
  if (std::strcmp(name, "p0") == 0 || std::strcmp(name, "all") == 0)
    return {named(ValKind::Copy), named(ValKind::Compute), named(ValKind::Seq),
            named(ValKind::Ovl),  def(ValKind::Copy),     def(ValKind::Compute),
            def(ValKind::Seq),    def(ValKind::Ovl)};
  if (std::strcmp(name, "named") == 0)
    return {named(ValKind::Copy), named(ValKind::Compute), named(ValKind::Seq),
            named(ValKind::Ovl)};
  if (std::strcmp(name, "default") == 0)
    return {def(ValKind::Copy), def(ValKind::Compute), def(ValKind::Seq),
            def(ValKind::Ovl)};
  if (std::strcmp(name, "copy-named") == 0)
    return {named(ValKind::Copy)};
  if (std::strcmp(name, "compute-named") == 0)
    return {named(ValKind::Compute)};
  if (std::strcmp(name, "seq-named") == 0)
    return {named(ValKind::Seq)};
  if (std::strcmp(name, "ovl-named") == 0)
    return {named(ValKind::Ovl)};
  if (std::strcmp(name, "copy-default") == 0)
    return {def(ValKind::Copy)};
  if (std::strcmp(name, "compute-default") == 0)
    return {def(ValKind::Compute)};
  if (std::strcmp(name, "seq-default") == 0)
    return {def(ValKind::Seq)};
  if (std::strcmp(name, "ovl-default") == 0)
    return {def(ValKind::Ovl)};
  std::fprintf(stderr, "s2c2-cuda-run: unknown --cuda-val %s\n", name);
  std::exit(1);
}

// V2 pinned vs pageable. Named nonblocking only.
// Does not change V1 --cuda-val timed bodies.
enum class ValMemKind { HtoD, DtoH, Compute, OvlHtoD, OvlDtoH };
enum class ValMemRes { Pinned, Pageable, Device };

struct ValMemArm {
  ValMemKind kind;
  ValMemRes res;
};

struct ValMemBuf {
  float *hostPin = nullptr;
  float *hostPage = nullptr;
  float *check = nullptr;
  float *dest = nullptr;
  float *scratch = nullptr;
  int n = 0;
  cudaStream_t sCopy = nullptr;
  cudaStream_t sCompute = nullptr;
  cudaEvent_t start = nullptr;
  cudaEvent_t stop = nullptr;

  float *hostOf(ValMemRes res) const {
    return res == ValMemRes::Pinned ? hostPin : hostPage;
  }

  void alloc(int n_) {
    n = n_;
    size_t bytes = sizeof(float) * static_cast<size_t>(n);
    CUDA_OK(cudaHostAlloc(&hostPin, bytes, cudaHostAllocDefault));
    hostPage = static_cast<float *>(std::malloc(bytes));
    if (!hostPage) {
      std::fprintf(stderr, "s2c2-cuda-run: pageable malloc failed\n");
      std::exit(2);
    }
    CUDA_OK(cudaHostAlloc(&check, bytes, cudaHostAllocDefault));
    CUDA_OK(cudaMalloc(&dest, bytes));
    CUDA_OK(cudaMalloc(&scratch, bytes));
    CUDA_OK(cudaStreamCreateWithFlags(&sCopy, cudaStreamNonBlocking));
    CUDA_OK(cudaStreamCreateWithFlags(&sCompute, cudaStreamNonBlocking));
    CUDA_OK(cudaEventCreate(&start));
    CUDA_OK(cudaEventCreate(&stop));
    fillHost(hostPin, n, 1);
    fillHost(hostPage, n, 1);
  }

  void freeAll() {
    cudaEventDestroy(stop);
    cudaEventDestroy(start);
    cudaStreamDestroy(sCompute);
    cudaStreamDestroy(sCopy);
    cudaFree(scratch);
    cudaFree(dest);
    cudaFreeHost(check);
    cudaFreeHost(hostPin);
    std::free(hostPage);
  }
};

static const char *valMemFunc(ValMemArm arm) {
  if (arm.kind == ValMemKind::Compute)
    return "val-compute-mem";
  if (arm.kind == ValMemKind::HtoD)
    return arm.res == ValMemRes::Pinned ? "val-htod-pinned"
                                        : "val-htod-pageable";
  if (arm.kind == ValMemKind::DtoH)
    return arm.res == ValMemRes::Pinned ? "val-dtoh-pinned"
                                        : "val-dtoh-pageable";
  if (arm.kind == ValMemKind::OvlHtoD)
    return arm.res == ValMemRes::Pinned ? "val-ovl-htod-pin"
                                        : "val-ovl-htod-page";
  return arm.res == ValMemRes::Pinned ? "val-ovl-dtoh-pin"
                                      : "val-ovl-dtoh-page";
}

static const char *valMemExtraHb(ValMemArm arm) {
  bool ovl =
      arm.kind == ValMemKind::OvlHtoD || arm.kind == ValMemKind::OvlDtoH;
  if (ovl && arm.res == ValMemRes::Pageable)
    return "pageable-host";
  return "none";
}

static bool valMemNeedsPoison(ValMemArm arm) {
  return arm.kind == ValMemKind::DtoH || arm.kind == ValMemKind::OvlDtoH;
}

static void provisionValMem(ValMemBuf &b) {
  size_t bytes = sizeof(float) * static_cast<size_t>(b.n);
  CUDA_OK(cudaMemcpyAsync(b.scratch, b.hostPin, bytes, cudaMemcpyHostToDevice,
                          b.sCopy));
  CUDA_OK(cudaMemcpyAsync(b.dest, b.hostPin, bytes, cudaMemcpyHostToDevice,
                          b.sCopy));
  CUDA_OK(cudaStreamSynchronize(b.sCopy));
}

static void runValMem(ValMemBuf &b, ValMemArm arm, int k) {
  size_t bytes = sizeof(float) * static_cast<size_t>(b.n);
  float *h = b.hostOf(arm.res == ValMemRes::Device ? ValMemRes::Pinned
                                                   : arm.res);
  switch (arm.kind) {
  case ValMemKind::HtoD:
    CUDA_OK(cudaMemcpyAsync(b.dest, h, bytes, cudaMemcpyHostToDevice, b.sCopy));
    CUDA_OK(cudaStreamSynchronize(b.sCopy));
    break;
  case ValMemKind::DtoH:
    CUDA_OK(cudaMemcpyAsync(h, b.dest, bytes, cudaMemcpyDeviceToHost, b.sCopy));
    CUDA_OK(cudaStreamSynchronize(b.sCopy));
    break;
  case ValMemKind::Compute:
    siluLaunch(b.scratch, b.n, b.sCompute, k);
    CUDA_OK(cudaStreamSynchronize(b.sCompute));
    break;
  case ValMemKind::OvlHtoD:
    siluLaunch(b.scratch, b.n, b.sCompute, k);
    CUDA_OK(cudaMemcpyAsync(b.dest, h, bytes, cudaMemcpyHostToDevice, b.sCopy));
    CUDA_OK(cudaStreamSynchronize(b.sCompute));
    CUDA_OK(cudaStreamSynchronize(b.sCopy));
    break;
  case ValMemKind::OvlDtoH:
    siluLaunch(b.scratch, b.n, b.sCompute, k);
    CUDA_OK(cudaMemcpyAsync(h, b.dest, bytes, cudaMemcpyDeviceToHost, b.sCopy));
    CUDA_OK(cudaStreamSynchronize(b.sCompute));
    CUDA_OK(cudaStreamSynchronize(b.sCopy));
    break;
  }
}

static bool checkValMem(ValMemBuf &b, ValMemArm arm, int seed, int k) {
  size_t bytes = sizeof(float) * static_cast<size_t>(b.n);
  if (arm.kind == ValMemKind::HtoD || arm.kind == ValMemKind::OvlHtoD) {
    CUDA_OK(cudaMemcpy(b.check, b.dest, bytes, cudaMemcpyDeviceToHost));
    if (!valSpotOk(b.check, b.n, seed, 0))
      return false;
  }
  if (arm.kind == ValMemKind::DtoH || arm.kind == ValMemKind::OvlDtoH) {
    if (!valSpotOk(b.hostOf(arm.res), b.n, seed, 0))
      return false;
  }
  if (arm.kind == ValMemKind::Compute || arm.kind == ValMemKind::OvlHtoD ||
      arm.kind == ValMemKind::OvlDtoH) {
    CUDA_OK(cudaMemcpy(b.check, b.scratch, bytes, cudaMemcpyDeviceToHost));
    if (!valSpotOk(b.check, b.n, seed, k))
      return false;
  }
  return true;
}

static void printValMem(ValMemArm arm, const char *dev, int n, int k,
                        double us) {
  std::fprintf(stderr,
               "s2c2-cuda-adapter func=%s sched=%s map=%s device=%s "
               "n=%d provisioned=1 k=%d score3_total=0 latency_us=%.1f "
               "correct=1 extra_hb=%s\n",
               valMemFunc(arm), kSched, kMap, dev, n, k, us,
               valMemExtraHb(arm));
}

static double timeValMemArm(ValMemBuf &b, ValMemArm arm, int warmup, int reps,
                            int k) {
  auto body = [&]() { runValMem(b, arm, k); };
  for (int i = 0; i < warmup; ++i) {
    fillHost(b.hostPin, b.n, 1);
    fillHost(b.hostPage, b.n, 1);
    provisionValMem(b);
    if (valMemNeedsPoison(arm))
      fillHost(b.hostOf(arm.res), b.n, 7919);
    body();
  }
  std::vector<float> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    int seed = i + 2;
    fillHost(b.hostPin, b.n, seed);
    fillHost(b.hostPage, b.n, seed);
    provisionValMem(b);
    if (valMemNeedsPoison(arm))
      fillHost(b.hostOf(arm.res), b.n, seed + 7919);
    CUDA_OK(cudaDeviceSynchronize());
    CUDA_OK(cudaEventRecord(b.start));
    body();
    CUDA_OK(cudaEventRecord(b.stop));
    CUDA_OK(cudaEventSynchronize(b.stop));
    float ms = 0.f;
    CUDA_OK(cudaEventElapsedTime(&ms, b.start, b.stop));
    samples.push_back(ms * 1000.f);
    if (!checkValMem(b, arm, seed, k)) {
      std::fprintf(stderr, "s2c2-cuda-run: %s correct=0\n", valMemFunc(arm));
      std::exit(3);
    }
  }
  return medianUs(samples);
}

static std::vector<ValMemArm> parseValMemList(const char *name) {
  auto pin = [](ValMemKind k) { return ValMemArm{k, ValMemRes::Pinned}; };
  auto page = [](ValMemKind k) { return ValMemArm{k, ValMemRes::Pageable}; };
  if (std::strcmp(name, "off") == 0)
    return {};
  if (std::strcmp(name, "p0") == 0 || std::strcmp(name, "all") == 0)
    return {pin(ValMemKind::HtoD),        page(ValMemKind::HtoD),
            pin(ValMemKind::DtoH),        page(ValMemKind::DtoH),
            {ValMemKind::Compute, ValMemRes::Device},
            pin(ValMemKind::OvlHtoD),     page(ValMemKind::OvlHtoD),
            pin(ValMemKind::OvlDtoH),     page(ValMemKind::OvlDtoH)};
  if (std::strcmp(name, "htod") == 0)
    return {pin(ValMemKind::HtoD), page(ValMemKind::HtoD)};
  if (std::strcmp(name, "dtoh") == 0)
    return {pin(ValMemKind::DtoH), page(ValMemKind::DtoH)};
  if (std::strcmp(name, "ovl-htod") == 0)
    return {pin(ValMemKind::OvlHtoD), page(ValMemKind::OvlHtoD)};
  if (std::strcmp(name, "ovl-dtoh") == 0)
    return {pin(ValMemKind::OvlDtoH), page(ValMemKind::OvlDtoH)};
  if (std::strcmp(name, "compute") == 0 || std::strcmp(name, "compute-mem") == 0)
    return {{ValMemKind::Compute, ValMemRes::Device}};
  if (std::strcmp(name, "htod-pinned") == 0)
    return {pin(ValMemKind::HtoD)};
  if (std::strcmp(name, "htod-pageable") == 0)
    return {page(ValMemKind::HtoD)};
  if (std::strcmp(name, "dtoh-pinned") == 0)
    return {pin(ValMemKind::DtoH)};
  if (std::strcmp(name, "dtoh-pageable") == 0)
    return {page(ValMemKind::DtoH)};
  if (std::strcmp(name, "ovl-htod-pin") == 0)
    return {pin(ValMemKind::OvlHtoD)};
  if (std::strcmp(name, "ovl-htod-page") == 0)
    return {page(ValMemKind::OvlHtoD)};
  if (std::strcmp(name, "ovl-dtoh-pin") == 0)
    return {pin(ValMemKind::OvlDtoH)};
  if (std::strcmp(name, "ovl-dtoh-page") == 0)
    return {page(ValMemKind::OvlDtoH)};
  std::fprintf(stderr, "s2c2-cuda-run: unknown --cuda-val-mem %s\n", name);
  std::exit(1);
}

// C_light || C_heavy. Named nonblocking only.
// Does not change V1 --cuda-val or V2 --cuda-val-mem timed bodies.
static constexpr int kValCcDim = 1024;

enum class ValCcKind { Silu, Matmul, Seq, Ovl, SiluSilu };

struct ValCcBuf {
  float *hostSilu = nullptr;
  float *hostA = nullptr;
  float *hostB = nullptr;
  float *checkVec = nullptr;
  float *checkMat = nullptr;
  float *dSilu0 = nullptr;
  float *dSilu1 = nullptr;
  float *dA = nullptr;
  float *dB = nullptr;
  float *dC = nullptr;
  int n = 0;
  int dim = kValCcDim;
  cudaStream_t sA = nullptr;
  cudaStream_t sB = nullptr;
  cudaEvent_t start = nullptr;
  cudaEvent_t stop = nullptr;

  void alloc(int n_) {
    n = n_;
    dim = kValCcDim;
    size_t vecBytes = sizeof(float) * static_cast<size_t>(n);
    size_t matBytes = sizeof(float) * static_cast<size_t>(dim) *
                      static_cast<size_t>(dim);
    CUDA_OK(cudaHostAlloc(&hostSilu, vecBytes, cudaHostAllocDefault));
    CUDA_OK(cudaHostAlloc(&hostA, matBytes, cudaHostAllocDefault));
    CUDA_OK(cudaHostAlloc(&hostB, matBytes, cudaHostAllocDefault));
    CUDA_OK(cudaHostAlloc(&checkVec, vecBytes, cudaHostAllocDefault));
    CUDA_OK(cudaHostAlloc(&checkMat, matBytes, cudaHostAllocDefault));
    CUDA_OK(cudaMalloc(&dSilu0, vecBytes));
    CUDA_OK(cudaMalloc(&dSilu1, vecBytes));
    CUDA_OK(cudaMalloc(&dA, matBytes));
    CUDA_OK(cudaMalloc(&dB, matBytes));
    CUDA_OK(cudaMalloc(&dC, matBytes));
    CUDA_OK(cudaStreamCreateWithFlags(&sA, cudaStreamNonBlocking));
    CUDA_OK(cudaStreamCreateWithFlags(&sB, cudaStreamNonBlocking));
    CUDA_OK(cudaEventCreate(&start));
    CUDA_OK(cudaEventCreate(&stop));
    fillHost(hostSilu, n, 1);
    fillHost(hostA, dim * dim, 101);
    fillHost(hostB, dim * dim, 202);
  }

  void freeAll() {
    cudaEventDestroy(stop);
    cudaEventDestroy(start);
    cudaStreamDestroy(sB);
    cudaStreamDestroy(sA);
    cudaFree(dC);
    cudaFree(dB);
    cudaFree(dA);
    cudaFree(dSilu1);
    cudaFree(dSilu0);
    cudaFreeHost(checkMat);
    cudaFreeHost(checkVec);
    cudaFreeHost(hostB);
    cudaFreeHost(hostA);
    cudaFreeHost(hostSilu);
  }
};

static const char *valCcFunc(ValCcKind kind) {
  switch (kind) {
  case ValCcKind::Silu:
    return "val-cc-silu";
  case ValCcKind::Matmul:
    return "val-cc-matmul";
  case ValCcKind::Seq:
    return "val-cc-seq";
  case ValCcKind::Ovl:
    return "val-cc-ovl";
  case ValCcKind::SiluSilu:
    return "val-cc-silu-silu";
  }
  return "val-cc-off";
}

static const char *valCcObservedConstraint(ValCcKind kind) {
  // Candidate label only. Analyzer decides from T_ovl vs T_seq.
  // resource_contention is not extra HB (#60 reserved extra_hb).
  if (kind == ValCcKind::Ovl)
    return "resource_contention";
  return "none";
}

static void provisionValCc(ValCcBuf &b) {
  size_t vecBytes = sizeof(float) * static_cast<size_t>(b.n);
  size_t matBytes = sizeof(float) * static_cast<size_t>(b.dim) *
                    static_cast<size_t>(b.dim);
  CUDA_OK(cudaMemcpyAsync(b.dSilu0, b.hostSilu, vecBytes,
                          cudaMemcpyHostToDevice, b.sA));
  CUDA_OK(cudaMemcpyAsync(b.dSilu1, b.hostSilu, vecBytes,
                          cudaMemcpyHostToDevice, b.sA));
  CUDA_OK(cudaMemcpyAsync(b.dA, b.hostA, matBytes, cudaMemcpyHostToDevice,
                          b.sA));
  CUDA_OK(cudaMemcpyAsync(b.dB, b.hostB, matBytes, cudaMemcpyHostToDevice,
                          b.sA));
  CUDA_OK(cudaStreamSynchronize(b.sA));
}

static void runValCc(ValCcBuf &b, ValCcKind kind, int k, int m) {
  switch (kind) {
  case ValCcKind::Silu:
    siluLaunch(b.dSilu0, b.n, b.sA, k);
    CUDA_OK(cudaStreamSynchronize(b.sA));
    break;
  case ValCcKind::Matmul:
    for (int i = 0; i < m; ++i)
      matmulLaunch(b.dA, b.dB, b.dC, b.dim, b.sB);
    CUDA_OK(cudaStreamSynchronize(b.sB));
    break;
  case ValCcKind::Seq:
    siluLaunch(b.dSilu0, b.n, b.sA, k);
    for (int i = 0; i < m; ++i)
      matmulLaunch(b.dA, b.dB, b.dC, b.dim, b.sA);
    CUDA_OK(cudaStreamSynchronize(b.sA));
    break;
  case ValCcKind::Ovl:
    siluLaunch(b.dSilu0, b.n, b.sA, k);
    for (int i = 0; i < m; ++i)
      matmulLaunch(b.dA, b.dB, b.dC, b.dim, b.sB);
    CUDA_OK(cudaStreamSynchronize(b.sA));
    CUDA_OK(cudaStreamSynchronize(b.sB));
    break;
  case ValCcKind::SiluSilu:
    siluLaunch(b.dSilu0, b.n, b.sA, k);
    siluLaunch(b.dSilu1, b.n, b.sB, k);
    CUDA_OK(cudaStreamSynchronize(b.sA));
    CUDA_OK(cudaStreamSynchronize(b.sB));
    break;
  }
}

static bool matmulSpotOk(const float *got, const float *a, const float *b,
                         int dim) {
  int idx[3][2] = {{0, 0}, {dim / 2, dim / 2}, {dim - 1, dim - 1}};
  for (int t = 0; t < 3; ++t) {
    int row = idx[t][0];
    int col = idx[t][1];
    float want = 0.f;
    for (int k = 0; k < dim; ++k)
      want += a[row * dim + k] * b[k * dim + col];
    float diff = fabsf(got[row * dim + col] - want);
    float scale = fabsf(want) > 1.f ? fabsf(want) : 1.f;
    if (diff > 5e-3f * scale)
      return false;
  }
  return true;
}

static bool checkValCc(ValCcBuf &b, ValCcKind kind, int seed, int k) {
  size_t vecBytes = sizeof(float) * static_cast<size_t>(b.n);
  size_t matBytes = sizeof(float) * static_cast<size_t>(b.dim) *
                    static_cast<size_t>(b.dim);
  if (kind == ValCcKind::Silu || kind == ValCcKind::Seq ||
      kind == ValCcKind::Ovl || kind == ValCcKind::SiluSilu) {
    CUDA_OK(cudaMemcpy(b.checkVec, b.dSilu0, vecBytes, cudaMemcpyDeviceToHost));
    if (!valSpotOk(b.checkVec, b.n, seed, k))
      return false;
  }
  if (kind == ValCcKind::SiluSilu) {
    CUDA_OK(cudaMemcpy(b.checkVec, b.dSilu1, vecBytes, cudaMemcpyDeviceToHost));
    if (!valSpotOk(b.checkVec, b.n, seed, k))
      return false;
  }
  if (kind == ValCcKind::Matmul || kind == ValCcKind::Seq ||
      kind == ValCcKind::Ovl) {
    CUDA_OK(cudaMemcpy(b.checkMat, b.dC, matBytes, cudaMemcpyDeviceToHost));
    if (!matmulSpotOk(b.checkMat, b.hostA, b.hostB, b.dim))
      return false;
  }
  return true;
}

static void printValCc(ValCcKind kind, const char *dev, int n, int k, int m,
                       double us) {
  std::fprintf(stderr,
               "s2c2-cuda-adapter func=%s sched=%s map=%s device=%s "
               "n=%d provisioned=1 k=%d score3_total=0 latency_us=%.1f "
               "correct=1 observed_constraint=%s extra_hb=not-applicable "
               "m=%d dim=%d\n",
               valCcFunc(kind), kSched, kMap, dev, n, k, us,
               valCcObservedConstraint(kind), m, kValCcDim);
}

static double timeValCcArm(ValCcBuf &b, ValCcKind kind, int warmup, int reps,
                           int k, int m) {
  auto body = [&]() { runValCc(b, kind, k, m); };
  for (int i = 0; i < warmup; ++i) {
    fillHost(b.hostSilu, b.n, 1);
    fillHost(b.hostA, b.dim * b.dim, 101);
    fillHost(b.hostB, b.dim * b.dim, 202);
    provisionValCc(b);
    body();
  }
  std::vector<float> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    int seed = i + 2;
    fillHost(b.hostSilu, b.n, seed);
    fillHost(b.hostA, b.dim * b.dim, seed + 100);
    fillHost(b.hostB, b.dim * b.dim, seed + 200);
    provisionValCc(b);
    CUDA_OK(cudaDeviceSynchronize());
    CUDA_OK(cudaEventRecord(b.start));
    body();
    CUDA_OK(cudaEventRecord(b.stop));
    CUDA_OK(cudaEventSynchronize(b.stop));
    float ms = 0.f;
    CUDA_OK(cudaEventElapsedTime(&ms, b.start, b.stop));
    samples.push_back(ms * 1000.f);
    if (!checkValCc(b, kind, seed, k)) {
      std::fprintf(stderr, "s2c2-cuda-run: %s correct=0\n", valCcFunc(kind));
      std::exit(3);
    }
  }
  return medianUs(samples);
}

static std::vector<ValCcKind> parseValCcList(const char *name) {
  if (std::strcmp(name, "off") == 0)
    return {};
  if (std::strcmp(name, "p0") == 0 || std::strcmp(name, "all") == 0)
    return {ValCcKind::Silu, ValCcKind::Matmul, ValCcKind::Seq, ValCcKind::Ovl,
            ValCcKind::SiluSilu};
  if (std::strcmp(name, "silu") == 0)
    return {ValCcKind::Silu};
  if (std::strcmp(name, "matmul") == 0)
    return {ValCcKind::Matmul};
  if (std::strcmp(name, "seq") == 0)
    return {ValCcKind::Seq};
  if (std::strcmp(name, "ovl") == 0)
    return {ValCcKind::Ovl};
  if (std::strcmp(name, "silu-silu") == 0)
    return {ValCcKind::SiluSilu};
  std::fprintf(stderr, "s2c2-cuda-run: unknown --cuda-val-cc %s\n", name);
  std::exit(1);
}

// Async alloc + cross-stream wait. Named nonblocking only.
// Does not change V1 --cuda-val, V2 --cuda-val-mem, or --cuda-val-cc timed bodies.
enum class ValAsyncKind { Copy, Compute, LifeSync, LifeAsync, HbWait };

struct ValAsyncBuf {
  float *host = nullptr;
  float *check = nullptr;
  float *scratch = nullptr;
  int n = 0;
  cudaStream_t sA = nullptr;
  cudaStream_t sB = nullptr;
  cudaEvent_t evReady = nullptr;
  cudaEvent_t evDone = nullptr;
  cudaEvent_t start = nullptr;
  cudaEvent_t stop = nullptr;

  void alloc(int n_) {
    n = n_;
    size_t bytes = sizeof(float) * static_cast<size_t>(n);
    CUDA_OK(cudaHostAlloc(&host, bytes, cudaHostAllocDefault));
    CUDA_OK(cudaHostAlloc(&check, bytes, cudaHostAllocDefault));
    CUDA_OK(cudaMalloc(&scratch, bytes));
    CUDA_OK(cudaStreamCreateWithFlags(&sA, cudaStreamNonBlocking));
    CUDA_OK(cudaStreamCreateWithFlags(&sB, cudaStreamNonBlocking));
    CUDA_OK(cudaEventCreateWithFlags(&evReady, cudaEventDisableTiming));
    CUDA_OK(cudaEventCreateWithFlags(&evDone, cudaEventDisableTiming));
    CUDA_OK(cudaEventCreate(&start));
    CUDA_OK(cudaEventCreate(&stop));
    fillHost(host, n, 1);
  }

  void freeAll() {
    cudaEventDestroy(stop);
    cudaEventDestroy(start);
    cudaEventDestroy(evDone);
    cudaEventDestroy(evReady);
    cudaStreamDestroy(sB);
    cudaStreamDestroy(sA);
    cudaFree(scratch);
    cudaFreeHost(check);
    cudaFreeHost(host);
  }
};

static const char *valAsyncFunc(ValAsyncKind kind) {
  if (kind == ValAsyncKind::Copy)
    return "val-async-copy";
  if (kind == ValAsyncKind::Compute)
    return "val-async-compute";
  if (kind == ValAsyncKind::LifeSync)
    return "val-async-life-sync";
  if (kind == ValAsyncKind::LifeAsync)
    return "val-async-life-async";
  return "val-async-hb";
}

static const char *valAsyncObservedConstraint(ValAsyncKind kind) {
  // Candidate label only. Analyzer decides from T_sync / T_async.
  // Allocator rate is not extra HB (#60 reserved extra_hb).
  return kind == ValAsyncKind::LifeSync ? "allocator_sync" : "none";
}

static void provisionValAsync(ValAsyncBuf &b) {
  size_t bytes = sizeof(float) * static_cast<size_t>(b.n);
  CUDA_OK(cudaMemcpyAsync(b.scratch, b.host, bytes, cudaMemcpyHostToDevice,
                          b.sA));
  CUDA_OK(cudaStreamSynchronize(b.sA));
}

static void runValAsync(ValAsyncBuf &b, ValAsyncKind kind, int k) {
  size_t bytes = sizeof(float) * static_cast<size_t>(b.n);
  float *d = nullptr;
  switch (kind) {
  case ValAsyncKind::Copy:
    CUDA_OK(cudaMemcpyAsync(b.scratch, b.host, bytes, cudaMemcpyHostToDevice,
                            b.sA));
    CUDA_OK(cudaStreamSynchronize(b.sA));
    break;
  case ValAsyncKind::Compute:
    siluLaunch(b.scratch, b.n, b.sA, k);
    CUDA_OK(cudaStreamSynchronize(b.sA));
    break;
  case ValAsyncKind::LifeSync:
    CUDA_OK(cudaMalloc(&d, bytes));
    CUDA_OK(cudaMemcpyAsync(d, b.host, bytes, cudaMemcpyHostToDevice, b.sA));
    siluLaunch(d, b.n, b.sA, k);
    CUDA_OK(cudaMemcpyAsync(b.check, d, bytes, cudaMemcpyDeviceToHost, b.sA));
    CUDA_OK(cudaStreamSynchronize(b.sA));
    CUDA_OK(cudaFree(d));
    break;
  case ValAsyncKind::LifeAsync:
    CUDA_OK(cudaMallocAsync(&d, bytes, b.sA));
    CUDA_OK(cudaMemcpyAsync(d, b.host, bytes, cudaMemcpyHostToDevice, b.sA));
    siluLaunch(d, b.n, b.sA, k);
    CUDA_OK(cudaMemcpyAsync(b.check, d, bytes, cudaMemcpyDeviceToHost, b.sA));
    CUDA_OK(cudaFreeAsync(d, b.sA));
    CUDA_OK(cudaStreamSynchronize(b.sA));
    break;
  case ValAsyncKind::HbWait:
    CUDA_OK(cudaMallocAsync(&d, bytes, b.sA));
    CUDA_OK(cudaMemcpyAsync(d, b.host, bytes, cudaMemcpyHostToDevice, b.sA));
    CUDA_OK(cudaEventRecord(b.evReady, b.sA));
    CUDA_OK(cudaStreamWaitEvent(b.sB, b.evReady, 0));
    siluLaunch(d, b.n, b.sB, k);
    CUDA_OK(cudaEventRecord(b.evDone, b.sB));
    CUDA_OK(cudaStreamWaitEvent(b.sA, b.evDone, 0));
    CUDA_OK(cudaMemcpyAsync(b.check, d, bytes, cudaMemcpyDeviceToHost, b.sA));
    CUDA_OK(cudaFreeAsync(d, b.sA));
    CUDA_OK(cudaStreamSynchronize(b.sA));
    CUDA_OK(cudaStreamSynchronize(b.sB));
    break;
  }
}

static bool checkValAsync(ValAsyncBuf &b, ValAsyncKind kind, int seed, int k) {
  size_t bytes = sizeof(float) * static_cast<size_t>(b.n);
  if (kind == ValAsyncKind::Copy) {
    CUDA_OK(cudaMemcpy(b.check, b.scratch, bytes, cudaMemcpyDeviceToHost));
    return valSpotOk(b.check, b.n, seed, 0);
  }
  if (kind == ValAsyncKind::Compute) {
    CUDA_OK(cudaMemcpy(b.check, b.scratch, bytes, cudaMemcpyDeviceToHost));
    return valSpotOk(b.check, b.n, seed, k);
  }
  return valSpotOk(b.check, b.n, seed, k);
}

static void printValAsync(ValAsyncKind kind, const char *dev, int n, int k,
                          double us) {
  std::fprintf(stderr,
               "s2c2-cuda-adapter func=%s sched=%s map=%s device=%s "
               "n=%d provisioned=1 k=%d score3_total=0 latency_us=%.1f "
               "correct=1 observed_constraint=%s extra_hb=not-applicable\n",
               valAsyncFunc(kind), kSched, kMap, dev, n, k, us,
               valAsyncObservedConstraint(kind));
}

static double timeValAsyncArm(ValAsyncBuf &b, ValAsyncKind kind, int warmup,
                              int reps, int k) {
  auto body = [&]() { runValAsync(b, kind, k); };
  for (int i = 0; i < warmup; ++i) {
    fillHost(b.host, b.n, 1);
    if (kind == ValAsyncKind::Copy || kind == ValAsyncKind::Compute)
      provisionValAsync(b);
    body();
  }
  std::vector<float> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    int seed = i + 2;
    fillHost(b.host, b.n, seed);
    if (kind == ValAsyncKind::Copy || kind == ValAsyncKind::Compute)
      provisionValAsync(b);
    CUDA_OK(cudaDeviceSynchronize());
    CUDA_OK(cudaEventRecord(b.start));
    body();
    CUDA_OK(cudaEventRecord(b.stop));
    CUDA_OK(cudaEventSynchronize(b.stop));
    float ms = 0.f;
    CUDA_OK(cudaEventElapsedTime(&ms, b.start, b.stop));
    samples.push_back(ms * 1000.f);
    if (!checkValAsync(b, kind, seed, k)) {
      std::fprintf(stderr, "s2c2-cuda-run: %s correct=0\n",
                   valAsyncFunc(kind));
      std::exit(3);
    }
  }
  return medianUs(samples);
}

static std::vector<ValAsyncKind> parseValAsyncList(const char *name) {
  if (std::strcmp(name, "off") == 0)
    return {};
  if (std::strcmp(name, "p0") == 0 || std::strcmp(name, "all") == 0)
    return {ValAsyncKind::Copy, ValAsyncKind::Compute, ValAsyncKind::LifeSync,
            ValAsyncKind::LifeAsync, ValAsyncKind::HbWait};
  if (std::strcmp(name, "copy") == 0)
    return {ValAsyncKind::Copy};
  if (std::strcmp(name, "compute") == 0)
    return {ValAsyncKind::Compute};
  if (std::strcmp(name, "life-sync") == 0)
    return {ValAsyncKind::LifeSync};
  if (std::strcmp(name, "life-async") == 0)
    return {ValAsyncKind::LifeAsync};
  if (std::strcmp(name, "hb") == 0 || std::strcmp(name, "hb-wait") == 0)
    return {ValAsyncKind::HbWait};
  std::fprintf(stderr, "s2c2-cuda-run: unknown --cuda-val-async %s\n", name);
  std::exit(1);
}

// Complete SSD+MLP program wall-clock. Same three arms as the 910B
// timed path. Not a Pilot func, not Score_3, not Cost v0.4.
enum class ProgArm { Seq, Evi, Par };

static bool closeEnough(float a, float b) {
  float d = std::fabs(a - b);
  return d <= 1e-3f * (1.f + std::fabs(b));
}

static float hostSilu(float v, int k) {
  for (int i = 0; i < k; ++i)
    v = v / (1.f + expf(-v));
  return v;
}

static void provisionSsd(CapBuf &b) {
  CUDA_OK(cudaMemcpyAsync(b.dev0, b.host0, b.bytes(), cudaMemcpyHostToDevice,
                          b.s0));
  CUDA_OK(cudaMemcpyAsync(b.dev1, b.host1, b.bytes(), cudaMemcpyHostToDevice,
                          b.s0));
  CUDA_OK(cudaStreamSynchronize(b.s0));
}

static void runSsdMlpProgram(CapBuf &prefetch, CapBuf &cc, int kMlp, int kCc,
                             ProgArm arm) {
  size_t pbytes = prefetch.bytes();
  if (arm == ProgArm::Seq) {
    CUDA_OK(cudaMemcpyAsync(prefetch.dev0, prefetch.host0, pbytes,
                            cudaMemcpyHostToDevice, prefetch.s0));
    CUDA_OK(cudaStreamSynchronize(prefetch.s0));
    siluLaunch(prefetch.dev0, prefetch.n, prefetch.s0, kMlp);
    CUDA_OK(cudaStreamSynchronize(prefetch.s0));
    siluLaunch(cc.dev0, cc.n, cc.s0, kCc);
    CUDA_OK(cudaStreamSynchronize(cc.s0));
    siluLaunch(cc.dev1, cc.n, cc.s1, kCc);
    CUDA_OK(cudaStreamSynchronize(cc.s1));
    return;
  }
  siluLaunch(prefetch.dev1, prefetch.n, prefetch.s0, kMlp);
  CUDA_OK(cudaMemcpyAsync(prefetch.dev0, prefetch.host0, pbytes,
                          cudaMemcpyHostToDevice, prefetch.s1));
  CUDA_OK(cudaStreamSynchronize(prefetch.s0));
  CUDA_OK(cudaStreamSynchronize(prefetch.s1));
  if (arm == ProgArm::Evi) {
    siluLaunch(cc.dev0, cc.n, cc.s0, kCc);
    CUDA_OK(cudaStreamSynchronize(cc.s0));
    siluLaunch(cc.dev1, cc.n, cc.s1, kCc);
    CUDA_OK(cudaStreamSynchronize(cc.s1));
    return;
  }
  siluLaunch(cc.dev0, cc.n, cc.s0, kCc);
  siluLaunch(cc.dev1, cc.n, cc.s1, kCc);
  CUDA_OK(cudaStreamSynchronize(cc.s0));
  CUDA_OK(cudaStreamSynchronize(cc.s1));
}

static bool checkDevSilu(CapBuf &b, float *dev, const float *host, int k) {
  CUDA_OK(cudaMemcpy(b.host2, dev, b.bytes(), cudaMemcpyDeviceToHost));
  int step = b.n > 4096 ? b.n / 4096 : 1;
  for (int i = 0; i < b.n; i += step) {
    if (!closeEnough(b.host2[i], hostSilu(host[i], k)))
      return false;
  }
  if (!closeEnough(b.host2[b.n - 1], hostSilu(host[b.n - 1], k)))
    return false;
  return true;
}

static bool checkDevCopy(CapBuf &b, float *dev, const float *host) {
  CUDA_OK(cudaMemcpy(b.host2, dev, b.bytes(), cudaMemcpyDeviceToHost));
  int step = b.n > 4096 ? b.n / 4096 : 1;
  for (int i = 0; i < b.n; i += step) {
    if (!closeEnough(b.host2[i], host[i]))
      return false;
  }
  if (!closeEnough(b.host2[b.n - 1], host[b.n - 1]))
    return false;
  return true;
}

static bool checkSsdMlp(CapBuf &prefetch, CapBuf &cc, int kMlp, int kCc,
                        ProgArm arm) {
  if (arm == ProgArm::Seq) {
    if (!checkDevSilu(prefetch, prefetch.dev0, prefetch.host0, kMlp))
      return false;
  } else {
    if (!checkDevSilu(prefetch, prefetch.dev1, prefetch.host1, kMlp))
      return false;
    if (!checkDevCopy(prefetch, prefetch.dev0, prefetch.host0))
      return false;
  }
  return checkDevSilu(cc, cc.dev0, cc.host0, kCc) &&
         checkDevSilu(cc, cc.dev1, cc.host1, kCc);
}

static double timeSsdMlp(CapBuf &prefetch, CapBuf &cc, int kMlp, int kCc,
                         int warmup, int reps, ProgArm arm) {
  auto prep = [&](int seedA, int seedB) {
    fillHost(prefetch.host0, prefetch.n, seedA);
    fillHost(prefetch.host1, prefetch.n, seedB);
    fillHost(cc.host0, cc.n, seedA + 1);
    fillHost(cc.host1, cc.n, seedB + 1);
    provisionSsd(prefetch);
    provisionSsd(cc);
  };
  for (int i = 0; i < warmup; ++i) {
    prep(i + 3, i + 7);
    runSsdMlpProgram(prefetch, cc, kMlp, kCc, arm);
  }
  std::vector<float> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    prep(i + 11, i + 19);
    auto start = std::chrono::steady_clock::now();
    runSsdMlpProgram(prefetch, cc, kMlp, kCc, arm);
    auto stop = std::chrono::steady_clock::now();
    samples.push_back(static_cast<float>(
        std::chrono::duration<double, std::micro>(stop - start).count()));
    if (!checkSsdMlp(prefetch, cc, kMlp, kCc, arm)) {
      std::fprintf(stderr,
                   "s2c2-cuda-run correctness=0 arm=ssd-mlp-wallclock\n");
      std::exit(1);
    }
  }
  return medianUs(samples);
}

static int runSsdMlpWallclock(int nHtod, int nCc, int kRef, int warmup,
                              int reps) {
  CapBuf prefetch;
  CapBuf cc;
  prefetch.alloc(nHtod, false);
  cc.alloc(nCc, false);
  fillHost(prefetch.host0, prefetch.n, 1);
  fillHost(prefetch.host1, prefetch.n, 2);
  fillHost(cc.host0, cc.n, 1);
  fillHost(cc.host1, cc.n, 2);
  provisionSsd(prefetch);
  provisionSsd(cc);
  siluLaunch(prefetch.dev1, prefetch.n, prefetch.s0, 1);
  siluLaunch(cc.dev0, cc.n, cc.s0, 1);
  siluLaunch(cc.dev1, cc.n, cc.s1, 1);
  CUDA_OK(cudaStreamSynchronize(prefetch.s0));
  CUDA_OK(cudaStreamSynchronize(cc.s0));
  CUDA_OK(cudaStreamSynchronize(cc.s1));

  double tSeq = timeSsdMlp(prefetch, cc, kRef, kRef, warmup, reps, ProgArm::Seq);
  double tEvi = timeSsdMlp(prefetch, cc, kRef, kRef, warmup, reps, ProgArm::Evi);
  double tPar = timeSsdMlp(prefetch, cc, kRef, kRef, warmup, reps, ProgArm::Par);
  double ratio = tSeq > 0.0 ? tEvi / tSeq : 0.0;

  std::fprintf(stderr, "s2c2-cuda-run hardware_id=rtx4090:cuda sched=%s "
                       "map=%s device=gpu sync=named-nonblocking\n",
               kSched, kMap);
  std::fprintf(stderr, "s2c2-cuda-run workload compute=elemwise\n");
  std::fprintf(stderr, "s2c2-cuda-run workload transfer=host_to_device|"
                       "device_to_host\n");
  std::fprintf(stderr,
               "s2c2-cuda-run note workload-semantic-ne-kernel-backend\n");
  std::fprintf(stderr, "s2c2-cuda-run timing=host-wall-clock\n");
  std::fprintf(stderr, "s2c2-cuda-run timing completion=s0,s1\n");
  std::fprintf(stderr, "s2c2-cuda-run ssd-mlp-wallclock=1\n");
  std::fprintf(stderr,
               "s2c2-cuda-run ssd-mlp-wallclock program-measurement=yes\n");
  std::fprintf(stderr, "s2c2-cuda-run ssd-mlp-wallclock note not-stage-ab\n");
  std::fprintf(stderr,
               "s2c2-cuda-run ssd-mlp-wallclock n-htod=%d n-cc=%d k_ref=%d\n",
               nHtod, nCc, kRef);
  std::fprintf(stderr, "s2c2-cuda-run ssd-mlp-wallclock measured=yes\n");
  std::fprintf(stderr,
               "s2c2-cuda-run ssd-mlp-wallclock timing seq=%.1f evi=%.1f "
               "par=%.1f opt_over_base=%.3f\n",
               tSeq, tEvi, tPar, ratio);
  std::fprintf(stderr, "s2c2-cuda-run ssd-mlp-wallclock correctness=1\n");
  std::fprintf(stderr,
               "s2c2-cuda-run ssd-mlp-wallclock note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-cuda-run ssd-mlp-wallclock note 32M-outlier-not-cost\n");
  std::fprintf(stderr,
               "s2c2-cuda-run ssd-mlp-wallclock note logical-ssd-ne-disk\n");
  std::fprintf(stderr, "s2c2-cuda-run ssd-mlp-wallclock note not-cost-v04\n");
  std::fprintf(stderr,
               "s2c2-cuda-run ssd-mlp-wallclock cost=unchanged "
               "semantics=unchanged v3=not-claimed\n");
  prefetch.freeAll();
  cc.freeAll();
  return 0;
}

// Two-tile storage-aware pipeline wall-clock. Logical SSD is a
// pageable host buffer, not NVMe. T_evi keeps C||Storage overlap
// and flattens licensed C||C. Not Cost v0.4.
struct PipeTile {
  float *ssd = nullptr;
  float *host = nullptr;
  float *dev = nullptr;
  int n = 0;

  void alloc(int n_) {
    n = n_;
    size_t bytes = sizeof(float) * static_cast<size_t>(n);
    ssd = static_cast<float *>(std::malloc(bytes));
    if (!ssd) {
      std::fprintf(stderr, "s2c2-cuda-run: ssd alloc failed\n");
      std::exit(2);
    }
    CUDA_OK(cudaHostAlloc(&host, bytes, cudaHostAllocDefault));
    CUDA_OK(cudaMalloc(&dev, bytes));
  }

  void freeAll() {
    cudaFree(dev);
    cudaFreeHost(host);
    std::free(ssd);
  }

  size_t bytes() const { return sizeof(float) * static_cast<size_t>(n); }
};

static void ssdPrefetch(PipeTile &t) {
  std::memcpy(t.host, t.ssd, t.bytes());
}

static void tileHtoD(PipeTile &t, cudaStream_t stream) {
  CUDA_OK(cudaMemcpyAsync(t.dev, t.host, t.bytes(), cudaMemcpyHostToDevice,
                          stream));
}

static void runStoragePipeline(PipeTile &t0, PipeTile &t1, CapBuf &cc16,
                               CapBuf &cc128, int kTile, int kCc, ProgArm arm) {
  if (arm == ProgArm::Seq) {
    ssdPrefetch(t0);
    tileHtoD(t0, cc16.s0);
    CUDA_OK(cudaStreamSynchronize(cc16.s0));
    siluLaunch(t0.dev, t0.n, cc16.s0, kTile);
    CUDA_OK(cudaStreamSynchronize(cc16.s0));
    ssdPrefetch(t1);
    tileHtoD(t1, cc16.s0);
    CUDA_OK(cudaStreamSynchronize(cc16.s0));
    siluLaunch(cc16.dev0, cc16.n, cc16.s0, kCc);
    CUDA_OK(cudaStreamSynchronize(cc16.s0));
    siluLaunch(cc16.dev1, cc16.n, cc16.s1, kCc);
    CUDA_OK(cudaStreamSynchronize(cc16.s1));
    siluLaunch(cc128.dev0, cc128.n, cc128.s0, kCc);
    CUDA_OK(cudaStreamSynchronize(cc128.s0));
    siluLaunch(cc128.dev1, cc128.n, cc128.s1, kCc);
    CUDA_OK(cudaStreamSynchronize(cc128.s1));
    return;
  }
  ssdPrefetch(t0);
  tileHtoD(t0, cc16.s0);
  CUDA_OK(cudaStreamSynchronize(cc16.s0));
  siluLaunch(t0.dev, t0.n, cc16.s0, kTile);
  ssdPrefetch(t1);
  CUDA_OK(cudaStreamSynchronize(cc16.s0));
  tileHtoD(t1, cc16.s1);
  CUDA_OK(cudaStreamSynchronize(cc16.s1));
  if (arm == ProgArm::Evi) {
    siluLaunch(cc16.dev0, cc16.n, cc16.s0, kCc);
    CUDA_OK(cudaStreamSynchronize(cc16.s0));
    siluLaunch(cc16.dev1, cc16.n, cc16.s1, kCc);
    CUDA_OK(cudaStreamSynchronize(cc16.s1));
    siluLaunch(cc128.dev0, cc128.n, cc128.s0, kCc);
    CUDA_OK(cudaStreamSynchronize(cc128.s0));
    siluLaunch(cc128.dev1, cc128.n, cc128.s1, kCc);
    CUDA_OK(cudaStreamSynchronize(cc128.s1));
    return;
  }
  siluLaunch(cc16.dev0, cc16.n, cc16.s0, kCc);
  siluLaunch(cc16.dev1, cc16.n, cc16.s1, kCc);
  CUDA_OK(cudaStreamSynchronize(cc16.s0));
  CUDA_OK(cudaStreamSynchronize(cc16.s1));
  siluLaunch(cc128.dev0, cc128.n, cc128.s0, kCc);
  siluLaunch(cc128.dev1, cc128.n, cc128.s1, kCc);
  CUDA_OK(cudaStreamSynchronize(cc128.s0));
  CUDA_OK(cudaStreamSynchronize(cc128.s1));
}

static bool checkStoragePipeline(PipeTile &t0, PipeTile &t1, CapBuf &cc16,
                                 CapBuf &cc128, int kTile, int kCc) {
  CUDA_OK(cudaMemcpy(cc16.host2, t0.dev, t0.bytes(), cudaMemcpyDeviceToHost));
  int step = t0.n > 4096 ? t0.n / 4096 : 1;
  for (int i = 0; i < t0.n; i += step) {
    if (!closeEnough(cc16.host2[i], hostSilu(t0.ssd[i], kTile)))
      return false;
  }
  CUDA_OK(cudaMemcpy(cc16.host2, t1.dev, t1.bytes(), cudaMemcpyDeviceToHost));
  for (int i = 0; i < t1.n; i += step) {
    if (!closeEnough(cc16.host2[i], t1.ssd[i]))
      return false;
  }
  return checkDevSilu(cc16, cc16.dev0, cc16.host0, kCc) &&
         checkDevSilu(cc16, cc16.dev1, cc16.host1, kCc) &&
         checkDevSilu(cc128, cc128.dev0, cc128.host0, kCc) &&
         checkDevSilu(cc128, cc128.dev1, cc128.host1, kCc);
}

static double timeStoragePipeline(PipeTile &t0, PipeTile &t1, CapBuf &cc16,
                                  CapBuf &cc128, int kTile, int kCc,
                                  int warmup, int reps, ProgArm arm) {
  auto prep = [&](int seed) {
    fillHost(t0.ssd, t0.n, seed);
    fillHost(t1.ssd, t1.n, seed + 1);
    fillHost(cc16.host0, cc16.n, seed + 2);
    fillHost(cc16.host1, cc16.n, seed + 3);
    fillHost(cc128.host0, cc128.n, seed + 4);
    fillHost(cc128.host1, cc128.n, seed + 5);
    provisionSsd(cc16);
    provisionSsd(cc128);
  };
  for (int i = 0; i < warmup; ++i) {
    prep(i + 3);
    runStoragePipeline(t0, t1, cc16, cc128, kTile, kCc, arm);
  }
  std::vector<float> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    prep(i + 11);
    auto start = std::chrono::steady_clock::now();
    runStoragePipeline(t0, t1, cc16, cc128, kTile, kCc, arm);
    auto stop = std::chrono::steady_clock::now();
    samples.push_back(static_cast<float>(
        std::chrono::duration<double, std::micro>(stop - start).count()));
    if (!checkStoragePipeline(t0, t1, cc16, cc128, kTile, kCc)) {
      std::fprintf(stderr,
                   "s2c2-cuda-run correctness=0 arm=storage-pipeline\n");
      std::exit(1);
    }
  }
  return medianUs(samples);
}

static int runStoragePipelineWallclock(int nTile, int nCc, int kRef, int warmup,
                                       int reps) {
  PipeTile t0;
  PipeTile t1;
  CapBuf cc16;
  CapBuf cc128;
  t0.alloc(nTile);
  t1.alloc(nTile);
  cc16.alloc(nTile, false);
  cc128.alloc(nCc, false);
  fillHost(t0.ssd, t0.n, 1);
  fillHost(t1.ssd, t1.n, 2);
  fillHost(cc16.host0, cc16.n, 1);
  fillHost(cc16.host1, cc16.n, 2);
  fillHost(cc128.host0, cc128.n, 1);
  fillHost(cc128.host1, cc128.n, 2);
  provisionSsd(cc16);
  provisionSsd(cc128);
  siluLaunch(t0.dev, t0.n, cc16.s0, 1);
  siluLaunch(cc16.dev0, cc16.n, cc16.s0, 1);
  siluLaunch(cc128.dev0, cc128.n, cc128.s0, 1);
  CUDA_OK(cudaStreamSynchronize(cc16.s0));
  CUDA_OK(cudaStreamSynchronize(cc128.s0));

  double tSeq =
      timeStoragePipeline(t0, t1, cc16, cc128, kRef, kRef, warmup, reps,
                          ProgArm::Seq);
  double tEvi =
      timeStoragePipeline(t0, t1, cc16, cc128, kRef, kRef, warmup, reps,
                          ProgArm::Evi);
  double tPar =
      timeStoragePipeline(t0, t1, cc16, cc128, kRef, kRef, warmup, reps,
                          ProgArm::Par);
  double ratio = tSeq > 0.0 ? tEvi / tSeq : 0.0;

  std::fprintf(stderr, "s2c2-cuda-run hardware_id=rtx4090:cuda sched=%s "
                       "map=%s device=gpu sync=named-nonblocking\n",
               kSched, kMap);
  std::fprintf(stderr, "s2c2-cuda-run workload compute=elemwise\n");
  std::fprintf(stderr, "s2c2-cuda-run workload transfer=storage_to_host|"
                       "host_to_device\n");
  std::fprintf(stderr,
               "s2c2-cuda-run note workload-semantic-ne-kernel-backend\n");
  std::fprintf(stderr, "s2c2-cuda-run timing=host-wall-clock\n");
  std::fprintf(stderr, "s2c2-cuda-run storage-pipeline=1\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-pipeline program-measurement=yes\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-pipeline note storage-prefetch||compute\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-pipeline n-tile=%d n-cc16=%d n-cc128=%d "
               "k_ref=%d\n",
               nTile, nTile, nCc, kRef);
  std::fprintf(stderr, "s2c2-cuda-run storage-pipeline measured=yes\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-pipeline timing seq=%.1f evi=%.1f "
               "par=%.1f opt_over_base=%.3f\n",
               tSeq, tEvi, tPar, ratio);
  std::fprintf(stderr, "s2c2-cuda-run storage-pipeline correctness=1\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-pipeline evi=keep-C||Storage,"
               "serialize-licensed-C||C\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-pipeline note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-pipeline note logical-ssd-ne-disk\n");
  std::fprintf(stderr, "s2c2-cuda-run storage-pipeline note not-cost-v04\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-pipeline cost=unchanged "
               "semantics=unchanged v3=not-claimed\n");
  t0.freeAll();
  t1.freeAll();
  cc16.freeAll();
  cc128.freeAll();
  return 0;
}

// Phase 5B: one runnable arm per @ssd_hierarchy_lifetime inhabitant.
// Axes: PREFETCH/PRESERVE × KEEP_RESIDENCY/TRANSFER × KEEP_RESIDENCY/TRANSFER.
// Independent compute is tile0 elemwise (IR gated_mlp is semantic).
// KEEP skips the rematerialize copy; TRANSFER repeats it. Not a rewrite.
// Do not FileCheck microseconds. Do not re-measure pipeline S0/S1.
static const char *kHierPrefix =
    "MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//";

static const char *hierTail(bool prefetch, bool keepHost, bool keepDev) {
  if (prefetch && keepHost && keepDev)
    return "PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY";
  if (prefetch && keepHost && !keepDev)
    return "PREFETCH|TRANSFER|KEEP_RESIDENCY|TRANSFER";
  if (prefetch && !keepHost && keepDev)
    return "PREFETCH|TRANSFER|TRANSFER|KEEP_RESIDENCY";
  if (prefetch && !keepHost && !keepDev)
    return "PREFETCH|TRANSFER|TRANSFER|TRANSFER";
  if (!prefetch && keepHost && keepDev)
    return "PRESERVE|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY";
  if (!prefetch && keepHost && !keepDev)
    return "PRESERVE|TRANSFER|KEEP_RESIDENCY|TRANSFER";
  if (!prefetch && !keepHost && keepDev)
    return "PRESERVE|TRANSFER|TRANSFER|KEEP_RESIDENCY";
  return "PRESERVE|TRANSFER|TRANSFER|TRANSFER";
}

static void runStorageHierarchy(PipeTile &t0, PipeTile &t1, cudaStream_t sComp,
                                cudaStream_t sCopy, int k, bool prefetch,
                                bool keepHost, bool keepDev) {
  ssdPrefetch(t0);
  tileHtoD(t0, sCopy);
  CUDA_OK(cudaStreamSynchronize(sCopy));
  if (prefetch) {
    siluLaunch(t0.dev, t0.n, sComp, k);
    ssdPrefetch(t1);
    CUDA_OK(cudaStreamSynchronize(sComp));
  } else {
    siluLaunch(t0.dev, t0.n, sComp, k);
    CUDA_OK(cudaStreamSynchronize(sComp));
    ssdPrefetch(t1);
  }
  tileHtoD(t1, sCopy);
  CUDA_OK(cudaStreamSynchronize(sCopy));
  if (!keepHost)
    ssdPrefetch(t1);
  if (!keepDev) {
    tileHtoD(t1, sCopy);
    CUDA_OK(cudaStreamSynchronize(sCopy));
  }
}

static bool checkStorageHierarchy(PipeTile &t0, PipeTile &t1, int k) {
  std::vector<float> got(static_cast<size_t>(t0.n));
  CUDA_OK(cudaMemcpy(got.data(), t0.dev, t0.bytes(), cudaMemcpyDeviceToHost));
  int step = t0.n > 4096 ? t0.n / 4096 : 1;
  for (int i = 0; i < t0.n; i += step) {
    if (!closeEnough(got[i], hostSilu(t0.ssd[i], k)))
      return false;
  }
  CUDA_OK(cudaMemcpy(got.data(), t1.dev, t1.bytes(), cudaMemcpyDeviceToHost));
  for (int i = 0; i < t1.n; i += step) {
    if (!closeEnough(got[i], t1.ssd[i]))
      return false;
  }
  return true;
}

static double timeStorageHierarchy(PipeTile &t0, PipeTile &t1,
                                   cudaStream_t sComp, cudaStream_t sCopy,
                                   int k, int warmup, int reps, bool prefetch,
                                   bool keepHost, bool keepDev) {
  auto prep = [&](int seed) {
    fillHost(t0.ssd, t0.n, seed);
    fillHost(t1.ssd, t1.n, seed + 1);
  };
  for (int i = 0; i < warmup; ++i) {
    prep(i + 3);
    runStorageHierarchy(t0, t1, sComp, sCopy, k, prefetch, keepHost, keepDev);
  }
  std::vector<float> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    prep(i + 11);
    auto start = std::chrono::steady_clock::now();
    runStorageHierarchy(t0, t1, sComp, sCopy, k, prefetch, keepHost, keepDev);
    CUDA_OK(cudaStreamSynchronize(sComp));
    CUDA_OK(cudaStreamSynchronize(sCopy));
    auto stop = std::chrono::steady_clock::now();
    samples.push_back(static_cast<float>(
        std::chrono::duration<double, std::micro>(stop - start).count()));
    if (!checkStorageHierarchy(t0, t1, k)) {
      std::fprintf(stderr,
                   "s2c2-cuda-run correctness=0 arm=storage-hierarchy-measured\n");
      std::exit(1);
    }
  }
  return medianUs(samples);
}

static int runStorageHierarchyMeasured(int nTile, int kRef, int warmup,
                                       int reps) {
  PipeTile t0;
  PipeTile t1;
  t0.alloc(nTile);
  t1.alloc(nTile);
  cudaStream_t sComp = nullptr;
  cudaStream_t sCopy = nullptr;
  CUDA_OK(cudaStreamCreateWithFlags(&sComp, cudaStreamNonBlocking));
  CUDA_OK(cudaStreamCreateWithFlags(&sCopy, cudaStreamNonBlocking));
  fillHost(t0.ssd, t0.n, 1);
  fillHost(t1.ssd, t1.n, 2);
  siluLaunch(t0.dev, t0.n, sComp, 1);
  CUDA_OK(cudaStreamSynchronize(sComp));

  std::fprintf(stderr, "s2c2-cuda-run hardware_id=rtx4090:cuda sched=%s "
                       "map=%s device=gpu sync=named-nonblocking\n",
               kSched, kMap);
  std::fprintf(stderr, "s2c2-cuda-run storage-hierarchy-measured=1\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-hierarchy-measured "
               "program-measurement=yes\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-hierarchy-measured "
               "note one-arm-per-signature\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-hierarchy-measured "
               "note measurement-cannot-expand-F\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-hierarchy-measured "
               "note keep-residency-ne-rewrite\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-hierarchy-measured n-tile=%d k_ref=%d "
               "arms=8\n",
               nTile, kRef);
  std::fprintf(stderr,
               "s2c2-cuda-run storage-hierarchy-measured measured=yes\n");

  int idx = 0;
  for (int pf = 1; pf >= 0; --pf) {
    for (int kh = 1; kh >= 0; --kh) {
      for (int kd = 1; kd >= 0; --kd) {
        double us = timeStorageHierarchy(t0, t1, sComp, sCopy, kRef, warmup,
                                         reps, pf != 0, kh != 0, kd != 0);
        char sig[256];
        std::snprintf(sig, sizeof(sig), "%s%s", kHierPrefix,
                      hierTail(pf != 0, kh != 0, kd != 0));
        std::fprintf(stderr,
                     "s2c2-cuda-run storage-hierarchy-measured "
                     "signature=%s timing=%.1f correctness=1\n",
                     sig, us);
        ++idx;
      }
    }
  }
  std::fprintf(stderr,
               "s2c2-cuda-run storage-hierarchy-measured count=%d "
               "note one-row-per-signature\n",
               idx);
  std::fprintf(stderr,
               "s2c2-cuda-run storage-hierarchy-measured note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-hierarchy-measured "
               "note not-pipeline-s0-s1\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-hierarchy-measured note not-cost-v04\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-hierarchy-measured "
               "note measured-ne-rewrite-license\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-hierarchy-measured cost=unchanged "
               "semantics=unchanged v3=not-claimed\n");
  CUDA_OK(cudaStreamDestroy(sCopy));
  CUDA_OK(cudaStreamDestroy(sComp));
  t0.freeAll();
  t1.freeAll();
  return 0;
}

// Phase 5C: one runnable arm per @ssd_ntile_pipeline inhabitant.
// Axes: two independent PREFETCH/PRESERVE overlap sites.
// Rematerialize KEEP is proven reuse and is not in F; skip those
// copies on every arm. Do not FileCheck microseconds.
// Do not re-measure frozen 5A/5B sets.
static const char *kNtilePrefix =
    "MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//";

static const char *ntileTail(bool pf0, bool pf1) {
  if (pf0 && pf1)
    return "PREFETCH|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER";
  if (pf0 && !pf1)
    return "PREFETCH|TRANSFER//PRESERVE|TRANSFER//TRANSFER|TRANSFER";
  if (!pf0 && pf1)
    return "PRESERVE|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER";
  return "PRESERVE|TRANSFER//PRESERVE|TRANSFER//TRANSFER|TRANSFER";
}

static void overlapOrSeq(PipeTile &comp, PipeTile &next, cudaStream_t sComp,
                         int k, bool prefetch) {
  if (prefetch) {
    siluLaunch(comp.dev, comp.n, sComp, k);
    ssdPrefetch(next);
    CUDA_OK(cudaStreamSynchronize(sComp));
  } else {
    siluLaunch(comp.dev, comp.n, sComp, k);
    CUDA_OK(cudaStreamSynchronize(sComp));
    ssdPrefetch(next);
  }
}

static void runStorageNtile(PipeTile &t0, PipeTile &t1, PipeTile &t2,
                            cudaStream_t sComp, cudaStream_t sCopy, int k,
                            bool pf0, bool pf1) {
  ssdPrefetch(t0);
  tileHtoD(t0, sCopy);
  CUDA_OK(cudaStreamSynchronize(sCopy));
  overlapOrSeq(t0, t1, sComp, k, pf0);
  tileHtoD(t1, sCopy);
  CUDA_OK(cudaStreamSynchronize(sCopy));
  overlapOrSeq(t1, t2, sComp, k, pf1);
  tileHtoD(t2, sCopy);
  CUDA_OK(cudaStreamSynchronize(sCopy));
  siluLaunch(t2.dev, t2.n, sComp, k);
  CUDA_OK(cudaStreamSynchronize(sComp));
}

static bool checkStorageNtile(PipeTile &t0, PipeTile &t1, PipeTile &t2, int k) {
  std::vector<float> got(static_cast<size_t>(t0.n));
  int step = t0.n > 4096 ? t0.n / 4096 : 1;
  PipeTile *tiles[3] = {&t0, &t1, &t2};
  for (int t = 0; t < 3; ++t) {
    CUDA_OK(cudaMemcpy(got.data(), tiles[t]->dev, tiles[t]->bytes(),
                       cudaMemcpyDeviceToHost));
    for (int i = 0; i < tiles[t]->n; i += step) {
      if (!closeEnough(got[i], hostSilu(tiles[t]->ssd[i], k)))
        return false;
    }
  }
  return true;
}

static double timeStorageNtile(PipeTile &t0, PipeTile &t1, PipeTile &t2,
                               cudaStream_t sComp, cudaStream_t sCopy, int k,
                               int warmup, int reps, bool pf0, bool pf1) {
  auto prep = [&](int seed) {
    fillHost(t0.ssd, t0.n, seed);
    fillHost(t1.ssd, t1.n, seed + 1);
    fillHost(t2.ssd, t2.n, seed + 2);
  };
  for (int i = 0; i < warmup; ++i) {
    prep(i + 3);
    runStorageNtile(t0, t1, t2, sComp, sCopy, k, pf0, pf1);
  }
  std::vector<float> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    prep(i + 11);
    auto start = std::chrono::steady_clock::now();
    runStorageNtile(t0, t1, t2, sComp, sCopy, k, pf0, pf1);
    CUDA_OK(cudaStreamSynchronize(sComp));
    CUDA_OK(cudaStreamSynchronize(sCopy));
    auto stop = std::chrono::steady_clock::now();
    samples.push_back(static_cast<float>(
        std::chrono::duration<double, std::micro>(stop - start).count()));
    if (!checkStorageNtile(t0, t1, t2, k)) {
      std::fprintf(stderr,
                   "s2c2-cuda-run correctness=0 arm=storage-ntile-measured\n");
      std::exit(1);
    }
  }
  return medianUs(samples);
}

static int runStorageNtileMeasured(int nTile, int kRef, int warmup, int reps) {
  PipeTile t0;
  PipeTile t1;
  PipeTile t2;
  t0.alloc(nTile);
  t1.alloc(nTile);
  t2.alloc(nTile);
  cudaStream_t sComp = nullptr;
  cudaStream_t sCopy = nullptr;
  CUDA_OK(cudaStreamCreateWithFlags(&sComp, cudaStreamNonBlocking));
  CUDA_OK(cudaStreamCreateWithFlags(&sCopy, cudaStreamNonBlocking));
  fillHost(t0.ssd, t0.n, 1);
  fillHost(t1.ssd, t1.n, 2);
  fillHost(t2.ssd, t2.n, 3);
  siluLaunch(t0.dev, t0.n, sComp, 1);
  CUDA_OK(cudaStreamSynchronize(sComp));

  std::fprintf(stderr, "s2c2-cuda-run hardware_id=rtx4090:cuda sched=%s "
                       "map=%s device=gpu sync=named-nonblocking\n",
               kSched, kMap);
  std::fprintf(stderr, "s2c2-cuda-run storage-ntile-measured=1\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-ntile-measured program-measurement=yes\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-ntile-measured "
               "note one-arm-per-signature\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-ntile-measured "
               "note measurement-cannot-expand-F\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-ntile-measured "
               "note two-independent-prefetch-sites\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-ntile-measured "
               "note contention-not-preclaimed\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-ntile-measured n-tile=%d k_ref=%d "
               "arms=4\n",
               nTile, kRef);
  std::fprintf(stderr, "s2c2-cuda-run storage-ntile-measured measured=yes\n");

  int idx = 0;
  for (int a = 1; a >= 0; --a) {
    for (int b = 1; b >= 0; --b) {
      double us = timeStorageNtile(t0, t1, t2, sComp, sCopy, kRef, warmup,
                                   reps, a != 0, b != 0);
      char sig[320];
      std::snprintf(sig, sizeof(sig), "%s%s", kNtilePrefix,
                    ntileTail(a != 0, b != 0));
      std::fprintf(stderr,
                   "s2c2-cuda-run storage-ntile-measured "
                   "signature=%s timing=%.1f correctness=1\n",
                   sig, us);
      ++idx;
    }
  }
  std::fprintf(stderr,
               "s2c2-cuda-run storage-ntile-measured count=%d "
               "note one-row-per-signature\n",
               idx);
  std::fprintf(stderr,
               "s2c2-cuda-run storage-ntile-measured note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-ntile-measured note not-hierarchy-8\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-ntile-measured note not-pipeline-s0-s1\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-ntile-measured note not-cost-v04\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-ntile-measured "
               "note measured-ne-rewrite-license\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-ntile-measured cost=unchanged "
               "semantics=unchanged v3=not-claimed\n");
  CUDA_OK(cudaStreamDestroy(sCopy));
  CUDA_OK(cudaStreamDestroy(sComp));
  t0.freeAll();
  t1.freeAll();
  t2.freeAll();
  return 0;
}

// 3I scf.for realization wall-clock. Prologue tile 0, then two
// iterations of compute(i) || prefetch(i+1) and sequential HtoD.
// T_evi keeps C||Storage. T_par is the same schedule (no C||C).
// Logical SSD is a pageable host buffer. Not Cost v0.4.
static void runStorageLoop(PipeTile t[3], cudaStream_t sCompute,
                           cudaStream_t sCopy, int k, ProgArm arm) {
  ssdPrefetch(t[0]);
  tileHtoD(t[0], sCopy);
  CUDA_OK(cudaStreamSynchronize(sCopy));
  for (int i = 0; i < 2; ++i) {
    int next = i + 1;
    if (arm == ProgArm::Seq) {
      siluLaunch(t[i].dev, t[i].n, sCompute, k);
      CUDA_OK(cudaStreamSynchronize(sCompute));
      ssdPrefetch(t[next]);
      tileHtoD(t[next], sCopy);
      CUDA_OK(cudaStreamSynchronize(sCopy));
    } else {
      siluLaunch(t[i].dev, t[i].n, sCompute, k);
      ssdPrefetch(t[next]);
      CUDA_OK(cudaStreamSynchronize(sCompute));
      tileHtoD(t[next], sCopy);
      CUDA_OK(cudaStreamSynchronize(sCopy));
    }
  }
}

static bool checkStorageLoop(PipeTile t[3], float *check, int k) {
  int step = t[0].n > 4096 ? t[0].n / 4096 : 1;
  for (int tile = 0; tile < 2; ++tile) {
    CUDA_OK(cudaMemcpy(check, t[tile].dev, t[tile].bytes(),
                       cudaMemcpyDeviceToHost));
    for (int i = 0; i < t[tile].n; i += step) {
      if (!closeEnough(check[i], hostSilu(t[tile].ssd[i], k)))
        return false;
    }
  }
  CUDA_OK(cudaMemcpy(check, t[2].dev, t[2].bytes(), cudaMemcpyDeviceToHost));
  for (int i = 0; i < t[2].n; i += step) {
    if (!closeEnough(check[i], t[2].ssd[i]))
      return false;
  }
  return true;
}

static double timeStorageLoop(PipeTile t[3], cudaStream_t sCompute,
                              cudaStream_t sCopy, float *check, int k,
                              int warmup, int reps, ProgArm arm) {
  auto prep = [&](int seed) {
    for (int i = 0; i < 3; ++i)
      fillHost(t[i].ssd, t[i].n, seed + i);
  };
  for (int i = 0; i < warmup; ++i) {
    prep(i + 3);
    runStorageLoop(t, sCompute, sCopy, k, arm);
  }
  std::vector<float> samples;
  samples.reserve(reps);
  for (int i = 0; i < reps; ++i) {
    prep(i + 11);
    auto start = std::chrono::steady_clock::now();
    runStorageLoop(t, sCompute, sCopy, k, arm);
    auto stop = std::chrono::steady_clock::now();
    samples.push_back(static_cast<float>(
        std::chrono::duration<double, std::micro>(stop - start).count()));
    if (!checkStorageLoop(t, check, k)) {
      std::fprintf(stderr,
                   "s2c2-cuda-run correctness=0 arm=storage-loop-wallclock\n");
      std::exit(1);
    }
  }
  return medianUs(samples);
}

static int runStorageLoopWallclock(int nTile, int kRef, int warmup, int reps) {
  PipeTile t[3];
  for (int i = 0; i < 3; ++i)
    t[i].alloc(nTile);
  float *check = nullptr;
  CUDA_OK(cudaHostAlloc(&check, t[0].bytes(), cudaHostAllocDefault));
  cudaStream_t sCompute = nullptr;
  cudaStream_t sCopy = nullptr;
  CUDA_OK(cudaStreamCreate(&sCompute));
  CUDA_OK(cudaStreamCreate(&sCopy));
  for (int i = 0; i < 3; ++i)
    fillHost(t[i].ssd, t[i].n, i + 1);
  siluLaunch(t[0].dev, t[0].n, sCompute, 1);
  CUDA_OK(cudaStreamSynchronize(sCompute));

  double tSeq =
      timeStorageLoop(t, sCompute, sCopy, check, kRef, warmup, reps,
                      ProgArm::Seq);
  double tEvi =
      timeStorageLoop(t, sCompute, sCopy, check, kRef, warmup, reps,
                      ProgArm::Evi);
  double tPar =
      timeStorageLoop(t, sCompute, sCopy, check, kRef, warmup, reps,
                      ProgArm::Par);
  double ratio = tSeq > 0.0 ? tEvi / tSeq : 0.0;

  std::fprintf(stderr, "s2c2-cuda-run hardware_id=rtx4090:cuda sched=%s "
                       "map=%s device=gpu sync=named-nonblocking\n",
               kSched, kMap);
  std::fprintf(stderr, "s2c2-cuda-run workload compute=elemwise\n");
  std::fprintf(stderr, "s2c2-cuda-run workload transfer=storage_to_host|"
                       "host_to_device\n");
  std::fprintf(stderr,
               "s2c2-cuda-run note workload-semantic-ne-kernel-backend\n");
  std::fprintf(stderr, "s2c2-cuda-run timing=host-wall-clock\n");
  std::fprintf(stderr, "s2c2-cuda-run storage-loop-wallclock=1\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-loop-wallclock program-measurement=yes\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-loop-wallclock "
               "note scf-for-software-pipeline\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-loop-wallclock "
               "note not-arbitrary-runtime-n\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-loop-wallclock "
               "note compute-then-prefetch-next\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-loop-wallclock n-tile=%d tiles=3 "
               "trip=2 k_ref=%d\n",
               nTile, kRef);
  std::fprintf(stderr, "s2c2-cuda-run storage-loop-wallclock measured=yes\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-loop-wallclock timing seq=%.1f evi=%.1f "
               "par=%.1f opt_over_base=%.3f\n",
               tSeq, tEvi, tPar, ratio);
  std::fprintf(stderr, "s2c2-cuda-run storage-loop-wallclock correctness=1\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-loop-wallclock evi=keep-C||Storage\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-loop-wallclock note evi-eq-par\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-loop-wallclock note catalog-untouched\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-loop-wallclock note logical-ssd-ne-disk\n");
  std::fprintf(stderr, "s2c2-cuda-run storage-loop-wallclock note not-cost-v04\n");
  std::fprintf(stderr,
               "s2c2-cuda-run storage-loop-wallclock cost=unchanged "
               "semantics=unchanged v3=not-claimed\n");
  cudaStreamDestroy(sCompute);
  cudaStreamDestroy(sCopy);
  cudaFreeHost(check);
  for (int i = 0; i < 3; ++i)
    t[i].freeAll();
  return 0;
}

int main(int argc, char **argv) {
  const char *func = "all";
  const char *device = kDevice;
  const char *matchedArg = "off";
  const char *capArg = "off";
  const char *phaseArg = "off";
  const char *pipeArg = "off";
  const char *valArg = "off";
  const char *valMemArg = "off";
  const char *valCcArg = "off";
  const char *valAsyncArg = "off";
  int n = 1 << 24;
  int nCc = 33554432;
  int warmup = 5;
  int reps = 21;
  int k = 1;
  int m = 1;
  int tiles = 8;
  bool provisioned = false;
  bool ssdMlp = false;
  bool storagePipe = false;
  bool storageLoop = false;
  bool storageHier = false;
  bool storageNtile = false;
  bool kSet = false;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (a.rfind("--func=", 0) == 0)
      func = argv[i] + 7;
    else if (a.rfind("--device=", 0) == 0)
      device = argv[i] + 9;
    else if (a.rfind("--n-cc=", 0) == 0)
      nCc = std::atoi(argv[i] + 7);
    else if (a.rfind("--n=", 0) == 0)
      n = std::atoi(argv[i] + 4);
    else if (a.rfind("--warmup=", 0) == 0)
      warmup = std::atoi(argv[i] + 9);
    else if (a.rfind("--reps=", 0) == 0)
      reps = std::atoi(argv[i] + 7);
    else if (a.rfind("--k=", 0) == 0) {
      k = std::atoi(argv[i] + 4);
      kSet = true;
    } else if (a == "--ssd-mlp-wallclock")
      ssdMlp = true;
    else if (a == "--storage-pipeline")
      storagePipe = true;
    else if (a == "--storage-loop-wallclock")
      storageLoop = true;
    else if (a == "--storage-hierarchy-measured")
      storageHier = true;
    else if (a == "--storage-ntile-measured")
      storageNtile = true;
    else if (a.rfind("--matched=", 0) == 0)
      matchedArg = argv[i] + 10;
    else if (a.rfind("--cap=", 0) == 0)
      capArg = argv[i] + 6;
    else if (a.rfind("--phase=", 0) == 0)
      phaseArg = argv[i] + 8;
    else if (a.rfind("--pipe=", 0) == 0)
      pipeArg = argv[i] + 7;
    else if (a.rfind("--cuda-val-async=", 0) == 0)
      valAsyncArg = argv[i] + 17;
    else if (a.rfind("--cuda-val-cc=", 0) == 0)
      valCcArg = argv[i] + 14;
    else if (a.rfind("--cuda-val-mem=", 0) == 0)
      valMemArg = argv[i] + 15;
    else if (a.rfind("--cuda-val=", 0) == 0)
      valArg = argv[i] + 11;
    else if (a.rfind("--m=", 0) == 0)
      m = std::atoi(argv[i] + 4);
    else if (a.rfind("--tiles=", 0) == 0)
      tiles = std::atoi(argv[i] + 8);
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
                   "s2c2-cuda-run --pipe=d1|d2|d3|d4|copy|compute|depths|all "
                   "--device=gpu --n=N --k=K --tiles=8\n"
                   "s2c2-cuda-run --cuda-val=p0|named|default|ovl-named|"
                   "ovl-default --device=gpu --n=N --k=K\n"
                   "s2c2-cuda-run --cuda-val-mem=p0|htod|dtoh|ovl-htod|"
                   "ovl-dtoh --device=gpu --n=N --k=K\n"
                   "s2c2-cuda-run --cuda-val-cc=p0|silu|matmul|seq|ovl|"
                   "silu-silu --device=gpu --n=N --k=K --m=M\n"
                   "s2c2-cuda-run --cuda-val-async=p0|copy|compute|life-sync|"
                   "life-async|hb --device=gpu --n=N --k=K\n"
                   "s2c2-cuda-run --ssd-mlp-wallclock [--n=N] [--n-cc=N] "
                   "--k=K --warmup=W --reps=R\n"
                   "s2c2-cuda-run --storage-pipeline [--n=N] [--n-cc=N] "
                   "--k=K --warmup=W --reps=R\n"
                   "s2c2-cuda-run --storage-loop-wallclock [--n=N] "
                   "--k=K --warmup=W --reps=R\n"
                   "s2c2-cuda-run --storage-hierarchy-measured [--n=N] "
                   "--k=K --warmup=W --reps=R\n"
                   "s2c2-cuda-run --storage-ntile-measured [--n=N] "
                   "--k=K --warmup=W --reps=R\n"
                   "s2c2-cuda-run --print-meta\n");
      return 0;
    } else {
      std::fprintf(stderr, "s2c2-cuda-run: unknown arg %s\n", argv[i]);
      return 1;
    }
  }
  if (n <= 0 || warmup < 0 || reps <= 0 || k <= 0 || tiles <= 0 || m <= 0) {
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
  std::vector<PipeArm> pipeArms = parsePipeList(pipeArg);
  std::vector<ValArm> valArms = parseValList(valArg);
  std::vector<ValMemArm> valMemArms = parseValMemList(valMemArg);
  std::vector<ValCcKind> valCcArms = parseValCcList(valCcArg);
  std::vector<ValAsyncKind> valAsyncArms = parseValAsyncList(valAsyncArg);
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
  if (!pipeArms.empty() &&
      (matchedOn || !capArms.empty() || !phaseArms.empty())) {
    std::fprintf(stderr,
                 "s2c2-cuda-run: --pipe cannot combine with --phase/--cap/--matched\n");
    return 1;
  }
  if (!valArms.empty() &&
      (matchedOn || !capArms.empty() || !phaseArms.empty() ||
       !pipeArms.empty())) {
    std::fprintf(stderr,
                 "s2c2-cuda-run: --cuda-val cannot combine with "
                 "--pipe/--phase/--cap/--matched\n");
    return 1;
  }
  if (!valMemArms.empty() &&
      (matchedOn || !capArms.empty() || !phaseArms.empty() ||
       !pipeArms.empty() || !valArms.empty())) {
    std::fprintf(stderr,
                 "s2c2-cuda-run: --cuda-val-mem cannot combine with "
                 "--cuda-val/--pipe/--phase/--cap/--matched\n");
    return 1;
  }
  if (!valCcArms.empty() &&
      (matchedOn || !capArms.empty() || !phaseArms.empty() ||
       !pipeArms.empty() || !valArms.empty() || !valMemArms.empty())) {
    std::fprintf(stderr,
                 "s2c2-cuda-run: --cuda-val-cc cannot combine with "
                 "--cuda-val-mem/--cuda-val/--pipe/--phase/--cap/--matched\n");
    return 1;
  }
  if (!valAsyncArms.empty() &&
      (matchedOn || !capArms.empty() || !phaseArms.empty() ||
       !pipeArms.empty() || !valArms.empty() || !valMemArms.empty() ||
       !valCcArms.empty())) {
    std::fprintf(stderr,
                 "s2c2-cuda-run: --cuda-val-async cannot combine with "
                 "--cuda-val-cc/--cuda-val-mem/--cuda-val/"
                 "--pipe/--phase/--cap/--matched\n");
    return 1;
  }
  if (ssdMlp) {
    if (matchedOn || !capArms.empty() || !phaseArms.empty() ||
        !pipeArms.empty() || !valArms.empty() || !valMemArms.empty() ||
        !valCcArms.empty() || !valAsyncArms.empty() || storagePipe ||
        storageLoop || storageHier || storageNtile) {
      std::fprintf(stderr,
                   "s2c2-cuda-run: --ssd-mlp-wallclock cannot combine with "
                   "other timed modes\n");
      return 1;
    }
    if (!gpu) {
      std::fprintf(stderr, "s2c2-cuda-run: --ssd-mlp-wallclock is gpu only\n");
      return 1;
    }
    if (!kSet)
      k = 32;
    if (n <= 0 || nCc <= 0 || k <= 0) {
      std::fprintf(stderr,
                   "s2c2-cuda-run: --ssd-mlp-wallclock needs n>0 n-cc>0 k>0\n");
      return 1;
    }
    int count = 0;
    CUDA_OK(cudaGetDeviceCount(&count));
    if (count < 1) {
      std::fprintf(stderr, "s2c2-cuda-run: no CUDA device\n");
      return 2;
    }
    return runSsdMlpWallclock(n, nCc, k, warmup, reps);
  }
  if (storagePipe) {
    if (ssdMlp || matchedOn || !capArms.empty() || !phaseArms.empty() ||
        !pipeArms.empty() || !valArms.empty() || !valMemArms.empty() ||
        !valCcArms.empty() || !valAsyncArms.empty() ||         storageLoop ||
        storageHier || storageNtile) {
      std::fprintf(stderr,
                   "s2c2-cuda-run: --storage-pipeline cannot combine with "
                   "other timed modes\n");
      return 1;
    }
    if (!gpu) {
      std::fprintf(stderr, "s2c2-cuda-run: --storage-pipeline is gpu only\n");
      return 1;
    }
    if (!kSet)
      k = 32;
    if (n == (1 << 24))
      n = 4194304;
    if (n <= 0 || nCc <= 0 || k <= 0) {
      std::fprintf(stderr,
                   "s2c2-cuda-run: --storage-pipeline needs n>0 n-cc>0 k>0\n");
      return 1;
    }
    int count = 0;
    CUDA_OK(cudaGetDeviceCount(&count));
    if (count < 1) {
      std::fprintf(stderr, "s2c2-cuda-run: no CUDA device\n");
      return 2;
    }
    return runStoragePipelineWallclock(n, nCc, k, warmup, reps);
  }
  if (storageLoop) {
    if (ssdMlp || storagePipe || matchedOn || !capArms.empty() ||
        !phaseArms.empty() || !pipeArms.empty() || !valArms.empty() ||
        !valMemArms.empty() || !valCcArms.empty() || !valAsyncArms.empty() ||
        storageHier || storageNtile) {
      std::fprintf(stderr,
                   "s2c2-cuda-run: --storage-loop-wallclock cannot combine "
                   "with other timed modes\n");
      return 1;
    }
    if (!gpu) {
      std::fprintf(stderr,
                   "s2c2-cuda-run: --storage-loop-wallclock is gpu only\n");
      return 1;
    }
    if (!kSet)
      k = 32;
    if (n == (1 << 24))
      n = 4194304;
    if (n <= 0 || k <= 0) {
      std::fprintf(stderr,
                   "s2c2-cuda-run: --storage-loop-wallclock needs n>0 k>0\n");
      return 1;
    }
    int count = 0;
    CUDA_OK(cudaGetDeviceCount(&count));
    if (count < 1) {
      std::fprintf(stderr, "s2c2-cuda-run: no CUDA device\n");
      return 2;
    }
    return runStorageLoopWallclock(n, k, warmup, reps);
  }
  if (storageHier) {
    if (ssdMlp || storagePipe || storageLoop || matchedOn || !capArms.empty() ||
        !phaseArms.empty() || !pipeArms.empty() || !valArms.empty() ||
        !valMemArms.empty() || !valCcArms.empty() || !valAsyncArms.empty() ||
        storageNtile) {
      std::fprintf(stderr,
                   "s2c2-cuda-run: --storage-hierarchy-measured cannot "
                   "combine with other timed modes\n");
      return 1;
    }
    if (!gpu) {
      std::fprintf(stderr,
                   "s2c2-cuda-run: --storage-hierarchy-measured is gpu only\n");
      return 1;
    }
    if (!kSet)
      k = 32;
    if (n == (1 << 24))
      n = 4194304;
    if (n <= 0 || k <= 0) {
      std::fprintf(stderr,
                   "s2c2-cuda-run: --storage-hierarchy-measured needs n>0 k>0\n");
      return 1;
    }
    int count = 0;
    CUDA_OK(cudaGetDeviceCount(&count));
    if (count < 1) {
      std::fprintf(stderr, "s2c2-cuda-run: no CUDA device\n");
      return 2;
    }
    return runStorageHierarchyMeasured(n, k, warmup, reps);
  }
  if (storageNtile) {
    if (ssdMlp || storagePipe || storageLoop || storageHier || matchedOn ||
        !capArms.empty() || !phaseArms.empty() || !pipeArms.empty() ||
        !valArms.empty() || !valMemArms.empty() || !valCcArms.empty() ||
        !valAsyncArms.empty()) {
      std::fprintf(stderr,
                   "s2c2-cuda-run: --storage-ntile-measured cannot "
                   "combine with other timed modes\n");
      return 1;
    }
    if (!gpu) {
      std::fprintf(stderr,
                   "s2c2-cuda-run: --storage-ntile-measured is gpu only\n");
      return 1;
    }
    if (!kSet)
      k = 32;
    if (n == (1 << 24))
      n = 4194304;
    if (n <= 0 || k <= 0) {
      std::fprintf(stderr,
                   "s2c2-cuda-run: --storage-ntile-measured needs n>0 k>0\n");
      return 1;
    }
    int count = 0;
    CUDA_OK(cudaGetDeviceCount(&count));
    if (count < 1) {
      std::fprintf(stderr, "s2c2-cuda-run: no CUDA device\n");
      return 2;
    }
    return runStorageNtileMeasured(n, k, warmup, reps);
  }
  if (m != 1 && valCcArms.empty()) {
    std::fprintf(stderr, "s2c2-cuda-run: --m is --cuda-val-cc only\n");
    return 1;
  }
  if (!valArms.empty()) {
    if (!gpu) {
      std::fprintf(stderr, "s2c2-cuda-run: --cuda-val is gpu only\n");
      return 1;
    }
    int count = 0;
    CUDA_OK(cudaGetDeviceCount(&count));
    if (count < 1) {
      std::fprintf(stderr, "s2c2-cuda-run: no CUDA device\n");
      return 2;
    }
    ValBuf namedBuf;
    ValBuf defaultBuf;
    bool needNamed = false;
    bool needDefault = false;
    for (ValArm arm : valArms) {
      if (arm.stream == ValStreamKind::Named)
        needNamed = true;
      else
        needDefault = true;
    }
    if (needNamed)
      namedBuf.alloc(n, ValStreamKind::Named);
    if (needDefault)
      defaultBuf.alloc(n, ValStreamKind::Default);
    for (ValArm arm : valArms) {
      ValBuf &b =
          arm.stream == ValStreamKind::Named ? namedBuf : defaultBuf;
      double us = timeValArm(b, arm, warmup, reps, k);
      printVal(arm, "gpu", n, k, us);
    }
    if (needNamed)
      namedBuf.freeAll();
    if (needDefault)
      defaultBuf.freeAll();
    std::fprintf(stderr, "s2c2-cuda-adapter v3=not-claimed\n");
    return 0;
  }
  if (!valMemArms.empty()) {
    if (!gpu) {
      std::fprintf(stderr, "s2c2-cuda-run: --cuda-val-mem is gpu only\n");
      return 1;
    }
    int count = 0;
    CUDA_OK(cudaGetDeviceCount(&count));
    if (count < 1) {
      std::fprintf(stderr, "s2c2-cuda-run: no CUDA device\n");
      return 2;
    }
    ValMemBuf b;
    b.alloc(n);
    for (ValMemArm arm : valMemArms) {
      double us = timeValMemArm(b, arm, warmup, reps, k);
      printValMem(arm, "gpu", n, k, us);
    }
    b.freeAll();
    std::fprintf(stderr, "s2c2-cuda-adapter v3=not-claimed\n");
    return 0;
  }
  if (!valCcArms.empty()) {
    if (!gpu) {
      std::fprintf(stderr, "s2c2-cuda-run: --cuda-val-cc is gpu only\n");
      return 1;
    }
    int count = 0;
    CUDA_OK(cudaGetDeviceCount(&count));
    if (count < 1) {
      std::fprintf(stderr, "s2c2-cuda-run: no CUDA device\n");
      return 2;
    }
    ValCcBuf b;
    b.alloc(n);
    for (ValCcKind arm : valCcArms) {
      double us = timeValCcArm(b, arm, warmup, reps, k, m);
      printValCc(arm, "gpu", n, k, m, us);
    }
    b.freeAll();
    std::fprintf(stderr, "s2c2-cuda-adapter v3=not-claimed\n");
    return 0;
  }
  if (!valAsyncArms.empty()) {
    if (!gpu) {
      std::fprintf(stderr, "s2c2-cuda-run: --cuda-val-async is gpu only\n");
      return 1;
    }
    int count = 0;
    CUDA_OK(cudaGetDeviceCount(&count));
    if (count < 1) {
      std::fprintf(stderr, "s2c2-cuda-run: no CUDA device\n");
      return 2;
    }
    ValAsyncBuf b;
    b.alloc(n);
    for (ValAsyncKind arm : valAsyncArms) {
      double us = timeValAsyncArm(b, arm, warmup, reps, k);
      printValAsync(arm, "gpu", n, k, us);
    }
    b.freeAll();
    std::fprintf(stderr, "s2c2-cuda-adapter v3=not-claimed\n");
    return 0;
  }
  if (!pipeArms.empty()) {
    if (!gpu) {
      std::fprintf(stderr, "s2c2-cuda-run: --pipe is gpu only\n");
      return 1;
    }
    if (n % tiles != 0) {
      std::fprintf(stderr, "s2c2-cuda-run: n must divide tiles\n");
      return 1;
    }
    int count = 0;
    CUDA_OK(cudaGetDeviceCount(&count));
    if (count < 1) {
      std::fprintf(stderr, "s2c2-cuda-run: no CUDA device\n");
      return 2;
    }
    PipeBuf b;
    b.alloc(n, tiles);
    for (PipeArm arm : pipeArms) {
      double us = timePipeArm(b, arm, warmup, reps, k);
      printPipe(arm, "gpu", n, k, us);
    }
    b.freeAll();
    std::fprintf(stderr, "s2c2-cuda-adapter v3=not-claimed\n");
    return 0;
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
