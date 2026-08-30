extends QATestCase
## Unit coverage for AnimalDefinition.pick_variant() and the model_scenes schema field —
## no coverage of this shape existed for either AnimalDefinition or its TerrainDefinition
## sibling before this suite (checked by reading test_terrain_schema.gd in full: it
## asserts model_scenes is non-empty, never that pick_variant() distributes correctly).

const GREY_BOX: String = "res://assets/placeholder/grass/Grass.tscn"

func _init() -> void:
	begin("AnimalDefinition.pick_variant()")

	var grey: PackedScene = load(GREY_BOX) as PackedScene
	if not check(grey != null, "fixture grey-box scene loads"):
		finish()
		return

	# --- empty model_scenes returns null, never crashes -----------------------
	var empty_def := AnimalDefinition.new()
	check(empty_def.pick_variant(0) == null, "empty model_scenes: pick_variant() returns null")
	check(empty_def.pick_variant(7) == null, "...for any index, not just 0")

	# --- single entry: always that entry, no hashing needed --------------------
	var single_def := AnimalDefinition.new()
	single_def.model_scenes = [grey]
	check_eq(single_def.pick_variant(0), grey, "single entry: index 0 returns the one scene")
	check_eq(single_def.pick_variant(41), grey, "...and so does any other index")

	# --- multiple entries: same index always returns the same scene ------------
	var multi_def := AnimalDefinition.new()
	var scene_a: PackedScene = grey
	var scene_b: PackedScene = load("res://assets/placeholder/forest/Forest.tscn") as PackedScene
	if not check(scene_b != null, "second fixture scene loads"):
		finish()
		return
	multi_def.model_scenes = [scene_a, scene_b]
	var first_pick: PackedScene = multi_def.pick_variant(3)
	check(first_pick == scene_a or first_pick == scene_b,
		"a real index picks one of the entries, not null or garbage")
	check_eq(multi_def.pick_variant(3), first_pick,
		"the SAME index always returns the SAME scene (stability, not a fresh roll)")

	# --- distribution: not every index collapses to the same entry -------------
	# Not a statistical claim — just proves the hash actually varies with index, the same
	# thing TerrainDefinition.pick_variant()'s x/z hashing relies on.
	var seen: Dictionary = {}
	for i in range(20):
		seen[multi_def.pick_variant(i)] = true
	check(seen.size() > 1,
		"across 20 distinct indices, more than one model_scenes entry gets picked",
		"got only %d distinct result(s) — hash is not varying with index" % seen.size())

	finish()
