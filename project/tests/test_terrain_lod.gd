extends QATestCase
## Terrain LOD + collision-consolidation suite (2026-08-22 performance pass).
## See docs/superpowers/specs/2026-08-22-terrain-lod-web-threading-design.md.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_terrain_lod.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("terrain LOD + collision consolidation")
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

	if _frames == 3:
		_check_single_picking_body()
		_check_picking_body_resizes_on_grow()
		# The grown picking body's new extent is NOT visible to `intersect_ray()` in the
		# same frame the box is resized/moved — the physics server only rebuilds the
		# broadphase entry on its next step. Verified directly with a throwaway probe:
		# same-frame the ray into the newly-grown region misses, next-frame it resolves.
		# So the geometric proof that the box actually grew waits one frame; everything
		# after it runs on frame 4 instead of frame 3, which no other check depends on.
		return false

	_check_picking_body_covers_the_grown_region()
	_check_screen_to_grid_still_resolves_a_tile()
	_check_out_of_bounds_tap_is_still_a_miss()
	_check_chunk_of_groups_tiles_correctly()
	_check_is_near_true_within_radius()
	_check_is_near_false_beyond_radius()
	_check_far_tier_batches_into_multimesh()
	_check_near_tier_keeps_individual_scenes()
	_check_far_to_near_restores_individual_scenes()
	_check_update_camera_promotes_a_chunk_to_far()
	_check_single_tile_edit_rebuilds_only_its_own_chunk()
	_check_update_camera_bounds_rebuilds_per_call()
	_check_forest_style_default_resolves_variant()
	_check_rock_ignores_style_defaults()

	finish()
	return true


## THE CORE FIX: today's code creates one `StaticBody3D` per tile (up to 16,384 at the
## 128x128 cap). One body should answer every tap, at any grid size.
func _check_single_picking_body() -> void:
	var bodies: int = 0
	for child in _world.view.get_children():
		if child is StaticBody3D:
			bodies += 1
	check_eq(bodies, 1, "TerrainView has exactly 1 StaticBody3D after attach(), not one per tile")


## Growing the grid must not add a second body — the single body resizes in place.
func _check_picking_body_resizes_on_grow() -> void:
	_world.grid.grow(40, 40, 1)
	var bodies: int = 0
	for child in _world.view.get_children():
		if child is StaticBody3D:
			bodies += 1
	check_eq(bodies, 1, "growing the grid still leaves exactly 1 StaticBody3D")


## Proves the single body's box actually GREW, not just that the count stayed 1 — a bug that
## left the box at its original 36x36 size would pass the count check above. Runs one frame
## after the grow (see `_process()`) because the physics broadphase doesn't see the resize
## until its next step.
func _check_picking_body_covers_the_grown_region() -> void:
	# Tile (39, 39) is inside the newly-grown 40x40 region (the original grid was 36x36).
	var grown_tile_pos: Vector3 = _world.grid_to_world(39, 39)
	var camera: Camera3D = root.get_viewport().get_camera_3d()
	(camera as CameraRig).set_focus(grown_tile_pos)
	(camera as CameraRig).set_zoom_tiles(CameraRig.ZOOM_MIN_TILES)
	var screen: Vector2 = camera.unproject_position(grown_tile_pos)
	var picked: Vector2i = _world.screen_to_grid(screen)
	check_eq(picked, Vector2i(39, 39), "a tile inside the newly-grown region resolves — proves the box actually resized, not just that the count stayed 1")


## Picking must still resolve a real tile after the collision-body refactor.
func _check_screen_to_grid_still_resolves_a_tile() -> void:
	var world_pos: Vector3 = _world.grid_to_world(5, 5)
	var camera: Camera3D = root.get_viewport().get_camera_3d()
	(camera as CameraRig).initialize()
	(camera as CameraRig).set_focus(world_pos)
	(camera as CameraRig).set_zoom_tiles(CameraRig.ZOOM_MIN_TILES)
	var screen: Vector2 = camera.unproject_position(world_pos)
	var picked: Vector2i = _world.screen_to_grid(screen)
	check_eq(picked, Vector2i(5, 5), "tapping tile (5,5) still resolves via screen_to_grid()")


