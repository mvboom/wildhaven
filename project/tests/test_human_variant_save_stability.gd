extends QATestCase
## Closes the content-variety-pass spec's core claim: a villager's randomly-chosen human
## look survives a WorldSnapshot capture/apply round trip, with NO save-format change —
## proven against the REAL save/load path, not just AnimalDefinition.pick_variant() in
## isolation (that determinism is test_animal_variant_spawn.gd's job).

const WORLD_PATH: String = "res://scenes/Main.tscn"
const SITE_POS: Vector2i = Vector2i(10, 10)

var _source: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("human variant save/load stability")
	# `packed` is deliberately local to this function and NOT promoted to a member: `_process()`
	# needs its own `WorldRoot` instance later and re-`load()`s the same scene there, the same
	# pattern `test_save_round_trip.gd`'s helpers use. Sharing one variable across the two
	# function scopes does not compile.
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	_source = packed.instantiate() as WorldRoot
	root.add_child(_source)
	_setup_ok = _source != null


func _process(_delta: float) -> bool:
	if not _setup_ok:
		finish()
		return true
	_frames += 1
	if _frames < 3:
		return false

	_source.simulation.set_process(false)
	_source.wood.set_process(false)
	_source.presentation.set_process(false)
	_source.displacement.set_process(false)
	_source.removals.set_process(false)

	# Seed 3 human residents directly, same shortcut test_world_snapshot.gd uses for
	# "rabbit" — bypasses arrival timing, exercises the same restore_site() Task 2 changed.
	var positions: Array = [
		_source.grid.tile_to_world(SITE_POS.x, SITE_POS.y),
		_source.grid.tile_to_world(SITE_POS.x, SITE_POS.y) + Vector3(0.3, 0, 0),
		_source.grid.tile_to_world(SITE_POS.x, SITE_POS.y) + Vector3(0.6, 0, 0),
	]
	var site: HomeSite = _source.simulation.restore_site(
		SITE_POS, "human", 8, [] as Array[String], positions
	)
	if not check(site != null, "a 3-resident human site exists to capture"):
		finish()
		return true
	check_eq(site.residents.size(), 3, "all 3 residents were created (pick_variant(i) never silently dropped one)")

	# Record which look each resident got, by index, BEFORE capture.
	var before_paths: Array[String] = []
	for resident: Node3D in site.residents:
		before_paths.append(resident.scene_file_path if resident != null else "")
	check(not before_paths.has(""), "every resident instantiated a real scene (no null model)")

	# Capture, then apply into a FRESH WorldRoot — the real load path, not a second
	# hand-built site.
	var data: Dictionary = WorldSnapshot.capture(_source, "W", "meadow_start", 0)

	# `packed` from `_initialize()` is out of scope here (separate function), so it is
	# reloaded — the same pattern `test_save_round_trip.gd`'s helpers use every time they
	# need a fresh `WorldRoot` instance.
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var probe: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(probe)
	probe.simulation.set_process(false)
	probe.wood.set_process(false)
	probe.presentation.set_process(false)
	probe.displacement.set_process(false)
	probe.removals.set_process(false)
	WorldSnapshot.apply(probe, data)

	var restored_site: HomeSite = null
	for s: HomeSite in probe.simulation.registry().sites():
		if s.position == SITE_POS:
			restored_site = s
	if not check(restored_site != null, "the restored world carries the same home site"):
		probe.queue_free()
		finish()
		return true
	check_eq(restored_site.residents.size(), 3, "all 3 residents survived the round trip")

	var after_paths: Array[String] = []
	for resident: Node3D in restored_site.residents:
		after_paths.append(resident.scene_file_path if resident != null else "")

	check_eq(after_paths, before_paths,
		"each resident's look (by array index) is IDENTICAL before capture and after "
		+ "restore — the spec's 'no save-format change, stable villager identity' claim, "
		+ "proven against the real capture()/apply() path")

	probe.queue_free()
	finish()
	return true
