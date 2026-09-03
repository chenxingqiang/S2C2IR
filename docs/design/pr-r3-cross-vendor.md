# PR-R3: 4090 vs 910B scoped cross-vendor schedule

**Status:** compiler witness. Not Cost v0.4. Does **not** overwrite
`#69`, densify 910B `C||C` grids, invent `910B C||C = parallel`,
add Schema v1 keys, or claim V3.

```text
Same S²C² IR
+ Same semantic contract
+ Scoped measured evidence per hardware
→ legal realization may differ

Insufficient evidence → keep
Guessing parallel/serial → forbidden
C||C must disagree            → not required
Catalog ≠ Phase evidence ≠ Rewrite license
seq-slack=1.05                ≠ Cost / HB / semantics
npu-demo inferred             ≠ this witness
```

## Why this cut

`#74` licensed one 910B regime:

```text
910B C||C  r≈1  named-nonblocking  payload 128MiB..512MiB
    rewrite_license=yes
```

`#69` catalog `C||C` stays `underdetermined`. 4090 occupancy
`C||C` is a device-wide `size_range=n/a` serial cell.

The old inequality gate

```text
pair_relation_4090 != pair_relation_910B
```

is **sufficient but not required**. Requiring `C||C` to produce two
schedules would either invent a 910B parallel cell or overwrite
`#69`. This increment instead witnesses:

> The same program, under the same semantic contract, receives a
> legal realization from each hardware's **scoped** measured
> evidence. If that evidence is missing or unlicensed, the
> compiler keeps the original schedule instead of guessing.

## Witness IR

Same two `sched.concurrent { elemwise, elemwise }` functions.
Payload bytes = `N` floats × 4.

| IR payload | 4090 occupancy `C||C` | 910B overlay | `#69` catalog |
| ---------- | --------------------- | ------------ | ------------- |
| 16MiB (N=4M, mixed band) | serialize (`n/a` serial, licensed) | keep (`mixed`, `rewrite_license=no`) | keep (`underdetermined`) |
| 128MiB (N=32M, licensed serial band) | serialize | serialize (`serial` + A/B license) | keep (`underdetermined`) |

```text
16MiB:   Schedule_4090 ≠ Schedule_910B     (scoped evidence differs)
128MiB:  Schedule_4090 = Schedule_910B     (both licensed serial)
#69:     never serializes C||C             (do not guess)
```

That is the product. Mixed / transition bands stay unlicensed.
Flattening is parent IR order, not a sibling `sched.wait`.
`--check-s2c2-execution` after every rewrite.

## R3 Gate (refined)

```text
Same IR ∧ same pair contract
Hardware A: measured scoped cell → decision_A ∈ {keep, serialize}
Hardware B: measured scoped cell → decision_B ∈ {keep, serialize}
Insufficient ∨ rewrite_license=no ∨ not serial → keep
```

A disagreement of `pair_relation` is allowed when both cells are
applicable. It is **not** a requirement that `C||C` disagree.
`npu-demo` inferred parallel is not production R3.

## Out of scope

```text
Cost v0.4 ranking
overwriting #69
more 910B C||C r/N points
inventing 910B C||C = parallel
D2D / P2P / ROCm
Schema v1 extra keys
```
