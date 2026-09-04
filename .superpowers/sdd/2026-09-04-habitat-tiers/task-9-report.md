# Task 9 report — Re-spec the roster

## Summary

Converted all **fifteen** shipped `AnimalDefinition` `.tres` files to carry real `tiers`
(and, for the two resident-emitting species, `emits_tags`), transcribed from the spec's
§ 9 table. `chicken.tres` was **not created** — the brief's "sixteen species" was wrong
(corrected by the dispatcher); Chicken's asset was never purchased, so `coop` (emitted by
`ChickenCoop`) now has no consuming species in the shipped roster, same posture as the
already-dormant `sand` tag. Legacy flat fields (`habitat_needs`, `tiles_per_individual`,
`max_individuals`) were left in place, untouched, on every file — they are now inert
(`effective_tiers()` prefers non-empty `tiers`) but make a rollback a one-line edit.

`deer.tres` and `human.tres` were converted **last**, as instructed, since they are the
roster's only two `emits_tags` carriers.

New suite `project/tests/test_roster_signatures.gd` asserts the distinctness guarantee
directly: 15 species, 15 distinct signatures, every species categorised (person/wild/
domesticated), exactly two emitters (`human`→`people`, `deer`→`deer`), and an acyclic
dependency graph. It is **green**.

All five previously-red suites (`test_fox_schema`, `test_human_schema`,
`test_inert_land_invariant`, `test_news_report`, `test_rabbit_schema`) are now **green**.
Fixing them required one small code change (`AnimalDefinition.BARE_TAGS` still referenced
the retired `quiet` tag) plus test-fixture updates in eight *other* suites that painted
the rabbit's now-obsolete `cover`/`rock` habitat directly — every one of those was a real,
traceable consequence of `capacity_at()` now reading `effective_tiers()` instead of the
legacy flat fields once `tiers` went non-empty. **The full suite is green: 126/126
suites passed.**

## The final 15-species table, as committed

Notation matches the spec: `tag/divisor` = scaling need (radius `@n` when explicit,
otherwise follows `scout_radius`), `tag*` = `GATE_ONLY`, `!tag≤N` = limit.

### Wild (carries a `built` limit)

| Species | Tier(s) |
|---|---|
| Deer | **base**: `open_grass/5` `forest/4` `!built≤1`, max 4 · **herd**: `open_grass/5@14` `forest/4@14` `browse/6@14` `!built≤0@14`, max 8, arrive 3 |
| Stag | **rare**: `open_grass/5@14` `forest/3@14` `deer/4@14` `!built≤0@14`, max 2 |
| Fox | **territory**: `forest/4` `open_grass/5` `water/6` `!built≤0`, max 6 |
| Rabbit | **base**: `open_grass/4` `cultivated/4` `!built≤2`, max 3 · **warren**: + `flowers/5` (same limit), max 8, arrive 4 |
| Donkey | **range**: `browse/5` `rocks/4` `!built≤1`, max 6 |

### Domesticated (≥1 building gate; no `built` limit)

