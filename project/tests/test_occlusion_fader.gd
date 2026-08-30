extends QATestCase
## Bounded occlusion fade (→ D-41 spec §4): only forest tiles within
## RESIDENT_CHECK_RADIUS_TILES of an actual resident are ever tested, and only a
## tile actually blocking that resident's line of sight to the camera fades.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_occlusion_fader.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

var _world: WorldRoot = null
var _fader: OcclusionFader = null
var _frames: int = 0
var _setup_ok: bool = false
var _resident: Node3D = null
var _behind_point: Vector3 = Vector3.ZERO


func _initialize() -> void:
	begin("occlusion fader")
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

	_fader = _world.get_node_or_null("OcclusionFader") as OcclusionFader
	if not check(_fader != null, "Main.tscn has an OcclusionFader node"):
		finish()
		return true

	var camera: CameraRig = root.get_viewport().get_camera_3d() as CameraRig
	camera.initialize()

	# Paint a forest block, then a synthetic resident directly behind it from the
	# camera's own forward direction, mirroring the spike's validated approach.
	for x in range(8, 14):
		for z in range(10, 16):
			_world.paint_tile(x, z, "forest")
	var forward: Vector3 = -camera.transform.basis.z.normalized()
	_behind_point = _world.grid_to_world(10, 12) - forward * 3.0
	_resident = Node3D.new()
	_resident.position = _behind_point
	_world.add_child(_resident)
	camera.set_focus(_world.grid_to_world(10, 12))
	camera.set_zoom_tiles(CameraRig.ZOOM_MIN_TILES)

	# FADE_HYSTERESIS_FRAMES consecutive agreeing checks are required before a tile
	# actually flips (the flicker guard) — call enough times to let it settle, the
	# same way `FADE_HYSTERESIS_FRAMES` real 0.1s `_process()` ticks would in play.
	for i in range(OcclusionFader.FADE_HYSTERESIS_FRAMES):
		_fader.refresh([_resident])

	var faded_count: int = _fader.faded_tile_count_for_testing()
	check(
		faded_count >= 1 and faded_count <= 4,
		"a small number of tiles fade (%d), not the whole forest block" % faded_count
	)

	# Move the resident far away and re-check: it should un-fade, once the same
	# hysteresis window has elapsed in the other direction.
	_resident.position = _world.grid_to_world(30, 30)
	for i in range(OcclusionFader.FADE_HYSTERESIS_FRAMES):
		_fader.refresh([_resident])
	check_eq(
		_fader.faded_tile_count_for_testing(), 0,
		"nothing stays faded once no resident is behind it"
	)
	# Un-fading isn't enough on its own — the tile's cache entries must actually be
	# dropped from the tracking dicts, or steady-state cost grows with every forest
	# tile ever visited over a session (the bounded-cost claim this file promises).
	check_eq(
		_fader.tracked_tile_count_for_testing(), 0,
		"settled un-faded tiles are pruned from tracking, not just un-faded"
	)

	# The last resident vanishing (gentle_displacement.gd's queue_free() on
	# departure) must still let a faded tile un-fade — _process() must not
	# early-return on an empty resident list, since the un-fade sweep lives inside
	# refresh() itself.
	_resident.position = _behind_point
	for i in range(OcclusionFader.FADE_HYSTERESIS_FRAMES):
		_fader.refresh([_resident])
	check(
		_fader.faded_tile_count_for_testing() >= 1,
		"precondition: a tile is faded again before testing the empty-residents case"
	)
	for i in range(OcclusionFader.FADE_HYSTERESIS_FRAMES):
		_fader.refresh([])
	check_eq(
		_fader.faded_tile_count_for_testing(), 0,
		"a faded tile un-fades even when called with no residents at all"
	)

	_check_repaint_clears_stale_cache()
	_check_unfade_restores_original_material()
	_check_hysteresis_prevents_premature_flicker()
	_check_bounded_scan_ignores_distant_tile()

	finish()
	return true


