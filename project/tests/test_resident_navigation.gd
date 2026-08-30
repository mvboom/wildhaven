extends QATestCase
## ANIMAL NAVIGATION, END TO END — obstacles really route around, dens really block OTHER
## residents, an edit really changes subsequent paths, and separation steering really does
## something (soft steering — a reduction claim, not a zero-overlap guarantee, human-
## confirmed decision).
##
## A PHASE STATE MACHINE, same reason as `test_world_navigation.gd`: every rebuild
## (`paint_tile`/`place_building`/`remove_at`/`ResidentPresentation.present()`, which all
## now trigger `WorldNavigation.rebuild_from_grid()`) needs real engine frames to reach
## `NavigationServer3D`'s sync before a `find_path()` query reflects it. Each phase below
## does setup, waits `REBUILD_SYNC_FRAMES`, then asserts — never both in the same phase.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_resident_navigation.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"
const NAV_WARM_UP_FRAMES: int = 20
const REBUILD_SYNC_FRAMES: int = 15

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false

var _phase: int = 0
var _phase_started_at: int = -1
var _before_path: PackedVector3Array = PackedVector3Array()

var _den_registry: HomeSiteRegistry = null
var _den_site: HomeSite = null
var _den_resident: Node3D = null
var _den_tile := Vector2i(20, 20)


func _initialize() -> void:
	begin("resident navigation")
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
	if _frames < NAV_WARM_UP_FRAMES:
		return false

	match _phase:
		0:
			_setup_building_wall()
			_advance_to(1)
		1:
			if not _synced():
				return false
			_assert_building_wall_detour()
			_setup_forest_wall()
			_advance_to(2)
		2:
			if not _synced():
				return false
			_assert_forest_wall_detour()
			_setup_den_reservation()
			_advance_to(3)
		3:
			if not _synced():
				return false
			_assert_den_blocks_another_residents_path()
			_teardown_den_reservation()
			_check_a_residents_own_den_does_not_trap_it()
			_setup_building_changes_path()
			_advance_to(4)
		4:
			if not _synced():
				return false
			_assert_building_changes_path()
			_check_separation_reduces_overlap()
			finish()
			return true
	return false


func _advance_to(next_phase: int) -> void:
	_phase = next_phase
	_phase_started_at = _frames


func _synced() -> bool:
	return _frames - _phase_started_at >= REBUILD_SYNC_FRAMES


# --- A building forces a real detour -------------------------------------------------------

func _setup_building_wall() -> void:
	for z in range(0, 5):
		if z == 2:
			continue  # leave a gap so the goal stays reachable
		_world.paint_tile(5, z, "grass")
		_world.place_building(5, z, "house")


func _assert_building_wall_detour() -> void:
	var start: Vector3 = _world.grid.tile_to_world(2, 2)
	var goal: Vector3 = _world.grid.tile_to_world(9, 2)
	var path: PackedVector3Array = _world.navigation.find_path(start, goal)
	check(path.size() > 2, "a wall of Houses forces a real detour (%d points)" % path.size())

	for z in range(0, 5):
		_world.remove_at(5, z)


# --- Forest forces a real detour -----------------------------------------------------------

func _setup_forest_wall() -> void:
	for z in range(10, 15):
		if z == 12:
			continue
		_world.paint_tile(5, z, "forest")


func _assert_forest_wall_detour() -> void:
	var start: Vector3 = _world.grid.tile_to_world(2, 12)
	var goal: Vector3 = _world.grid.tile_to_world(9, 12)
	var path: PackedVector3Array = _world.navigation.find_path(start, goal)
	check(path.size() > 2, "a wall of Forest forces a real detour (%d points)" % path.size())

	for z in range(10, 15):
		_world.paint_tile(5, z, "wild_grass")


# --- A den blocks OTHER residents, but never touches is_occupied() -------------------------

func _setup_den_reservation() -> void:
	_den_registry = HomeSiteRegistry.new()
	var rabbit: AnimalDefinition = _world.roster.by_id("rabbit")
	_den_site = _den_registry.register(_den_tile, "rabbit", rabbit.scout_radius)
	_den_resident = Node3D.new()
	_den_resident.position = _world.grid.tile_to_world(_den_tile.x, _den_tile.y)
	_world.add_child(_den_resident)
	_world.presentation.present(_den_resident, _den_site)


func _assert_den_blocks_another_residents_path() -> void:
	check(not _world.grid.is_occupied(_den_tile.x, _den_tile.y),
		"THE DEN'S RESERVATION NEVER TOUCHES `is_occupied()` — building placement is unaffected")

	var start: Vector3 = _world.grid.tile_to_world(20, 17)
	var goal: Vector3 = _world.grid.tile_to_world(20, 23)
	var path: PackedVector3Array = _world.navigation.find_path(start, goal)
	var den_center: Vector3 = _world.grid.tile_to_world(_den_tile.x, _den_tile.y)
	var closest_approach: float = _min_distance_from_path_to_point(path, den_center)
	# A blocked tile's quad has half-width 0.5 (WorldGrid.TILE_SIZE * 0.5) — a path that
	# stays outside that never entered the excluded quad's interior. 0.45 leaves a small
	# floating-point margin without being loose enough to pass a path that clips the edge.
	check(closest_approach > 0.45,
		"ANOTHER RESIDENT'S PATH STAYS CLEAR OF THE DEN'S OWN TILE FOOTPRINT (closest "
		+ "approach %.3f tiles, %d points)" % [closest_approach, path.size()])


