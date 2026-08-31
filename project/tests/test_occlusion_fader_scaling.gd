extends QATestCase
## THE FADE SWEEP MUST ONLY DO WORK THAT CAN CHANGE THE ANSWER.
##
## `OcclusionFader.refresh()` runs ten times a second, and at 110 residents it measured 6.5ms
## per call — a single burst, not spread out, which in the single-threaded WASM build is a
## dropped frame ten times a second (`probe_frame_cost.gd`, 2026-08-30). Two thirds of that
## was work that could not possibly affect the outcome:
##
##   1. Phase 2 tested EVERY candidate forest tile against EVERY resident, including
##      residents nowhere near that tile. A resident can only be occluded by a tile within
##      `RESIDENT_CHECK_RADIUS_TILES` of itself — which is precisely the rule phase 1 already
##      used to gather the candidate in the first place — so every other pairing is a ray
##      test whose answer is known in advance.
##   2. `_tile_aabb()` re-walked a tile's scene tree and re-transformed eight corners per mesh
##      on EVERY call, for geometry that only changes when the tile itself is repainted — and
##      `_on_grid_tile_changed()` already exists as the hook that knows when that happens.
##
## ASSERTED ON WORK COUNTERS, NOT ON WALL-CLOCK TIME. `geometry_rebuilds` and
## `occlusion_tests` count the two things the sweep's cost is made of, so these checks are
## exact and machine-independent — a timing threshold would be both flaky and a tuning value,
## which the ground rules make the human's call. `test_occlusion_fader.gd` continues to own
## the question of whether the RIGHT tiles fade; this suite only asserts how much work
## reaching that answer takes.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_occlusion_fader_scaling.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

## The forest the residents actually stand in.
const FOREST_MIN: int = 6
const FOREST_MAX: int = 16
## Residents inside that forest — the ones whose sightlines genuinely need testing.
const NEAR_RESIDENTS: int = 8
## Residents parked in a bare corner, more than `RESIDENT_CHECK_RADIUS_TILES` from any forest
## tile. They contribute no candidates, so they must cost no ray tests at all.
const FAR_RESIDENTS: int = 150
const FAR_MIN: int = 26
const FAR_MAX: int = 34

var _world: WorldRoot = null
var _fader: OcclusionFader = null
var _frames: int = 0
var _setup_ok: bool = false
var _near: Array = []
var _far: Array = []


func _initialize() -> void:
	begin("occlusion fader scaling")
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

	_fader = _world.get_node_or_null("OcclusionFader") as OcclusionFader
	if not check(_fader != null, "Main.tscn has an OcclusionFader node"):
		finish()
		return true

	var camera: CameraRig = root.get_viewport().get_camera_3d() as CameraRig
	if not check(camera != null, "a CameraRig is active"):
		finish()
		return true
	camera.initialize()
	camera.set_focus(_world.grid_to_world(11, 11))

	_paint_forest()
	_spawn_residents()

	_check_far_residents_cost_nothing()
	_check_geometry_is_cached_until_its_tile_changes()

	finish()
	return true


func _paint_forest() -> void:
	for x in range(FOREST_MIN, FOREST_MAX):
		for z in range(FOREST_MIN, FOREST_MAX):
			_world.grid.set_terrain(x, z, "forest")


func _spawn_residents() -> void:
	for i in NEAR_RESIDENTS:
		_near.append(_make_resident(
			FOREST_MIN + 1 + (i % 8), FOREST_MIN + 1 + (i / 8)))
	var span: int = FAR_MAX - FAR_MIN
	for i in FAR_RESIDENTS:
		_far.append(_make_resident(FAR_MIN + (i % span), FAR_MIN + ((i / span) % span)))


func _make_resident(x: int, z: int) -> Node3D:
	var node := Node3D.new()
	node.position = _world.grid_to_world(x, z)
	_world.add_child(node)
	return node


## A resident with no forest within `RESIDENT_CHECK_RADIUS_TILES` cannot be occluded by
## anything, so adding 150 of them must not add a single ray test.
func _check_far_residents_cost_nothing() -> void:
	var with_near: int = _tests_for(_near)
	var with_both: int = _tests_for(_near + _far)
	check(
		with_both == with_near,
		"adding %d residents far from every forest tile adds no occlusion tests (%d vs %d)"
			% [FAR_RESIDENTS, with_both, with_near],
		"phase 2 is pairing every candidate tile with every resident: %d extra ray tests for "
			% [with_both - with_near]
		+ "residents that no candidate tile could possibly occlude."
	)


## Tile geometry is static between repaints, and `_on_grid_tile_changed()` already fires on
## exactly the event that invalidates it.
func _check_geometry_is_cached_until_its_tile_changes() -> void:
	_fader.refresh(_near)  # warm
	var before: int = _fader.geometry_rebuilds
	_fader.refresh(_near)
	var repeat_rebuilds: int = _fader.geometry_rebuilds - before
	check(
		repeat_rebuilds == 0,
		"a repeat sweep over an unchanged world rebuilds no tile geometry (%d rebuilds)"
			% repeat_rebuilds,
		"_tile_aabb() is re-walking the scene tree every call for geometry that has not moved."
	)

	# Invalidate exactly one candidate tile, by repainting it away from forest and back.
	var victim := Vector2i(FOREST_MIN + 2, FOREST_MIN + 2)
	_world.grid.set_terrain(victim.x, victim.y, "grass")
	_world.grid.set_terrain(victim.x, victim.y, "forest")

	before = _fader.geometry_rebuilds
	_fader.refresh(_near)
	var after_repaint: int = _fader.geometry_rebuilds - before
	check(
		after_repaint == 1,
		"repainting one tile rebuilds exactly that one tile's geometry (%d rebuilds)"
			% after_repaint,
		"expected 1 — a repaint must invalidate its own tile and no other. 0 means the cache "
		+ "is stale and the fade would be computed against freed nodes; more than 1 means the "
		+ "whole cache is being dropped for a single tile's change."
	)


func _tests_for(residents: Array) -> int:
	var before: int = _fader.occlusion_tests
	_fader.refresh(residents)
	return _fader.occlusion_tests - before
