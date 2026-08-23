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
| `driver_version` | driver |
| `cuda_runtime` | CUDA runtime string if available |
| `nvcc_version` | `nvcc --version` |
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

## 5. Out of scope

```text
Cost v0.4 / C_overlap rewrite
new T kind / Search
changing provisioned semantics
claiming V3 pass
storing credentials
```
