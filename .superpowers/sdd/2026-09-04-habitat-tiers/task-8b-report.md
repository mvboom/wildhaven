# Task 8b report — hotbar overflow fix (grass-family terrain group)

## What this closes

The previous task (Task 8) added 3 terrains (Meadow, Scrub, Snowfield), taking the
Terraform+Build hotbar row from 8 buttons to 11, overflowing the fixed band between the
Help button and the Rotate/Exit corner cluster — `test_hud_hotbar.gd`'s
`_check_palette_row_never_overlaps_the_corner_clusters()` was left failing on purpose to
prove it.

Per the human's ruling, `grass`, `wild_grass`, `meadow` and `scrub` now group into ONE
palette button (id `grass_family`); `snowfield` stays its own top-level button. Terrain
buttons: water, forest, rock, cultivated_field, snowfield, grass_family = 6. + House + Farm
Building = **8 buttons total**, the count the band was originally built for. The overlap
guard now passes on real, laid-out geometry — I did not touch its assertions or its
tolerances.

## How I mirrored the Farm Building grouping

Farm Building groups 9 `PlaceableDefinition`s behind one button via a data field
(`PlaceableDefinition.hotbar_category`), read by `GameHud._placeable_group_keys()` /
`_placeable_group_row()`, resolved at tap time through
`WorldRoot.get_style_default()`/`style_ids_for_category()`, with a long-press
`StylePickerPopup` as the sub-palette.

I built the exact same mechanism for terrain, function-for-function:

| Farm Building (existing) | Grass-family group (new) |
|---|---|
| `_placeable_group_keys()` | `_terrain_group_keys()` |
| `_placeable_group_row()` | `_terrain_group_row()` |
| `_placeable_group_key_for()` | `_terrain_group_key_for()` |
| grouped by `PlaceableDefinition.hotbar_category` (data field) | grouped by a **hardcoded id list**, `GameHud.TERRAIN_GROUP_MEMBERS` |
| `WorldRoot.get_style_default("farm_building")` etc. | `WorldRoot.get_style_default("grass_family")` etc. — same functions, one more `if category == ...` branch each in `style_ids_for_category()` |
| long-press → `StylePickerPopup` lists every member, tap selects+activates | identical — `grass_family` added to `_PICKER_CATEGORIES`, same `_wire_long_press()`/swallow-flag machinery, same popup scene |
| `refresh_palette_button()` repaints the button after a pick | widened (was placeable-only) to also repaint a terrain-group button |
| `activate_palette_entry()` resolves a placeable group key to a real id via `get_style_default()` | the terrain branch of `activate_palette_entry()` now does the identical resolution for a terrain group key |
| `_is_entry_active()` compares the selection's own group key against the button's id | terrain branch does the same, via `_terrain_group_key_for()` |

**One deliberate difference (structural, not stylistic):** `TerrainDefinition` has no
`hotbar_category` field, and adding one would mean editing every affected `.tres` —
explicitly out of scope ("do not touch `project/data/terrain/*.tres`"). So the grouping is a
hardcoded id list (`GameHud.TERRAIN_GROUP_MEMBERS` / `WorldRoot.TERRAIN_GROUP_MEMBERS`,
deliberately duplicated rather than shared — the same "no shared owner" posture the
`"farm_building"` literal already has across `game_hud.gd`/`world_root.gd`/
`style_picker_popup.gd`/`tile_icon.gd`) rather than a data field. No `.tres` file was
touched.

