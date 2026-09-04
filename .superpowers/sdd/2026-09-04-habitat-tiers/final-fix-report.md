# Final whole-branch review — fix report (`feature/habitat-tiers`)

Scope: FINDING C1 (Critical), FINDING I2 (Important), and the two one-line validation
guards. Nothing else touched.

---

## C1 — onboarding coach misinstructs a child

### The failing test, run against pre-fix code

Isolated demo (not committed) driving `OnboardingCoach.bind_content()` against a
single-species (Rabbit) fixture roster, pre-fix source:

```
PASS  rabbit.tres's flat habitat_needs is still the pre-tier pair
RENDERED TEXT: [COPY] Rabbit are easiest. Likes open grass and rocky cover. Tap Grass, then tap the ground.
FAIL  beat 2 no longer tells a player to place Rock: '...Likes open grass and rocky cover...'
PASS  beat 2 names open_grass: '...'
FAIL  beat 2 names cultivated: '...Likes open grass and rocky cover...'
  --- demo c1: 3 passed, 2 failed ---
```

The permanent regression test committed for this
(`test_onboarding_coach.gd::_check_bind_content_beat_two_uses_rabbits_real_tier_not_the_stale_flat_fields`)
reproduces the same two failures when run against the pre-fix `onboarding_coach.gd` /
`habitat_recipe.gd` (verified via `git stash` of the source files, test file unchanged):
the assertions `not text.contains("rocky cover")` and `text.contains("farm field")` both
fail, `text.contains("open grass")` passes (present in both the real tier and the stale
flat fields, so it alone would not have caught the regression — noted in the test's own
comment).

### The fix

