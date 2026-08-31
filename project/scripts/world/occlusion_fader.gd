class_name OcclusionFader
extends Node
## Selective per-tile transparency fade (→ D-41 spec §4, the human's own proposal,
## validated against Stardew Valley's shipped default). Fades ONLY a forest tile
## currently blocking a REAL resident's line of sight to the active camera — never
## all trees, never always.
##
## BOUNDED BY CONSTRUCTION, unlike the spike's brute-force version: for each
## resident (a small, capacity-bounded number), only forest tiles within
## `RESIDENT_CHECK_RADIUS_TILES` are ever tested — the occlusion probe measured a
## squashed canopy's shadow at only a few tiles, so nothing farther away can ever
## occlude a given resident. Cost is O(residents x (2*radius+1)^2), independent of
## world size, matching the GDD's event-driven/bounded-cost philosophy elsewhere
## (the dirty-neighbourhood queue).
##
## FLICKER GUARD: a tile must disagree with its current fade state for
## FADE_HYSTERESIS_FRAMES consecutive checks before it actually flips — guards
## against exactly the failure mode a Don't Starve Together developer described
## (a wobbling detection boundary causing visible flutter).

## Default 90% opaque (10% see-through) — the human's own starting point, tunable
## here without touching detection logic.
@export var fade_alpha: float = 0.9

## How many tiles out from a resident's own position to check for a blocking
## forest tile. Bounds the scan; a canopy's occlusion "shadow" measured only a few
## tiles in the probe that validated this approach.
const RESIDENT_CHECK_RADIUS_TILES: int = 3

const FADE_HYSTERESIS_FRAMES: int = 6
const RAY_BACKOFF: float = 60.0
const CHECK_INTERVAL_SECONDS: float = 0.1

var _world: WorldRoot = null
var _materials_by_tile: Dictionary = {}       # Vector2i -> Array[Array[StandardMaterial3D]], outer per mesh instance, inner per surface
var _faded_by_tile: Dictionary = {}           # Vector2i -> bool
var _pending_frames_by_tile: Dictionary = {}  # Vector2i -> int
var _aabb_by_tile: Dictionary = {}            # Vector2i -> AABB, see `_tile_aabb()`
var _clock: float = 0.0

## WORK COUNTERS, same shape and purpose as `HabitatSimulation.evaluations_run`: the two
## quantities this sweep's cost is actually made of, counted exactly so a test can assert the
## ALGORITHM rather than a wall-clock number (which would be machine-dependent, and which the
## ground rules make the human's call anyway). Never reset by production code.
##
##   * `geometry_rebuilds` — how many times `_tile_aabb()` walked a tile's scene tree.
##   * `occlusion_tests`   — how many tile-vs-resident ray tests phase 2 actually ran.
##
## `test_occlusion_fader_scaling.gd` pins both.
var geometry_rebuilds: int = 0
var occlusion_tests: int = 0


func _ready() -> void:
	_world = get_parent() as WorldRoot
	# Same ordering fix `MistBoundary.bind_world()`/`GameUI.bind_world()` already use for the
	# identical parent/child relationship: `WorldRoot` builds `grid` inside its own `_ready()`
	# (world_root.gd:239), which — for a child node under `WorldRoot`, per Godot's
	# children-before-parent ready order — runs AFTER this node's `_ready()`. Connecting to
	# `_world.grid.tile_changed` directly here reads `_world.grid` as still null, so the old
	# guard silently skipped the connection forever, with nothing to retry it. Deferring to the
	# end of the current idle frame guarantees every node's `_ready()` in the tree — including
	# `WorldRoot`'s own — has already run, so `grid` is real by the time `bind_world()` fires.
	call_deferred("bind_world")


