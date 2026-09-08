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
## CORRECTED 2026-09-07 — this header used to claim "every building model in the catalog is
## authored centered on its own local origin (verified by measuring all of them)". THAT WAS
## FALSE, and it was false because this suite only ever placed TWO of the ten buildables, so
## "all of them" was never actually measured through this code path. A full audit found EIGHT
## off-centre wrappers, and `windmill` was live-spilling 0.0675 units onto its neighbouring
## tile. Each was corrected in its own `.tscn` by a translation equal to the negation of its
## measured AABB centre (see any wrapper's header); the rule "centre the node on the footprint"
## is right, but it only holds once the mesh is centred on its own origin, which is an asset
## fact this suite must verify rather than assume.
##
## SO THIS NOW PLACES EVERY BUILDABLE, not a hand-picked two. That is the whole fix: a
## per-asset defect class cannot be covered by a per-asset opt-in list, because the asset
## nobody added to the list is exactly the one that rots. The catalog is read from
## `placeable_options()` at runtime, so a buildable added later is covered the day it lands
## without anyone remembering to come back here.
##
## Two cases still carry named, pinned expectations on top of the generic sweep, because they
## are what the ORIGINAL 2x2 bug was about and a re-ruling of either would silently gut the
## coverage:
##   * house (1x1)  -> visual lands exactly on its single reserved tile's center.
##   * barn  (2x2)  -> visual lands exactly on the 2x2 block's center, and the whole mesh
##                     stays inside the four tiles the building reserves.
## Both are pinned by ID (in `EXPECTED_FOOTPRINTS`), never by catalog position — see the pad
## comment below for why an earlier draft's position-pinning was wrong.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_building_footprint_alignment.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

## Well-separated grass pads, each cleared to grass and large enough for a 2x2 plus a one-tile
## margin, so no placement can be refused for terrain or occupancy reasons. Pads are GENERATED
## on a 6-by-8 lattice (`_pad_for()`) rather than listed, because the count now follows the
## catalog size rather than a hand-maintained list.
##
## No buildable gets a NAMED pad any more. An earlier draft of this rewrite kept HOUSE_PAD and
## BARN_PAD and asserted that house and barn landed on them; that pinned a buildable's INDEX in
## `placeable_options()`, which is not a fact this suite has any business defending — reordering
## the catalog is not a bug, and the assertion failed the moment the real order was read. What
## actually needs pinning about those two is their FOOTPRINTS (`EXPECTED_FOOTPRINTS` below) and
## their presence in the catalog at all (the sweep's own missing-buildable check), both of which
## are asserted by name and neither of which cares where the building was put down.
const PAD_MARGIN: int = 3

## The style-default check needs its own pad, taken from the far end of the lattice so it can
## never collide with a catalog pad however long the catalog grows.
const STYLE_PAD := Vector2i(28, 28)

