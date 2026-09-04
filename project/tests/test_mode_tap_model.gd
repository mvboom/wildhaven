extends QATestCase
## PILLAR 3, SHIPPED WHOLE — the three-mode tap model, Tier 1 row 2's other half.
##
## gdd.md -> Player Interface & Controls: "One unified tap-based system underlies every
## interaction — a 6–10 year old only ever learns **'pick a mode (or none), then tap.'**"
## spec.md lists the three-mode tap model under "not depth axes", so this is an invariant,
## not tuning.
##
## THE PRIORITY RULE IS THE LOAD-BEARING ONE. gdd.md: "an animal standing on a tappable tile
## always wins the tap — generous animal hitboxes beat ambiguous taps for young kids." It is
## asserted **in all three modes**, and in Terraform and Build the tap is set up to be one
## that WOULD have succeeded — otherwise "nothing happened" would prove nothing.
##
## **AND IT IS ASSERTED AGAINST A RESIDENT THAT HAS MOVED.** Residents wander (row 6), so the
## rule is only true if the hitbox travels with the animal. The resident here is registered
## through the real `HomeSiteRegistry`, tapped, then walked to another tile inside its home
## radius and tapped again — at its new position, which must hit, and at its old one, which
## must not. That second assertion is the one that would have caught the deleted
## `ResidentIndex`, whose list was built from arrival-time positions.
##
## THE LIVE NEIGHBORHOOD PREVIEW (row 6's third thin-form clause) is exercised through
## `TapRouter.refresh_preview()` — the same function the cursor poll drives: qualitative bands
## only, never shown in Inspect, and its per-read cost measured against `NeighborhoodPreview`'s
## own query log rather than assumed.
##
## REFUSALS ARE SILENT. An ineligible Build target produces a `TapCue.soft()` ring and
## nothing else: no error, no message, no penalty, no blocked state (Pillar 1).
##
## Taps are driven through `TapRouter.handle_tap(screen_position)` — the same function the
## mouse drives — with the screen position obtained by projecting a known tile through the
## live camera, so the whole camera/ray/collider chain is exercised rather than stubbed.
##
## THE CAMERA (D-41, fixed pan/zoom, no first-person). Most taps in this file target a tile
## roughly in front of wherever `CameraRig.initialize()`'s default placement (the world bounds'
## centre, at default zoom) happens to face, and `_tap()`'s own comment explains why that is
## sufficient: projecting a tile then raycasting the same screen point back through the same
## camera is self-consistent regardless of where on screen it lands, as long as the point is not
## BEHIND the camera. Checks whose target falls outside that default framing — a resident to
## test the priority rule against, or the neighbourhood-preview cursor — call `_aim_camera_at()`
## first instead: re-focus/re-zoom the camera onto the target, "focus-and-tap" (D-41), the same
## fixture pattern `test_resident_lookup.gd` and `test_fact_card.gd` use. (This replaces D-33's
## first-person "look-and-press": park the `Player`, `look_at()` the target — no `Player` exists
## any more.)
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_mode_tap_model.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

## Controls that block the mouse without being pressable, and are KNOWN to do so. This is a
## defect list, not an allow-list: every entry is reported as a `note_expected_pending()` below
## and is meant to shrink to nothing. A blocking panel that is NOT on this list fails the suite
## the day it is added, which is the point.
## EMPTY as of 2026-07-28. `WoodPanel` was the last entry — fixed by setting `mouse_filter = 2`
## on `HUD/WoodPanel` in `scenes/ui/GameUI.tscn`, the same repair `HUD/TileReadout` had already
## received. The list has done its job; keep it here so the next blocker still fails the suite.
const KNOWN_BLOCKING_PANELS: Array[String] = []

var _world: WorldRoot = null
var _ui: GameUI = null
var _hud: GameHud = null
var _router: TapRouter = null
var _card: FactCard = null
var _cue: TapCue = null
var _camera: Camera3D = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("three-mode tap model")

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


func _process(_delta: float) -> bool:
	if not _setup_ok:
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
	_router = _ui.tap_router
	_card = _ui.fact_card
	_cue = _ui.tap_cue
	_camera = root.get_viewport().get_camera_3d()
	(_camera as CameraRig).initialize()

	if not check(_ui.world() == _world, "the UI bound itself to the live world"):
		finish()
		return true

	_check_modes_exist_and_default_to_inspect()
	_check_palettes_are_data_driven()
	_check_terraform_tap_paints()
	_check_build_tap_places()
	_check_inspect_tap_does_neither()
	_check_inspect_names_the_building_on_the_tile()
	_check_ineligible_build_refuses_silently()
	_check_priority_rule_in_all_three_modes()
	_check_off_world_tap_is_not_a_refusal()
	_check_hud_panels_do_not_swallow_gameplay_taps()
	_check_live_neighborhood_preview()

	note_expected_pending(
		"`terrain_options()` INCLUDES `wild_grass`, so the player can paint it (reported defect)",
		"Wild grass is what the MIST reveals (row 13) and its whole job is being tag-inert. "
		+ "Putting it in the Terraform palette hands the player a brush that un-makes habitat "
		+ "with no cue that it differs from grass. The palette is data-driven and correct; the "
		+ "gap is that `WorldRoot.terrain_options()` has no notion of a non-paintable terrain. "
		+ "Self-reported by the UI dispatch; recorded here so it cannot be forgotten."
	)
	note_expected_pending(
		"TAP-TO-TEND is absent from Inspect and that is correct (row-5 depth)",
		"gdd.md row 2: \"Inspect's taps thin except tap-to-tend\" — the floor ships without it."
	)
	note_expected_pending(
		"THE CONTROL LAYER IS ONLY CHECKED STRUCTURALLY — a harness limit, recorded not hidden",
		"`TapRouter` takes input in `_unhandled_input`, so the end-to-end path is "
		+ "mouse -> Viewport -> every Control's turn -> `_unhandled_input` -> `handle_tap()`. "
		+ "MEASURED IN THIS HARNESS: neither `Viewport.push_input()` nor "
		+ "`Input.parse_input_event()` + `flush_buffered_events()` delivers anything to "
		+ "`_unhandled_input` under `--headless --script`, on the pushing frame or on any of the "
		+ "three frames after, with `is_processing_unhandled_input()` true the whole time. So "
		+ "every tap in this suite enters at `handle_tap()`, one step PAST the Control layer, and "
		+ "the mouse-filter invariant above is asserted on the node properties instead. A Control "
		+ "that blocked taps some other way (a full-screen `Panel` added with a script that "
		+ "consumes `_gui_input`) would not be caught here. That is a human check on a real "
		+ "build, and it is how the readout defect was found in the first place."
	)
	note_expected_pending(
		"HARVEST is listed as a fourth tap action in gdd.md's input table but has no mode",
		"\"Left-click | Every tap action (Inspect / Terraform / Build / Harvest)\". Harvest is "
		+ "tap-to-tend inside Inspect, not a fourth mode, so the three-mode model is intact — "
		+ "recorded because the table reads as four."
	)

	finish()
	return true


