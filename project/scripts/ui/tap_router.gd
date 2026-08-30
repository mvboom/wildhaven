class_name TapRouter
extends Node
## **The whole of Wildhaven's gameplay input.** One gesture — look at the target and
## left-click — resolved against the current mode. Pillar 3, in one function: "pick a mode
## (or none), then tap."
##
## gdd.md -> Player Interface & Controls gives the table this file implements:
##   Left-click                     cursor-position tap: every tap action (Inspect/Terraform/Build)
##   Right-drag, wheel, WASD/arrows pan + zoom      -> `CameraRig`, never here
##   Home, held (and a HUD button)  the map peek    -> `CameraRig`, never here
##   Tab                            open/close the menu window -> `CameraRig`, never here
##
## CURSOR-POSITION TARGETING (D-41, reverses D-33's first-person look-and-press). The camera
## is a fixed pan/zoom orthographic rig that never captures the mouse (`CameraRig`'s own
## header) — there is no hidden OS cursor and no meaningful screen-centre crosshair to raycast
## from instead. A tap always raycasts from the real, always-visible cursor position, tracked
## on every `InputEventMouseMotion` in `_unhandled_input()` below, regardless of
## `Input.mouse_mode` (which never leaves `MOUSE_MODE_VISIBLE` under this camera, but nothing
## here depends on that being true).
##
## The split is the pillar's other half — "Camera control lives on entirely separate inputs
## and never conflicts with gameplay taps" — and it is structural: this file only ever looks
## at `MOUSE_BUTTON_LEFT`, and `CameraRig` never looks at it.
##
## THE PRIORITY RULE IS MODE-AWARE (REVERSED 2026-08-01, -> D-29 #7; was "in every mode").
## gdd.md's "an animal standing on a tappable tile always wins the tap — generous animal
## hitboxes beat ambiguous taps for young kids" now holds **only in Inspect**, where
## `handle_tap()` still asks `WorldRoot.resident_record_at()` before it asks the grid, so
## residents stay reliably tappable for fact cards. **In Terraform and Build, the tile action
## under the cursor always wins instead, regardless of whether a resident's hitbox overlaps
## that point** — the resident query is not even run in those two modes. A tap on a tile is a
## tile action there, full stop, never intercepted by a resident standing near or on it.
##
## Why: even after D-27 #3 capped the resident hitbox at one tile wide, a villager standing on
## its own House still won every tap on the field beside it, which made the floor's likeliest
## Gentle Displacement scenario (clearing that field) unreachable while the family was home.
## D-27 #3 fixed the hitbox's SIZE; this fixes which system wins the tap. The one-interaction-
## pattern pillar is unchanged — it is still exactly one left-click, resolved against the mode.
##
## **THE HIT TEST RESOLVES AGAINST LIVE POSITIONS.** It used to run against the UI's own list of
## `resident_arrived` payloads (`resident_index.gd`, deleted here), which recorded where each
## animal stood *at arrival*. Residents wander now, so that list was wrong from the animal's
## first step — and the symptom was not "the animal stops being tappable". Measured over 120 s
## of real wander at default zoom (where the effective radius is ~110 px, not the 44 px floor):
## the animal left the stale hitbox within ~4-8 s and reached 420-820 px away, which left a
## **ghost hitbox standing over the empty den** — a tap on bare ground opening a fact card and
## silently declining to paint the tile the player aimed at — and in one run of three the animal
## wandered back inside the ghost by the end, so the break was intermittent rather than clean.
## `WorldRoot` owns the query now, over `HomeSiteRegistry`'s own resident nodes, and there is
## deliberately no second list in the UI that could go stale or drift from its constants.
##
## THE LIVE NEIGHBORHOOD PREVIEW rides this same file because it rides the same targeting
## (gdd.md: "It rides that same targeting tap, so no sixth pattern"). It adds **no gesture** —
## the player still only ever taps — and its cost is bounded by `PREVIEW_POLL_SECONDS` plus
## `NeighborhoodPreview`'s own same-tile short-circuit.
##
## REFUSALS ARE SILENT. `WorldRoot.paint_tile()` / `place_building()` return false and change
## nothing when an edit is ineligible or unaffordable. This file turns that false into a
## `TapCue.soft()` ring and nothing else: no message, no sound, no penalty, no blocked state
## (Pillar 1; buildings.md's "a soft cue, never an error").
##
## HUD CLICKS NEVER REACH HERE. Input is taken in `_unhandled_input`, which the engine only
## reaches after every Control has had its turn — so a press on a palette button cannot also
## paint the tile behind it, without this file knowing anything about the HUD's geometry.