`onboarding_coach.gd`'s `bind_content()` called `HabitatRecipe.easiest_species()` →
`recipe_for()` → `describe()` — the three flat-field functions that read
`AnimalDefinition.habitat_needs` / `tiles_per_individual` directly. Every shipped species'
`.tres` now carries real `tiers`; the flat fields are stale leftovers kept only for
rollback (per each `.tres`'s own header comment) and for `AnimalDefinition.legacy_tier()`'s
migration fallback for a species with no authored tiers.

Rewriting `recipe_for()` / `describe()` / `easiest_species()` in place was rejected: every
shipped species has authored tiers today, so that would silently change their meaning for
every existing caller and test at once (`test_habitat_recipe.gd`,
`test_field_guide_reachability.gd`), not just the coach's — out of this task's scope, and
risks the exact kind of collateral breakage the task explicitly warned against.

Instead, `habitat_recipe.gd` gained a parallel, tier-aware section ("THE COACH'S OWN
PATH"): `starter_tier()`, `recipe_for_tier()`, `describe_tier_needs()`,
`easiest_species_by_tier()` — built on `AnimalDefinition.effective_tiers()` from the
start, reusing `tag_sources()` / `_cheapest()` / `SOURCE_PHRASES` / `_join_and()` verbatim
so the coach's wording never drifts from the Field Guide's register. `onboarding_coach.gd`
now calls these instead. The old `recipe_for()` / `describe()` / `easiest_species()`
remain, unchanged, for the flat-fallback path and the tests that pin them directly — but
no longer sit on any display path.

One judgment call flagged as a Proposal: `easiest_species_by_tier()`'s effort ranking
charges a GATE_ONLY need (`tiles_per_individual == 0`) as ONE tile, not zero
(`maxi(count, 1)`), so an expensive gate building is not scored as free. Without this,
Human's `single` tier (a gate-only House + `cultivated/1`) would rank as the cheapest
species in the roster despite requiring a 15-wood House.

### Passing output, post-fix

```
bash scripts/run-tests.sh onboarding_coach
  --- onboarding coach: 32 passed, 0 failed ---
  onboarding coach OK
```

Full relevant excerpt (the regression test, passing):

```
PASS  rabbit.tres loads
PASS  rabbit.tres's flat `habitat_needs` is still the pre-tier ['open_grass', 'cover'] pair ...
PASS  beat 2 no longer tells a player to place Rock — Rabbit's STALE flat need ('rocky cover'), the literal misinstruction finding C1 reported: '[COPY] Rabbit are easiest. Likes open grass and farm field. Tap Grass, then tap the ground.'
PASS  beat 2 names open_grass ('open grass'), which Rabbit's REAL base tier shares with the stale flat fields ...
PASS  beat 2 names cultivated ('farm field', Rabbit's REAL second base-tier need) that the stale flat fields never mentioned at all: '...'
PASS  beat 2 targets the Grass button — the first need in Rabbit's REAL base tier (open_grass) — not Rock, the stale flat fields' second need
```

### The real rendered coach text for Rabbit, post-fix

```
[COPY] Rabbit are easiest. Likes open grass and farm field. Tap Grass, then tap the ground.
```

(Rendered by driving `OnboardingCoach.bind_content()` against a fixture roster containing
only the real, `load()`-ed `rabbit.tres` — see the test above.)

**Important note for the human:** against the FULL live roster (all 15 species), the
"easiest species" the coach actually recommends is no longer Rabbit — it is **Deer**
(tied with Donkey; Deer wins on roster load order). This is not a bug in the fix; it is a
direct, correct consequence of it. Rabbit's real base tier needs `cultivated` (Farm
terrain, cost 2 wood), while Deer's real base tier (`open_grass` + `forest`) is entirely
free terrain — and `WOOD_COST_WEIGHT`'s own stated purpose is "free terrain always beats
anything costing wood, so the coach names a starter a player can reach with no stockpile
at all." The OLD flat-field ranking picked Rabbit only because its stale flat fields
(`open_grass` + `cover`, both free) hid the real, wood-costing `cultivated` requirement.
Verified directly:

```
STARTER: deer
TIER id: base
DESCRIBE: Likes open grass and woods.
```

Full rendered text against the live roster:
`[COPY] Deer are easiest. Likes open grass and woods. Tap Grass, then tap the ground.`

This is flagged under Proposals below — it is a legitimate consequence of fixing the data
source, but it is a game-balance/UX outcome (which species a brand-new player is steered
toward) that the human may want to review.

### Grep proof — no raw flat-field read remains on any display path

```
$ grep -rn '\.habitat_needs\b\|\.tiles_per_individual\b' project/scripts
project/scripts/definitions/animal_definition.gd:418:   need.tiles_per_individual = tiles_per_individual   # legacy_tier() itself — the derivation, not a display
project/scripts/ui/news_report_content.gd:82:          for tag: String in species.habitat_needs:      # pre-existing, OUT OF SCOPE — see below
project/scripts/ui/habitat_recipe.gd:145:      for tag: String in species.habitat_needs:              # old recipe_for() — see below
project/scripts/ui/habitat_recipe.gd:161:                      "count": species.tiles_per_individual, # old recipe_for() — see below
project/scripts/ui/habitat_recipe.gd:449: (doc comment only)
project/scripts/ui/habitat_recipe.gd:505:              "count": need.tiles_per_individual,            # HabitatNeed.tiles_per_individual — TIER data, NOT the flat AnimalDefinition field
project/scripts/ui/field_guide.gd:190: (doc comment only, "no flat describe() ... any more")
project/scripts/simulation/capacity_evaluator.gd:227:  var supported: int = count / need.tiles_per_individual  # HabitatNeed.tiles_per_individual — TIER data
```

```
$ grep -rn 'HabitatRecipe\.recipe_for(\|HabitatRecipe\.describe(\|HabitatRecipe\.easiest_species(' project/scripts
project/scripts/ui/field_guide.gd:28: (doc comment only)
```

No production script calls the flat `recipe_for()` / `describe()` / `easiest_species()`
any more — the only remaining callers are `test_habitat_recipe.gd` (pinning them
directly, unchanged) and doc comments. The two remaining live reads of the raw flat
fields:
  * `animal_definition.gd:418` is `legacy_tier()` itself — the sanctioned migration
    derivation, not a display path.
  * `news_report_content.gd:82` is `NewsReportContent.pick_species()`'s terrain-bias
    weighting for WHICH species gets a pre-written flavor line in the News Report ticker.
    It does not render any text derived from `habitat_needs` (the line itself comes from
    `species.news_reports`, a fixed, human-approved pool) and does not tell a player what
    to build — out of scope for C1, noted for the human, not touched.

---

## I2 — wide tiers never re-evaluate

### The failing tests, run against pre-fix code

`test_wide_tier_home_site_radius.gd` (new suite), run against the pre-fix
`habitat_simulation.gd` / `home_site_registry.gd` / `home_site.gd` (via `git stash` of
just those three files):

```
PASS  the synthetic Big Barn is placed
PASS  SETUP: the site starts registered wide (14)
PASS  SETUP: Shrew actually claimed the site
FAIL  the claim did NOT narrow the site's radius back down to Shrew's own (3) -- the Horse/Open Barn regression finding I2 reported
      expected 14 (int), got 3 (int)
PASS  deer.tres loads
PASS  SETUP: deer.tres's scout_radius is still 10
PASS  SETUP: the world is fully settled -- nothing left over to contaminate the distant-edit discriminator below
PASS  SETUP: a deer settled at the origin via its base tier
FAIL  the site registers at 14 -- the HERD tier's own max_radius() -- even though only the BASE tier (scout_radius 10) is what actually qualified it
      expected 14 (int), got 10 (int)
PASS  SETUP: before the distant edit, base is the winning tier
FAIL  an edit 11-14 tiles out actually re-enqueued and re-evaluated the deer site -- pre-fix, `sites_covering()` never included this site at that distance (site.radius was 10), so `capacity_evaluated` would never fire again for it at all
FAIL  the site's radius is unchanged by the distant edits
      expected 14 (int), got 10 (int)
PASS  ...and the winning tier is now herd, the tier the distant edit actually unlocked
--- wide-tier home site radius (finding I2): 9 passed, 4 failed ---
```

(The last "herd wins" check passes even pre-fix because it calls
`CapacityEvaluator.evaluate()` directly, which reads `tier.max_radius()` on its own,
independent of whether the simulation's dirty queue ever re-enqueued the site — see the
test's own comment. It is a secondary, non-discriminating check; the `capacity_evaluated`
signal check right above it is the one that actually proves the bug.)

### The fix

Two independent bugs, both from `HomeSite.radius` being set to a bare
`species.scout_radius` instead of the widest radius any of the species' own tiers
actually reaches:

1. **`HomeSiteRegistry.claim()`** overwrote `site.radius = radius` unconditionally. A
   structure site registered wide (via `_home_site_radius_for()`'s max across every
   species/tier a building could serve) silently narrowed the moment ANY one species
   claimed it — breaking the spec's own flagship Horse/Open Barn example from the first
   arrival onward. Fixed: `site.radius = maxi(site.radius, radius)` — never narrows.

2. **`HabitatSimulation._move_in()`** registered/claimed a SETTLED (non-structure) site at
   a bare `species.scout_radius`, even when a tier's own need/limit reaches wider
   (`HabitatTier.max_radius()`). Deer's herd tier counts at radius 14 while `scout_radius`
   is 10; land painted 11-14 tiles out never marked the site dirty, because
   `HomeSiteRegistry.sites_covering()` / `HomeSite.covers()` are both keyed on
   `site.radius`. Fixed: a new `_species_widest_radius(species)` helper (maxing
   `tier.max_radius(species.scout_radius)` across `effective_tiers()` — the same
   `tier.max_radius()` call `_home_site_radius_for()` already used for the structure
   case) is now used at both the `register()` and `claim()` call sites in `_move_in()`.

`HomeSite.radius`'s stale doc comment ("the species' scout_radius, which is the radius
that picked the site") was also corrected to describe the new contract.

### Passing output, post-fix

```
bash scripts/run-tests.sh wide_tier_home_site_radius
  --- wide-tier home site radius (finding I2): 13 passed, 0 failed ---
  wide-tier home site radius (finding I2) OK

bash scripts/run-tests.sh structure_home_site_tiers
  --- structure home site — tier-aware (task 9b): 16 passed, 0 failed ---
```

---

## The two one-line validation guards

* `HabitatTier.validate()` gained `_duplicate_bucket_problems()`: flags two children
  (needs and/or limits) sharing a tag AND the same raw `radius` (including both left at
  the sentinel, which always resolves to the same fallback for whichever species owns the
  tier) — the `count_key(tag, radius)` bucket `CapacityEvaluator.tag_counts()` would
  otherwise double-count. Pinned in `test_habitat_tier_schema.gd` (need+need,
  need+limit-at-sentinel, and a negative control at two genuinely different radii).
* `AnimalDefinition.validate()` gained a duplicate-entry check on `emits_tags`: a
  duplicate tag is never deduped by `CapacityEvaluator.tag_counts()`'s
  `resident_tags` loop, so a site would double-count its own population for that tag.
  Pinned in `test_habitat_validation.gd`.

Both are non-fatal `validate()` warnings, matching every other check in those functions —
no live instance in the shipped roster today.

---

## Full-suite confirmation

```
bash scripts/run-tests.sh
Suites: 128 total, 128 passed, 0 failed
```

(127 pre-existing suites + 1 new: `test_wide_tier_home_site_radius.gd`.)

---

## Self-review

* **Scope discipline.** I deliberately did NOT rewrite `HabitatRecipe.recipe_for()` /
  `describe()` / `easiest_species()` in place, even though the task text offered that as
  one option, because every shipped species now has authored tiers and doing so would
  have silently changed behavior for `test_habitat_recipe.gd` and
  `test_field_guide_reachability.gd` — collateral scope the task explicitly said not to
  take on. The parallel tier-aware functions cost more code but touch nothing else.
* **A real bug in my own first test draft.** The I2 "distant edit re-evaluates" check
  originally used a bare `bool` captured by a lambda connected to `capacity_evaluated` —
  GDScript closures capture value-type locals by snapshot, so the assignment inside the
  lambda never reached the outer variable, and the assertion silently passed regardless of
  whether the fix was present. Caught only by deliberately running the new test against
  pre-fix source (as instructed) and seeing it pass when it should have failed. Fixed by
  capturing a one-element `Array[bool]` instead (a reference type), matching
  `test_group_arrivals.gd`'s existing `arrived.append(...)` idiom. A second, related trap
  in the same test: the initial move-in's `on_resident_arrived()` broadcasts
  `_mark_all_sites_dirty()`, which re-enqueues the deer's own site regardless of distance —
  a leftover pending entry from that broadcast would have let the discriminating assertion
  pass by coincidence even pre-fix. Fixed by draining the world to fully idle
  (`while not sim.is_idle(): sim.tick(0.0)`) before starting the distant-edit phase. Both
  are documented in the test's own comments.
* **The Rabbit → Deer starter change (C1).** Flagged prominently above and under
  Proposals — I judged it correct (it follows directly from fixing the data source, and
  matches `WOOD_COST_WEIGHT`'s own stated intent), but it changes which species a
  brand-new player is steered toward, which is a judgment call worth the human's eyes.
* **`news_report_content.gd`'s remaining flat-field read** is pre-existing and out of
  scope for C1 (it biases which species gets a flavor line, never renders build
  instructions), but it is the same underlying staleness this branch introduced
  everywhere else — flagged for the human as a likely future finding, not fixed here.
* **Gate-only weighting in `easiest_species_by_tier()`** (`maxi(count, 1)`) is a genuine
  judgment call, not a value pulled from spec — flagged under Proposals.
* Constraints honored: `_tile_counts_for()` untouched; `qualifies ≡ capacity ≥ 1` stays one
  function; no lower clamp added anywhere; `HabitatRecipe`'s existing functions stay
  stateless and mutation-free (the new ones are too); every new player-facing string stays
  `[COPY]`-marked (none were added — the tier-aware coach path reuses
  `BEAT_TWO_TEMPLATE` and `SOURCE_PHRASES`/`DESCRIBE_LEAD` verbatim); no assertion was
  deleted anywhere; `.gd.uid` committed for the one new script.

---

## Proposals for the human

* `easiest_species_by_tier()` charges a GATE_ONLY need as 1 tile for ranking purposes
  (`maxi(entry.count, 1)`), not its literal 0 — otherwise an expensive gate building (e.g.
  Human's House) scores as free and can out-rank genuinely free-terrain species. This is a
  scoring judgment call, not a spec value.
* Fixing C1's data source changes the coach's live recommendation from Rabbit to **Deer**
  (tied with Donkey, Deer wins on roster load order) — a direct, correct consequence of
  reading real tier data instead of stale flat fields, but a game-balance/UX outcome worth
  the human's review (see the C1 section above for the full reasoning).
* `NewsReportContent.pick_species()`'s terrain-bias weighting (`news_report_content.gd:82`)
  still reads the same stale `species.habitat_needs` flat field C1 fixed for the coach. It
  never renders build instructions (only biases which species gets a pre-written flavor
  line), so it is out of this task's scope, but the human may want a follow-up task to
  migrate it onto tier data too.
