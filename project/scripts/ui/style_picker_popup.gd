class_name StylePickerPopup
extends Control
## The long-press style picker — style-picker sub-project B2, Task 7.
##
## OPENED BY `GameHud`, ONLY ON A LONG PRESS. A quick tap on a palette button never reaches
## this file at all (see `game_hud.gd`'s `_wire_long_press()`); this only exists to let the
## player choose WHICH member of a picker category (forest/wild_grass/house/farm_building)
## a button shows and places, an entirely optional second gesture layered on top of the one
## interaction pattern, never a replacement for it.
##
## NO SCRIM, NO FULL-SCREEN BACKGROUND (spec's own instruction for this screen, Pillar 1:
## "nothing here should feel like it's protecting the player from anything" — this is a
## lightweight dropdown, not a modal). `_outside_catcher` still covers the full rect so a
## tap anywhere outside the visible list closes it without falling through to whatever is
## underneath (mirrors `FactCard`/`MenuWindow`'s own scrim-catches-the-tap convention —
## see either file's `_on_scrim_input()` — just with no colour painted on top of the world).
##
## HIDDEN BY DEFAULT, ALWAYS. `visible = false` in `_ready()` and again in `close()` is what
## keeps `_outside_catcher` (a plain, non-Button Control at `MOUSE_FILTER_STOP`) invisible to
## `test_mode_tap_model.gd`'s "no informational panel blocks a gameplay tap" scan — that scan
## only flags a blocker that `is_visible_in_tree()`, so a popup that is never left open by
## accident is never a candidate in the first place.

## Fired when the player taps a row — never on an outside-tap dismiss (that closes with no
## signal at all, per Task 7's own contract: "closes it with no change"). `GameHud` is the
## only listener; this file never touches `WorldRoot` or `GameHud` directly, the same
## signal-out, no-upward-reference shape `palette_changed`/`mode_changed` already use.
signal style_selected(category: String, style_id: String)

## PLACEHOLDER geometry — human's call, same posture as every other pixel value in
## `UiPalette`. Caps the dropdown's height so a long list (e.g. Farm Building's 8 members)
## scrolls instead of running off the top of the screen; a short list sizes down to fit its own
## rows rather than always reserving the full height. UPDATED (review fix, 2026-08-27): every
## style now gets a row, including the current default (`_rebuild_rows()`'s own header) — this
## is no longer about a "remaining" count after excluding one, and a category can legitimately
## have as few as ONE row (e.g. Wild Grass, after its separate content revert back to a single
## `model_scenes` entry) — `GameHud._has_style_choice()` is what keeps a single-row category
## from advertising a popup via its palette button's indicator in the first place, but this
## popup itself still renders correctly for any row count, one included.
const _POPUP_WIDTH: float = 240.0
const _ROW_HEIGHT: float = 44.0
const _ROW_SPACING: float = 6.0
const _POPUP_MAX_HEIGHT: float = 320.0
const _SCREEN_MARGIN: float = 8.0

## Player-facing labels for the three House looks (house cull, 2026-09-07). The ONLY place a
## style id gets an authored label instead of a derived one — every other picker category either
## reads a real `display_name` off its definition (`farm_building`, the grass-family group) or
## humanizes its id with `String.capitalize()`.
##
## WHY A MAP AND NOT A RENAME: `capitalize()` cannot produce the " - " the human's names carry
## ("House - Large", not "House Large"), and a style id is DERIVED FROM A FILENAME
## (`WorldRoot._style_id_from_scene_path()`), so no filename can spell one. The asset folders were
## still renamed alongside this (`house_secondage_1_level1` -> `house_large`, and its two
## siblings) so the stored id, the scene on disk and this label all say the same word; the map
## exists only for the punctuation.
##
## WHY NOT `PlaceableDefinition.display_name`: that field names the BUILDABLE ("House"), one per
## `.tres`. These three are `model_scenes` entries of that single buildable — variants have no
## definition of their own to carry a name, which is the same reason `_label_for()` derives
## forest/wild_grass labels rather than reading them.
##
## A MISS FALLS THROUGH, it does not break: an id not listed here (a re-wired variant from the 15
## the cull left unwired on disk, say) still renders via `capitalize()` below, so this map can go
## stale without ever producing an empty row. Keep it in step with `data/buildings/house.tres`'s
## `model_scenes` — see that file's "LOOK POOL CUT" header note for the other half of this fact.
## Player-facing labels for the five Forest looks (2026-09-08 human naming pass). Second map of
## the same kind as `_HOUSE_LABELS` below, and for the same two reasons: `String.capitalize()`
## cannot produce the " - " these names carry, and it would render `bush_common` as "Bush Common"
## where the human named it plainly "Bush".
##
## NOTE THE IDS DO NOT SPELL THE NAMES, and unlike the house cull the asset folders were NOT
## renamed to match. `common_tree_1` is "Tree - Tall" and `common_tree_3` is "Tree - Short", so
## the numbers carry no ordering meaning. That is deliberate: a style id is DERIVED FROM ITS
## FILENAME (`WorldRoot._style_id_from_scene_path()`), and since D-57 a tile stores the id it was
## painted with — so renaming the folders would strand every captured style in every existing
## save and re-randomise those trees on load, which is the exact symptom two bug reports in this
## same session were about. The house cull could rename freely because nothing stored per-tile
## style yet. Renaming here is still possible LATER, but it is a save-affecting change and needs
## its own ruling, not a tidy-up.
##
## A miss falls through to `capitalize()` exactly as the house map's does — keep in step with
## `data/terrain/forest.tres`'s `model_scenes`.
const _FOREST_LABELS: Dictionary = {
	"common_tree_1": "Tree - Tall",
	"common_tree_2": "Tree - Medium",
	"common_tree_3": "Tree - Short",
	"twisted_tree_1": "Tree - Twisted",
	"bush_common": "Bush",
}

