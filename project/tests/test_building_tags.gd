extends QATestCase
## Every placeable's `emitted_tags`, pinned. These are the tag SOURCES the roster reads,
## so a silent change here would break species that look fine in isolation.
##
## Run:
##   bash scripts/run-tests.sh building_tags

const EXPECTED: Dictionary = {
	"house": ["built", "house"],
	"farmhouse": ["built", "house", "large_house"],
	"small_barn": ["built", "barn"],
	"barn": ["built", "barn", "large_barn"],
	"open_barn": ["built", "barn", "stable"],
	"chicken_coop": ["built", "coop"],
	"silo": ["built", "silo"],
	"windmill": ["built", "mill"],
	"well": ["built", "water"],
	"water_tower": ["built", "water"],
}


func _init() -> void:
	begin("building tags")
	var found: Dictionary = _load_placeables()
	for id: String in EXPECTED:
		var def: PlaceableDefinition = found.get(id, null)
		if not check(def != null, "placeable \"%s\" exists" % id):
			continue
		var expected: Array = EXPECTED[id]
		var actual: Array[String] = def.emitted_tags
		check_eq(actual.size(), expected.size(), "\"%s\" emits %d tag(s)" % [id, expected.size()])
		for tag: String in expected:
			check(actual.has(tag), "\"%s\" emits \"%s\"" % [id, tag])
		check(
			actual.has("built"),
			"\"%s\" emits `built` — the universal exclusion handle" % id
		)
		for tag: String in actual:
			check(
				AnimalDefinition.HABITAT_TAGS.has(tag),
				"\"%s\" tag \"%s\" is in the shared vocabulary" % [id, tag]
			)
	finish()


func _load_placeables() -> Dictionary:
	var found: Dictionary = {}
	for path: String in _tres_paths("res://data/buildings"):
		var res: Resource = load(path)
		if res is PlaceableDefinition:
			found[(res as PlaceableDefinition).id] = res
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
