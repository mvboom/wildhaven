extends QATestCase
## THE FIXED PALETTE ROW (terraform-bar rework). Retires the old 5-slot assignable hotbar
## outright: `GameHud` now builds exactly one button per catalog entry (every terrain, then
## every placeable), always all present, never assigned — see `game_hud.gd`'s own header.
##
## Run:
##   bash scripts/run-tests.sh hud_hotbar

const WORLD_PATH: String = "res://scenes/Main.tscn"

var _world: WorldRoot = null
var _ui: GameUI = null
var _hud: GameHud = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("palette row")
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		finish()
		return
	_world = node as WorldRoot
	root.add_child(_world)
	_setup_ok = true


func _process(delta: float) -> bool:
	if not _setup_ok:
		return true

	# Real-time-wait phase (review finding #3): once every synchronous check below has run,
	# `_pending_real_long_press` is set and this accumulates actual elapsed `_process()` time
	# — not a bare frame count — until a real `Timer` (elsewhere in the tree, ticking on its
	# own every frame the engine processes) has had strictly more than `LONG_PRESS_SECONDS` to
	# fire. This is the ONLY thing that makes this suite take noticeably longer to run than it
	# used to; that cost buys real coverage of the `Timer`'s own wiring, not just its handler.
	if _pending_real_long_press:
		_real_long_press_elapsed += delta
		if _real_long_press_elapsed < _real_long_press_deadline:
			return false
		_pending_real_long_press = false
		_finish_real_long_press_timer_wait()
		finish()
		return true

	_frames += 1
	if _frames < 3:
		return false

	var ui_node: Node = _world.get_node_or_null("GameUI")
	if not check(ui_node is GameUI, "Main.tscn instances the GameUI shell"):
		finish()
		return true
	_ui = ui_node as GameUI
	_ui.bind_world()
	_hud = _ui.hud

	_check_hit_target_shrunk()
	_check_serialised_icon_ordinals_still_point_at_their_glyphs()
	_check_palette_row_never_overlaps_the_corner_clusters()
	_check_inspect_toggle_remembers_last_content_mode()
	_check_every_catalog_entry_has_a_button()
	_check_farm_rename()
	_check_erase_is_relabelled()
	_check_row_order_look_then_catalog_then_erase()
	_check_rotate_buttons_are_not_in_the_palette_row_and_are_the_same_size()
	_check_look_button_has_icon_number_and_name()
	_check_button_chrome_icon_number_name()
	_check_activate_sets_mode_implicitly()
	_check_activate_remove()
	_check_palette_changed_signal_fires()
	_check_number_key_activates_entry()
	_check_number_key_zero_toggles_inspect()
	_check_land_and_build_buttons_are_gone()
	_check_hotbar_visible_in_every_mode()
	_check_rotate_and_exit_buttons_hover_like_every_other_button()
	_check_farm_buildings_group_into_one_button()
	_check_palette_row_totals_8_buttons_not_15()
	_check_farm_building_button_resolves_to_the_current_style_default()
	_check_refresh_palette_button_repaints_farm_building_chrome()
	_check_quick_tap_on_picker_buttons_is_unaffected_by_long_press_wiring()
	_check_popup_indicator_exists_only_on_multi_style_picker_buttons()
	_check_long_press_opens_style_picker_and_swallows_the_release()
	_check_style_picker_lists_every_style_with_current_highlighted()
	_check_style_picker_selection_updates_default_and_button_chrome()
	_check_style_picker_selection_immediately_activates_the_choice()
	_check_style_picker_reselecting_current_still_activates_it()
	_check_changing_a_group_default_retargets_the_live_selection()
	_check_style_picker_outside_tap_dismisses_with_no_change_and_does_not_leak_through()
	_check_style_picker_panel_shrinks_back_down_after_a_longer_list()
	_check_long_press_drag_off_release_via_real_routed_input_does_not_strand_the_swallow_flag()

	return not _begin_real_long_press_timer_wait()


## REGRESSION GUARD (2026-09-03), and the defect it guards was LIVE AT THE DEFAULT SIZE, not on
## some hypothetical small screen. `PaletteRow` centred on the whole canvas while `HelpButton`
## and `BottomRight` sat pinned in the corners, so at the 1152-wide canvas that
## `window/stretch/mode="canvas_items"` + `aspect="expand"` produces for EVERY window at 16:9
## or narrower, the row spanned 171..981 against a Rotate cluster at 892..1046 — Erase was
## entirely underneath it and unpressable. It cleared only on an ultrawide canvas (1536), which
## is exactly the kind of defect that looks fine on whichever machine you happened to check.
##
## Asserted as REAL LAID-OUT RECTS, deliberately: `_fit_palette_row()` could compute a perfect
## band and still be wrong if the row did not end up where it thought. The gap must be
## non-negative on BOTH sides — the left corner is one Help-button-width from overlapping too.
func _check_palette_row_never_overlaps_the_corner_clusters() -> void:
	var hud_node: Control = _hud as Control
	var help: Control = hud_node.get_node_or_null("HelpButton") as Control
	var bottom_right: Control = hud_node.get_node_or_null("BottomRight") as Control
	var row: Control = hud_node.get_node_or_null("PaletteRow") as Control
	if not check(help != null and bottom_right != null and row != null,
			"the bottom band's three pieces are all present"):
		return

	var left_gap: float = row.get_rect().position.x - help.get_rect().end.x
	var right_gap: float = bottom_right.get_rect().position.x - row.get_rect().end.x
	check(left_gap >= 0.0, "the palette row does not overlap the Help button",
		"left gap %.0fpx (row starts %.0f, Help ends %.0f)"
			% [left_gap, row.get_rect().position.x, help.get_rect().end.x])
	check(right_gap >= 0.0,
		"THE FIXED DEFECT: the palette row does not run under the Rotate buttons — Erase is the "
		+ "last button in the row and it was completely covered",
		"right gap %.0fpx (row ends %.0f, Rotate starts %.0f)"
			% [right_gap, row.get_rect().end.x, bottom_right.get_rect().position.x])

	# Erase specifically, by node: the check above would still pass if Erase had been dropped
	# from the row entirely, which would "fix" the overlap by deleting the button.
	var erase: Button = _hud.get_node_or_null("%RemoveButton") as Button
	if check(erase != null, "the Erase button is in the row"):
		check(erase.get_global_rect().end.x <= bottom_right.get_global_rect().position.x,
			"...and its right edge clears the Rotate cluster",
			"Erase ends %.0f, Rotate starts %.0f"
				% [erase.get_global_rect().end.x, bottom_right.get_global_rect().position.x])

	# The fit spends separation before hit target, and never crosses the floor.
	var metrics: Dictionary = _hud.palette_fit_metrics()
	check(metrics["used"] <= metrics["band"],
		"the row fits the band between the corner clusters",
		"used %.0f of %.0f" % [metrics["used"], metrics["band"]])
	check_eq(metrics["button_size"], float(UiPalette.HIT_TARGET),
		"...without shrinking a button below UiPalette.HIT_TARGET, the stated touch floor")
	check(metrics["separation"] >= GameHud.PALETTE_SEPARATION_MIN,
		"...and separation stayed at or above its own minimum",
		"separation %d" % metrics["separation"])


