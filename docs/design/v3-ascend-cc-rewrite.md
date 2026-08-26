# S²C² 910B C∥C rewrite-license A/B

**Status:** measured. Not Cost v0.4. Does **not** open PR-R3,
overwrite `#69`, densify the r/N grid, or add Schema v1 keys.

```text
Observed serial     ≠  rewrite license
T_par ≈ T_sum       ≠  serialize is beneficial
seq-slack=1.05      ≠  a Cost axiom
Capability limitation ≠ Optimization opportunity
#69 underdetermined ≠  this overlay
```

## Why this cut

`#73` made size bands queryable and kept mixed / transition
unlicensed. This increment asks one question inside a **narrow
regime**:

```text
910B
C||C
N ∈ {32M, 64M, 128M} floats     payload ≥ 128MiB
r ≈ 1
k_ref = 32
named-nonblocking
```

Is a sequential realization **not worse** than named concurrent?

```text
T_seq  = C1 on s0 to completion, then C2 on s1
T_par  = existing T_pair = completion(s0,s1)
seq/par ≤ 1.05  →  benefit=yes
```

License only if **every** N in the grid is `serial` **and**
`benefit=yes`, with `correctness=1` on both arms.

```text
serial + benefit yes → rewrite_license=yes
serial + benefit no  → rewrite_license=no
non-serial           → rewrite_license=no
```

```text
Applicable ∧ Measured ∧ Stable ∧ RewriteLicensed
    →  flatten 2-task concurrent into parent IR order
```

That is not Cost v0.4. Do not FileCheck microseconds.

## A/B

Both arms check `y←2x+1` on dest2/dest3. Sequential is parent IR
order, not a sibling `sched.wait`.

Mixed / transition bands stay `rewrite_license=no`.

## Measured result

Log: `docs/design/v3-dataset/ascend910b/cc-rewrite.log`.

| N | pair_relation | seq/par | benefit | license |
| - | ------------- | ------- | ------- | ------- |
| 32M | serial / resource_contention | 0.247 | yes | yes |
| 64M | serial / resource_contention | 1.011 | yes | yes |
| 128M | serial / resource_contention | 1.012 | yes | yes |

Analyzer: `relations=serial`, `benefit=yes`, `rewrite_license=yes`.

32M `T_par` is the same outlier class as `#72` (`par/sum` ≫ 1).
Do **not** freeze that ratio as Cost. 64M / 128M `seq/par ≈ 1.01`
is the stable matched evidence: named concurrent has no benefit
inside the slack, so a sequential realization is allowed.

The overlay serial band (`128MiB..512MiB`) is therefore
`rewrite_license=yes`. Mixed and transition bands stay `no`.
`#69` `C||C` stays `underdetermined`.

## R3

Closed. 4090 occupancy `C||C` is a device-wide serial cell.
Licensing one 910B size band is a different evidence structure,
not a cross-vendor schedule product gate.

## Out of scope

```text
Cost v0.4 ranking
opening PR-R3
overwriting #69
more r or N points
D2D / P2P / ROCm
```
