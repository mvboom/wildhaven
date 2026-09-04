extends QATestCase
## Schema validation of the 8 NEW farm-building `PlaceableDefinition` `.tres` files
## (content-variety pass Task 3, 2026-08-26) — Barn, SmallBarn, OpenBarn, ChickenCoop,
## Silo, Windmill, WaterTower, Well. Each is its own independent buildable (its own
## cost/footprint, its own model), not a look variant of House or of each other.
##
## Follows `test_placeable_schema.gd`'s shape (house.tres), adapted for 8 entries. Per
## Task 1, `PlaceableDefinition.model_scenes` has no `pick_variant()` — every placed
## instance shows the SAME look, so each entry here carries exactly one model_scenes
## entry (index 0), unlike house.tres's 10.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_farm_buildings_schema.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

## Terrain ids that actually have a TerrainDefinition `.tres` on disk. Same roster
## test_placeable_schema.gd validates house.tres against.
const KNOWN_TERRAIN_IDS: PackedStringArray = [
	"cultivated_field", "forest", "grass", "rock", "water", "wild_grass",
]

## This task's proposal table (task-3-brief.md) — NOT design-locked. Every value here is a
## FIRST-PASS PROPOSAL, sourced only from House's own stated baselines (buildings.md:
## ~15 Wood at 1x1, ~30 Wood at 2x2); flagged for human sign-off in the build report,
## Barn's 2x2 footprint especially (the one outlier in an otherwise uniform table).
## emitted_tags RE-POINTED 2026-09-04 (habitat-tiers Task 7): every entry was `[]` --
## placeable decoration with no simulation meaning. `built` is now emitted by EVERY
## placeable (the universal `HabitatLimit` exclusion handle); Barn/OpenBarn additionally
## carry their deliberate subsumption tags (`large_barn`, `stable`). See
## docs/superpowers/specs/2026-09-04-habitat-tiers-design.md § 8.
const EXPECTED: Array[Dictionary] = [
	{
		"tres": "res://data/buildings/barn.tres",
		"model": "res://assets/buildings/barn/Barn.tscn",
		"id": "barn",
		"display_name": "Barn",
		"cost": 30,
		"footprint": Vector2i(2, 2),
		"emitted_tags": ["built", "barn", "large_barn"],
	},
	{
		"tres": "res://data/buildings/small_barn.tres",
		"model": "res://assets/buildings/small_barn/SmallBarn.tscn",
		"id": "small_barn",
		"display_name": "Small Barn",
		"cost": 15,
		"footprint": Vector2i(1, 1),
		"emitted_tags": ["built", "barn"],
	},
	{
		"tres": "res://data/buildings/open_barn.tres",
		"model": "res://assets/buildings/open_barn/OpenBarn.tscn",
		"id": "open_barn",
		"display_name": "Open Barn",
		"cost": 15,
		"footprint": Vector2i(1, 1),
		"emitted_tags": ["built", "barn", "stable"],
	},
	{
		"tres": "res://data/buildings/chicken_coop.tres",
		"model": "res://assets/buildings/chicken_coop/ChickenCoop.tscn",
		"id": "chicken_coop",
		"display_name": "Chicken Coop",
		"cost": 15,
		"footprint": Vector2i(1, 1),
		"emitted_tags": ["built", "coop"],
	},
	{
		"tres": "res://data/buildings/silo.tres",
		"model": "res://assets/buildings/silo/Silo.tscn",
		"id": "silo",
		"display_name": "Silo",
		"cost": 15,
		"footprint": Vector2i(1, 1),
		"emitted_tags": ["built", "silo"],
	},
	{
		"tres": "res://data/buildings/windmill.tres",
		"model": "res://assets/buildings/windmill/Windmill.tscn",
		"id": "windmill",
		"display_name": "Windmill",
		"cost": 15,
		"footprint": Vector2i(1, 1),
		"emitted_tags": ["built", "mill"],
	},
	{
		"tres": "res://data/buildings/water_tower.tres",
		"model": "res://assets/buildings/water_tower/WaterTower.tscn",
		"id": "water_tower",
		"display_name": "Water Tower",
		"cost": 15,
		"footprint": Vector2i(1, 1),
		"emitted_tags": ["built", "water"],
	},
	{
		"tres": "res://data/buildings/well.tres",
		"model": "res://assets/buildings/well/Well.tscn",
		"id": "well",
		"display_name": "Well",
		"cost": 15,
		"footprint": Vector2i(1, 1),
		"emitted_tags": ["built", "water"],
	},
]

