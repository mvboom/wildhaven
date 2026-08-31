extends QATestCase
## PERFORMANCE PROBE — not a gate, not collected by run-tests.sh (`test_*.gd` only).
##
## Answers one question with numbers instead of theory: at a large resident population,
## which per-frame subsystem actually costs the most, and HOW DOES EACH ONE SCALE?
##
## Every subsystem below is timed at several populations. The column that matters is
## "x2 cost ratio": a subsystem whose cost DOUBLES when the population doubles is O(N)
## and fine; one whose cost QUADRUPLES is O(N^2) and is what makes 150+ residents feel
## over-taxed while 40 feels fine.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/probe_frame_cost.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"
const POPULATIONS: Array[int] = [25, 50, 100, 200]
const FRAME_DELTA: float = 1.0 / 60.0
## Long enough that residents are past their initial pause and in steady-state wander.
const WARMUP_FRAMES: int = 900
const MEASURE_FRAMES: int = 600
const FADER_CALLS: int = 30
## A forest patch, so OcclusionFader has real candidate tiles to test (its cost scales
## with forest tiles AND residents).
const FOREST_ORIGIN: Vector2i = Vector2i(6, 6)
const FOREST_SIZE: Vector2i = Vector2i(28, 28)

var _world: WorldRoot = null
var _fader: OcclusionFader = null
var _frames: int = 0
var _setup_ok: bool = false
var _spawned: Array[Node3D] = []
var _rows: Array[Dictionary] = []


func _initialize() -> void:
	begin("frame cost probe")
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
	var camera: CameraRig = root.get_viewport().get_camera_3d() as CameraRig
	if camera != null:
		camera.initialize()
		camera.set_focus(_world.grid_to_world(24, 24))

	_paint_forest()

	print("")
	print("  grid %s | forest patch %s | %d frames measured per population" % [
		_world.grid_size(), FOREST_SIZE, MEASURE_FRAMES])
	print("")

	for target: int in POPULATIONS:
		_grow_population_to(target)
		_rows.append(_measure(target))

	_report()
	finish()
	return true


func _paint_forest() -> void:
	for x in range(FOREST_ORIGIN.x, FOREST_ORIGIN.x + FOREST_SIZE.x):
		for z in range(FOREST_ORIGIN.y, FOREST_ORIGIN.y + FOREST_SIZE.y):
			# Checkerboard: a solid block would be one big occluder; scattered forest is
			# both more realistic and more expensive, which is the honest case to measure.
			if (x + z) % 2 == 0:
				_world.grid.set_terrain(x, z, "forest")


## Spawns REAL resident model scenes (glTF with AnimationPlayer), registered in the real
## HomeSiteRegistry and presented through the real ResidentPresentation — the same objects
## a live game holds, so the numbers are the game's own, not a synthetic stand-in.
func _grow_population_to(target: int) -> void:
	var species_pool: Array[AnimalDefinition] = _world.roster.species()
	if species_pool.is_empty():
		return
	var grid_size: Vector2i = _world.grid_size()
	var index: int = _spawned.size()
	var stride: int = 3
	while _spawned.size() < target:
		var per_row: int = maxi(1, (grid_size.x - 4) / stride)
		var x: int = 2 + (index % per_row) * stride
		var z: int = 2 + (index / per_row) * stride
		index += 1
		if z >= grid_size.y - 2:
			break
		var species: AnimalDefinition = species_pool[_spawned.size() % species_pool.size()]
		if species.model_scenes.is_empty():
			continue
		var node: Node3D = (species.variant_scene(0) as PackedScene).instantiate() as Node3D
		if node == null:
			continue
		var pos := Vector2i(x, z)
		var site: HomeSite = _world.registry.register(pos, species.id, species.scout_radius)
		node.position = _world.grid_to_world(pos.x, pos.y)
		_world.add_child(node)
		site.residents.append(node)
		_world.presentation.present(node, site)
		_spawned.append(node)


