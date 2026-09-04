# Task 3 report — vocabulary extension, radius band replacement, and new validation rules

## What I implemented

Followed the brief verbatim (transcribed, not redesigned).

1. **`project/scripts/definitions/animal_definition.gd`**
   - Replaced `HABITAT_TAGS` with the extended vocabulary (adds `built`, `people`, `deer`,
     `browse`, `snow`, `barn`, `large_barn`, `large_house`, `stable`, `coop`, `silo`, `mill`;
     retires `quiet`), added `BUILDING_TAGS`, and the `CATEGORY_PERSON` / `CATEGORY_WILD` /
     `CATEGORY_DOMESTICATED` constants.
   - Added `category() -> String` immediately after `effective_tiers()`, implementing the
     ordered precedence test exactly as specified: Person (needs or emits `people`) first,
     then Wild (no building need + at least one limit), then Domesticated (a building tag as
     a `GATE_ONLY` need), else `""`.
   - Replaced the two 8–12 radius-band checks in `validate()` with a single `HabitatNeed.RADIUS_MIN`
     (2) – `HabitatNeed.RADIUS_MAX` (16) band applied to `scout_radius` and `capacity_radius`
     (sentinel exempt).
   - Replaced the flat-`habitat_needs` inert-land check with a tier-aware one that iterates
     `effective_tiers()` and reads only `tier.needs` (positive requirements) — `tier.limits`
     never participates, per subtlety 2 in the task context.
   - Added the tier/limit vocabulary check, `emits_tags` vocabulary check, and the
     category-coherence warning, placed before the existing `known_ids` block as directed.

2. **`project/scripts/definitions/habitat_graph.gd`** (new) — `HabitatGraph.find_cycle()`,
   transcribed verbatim from the brief. Builds a tag→emitter-ids map from `emits_tags`, an
   id→depends-on-ids edge map from `effective_tiers()` needs (explicitly skipping
   `emitter_id != def.id` so self-emission — e.g. deer needing `deer` — is never treated as
   a cycle edge), then runs an iterative-per-root DFS with a stack-membership check to detect
   cross-species cycles.

3. **`project/tests/test_habitat_validation.gd`** (new) — transcribed verbatim from the brief.

## Deviations from the brief

None in code. One observation: the brief's own docstring says "Expected: PASS, 16
assertions"; the suite actually reports 19 `PASS` lines (the radius-band loop over
`def.validate()` problems on a definition with `scout_radius = 14` emits one `check()` per
problem string plus the fixed checks, so the exact count depends on how many other problems
that fixture happens to report — with no `model_scenes`/`fact_text_pool` set it reports
several). This is a difference in the brief's assertion-count estimate, not a defect; all
checks pass. Noted here rather than silently ignored.

I did not touch `AnimalDefinition.BARE_TAGS` (still the pre-existing hardcoded
`["open_grass", "quiet"]`). The brief's inert-land block references `BARE_TAGS` as-is and
does not ask for a derivation change; `project/tests/test_bare_tags_derivation.gd` already
pins the hardcoded-vs-derived gap as explicitly *not* this task's work ("Reconciling them
... is Tier 1 row 6's work"). Confirmed by inspection before editing — did not reintroduce
a *second* hardcoded copy anywhere in my new code; both the tier-aware inert-land check and
nothing else read `BARE_TAGS` from its single existing declaration.

## Test command 1 — new suite

```
bash scripts/run-tests.sh habitat_validation
```

Result: **PASS** — `habitat validation: 19 passed, 0 failed`.

## Test command 2 — full suite

```
bash scripts/run-tests.sh
```

