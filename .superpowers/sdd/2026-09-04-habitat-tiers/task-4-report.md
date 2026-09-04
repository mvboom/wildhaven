# Task 4 report — the tiered capacity formula

## What I implemented

`project/scripts/simulation/capacity_evaluator.gd` was rewritten around the tiered
formula:

```
capacity(h, S) = max over tiers T of tier_capacity(h, S, T)
```

Added:
- `count_key(tag, radius) -> String` — `"%s@%d"`, the counts-dictionary key shape for a
  (tag, radius) pair.
- `tag_counts(grid, registry, origin, species, tier = null, self_site = null) -> Dictionary`
  — the one-walk tile counter. Walks once to `tier.max_radius(fallback)` and buckets each
  tile into every `(tag, radius)` pair the tier reads (needs and limits alike), rather than
  walking once per need.
- `tier_capacity_from_counts(counts, species, tier) -> int` — the pure per-tier formula:
  limits gate first (violated -> 0, cheapest rejection), then `GATE_ONLY` needs gate
  (absent -> 0, present -> no scaling contribution), then Liebig's min over the remaining
  scaling needs against their own divisors, capped by `tier.max_individuals`. No lower
  clamp.
- `capacity(...)` — rewritten to iterate `species.effective_tiers()`, taking the max
  `tier_capacity_from_counts()` over all of them. Signature unchanged.
- `best_tier(...)` — new; same iteration, returns the winning `HabitatTier` (or null),
  needed by later tasks (arrival group size, Field Guide tier display).
- `capacity_from_counts(counts, species) -> int` — kept its exact old signature. Now a
  thin adapter: resolves `species.legacy_tier()`, rekeys the caller's bare-tag dict into
  `count_key(tag, effective_capacity_radius())` form, and delegates to
  `tier_capacity_from_counts`. No second copy of the arithmetic.
- `_uncached_legacy_tier(species) -> HabitatTier` — new, private. See "Deviation" below.
- `qualifies(...)` and `_tile_counts_for(...)` — unchanged.

## Deviation from the brief, and why

The brief's Step 3 reference code gives `tag_counts` this signature: `tier: HabitatTier`
with **no default**, positioned before `self_site: HomeSite = null`. I implemented `tier`
with a default of `null` instead. Two reasons, both load-bearing:

1. **Compile compatibility.** `test_capacity_formula.gd` (the pinned, must-not-edit
   regression gate) calls `CapacityEvaluator.tag_counts(grid, empty, origin, near)` —
   4 positional args, no tier, no self_site — six times across
   `_check_capacity_radius_is_consumed()` and `_check_sentinel_follows_scout_radius()`. A
   required `tier` parameter would fail GDScript's static argument-count check on those
   calls, which is a parse-time failure, not something fixable by any adapter downstream.
   Making `tier` optional (default `null`) preserves those calls' validity.

2. **The `.get("cover", ...)` reads.** Those same two test functions read the returned
   dictionary with a bare tag key (`"cover"`), not `count_key("cover", radius)`. When
   `tag_counts` resolves `tier` via its `null` fallback, each bucket is seeded with BOTH
   its `count_key()` entry and a bare-tag alias, so those reads keep returning exactly what
   they did before tiers existed. Every other caller (this file's own `capacity()` /
   `best_tier()`, and every external caller I updated for this task) always passes a real
   `HabitatTier` explicitly and never touches the alias path — so the "one formula, two key
   shapes" property the brief asks for still holds for `capacity_from_counts`, and this
   alias is additive, not a competing formula.

**A bug I found and fixed while proving this out, per the brief's own instruction ("if
that suite goes red, your adapter or your `legacy_tier()` assumption is wrong; fix your
code, never the suite"):** my first pass at the `tier == null` fallback called
`species.legacy_tier()` directly. That function is CACHED on the `AnimalDefinition`
instance and bakes a CONCRETE radius (`effective_capacity_radius()` at first-call time)
into each synthesised need, rather than leaving the `RADIUS_FOLLOWS_SCOUT` sentinel in
place. `_check_sentinel_follows_scout_radius()` retunes `scout_radius` on a live species
object between two direct `tag_counts()` calls and expects the tile walk to follow (2 tiles
-> 5 tiles). With the cached tier, the second call still used the FIRST call's baked
radius, and the assertion failed (`expected 5, got 2`).