# --- The three modes -------------------------------------------------------------------------

func _check_modes_exist_and_default_to_inspect() -> void:
	check_eq(GameHud.Mode.size(), 3, "there are exactly three modes — no fourth control")
	check_eq(_hud.mode(), GameHud.Mode.INSPECT,
		"Inspect is the default — the \"or none\" in \"pick a mode (or none), then tap\"")


func _check_palettes_are_data_driven() -> void:
	# Nothing in the HUD knows a terrain's name or how many there are: the palette is exactly
	# what `WorldRoot` reports, which is what makes "adding content is a .tres" true.
	var terrain_ids: Array[String] = []
	for terrain: TerrainDefinition in _world.terrain_options():
		terrain_ids.append(terrain.id)
	var placeable_ids: Array[String] = []
	for placeable: PlaceableDefinition in _world.placeable_options():
		placeable_ids.append(placeable.id)

	_hud.set_mode(GameHud.Mode.TERRAFORM)
	check_eq(_hud.palette_option_ids().size(), terrain_ids.size(),
		"the Terraform palette has exactly as many entries as `terrain_options()` (%d)"
			% terrain_ids.size())
	check_eq(_hud.palette_option_ids(), terrain_ids,
		"...and they are the same ids, in the same order — no hardcoded list")

	_hud.set_mode(GameHud.Mode.BUILD)
	check_eq(_hud.palette_option_ids().size(), placeable_ids.size(),
		"the Build palette has exactly as many entries as `placeable_options()` (%d)"
			% placeable_ids.size())
	check_eq(_hud.palette_option_ids(), placeable_ids, "...and they are the same ids")

	_hud.set_mode(GameHud.Mode.INSPECT)
	check_eq(_hud.palette_option_ids().size(), 0, "Inspect has no palette at all (spec.md)")


# --- Terraform / Build / Inspect ------------------------------------------------------------------

func _check_terraform_tap_paints() -> void:
	var tile := Vector2i(10, 10)
	_hud.set_mode(GameHud.Mode.TERRAFORM)
	check(_hud.select_palette_option("rock"), "Rock is selectable from the Terraform palette")
	check_eq(_hud.selected_terrain_id(), "rock", "...and it is the selected brush")
	# RE-POINTED (-> D-29 #1): the world now starts all-`wild_grass`, not `grass` — this check's
	# own intent (painting works regardless of the starting terrain) is unaffected either way.
	check_eq(_world.get_tile_terrain(tile.x, tile.y), "wild_grass",
		"the target tile starts as wild_grass")

	check_eq(_tap(tile), TapRouter.RESULT_PAINTED, "a Terraform tap PAINTS")
	check_eq(_world.get_tile_terrain(tile.x, tile.y), "rock", "...and the tile converted to rock")
	check(not _world.grid.is_occupied(tile.x, tile.y), "...and no building appeared")


func _check_build_tap_places() -> void:
	var tile := Vector2i(14, 14)
	# RE-POINTED (-> D-29 #1): the House's `allowed_terrain` is `["grass"]` specifically, not
	# `wild_grass` (buildings.md — a House builds on grass only). The old ambient `grass`
	# backdrop made this tile eligible for free; the new tag-inert default does not, so the
	# fixture now states the terrain it needs rather than borrowing the world's old default.
	_world.paint_tile(tile.x, tile.y, "grass")
	check_eq(_world.get_tile_terrain(tile.x, tile.y), "grass",
		"the Build target tile is explicitly grass, which the House requires")

	_hud.set_mode(GameHud.Mode.BUILD)
	check(_hud.select_palette_option("house"), "the House is selectable from the Build palette")
	check_eq(_hud.selected_placeable_id(), "house", "...and it is the selected building")

	check_eq(_tap(tile), TapRouter.RESULT_PLACED, "a Build tap PLACES")
	check(_world.grid.is_occupied(tile.x, tile.y), "...and the tile is occupied by the House")
	check_eq(_world.get_tile_terrain(tile.x, tile.y), "grass",
		"...and the ground underneath is unchanged (a building sits on terrain, it is not terrain)")


