# Evidence-Bounded Schedule Optimizer

**Status:** project narrative + first end-to-end slice. Not Cost v0.4.
Does **not** densify Capability matrices, overwrite `#69`, invent
`910B C||C = parallel`, or open Search ranking.

```text
Evidence-backed, hardware-aware schedule realization
```

```text
S²C²
  = Semantic Execution IR
  + Hardware Capability Model
  + Evidence-Bounded Schedule Optimizer
```

Hardware evidence is local, conditional, and noisy. The compiler
must not promote one benchmark into a global rewrite law.

```text
No evidence  ⇒  no destructive optimization
```

## Three decision layers

```text
1. Semantic
   sched.concurrent = NoOrderingRequirement
   does not promise physical parallelism

2. Capability
   what this hardware can do in this regime
   Capability = f(hardware, pair, size, r, residency, sync, resource)

3. Optimization authorization
   serial ∧ applicable ∧ measured ∧ benefit proven
       ⇒ rewrite_license = yes
   answers: may the compiler change the program?
```

`Rewrite License` is the product. Capability classification alone
is not a rewrite.

## Frozen invariants

```text
1. Semantic dependency     ≠  performance serialization
2. Capability classification ≠  rewrite authorization
3. Scoped evidence         ≠  global rule
4. Unknown / underdetermined  ⇒  preserve
5. Rewrite must preserve semantic validity / HB
   HB_before ⊆ HB_after
   no invented sibling sched.wait
```

Pipeline:

```text
Measured Evidence
        ↓
Capability
        ↓
Applicability
        ↓
Rewrite License
        ↓
Schedule Transformation
        ↓
HB Verification
```

That is not Cost v0.4. `seq-slack=1.05` remains an optimizer
policy threshold.

## End-to-end slice (this increment)

One S²C² program with three stages:

```text
SSD prefetch || Gated MLP     (C||HtoD)
C||C at 16MiB                 (mixed / unlicensed on 910B overlay)
C||C at 128MiB                (licensed serial band on 910B overlay)
```

Same IR, three catalogs:

| Stage | 4090 | 910B overlay | `#69` catalog |
| ----- | ---- | ------------ | ------------- |
| prefetch \|\| MLP | keep (tiny payload outside 16MiB..256MiB) | keep (no overlay cell / not licensed) | keep (`C||HtoD` underdetermined) |
| C\|\|C 16MiB | serialize | keep (mixed, `rewrite_license=no`) | keep (underdetermined) |
| C\|\|C 128MiB | serialize | serialize (A/B licensed) | keep (underdetermined) |

`--check-s2c2-execution` after rewrite. `--s2c2-lower` still
produces a sequential realization. Flattening is parent IR order.

`T_opt / T_base` for the licensed `C||C` stage is the existing
910B A/B (`T_seq / T_par` in `cc-rewrite.log`). That is a
**stage measurement**, not a Cost axiom and not a full-model
wall-clock claim. 32M `T_par` stays an outlier.

## Out of scope

```text
Cost v0.4 ranking of candidate schedules
new 4090 / 910B Capability grid points
full SSD+MLP device wall-clock campaign
D2D / P2P / ROCm
overwriting #69
```