## A tap past the revealed rectangle must still miss, exactly as it did when only in-bounds
## tiles carried a body — proves the single body doesn't over-cover unrevealed land.
func _check_out_of_bounds_tap_is_still_a_miss() -> void:
	var beyond: Vector3 = _world.grid_to_world(_world.grid.width + 5, _world.grid.depth + 5)
	var camera: Camera3D = root.get_viewport().get_camera_3d()
	(camera as CameraRig).set_focus(beyond)
	(camera as CameraRig).set_zoom_tiles(CameraRig.ZOOM_MIN_TILES)
	var screen: Vector2 = camera.unproject_position(beyond)
	var picked: Vector2i = _world.screen_to_grid(screen)
	check_eq(picked, Vector2i(-1, -1), "a tap beyond the revealed rectangle is still a miss")


## STYLE-DEFAULT RESOLUTION (sub-project B2, Task 5): a Forest tile painted AFTER
## `style_defaults["forest"]` names a non-default look must render THAT look, never
## `pick_variant()`'s per-tile hash. Forces the tile's chunk to the near tier explicitly
## (rather than trusting the ambient default) because earlier checks in this suite have
## already driven `update_camera()` with several different focuses/zooms, so this chunk's
## tier by this point in the run is not something to assume.
func _check_forest_style_default_resolves_variant() -> void:
	var tile := Vector2i(90, 10)
	_world.style_defaults["forest"] = "birch_tree"
	check(_world.paint_tile(tile.x, tile.y, "forest"), "setup: forest paints at %s" % tile)
	var chunk_lod: TerrainChunkLod = _world.view._chunk_lod
	chunk_lod.set_chunk_tier(TerrainChunkLod.chunk_of(tile.x, tile.y), true)
	var container: Node3D = chunk_lod._tile_containers.get(tile, null) as Node3D
	if not check(container != null, "setup: tile %s has a near-tier container" % tile):
		return
	var rendered: String = _sole_child_name(container)
	check_eq(rendered, "BirchTree",
		"style_defaults[\"forest\"] = \"birch_tree\" renders BirchTree.tscn, "
		+ "not pick_variant()'s per-tile hash")


## The Rock terrain has no style picker (rock/water/cultivated_field are untouched by this
## feature by design — see terrain_chunk_lod.gd's `_resolve_variant()` header). Even a
## style_defaults entry keyed "rock" — which no UI ever writes, since "rock" is not one of
## the four picker categories — must be silently ignored: the rendered variant stays
## exactly what `pick_variant()`'s stable per-tile hash would have produced on its own.
func _check_rock_ignores_style_defaults() -> void:
	var tile := Vector2i(50, 90)
	var terrain: TerrainDefinition = _world.grid.terrain_definition("rock")
	var expected_scene: PackedScene = terrain.pick_variant(tile.x, tile.y)
	var expected_name: String = expected_scene.resource_path.get_file().get_basename()
	_world.style_defaults["rock"] = "birch_tree"  # not a real rock style; must be ignored
	check(_world.paint_tile(tile.x, tile.y, "rock"), "setup: rock paints at %s" % tile)
	var chunk_lod: TerrainChunkLod = _world.view._chunk_lod
	chunk_lod.set_chunk_tier(TerrainChunkLod.chunk_of(tile.x, tile.y), true)
	var container: Node3D = chunk_lod._tile_containers.get(tile, null) as Node3D
	if not check(container != null, "setup: tile %s has a near-tier container" % tile):
		return
	var rendered: String = _sole_child_name(container)
	check_eq(rendered, expected_name,
		"rock ignores style_defaults entirely and keeps pick_variant()'s stable per-tile hash")


