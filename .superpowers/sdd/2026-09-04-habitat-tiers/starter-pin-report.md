# Starter species pin — fix report (2026-09-04)

## The ruling

Pin the tutorial's starter species to Rabbit, in data, instead of letting the coach
derive it from `HabitatRecipe.easiest_species_by_tier()`'s cost score. Against real
habitat-tier data that score picks Deer (free terrain vs. Rabbit's Wood-costing
`cultivated` need) — correct arithmetic, wrong lesson: Deer is Shy (spends deliberate
time in cover, so a child's first animal would be hard to actually see), and Deer's tier
teaches a constraint (`!built<=1`) before Rabbit's purely additive lesson (paint grass,
paint a field).

## Where the pin lives, and why

`PINNED_STARTER_SPECIES_ID: String = "rabbit"` — a new constant in
`project/scripts/ui/habitat_recipe.gd`, right after `easiest_species_by_tier()`.

Why there and not `onboarding_coach.gd`: `onboarding_coach.gd`'s own header doc comment
states as a design invariant that the coach file "NAMES NO SPECIES AND NO TERRAIN" — beat
2's wording is composed entirely from live `HabitatRecipe` calls so a roster retune never
requires touching that file. Putting a hardcoded species id directly in
`onboarding_coach.gd` would violate that stated invariant. `habitat_recipe.gd` already
owns species selection (`easiest_species()`, `easiest_species_by_tier()`) and is the file
the Field Guide, the `[?]` route and the coach all already read from, so a designer
retuning the starter looks in exactly one place.

Why a plain constant and not a new `.tres`/resource field: `WorldPreset.DEFAULT_PRESET_ID`
is this codebase's existing convention for "the one a designer would look here to
change" — a named-default `const` living beside the code that resolves it (see
`world_preset.gd`'s `DEFAULT_PRESET_ID` and `default_preset()`). `WorldPreset` itself was
explicitly ruled out as a home: its own header states "there is therefore deliberately
no species field... on this resource, and adding one would be a pillar-level change" (world
presets set terrain only, never content gates). A new resource type for a single pinned id
would be over-engineering for one value with one reader; a plain `const` matches the
`WorldPreset` precedent and needs no schema, `.tres`, or `data/` file.

## The fallback

```gdscript
static func starter_species(world: WorldRoot) -> AnimalDefinition:
    if world == null or world.roster == null:
        return null
    var pinned: AnimalDefinition = world.roster.by_id(PINNED_STARTER_SPECIES_ID)
    if pinned != null:
        return pinned
    return easiest_species_by_tier(world)
```

If the pinned id is missing from the live roster (typo, or the species later retired),
`starter_species()` falls back to `easiest_species_by_tier()`'s derived pick rather than
returning `null` — `onboarding_coach.bind_content()` already treats a `null` starter as
"nothing satisfiable" and calls `_finish()`, retiring the coach with no chip shown, so this
fallback is what keeps a stale pinned id from silently blanking the whole onboarding path.
`easiest_species_by_tier()` itself is untouched and not deleted — it is now the fallback,
exactly as required.

`onboarding_coach.gd`'s `bind_content()` now calls `HabitatRecipe.starter_species(world)`
instead of `HabitatRecipe.easiest_species_by_tier(world)` — a one-line change. Its header
comment was updated to explain the pin and point at `PINNED_STARTER_SPECIES_ID`'s doc
comment for the human's full reasoning, while keeping the "names no species" invariant
literally true (the id itself never appears in this file).

## What was NOT touched

- `starter_tier()` / `recipe_for_tier()` / `describe_tier_needs()` are unchanged — still
  the tier-aware path, still reading `effective_tiers()`, never the flat `habitat_needs` /
  `tiles_per_individual` fields. No new raw flat-field read was introduced anywhere.
- `easiest_species_by_tier()` is unchanged and not deleted (it is the fallback).
- `recipe_for()` / `describe()` / `easiest_species()` (the flat-field generation) are
  unchanged — out of scope, as documented in `habitat_recipe.gd`'s "THE COACH'S OWN PATH"
  section.

## The executed Rabbit coach line (real run, full live roster, `test_onboarding_coach`)

```
[COPY] Rabbit are easiest. Likes open grass and farm field. Tap Grass, then tap the ground.
```

Captured verbatim from the `PASS` line for
`_check_bind_content_beat_two_uses_rabbits_real_tier_not_the_stale_flat_fields` in the
actual `bash scripts/run-tests.sh onboarding_coach` run below. This is Rabbit's REAL base
tier (`open_grass/4` + `cultivated/4`), not the stale flat `habitat_needs`
(`["open_grass", "cover"]`) — confirming the previously-landed fix's guarantee is intact
under the pin.

## Tests added / changed

**`project/tests/test_habitat_recipe.gd`** (new):
- `_check_starter_species_prefers_the_pinned_id_over_the_cost_score()` — asserts
  `HabitatRecipe.starter_species(_world).id == "rabbit"` against the full, untouched live
  roster. This is the direct regression pin for the pin itself.
