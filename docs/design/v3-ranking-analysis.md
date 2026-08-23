# V3 Ranking Analysis (v0.1)

Status: **analysis of the frozen 4090 dataset**. Not Cost v0.4.
Does **not** change Cost, HB, `R`, Search, Transformation, or
adapter A/B/C bodies. Baseline: `b10087c` (`#49`).
Records: [`v3-dataset/`](v3-dataset/).

```text
Question     :  is Rank(Score_3) vs Rank(Latency) stable,
                or an artifact of this stand-in?
V3           ≠  validated
Cost v0.4    ≠  opened
```

---

## 1. What is compared

Score_3 is **IR-structural** and constant per case:

```text
B  128  <  A  130  <  C  163
```

It does not depend on `N`, `k`, or `provisioned`.

Latency is **hardware** and does depend on those axes.
Each slice is one `(N, k, provisioned)` with cases `{A,B,C}`.
Lower Score_3 and lower latency are both “better.”

What each timed body actually does:

| case | provisioned=0 | provisioned=1 |
| ---- | ------------- | ------------- |
| A | HtoD then SiLU | SiLU only |
| B | (HtoD+SiLU) ∥ HtoD | SiLU ∥ HtoD |
| C | HtoD, wait, SiLU, DtoH | SiLU then DtoH |

So a same-slice `A vs B` is **not** “same remaining work,
different schedule.” When `provisioned=1`, A has no copy left
and B still has one HtoD.

---

## 2. Stability on this grid

12 slices. Cost rank is always `bac`. Latency always puts
**A first**.

```text
B < A   agreement    0 / 12     never
A < C   agreement   12 / 12     always
B < C   agreement    8 / 12     only k=8 or N=64M
mean Spearman ρ      0.167
```

The `B < A` mismatch is **stable** across `N ∈ {4M,16M,64M}`,
`k ∈ {1,8}`, and both provisioning modes. It is not a single
noisy point.

It is **not** yet evidence that `C_overlap` is the wrong
direction on real hardware in general. On this stand-in:

- `provisioned=1`: A is compute-only; B still pays a copy.
  A must win while `T_compute ≪ T_copy` (all 12 slices).
- `provisioned=0`: B issues two HtoDs; A issues one.
  A wins because the stand-in gives B more copy work.

The earlier 2742 vs 2681 µs pair was **cross-slice**
(`A, provisioned=0` vs `B, provisioned=1`) and is not a
same-slice rank.

`B < C` flipping with `k` / `N` is the only axis that looks
like a compute/copy-ratio effect: larger `k` or larger `N`
makes B beat C, matching “more compute or more copy changes
the wall-clock order of B vs C,” not B vs A.

---

## 3. Verdict

```text
On this stand-in, B<A mismatch is a stable structure
of the comparison, not a one-off measurement error.
```

It is **also** stand-in-specific: Score_3 credits overlap on
B against sequential A, while the timed A/B bodies do not
keep the same remaining copy+compute work.

```text
Do not open Cost v0.4 from this grid.
V3 remains a probe.
```

A later experiment that could separate “model error” from
“stand-in artifact” must time **the same remaining work**
on A and B (one HtoD + SiLU sequential vs overlapped) at
several `T_compute / T_copy` ratios, still under the frozen
metadata protocol.

---

## 4. Out of scope

```text
rewriting C_overlap / Score_3
new T kind
claiming V3 pass
new 4090 sweep
```
