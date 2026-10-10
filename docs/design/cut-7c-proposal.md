# Cut Proposal: 7C End-to-End Executable Optimization

**Status:** PROPOSAL. Review not done. `next_cut` stays
`NOT OPENED`. Merging this page does not open the cut.
This page adds no dialect op, no contract, no code, and
does not move the semantic baseline
`36fd6fd931c109c6849cc366bd91b5abdfcab4b1`.

**Recorded (2026-10-10):** the owner chose option A, then
reading A2 (the orchestrator derives the program from the IR).
That makes 7C a **semantic cut**, and it does not meet the
written opening condition. The owner also set the decision
rule: selection is the most efficient optimal strategy, and
that strategy is the authorization. These are decisions 1, 2,
and 4. They are not a go-ahead. Decisions 3 and 5 are open.
Implementation waits for those, a review, a freeze, and a
separate verbal go.

```text
Goal     one IR file takes the whole path to an ApplyResult
Not      7D / 7E / 7F / 8A, Search, routing, a second pattern
Rewrite  W0-3/2 only; evaluate_apply unchanged
```

How a cut opens is already written down: propose, review,
freeze, then verbal go
([`storage-schedule-family.md`](storage-schedule-family.md)).
This is the propose step. Decisions 1, 2, and 4 are answered.
Decisions 3 and 5 are not.

## Is 7C a semantic cut?

**Undecided, and it depends on one thing: the mapping.**

If 7C only chains stages that already have frozen contracts,
it adds no contract. It changes a frozen boundary, and the
gate is the process above. If 7C must **define** how an IR
file becomes the program the host consumes, that definition
is itself semantics: which tile becomes which store, how op
order is fixed, where happens-before edges come from. That
would be a new contract, and the condition in
[`empirical-semantic-boundary-v1.md`](empirical-semantic-boundary-v1.md)
applies (a real scene that `stor`, `comp`, `comm`, `sched`
cannot express).

An earlier draft of this page said 7C adds no contract. That
was too early. It is withdrawn.

## What opening would touch

| Frozen statement | Under 7C |
| ---------------- | -------- |
| Dialect ops are the ones in `include/s2c2` | unchanged |
| Apply host is W0-3/2 only | unchanged |
| `can-run-plan` stays `no` | unchanged, even end to end |
| `evaluate_apply` | unchanged |
| Semantic baseline `36fd6fd` | unchanged **only if** the mapping adds no contract |
| The carrier text and `s2c2-opt` stay separate | holds under option A |
| `next_cut` is `NOT OPENED` | would move to this one named slice |

## What exists today

Checked on `main` by running it, not assumed. There are two
optimization axes, and they are connected differently.

**Schedule axis, in C++.** `s2c2-opt` reads IR, decides, and
prints transformed IR. Running
`s2c2-opt test/Integration/evidence-bounded-schedule.mlir
--profile=rtx4090 --s2c2-evidence-bounded-schedule
--check-s2c2-execution` gives four candidates (`KEEP` 1,
`FLATTEN` 3) and an HB check. The input has four
`sched.concurrent` regions outside comments. The output keeps
one (the `KEEP`) and rewrites three into sequential
`sched.task`s. The same IR is left alone under the `NPU` and
`UNK` profiles in that test, because those profiles have no
device evidence for it. Passes such as `s2c2-enumerate`,
`s2c2-argmin`, `s2c2-xform`, and `s2c2-capacity-plan-query`
exist. Only the two commands above were run for this page.

**Storage-capacity axis (EVICT, TRANSFER, RESTORE).**
- `s2c2-opt FILE --capacity=2 --dump-capacity-plan=OUT`
  writes a plan. Its top-level keys are `candidates`,
  `capacity`, `enumerated`, `feasible`, `peak_live`, `policy`,
  `rewrite`, `rewrite_license`, `schema`, `selected`, `space`,
  `subseteq_residency`, `truncated`. A candidate has `id`,
  `identity`, `keep`, `evict`, `rematerialize`, `restores`.
- Sufficiency, authorization, rewrite-plan, and apply exist
  only as Python hosts under `runtime/`. They are Decision
  contracts, not compiler stages. Their inputs in the
  contract runs are spec fixtures.
