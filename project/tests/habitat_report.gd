extends QATestCase
## THE TAG-ECONOMY SCOREBOARD — a REPORT, not a gate.
##
## The human's roster/tag/water/buildings retune is driven against this output. It is
## deliberately not a test suite: making a recipe collision FAIL would hold `run-tests.sh`
## red for the entire duration of that retune, which teaches everyone to ignore a red bar.
## The one thing that IS a hard gate lives in test_field_guide_reachability.gd.
##
## Run:
##   bash scripts/habitat-report.sh

const WORLD_PATH: String = "res://scenes/Main.tscn"

## Inert by design (-> D-22/D-25), never a finding.
const DELIBERATELY_INERT: Array[String] = [TerrainDefinition.WILD_GRASS_ID]

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("habitat report")
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
	if not check(_world.roster != null, "the roster loaded"):
		finish()
		return true

	var sources: Dictionary = HabitatRecipe.tag_sources(_world)
	var wanted: Dictionary = {}
	for species: AnimalDefinition in _world.roster.species():
		for tag: String in species.habitat_needs:
			wanted[tag] = true

	_print_tag_sources(sources)
	_print_unwanted_tags(sources, wanted)
	_print_inert_buildables()
	_print_collisions()

	finish()
	return true


func _print_tag_sources(sources: Dictionary) -> void:
	print("\n=== 1. TAG SOURCES ===")
	for tag: String in AnimalDefinition.HABITAT_TAGS:
		var entries: Array = sources.get(tag, []) as Array
		if entries.is_empty():
			print("  %-12s NO SOURCE" % tag)
			continue
		var ids: Array[String] = []
		for entry: Dictionary in entries:
			ids.append(entry["id"] as String)
		print("  %-12s <- %s" % [tag, ", ".join(ids)])


func _print_unwanted_tags(sources: Dictionary, wanted: Dictionary) -> void:
	print("\n=== 2. SOURCED TAGS NOBODY WANTS ===")
	var found: bool = false
	for tag: String in sources:
		if not wanted.has(tag):
			print("  %s (buildable, but no species needs it)" % tag)
			found = true
	if not found:
		print("  none")


func _print_inert_buildables() -> void:
	print("\n=== 3. INERT BUILDABLES (emit nothing) ===")
	var found: bool = false
	for terrain: TerrainDefinition in _world.terrain_options():
		if terrain.emitted_tags.is_empty() and not (terrain.id in DELIBERATELY_INERT):
			print("  terrain    %s" % terrain.id)
			found = true
	for placeable: PlaceableDefinition in _world.placeable_options():
		if placeable.emitted_tags.is_empty():
			print("  placeable  %s" % placeable.id)
			found = true
	if not found:
		print("  none")


func _print_collisions() -> void:
	print("\n=== 4. RECIPE COLLISIONS ===")
	var by_signature: Dictionary = {}
	for species: AnimalDefinition in _world.roster.species():
		var recipe: Dictionary = HabitatRecipe.recipe_for(species, _world)
		if not (recipe["satisfiable"] as bool):
			continue
		var parts: Array[String] = []
		for entry: Dictionary in (recipe["entries"] as Array):
			parts.append("%sx%d" % [entry["id"], entry["count"]])
		parts.sort()
		var signature: String = " + ".join(parts)
		if not by_signature.has(signature):
			by_signature[signature] = []
		(by_signature[signature] as Array).append(species.display_name)
	var found: bool = false
	for signature: String in by_signature:
		var names: Array = by_signature[signature] as Array
		if names.size() > 1:
			print("  %-28s %s" % [signature, ", ".join(names)])
			found = true
	if not found:
		print("  none — every species has its own recipe")
