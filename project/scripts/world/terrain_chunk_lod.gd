class_name TerrainChunkLod
extends Node3D
## Distance-banded LOD tiering for `TerrainView`'s tile visuals. Tiles are grouped into
## `LOD_CHUNK_SIZE`-square chunks; each chunk is independently tiered near/far (see
## `is_near`/`set_chunk_tier`). Near-tier chunks keep a real per-tile scene instance, exactly
## as pre-LOD behavior. Far-tier chunks batch their tiles into one `MultiMeshInstance3D` PER
## MESH PIECE per terrain type present in the chunk (a terrain scene can have several mesh
## pieces — e.g. rock's ground slab plus several boulder chunks — so a single-terrain chunk
## can still produce more than one MultiMeshInstance3D; what collapses is the PER-TILE cost,
## not the per-piece one).
##
## STRUCTURAL REQUIREMENT (for `occlusion_fader.gd` dependency): Near-tier tiles get a wrapper
## Node3D named `"Tile_%d_%d"` for each tile, parented directly under TerrainView
## (passed via `near_visual_parent`), with the real scene-instance visual as its child. This
## container is created ONCE per tile and reused across repaints — never freed-and-recreated
## in the same call, which would race Godot's sibling-rename-on-collision behavior and leave
## the fader pointing at stale, about-to-be-freed geometry. `occlusion_fader.gd` depends on
## this exact naming/parenting structure to find fadeable meshes; see lines 193, 282, 322 of
## occlusion_fader.gd. Far-tier MultiMeshInstance3D nodes carry no such requirement — a chunk's
## far batch is freed and rebuilt wholesale on any change within it.

## PROPOSED (2026-08-22) — tiles per chunk edge. 256 chunks at the 128x128 cap: small enough
## to avoid visible popping at tier transitions, large enough that far-tier draw calls stay
## in the low hundreds. No existing spec.md value; this is a new constant.
const LOD_CHUNK_SIZE: int = 8

## PROPOSED (2026-08-22) — `CameraRig.zoom_tiles()` is the camera's full orthographic
## extent, not a half-extent, so a 1.0 multiplier gives roughly double the on-screen radius
## (~4x the on-screen area) — deliberately generous so panning at any zoom level keeps more
## than just the exact viewport at full detail. Capped by `LOD_NEAR_RADIUS_CAP_TILES` below,
## since left uncapped this alone would make every chunk "near" once `zoom_tiles()` reaches
## the whole-world overview size (see that constant's comment).
const LOD_NEAR_MULTIPLIER: float = 1.0

## PROPOSED (2026-08-22) — buffer so tiles just past the viewport edge don't visibly pop
## between tiers mid-pan.
const LOD_NEAR_MARGIN_TILES: float = 4.0

## PROPOSED (2026-08-22) — hard cap on the near-tier radius, independent of zoom. Without
## this, `LOD_NEAR_MULTIPLIER * zoom_tiles()` grows without bound as the camera zooms out —
## and `CameraRig.set_zoom_tiles()` clamps to `_overview_size()`, which by construction
## frames the ENTIRE world. Uncapped, the near radius at full zoom-out always exceeds the
## world's own half-diagonal, so nothing would ever go far-tier at full zoom-out — exactly
## the 16k-tile worst case this LOD system exists to fix. The cap makes "zoomed all the way
## out" behave like the spec's stated intent: individual tiles stop mattering once the
## camera is far enough out, batching kicks in regardless of how large `zoom_tiles()` gets.
## 24 tiles is comfortably past `CameraRig.ZOOM_DEFAULT_TILES` (14) plus this file's own
## margin, so ordinary gameplay zoom is unaffected; it only engages once the camera pulls
## back well past normal play.
const LOD_NEAR_RADIUS_CAP_TILES: float = 24.0

## PROPOSED (2026-08-22) — half-width of the hysteresis dead-band around the near/far
## threshold, in tiles. Applied only in `update_camera()`'s periodic recheck (biased by a
## chunk's OWN current tier, so a chunk already near needs to cross further out to become
## far, and vice versa) — `is_near()` itself stays the plain, unbiased threshold test for
## a chunk's first-ever tier assignment, where there is no prior tier to bias from. Without
## this, a camera sitting still near the boundary would flip a chunk's tier every single
## `LOD_REBUILD_CHECK_INTERVAL_SECONDS` tick from floating-point/panning jitter.
const LOD_HYSTERESIS_TILES: float = 2.0