## REGRESSION GUARD (2026-09-03). `TileIcon.kind` is an `@export`, so a scene that sets it
## stores the ENUM'S INTEGER: GameUI's Field Guide button is `kind = 10` and LeaveOverlay's
## Exit is `kind = 8`. Adding FARM_BUILDING in the MIDDLE of `TileIcon.Kind` shifted both by
## one — the Field Guide's "?" silently became LOOK's arrow, and Leave's "X" became the eraser
## block. Nothing threw and no existing check noticed, because both scenes were still perfectly
## valid; they just meant something else.
##
## Asserted against the LITERALS the two .tscn files carry, deliberately: reading the scene's
## number back out of the scene would agree with itself no matter what the enum did. These are
## the ordinals on disk, and this fails if the enum stops agreeing with them.
func _check_serialised_icon_ordinals_still_point_at_their_glyphs() -> void:
	check_eq(int(TileIcon.Kind.HELP), 10,
		"GameUI.tscn's Field Guide button (kind = 10) still resolves to the HELP question mark")
	check_eq(int(TileIcon.Kind.EXIT), 8,
		"LeaveOverlay.tscn's Exit button (kind = 8) still resolves to the EXIT cross")

	# The rest of the enum is pinned too, so an insertion anywhere is caught here rather than
	# in whichever scene happens to serialise the member that moved.
	var expected: Dictionary = {
		"WILD_GRASS": 0, "GRASS": 1, "WATER": 2, "FOREST": 3, "ROCK": 4, "FARM": 5,
		"HOUSE": 6, "ERASER": 7, "EXIT": 8, "LOOK": 9, "HELP": 10, "FARM_BUILDING": 11,
	}
	for name: String in expected:
		check_eq(int(TileIcon.Kind[name]), expected[name] as int,
			"TileIcon.Kind.%s keeps ordinal %d — new members APPEND, never insert"
				% [name, expected[name]])
	check_eq(TileIcon.Kind.size(), expected.size(),
		"...and every member of the enum is accounted for above")


func _check_hit_target_shrunk() -> void:
	check_eq(UiPalette.HIT_TARGET, 72,
		"HIT_TARGET stays 72 — unrelated to this rework, ported forward unchanged")


func _check_inspect_toggle_remembers_last_content_mode() -> void:
	_hud.activate_palette_entry("terrain", "grass")
	var before: GameHud.Mode = _hud.mode()
	_hud.toggle_inspect()
	check_eq(_hud.mode(), GameHud.Mode.INSPECT, "toggle_inspect() enters Inspect")
	_hud.toggle_inspect()
	check_eq(_hud.mode(), before, "...and returns to the remembered content mode")


## THE CORE GUARANTEE THIS REWORK EXISTS FOR: every terrain the catalog reports gets a real
## button, with no assignment step and no empty/unreachable slot. Placeables are the SAME
## guarantee one level up — every placeable is reachable through its GROUP's button (see
## `_check_farm_buildings_group_into_one_button()` below for the B2 Task 6 grouping itself) —
## because a permanent button per raw `PlaceableDefinition` is exactly the interim state B2
## Task 6 closes (8 farm buildings each had their own button).
func _check_every_catalog_entry_has_a_button() -> void:
	var terrain_ids: Array[String] = []
	_hud.set_mode(GameHud.Mode.TERRAFORM)
	terrain_ids = _hud.palette_option_ids()
	if not check(terrain_ids.size() > 0, "the Terraform catalog has at least one entry"):
		return
	for id: String in terrain_ids:
		check(_hud.palette_button_for(id) != null,
			"terrain id '%s' has a permanent palette button" % id)

	var placeable_ids: Array[String] = []
	_hud.set_mode(GameHud.Mode.BUILD)
	placeable_ids = _hud.palette_option_ids()
	check(placeable_ids.size() > 0, "the Build catalog has at least one entry")

	check(_hud.palette_button_for("house") != null,
		"the House button specifically exists — Build is reachable with no other door needed")
	check(_hud.palette_button_for("farm_building") != null,
		"...and the Farm Building GROUP button exists, keyed by category rather than by any one "
		+ "of its 9 members' real ids")


func _check_farm_rename() -> void:
	_hud.set_mode(GameHud.Mode.TERRAFORM)
	var button: Button = _hud.palette_button_for("cultivated_field")
	if not check(button != null, "the cultivated_field button exists"):
		return
	check_eq(button.tooltip_text, "Farm",
		"the cultivated_field button's accessible name reads 'Farm', not 'Cultivated field'")


## Item 7 of the rework: "Take Away" reads unclear next to an eraser icon.
func _check_erase_is_relabelled() -> void:
	var remove_button: Button = _hud.get_node_or_null("%RemoveButton") as Button
	if not check(remove_button != null, "the Erase button exists"):
		return
	check_eq(remove_button.tooltip_text, "Erase",
		"the erase button's accessible name reads 'Erase', not the old '[COPY] Take Away' stub")
	var name_label: Label = remove_button.get_node_or_null("NameLabel") as Label
	if check(name_label != null, "...and it has a visible name label, same as every other button"):
		check_eq(name_label.text, "Erase", "...reading 'Erase'")
	check(remove_button.get_node_or_null("Number") == null,
		"...but no number badge — Erase has no keyboard shortcut")


## Item 5 of the rework: Look (now "Info", human-decided rename) becomes a full
## palette-row-style button — an icon, "Info" underneath, and key 0 — instead of the old
## separate green "[COPY] Look" text pill.
func _check_look_button_has_icon_number_and_name() -> void:
	var look_button: Button = _hud.get_node_or_null("%InspectButton") as Button
	if not check(look_button != null, "the Info (Look) button exists"):
		return
	check(look_button.get_node_or_null("Icon") is TileIcon, "...with an icon (an arrow glyph)")
	var number: Label = look_button.get_node_or_null("Number") as Label
	if check(number != null, "...a number badge"):
		check_eq(number.text, "0", "...reading '0', read before key 1")
	var name_label: Label = look_button.get_node_or_null("NameLabel") as Label
	if check(name_label != null, "...and a name label"):
		check_eq(name_label.text, "Info", "...reading 'Info', the human-decided rename from 'Look'")


## Item 3 of the rework: every palette-row button (not just Info/Erase) shows its name below
## its icon, small — an icon alone did not say what a button was.
func _check_button_chrome_icon_number_name() -> void:
	_hud.set_mode(GameHud.Mode.TERRAFORM)
	var button: Button = _hud.palette_button_for("grass")
	if not check(button != null, "the grass button exists"):
		return
	check(button.get_node_or_null("Icon") is TileIcon, "...has an icon")
	var number: Label = button.get_node_or_null("Number") as Label
	check(number != null, "...a number badge")
	var name_label: Label = button.get_node_or_null("NameLabel") as Label
	if check(name_label != null, "...and a visible name label"):
		check_eq(name_label.text, "Grass", "...reading the catalog's own display name")
		check(
			name_label.get_theme_font_size("font_size") < UiPalette.FONT_HOTBAR,
			"...small, per the playtest ask — smaller than the HUD's ordinary chrome font"
		)


## The palette row's required order: Info, then every terrain/building button, then the fixed
## Erase button — one row, nothing overlaid. Rotate is NOT in this row (playtest feedback,
## item 8: moved out to sit next to the Exit button instead) — `_check_rotate_buttons_are_not_
## in_the_palette_row_and_are_the_same_size` below covers that half.
func _check_row_order_look_then_catalog_then_erase() -> void:
	var row: HBoxContainer = _hud.get_node_or_null("%PaletteRow") as HBoxContainer
	if not check(row != null, "the palette row exists"):
		return
	var look_button: Button = _hud.get_node_or_null("%InspectButton") as Button
	var remove_button: Button = _hud.get_node_or_null("%RemoveButton") as Button
	if not check(look_button != null and remove_button != null, "Info and Erase both exist"):
		return
	check_eq(look_button.get_index(), 0, "Info is the row's first (leftmost) button")

	var house_button: Button = _hud.palette_button_for("house")
	if check(house_button != null, "a catalog button exists to compare positions against"):
		check(look_button.get_index() < house_button.get_index(),
			"Info sits before a catalog button")
		check(house_button.get_index() < remove_button.get_index(),
			"...which sits before Erase — Erase is the row's last button")


