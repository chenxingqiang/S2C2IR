# V3 Measurement Campaign (v0.1)

Status: **campaign design**. Not v0.5.x. Does **not** change
Cost, HB, `R`, or the frozen measurement adapter contract.
Baseline: `090b247` (`#46`).

```text
Campaign     ≠  Cost v0.4
provisioned  ≠  a new Pilot IR
more N / k   ≠  Spearman validation
V3           ≠  claimed
```

---

## 1. Why a campaign, not a Cost patch

The first 4090 probe showed:

```text
Cost rank:     B < A < C
Latency rank:  A fastest; B ≈ C and ~2× A
```

B's stand-in times two HostToDevice copies (compute
provisioning + comm). That mixes:

```text
IR semantic work          vs  adapter-specific provisioning
```

Do **not** rewrite `C_overlap` from `n=3`. Collect
`(Score_3, Latency)` under controlled variants first.

---

## 2. Axes

| Axis | Values | Question |
| ---- | ------ | -------- |
| `P_id` | A / B / C | frozen Pilot shapes |
| `N` | 4M / 16M / 64M | copy size |
| `k` | 1 / 8 | SiLU repeats (compute intensity) |
| `provisioned` | 0 / 1 | exclude first HtoD from the timed window |

`provisioned=1` on B times `SiLU(scratch) ∥ HtoD(hbm)` after
scratch is already on device. That is the IR concurrent pair
without the extra compute-path copy.

`M` stays `(gpu-async, default, gpu)`. Score_3 stays 130 /
128 / 163.

---

## 3. One RTX 4090 sweep (not V3)

Median `cudaEvent`, CUDA 12.8 / driver 570. Do not FileCheck.

**provisioned=0** (original stand-in, two HtoD on B):

| N | k | A | B | C |
| - | - | - | - | - |
| 4M | 1 | 693 | 1339 | 1339 |
| 16M | 1 | 2742 | 5331 | 5314 |
| 64M | 1 | 11185 | 21268 | 21834 |

**provisioned=1** (first HtoD excluded):

| N | k | A (SiLU) | B (SiLU ∥ HtoD) | C (SiLU + DtoH) |
| - | - | -------- | --------------- | --------------- |
| 4M | 1 | 20 | 677 | 667 |
| 16M | 1 | 70 | 2681 | 2631 |
| 64M | 1 | 544 | 10664 | 11206 |
| 16M | 8 | 558 | 2702 | 3122 |
| 64M | 8 | 4618 | 10736 | 15280 |

Fair overlap probe at N=16M, k=1:

```text
A provisioned=0   HtoD then SiLU     2742 μs
B provisioned=1   SiLU ∥ HtoD        2681 μs
```

Compute is ~70 μs; the copy is ~2.6 ms. Overlap hides the
kernel, not the copy. Cost's 128 vs 130 is a 2-point gap on
a 130-scale — the same *order* as this ~2% wall-clock gap.
The original two-HtoD stand-in hid that.

```text
V3  still not claimed
C_overlap  not rewritten
```

---

## 4. Out of scope

```text
changing C_overlap / Score_3
new T kind
new Pilot IR
claiming V3 / Spearman
real SSD
```