## Connects to `WorldRoot.grid.tile_changed` once the grid actually exists. Idempotent and
## public so a headless test can call it directly instead of waiting on a deferred call — the
## same shape `MistBoundary.bind_world()`/`GameUI.bind_world()` already use.
func bind_world() -> void:
	if _world == null or _world.grid == null:
		return
	if not _world.grid.tile_changed.is_connected(_on_grid_tile_changed):
		_world.grid.tile_changed.connect(_on_grid_tile_changed)


func _process(delta: float) -> void:
	if _world == null or _world.view == null:
		return
	# Extra safety net for trickier ordering, matching `MistBoundary._process()`'s own retry:
	# if the deferred call somehow ran before `WorldRoot.grid` existed (e.g. a future caller
	# reparents this node after `_ready()`), keep trying here every frame until it connects.
	if _world.grid != null and not _world.grid.tile_changed.is_connected(_on_grid_tile_changed):
		bind_world()
	_clock += delta
	if _clock < CHECK_INTERVAL_SECONDS:
		return
	_clock = 0.0
	var residents: Array = _live_residents()
	# Deliberately no early-return when residents is empty: the un-fade path below
	# lives inside refresh() and only runs for previously-tracked tiles when it is
	# called. Skipping the call whenever every resident has been queue_free()'d
	# (gentle_displacement.gd does this on departure) would leave any tile that was
	# faded for the last-remaining resident permanently faded.
	refresh(residents)


## `TerrainView._on_tile_changed()` frees and rebuilds a tile's visual node whenever
## `WorldGrid.tile_changed` fires (a repaint, including forest -> other -> forest).
## Any cached material references for that tile now point at freed nodes, so drop
## them — the next relevant `_apply_fade()` call rebuilds the cache against
## whatever node exists then.
func _on_grid_tile_changed(x: int, z: int) -> void:
	var tile := Vector2i(x, z)
	_faded_by_tile.erase(tile)
	_pending_frames_by_tile.erase(tile)
	_materials_by_tile.erase(tile)
	# The rebuilt visual can be a different model at a different height, so its bounds are
	# stale for the same reason its materials are. Erased per tile, never wholesale: a single
	# repaint must not throw away every other tile's cached geometry.
	_aabb_by_tile.erase(tile)


## Every currently-settled resident node, read off `WorldRoot`'s own registry via
## the same `HomeSiteRegistry` shape `ResidentPicker` already reads.
func _live_residents() -> Array:
	if _world.registry == null:
		return []
	var result: Array = []
	for site: HomeSite in _world.registry.sites():
		for resident: Node3D in site.residents:
			if resident != null and is_instance_valid(resident):
				result.append(resident)
	return result