func _check_inspect_tap_does_neither() -> void:
	var tile := Vector2i(18, 6)
	_hud.set_mode(GameHud.Mode.INSPECT)
	var terrain_before: String = _world.get_tile_terrain(tile.x, tile.y)
	var wood_before: int = _world.get_wood()

	check_eq(_tap(tile), TapRouter.RESULT_INSPECT, "an Inspect tap resolves to Inspect")
	check_eq(_world.get_tile_terrain(tile.x, tile.y), terrain_before,
		"an Inspect tap PAINTS NOTHING")
	check(not _world.grid.is_occupied(tile.x, tile.y), "...and PLACES NOTHING")
	check_eq(_world.get_wood(), wood_before, "...and spends nothing")
	check(_hud.tile_readout_visible(), "...it shows the tile's readout instead")
	# RE-POINTED (-> D-29 #1): the tile's untouched default is now `wild_grass`
	# (`display_name` "Wild grass"), not `grass` — this check's intent (the readout names the
	# terrain from data, not a hardcoded string) is unaffected by which terrain it is.
	check(_hud.tile_readout_text().contains("Wild grass"),
		"...naming the terrain from data", "got %s" % _hud.tile_readout_text())


## Inspecting an OCCUPIED tile names the building, not the ground under it. Before this, the
## readout named the terrain and listed the tile's tags, so a House read as its `emitted_tags`
## entry ("house") and every farm building — none of which emit any tags — read as the no-tags
## em dash with nothing naming it at all.
func _check_inspect_names_the_building_on_the_tile() -> void:
	var tile := Vector2i(19, 6)
	_hud.set_mode(GameHud.Mode.BUILD)
	_hud.select_palette_option("house")
	check_eq(_tap(tile), TapRouter.RESULT_PLACED, "a House is standing on the tile")

	_hud.set_mode(GameHud.Mode.INSPECT)
	check_eq(_tap(tile), TapRouter.RESULT_INSPECT, "an Inspect tap on it resolves to Inspect")
	check_eq(_hud.tile_readout_text(), "House",
		"...and the readout is the building's name, and only that")

	# A farm building was the case the old two-line readout rendered as a bare em dash, back
	# when every farm building emitted no tags at all. RE-POINTED 2026-09-04 (habitat-tiers
	# Task 7): the Well now emits ["built", "water"] (the universal `built` exclusion handle
	# plus the tag it shares with natural water), so it no longer emits zero tags — but the
	# INVARIANT this test protects is unchanged and, if anything, now proven more strongly:
	# the readout names the building from its display_name regardless of whether emitted_tags
	# is empty or not. Addressed by its REAL id, not the "farm_building" group key —
	# `select_palette_option()` takes catalog ids only (a group key returns false and would
	# silently leave the House selected).
	var barn_tile := Vector2i(20, 6)
	_hud.set_mode(GameHud.Mode.BUILD)
	check(_hud.select_palette_option("well"), "the Well is selectable by its catalog id")
	check_eq(_tap(barn_tile), TapRouter.RESULT_PLACED, "a farm building is standing on a second tile")
	var placed: PlaceableDefinition = _world.grid.get_building(barn_tile.x, barn_tile.y)
	check(placed != null and not placed.display_name.is_empty(), "...and it has a display name")
	check_eq(PackedStringArray(placed.emitted_tags), PackedStringArray(["built", "water"]),
		"...and now emits [\"built\", \"water\"] (habitat-tiers), yet the readout still resolves "
		+ "to the display_name, not a tag list — the em-dash bug is about the readout logic, "
		+ "not about which buildings happen to have zero tags")

	_hud.set_mode(GameHud.Mode.INSPECT)
	check_eq(_tap(barn_tile), TapRouter.RESULT_INSPECT, "an Inspect tap on it resolves to Inspect")
	check_eq(_hud.tile_readout_text(), placed.display_name,
		"...and the readout names it from data, not a hardcoded string")

	# The bare-tile path is unchanged: no building means the terrain still names the tile.
	check_eq(_world.get_building_display_name(4, 4), "", "a bare tile reports no building")


# --- The soft "no" -----------------------------------------------------------------------------------

func _check_ineligible_build_refuses_silently() -> void:
	# A rock tile: the House's `allowed_terrain` is grass only, so this is ineligible rather
	# than unaffordable, which is the case buildings.md calls "a soft cue, never an error".
	var tile := Vector2i(10, 10)
	check_eq(_world.get_tile_terrain(tile.x, tile.y), "rock", "the target tile is rock, not grass")
	check(not _world.can_place(tile.x, tile.y, "house"), "...so the House is ineligible there")

	_hud.set_mode(GameHud.Mode.BUILD)
	_hud.select_palette_option("house")
	var wood_before: int = _world.get_wood()
	var cues_before: int = _cue.active_cues()

	# TapRouter declares two signals now (added for the onboarding coach; see the header
	# comment beside their declaration) but they are strictly success signals, emitted only
	# from the already-guarded success branches `paint_tile()` / `place_building()` return true
	# from. Connecting both here and proving neither fires below is what keeps this test's
	# original point true in spirit: a refusal still has no channel to speak through.
	var painted_fired := false
	var placed_fired := false
	_router.tile_painted.connect(func() -> void: painted_fired = true)
	_router.building_placed.connect(func() -> void: placed_fired = true)

	check_eq(_tap(tile), TapRouter.RESULT_REFUSED, "the tap is REFUSED")
	check(not _world.grid.is_occupied(tile.x, tile.y), "...nothing was placed")
	check_eq(_world.get_tile_terrain(tile.x, tile.y), "rock", "...the tile is unchanged")
	check_eq(_world.get_wood(), wood_before, "...nothing was spent")
	check(not _card.is_open(), "...no card, no modal, no message")

	# The entire "no" vocabulary is one soft ring. It fires (so the tap was received) and it is
	# the ONLY thing that fires.
	check_eq(_cue.active_cues(), cues_before + 1,
		"...exactly one soft cue was drawn — proof the tap landed, and the whole 'no' vocabulary")
	check(not painted_fired and not placed_fired,
		"...and neither success signal fired — a refusal still has no error channel to speak through")

	var router_signals: Array[String] = []
	for entry: Dictionary in _router.get_script().get_script_signal_list():
		router_signals.append(entry["name"])
	check_eq(router_signals, ["tile_painted", "building_placed"] as Array[String],
		"TapRouter declares exactly its two success signals, added for the onboarding coach")


