# Task 6 report — Group arrivals

## What I implemented

- `project/scripts/simulation/arrival_queue.gd`:
  - `enqueue(position, species_id, count: int = 1) -> bool` — a new pending entry gains a
    `"count"` key, clamped to at least 1 (`maxi(count, 1)`).
  - `to_save()` writes `"count"` on every entry.
  - `restore()` reads a missing/absent `"count"` as `1`, never `0` — a defensive
    `int(entry.get("count", 1))` followed by a `< 1` clamp, matching the file's existing
    type-before-cast discipline for hand-editable saves.
- `project/scripts/simulation/capacity_evaluator.gd`:
  - Added `CapacityEvaluator.evaluate(grid, registry, origin, species, self_site = null) ->
    Dictionary` returning `{"capacity": int, "tier": HabitatTier}` — see "The double-walk
    fix" below.
  - `capacity()` and `best_tier()` are now thin one-line adapters over `evaluate()`, so there
    is exactly one copy of the tier loop left in the file (previously two byte-identical
    copies).
- `project/scripts/simulation/habitat_simulation.gd`:
  - `_evaluate()` calls `CapacityEvaluator.evaluate()` once per species and reads both
    `capacity` and `tier` off the single result; enqueues
    `mini(tier.arrival_group_size, cap - population)` (or `1` when no tier won, which cannot
    actually happen when `cap >= population + 1`, but keeps the null-tier case honest).
  - `_resolve_due_arrivals()` passes `int(entry.get("count", 1))` through to `_land_or_drop()`.
  - `_land_or_drop(position, species_id, count: int = 1)` now loops `range(maxi(count, 1))`,
    re-resolving `site`, `cap` and `population` **inside** the loop on every iteration, and
    returning (silent drop of the remainder) the moment `cap < population + 1`. Each
    successful iteration calls `_move_in()` once, which is what changes `population` for the
    next iteration's check.
  - `_move_in()`'s header comment updated — it no longer claims group size is uniformly 1
    (that was spec.md #7 -> D-25's v1 rule, now superseded by `arrival_group_size`).
- `project/scripts/save/world_snapshot.gd`: `SAVE_VERSION` bumped `5 -> 6`; `migrate()` gained
  a `version < 6` step (pure version-bump bookkeeping, no field invented — see below); the two
  header comments that named `v6` as "reserved for row 13's mist extent" now say `v7`.
- `project/tests/test_group_arrivals.gd` (new, + generated `.gd.uid` sibling): the brief's
  four checks, plus a fifth real integration check (see next section).

## The double-walk fix

**Chose:** a single combined accessor, `CapacityEvaluator.evaluate()`, per the brief's
suggested option — not the restructure alternative.

The brief's reference snippet called `CapacityEvaluator.capacity(...)` and then
`CapacityEvaluator.best_tier(...)` back to back inside `_evaluate()`. Both functions run the
exact same loop over `species.effective_tiers()`, and each iteration calls `tag_counts()`,
which is the one-grid-walk-per-tier cost the whole performance argument (gdd.md ->
Performance; `capacity_evaluator.gd`'s own "ONE TIER, ONE WALK" header) rests on. Pasting the
snippet as written would have made every dirty-queue evaluation walk the grid twice per
species instead of once.

`evaluate()` runs that loop exactly once, tracking both the winning value and the winning
tier in the same pass, and returns `{"capacity": ..., "tier": ...}`. `_evaluate()` now calls
`evaluate()` a single time per species and reads both fields off the one result.
`CapacityEvaluator.capacity()` and `.best_tier()` themselves were rewritten to call
`evaluate()` too (`capacity()` returns `int(evaluate(...)["capacity"])`, `best_tier()` returns
`evaluate(...)["tier"] as HabitatTier`) so there is only one implementation of the tier loop
left in the file — a caller who (wrongly) chains `capacity()` then `best_tier()` elsewhere in
the codebase still walks the grid twice, but that pattern is now structurally impossible
inside `_evaluate()` itself, which is the hot path this task's brief specifically flagged.

**Evidence `_evaluate()` walks the grid no more times than before this task:** before this
task, `_evaluate()` called `CapacityEvaluator.capacity()` exactly once per species — one tier
loop, one `tag_counts()` walk per tier. After this task, `_evaluate()` calls
`CapacityEvaluator.evaluate()` exactly once per species — still one tier loop, still one
`tag_counts()` walk per tier (verified by reading `evaluate()`'s body: a single `for tier in
species.effective_tiers()` loop with one `tag_counts()` call inside it, no nested call to
`capacity()` or `best_tier()`). The call count and grid-walk count are therefore identical to
pre-task, not doubled. `test_capacity_formula.gd` (the pinned gate, unedited) and
`test_event_driven_simulation.gd`'s bounded-drain/idle-world checks — which assert on
`evaluations_run` and on real engine frame counts, and would be the first suites to notice a
cost regression — both still pass (see test output below).

## Two correctness requirements

**Partial landing, checked inside the loop.** `_land_or_drop()`'s `for i in
range(maxi(count, 1))` re-resolves `site`, `cap := CapacityEvaluator.capacity(...)` and
`population := site.population()` on every iteration, not once before the loop. Each
successful `_move_in()` call appends a resident to `site.residents`, which changes
`site.population()` for the next iteration's `cap < population + 1` test — exactly the
brief's requirement that the re-check "happen inside the loop, per individual." The real test
below (`_check_partial_landing_lands_exactly_what_fits`) drives this directly: a site with 1
resident already home and capacity 3 (room for 2 more), given a group of 3, lands exactly 2 —
not 3, not 0.

**Save compatibility.** `ArrivalQueue.restore()` reads `int(entry.get("count", 1))` and clamps
`< 1` back up to `1`, so a pre-Task-6 save (no `"count"` key at all) restores every pending
arrival at count 1, identical to what that arrival always implicitly was. `save_version`
bumped `5 -> 6` in `world_snapshot.gd`'s `migrate()`, as pure version-bump bookkeeping (no
field is invented in the migration step itself — `ArrivalQueue.restore()` already handles the
missing key defensively, the same pattern the v3 -> v4 and v4 -> v5 steps already use for
fields whose absence is self-describing).

## The brief's test snippet had a bug — fixed, not transcribed

`_check_missing_count_restores_as_one()`'s brief snippet built its legacy fixture as
`{"position": Vector2i(2, 2), ...}`. `ArrivalQueue.restore()` type-checks `position` as
`TYPE_ARRAY` before ever casting it (saves are hand-editable and JSON never carries a
`Vector2i`), so a bare `Vector2i` is rejected as malformed and the entry is dropped with a
warning — the check then failed with "expected 1, got 0" and a follow-on out-of-bounds crash
reading `queue.to_save()[0]`. Fixed by writing the legacy fixture the way `to_save()` and
every other test in this suite already do: `"position": [2, 2]`. This is a test-only fix — no
production `restore()` behaviour changed to accommodate it.

## The real partial-landing test

`_check_partial_landing_lands_exactly_what_fits()` builds a real `WorldGrid` +
`HomeSiteRegistry` + `HabitatSimulation` (the fixture shape `test_event_driven_simulation.gd`
already uses: a synthetic one-species roster needing `cover` at 4 tiles/individual, radius 8).
It paints a 3x4 block of rock (12 tiles, well inside radius 8) so `capacity == 3`, registers a
home site directly with 1 resident already settled (`population() == 1`, so room for exactly
2 more), then calls `arrivals.enqueue(origin, species.id, 3)` directly (bypassing
`_evaluate()`, to pin `_land_or_drop()`'s loop in isolation from the qualification predicate)
and ticks past the whole arrival-delay band. It asserts `site.population() == 3` (1 + 2, not
4 and not 1), `resident_arrived` fired exactly twice, and the queue entry is fully consumed —
`_check_partial_landing_arithmetic()` (the brief's placeholder, kept, retitled as a
placeholder in the doc comment) only pins `mini()`'s own behaviour and cannot catch a
regression in `_land_or_drop()` itself.

## Test commands and output

1. `bash scripts/run-tests.sh group_arrivals` (sandbox disabled) — **PASS**, 17/17
   assertions (the brief's 9 minus the one fixed above, actually corrected not removed, plus
   the new 6-assertion integration check).
2. `bash scripts/run-tests.sh arrival` — **PASS** (matches only `test_group_arrivals.gd`,
   whose filename contains "arrival" as a substring of "arrivals" — no other suite's filename
   matches this filter).
3. `bash scripts/run-tests.sh save` — **PASS**, 6 suites (`test_saved_worlds_screen`,
   `test_save_round_trip`, `test_save_store`, `test_save_thumbnail`, and others matching
   "save"), 0 failed. Confirms old saves restore cleanly through the `save_version` bump.
4. `bash scripts/run-tests.sh capacity_formula` — **PASS**, 53/53, file untouched (pinned
   gate).
5. `bash scripts/run-tests.sh` (full suite) — 123 total, 118 passed, 5 failed. Failed suites:
   `test_fox_schema`, `test_human_schema`, `test_inert_land_invariant`, `test_news_report`,
   `test_rabbit_schema` — exactly the five expected-red suites from Task 3; no new failures
   added.

## Self-review findings

- Confirmed `test_capacity_formula.gd` was not edited (grep + `git status`).
- Confirmed `CapacityEvaluator.capacity()`/`best_tier()`'s external callers
  (`gentle_displacement.gd`, `test_home_prop.gd`, `probe_frame_cost.gd`,
  `test_save_round_trip.gd`, `test_capacity_formula.gd`) are unaffected — their call
  signatures are unchanged, and each now walks the grid via `evaluate()` internally, which is
  the same one-walk-per-tier cost their prior direct implementations already had. None of
  them chains `capacity()` and `best_tier()` back to back, so none of them was ever exposed
  to the double-walk bug in the first place.
- Confirmed the `_evaluate()` hot path's grid-walk count is unchanged (see "Evidence" above);
  `test_event_driven_simulation.gd`'s idle-world-does-zero-work and bounded-drain checks,
  which are sensitive to per-evaluation cost, still pass unmodified.
- Confirmed `arrivals[].count` is additive in the schema — `test_world_snapshot.gd` and
  `test_save_round_trip.gd`'s existing assertions on `arrivals` shape were not touched and
  still pass.
- Confirmed the red list did not grow: ran the full suite once before finalizing and once
  more (background) after, both showing the same five expected failures.
- `_land_or_drop()`'s `count` parameter defaults to `1`, so any other caller of this private
  method (there are none outside this file) stays behaviourally unchanged.

## Changed files

- `project/scripts/simulation/arrival_queue.gd` (modified)
- `project/scripts/simulation/capacity_evaluator.gd` (modified)
- `project/scripts/simulation/habitat_simulation.gd` (modified)
- `project/scripts/save/world_snapshot.gd` (modified — `SAVE_VERSION` 5 -> 6)
- `project/tests/test_group_arrivals.gd` (new)
- `project/tests/test_group_arrivals.gd.uid` (new, generated by the import pass)