## The production sweep: recomputes which forest tiles currently block a resident's
## line of sight to the camera and updates their fade state. `_process()` calls this
## every `CHECK_INTERVAL_SECONDS`; `test_occlusion_fader.gd` also calls it directly
## with a synthetic resident list — same "position-driven, no synthetic timing"
## reasoning `TapRouter.handle_tap()` already follows in this codebase — so the test
## can settle the hysteresis window deterministically instead of waiting on frames.
func refresh(residents: Array) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var forward: Vector3 = -camera.global_transform.basis.z.normalized()
	var back: Vector3 = -forward
	# THE VALUE IS THE POINT. This used to be a plain `Vector2i -> true` set, and phase 2 then
	# paired every candidate with every resident in the world. But a tile only becomes a
	# candidate BECAUSE some resident is within `RESIDENT_CHECK_RADIUS_TILES` of it — and that
	# same bound is the reason nothing farther away can occlude that resident (see this file's
	# header). So the residents gathered here are exactly the residents the tile could ever
	# block, and testing it against anyone else is a ray test whose answer is already known.
	# Keeping the contributors instead of discarding them turns phase 2 from
	# O(candidates x residents) into O(candidates x nearby residents).
	var candidate_tiles: Dictionary = {}  # Vector2i -> Array[Node3D], the residents it may block
	for resident: Node3D in residents:
		if not is_instance_valid(resident):
			continue
		var tile: Vector2i = _world.grid.world_to_tile(resident.global_position)
		for dx in range(-RESIDENT_CHECK_RADIUS_TILES, RESIDENT_CHECK_RADIUS_TILES + 1):
			for dz in range(-RESIDENT_CHECK_RADIUS_TILES, RESIDENT_CHECK_RADIUS_TILES + 1):
				var candidate := Vector2i(tile.x + dx, tile.y + dz)
				if _world.grid.get_terrain_id(candidate.x, candidate.y) != "forest":
					continue
				if not candidate_tiles.has(candidate):
					candidate_tiles[candidate] = [] as Array[Node3D]
				(candidate_tiles[candidate] as Array[Node3D]).append(resident)

	var blocked_tiles: Dictionary = {}  # Vector2i -> true
	for tile: Vector2i in candidate_tiles.keys():
		var aabb: AABB = _tile_aabb(tile)
		for resident: Node3D in (candidate_tiles[tile] as Array[Node3D]):
			if not is_instance_valid(resident):
				continue
			var target: Vector3 = resident.global_position
			var ray_origin: Vector3 = target + back * RAY_BACKOFF
			occlusion_tests += 1
			var hit = aabb.intersects_ray(ray_origin, forward)
			if hit != null:
				var t_hit: float = (hit as Vector3 - ray_origin).dot(forward)
				if t_hit < RAY_BACKOFF - 0.05:
					blocked_tiles[tile] = true
					break

	# Every previously-tracked tile not in this round's candidate set has no
	# resident anywhere nearby any more; treat it as unblocked so it un-fades.
	var all_tiles: Dictionary = candidate_tiles.duplicate()
	for tile: Vector2i in _faded_by_tile.keys():
		all_tiles[tile] = true
	for tile: Vector2i in all_tiles.keys():
		_update_tile(tile, blocked_tiles.has(tile))


func faded_tile_count_for_testing() -> int:
	var count: int = 0
	for faded: bool in _faded_by_tile.values():
		if faded:
			count += 1
	return count


## Which tiles are actually faded right now — lets a test pick a real faded tile (the ray
## test decides which of a forest block's tiles actually block the resident; it's not any
## particular fixed coordinate) instead of assuming one.
func faded_tiles_for_testing() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for tile: Vector2i in _faded_by_tile.keys():
		if _faded_by_tile[tile]:
			result.append(tile)
	return result


## Total tiles still present in `_faded_by_tile` — i.e. still being tracked at all,
## faded or not (mid-hysteresis counts too). Used to confirm the pruning fix: a
## tile that has un-faded and settled should disappear from here, not just read
## zero in `faded_tile_count_for_testing()`.
func tracked_tile_count_for_testing() -> int:
	return _faded_by_tile.size()


## Whether `tile` is tracked at all right now (faded, mid-hysteresis, or otherwise not
## settled-unfaded) — lets a test prove the bounded scan (RESIDENT_CHECK_RADIUS_TILES)
## never adds a tile far from every resident to tracking in the first place, rather than
## only checking it never happens to end up faded.
func is_tracked_for_testing(tile: Vector2i) -> bool:
	return _faded_by_tile.has(tile)