## PROPOSED (2026-08-22) — `occlusion_fader.gd`'s CHECK_INTERVAL_SECONDS is 0.1s for a cheap
## fade check; an LOD tier recheck is similarly cheap but the rebuild it can trigger is
## heavier (regenerating a MultiMesh), so a slightly longer interval avoids churn during
## smooth zoom/pan.
const LOD_REBUILD_CHECK_INTERVAL_SECONDS: float = 0.25

## PROPOSED (2026-08-23) — max chunk tier flips `update_camera()` actually rebuilds per call.
## A tier flip is real work (node teardown/creation, mesh-piece extraction, `MultiMesh`
## construction) — cheap on native, but a large/fast zoom can cross the near/far threshold
## for many chunks in the same throttled tick, and rebuilding all of them synchronously in
## one call was a reported multi-second stall under WASM (Web export). Mirrors
## `HabitatSimulation.MAX_EVALUATIONS_PER_FRAME`'s bounded-drain pattern: chunks past the
## budget catch up on the next tick, invisible at a 0.25s cadence.
const MAX_CHUNK_REBUILDS_PER_TICK: int = 4


## The chunk coordinate a tile belongs to.
static func chunk_of(x: int, z: int) -> Vector2i:
	return Vector2i(floori(float(x) / LOD_CHUNK_SIZE), floori(float(z) / LOD_CHUNK_SIZE))


## World-space centre of `chunk`, clamped to whatever of it actually exists on `grid` (the
## grid's last chunk in a row/column is usually smaller than `LOD_CHUNK_SIZE`).
static func chunk_centre(chunk: Vector2i, grid: WorldGrid) -> Vector3:
	var first: Vector3 = grid.tile_to_world(chunk.x * LOD_CHUNK_SIZE, chunk.y * LOD_CHUNK_SIZE)
	var last_x: int = mini(chunk.x * LOD_CHUNK_SIZE + LOD_CHUNK_SIZE - 1, grid.width - 1)
	var last_z: int = mini(chunk.y * LOD_CHUNK_SIZE + LOD_CHUNK_SIZE - 1, grid.depth - 1)
	var last: Vector3 = grid.tile_to_world(last_x, last_z)
	return (first + last) * 0.5


## The near-tier radius for a given zoom level, shared by `is_near()` and the hysteresis
## variant `update_camera()` uses — see `LOD_NEAR_RADIUS_CAP_TILES`'s comment for why this
## is capped rather than growing unboundedly with `zoom_tiles()`.
static func _base_radius(zoom_tiles: float) -> float:
	return minf(zoom_tiles * LOD_NEAR_MULTIPLIER + LOD_NEAR_MARGIN_TILES, LOD_NEAR_RADIUS_CAP_TILES)


## True when the chunk centred at `chunk_world_centre` should render at full per-tile detail.
## `camera_focus`/`zoom_tiles` are plain values, not a `CameraRig` reference, so this needs no
## live camera to test. Unbiased — used for a chunk's first-ever tier assignment. The periodic
## recheck in `update_camera()` uses `_is_near_with_hysteresis()` instead, once a chunk has a
## prior tier to bias from.
static func is_near(chunk_world_centre: Vector3, camera_focus: Vector3, zoom_tiles: float) -> bool:
	var flat_centre := Vector2(chunk_world_centre.x, chunk_world_centre.z)
	var flat_focus := Vector2(camera_focus.x, camera_focus.z)
	return flat_centre.distance_to(flat_focus) <= _base_radius(zoom_tiles)


## `is_near()` plus a symmetric dead-band biased by the chunk's current tier, so a camera
## sitting near the boundary doesn't flip a chunk every recheck.
static func _is_near_with_hysteresis(
	chunk_world_centre: Vector3, camera_focus: Vector3, zoom_tiles: float, currently_near: bool
) -> bool:
	var flat_centre := Vector2(chunk_world_centre.x, chunk_world_centre.z)
	var flat_focus := Vector2(camera_focus.x, camera_focus.z)
	var base: float = _base_radius(zoom_tiles)
	var radius: float = base + LOD_HYSTERESIS_TILES if currently_near else base - LOD_HYSTERESIS_TILES
	return flat_centre.distance_to(flat_focus) <= radius