- On `test/Integration/storage-capacity.mlir`, candidate 0 has
  `usable: false` with `no-source-replica`.

So no IR file reaches a successful storage-rewrite apply on
its own. That statement is about this axis. It is not a
statement about `s2c2-opt` in general.

## The mapping is the hard part

The apply host consumes a dict: `blocks[].ops[]` with `name`,
`op`, and `op-id`, plus `capacity`, `working-set`, and `hb`.
The plan above carries none of `op-id`, op order, or `hb`.
(A search for those strings in the plan JSON matches once, on
`"space": "hbm"`. That is the letters `hb` inside `hbm`, not an
`hb` field.)

The carrier is text projected onto that dict
([`mlir-carrier-v0.md`](mlir-carrier-v0.md)). It is written by
hand. Nothing in the tree turns an IR file into carrier text.

The one visible link is naming: plan identities use tile ids
`0`, `1`, `2`, and the host's acceptance program names its
stores `0`, `1`, `2`. Whether that is a design or a
coincidence is not established here. It is not a contract.

## What an end-to-end path must answer

1. **Evidence.** The usable inputs come from fixtures today.
   `s2c2-opt --query-capacity-plan` produces per-restore flags
   that look like the input to the Python evidence records
   (`provenance=occupancy-query` appears in the algebra
   matrix). Whether they are the same thing is to be checked in
   review, not assumed.
2. **Authorization.** The owner rule below replaces the
   separate signer for this cut. The selected optimum is the
   authorization. Frozen 7A still forbids
   `if sufficient: authorized = yes` on this tree; this page
   does not change that evaluator.
3. **Witness.** The legality witness is an external oracle by
   contract. A witness the driver builds from the candidate is
   acceptance only.
4. **Program.** See the mapping above.

## Options

**A. Orchestrator outside `s2c2-opt`. Chosen.** A script
chains `s2c2-opt` output, the Python hosts, and apply.
`s2c2-opt` still does not call `evaluate_apply`, so the
carrier boundary holds. It is end to end and measurable, but
it is not `s2c2-opt` orchestration. A has two readings, and
they differ on the mapping:

- **A1. Caller supplies the program.** The caller gives the IR
  and, separately, carrier text. The orchestrator **checks**
  that the plan identity matches the carrier region's
  realization identity. The host already makes that check and
  emits `rewrite.identity-mismatch` on a mismatch. The
  orchestrator invents no mapping. Under the owner rule,
  authorization is the selected optimum, not a file. The
  legality witness is still an open input (decision 3). This
  reading adds no contract.
- **A2. Orchestrator derives the program from the IR.
  Chosen (2026-10-10).** It must define the mapping. That is
  a contract (see above).

A1 would have kept the cut non-semantic, and would have left
the hand-written carrier in place. A2 removes the hand-written
step, and in exchange it is a semantic cut. The next two
sections say what that means.

B (`s2c2-opt` calls the Python hosts) and C (port the Decision
hosts to C++) are not chosen. B makes a C++ tool depend on
Python at run time and changes the carrier boundary. C
re-derives frozen semantics in a second language.

## A2: what the mapping must define

Read from the IR that the capacity plan is computed from
(`test/Integration/storage-capacity.mlir`, function
`@four_tile_hbm`): four `stor.object`, each with a
`stor.materialize` into an `hbm` buffer, and a `stor.unpack`
as the use. The host consumes `store` operations. The mapping
has to answer each of these. The candidate answers are
**not decided**; they are here so a review has something to
accept or reject.

| Question | Candidate answer |
| -------- | ---------------- |
| Which IR op is a host `store`? `stor.materialize` creates a residency and writes no data. `stor.pack` writes data. `stor.unpack` reads. | `stor.materialize` into the constrained space |
| Where do `name` and `op-id` come from? Both must be unique strings. | the plan's tile ids and a stable derived id; how the pass numbers tiles is implementation, not a stated contract |
| Which three of four tiles form the one region, with `working-set` 3 and `capacity` 2? | the tiles the plan keeps or evicts; `working-set` from `peak_live` |
| Where does order come from, and does `sched` become `hb`? | program order in the block; no `hb` unless `sched` edges are mapped on purpose |
| What is `stor.unpack`, and what are `comp` and `comm` ops inside the window? The host allows `compute` and `load` and forbids the rest. | classify each; refuse what is not classified |
| What if the IR does not fit? | refuse before the host, as carrier extract does |

