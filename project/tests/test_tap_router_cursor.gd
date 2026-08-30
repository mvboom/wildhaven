extends QATestCase
## D-41: TapRouter reverted to cursor-position targeting. The fixed pan/zoom `CameraRig`
## (Task 2) never captures the mouse, so the old D-33 look-and-press model — track the
## cursor only while NOT captured, fire a tap only while captured — meant a tap could never
## fire at all under the new camera. This suite locks in the two structural fixes:
##
##   FIX 1/3 — `_unhandled_input()`/`_process()` track and act on the real cursor position
##   unconditionally, regardless of `Input.mouse_mode`.
##   FIX 2 — the old `MAX_INTERACTION_RANGE` "walk closer" ceiling (and both its call sites,
##   in `handle_tap()` and `_resolve_crosshair_state()`) is gone: under a camera that only
##   pans/zooms, there is no "walking closer" concept, so a tap far from the camera's own
##   focus must still succeed.
##
## Same fixture pattern `test_mode_tap_model.gd` uses — a real `Main.tscn`, taps driven
## through `TapRouter.handle_tap()` (and, for the mouse_mode regression itself, through
## `TapRouter._unhandled_input()` with synthetic events, since that is the function the
## removed gating lived in).
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_tap_router_cursor.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

var _world: WorldRoot = null
var _ui: GameUI = null
var _hud: GameHud = null
var _router: TapRouter = null
var _camera: CameraRig = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("tap router: cursor-position targeting (D-41)")

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

	var camera_node: Camera3D = root.get_viewport().get_camera_3d()
	if not check(camera_node is CameraRig, "the live camera is a CameraRig"):
		finish()
		return true
	_camera = camera_node as CameraRig
	_camera.initialize()

	_check_mouse_is_never_captured()
	_check_click_routes_unconditionally_of_mouse_mode()
	_check_process_polls_the_tracked_cursor_not_a_crosshair()
	_check_far_tap_is_no_longer_range_refused()
	_check_far_resident_tap_is_no_longer_range_refused()
	_check_erase_button_press_and_real_click_actually_removes_a_tile()

	finish()
	return true


## FIX 1/4's whole premise: nothing anywhere sets the pointer captured any more, since this
## camera only ever pans/zooms. If this ever starts failing, Fix 1's "regardless of
## Input.mouse_mode" reasoning needs revisiting, not just this assertion.
func _check_mouse_is_never_captured() -> void:
	check_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE,
		"the pointer is VISIBLE (never captured) under the fixed pan/zoom camera")


## THE REGRESSION FIX 1 GUARDS AGAINST: the old code tracked mouse motion only while NOT
## captured, and fired a tap only while captured — under a camera that never captures, that
## meant the click branch's `if Input.mouse_mode != MOUSE_MODE_CAPTURED: return` discarded
## every left-click before `handle_tap()` was ever called. Driven through
## `TapRouter._unhandled_input()` itself (not `handle_tap()` directly) because that is
## exactly the function the removed gating lived in — calling `handle_tap()` directly would
## pass even if the old gate were still there.
func _check_click_routes_unconditionally_of_mouse_mode() -> void:
	var tile := Vector2i(15, 15)
	_world.paint_tile(tile.x, tile.y, "wild_grass")
	_hud.set_mode(GameHud.Mode.TERRAFORM)
	_hud.select_palette_option("rock")

	_camera.set_focus(_world.grid_to_world(tile.x, tile.y))
	_camera.set_zoom_tiles(6.0)
	var screen: Vector2 = _camera.unproject_position(_world.grid_to_world(tile.x, tile.y))

	check_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE,
		"...and still VISIBLE going into the click, so a passing result cannot be explained "
		+ "by an accidentally-captured pointer")

	var motion := InputEventMouseMotion.new()
	motion.position = screen
	_router._unhandled_input(motion)
	check_eq(_router._cursor_position, screen,
		"mouse motion updates the tracked cursor position even while the pointer is not "
		+ "captured (this half already worked before Fix 1; asserted here as a baseline)")
	check(_router._cursor_seen, "...and marks a cursor as having been seen at all")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen
	_router._unhandled_input(click)

	check_eq(_world.get_tile_terrain(tile.x, tile.y), "rock",
		"a left-click at the tracked cursor position routes through handle_tap() and paints "
		+ "the tile -- i.e. the tap fires at all, and its result is not RESULT_NONE -- even "
		+ "though the pointer was never captured (Fix 1)")

	# A second tap at the same tracked position, called the same way `handle_tap()` is
	# documented to be driven (position-driven, no synthetic events required), makes the
	# "not RESULT_NONE" routing explicit rather than only inferred from world state.
	var result: String = _router.handle_tap(screen)
	check(result != TapRouter.RESULT_NONE,
		"a tap at the tracked cursor position routes to a real result, never RESULT_NONE",
		"got '%s'" % result)


