# MLIR Carrier v0

**Status:** DESIGN ONLY. Not implemented. Not a lowering.
Not a new semantic model. Semantic baseline remains
`36fd6fd931c109c6849cc366bd91b5abdfcab4b1`.
This page does not change a dialect in the tree, the IR,
or Apply.

```text
Goal     name the syntax that projects onto the frozen host program
Not      routing, a second device, a new HB rule, or a new contract
Rewrite  still the existing 7B envelope; extract does not build it
```

Host: `runtime/record_storage_apply.py` `evaluate_apply`.
Parent inhabitant: [`ir-apply-inhabitant.md`](ir-apply-inhabitant.md).

```text
carrier text
    ↓
extract          projection only; not implemented here
    ↓
host program     the dict evaluate_apply already consumes
    ↓
evaluate_apply   unchanged
    ↓
ApplyResult      unchanged
```

```text
carrier = syntax / data carrier
carrier ≠ new semantic model
```

`stor.transfer` is not this carrier. That op allocates a
residency and copies a payload. The host string `"transfer"`
is a machinery step inside `construct_candidate`. Mapping
one onto the other would be a new meaning. This design
does not do that.

## Fields

extract may emit only fields the host already reads:

```text
blocks[].ops[].name
blocks[].ops[].op
blocks[].ops[].op-id
capacity
working-set
hb                 optional
induced-hb         optional; not part of source canonical text
```

No other attribute is a host field. A carrier that needs
one of the following has left this design:

```text
routing result
multi-device choice
new HB rule
new authorization
new rewrite license
Enum_F
Search
generic rewrite
can-run-plan
```

## Grammar

One module. Facts have no SSA results. Order of facts
inside a block is the host op order. Order of blocks is
the host block order. Attribute order is not order.

```mlir
module attributes {
  s2c2.carrier.capacity = 2 : i64,
  s2c2.carrier.working_set = 3 : i64
} {
  carrier.block {
    carrier.fact {name = "0", op = "store", op_id = "id0"}
    carrier.fact {name = "1", op = "store", op_id = "id1"}
    carrier.fact {name = "2", op = "store", op_id = "id2"}
    carrier.hb {from = "id0", to = "id1"}
    carrier.hb {from = "id1", to = "id2"}
  }
}
```

`carrier.fact` attributes are exactly `name`, `op`, and
`op_id`, each a string. `op_id` spells the host key
`op-id`. `carrier.hb` attributes are exactly `from` and
`to`, each a string op-id. Module attributes of this
carrier are exactly `s2c2.carrier.capacity` and
`s2c2.carrier.working_set`, each `i64`. `i1` is not an
integer capacity. The host rejects a boolean capacity;
the carrier does not spell one.

`carrier.hb` may be absent. Absence omits the host key
`hb`. The host then induces edges from op order inside
each block. Presence emits only the written pairs. extract
does not add induced edges beside written pairs.

`induced-hb` is not spelled in v0 source text. The host
reads it only when a later candidate constructor supplies
it. extract of source text does not invent it.

This grammar is a specification. This pull request does
not add `carrier.block`, `carrier.fact`, or `carrier.hb`
to TableGen.

## Canonicalization

Two texts are the same carrier when all of the following
hold:

- the same `i64` capacity and the same `i64` working-set
- the same blocks, in the same order
- inside each block, the same facts, in the same order,
  compared as `(name, op, op-id)`
- the same multiset of hb pairs, or both texts omit hb

These do not change the carrier:

- attribute order inside a fact or an hb edge
- source order of `carrier.hb` ops
- whitespace

Fact order is significant. extract does not sort facts.
Block order is significant. extract does not merge blocks
and does not sort blocks.

Host equality stays `canonical_program` in
`record_storage_apply.py`. extract does not define a
second canonical program. `CandidateId(P')` stays
`canonical(P')` on the host.

## extract boundary

Input: one module of the grammar above. Output: the host
dict, or a refusal.

Refusal happens before `evaluate_apply`. It is not an
`ApplyResult`. It does not mint a reason token. The caller
does not observe `applied=yes`.

```text
extract refusal
    ≠
Apply match=no
    ≠
Apply applied=no
```

Refuse when the text cannot be projected without
inventing a field:

- zero modules, or more than one module
- a `carrier.fact` or `carrier.hb` outside a `carrier.block`
- zero `carrier.block`
- a fact missing `name`, `op`, or `op_id`
- an hb edge missing `from` or `to`
- capacity or working-set absent, or not `i64`
- any attribute outside the closed sets above,
  including a device name, a router result, or a
  collective kind