There is a precedent against doing this by name. Carrier v0
refuses to map `stor.transfer` onto the host's `"transfer"`
step, because "mapping one onto the other would be a new
meaning" ([`mlir-carrier-v0.md`](mlir-carrier-v0.md)). The
`store` question above is the same kind of question. A2 is
where that meaning gets decided.

## A2: the opening condition is not met

The written condition for a semantic cut asks for a real scene
that `stor`, `comp`, `comm`, `sched` cannot express
([`empirical-semantic-boundary-v1.md`](empirical-semantic-boundary-v1.md)).
A2 does not fit it. Its problem is that the mapping is
unwritten, not that a relation is inexpressible. The IR above
already expresses the scene.

So A2 cannot open under the rule as written. There are three
paths, and this page does not pick one:

1. **The owner records an amendment.** A connectivity cut,
   limited to this mapping, may open without the
   inexpressibility condition. It must be written in a merged
   page, not implied.
2. **Go back to A1.** No amendment is needed.
3. **Find a real scene** the four dialects cannot express. A2
   was not motivated by one.

The condition is the owner's rule, so only the owner can
amend it. The rule recorded below is about authorization.
It does not amend this opening condition, and it does not
answer decision 5.

## Owner rule: the optimum is the authorization

Recorded 2026-10-10. This is decision 2.

```text
Every selection is the most efficient optimal strategy.
The optimal strategy is authorized by being optimal.
```

Among legal candidates, the strategy the frozen cost policy
already selects is `authorized=yes` and carries the rewrite
license for that action. There is no second signer and no
authorization file.

This is the opposite of frozen 7A (`sufficient` does not
imply `authorized`) and of the spine path that forbids
`F → argmin → rewrite`. Adopting it is an amendment of those
two sentences for this cut, and only when the cut opens.
Until then the running hosts keep the old doors.

Legality stays a filter in front of the selection: a
candidate that is not legal is not a strategy. The witness
that attests legality is decision 3 and is still open.

## Acceptance, if opened

Common to both readings:

```text
one IR file in test/ → capacity plan → hosts → ApplyResult
authorization is the selected optimum; no authorization file
witness source stays decision 3; a missing witness stays applied=no
a missing or refused input stays applied=no, source unchanged
can-run-plan stays no
scripts/check-host.sh PASS 53 FAIL 0
check-s2c2 PASS
S05 stays a known difference; evaluate_apply unchanged
no new Decision subject, dialect op, HB rule, or Enum_F
```

A2 only:

```text
the mapping spec page is reviewed and frozen before any code
the mapping is a pure function: same IR, same program
an IR that expresses the acceptance scene maps to exactly the
  program the frozen host already accepts (no drift from it)
an IR shape the mapping does not cover is refused before the
  host, and that refusal is not match=no
whether the semantic baseline moves is decided by the owner;
  it is not assumed unchanged
```

## Decisions

1. Option. **Answered: A.**
2. Authorization source. **Answered:** the optimal strategy
   is the authorization. No caller-supplied authorization file.
3. Legality witness source. Needs the owner to confirm.
4. A1 or A2. **Answered: A2.** That makes this a semantic cut.
5. How A2 gets past the opening condition: amend it, return
   to A1, or produce a scene. Open.

Until 3 and 5 are answered and a review passes, this page
does not open the cut.

## Host for decision 2

`runtime/record_optimum_authorization.py` implements the rule
above. A unique minimum cost among `legal=yes` strategies is
the authorization and the rewrite license, then the existing
7B plan. A tie, a missing cost, or no legal strategy stays
unauthorized. The frozen `evaluate_authorization` is not
changed: `sufficient=yes` with a missing policy is still
`authorized=no`. Apply still requires the existing witness.
`can-run-plan` stays `no`. This host does not derive a program
from IR, so it is not A2, and it does not open the cut.