## FIX 3's regression: `_process()` used to poll the screen-centre crosshair while captured,
## and the tracked cursor only otherwise. Proven here by making the screen-centre tile and
## the actual cursor tile disagree about paintability -- if `_process()` ever polls the
## centre again instead of the tracked cursor, this flips to invalid.
func _check_process_polls_the_tracked_cursor_not_a_crosshair() -> void:
	var centre_tile := Vector2i(18, 18)
	var cursor_tile := Vector2i(21, 18)
	_world.paint_tile(centre_tile.x, centre_tile.y, "rock")  # already rock: NOT paintable to rock
	_world.paint_tile(cursor_tile.x, cursor_tile.y, "wild_grass")  # paintable to rock

	_hud.set_mode(GameHud.Mode.TERRAFORM)
	_hud.select_palette_option("rock")

	# The screen-centre tile becomes the camera's own focus, so `get_visible_rect().size *
	# 0.5` (the deleted `_crosshair_position()`'s formula) would project back onto it.
	_camera.set_focus(_world.grid_to_world(centre_tile.x, centre_tile.y))
	_camera.set_zoom_tiles(6.0)
	var screen_centre: Vector2 = root.get_viewport().get_visible_rect().size * 0.5
	check_eq(_world.screen_to_grid(screen_centre), centre_tile,
		"the viewport's own screen-centre really does resolve to the focus tile (fixture "
		+ "sanity check)")

	var cursor_screen: Vector2 = _camera.unproject_position(
		_world.grid_to_world(cursor_tile.x, cursor_tile.y)
	)
	check(cursor_screen.distance_to(screen_centre) > 1.0,
		"the tracked-cursor tile really does project somewhere other than screen centre "
		+ "(fixture sanity check)")

	var motion := InputEventMouseMotion.new()
	motion.position = cursor_screen
	_router._unhandled_input(motion)

	_router._process(1.0)  # comfortably clears PREVIEW_POLL_SECONDS (0.1s)

	check(_router.is_crosshair_valid(),
		"_process() resolved crosshair validity against the TRACKED CURSOR tile "
		+ "(wild_grass, paintable to rock: valid) -- if it instead polled the screen-centre "
		+ "crosshair (already rock: not paintable), this would read false")
	check_eq(_router.preview().tile(), cursor_tile,
		"...and the live neighborhood preview polled the same tracked-cursor tile, not the "
		+ "screen-centre tile")


## FIX 2's core claim: under the fixed pan/zoom camera, there is no "walking closer" --
## a tap far from wherever the camera happens to be focused must still succeed. Uses a tile
## near the world's corner, comfortably past the OLD `MAX_INTERACTION_RANGE` (13.0 units)
## from a camera focused at the world's centre.
func _check_far_tap_is_no_longer_range_refused() -> void:
	var bounds: Rect2 = _camera.world_bounds()
	var centre: Vector2 = bounds.position + bounds.size * 0.5
	_camera.set_focus(Vector3(centre.x, 0.0, centre.y))
	_camera.set_zoom_tiles(CameraRig.ZOOM_DEFAULT_TILES)

	var far_tile := Vector2i(2, 2)
	_world.paint_tile(far_tile.x, far_tile.y, "wild_grass")
	_hud.set_mode(GameHud.Mode.TERRAFORM)
	_hud.select_palette_option("rock")

	var far_world: Vector3 = _world.grid_to_world(far_tile.x, far_tile.y)
	var distance: float = _world.distance_to(far_world)
	check(distance > 13.0,
		"the fixture tile really is farther than the old MAX_INTERACTION_RANGE (13.0) from "
		+ "the camera", "got %f" % distance)

	var screen: Vector2 = _camera.unproject_position(far_world)
	check_eq(_router.handle_tap(screen), TapRouter.RESULT_PAINTED,
		"a tap far beyond the old 13.0-unit range now PAINTS instead of being refused -- "
		+ "there is no 'walk closer' under a camera that only pans and zooms (Fix 2)")
	check_eq(_world.get_tile_terrain(far_tile.x, far_tile.y), "rock",
		"...and the tile actually changed")


