extends QATestCase
## Confirms D-33's movement-blocking machinery is gone (→ D-41: nothing walks, so
## nothing needs to collide) while picking still works exactly as before.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_terrain_view_no_blocking.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("terrain view: no movement-blocking collision")
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

	# Verify removal by BEHAVIOR, not script-source introspection: paint a forest tile (the
	# terrain id that used to be impassable) and confirm no movement-blocking body was ever
	# created for it. `_refresh_tile_blocking()` used to name these bodies "Blocker_<x>_<z>";
	# that node simply shouldn't exist anywhere under TerrainView anymore.
	_world.paint_tile(5, 5, "forest")
	var view: TerrainView = _world.view
	check(
		view.get_node_or_null("Blocker_5_5") == null,
		"no movement-blocking body was created for a forest tile"
	)
	# Picking must still work: confirm screen_to_grid()
	# still resolves it (this used to also carry a movement blocker on top).
	var world_pos: Vector3 = _world.grid_to_world(5, 5)
	var camera: Camera3D = root.get_viewport().get_camera_3d()
	(camera as CameraRig).initialize()
	(camera as CameraRig).set_focus(world_pos)
	(camera as CameraRig).set_zoom_tiles(CameraRig.ZOOM_MIN_TILES)
	var screen: Vector2 = camera.unproject_position(world_pos)
	var picked: Vector2i = _world.screen_to_grid(screen)
	check_eq(picked, Vector2i(5, 5), "tapping a forest tile still resolves via screen_to_grid()")
	finish()
	return true