var _grid: WorldGrid = null
var _near_visual_parent: Node3D = null
var _world: WorldRoot = null
var _tile_containers: Dictionary = {}       # Vector2i(x, z) -> Node3D (near-tier only)
var _chunk_tiles: Dictionary = {}           # Vector2i chunk -> Array[Vector2i] tiles
var _chunk_tiers: Dictionary = {}           # Vector2i chunk -> bool (true = near); default near
var _far_multimeshes: Dictionary = {}       # Vector2i chunk -> Array[MultiMeshInstance3D]
var _mesh_cache: Dictionary = {}            # String terrain_id -> Array[Dictionary] mesh pieces
var _last_camera_focus: Vector3 = Vector3.ZERO
var _last_zoom_tiles: float = 0.0
var _has_camera_state: bool = false


## `world` is optional (defaults null) so any test that builds a bare `TerrainChunkLod`
## keeps working — `_resolve_variant()` degrades to `pick_variant()`'s pre-feature
## behaviour whenever `_world` is null, exactly as it does for a non-picker terrain.
func attach(grid: WorldGrid, near_visual_parent: Node3D, world: WorldRoot = null) -> void:
	_grid = grid
	_near_visual_parent = near_visual_parent
	_world = world
	for child in get_children():
		child.queue_free()
	_tile_containers = {}
	_chunk_tiles = {}
	_chunk_tiers = {}
	_far_multimeshes = {}
	_mesh_cache = {}
	_has_camera_state = false


## Registers `(x, z)` under its chunk (if not already) and refreshes just that tile's
## representation according to its chunk's current tier. Near tier: reuse-or-create this
## one tile's container (Task 1's structural requirement — see the file header). Far tier:
## a single tile's terrain can move it between per-terrain MultiMesh groups, so the whole
## chunk's batch rebuilds — never a whole-GRID rescan, only this one chunk.
##
## BUILD TIER-AWARE, NOT BUILD-THEN-DEMOTE: a brand new chunk's tier is decided immediately
## from the last camera state `update_camera()` recorded, if any, instead of always
## defaulting to near and waiting for the next periodic recheck to correct it. This can't
## help the very first tiles registered before `update_camera()` has ever run once (no
## camera state exists yet) — but it means every `on_grown()` mist-reveal during normal
## play (camera already live by then) never briefly builds full detail it's about to
## discard.
func refresh_tile(x: int, z: int) -> void:
	var tile := Vector2i(x, z)
	var chunk: Vector2i = chunk_of(x, z)
	var is_new_chunk: bool = not _chunk_tiles.has(chunk)
	if is_new_chunk:
		_chunk_tiles[chunk] = []
	if not _chunk_tiles[chunk].has(tile):
		_chunk_tiles[chunk].append(tile)

	if is_new_chunk and _has_camera_state:
		var centre: Vector3 = chunk_centre(chunk, _grid)
		_chunk_tiers[chunk] = is_near(centre, _last_camera_focus, _last_zoom_tiles)

	if _chunk_tiers.get(chunk, true):
		_refresh_near_tile(tile)
	else:
		_rebuild_chunk_far(chunk)


## Sets `chunk`'s tier and rebuilds it if the tier actually changed. This is the entry
## point `TerrainView`'s camera-driven recheck (Task 4) calls; tests call it directly to
## exercise a tier's rendering without a live camera.
##
## SAFETY: Calling this twice on the SAME chunk within the same frame (before the intervening
## idle-frame processing completes `queue_free()`) reproduces the node-rename race described in
## Task 1 — a freed `"Tile_x_z"` container and its same-named replacement briefly coexist.
## Normal `update_camera()` usage is safe (at most one call per chunk per throttled tick).
func set_chunk_tier(chunk: Vector2i, near: bool) -> void:
	if _chunk_tiers.get(chunk, true) == near:
		return
	_chunk_tiers[chunk] = near
	if near:
		_free_chunk_far(chunk)
		for tile: Vector2i in _chunk_tiles.get(chunk, []):
			_refresh_near_tile(tile)
	else:
		_free_chunk_near(chunk)
		_rebuild_chunk_far(chunk)