## The name of a near-tier tile container's CURRENT visual — the LAST child, not
## necessarily the only one: `_refresh_near_tile()` queues a container's old children with
## `queue_free()` (deferred, not immediate) before `add_child()`-ing the new one, so within
## a single synchronous test script a just-replaced tile can briefly show both an old,
## about-to-be-freed child and the new one side by side. `add_child()` always appends, so
## the last child is always the current one regardless. Returns "" if the container is
## empty.
func _sole_child_name(container: Node3D) -> String:
	var count: int = container.get_child_count()
	return String(container.get_child(count - 1).name) if count > 0 else ""


## LOD_CHUNK_SIZE = 8: tiles (0,0)-(7,7) are chunk (0,0); (8,0) starts the next chunk over.
func _check_chunk_of_groups_tiles_correctly() -> void:
	check_eq(TerrainChunkLod.chunk_of(0, 0), Vector2i(0, 0), "tile (0,0) is in chunk (0,0)")
	check_eq(TerrainChunkLod.chunk_of(7, 7), Vector2i(0, 0), "tile (7,7) is still chunk (0,0)")
	check_eq(TerrainChunkLod.chunk_of(8, 0), Vector2i(1, 0), "tile (8,0) starts chunk (1,0)")
	check_eq(TerrainChunkLod.chunk_of(15, 23), Vector2i(1, 2), "tile (15,23) is chunk (1,2)")


func _check_is_near_true_within_radius() -> void:
	var centre := Vector3(5.0, 0.0, 5.0)
	var focus := Vector3(5.0, 0.0, 5.0)
	check(
		TerrainChunkLod.is_near(centre, focus, 10.0),
		"a chunk centred exactly on the camera focus is always near"
	)


func _check_is_near_false_beyond_radius() -> void:
	var centre := Vector3(500.0, 0.0, 500.0)
	var focus := Vector3(0.0, 0.0, 0.0)
	check(
		not TerrainChunkLod.is_near(centre, focus, 10.0),
		"a chunk far outside the near radius is far"
	)


## A far-tier chunk's tiles collapse into one MultiMeshInstance3D per terrain type present,
## not one node per tile.
func _check_far_tier_batches_into_multimesh() -> void:
	# Chunk (2,2) covers tiles (16..23, 16..23) at LOD_CHUNK_SIZE=8 — paint them all to rock
	# so the chunk is single-terrain and every MultiMeshInstance3D found belongs to it.
	for x in range(16, 24):
		for z in range(16, 24):
			_world.paint_tile(x, z, "rock")
	var chunk_lod: TerrainChunkLod = _world.view._chunk_lod
	chunk_lod.set_chunk_tier(Vector2i(2, 2), false)

	var multimeshes: int = 0
	var individual_containers: int = 0
	for x in range(16, 24):
		for z in range(16, 24):
			if chunk_lod._tile_containers.has(Vector2i(x, z)):
				individual_containers += 1
	# Scoped by node name to chunk (2,2)'s own batch rather than every MultiMeshInstance3D
	# under `chunk_lod`: `TerrainView._process()`'s throttled `update_camera()` could in
	# principle have demoted some other chunk by now, and a partly-painted chunk's batch
	# would have a different instance_count. Same scoping the far->near check below uses.
	for child in chunk_lod.get_children():
		if child is MultiMeshInstance3D and (child as MultiMeshInstance3D).name.begins_with("Far_rock_2_2_"):
			multimeshes += 1
			check_eq(
				(child as MultiMeshInstance3D).multimesh.instance_count, 64,
				"every far-tier MultiMeshInstance3D for this chunk has one instance per tile"
			)
	check(multimeshes >= 1, "chunk (2,2) batches into at least one MultiMeshInstance3D (rock's multi-piece asset produces more than one, correctly — see C1's fix)")
	check_eq(individual_containers, 0, "no near-tier containers remain for chunk (2,2)'s tiles once it's far-tier (I3b: proves _free_chunk_near actually ran)")


