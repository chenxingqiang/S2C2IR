# Scenario Corpus v1

**Status:** engineering replay of the sealed baseline
`71a6880dbaaac929bac837af0b7fbcad78708bb4`.
Not a contract change. Not an inhabitant change.
Not `Enum_F`. Not Search. Not `can-run-plan`.

The acceptance anchor
`w0-3-2-storage-capacity-001` stays the single success pin.
This corpus replays that producer chain across ten scenes
and pins one behavior fingerprint.

```text
authorization → 7B rewrite-plan → evaluate_apply
        ↓
S01..S10
        ↓
fingerprint
        ↓
PASS / DRIFT
```

| ID | Scene | Expected |
| -- | ----- | -------- |
| S01 | canonical success | `match=yes`, `applied=yes`, pinned `canonical(P')` |
| S02 | KEEP order differs | `match=no`, `rewrite.identity-mismatch` |
| S03 | multiple regions | `match=no` |
| S04 | cross-block | `match=no` |
| S05 | HB* violation | `match=yes`, `applied=no` |
| S06 | missing witness | `match=yes`, `applied=no` |
| S07 | wrong device | `match=yes`, `applied=no` |
| S08 | op-id collision | `match=yes`, `applied=no` |
| S09 | transformation mismatch | `match=no`, `decision.unknown-reason` |
| S10 | source and envelope immutability | unchanged, second success run equal |

S09 starts from the real 7B envelope and changes only
`transformation`. It does not build a parallel plan producer.

`can-run-plan` stays no on every scene. Failure leaves the
source program and the envelope unchanged. S01's result
digest is the acceptance anchor's `canonical(P')` digest.
`authorization-reopened` is the observed call count during
`evaluate_apply`. A call fails the corpus before PASS.
The producer may still call authorization while building
the 7B envelope.

```bash
python3 runtime/record_scenario_corpus.py --print-scenario-corpus
```

Evidence scope stays contract-level and host-level.
`compiler-e2e` stays no. A fingerprint change is drift of
this host, not by itself a new semantic cut.