| Species | Tier(s) |
|---|---|
| Cow | **pair**: `barn*` `silo*` `open_grass/5`, max 2 · **herd**: + `water/3`, max 6, arrive 2 |
| Bull | **pen**: `large_barn*` `cultivated/6`, max 1 |
| Horse | **pair**: `stable*@5` `open_grass/6@8`, max 2 · **herd**: `stable*@5` `open_grass/4@14` `water/2@12`, max 12, arrive 3 (brief's own worked example, transcribed verbatim) |
| Alpaca | **highland**: `barn*` `open_grass/5` `rocks/6`, max 6 |

### Person (needs or emits `people`; checked first)

| Species | Tier(s) |
|---|---|
| Villager (human) | **single**: `house*` `cultivated/1`, max 1 · **family**: `large_house*` `cultivated/2`, max 4, arrive 3. `emits_tags = ["people"]` |
| Pig | **sty**: `cultivated/4` `people/2`, max 6 |
| Sheep | **base**: `open_grass/4` `people/3`, max 3 · **flock**: + `mill*` (GATE_ONLY — see interpretation flag below), max 8, arrive 4 |
| Husky | **companion**: `snow/6` `people/2`, max 6 |
| Pug | **companion**: `house*` `people/5`, max 6 |
| Shiba Inu | **companion**: `house*` `rocks/4` `people/3`, max 6 |
| Deer | *(emitter, see Wild table above)* `emits_tags = ["deer"]` |

Fifteen species, fifteen distinct signatures — verified by `test_roster_signatures.gd`.

## Expectation edits — every one, old → new, file, reason

### Code (non-test)

1. **`project/scripts/definitions/animal_definition.gd`** — `BARE_TAGS`:
   `["open_grass", "quiet"]` → `["open_grass"]`. Reason: `quiet` was retired from
   `HABITAT_TAGS` by an earlier task in this design (habitat-tiers ruling, spec OQ-F), but
   `BARE_TAGS` was never updated to match, so `test_inert_land_invariant.gd`'s
   "every `BARE_TAGS` entry is in the shared vocabulary" check failed. This is a real
   defect fix, not a data-value proposal — traced directly to the tag retirement, not
   invented here.

### The five target suites

2. **`test_inert_land_invariant.gd`** — two assertions repointed from "a species needing
   only `quiet` / `open_grass`+`quiet` is REJECTED" to "...is NOT flagged by the inert-land
   invariant specifically any more". Reason: `quiet` is no longer in `BARE_TAGS` (see
   above), so a species needing only the retired tag can no longer trip *this* invariant
   (it still gets a different, vocabulary-unknown-tag problem, which this suite's
   substring filter deliberately doesn't chase). No assertion deleted; both were rewritten
   to state the new, correct behaviour and explain why.
3. **`test_fox_schema.gd`, `test_human_schema.gd`, `test_rabbit_schema.gd`** — **no edits
   needed.** These three went green purely from fox/human/rabbit gaining real `tiers`
   (giving each species a `category()` other than `""`), which is what `validate()`'s
   category-coherence check required. All pinned legacy-field values (`habitat_needs`,
   `tiles_per_individual`, `scout_radius`, `fact_text`, etc.) were left untouched and still
   match, because I never touched the legacy fields.
4. **`test_news_report.gd`** — the synthetic `fresh` critter fixture in
   `_check_schema_field_exists()`: `habitat_needs = ["cover"]` → `habitat_needs = ["cover",
   "people"]`. Reason: same category-coherence requirement as above; this fixture predates
   that rule and had no building gate/limit, so it matched no category. Adding `"people"`
   as a second need makes it Person (the same category a real needs-`people` species like
   Pig resolves to), without touching what the check actually verifies (that
   `news_reports` stays optional).

### Eight collateral suites (traceable to the same root cause: `capacity_at()` now reads
`effective_tiers()`, and Rabbit's tier needs `open_grass`+`cultivated`, not `cover`)

Every one of these suites had its own copy of the "paint a rock block beside a grass
border to make the shipped Rabbit qualify" fixture, several written explicitly to exercise
the *real* `.tres` files (not synthetic species) through the real causal chain. All were
repointed the same way: the block that used to be painted `rock` (providing `cover`) is
now painted `cultivated_field` (providing `cultivated`) — same block size, same divisor
(4), same arithmetic, only which terrain supplies the tag changed. Grass borders
(`open_grass`) were left untouched. Comments were updated in place to explain the
re-point and cite this task.

5. **`test_avoids_distance_keeping.gd`** — `_check_avoids_never_gates_a_move_in()`:
   rabbit's rock+grass blocks → grass + `cultivated_field`; fox's forest+rock blocks →
   forest + a 6/6 split of `water`/`grass` (Fox's tier now needs `forest/4` `open_grass/5`
   `water/6`, not `forest`+`cover`).
6. **`test_causality_end_to_end.gd`** — `_check_wild_species_causality()`: the 4x3
   `ROCK_ORIGIN` block → `cultivated_field`; assertion message and the
   `_note_capacity_is_not_a_binding_cap()` pending-note text updated from "cover"/"rock" to
   "cultivated". `capacity_at()` re-derivation assertion text updated; the numeric
   expectation (3) is unchanged — only which tag supplies it moved.
7. **`test_event_driven_simulation.gd`** — `_check_wander_is_not_simulation_work_hand_driven()`:
   `WANDER_ROCK_ORIGIN` block → `cultivated_field`.
8. **`test_home_prop.gd`** — `_check_prop_changes_nothing_about_the_tile()`'s synthetic
   grid (`grid.set_terrain(..., "rock")` → `"cultivated_field"`) and
   `_check_counts_in_the_real_world()`'s real-world block (`_world.paint_tile(...,
   "rock")` → `"cultivated_field"`).
9. **`test_mode_tap_model.gd`** — `_check_the_live_neighborhood_preview_...()` (near the
   tap-cursor preview check): the 4x4-minus-centre block → `cultivated_field`; assertion
   message "cover for a rabbit" → "cultivated for a rabbit".
10. **`test_neighborhood_preview.gd`** — the boundary-crossing sweep (`SWEEP_TILE`, 15
    incremental tiles), the `home`-band fixture (`HOME_ORIGIN` block), and the
    near-miss demonstration (3 tiles, then the 4th) all repointed from `rock` to
    `cultivated_field`. Also added `_world.wood.reset(1000)` in `_initialize()` — the
    scarce need moved from free `rock` to `cultivated_field` (cost 2/tile), and this
    suite's several such blocks together exceed the 50-Wood starting budget; no check in
    this suite asserts on Wood, so this is a pure test-fixture fix, same pattern
    `test_economy_rules.gd`/`test_removal_refund.gd`/`test_mode_tap_model.gd` already use.
11. **`test_resident_lookup.gd`** — the `ROCK_ORIGIN` block → `cultivated_field`.
12. **`test_save_round_trip.gd`** — `_build_a_world_through_the_real_causal_path()`'s
    `ROCK_X_FROM..ROCK_X_TO` row → `cultivated_field`, and
    `_check_a_pending_arrival_survives_a_reload_with_no_home_site_yet()`'s identical row →
    `cultivated_field`. Const-level doc comment updated.

**Counts stayed flat or rose everywhere; no assertion was deleted; no vocabulary or radius
band was widened.** Every edit either (a) followed directly from a species' real tier
needs changing, or (b) was a documented test-fixture-only Wood budget bump with no
assertion consequence.

## Values awaiting human sign-off (every one is a PROPOSAL)

Recorded in each `.tres`'s own header comment, citing
`docs/superpowers/specs/2026-09-04-habitat-tiers-design.md § 9`, per the established
`horse.tres`/`barn.tres` convention. Summarized here:

- **Every divisor, radius, limit, `max_individuals`, and `arrival_group_size` value** in
  all 15 files — the spec's § 9 table gives tags/gates/limits and a handful of explicit
  numbers (Stag max 2, Bull max 1, Horse's full worked example, Villager 1/4, Rabbit
  arrive 4, Sheep arrive 4, Cow arrive 2, Deer arrive 3); every number *not* explicitly
  given by the spec (most `max_individuals` values, all "base tier" caps, the wider radii
  on group/herd tiers) is this task's own first-pass proposal, sourced only from the
  legacy `max_individuals`/`tiles_per_individual` values already shipped and from the
  design's own worked examples (Horse, Stag). None of these are decisions.
- **Sheep's `mill` group-tier need — interpretation flag.** The spec table writes it as
  bare `mill`, with no `/divisor` and no explicit `*`. I read this as `GATE_ONLY`
  (present-or-not, matching the Windmill's role as a landmark rather than a scaling
  resource) and flagged this explicitly in `sheep.tres`'s header. The human should confirm
  this reading or supply a divisor.
- **Deer's group-tier "wider radii" and Stag's `@14`** — the spec names the *concept*
  ("wider radii") for Deer's herd tier without a specific number, and gives Stag's number
  (`@14`) directly. I used `14` for both, for consistency (Deer's herd tier is meant to
  read as genuinely wide land, same as Stag's neighbourhood-scale reading of a deer
  population) — this specific choice of 14 for Deer is my own proposal, not the spec's.
- **`AnimalDefinition.BARE_TAGS`'s new value (`["open_grass"]`)** is a direct, mechanical
  consequence of `quiet`'s prior retirement (spec OQ-F) — not a new proposal, but flagged
  here since it is a code change, not a `.tres` proposal.

## Disagreement with the brief, corrected before starting

The brief said "sixteen species" and directed `roster.size() >= 16`. Per the dispatching
agent's own correction message, there are **fifteen**: `project/data/animals/` holds
exactly `alpaca bull cow deer donkey fox horse human husky pig pug rabbit sheep shiba_inu
stag`; Chicken has no `AnimalDefinition` (asset unpurchased). I did not create
`chicken.tres`, wrote the new suite's assertion as `roster.size() >= 15`, and this report
states 15 throughout. Consequence recorded: `coop` (emitted by `ChickenCoop`) has no
consuming species in the shipped roster — acceptable, matching the already-dormant `sand`
tag, not something I invented a consumer for.

## Test commands and output

1. `bash scripts/run-tests.sh roster_signatures` — **PASS**. All checks green: every
   species validates clean, 15 distinct signatures, every species categorised, exactly two
   emitters (`human`, `deer`), acyclic graph.
2. `bash scripts/run-tests.sh fox_schema` / `human_schema` / `inert_land` / `news_report` /
   `rabbit_schema` — **all PASS** individually.
3. `bash scripts/run-tests.sh` (full suite) — **126 total, 126 passed, 0 failed.**

All Godot invocations run with `dangerouslyDisableSandbox: true` (segfaults writing
`user://logs` otherwise, per this repo's known sandbox gotcha); `--import` was run before
every `--script`/test invocation via `scripts/run-tests.sh`, never a bare `--quit`.

