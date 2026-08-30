class_name WorldNavigation
extends RefCounted
## Builds a `NavigationServer3D` navmesh DIRECTLY FROM `WorldGrid`'s tile data — one quad
## per open tile, no quad for a blocked one. No mesh geometry is ever baked, and no
## collision shape is ever added to any prop/tree/building — a tile is either walkable or
## it is not, and that is the entire input.
##
## VERIFIED HEADLESS (throwaway spike, 2026-08-24, see the design doc): a hand-built
## `NavigationMesh` registered this way produces genuine multi-corner detour paths under
## `--headless --script`, no rendering, no `NavigationAgent3D` node required. The map takes
## several physics frames to sync after a region change before `map_get_path()` reflects
## it — callers in real gameplay never notice (frames pass constantly); test suites must
## wait for it explicitly (see `test_world_navigation.gd`).
##
## A tile is blocked when ANY of: `WorldGrid.is_occupied()` (a building),
## `TerrainDefinition.blocks_movement` (Forest, in this pass), or a navigation-only DEN
## reservation set via `set_den_tile_blocked()` — which deliberately does NOT touch
## `WorldGrid.is_occupied()`, so building placement and capacity math are unaffected by a
## den's presence (`ResidentPresentation._spawn_home_prop()`/`release()` are the only
## callers of that method).

var _map: RID
var _region: RID
var _den_tiles: Dictionary = {}  # Vector2i -> true
var _grid: WorldGrid = null


func _init() -> void:
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(_map, true)
	NavigationServer3D.map_set_cell_size(_map, 0.25)
	_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(_region, _map)
	NavigationServer3D.region_set_enabled(_region, true)


## Full re-scan of `grid` — one quad per tile that is not blocked. Rare event (a world
## edit), not a per-frame cost; O(grid tiles), accepted at the 36x36 test scale and the
## 128x128 cap (see the design doc's Risks section).
func rebuild_from_grid(grid: WorldGrid) -> void:
	_grid = grid
	var half: float = WorldGrid.TILE_SIZE * 0.5
	var verts := PackedVector3Array()
	var polygons: Array[PackedInt32Array] = []

	for x in grid.width:
		for z in grid.depth:
			if _tile_blocked(grid, x, z):
				continue
			var center: Vector3 = grid.tile_to_world(x, z)
			var base_index: int = verts.size()
			verts.append(Vector3(center.x - half, 0.0, center.z - half))
			verts.append(Vector3(center.x + half, 0.0, center.z - half))
			verts.append(Vector3(center.x + half, 0.0, center.z + half))
			verts.append(Vector3(center.x - half, 0.0, center.z + half))
			polygons.append(PackedInt32Array(
				[base_index, base_index + 1, base_index + 2, base_index + 3]
			))

	var navmesh := NavigationMesh.new()
	navmesh.set_vertices(verts)
	for polygon: PackedInt32Array in polygons:
		navmesh.add_polygon(polygon)
	NavigationServer3D.region_set_navigation_mesh(_region, navmesh)


## A navigation-only reservation for a home site's den tile — NOT `WorldGrid.is_occupied()`.
## Re-derives from the last grid passed to `rebuild_from_grid()`; a no-op (beyond recording
## the reservation) if that has never been called.
func set_den_tile_blocked(tile: Vector2i, blocked: bool) -> void:
	if blocked:
		_den_tiles[tile] = true
	else:
		_den_tiles.erase(tile)
	if _grid != null:
		rebuild_from_grid(_grid)


func find_path(start: Vector3, goal: Vector3) -> PackedVector3Array:
	return NavigationServer3D.map_get_path(_map, start, goal, true)


## Releases the server-side map/region RIDs. `WorldNavigation` is a `RefCounted`, and RIDs
## are not reference-counted — call this explicitly when done (`WorldRoot._exit_tree()`
## does; every test fixture that constructs one does too).
func free_navigation() -> void:
	NavigationServer3D.free_rid(_region)
	NavigationServer3D.free_rid(_map)


func _tile_blocked(grid: WorldGrid, x: int, z: int) -> bool:
	if grid.is_occupied(x, z):
		return true
	if _den_tiles.has(Vector2i(x, z)):
		return true
	var terrain: TerrainDefinition = grid.get_terrain(x, z)
	return terrain != null and terrain.blocks_movement