func _measure(population: int) -> Dictionary:
	# Steady state first: a resident still in its spawn pause does no separation work, so
	# measuring cold would understate the walking cost that actually dominates.
	for _i in WARMUP_FRAMES:
		_world.presentation.tick(FRAME_DELTA)

	var walking: int = _walking_count()

	# --- Attribution by SUBTRACTION -------------------------------------------------
	# Nothing in production is edited. Each pass unbinds one more of the two O(N) neighbour
	# queries from every roamer, so the drop between passes IS that query's cost. The
	# roamers are restored to fully-bound before the next population grows.
	var full_usec: float = _time_ticks()
	_set_providers(true, false)
	var no_separation_usec: float = _time_ticks()
	_set_providers(false, false)
	var bare_usec: float = _time_ticks()
	_set_providers(true, true)

	var sim_usec: float = 0.0
	var t0: int = Time.get_ticks_usec()
	for _i in MEASURE_FRAMES:
		_world.simulation.tick(FRAME_DELTA)
	sim_usec = float(Time.get_ticks_usec() - t0) / float(MEASURE_FRAMES)

	var fader_usec: float = 0.0
	var aabb_usec: float = 0.0
	var candidates: int = 0
	if _fader != null:
		var residents: Array = []
		for node: Node3D in _spawned:
			residents.append(node)
		t0 = Time.get_ticks_usec()
		for _i in FADER_CALLS:
			_fader.refresh(residents)
		fader_usec = float(Time.get_ticks_usec() - t0) / float(FADER_CALLS)
		# How much of that is recomputing STATIC tile geometry every single call?
		var tiles: Array = _candidate_tiles(residents)
		candidates = tiles.size()
		t0 = Time.get_ticks_usec()
		for _i in FADER_CALLS:
			for tile: Vector2i in tiles:
				_fader._tile_aabb(tile)
		aabb_usec = float(Time.get_ticks_usec() - t0) / float(FADER_CALLS)

	var paint: Dictionary = _measure_paint()
	var eval_detail: Dictionary = _measure_evaluation()
	var arrival_detail: Dictionary = _measure_arrival()

	return {
		"population": population,
		"paint_frames": paint["frames"],
		"paint_usec": paint["usec"],
		"paint_evals": paint["evals"],
		"paint_worst": paint["worst"],
		"call": paint["call"],
		"nav": paint["nav"],
		"eval_usec": eval_detail["eval"],
		"struct_usec": eval_detail["struct"],
		"tiles": eval_detail["tiles"],
		"arrival_usec": arrival_detail["arrival"],
		"full_rebuild_usec": arrival_detail["full_rebuild"],
		"actual": _spawned.size(),
		"walking": walking,
		"roamer": full_usec,
		"no_sep": no_separation_usec,
		"bare": bare_usec,
		"sim": sim_usec,
		"fader": fader_usec,
		"aabb": aabb_usec,
		"candidates": candidates,
	}


## THE PLAYER-ACTION COST. Paints one tile and then drives frames until the simulation
## goes idle again, timing the whole recovery. `_mark_neighbourhood_dirty()` enqueues the
## painted tile PLUS every home site whose radius covers it — so the more residents are
## packed around that tile, the longer this takes, and it is spread over many frames
## because the drain budget is MAX_EVALUATIONS_PER_FRAME.
func _measure_paint() -> Dictionary:
	var grid_size: Vector2i = _world.grid_size()
	var target := Vector2i(grid_size.x / 2, grid_size.y / 2)
	var before: int = _world.simulation.evaluations_run
	# Drain anything already pending so we time THIS paint only.
	var guard: int = 0
	while not _world.simulation.is_idle() and guard < 100000:
		_world.simulation.tick(FRAME_DELTA)
		guard += 1

	# The REAL player path, not a raw grid poke: paint_tile() is what a Terraform tap calls,
	# and it does far more than set a tile (navmesh rebuild, displacement window, mist).
	_world.wood.add(100000)
	var current: String = _world.grid.get_terrain_id(target.x, target.y)
	var paint_to: String = "forest" if current != "forest" else "wild_grass"

	before = _world.simulation.evaluations_run
	var t_paint: int = Time.get_ticks_usec()
	var painted: bool = _world.paint_tile(target.x, target.y, paint_to)
	var paint_call_usec: float = float(Time.get_ticks_usec() - t_paint)

	# How much of that single synchronous call was the full navmesh rebuild?
	var t_nav: int = Time.get_ticks_usec()
	_world.navigation.rebuild_from_grid(_world.grid)
	var nav_usec: float = float(Time.get_ticks_usec() - t_nav)

	var frames: int = 0
	var worst: int = 0
	var t0: int = Time.get_ticks_usec()
	while not _world.simulation.is_idle() and frames < 100000:
		var f0: int = Time.get_ticks_usec()
		_world.simulation.tick(FRAME_DELTA)
		worst = maxi(worst, Time.get_ticks_usec() - f0)
		frames += 1
	var total: int = Time.get_ticks_usec() - t0

	return {
		"frames": frames,
		"usec": float(total),
		"evals": _world.simulation.evaluations_run - before,
		"worst": float(worst),
		"call": paint_call_usec,
		"nav": nav_usec,
		"painted": painted,
	}