## A chunk explicitly set to the near tier still gets a real per-tile container/scene.
func _check_near_tier_keeps_individual_scenes() -> void:
	for x in range(0, 8):
		for z in range(0, 8):
			_world.paint_tile(x, z, "rock")
	var chunk_lod: TerrainChunkLod = _world.view._chunk_lod
	chunk_lod.set_chunk_tier(Vector2i(0, 0), true)

	var individual_containers: int = 0
	for x in range(0, 8):
		for z in range(0, 8):
			if chunk_lod._tile_containers.has(Vector2i(x, z)):
				individual_containers += 1
	check_eq(individual_containers, 64, "chunk (0,0) at the near tier has one container per tile")


## The far->near path (the reverse of _check_near_tier_keeps_individual_scenes) — currently
## untested before this check existed. Starts a chunk far, flips it to near, confirms real
## per-tile containers appear and the far-tier MultiMeshInstance3D nodes are gone.
func _check_far_to_near_restores_individual_scenes() -> void:
	var chunk := Vector2i(3, 3)  # tiles (24..31, 24..31) at LOD_CHUNK_SIZE=8
	for x in range(24, 32):
		for z in range(24, 32):
			_world.paint_tile(x, z, "rock")
	var chunk_lod: TerrainChunkLod = _world.view._chunk_lod
	chunk_lod.set_chunk_tier(chunk, false)

	var multimeshes_before: int = 0
	for child in chunk_lod.get_children():
		if child is MultiMeshInstance3D and (child as MultiMeshInstance3D).name.begins_with("Far_rock_3_3_"):
			multimeshes_before += 1
	check(multimeshes_before >= 1, "setup: chunk (3,3) is far-tier with at least one MultiMeshInstance3D before the flip")

	chunk_lod.set_chunk_tier(chunk, true)

	var individual_containers: int = 0
	for x in range(24, 32):
		for z in range(24, 32):
			if chunk_lod._tile_containers.has(Vector2i(x, z)):
				individual_containers += 1
	check_eq(individual_containers, 64, "chunk (3,3) flipped back to near has one real container per tile")

	var multimeshes_after: int = 0
	for child in chunk_lod.get_children():
		if child is MultiMeshInstance3D and (child as MultiMeshInstance3D).name.begins_with("Far_rock_3_3_"):
			multimeshes_after += 1
	check_eq(multimeshes_after, 0, "chunk (3,3)'s far-tier MultiMeshInstance3D nodes are gone after flipping back to near")


## A chunk far outside the near radius switches to the far tier once update_camera() runs,
## with no explicit set_chunk_tier() call.
func _check_update_camera_promotes_a_chunk_to_far() -> void:
	_world.grid.grow(104, 104, 1)
	for x in range(96, 104):
		for z in range(96, 104):
			_world.paint_tile(x, z, "rock")
	var chunk_lod: TerrainChunkLod = _world.view._chunk_lod
	# Growing to 104x104 registers ~169 chunks, most of them far from the origin focus below
	# — MAX_CHUNK_REBUILDS_PER_TICK bounds each call to a handful of rebuilds (the whole
	# point of that bound: a huge grid growth settles gradually over several ticks instead
	# of stalling in one synchronous call), so this drains it across enough calls to
	# guarantee every chunk, including the one this check cares about, gets its turn.
	for _tick in 60:
		chunk_lod.update_camera(Vector3.ZERO, 10.0)

	var far_chunk := Vector2i(12, 12)
	check_eq(
		chunk_lod._chunk_tiers.get(far_chunk, true), false,
		"a chunk 96+ tiles from a focus at the origin with zoom_tiles=10 goes far-tier"
	)


