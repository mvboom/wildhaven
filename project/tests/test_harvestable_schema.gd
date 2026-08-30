extends QATestCase
## Schema validation of res://data/terrain/forest_harvest.tres against the
## HarvestableTileDefinition contract (spec.md -> Data Schemas) and terrain.md's decided
## values for Forest, v1's sole harvestable.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_harvestable_schema.gd

const HARVEST_PATH: String = "res://data/terrain/forest_harvest.tres"
const FOREST_PATH: String = "res://data/terrain/forest.tres"


func _init() -> void:
	begin("forest_harvest.tres schema")

	# --- loads at all ---------------------------------------------------------
	var res: Resource = load(HARVEST_PATH)
	if not check(res != null, "%s loads" % HARVEST_PATH):
		finish()
		return

	# --- binds to the typed class, not a bare Resource ------------------------
	# Asserted before any field is read — a `.tres` whose script_class failed to resolve
	# loads fine and arrives as untyped metadata, silently passing a field check.
	if not check(res is HarvestableTileDefinition,
			"binds to HarvestableTileDefinition (not a bare Resource)",
			"got class %s / script %s" % [res.get_class(), res.get_script()]):
		finish()
		return
	var harvest: HarvestableTileDefinition = res as HarvestableTileDefinition
	check(harvest.get_script() != null, "has a script attached")

	# --- identity -------------------------------------------------------------
	check_eq(harvest.id, "forest_harvest", "id")
	check_eq(harvest.display_name, "Forest", "display_name")

	# --- decided values (terrain.md -> Harvestable terrain) -------------------
	check_eq(harvest.resource_type, "wood", "resource_type == \"wood\" (v1's only resource)")
	check_eq(harvest.resource_type, HarvestableTileDefinition.RESOURCE_WOOD,
		"resource_type is the declared constant, not a hand-typed literal that merely matches")
	check(HarvestableTileDefinition.RESOURCE_TYPES.has(harvest.resource_type),
		"resource_type is inside the declared domain %s" % str(HarvestableTileDefinition.RESOURCE_TYPES))

	check_eq(harvest.land_use, "wild", "land_use == \"wild\" (Forest is wild land)")
	check_eq(harvest.land_use, HarvestableTileDefinition.LAND_USE_WILD,
		"land_use is the declared constant")
	check(HarvestableTileDefinition.LAND_USES.has(harvest.land_use),
		"land_use is inside the declared domain %s" % str(HarvestableTileDefinition.LAND_USES))

	# THE PILLAR OBLIGATION, not a tuning value. terrain.md calls Forest "zero-downside by
	# design", and gdd.md's free-Forest recovery guarantee (Tier 1 row 5) — the reason a
	# player can never be stranded at zero Wood — only holds while tending Forest costs
	# the player nothing. A `true` here breaks the no-dead-ends floor, which is why it is
	# asserted as an exact value and not merely as "a bool".
	check_eq(harvest.removes_habitat_when_harvested, false,
		"removes_habitat_when_harvested == false — the zero-downside design rule")

	# --- types ----------------------------------------------------------------
	check_eq(typeof(harvest.resource_type), TYPE_STRING,
		"resource_type is String (self-documenting on disk, not an enum ordinal)")
	check_eq(typeof(harvest.land_use), TYPE_STRING, "land_use is String")
	check_eq(typeof(harvest.removes_habitat_when_harvested), TYPE_BOOL,
		"removes_habitat_when_harvested is bool")

	# --- NO model_scene, deliberately (-> D-26) ---------------------------------
	# A harvestable is a YIELD RULE, not a thing on the ground; the model lives on the
	# host TerrainDefinition. Pinned in both directions so the field cannot creep back:
	# the property must not exist, and the host terrain must supply the model instead.
	check(not (&"model_scene" in harvest),
		"HarvestableTileDefinition exposes no model_scene property")
	var host: TerrainDefinition = load("res://data/terrain/forest.tres") as TerrainDefinition
	check(host != null, "host terrain forest.tres loads")
	check(host != null and not host.model_scenes.is_empty(),
		"the host terrain owns the model instead")
	check(host != null and host.harvestable == harvest,
		"forest.tres references exactly this harvestable")

	# --- validate(): must be clean ---------------------------------------------
	# FIXED-COUNT: problems are printed, never iterated with check().
	var problems: Array[String] = harvest.validate()
	if not problems.is_empty():
		print("  validate() returned %d problem(s):" % problems.size())
		for p: String in problems:
			print("      - %s" % p)
	check(problems.is_empty(), "validate() is CLEAN (zero problems)",
		"unexpected: %s" % str(problems))

	# --- forest.tres actually points HERE ---------------------------------------
	# Without this, the two suites could both pass while forest.tres referenced some other
	# harvestable: test_terrain_schema.gd only asserts forest's `harvestable` is non-null.
	var forest: TerrainDefinition = load(FOREST_PATH) as TerrainDefinition
	if check(forest != null, "%s loads as TerrainDefinition" % FOREST_PATH):
		check(forest.harvestable == harvest,
			"forest.tres's `harvestable` IS this resource (same instance, not a copy)",
			"got %s" % str(forest.harvestable))

	# --- v1 has exactly one harvestable -----------------------------------------
	# terrain.md: "Forest is v1's sole harvestable." Asserted over the loaded terrain set
	# so a second harvestable arriving by data edit is a failure, not a surprise at runtime.
	var with_harvest: PackedStringArray = PackedStringArray()
	for def: TerrainDefinition in TerrainDefinition.load_all():
		if def.harvestable != null:
			with_harvest.append(def.id)
	check_eq(with_harvest, PackedStringArray(["forest"]),
		"forest is the ONLY terrain carrying a harvestable in v1")

	# The passive Wood RATE (~1 Wood / forest tile / 60 s, #8) is deliberately NOT a field
	# on this schema — it belongs to the row-5 economy evaluator. Recorded so its absence
	# reads as a decision rather than as a missing field.
	note_expected_pending("passive Wood rate is not a field here (Open Question #8)",
		"~1 Wood / forest tile / 60 s belongs to the row-5 economy evaluator, which does not exist yet.")

	finish()
