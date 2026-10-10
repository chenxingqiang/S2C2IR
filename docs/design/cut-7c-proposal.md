# Cut Proposal: 7C End-to-End Executable Optimization

**Status:** PROPOSAL. Review not done. `next_cut` stays
`NOT OPENED`. Merging this page does not open the cut.
This page adds no dialect op, no contract, no code, and
does not move the semantic baseline
`36fd6fd931c109c6849cc366bd91b5abdfcab4b1`.

```text
Goal     one IR file takes the whole path to an ApplyResult
Not      7D / 7E / 7F / 8A, Search, routing, a second pattern
Rewrite  W0-3/2 only; evaluate_apply unchanged
```

How a cut opens is already written down: propose, review,
freeze, then verbal go
([`storage-schedule-family.md`](storage-schedule-family.md)).
This is the propose step. Nothing below is decided.

The condition in
[`empirical-semantic-boundary-v1.md`](empirical-semantic-boundary-v1.md)
(a real scene that `stor`, `comp`, `comm`, `sched` cannot
express) gates a **semantic** cut: a new contract. 7C adds
no contract. What gates it is different: it changes a
boundary that is frozen today.

## What opening would touch

| Frozen statement | Under 7C |
| ---------------- | -------- |
| Dialect ops are the ones in `include/s2c2` | unchanged |
| Apply host is W0-3/2 only | unchanged |
| `can-run-plan` stays `no` | unchanged, even end to end |
| Semantic baseline `36fd6fd` | unchanged unless a contract is added; none is proposed |
| `evaluate_apply` | unchanged |
| The carrier text and `s2c2-opt` stay separate | **at stake**, see options |
| `next_cut` is `NOT OPENED` | would move to this one named slice |

## What exists today

Checked on `main`, not assumed.

- `s2c2-opt FILE --capacity=2 --dump-capacity-plan=OUT`
  writes a capacity plan. Candidates carry an `identity`
  such as `keep{0,1}|evict{2}|rematerialize{}`.
- Sufficiency, authorization, rewrite-plan, and apply exist
  only as Python hosts under `runtime/`. They are Decision
  contracts, not compiler stages.
- In the contract runs their inputs are spec fixtures, not
  values read from an IR file.
- On `test/Integration/storage-capacity.mlir`, candidate 0
  has `usable: false` with `no-source-replica`. No IR file in
  the tree reaches a successful apply on its own.

## What an end-to-end path must answer

These are not implementation details. Each one is a place
where a driver could quietly decide something it must not.

1. **Evidence.** Where do the usable-predicate inputs come
   from: the IR, a spec, or the Evidence DB? Today they are
   fixtures.
2. **Authorization.** 7A forbids `if sufficient: authorized =
   yes`. Authorization needs an independent policy. An
   end-to-end path cannot grant it to itself. The acceptance
   driver's fixture authorization is acceptance evidence, not
   this.
3. **Witness.** The legality witness is an external oracle by
   contract. A witness the driver builds from the candidate is
   acceptance only.
4. **Program.** The host consumes a dict. Whether it comes
   from carrier text or from an IR file decides which side of
   the `s2c2-opt` boundary the work sits on.

## Options

**A. Orchestrator outside `s2c2-opt`.** A script chains
`s2c2-opt` output, the Python hosts, and apply. `s2c2-opt`
still does not call `evaluate_apply`, so the carrier boundary
holds. It is end to end and measurable, but it is not
`s2c2-opt` orchestration. Questions 1 to 3 still need answers.

**B. `s2c2-opt` calls the Python hosts.** Changes the
boundary directly. A C++ tool would depend on Python at run
time. Not recommended.

**C. Port the Decision hosts to C++ passes.** Largest change.
Re-derives frozen semantics in a second language, so the
baseline replay and the 52 host checks would have to keep
agreeing with it. Highest risk.

Recommendation: A, one workload, W0-3/2, and only after 1 to 3
have owners. This is a recommendation, not a decision.

## Acceptance, if opened

```text
one IR file in test/ → capacity plan → hosts → ApplyResult
authorization and witness supplied by the caller, not fixtures
a missing or refused input stays applied=no, source unchanged
can-run-plan stays no
Semantic Baseline v1 = PASS, baseline still 36fd6fd
scripts/check-host.sh PASS 52 FAIL 0
check-s2c2 PASS
S05 stays a known difference; evaluate_apply unchanged
no new Decision subject, dialect op, HB rule, or Enum_F
```

## Decisions needed from the owner

1. Option A, B, or C.
2. Where the authorization policy comes from.
3. Where the legality witness comes from.
4. Whether any of this counts as a contract change. This page
   says no. If the answer is yes, it is a semantic cut and the
   empirical-boundary condition applies.

Until those are answered and a review passes, this page
changes nothing.