## Editing one tile's terrain must rebuild only that tile's chunk — never a whole-grid scan.
## Proven by watching a DIFFERENT chunk's node instance identity: it must not change.
func _check_single_tile_edit_rebuilds_only_its_own_chunk() -> void:
	var chunk_lod: TerrainChunkLod = _world.view._chunk_lod
	chunk_lod.set_chunk_tier(Vector2i(0, 0), true)
	var untouched_tile := Vector2i(3, 3)
	var before: Node3D = chunk_lod._tile_containers.get(untouched_tile, null) as Node3D
	check(before != null, "setup: tile (3,3) has a tracked near-tier visual before the edit")

	_world.paint_tile(0, 0, "forest")  # same chunk (0,0), different tile, genuine terrain change from "rock"

	var after: Node3D = chunk_lod._tile_containers.get(untouched_tile, null) as Node3D
	check_eq(
		before, after,
		"editing tile (0,0) does not replace tile (3,3)'s visual node identity "
		+ "(both are in chunk (0,0), so this proves the whole chunk isn't blindly torn down "
		+ "on every edit — only the edited tile's own chunk work happens)"
	)


## A large/fast zoom can cross the near/far threshold for MANY chunks in the same throttled
## tick. update_camera() must not rebuild all of them synchronously in one call — each
## rebuild is real work (node teardown/creation, mesh-piece extraction, MultiMesh
## construction), and an unbounded burst is a multi-second stall under WASM even though it's
## invisible on native (reported: zooming causing a several-second hang in the Web export).
##
## Measures the bound GLOBALLY (every chunk `TerrainChunkLod` knows about, not just a claimed
## subset) rather than assuming which specific chunks flip first — `_chunk_tiles.keys()`
## iterates in registration order, not distance order, so a test that only tracked "its own"
## chunks would be at the mercy of where those chunks happen to fall in that order relative
## to everything else already registered by earlier checks in this file.
func _check_update_camera_bounds_rebuilds_per_call() -> void:
	var chunk_lod: TerrainChunkLod = _world.view._chunk_lod

	for tile_x in range(40, 72):
		for tile_z in range(40, 72):
			_world.paint_tile(tile_x, tile_z, "rock")

	# Force EVERY currently-known chunk far, so a subsequent near-facing camera has a large
	# backlog to drain — guarantees more than MAX_CHUNK_REBUILDS_PER_TICK chunks want to
	# flip on the very next call, regardless of iteration order.
	var all_chunks: Array = chunk_lod._chunk_tiles.keys()
	for chunk: Vector2i in all_chunks:
		chunk_lod.set_chunk_tier(chunk, false)

	var focus: Vector3 = _world.grid_to_world(55, 55)  # centre of the freshly-painted range
	var before: Dictionary = chunk_lod._chunk_tiers.duplicate()
	chunk_lod.update_camera(focus, 20.0)  # radius = min(20*1+4, 24) = 24

	var changed_first_call: int = 0
	for chunk: Vector2i in all_chunks:
		if chunk_lod._chunk_tiers.get(chunk, true) != before.get(chunk, true):
			changed_first_call += 1
	check(
		changed_first_call >= 1,
		"setup: at least one chunk changed tier on the first call"
	)
	check(
		changed_first_call <= TerrainChunkLod.MAX_CHUNK_REBUILDS_PER_TICK,
		("a single update_camera() call rebuilds at most MAX_CHUNK_REBUILDS_PER_TICK chunks "
		+ "(%d changed, budget %d) — proves the rebuild work is bounded per call, even when "
		+ "far more than that many chunks need to flip") % [
			changed_first_call, TerrainChunkLod.MAX_CHUNK_REBUILDS_PER_TICK
		]
	)

	var before_second: Dictionary = chunk_lod._chunk_tiers.duplicate()
	chunk_lod.update_camera(focus, 20.0)  # second throttled tick: more should drain
	var changed_second_call: int = 0
	for chunk: Vector2i in all_chunks:
		if chunk_lod._chunk_tiers.get(chunk, true) != before_second.get(chunk, true):
			changed_second_call += 1
	check(
		changed_second_call >= 1,
		("a second update_camera() call drains more of the backlog (%d more changed) — "
		+ "proves it's a bounded DRAIN, not a permanent cap that never finishes")
		% changed_second_call
	)