# --- The priority rule, in all three modes ---------------------------------------------------------------

## RE-POINTED WHOLE (-> D-29 #7): the priority rule stopped being uniform across all three
## modes. gdd.md's "an animal standing on a tappable tile always wins the tap" now holds ONLY
## in Inspect; in Terraform and Build the tile action under the cursor always wins instead, and
## `TapRouter.handle_tap()` does not even run the resident query there. This rewrites the
## function's Terraform/Build halves to assert the NEW rule (rather than deleting coverage of
## the conflict D-29 #7 exists to resolve) and keeps the Inspect + wander halves, which the
## ruling does not touch, intact.
func _check_priority_rule_in_all_three_modes() -> void:
	_world.wood.reset(WoodLedger.STARTING_WOOD)
	var species: AnimalDefinition = _world.roster.by_id("rabbit")
	if not check(species != null, "the rabbit is in the roster"):
		return

	# --- INSPECT: the rule is unchanged here — the animal still wins the tap. -----------------
	var tile := Vector2i(24, 24)
	# RE-POINTED (-> D-29 #1): explicit now, not borrowed from the world's old ambient `grass`.
	_world.paint_tile(tile.x, tile.y, "grass")
	check_eq(_world.get_tile_terrain(tile.x, tile.y), "grass", "the contested tile is grass")

	# A REAL resident, registered the way a move-in registers one: a home site in the live
	# `HomeSiteRegistry` with a node hanging off it. The tap path then runs over exactly the
	# data the simulation owns — there is no UI-side list left to seed.
	var site: HomeSite = _world.registry.register(tile, "rabbit", species.scout_radius)
	var anchor: Vector3 = _world.grid_to_world(tile.x, tile.y)
	var resident := Node3D.new()
	resident.name = "PriorityRuleResident"
	resident.position = anchor
	_world.add_child(resident)
	site.residents.append(resident)

	# FOCUS-AND-TAP (D-41): re-focus/re-zoom the camera onto this tile — it falls outside the
	# default framing `CameraRig.initialize()` starts with, so without this the resident (and the
	# tile itself, for the wander half below) would project to a point the camera's own
	# `is_position_behind()` guard discards.
	_aim_camera_at(anchor + Vector3(0.0, ResidentPicker.BODY_CENTRE_HEIGHT, 0.0))
	var screen: Vector2 = _camera.unproject_position(
		anchor + Vector3(0.0, ResidentPicker.BODY_CENTRE_HEIGHT, 0.0)
	)
	check(not _world.resident_record_at(screen).is_empty(),
		"`WorldRoot.resident_record_at()` resolves the resident at that screen point")

	_hud.set_mode(GameHud.Mode.INSPECT)
	check_eq(_router.handle_tap(screen), TapRouter.RESULT_RESIDENT,
		"PRIORITY RULE in Inspect: the animal wins the tap (this is the replay path)")
	# REPOINTED (Task 5, notification-surfaces): the replay routes to the feed now, never the
	# big card — see `test_fact_card.gd`'s `_check_tap_to_replay_in_inspect()` for the same
	# pattern.
	check(not _card.is_open(), "...and the card does NOT replay — the tap routes to the feed instead")
	var feed: NotificationFeed = _ui.notification_feed
	check_eq(feed.entry_texts()[0], "%s. %s" % [species.display_name, species.effective_fact_text()],
		"...the feed gains the replay entry instead, with the same verbatim copy")

	# --- THE WANDER HALF: the hitbox travels with the animal (Inspect only) -------------------
	# Residents roam (row 6). gameplay-engineer measured the arrival-time hit point 43.1 px from
	# the live one after 120 s of wander, against a 44 px minimum tap radius — so an index built
	# from `resident_arrived` payloads was one waypoint from breaking the priority rule in
	# silence. These four assertions are what make that unrepeatable.
	var arrival_screen: Vector2 = screen
	var walked: Vector3 = _world.grid_to_world(tile.x + 3, tile.y)
	resident.position = walked  # a waypoint step, inside the home radius, exactly as the roamer moves it
	var live_screen: Vector2 = _camera.unproject_position(
		walked + Vector3(0.0, ResidentPicker.BODY_CENTRE_HEIGHT, 0.0)
	)
	check(live_screen.distance_to(arrival_screen) > ResidentPicker.MIN_TAP_RADIUS_PIXELS,
		"the walk moved the animal further than one whole tap radius (%.1f px > %.1f px)"
			% [live_screen.distance_to(arrival_screen), ResidentPicker.MIN_TAP_RADIUS_PIXELS])

	check_eq(_router.handle_tap(live_screen), TapRouter.RESULT_RESIDENT,
		"A TAP AT THE ANIMAL'S LIVE POSITION HITS IT (still Inspect)")
	# REPOINTED (Task 5, notification-surfaces): same routing change as above.
	check(not _card.is_open(), "...and does NOT open its card — the feed gains an entry instead")
	check_eq(feed.entry_texts()[0], "%s. %s" % [species.display_name, species.effective_fact_text()],
		"...still the same verbatim copy")

	# RE-POINTED (-> D-29 #7): this used to prove the STALE hitbox misses. Terraform no longer
	# runs the resident query at all, so a tap at the animal's old arrival position paints in
	# Terraform regardless of whether the hitbox is stale — that half of the old story is now
	# true for a different reason and is folded into the Terraform block below instead. What
	# stays provable here, in Inspect, is that the LIVE point still hits and the stale one does
	# not, which is the wander-hitbox guarantee this section exists for.
	_hud.set_mode(GameHud.Mode.INSPECT)
	check_eq(_router.handle_tap(arrival_screen), TapRouter.RESULT_INSPECT,
		"IN INSPECT, THE STALE ARRIVAL POINT DOES NOT HIT THE ANIMAL — it reads the tile instead")
	check(not _card.is_open(), "...and opens no card, because nobody is standing there")

	# The control: remove the resident and the identical live tap, still in Inspect, now reads
	# the bare tile. Without this, the assertion above would pass on a router that never looks
	# for a resident there at all.
	site.residents.clear()
	_world.registry.unregister(site)
	resident.queue_free()
	check_eq(_world.total_residents(), 0, "the test resident is removed from the world")
	check_eq(_router.handle_tap(live_screen), TapRouter.RESULT_INSPECT,
		"CONTROL: with the resident gone, the very same live tap reads the tile instead")

	# --- TERRAFORM / BUILD (-> D-29 #7): the tile action always wins, resident query never runs.
	_check_tile_action_wins_over_resident(GameHud.Mode.TERRAFORM, Vector2i(26, 24), species)
	_check_tile_action_wins_over_resident(GameHud.Mode.BUILD, Vector2i(28, 24), species)


