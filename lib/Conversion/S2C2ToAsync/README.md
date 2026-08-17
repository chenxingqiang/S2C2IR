Reserved for Phase 2B: event-preserving `!sched.token` → `!async.token`.

Phase 2A `--sequentialize-s2c2-schedule` and `comm.stream` → `memref.copy`
are a **blocking baseline**. They erase completion consumers and must not
be treated as the definition of S²C² schedule or communication semantics.