## Reuse-or-create `tile`'s near-tier container (Task 1's structural requirement: a
## persistent node per tile, never freed-and-recreated in the same call, so
## `occlusion_fader.gd`'s name-based lookup never races a pending `queue_free()`). Only
## the container's CHILD visual is replaced on a terrain change.
func _refresh_near_tile(tile: Vector2i) -> void:
	var container: Node3D = _tile_containers.get(tile, null) as Node3D
	if container == null or not is_instance_valid(container):
		container = Node3D.new()
		container.name = "Tile_%d_%d" % [tile.x, tile.y]
		container.position = _grid.tile_to_world(tile.x, tile.y)
		if _near_visual_parent != null:
			_near_visual_parent.add_child(container)
		else:
			add_child(container)
		_tile_containers[tile] = container
	else:
		for child in container.get_children():
			child.queue_free()

	var terrain: TerrainDefinition = _grid.get_terrain(tile.x, tile.y)
	if terrain == null:
		return
	var variant: PackedScene = _resolve_variant(terrain, tile.x, tile.y)
	if variant == null:
		return
	var visual: Node3D = variant.instantiate() as Node3D
	if visual == null:
		return
	container.add_child(visual)


## Picker categories (forest, wild_grass) always resolve through the player's chosen style
## default (`WorldRoot.resolve_style_scene()`); every other terrain (rock, water,
## cultivated_field) keeps using `pick_variant()`'s stable per-tile hash, completely
## unaffected by this feature — that split, not an oversight, is this task's whole scope.
func _resolve_variant(terrain: TerrainDefinition, x: int, z: int) -> PackedScene:
	if _world == null or (terrain.id != "forest" and terrain.id != "wild_grass"):
		return terrain.pick_variant(x, z)
	var resolved: PackedScene = _world.resolve_style_scene(terrain.id)
	return resolved if resolved != null else terrain.pick_variant(x, z)


## Frees every tile container belonging to `chunk` — used when a chunk flips to the far
## tier (its tiles no longer need individual near-tier containers).
func _free_chunk_near(chunk: Vector2i) -> void:
	for tile: Vector2i in _chunk_tiles.get(chunk, []):
		var container: Node3D = _tile_containers.get(tile, null) as Node3D
		if container != null and is_instance_valid(container):
			container.queue_free()
		_tile_containers.erase(tile)


## Frees `chunk`'s far-tier MultiMesh instances — used when a chunk flips to the near
## tier, or before rebuilding the far batch after a terrain edit. `remove_child()` before
## `queue_free()` so a same-call rebuild never has an about-to-be-freed node still present
## when its (differently-named, so harmless today, but worth closing structurally) sibling
## is added.
func _free_chunk_far(chunk: Vector2i) -> void:
	var built: Array = _far_multimeshes.get(chunk, [])
	for mmi: MultiMeshInstance3D in built:
		if is_instance_valid(mmi):
			remove_child(mmi)
			mmi.queue_free()
	_far_multimeshes.erase(chunk)


## Rebuilds `chunk`'s far-tier representation from scratch: one `MultiMeshInstance3D` per
## mesh piece per terrain type present in the chunk (see the file header — a terrain scene
## can have more than one mesh piece).
func _rebuild_chunk_far(chunk: Vector2i) -> void:
	_free_chunk_far(chunk)
	var tiles: Array = _chunk_tiles.get(chunk, [])
	if tiles.is_empty():
		return

	var by_terrain: Dictionary = {}  # String terrain_id -> Array[Vector2i]
	for tile: Vector2i in tiles:
		var terrain_id: String = _grid.get_terrain_id(tile.x, tile.y)
		if terrain_id.is_empty():
			continue
		if not by_terrain.has(terrain_id):
			by_terrain[terrain_id] = []
		by_terrain[terrain_id].append(tile)

	var built: Array = []
	for terrain_id: String in by_terrain:
		var pieces: Array = _mesh_pieces_for_terrain(terrain_id)
		if pieces.is_empty():
			continue
		var tile_list: Array = by_terrain[terrain_id]
		for piece_index in pieces.size():
			var piece: Dictionary = pieces[piece_index]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = piece["mesh"]
			mm.instance_count = tile_list.size()
			for i in tile_list.size():
				var t: Vector2i = tile_list[i]
				var tile_origin := Transform3D(Basis(), _grid.tile_to_world(t.x, t.y))
				mm.set_instance_transform(i, tile_origin * (piece["transform"] as Transform3D))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Far_%s_%d_%d_%d" % [terrain_id, chunk.x, chunk.y, piece_index]
			mmi.multimesh = mm
			if piece["material"] != null:
				mmi.material_override = piece["material"]
			add_child(mmi)
			built.append(mmi)
	_far_multimeshes[chunk] = built


