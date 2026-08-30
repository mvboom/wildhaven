extends QATestCase
## A PLACED BUILDING'S VISUAL SITS CENTERED ON THE TILES IT ACTUALLY RESERVES — including
## multi-tile footprints.
##
## WHY THIS SUITE EXISTS (final whole-branch review, building-variety B1, 2026-08-26):
## `TerrainView._refresh_building_visual()` positioned every building at
## `tile_to_world(origin)` — the center of its ORIGIN TILE. That is correct for a 1x1 and
## silently wrong for anything larger: `WorldGrid.footprint_tiles()` anchors a footprint at
## `origin` and grows it in +x/+z, so a 2x2 block's center is half a tile further along each
## axis than its origin tile's center. The bug was unreachable until `barn.tres` (2x2) became
## the first non-1x1 placeable this project has ever had, at which point a placed Barn
## rendered spilling ~0.3 units outside the tiles it reserves on two sides while the far half
## of its own reserved footprint showed empty ground.
##
## Every building model in the catalog is authored centered on its own local origin (verified
## by measuring all of them), which is what makes "center the node on the footprint" the
## correct rule rather than a per-asset nudge.
##
## Asserted for BOTH cases so the 1x1 path is pinned as a no-op, not just the 2x2 fix:
##   * house (1x1)  -> visual lands exactly on its single reserved tile's center.
##   * barn  (2x2)  -> visual lands exactly on the 2x2 block's center, and the whole mesh
##                     stays inside the four tiles the building reserves.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_building_footprint_alignment.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

## Two well-separated grass pads, each cleared to grass and large enough for a 2x2 plus a
## one-tile margin, so neither placement can be refused for terrain or occupancy reasons.
const HOUSE_PAD := Vector2i(6, 6)
const BARN_PAD := Vector2i(16, 16)
const STYLE_PAD := Vector2i(26, 6)
const PAD_MARGIN: int = 3

## Placement is centered to well under a millimetre; the tolerance only absorbs float noise.
const EPSILON: float = 0.001

var _world: WorldRoot = null
var _frames: int = 0
var _ready_ok: bool = false


func _initialize() -> void:
	begin("building footprint alignment")

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

	# Buildings cost Wood; the default start (50) does not cover both placements.
	_world.wood.add(1000)
	_clear_pad(HOUSE_PAD)
	_clear_pad(BARN_PAD)
	_clear_pad(STYLE_PAD)

	_check_building("house", HOUSE_PAD, Vector2i(1, 1))
	_check_building("barn", BARN_PAD, Vector2i(2, 2))
	_check_house_style_default_variant()

	finish()
	return true


## Paints a square of grass around `pad` so `terrain_allows()` cannot refuse the placement
## for a reason this suite is not testing.
func _clear_pad(pad: Vector2i) -> void:
	for dz in range(-1, PAD_MARGIN):
		for dx in range(-1, PAD_MARGIN):
			_world.grid.set_terrain(pad.x + dx, pad.y + dz, "grass")


func _check_building(id: String, origin: Vector2i, expected_footprint: Vector2i) -> void:
	var def: PlaceableDefinition = _world.buildings.definition(id)
	if not check(def != null, "%s has a PlaceableDefinition" % id):
		return
	# Pins the fixture's own premise: if the human re-rules barn to 1x1, this check fails
	# loudly here rather than letting the 2x2 case quietly stop being tested.
	check_eq(def.footprint, expected_footprint,
		"%s footprint is %s (this suite's 1x1-vs-multi-tile coverage depends on it)"
			% [id, expected_footprint])

	if not check(_world.place_building(origin.x, origin.y, id),
			"%s places at %s" % [id, origin]):
		return

	var tiles: Array[Vector2i] = WorldGrid.footprint_tiles(origin, def)
	check_eq(tiles.size(), def.footprint.x * def.footprint.y,
		"%s reserves %d tile(s)" % [id, def.footprint.x * def.footprint.y])

	# The reserved block's true center: midpoint of its lowest and highest tile centers.
	var low: Vector3 = _world.grid.tile_to_world(origin.x, origin.y)
	var high: Vector3 = _world.grid.tile_to_world(
		origin.x + def.footprint.x - 1, origin.y + def.footprint.y - 1)
	var block_center: Vector3 = (low + high) * 0.5

	var visual: Node3D = _find_visual(def)
	if not check(visual != null, "%s has a visual under the buildings root" % id):
		return

	check(absf(visual.position.x - block_center.x) <= EPSILON
			and absf(visual.position.z - block_center.z) <= EPSILON,
		"%s visual is centered on its %s footprint, not on its origin tile"
			% [id, def.footprint],
		"visual=(%.4f, %.4f) block center=(%.4f, %.4f)"
			% [visual.position.x, visual.position.z, block_center.x, block_center.z])

	# The stronger, asset-aware half: the mesh itself must stay within the reserved tiles.
	var mesh_aabb: AABB = _composed_aabb(visual)
	var min_x: float = low.x - WorldGrid.TILE_SIZE * 0.5
	var max_x: float = high.x + WorldGrid.TILE_SIZE * 0.5
	var min_z: float = low.z - WorldGrid.TILE_SIZE * 0.5
	var max_z: float = high.z + WorldGrid.TILE_SIZE * 0.5
	check(mesh_aabb.position.x >= min_x - EPSILON and mesh_aabb.end.x <= max_x + EPSILON
			and mesh_aabb.position.z >= min_z - EPSILON and mesh_aabb.end.z <= max_z + EPSILON,
		"%s mesh stays inside the tiles it reserves (no spill onto neighbours)" % id,
		"mesh X[%.4f, %.4f] Z[%.4f, %.4f] vs reserved X[%.4f, %.4f] Z[%.4f, %.4f]"
			% [mesh_aabb.position.x, mesh_aabb.end.x, mesh_aabb.position.z, mesh_aabb.end.z,
				min_x, max_x, min_z, max_z])