## Cached in `_aabb_by_tile`, because a tile's world-space bounds only move when the tile
## itself is repainted — and `_on_grid_tile_changed()` is already connected to exactly that
## event, so the invalidation costs nothing new. Uncached, this walked the tile's whole
## subtree and re-transformed eight corners per mesh on every sweep, ten times a second, for
## every candidate: a measured 20-25% of the call (`probe_frame_cost.gd`).
##
## A MISSING TILE NODE IS NEVER CACHED. `TerrainView` frees and re-instantiates a tile's
## visual on repaint, so a null lookup here means "not built yet", which is transient —
## caching the empty AABB it produces would make that transient state permanent and the tile
## would never fade again.
func _tile_aabb(tile: Vector2i) -> AABB:
	if _aabb_by_tile.has(tile):
		return _aabb_by_tile[tile] as AABB
	geometry_rebuilds += 1
	var tile_node: Node = _world.view.get_node_or_null("Tile_%d_%d" % [tile.x, tile.y])
	var result: AABB
	var first: bool = true
	if tile_node == null:
		return AABB()
	var mesh_instances: Array = []
	_collect_fadeable_meshes(tile_node, mesh_instances)
	for mi in mesh_instances:
		var vi: VisualInstance3D = mi as VisualInstance3D
		if vi == null:
			continue
		var local_aabb: AABB = vi.get_aabb()
		var xform: Transform3D = vi.global_transform
		for i in range(8):
			var corner: Vector3 = local_aabb.position + Vector3(
				local_aabb.size.x if (i & 1) else 0.0,
				local_aabb.size.y if (i & 2) else 0.0,
				local_aabb.size.z if (i & 4) else 0.0
			)
			var world_corner: Vector3 = xform * corner
			if first:
				result = AABB(world_corner, Vector3.ZERO)
				first = false
			else:
				result = result.expand(world_corner)
	_aabb_by_tile[tile] = result
	return result


## Skips any node named "Slab" (the ground plane) — fading it would open a
## transparent hole in the ground, not "see past the tree."
func _collect_fadeable_meshes(node: Node, out: Array) -> void:
	if node.name == "Slab":
		return
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_fadeable_meshes(child, out)


func _update_tile(tile: Vector2i, blocked: bool) -> void:
	var current: bool = _faded_by_tile.get(tile, false)
	var pending: int = _pending_frames_by_tile.get(tile, 0)
	var had_cache: bool = _materials_by_tile.has(tile)
	if blocked != current:
		pending += 1
		if pending >= FADE_HYSTERESIS_FRAMES:
			current = blocked
			pending = 0
	else:
		pending = 0

	# "Settled unfaded": not currently faded, and not mid-hysteresis toward being
	# faded either — nothing about this tile's visual state needs attention.
	var settled_unfaded: bool = not current and pending == 0

	if settled_unfaded and not had_cache:
		# Never faded, not fading now, no material cache was ever built for it —
		# there is nothing to apply. Drop any stale hysteresis-only bookkeeping
		# (e.g. a pending count that just reset to 0) instead of leaving a
		# permanent entry for a tile that will never do anything again.
		_faded_by_tile.erase(tile)
		_pending_frames_by_tile.erase(tile)
		return

	if current or had_cache:
		# Either actually needs to be faded right now, or was faded before and its
		# cached materials need restoring to full opacity.
		_apply_fade(tile, current)

	if settled_unfaded:
		# Fully un-faded and settled: prune every tracking dict so steady-state
		# cost stays bounded by residents x radius rather than growing with every
		# forest tile ever visited over a session.
		_faded_by_tile.erase(tile)
		_pending_frames_by_tile.erase(tile)
		_materials_by_tile.erase(tile)
	else:
		_faded_by_tile[tile] = current
		_pending_frames_by_tile[tile] = pending