## Self-review findings

- Confirmed the species directory contents (`find project -name 'horse.tres'` and a
  listing of `project/data/animals/`) before writing anything, per the brief's own
  instruction, and before trusting the "sixteen" claim.
- Worked species-by-species, running `roster_signatures` after each file, exactly as
  instructed — every species landed green in isolation before moving to the next, so a
  mistake would have been attributable to the file that caused it. (None were.)
- Converted `deer.tres` and `human.tres` last, as instructed — confirmed the acyclicity
  check first ran green against the fullest possible graph (both emitters present) on the
  very last file edit.
- Manually verified signature distinctness by hand (tag/divisor/radius/limit tuples per
  species) before running the suite, to catch a collision before burning a test cycle on
  it — none were found; the test run confirmed this.
- Checked every other test file in the repo for a hardcoded dependency on a specific
  species' `habitat_needs`, tier count, or the pre-existing roster size, via
  `grep -l "res://data/animals"` and a `roster.size()`/`SpeciesRoster.new()` sweep — found
  and fixed all 8 real collateral suites (none were missed on the first full-suite run
  after the roster conversion).
- Did **not** touch `HabitatRecipe`/the UI recipe display code path: confirmed by reading
  `scripts/ui/habitat_recipe.gd` that it reads the LEGACY flat `habitat_needs`/
  `tiles_per_individual` fields directly, never `effective_tiers()` — so leaving those
  fields untouched on every species (per the brief) was sufficient to keep
  `test_habitat_recipe.gd` green with zero edits, which it was.
