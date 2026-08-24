# Compiler Decision Model (Capability-Aware)

Status: **frozen claim**. Not Cost v0.4. Does **not** change
HB axioms, `R`, Search `A`, Transformation, Pilot IR, A/B/C
bodies, or any `--cuda-val*` timed body. Baseline: `dda0d2e`
(`#62`).

This document freezes what the 4090 evidence is *for*.
It is not a new CUDA arm and not a Cost formula.

```text
faster kernel              !=  the contribution
two streams                !=  physical concurrency
Capability matrix          !=  a dataset archive
Cost v0.4                  !=  this layer
V3                         !=  claimed
```

---

## 1. What is frozen

```text
Semantic Concurrency  !=  Capability  !=  Runtime Constraint
Slow                  !=  Serialized  !=  Semantically Dependent
Concurrent Semantics  !=  Physical Concurrency
```

Scheduler question (allowed):

```text
On this hardware target, what is the Capability of this
execution pair?
```

Scheduler question (not allowed as a substitute):

```text
Do these two tasks use different CUDA streams?
```

Hardware specialization without IR specialization:

```text
Semantics(P)                 unchanged
CapabilityProfile(H)         per target
Mapping(P, H_A)  !=  Mapping(P, H_B)
```

---

## 2. Three different reasons a pair looks "slow"

| Bucket | Meaning | 4090 witness | Compiler consequence |
| ------ | ------- | ------------ | -------------------- |
| Semantic dependency | source HB already orders the pair | StageOrder / SW / PO | must preserve `HB_source ⊆ HB_lowered` |
| Runtime-added constraint | realization inserted extra HB | `#60` legacy default stream; `extra_hb=legacy-default` | reject / rewrite the realization; not a semantic edge |
| Hardware resource contention | named, legal, still no overlap | `#63` SiLU\|\|GEMM; `observed_constraint=resource_contention`; `extra_hb=not-applicable` | overlap benefit ≈ 0; may pick a serial *realization* of a concurrent *semantic* |

Two more rate facts that are **not** extra HB:

```text
#61  pageable host     Storage property → Communication rate
#62  MallocAsync+wait  Storage lifetime + legal SW → valid CUDA
                       observed_constraint = none
```

```text
serialization/constraint
├── legacy_default          #60   extra_hb = legacy-default
├── resource_contention     #63   extra_hb = not-applicable
└── allocator_sync          #62   candidate; not observed on 4090
```

Do not dump all of these into `extra_hb`. `#60` reserved
`extra_hb` for runtime-added sync.

---

## 3. What a later optimizer may do

Legal schedule space is already frozen (`ValidSchedules`,
NoOrderingRequirement). Capability does not invent semantic
dependency.

```text
Candidate A:  C || HtoD
  4090 named nonblocking → pair_relation = parallel
  → keep concurrent realization

Candidate B:  SiLU || GEMM
  4090 named             → pair_relation = serial
                          observed_constraint = resource_contention
  → semantically legal concurrent
  → no expected overlap benefit
  → optimizer may select a serial realization

Candidate C:  C || HtoD on legacy default
  → extra_hb = legacy-default
  → not a capable realization of Concurrent
```

Invariant for any later `--s2c2-capability-schedule`:

```text
Capability optimization preserves semantic validity
Concurrent → serial realization   allowed
Pipeline StageOrder               must not be broken
HB_before ⊆ HB_after
```

First version asks only:

```text
Which schedules are legal?
Which schedules are realizable on this profile?
Which schedules are likely beneficial?
```

It does **not** rank by Cost.

---

## 4. Out of this freeze

```text
Cost v0.4 rewrite
more 4090 microbenchmarks as the next increment
claiming V3
changing S^2C^2 Semantics
treating #59 schema as Cost
Capability pass that invents sibling HB
```

Next compiler-facing increment is implemented:

[`v3-capability-schema.md`](v3-capability-schema.md),
[`capability-aware-schedule.md`](capability-aware-schedule.md)
(`--s2c2-capability-query`, `--s2c2-capability-schedule`).
Capability data enters the compiler decision path.

```text
Program → S^2C^2 → Hardware Capability → Legal Realization → Schedule
```