## One mode's half of D-29 #7: a resident stands on the tapped tile, and the tile action wins
## anyway because Terraform/Build never run the resident query at all (`handle_tap()`'s own
## doc). Asserted on a tap that WOULD have hit the resident under the old uniform rule (the
## `resident_record_at()` check below proves the animal really is there), so "the tile acted"
## proves the query was skipped rather than merely losing a tie it was never in.
func _check_tile_action_wins_over_resident(
	mode: GameHud.Mode, tile: Vector2i, species: AnimalDefinition
) -> void:
	var mode_name: String = "Terraform" if mode == GameHud.Mode.TERRAFORM else "Build"

	_world.paint_tile(tile.x, tile.y, "grass")
	check_eq(_world.get_tile_terrain(tile.x, tile.y), "grass",
		"[%s] the contested tile is grass" % mode_name)

	var site: HomeSite = _world.registry.register(tile, "rabbit", species.scout_radius)
	var anchor: Vector3 = _world.grid_to_world(tile.x, tile.y)
	var resident := Node3D.new()
	resident.name = "TileActionWinsResident_%s" % mode_name
	resident.position = anchor
	_world.add_child(resident)
	site.residents.append(resident)

	# FOCUS-AND-TAP (D-41): each mode's contested tile is a fresh spot, so re-focus fresh on it
	# too. Overridden to ZOOM_DEFAULT_TILES (not `_aim_camera_at()`'s usual ZOOM_MIN_TILES): at
	# min zoom the elevated (BODY_CENTRE_HEIGHT) screen point and the ground-level screen point
	# are far enough apart that a ground-level tap can miss the resident's own pickable hitbox —
	# weakening this check to "the tile action hits point P, and a resident is pickable at a
	# different point P'" instead of one point genuinely contested between both systems. At
	# ZOOM_DEFAULT_TILES the `MIN_TAP_RADIUS_PIXELS` floor binds instead of the tile-fraction cap
	# (see `ResidentPicker._tap_radius()`), so the ground-level point sits comfortably inside the
	# resident's actual tap radius and one shared screen point can correctly serve both the setup
	# check and the tap.
	_aim_camera_at(anchor)
	(_camera as CameraRig).set_zoom_tiles(CameraRig.ZOOM_DEFAULT_TILES)

	# ONE SCREEN POINT, GROUND-LEVEL — used for both the setup check and the actual tap.
	# `TapRouter.handle_tap()` never calls `resident_record_at()` outside Inspect (its own doc,
	# above `handle_tap()`), so Terraform/Build resolve the target tile purely through
	# `WorldRoot.screen_to_grid()`'s ground raycast — the tap must be the ground-level point, not
	# the elevated (BODY_CENTRE_HEIGHT) one `ResidentPicker` hit-tests against, or the raycast
	# parallax documented in `test_resident_lookup.gd`'s stale-tile fixture note silently
	# paints/places on the diagonal neighbour tile instead of the contested one. At this zoom the
	# same ground-level point also falls inside the resident's own tap radius (the floor above),
	# so the setup check below proves the resident really is pickable at the SAME point the tile
	# action is about to be tapped at — a single point genuinely contested between both systems.
	var screen: Vector2 = _camera.unproject_position(anchor)
	check(not _world.resident_record_at(screen).is_empty(),
		"[%s] the resident really is standing on the tapped tile" % mode_name)

	_hud.set_mode(mode)
	if mode == GameHud.Mode.TERRAFORM:
		_hud.select_palette_option("water")
		check(_world.can_paint(tile.x, tile.y, "water"), "[%s] the tap here WOULD succeed" % mode_name)
		check_eq(_router.handle_tap(screen), TapRouter.RESULT_PAINTED,
			"D-29 #7: in %s the tile action wins the tap even though a resident stands on it"
				% mode_name)
		check_eq(_world.get_tile_terrain(tile.x, tile.y), "water",
			"...the tile the resident stands on WAS painted")
	else:
		_hud.select_palette_option("house")
		check(_world.can_place(tile.x, tile.y, "house"), "[%s] the tap here WOULD succeed" % mode_name)
		var wood_before: int = _world.get_wood()
		check_eq(_router.handle_tap(screen), TapRouter.RESULT_PLACED,
			"D-29 #7: in %s the tile action wins the tap even though a resident stands on it"
				% mode_name)
		check(_world.grid.is_occupied(tile.x, tile.y), "...and the House was built on top of it")
		check(_world.get_wood() < wood_before, "...and Wood was spent")

	check(not _card.is_open(),
		"...and no fact card opened — the resident query never ran in %s at all" % mode_name)

	site.residents.clear()
	_world.registry.unregister(site)
	resident.queue_free()


