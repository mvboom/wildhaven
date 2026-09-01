extends QATestCase
## EVERY SPECIES THE FIELD GUIDE SHOWS MUST BE REACHABLE.
##
## D-40 kept the Field Guide to existence-only so "a player is never encouraged to build a
## habitat for a species that can never appear." Its successor decision shows the habitat
## outright, which means that promise now needs an enforcer instead of a silence. This is it.
##
## A red bar here means the guide would print a recipe a player could follow forever without
## result — the single worst failure this screen can have.
##
## Run:
##   bash scripts/run-tests.sh reachability

const WORLD_PATH: String = "res://scenes/Main.tscn"

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("field guide reachability")
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
	# Final review finding #4: `roster != null` alone is a vacuous gate — an empty-but-non-null
	# roster (a load that "succeeds" onto zero entries) passes that check and then the loop
	# below iterates zero times, silently dropping all ~80 assertions this suite exists to make
	# while still reporting one clean green check. This suite carries the ENTIRE safety property
	# of the successor decision to D-40 (every shown species must be reachable) — it must not be
	# able to go green having verified nothing, so a non-empty roster is asserted explicitly and
	# the run bails on failure exactly like the null check above.
	if not check(not _world.roster.species().is_empty(), "the roster is non-empty"):
		finish()
		return true

	var sources: Dictionary = HabitatRecipe.tag_sources(_world)
	for species: AnimalDefinition in _world.roster.species():
		for tag: String in species.habitat_needs:
			check(tag in AnimalDefinition.HABITAT_TAGS,
				"%s's need '%s' is in the declared vocabulary" % [species.id, tag])
			check(not (sources.get(tag, []) as Array).is_empty(),
				"%s's need '%s' has a buildable source" % [species.id, tag],
				"nothing in terrain_options()/placeable_options() emits it")
		check((HabitatRecipe.recipe_for(species, _world)["satisfiable"] as bool),
			"%s resolves to a complete recipe" % species.id)

	finish()
	return true
