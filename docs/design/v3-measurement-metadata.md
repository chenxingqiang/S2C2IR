# V3 Measurement Metadata Protocol (v0.1)

Status: **metadata protocol**. Not Cost v0.4. Does **not**
change Cost, HB, `R`, Search, Transformation, or CUDA adapter
semantics. Baseline: `40f8a2b` (`#48`).

```text
Metadata     ≠  Cost revision
JSONL / CSV  ≠  FileCheck of microseconds
V3           ≠  claimed
```

---

## 1. Why metadata first

Latency is

```text
Latency = f(Hardware, Driver, Clock, N, k, Provisioning)
```

not `f(N, k)` alone. A later rank comparison across machines
or days needs a fixed record. This layer freezes the record
before the 4090 rerun.

---

## 2. Record (one GPU point)

| Field | Meaning |
| ----- | ------- |
| `git_commit` | S²C² revision that produced the binary |
| `timestamp` | UTC ISO-8601 |
| `gpu_model` | `nvidia-smi` name |
| `gpu_memory` | total MiB |
| `driver_version` | `nvidia-smi` driver |
| `cuda_runtime` | `cudaRuntimeGetVersion()` from the measurement binary |
| `nvcc_version` | `nvcc --version` |

```text
Driver Version  ≠  NVCC Version  ≠  CUDA Runtime Version
```

`cuda_runtime` is the loaded **libcudart** API integer
(e.g. `12080`). It is **not** the `nvidia-smi` `CUDA Version:`
banner (driver compatibility) and not `nvcc`.
| `clock_state` | pstate + SM/mem clocks when readable |
| `power_mode` | power limit when readable |
| `case` | `a` / `b` / `c` |
| `N` | float count |
| `k` | SiLU repeats |
| `provisioned` | `0` / `1` |
| `warmup` | warmup runs |
| `reps` | timed samples |
| `statistic` | `median` |
| `latency_us` | median microseconds |
| `score3` | frozen Score_3 for that case |

No host, account, password, or IP. Adapter A/B/C bodies are
unchanged.

Formats: **JSONL** (one object per line) and **CSV** (same
columns). Writer: `runtime/cuda/record_v3.py`.

---

## 3. Dataset grid

```text
case         ∈ {a, b, c}
N            ∈ {4M, 16M, 64M} = {4194304, 16777216, 67108864}
k            ∈ {1, 8}
provisioned  ∈ {0, 1}
```

```text
3 × 3 × 2 × 2  =  36 GPU points
```

`M` stays `(gpu-async, default, gpu)`. Score_3 stays 130 /
128 / 163.

---

## 4. Analysis (after the rerun)

Per `(N, k, provisioned)` slice of `{A,B,C}`:

```text
Rank(Score_3)  vs  Rank(Latency)
Spearman ρ
pairwise agreement (BA, AC, BC)
```

Lower Score_3 and lower latency are both “better”. This is a
**probe**, not V3 validated. Do not FileCheck ρ.

---

## 5. One RTX 4090 rerun (36 points, not V3)

Files: [`v3-dataset/`](v3-dataset/). Median of 21 timed reps,
warmup 5. Score_3 stays 130 / 128 / 163.

Hardware snapshot (not a lock):

```text
gpu_model        NVIDIA GeForce RTX 4090
gpu_memory       24564
driver_version   570.124.06
cuda_runtime     12080   (cudaRuntimeGetVersion; not smi banner 12.8)
nvcc_version     release 12.8, V12.8.61
power_mode       limit_w=450.00
clock_state      pre-sweep snapshot (idle P8 on this run)
```

Cost rank is always `bac` (B < A < C). Latency always puts
**A first**. Pair `B<A` never agrees.

| N | k | prov | lat A | lat B | lat C | lat rank | ρ | BA | AC | BC |
| - | - | ---- | ----- | ----- | ----- | -------- | - | -- | -- | -- |
| 4M | 1 | 0 | 692 | 1341 | 1339 | acb | −0.5 | N | Y | N |
| 4M | 1 | 1 | 18 | 676 | 666 | acb | −0.5 | N | Y | N |
| 4M | 8 | 0 | 772 | 1341 | 1418 | abc | 0.5 | N | Y | Y |
| 4M | 8 | 1 | 97 | 691 | 744 | abc | 0.5 | N | Y | Y |
| 16M | 1 | 0 | 2883 | 5486 | 5383 | acb | −0.5 | N | Y | N |
| 16M | 1 | 1 | 66 | 2680 | 2635 | acb | −0.5 | N | Y | N |
| 16M | 8 | 0 | 3324 | 5489 | 5859 | abc | 0.5 | N | Y | Y |
| 16M | 8 | 1 | 554 | 2700 | 3138 | abc | 0.5 | N | Y | Y |
| 64M | 1 | 0 | 11486 | 21890 | 22262 | abc | 0.5 | N | Y | Y |
| 64M | 1 | 1 | 538 | 10967 | 11336 | abc | 0.5 | N | Y | Y |
| 64M | 8 | 0 | 15563 | 21761 | 25926 | abc | 0.5 | N | Y | Y |
| 64M | 8 | 1 | 4616 | 10709 | 15277 | abc | 0.5 | N | Y | Y |

```text
slices            12
mean Spearman ρ   0.167
pairwise          20/36  (AC always; BA never; BC when k=8 or N=64M)
V3                not claimed
Cost v0.4         not opened
```

Fair overlap at N=16M, k=1, provisioned=1 is still A 66 μs vs
B 2680 μs (SiLU-only vs SiLU∥HtoD). The 2742 vs 2681 pair
compares A *provisioned=0* to B *provisioned=1* and is not a
same-slice rank.

---

## 6. Out of scope

```text
Cost v0.4 / C_overlap rewrite
new T kind / Search
changing provisioned semantics
claiming V3 pass
storing credentials
```
