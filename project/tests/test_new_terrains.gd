extends QATestCase
## The three terrains the habitat-tiers ruling added, and their tag emissions.
##
## Run:
##   bash scripts/run-tests.sh new_terrains

const EXPECTED: Dictionary = {
	"meadow": ["open_grass", "flowers"],
	"scrub": ["browse", "rocks"],
	"snowfield": ["snow"],
}


func _init() -> void:
	begin("new terrains")
	var found: Dictionary = _load_terrains()
	for id: String in EXPECTED:
		var def: TerrainDefinition = found.get(id, null)
		if not check(def != null, "terrain \"%s\" exists" % id):
			continue
		var expected: Array = EXPECTED[id]
		check_eq(def.emitted_tags.size(), expected.size(), "\"%s\" emits %d tag(s)" % [id, expected.size()])
		for tag: String in expected:
			check(def.emitted_tags.has(tag), "\"%s\" emits \"%s\"" % [id, tag])
			check(AnimalDefinition.HABITAT_TAGS.has(tag), "\"%s\" is in the shared vocabulary" % tag)
		check_eq(def.cost, 0, "\"%s\" is natural terrain and free to paint" % id)
		check(not def.model_scenes.is_empty(), "\"%s\" has at least one model" % id)
		check(def.validate().is_empty(), "\"%s\" validates clean" % id)

	# The inert-land invariant must be untouched: wild grass still emits nothing.
	# derive_bare_tags() takes the loaded definition set (see terrain_definition.gd) —
	# not a bare call — so this reads directly off disk via load_all(), same as
	# test_bare_tags_derivation.gd does.
	var bare: PackedStringArray = TerrainDefinition.derive_bare_tags(TerrainDefinition.load_all())
	check(bare.is_empty(), "wild grass still emits nothing — the inert-land invariant holds")
	finish()


func _load_terrains() -> Dictionary:
	var found: Dictionary = {}
	for path: String in _tres_paths("res://data/terrain"):
		var res: Resource = load(path)
		if res is TerrainDefinition:
			found[(res as TerrainDefinition).id] = res
	return found


func _tres_paths(dir_path: String) -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			paths.append_array(_tres_paths("%s/%s" % [dir_path, entry]))
		elif entry.ends_with(".tres"):
			paths.append("%s/%s" % [dir_path, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	return paths