## What a tap resolved to. Returned by `handle_tap()` purely so a headless test can assert
## the routing; nothing in the game branches on it.
const RESULT_NONE: String = "none"
const RESULT_CARD_OPEN: String = "card_open"
const RESULT_RESIDENT: String = "resident"
const RESULT_MISS: String = "miss"
const RESULT_INSPECT: String = "inspect"
const RESULT_PAINTED: String = "painted"
const RESULT_PLACED: String = "placed"
const RESULT_REMOVED: String = "removed"
const RESULT_REFUSED: String = "refused"

## DECIDED 2026-08-01 (-> D-29). How often the cursor's tile is re-resolved for the live
## neighborhood preview, in seconds. **This is the "cursor rate" in gdd.md -> Performance's
## cost bound, made into a number.** Mouse motion can arrive many times per frame; this caps
## the preview at ten screen->grid raycasts a second regardless, and the capacity read behind
## it only runs when that raycast lands on a *different* tile (or an edit invalidated the last
## one). 0.1 s is below the threshold where a hover readout feels laggy and far above the rate
## at which a hand actually crosses tiles.
const PREVIEW_POLL_SECONDS: float = 0.1

var _world: WorldRoot = null
var _hud: GameHud = null
var _fact_card: FactCard = null
var _notification_feed: NotificationFeed = null
var _cue: TapCue = null
var _crosshair: Crosshair = null

var _preview := NeighborhoodPreview.new()
var _cursor_position: Vector2 = Vector2.ZERO
var _cursor_seen: bool = false
var _preview_clock: float = 0.0
var _crosshair_valid: bool = false


func attach(
	world: WorldRoot, hud: GameHud, fact_card: FactCard, feed: NotificationFeed,
	cue: TapCue, crosshair: Crosshair
) -> void:
	_world = world
	_hud = hud
	_fact_card = fact_card
	_notification_feed = feed
	_cue = cue
	_crosshair = crosshair


## The preview instance, so a headless check can read `queries_run` / `last_query_origins`.
func preview() -> NeighborhoodPreview:
	return _preview


## Whether a tap at the last-polled crosshair position would do something other than
## refuse, right now. Exposed for headless tests; the live `Crosshair` never polls this —
## `_refresh_crosshair_state()` pushes the same value straight to it via `set_valid()` the
## moment it changes, computed on the same throttled cadence as the neighborhood preview,
## not on every frame, for the same cost-bound reason `PREVIEW_POLL_SECONDS` exists.
func is_crosshair_valid() -> bool:
	return _crosshair_valid


## An edit changed the world, so whatever the preview last computed may no longer be true —
## including for a cursor that has not moved, which is precisely beat 4 of the First 60 Seconds
## (paint a tile, watch the read under your hand change). Wired to `WorldRoot.tile_changed` by
## `GameUI`. O(1): the recompute happens on the next poll, never inside the edit.
func invalidate_preview() -> void:
	_preview.invalidate()