## Round-2 regression: `WorldGrid.tile_changed` must actually be connected (deferred, since
## `WorldRoot.grid` doesn't exist yet during `OcclusionFader._ready()` — see `bind_world()`'s
## own comment) so a repainted tile's stale per-tile material cache gets dropped instead of
## silently pointing at freed mesh instances forever. This exercises the real repaint path
## (`WorldRoot.paint_tile()` -> `WorldGrid.set_terrain()` -> `tile_changed`), not just the
## visual outcome, since a dead connection here previously passed every other assertion above.
func _check_repaint_clears_stale_cache() -> void:
	# Fade the same tile behind the resident again, from scratch.
	_resident.position = _behind_point
	for i in range(OcclusionFader.FADE_HYSTERESIS_FRAMES):
		_fader.refresh([_resident])
	check(
		_fader.tracked_tile_count_for_testing() >= 1,
		"precondition: at least one tile is tracked before the repaint"
	)

	# Repaint every forest tile in the block to grass, then back to forest — this fires
	# WorldGrid.tile_changed once per tile via WorldRoot.paint_tile(), exactly the signal
	# `bind_world()` connects to.
	for x in range(8, 14):
		for z in range(10, 16):
			_world.paint_tile(x, z, "grass")
	for x in range(8, 14):
		for z in range(10, 16):
			_world.paint_tile(x, z, "forest")

	check_eq(
		_fader.tracked_tile_count_for_testing(), 0,
		"a repaint clears the stale cache entry for every tile it touched"
	)


## Which `forest.tres` `model_scenes` variants actually ship TRANSPARENCY_ALPHA_SCISSOR
## materials, keyed by scene resource path. Discovered at runtime by instantiating each
## variant once and reading its REAL surface materials — deliberately not a hardcoded list.
##
## WHY THIS IS DISCOVERED, NOT ASSUMED (2026-08-26): `forest.tres` grew from 3 variants to 8
## in the content-variety pass, and only the two `CommonTree` entries are alpha-cutout
## foliage — `PineTree` (already, before that pass), `BirchTree`, `DeadTree`, `PineTree2`,
## `Bush` and `BushBerries` all ship solid vertex-coloured meshes at TRANSPARENCY_DISABLED.
## The previous version of this suite hardcoded a tile block and asserted every variant that
## could land there was ALPHA_SCISSOR, which was already false for `PineTree` and became
## loudly false once the 5 new variants landed. The claim under test has nothing to do with
## WHICH variant a tile draws, so this file no longer bets on the tile-coordinate hash.
func _alpha_scissor_variant_paths() -> Dictionary:
	var result: Dictionary = {}
	var forest: TerrainDefinition = _world.grid.terrain_definition("forest")
	if forest == null:
		return result
	for variant: PackedScene in forest.model_scenes:
		if variant == null:
			continue
		var probe: Node = variant.instantiate()
		root.add_child(probe)
		var meshes: Array = []
		_fader._collect_fadeable_meshes(probe, meshes)
		for mesh_node in meshes:
			var mesh_instance: MeshInstance3D = mesh_node as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null:
				continue
			for surface in range(mesh_instance.mesh.get_surface_count()):
				var material: Material = mesh_instance.get_active_material(surface)
				if material is BaseMaterial3D and (material as BaseMaterial3D).transparency \
						== BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
					result[variant.resource_path] = true
		probe.free()
	return result


## A 3x3 block origin whose CENTRE tile stably resolves (via the same
## `TerrainDefinition.pick_variant(x, z)` hash `TerrainChunkLod` uses to build the visual) to
## one of the alpha-cutout variants in `scissor_paths` — so the regression guard below is
## exercised against a real cutout material by construction, not by luck of the hash.
##
## The centre tile is the one this suite asserts on because it is the tile the resident is
## placed directly behind, and therefore the one that always ends up in the blocked set when
## anything in the block fades at all (verified empirically across several block positions).
##
## Scan window: kept close to the block position this check has always used (20, 4), well
## clear of the 8..13/10..15 block the checks above repaint and of the (30, 30) tile
## `_check_bounded_scan_ignores_distant_tile()` uses, and close enough to the camera focus
## that its chunk is still near-tier (a far-tier chunk has no per-tile container at all, so
## nothing there can fade).
func _find_cutout_block_origin(scissor_paths: Dictionary) -> Vector2i:
	var forest: TerrainDefinition = _world.grid.terrain_definition("forest")
	if forest == null:
		return Vector2i(-1, -1)
	for origin_x in range(18, 26):
		for origin_z in range(2, 10):
			if not _world.grid.in_bounds(origin_x + 2, origin_z + 2):
				continue
			var centre_variant: PackedScene = forest.pick_variant(origin_x + 1, origin_z + 1)
			if centre_variant != null and scissor_paths.has(centre_variant.resource_path):
				return Vector2i(origin_x, origin_z)
	return Vector2i(-1, -1)


