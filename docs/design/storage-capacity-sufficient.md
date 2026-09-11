# Capacity Sufficient Proof (Phase 6C-M, query / proof only)

**Status:** design freeze from `0f96895` (6C-L merged).
6C-B–L stay FROZEN. This cut defines the `sufficient`
predicate as a **query/proof** composition. It does
**not** classify `restore-target` yet, does **not** print
`sufficient=yes`, does **not** issue
`rewrite-license=yes`, and does **not** open a rewrite
path. 5A–6B is the **stable baseline**
([`stable-baseline.md`](stable-baseline.md)).
Do not FileCheck microseconds.

```text
Goal     freeze the four-layer predicate; sufficient ≠ rewrite
Not      restore-target classification, a yes-license, rewrite, or F_storage_schedule
Rewrite  still only from an existing capability license
```

```text
usable = source-data ∧ restore-ordering

usable ≠ dest-invalidation

sufficient =
    usable
    ∧ dest-invalidation
    ∧ restore-target

sufficient=yes ≠ rewrite-license=yes ≠ rewrite-path=yes
```

**Forbidden assumption (this freeze):**

```text
sufficient  ≠  usable ∧ dest-invalidation
```

6C-J / 6C-K / 6C-L are evidence. They are not sufficiency.
Jumping from dest-invalidation to `sufficient=yes` would
skip the resource / capacity / target-legality proof.

## Why this cut

6C-I froze `necessary` ≠ `sufficient` and left
`sufficient=no`. 6C-J–L then proved three independent
conjuncts. The dest-invalidation fixture already has:

```text
usable=yes
dest-invalidation=yes
sufficient=no
```

That row must stay the 6C-L → 6C-M **non-implication**
lock. 6C-M names the missing conjunct instead of treating
rewrite-path as the thing that makes a query sufficient.

```text
6C-I sufficient list (frozen printer)
  source-data, restore-ordering, dest-invalidation, rewrite-path

6C-M refinement (this design)
  rewrite-path is later IR application, after license
  restore-target is the query/proof conjunct still missing
```

The frozen 6C-I contract printer is **not** rewritten this
cut. A later implementation cut may add prefix
`s2c2-capacity-sufficient` without opening rewrite.

## Four-layer predicate (frozen)

```text
source-data            6C-J FROZEN
        ∧
restore-ordering       6C-K FROZEN
        ↓
usable
        ≠
dest-invalidation      6C-L FROZEN
        ≠
restore-target         6C-M defined; not classified this cut
        ↓
sufficient
        ≠
rewrite-license        CLOSED
        ≠
rewrite-path           CLOSED
        ≠
F_storage_schedule     CLOSED
```

```text
Semantic → Residency/lifetime → Capacity feasibility → F_capacity
  → CapacityPlan → query / consumer API
  → capacity-policy (s0 or measured-capacity-v1)
  → Rewrite License gate          ← 6C-G FROZEN, still no
  → EVICT→TRANSFER restore        ← 6C-H FROZEN
  → license predicate             ← 6C-I FROZEN
  → source-data validity          ← 6C-J FROZEN
  → restore ordering              ← 6C-K FROZEN
  → dest invalidation             ← 6C-L FROZEN
  → sufficient                    ← 6C-M this design (query/proof)
  → rewrite-license               ← later capability / license gate
  → rewrite path / replace/erase  ← later
  → F_storage_schedule            ← later opportunity, not next impl
```

## Necessary conditions for `sufficient=yes`

An EVICT selected candidate is `sufficient=yes` only when
**all** of the following hold. Unknown → `no`.

| Conjunct | Cut | Accepted witness | Accepted scope | What it proves |
| -------- | --- | ---------------- | -------------- | -------------- |
| `source-data` | 6C-J | `spec-unmutated-cover` | `occupancy-live` | scoped replica holds a usable value over occupancy live |
| `restore-ordering` | 6C-K | `spec-before-consumer` | `occupancy-live` | TRANSFER completes at required point `occ.end` |
| `usable` | 6C-K | (derived) | (derived) | `source-data ∧ restore-ordering` |
| `dest-invalidation` | 6C-L | `spec-drop-stale` | `occupancy-live` | fast-space copy is dropped without stale reads |
| `restore-target` | 6C-M | `spec-restore-target-legal` | `occupancy-live` | restore may re-occupy the occupancy destination without breaking \(F_{\mathrm{capacity}}\) |

```text
usable
  = source-data ∧ restore-ordering

restore-target
  ≠ dest-invalidation
  ≠ usable
  ≠ rewrite-path

sufficient
  = usable ∧ dest-invalidation ∧ restore-target
```

`restore-target` is the resource / capacity / target
legality proof. Dest-invalidation proves the HBM copy is
gone. It does **not** prove the TRANSFER is allowed to
land on that destination, that the destination equals the
occupancy / restore `to` space, or that the selected
assignment remains an inhabitant of enumerated
\(F_{\mathrm{capacity}}\).

6C-I **necessary** conjuncts stay frozen and separate:

```text
selected ∈ F_capacity
enumerated && !truncated
capacity-proof
evict-closed=yes
restore-kind=TRANSFER
```

`necessary=yes` is still not `sufficient=yes`.

## Witness / scope / schema (defined, not parsed this cut)

Future query prefix (not printed this cut):

