# S²C² Ascend 910B C∥C phase sweep

**Status:** measurement. Not Cost v0.4. Does **not** change HB,
`R`, Search, Transformation, `--s2c2-capability-schedule`,
Schema v1 keys, the #69 pair catalog, or R4 memory records.
PR-R3 stays closed until the R3 Gate below holds.

```text
C||C phase             ≠  a 3-pair re-matrix
r = T_C1 / T_C2        ≠  a Cost axiom
#69 underdetermined    ≠  this increment overwrites it
unique relation        ≠  open PR-R3 by itself
```

## Why this cut

`#69` projected `C||C` as `underdetermined` because sizes disagree:

```text
4M   mixed
16M  serial
64M  serial
```

Scheduler must keep concurrent. This increment measures one pair
along two axes:

```text
Capability_910B(C, C, r, N)
r = T_C1 / T_C2
N ∈ {4M, 16M, 64M} floats
```

First-cut `r_target`:

```text
0.5 / 0.75 / 1.0 / 1.5 / 2.0
```

The goal is a region map, not a pretty scalar:

```text
parallel | mixed | serial | underdetermined
```

Do not majority-vote the #69 cell. If `(r,N)` still disagree,
the pair catalog stays `underdetermined`.

## Protocol

Named streams. `T_pair = completion(s0,s1)`. Elemwise `y←2x+1`.
`k2 = k_ref` (default 32, same as #69). `k1 = max(1, round(r·k2))`.
Solo `T_C1(k1)`, `T_C2(k2)`, then overlap `T_par(k1 on s0, k2 on s1)`.
`r_achieved = T_C1 / T_C2`. Classifier slack unchanged.

```text
par/sum ≥ 0.90                         → serial
par/max ≤ 1.15  and  par/sum ≤ 0.75    → parallel
else                                   → mixed
```

Serial `C||C` still stamps `observed_constraint=resource_contention`
(same harness rule as #69). That is a measurement label, not a
proof that 910B contention equals 4090 SM occupancy.

Do not FileCheck microseconds. Do not compare 4090 μs to 910B μs.
Do not store host / password / IP.

## R3 Gate (frozen for this measurement PR)

The inequality form below is **sufficient but not required**.
Opening R3 does not demand `C||C` disagree, and does not invent a
910B parallel cell. See [`pr-r3-cross-vendor.md`](pr-r3-cross-vendor.md).

```text
For the same semantic pair:
  hardware A:
      confidence = measured
      applicable = yes
      pair_relation ∈ {parallel, serial, mixed}

  hardware B:
      confidence = measured
      applicable = yes
      pair_relation ∈ {parallel, serial, mixed}

AND
  pair_relation_A != pair_relation_B
```

or the same relation with a different `observed_constraint`.

This measurement PR did not open R3 and does not compare 4090 vs
910B microseconds.

## Out of scope

```text
Cost v0.4
4090 extra matrix
D2D / P2P
full 3-pair re-sweep
opening PR-R3
```

## 910B result

`correctness=1`. `unique=no`. `#69` `C||C` stays `underdetermined`.
PR-R3 stays closed.

```text
          r=0.5    0.75     1.0      1.5      2.0
4M        mixed    mixed    mixed    mixed    mixed
16M       serial   serial   serial   serial   serial
64M       serial   serial   serial   serial   serial
```

No parallel cell on this first-cut `r` grid. 4M stays mixed for
every `r`. 16M and 64M stay serial with
`observed_constraint=resource_contention` for every `r`.

So on this regime:

```text
Capability_910B(C, C, r, N)
  ≈  f(N)
  not f(r) for r ∈ [0.5, 2]
```

That is still not a single applicable pair_relation. Do not
majority-vote `serial`. Do not invent `parallel`.

Files: `docs/design/v3-dataset/ascend910b/cc-phase.log`,
`cc-phase.csv`. Do not FileCheck microseconds.
