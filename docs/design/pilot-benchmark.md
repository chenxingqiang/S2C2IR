# S²C² Pilot / Research Validation

Status: **pilot design**. Not v0.5.x. Does **not** add a kind,
Search algorithm, Cost axiom, or backend. Architecture v0.5.0–
v0.5.2 stay frozen at `c27f2fd` (`#42`). This layer asks whether
the frozen stack is **empirically usable** on three stand-in
workloads.

```text
Research Prototype  —  this document
Production compiler —  out of scope (no real backend / runtime)
```

Shapes are scaled-down (`tensor<8xf32>`). They stand in for
SSD→HBM→Compute, Compute∥Comm, and three-stage Pipeline. They
are **not** a hardware benchmark.

---

## 1. Why a Pilot now

The frozen stack already answers:

```text
Is M legal?     Enum_F / IsLegal
Which M score?  Score_3 / ArgMin_F / Pareto_F
Does T keep HB? T_reorder on concurrent siblings
```

It does **not** yet answer:

```text
Does rank(Cost) match rank(real latency)?
```

That needs a backend. Pilot V1–V2 run here. V3–V4 need hardware.

---

## 2. Three cases

| ID | Func | Pattern |
| -- | ---- | ------- |
| A | `@pilot_a_ssd_hbm_compute` | pack SSD → stream → wait → unpack HBM → compute |
| B | `@pilot_b_compute_par_comm` | Concurrent: compute ∥ SSD→HBM stream |
| C | `@pilot_c_pipeline_three_stage` | StageOrder: prefetch / compute / writeback |

File: `test/Pilot/s2c2-pilot-workloads.mlir`.

Frozen compiler scores (F_0, `--s2c2-cost-cp` / `--s2c2-argmin`):

```text
A  GPU/NPU 130   <  CPU/CIM 137
B  GPU/NPU 128   <  CIM 129  <  CPU 136
C  GPU     163   <  NPU 164  <  CPU 173  <  CIM 177
```

`|Enum_F| = 8` on all three (non-empty body + F_0 capability).

`T_reorder` accepts only B (`hb-eq=1`, `x-rebuilt=8`). A and C
have no HB-independent concurrent sibling pair (`accepted=0`).

---

## 3. Validation gates

```text
V1  Semantic     --check-s2c2-execution   (this PR)
V2  Enumeration  Output = R ∩ F, count=8  (this PR)
V3  Cost rank    rank(Cost) ≈ rank(Latency)   NEEDS backend
V4  Transform    HB-preserving T improves a measured metric
                 NEEDS executable + metric
```

V3/V4 are **acceptance criteria for a later experiment**, not
FileCheck in this repo until a real target exists.

---

## 4. Out of scope

```text
v0.5.3+ architecture
--s2c2-search / beam / more kinds
real GPU / NPU / SSD runtime
kernel generation
claiming hardware speedups
changing Cost / HB / R
```
