# `cover` habitat tag retirement — report

Branch: `fix/improve-evals`. Scope: code, data, tests only (no `game-design/`, `decisions.md`,
or `docs/` touched — the human is editing those in parallel).

## 1. Files changed and why

### Production code
- `project/scripts/definitions/animal_definition.gd` — removed `"cover"` from
  `HABITAT_TAGS`. Extended the doc comment above the const (which already explained
  `quiet`'s 2026-09-04 retirement) with the same reasoning for `cover`: a source (Rock)
  with no remaining consumer, the same shape `quiet` had.

### Data (`.tres`)
- `project/data/terrain/rock.tres` — `emitted_tags` changed from `["cover", "rocks"]` to
  `["rocks"]`. Header comment rewritten: Rock's job is now `rocks` alone, consumed by
  Donkey, Alpaca, Shiba Inu and Stag (verified below); the original `cover`+`rocks`
  decision (`D-25`) is preserved as history, not asserted as current.
- `project/data/animals/fox.tres` — legacy `habitat_needs` `["forest", "cover"]` →
  `["forest"]`. Added a header note: this legacy flat field is retained only so a rollback
  to it is a one-line edit, but with `cover` gone the rollback is no longer faithful — it
  now falls back to a single tag, below the design's own "at least two tags each" rule.
- `project/data/animals/rabbit.tres` — legacy `habitat_needs` `["open_grass", "cover"]` →
  `["open_grass"]`. Same rollback-fidelity note added.
- `project/data/animals/stag.tres` — legacy `habitat_needs`
  `["forest", "cover", "rocks"]` → `["forest", "rocks"]`. Same note added: still two tags
  for Stag specifically, but the rollback no longer reproduces the original three-tag
  "forest + cover + rocks, one tag harder than Fox" framing described earlier in the same
  file's header.

These three `habitat_needs` fields are inert in gameplay (`effective_tiers()` prefers the
real `tiers` array all three species carry), but `validate()` checks them against the
shared vocabulary regardless, so leaving `cover` there would have produced a false
"not in the shared vocabulary" report on all three.

## 2. Test expectations changed (old → new, one reason each)

Two different situations came up, per the task's own categories:

**A. Direct pins on the deliberate change** (Rock's emission / a legacy field's literal
value) — the expectation simply had to follow the new data:

| File | Check | Old | New |
|---|---|---|---|
| `test_terrain_schema.gd` | `EXPECTED_TAGS["rock"]` | `["cover", "rocks"]` | `["rocks"]` |
| `test_fox_schema.gd` | `fox.habitat_needs` | `["forest", "cover"]` | `["forest"]` |
| `test_rabbit_schema.gd` | `rabbit.habitat_needs` | `["open_grass", "cover"]` | `["open_grass"]` |
| `test_causality_end_to_end.gd` | `rabbit.habitat_needs` (legacy-field pin, incidental to the causality assertion) | `["open_grass", "cover"]` | `["open_grass"]` |
| `test_onboarding_coach.gd` | fixture-premise pin (`rabbit.tres`'s stale flat field) | `["open_grass", "cover"]` | `["open_grass"]` |
| `test_habitat_recipe.gd` | `_check_rock_is_the_source_of_both_its_tags` → renamed `_check_rock_is_the_source_of_rocks` | both `cover` and `rocks` resolve to Rock | only `rocks` resolves to Rock; added assertions that `cover` now resolves to **no** source, and that `rocks` now has **2** sources (Rock + Scrub) |
| `test_habitat_recipe.gd` | `_check_stag_dedupes_to_two_chips_at_single_count` → renamed `_check_stag_no_longer_dedupes_after_cover_retirement` | Stag's 3 legacy needs collapse to 2 chips (Rock served 2 tags); the Rock chip carries 2 tags | Stag's 2 legacy needs (`forest`, `rocks`) resolve to 2 DISTINCT chips; each chip carries exactly 1 tag (see coverage note below) |
| `test_habitat_recipe.gd` | `_check_fox_reads_forest_and_rock` → renamed `_check_fox_reads_forest` | resolves to `["forest", "rock"]` | resolves to `["forest"]` |
| `test_habitat_recipe.gd` | suite header + `_check_description_never_repeats_a_shared_source` comment | described Rock as serving 2 of Stag's needs | comment updated; assertion itself (`Rock phrase appears once`) still holds and was not changed |

**Judgment call, flagged for the human**: `_check_stag_dedupes_to_two_chips_at_single_count`
was this suite's OWN stated reason for existing (its header: "Rock emits BOTH `cover` and
`rocks`, so Stag's three needs must collapse to TWO chips"). With `cover` retired, no real
species+terrain combination in the shipped data can any longer exercise
"one terrain tile satisfies two of a species' tags at once" — `rocks` now has two real
sources (Rock, Scrub), so a synthetic species needing both `browse`+`rocks` does NOT
collapse either (the cheapest-tie-break always resolves `rocks` to Rock, `browse` to
Scrub — two different buttons). I did not invent a synthetic terrain fixture to keep
exercising that exact mechanism, since that felt like scope creep beyond "retire cover and
fix what breaks" for a pure-cleanup task; I instead pinned the new, honest shape (no dedup)
and documented the gap in both the suite header and the renamed check. The general
button-dedup mechanism (two tags, one PALETTE BUTTON) is still exercised at the
building-tag level by this same suite's `_check_grouped_button_names_the_tag_carrying_member`
and `_check_grouped_building_tags_name_the_carrying_member`. **This is a real, if minor,
test-coverage loss** — flagging it rather than silently accepting it.

**B. Fixture re-points** (a test used `cover` purely as an arbitrary tag paired with real
`rock`-terrain painting, to exercise something unrelated to `cover` itself — divisor/radius
arithmetic, exclusivity, displacement triggers, etc.). Re-pointed every one to `rocks` (the
tag Rock still emits), leaving the terrain painted as literal `"rock"` throughout, so the
mechanism under test is byte-for-byte unchanged:

| File | What changed |
|---|---|
| `test_capacity_formula.gd` | 7 synthetic species' `habitat_needs` `["cover"]` → `["rocks"]`; all `.get("cover", ...)` → `.get("rocks", ...)`; prose ("N cover tiles") → ("N rock tiles") |
| `test_tile_exclusivity.gd` | 3 synthetic species re-pointed the same way; helper `_cover_count()` renamed `_rocks_count()` |
| `test_event_driven_simulation.gd` | shared `_fixture()`'s synthetic species re-pointed (feeds 2 checks) |
| `test_settlement_window.gd` | shared `_fixture()`'s synthetic species re-pointed (feeds nearly every check in the suite); helper `_lay_cover()` renamed `_lay_rocks()` |
| `test_gentle_displacement.gd` | shared fixtures' synthetic species re-pointed, INCLUDING a synthetic `PlaceableDefinition` (`"shelter"`) that emits `cover` to combine with terrain-emitted `cover` in the mode-agnosticism (build/terraform/removal) check — now emits `rocks` to match; helper `_lay_cover()` renamed `_lay_rocks()` |
| `test_group_arrivals.gd` | shared fixture's synthetic species re-pointed |
| `test_villager_variant_variety.gd` | shared fixture's synthetic species re-pointed |
| `probe_overcap.gd` | same re-point (this file is a standalone probe, not matched by `run-tests.sh`'s `test_*.gd` glob, so it isn't part of the 128-suite gate — fixed anyway so it isn't silently broken if ever run by hand) |
| `test_news_report.gd` | fixture `habitat_needs` `["cover", "people"]` → `["open_grass", "people"]` — this one DID fail (`validate()` now reports `cover` as an unknown-vocabulary tag), since the check asserts `validate().is_empty()` |
| `test_placeable_schema.gd` | synthetic `AnimalDefinition.habitat_needs` `["forest", "cover"]` → `["forest", "rocks"]` — did not actually fail (the check only greps for a `"fact_text"` substring in `validate()`'s output), re-pointed anyway to avoid a stale/confusing fixture |
| `test_inert_land_invariant.gd` | two "legitimate species pass" fixtures re-pointed from `["open_grass", "cover"]` / `["forest", "cover"]` to real post-retirement pairs: `["open_grass", "cultivated"]` (Rabbit-style) and `["forest", "rocks"]` (Stag-style) — did not fail (this invariant checks only `BARE_TAGS` subset membership, not vocabulary), re-pointed so the fixtures no longer cite a tag no species names any more |

No assertion was deleted anywhere; the `_check_rock_is_the_source_of_rocks` rewrite and the
`_check_stag_no_longer_dedupes_after_cover_retirement` rewrite each end up with an equal or
greater number of `check()`/`check_eq()` calls than the code they replaced.

**Left unchanged, verified safe** (incidental prose or fixtures that never call
`validate()` and never depend on real Rock emission, so removing `cover` from the
vocabulary cannot affect them): `test_avoids_distance_keeping.gd` (a synthetic species
needs `["cover"]` but no terrain in that file ever paints `rock`, and the suite's
assertions concern wander/avoids-bias mechanics, not settling), `test_bare_tags_derivation.gd`,
`test_animal_tiers.gd`, `test_tier_capacity.gd`, `test_tile_tag_mask.gd`, and
`capacity_evaluator.gd`'s own doc comment (which describes `test_capacity_formula.gd`'s old
`.get("cover", ...)` alias behaviour generically, not tied to the vocabulary).

## 3. Evidence for the "pure cleanup, no gameplay change" claim

- `grep -rn habitat_needs project/data/animals/*.tres` (post-change): no shipped species
  names `"cover"` anywhere; `fox`, `rabbit`, `stag` are the only three files that ever did,
  and all three are now edited.
- `grep -rln '"cover"' project/data/ project/scripts/`: the only remaining hits are
  historical prose comments (`rock.tres`'s "Originally emitted_tags..." note, and the three
  species' "legacy rollback no longer faithful" notes) plus `capacity_evaluator.gd`'s
  incidental doc comment about `test_capacity_formula.gd`'s alias key — none is a live field.
- `rocks` consumers, confirmed via `grep -rn 'tag = "rocks"' project/data/animals/*.tres`
  plus Stag's flat field: **Donkey, Alpaca, Shiba Inu, Stag** all still name `rocks` — Rock
  keeps a real reason to exist.
- Full suite is green (below) with the SAME set of gameplay-facing systems exercised as
  before (capacity formula, tile exclusivity, displacement, settlement window, group
  arrivals, villager variant variety, event-driven simulation) — every one of those suites
  now passes against `rocks` instead of `cover` with byte-identical terrain paints, which is
  the strongest evidence available that no arithmetic moved, only a tag's name did.

## 4. Full-suite output

```
==> Importing project (registers class_name, rebuilds import cache)
==> Running 128 suite(s)

  PASS  test_alpaca_animations
  PASS  test_alpaca_fidelity
  PASS  test_animal_pick_variant
  PASS  test_animal_tiers
  PASS  test_animal_variant_spawn
  PASS  test_attribution
  PASS  test_autosave_triggers
  PASS  test_avoids_distance_keeping
  PASS  test_bare_tags_derivation
  PASS  test_building_footprint_alignment
  PASS  test_building_tags
  PASS  test_bull_animations
  PASS  test_bull_fidelity
  PASS  test_camera_menu_toggle
  PASS  test_camera_rails
  PASS  test_capacity_formula
  PASS  test_causality_end_to_end
  PASS  test_common_tree_1_import
  PASS  test_common_tree_2_import
  PASS  test_cow_animations
  PASS  test_cow_fidelity
  PASS  test_credits_screen
  PASS  test_deer_animations
  PASS  test_deer_fidelity
  PASS  test_den_import
  PASS  test_displacement_notice
  PASS  test_displacement_notice_speaking
  PASS  test_donkey_animations
  PASS  test_donkey_fidelity
  PASS  test_economy_rules
  PASS  test_event_driven_simulation
  PASS  test_fact_card
  PASS  test_farm_buildings_schema
  PASS  test_fidelity_probe
  PASS  test_field_guide
  PASS  test_field_guide_reachability
  PASS  test_font_glyph_coverage
  PASS  test_fox_animations
  PASS  test_fox_fidelity
  PASS  test_fox_schema
  PASS  test_fox_spawn
  PASS  test_gentle_displacement
  PASS  test_grass_common_short_import
  PASS  test_grass_common_tall_import
  PASS  test_group_arrivals
  PASS  test_habitat_recipe
  PASS  test_habitat_tier_schema
  PASS  test_habitat_validation
  PASS  test_harvestable_schema
  PASS  test_home_prop
  PASS  test_horse_animations
  PASS  test_horse_fidelity
  PASS  test_house_import
  PASS  test_house_secondage_variants_import
  PASS  test_house_variants_import
  PASS  test_hud_hotbar
  PASS  test_human_adventurer_import
  PASS  test_human_animation_loops
  PASS  test_human_hoodie_import
  PASS  test_human_man_import
  PASS  test_human_pack_variants_import
  PASS  test_human_punk_import
  PASS  test_human_schema
  PASS  test_human_variant_save_stability
  PASS  test_human_woman_import
  PASS  test_husky_animations
  PASS  test_husky_fidelity
  PASS  test_inert_land_invariant
  PASS  test_iso_camera_framing
  PASS  test_menu_window
  PASS  test_mist_boundary
  PASS  test_mist_reveal
  PASS  test_mode_tap_model
  PASS  test_navigation_rebuild_coalescing
  PASS  test_neighborhood_preview
  PASS  test_new_game_screen
  PASS  test_news_report
  PASS  test_new_terrains
  PASS  test_occlusion_fader
  PASS  test_occlusion_fader_scaling
  PASS  test_onboarding_coach
  PASS  test_ownership_index_integrity
  PASS  test_pig_fidelity
  PASS  test_pig_import
  PASS  test_pine_tree_import
  PASS  test_placeable_schema
  PASS  test_placeholder_scenes
  PASS  test_pug_fidelity
  PASS  test_pug_import
  PASS  test_rabbit_animations
  PASS  test_rabbit_schema
  PASS  test_rabbit_spawn
  PASS  test_registry_scaling
  PASS  test_removal_refund
  PASS  test_resident_lookup
  PASS  test_resident_navigation
  PASS  test_resident_tags
  PASS  test_resident_wander
  PASS  test_restore_seams
  PASS  test_roamer_budget
  PASS  test_rock_1_import
  PASS  test_roster_signatures
  PASS  test_saved_worlds_screen
  PASS  test_save_round_trip
  PASS  test_save_store
  PASS  test_save_thumbnail
  PASS  test_settings_screen
  PASS  test_settlement_window
  PASS  test_sheep_fidelity
  PASS  test_sheep_import
  PASS  test_shiba_inu_animations
  PASS  test_shiba_inu_fidelity
  PASS  test_stag_animations
  PASS  test_structure_home_site_tiers
  PASS  test_style_defaults
  PASS  test_tap_router_cursor
  PASS  test_terrain_lod
  PASS  test_terrain_schema
  PASS  test_terrain_view_no_blocking
  PASS  test_tier_capacity
  PASS  test_tile_exclusivity
  PASS  test_tile_tag_mask
  PASS  test_title_screen
  PASS  test_villager_variant_variety
  PASS  test_wide_tier_home_site_radius
  PASS  test_world_navigation
  PASS  test_world_preset
  PASS  test_world_snapshot

================================================================
Suites: 128 total, 128 passed, 0 failed
================================================================
```

Note on the count: the task brief cited a starting baseline of 129/129. This run shows 128
suite files (`find project/tests -maxdepth 1 -name 'test_*.gd'` also returns 128). The repo
is shared with at least one other concurrently-running agent this session (see §6) whose
uncommitted work includes deleting `test_notification_feed.gd` — that is the most likely
source of the 129→128 discrepancy, not anything in this dispatch. It is not my file to
touch or restore.

Individually-named runs during the fix, before the full run above, also confirmed:
`roster_signatures` (50/50), `habitat_validation` (21/21), `new_terrains` (26/26),
`capacity_formula` (53/53, after the fix), `tier_capacity` (12/12), and each touched suite
green on its own.

## 5. Self-review

- Verified the human's "no shipped species needs `cover` any more" claim directly against
  the roster data (§3) rather than assuming it from the task brief.
  `rocks`-consumer count matches (Donkey, Alpaca, Shiba Inu, Stag).
- Distinguished, file by file, between "cover pinned as a vocabulary/emission fact" (fix
  the expectation) and "cover used as an arbitrary fixture tag riding real Rock terrain"
  (re-point to `rocks`, keep the terrain paint identical) — traced every failure back to
  one of those two causes before touching it; none required a change I couldn't explain.
  No test failed for a reason I couldn't trace to the deliberate change.
- The one place I made a judgment call beyond a mechanical fix
  (`test_habitat_recipe.gd`'s Stag/Rock dedup check) is flagged explicitly above rather
  than silently resolved, per the task's own instruction to stop-and-report rather than
  guess on anything outside pure mechanical fixing. I chose to document the coverage gap
  rather than build a new synthetic-terrain fixture to preserve it, since that felt like it
  would exceed "retire cover and fix what breaks" — flagging for the human to decide if a
  replacement fixture is worth adding.
- Did not touch `game-design/`, `decisions.md`, or `docs/`.
- Reverted `project/scripts/build_info.gd`'s regenerated `BUILD_TIMESTAMP` before writing
  this report, per instructions.
- This working tree has substantial unrelated, uncommitted changes from what appears to be
  a concurrently-running agent (UI/notification-feed work: `tap_router.gd`, `coach_chip.gd`,
  `field_guide.gd`, `game_ui.gd`, several `test_*` files, and deleted
  `NotificationFeed`/`notification_feed_poc` files), plus the human's own in-progress edits
  to `game-design/spec.md` and `game-design/tier1-status.md`. None of these are mine; I did
  not stage or commit them, and the commit for this task adds only the 22 files listed in
  §1/§2 above by name.
