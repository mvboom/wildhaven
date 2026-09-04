# Task 8 report — The three new terrains

## Summary

Added `meadow`, `scrub`, and `snowfield` as new `TerrainDefinition` entries, each backed
by real (already-cleared) art, wired as a single `model_scenes` variant. `wild_grass.tres`
was **not touched**; `TerrainDefinition.derive_bare_tags()` still returns empty
(`test_new_terrains.gd` and `test_bare_tags_derivation.gd` both assert this directly). No
placement/adjacency restriction was added anywhere for Snowfield, per the human's OQ-E
ruling.

One real, player-visible regression surfaced and was deliberately **not** papered over —
see "A real defect, not a stale pin" below.

## The three terrains as committed

| id | `emitted_tags` | `cost` | `model_scenes` |
|---|---|---|---|
| `meadow` | `["open_grass", "flowers"]` | 0 | `Meadow.tscn` (1 variant) |
| `scrub` | `["browse", "rocks"]` | 0 | `Scrub.tscn` (1 variant) |
| `snowfield` | `["snow"]` | 0 | `Snowfield.tscn` (1 variant) |

`.tres` files: `project/data/terrain/meadow.tres`, `scrub.tres`, `snowfield.tres` — all
modeled field-for-field on `grass.tres` (`id`, `display_name`, `emitted_tags`, `cost`,
`model_scenes`, `harvestable = null`), each with a header comment stating the values are
a PROPOSAL awaiting human sign-off (same convention as `barn.tres`).

## Source assets imported

All from the two already-cleared, already-attributed packs named in the brief — no new
sourcing, no new pack audit.

**Ultimate Nature Pack** (Quaternius, CC0 1.0 Universal) — Snowfield:
- `BirchTree_Snow_3.fbx` → `project/assets/terrain/birch_tree_snow/BirchTree_Snow_3.fbx`
- `Bush_Snow_1.fbx` → `project/assets/terrain/bush_snow/Bush_Snow_1.fbx`

**Stylized Nature MegaKit (Standard/free)** (Quaternius, CC0 1.0 Universal) — Meadow/Scrub:
- `Flower_3_Group.gltf` (+`.bin`, `Leaves.png`, `Flowers.png`) → `project/assets/terrain/flower_3_group/`
- `Flower_4_Group.gltf` (+`.bin`, `Leaves.png`, `Flowers.png`) → `project/assets/terrain/flower_4_group/`
- `Bush_Common_Flowers.gltf` (+`.bin`, `Leaves_NormalTree_C.png`, `Flowers.png`) → `project/assets/terrain/bush_common_flowers/`
- `Fern_1.gltf` (+`.bin`, `Leaves.png`) → `project/assets/terrain/fern_1/`
- `Grass_Wispy_Short.gltf` (+`.bin`, `Grass.png`) → `project/assets/terrain/grass_wispy_short/`

**Reused, no new download:** `Rock_1.fbx` (already at `project/assets/terrain/rock_1/`,
already in `quaternius_ultimate_nature_pack.tres`) — referenced directly by uid into
`Scrub.tscn`, same "reuse the raw piece, not the sibling terrain's full wrapper"
convention `RockCluster1.tscn` already established.

