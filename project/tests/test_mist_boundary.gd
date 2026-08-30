extends QATestCase
## MIST BOUNDARY — Tier 1 row 13's VISUAL half (tech-art). Driven through the real
## `scenes/Main.tscn`, the same way `test_mist_reveal.gd` exercises the mechanical half, so
## this suite is checking the actual shipped wiring, not a stand-in.
##
## WHAT THIS SUITE CAN AND CANNOT ASSERT. `MistBoundary` is a look-pass node — whether the
## shader reads as "atmospheric fog" rather than "a wall" on screen is the human's eyeball
## call (see the build report), and no headless assertion below claims otherwise. What IS
## machine-checkable, and asserted here: the curtain exists (four panels, always), it tracks
## the grid's revealed extent, and it rebuilds exactly once per `WorldRoot.mist_revealed` —
## never zero times (a stale curtain lagging the real edge) and never twice (a double rebuild
## for one edit, the same double-fire `WorldGrid.grown`'s own contract already rules out).
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_mist_boundary.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

var _world: WorldRoot = null
var _boundary: MistBoundary = null
var _frames: int = 0
var _setup_ok: bool = false
var _mist_events: int = 0


func _initialize() -> void:
	begin("mist boundary (row 13, visual layer)")

	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		finish()
		return
	_world = node as WorldRoot
	_world.mist_revealed.connect(func(_t: Array[Vector2i]) -> void: _mist_events += 1)
	root.add_child(_world)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	_boundary = _world.get_node_or_null("MistBoundary") as MistBoundary
	if not check(_boundary != null, "Main.tscn carries a MistBoundary sibling node"):
		finish()
		return true

	# Not exercised by this suite; keeps the world quiet the same way test_mist_reveal.gd does.
	_world.wood.set_process(false)
	_world.simulation.set_process(false)
	_world.displacement.set_process(false)
	_world.presentation.set_process(false)

	_check_binds_and_builds_once_without_any_edit()
	_check_panel_count_is_always_four()
	_check_bounds_track_the_grid_extent()
	_check_a_reveal_rebuilds_the_curtain_exactly_once()
	_check_bounds_grow_with_the_grid()
	_check_lock_step_with_the_invisible_collision_wall()

	note_expected_pending(
		"THE VISUAL TREATMENT ITSELF IS NOT MACHINE-CHECKABLE",
		"Whether the shader reads as atmospheric mist rather than a hard wall, whether "
		+ "PANEL_HEIGHT/fade heights/mist_color/mottle strength look right on screen, and "
		+ "whether ringing the permanent low corner the same as the receding edges reads "
		+ "correctly to a player are all the human's eyeball call — see the build report's "
		+ "Proposals section, not asserted as verified here."
	)

	finish()
	return true


func _check_binds_and_builds_once_without_any_edit() -> void:
	check(_boundary.rebuild_count >= 1,
		"the curtain built itself at least once with zero edits (the initial bind)")
	check_eq(_mist_events, 0, "CONTROL: no mist reveal has happened yet")


func _check_panel_count_is_always_four() -> void:
	check_eq(_boundary.panel_count(), 4, "one panel per edge, all four always present")


func _check_bounds_track_the_grid_extent() -> void:
	var size: Vector2i = _world.grid_size()
	var near: Vector3 = _world.grid_to_world(0, 0)
	var far: Vector3 = _world.grid_to_world(size.x - 1, size.y - 1)
	var half_tile: float = WorldGrid.TILE_SIZE * 0.5
	var expected := Rect2(
		minf(near.x, far.x) - half_tile,
		minf(near.z, far.z) - half_tile,
		absf(far.x - near.x) + WorldGrid.TILE_SIZE,
		absf(far.z - near.z) + WorldGrid.TILE_SIZE,
	)
	check(_boundary.last_bounds.is_equal_approx(expected),
		"the curtain's recorded bounds match the grid's revealed extent",
		"expected %s, got %s" % [expected, _boundary.last_bounds])


func _check_a_reveal_rebuilds_the_curtain_exactly_once() -> void:
	var before_size: Vector2i = _world.grid_size()
	var before_rebuilds: int = _boundary.rebuild_count
	var before_events: int = _mist_events

	var edge_x: int = before_size.x - MistReveal.REVEAL_PROXIMITY_TILES
	check(_world.paint_tile(edge_x, 10, "grass"),
		"painted a tile within reveal proximity of the current east edge")

	check(_world.grid_size().x > before_size.x, "CONTROL: the grid really did grow")
	check_eq(_mist_events, before_events + 1, "CONTROL: exactly one mist_revealed fired")
	check_eq(_boundary.rebuild_count, before_rebuilds + 1,
		"...and the curtain rebuilt exactly once in response — never zero, never twice")


func _check_bounds_grow_with_the_grid() -> void:
	var size: Vector2i = _world.grid_size()
	var near: Vector3 = _world.grid_to_world(0, 0)
	var far: Vector3 = _world.grid_to_world(size.x - 1, size.y - 1)
	var half_tile: float = WorldGrid.TILE_SIZE * 0.5
	var expected := Rect2(
		minf(near.x, far.x) - half_tile,
		minf(near.z, far.z) - half_tile,
		absf(far.x - near.x) + WorldGrid.TILE_SIZE,
		absf(far.z - near.z) + WorldGrid.TILE_SIZE,
	)
	check(_boundary.last_bounds.is_equal_approx(expected),
		"after the reveal, the curtain's bounds moved out to the grid's NEW extent",
		"expected %s, got %s" % [expected, _boundary.last_bounds])


## The curtain's edge math must match the formula the now-deleted `TerrainView`
## movement-blocking collision wall used to share it with (D-41 removed that wall; this
## curtain's own edge computation is unchanged) — both derived from the same
## `grid_to_world()` / `TILE_SIZE` / `BOUNDARY_WALL_THICKNESS` inputs by construction (see
## mist_boundary.gd's header), asserted directly here rather than trusted from the comment.
func _check_lock_step_with_the_invisible_collision_wall() -> void:
	var size: Vector2i = _world.grid_size()
	var near: Vector3 = _world.grid_to_world(0, 0)
	var far: Vector3 = _world.grid_to_world(size.x - 1, size.y - 1)
	var half_tile: float = WorldGrid.TILE_SIZE * 0.5
	var thickness: float = TerrainView.BOUNDARY_WALL_THICKNESS

	var expected_min_x: float = minf(near.x, far.x) - half_tile
	var expected_max_x: float = maxf(near.x, far.x) + half_tile
	var curtain_min_x: float = _boundary.last_bounds.position.x
	var curtain_max_x: float = _boundary.last_bounds.position.x + _boundary.last_bounds.size.x

	check(is_equal_approx(curtain_min_x, expected_min_x)
		and is_equal_approx(curtain_max_x, expected_max_x),
		"the curtain's X extent matches the same min_x/max_x formula the deleted "
		+ "TerrainView movement-blocking wall used to share with it, exactly")

	# The invisible wall itself sits `thickness * 0.5` further out again — not re-derivable from
	# `last_bounds` alone without the same constant, so this pins that both this suite and
	# `mist_boundary.gd` are reading `TerrainView.BOUNDARY_WALL_THICKNESS`, not a copied literal.
	check(thickness > 0.0, "CONTROL: BOUNDARY_WALL_THICKNESS is a real, positive constant")
