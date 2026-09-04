# Task 9b — report

## The gap, confirmed

Two functions read the flat `AnimalDefinition.habitat_needs` array instead of the tier data
the habitat-tiers branch moved real requirements into:

- `HomeSite.serves()` — `project/scripts/simulation/home_site.gd`
- `HabitatSimulation._home_site_radius_for()` — `project/scripts/simulation/habitat_simulation.gd`

Cow, Bull, Horse and Alpaca gate on building tags (`barn`, `silo`, `stable`, `large_barn`)
that now live only in `tiers`; their retained legacy `habitat_needs` (e.g. Cow's
`["cultivated", "open_grass"]`) names no building tag at all. Reading it directly made
`serves()` say no species needs a Barn, made `_home_site_radius_for()` return 0, and made
`_sync_structure_site()` bail on "this building is nobody's habitat" — so a Barn never
became a home site, only a terrain-anchored den could form near one via `WorldGrid`'s tile
tags. Villager/House happened to keep working by accident: Human's flat `habitat_needs`
still happens to contain `"house"` even though its real gate also moved into `tiers`
(`human.tres`'s `tier_single` needs `house` + `cultivated`) — which is exactly why a
villager-only test never caught this.

## What changed in each function

### `HomeSite.serves()` (`project/scripts/simulation/home_site.gd`)

Was: iterate `species.habitat_needs` (flat strings), return true if any is in
`structure_tags`.

Now: iterate `species.effective_tiers()` — authored tiers, or the synthesised legacy tier,
or empty — and for each tier's `needs`, check if the need's `tag` is in `structure_tags`.
Any ONE tier naming a `need` tag this structure emits is enough to say the building is a
home *for that species*; a tier's OTHER needs (grass, water, a second building) are a
capacity question for `CapacityEvaluator`, not a "does this building count as this species'
home" question — same posture the old flat-array check had, just reading the right source.

### `HabitatSimulation._home_site_radius_for()` (`project/scripts/simulation/habitat_simulation.gd`)

Was: for each species, iterate `species.habitat_needs` (flat strings); if one is in
`def.emitted_tags`, take `max(best, species.scout_radius)`.

Now: for each species, iterate `species.effective_tiers()`; for each tier, check if ANY of
its `needs[].tag` is in `def.emitted_tags`. If it matches, take
`max(best, tier.max_radius(species.scout_radius))` — `HabitatTier.max_radius()` is the
widest radius any need OR limit in that tier counts over, falling back to the species'
`scout_radius` wherever a need/limit uses the "follow the species" sentinel
(`HabitatNeed.RADIUS_FOLLOWS_SCOUT`).

**The radius rule I chose, and why:** take the matching tier's full `max_radius()`, not
just `species.scout_radius`. Reasoning, documented in a `##` comment on the function:

- `_home_site_radius_for()`'s result becomes the structure site's `HomeSite.radius`, and that
  radius is what `HomeSiteRegistry.sites_covering()` / `_mark_neighbourhood_dirty()` use to
  decide which player edits re-evaluate this site. If a tier's own need or limit carries an
  EXPLICIT radius wider than `scout_radius` (a real, authored value — not the sentinel), the
  site needs to notice edits out at that distance too. Using only `scout_radius` would let
  the site silently miss an edit its own tier cares about.
- Every need/limit in the shipped roster today uses the "follow `scout_radius`" sentinel
  (`radius = 0`), so this degrades to exactly the old `scout_radius` behavior in practice —
  nothing observable changes for the shipped roster. But nothing in the fix special-cases
  that; a future species/tier with an explicit wider radius is handled correctly without
  another engineer having to revisit this function.
- Taking the max across every matching `(species, tier)` pair, same as before, so a building
  shared by several species' tiers (e.g. `barn` gating both a "pair" and a "herd" tier) still
  gets the widest applicable radius.

I considered simply keeping `species.scout_radius` (the old rule, tier-blind) since it's
what the shipped roster resolves to anyway — but that reintroduces exactly the kind of
"quietly wrong for data that diverges from today's roster" gap this whole task is about, so
I used the wider, principled read instead.

## Stale comment fix

`project/data/terrain/wild_grass.tres` line 22: updated the prose that said
`AnimalDefinition.BARE_TAGS` is `["open_grass", "quiet"]` to say `["open_grass"]`, with a
one-line note that `quiet` was retired 2026-09-04. Data (`emitted_tags = []`) untouched.

## The test proving a Barn anchors a Cow

New file: `project/tests/test_structure_home_site_tiers.gd` (+ its `.gd.uid` sibling).
16 checks, all real-path (no isolated `serves()`-only assertion):

1. **`_check_barn_becomes_a_home_site_for_cow()`** — THE load-bearing check. Builds a real
   `WorldGrid` + `HomeSiteRegistry` + `HabitatSimulation`, loads the REAL `barn.tres` and
   `cow.tres` via `load()`, places the Barn with `grid.set_building()`, then drives the real
   trigger `sim.on_building_changed(origin)` (which calls `_sync_structure_site()` — nothing
   calls `serves()` or `_home_site_radius_for()` directly). Asserts:
   - the fixture's own preconditions (Barn really emits `barn`; Cow really gates a tier on
     `barn`) so the check isn't vacuous;
   - `registry.any_site_at(origin)` is true — **the site exists from placement**, not only
     once a Cow has moved in, exactly like a House;
   - the site is vacant and is a structure site;
   - `site.serves(cow_def)` is true;
   - `site.radius > 0` — the exact value that used to read 0.