All raw meshes were measured for real (post-import) AABB via a one-off headless
`SceneTree` probe (same procedure prior look-passes in this repo used — see e.g.
`WaterLilypad1.tscn`'s header), not guessed. Scale targets matched this codebase's
established conventions (canopy trees ~2.5 tile-units, ground-level shrubs ~0.6
tile-units, grass ~0.10-0.15, per each composed scene's own header comment). All scale
choices are first-pass proposals flagged for human sign-off — no GDD number exists for
any of them, same posture as every prior prop-scale call in this repo.

Composed wrapper scenes (the terrain's actual `model_scenes` entries):
- `project/assets/terrain/meadow/Meadow.tscn` — grass-green slab + 2 floor patches + 4
  scattered flower-clump instances (2x Flower_3_Group, 2x Flower_4_Group).
- `project/assets/terrain/scrub/Scrub.tscn` — dry olive/tan slab + 1 Rock_1 + 1
  Bush_Common_Flowers + 1 Fern_1 + 2 Grass_Wispy_Short instances.
- `project/assets/terrain/snowfield/Snowfield.tscn` — pale snow-white slab + 2 drift-tint
  floor patches + 1 BirchTree_Snow_3 + 1 Bush_Snow_1.

Each ships a single `model_scenes` variant, matching how Grass/Rock/Wild grass all
started before their own later multi-variant look-passes — a variety pass is explicitly
out of scope for this task.

## Attribution entries touched

- `project/attribution/sources/quaternius_ultimate_nature_pack.tres` — `assets_used`
  extended with `BirchTree_Snow_3`, `Bush_Snow_1`; a "Seventh use" note added.
- `project/attribution/sources/quaternius_stylized_nature_megakit.tres` — `assets_used`
  extended with `Flower_3_Group`, `Flower_4_Group`, `Bush_Common_Flowers`, `Fern_1`,
  `Grass_Wispy_Short`; a "Second use" note added.
- `project/CREDITS.md` regenerated (`godot --headless --path project --script
  res://attribution/generate_credits.gd` — exit 0, "13 source(s), 1 with binding
  obligations"). `test_attribution.gd`: 50/50 PASS, no hardcoded source-count assertion
  needed an edit (this extends 2 existing entries, adds no new source file).

## Expectation edits — every one, old → new, file, reason

All 4 files below hit the exact "stale pinned literal" shape the task pre-authorized
(`expected N, got M`), all traceable directly to the 3 new terrains this task adds. Per
the rules: assertion counts only went up, no assertion was deleted, and no rule was
weakened.

1. **`project/tests/test_terrain_schema.gd`** — `TERRAIN_IDS` (a fixed literal the header
   explicitly says drives the suite's assertion count) grew from the 6 v1 ids to all 9
   (added `meadow`, `scrub`, `snowfield`, alphabetical-within-list per the file's own
   filename-order convention). `EXPECTED_TAGS`, `EXPECTED_COST`,
   `EXPECTED_BLOCKS_MOVEMENT`, `EXPECTED_HARVESTABLE`, `EXPECTED_DISPLAY_NAMES` all grew
   3 new entries each (all `false`/`0`/natural-terrain values, matching the new `.tres`
   files). The final "`load_all()` finds exactly N terrain ids" assertion's expected
   count and message: 6 → 9. Suite assertion count 84 → 127.
2. **`project/tests/test_bare_tags_derivation.gd`** — `EXPECTED_TERRAIN_COUNT`: 6 → 9.
   Reason: `TerrainDefinition.load_all()` now legitimately finds 9 `.tres` files on disk;
   none of the 3 new ones is `wild_grass`, so the derivation's actual output
   (`derive_bare_tags(load_all())` still empty) is unaffected — only the raw disk count
   the suite separately asserts needed updating.
3. **`project/tests/test_economy_rules.gd`** — `EXPECTED_FREE_TERRAINS`:
   `["forest", "grass", "rock", "water", "wild_grass"]` →
   `["forest", "grass", "meadow", "rock", "scrub", "snowfield", "water", "wild_grass"]`.
   Reason: all 3 new terrains are natural terrain, `cost = 0`, so they belong in the
   "every natural terrain is free" pricing-rule check exactly like every other
   free terrain already listed. `cultivated_field` (cost 2) correctly stays excluded, as
   before.
4. **`project/tests/test_hud_hotbar.gd`** — `_check_palette_row_totals_8_buttons_not_15()`:
   expected button count 8 → 11 (9 terrain + House + Farm Building group), expected
   `PaletteRow` child count 10 → 13 (Info + 11 catalog buttons + Erase). Reason: the
   Terraform palette lists every loaded `TerrainDefinition`, so 3 new terrains are 3 new
   real buttons — this is exactly the "new terrains appearing in the Terraform palette"
   consequence the task brief told me to expect and flag. **The other 4 failing
   assertions in this same suite were NOT edited — see next section.**

## A real defect, not a stale pin (flagged, not fixed)

`test_hud_hotbar.gd`'s `_check_palette_row_never_overlaps_the_corner_clusters()` — a
"REGRESSION GUARD (2026-09-03)" suite written specifically to catch the palette row
visually overlapping the Help button or the Rotate/Erase corner cluster — now **genuinely
fails**, with 4 assertions:

- "the palette row does not overlap the Help button"
- "THE FIXED DEFECT: the palette row does not run under the Rotate buttons — Erase is the
  last button in the row and it was completely covered"
- "...and its right edge clears the Rotate cluster"
- "the row fits the band between the corner clusters"

Root cause: `GameHud._fit_palette_row()` shrinks button size/separation down to a floor
before giving up and reporting overflow (`game_hud.gd:485-492`). At 8 buttons the row fit
the ~776px band; at 11 buttons (9 terrain + House + Farm Building, after this task) it
needs ~1008px and does not fit — `push_warning` fires
(`"GameHud: the palette row needs 1008px (13 buttons at 72px, 6px apart) but the band...
is only 776px. It will overlap a corner cluster."`, visible in `test_terrain_view_no_
blocking`'s output too) and the row genuinely overlaps the Rotate/Erase cluster.

This is **not** a stale pin — it is real, measured, laid-out-rect behavior that changed
because 3 new real buttons landed in the palette, exactly the class of failure the brief's
rule 2 says must not be weakened to fit the data. I left these 4 assertions untouched and
failing rather than loosen or delete them. This is squarely out of tech-art's lane (HUD
layout/UI code, not asset import) to fix.

**Numeric pins in the same suite (button/child count) WERE updated** — see item 4 above —
because those are a straightforward function of catalog size, same shape as every other
stale-pin fix in this report, and updating them does not touch the overlap logic at all.

## Values needing human sign-off

Recorded in each `.tres`'s and `.tscn`'s own header comment, summarized here:

- **Meadow:** flower-clump scale (0.146 Flower_3 / 0.1206 Flower_4, target ~0.30
  tile-units height) and the grass-plus-flower composition/slab tint.
- **Scrub:** every prop scale (rock 0.25, bush 0.3793, fern 0.4165, wispy grass 0.14) and
  the dry olive/tan slab tint (`Color(0.58, 0.52, 0.34, 1)`, deliberately distinct from
  Grass/Meadow's green and Forest's dark green).
- **Snowfield:** canopy-tree scale (0.602, matched to the established 2.5 tile-unit
  target) and bush scale (0.4672, matched to Bush.tscn's established 0.6 tile-unit
  target), and the pale snow-white slab tint.
- All 3: single-variant only — a multi-variant look-pass (more flower/scrub/snow picks)
  is explicitly out of scope for this task.
- **The HUD palette-row overflow** (see above) — not a look choice, a genuine
  layout defect needing a human/HUD-owner decision: widen the band, reduce top-level
  catalog buttons (e.g. group the 3 grazing/cold terrains under a submenu the way Farm
  Building already groups its members), or another mitigation. Not attempted here.

## Test commands and output

1. `bash scripts/run-tests.sh new_terrains` — **PASS**, 26/26 assertions (all 3 terrains'
   identity/tags/cost/model/validate() checks, plus the inert-land invariant check).
2. `bash scripts/run-tests.sh terrain` — **PASS**, all 4 suites (`test_terrain_lod`,
   `test_terrain_schema` 127/127, `test_terrain_view_no_blocking`, and the new-terrains
   suite runs separately under its own filter).
3. `bash scripts/run-tests.sh` (full suite, `-q`) — **119/125 suites passed.** Final red
   list:
   ```
   test_fox_schema
   test_hud_hotbar          <- NEW, real defect, see above (not one of the 5 pre-existing)
   test_human_schema
   test_inert_land_invariant
   test_news_report
   test_rabbit_schema
   ```
   The other 5 are exactly the pre-existing red list this task was told to expect
   (Task 9's responsibility). `test_hud_hotbar` is the one addition, and it is a genuine
   consequence of this task's data change, not a bug in the test file.
4. `bash scripts/run-tests.sh attribution` — **PASS**, 50/50.

All Godot invocations run with `dangerouslyDisableSandbox: true` (segfaults writing
`user://logs`/editor settings otherwise, per this repo's known sandbox gotcha);
`--import` was run before every `--script`/test invocation.

## Self-review findings

- Confirmed `TerrainDefinition.derive_bare_tags()`'s real signature
  (`derive_bare_tags(defs: Array) -> PackedStringArray`, not a bare no-arg call) via
  `grep` before writing the test, and corrected `test_new_terrains.gd` from the brief's
  literal snippet accordingly (`TerrainDefinition.derive_bare_tags(TerrainDefinition.
  load_all())`), matching the pattern `test_bare_tags_derivation.gd` and
  `test_event_driven_simulation.gd` already use.
- Verified `wild_grass.tres` byte-for-byte untouched (`git status` shows no modification
  to it) and that both `test_new_terrains.gd`'s own inert-land check and
  `test_bare_tags_derivation.gd`'s full suite pass.
- Verified no placement/adjacency/climate-gating code or data was added anywhere for
  Snowfield — grepped the new `.tres`/`.tscn` files and `terrain_definition.gd` for any
  neighbor/adjacency logic; none exists, none added.
- Ran `test_attribution.gd` and regenerated `CREDITS.md` in the same task, per the
  pipeline's step 6 gate.
- Did not touch `game-design/art.md` — no existing "Pending Tasks for Tech Art" entry
  named these 3 terrains (this task originates from task-8-brief.md, not a pre-existing
  art.md backlog item), and per the doc map, current per-item state lives in
  content-pipeline-status.md, not art.md; editing art.md was judged out of scope.
- Ran no git commands, per the report format's own instruction — changed files are
  listed below and in `git status` for the orchestrating agent to commit.

## Changed files

**New:**
- `project/data/terrain/meadow.tres`, `scrub.tres`, `snowfield.tres`
- `project/assets/terrain/meadow/Meadow.tscn`, `scrub/Scrub.tscn`, `snowfield/Snowfield.tscn`
- `project/assets/terrain/birch_tree_snow/BirchTree_Snow_3.fbx(.import)`
- `project/assets/terrain/bush_snow/Bush_Snow_1.fbx(.import)`
- `project/assets/terrain/flower_3_group/` (Flower_3_Group.gltf/.bin/.import, Leaves.png, Flowers.png + .import)
- `project/assets/terrain/flower_4_group/` (Flower_4_Group.gltf/.bin/.import, Leaves.png, Flowers.png + .import)
- `project/assets/terrain/bush_common_flowers/` (Bush_Common_Flowers.gltf/.bin/.import, Leaves_NormalTree_C.png, Flowers.png + .import)
- `project/assets/terrain/fern_1/` (Fern_1.gltf/.bin/.import, Leaves.png + .import)
- `project/assets/terrain/grass_wispy_short/` (Grass_Wispy_Short.gltf/.bin/.import, Grass.png + .import)
- `project/tests/test_new_terrains.gd` + `.gd.uid`

**Modified:**
- `project/tests/test_terrain_schema.gd` (6 → 9 terrain ids, all expectation dicts extended)
- `project/tests/test_bare_tags_derivation.gd` (`EXPECTED_TERRAIN_COUNT` 6 → 9)
- `project/tests/test_economy_rules.gd` (`EXPECTED_FREE_TERRAINS` extended)
- `project/tests/test_hud_hotbar.gd` (button/child count 8/10 → 11/13; the 4 overlap
  assertions in this same file were left untouched, still correctly failing)
- `project/attribution/sources/quaternius_ultimate_nature_pack.tres`
- `project/attribution/sources/quaternius_stylized_nature_megakit.tres`
- `project/CREDITS.md` (regenerated)
- `game-design/content-pipeline-status.md` (Terrain scan table + 3 new item rows +
  intro note, including the HUD-overflow flag)

## Proposals for the human

1. All per-terrain scale/tint/composition choices listed under "Values needing human
   sign-off" above.
2. **The palette-row overflow is the one that needs a decision, not just a look**: adding
   Meadow/Scrub/Snowfield pushed the Terraform+Build palette from 8 to 11 top-level
   buttons, which no longer fits the fixed band and now visibly overlaps the Rotate/Erase
   corner cluster (`test_hud_hotbar.gd` correctly fails on this). Needs either a wider
   band, fewer top-level buttons (e.g. grouping terrains the way Farm Building groups its
   members), or another HUD-side fix — not attempted in this task.