## ONE evaluation, broken down. An evaluation is one candidate tile against the WHOLE
## roster. Inside it, `CapacityEvaluator._tile_counts_for()` calls
## `HomeSiteRegistry.structure_site_at()` once per tile per species — and that function is
## a LINEAR SCAN over every registered home site. This times the whole evaluation, then
## times just the scans it performs, so the share is measured rather than reasoned about.
func _measure_evaluation() -> Dictionary:
	var grid_size: Vector2i = _world.grid_size()
	var origin := Vector2i(grid_size.x / 2, grid_size.y / 2)
	var species_pool: Array[AnimalDefinition] = _world.roster.species()

	var t0: int = Time.get_ticks_usec()
	var tiles: int = 0
	for species: AnimalDefinition in species_pool:
		CapacityEvaluator.capacity(_world.grid, _world.registry, origin, species, null)
		var r: int = species.effective_capacity_radius()
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if dx * dx + dz * dz <= r * r:
					tiles += 1
	var eval_usec: float = float(Time.get_ticks_usec() - t0)

	# The same number of structure_site_at() calls that evaluation just made.
	t0 = Time.get_ticks_usec()
	for species: AnimalDefinition in species_pool:
		var r: int = species.effective_capacity_radius()
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if dx * dx + dz * dz > r * r:
					continue
				_world.registry.structure_site_at(origin + Vector2i(dx, dz))
	var struct_usec: float = float(Time.get_ticks_usec() - t0)

	return {"eval": eval_usec, "struct": struct_usec, "tiles": tiles}


## WHAT A MOVE-IN ACTUALLY COSTS THE REGISTRY, measured through the public API a real
## arrival uses — `register()` then `unregister()` — rather than by poking
## `rebuild_ownership()` directly. That distinction matters now that the rebuild is scoped:
## calling it with no arguments still means "rebuild every scope", which is the save-load
## path, NOT the arrival path. Both are reported so the narrowing is visible.
func _measure_arrival() -> Dictionary:
	var grid_size: Vector2i = _world.grid_size()
	var free_tile := Vector2i(grid_size.x - 2, grid_size.y - 2)

	var t0: int = Time.get_ticks_usec()
	for i in 10:
		var site: HomeSite = _world.registry.register(free_tile, "rabbit", 8)
		_world.registry.unregister(site)
	# Two registry mutations per iteration (one in, one out), so halve for a per-arrival cost.
	var arrival_usec: float = float(Time.get_ticks_usec() - t0) / 20.0

	t0 = Time.get_ticks_usec()
	for _i in 5:
		_world.registry.rebuild_ownership()
	var full_usec: float = float(Time.get_ticks_usec() - t0) / 5.0

	return {"arrival": arrival_usec, "full_rebuild": full_usec}


func _time_ticks() -> float:
	var t0: int = Time.get_ticks_usec()
	for _i in MEASURE_FRAMES:
		_world.presentation.tick(FRAME_DELTA)
	return float(Time.get_ticks_usec() - t0) / float(MEASURE_FRAMES)


## Rebinds (or clears) each roamer's two neighbour-query callables. Clearing one makes
## `ResidentRoamer` take its own documented early-out, so the measured drop is exactly
## that query and nothing else.
func _set_providers(avoid: bool, separation: bool) -> void:
	for i in _world.presentation.roamer_count():
		var r: ResidentRoamer = _world.presentation.roamer(i)
		if r == null or not r.is_valid():
			continue
		if avoid:
			r.set_nearby_avoid_provider(
				Callable(_world.presentation, "_nearby_avoid_positions").bind(r))
		else:
			r.set_nearby_avoid_provider(Callable())
		if separation:
			r.set_nearby_resident_provider(
				Callable(_world.presentation, "_nearby_resident_positions").bind(r))
		else:
			r.set_nearby_resident_provider(Callable())


## The same candidate set `OcclusionFader.refresh()` builds, so the AABB timing above
## covers exactly the tiles the real sweep touches.
func _candidate_tiles(residents: Array) -> Array:
	var out: Dictionary = {}
	for resident: Node3D in residents:
		var tile: Vector2i = _world.grid.world_to_tile(resident.global_position)
		var r: int = OcclusionFader.RESIDENT_CHECK_RADIUS_TILES
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var c := Vector2i(tile.x + dx, tile.y + dz)
				if _world.grid.get_terrain_id(c.x, c.y) == "forest":
					out[c] = true
	return out.keys()


func _walking_count() -> int:
	var count: int = 0
	for i in _world.presentation.roamer_count():
		var r: ResidentRoamer = _world.presentation.roamer(i)
		if r != null and r.is_valid() and r.state_name() == "Walk":
			count += 1
	return count


