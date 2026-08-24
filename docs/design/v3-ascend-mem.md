# S²C² Ascend 910B pinned vs pageable (R4)

**Status:** measurement. Not Cost v0.4. Does **not** change HB,
`R`, Search, Transformation, `--s2c2-capability-schedule`,
the #69 pair catalog, or Schema v1 keys. PR-R3 stays closed.

```text
Host residency     ≠  a Cost axiom
pageable HtoD      ≠  a Schedule rewrite
stor.space<host>   ≠  one Ascend realization
#69 pair catalog   ≠  this increment
PR-R3              ≠  this increment
```

## Questions (kept separate)

```text
1. Communication rate:   T_pageable / T_pinned  ?
2. Extra HB / overlap:   does pageable serialize C || copy?
```

A bandwidth-only gap without a serial flip is **not** extra HB.

Counterexample:

```text
pinned   C||HtoD  →  parallel
pageable C||HtoD  →  serial     (ovl/sum ≥ 0.90)
```

and/or the same flip on `C||DtoH`.

A mixed cell with `ovl/max ≤ 1.15` is still max-like (r-unbalance
from a slower pageable copy), not extra HB.

## Grid

Named streams. `T_pair = completion(s0,s1)`.
`N ∈ {4M,16M,64M}` floats. `k=0` calibrates from pinned HtoD /
compute(k=1). Schema v1 `size_range` is payload **bytes**, not the
N label:

```text
N floats              4M         16M         64M
payload bytes         16MiB      64MiB       256MiB
size_range            16MiB..256MiB
```

Do not write `4MiB..64MiB`: that would treat element counts as
bytes, exclude the measured 256MiB arm from Applicability, and
apply the cell to unmeasured 4MiB payloads.

```text
pinned  = aclrtMallocHost
pageable = malloc
```

Pairs: `C||HtoD`, `C||DtoH`. Compute is `elemwise` (`y←2x+1`).

CANN: page-locked `aclrtMemcpyAsync` may return before the copy
completes; non-page-locked `aclrtMemcpyAsync` waits until the copy
completes. That is a residency → communication fact to measure,
not extra HB until a serial flip is observed.

Do not FileCheck microseconds. Do not compare 4090 μs to 910B μs.
Do not invent extra HB.

## 910B result

`correctness=1` on all arms. `counterexamples=0`.

Pageable copies can be slower (especially 4M). Overlap never
flipped pinned-parallel → pageable-serial. 16M stays parallel
for both residencies. 64M pageable `C||copy` is mixed, not serial.

```text
Communication rate  =  f(residency, direction, size)
C || copy           does not gain extra HB from pageable host
                    on this elemwise / named-stream / N grid
extra_hb            =  none
```

`#69` pair catalog is unchanged. PR-R3 stays closed.