## Item 8 of the rework: Rotate moves OUT of the palette row entirely, into its own
## bottom-right cluster next to `LeaveOverlay`'s Exit button (a separate scene this suite does
## not instantiate, so "next to Exit" itself is a human check on a real build — this proves
## the structural half: Rotate is not mixed into the content-picking row, and it kept its size).
func _check_rotate_buttons_are_not_in_the_palette_row_and_are_the_same_size() -> void:
	var row: HBoxContainer = _hud.get_node_or_null("%PaletteRow") as HBoxContainer
	var rotate_ccw: Button = _hud.get_node_or_null("%RotateCcwButton") as Button
	var rotate_cw: Button = _hud.get_node_or_null("%RotateCwButton") as Button
	if not check(row != null and rotate_ccw != null and rotate_cw != null,
		"the palette row and both Rotate buttons exist"):
		return
	check(rotate_ccw.get_parent() != row, "Rotate CCW is not a child of the palette row")
	check(rotate_cw.get_parent() != row, "...neither is Rotate CW")
	check_eq(rotate_ccw.get_parent(), rotate_cw.get_parent(),
		"...they share the same (other) parent, so they still sit next to each other")
	var expected := Vector2(UiPalette.HIT_TARGET, UiPalette.HIT_TARGET)
	check_eq(rotate_ccw.custom_minimum_size, expected, "Rotate CCW kept the standard button size")
	check_eq(rotate_cw.custom_minimum_size, expected, "...and so did Rotate CW")


func _check_activate_sets_mode_implicitly() -> void:
	_hud.set_mode(GameHud.Mode.INSPECT)
	_hud.activate_palette_entry("terrain", "water")
	check_eq(_hud.mode(), GameHud.Mode.TERRAFORM,
		"activating a terrain entry switches to TERRAFORM implicitly")
	check_eq(_hud.selected_terrain_id(), "water", "...and selects that exact terrain")
	check(not _hud.is_remove_selected(), "...and Remove is not implicitly selected")

	_hud.set_mode(GameHud.Mode.INSPECT)
	_hud.activate_palette_entry("placeable", "house")
	check_eq(_hud.mode(), GameHud.Mode.BUILD,
		"activating a placeable entry switches to BUILD implicitly")
	check_eq(_hud.selected_placeable_id(), "house", "...and selects that exact placeable")


func _check_activate_remove() -> void:
	_hud.activate_palette_entry("terrain", "grass")
	_hud.activate_remove()
	check(_hud.is_remove_selected(), "activate_remove() selects the Remove tool")


func _check_palette_changed_signal_fires() -> void:
	var fired: Array[bool] = [false]
	_hud.palette_changed.connect(func() -> void: fired[0] = true)
	_hud.activate_palette_entry("terrain", "rock")
	check(fired[0], "activate_palette_entry() emits palette_changed")


func _check_number_key_activates_entry() -> void:
	_hud.set_mode(GameHud.Mode.TERRAFORM)
	var ids: Array[String] = _hud.palette_option_ids()
	if not check(ids.size() > 0, "at least one terrain id exists at key 1"):
		return

	# D-41: the number-key handler no longer gates on Input.mouse_mode (the fixed pan/zoom
	# camera never captures the pointer). This still drives the underlying activation
	# directly rather than a synthetic key event, since this headless harness has no way to
	# dispatch a real InputEventKey through the engine's own input pipeline.
	_hud._activate_palette_entry_by_number(1)
	check(_hud.selected_terrain_id() != "" or _hud.selected_placeable_id() != "",
		"key 1 activates whatever the first palette entry is")

	note_expected_pending(
		"THE REAL KEYPRESS 1-9 IS NOT EXERCISED END-TO-END HEADLESSLY (measured)",
		"This harness has no way to dispatch a real InputEventKey through the engine's input "
		+ "pipeline, so the live keypress -> _unhandled_input() -> activate path needs a human "
		+ "check on a real desktop build."
	)


## Item 5's key 0: routes to `toggle_inspect()`, NOT into `_palette_order` — a different branch
## inside `_unhandled_input()` than the 1-9 path above. Calling `_unhandled_input()` directly
## with a hand-built `InputEventKey` is a plain function call (not the engine's own input
## pipeline `Viewport.push_input()` cannot reach headlessly — see the pending note above), so
## this exercises the branch itself, not the OS-level keypress.
func _check_number_key_zero_toggles_inspect() -> void:
	check_eq(_hud._number_for_keycode(KEY_0), 0, "KEY_0 maps to palette-key number 0")

	_hud.activate_palette_entry("terrain", "grass")
	var before: GameHud.Mode = _hud.mode()
	var event := InputEventKey.new()
	event.keycode = KEY_0
	event.pressed = true
	_hud._unhandled_input(event)
	check_eq(_hud.mode(), GameHud.Mode.INSPECT,
		"key 0 toggles Inspect, the same as pressing the Info button")

	_hud._unhandled_input(event)
	check_eq(_hud.mode(), before,
		"...and pressing it again returns to the remembered content mode")


func _check_land_and_build_buttons_are_gone() -> void:
	check(_hud.get_node_or_null("%TerraformButton") == null,
		"the retired Land (Terraform category) button no longer exists")
	check(_hud.get_node_or_null("%BuildButton") == null,
		"the retired Build category button no longer exists")


func _check_hotbar_visible_in_every_mode() -> void:
	var row: Control = _hud.get_node_or_null("%PaletteRow") as Control
	if not check(row != null, "the palette row exists"):
		return
	for mode: GameHud.Mode in [GameHud.Mode.INSPECT, GameHud.Mode.TERRAFORM, GameHud.Mode.BUILD]:
		_hud.set_mode(mode)
		check(row.visible, "the palette row stays visible in mode %d, including Inspect" % mode)


## Playtest feedback: Rotate's and Exit's hover states "did not hover well" next to every other
## button — both only ever had a `normal` stylebox set directly in their `.tscn`, never `hover`,
## so they fell back to Godot's stock theme for it instead of the HUD's own cream/sand look.
func _check_rotate_and_exit_buttons_hover_like_every_other_button() -> void:
	var rotate_ccw: Button = _hud.get_node_or_null("%RotateCcwButton") as Button
	var rotate_cw: Button = _hud.get_node_or_null("%RotateCwButton") as Button
	if check(rotate_ccw != null and rotate_cw != null, "both Rotate buttons exist"):
		check(rotate_ccw.has_theme_stylebox_override("hover"),
			"Rotate CCW has a real hover stylebox override, same as every palette button")
		check(rotate_cw.has_theme_stylebox_override("hover"),
			"...and so does Rotate CW")

	var leave_overlay: Node = _world.get_node_or_null("LeaveOverlay")
	var leave_button: Button = null
	if leave_overlay != null:
		leave_button = leave_overlay.get_node_or_null("%LeaveButton") as Button
	if check(leave_button != null, "the Exit (Leave) button exists"):
		check(leave_button.has_theme_stylebox_override("hover"),
			"...and it has a real hover stylebox override too")


# --- Style-picker B2, Task 6: Farm Building grouping ---------------------------------------
#
# B1 shipped 8 independent Farm Building `PlaceableDefinition`s (barn, small_barn, open_barn,
# chicken_coop, silo, windmill, water_tower, well), each rendering its own palette button — an
# accepted interim state, explicitly meant to close here. `game_hud.gd`'s header (the
# `hotbar_category` note) documents the mechanism; these checks prove the regression itself is
# actually fixed, not just that grouping code exists.

## Every farm-building `PlaceableDefinition.id` currently in the catalog, in `placeable_options()`
## order. Read fresh from `WorldRoot` rather than hardcoded — same "no hardcoded list" rule the
## rest of this file follows.
func _farm_building_ids() -> Array[String]:
	var ids: Array[String] = []
	for placeable: PlaceableDefinition in _world.placeable_options():
		if placeable.hotbar_category == "farm_building":
			ids.append(placeable.id)
	return ids


