# PR #152 evidence audit

**Status:** post-merge record. Not `PR #152 — APPROVED`.
The GitHub merge is a repository fact. It is not a
review token from this record. Semantic baseline remains
`36fd6fd931c109c6849cc366bd91b5abdfcab4b1`.
`next_cut` stays `NOT OPENED`.

```text
Technical review       PASS, host handoff scope only
GitHub state           MERGED, 463c6b0, head 2d858a0
LLVM check-s2c2        NOT VERIFIED
Semantic baseline      36fd6fd, UNCHANGED
evaluate_apply         UNCHANGED
can-run-plan           no
next_cut               NOT OPENED
PR #152 — APPROVED     NOT ISSUED
```

Merged range is the host handoff: acceptance entry
refuses before `bound_witness` and `evaluate_apply`;
29 matrix rows compare carrier-spellable fields with
the direct host call; S05 stays a recorded difference.
`induced-hb` is not copied back. Eight spellable corpus
scenes match. The full corpus fingerprint is not claimed
through the carrier. This merge does not authorize Token
Path, a device backend, Search, or a new semantic rule.

The sections below were written before `463c6b0`.
They describe the audit that removed the silent
`induced-hb` copy. Where they say the pull request is
still a draft, or that `#135` and `#144` are unmerged,
that was true at audit time and is not the post-merge
state.

## P0. What the pull request actually contains

`review/pr-152` matches this branch. `git diff --check` is clean.

```text
6385322  Refuse a carrier text that is not one W0-3/2 region.
2ec7572  Replay the host matrix through the carrier handoff.
40ef6e6  Replay the W0-3/2 scenario corpus through carrier text.
5174b41  State that induced-hb is restored outside carrier text.
```

Files against `main`:

```text
README.md
docs/design/compiler-spine.md
docs/design/compiler-spine-integration.md
runtime/record_compiler_spine.py
runtime/record_goal_alignment.py
```

`runtime/record_storage_apply.py` is the same blob as `main`.
No dialect, no TableGen, no `s2c2-opt` registration.

`2ec7572` is not the branch tip. `40ef6e6` added the corpus
replay. `5174b41` documented an out-of-band copy of
`induced-hb`. Those two commits are in the diff under review.
They are not a separate accepted slice.

## P1. `induced-hb` was a silent fill

Carrier v0 spells `blocks`, `capacity`, `working-set`, and
optional `hb`. `render` does not write `induced-hb`.
`extract` does not invent it.

`40ef6e6` copied the fixture's `induced-hb` onto the
extracted program before the corpus observation. That copy
changes S05. The fixture observation is `applied no`. The
extracted text, observed alone, is `applied yes`. Pasting
the field back made the corpus pin look like a carrier
result. The matrix row `postcondition-hb` does not change
`match` or `applied` if the field is left off, because its
witness is already the fixture witness. The copy was still
a hidden input.

This audit removes the copy. The replay compares the
extracted program with the host. It does not attach
fixture fields. S05 is reported as a difference, not
forced back to the pin. The corpus fingerprint is not
claimed through this handoff.

## P2. Commands re-run after that removal

```text
compiler-spine gate=handoff
spine-match yes
spine-applied yes
opt-bypass refusal apply-not-called
extract-refusal apply-not-called
no-region refusal apply-not-called
other-program match no
other-program applied no
apply-called yes
host-matrix-through-spine 29
induced-hb-copied no
scenario-corpus-spellable 8
S05-fixture applied no
S05-carrier-only applied yes
carrier-encodes-induced-hb no
can-run-plan no
next-cut no
```

```text
Semantic Baseline v1 = PASS
host-matrix-through-carrier 29
corpus-result PASS
next-cut NOT-OPENED
host contract commands PASS 52 FAIL 0
```

The 52 commands are the host contract and matrix printers
under `runtime/record_*.py`, plus the Ascend schema
identity check and the CUDA schema printer. They do not
include `check-s2c2`.

## P3. LLVM

`build/bin/s2c2-opt` is absent in this environment.
`check-s2c2` was not run. That is `NOT VERIFIED`.
It is not a pass, and it does not open a cut.

## P4. Conclusion

The opaque `induced-hb` restore was in the diff. It is
removed, and the regressions above were run again.
`evaluate_apply` is unchanged. This page does not approve
or merge `#152`, and it does not merge `#135` or `#144`.
