extends QATestCase
## THE DERIVATION LAYER — habitat_needs -> emitted_tags -> palette button -> glyph.
##
## The two arithmetic traps this suite exists to pin:
##   * Rock emits BOTH `cover` and `rocks`, so Stag's three needs must collapse to TWO
##     chips, not three;
##   * and a rock tile qualifies for both tags independently, so the merged chip's count is
##     `tiles_per_individual` (8), NOT double it.
##
## Run:
##   bash scripts/run-tests.sh habitat_recipe

const WORLD_PATH: String = "res://scenes/Main.tscn"
const FOX_PATH: String = "res://data/animals/fox.tres"
const STAG_PATH: String = "res://data/animals/stag.tres"

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("habitat recipe")
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		finish()
		return
	_world = node as WorldRoot
	root.add_child(_world)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	_check_rock_is_the_source_of_both_its_tags()
	_check_stag_dedupes_to_two_chips_at_single_count()
	_check_fox_reads_forest_and_rock()
	_check_unsourced_need_is_unsatisfiable()

	finish()
	return true


func _check_rock_is_the_source_of_both_its_tags() -> void:
	var sources: Dictionary = HabitatRecipe.tag_sources(_world)
	for tag: String in ["cover", "rocks"]:
		var entries: Array = sources.get(tag, []) as Array
		if not check(not entries.is_empty(), "tag '%s' has a source" % tag):
			continue
		check_eq((entries[0] as Dictionary)["id"], "rock", "'%s' resolves to the Rock button" % tag)


func _check_stag_dedupes_to_two_chips_at_single_count() -> void:
	var stag: AnimalDefinition = load(STAG_PATH) as AnimalDefinition
	if not check(stag != null, "stag.tres loads"):
		return
	var recipe: Dictionary = HabitatRecipe.recipe_for(stag, _world)
	check(recipe["satisfiable"] as bool, "stag is satisfiable")
	var entries: Array = recipe["entries"] as Array
	check_eq(entries.size(), 2, "stag's 3 needs collapse to 2 chips (Rock serves two tags)")
	for entry: Dictionary in entries:
		check_eq(entry["count"], stag.tiles_per_individual,
			"chip '%s' counts tiles_per_individual, not a per-tag multiple" % entry["id"])
		if (entry["id"] as String) == "rock":
			check_eq((entry["tags"] as Array).size(), 2, "the Rock chip carries both its tags")


func _check_fox_reads_forest_and_rock() -> void:
	var fox: AnimalDefinition = load(FOX_PATH) as AnimalDefinition
	if not check(fox != null, "fox.tres loads"):
		return
	var recipe: Dictionary = HabitatRecipe.recipe_for(fox, _world)
	var ids: Array[String] = []
	for entry: Dictionary in (recipe["entries"] as Array):
		ids.append(entry["id"] as String)
	ids.sort()
	check_eq(ids, ["forest", "rock"] as Array[String], "fox resolves to Forest + Rock")


func _check_unsourced_need_is_unsatisfiable() -> void:
	var ghost := AnimalDefinition.new()
	ghost.id = "ghost"
	ghost.display_name = "Ghost"
	ghost.habitat_needs = ["quiet"] as Array[String]
	var recipe: Dictionary = HabitatRecipe.recipe_for(ghost, _world)
	check(not (recipe["satisfiable"] as bool), "a need with no source is unsatisfiable")
	check_eq((recipe["entries"] as Array).size(), 0, "an unsatisfiable species shows no partial recipe")