## Builds (once) and writes a per-surface, per-mesh unique material cache for a
## tile, then pushes `faded`'s target alpha into every cached material. Callers
## (`_update_tile()`) only invoke this when the tile is actually fading or was
## faded before and needs restoring — never for a tile that has settled unfaded
## and never had a cache, so a candidate tile that merely sits within a resident's
## check radius but never blocks anything is never touched.
func _apply_fade(tile: Vector2i, faded: bool) -> void:
	if not _materials_by_tile.has(tile):
		var tile_node: Node = _world.view.get_node_or_null("Tile_%d_%d" % [tile.x, tile.y])
		if tile_node == null:
			return
		var mesh_instances: Array = []
		_collect_fadeable_meshes(tile_node, mesh_instances)
		# Outer array is one entry per mesh instance; inner array is one unique
		# material per surface on that mesh (e.g. CommonTree_1.gltf's bark +
		# leaves) so `set_surface_override_material()` never collapses distinct
		# surfaces onto a single material the way a whole-instance
		# `material_override` would.
		var per_mesh_materials: Array = []
		for mi in mesh_instances:
			var mesh_instance: MeshInstance3D = mi as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null:
				continue
			var surface_materials: Array = []
			for i in range(mesh_instance.mesh.get_surface_count()):
				var base_material: Material = mesh_instance.get_active_material(i)
				var unique: StandardMaterial3D
				if base_material is StandardMaterial3D:
					unique = (base_material as StandardMaterial3D).duplicate()
				else:
					unique = StandardMaterial3D.new()
				mesh_instance.set_surface_override_material(i, unique)
				surface_materials.append(unique)
			per_mesh_materials.append(surface_materials)
		_materials_by_tile[tile] = per_mesh_materials

	if not faded:
		# Un-fade: do NOT write alpha=1.0 into the cached duplicate. The imported tree
		# materials (CommonTree_1.gltf's Bark/Leaves) ship with
		# TRANSPARENCY_ALPHA_SCISSOR (an alpha-cutout mode) — writing anything into the
		# duplicate and leaving it as the surface override, even at alpha=1.0, means the
		# tile never goes back to its real imported material. A prior version of this
		# function set TRANSPARENCY_DISABLED here, which ignores alpha entirely and
		# permanently turned the leaf cutout cards into solid opaque quads after any
		# fade/un-fade cycle. Clearing the override back to null restores the tile's
		# actual original material — untouched, with its correct transparency mode
		# intact — instead of a modified stand-in for it.
		var mesh_instances: Array = []
		var tile_node: Node = _world.view.get_node_or_null("Tile_%d_%d" % [tile.x, tile.y])
		if tile_node != null:
			_collect_fadeable_meshes(tile_node, mesh_instances)
			for mi in mesh_instances:
				var mesh_instance: MeshInstance3D = mi as MeshInstance3D
				if mesh_instance == null or mesh_instance.mesh == null:
					continue
				for i in range(mesh_instance.mesh.get_surface_count()):
					mesh_instance.set_surface_override_material(i, null)
		return

	for surface_materials: Array in _materials_by_tile[tile]:
		for mat in surface_materials:
			var sm: StandardMaterial3D = mat as StandardMaterial3D
			if sm == null:
				continue
			if is_equal_approx(sm.albedo_color.a, fade_alpha):
				continue
			# TRANSPARENCY_ALPHA_DEPTH_PRE_PASS, not plain TRANSPARENCY_ALPHA (human-
			# reported bug, 2026-08-26: "transparency view trees turn white when an
			# animal walks behind it"). Root cause: CommonTree1/CommonTree2's Bark/Leaves
			# surfaces are cull_mode = CULL_DISABLED (double-sided cutout foliage) with a
			# neutral-white albedo_color(1,1,1,1) base tint (the texture supplies the real
			# color). Plain TRANSPARENCY_ALPHA writes no depth, so at fade_alpha's mere
			# 0.9 (barely-transparent) every overlapping double-sided leaf-card triangle
			# in the canopy blends with every OTHER triangle behind it, not just with the
			# sky — dozens of near-opaque white-tinted layers stacked this way accumulate
			# toward white far more visibly than a single 10%-alpha layer would. Switching
			# to the depth-pre-pass variant writes real depth first, so only the nearest
			# visible layer actually blends (with whatever is truly behind it), which is
			# what "the tile fades by 10%" is supposed to look like. This was flagged as
			# the likely-correct fix in a prior pass but deferred pending visual
			# confirmation — this human report IS that confirmation.
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			var c: Color = sm.albedo_color
			c.a = fade_alpha
			sm.albedo_color = c
