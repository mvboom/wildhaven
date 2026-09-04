# Task 5 report — Resident-emitted tags counted per individual

## Fix round 1 (coordinator finding: Important — suite never called production code)

**Finding.** All three original assertions in `test_resident_tags.gd` were algebraic
mirrors of the logic (`contributed[tag] += site.population()` computed in the test itself)
rather than calls into `CapacityEvaluator.tag_counts()`. Nothing exercised the bucket-write
loop actually changed at `capacity_evaluator.gd:132-142`, so a regression there (e.g. one
per SITE instead of one per RESIDENT) would have passed the suite silently.

**Fix.** Kept the three original checks (they still pin the data shape) and added four
integration checks that build a real `WorldGrid` + `HomeSiteRegistry` — copying
`test_tile_exclusivity.gd`'s own setup pattern (`WorldGrid.new(); grid.build(TerrainDefinition
.load_all(), 20, 20)`) — and call `CapacityEvaluator.tag_counts()` directly:

1. `_check_tag_counts_counts_residents_per_individual()` — THE LOAD-BEARING CASE. A
   registered site 2 tiles from the query origin holds 4 residents and `resident_tags =
   ["people"]`; queried with an explicit `HabitatTier` (`people` need, radius 6, divisor 1),
   `tag_counts()` must return `people@6 = 4`. This is the assertion that would catch a
   per-tile (rather than per-individual) implementation.
2. `_check_tag_counts_reaches_both_key_shapes()` — same setup, called with no `tier`
   argument (legacy mode, resolving through `species.legacy_tier()`). Asserts residents
   reach BOTH the radius-keyed entry (`count_key("people", 6)`) AND the bare-tag alias
   (`counts.get("people")`) — the gap the task brief specifically warned about ("if you add
   residents only to radius-keyed buckets, legacy-mode callers silently see zero
   residents"). Previously only verified by reading code; now executable.
3. `_check_tag_counts_vacant_contributes_nothing()` — a registered but unclaimed-of-
   residents site (`resident_tags` set, zero residents appended) must read `people@6 = 0`
   through the real function — the behavioural difference between needing `people` and
   needing `house`.
4. `_check_tag_counts_self_site_skips_own_residents()` — a species `"colony"` that both
   needs and (via its site's `resident_tags`) emits `people`, queried with its OWN site
   passed as `self_site`, must read `people@6 = 0` (no bootstrap). A negative control in the
   same check — an UNRELATED species (`"dog"`) querying the same site from a nearby
   position — confirms the zero is specifically the self-site skip and not a broken counter
   (it reads `4`). Note: the negative control deliberately uses a *different* species scope,
   not the same `"colony"` species from a different position — querying with `"colony"`
   again would instead hit the pre-existing SAME-SPECIES tile-exclusivity rule (the
   registered site is the strictly-nearer owner of its own tile), a different mechanism
   than the one this check targets.

**Production code:** untouched in this round, per instruction. `git status` after this
round shows only `project/tests/test_resident_tags.gd` modified.

**No production bug found.** All four new integration checks passed against the existing
implementation from the first round; nothing needed fixing in `capacity_evaluator.gd`,
`home_site.gd`, `home_site_registry.gd`, or `habitat_simulation.gd`.

### Test commands and output (fix round 1)

1. `bash scripts/run-tests.sh resident_tags` (sandbox disabled) — **PASS**, 14/14
   assertions (8 original + 4 new integration checks, one of which — the self-site-skip
   check — itself carries 2 assertions).
2. `bash scripts/run-tests.sh capacity_formula` — **PASS**, 53/53, file untouched.
3. `bash scripts/run-tests.sh tier_capacity` — **PASS**, 12/12.
   `bash scripts/run-tests.sh tile_exclusivity` — **PASS**, 45/45.
4. `bash scripts/run-tests.sh` (full suite) — 122 total, 117 passed, 5 failed. Failed
   suites unchanged: `test_fox_schema`, `test_human_schema`, `test_inert_land_invariant`,
   `test_news_report`, `test_rabbit_schema`.

One iteration during this round: the first draft of the self-site negative control queried
with the SAME species (`"colony"`) from a different position and got `0` instead of the
expected `4` — not a production bug, but the negative control itself exercising the
pre-existing same-species tile-exclusivity rule (the registered site is the strictly-nearer
owner of its own tile, so a same-species rival 2 tiles away cannot read tags off it either).
Switched the negative control to an unrelated species (`"dog"`) to isolate the self-counting
mechanism from the exclusivity mechanism, per the comment left in the test.

---

## What I implemented

- `project/scripts/simulation/home_site.gd`: added `resident_tags: Array[String]`, a
  derived (never-persisted) field documented as copied from the species' `emits_tags` at
  claim/restore time.
- `project/scripts/simulation/home_site_registry.gd`: added `sites_at(position: Vector2i)
  -> Array[HomeSite]`, returning every site whose own position exactly matches (distinct
  from `sites_covering()`, which is radius-based).
- `project/scripts/simulation/capacity_evaluator.gd`: `tag_counts()`'s per-tile inner loop
  now also reads resident-emitted tags for the current tile, gated behind the same
  `_tile_counts_for()` exclusivity check that already gates terrain tags, and skipping
  `self_site` to prevent self-counting.
- `project/scripts/simulation/habitat_simulation.gd`: `_move_in()` now sets
  `site.resident_tags = species.emits_tags.duplicate()` right after the site is
  registered/claimed; `restore_site()` sets the same thing right after `species` is
  resolved (and the "unknown species" null-check has already returned).
- `project/tests/test_resident_tags.gd` (new, plus `.gd.uid` sibling): the brief's suite,
  with one correction (see below).

## Adapting the stale `tag_counts()` snippet to the real shape

The brief's reference snippet assumed a `key`/`counts[key]+=1` bucket shape from before
Task 4. The current `tag_counts()` instead builds `buckets` as `{keys: Array[String], tag,
r_squared}`, where `keys` holds:
- always: the radius-keyed `count_key(tag, radius)` entry;
- additionally, in legacy mode (`tier == null`, i.e. `species.legacy_tier()` resolved):
  the bare-tag alias key (no `@radius` suffix), for `test_capacity_formula.gd`'s pinned
  bare-tag reads.

I kept the walk's existing per-tile, per-bucket loop and added a `resident_counts`
Dictionary built once per tile (summing `resident_site.population()` per emitted tag,
across every `HomeSiteRegistry.sites_at(tile)` entry except `self_site`, only when
`population() >= 1`). Inside the existing bucket loop I compute `added = (1 if tile_tags
has the tag else 0) + resident_counts.get(tag, 0)`, then write `added` into **every** entry
of `bucket["keys"]` — the same array the terrain-tag branch already wrote 1 into. Because
that array already contains both the radius-keyed entry and (in legacy mode) the bare-tag
alias, resident contributions land in both key shapes automatically, by construction, not
by a second special case.

## How I verified both key shapes see residents

1. `test_resident_tags.gd`'s `_check_counted_per_individual()` exercises the tiered path
   directly on a `HomeSite` object (no `tag_counts()` call) — this is the load-bearing
   per-individual assertion from the brief, confirmed passing.
2. I traced the code path rather than adding a redundant legacy-mode test: `buckets` is
   built once per call and is the same array object read by both the terrain-tag branch
   (`tile_tags.has(bucket_tag)`) and the new resident branch (`resident_counts.get(...)`).
   Since the terrain branch already writes into every `bucket["keys"]` entry and is
   exercised by `test_capacity_formula.gd`'s legacy-mode (`tag_counts(grid, registry,
   origin, species)`, no `tier` arg) assertions that read bare-tag keys and pass, the
   resident branch — which loops over the identical `bucket["keys"]` array with the same
   `for key: String in (...)` — is structurally guaranteed to reach the same keys. I also
   re-ran `bash scripts/run-tests.sh capacity_formula` (53/53 pass, unedited file) as a
   negative control: no species in the current roster sets `emits_tags` yet, so
   `resident_counts` is always empty there and every existing assertion is byte-identical
   to before this task — confirming the new branch is additive and does not disturb the
   legacy-mode key set already under test.

## `restore_site()`

Added `site.resident_tags = species.emits_tags.duplicate()` in
`HabitatSimulation.restore_site()` immediately after `species` is resolved via
`_roster.by_id(site.species_id)` and the "unknown species" guard clause (which already
returns/unregisters and must not fall through to derive tags for a species that doesn't
exist). Placed before the resident-node reconstruction loop, matching the brief's
placement instruction ("immediately after the site is obtained" — here, immediately after
the species used to build it is obtained, since resolving `species_id` alone isn't enough
to look up `emits_tags`). A vacant restored structure site (`site.is_vacant()` returns
early above this line) keeps `resident_tags` at its default `[]`, which is correct: no
species, no residents, nothing to derive.

## Self-counting guard

`self_site` is skipped by identity (`if resident_site == self_site: continue`) inside the
`sites_at(tile)` loop, for both call shapes:
- **Prospective candidate** (`self_site == null`): can never equal a real `HomeSite`
  instance, so the skip is a no-op and every resident site at that tile counts normally.
- **Re-evaluation** (`self_site` is the registered site itself): when the walk reaches the
  site's own tile (`dx == 0, dz == 0` is always in radius), `sites_at(tile)` will include
  `self_site` among possibly other species' sites sharing that position; the identity skip
  excludes only that one entry, so a species doesn't bootstrap off its own residents while
  still correctly counting a *different* species' co-located residents (e.g. a Husky's
  `people` need reads a human site sharing its tile, not itself).

## One correction to the brief's test

The brief's `_check_absent_when_vacant()` snippet constructed `HomeSite.new(Vector2i(0,0),
"human", 9, 0)` and then asserted `site.is_vacant()`. `HomeSite.is_vacant()` is unmodified,
pre-existing code that reads `species_id == ""`, not population — so a site constructed
with `species_id = "human"` can never be vacant by that definition, and the assertion
failed (7/8, not 8/8). I changed the constructor call to `species_id = ""`, which is what
`HomeSiteRegistry.release()` actually leaves behind once the last resident departs a house
(`structure_remains = true` path) — the real-world state the test's own comment ("an empty
house is vacant") describes. `resident_tags` staying stale (`["people"]`) on that vacated
site is intentional and still exercised: `population() == 0` gates it out of any
contribution regardless. This is a test-only fix; no production file's `is_vacant()`
semantics were touched.

## Test commands and output

1. `bash scripts/run-tests.sh resident_tags` (sandbox disabled) — **PASS**, 8/8 assertions:
   sites_at (3), counted-per-individual (2), absent-when-vacant (3).
2. `bash scripts/run-tests.sh capacity_formula` — **PASS**, 53/53, file untouched.
3. `bash scripts/run-tests.sh tier_capacity` — **PASS**, 12/12.
   `bash scripts/run-tests.sh tile_exclusivity` — **PASS**, 45/45.
4. `bash scripts/run-tests.sh` (full suite) — 122 total, 117 passed, 5 failed. Failed
   suites: `test_fox_schema`, `test_human_schema`, `test_inert_land_invariant`,
   `test_news_report`, `test_rabbit_schema` — exactly the five expected-red suites from
   Task 3; no new failures added.

Note: the first `resident_tags` run crashed under the default sandbox (signal 11,
`Failed to open 'user://logs/...'`) before any test output — a filesystem-write
restriction, not a code defect. Re-run with `dangerouslyDisableSandbox: true` (as directed
by the task) produced clean output.

## Self-review findings

- Confirmed `capacity_evaluator.gd`'s pinned suite (`test_capacity_formula.gd`) was not
  edited and still passes byte-for-byte against its own assertions.
- Confirmed the resident branch respects the same `_tile_counts_for()` exclusivity gate
  the terrain-tag branch already respects, rather than bypassing it — a resident's tag
  contribution is only visible to candidates the land tile itself counts for.
- Confirmed no species in the current roster sets `emits_tags` yet (grepped
  `roster/*.tres`), so this task changes zero existing capacity numbers — consistent with
  the brief's expectation ("no species emits anything yet, so counts are unchanged").
- Left `_tile_counts_for()` untouched, per instruction.

## Changed files

- `project/scripts/simulation/home_site.gd` (modified)
- `project/scripts/simulation/home_site_registry.gd` (modified)
- `project/scripts/simulation/capacity_evaluator.gd` (modified)
- `project/scripts/simulation/habitat_simulation.gd` (modified)
- `project/tests/test_resident_tags.gd` (new)
- `project/tests/test_resident_tags.gd.uid` (new, generated by the import pass)
