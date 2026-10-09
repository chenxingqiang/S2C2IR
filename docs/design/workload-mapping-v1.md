# Workload Mapping v1

**Status:** evidence only. Not a contract change. Not code.
Not an IR change. Baseline
`36fd6fd931c109c6849cc366bd91b5abdfcab4b1`.
Scenario Corpus v1 is not extended here.

Evidence scope: semantic reduction against frozen W0-3/2.
Not a measured workload. Not compiler E2E. Not hardware.
Not `s2c2-opt`. `can-run-plan` stays no.

Frozen pattern this record may call EXPRESSIBLE:

```text
one contiguous region in one block
exactly three named stores K1, K2, E
no other store in that window
capacity = 2
working-set > capacity
KEEP K1, KEEP K2, EVICT E, TRANSFER E, RESTORE E
one device D
HB* on Im(π_R) preserved
external witness binds canonical(P') and D
```

Object text of the frozen plan is `"2"`.
Selected text of the frozen plan is
`keep{0,1}|evict{2}|rematerialize{}`.
A different selected string is identity-mismatch, which
the contract already emits. That rejection is not a new
semantic.

```text
EXPRESSIBLE        the scene reduces to the pattern above
INVALID            the contract already rejects it
OUTSIDE-CONTRACT   the relation is not that pattern
```

```text
A  input is illegal for this plan
B  contract can express the outcome; plan or witness is absent
C  the contract cannot express the relation
```

Only C is a candidate real semantic gap.
This record does not open a cut.

## W1  kv-capacity-pressure

LLM decode keeps a KV working set in one device memory.
Pressure is three live KV blocks and room for two.

semantic objects: KV0, KV1, KV2 as three stores.
storage relation: capacity 2, working-set 3, keep two, evict one.
compute relation: attention reads the kept blocks. Not part of T.
communication relation: one transfer of the evicted block, then one restore.
HB relation: program order of the three stores, preserved on the image of π_R.
candidate realization shape: keep-evict-transfer-restore of that one triple.

current contract: EXPRESSIBLE

The reduction is the acceptance pattern.
One block, three stores, capacity 2, one evict, one transfer,
one restore, one device. If the realized identity is not the
frozen plan identity, the contract already says `match=no`
and `rewrite.identity-mismatch`. If the witness is missing
or names another device, the contract already says
`match=yes`, `applied=no`. Those are A/B, not a new relation.

A KV cache with capacity other than 2, or more than three
live blocks, is the same storage-pressure mode with a
different parameter. The frozen contract rejects it
(`match=no`). That is INVALID for this plan. It is not
evidence for a W0-3/4 cut.

required new semantic? no

## W2  moe-expert-working-set

A token routes to a changing subset of expert weights.
The live set is chosen by the router, then weights move.

semantic objects: expert weights, plus a routing decision.
storage relation: a working set of experts against device capacity.
compute relation: the active experts run; the router result picks them.
communication relation: expert load, often collective, not one evict edge.
HB relation: the evict set is data-dependent. It is not three static stores.
candidate realization shape: not one static keep-evict-transfer-restore triple.

current contract: OUTSIDE-CONTRACT

W0-3/2 matches one static store triple. It has no object for
"the router selects E". Rewriting three frozen experts as
stores 0, 1, 2 would delete the routing relation. What
remains would be EXPRESSIBLE, and it would no longer be this
workload. Class C. This is a different abstraction, not a
larger capacity on the same pattern.

A static three-expert, capacity-2 slice with no router is
EXPRESSIBLE, and it is not W2.

required new semantic? not for this contract.
Extending W0-3/2 would not state routing.
A routing contract is a different subject. This record does
not open it.

## W3  heterogeneous-storage-movement

GPU, NPU, and CIM memories move values across devices.
Transfer is asynchronous and can overlap compute in both
directions.

semantic objects: a value, plus at least two devices.
storage relation: residency changes across memories.
compute relation: overlap with transfer. That is a schedule.
communication relation: bidirectional cross-device transfer.
HB relation: overlap edges between devices.
candidate realization shape: not one evict on device D.

current contract: OUTSIDE-CONTRACT

The witness binds one device D. `transfer` and `restore`
are machinery of one evicted store. A second device, a
reverse transfer, or overlap with compute is not that
pattern. Wrong-device on a W0-3/2 program is already
INVALID: `match=yes`, `applied=no`. W3 is not that failure.
Class C. Current W0-3/2 only models one storage-capacity
rewrite.

required new semantic? candidate only.
Not opened. Not `can-run-plan`. Not `Enum_F`. Not a CIM dialect.

## Judgment

```text
W1  EXPRESSIBLE        same pattern; capacity≠2 stays INVALID
W2  OUTSIDE-CONTRACT   routing is a different abstraction
W3  OUTSIDE-CONTRACT   cross-device async overlap is a different relation

REAL SEMANTIC GAP THAT OPENS A CUT = NONE PROPOSED
NEXT CUT = NOT OPENED
```

W2 and W3 do not show that the frozen pattern is unable to
say what it claims. They show those workloads do not reduce
to it. Gate B is a real workload that proves the contract
cannot express a relation it would have to carry. Until
that evidence exists, no new contract is proposed.
