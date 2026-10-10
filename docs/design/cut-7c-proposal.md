# Cut Proposal: 7C End-to-End Executable Optimization

**Status:** PROPOSAL. Review not done. `next_cut` stays
`NOT OPENED`. Merging this page does not open the cut.
This page adds no dialect op, no contract, no code, and
does not move the semantic baseline
`36fd6fd931c109c6849cc366bd91b5abdfcab4b1`.

**Recorded:** the owner chose option A (2026-10-10). That is
decision 1 of 4. It is not a go-ahead. Implementation waits
for review, freeze, and a separate verbal go.

```text
Goal     one IR file takes the whole path to an ApplyResult
Not      7D / 7E / 7F / 8A, Search, routing, a second pattern
Rewrite  W0-3/2 only; evaluate_apply unchanged
```

How a cut opens is already written down: propose, review,
freeze, then verbal go
([`storage-schedule-family.md`](storage-schedule-family.md)).
This is the propose step. Nothing below is decided except
decision 1.

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
2. **Authorization.** 7A forbids `if sufficient: authorized =
   yes`. Authorization needs an independent policy, so an
   end-to-end path cannot grant it to itself. The acceptance
   driver's fixture authorization is acceptance evidence, not
   this.
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
  orchestrator invents no mapping. Authorization and witness
  are also caller-supplied files with no default. This adds no
  contract.
- **A2. Orchestrator derives the program from the IR.** It
  must define the mapping. That is a contract (see above).

A1 is the reading that keeps the cut non-semantic. It also
means the end-to-end path does not remove the hand-written
carrier: it only connects the stages around it. A2 would, and
it is the larger decision.

B (`s2c2-opt` calls the Python hosts) and C (port the Decision
hosts to C++) are not chosen. B makes a C++ tool depend on
Python at run time and changes the carrier boundary. C
re-derives frozen semantics in a second language.

## Acceptance, if opened

```text
one IR file in test/ → capacity plan → hosts → ApplyResult
program supplied by the caller (A1); no derived mapping
authorization and witness supplied by the caller, no default
a missing or refused input stays applied=no, source unchanged
plan identity and carrier identity disagree → host mismatch
can-run-plan stays no
Semantic Baseline v1 = PASS, baseline still 36fd6fd
scripts/check-host.sh PASS 52 FAIL 0
check-s2c2 PASS
S05 stays a known difference; evaluate_apply unchanged
no new Decision subject, dialect op, HB rule, or Enum_F
```

## Decisions

1. Option. **Answered: A.**
2. Authorization policy source. Under A1: a caller-supplied
   file, no default in the repo. Needs the owner to confirm.
3. Legality witness source. Under A1: a caller-supplied file,
   no default. Needs the owner to confirm.
4. A1 or A2. **Open.** A1 keeps the cut non-semantic. A2 is a
   semantic cut and needs the empirical-boundary condition.

Until 2 to 4 are answered and a review passes, this page
changes nothing.