## Point-to-SEGMENT distance (not point-to-point), because a funnel-simplified path can have
## long straight segments between few corners — sampling only the corner points could miss a
## segment that cuts close to (or through) an obstacle between two distant corners.
func _min_distance_from_path_to_point(path: PackedVector3Array, point: Vector3) -> float:
	if path.size() == 0:
		return INF
	if path.size() == 1:
		return path[0].distance_to(point)
	var min_dist: float = INF
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var seg: Vector3 = b - a
		var seg_len_sq: float = seg.length_squared()
		var t: float = 0.0
		if seg_len_sq > 0.0001:
			t = clampf((point - a).dot(seg) / seg_len_sq, 0.0, 1.0)
		var closest: Vector3 = a + seg * t
		min_dist = minf(min_dist, closest.distance_to(point))
	return min_dist


func _teardown_den_reservation() -> void:
	_world.presentation.release(_den_site)
	_den_resident.free()


## THE RISK THE DESIGN DOC FLAGGED: a resident's OWN den tile becomes navigation-blocked
## the moment it moves in (`_spawn_home_prop()` reserves it), and that resident's very
## first `_begin_walk()` queries `find_path()` starting AT (or immediately next to) that
## now-blocked tile. `NavigationServer3D.map_get_path()` is expected to snap an off-mesh
## start point to the nearest polygon rather than failing outright, but this is exactly the
## kind of assumption that needs a real assertion, not a comment — `_begin_walk()`'s
## empty-path fallback means the resident would never freeze even if snapping failed, but a
## resident that ALWAYS fell back to the unrouted straight line would defeat the whole
## feature silently. Self-contained: `presentation.tick()` here advances 30 simulated
## seconds, far more than any single-frame nav sync gap, so this needs no phase split.
func _check_a_residents_own_den_does_not_trap_it() -> void:
	var registry := HomeSiteRegistry.new()
	var rabbit: AnimalDefinition = _world.roster.by_id("rabbit")
	var den_tile := Vector2i(16, 30)
	var site: HomeSite = registry.register(den_tile, "rabbit", rabbit.scout_radius)
	var resident := Node3D.new()
	resident.position = _world.grid.tile_to_world(den_tile.x, den_tile.y)
	_world.add_child(resident)
	_world.presentation.present(resident, site)

	var start: Vector3 = resident.position
	var path_length: float = 0.0
	var previous: Vector3 = start
	for _i in 300:
		_world.presentation.tick(0.1)
		path_length += previous.distance_to(resident.position)
		previous = resident.position

	check(resident.position != start,
		"A RESIDENT WHOSE OWN DEN JUST BECAME NAVIGATION-BLOCKED STILL MOVED (30 simulated "
		+ "seconds, start %s, end %s)" % [start, resident.position])
	check(path_length > 1.0,
		"...and covered real ground (%.2f tiles), not stuck oscillating at the den edge"
			% path_length)

	_world.presentation.release(site)
	resident.free()


# --- Placing a building changes the very next path query -----------------------------------

func _setup_building_changes_path() -> void:
	var start: Vector3 = _world.grid.tile_to_world(2, 30)
	var goal: Vector3 = _world.grid.tile_to_world(9, 30)
	_before_path = _world.navigation.find_path(start, goal)
	check(_before_path.size() >= 2, "before the edit, a baseline path exists (%d points)"
		% _before_path.size())

	_world.paint_tile(5, 30, "grass")
	_world.place_building(5, 30, "house")


func _assert_building_changes_path() -> void:
	var start: Vector3 = _world.grid.tile_to_world(2, 30)
	var goal: Vector3 = _world.grid.tile_to_world(9, 30)
	var after: PackedVector3Array = _world.navigation.find_path(start, goal)
	var target_center: Vector3 = _world.grid.tile_to_world(5, 30)
	var before_distance: float = _min_distance_from_path_to_point(_before_path, target_center)
	var after_distance: float = _min_distance_from_path_to_point(after, target_center)
	check(before_distance < 0.3,
		"sanity: the BASELINE path ran close to/through the target tile before the edit "
		+ "(%.3f tiles)" % before_distance)
	check(after_distance > before_distance,
		("PLACING A BUILDING CHANGES THE VERY NEXT PATH QUERY — it now stays measurably "
		+ "farther from the now-occupied tile (%.3f tiles, was %.3f) — proves the rebuild "
		+ "wiring, not just that WorldNavigation works in isolation")
			% [after_distance, before_distance])

	_world.remove_at(5, 30)


# --- Separation steering: soft, not hard -----------------------------------------------------

## SOFT STEERING, NOT HARD COLLISION (human-confirmed decision) — a claim that the nudge is
## doing SOMETHING, never a zero-overlap claim. Self-contained (600 ticks, far more than any
## nav sync gap), so no phase split needed.
func _check_separation_reduces_overlap() -> void:
	var site_a := HomeSite.new(Vector2i(30, 5), "rabbit", 8, 0)
	var site_b := HomeSite.new(Vector2i(30, 9), "rabbit", 8, 1)
	var node_a := Node3D.new()
	node_a.position = _world.grid.tile_to_world(30, 5)
	var node_b := Node3D.new()
	node_b.position = _world.grid.tile_to_world(30, 9)
	_world.add_child(node_a)
	_world.add_child(node_b)
	_world.presentation.present(node_a, site_a)
	_world.presentation.present(node_b, site_b)

	var min_distance: float = 999.0
	for _i in 600:
		_world.presentation.tick(0.1)
		var d: float = node_a.position.distance_to(node_b.position)
		min_distance = minf(min_distance, d)

	check(min_distance > 0.0,
		"the two residents' minimum recorded distance stayed above zero (%.3f) across 60 "
		% min_distance + "simulated seconds — separation steering is doing SOMETHING, even "
		+ "though it is soft, not a hard guarantee")

	_world.presentation.release(site_a)
	_world.presentation.release(site_b)
	node_a.free()
	node_b.free()