## RE-POINTED 2026-09-04 (habitat-tiers Task 7): was 8. Farmhouse joins the group as a
## real, independent `farm_building`-category buildable (habitat-tiers ruling, `large_house`
## tag) — PLAYER-VISIBLE EFFECT: it now appears as a 9th option behind the single grouped
## "Farm Building" hotbar button, same as every other farm building. The button count itself
## (2, checked below) is unaffected — grouping is by category, not by member count.
##
## The 9 raw farm-building `PlaceableDefinition`s render through exactly ONE button, keyed by
## the shared `hotbar_category` rather than by any one member's own id — none of the 9 gets a
## button of its own.
func _check_farm_buildings_group_into_one_button() -> void:
	_hud.set_mode(GameHud.Mode.BUILD)
	var farm_building_ids: Array[String] = _farm_building_ids()
	if not check(farm_building_ids.size() == 9,
		"the farm-building catalog now has 9 members (got %d) — Farmhouse added by the habitat-tiers ruling" % farm_building_ids.size()):
		return

	for id: String in farm_building_ids:
		check(_hud.palette_button_for(id) == null,
			"'%s' has NO permanent button of its own — B1's interim state" % id)

	check(_hud.palette_button_for("farm_building") != null,
		"...they render through exactly one button, keyed 'farm_building'")

	var placeable_button_count: int = 0
	for entry: Dictionary in _hud._palette_order:
		if (entry["kind"] as String) == "placeable":
			placeable_button_count += 1
	check_eq(placeable_button_count, 2,
		"the Build half of the row totals 2 buttons — House and Farm Building — not 9")


## THE SPECIFIC REGRESSION THIS TASK FIXES: 15 buttons (6 terrain + 9 raw placeables, B1's
## shipped interim state) down to 8 (6 terrain + House + Farm Building).
##
## COUNT UPDATED (2026-09-04, habitat-tiers Task 8): 8 -> 11. The habitat-tiers ruling adds
## 3 new terrain `.tres` entries — Meadow, Scrub, Snowfield (task-8-brief.md) — each a real,
## player-visible new entry in the Terraform palette, so the row is now 9 terrain + House +
## Farm Building = 11. Still nowhere near the 15-button regression this check exists to
## guard against; the "not 15" framing stays true. See
## `_check_palette_row_never_overlaps_the_corner_clusters()`'s own failures for the SEPARATE,
## genuine consequence this count increase has on the row's fit within the fixed band —
## that is a real layout defect this task's data change exposes, not something this count
## assertion papers over.
func _check_palette_row_totals_8_buttons_not_15() -> void:
	check_eq(_hud._palette_order.size(), 11,
		"the BUILD+TERRAFORM row totals 11 buttons — 9 terrain + House + Farm Building — not 15")

	var row: HBoxContainer = _hud.get_node_or_null("%PaletteRow") as HBoxContainer
	if not check(row != null, "the palette row exists"):
		return
	# Info + 11 catalog buttons + Erase = 13 real children — the row's own scene tree, not just
	# the bookkeeping array, so this catches a divergence between the two.
	check_eq(row.get_child_count(), 13,
		"the row's real child count matches: Info (1) + 11 catalog buttons + Erase (1)")


## Step 2's contract: tapping the Farm Building button resolves to whichever member is
## CURRENTLY `get_style_default("farm_building")`'s answer — verified against what
## `WorldRoot.place_building()` actually places, not just against `selected_placeable_id()`.
func _check_farm_building_button_resolves_to_the_current_style_default() -> void:
	var expected_id: String = _world.get_style_default("farm_building")
	if not check(expected_id != "", "get_style_default('farm_building') returns a real id"):
		return

	_hud.set_mode(GameHud.Mode.INSPECT)
	_hud.activate_palette_entry("placeable", "farm_building")
	check_eq(_hud.mode(), GameHud.Mode.BUILD,
		"tapping the Farm Building button switches to BUILD implicitly, like any placeable")
	check_eq(_hud.selected_placeable_id(), expected_id,
		"...and resolves the group id to the real, currently-default member id — never the "
		+ "literal string 'farm_building'")

	var tile := Vector2i(21, 21)
	# Paint a 2x2 block, not just the origin tile: the resolved default may be Barn (the one
	# 2x2-footprint farm building), and `place_building()` requires every footprint tile to
	# already be eligible terrain.
	for dx in range(2):
		for dz in range(2):
			_world.paint_tile(tile.x + dx, tile.y + dz, "grass")
	var placed: bool = _world.place_building(tile.x, tile.y, _hud.selected_placeable_id())
	check(placed, "WorldRoot.place_building() accepts the resolved id")
	var built: PlaceableDefinition = _world.grid.get_building(tile.x, tile.y)
	check(built != null and built.id == expected_id,
		"...and what actually landed on the tile is the resolved member, not the group key")


## Step 3's forward-looking hook for Task 7's (not-yet-built) long-press popup:
## `refresh_palette_button()` repaints one button's icon/name against a NEW style default,
## without rebuilding the row or touching any other button. No popup exists yet to call it, so
## this drives the same write (`WorldRoot.set_style_default()`) the popup will make directly.
func _check_refresh_palette_button_repaints_farm_building_chrome() -> void:
	var farm_building_ids: Array[String] = _farm_building_ids()
	var current: String = _world.get_style_default("farm_building")
	var other: String = ""
	for id: String in farm_building_ids:
		if id != current:
			other = id
			break
	if not check(other != "", "a different farm-building member exists to switch the default to"):
		return

	_world.set_style_default("farm_building", other)
	_hud.refresh_palette_button("farm_building")

	var button: Button = _hud.palette_button_for("farm_building")
	if not check(button != null, "the Farm Building button still exists after refresh"):
		return
	var expected_name: String = ""
	for placeable: PlaceableDefinition in _world.placeable_options():
		if placeable.id == other:
			expected_name = placeable.display_name
			break
	check_eq(button.tooltip_text, expected_name,
		"refresh_palette_button() repaints the tooltip against the NEW default")
	var name_label: Label = button.get_node_or_null("NameLabel") as Label
	if check(name_label != null, "...and the button kept its name label"):
		check_eq(name_label.text, expected_name, "...repainted to the new default's name too")

	# The same guarantee proved above, proved again after a live default change: a tap resolves
	# live through WorldRoot, never through anything cached at refresh time.
	_hud.set_mode(GameHud.Mode.INSPECT)
	_hud.activate_palette_entry("placeable", "farm_building")
	check_eq(_hud.selected_placeable_id(), other,
		"...and a tap after the swap resolves to the NEW default, not the old one")


# --- Task 7: long-press style picker ------------------------------------------------------
#
# Most checks below drive signals directly (`button.button_down.emit()` etc.) — the same
# style every other check in this file already uses one level up (calling
# `activate_palette_entry()` directly instead of `pressed` at all): fast, and enough to prove
# the swallow mechanism's LOGIC. CORRECTED (2026-08-27 review): this is a convenience choice,
# not a harness limitation — `test_mode_tap_model.gd`'s own header note that a real
# `InputEventMouseButton` "cannot reach `_unhandled_input`" is specifically about
# `TapRouter`'s pipeline, a DIFFERENT one than ordinary `Control`/`Button` GUI input.
# Real routed GUI input (`root.push_input(event, true)` — the `true` matters: local
# coordinates, needed under this project's content-scale `final_transform`) reaches
# `gui_input`/`button_down`/`button_up`/`pressed` in this headless harness just fine, and
# `_check_long_press_drag_off_release_via_real_routed_input_does_not_strand_the_swallow_flag()`
# below proves the drag-off-release fix against that real path, not the signal-emission
# shortcut — this is the test that would have caught the original swallow-flag bug (a
# long-press release with the pointer dragged off the button never emits Godot's own
## `pressed` signal at all, so nothing that only listens for `pressed` can ever notice).
const _PICKER_CATEGORIES: Array[String] = ["forest", "wild_grass", "house", "farm_building"]