const _HOUSE_LABELS: Dictionary = {
	"house_large": "House - Large",
	"house_medium": "House - Medium",
	"house_small": "House - Small",
}

var _world: WorldRoot = null
var _category: String = ""

## One entry per currently-listed row, `{"style_id": String, "button": Button}` —
## index-aligned with `_list`'s children. Exposed to tests via `row_count()`/`row_style_id()`/
## `select_row()` rather than the raw array, mirroring `GameHud._palette_order`'s own
## test-facing shape.
var _rows: Array[Dictionary] = []

@onready var _outside_catcher: Control = %OutsideCatcher
@onready var _panel: PanelContainer = %Panel
@onready var _scroll: ScrollContainer = %Scroll
@onready var _list: VBoxContainer = %List


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outside_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_outside_catcher.gui_input.connect(_on_outside_catcher_gui_input)
	_panel.add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.CREAM, UiPalette.CORNER_RADIUS_SMALL))
	_list.add_theme_constant_override("separation", int(_ROW_SPACING))


## Opens the picker for `category`, anchored above `anchor_button` ("pops up from the top" —
## the popup's bottom edge lands on the button's top edge). A no-op if `world` or `category`
## is missing — never opens into a broken/empty state.
func open(world: WorldRoot, category: String, anchor_button: Control) -> void:
	if world == null or category == "":
		return
	_world = world
	_category = category
	_rebuild_rows()
	_position_against(anchor_button)
	visible = true
	move_to_front()


## Closes with no change — the outside-tap and the row-selection paths both funnel here;
## only the latter emits `style_selected` first.
func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func category() -> String:
	return _category


func row_count() -> int:
	return _rows.size()


func row_style_id(index: int) -> String:
	return "" if index < 0 or index >= _rows.size() else _rows[index]["style_id"] as String


func row_label(index: int) -> String:
	if index < 0 or index >= _rows.size():
		return ""
	var button: Button = _rows[index]["button"] as Button
	return "" if button == null else button.text


## Test-driving entry point (mirrors `GameHud.palette_button_for()`'s role): selects row
## `index` exactly as tapping its button would, including the close-and-signal it does.
func select_row(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	_on_row_pressed(_rows[index]["style_id"] as String)


## Test-driving entry point for "tap outside dismisses, with no change" — a convenience
## shortcut, not a workaround for a harness limit. CORRECTED (2026-08-27 review): ordinary
## `Control`/`Button` GUI input (`gui_input`, `button_down`/`button_up`/`pressed`) CAN be
## routed headlessly, via `root.push_input(event, true)` (the `true` matters — local
## coordinates, since this project's content-scale `final_transform` would otherwise put a
## non-local-coordinate click nowhere useful); `test_hud_hotbar.gd`'s Task 7 section has a
## real routed-input regression test that does exactly this. Only `TapRouter`'s
## `_unhandled_input` pipeline is the one `test_mode_tap_model.gd`'s own header note documents
## as unroutable in this harness — a DIFFERENT pipeline than this popup's own `gui_input`-based
## dismiss handling. This helper (and `_outside_catcher`'s own `MOUSE_FILTER_STOP`, proven
## structurally the same way `test_mode_tap_model.gd` checks `FactCard`'s/`MenuWindow`'s
## scrims) still exists because it's less code at each call site than constructing a real
## `InputEventMouseButton` every time, not because the real path is unavailable.
func simulate_outside_tap() -> void:
	close()


## Rebuilds the row list against `_category`'s CURRENT catalog and CURRENT default — always
## called fresh on `open()` (never cached across opens), so a style chosen elsewhere between
## two long-presses on the same button is reflected correctly.
##
## LISTS EVERY STYLE, INCLUDING THE CURRENT ONE (refinement round, 2026-08-27) — the earlier
## `if style_id == current: continue` skip is gone. The current default's row is instead the
## SAME green highlight `UiPalette.paint_button(..., true)` already means everywhere else in
## this HUD (`_refresh_palette_rendering()`'s `is_active` paint, `_refresh_mode_buttons()`'s
## Inspect toggle): "this is the one that's on" reads the same way here as it does anywhere
## else in the game, rather than the popup inventing its own "missing row means selected"
## convention that a player would have to learn separately.
func _rebuild_rows() -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	_rows.clear()

	if _world == null:
		return
	var current: String = _world.get_style_default(_category)
	for style_id: String in _world.style_ids_for_category(_category):
		var label: String = _label_for(style_id)
		var button := Button.new()
		button.name = "StyleRow_%s" % style_id
		button.text = label
		button.custom_minimum_size = Vector2(0, _ROW_HEIGHT)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_row_pressed.bind(style_id))
		UiPalette.paint_button(button, style_id == current)
		_list.add_child(button)
		_rows.append({"style_id": style_id, "button": button})

	var content_height: float = (
		_rows.size() * _ROW_HEIGHT + maxf(0.0, float(_rows.size() - 1)) * _ROW_SPACING
	)
	_scroll.custom_minimum_size = Vector2(
		_POPUP_WIDTH, clampf(content_height, _ROW_HEIGHT, _POPUP_MAX_HEIGHT)
	)

	# IMPORTANT FIX (2026-08-27 review, reproduced live): a Control's actual `size` only ever
	# grows to match a larger minimum size — it does not shrink back down on its own when the
	# minimum later gets smaller. Without this reset, opening a long list once (e.g. House, 9
	# rows) and then a shorter one afterward (e.g. Wild Grass, 2 rows) left `_panel` stuck at
	# the LONGER list's size for the rest of the session — misplaced and running off-screen,
	# since `_position_against()` positions the panel using its (now correct, smaller) minimum
	# size while the panel itself kept rendering at the old, larger one. Must run AFTER
	# `_scroll.custom_minimum_size` is set above (this call resets `_panel`'s size down to ITS
	# CURRENT minimum, which is only correct once that minimum reflects the new row count) and
	# BEFORE `_position_against()` reads it (called next, from `open()`).
	_panel.reset_size()


