class_name TerrainView
extends Node3D
## The visual + collision layer for `WorldGrid` — Tier 1 row 3's presentation half.
##
## Holds no simulation state. It listens to `WorldGrid.tile_changed` and re-instantiates
## a stably-picked entry from that tile's `TerrainDefinition.model_scenes` (or the
## building's, on top).
##
## PICKING COLLISION IS A SINGLE BODY, NOT ONE PER TILE (2026-08-22 LOD pass). `WorldGrid`
## only ever grows as a clean axis-aligned rectangle from (0,0) — `grow()`'s own header
## confirms this — so one `StaticBody3D` sized to `width x depth` answers every tap exactly
## as a per-tile body did, at O(1) node cost instead of O(tiles). `screen_to_grid()` recovers
## the tile from the hit position via `WorldGrid.world_to_tile()` + `in_bounds()`, not from
## per-body metadata.
##
## Visual LOD (gdd.md -> Performance) batches far tiles via `TerrainChunkLod` — see that
## file.
##

## Physics layer the single picking body lives on (bit 0, value 1). Screen-tap raycasts
## (`screen_to_grid()` below) query exactly this layer.
const PICKING_COLLISION_LAYER: int = 1

## Read externally by `mist_boundary.gd` to size its visual curtain panels at the world edge
## — nothing to do with movement collision (which no longer exists in this file). Kept as a
## shared constant so the curtain's geometry can't silently drift from whatever this file
## considers "the world edge."
const BOUNDARY_WALL_THICKNESS: float = 1.0

var _grid: WorldGrid = null
var _world: WorldRoot = null
var _picking_body: StaticBody3D = null
var _picking_shape: BoxShape3D = null
var _building_visuals: Dictionary = {}  # Vector2i origin -> Node3D
var _buildings_root: Node3D = null
var _chunk_lod: TerrainChunkLod = null
var _lod_clock: float = 0.0


## Builds the whole view for a grid and subscribes to its changes. `world` is threaded down
## to `_chunk_lod` and kept here too, so the House visual (`_refresh_building_visual()`) can
## resolve its picked style through `WorldRoot.resolve_style_scene()` — see that method's
## header. Optional (defaults null) so any test that builds a bare `TerrainView` without a
## `WorldRoot` keeps working; every resolution path degrades to its pre-feature fallback
## when `_world` is null.
func attach(grid: WorldGrid, world: WorldRoot = null) -> void:
	_grid = grid
	_world = world
	_clear()
	_buildings_root = Node3D.new()
	_buildings_root.name = "Buildings"
	add_child(_buildings_root)

	_build_picking_body()
	_resize_picking_body()

	_chunk_lod = TerrainChunkLod.new()
	_chunk_lod.name = "ChunkLod"
	add_child(_chunk_lod)
	_chunk_lod.attach(grid, self, world)

	for x in grid.width:
		for z in grid.depth:
			_chunk_lod.refresh_tile(x, z)

	if not grid.tile_changed.is_connected(_on_tile_changed):
		grid.tile_changed.connect(_on_tile_changed)
	if not grid.grown.is_connected(on_grown):
		grid.grown.connect(on_grown)


func _clear() -> void:
	for child in get_children():
		child.queue_free()
	_picking_body = null
	_picking_shape = null
	_building_visuals = {}
	_chunk_lod = null


## One `StaticBody3D` for the whole grid's tap-to-select raycasting. Created once; resized
## (never rebuilt) by `_resize_picking_body()` whenever the grid grows.
func _build_picking_body() -> void:
	_picking_body = StaticBody3D.new()
	_picking_body.name = "PickingBody"
	_picking_body.collision_layer = PICKING_COLLISION_LAYER
	_picking_body.collision_mask = 0

	var collision := CollisionShape3D.new()
	_picking_shape = BoxShape3D.new()
	collision.shape = _picking_shape
	_picking_body.add_child(collision)
	add_child(_picking_body)


## Sizes and positions the single picking body to cover exactly `_grid.width x _grid.depth`,
## the same rectangle `WorldGrid.grow()` always fills (never sparse — see that function's
## header). Safe to call repeatedly; a smaller/unchanged grid just re-applies the same values.
func _resize_picking_body() -> void:
	var origin: Vector3 = _grid.tile_to_world(0, 0)
	var far_corner: Vector3 = _grid.tile_to_world(_grid.width - 1, _grid.depth - 1)
	var centre: Vector3 = (origin + far_corner) * 0.5
	_picking_shape.size = Vector3(
		_grid.width * WorldGrid.TILE_SIZE,
		WorldGrid.TILE_HEIGHT,
		_grid.depth * WorldGrid.TILE_SIZE
	)
	# The grey-box slabs hang below y = 0 (origin at each tile's top surface), so the
	# collider hangs with them and a tap lands on the surface the player can see.
	_picking_body.position = Vector3(centre.x, -WorldGrid.TILE_HEIGHT * 0.5, centre.z)


## TIER 1 ROW 13 (MIST). `WorldGrid.grown`'s handler: resizes the picking body to cover the
## grown rectangle and builds a real visual for every newly revealed coordinate. Public —
## `WorldGrid.grow()` connects to it directly, the same Callable-to-signal shape
## `_on_tile_changed` already uses for `tile_changed`.
func on_grown(new_tiles: Array[Vector2i]) -> void:
	_resize_picking_body()
	for tile: Vector2i in new_tiles:
		_chunk_lod.refresh_tile(tile.x, tile.y)


