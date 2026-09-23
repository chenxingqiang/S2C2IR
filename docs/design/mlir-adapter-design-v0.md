# MLIR Adapter Design v0

**Status:** DESIGN REVIEW = PASS. READY / NOT IMPLEMENTED.
Implementation is not authorized. Not an IR change.
Not a new contract. Not an inhabitant change.
Baseline `36fd6fd931c109c6849cc366bd91b5abdfcab4b1`.

Host: `runtime/record_storage_apply.py` `evaluate_apply`.
Plan source: the existing 7B envelope. The adapter does not
build it.

```text
MLIR region
    ↓
extract          projection only
    ↓
host program     the dict evaluate_apply already consumes
    ↓
evaluate_apply   unchanged
    ↓
ApplyResult      unchanged
```

The adapter adds no semantic. It does not own match, HB*,
legality, or commit.

## Determinism

A successful extract is a function of the canonical MLIR
region. The same canonical region yields the same host
program. Two extracts are equal only when that relevant
canonical structure is equal.

```text
same canonical MLIR region
        ↓
same host program
```

This is an interface constraint. It does not add a
semantic, a dialect, or a new canonical-form definition.
Until a carrier exists, the constraint is stated and not
implemented.

## extract

Input: one MLIR region, plus the device string the host
already takes. Output: the host program, or refuse.

The program may contain only fields the host already reads:

```text
blocks[].ops[].name
blocks[].ops[].op
blocks[].ops[].op-id
capacity
working-set
hb            optional; omitted means program order inside each block
induced-hb    optional; not part of source canonical text
```

Refuse, before `evaluate_apply`, when a field would have
to be invented:

```text
op has no name or no op-id
capacity or working-set is absent
more than one block is not a reason to merge blocks
a second device is not a reason to pick one
a router result is not a reason to choose E
```

Refusal is not a new `ApplyResult` and not a new reason
token. The caller does not get `applied=yes`.

```text
adapter rejection
    ≠
Apply match=no
    ≠
Apply applied=no
```

If the projection succeeds, extract does not interpret it.
Zero regions, two regions, capacity other than 2, KEEP
order, HB* failure, a missing witness, a wrong device, and
an op-id collision stay inside `evaluate_apply`.

## What stays outside extract

```text
7B envelope          already produced; not re-authorized
witness              external; schema s2c2.apply_legality_witness.v1
candidate-id         canonical(P'), computed by the host
IsLegal              external oracle
device D             the existing evaluate_apply argument
```

extract must not call `evaluate_authorization`.

## Workload boundary

W1, three stores, capacity 2, one device: the projection
is the host program. EXPRESSIBLE scenes stay EXPRESSIBLE.

W2 routing and W3 cross-device overlap do not become
fields. An adapter that stored a router choice or a second
device would be a new semantic. Those scenes stay
OUTSIDE-CONTRACT.

## Gap check

This interface does not need a new IR witness schema, a
new identity, a new event, or a new plan format. evict,
transfer, and restore are still produced by
`construct_candidate`. The plan is still the 7B envelope.

There is no checked-in MLIR op for this pattern. Naming a
carrier dialect is an IR change and is not part of this
design. Until that carrier already exists, extract is
unspecified and unimplemented. That absence is not a
contract gap. The host contract does not claim to parse
MLIR.

Gate A is a real MLIR carrier. Only then is it worth
reviewing an implementation of extract.

## Not in this design

```text
implementation
s2c2-opt
Enum_F
Search
can-run-plan
routing semantics
cross-device execution semantics
generic rewrite
authorization changes
hardware execution
W0-3/4
```

`compiler-e2e` stays no.
NEXT CUT stays NOT OPENED.