**One deliberate difference (copy, flagged below):** Farm Building's button label *tracks*
whichever member is currently the default ("Barn", then "Silo" after a pick). Doing the same
for the grass-family group would make the button literally read "Grass" whenever grass is
the resolved default — and grass is the default from a fresh world, since it's first in
`TERRAIN_GROUP_MEMBERS`. The human ruling explicitly rejects that ("the group cannot just be
'Grass'"), so this button's label is a **fixed** group name instead, never the resolved
member's own name. Only the icon still swaps per member.

**One quality addition:** meadow and scrub had no `TileIcon` glyph of their own (only
`grass`/`wild_grass` did). Left alone, the group button would render blank whenever one of
those two was the resolved default — the exact "Barn button looks blank" bug Farm Building's
own fallback glyph already exists to prevent. I added `TileIcon.Kind.GRASS_FAMILY = 12`
(appended, never inserted — the enum's ordinals are a serialized contract, see its own
header) with a small vector glyph (a grass fan plus a flower, nodding at Meadow's `flowers`
tag) and mapped `"grass_family"` to it in `KIND_BY_ID`, mirroring `"farm_building"`'s own
fallback role exactly.

**One structural consequence I had to resolve (not invented, forced by the ruling):**
`wild_grass` was previously ALSO one of the 4 `_PICKER_CATEGORIES` in its own right — a
*different* axis of choice (its own `model_scenes` visual-variant picker, currently sitting
at exactly 1 variant post-revert, so its indicator never showed). Once `wild_grass` has no
top-level button of its own, that picker has no button left to long-press through. I did
**not** invent a nested "picker inside a picker" to preserve it (that would be a second
grouping idiom, which the brief explicitly says is worse than the overflow). I removed
`wild_grass` from `_PICKER_CATEGORIES` and flagged the loss of reachability in a code
comment and here. `WorldRoot.style_ids_for_category("wild_grass")` /
`resolve_style_scene("wild_grass")` are untouched and still power how a *placed* wild_grass
tile renders (`TerrainChunkLod`'s own concern) — only the hotbar's long-press door to that
catalog is gone, and nothing currently reachable through it (1 style) is lost in practice.

## Final button count and layout

- Terrain buttons (6): water, forest, rock, cultivated_field, snowfield, grass_family
  (order preserved: the group sits where `grass` — the first member — would have appeared,
  alphabetically between forest and rock)
- Placeable buttons (2): house, farm_building
- **Total palette-order entries: 8** (`_hud._palette_order.size() == 8`)
- Row children: Info (1) + 8 catalog buttons + Erase (1) = **10**
- Overlap guard passes at `UiPalette.HIT_TARGET` (72px), separation at its max (10px) — the
  row isn't even forced to shrink, confirming the band was sized for exactly 8.

## Group name — AWAITING HUMAN SIGN-OFF

Proposed player-facing name: **"Grasslands"**.

This is a copy decision, explicitly not mine to make. I implemented it as
`GameHud.TERRAIN_GROUP_DISPLAY_NAME` (a single constant, `[COPY]`-tagged in its own doc
comment) so changing it is a one-line diff with no logic to touch. Reasoning for the
proposal: it names what the 4 members share (open and cultivated grass-family ground) at an
8-year-old's vocabulary level, without colliding with "Grass" (one member's own name) —
satisfying the human's own stated constraint ("the group cannot just be 'Grass'"). The
content-writer's lane owns the final word.

## Test edits, old → new

All in `project/tests/test_hud_hotbar.gd`.

1. **`_check_serialised_icon_ordinals_still_point_at_their_glyphs()`** — added
   `"GRASS_FAMILY": 12` to the pinned-ordinal dict (append, not insert — matches the new
   `TileIcon.Kind` member).
2. **`_check_every_catalog_entry_has_a_button()`** — old: asserted every terrain id
   (including the 4 that now group) has its own permanent button. New: the 4 members assert
   `palette_button_for(id) == null` (they group instead), the other 5 standalone terrains
   keep the original `!= null` assertion, plus a new explicit assertion that the
   `grass_family` group button exists. Net: more assertions than before, not fewer.
3. **`_check_button_chrome_icon_number_name()`** — old: checked the `grass` button's chrome.
   New: checks `rock` (still standalone) — `grass` has no button of its own anymore to check.
4. **New: `_check_grass_family_terrain_group_into_one_button()`** — mirrors
   `_check_farm_buildings_group_into_one_button()`: proves all 4 members have no button of
   their own, the group button exists, `snowfield` is *not* swept in, the terrain-half count
   is 6, and the group button's label is the fixed name (never literally "Grass").
5. **New: `_check_grass_family_members_remain_selectable_and_functional()`** — the coverage
   the brief explicitly asked for: for each of the 4 members, opens the grouped button's
   long-press picker, selects that member, and proves (a) it becomes the group's style
   default, (b) it becomes the live `selected_terrain_id()` immediately (not just written to
   a default nobody reads), (c) a plain tap on the *group button itself* also resolves to it,
   and (d) `WorldRoot.paint_tile()` genuinely paints that real terrain onto a tile (not the
   literal group key) — checked against `get_tile_terrain()`, not just HUD bookkeeping.
6. **`_check_palette_row_totals_8_buttons_not_15()`** — count pin updated 11 → 8, row child
   count 13 → 10, doc comment extended (not replaced) to record the count's third value in
   this file's own history (15 → 8 → 11 → 8), consistent with the brief's own instruction
   that "changing a count pin to match a deliberate layout change is fine."
7. **`_PICKER_CATEGORIES`** (test-local mirror) — `wild_grass` removed, `grass_family`
   added; net count unchanged (4).
8. **`_check_popup_indicator_exists_only_on_multi_style_picker_buttons()`** — the
   `wild_grass`-specific "exactly one style, no indicator" block repointed: it now asserts
   the underlying data fact (`style_ids_for_category("wild_grass").size() == 1`, unaffected
   by hotbar grouping) *and* the new, stricter structural fact
   (`palette_button_for("wild_grass") == null`) rather than the now-impossible "has a button
   but no indicator." The generic per-category loop gained `grass_family` for free (its
   count is 4, so it expects — and gets — an indicator). The trailing "4 categories with real
   choice" block and the "skip picker-enabled ids" loop at the bottom both gained
   `grass_family`/`TERRAIN_GROUP_MEMBERS`.