func _check_off_world_tap_is_not_a_refusal() -> void:
	# A tap that hits no tile at all is not a "no" — it is nothing. It must not draw a soft
	# cue, because a cue there would teach the player that the empty sky refused them.
	#
	# D-41 NOTE: this used to tap the fixed screen pixel `(2.0, 2.0)`, which was off-world only
	# because of the OLD first-person camera's default framing. The fixed pan/zoom camera can be
	# focused/zoomed anywhere (every check above that calls `_aim_camera_at()` leaves it wherever
	# it last looked), so a hardcoded pixel is no longer reliably off-world — it started landing
	# on real terrain and painting it once the earlier checks left the camera zoomed in tight on
	# tile (28, 24). Projecting a tile FAR outside `_world.grid_size()` through the live camera
	# instead — same self-consistent round trip `_tap()`'s own doc describes — guarantees a miss
	# regardless of where the camera happens to be focused.
	_hud.set_mode(GameHud.Mode.TERRAFORM)
	_hud.select_palette_option("rock")
	var cues_before: int = _cue.active_cues()
	var off_world_screen: Vector2 = _camera.unproject_position(_world.grid_to_world(-1000, -1000))
	check_eq(_router.handle_tap(off_world_screen), TapRouter.RESULT_MISS,
		"a tap off the world resolves to a miss")
	check_eq(_cue.active_cues(), cues_before, "...and draws no cue at all")


# --- The HUD's informational panels must not eat the player's tap -----------------------------------------

## REGRESSION TEST FOR A FIXED DEFECT (ui-engineer, 2026-07-28): `HUD/TileReadout` was
## `MOUSE_FILTER_STOP`, so for the four seconds it was on screen after every Inspect tap it
## swallowed clicks in a band across the middle of the world — the player tapped a tile and
## nothing happened at all, which is the one outcome Pillar 1 has no vocabulary for.
##
## ASSERTED AS AN INVARIANT OVER THE WHOLE `Main.tscn` TREE, not as three named nodes: **every
## visible Control anywhere under the running world — `GameUI`, `LeaveOverlay`, whatever comes
## next — that blocks the mouse must be one the player is meant to press.** WIDENED (row 1,
## 2026-08-01) from `GameUI` alone to `_world` so `LeaveOverlay`, its own sibling CanvasLayer, is
## covered by the same invariant rather than sitting outside it. That is the general form of the
## defect — the next informational panel added at the default filter fails here on the day it
## lands, without anyone remembering to add a check for it.
##
## WHY NOT A REAL CLICK. `TapRouter` takes input in `_unhandled_input`, so the honest test would
## push an `InputEventMouseButton` at the viewport and watch it come out the other side. It
## cannot be done in this harness: `Viewport.push_input()` and `Input.parse_input_event()` were
## both measured here and NEITHER reaches `_unhandled_input` under `--headless --script`, on the
## same frame or several frames later, with `is_processing_unhandled_input()` true throughout.
## That is why every other tap in this suite calls `handle_tap()` directly, and it is recorded
## as a `note_expected_pending()` rather than hidden, because it means the Control layer itself
## is only ever checked structurally.
func _check_hud_panels_do_not_swallow_gameplay_taps() -> void:
	var readout: Control = _hud.get_node_or_null("TileReadout") as Control
	if not check(readout != null, "the HUD's tile readout panel is where this check expects it"):
		return
	_hud.set_mode(GameHud.Mode.INSPECT)
	_hud.show_tile_readout("Grass")
	check(_hud.tile_readout_visible(), "the readout is on screen — the state the defect needed")
	check_eq(readout.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"THE FIXED DEFECT: the tile readout is MOUSE_FILTER_IGNORE. It is a label, and a label "
		+ "must not be a wall across the middle of the world for four seconds at a time")

	var preview_panel: Control = _hud.get_node_or_null("PreviewPanel") as Control
	if check(preview_panel != null, "the neighborhood preview panel exists"):
		check_eq(preview_panel.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"...and so is the neighborhood preview — it follows the cursor, so a wall there "
			+ "would block the very taps it is describing")

	# THE GENERAL FORM. Every blocking Control in the UI, enumerated — and this is what found
	# `WoodPanel`, which three named-node assertions would have walked straight past.
	#
	# WIDENED (row 1, 2026-08-01): the root is `_world` (the whole `Main.tscn` tree), not `_ui`
	# (`GameUI` alone), so `LeaveOverlay` — its own CanvasLayer, sibling to `GameUI` — is covered
	# by the same invariant instead of sitting outside every scan that used to stop at GameUI.
	var blockers: Array[String] = []
	var scanned: Array[int] = [0]
	_scan_controls(_world, blockers, scanned)
	check(scanned[0] > 10,
		"the scan walked the whole Main.tscn tree (%d Controls), so its findings mean something"
			% scanned[0])
	var unexpected: Array[String] = []
	for entry: String in blockers:
		if not KNOWN_BLOCKING_PANELS.has(entry.get_slice(" ", 0)):
			unexpected.append(entry)
	check(unexpected.is_empty(),
		"NO NEW informational panel blocks a gameplay tap — the only blockers in the UI are the "
		+ "buttons plus the one recorded defect below",
		"unexpected blocking non-buttons: %s" % str(unexpected))
	check_eq(blockers.size(), KNOWN_BLOCKING_PANELS.size(),
		"...and the recorded defect list is exactly the blockers present (%s)" % str(blockers))

	# The A/B control: put the old filter back and the scan must find it. Without this the
	# result above could just mean the scan never looked at that node.
	readout.mouse_filter = Control.MOUSE_FILTER_STOP
	var regressed: Array[String] = []
	var rescanned: Array[int] = [0]
	_scan_controls(_world, regressed, rescanned)
	var found_readout: bool = false
	for entry: String in regressed:
		if entry.begins_with("TileReadout"):
			found_readout = true
	check(found_readout,
		"CONTROL: restoring MOUSE_FILTER_STOP on the readout makes the scan report it (%s) — the "
			% str(regressed) + "result above is a measurement, not an empty search")
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.hide_tile_readout()

	# PROMOTED 2026-07-28 from a reported defect to a live assertion, the same way Rail 2 was.
	# `HUD/WoodPanel` was MOUSE_FILTER_STOP and is on screen ALWAYS, so every tap in the world's
	# top-left corner was silently swallowed: no paint, no build, no fact card, and no soft cue —
	# the one outcome Pillar 1 has no vocabulary for. It is the Wood counter, a pure readout, so
	# it must never take the mouse. The old check reported this unconditionally on the node's
	# existence, which would have kept claiming the defect forever after the fix.
	var wood: Control = _hud.get_node_or_null("WoodPanel") as Control
	if check(wood != null, "the Wood counter panel exists — the state this guarantee needs"):
		check(wood.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"the Wood counter is MOUSE_FILTER_IGNORE — an always-on-screen readout never eats a tap",
			"mouse_filter is %d (want %d); rect %s in a %s viewport" % [
				wood.mouse_filter, Control.MOUSE_FILTER_IGNORE,
				str(wood.get_global_rect()), str(_ui.get_viewport().get_visible_rect().size)])

	# The flip side, so the fix cannot be over-applied: interactive controls must still stop the
	# mouse, or a press on a palette button would also paint the tile behind it.
	_hud.set_mode(GameHud.Mode.TERRAFORM)
	var button: Control = _first_palette_button()
	if check(button != null, "the Terraform palette has a button"):
		check_eq(button.mouse_filter, Control.MOUSE_FILTER_STOP,
			"a palette BUTTON does stop the mouse — that is what keeps a press off the tile "
			+ "behind it, and it is why the rule is \"only interactive controls block\"")