Fix: added `_uncached_legacy_tier(species)` — a private, NEVER-CACHED mirror of
`AnimalDefinition.legacy_tier()`'s construction, differing only in that it leaves each
need's `radius` at `HabitatNeed.RADIUS_FOLLOWS_SCOUT` (the sentinel) instead of baking a
concrete value. `tag_counts`'s `tier == null` fallback now calls this instead of
`species.legacy_tier()`, so the fallback radius is re-resolved fresh from
`species.effective_capacity_radius()` on every call — matching the pre-tier `tag_counts`'s
behaviour exactly. `capacity_from_counts` still uses `species.legacy_tier()` (the cached,
brief-verbatim path) because nothing in the pinned suite retunes `scout_radius` between two
`capacity_from_counts` calls on the same species — the caching hazard is real but not
exercised there.

Both deviations are documented in code comments on `tag_counts` and
`_uncached_legacy_tier`.

## Callers of `tag_counts()` updated

`grep -rn "tag_counts" project/` found exactly one external caller besides the two
production sites inside `capacity_evaluator.gd` itself (`capacity()`, and now
`best_tier()`):

- **`project/tests/test_tile_exclusivity.gd`** — six call sites (`_check_overlapping_sites_split_the_tiles`,
  `_check_different_species_do_not_split_tiles`, `_check_prospective_candidate_loses_ties`),
  all built synthetic legacy-fielded species (`habitat_needs` / `tiles_per_individual` /
  `scout_radius`, no `tiers`). These previously called `tag_counts(grid, registry, origin,
  species, self_site)` positionally — under the new signature that fifth positional arg
  would bind to the new `tier: HabitatTier` parameter, and passing a `HomeSite` there is a
  static type mismatch (a genuine compile break, confirming this really is a caller that
  needed updating, not one the null-default trick could paper over). I added a small test
  helper, `_cover_count(grid, registry, origin, species, self_site)`, that resolves
  `species.legacy_tier()` explicitly and reads back
  `count_key("cover", species.effective_capacity_radius())`, and replaced all six call
  sites (plus the two "solo" comparison calls and the "unclaimed" sanity call) with it.
  Behaviour is unchanged; only the plumbing to reach it moved.

`test_capacity_formula.gd`'s own `tag_counts` calls needed no edits — see "Deviation"
above; they are exactly what the `tier == null` fallback exists for.

No other file (`habitat_simulation.gd`, `gentle_displacement.gd`, `home_site_registry.gd`,
`news_report_content.gd`, `probe_frame_cost.gd`, `test_registry_scaling.gd`,
`test_save_round_trip.gd`, `test_home_prop.gd`, `test_causality_end_to_end.gd`) calls
`tag_counts` directly — they all go through `capacity()` / `qualifies()`, whose signatures
did not change.

## Files changed

- `project/scripts/simulation/capacity_evaluator.gd` (modified) — the rewrite above.
- `project/tests/test_tier_capacity.gd` (new) — the brief's Step-1 test, verbatim.
- `project/tests/test_tier_capacity.gd.uid` (new, engine-generated) — committed alongside.
- `project/tests/test_tile_exclusivity.gd` (modified) — updated `tag_counts()` call sites,
  added `_cover_count()` helper.
- Five carried `.gd.uid` files from Tasks 1-2, committed as a separate first commit per the
  dispatch instructions:
  - `project/scripts/definitions/habitat_limit.gd.uid`
  - `project/scripts/definitions/habitat_need.gd.uid`
  - `project/scripts/definitions/habitat_tier.gd.uid`
  - `project/tests/test_animal_tiers.gd.uid`
  - `project/tests/test_habitat_tier_schema.gd.uid`

## Test commands and output

