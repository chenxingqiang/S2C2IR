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