- `_check_starter_species_falls_back_when_the_pinned_id_is_missing()` — swaps in a
  roster containing only Deer (no "rabbit" id present), asserts `starter_species()`
  returns exactly what `easiest_species_by_tier()` derives on that same roster, rather
  than `null` or a crash.

**`project/tests/test_onboarding_coach.gd`** (changed, not deleted):
- `_check_bind_content_at_beat_two_names_the_derived_starter()` now calls
  `HabitatRecipe.starter_species(_world)` (matching what `bind_content()` itself now
  calls) and adds `check_eq(starter.id, "rabbit", ...)` against the full live roster —
  this is the assertion that would have caught the silent switch to Deer: it fails if
  `starter_species()` ever falls through to the derived score unconditionally.
- `_check_bind_content_beat_two_uses_rabbits_real_tier_not_the_stale_flat_fields()` is
  **unchanged** — it already derives its expectations independently, straight from
  `rabbit.tres` and `HabitatRecipe.SOURCE_PHRASES` (a data table), never by comparing one
  `HabitatRecipe` call's output against another. This satisfies the requirement that the
  rendered coach text be checked against Rabbit's real tier needs independently of any
  self-referential `HabitatRecipe`-vs-`HabitatRecipe` comparison.
- No existing assertion was deleted; the two doc comments above the changed function were
  rewritten to explain the new call and the new hardcoded-id assertion (both marked with
  "REWRITTEN AGAIN" and dated, per this codebase's convention for non-silent test edits).

## Test commands and output

`bash scripts/run-tests.sh onboarding_coach` (run with sandbox disabled — headless Godot
segfaults writing `user://logs` under the sandbox):

```
--- onboarding coach: 33 passed, 0 failed ---
onboarding coach OK
Suites: 1 total, 1 passed, 0 failed
```//passed lines include:
  PASS  the coach's starter is pinned to Rabbit against the full, untouched live roster —
        not whatever species the cost score currently favours (Deer, once real tier data
        replaced the retired flat fields — see PINNED_STARTER_SPECIES_ID)
  PASS  beat 2 no longer tells a player to place Rock — Rabbit's STALE flat need
        ('rocky cover'), the literal misinstruction finding C1 reported:
        '[COPY] Rabbit are easiest. Likes open grass and farm field. Tap Grass, then tap
        the ground.'

`bash scripts/run-tests.sh habitat_recipe`:

```
--- habitat recipe: 199 passed, 0 failed ---
habitat recipe OK
Suites: 1 total, 1 passed, 0 failed
```
Includes:
  PASS  a starter species is derivable from the live roster (existing, unaffected)
  (new checks pass silently as part of the 199 — no dedicated printed line beyond the
  `check`/`check_eq` calls themselves, verified by diffing pass count before/after: 195 ->
  199, exactly the 4 new assertions added across the two new functions)

`bash scripts/run-tests.sh field_guide`:

```
--- field guide reachability: 81 passed, 0 failed ---
field guide reachability OK
Suites: 2 total, 2 passed, 0 failed
```
(unaffected by this change — no `starter_species`/`PINNED_STARTER_SPECIES_ID` reference
anywhere in `field_guide.gd` or its test file, confirmed by grep before editing)

Full suite, `bash scripts/run-tests.sh`:

```
Suites: 128 total, 128 passed, 0 failed
```

All three targeted suites and the full suite ran with `--import` before `--script` (the
runner script's own sequencing, unchanged) and with the sandbox disabled for the Bash
calls, per the known `user://logs` segfault under sandboxing.

## Self-review

- **Ground truth honoured, not just the id.** The doc comment on
  `PINNED_STARTER_SPECIES_ID` restates the human's three reasons (Bold vs. Shy visibility,
  constraint-first vs. additive-first lesson, "a derived starter silently changes") so a
  future maintainer who considers repointing the pin has to read past them first.
- **No interaction-pattern change.** This is a data/selection change only; no new UI
  affordance, no new tap pattern.
- **No new player-facing copy.** `BEAT_TWO_TEMPLATE` in `onboarding_coach.gd` is
  unchanged and still `[COPY]`-marked; nothing new was added to it.
- **`.gd.uid` siblings.** No new `.gd` file was created (only existing files edited), so
  there is no new `.uid` sibling to commit.
- **Boundary check.** I did not touch `easiest_species_by_tier()`'s ranking logic, did not
  invent a new interaction pattern, and did not write approved player-facing strings —
  only reused the existing `[COPY]`-marked template verbatim.
- **Residual risk / judgment call for the human:** `starter_species()`'s fallback returns
  whatever `easiest_species_by_tier()` currently favours (Deer, live) if "rabbit" ever goes
  missing from the roster — that fallback pick is not itself pinned to anything Bold. If a
  human wants a *specific* fallback species (rather than "whatever the score currently
  says") that would need a second named constant; left as the derived pick per the task's
  instruction ("Degrade gracefully... Fall back to the existing derived pick").