- Did not touch `game-design/roster.md`, `content-pipeline-status.md`, or
  `systems-pipeline.md`/`tier1-status.md` — this task's brief and the dispatching agent's
  scope were the `.tres` files, the new test, and any collateral test breakage; the design
  doc / pipeline-status updates that would normally accompany a Content Pipeline step 4
  landing were not part of this dispatch and are noted here as a gap, not silently
  skipped.
- Ran no git commands, per the report format's own instruction — changed files are listed
  below and in `git status` for the orchestrating agent to commit.

## Changed files

**New:**
- `project/tests/test_roster_signatures.gd` + `.gd.uid`

**Modified — all 15 species `.tres` (every habitat value inside is a PROPOSAL awaiting
human sign-off, per each file's own header comment):**
- `project/data/animals/alpaca.tres`
- `project/data/animals/bull.tres`
- `project/data/animals/cow.tres`
- `project/data/animals/deer.tres`
- `project/data/animals/donkey.tres`
- `project/data/animals/fox.tres`
- `project/data/animals/horse.tres`
- `project/data/animals/human.tres`
- `project/data/animals/husky.tres`
- `project/data/animals/pig.tres`
- `project/data/animals/pug.tres`
- `project/data/animals/rabbit.tres`
- `project/data/animals/sheep.tres`
- `project/data/animals/shiba_inu.tres`
- `project/data/animals/stag.tres`

**Modified — code:**
- `project/scripts/definitions/animal_definition.gd` (`BARE_TAGS`: dropped the retired
  `quiet` tag)

**Modified — the five target suites (now green):**
- `project/tests/test_inert_land_invariant.gd`
- `project/tests/test_news_report.gd`
- (`test_fox_schema.gd`, `test_human_schema.gd`, `test_rabbit_schema.gd` needed **no**
  edits — they went green from the species data alone)

**Modified — eight collateral suites (rabbit's obsolete `cover`/`rock` fixtures
repointed to `open_grass`/`cultivated_field`), now green:**
- `project/tests/test_avoids_distance_keeping.gd`
- `project/tests/test_bare_tags_derivation.gd` (pinned `BARE_TAGS` value updated to match
  the code change above)
- `project/tests/test_causality_end_to_end.gd`
- `project/tests/test_event_driven_simulation.gd`
- `project/tests/test_home_prop.gd`
- `project/tests/test_mode_tap_model.gd`
- `project/tests/test_neighborhood_preview.gd`
- `project/tests/test_resident_lookup.gd`
- `project/tests/test_save_round_trip.gd`

## Proposals for the human

1. Every habitat-tier value (divisors, radii, limits, `max_individuals`,
   `arrival_group_size`) in all 15 `.tres` files — see "Values awaiting human sign-off"
   above for the full breakdown of what's spec-given vs. this task's own first-pass fill.
2. **Sheep's `mill` group-tier need** — read as `GATE_ONLY` in the absence of a divisor in
   the spec table; needs explicit confirmation or a divisor.
3. **Deer's herd-tier radius and Stag's `@14`** — used the same `14` for both for
   consistency; the specific number for Deer's "wider radii" instruction was not given by
   the spec and is my own choice.
4. **`AnimalDefinition.BARE_TAGS = ["open_grass"]`** — flagged as a code-side consequence
   of the prior `quiet` retirement, not a new design proposal, but worth the human's eyes
   since it changes what the inert-land invariant considers bare.
5. The design doc trail (`roster.md`'s Already-Defined table, `content-pipeline-status.md`,
   `systems-pipeline.md`/`tier1-status.md`) was **not** updated as part of this dispatch —
   flagged as a likely follow-up, not something I judged in-scope to touch here.
