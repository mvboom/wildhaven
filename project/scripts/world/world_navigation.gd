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

## How many full navmesh rebuilds have actually run. Same shape and purpose as
## `HabitatSimulation.evaluations_run` — an exact work counter, so
## `test_navigation_rebuild_coalescing.gd` can assert that a burst of edits collapses into
## one rebuild without asserting a wall-clock number. Never reset by production code.
var rebuilds_run: int = 0

## Set by `mark_dirty()`, cleared by `rebuild_from_grid()`. See `mark_dirty()`'s own doc.
var _dirty: bool = false
var _flush_scheduled: bool = false


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
	_dirty = false
	rebuilds_run += 1
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
	mark_dirty()


## THE COALESCING ENTRY POINT. Records that the navmesh no longer matches the world, without
## paying for a rebuild here. Every world edit calls this instead of `rebuild_from_grid()`.
##
## A rebuild is a full re-scan of every tile (2.4ms of a 2.8ms `paint_tile()` call —
## `probe_frame_cost.gd`), and it was previously run once per edit: once per tile of a dragged
## stroke, and once per resident arrival via the den reservation above. Nothing observes the
## navmesh between two edits, so every rebuild but the last was thrown away unlooked-at.
##
## THE PENDING REBUILD IS SETTLED TWO WAYS, AND EITHER IS SUFFICIENT:
##   * `call_deferred` flushes it at the end of the current frame, so in normal play the
##     rebuild still happens on the same frame as the edit that caused it — the timing the
##     synchronous version had, minus the duplicates. `NavigationServer3D` then gets its usual
##     several frames to sync before anything paths (this file's header).
##   * `find_path()` flushes it first, so a reader can never observe stale geometry even if
##     no frame boundary has passed — which is also what makes this deterministic under
##     `--headless --script`, where a test drives calls directly rather than pumping frames.
##
## Safe before the first `rebuild_from_grid()`: `_ensure_fresh()` no-ops while `_grid` is
## null, exactly as `set_den_tile_blocked()`'s old guard did.
func mark_dirty() -> void:
	_dirty = true
	if _flush_scheduled:
		return
	_flush_scheduled = true
	call_deferred("_flush_pending")


func _flush_pending() -> void:
	_flush_scheduled = false
	_ensure_fresh()


## Rebuilds only if an edit is actually outstanding. Idempotent, so the deferred flush and a
## reader racing to settle the same edit cost one rebuild between them, not two.
func _ensure_fresh() -> void:
	if _dirty and _grid != null:
		rebuild_from_grid(_grid)


func find_path(start: Vector3, goal: Vector3) -> PackedVector3Array:
	_ensure_fresh()
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