- a nested region on a fact or an hb edge

Do not refuse, and do not interpret, when the dict is
well formed and the host already knows how to reject it:

- capacity present and not 2
- working-set present and not greater than 2
- one block whose stores are not exactly one region
- more than one block
- an `op` string the host window will reject
- hb pairs that fail `projection_holds` after construct

Those stay inside `evaluate_apply`.

extract does not call `evaluate_authorization`. It does
not build the 7B envelope. It does not bind the witness.
It does not compute `CandidateId`. It does not run
`IsLegal`. Device `D` stays the existing
`evaluate_apply` argument. Witness schema stays
`s2c2.apply_legality_witness.v1`.

## Identity mapping

| Carrier | Host |
| ------- | ---- |
| `carrier.block` in source order | `blocks[]` in that order |
| `carrier.fact` in source order | `blocks[].ops[]` in that order |
| `name` | `name` |
| `op` | `op` |
| `op_id` | `op-id` |
| `s2c2.carrier.capacity` | `capacity` |
| `s2c2.carrier.working_set` | `working-set` |
| no `carrier.hb` | key `hb` omitted |
| one or more `carrier.hb` | `hb` = those pairs, sorted lexicographically |

Sorting hb pairs matches `canonical_program`, which sorts
edges. The multiset is unchanged. Duplicate pairs stay
duplicate.

The acceptance source in `record_apply_scenario.py` is
three stores named `0`, `1`, `2`, op-ids `id0`, `id1`,
`id2`, capacity 2, working-set 3, hb `id0→id1` and
`id1→id2`. extract of the grammar example above must
equal that host dict. `evaluate_apply` then remains the
only producer of `P'`, including `id2.evict`,
`id2.transfer`, and `id2.restore`.

## Determinism

```text
same canonical carrier
        ↓
same extracted host program
        ↓
same CandidateId
        ↓
same ApplyResult
```

The last two steps are the unchanged host, given the same
7B envelope, the same witness, and the same device
argument. extract adds no branch to that chain.

## Test plan

Not executable in this pull request. Phase 2 implements
them against this page. `evaluate_apply` is not copied.

| id | layer | input | required result |
| --- | --- | --- | --- |
| C01 | extract | the grammar example | host dict equal to the acceptance source, including hb |
| C02 | extract | C01 with attribute order and hb source order swapped | same dict as C01 |
| C03 | host | C01 dict, the existing yes envelope, bound witness, device `D0` | same `CandidateId` and same `ApplyResult` as `w0-3-2-storage-capacity-001` |
| C04 | extract | a fact with no `op_id` | refusal; `evaluate_apply` not called |
| C05 | extract | capacity attribute absent | refusal; `evaluate_apply` not called |
| C06 | extract | a `s2c2.carrier.device` attribute | refusal; device is not chosen here |
| C07 | extract | zero `carrier.block` | refusal |
| C08 | host | extracted program, capacity 4, three stores | `match=no`, `applied=no`; no region |
| C09 | host | one block, two stores | `match=no`, `applied=no`; region count is not 1 |
| C10 | host | two blocks, each a three-store region | blocks not merged; `match=no`, `applied=no` |
| C11 | host | envelope sequence is not KEEP, EVICT, TRANSFER, RESTORE for that region | `rewrite.sequence-mismatch` |
| C12 | host | witness absent | `match=yes`, `applied=no` |
| C13 | host | witness device `D2` while `evaluate_apply` is called with `D0` | `match=yes`, `applied=no` |
| C14 | host | hb that fails `projection_holds` after construct | `match=yes`, `applied=no` |
| C15 | host | envelope identity is not `RealizationIdentity(P, R)` | `rewrite.identity-mismatch` |
| C16 | host | an existing op-id equal to `id2.evict` | `match=yes`, `applied=no`; source `P` unchanged |

C08 through C16 are host results already defined by the
inhabitant. The carrier test only checks that extract
handed the dict through unchanged.

## Not in this design

```text
implementation of extract
TableGen ops
lowering
s2c2-opt
a change to evaluate_apply
a change to the 7B envelope
W0-3/4
MoE, tensor parallel, pipeline send, collectives
routing semantics
multi-device semantics
a new HB rule
Enum_F
Search
generic rewrite
authorization changes
can-run-plan
hardware execution
a new semantic baseline
```

`compiler-e2e` stays no. NEXT CUT stays NOT OPENED.
`can-run-plan` stays no. Success of a later extract still
does not grant `can-run-plan`.
