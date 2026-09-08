extends QATestCase
## ERASING A BUILDING TAKES ITS MODEL OFF THE MAP.
##
## WHY THIS SUITE EXISTS (2026-09-08, reported from play: "the erase button does not work
## with Buildings, only terrain"). `WorldRoot.remove_at()` cleared the building out of
## `WorldGrid` correctly — the tiles freed, the refund landed, the habitat re-ran — but the
## MESH STAYED STANDING, so to the player nothing had happened and the tool read as broken.
##
## The cause was an ordering fact in `TerrainView._on_tile_changed()`: it asked the grid
## which building owns the changed tile and refreshed that origin's visual. `clear_building()`
## writes `Vector2i(-1, -1)` into every footprint tile BEFORE it emits `tile_changed`, so by
## the time the view is told, the tile can no longer name the building that just left, and the
## refresh — the only code that frees a building node — was skipped every single time.
##
## Terraform reverts were unaffected (they change terrain, which `TerrainChunkLod` redraws
## from the tile itself), which is exactly why the bug read as "buildings only".
##
## Covers 1x1 and multi-tile footprints: a 2x2's non-origin tiles take the same path.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_building_removal_visual.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

## One pad per case, far enough apart that no cleared square overlaps another.
const HOUSE_PAD := Vector2i(6, 6)
const BARN_PAD := Vector2i(14, 6)
const PAD_MARGIN: int = 3

var _world: WorldRoot = null
var _frames: int = 0
var _ready_ok: bool = false


func _initialize() -> void:
	begin("building removal visual")

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
	_ready_ok = true


func _process(_delta: float) -> bool:
	if not _ready_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	_world.wood.add(100000)

	# 1x1: erased on its own tile, the only tile it has.
	_check_removal("house", HOUSE_PAD, HOUSE_PAD)
	# 2x2: erased by tapping a NON-ORIGIN tile, the path a player is most likely to take and
	# the one that has to resolve the whole footprint's building rather than the tile's own.
	_check_removal("barn", BARN_PAD, BARN_PAD + Vector2i(1, 1))

	finish()
	return true


## Places `id` at `origin`, erases it by tapping `erase_tile`, and asserts that both the grid
## and the view forgot it.
func _check_removal(id: String, origin: Vector2i, erase_tile: Vector2i) -> void:
	_clear_pad(origin)
	if not check(_world.place_building(origin.x, origin.y, id),
			"%s places at %s" % [id, origin]):
		return
	var visual: Node3D = _world.view._building_visuals.get(origin, null) as Node3D
	if not check(visual != null, "%s has a visual after placement" % id):
		return

	if not check(_world.remove_at(erase_tile.x, erase_tile.y),
			"remove_at%s erases the %s" % [erase_tile, id]):
		return

	check(not _world.grid.is_occupied(origin.x, origin.y),
		"%s's origin tile is free in the grid after the erase" % id)
	check(not _world.view._building_visuals.has(origin),
		"%s's visual is no longer tracked by TerrainView" % id)
	check(not is_instance_valid(visual) or visual.is_queued_for_deletion(),
		"%s's model is gone from the world (this is what the player sees)" % id)


func _clear_pad(pad: Vector2i) -> void:
	for dz in range(-1, PAD_MARGIN):
		for dx in range(-1, PAD_MARGIN):
			_world.grid.set_terrain(pad.x + dx, pad.y + dz, "grass")