## House: an authored label from `_HOUSE_LABELS` (the three looks the 2026-09-07 cull left
## wired), falling through to the humanized id for anything not listed there.
##
## Forest: an authored label from `_FOREST_LABELS` (2026-09-08 naming pass), falling through to
## the humanized id for anything not listed.
##
## Wild Grass: humanize the derived style id (`"wild_grass"` -> `"Wild Grass"` —
## `String.capitalize()` is exactly this rule: underscores become spaces, each word's first
## letter uppercases). Farm Building AND the grass-family terrain group (habitat-tiers Task
## 8b): the resolved definition's own real `display_name` — already real human-authored copy,
## no humanization needed (and, for the grass-family group specifically, correct where
## `capitalize()` would not always be: `wild_grass`'s own `display_name` is "Wild grass",
## lowercase `g`, which `"wild_grass".capitalize()` alone would get wrong).
func _label_for(style_id: String) -> String:
	if _category == "farm_building":
		for placeable: PlaceableDefinition in _world.placeable_options():
			if placeable.id == style_id:
				return placeable.display_name
		return style_id
	if _category == GameHud.TERRAIN_GROUP_ID:
		for terrain: TerrainDefinition in _world.terrain_options():
			if terrain.id == style_id:
				return terrain.display_name
		return style_id.capitalize()
	if _category == "house" and _HOUSE_LABELS.has(style_id):
		return _HOUSE_LABELS[style_id] as String
	if _category == "forest" and _FOREST_LABELS.has(style_id):
		return _FOREST_LABELS[style_id] as String
	return style_id.capitalize()


func _on_row_pressed(style_id: String) -> void:
	style_selected.emit(_category, style_id)
	close()


## "pops up from the top": the panel's BOTTOM edge lands on `anchor_button`'s TOP edge,
## horizontally centred on the button and clamped to stay on screen. A **visual judgment
## call** (exact clamping/centring behaviour) — flagged under Proposals.
func _position_against(anchor_button: Control) -> void:
	if anchor_button == null:
		return
	var button_rect: Rect2 = anchor_button.get_global_rect()
	var panel_size: Vector2 = _panel.get_combined_minimum_size()
	var x: float = button_rect.position.x + button_rect.size.x * 0.5 - panel_size.x * 0.5
	var y: float = button_rect.position.y - panel_size.y
	var viewport_width: float = get_viewport_rect().size.x
	x = clampf(x, _SCREEN_MARGIN, maxf(_SCREEN_MARGIN, viewport_width - panel_size.x - _SCREEN_MARGIN))
	_panel.position = Vector2(x, maxf(0.0, y))


## "tapping outside the popup's rect closes it with no change" — the catcher covers the full
## rect BEHIND the visible panel (added first, drawn under it — same z-order trick
## `FactCard`'s `Scrim`/`Card` pair uses), so a tap that lands on the panel or one of its row
## buttons never reaches here; `accept_event()` is what stops this same tap from also
## reaching whatever `TapRouter`/a palette button underneath would otherwise see.
func _on_outside_catcher_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		close()
		accept_event()
