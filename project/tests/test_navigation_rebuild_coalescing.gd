extends QATestCase
## A BURST OF EDITS IS ONE NAVMESH REBUILD, NOT ONE PER EDIT.
##
## `WorldNavigation.rebuild_from_grid()` re-scans every tile in the world and hands
## `NavigationServer3D` a whole new mesh. It was being called SYNCHRONOUSLY from each of the
## five `WorldRoot` edit entry points and again from every `set_den_tile_blocked()` — so
## painting one tile cost a full rebuild (2.4ms of a 2.8ms `paint_tile()` call at any
## population, `probe_frame_cost.gd` 2026-08-30), a dragged stroke cost one per tile, and
## every single resident arrival cost another one via its den reservation.
##
## None of those intermediate meshes is ever observed: nothing reads the navmesh between two
## edits in the same frame. Coalescing them is therefore invisible to gameplay and removes
## the entire multiple.
##
## WHY A COUNTER AND NOT A TIMING. `rebuilds_run` counts the exact thing that was happening
## too often, so this suite is deterministic and machine-independent. It also states the
## contract in the only terms that actually matter — "how many times did the expensive thing
## run" — rather than in microseconds, which are a tuning value and the human's call.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_navigation_rebuild_coalescing.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"
## A dragged terraform stroke. Big enough that "one per edit" and "one for the burst" are
## unmistakably different numbers.
const STROKE_TILES: int = 20
## Enough wood that no paint can be refused for cost — a refused paint would silently make
## this suite assert nothing.
const WOOD_GRANT: int = 100000

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("navigation rebuild coalescing")
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	_world = packed.instantiate() as WorldRoot
	root.add_child(_world)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	if not check(_world.navigation != null, "the world built a WorldNavigation"):
		finish()
		return true
	_world.wood.add(WOOD_GRANT)

	_check_a_stroke_is_one_rebuild()
	_check_den_reservations_coalesce()
	_check_a_reader_always_sees_fresh_geometry()

	finish()
	return true


## The player action: many tiles painted before anything reads the navmesh again.
func _check_a_stroke_is_one_rebuild() -> void:
	var painted: int = 0
	var before: int = _world.navigation.rebuilds_run
	for i in STROKE_TILES:
		if _world.paint_tile(2 + i, 30, "forest"):
			painted += 1
	# A read is what forces the pending rebuild to happen, so the burst plus one read is the
	# complete, honest cost of the stroke.
	_world.navigation.find_path(_world.grid_to_world(1, 1), _world.grid_to_world(20, 20))
	var rebuilds: int = _world.navigation.rebuilds_run - before

	if not check(painted == STROKE_TILES,
			"all %d paints in the stroke were accepted (%d were)" % [STROKE_TILES, painted]):
		return
	check(
		rebuilds == 1,
		"a %d-tile stroke costs ONE navmesh rebuild (%d)" % [STROKE_TILES, rebuilds],
		"expected 1 — %d means the navmesh is still being rebuilt synchronously per edit."
			% rebuilds
	)


## The arrival path: `ResidentPresentation` reserves a den tile per move-in, and each
## reservation used to rebuild the whole navmesh on the spot.
func _check_den_reservations_coalesce() -> void:
	var before: int = _world.navigation.rebuilds_run
	for i in STROKE_TILES:
		_world.navigation.set_den_tile_blocked(Vector2i(2 + i, 33), true)
	_world.navigation.find_path(_world.grid_to_world(1, 1), _world.grid_to_world(20, 20))
	var rebuilds: int = _world.navigation.rebuilds_run - before
	check(
		rebuilds == 1,
		"%d den reservations cost ONE navmesh rebuild (%d)" % [STROKE_TILES, rebuilds],
		"expected 1 — every resident arrival reserves a den tile, so one rebuild each is a "
		+ "full navmesh rebuild per move-in."
	)


## COALESCING MUST NEVER MEAN SERVING STALE GEOMETRY. Deferring the rebuild is only safe if
## any reader still observes the edit; this pins that, so a future change that drops the
## pending rebuild entirely fails here rather than as mysterious pathing through a wall.
func _check_a_reader_always_sees_fresh_geometry() -> void:
	_world.navigation.find_path(_world.grid_to_world(1, 1), _world.grid_to_world(20, 20))
	var settled: int = _world.navigation.rebuilds_run

	_world.navigation.set_den_tile_blocked(Vector2i(5, 34), true)
	_world.navigation.find_path(_world.grid_to_world(1, 1), _world.grid_to_world(20, 20))
	check(
		_world.navigation.rebuilds_run == settled + 1,
		"an edit followed by a read rebuilds exactly once, never zero",
		"a read after a pending edit must flush it — got %d rebuild(s)."
			% [_world.navigation.rebuilds_run - settled]
	)

	# ...and a read with nothing pending must not rebuild at all.
	var quiet: int = _world.navigation.rebuilds_run
	_world.navigation.find_path(_world.grid_to_world(1, 1), _world.grid_to_world(20, 20))
	check(
		_world.navigation.rebuilds_run == quiet,
		"a read with no pending edit rebuilds nothing",
		"the dirty flag is not being cleared — every path query is rebuilding the navmesh."
	)