## Style-picker refinement round: a small `PopupIndicator` glyph (vector-drawn — see
## `popup_indicator_glyph.gd`, not a `Label` glyph a Web export's bundled font might not cover)
## marks a `_PICKER_CATEGORIES` button ONLY when its catalog currently offers more than one real
## style to choose between — REVIEW FIX (2026-08-27): a category with exactly one style (Wild
## Grass, after its separate, already-approved revert back to a single `model_scenes` entry)
## must NOT show it, since a long-press there would open a one-row popup, already highlighted as
## current, that changes nothing — an indicator promising a choice that does not exist. Checked
## dynamically against `style_ids_for_category()`'s own current answer, not a hardcoded
## "wild_grass is the exception" special case, so this stays correct if the catalog ever changes
## again. No other button (the non-picker terrain buttons, Info, Erase) ever shows it.
func _check_popup_indicator_exists_only_on_multi_style_picker_buttons() -> void:
	for category: String in _PICKER_CATEGORIES:
		var button: Button = _hud.palette_button_for(category)
		if not check(button != null, "%s has a palette button" % category):
			continue
		var style_count: int = _world.style_ids_for_category(category).size()
		var expects_indicator: bool = style_count > 1
		var has_indicator: bool = button.get_node_or_null("PopupIndicator") != null
		check_eq(has_indicator, expects_indicator,
			"%s: has %d style(s) — indicator should be %s"
				% [category, style_count, "shown" if expects_indicator else "hidden"])

	# The specific regression this fix closes, spelled out rather than only implied by the loop
	# above: Wild Grass, today, has exactly one style and must not show the indicator.
	var wild_grass_button: Button = _hud.palette_button_for("wild_grass")
	if check(wild_grass_button != null, "wild_grass has a palette button"):
		check_eq(_world.style_ids_for_category("wild_grass").size(), 1,
			"setup: wild_grass currently has exactly one style (post-revert)")
		check(wild_grass_button.get_node_or_null("PopupIndicator") == null,
			"wild_grass: no popup indicator — its one-row popup would be a dead end")

	# The other 3 categories are expected to still have real choice today; spelled out the same
	# way so a future content change that drops one of THEM to a single style is caught here too,
	# not just silently accepted by the generic loop above.
	for category: String in ["forest", "house", "farm_building"]:
		var button: Button = _hud.palette_button_for(category)
		if check(button != null, "%s has a palette button" % category):
			check(_world.style_ids_for_category(category).size() > 1,
				"setup: %s currently has more than one style" % category)
			check(button.get_node_or_null("PopupIndicator") != null,
				"%s: shows the popup indicator — a real choice exists" % category)

	var look_button: Button = _hud.get_node_or_null("%InspectButton") as Button
	if check(look_button != null, "the Info button exists"):
		check(look_button.get_node_or_null("PopupIndicator") == null,
			"Info: no popup indicator — it has no long-press popup")

	var remove_button: Button = _hud.get_node_or_null("%RemoveButton") as Button
	if check(remove_button != null, "the Erase button exists"):
		check(remove_button.get_node_or_null("PopupIndicator") == null,
			"Erase: no popup indicator — it has no long-press popup")

	_hud.set_mode(GameHud.Mode.TERRAFORM)
	for id: String in _hud.palette_option_ids():
		if id in _PICKER_CATEGORIES:
			continue
		var terrain_button: Button = _hud.palette_button_for(id)
		if check(terrain_button != null, "the non-picker terrain '%s' has a palette button" % id):
			check(terrain_button.get_node_or_null("PopupIndicator") == null,
				"%s: no popup indicator — it has no style picker" % id)


## THE REGRESSION BAR (Task 7's own words): a `button_up` before the long-press threshold
## behaves identically to today for all 4 picker categories — no popup, normal paint/place.
func _check_quick_tap_on_picker_buttons_is_unaffected_by_long_press_wiring() -> void:
	for category: String in _PICKER_CATEGORIES:
		var button: Button = _hud.palette_button_for(category)
		if not check(button != null, "%s has a palette button" % category):
			continue
		_hud.set_mode(GameHud.Mode.INSPECT)
		button.button_down.emit()
		button.button_up.emit()
		button.pressed.emit()
		check(not _hud.is_style_picker_open(),
			"%s: a quick tap (button_up before the threshold) never opens the style picker"
				% category)
		if category == "forest" or category == "wild_grass":
			check_eq(_hud.mode(), GameHud.Mode.TERRAFORM,
				"%s: quick tap still enters TERRAFORM implicitly, exactly as before this task"
					% category)
			check_eq(_hud.selected_terrain_id(), category,
				"%s: quick tap still selects the terrain brush" % category)
		else:
			check_eq(_hud.mode(), GameHud.Mode.BUILD,
				"%s: quick tap still enters BUILD implicitly, exactly as before this task"
					% category)
			var expected_id: String = (
				category if category == "house" else _world.get_style_default("farm_building")
			)
			check_eq(_hud.selected_placeable_id(), expected_id,
				"%s: quick tap still resolves/selects the placeable brush" % category)


## A `button_up` after the threshold opens the popup and does NOT also paint/place. Covers the
## IN-PLACE release case (`pressed` fires, then `button_up` — measured order, corrected
## 2026-08-27 review); the DRAG-OFF release case (no `pressed` at all) has its own dedicated,
## real-routed-input regression test further down this file — see
## `_check_long_press_drag_off_release_via_real_routed_input_does_not_strand_the_swallow_flag()`.
func _check_long_press_opens_style_picker_and_swallows_the_release() -> void:
	for category: String in _PICKER_CATEGORIES:
		var button: Button = _hud.palette_button_for(category)
		if not check(button != null, "%s has a palette button" % category):
			continue
		_hud.set_mode(GameHud.Mode.INSPECT)
		var mode_before: GameHud.Mode = _hud.mode()
		var terrain_before: String = _hud.selected_terrain_id()
		var placeable_before: String = _hud.selected_placeable_id()

		button.button_down.emit()
		_hud.simulate_long_press(category)
		check(_hud.is_style_picker_open(),
			"%s: holding past the threshold opens the style picker" % category)
		check_eq(_hud.style_picker().category(), category,
			"%s: ...for the button's own category" % category)

		# The eventual in-place release still fires `pressed` BEFORE `button_up` — measured
		# against the real engine (fix round, 2026-08-27 review), corrected here from this
		# test's own earlier wrong-order assumption — and both must leave no side effect.
		button.pressed.emit()
		button.button_up.emit()
		check_eq(_hud.mode(), mode_before,
			"%s: the swallowed release does not change mode" % category)
		check_eq(_hud.selected_terrain_id(), terrain_before,
			"%s: ...nor the terrain brush" % category)
		check_eq(_hud.selected_placeable_id(), placeable_before,
			"%s: ...nor the placeable brush — no paint, no place, on a long press" % category)

		_hud.style_picker().close()


## RENAMED (was `_check_style_picker_lists_every_style_except_current_with_correct_labels`) —
## refinement round, 2026-08-27: the popup now lists EVERY style id `style_ids_for_category()`
## reports, INCLUDING the current `get_style_default()` answer, with that one row visually
## highlighted (`UiPalette.paint_button(..., true)` — the same green-selected mechanism used
## everywhere else in this HUD) rather than omitted. Label rule per category is unchanged
## (Task 7, Step 3): Forest/Wild Grass/House humanize the id, Farm Building uses the resolved
## `PlaceableDefinition.display_name` verbatim.
func _check_style_picker_lists_every_style_with_current_highlighted() -> void:
	for category: String in _PICKER_CATEGORIES:
		var button: Button = _hud.palette_button_for(category)
		if not check(button != null, "%s has a palette button to anchor the popup to" % category):
			continue
		var current: String = _world.get_style_default(category)
		var expected_ids: Array[String] = []
		for id: String in _world.style_ids_for_category(category):
			expected_ids.append(id)

		_hud.open_style_picker(category, button)
		var popup: StylePickerPopup = _hud.style_picker()
		if not check(popup != null and popup.is_open(),
			"%s: open_style_picker() opens the popup directly, no long-press needed" % category):
			continue
		check_eq(popup.category(), category, "%s: the open popup reports its own category" % category)
		check_eq(popup.row_count(), expected_ids.size(),
			"%s: lists EVERY style id, including the current default (%d expected)"
				% [category, expected_ids.size()])

		var found_current: bool = false
		for i in mini(popup.row_count(), expected_ids.size()):
			var style_id: String = expected_ids[i]
			check_eq(popup.row_style_id(i), style_id,
				"%s row %d: id matches style_ids_for_category()'s own order" % [category, i])
			var expected_label: String = _expected_style_label(category, style_id)
			check_eq(popup.row_label(i), expected_label,
				"%s row %d: label follows the category's own rule" % [category, i])

			var row_button: Button = popup._rows[i]["button"] as Button
			var highlighted: bool = _row_looks_selected(row_button)
			if style_id == current:
				found_current = true
				check(highlighted,
					"%s row %d (%s): the CURRENT default's row is highlighted green" % [
						category, i, style_id
					])
			else:
				check(not highlighted,
					"%s row %d (%s): a non-current row is NOT highlighted" % [category, i, style_id])
		check(found_current,
			"%s: the current default (%s) appears as one of the listed rows" % [category, current])

		popup.close()