## Every visible Control at or under `node` that blocks the mouse without being something the
## player presses. Buttons are the whole allowed set at the floor; the HUD has no other
## interactive widget.
func _scan_controls(node: Node, blockers: Array[String], scanned: Array[int]) -> void:
	var control: Control = node as Control
	if control != null:
		scanned[0] = (scanned[0] as int) + 1
		if (control.mouse_filter != Control.MOUSE_FILTER_IGNORE
			and not (control is BaseButton)
			and control.is_visible_in_tree()):
			blockers.append("%s (%s)" % [control.name, control.get_class()])
	for child: Node in node.get_children():
		_scan_controls(child, blockers, scanned)


func _first_palette_button() -> Control:
	var row: Node = _hud.get_node_or_null("%PaletteRow")
	if row == null:
		row = _hud.find_child("PaletteRow", true, false)
	if row == null:
		return null
	for child: Node in row.get_children():
		if child is Button and (child as Button).visible:
			return child as Control
	return null


# --- The live neighborhood preview (row 6's third thin-form clause) --------------------------------------

func _check_live_neighborhood_preview() -> void:
	var preview: NeighborhoodPreview = _router.preview()
	# A corner of the world nothing else in this suite has touched, and outside the camera's
	# default framing (`CameraRig.initialize()`'s focus/zoom) — so this re-focuses the camera
	# there first (D-41, focus-and-tap), the same fixture pattern every other check above uses.
	var tile := Vector2i(6, 30)
	_aim_camera_at(_world.grid_to_world(tile.x, tile.y))
	var screen: Vector2 = _camera.unproject_position(_world.grid_to_world(tile.x, tile.y))
	check_eq(_world.screen_to_grid(screen), tile, "the preview cursor is over tile %s" % tile)

	# 1. Inspect is silent. gdd.md scopes the preview to Terraform and Build; Inspect's job is
	#    "just enjoy the world".
	_hud.set_mode(GameHud.Mode.INSPECT)
	check_eq(_router.refresh_preview(screen), NeighborhoodPreview.BAND_NONE,
		"the preview says NOTHING in Inspect mode")
	check(not _hud.neighborhood_preview_visible(), "...and its panel is not on screen")

	# 2. In Terraform it reads the land — qualitatively.
	_hud.set_mode(GameHud.Mode.TERRAFORM)
	var wild_band: String = _router.refresh_preview(screen)
	check_eq(wild_band, NeighborhoodPreview.BAND_WILD,
		"untouched land reads as wild — nobody could settle here yet")
	check(_hud.neighborhood_preview_visible(), "...and the preview panel is on screen")
	var wild_text: String = _hud.neighborhood_preview_text()

	# THE #27 ASSERTION. "never an `X / Y` fraction, which a child reads as a container to
	# fill." Asserted as an absence of digits AND of a slash, so no numeric form can creep in.
	var digits: String = ""
	for digit: String in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		if wild_text.contains(digit):
			digits += digit
	check(digits == "", "the preview shows NO digit at all (#27: qualitative ships)",
		"text: %s / digits found: %s" % [wild_text, digits])
	check(not wild_text.contains("/"), "...and no fraction")

	# 3. It changes as the land is painted — beat 4 of the First 60 Seconds, and proof that
	#    `WorldRoot.tile_changed` really does invalidate a read under a cursor that has not
	#    moved (without that wiring the same-tile short-circuit would return the stale band).
	var evaluations_before: int = _world.simulation.evaluations_run

	# RE-POINTED (-> D-29 #1, `WorldGrid.START_TERRAIN_ID` "grass" -> "wild_grass"): the rabbit
	# needs BOTH `open_grass` and `cover`, and the old ambient `grass` backdrop used to supply
	# the `open_grass` half implicitly everywhere. `wild_grass` emits nothing, so painting only
	# `cover` (rock) now caps capacity at 0 forever — this ring of explicit `grass` just outside
	# the rock block supplies the other need without touching the rock tiles or the cursor tile
	# itself, which must stay untouched land for check 2 above.
	var grass_painted: int = 0
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			if dx >= -2 and dx <= 1 and dz >= -2 and dz <= 1:
				continue  # the rock block's own footprint, painted below
			if _world.paint_tile(tile.x + dx, tile.y + dz, "grass"):
				grass_painted += 1
	check(grass_painted >= 4,
		"painted %d grass tiles for the rabbit's other need (open_grass)" % grass_painted)

	var painted: int = 0
	for dx in range(-2, 2):
		for dz in range(-2, 2):
			if dx == 0 and dz == 0:
				continue
			if _world.paint_tile(tile.x + dx, tile.y + dz, "rock"):
				painted += 1
	check(painted >= 12, "painted %d rock tiles beside the cursor (cover for a rabbit)" % painted)

	var settled_band: String = _router.refresh_preview(screen)
	check_eq(settled_band, NeighborhoodPreview.BAND_WELCOMING,
		"THE SAME CURSOR now reads as welcoming — the preview followed the player's edit")
	check(_hud.neighborhood_preview_text() != wild_text,
		"...and the line on screen actually changed",
		"before: %s / after: %s" % [wild_text, _hud.neighborhood_preview_text()])

	# 4. THE COST BOUND (gdd.md -> Performance: "touching only home sites whose capacity radius
	#    contains the cursor … never a re-scan"). Measured, not assumed.
	var roster_size: int = NeighborhoodPreview.species_ids(_world).size()
	var neighbour := Vector2i(tile.x + 6, tile.y)
	var neighbour_screen: Vector2 = _camera.unproject_position(
		_world.grid_to_world(neighbour.x, neighbour.y)
	)
	var queries_before: int = preview.queries_run
	_router.refresh_preview(neighbour_screen)
	var spent: int = preview.queries_run - queries_before
	check(spent <= roster_size * 2,
		"one preview read costs at most two world queries per species (%d for %d species)"
			% [spent, roster_size])
	var scans: int = 0
	for origin: Vector2i in preview.last_query_origins:
		if origin != preview.tile():
			scans += 1
	check_eq(scans, 0, "EVERY query used the cursor tile as its origin — the preview never scans")

	var resting: int = preview.queries_run
	_router.refresh_preview(neighbour_screen)
	_router.refresh_preview(neighbour_screen)
	check_eq(preview.queries_run, resting,
		"a cursor that has not moved costs NOTHING — two more polls, zero queries")

	# The preview reads capacity through the same function the arrival predicate uses, so the two
	# can never disagree — but it must not be *simulation work*. gdd.md -> Performance's whole
	# CPU argument rests on `evaluations_run` being able to sit at zero, and a preview that
	# drove the dirty queue would spend that budget at cursor rate. (The paints above enqueue;
	# they only become evaluations on a `tick()`, which this suite never runs.)
	check_eq(_world.simulation.evaluations_run - evaluations_before, 0,
		"every preview read above cost ZERO simulation evaluations")

	# 5. Leaving the world, and leaving the mode, both take the panel away.
	# D-41 NOTE: same recalibration as `_check_off_world_tap_is_not_a_refusal()` — a hardcoded
	# `(2.0, 2.0)` is only off-world under the OLD first-person camera's default framing, not the
	# fixed pan/zoom camera the preceding checks leave zoomed in tight on tile (6, 30). Project a
	# tile far outside `_world.grid_size()` instead, same as that other check.
	_router.refresh_preview(_camera.unproject_position(_world.grid_to_world(-1000, -1000)))
	check(not _hud.neighborhood_preview_visible(),
		"a cursor off the world shows no preview — the same non-event as an off-world tap")
	_hud.set_mode(GameHud.Mode.INSPECT)
	check(not _hud.neighborhood_preview_visible(), "...and switching to Inspect clears it")

	note_expected_pending(
		"the WILD band cannot say \"nearly\" — the near-miss summary is unbuilt (row 12)",
		"gdd.md: the preview \"reads the qualification system's near-miss summary\", which is "
		+ "what makes it meaningful before anything qualifies. That summary belongs to "
		+ "Discovery (row 12) and does not exist, and `capacity_at()` reports the same 0 for a "
		+ "spot one tile short as for bare ground. So the thin form ships two honest bands "
		+ "either side of qualification and no \"getting closer\" between them."
	)