## STYLE-DEFAULT RESOLUTION (sub-project B2, Task 5): a House placed AFTER
## `style_defaults["house"]` names a non-default look must render THAT look, not
## `model_scenes[0]`'s shipped default (HousesFirstAge1Level1/"House") — proves
## `TerrainView._resolve_building_variant()` actually consults `WorldRoot.
## resolve_style_scene()` rather than the pre-feature unconditional `model_scenes[0]`.
##
## Reads `_world.view._building_visuals[STYLE_PAD]` directly (the exact node
## `_refresh_building_visual()` created for THIS placement) rather than searching the tree
## by name, because `_check_building("house", HOUSE_PAD, ...)` already placed an earlier
## House with the default look — a name search scoped to the whole world would find that
## unrelated node and prove nothing about this one.
func _check_house_style_default_variant() -> void:
	_world.style_defaults["house"] = "house_tower_firstage"
	if not check(_world.place_building(STYLE_PAD.x, STYLE_PAD.y, "house"),
			"house places at %s for the style-default check" % STYLE_PAD):
		return
	var visual: Node3D = _world.view._building_visuals.get(STYLE_PAD, null) as Node3D
	if not check(visual != null, "the style-default house has a tracked visual"):
		return
	check_eq(String(visual.name), "HouseTowerFirstage",
		"style_defaults[\"house\"] = \"house_tower_firstage\" renders HouseTowerFirstage.tscn "
		+ "(the tower variant), not model_scenes[0]'s shipped default look (\"House\")")


## The building visual `TerrainView` built for `def`, found by the wrapper scene's root name
## (each wrapper's root is named after the scene file, e.g. `Barn`, `House`).
func _find_visual(def: PlaceableDefinition) -> Node3D:
	var want: String = def.model_scenes[0].resource_path.get_file().get_basename()
	return _search(_world, want)


func _search(node: Node, want: String) -> Node3D:
	if node is Node3D and node.name == want:
		return node as Node3D
	for child: Node in node.get_children():
		var found: Node3D = _search(child, want)
		if found != null:
			return found
	return null


## World-space AABB of every mesh under `node`, composed from LOCAL transforms including
## `node`'s own (which carries the placement position set by `_refresh_building_visual()`).
## Deliberately not `global_transform` — see cultivated_field.tres's header for why that is
## unreliable here.
func _composed_aabb(node: Node3D) -> AABB:
	var state: Dictionary = {"aabb": AABB(), "first": true}
	_walk(node, node.transform, state)
	return state["aabb"] as AABB


func _walk(node: Node, xform: Transform3D, state: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			var world_aabb: AABB = xform * mesh.get_aabb()
			if state["first"]:
				state["aabb"] = world_aabb
				state["first"] = false
			else:
				state["aabb"] = (state["aabb"] as AABB).merge(world_aabb)
	for child: Node in node.get_children():
		var child_xform: Transform3D = xform
		if child is Node3D:
			child_xform = xform * (child as Node3D).transform
		_walk(child, child_xform, state)
