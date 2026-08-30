extends QATestCase
## WORLD NAVIGATION — the navmesh WorldNavigation builds from grid tile data, and the
## paths NavigationServer3D returns against it.
##
## THE MAP SYNCS ON THE PHYSICS STEP, not synchronously with `rebuild_from_grid()`. A
## rebuild-then-query done within the SAME `_process()` call would read a stale (or, on the
## very first rebuild, empty) path and call it a defect that isn't one — this suite is a
## PHASE STATE MACHINE across many `_process()` calls specifically so real engine frames
## elapse between every rebuild and the query that reads its effect, the same "return false
## to wait a frame" idiom every suite in this project already uses at its outer level,
## applied here at finer granularity within one suite.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_world_navigation.gd

const NAV_WARM_UP_FRAMES: int = 20
const REBUILD_SYNC_FRAMES: int = 15

var _frames: int = 0
var _navigation: WorldNavigation = null
var _grid: WorldGrid = null

var _phase: int = 0
var _phase_started_at: int = -1
var _before_path: PackedVector3Array = PackedVector3Array()


func _initialize() -> void:
	begin("world navigation")
	_grid = WorldGrid.new()
	_grid.build(TerrainDefinition.load_all(), 10, 10)
	root.add_child(_grid)
	_navigation = WorldNavigation.new()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < NAV_WARM_UP_FRAMES:
		return false

	match _phase:
		0:
			# Baseline: nothing blocks yet.
			_navigation.rebuild_from_grid(_grid)
			_advance_to(1)
		1:
			if not _synced():
				return false
			_check_open_grid_paths_straight()
			for z in range(0, 10):
				if z == 5:
					continue  # leave one gap so the goal stays reachable
				_grid.set_terrain(5, z, "forest")
			_navigation.rebuild_from_grid(_grid)
			_advance_to(2)
		2:
			if not _synced():
				return false
			_check_forest_tile_forces_a_detour()
			for z in range(0, 10):
				_grid.set_terrain(5, z, "wild_grass")
			var house := PlaceableDefinition.new()
			house.id = "test_house"
			house.footprint = Vector2i(1, 1)
			for z in range(0, 10):
				if z == 5:
					continue
				_grid.set_building(Vector2i(5, z), house)
			_navigation.rebuild_from_grid(_grid)
			_advance_to(3)
		3:
			if not _synced():
				return false
			_check_building_tile_forces_a_detour()
			for z in range(0, 10):
				_grid.clear_building(Vector2i(5, z))
			_navigation.rebuild_from_grid(_grid)
			for z in range(0, 10):
				if z == 5:
					continue
				_navigation.set_den_tile_blocked(Vector2i(5, z), true)
			_advance_to(4)
		4:
			if not _synced():
				return false
			_check_den_tile_forces_a_detour()
			for z in range(0, 10):
				_navigation.set_den_tile_blocked(Vector2i(5, z), false)
			_advance_to(5)
		5:
			if not _synced():
				return false
			_before_path = _navigation.find_path(
				_grid.tile_to_world(1, 1), _grid.tile_to_world(8, 1)
			)
			check(_before_path.size() >= 2,
				"before any wall, a baseline path exists (%d points) — the claim this "
				+ "phase exists for is the NEXT check's comparison against a wall, not "
				+ "this count in isolation" % _before_path.size())
			for z in range(0, 10):
				if z == 5:
					continue
				_grid.set_terrain(5, z, "forest")
			_navigation.rebuild_from_grid(_grid)
			_advance_to(6)
		6:
			if not _synced():
				return false
			var after: PackedVector3Array = _navigation.find_path(
				_grid.tile_to_world(1, 1), _grid.tile_to_world(8, 1)
			)
			check(after.size() > _before_path.size(),
				"AFTER rebuild, the SAME start/goal query detours (%d points, was %d)"
					% [after.size(), _before_path.size()])
			for z in range(0, 10):
				_grid.set_terrain(5, z, "wild_grass")
			_navigation.free_navigation()
			_grid.free()
			finish()
			return true
	return false


func _advance_to(next_phase: int) -> void:
	_phase = next_phase
	_phase_started_at = _frames


func _synced() -> bool:
	return _frames - _phase_started_at >= REBUILD_SYNC_FRAMES


## An all-`wild_grass` grid (nothing blocks) — a straight line, corner count small.
func _check_open_grid_paths_straight() -> void:
	var start: Vector3 = _grid.tile_to_world(1, 1)
	var goal: Vector3 = _grid.tile_to_world(8, 8)
	var path: PackedVector3Array = _navigation.find_path(start, goal)
	check(path.size() >= 2, "an open grid returns a real path (%d points)" % path.size())
	check(path[0].distance_to(start) < 1.0, "the path starts near the query start")
	check(path[path.size() - 1].distance_to(goal) < 1.0, "the path ends near the query goal")


## Painting a straight wall of Forest between start and goal forces a real detour — not a
## straight line through where the trees are.
func _check_forest_tile_forces_a_detour() -> void:
	var start: Vector3 = _grid.tile_to_world(1, 1)
	var goal: Vector3 = _grid.tile_to_world(8, 1)
	var path: PackedVector3Array = _navigation.find_path(start, goal)
	check(path.size() > 2,
		"a Forest wall forces a MULTI-CORNER detour (%d points), not a straight line"
			% path.size())
	var passed_through_the_gap: bool = false
	for p: Vector3 in path:
		var tile: Vector2i = _grid.world_to_tile(p)
		if tile.x == 5 and tile.y == 5:
			passed_through_the_gap = true
	check(passed_through_the_gap, "...and the detour actually uses the one open gap (5,5)")


## A building-occupied tile (`is_occupied()`) blocks exactly like a blocked terrain tile —
## no schema change needed for buildings, `WorldGrid.is_occupied()` is read directly.
func _check_building_tile_forces_a_detour() -> void:
	var start: Vector3 = _grid.tile_to_world(1, 1)
	var goal: Vector3 = _grid.tile_to_world(8, 1)
	var path: PackedVector3Array = _navigation.find_path(start, goal)
	check(path.size() > 2,
		"a wall of BUILDINGS forces a detour too (%d points) — is_occupied() blocks"
			% path.size())


## `set_den_tile_blocked()` — the navigation-only reservation, distinct from both terrain
## and `is_occupied()` — blocks a path exactly like the other two, and never touches
## `WorldGrid.is_occupied()`.
func _check_den_tile_forces_a_detour() -> void:
	var start: Vector3 = _grid.tile_to_world(1, 1)
	var goal: Vector3 = _grid.tile_to_world(8, 1)
	var path: PackedVector3Array = _navigation.find_path(start, goal)
	check(path.size() > 2,
		"a wall of DEN reservations forces a detour too (%d points)" % path.size())
	check(not _grid.is_occupied(5, 5),
		"...and none of it ever touched WorldGrid.is_occupied() — den reservations are "
		+ "navigation-only")
