extends QATestCase
## THE OTHER HALF of the villager-variety fix (`test_villager_variant_variety.gd` owns the
## regression and the shuffle bag itself): a villager's look survives a `WorldSnapshot`
## capture/apply round trip, proven against the REAL save/load path rather than against
## `AnimalDefinition` in isolation.
##
## WHAT CHANGED HERE, AND WHY THE OLD CLAIM IS GONE. This suite used to close on "with NO
## save-format change" — the look was re-derived on load from a resident's slot within its home
## site's `residents` array, so nothing had to be written down. That derivation WAS the reported
## bug: a slot index is not a global identity, so the first resident at every home site in the
## world derived the same look. Replacing it with a per-species shuffle bag makes the look a real
## random choice made once at move-in, and a random choice that is not persisted is re-rolled on
## every load — every villager in a child's town would change clothes each time the game opened.
## So the look is now save state (`save_version` 5: a `residents` entry went from `[x, y, z]` to
## `[x, y, z, variant_index]`), and stability is a property of the FILE rather than of a hash.
##
## Three claims are pinned:
##   1. **Persistence.** The look each resident is wearing is written into the file, and reading
##      it back reproduces the same look — no re-roll.
##   2. **Distinctness survives.** Three residents given three different looks still have three
##      different looks after the round trip (a round trip that collapsed them would satisfy
##      claim 1 vacuously if they had started identical).
##   3. **OLD SAVES STILL LOAD.** A file whose `residents` entries are 3-element arrays — every
##      save written before this fix — loads with its full population and with the looks that
##      world already had on screen, via `AnimalDefinition.legacy_variant_index()`. No error, no
##      reshuffle: an existing village is not made worse, and it is not silently rearranged.

const WORLD_PATH: String = "res://scenes/Main.tscn"
const SITE_POS: Vector2i = Vector2i(10, 10)

## Three deliberately non-adjacent, non-derived look indices. Non-derived matters: if these
## happened to equal `legacy_variant_index(0..2)` the old-save fallback and the persisted path
## would be indistinguishable, and claim 1 would prove nothing.
const CHOSEN_LOOKS: Array[int] = [2, 7, 11]

var _source: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false

## Every `WorldRoot` this suite instantiates, freed together at the end. `queue_free()` is not
## enough here: `finish()` quits the tree on the same frame, so a deferred free never runs and
## the engine reports leaked instances at exit.
var _worlds: Array[WorldRoot] = []


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
	_worlds.append(_source)
	_setup_ok = _source != null


func _process(_delta: float) -> bool:
	if not _setup_ok:
		finish()
		return true
	_frames += 1
	if _frames < 3:
		return false

	_quiesce(_source)

	var human: AnimalDefinition = _source.roster.by_id("human")
	if not check(human != null, "the shipped roster carries `human`"):
		_cleanup()
		finish()
		return true
	if not check(human.model_scenes.size() > CHOSEN_LOOKS.max(),
			"human carries enough looks for this fixture's indices %s" % str(CHOSEN_LOOKS),
			"model_scenes.size() == %d" % human.model_scenes.size()):
		_cleanup()
		finish()
		return true

	# Seed 3 human residents directly, same shortcut test_world_snapshot.gd uses for "rabbit" —
	# bypasses arrival timing and exercises the same restore_site() the load path uses. The
	# looks are handed in explicitly, standing in for what the shuffle bag would have dealt at
	# move-in; the bag's own behaviour is `test_villager_variant_variety.gd`'s subject.
	var positions: Array = [
		_source.grid.tile_to_world(SITE_POS.x, SITE_POS.y),
		_source.grid.tile_to_world(SITE_POS.x, SITE_POS.y) + Vector3(0.3, 0, 0),
		_source.grid.tile_to_world(SITE_POS.x, SITE_POS.y) + Vector3(0.6, 0, 0),
	]
	var site: HomeSite = _source.simulation.restore_site(
		SITE_POS, "human", 8, [] as Array[String], positions, CHOSEN_LOOKS
	)
	if not check(site != null, "a 3-resident human site exists to capture"):
		_cleanup()
		finish()
		return true
	check_eq(site.residents.size(), 3, "all 3 residents were created (none silently dropped)")

	# Record which look each resident got, by index, BEFORE capture.
	var before_paths: Array[String] = []
	for resident: Node3D in site.residents:
		before_paths.append(resident.scene_file_path if resident != null else "")
	check(not before_paths.has(""), "every resident instantiated a real scene (no null model)")

	var distinct_before: Dictionary = {}
	for path: String in before_paths:
		distinct_before[path] = true
	check_eq(distinct_before.size(), 3,
		"the three residents start with three DIFFERENT looks, so a round trip that collapsed "
		+ "them could not pass the comparison below by accident")

	# Capture, then apply into a FRESH WorldRoot — the real load path, not a second
	# hand-built site.
	var data: Dictionary = WorldSnapshot.capture(_source, "W", "meadow_start", 0)

	_check_the_file_names_each_look(data)

	var restored_site: HomeSite = _apply_and_find(data, SITE_POS)
	if not check(restored_site != null, "the restored world carries the same home site"):
		_cleanup()
		finish()
		return true
	check_eq(restored_site.residents.size(), 3, "all 3 residents survived the round trip")

	var after_paths: Array[String] = []
	for resident: Node3D in restored_site.residents:
		after_paths.append(resident.scene_file_path if resident != null else "")

	check_eq(after_paths, before_paths,
		"each resident's look (by array index) is IDENTICAL before capture and after restore "
		+ "— proven against the real capture()/apply() path, and now carried by the file "
		+ "rather than re-derived from a slot index")

	_check_a_pre_v5_save_still_loads(data, human)

	_cleanup()
	finish()
	return true


