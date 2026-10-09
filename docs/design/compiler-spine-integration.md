# Compiler Spine Integration

**Status:** host handoff. Not a lowering. Not compiler-e2e.
Semantic baseline remains
`36fd6fd931c109c6849cc366bd91b5abdfcab4b1`.
`s2c2-opt` is not given a carrier dialect. TableGen stays
absent. Apply stays `evaluate_apply`.

```bash
python3 runtime/record_compiler_spine.py --print-compiler-spine
```

```text
carrier text
    ↓
spine refuses an opt flag
    ↓
extract
    ↓
existing 7B envelope
    ↓
evaluate_apply
    ↓
ApplyResult
```

`s2c2-opt` registers `stor`, `comp`, `comm`, and `sched`.
It does not register `carrier.block`. Asking it to parse
this text would require a dialect, which this phase does
not add. Asking it to run `--s2c2-evidence-bounded-schedule`
or any other opt argument would let a pass produce a
result beside the host. The spine refuses that argument
before `extract` and before `evaluate_apply`.
A carrier text that extracts but does not contain exactly
one W0-3/2 region is refused before `bound_witness` and
before `evaluate_apply`. That refusal is not `match=no`.
Capacity other than 2, a working set that is not above 2,
fewer than three stores, and two regions in one block all
take that refusal. A different one-region program still
reaches the host. The host returns `match=no` and
`applied=no`, and it does not edit the source.

The same driver also replays the 29 host matrix rows.
Each row is rendered, extracted, and passed to
`evaluate_apply` with that row's own envelopes and
witness. The ApplyResult matches calling the host on the
source program. Rows the host rejects stay host
rejections. This replay does not build a witness and does
not turn a rejection into the acceptance apply.

```text
s2c2-opt-invoked no
s2c2-opt-bypass no
can-run-plan no
lowering no
```

The success path renders the acceptance source, extracts
it, and uses `scenario.rewrite_plan` plus
`bound_witness`. The `ApplyResult` matches
`w0-3-2-storage-capacity-001`. Authorization and the
rewrite plan stay the existing producers. This driver
does not re-evaluate them and does not copy
`evaluate_apply`.

## Not in this handoff

```text
a carrier dialect in s2c2-opt
TableGen
lowering
W0-3/2 device realization
MoE, tensor parallel, collectives
a new HB rule
Enum_F
Search
generic rewrite
can-run-plan
a new semantic baseline
```

NEXT CUT stays NOT OPENED.
