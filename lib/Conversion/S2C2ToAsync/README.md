`--convert-s2c2-token-to-async` is Phase 2B slice 1:

```text
!sched.token  →  !async.token
sched.wait    →  async.await
```

Acceptance: **HB-preserving lowering**, not “async works.”

Design: `docs/design/phase2b-token-to-async.md`.

`--convert-s2c2-concurrent-to-async` is Phase 2B slice 2:

```text
sched.concurrent { A, B, C }  →  async.execute A / B / C
```

Acceptance: **HB-preserving concurrent lowering**. Lexical sibling
order does not invent `async.await`.

`--convert-s2c2-pipeline-to-async` is the v0.1 pipeline slice:

```text
S1 → await → S2 → await → Sk
```

Acceptance: **StageOrder is preserved**, not “pipeline parallelism.”

Composition (no new semantics): run the three passes in this order on
one program (`docs/design/phase2b-composition.md`, test X1):

```text
--convert-s2c2-token-to-async
--convert-s2c2-concurrent-to-async
--convert-s2c2-pipeline-to-async
```

Not in these slices: overlap, iteration IR, memref/DMA, conflict/race
analysis. Phase 2B semantic verification is **frozen**.