## Whatever `UiPalette.paint_button(button, true)` actually sets, checked the same way this
## codebase already reads that mechanism (`paint_button()`'s own doc comment: "selection is
## carried by fill colour plus font colour") — the row's `normal` stylebox fill is `LEAF`
## (`CREAM` when unselected), so this is the exact same signal the HUD's own palette buttons
## are painted with, not a new, popup-only notion of "selected".
func _row_looks_selected(button: Button) -> bool:
	var style: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
	return style != null and style.bg_color == UiPalette.LEAF


func _expected_style_label(category: String, style_id: String) -> String:
	if category == "farm_building":
		for placeable: PlaceableDefinition in _world.placeable_options():
			if placeable.id == style_id:
				return placeable.display_name
		return style_id
	return style_id.capitalize()


## Selecting a row updates `get_style_default()`'s return value, closes the popup, and
## repaints the button's chrome immediately — proved against Farm Building (the one category
## whose button chrome, unlike Forest/Wild Grass's fixed `TileIcon.Kind`, actually renders
## differently per member: `refresh_palette_button()` is placeable-only by design, see its own
## doc comment). Forest/Wild Grass are still checked for the `get_style_default()` write
## itself — see the note left in this file's own header for what that leaves untested.
func _check_style_picker_selection_updates_default_and_button_chrome() -> void:
	var farm_building_ids: Array[String] = _farm_building_ids()
	var current: String = _world.get_style_default("farm_building")
	var other: String = ""
	for id: String in farm_building_ids:
		if id != current:
			other = id
			break
	if not check(other != "", "a different farm-building member exists to switch the default to"):
		return

	_hud.open_style_picker("farm_building", _hud.palette_button_for("farm_building"))
	var popup: StylePickerPopup = _hud.style_picker()
	var index: int = -1
	for i in popup.row_count():
		if popup.row_style_id(i) == other:
			index = i
			break
	if not check(index >= 0, "the target member appears as a row"):
		popup.close()
		return

	popup.select_row(index)
	check(not popup.is_open(), "selecting a row closes the popup")
	check_eq(_world.get_style_default("farm_building"), other,
		"selecting a row updates get_style_default()'s return value")

	var button: Button = _hud.palette_button_for("farm_building")
	var expected_name: String = ""
	for placeable: PlaceableDefinition in _world.placeable_options():
		if placeable.id == other:
			expected_name = placeable.display_name
	check_eq(button.tooltip_text, expected_name,
		"...and the button's rendered chrome (tooltip/name label) updates immediately, with "
		+ "no full palette rebuild")

	# Forest: the write itself, proved the same way — this category's button chrome (a fixed
	# TileIcon.Kind, a tooltip that is the terrain's own display_name) does not vary per style
	# id at all, so there is nothing else to observe changing on screen; see this check's own
	# header note.
	var forest_ids: PackedStringArray = _world.style_ids_for_category("forest")
	var forest_current: String = _world.get_style_default("forest")
	var forest_other: String = ""
	for id: String in forest_ids:
		if id != forest_current:
			forest_other = id
			break
	if check(forest_other != "", "a different forest variant exists to switch the default to"):
		_hud.open_style_picker("forest", _hud.palette_button_for("forest"))
		var forest_popup: StylePickerPopup = _hud.style_picker()
		var forest_index: int = -1
		for i in forest_popup.row_count():
			if forest_popup.row_style_id(i) == forest_other:
				forest_index = i
				break
		if check(forest_index >= 0, "the target forest variant appears as a row"):
			forest_popup.select_row(forest_index)
			check_eq(_world.get_style_default("forest"), forest_other,
				"forest: selecting a row updates get_style_default()'s return value too")
		forest_popup.close()


## Refinement round: picking ANY popup row, on ALL 4 categories, immediately becomes the live
## selection — `GameHud.mode()` and `selected_terrain_id()`/`selected_placeable_id()`, exactly
## what `TapRouter` would read on the very next tap/placement — not just a `get_style_default()`
## write nobody acts on until some later ordinary tap. Forest/Wild Grass: the terrain id itself
## IS the category (styles are visual variants of one terrain, not separate terrain ids — see
## `_PICKER_CATEGORIES`'s own header), so picking any style there switches to TERRAFORM with that
## terrain already the active brush. House/Farm Building: switches to BUILD with the resolved
## placeable already the active selection.
func _check_style_picker_selection_immediately_activates_the_choice() -> void:
	for category: String in ["forest", "wild_grass"]:
		var button: Button = _hud.palette_button_for(category)
		if not check(button != null, "%s has a palette button" % category):
			continue
		_hud.set_mode(GameHud.Mode.INSPECT)
		var ids: PackedStringArray = _world.style_ids_for_category(category)
		if not check(ids.size() > 0, "%s has at least one style" % category):
			continue
		var target: String = ids[0]

		_hud.open_style_picker(category, button)
		var popup: StylePickerPopup = _hud.style_picker()
		var index: int = -1
		for i in popup.row_count():
			if popup.row_style_id(i) == target:
				index = i
				break
		if not check(index >= 0, "%s: the target style appears as a row" % category):
			popup.close()
			continue

		popup.select_row(index)
		check_eq(_world.get_style_default(category), target,
			"%s: the style default is written" % category)
		check_eq(_hud.mode(), GameHud.Mode.TERRAFORM,
			"%s: picking a popup row switches to TERRAFORM immediately" % category)
		check_eq(_hud.selected_terrain_id(), category,
			"%s: ...with the terrain itself as the active brush, ready to paint immediately"
				% category)

	for category: String in ["house", "farm_building"]:
		var button: Button = _hud.palette_button_for(category)
		if not check(button != null, "%s has a palette button" % category):
			continue
		_hud.set_mode(GameHud.Mode.INSPECT)
		var ids: PackedStringArray = _world.style_ids_for_category(category)
		var current: String = _world.get_style_default(category)
		var target: String = ""
		for id: String in ids:
			if id != current:
				target = id
				break
		if not check(target != "", "%s: a different style exists to switch to" % category):
			continue

		_hud.open_style_picker(category, button)
		var popup: StylePickerPopup = _hud.style_picker()
		var index: int = -1
		for i in popup.row_count():
			if popup.row_style_id(i) == target:
				index = i
				break
		if not check(index >= 0, "%s: the target style appears as a row" % category):
			popup.close()
			continue

		popup.select_row(index)
		check_eq(_world.get_style_default(category), target,
			"%s: the style default is written" % category)
		check_eq(_hud.mode(), GameHud.Mode.BUILD,
			"%s: picking a popup row switches to BUILD immediately" % category)
		# House is a single-member group whose style id is a scene-derived slug, never a
		# placeable id — its own placeable id ("house") is what must be selected, unchanged
		# across styles. Farm Building resolves to the freshly-picked real member id.
		var expected_selection: String = category if category == "house" else target
		check_eq(_hud.selected_placeable_id(), expected_selection,
			"%s: ...with the resolved placeable as the active selection, ready to place immediately"
				% category)