```text
prefix           s2c2-capacity-sufficient
schema           s2c2.capacity_sufficient.v1
host             capacity-sufficient
query-only       yes
sufficient       no   (this cut; no restore-target classifier)
rewrite-license  no
rewrite-path     no
rewrite          no
```

Optional occupancy-spec field `restore_target` (not
occupancy, not a new \(F\) member, **not accepted by the
parser this cut**):

```text
object       occupancy id (tileN normalizes to N)
destination  hbm|ssd|host at parse
witness      token; accepted later: spec-restore-target-legal
scope        token; accepted later: occupancy-live
```

Later classification (not this cut), after dest
invalidation, independent of folding into `usable`:

```text
!restore source                 restore-target=no  sufficient=no
                                destination/witness/scope = n/a
                                reason=no-source-replica
restore, no restore_target      restore-target=no  sufficient=no
                                reason=no-target-witness
destination ≠ occupancy space
  or ≠ restore.to
  or ≠ dest_invalidation.destination
                                reason=target-scope-mismatch
witness ≠ spec-restore-target-legal   reason=unknown-witness
scope ≠ occupancy-live                reason=unknown-scope
else                            restore-target=yes
                                reason=witnessed-restore-target
sufficient = usable ∧ dest-invalidation ∧ restore-target
```

Unknown witness or unknown scope classifies as `no`.
Unknown → no rewrite.

```text
selected=none / all-KEEP        sufficient=no   (6C-I frozen)
EVICT, restore-target=no        sufficient=no
sufficient=yes                  ≠  rewrite-license=yes
sufficient=yes                  ≠  rewrite-path=yes
```

This cut does **not** add `restore_target` to the occupancy
spec parser. Extra keys stay rejected. A later
implementation cut owns the classifier.

## Fixture matrix

Existing 4-tile occupancy is unchanged
(`space=hbm`, `capacity_tiles=2`, `peak-live=3`,
\(F_{\mathrm{capacity}}\) size 3). Proof fields are not
occupancy and not new \(F\) members.

| Fixture | usable | dest-inv | restore-target | sufficient | rewrite-license | rewrite-path |
| ------- | ------ | -------- | -------------- | ---------- | --------------- | ------------ |
| `storage-capacity-4tile.jsonl` | no | no | no | no | no | no |
| `storage-capacity-4tile-transfer-restore.jsonl` | no | no | no | no | no | no |
| `storage-capacity-4tile-source-data.jsonl` | no | no | no | no | no | no |
| `storage-capacity-4tile-restore-order.jsonl` | **yes** | no | no | no | no | no |
| `storage-capacity-4tile-dest-invalidation.jsonl` | **yes** | **yes** | **no** | **no** | no | no |
| future `storage-capacity-4tile-sufficient.jsonl` | yes | yes | yes | yes | **no** | **no** |

**Negative lock (this cut, already loadable):**

```text
usable=yes
dest-invalidation=yes
restore-target=no     (no restore_target field; not classified)
sufficient=no
rewrite-license=no
rewrite-path=no
```

This is
[`v3-dataset/storage-capacity-4tile-dest-invalidation.jsonl`](v3-dataset/storage-capacity-4tile-dest-invalidation.jsonl).
It proves **6C-L ⇏ 6C-M**.

**Positive fixture (specified, not loaded this cut):**

```json
{
  "restore_target": [
    {
      "object": "tile0",
      "destination": "hbm",
      "witness": "spec-restore-target-legal",
      "scope": "occupancy-live"
    },
    {
      "object": "tile1",
      "destination": "hbm",
      "witness": "spec-restore-target-legal",
      "scope": "occupancy-live"
    },
    {
      "object": "tile2",
      "destination": "hbm",
      "witness": "spec-restore-target-legal",
      "scope": "occupancy-live"
    }
  ]
}
```

Same 4-tile occupancy, restore sources, source-data,
restore-order, and dest-invalidation as the 6C-L fixture.
`destination=hbm` equals occupancy space and TRANSFER
`to`. The later classifier may then print
`sufficient=yes` and must still print
`rewrite-license=no` `rewrite-path=no`. Adding this field
to a JSONL **today** is rejected (extra key). That is
intentional.

## Forced boundary

```text
sufficient=yes
        → rewrite-license=no
        → rewrite-path=no
```

even on the future positive fixture. 6C-M is evidence →
decision **query**. The capability / license gate stays
later. Rewrite stays after that.

```text
--capacity diagnostics     frozen; no sufficient prefix
query consumer             may later print s2c2-capacity-sufficient
applySchedule()            not a 6C-M entry
replace / erase            closed
F_storage_schedule         closed
```

## Out of scope

```text
restore-target classifier / parser
sufficient=yes print
rewrite-license=yes
rewrite-path / replace / erase
F_storage_schedule
changing 6C-I necessary print
changing 6C-J / 6C-K / 6C-L classification
changing dest-invalidation-still-no on the 6C-K prefix
valid/stale/dirty FSM
new Capability matrix
new hardware campaign
changing cost-v04 / default-3g / #69
changing Evidence DB identity
C||Storage flatten
invented sibling sched.wait
FileCheck of microseconds
```

## After this freeze

A later **implementation** cut may parse `restore_target`
and print `s2c2-capacity-sufficient`. It may set
`sufficient=yes` only on the positive fixture. It still
must not open rewrite-license or rewrite-path.
Architecture health check:
[`architecture-healthcheck.md`](architecture-healthcheck.md).