const EXPECTED_ALLOWED_TERRAIN: PackedStringArray = ["grass"]

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("farm buildings schema (8 new PlaceableDefinition entries)")

	# --- per-building schema checks (no live tree needed) ----------------------
	for entry: Dictionary in EXPECTED:
		_check_one(entry)

	# --- WorldRoot.placeable_options() surfaces all 10 buildables ---------------
	# RE-POINTED 2026-09-04 (habitat-tiers Task 7): was 9 (House + 8 farm buildings).
	# Farmhouse joins as a 10th, real, independent buildable (habitat-tiers ruling,
	# large_house tag). Needs a live, ticking SceneTree the same way test_mode_tap_model.gd/
	# test_hud_hotbar.gd instantiate Main.tscn -- WorldRoot's building registry is built
	# in _ready(), which needs the node actually entering the tree.
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

	var options: Array[PlaceableDefinition] = _world.placeable_options()
	check_eq(options.size(), 10, "WorldRoot.placeable_options() reports 10 buildables (House + 8 farm buildings + Farmhouse)")

	var ids: Array[String] = []
	for def: PlaceableDefinition in options:
		ids.append(def.id)
	check(ids.has("house"), "the catalog still includes house")
	for entry: Dictionary in EXPECTED:
		check(ids.has(entry["id"]),
			"the catalog includes %s (WorldRoot actually loads the new .tres, not just the file existing on disk)" % entry["id"])

	finish()
	return true


func _check_one(entry: Dictionary) -> void:
	var tres_path: String = entry["tres"]
	var res: Resource = load(tres_path)
	if not check(res != null, "%s loads" % tres_path):
		return
	if not check(res is PlaceableDefinition, "%s binds to PlaceableDefinition (not a bare Resource)" % entry["id"],
			"got class %s / script %s" % [res.get_class(), res.get_script()]):
		return
	var def: PlaceableDefinition = res as PlaceableDefinition
	check(def.get_script() != null, "%s has a script attached" % entry["id"])

	# --- identity ---------------------------------------------------------
	check_eq(def.id, entry["id"], "%s id" % entry["id"])
	check_eq(def.display_name, entry["display_name"], "%s display_name" % entry["id"])

	# --- proposed values (this task's table; FLAGGED for human sign-off) --
	check_eq(def.cost, entry["cost"], "%s cost (proposal, not decided)" % entry["id"])
	check_eq(def.footprint, entry["footprint"], "%s footprint (proposal, not decided)" % entry["id"])
	check_eq(PackedStringArray(def.allowed_terrain), EXPECTED_ALLOWED_TERRAIN,
		"%s allowed_terrain == [\"grass\"]" % entry["id"])
	check_eq(PackedStringArray(def.emitted_tags), PackedStringArray(entry["emitted_tags"]),
		"%s emitted_tags matches the habitat-tiers tag table (built + %s)" % [
			entry["id"], PackedStringArray(entry["emitted_tags"]).slice(1)])
	check_eq(def.hotbar_category, "farm_building",
		"%s hotbar_category groups this buildable under the Farm Building hotbar slot" % entry["id"])

	# --- types --------------------------------------------------------------
	check_eq(typeof(def.cost), TYPE_INT, "%s cost is int" % entry["id"])
	check_eq(typeof(def.footprint), TYPE_VECTOR2I, "%s footprint is Vector2i" % entry["id"])
	check_eq(def.allowed_terrain.get_typed_builtin(), TYPE_STRING,
		"%s allowed_terrain is a TYPED Array[String]" % entry["id"])
	check_eq(def.emitted_tags.get_typed_builtin(), TYPE_STRING,
		"%s emitted_tags is a TYPED Array[String]" % entry["id"])

	# --- allowed_terrain resolves against real terrain -----------------------
	var unresolved: Array[String] = def.unresolved_terrain(KNOWN_TERRAIN_IDS)
	check(unresolved.is_empty(),
		"%s every allowed_terrain entry resolves to a real TerrainDefinition" % entry["id"],
		"unresolved: %s" % str(unresolved))

	# --- model_scenes: exactly 1 entry (no pick_variant(), Task 1) -----------
	check_eq(def.model_scenes.size(), 1, "%s has exactly 1 model_scenes entry" % entry["id"])
	if def.model_scenes.size() > 0:
		var scene: PackedScene = def.model_scenes[0]
		check(scene is PackedScene, "%s model_scenes[0] is a PackedScene" % entry["id"])
		check(scene != null and scene.resource_path == entry["model"],
			"%s model_scenes[0] is the expected wrapper scene" % entry["id"],
			"got: %s" % (scene.resource_path if scene != null else "null"))
		check(scene != null and scene.can_instantiate(),
			"%s model_scenes[0] can instantiate" % entry["id"])
		if scene != null and scene.can_instantiate():
			_check_footprint(entry["id"], scene, entry["footprint"])

	# --- validate(): must be clean even with the placeholder fact_text -------
	var problems: Array[String] = def.validate(KNOWN_TERRAIN_IDS)
	if not problems.is_empty():
		print("  %s: validate() returned %d problem(s):" % [entry["id"], problems.size()])
		for p: String in problems:
			print("      - %s" % p)
	check(problems.is_empty(),
		"%s validate(KNOWN_TERRAIN_IDS) is CLEAN (zero problems)" % entry["id"],
		"unexpected: %s" % str(problems))
	var bare_problems: Array[String] = def.validate()
	check(bare_problems.is_empty(),
		"%s validate() with no terrain roster is CLEAN (zero problems)" % entry["id"],
		"unexpected: %s" % str(bare_problems))

	# --- fact_text: PLACEHOLDER is the CORRECT interim state here ------------
	# Content Pipeline step 5 is content-writer's job, not tech-art's -- a PLACEHOLDER-
	# prefixed string is a legitimate in-flight state PlaceableDefinition.pending_signoff()
	# already expects and handles, per placeable_definition.gd's own doc comment.
	var expected_fact_text: String = "PLACEHOLDER — flavor copy for the %s pending Content Pipeline step 5." % entry["display_name"]
	check_eq(def.fact_text, expected_fact_text, "%s fact_text is the expected PLACEHOLDER string" % entry["id"])
	check(def.fact_text.begins_with(AnimalDefinition.PLACEHOLDER_MARKER),
		"%s fact_text IS PLACEHOLDER-prefixed (content-writer's job, not done here)" % entry["id"])

	var no_fact_problem: bool = true
	for p: String in problems:
		if p.contains("fact_text"):
			no_fact_problem = false
	check(no_fact_problem,
		"%s validate() reports NO fact_text problem — a placeholder is a legal in-flight state for PlaceableDefinition" % entry["id"])

	# --- pending_signoff(): NOT zero here, unlike house.tres's already-closed fact_text --
	var pending: Array[String] = def.pending_signoff()
	check(pending.size() == 1 and pending[0].contains("fact_text"),
		"%s pending_signoff() reports exactly the fact_text placeholder (awaiting Content Pipeline step 5)" % entry["id"],
		"got: %s" % str(pending))