# --- helper -------------------------------------------------------------------------------------------------

## Projects a tile's world position through the live camera and taps it, exercising the real
## camera -> ray -> collider -> grid chain rather than passing coordinates by hand.
##
## D-41 NOTE: this deliberately does NOT re-aim the camera — most tiles this suite taps sit
## roughly in front of `CameraRig.initialize()`'s default placement (the world's bounds centre,
## at default zoom), and the round trip below (`unproject_position` then `screen_to_grid` back
## through the SAME camera) is self-consistent regardless of exactly where on screen the point
## lands, as long as it is not behind the camera. Checks whose target tile falls outside that
## default framing call `_aim_camera_at()` first instead — see each call site.
func _tap(tile: Vector2i) -> String:
	var screen: Vector2 = _camera.unproject_position(_world.grid_to_world(tile.x, tile.y))
	check_eq(_world.screen_to_grid(screen), tile,
		"the tap at %s resolves back to that tile (camera -> ray -> collider -> grid)" % tile)
	return _router.handle_tap(screen)


## FOCUS-AND-TAP FIXTURE (D-41): centres the pan/zoom camera on `target` at close
## zoom, replacing the old "park the Player and look_at()" fixture — the fixed
## orthographic camera has no facing to aim, so "framing `target`" is a focus point
## and a zoom level, not a position and a look direction. Every call site re-derives
## its own screen position afterward via `_camera.unproject_position(target)`, the
## same value passed in here, so there is no separate crosshair helper to update.
func _aim_camera_at(target: Vector3) -> void:
	var rig := _camera as CameraRig
	rig.set_focus(target)
	rig.set_zoom_tiles(CameraRig.ZOOM_MIN_TILES)