## Every mesh piece (mesh + material + accumulated local transform) in `terrain_id`'s first
## `model_scenes` variant — cached after the first extraction. A terrain scene can have
## multiple mesh pieces (e.g. rock's ground slab plus several boulder chunks); far-tier
## batching needs all of them, not just the first, or most of a terrain's silhouette
## vanishes. Reusing the real variant's pieces means no new `TerrainDefinition` field and
## no content-pipeline change; per-tile visual VARIETY (which of several `model_scenes`
## variants a tile would otherwise show) is lost at range, which is fine since far tiles
## are visually small — but every tile still shows its terrain's actual look, correctly
## materialed and positioned, just always the same (first) variant.
func _mesh_pieces_for_terrain(terrain_id: String) -> Array:
	if _mesh_cache.has(terrain_id):
		return _mesh_cache[terrain_id]
	var terrain: TerrainDefinition = _grid.terrain_definition(terrain_id)
	if terrain == null or terrain.model_scenes.is_empty():
		_mesh_cache[terrain_id] = []
		return []
	var sample: Node3D = terrain.model_scenes[0].instantiate() as Node3D
	var pieces: Array = []
	if sample != null:
		_collect_mesh_pieces(sample, sample, pieces)
		sample.queue_free()
	_mesh_cache[terrain_id] = pieces
	return pieces


## Depth-first collection of every `MeshInstance3D` under `node`, each paired with its
## active material and its transform accumulated relative to `root` — so a piece nested
## several levels deep (e.g. one of rock's individual boulders) keeps its correct offset,
## rotation and scale once replicated via a MultiMesh instance transform instead of the
## original node hierarchy. KNOWN LIMITATION: only `MeshInstance3D` is matched — a terrain
## scene whose geometry lives in a `MultiMeshInstance3D` instead (none does today) would
## silently contribute no far-tier geometry.
func _collect_mesh_pieces(node: Node, root: Node3D, out: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			out.append({
				"mesh": mi.mesh,
				"material": mi.material_override,
				"transform": _transform_relative_to(mi, root),
			})
	for child in node.get_children():
		_collect_mesh_pieces(child, root, out)


## `node`'s transform accumulated up through its ancestors, stopping at (not including)
## `root` — the transform that would place `node`'s mesh correctly if re-parented directly
## under something positioned where `root` currently is.
func _transform_relative_to(node: Node3D, root: Node3D) -> Transform3D:
	var xform: Transform3D = node.transform
	var current: Node3D = node.get_parent() as Node3D
	while current != null and current != root:
		xform = current.transform * xform
		current = current.get_parent() as Node3D
	return xform


## Recomputes every known chunk's tier against the camera's current focus/zoom and applies
## any changes via `set_chunk_tier()` (a no-op rebuild-wise for chunks whose tier didn't
## change). Called on a throttled timer from `TerrainView._process()`, never every frame.
## Records the camera state so `refresh_tile()` can assign a correct tier to brand-new
## chunks immediately instead of defaulting to near and waiting for the next tick.
##
## REBUILD WORK IS BOUNDED PER CALL (`MAX_CHUNK_REBUILDS_PER_TICK`): the tier CHECK below is
## cheap (a distance compare) and always runs for every chunk, but the actual rebuild
## (`set_chunk_tier()`, only called when a tier genuinely changed) stops once the budget is
## spent. A large/fast zoom can cross the threshold for many chunks in one tick; without this
## bound, all of them would rebuild synchronously in the same call — fine on native, but a
## real multi-second stall under WASM. The rest catch up on the next throttled tick.
func update_camera(camera_focus: Vector3, zoom_tiles: float) -> void:
	_last_camera_focus = camera_focus
	_last_zoom_tiles = zoom_tiles
	_has_camera_state = true
	var rebuilds_done: int = 0
	for chunk: Vector2i in _chunk_tiles.keys():
		if rebuilds_done >= MAX_CHUNK_REBUILDS_PER_TICK:
			break
		var centre: Vector3 = chunk_centre(chunk, _grid)
		var currently_near: bool = _chunk_tiers.get(chunk, true)
		var near: bool = _is_near_with_hysteresis(centre, camera_focus, zoom_tiles, currently_near)
		if near != currently_near:
			set_chunk_tier(chunk, near)
			rebuilds_done += 1
