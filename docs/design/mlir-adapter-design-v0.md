# MLIR Adapter Design v0

**Status:** design boundary. This page adds no code.
Not an IR change. Not a new contract. Not an inhabitant
change. Baseline
`36fd6fd931c109c6849cc366bd91b5abdfcab4b1`.
The spellable-field text extract already on main is
`runtime/record_mlir_carrier.py`. This page does not
extend it and does not register a dialect.

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

## Carrier extraction

A successful extract is a function of the canonical
carrier region only. The same region yields the same
host program. Two extracts are equal only when that
spellable structure is equal.

```text
blocks[].ops[].name
blocks[].ops[].op
blocks[].ops[].op-id
capacity
working-set
hb            optional; omitted means program order inside each block
```

`induced-hb` is not in this list. It is not source
canonical text. extract does not read it and does not
invent it.

```text
same canonical carrier region
        ↓
same extracted host program
```

## External inputs

These are not carrier fields. They enter only as
arguments of the later host call, or as host-side data
a caller already has. extract does not fill them in
when they are absent.

```text
device D             evaluate_apply's device argument
7B envelope          already produced; not re-authorized
witness              external; schema s2c2.apply_legality_witness.v1
candidate-id         canonical(P'), computed by the host
IsLegal              external oracle
induced-hb           host-side fixture or constructor field
```

## Determinism

```text
same carrier text
        ↓
same extracted program
```

The same carrier text with a different `device` still
extracts the same program. `ApplyResult` may differ,
because `device` is an `evaluate_apply` argument. That
difference is not a carrier decision.

The same carrier text with `induced-hb` attached
afterward is no longer the extract result. The outcome
is not determined by the carrier. Absence of
`induced-hb` is absence. It is not a signal to copy a
fixture, and it is not described as encoded.

## extract

Input of the projection: the canonical carrier region.
Output: the spellable host program, or refuse.
`device` is not an extract input.

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

Two different refusals stay separate. Neither one is a
new contract.

The W0-3/2 acceptance entry refuses before
`bound_witness` and before `evaluate_apply` when the
carrier text does not parse, or when the extracted
program is not one acceptance region. That includes zero
regions, two regions, capacity other than 2, a working
set that is not above 2, and fewer than three stores.
The caller does not get an `ApplyResult` from that
refusal.

After a spellable extract that meets that entry, the
existing host contract still decides. KEEP order, HB*
failure, a missing witness, a wrong device, and an op-id
collision stay inside `evaluate_apply`. This page does
not add an authorization and does not add a semantic.

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

Naming a carrier dialect is an IR change and is not part
of this design. The text extract on main spells only the
carrier fields above. This page does not add another
extract. The host contract does not claim to parse MLIR.
A missing external field is not a contract gap.

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
