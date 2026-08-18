`--convert-s2c2-token-to-async` is Phase 2B slice 1:

```text
!sched.token  →  !async.token
sched.wait    →  async.await
```

Acceptance: **HB-preserving lowering**, not “async works.”

Design: `docs/design/phase2b-token-to-async.md`.

Not in this slice: concurrent → many `async.execute`, pipeline, overlap,
memref/DMA, conflict/race analysis.