## Drives `refresh()` a full hysteresis window with `resident` parked far from anything, then
## retires it — so a check that bails early still leaves the fader settled and un-faded
## instead of cascading a single real failure into every later check's preconditions.
func _retire_regression_resident(resident: Node3D) -> void:
	resident.position = _world.grid_to_world(30, 30)
	for i in range(OcclusionFader.FADE_HYSTERESIS_FRAMES):
		_fader.refresh([resident])
	resident.queue_free()


## Final-review regression (Finding 1/2): un-fading a tile must restore its ACTUAL
## original material — with the imported tree material's real TRANSPARENCY_ALPHA_SCISSOR
## cutout mode intact — not a modified duplicate left at TRANSPARENCY_DISABLED (which
## renders the leaf cutout cards as solid opaque quads). The prior version of this file
## only ever asserted tile fade-STATE counts, never actual material state, which is
## exactly how this slipped past two prior review rounds.
##
## 2026-08-26 REWRITE (content-variety pass, final whole-branch review). Two assumptions this
## check used to make stopped being true once Forest grew to 8 variants and Wild grass grew
## desert-prop siblings:
##   1. "any tile in the hardcoded block is an ALPHA_SCISSOR tree" — false for 6 of Forest's
##      8 variants (and already false for `PineTree` before this pass). Fixed by picking the
##      block at runtime so the asserted tile is a real cutout variant, and by asserting the
##      restored transparency against the CAPTURED original rather than a hardcoded constant.
##   2. "a tile this check paints has exactly one fadeable mesh, because it is never
##      repainted" — false in both halves. Painting it forest IS a repaint (every tile starts
##      as wild grass), and `TerrainChunkLod._refresh_near_tile()`'s `queue_free()` of the old
##      visual is DEFERRED, so within this single synchronous `_process()` call the retired
##      visual is still a child of the tile container. That used to collect zero fadeable
##      meshes (wild grass keeps all its geometry under the exempt "Slab" node); Task 9's new
##      `WildGrassCactus`/`WildGrassPalm`/`WildGrassCoconut` variants hang their desert prop
##      OUTSIDE that wrapper, so the retired visual now contributes a fadeable mesh of its
##      own. Fixed by collecting the tile's fadeable meshes ONCE and asserting across every
##      mesh and every surface of that one captured list — which is race-proof by
##      construction, since the fader fades and restores exactly the same set.
func _check_unfade_restores_original_material() -> void:
	var scissor_paths: Dictionary = _alpha_scissor_variant_paths()
	if not check(
		not scissor_paths.is_empty(),
		"precondition: at least one forest model_scenes variant still ships ALPHA_SCISSOR "
		+ "cutout materials (the mode this regression guard exists for)",
		"no variant in forest.tres carries an ALPHA_SCISSOR material any more — the cutout "
		+ "regression below can no longer be exercised at all; re-check whether the guard is "
		+ "still meaningful rather than deleting it"
	):
		return
	var block_origin: Vector2i = _find_cutout_block_origin(scissor_paths)
	if not check(
		block_origin.x >= 0,
		"precondition: found a forest block whose centre tile draws an ALPHA_SCISSOR variant"
	):
		return

	var camera: Camera3D = root.get_viewport().get_camera_3d()
	var forward: Vector3 = -camera.transform.basis.z.normalized()
	for x in range(block_origin.x, block_origin.x + 3):
		for z in range(block_origin.y, block_origin.y + 3):
			_world.paint_tile(x, z, "forest")

	var tile := Vector2i(block_origin.x + 1, block_origin.y + 1)
	var centre: Vector3 = _world.grid_to_world(tile.x, tile.y)
	var regression_resident := Node3D.new()
	# Resident sits FARTHER along the camera's forward direction than the block
	# (`+ forward`, not `- forward`) so the block is genuinely between the camera and
	# the resident — real occlusion geometry, not just "near the block."
	regression_resident.position = centre + forward * 3.0
	_world.add_child(regression_resident)

	var tile_node: Node = _world.view.get_node_or_null("Tile_%d_%d" % [tile.x, tile.y])
	if not check(tile_node != null, "precondition: the centre tile's visual node exists"):
		_retire_regression_resident(regression_resident)
		return

	# Collect ONCE, then reuse this exact list for the baseline capture, the faded check and
	# the restore check — see the rewrite note above for why re-collecting between phases is
	# what made this check fragile.
	var mesh_instances: Array = []
	_fader._collect_fadeable_meshes(tile_node, mesh_instances)
	if not check(
		mesh_instances.size() >= 1,
		"precondition: the centre tile has at least one fadeable mesh",
		"got %d" % mesh_instances.size()
	):
		_retire_regression_resident(regression_resident)
		return

	# Capture every surface's REAL, untouched imported material before anything ever fades.
	var originals: Array = []  # per mesh instance: Array[Material], one per surface
	var scissor_surfaces: int = 0
	for mesh_node in mesh_instances:
		var mesh_instance: MeshInstance3D = mesh_node as MeshInstance3D
		var surface_materials: Array = []
		if mesh_instance != null and mesh_instance.mesh != null:
			for surface in range(mesh_instance.mesh.get_surface_count()):
				var material: Material = mesh_instance.get_active_material(surface)
				surface_materials.append(material)
				if material is BaseMaterial3D and (material as BaseMaterial3D).transparency \
						== BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
					scissor_surfaces += 1
		originals.append(surface_materials)
	if not check(
		scissor_surfaces >= 1,
		"precondition: the centre tile really draws an ALPHA_SCISSOR cutout material",
		"the chosen variant reported ALPHA_SCISSOR when probed standalone but not once "
		+ "instanced into the world"
	):
		_retire_regression_resident(regression_resident)
		return

	for i in range(OcclusionFader.FADE_HYSTERESIS_FRAMES):
		_fader.refresh([regression_resident])
	if not check(
		_fader.faded_tiles_for_testing().has(tile),
		"precondition: the centre tile — the one the resident sits directly behind — faded"
	):
		_retire_regression_resident(regression_resident)
		return

	# While faded, every surface override is a duplicate at TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	# — not plain TRANSPARENCY_ALPHA (2026-08-26, human-reported bug: cull-disabled double-
	# sided foliage like CommonTree1/2's leaves washed toward white under plain ALPHA, since
	# it writes no depth and every overlapping double-sided triangle blends with every OTHER
	# triangle behind it, not just with the sky — see occlusion_fader.gd's _apply_fade() for
	# the full mechanism).
	var faded_ok: bool = true
	var faded_materials: Array = []
	for mesh_index in mesh_instances.size():
		var mesh_instance: MeshInstance3D = mesh_instances[mesh_index] as MeshInstance3D
		var surface_materials: Array = []
		for surface in (originals[mesh_index] as Array).size():
			var material: Material = mesh_instance.get_active_material(surface)
			surface_materials.append(material)
			if not (material is BaseMaterial3D) \
					or (material as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS \
					or material == (originals[mesh_index] as Array)[surface]:
				faded_ok = false
		faded_materials.append(surface_materials)
	check(
		faded_ok,
		"while faded, EVERY surface of the tile carries a duplicate override at "
		+ "TRANSPARENCY_ALPHA_DEPTH_PRE_PASS — not the original material, and not only surface 0"
	)

	# Un-fade it (resident moved far away, full hysteresis window) and confirm every surface's
	# active material reverts to the mesh's OWN real material, transparency mode included.
	regression_resident.position = _world.grid_to_world(30, 30)
	for i in range(OcclusionFader.FADE_HYSTERESIS_FRAMES):
		_fader.refresh([regression_resident])
	if not check_eq(
		_fader.faded_tile_count_for_testing(), 0, "precondition: the tile settled un-faded"
	):
		regression_resident.queue_free()
		return

	var identity_restored: bool = true
	var still_faded_duplicate: bool = false
	var transparency_restored: bool = true
	var restored_scissor_surfaces: int = 0
	for mesh_index in mesh_instances.size():
		var mesh_instance: MeshInstance3D = mesh_instances[mesh_index] as MeshInstance3D
		var original_materials: Array = originals[mesh_index]
		for surface in original_materials.size():
			var original_material: Material = original_materials[surface]
			var restored_material: Material = mesh_instance.get_active_material(surface)
			if restored_material != original_material:
				identity_restored = false
			if restored_material == (faded_materials[mesh_index] as Array)[surface]:
				still_faded_duplicate = true
			var original_transparency: int = -1
			var restored_transparency: int = -2
			if original_material is BaseMaterial3D:
				original_transparency = (original_material as BaseMaterial3D).transparency
			if restored_material is BaseMaterial3D:
				restored_transparency = (restored_material as BaseMaterial3D).transparency
			if restored_transparency != original_transparency:
				transparency_restored = false
			if restored_transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				restored_scissor_surfaces += 1

	check(
		not still_faded_duplicate,
		"un-fade clears the surface override back to null — no surface is still showing the "
		+ "fader's faded duplicate"
	)
	check(
		identity_restored,
		"un-fade restores the SAME original material object captured before any fade ever "
		+ "ran, on every surface — not merely 'some different' material"
	)
	check(
		transparency_restored,
		"every restored surface carries the transparency mode its own imported material "
		+ "shipped with, whatever that mode is — the fader never rewrites it"
	)
	check_eq(
		restored_scissor_surfaces, scissor_surfaces,
		"REGRESSION GUARD: un-fade restores the real ALPHA_SCISSOR cutout mode on every "
		+ "cutout surface, not TRANSPARENCY_DISABLED (which would render the leaf cutout "
		+ "cards as solid opaque quads permanently after any fade/un-fade cycle)"
	)

	regression_resident.queue_free()


## Finding 5(a): every check above loops the FULL FADE_HYSTERESIS_FRAMES window before
## ever asserting, so an implementation with FADE_HYSTERESIS_FRAMES effectively a no-op
## (e.g. shipped as 1 — no flicker guard at all) would still pass every one of them.
## Prove the window is actually load-bearing: call refresh() with a blocking resident
## for ONE FEWER than FADE_HYSTERESIS_FRAMES calls (never enough to flip), then remove
## the blocking condition entirely — the tile must never have become faded.
func _check_hysteresis_prevents_premature_flicker() -> void:
	check_eq(
		_fader.tracked_tile_count_for_testing(), 0,
		"precondition: nothing tracked before the hysteresis-window check"
	)

	_resident.position = _behind_point
	for i in range(OcclusionFader.FADE_HYSTERESIS_FRAMES - 1):
		_fader.refresh([_resident])
	check_eq(
		_fader.faded_tile_count_for_testing(), 0,
		"a tile has NOT flipped to faded after one fewer than FADE_HYSTERESIS_FRAMES "
		+ "consecutive blocked checks"
	)

	# Remove the blocking condition before the window would ever have completed.
	_resident.position = _world.grid_to_world(30, 30)
	_fader.refresh([_resident])
	check_eq(
		_fader.faded_tile_count_for_testing(), 0,
		"...and it never becomes faded at all once the blocking condition is removed "
		+ "before the hysteresis window elapsed — proving the window actually guards "
		+ "against flicker rather than being cosmetic"
	)

	_resident.position = _behind_point


## Finding 5(b): the scan is bounded to RESIDENT_CHECK_RADIUS_TILES around each
## resident's own tile — a forest tile placed well outside that radius of every
## resident must never be added to tracking at all, proving the bound is real rather
## than "just happens to never fade."
func _check_bounded_scan_ignores_distant_tile() -> void:
	var distant_tile := Vector2i(30, 30)
	_world.paint_tile(distant_tile.x, distant_tile.y, "forest")
	_resident.position = _behind_point
	for i in range(OcclusionFader.FADE_HYSTERESIS_FRAMES):
		_fader.refresh([_resident])
	check(
		not _fader.is_tracked_for_testing(distant_tile),
		"a forest tile well outside RESIDENT_CHECK_RADIUS_TILES of every resident is "
		+ "never added to tracking at all"
	)
	_world.paint_tile(distant_tile.x, distant_tile.y, "grass")