1. `bash scripts/run-tests.sh tier_capacity` (sandbox disabled — required; a sandboxed run
   crashes with signal 11 on `user://logs/...` file access):
   ```
   PASS  test_tier_capacity
   --- tier capacity: 12 passed, 0 failed ---
   Suites: 1 total, 1 passed, 0 failed
   ```
   (The brief's Step 4 says "Expected: PASS, 11 assertions" — the file as given in the
   brief actually contains 12 `check_eq`/`check` calls across its six `_check_*`
   functions; I copied it verbatim and 12 is what runs and passes. Not a deviation, just a
   brief count that doesn't match its own code.)

2. `bash scripts/run-tests.sh capacity_formula` (sandbox disabled):
   ```
   PASS  test_capacity_formula
   --- capacity formula: 53 passed, 0 failed ---
   Suites: 1 total, 1 passed, 0 failed
   ```
   Unedited, fully green — the regression gate holds.

3. `bash scripts/run-tests.sh` (full suite, sandbox disabled):
   ```
   Suites: 121 total, 116 passed, 5 failed
   Failed suites:
     - test_fox_schema
     - test_human_schema
     - test_inert_land_invariant
     - test_news_report
     - test_rabbit_schema
   ```
   Exactly the five suites called out as expected-red from Task 3 (closed by Task 9). No
   new failures added.

## Self-review findings

- Confirmed the one-walk rule: `tag_counts()` walks the grid exactly once per
  `(site, tier)` pair, out to `tier.max_radius(fallback)`, and buckets each tile into every
  `(tag, radius)` pair whose squared radius contains it via the inner `buckets` loop — no
  per-need re-walk.
- Confirmed `GATE_ONLY` needs never contribute a `min` term (`continue`, not a `supported`
  comparison) and return 0 outright when absent — verified directly by
  `_check_gate_only_does_not_cap()`.
- Confirmed limits gate the whole tier to 0 on violation and never partially scale —
  verified by `_check_limits_gate()`.
- Confirmed no lower clamp: `tier_capacity_from_counts` returns `max(result, 0)` where
  `result` starts at `tier.max_individuals` and can only be pulled down, never up, and 0 is
  allowed through — verified by `_check_no_lower_clamp()` and the pinned suite's own
  "NO LOWER CLAMP" assertions.
- Confirmed `_tile_counts_for()` and its exclusivity/scope logic were left untouched, per
  instruction.
- Confirmed no stray `.gd.uid` files were left untracked after this task's edits (the new
  test file's `.uid` was generated by `--import` and is committed alongside it).

---

## Fix round 1 — remove `_uncached_legacy_tier()`, fix staleness at the source (human ruling, 2026-09-04)

**Finding closed (Important):** `AnimalDefinition.legacy_tier()` both cached and baked a
concrete radius (`need.radius = effective_capacity_radius()`). My original Task 4 patch
only worked around this in one path (`tag_counts()`'s null-tier fallback, via a new
`_uncached_legacy_tier()`). Two more paths still carried the staleness:

1. `capacity()` resolved every tier — including the synthesised legacy one — through the
   cached, baked `species.legacy_tier()`.
2. `capacity_from_counts()` rekeyed the caller's dictionary with a **live**
   `effective_capacity_radius()` against a tier holding a **baked** radius. On any mismatch
   (a retuned `scout_radius`/`capacity_radius` after the cache first populated) every need
   would read 0 from the mismatched key — surfacing silently as "unsuitable" rather than
   as an error, which the pre-tier code never did.

**The ruling, applied verbatim:**

1. `project/scripts/definitions/animal_definition.gd` — `legacy_tier()` now sets
   `need.radius = HabitatNeed.RADIUS_FOLLOWS_SCOUT` instead of baking
   `effective_capacity_radius()`. Every consumer (`tag_counts()`,
   `tier_capacity_from_counts()`, `capacity_from_counts()`'s rekey) computes `fallback`
   fresh as `effective_capacity_radius()` at call time, so the sentinel resolves to
   exactly the same value everywhere the keys are built, and the cache can no longer go
   stale because nothing concrete is baked into it.
2. `project/scripts/simulation/capacity_evaluator.gd` — deleted `_uncached_legacy_tier()`
   entirely. `tag_counts()`'s `tier == null` fallback now calls `species.legacy_tier()`
   directly again (the cached path), which is safe now that (1) is in place.
3. Updated `legacy_tier()`'s doc comment (this task's original text explained WHY the
   radius was baked; that rationale no longer applies) to explain that the sentinel is what
   keeps the cache safe across a retune. Also corrected `tag_counts()`'s and
   `capacity_from_counts()`'s doc comments, which still described the old baked-radius
   behaviour and were now factually wrong about the same fact this ruling changed —
   left everything else in both files untouched.
4. `project/tests/test_animal_tiers.gd` — Task 2's own pinned suite had one assertion,
   `tier.needs[0].effective_radius(0) == def.effective_capacity_radius()`, which relied on
   the OLD baked behaviour (passing fallback `0` only worked because the need's `radius`
   was already a concrete, non-sentinel value, so `effective_radius()` ignored the
   fallback entirely). With the sentinel now in place, `effective_radius(0)` correctly
   resolves to `0`, and the assertion needed to pass the species' own
   `effective_capacity_radius()` as the fallback instead — which is what every real caller
   does. Split into two assertions: one pinning that the need's `radius` field is now
   literally the sentinel, and one pinning that it still resolves to the species' capacity
   radius when given that as its fallback (preserving the original assertion's intent).

**Left alone, per explicit instruction** (deferred to the final whole-branch review):
- `tag_counts()`'s legacy mode still emits both a radius-keyed and a bare-tag-alias entry
  per bucket.
- Two needs sharing a tag and a resolved radius still share one bucket key.

### Test commands and output (sandbox disabled throughout)

**`bash scripts/run-tests.sh capacity_formula`** — the pinned 53-assertion gate, unedited:
```
--- capacity formula: 53 passed, 0 failed ---
capacity formula OK
Suites: 1 total, 1 passed, 0 failed
```
Includes, still passing: `capacity_radius is STILL the untouched sentinel after the
retune`, `...and effective_capacity_radius() followed scout_radius to 12 — the relation
held`, `...and the tile walk followed too: the three distance-10 tiles are now IN, 2 -> 5`,
`NEGATIVE CONTROL: retuning scout_radius back to 8 puts the count back to 2`.

**`bash scripts/run-tests.sh tier_capacity`**:
```
--- tier capacity: 12 passed, 0 failed ---
tier capacity OK
Suites: 1 total, 1 passed, 0 failed
```

**`bash scripts/run-tests.sh animal_tiers`** (after the `test_animal_tiers.gd` fix above):
```
--- animal tiers: 17 passed, 0 failed ---
animal tiers OK
Suites: 1 total, 1 passed, 0 failed
```
(15 passed / 1 failed before the fix — the one failure was the stale-baked-radius
assertion described above; now 17 passed / 0 failed, since the single assertion was split
into two.)

**`bash scripts/run-tests.sh`** (full suite):
```
Suites: 121 total, 116 passed, 5 failed
Failed suites:
  - test_fox_schema
  - test_human_schema
  - test_inert_land_invariant
  - test_news_report
  - test_rabbit_schema
================================================================
```
Exactly the five expected Task-3 suites, unchanged.

**`_uncached_legacy_tier()` confirmed removed:** `grep -rn "_uncached_legacy_tier"
project/` returns no matches anywhere in the project.

### Files changed in this fix round

- `project/scripts/definitions/animal_definition.gd` — `legacy_tier()` no longer bakes a
  concrete radius; doc comment rewritten.
- `project/scripts/simulation/capacity_evaluator.gd` — `_uncached_legacy_tier()` deleted;
  `tag_counts()` routes its null-tier fallback back through `species.legacy_tier()`;
  `tag_counts()`'s and `capacity_from_counts()`'s doc comments corrected to match.
- `project/tests/test_animal_tiers.gd` — one stale assertion split into two, now
  consistent with the sentinel-radius design.
