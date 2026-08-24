# S²C² Ascend 910B C∥C size-boundary sweep

**Status:** measurement. Not Cost v0.4. Does **not** change HB,
`R`, Search, Transformation, `--s2c2-capability-schedule`,
Schema v1 keys, the #69 pair catalog, R4 memory records, or the
#71 r-sweep cells. PR-R3 stays closed.

```text
size boundary          ≠  a Cost axiom
r ≈ 1                  ≠  ∀ r
#69 underdetermined    ≠  this increment overwrites it
N_transition           ≠  open PR-R3 by itself
```

## Why this cut

`#71` showed that within `r ∈ [0.5, 2]`:

```text
4M   mixed × 5
16M  serial × 5
64M  serial × 5
```

So further r-grid densification has low value. The remaining
question is the **N** axis at matched compute:

```text
r ≈ 1
N ∈ {4M, 8M, 12M, 16M, 32M, 64M, 128M} floats
```

Goal: locate, if it exists,

```text
N_transition : mixed → serial
```

Do not majority-vote `#69` `C||C` to serial. Do not claim
`∀ r`. Quote any size law as **within r≈1**.

## Protocol

Reuse `--cc-phase` with `--r=1` and `k_ref=32`. Named streams.
`T_pair = completion(s0,s1)`. Elemwise `y←2x+1`. Classifier
slack unchanged.

A monotonic mixed* then serial* walk is a boundary. Mixed after
serial is `transition=underdetermined`. All mixed or all serial
is `transition=none`.

## R3 Gate

Unchanged from `#71`. A size-conditioned profile is only a
**candidate** after a stable boundary is measured. This
increment does not rewrite schedules.

## Out of scope

```text
Cost v0.4
extra r-grid
4090 retest
D2D / P2P
opening PR-R3
overwriting #69 / #71
```