func _unhandled_input(event: InputEvent) -> void:
	# CURSOR-POSITION TARGETING (D-41). The camera never captures the mouse, so the real OS
	# cursor position is always meaningful and always tracked, on every motion event. A tap is
	# simply a left-click at wherever that tracked position currently is.
	if event is InputEventMouseMotion:
		_cursor_position = (event as InputEventMouseMotion).position
		_cursor_seen = true
		return
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	# A tap is also a targeting event: the tile under the cursor may now read differently.
	_cursor_position = mouse.position
	_cursor_seen = true
	handle_tap(_cursor_position)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _cursor_seen:
		return
	_preview_clock += delta
	if _preview_clock < PREVIEW_POLL_SECONDS:
		return
	_preview_clock = 0.0
	refresh_preview(_cursor_position)
	_refresh_crosshair_state(_cursor_position)


## The single tap entry point. Public and position-driven so a headless test can drive the
## exact path the mouse drives, with no synthetic events.
func handle_tap(screen_position: Vector2) -> String:
	if _world == null or _hud == null:
		return RESULT_NONE

	# The card's own scrim swallows taps while it is open, so this is belt-and-braces for the
	# scripted path only.
	if _fact_card != null and _fact_card.is_open():
		_fact_card.dismiss()
		return RESULT_CARD_OPEN

	# --- The priority rule, mode-aware (-> D-29 #7). ---
	# Inspect: the animal is asked first, exactly as before — residents stay reliably tappable
	# for fact cards. Terraform/Build: skip the resident query entirely, so the tile action
	# under the cursor always wins and a resident standing near or on the tile can never make
	# it untappable. `resident_record_at()` hit-tests where the animal IS, not where it
	# arrived, and takes no camera — it reads the viewport's own, exactly as `screen_to_grid()`
	# does.
	#
	# LOOKED UP BEFORE THE OFF-WORLD CHECK, and that is fine: it is a pure, stateless read (no
	# card opens, nothing else observable happens) — its only job here is to hand the check
	# below the resident's own position when there is one to prefer.
	var resident: Dictionary = {}
	if _hud.mode() == GameHud.Mode.INSPECT:
		resident = _world.resident_record_at(screen_position)

	# OFF-WORLD MISS ONLY (D-41 removed the old "walk closer" range ceiling this check used to
	# also enforce, alongside `MAX_INTERACTION_RANGE` itself: under the fixed pan/zoom camera
	# there is no "walking closer" concept at all, so a tap on anything the camera can see is
	# never refused for being far away). This still exists to catch a lookup that resolved to
	# nothing real: `distance_to()`/`crosshair_distance()` both return -1.0 on that.
	#
	# INSPECT WITH A RESIDENT PICKED measures against the RESIDENT'S OWN world position, not
	# the terrain ray under the crosshair — see `WorldRoot.crosshair_distance()`'s note. The
	# terrain ray travels past a resident (anchored above the ground for its screen-space hit
	# test) to whatever ground is behind it; measuring the resident's own position keeps this
	# check correct even though it no longer gates on distance.
	var distance: float
	if not resident.is_empty():
		distance = _world.distance_to(resident["world_position"] as Vector3)
	else:
		distance = _world.crosshair_distance(screen_position)
	if distance < 0.0:
		return RESULT_MISS  # off the world entirely: not a refusal, so not even a soft cue

	if not resident.is_empty():
		_show_species_card(resident["species_id"] as String)
		_accept(screen_position)
		return RESULT_RESIDENT

	var tile: Vector2i = _world.screen_to_grid(screen_position)
	if tile.x < 0:
		return RESULT_MISS  # off the world entirely: not a refusal, so not even a soft cue

	# REMOVAL IS ASKED BEFORE THE MODE IS, and that is the point. gdd.md's removal policy is
	# "uniform across Terraform reverts and Build removals" — one behaviour, not two — so the
	# remove tool resolves the same way from either palette and `WorldRoot.remove_at()` decides
	# what was there. **This adds no gesture**: the player picked a palette entry and tapped, the
	# same two steps as painting a rock.
	if _hud.is_remove_selected():
		return _tap_remove(tile, screen_position)

	match _hud.mode():
		GameHud.Mode.TERRAFORM:
			return _tap_terraform(tile, screen_position)
		GameHud.Mode.BUILD:
			return _tap_build(tile, screen_position)
		_:
			return _tap_inspect(tile, screen_position)