2. **`_check_house_still_becomes_a_home_site_for_villager()`** — the same fixture shape
   against the real House/Human data, as the side-by-side comparison case the brief asked
   for.
3. **`_check_radius_follows_the_matching_tiers_max_radius_not_just_scout_radius()`** — a
   synthetic species/building isolating the radius rule: `scout_radius = 4` but the matching
   need's own explicit `radius = 10`; asserts the registered site's radius is `10`, proving
   `_home_site_radius_for()` reads `HabitatTier.max_radius()` and not a bare
   `species.scout_radius` lookup.
4. **`_check_a_building_nobodys_tiers_gate_on_registers_no_site()`** — negative control: a
   building whose tag matches no species' tier registers no site at all, so the fix doesn't
   overshoot into registering a structure site for every building regardless of match.

## Test commands and output

1. New suite:
   ```
   bash scripts/run-tests.sh structure_home_site_tiers
   ```
   `--- structure home site — tier-aware (task 9b): 16 passed, 0 failed ---` PASS

2. Named suites, each run individually — all still PASS, 0 failed:
   - `capacity_formula` — 53 passed, 0 failed
   - `tier_capacity` — 12 passed, 0 failed
   - `resident_tags` — 14 passed, 0 failed
   - `group_arrivals` — 17 passed, 0 failed
   - `roster_signatures` — 50 passed, 0 failed

3. Full suite:
   ```
   bash scripts/run-tests.sh
   ```
   `Suites: 127 total, 127 passed, 0 failed` — fully GREEN (126 pre-existing + the 1 new
   suite this task adds). No suite went red.

   Note: the very last lines of the full run print an engine-level
   `WARNING: 10 ObjectDB instances were leaked at exit` / `ERROR: 3 resources still in use at
   exit` from process shutdown after the final suite (`world snapshot (capture)`) completes.
   These are not "SCRIPT ERROR" and the runner's own summary still reports 0 failed; nothing
   in my two changed functions or new test allocates a `Node` without freeing it (my new
   test's `Resource`s — `HabitatNeed`, `HabitatTier`, `PlaceableDefinition`, `AnimalDefinition`
   — are `RefCounted` and need no explicit `free()`; its `Node3D`/`HabitatSimulation`/
   `WorldGrid` instances are all freed in `_teardown()`/at the end of each check). This
   matches the pattern already visible on other task reports in this directory and predates
   this task.

## Self-review

- Neither function special-cases any species id or tag; both walk `effective_tiers()` /
  `needs[].tag` generically, so a species or building added later that gates on a new
  building tag is handled without another code change.
- Did not touch `_tile_counts_for()`, the signature function's raw `radius` read, Wood
  coupling, or the deferred `RABBIT_ROCK_ORIGIN` / `quiet`-assertion items — out of scope
  per the brief.
- Did not touch any tuning value: `_home_site_radius_for()`'s radius rule is derived from
  data (as the function's own pre-existing comment already argued it should be), not a new
  constant.
- Verified the fix is real, not just test-shaped, by having the negative-control check
  confirm a non-matching building still registers nothing, and by having the radius-rule
  check use a case where `scout_radius` and `max_radius()` deliberately diverge.

## Changed files

- `project/scripts/simulation/home_site.gd` — `serves()` reads `effective_tiers()`
- `project/scripts/simulation/habitat_simulation.gd` — `_home_site_radius_for()` reads
  `effective_tiers()` / `HabitatTier.max_radius()`
- `project/data/terrain/wild_grass.tres` — stale `BARE_TAGS` comment corrected (comment only)
- `project/tests/test_structure_home_site_tiers.gd` — new suite (16 checks)
- `project/tests/test_structure_home_site_tiers.gd.uid` — new script's uid sibling