## Pinned footprints for the whole catalog — the fixture premise, stated once. A human
## re-ruling any of these fails HERE, loudly, rather than quietly changing what this suite
## thinks it is covering (the original reason `barn`'s 2x2 was pinned; generalised 2026-09-07).
## RE-PINNED 2026-09-08 — the eight 1x1 entries became 2x2 (footprint-deepening trial, human
## ruling), and their wrapper meshes were doubled to the 1.738618 long-axis target Barn already
## used. NOTE THE COVERAGE LOSS THIS CREATES, deliberately not papered over: with every buildable
## at 2x2 this suite no longer exercises a 1x1 footprint at all, so the "1x1-vs-multi-tile"
## premise stated below is intact again: the chicken coop and the well were ruled back to 1x1
## on 2026-09-08, so this suite still covers 1x1, 2x2 and (with the Large Barn and Farmhouse) 3x3.
const EXPECTED_FOOTPRINTS: Dictionary = {
	"house": Vector2i(2, 2),
	"farmhouse": Vector2i(3, 3),
	"barn": Vector2i(3, 3),
	"small_barn": Vector2i(2, 2),
	"open_barn": Vector2i(2, 2),
	"chicken_coop": Vector2i(1, 1),
	"silo": Vector2i(2, 2),
	"windmill": Vector2i(2, 2),
	"water_tower": Vector2i(2, 2),
	"well": Vector2i(1, 1),
}

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

	# Buildings cost Wood; the default start (50) does not cover the whole catalog.
	_world.wood.add(100000)

	# EVERY buildable, on its own pad. Order follows placeable_options() so the pad a given
	# building lands on is stable across runs, which keeps a failure message reproducible.
	var options: Array[PlaceableDefinition] = _world.placeable_options()
	check(options.size() >= EXPECTED_FOOTPRINTS.size(),
		"the catalog has at least the %d buildables this suite pins footprints for (got %d)"
			% [EXPECTED_FOOTPRINTS.size(), options.size()])
	var seen: Array[String] = []
	for i in options.size():
		var def: PlaceableDefinition = options[i]
		var pad: Vector2i = _pad_for(i)
		_clear_pad(pad)
		seen.append(def.id)
		_check_building(def.id, pad, EXPECTED_FOOTPRINTS.get(def.id, def.footprint) as Vector2i)

	# A buildable this suite pins but the catalog no longer offers would otherwise vanish
	# silently — the sweep above can only check what it is handed.
	for id: String in EXPECTED_FOOTPRINTS.keys():
		check(seen.has(id),
			"the pinned buildable '%s' is still in the catalog and was placed" % id)

	_clear_pad(STYLE_PAD)
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

	var visual: Node3D = _find_visual(origin)
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
## `model_scenes[0]`'s shipped default (`house_large`) — proves
## `TerrainView._resolve_building_variant()` actually consults `WorldRoot.
## resolve_style_scene()` rather than the pre-feature unconditional `model_scenes[0]`.
##
## Reads `_world.view._building_visuals[STYLE_PAD]` directly (the exact node
## `_refresh_building_visual()` created for THIS placement) rather than searching the tree
## by name, because `_check_building("house", HOUSE_PAD, ...)` already placed an earlier
## House with the default look — a name search scoped to the whole world would find that
## unrelated node and prove nothing about this one.
## RE-POINTED 2026-09-07 (house cull): the non-default look driven here was
## `house_tower_firstage`, which the cull unwired — a style id no longer in `model_scenes` gets
## silently replaced by `get_style_default()`'s stale-id fallback, so the old assertion would
## have tested the fallback while claiming to test resolution, and passed for the wrong reason
## only because the expected node name would then also have been wrong. `house_small` is used
## instead: still a real, wired, NON-index-0 variant, which is the only property this check
## needs.
func _check_house_style_default_variant() -> void:
	_world.style_defaults["house"] = "house_small"
	if not check(_world.place_building(STYLE_PAD.x, STYLE_PAD.y, "house"),
			"house places at %s for the style-default check" % STYLE_PAD):
		return
	var visual: Node3D = _world.view._building_visuals.get(STYLE_PAD, null) as Node3D
	if not check(visual != null, "the style-default house has a tracked visual"):
		return
	check_eq(String(visual.name), "HouseSmall",
		"style_defaults[\"house\"] = \"house_small\" renders HouseSmall.tscn "
		+ "(the \"House - Small\" look), not model_scenes[0]'s default (\"HouseLarge\")")


## Pads on a 6-by-8 lattice, five to a row. Spacing is what keeps two `_clear_pad()` squares
## (each 4x4, from pad-1 to pad+2) from overlapping, so no building can be refused placement
## because a neighbour's pad already reserved its tiles.
func _pad_for(index: int) -> Vector2i:
	return Vector2i(4 + (index % 5) * 6, 4 + (index / 5) * 8)


## The building visual `TerrainView` built for the placement at `origin` — looked up by ORIGIN
## in `_building_visuals`, the exact node that placement created.
##
## CHANGED 2026-09-07 from a search-the-tree-by-node-name lookup. That was safe while this suite
## placed two buildings; with the whole catalog down it is not, because a name search is not
## scoped to the placement under test and `farmhouse`/`house` in particular draw their meshes
## from the same renamed House family. `_check_house_style_default_variant()` below already used
## this exact-lookup shape, and for the same stated reason.
func _find_visual(origin: Vector2i) -> Node3D:
	return _world.view._building_visuals.get(origin, null) as Node3D


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