## Inspect, thin form (gdd.md row 2: "Inspect's taps thin"). A resident replays its fact card
## — handled above by the priority rule — and land shows its terrain and tags. Tap-to-tend is
## row 5's depth and is deliberately absent.
func _tap_inspect(tile: Vector2i, screen_position: Vector2) -> String:
	_hud.show_tile_readout(_terrain_display_name(tile), _world.get_tile_tags(tile.x, tile.y))
	_accept(screen_position)
	return RESULT_INSPECT


func _tap_terraform(tile: Vector2i, screen_position: Vector2) -> String:
	var terrain_id: String = _hud.selected_terrain_id()
	if terrain_id != "" and _world.paint_tile(tile.x, tile.y, terrain_id):
		_accept(screen_position)
		return RESULT_PAINTED
	_refuse(screen_position)
	return RESULT_REFUSED


func _tap_build(tile: Vector2i, screen_position: Vector2) -> String:
	var placeable_id: String = _hud.selected_placeable_id()
	if placeable_id != "" and _world.place_building(tile.x, tile.y, placeable_id):
		_accept(screen_position)
		return RESULT_PLACED
	_refuse(screen_position)
	return RESULT_REFUSED


## The remove tool's tap, in either Terraform or Build.
##
## A tile with nothing to take back returns false from `remove_at()` and gets the same soft ring
## every other refusal gets — **not** a message and not an error. gdd.md's own reading: "a tile in
## its original state is not an error to remove, it is simply a tap that does nothing."
##
## THERE IS NO CONFIRMATION, and there must not be one. Removal is the *reversible* half of
## Pillar 1: inside the grace window it refunds 100% and re-settles the neighbourhood as though
## nothing happened, and if it displaces anybody the Gentle Displacement warning is what says so
## — after the fact, as disclosure. A "are you sure?" here would be a second interaction pattern
## and a deterrent, and gdd.md rejects both.
func _tap_remove(tile: Vector2i, screen_position: Vector2) -> String:
	if _world.remove_at(tile.x, tile.y):
		_accept(screen_position)
		return RESULT_REMOVED
	_refuse(screen_position)
	return RESULT_REFUSED


# --- The live neighborhood preview (row 6's third thin-form clause) -----------------------

## Re-resolves the cursor's tile and updates the preview. Returns the band now displayed.
##
## Public and position-driven for the same reason `handle_tap()` is: a headless check drives
## the exact path the mouse drives, with no synthetic events.
##
## WHEN IT SHOWS NOTHING, AND WHY:
##   * **Inspect** — gdd.md scopes the preview to "while a tile is targeted in Terraform or
##     Build". Inspect is "just enjoy the world"; a read that followed the cursor there would
##     be chatter over a mode whose whole job is quiet.
##   * **a card is open** — the world stays visible behind it (spec.md), but a second panel
##     narrating the land underneath the payoff is noise at the game's best moment.
##   * **off the world** — the same non-event as an off-world tap: not a refusal, so not a cue
##     and not a message.
func refresh_preview(screen_position: Vector2) -> String:
	if _world == null or _hud == null:
		return NeighborhoodPreview.BAND_NONE
	var previewing: bool = _hud.mode() != GameHud.Mode.INSPECT
	if _fact_card != null and _fact_card.is_open():
		previewing = false
	if not previewing:
		return _clear_preview()

	var tile: Vector2i = _world.screen_to_grid(screen_position)
	if tile.x < 0:
		return _clear_preview()

	if _preview.update(_world, tile):
		_hud.show_neighborhood_preview(_preview.band())
	return _preview.band()


func _clear_preview() -> String:
	_preview.clear()
	_hud.hide_neighborhood_preview()
	return NeighborhoodPreview.BAND_NONE


