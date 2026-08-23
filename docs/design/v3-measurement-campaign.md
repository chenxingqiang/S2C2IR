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

## 3. Out of scope

```text
changing C_overlap / Score_3
new T kind
new Pilot IR
claiming V3 / Spearman
real SSD
```