## Re-picking the row that was ALREADY the current default (no `style_defaults` value actually
## changes) must still correctly select+activate it — Change 3's own edge case, called out
## explicitly rather than special-cased away: `activate_palette_entry()` already handles "was
## already selected" uniformly with "wasn't selected", so this proves that path with no crash
## and no stale/double state left behind.
func _check_style_picker_reselecting_current_still_activates_it() -> void:
	for category: String in _PICKER_CATEGORIES:
		var button: Button = _hud.palette_button_for(category)
		if not check(button != null, "%s has a palette button" % category):
			continue
		_hud.set_mode(GameHud.Mode.INSPECT)
		var current: String = _world.get_style_default(category)

		_hud.open_style_picker(category, button)
		var popup: StylePickerPopup = _hud.style_picker()
		var index: int = -1
		for i in popup.row_count():
			if popup.row_style_id(i) == current:
				index = i
				break
		if not check(index >= 0, "%s: the current default appears as a row" % category):
			popup.close()
			continue

		popup.select_row(index)
		check(not popup.is_open(),
			"%s: re-selecting the already-current row still closes the popup" % category)
		check_eq(_world.get_style_default(category), current,
			"%s: re-selecting the current default is a no-op write" % category)

		if category == "forest" or category == "wild_grass":
			check_eq(_hud.mode(), GameHud.Mode.TERRAFORM,
				"%s: re-selecting still activates TERRAFORM" % category)
			check_eq(_hud.selected_terrain_id(), category,
				"%s: ...with the terrain correctly selected, no stale state" % category)
		else:
			check_eq(_hud.mode(), GameHud.Mode.BUILD,
				"%s: re-selecting still activates BUILD" % category)
			var expected_selection: String = category if category == "house" else current
			check_eq(_hud.selected_placeable_id(), expected_selection,
				"%s: ...with the correct member correctly selected, no weird double-state"
					% category)


## CROSS-TASK REGRESSION (2026-08-27, final whole-branch review — reproduced live before the
## fix). Task 6 caches a grouped button's resolved member id in `_selected_placeable_id` at TAP
## time; Task 7 changes that group's default WITHOUT a tap (a long-press's `pressed` is
## swallowed by design). Before the fix the two diverged silently: with Farm Building already
## selected, picking a different member repainted the button but left the OLD member selected,
## so the next tap on the world placed the building the player had just switched away from —
## button chrome and actual placement disagreeing, with nothing on screen saying so.
##
## Asserted against what `WorldRoot.place_building()` genuinely puts on the tile, not just
## against `selected_placeable_id()`, for the same reason
## `_check_farm_building_button_resolves_to_the_current_style_default()` does it that way.
##
## The House half is the other side of the same guard: House is a SINGLE-member group whose
## style ids are scene-derived slugs, never placeable ids, so changing its style must leave
## `_selected_placeable_id` alone — assigning "house_tower_firstage" there would break placement
## outright.
func _check_changing_a_group_default_retargets_the_live_selection() -> void:
	_hud.activate_palette_entry("placeable", "farm_building")
	var before: String = _hud.selected_placeable_id()
	if not check(before != "" and before != "farm_building",
		"setup: tapping the Farm Building button selects a real member id"):
		return

	var other: String = ""
	for id: String in _farm_building_ids():
		if id != before:
			other = id
			break
	if not check(other != "", "setup: a different farm-building member exists"):
		return

	_hud.open_style_picker("farm_building", _hud.palette_button_for("farm_building"))
	var popup: StylePickerPopup = _hud.style_picker()
	var index: int = -1
	for i in popup.row_count():
		if popup.row_style_id(i) == other:
			index = i
			break
	if not check(index >= 0, "the target member appears as a row"):
		popup.close()
		return
	popup.select_row(index)

	check_eq(_hud.selected_placeable_id(), other,
		"changing the Farm Building default RETARGETS the live selection — the button's chrome "
		+ "and what the next tap places can never disagree")

	# What actually lands on the tile, not just what the HUD says it would. Paint a 2x2 block
	# first, for the same reason the sibling check above does — Barn's footprint is 2x2 and
	# `place_building()` requires every footprint tile to already be eligible terrain.
	var tile := Vector2i(25, 25)
	for dx in range(2):
		for dz in range(2):
			_world.paint_tile(tile.x + dx, tile.y + dz, "grass")
	# Top up Wood before this placement: this check runs late in a long, growing suite that
	# has already spent Wood on earlier real placements (e.g.
	# `_check_farm_building_button_resolves_to_the_current_style_default`'s own Barn), and
	# WHICH farm-building id ends up as `other` here is itself derived from whatever the
	# CURRENT default happens to be when this check runs — order-dependent by design, not a
	# thing this check should be pinning down. Affordability is not what this check is about
	# (`can_place()`'s wood gate is `BuildingPlacement`'s own, separately covered concern);
	# it is about eligibility + selection resolving correctly, so wood is made a non-factor.
	if _world.wood != null:
		_world.wood.add(100)
	if check(_world.place_building(tile.x, tile.y, _hud.selected_placeable_id()),
		"the retargeted selection is genuinely placeable"):
		var def: PlaceableDefinition = _world.grid.get_building(tile.x, tile.y)
		check(def != null and def.id == other,
			"...and the building that actually landed on the tile is the NEWLY chosen member, "
			+ "not the one selected before the picker was used")

	# House: a single-member group's scene-derived style id must NEVER reach the selection.
	_hud.activate_palette_entry("placeable", "house")
	var house_ids: PackedStringArray = _world.style_ids_for_category("house")
	var house_current: String = _world.get_style_default("house")
	var house_other: String = ""
	for id: String in house_ids:
		if id != house_current:
			house_other = id
			break
	if check(house_other != "", "setup: a different house variant exists"):
		_hud.open_style_picker("house", _hud.palette_button_for("house"))
		var house_popup: StylePickerPopup = _hud.style_picker()
		var house_index: int = -1
		for i in house_popup.row_count():
			if house_popup.row_style_id(i) == house_other:
				house_index = i
				break
		if check(house_index >= 0, "the target house variant appears as a row"):
			house_popup.select_row(house_index)
			check_eq(_hud.selected_placeable_id(), "house",
				"changing HOUSE's style leaves the selection on the real placeable id — a "
				+ "scene-derived slug must never reach _selected_placeable_id")
		house_popup.close()


## "Tapping outside the popup's rect closes it with no change" (Task 7, Step 4) — and the
## outside tap must not ALSO reach the button underneath (`accept_event()` inside
## `_on_outside_catcher_gui_input()`), proved structurally the same way
## `test_mode_tap_model.gd` already proves `FactCard`/`MenuWindow`'s own scrims never leak a
## tap: the catcher covering the popup's full rect is `MOUSE_FILTER_STOP`, not a Button, so
## Godot's own input routing (topmost STOP-filter Control wins) is what does the consuming —
## nothing here has to race a real click against the button below it.
func _check_style_picker_outside_tap_dismisses_with_no_change_and_does_not_leak_through() -> void:
	var before_mode: GameHud.Mode = _hud.mode()
	var before_terrain: String = _hud.selected_terrain_id()
	var before: String = _world.get_style_default("wild_grass")

	_hud.open_style_picker("wild_grass", _hud.palette_button_for("wild_grass"))
	var popup: StylePickerPopup = _hud.style_picker()
	if not check(popup != null and popup.is_open(), "wild_grass: opens for the outside-tap check"):
		return

	var catcher: Control = popup.find_child("OutsideCatcher", true, false) as Control
	if check(catcher != null, "the popup has its outside-tap catcher"):
		check_eq(catcher.mouse_filter, Control.MOUSE_FILTER_STOP,
			"...MOUSE_FILTER_STOP — it, not a bare tap, is what consumes an outside click, "
			+ "the same convention FactCard's/MenuWindow's own scrim already uses")

	popup.simulate_outside_tap()
	check(not popup.is_open(), "an outside tap closes the popup")
	check_eq(_world.get_style_default("wild_grass"), before,
		"...with NO change to the style default")
	check_eq(_hud.mode(), before_mode,
		"...and no change to the HUD's mode either — an outside tap is consumed, not a "
		+ "second gesture on whatever is underneath")
	check_eq(_hud.selected_terrain_id(), before_terrain,
		"...nor to the selected terrain brush")


