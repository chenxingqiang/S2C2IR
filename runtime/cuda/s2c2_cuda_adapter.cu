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

static const char *valCcExtraHb(ValCcKind kind) {
  if (kind == ValCcKind::Ovl)
    return "mixed-kind-serial";
  if (kind == ValCcKind::SiluSilu)
    return "same-kind";
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
               "correct=1 extra_hb=%s m=%d dim=%d\n",
               valCcFunc(kind), kSched, kMap, dev, n, k, us,
               valCcExtraHb(kind), m, kValCcDim);
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
  int n = 1 << 24;
  int warmup = 5;
  int reps = 21;
  int k = 1;
  int m = 1;
  int tiles = 8;
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
    else if (a.rfind("--pipe=", 0) == 0)
      pipeArg = argv[i] + 7;
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