## Footprint fit: manual local-transform composition (NOT global_transform, which
## silently returns identity on a freshly-instantiated, not-yet-tree-attached node --
## see cultivated_field.tres's header / Task 2's test_house_variants_import.gd for the
## same method) against the REAL in-scene composed footprint (mesh AABB x the wrapper's
## scale transform), matching each building's proposed footprint (2x2 for Barn, 1x1 for
## the other 7) within its tile-unit budget.
func _check_footprint(id: String, scene: PackedScene, footprint: Vector2i) -> void:
	var inst: Node = scene.instantiate()
	var state: Dictionary = {"aabb": AABB(), "first": true}
	if inst is Node3D:
		_walk(inst, (inst as Node3D).transform, state)
	else:
		_walk(inst, Transform3D.IDENTITY, state)
	var aabb: AABB = state["aabb"]
	print("  %s: world-composed AABB size = %s (footprint budget %s)" % [id, aabb.size, footprint])
	check(aabb.size.x <= float(footprint.x) + 0.01 and aabb.size.z <= float(footprint.y) + 0.01,
		"%s footprint fits within its proposed %s-tile budget" % [id, footprint],
		"size=%s" % aabb.size)
	inst.free()


func _walk(node: Node, parent_xform: Transform3D, state: Dictionary) -> void:
	var local_xform: Transform3D = parent_xform
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			var mesh_aabb: AABB = mi.mesh.get_aabb()
			var world_aabb: AABB = local_xform * mesh_aabb
			if state["first"]:
				state["aabb"] = world_aabb
				state["first"] = false
			else:
				state["aabb"] = (state["aabb"] as AABB).merge(world_aabb)
	for child in node.get_children():
		var child_xform: Transform3D = local_xform
		if child is Node3D:
			child_xform = local_xform * (child as Node3D).transform
		_walk(child, child_xform, state)