# --- claim 1: the file names each look ---------------------------------------------------

func _check_the_file_names_each_look(data: Dictionary) -> void:
	check_eq(int(data["save_version"]), WorldSnapshot.SAVE_VERSION,
		"the capture is stamped at the current save_version")

	var entries: Array = _resident_entries(data, SITE_POS)
	if not check(entries.size() == 3, "the file holds 3 resident entries for the site"):
		return

	var written: Array[int] = []
	var all_four: bool = true
	for entry: Variant in entries:
		var xyz: Array = entry as Array
		if xyz.size() < 4:
			all_four = false
			continue
		written.append(int(xyz[3]))
	check(all_four, "every `residents` entry is [x, y, z, variant_index] — 4 elements, not 3")
	check_eq(written, CHOSEN_LOOKS,
		"...and the indices on disk are exactly the looks the residents are wearing")


# --- claim 3: a pre-v5 save still loads ---------------------------------------------------

## THE COMPATIBILITY HALF. Rewrites the captured file into the shape every save written before
## this fix has — `save_version: 4`, `residents` entries of 3 elements — and loads it.
##
## The expectation is deliberately the OLD derivation, not the new bag: an old file does not
## contain the looks, and the only answer that does not visibly rearrange a child's existing
## village is the one that reproduces what it was already showing.
func _check_a_pre_v5_save_still_loads(data: Dictionary, human: AnimalDefinition) -> void:
	var old: Dictionary = data.duplicate(true)
	old["save_version"] = 4
	for site_entry: Variant in old["home_sites"]:
		var s: Dictionary = site_entry as Dictionary
		var trimmed: Array = []
		for entry: Variant in (s["residents"] as Array):
			var xyz: Array = entry as Array
			trimmed.append([xyz[0], xyz[1], xyz[2]])
		s["residents"] = trimmed

	check(WorldSnapshot.can_apply(old), "a pre-v5 file is still openable")

	var restored: HomeSite = _apply_and_find(old, SITE_POS)
	if not check(restored != null, "a pre-v5 file's home site loads"):
		return
	check_eq(restored.residents.size(), 3,
		"...with its full population — a 3-element `residents` entry is not dropped")

	var expected: Array[String] = []
	for i in 3:
		var scene: PackedScene = human.variant_scene(human.legacy_variant_index(i))
		expected.append(scene.resource_path if scene != null else "")
	var actual: Array[String] = []
	for resident: Node3D in restored.residents:
		actual.append(resident.scene_file_path if resident != null else "")
	check_eq(actual, expected,
		"...and wearing exactly what that world already showed before the fix "
		+ "(legacy_variant_index), so an existing village does not reshuffle on first open")


# --- helpers -------------------------------------------------------------------------------

## Applies `data` into a fresh `WorldRoot` and returns the home site at `tile`, or null.
func _apply_and_find(data: Dictionary, tile: Vector2i) -> HomeSite:
	# `packed` from `_initialize()` is out of scope here (separate function), so it is reloaded
	# — the same pattern `test_save_round_trip.gd`'s helpers use every time they need a fresh
	# `WorldRoot` instance.
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var probe: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(probe)
	_worlds.append(probe)
	_quiesce(probe)
	WorldSnapshot.apply(probe, data)

	var found: HomeSite = null
	for s: HomeSite in probe.simulation.registry().sites():
		if s.position == tile:
			found = s
	# NOT freed here, unlike the old version of this suite: the caller reads the returned site's
	# resident nodes, so the world that owns them has to outlive the comparison. `_cleanup()`
	# takes them all down together at the end.
	return found


## Frees every world this suite built. Immediate `free()`, in reverse order of creation.
func _cleanup() -> void:
	for i in range(_worlds.size() - 1, -1, -1):
		var world: WorldRoot = _worlds[i]
		if world != null and is_instance_valid(world):
			world.free()
	_worlds.clear()


## Takes every `_process`-driven node off the frame clock, so nothing advances underneath a
## capture or a comparison.
func _quiesce(world: WorldRoot) -> void:
	world.simulation.set_process(false)
	world.wood.set_process(false)
	world.presentation.set_process(false)
	world.displacement.set_process(false)
	world.removals.set_process(false)


func _resident_entries(data: Dictionary, tile: Vector2i) -> Array:
	for site_entry: Variant in (data["home_sites"] as Array):
		var s: Dictionary = site_entry as Dictionary
		var pos: Array = s["position"] as Array
		if int(pos[0]) == tile.x and int(pos[1]) == tile.y:
			return s["residents"] as Array
	return []