## Recomputes and stores whether a tap at `screen_position` would currently do something
## other than refuse. Called on the same throttled cadence `refresh_preview()` already
## uses — see `_process()` — so this costs one extra `crosshair_distance()` call per poll,
## not one per frame.
func _refresh_crosshair_state(screen_position: Vector2) -> bool:
	_crosshair_valid = _resolve_crosshair_state(screen_position)
	if _crosshair != null:
		_crosshair.set_valid(_crosshair_valid)
	return _crosshair_valid


## Mirrors `handle_tap()`'s off-world-miss check (D-41 dropped the range ceiling both used to
## also enforce) so the reticle's valid/invalid colour never disagrees with what a tap at the
## same position would actually do: a picked resident's distance is measured against its own
## world position, never the terrain ray behind it.
func _resolve_crosshair_state(screen_position: Vector2) -> bool:
	if _world == null or _hud == null:
		return false

	var resident: Dictionary = {}
	if _hud.mode() == GameHud.Mode.INSPECT:
		resident = _world.resident_record_at(screen_position)

	var distance: float
	if not resident.is_empty():
		distance = _world.distance_to(resident["world_position"] as Vector3)
	else:
		distance = _world.crosshair_distance(screen_position)
	if distance < 0.0:
		return false

	if _hud.mode() == GameHud.Mode.INSPECT:
		if not resident.is_empty():
			return true
		return _world.screen_to_grid(screen_position).x >= 0

	var tile: Vector2i = _world.screen_to_grid(screen_position)
	if tile.x < 0:
		return false
	# KNOWN LIMIT: the remove tool has no dry-run predicate — `WorldRoot.remove_at()`
	# mutates, so there is nothing pure to ask "would this remove anything?" A tile in
	# range always reads valid while remove is selected; the tap itself still resolves
	# through the existing soft-cue path unchanged (`_tap_remove()`) if there is nothing
	# there. This only affects the reticle's own color, never what a tap actually does.
	if _hud.is_remove_selected():
		return true
	if _hud.mode() == GameHud.Mode.TERRAFORM:
		return _hud.selected_terrain_id() != "" and _world.can_paint(
			tile.x, tile.y, _hud.selected_terrain_id()
		)
	if _hud.mode() == GameHud.Mode.BUILD:
		return _hud.selected_placeable_id() != "" and _world.can_place(
			tile.x, tile.y, _hud.selected_placeable_id()
		)
	return false


## Opens the replay entry for a species, in the feed rather than the big payoff card — an
## Inspect-tap is curiosity, not a move-in (gdd.md -> Pillar 4: "on success AND on curiosity"),
## and the feed is where every non-first-ever fact-card moment lives now.
func _show_species_card(species_id: String) -> void:
	if _notification_feed == null:
		return
	var species: AnimalDefinition = species_definition(species_id)
	if species != null:
		_notification_feed.show_fact(species.display_name, species.effective_fact_text())


## Looks a species up by id.
##
## REPORTED API GAP: `WorldRoot`'s documented public surface has no
## `species_definition(id) -> AnimalDefinition`, but the fact card needs `display_name` and
## `effective_fact_text()`. Reading `world.roster` (a public field of `world_root.gd`) is the smallest
## possible reach and, crucially, keeps one roster: a second loader in the UI could load a
## different set of `.tres` files than the simulation acted on, and the card would then be
## able to disagree with the world. Replace this body with the real accessor when it exists.
func species_definition(species_id: String) -> AnimalDefinition:
	if _world == null:
		return null
	if _world.has_method("species_definition"):
		return _world.call("species_definition", species_id) as AnimalDefinition
	if _world.roster == null:
		return null
	return _world.roster.by_id(species_id)


func _terrain_display_name(tile: Vector2i) -> String:
	var terrain_id: String = _world.get_tile_terrain(tile.x, tile.y)
	for terrain: TerrainDefinition in _world.terrain_options():
		if terrain.id == terrain_id:
			return terrain.display_name
	return terrain_id


func _accept(screen_position: Vector2) -> void:
	if _cue != null:
		_cue.accepted(screen_position)


func _refuse(screen_position: Vector2) -> void:
	if _cue != null:
		_cue.soft(screen_position)