## FIX 2 ALSO REMOVED THE RESIDENT-DISTANCE CEILING in `handle_tap()`'s Inspect branch
## (measured against the resident's own world position, not the terrain ray) -- covered
## separately from the terrain case above because it is a different code path
## (`_world.distance_to(resident["world_position"])` vs. `_world.crosshair_distance()`).
func _check_far_resident_tap_is_no_longer_range_refused() -> void:
	var tile := Vector2i(3, 3)
	var species: AnimalDefinition = _world.roster.by_id("rabbit")
	if not check(species != null, "the rabbit is in the roster"):
		return

	var site: HomeSite = _world.registry.register(tile, "rabbit", species.scout_radius)
	var anchor: Vector3 = _world.grid_to_world(tile.x, tile.y)
	var resident := Node3D.new()
	resident.name = "FarResident"
	resident.position = anchor
	_world.add_child(resident)
	site.residents.append(resident)

	var bounds: Rect2 = _camera.world_bounds()
	var centre: Vector2 = bounds.position + bounds.size * 0.5
	_camera.set_focus(Vector3(centre.x, 0.0, centre.y))
	_camera.set_zoom_tiles(CameraRig.ZOOM_DEFAULT_TILES)

	var distance: float = _world.distance_to(anchor)
	check(distance > 13.0,
		"the resident really is farther than the old MAX_INTERACTION_RANGE (13.0) from the "
		+ "camera", "got %f" % distance)

	var screen: Vector2 = _camera.unproject_position(anchor)
	check(not _world.resident_record_at(screen).is_empty(),
		"the resident really is picked at this screen position")

	_hud.set_mode(GameHud.Mode.INSPECT)
	check_eq(_router.handle_tap(screen), TapRouter.RESULT_RESIDENT,
		"a far resident opens its fact card instead of being range-refused (Fix 2)")
	# REPOINTED (Task 5, notification-surfaces): the replay routes to the feed now, never the
	# big card — see `test_fact_card.gd`'s `_check_tap_to_replay_in_inspect()` for the same
	# pattern.
	check(not _ui.fact_card.is_open(),
		"...and the fact card does NOT open — the replay routes to the feed instead")
	var feed: NotificationFeed = _ui.notification_feed
	check_eq(feed.entry_texts()[0], "%s. %s" % [species.display_name, species.effective_fact_text()],
		"...the feed gains the replay entry instead, with the same verbatim copy")

	site.residents.clear()
	_world.registry.unregister(site)
	resident.queue_free()


## PLAYTEST REPORT: "Erase doesn't work at all now." Every existing check drives
## `GameHud.activate_remove()` directly, which bypasses the real button entirely — this instead
## presses the ACTUAL `%RemoveButton` (its real `pressed` signal, the same path a mouse click
## takes) and fires a REAL synthetic left-click through `TapRouter._unhandled_input()` (the
## same technique `_check_click_routes_unconditionally_of_mouse_mode()` above already uses),
## so a defect anywhere in that chain — the button's own wiring, `is_remove_selected()`, or
## `TapRouter`'s dispatch — would show up here even though it would not show up in a check that
## calls `activate_remove()` by hand.
func _check_erase_button_press_and_real_click_actually_removes_a_tile() -> void:
	var tile := Vector2i(24, 24)
	_world.paint_tile(tile.x, tile.y, "rock")
	check_eq(_world.get_tile_terrain(tile.x, tile.y), "rock", "setup: the tile is painted")

	var remove_button: Button = _hud.get_node_or_null("%RemoveButton") as Button
	if not check(remove_button != null, "the real Erase button exists"):
		return
	remove_button.pressed.emit()
	check(_hud.is_remove_selected(),
		"pressing the REAL Erase button (its own `pressed` signal, not a direct "
		+ "activate_remove() call) selects the remove tool")

	_camera.set_focus(_world.grid_to_world(tile.x, tile.y))
	_camera.set_zoom_tiles(6.0)
	var screen: Vector2 = _camera.unproject_position(_world.grid_to_world(tile.x, tile.y))

	var motion := InputEventMouseMotion.new()
	motion.position = screen
	_router._unhandled_input(motion)

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen
	_router._unhandled_input(click)

	check_eq(_world.get_tile_terrain(tile.x, tile.y), WorldGrid.START_TERRAIN_ID,
		"a REAL click at the tracked cursor, with the REAL Erase button pressed, actually "
		+ "removes the tile — this is the reported bug's exact end-to-end path")