func _report() -> void:
	print("")
	print("  ResidentPresentation.tick() — us per 60fps frame, and where it goes")
	print("  %-5s %-8s | %9s | %9s | %9s | %9s | %9s" % [
		"pop", "walking", "TOTAL", "ratio", "separation", "avoids", "motion"])
	print("  " + "-".repeat(84))
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var ratio: String = "    -"
		if i > 0:
			ratio = "x%.2f" % _ratio(_rows[i - 1]["roamer"], row["roamer"])
		print("  %-5d %-8d | %9.1f | %9s | %9.1f | %9.1f | %9.1f" % [
			row["actual"], row["walking"], row["roamer"], ratio,
			row["roamer"] - row["no_sep"], row["no_sep"] - row["bare"], row["bare"]])

	print("")
	print("  OcclusionFader.refresh() — us per call, called 10x per second")
	print("  %-5s %-11s | %9s | %9s | %-28s" % [
		"pop", "forest tiles", "TOTAL", "ratio", "of which _tile_aabb() rebuild"])
	print("  " + "-".repeat(84))
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var ratio: String = "    -"
		if i > 0:
			ratio = "x%.2f" % _ratio(_rows[i - 1]["fader"], row["fader"])
		var pct: float = 0.0
		if row["fader"] > 0.0:
			pct = 100.0 * float(row["aabb"]) / float(row["fader"])
		print("  %-5d %-11d | %9.1f | %9s | %9.1f  (%.0f%% of the call)" % [
			row["actual"], row["candidates"], row["fader"], ratio, row["aabb"], pct])

	print("")
	print("  ONE TILE PAINT — what a single player terraform action actually costs")
	print("  %-5s | %14s | %6s | %10s | %-18s | %s" % [
		"pop", "paint_tile() call", "evals", "frames", "drain to idle",
		"one nav rebuild*"])
	print("  " + "-".repeat(88))
	for row: Dictionary in _rows:
		print("  %-5d | %11.0f us | %6d | %10d | %9.0f us (worst %5.0f us) | %7.0f us" % [
			row["actual"], row["call"], row["paint_evals"],
			row["paint_frames"], row["paint_usec"], row["paint_worst"], row["nav"]])
	print("  * measured by calling rebuild_from_grid() explicitly. Since edits were coalesced")
	print("    it is NO LONGER part of paint_tile() — a burst of paints pays it once, later.")

	print("")
	print("  INSIDE ONE EVALUATION (one candidate tile vs the whole 14-species roster)")
	print("  %-5s | %10s | %16s | %-34s" % [
		"pop", "tile checks", "whole evaluation", "of which structure_site_at() scans"])
	print("  " + "-".repeat(88))
	for row: Dictionary in _rows:
		var pct: float = 0.0
		if float(row["eval_usec"]) > 0.0:
			pct = 100.0 * float(row["struct_usec"]) / float(row["eval_usec"])
		print("  %-5d | %10d | %13.0f us | %13.0f us  (%.0f%% of the evaluation)" % [
			row["actual"], row["tiles"], row["eval_usec"], row["struct_usec"], pct])

	print("")
	print("  ONE RESIDENT ARRIVAL — the registry work a move-in costs")
	print("  %-5s | %22s | %-34s" % [
		"pop", "per arrival", "a full all-scopes rebuild, for comparison"])
	print("  " + "-".repeat(88))
	for row: Dictionary in _rows:
		print("  %-5d | %19.0f us | %19.0f us" % [
			row["actual"], row["arrival_usec"], row["full_rebuild_usec"]])

	print("")
	print("  HabitatSimulation.tick() on an idle world: %.2f us/frame — the event-driven" % _rows[-1]["sim"])
	print("  zero holds. Background simulation is NOT a cost here.")
	print("")
	print("  Population doubles between rows: x~2 = linear, x~4 = quadratic.")
	var last: Dictionary = _rows[-1]
	var per_frame: float = float(last["roamer"]) + float(last["fader"]) / 6.0
	print("  At %d residents, native headless CPU per 60fps frame: %.0f us of 16667 (%.1f%%)," % [
		last["actual"], per_frame, 100.0 * per_frame / 16667.0])
	print("  and the fader arrives as a single %.0f us spike 10x a second, not spread out." % last["fader"])
	print("")
	check(true, "probe complete (no assertions — read the tables above)")


## Cost growth between two adjacent rows. Population doubles each row, so this IS the
## scaling exponent read directly: ~2 is linear, ~4 is quadratic.
func _ratio(before: Variant, after: Variant) -> float:
	var b: float = float(before)
	if b <= 0.0:
		return 0.0
	return float(after) / b