Result: `Suites: 120 total, 115 passed, 5 failed` (both commands run with
`dangerouslyDisableSandbox: true`, sandbox off, per the task's environment note).

### Failing suites and reasons (the blast radius)

All five failures are caused by the **same new rule**: the category-coherence warning
(`category() == ""` → a non-fatal "matches none of person/wild/domesticated" problem).
None are caused by the radius-band replacement (the shipped roster's scout radii, e.g.
fox/rabbit at 8, human at 8, are inside both the old 8–12 band and the new 2–16 band, so
that check alone changed nothing observable in the current suite run).

- **`test_fox_schema`** — `fox.tres`'s flat needs (`forest`, `cover`) carry no building tag
  and no limit under the synthesised legacy tier, so `category()` returns `""`. Two
  assertions that expect `validate()` / `validate(KNOWN_IDS)` to be clean now see the one
  new warning string.
- **`test_rabbit_schema`** — same shape as fox (`open_grass`, `cover`, no limit, no
  building tag): `category()` returns `""`. Same two assertions fail.
- **`test_human_schema`** — human's needs (`house`, `cultivated`) do include a building tag
  (`house`), but the legacy-synthesised need carries `tiles_per_individual = 1`, so it is
  not `GATE_ONLY` and `has_building_gate` stays false; `human.tres` also does not yet
  populate `emits_tags = ["people"]`. So it hits neither Person nor Domesticated and
  `category()` returns `""`. Two assertions fail for the same reason as fox/rabbit.
- **`test_inert_land_invariant`** — one assertion, `BARE_TAG "quiet" is in the shared
  vocabulary`, fails because `quiet` was deliberately retired from `HABITAT_TAGS` while
  remaining (for now) in the still-hardcoded `BARE_TAGS`. This is the vocabulary retirement
  working as intended, not a regression in the invariant itself — the other 39 assertions in
  that suite (including every shipped species' inert-land check) still pass.
- **`test_news_report`** — its `validate()`-is-clean assertions run over a bare default
  `AnimalDefinition()` fixture and over fox/rabbit/human `.tres` with `news_reports`
  populated; all four hit the same `category() == ""` warning as above (none of the
  fixtures used there declare a limit, a building gate, or `emits_tags = ["people"]"`).

**Full list:** `test_fox_schema`, `test_human_schema`, `test_inert_land_invariant`,
`test_news_report`, `test_rabbit_schema` — 5 suites, matching the task's expectation that
this task turns other suites red and Task 9 closes them by re-speccing the roster with
tiers, limits, gates and `emits_tags`.

## Self-review findings

- Verified `HabitatNeed`, `HabitatLimit`, `HabitatTier` (Tasks 1–2, already committed)
  exactly match the interfaces the brief assumes (`RADIUS_MIN`/`RADIUS_MAX` = 2/16,
  `GATE_ONLY` = 0, `is_gate_only()`, `effective_radius()`, `validate()`) — no adjustment
  needed, none made.
- Confirmed the inert-land check reads `tier.needs` only, never `tier.limits` — matches
  subtlety 2 exactly, and the new suite's `_check_inert_land_ignores_limits()` assertion
  passes.
- Confirmed `HabitatGraph.find_cycle()` skips `emitter_id != def.id` so deer→deer is not a
  self-cycle, and the new suite's acyclicity checks (both the shipped-shape graph and a
  synthetic mutual dependency) pass.
- Confirmed category precedence is genuinely ordered (Person checked before Wild/
  Domesticated) via the Pug fixture in `_check_categories()`, which gates on `house*`
  `GATE_ONLY` and would read as Domesticated if Person were not checked first.
- `validate()` remains non-fatal throughout — every new branch only appends to `problems`,
  never raises or mutates state.
- Did not widen `HABITAT_TAGS`, did not re-add `quiet`, did not touch the 2–16 band, and did
  not relax any check to make a currently-red suite pass — confirmed by re-reading the
  final diff before committing.
- Style: all new/changed loop variables are typed (`for tier: HabitatTier in ...`, etc.),
  and every new public member (`category()`, `BUILDING_TAGS`, the category constants,
  `HabitatGraph.find_cycle()`) carries a `##` doc comment.
- Left `project/scripts/definitions/habitat_limit.gd.uid`,
  `project/scripts/definitions/habitat_need.gd.uid`,
  `project/scripts/definitions/habitat_tier.gd.uid`,
  `project/tests/test_animal_tiers.gd.uid`, and
  `project/tests/test_habitat_tier_schema.gd.uid` untouched/unstaged: these are `.uid`
  siblings of files Tasks 1–2 already committed without their generated `.uid` (the repo
  convention tracks `.gd`/`.gd.uid` pairs — see `animal_definition.gd.uid`,
  `terrain_definition.gd.uid`). They appeared as untracked files when Godot's `--import`
  regenerated them during my test runs. Not this task's scope to fix; flagging for the
  human/whoever picks up Task 4+ so they aren't lost.

## Changed files

- `project/scripts/definitions/animal_definition.gd` (modified)
- `project/scripts/definitions/habitat_graph.gd` (new)
- `project/scripts/definitions/habitat_graph.gd.uid` (new)
- `project/tests/test_habitat_validation.gd` (new)
- `project/tests/test_habitat_validation.gd.uid` (new)

## Commit

`9ff6a4d` on `feature/habitat-tiers` — "Extend habitat vocabulary, replace radius band, add
tier validation and cycle checker". No push, no PR, no touch to `main`.