## The visual `def`'s next-placed instance should use: the player's chosen style default
## for `def.id` (currently only "house" has a picker) if one resolves, else
## `def.model_scenes[0]` — today's exact pre-feature behaviour. **Farm Building is NOT
## resolved here**: a placed farm building is already a concrete `PlaceableDefinition` id
## (e.g. "barn"), never the "farm_building" category label, so
## `WorldRoot.resolve_style_scene("barn")` correctly finds no scenes for that id and falls
## through to `model_scenes[0]` — this file never needs to know the category label exists.
func _resolve_building_variant(def: PlaceableDefinition) -> PackedScene:
	if _world != null:
		var resolved: PackedScene = _world.resolve_style_scene(def.id)
		if resolved != null:
			return resolved
	return null if def.model_scenes.is_empty() else def.model_scenes[0]


func _refresh_building_visual(origin: Vector2i) -> void:
	var existing: Node3D = _building_visuals.get(origin, null) as Node3D
	var def: PlaceableDefinition = _grid.get_building(origin.x, origin.y)
	if def == null:
		if existing != null and is_instance_valid(existing):
			existing.queue_free()
		_building_visuals.erase(origin)
		return
	if existing != null and is_instance_valid(existing):
		return
	var variant: PackedScene = _resolve_building_variant(def)
	if variant == null:
		return
	var node: Node3D = variant.instantiate() as Node3D
	if node == null:
		return
	# Every building model in this project is authored centered on its own local origin, so
	# a 1x1 placed at its tile's center sits correctly. A MULTI-TILE footprint's center is
	# NOT its origin tile's center, though: `footprint_tiles()` anchors the block at `origin`
	# and grows it in +x/+z, so the block's center is half a tile further along each axis per
	# extra tile. Without this offset a 2x2 building renders straddling its ORIGIN tile —
	# spilling outside the tiles it reserves on two sides while leaving the far half of its
	# own footprint visually empty. Latent until `barn.tres` (2x2) became the first non-1x1
	# placeable this project has ever had; reduces to exactly zero for a 1x1, so House and
	# every other placeable are unaffected. Covered by test_building_footprint_alignment.gd.
	var footprint_offset := Vector3(
		float(def.footprint.x - 1) * WorldGrid.TILE_SIZE * 0.5,
		0.0,
		float(def.footprint.y - 1) * WorldGrid.TILE_SIZE * 0.5
	)
	node.position = _grid.tile_to_world(origin.x, origin.y) + footprint_offset
	_buildings_root.add_child(node)
	_building_visuals[origin] = node


func _on_tile_changed(x: int, z: int) -> void:
	_chunk_lod.refresh_tile(x, z)
	var origin: Vector2i = _grid.get_building_origin(x, z)
	if origin.x >= 0:
		_refresh_building_visual(origin)


## Maps a screen position to grid coordinates by raycasting the single picking body, then
## recovering the tile from the hit's world position — not from per-body metadata, which no
## longer exists. Returns `Vector2i(-1, -1)` on a miss (off the world, or no camera yet).
##
## Exposed through `WorldRoot.screen_to_grid()` so the UI dispatch never re-derives the
## camera/ray/collider chain — one implementation, one place to fix.
func screen_to_grid(screen_position: Vector2, ray_length: float = 1000.0) -> Vector2i:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return Vector2i(-1, -1)
	var from: Vector3 = camera.project_ray_origin(screen_position)
	var to: Vector3 = from + camera.project_ray_normal(screen_position) * ray_length
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Picking-layer only (see the file header).
	query.collision_mask = PICKING_COLLISION_LAYER
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector2i(-1, -1)
	var tile: Vector2i = _grid.world_to_tile(hit["position"] as Vector3)
	if not _grid.in_bounds(tile.x, tile.y):
		return Vector2i(-1, -1)
	return tile


## The world-space distance from the camera to whatever `screen_to_grid()` would hit at
## `screen_position`, or -1.0 on the same miss `screen_to_grid()` reports (off the world, or
## no camera yet). Runs the identical raycast — same ray, same `PICKING_COLLISION_LAYER` mask
## — so a caller never has to worry the two could disagree about what was hit.
##
## Wrapped by `WorldRoot.crosshair_distance()`, which `tap_router.gd`'s range check reads
## alongside `WorldRoot.distance_to()` (a separate straight-line measure against a resident's
## own position) to tell a real hit from a miss: `screen_to_grid()` alone answers "which tile,"
## never "how far."
func hit_distance(screen_position: Vector2, ray_length: float = 1000.0) -> float:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return -1.0
	var from: Vector3 = camera.project_ray_origin(screen_position)
	var to: Vector3 = from + camera.project_ray_normal(screen_position) * ray_length
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = PICKING_COLLISION_LAYER
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return -1.0
	return from.distance_to(hit["position"] as Vector3)


func _process(delta: float) -> void:
	if _grid == null or _chunk_lod == null:
		return
	_lod_clock += delta
	if _lod_clock < TerrainChunkLod.LOD_REBUILD_CHECK_INTERVAL_SECONDS:
		return
	_lod_clock = 0.0
	var camera := get_viewport().get_camera_3d() as CameraRig
	if camera == null:
		return
	_chunk_lod.update_camera(camera.focus(), camera.zoom_tiles())