9. **`_check_quick_tap_on_picker_buttons_is_unaffected_by_long_press_wiring()`** —
   `grass_family` added to the TERRAFORM-mode branch condition, with resolution through
   `get_style_default()` (mirrors how `house` vs `farm_building` already differ in the
   BUILD-mode branch below it).
10. **`_check_style_picker_selection_immediately_activates_the_choice()`** — `wild_grass`
    dropped from its first loop (`["forest", "wild_grass"]` → `["forest"]`); this test's own
    structure assumes `selected_terrain_id() == category`, which holds for `forest` but not
    for a true group (`grass_family` resolves to a *different* id). `grass_family` is instead
    covered exhaustively by the new function (#5 above), which doesn't share that
    assumption.
11. **`_check_style_picker_reselecting_current_still_activates_it()`** — `grass_family`
    added to the TERRAFORM-mode branch, resolving `selected_terrain_id()` through the current
    default rather than the literal category (mirrors the BUILD-mode branch's own
    `category if category == "house" else current` shape).
12. **`_check_style_picker_outside_tap_dismisses_with_no_change_and_does_not_leak_through()`**
    — repointed from `wild_grass` to `grass_family` (strict upgrade: now proves the *new*
    group's own popup dismisses cleanly, not just an unrelated one).
13. **`_check_style_picker_panel_shrinks_back_down_after_a_longer_list()`** — repointed the
    "short list" half from `wild_grass` (1 row) to `grass_family` (4 rows) — still
    comfortably shorter than House's 18, keeps the same long-then-short shrink proof.
14. **`_REAL_LONG_PRESS_CATEGORY`** — repointed from `"wild_grass"` to `GameHud.TERRAIN_GROUP_ID`
    — the real-elapsed-Timer test now proves the *new* group's long-press `Timer` fires on
    its own, not just its handler logic.

No assertion was deleted anywhere in this file; every repointed check either kept the same
assertion shape against a different (still-valid) target, or gained assertions.

## Proof the overlap guard passes on geometry, not a relaxed assertion

I did not edit `_check_palette_row_never_overlaps_the_corner_clusters()` at all — confirmed
via `git diff` on `test_hud_hotbar.gd` (that function does not appear in the diff). Its own
assertions are unchanged:

```
PASS  the palette row does not overlap the Help button
PASS  THE FIXED DEFECT: the palette row does not run under the Rotate buttons — Erase is the last button in the row and it was completely covered
PASS  the row fits the band between the corner clusters
PASS  ...without shrinking a button below UiPalette.HIT_TARGET, the stated touch floor
PASS  ...and separation stayed at or above its own minimum
```

`button_size == UiPalette.HIT_TARGET` (72px, unshrunk) and `separation` at its maximum —
the row isn't even squeezed. It passes because the button count genuinely dropped back to 8,
not because a tolerance moved.

## Self-review

- Confirmed via `git diff --stat` that only 5 files changed:
  `project/scripts/ui/game_hud.gd`, `project/scripts/ui/style_picker_popup.gd`,
  `project/scripts/ui/tile_icon.gd`, `project/scripts/world/world_root.gd`,
  `project/tests/test_hud_hotbar.gd`. No `.tres` file, no new script file (so no new
  `.gd.uid` needed).
- `select_palette_option()` (the test-driving id-based selector used across
  `test_mode_tap_model.gd`/`test_resident_lookup.gd`/`test_tap_router_cursor.gd`/
  `test_fact_card.gd`) needed no change: it already operates on real catalog ids, and
  `grass`/`wild_grass`/`meadow`/`scrub` remain real, independent entries in
  `_terrain_entries` — only their hotbar *button* collapsed. Grepped every
  `palette_button_for(`/`select_palette_option(` call across the test suite to confirm
  nothing outside `test_hud_hotbar.gd` touches a now-grouped id by its own button.
- `refresh_palette_button()` was widened from placeable-only to also handle a terrain-kind
  entry; verified this is a harmless no-op for `forest`/`wild_grass` (previously silently
  skipped by the `kind == "placeable"` filter — now resolves to the identical
  already-displayed values via `_terrain_group_row()`'s standalone branch).
- Did not touch `_check_palette_row_never_overlaps_the_corner_clusters()` — per the brief's
  own instruction, if I'd found myself wanting to edit that guard's geometry expectations I
  was to stop and report instead; I never needed to.

## Test commands run

```
bash scripts/run-tests.sh hud_hotbar
  --- palette row: 466 passed, 0 failed ---
  Suites: 1 total, 1 passed, 0 failed

bash scripts/run-tests.sh mode_tap
  --- three-mode tap model: 116 passed, 0 failed ---
  Suites: 1 total, 1 passed, 0 failed

bash scripts/run-tests.sh terrain
  Suites: 4 total, 4 passed, 0 failed
  (test_terrain_schema, test_new_terrains, test_terrain_lod, test_terrain_view_no_blocking)

bash scripts/run-tests.sh
  Suites: 125 total, 120 passed, 5 failed
  Failed suites:
    - test_fox_schema
    - test_human_schema
    - test_inert_land_invariant
    - test_news_report
    - test_rabbit_schema
```

Exactly the five suites the brief named as pre-existing/not-mine, and `test_hud_hotbar` is
off the red list.

## Concerns / things worth a second look

- The `wild_grass` model-scene style-variant picker (currently dormant, 1 style) has lost
  its hotbar door. Not a regression in player-reachable functionality today (nothing was
  reachable through it that isn't still reachable via `WorldRoot` directly), but a future
  content pass re-adding Cactus/Palm variants to `wild_grass.tres` would need a fresh design
  decision on how a player reaches them, since `wild_grass` no longer has its own button.
- `TERRAIN_GROUP_MEMBERS` is deliberately duplicated (not shared) between `game_hud.gd` and
  `world_root.gd`, matching the existing `"farm_building"` bare-literal convention already
  in this codebase across 4 files. If a future terrain joins or leaves the group, both
  copies need updating — a code review catch, not a data edit, until/unless a real
  `hotbar_category`-style field is added to `TerrainDefinition`'s schema (out of scope here).