## IMPORTANT FIX REGRESSION TEST (2026-08-27 review finding #2). `Control.size` only ever
## grows to match a larger minimum size — it does not shrink back down on its own when the
## minimum later gets smaller. Reproduced against the real numbers this review measured: House
## (9 rows) sizes the popup to its clamped max (~360px tall); opening Wild Grass (2 rows)
## afterward, without `_panel.reset_size()`, left the panel stuck at House's larger size —
## misplaced and running off-screen. Proves the fix directly against `Panel`'s own `.size`,
## not just its (unaffected) minimum size.
func _check_style_picker_panel_shrinks_back_down_after_a_longer_list() -> void:
	_hud.open_style_picker("house", _hud.palette_button_for("house"))
	var popup: StylePickerPopup = _hud.style_picker()
	if not check(popup != null and popup.is_open(), "house: opens for the panel-size check"):
		return
	var panel: Control = popup.find_child("Panel", true, false) as Control
	if not check(panel != null, "the popup has its Panel node"):
		popup.close()
		return
	var long_list_height: float = panel.size.y
	popup.close()

	_hud.open_style_picker("wild_grass", _hud.palette_button_for("wild_grass"))
	var short_list_height: float = panel.size.y
	check(short_list_height < long_list_height,
		"the panel shrinks back down for Wild Grass's short list after showing House's long "
		+ "one, instead of staying stuck at the longer list's size",
		"long(house)=%.1f short(wild_grass)=%.1f" % [long_list_height, short_list_height])
	popup.close()


# --- Fix round (2026-08-27 review): real routed input, not signal shortcuts ----------------

func _routed_mouse_button_event(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = pos
	event.global_position = pos
	return event


func _routed_mouse_motion_event(pos: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = pos
	event.global_position = pos
	return event


## CRITICAL FIX REGRESSION TEST (2026-08-27 review finding #1). A long-press's release is not
## always in-place — the popup opens directly above the triggering button, so sliding toward
## it and lifting is an entirely ordinary motion, and that is a DRAG-OFF release. Godot's own
## `Button` does not emit `pressed` at all for a drag-off release (measured against the real
## engine, not assumed), so the only honest way to prove the fix (`_on_picker_button_up()` now
## unconditionally erasing `_swallow_next_press[id]`) is to route a REAL press, a REAL motion
## off the button's rect, and a REAL release through `root.push_input(event, true)` — not
## `button.button_up.emit()`, which cannot exercise Godot's own `pressing_inside` bookkeeping
## at all, and is exactly why the original bug shipped past every earlier signal-driven check
## in this file. The long-press RECOGNITION itself still uses `simulate_long_press()` (this
## test's job is the release path, not re-proving the Timer fires on its own — see
## `_check_wild_grass_long_press_timer_fires_after_real_elapsed_time()` for that).
func _check_long_press_drag_off_release_via_real_routed_input_does_not_strand_the_swallow_flag() -> void:
	var category: String = "forest"
	var button: Button = _hud.palette_button_for(category)
	if not check(button != null, "%s has a palette button for the real-routed-input check"
		% category):
		return
	_hud.set_mode(GameHud.Mode.INSPECT)

	var rect: Rect2 = button.get_global_rect()
	var press_pos: Vector2 = rect.get_center()
	var away_pos: Vector2 = press_pos + Vector2(0, -maxf(rect.size.y * 4.0, 200.0))

	root.push_input(_routed_mouse_button_event(press_pos, true), true)
	_hud.simulate_long_press(category)
	if not check(_hud.is_style_picker_open(),
		"%s: a real routed press, held past the threshold, opens the style picker" % category):
		return

	# THE FIX UNDER TEST: drag off the button, THEN release — both routed for real.
	root.push_input(_routed_mouse_motion_event(away_pos), true)
	root.push_input(_routed_mouse_button_event(away_pos, false), true)

	if _hud.style_picker() != null:
		_hud.style_picker().close()

	# THE REGRESSION ITSELF: without the fix, `_swallow_next_press[category]` stayed `true`
	# forever after a drag-off release, and the VERY NEXT ordinary tap on this same button was
	# silently eaten — no popup, no paint, no feedback of any kind.
	root.push_input(_routed_mouse_button_event(press_pos, true), true)
	root.push_input(_routed_mouse_button_event(press_pos, false), true)
	check_eq(_hud.mode(), GameHud.Mode.TERRAFORM,
		(
			"%s: the tap immediately after a drag-off long-press release still enters "
			+ "TERRAFORM — it was NOT silently eaten"
		) % category)
	check_eq(_hud.selected_terrain_id(), category,
		"%s: ...and still selects the terrain brush, exactly like an untouched button" % category)


## REVIEW FINDING #3 (2026-08-27). Every other long-press check in this file (including the one
## directly above) reaches the "long press recognised" state via `simulate_long_press()` — a
## direct call to the timeout handler, not a real elapsed wait. That proves the HANDLER's logic
## but never proves the `Timer` itself (`one_shot`, `wait_time = LONG_PRESS_SECONDS`, the
## `timeout` connection in `_wire_long_press()`) is wired correctly enough to fire on its own.
## This check waits out a REAL `LONG_PRESS_SECONDS` via actual elapsed `_process()` frames — see
## `_process()`'s own real-time-wait phase below — driven by `_begin_real_long_press_timer_wait()`
## / `_finish_real_long_press_timer_wait()`, the only two functions this check is split across.
var _pending_real_long_press: bool = false
var _real_long_press_elapsed: float = 0.0
var _real_long_press_deadline: float = 0.0
const _REAL_LONG_PRESS_CATEGORY: String = "wild_grass"


## Returns `true` if `_process()` should now wait for the real Timer (`_pending_real_long_press`
## is set); `false` if setup failed and `finish()` has already been called directly — either
## way `_process()`'s caller knows exactly what to do next, so a lookup failure here can never
## leave the wait loop or the "run every check again" fallthrough in an inconsistent state.
func _begin_real_long_press_timer_wait() -> bool:
	var button: Button = _hud.palette_button_for(_REAL_LONG_PRESS_CATEGORY)
	if not check(button != null, "%s has a palette button for the real-timer-wait check"
		% _REAL_LONG_PRESS_CATEGORY):
		finish()
		return false
	_hud.set_mode(GameHud.Mode.INSPECT)
	button.button_down.emit()
	check(not _hud.is_style_picker_open(),
		"%s: the popup is not open the instant the press begins" % _REAL_LONG_PRESS_CATEGORY)
	# A margin over the real threshold, not the threshold itself — this is proving the Timer
	# actually fires ON ITS OWN, so it must be allowed strictly more real time than
	# LONG_PRESS_SECONDS to do it in.
	_real_long_press_deadline = GameHud.LONG_PRESS_SECONDS + 0.25
	_real_long_press_elapsed = 0.0
	_pending_real_long_press = true
	return true


func _finish_real_long_press_timer_wait() -> void:
	check(_hud.is_style_picker_open(),
		(
			"%s: after really waiting out %.2fs (not simulated), the real Timer fired on its "
			+ "own and opened the style picker"
		) % [_REAL_LONG_PRESS_CATEGORY, GameHud.LONG_PRESS_SECONDS])
	var popup: StylePickerPopup = _hud.style_picker()
	if popup != null and popup.is_open():
		check_eq(popup.category(), _REAL_LONG_PRESS_CATEGORY, "...for the right category")
		popup.close()
	var button: Button = _hud.palette_button_for(_REAL_LONG_PRESS_CATEGORY)
	if button != null:
		button.button_up.emit()
