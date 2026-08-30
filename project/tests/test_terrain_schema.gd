extends QATestCase
## Schema validation of all six v1 terrain `.tres` entries against the
## TerrainDefinition contract (spec.md -> Data Schemas) and the human-decided values in
## terrain.md (-> Already-Defined Terrain: the v1 tag-source mapping and the cost table).
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_terrain_schema.gd
##
## SCOPE NOTE: this suite pins per-terrain VALUES. The inert-land invariant's derivation
## machinery (`derive_bare_tags()`, the wild-grass existence assertion, the load_all()
## count) is deliberately a separate suite — test_bare_tags_derivation.gd — because it is
## the invariant, not a data entry, and must fail on its own name.

const DATA_DIR: String = "res://data/terrain"

## The six v1 terrains, in filename order. `sand` is depth, not floor (terrain.md), and
## has no `.tres`; it is deliberately absent rather than expected-and-missing.
##
## This list is a FIXED LITERAL, which is what keeps this suite's assertion count fixed:
## the count is a function of this constant and never of what happens to be on disk.
const TERRAIN_IDS: PackedStringArray = [
	"cultivated_field",
	"forest",
	"grass",
	"rock",
	"water",
	"wild_grass",
]

## terrain.md -> Already-Defined Terrain, "v1 tag-source mapping" (#5 closed -> D-25).
## Transcribed exactly, INCLUDING ORDER, so a reordering edit is visible as a diff rather
## than silently tolerated. Rock's two-tag row is the load-bearing one: rock, not forest,
## is the `cover` source, and both floor species need `cover`.
##
## Wild grass's EMPTY entry is a decided value, not an unfinished row (spec.md -> Shared
## Patterns, the inert-land invariant).
const EXPECTED_TAGS: Dictionary = {
	"cultivated_field": ["cultivated"],
	"forest": ["forest"],
	"grass": ["open_grass"],
	"rock": ["cover", "rocks"],
	"water": ["water"],
	"wild_grass": [],
}

## terrain.md -> Cost: "nature is free; construction costs materials". Every natural
## terrain is 0; the cultivated field's ~2 Wood is the only non-zero cost in v1 and is a
## PLACEHOLDER at terrain.md's stated baseline (Open Question #8) — pinned here so a
## silent drift in the placeholder is caught, exactly as fox's scout_radius is pinned.
const EXPECTED_COST: Dictionary = {
	"cultivated_field": 2,
	"forest": 0,
	"grass": 0,
	"rock": 0,
	"water": 0,
	"wild_grass": 0,
}

## Animal-navigation pass (2026-08-24): Forest is the only terrain an animal must path
## AROUND rather than through. Human-confirmed: Rock stays crossable (deferred), Water
## stays crossable (unchanged, already-deliberate roam behavior).
const EXPECTED_BLOCKS_MOVEMENT: Dictionary = {
	"cultivated_field": false,
	"forest": true,
	"grass": false,
	"rock": false,
	"water": false,
	"wild_grass": false,
}

## Forest is v1's SOLE harvestable (terrain.md). Every other terrain must carry a null
## `harvestable` — asserted positively for all six rather than only for forest, because
## "nothing else accidentally became harvestable" is the half that rots quietly.
const EXPECTED_HARVESTABLE: Dictionary = {
	"cultivated_field": false,
	"forest": true,
	"grass": false,
	"rock": false,
	"water": false,
	"wild_grass": false,
}

## Display names as authored. Asserted so a terrain cannot ship with an empty or
## placeholder player-facing name (validate() only catches the empty case).
const EXPECTED_DISPLAY_NAMES: Dictionary = {
	"cultivated_field": "Farm",
	"forest": "Forest",
	"grass": "Grass",
	"rock": "Rock",
	"water": "Water",
	"wild_grass": "Wild grass",
}


## Tags in `def.emitted_tags` that are not in the shared v1 vocabulary.
##
## Returns the offenders instead of asserting per-tag: one check() per emitted tag would
## make the suite's assertion count depend on how many tags a terrain happens to emit,
## which is the exact data-dependence that produced an unexplained count discrepancy in
## test_fox_schema.gd. One fixed assertion per terrain, with the offenders in the detail.
func _unknown_tags(def: TerrainDefinition) -> Array[String]:
	var out: Array[String] = []
	for tag: String in def.emitted_tags:
		if not AnimalDefinition.HABITAT_TAGS.has(tag):
			out.append(tag)
	return out


func _init() -> void:
	begin("terrain .tres schema")

	for terrain_id: String in TERRAIN_IDS:
		var path: String = "%s/%s.tres" % [DATA_DIR, terrain_id]

		# --- loads at all -----------------------------------------------------
		var res: Resource = load(path)
		if not check(res != null, "%s loads" % path):
			continue

		# --- binds to the typed class, not a bare Resource --------------------
		# Load-bearing and asserted before any field is read: a `.tres` whose
		# script_class failed to resolve still LOADS, arriving as a plain Resource with
		# every field as untyped metadata. Field-by-field checks below would then pass
		# against metadata that the game will never read as a TerrainDefinition.
		if not check(res is TerrainDefinition,
				"%s binds to TerrainDefinition (not a bare Resource)" % terrain_id,
				"got class %s / script %s" % [res.get_class(), res.get_script()]):
			continue
		var def: TerrainDefinition = res as TerrainDefinition

		# --- identity ---------------------------------------------------------
		check_eq(def.id, terrain_id, "%s: id" % terrain_id)
		check_eq(def.display_name, EXPECTED_DISPLAY_NAMES[terrain_id],
			"%s: display_name" % terrain_id)

		# --- tag emission: terrain.md's tag-source mapping, exactly ------------
		check_eq(def.emitted_tags.get_typed_builtin(), TYPE_STRING,
			"%s: emitted_tags is a TYPED Array[String]" % terrain_id)
		check_eq(PackedStringArray(def.emitted_tags),
			PackedStringArray(EXPECTED_TAGS[terrain_id]),
			"%s: emitted_tags matches terrain.md's tag-source mapping" % terrain_id)
		var unknown: Array[String] = _unknown_tags(def)
		check(unknown.is_empty(),
			"%s: every emitted tag is in the shared v1 vocabulary" % terrain_id,
			"not in AnimalDefinition.HABITAT_TAGS: %s" % str(unknown))

		# --- cost: terrain.md's one pricing rule -------------------------------
		check_eq(def.cost, EXPECTED_COST[terrain_id], "%s: cost" % terrain_id)

		# --- blocks_movement: animal-navigation pass ---------------------------
		check_eq(def.blocks_movement, EXPECTED_BLOCKS_MOVEMENT[terrain_id],
			"%s: blocks_movement" % terrain_id)

		# --- harvestable: forest and only forest -------------------------------
		var wants_harvestable: bool = EXPECTED_HARVESTABLE[terrain_id]
		if wants_harvestable:
			check(def.harvestable != null,
				"%s: harvestable is NON-NULL (v1's sole harvestable)" % terrain_id)
			check(def.harvestable is HarvestableTileDefinition,
				"%s: harvestable binds to HarvestableTileDefinition" % terrain_id,
				"got %s" % str(def.harvestable))
		else:
			check(def.harvestable == null,
				"%s: harvestable is NULL (only Forest produces in v1)" % terrain_id,
				"got %s" % str(def.harvestable))
			# Kept as a matched pair with the branch above so the assertion count is
			# identical on both paths and stays independent of which terrain harvests.
			check(true, "%s: (no harvestable to type-check)" % terrain_id)

		# --- model_scenes --------------------------------------------------------
		# Grey-box placeholders today (assets/placeholder/), the real tile visuals later.
		# Which scene(s) it points at is a look-pass question the art pass owns; that it
		# points at SOMETHING instantiable is a schema question and belongs here.
		check(not def.model_scenes.is_empty(), "%s: model_scenes is non-empty" % terrain_id)
		var all_packed_scenes: bool = true
		for scene in def.model_scenes:
			if not (scene is PackedScene):
				all_packed_scenes = false
		check(all_packed_scenes, "%s: every model_scenes entry is a PackedScene" % terrain_id)

		# --- validate(): must be clean ------------------------------------------
		# FIXED-COUNT: the problems are printed, never iterated with check(). Iterating
		# validate() output makes the suite's total assertion count move with the data,
		# with no file edit — a real past defect in this repo.
		var problems: Array[String] = def.validate()
		if not problems.is_empty():
			print("  %s validate() returned %d problem(s):" % [terrain_id, problems.size()])
			for p: String in problems:
				print("      - %s" % p)
		check(problems.is_empty(),
			"%s: validate() is CLEAN (zero problems)" % terrain_id,
			"unexpected: %s" % str(problems))

	# --- the set on disk is exactly the six expected ---------------------------
	# Guards the loop above against being vacuous in the other direction: it proves each
	# EXPECTED id exists, not that no SEVENTH terrain quietly appeared.
	var loaded: Array[TerrainDefinition] = TerrainDefinition.load_all()
	var loaded_ids: PackedStringArray = PackedStringArray()
	for d: TerrainDefinition in loaded:
		loaded_ids.append(d.id)
	loaded_ids.sort()
	var expected_ids: PackedStringArray = TERRAIN_IDS.duplicate()
	expected_ids.sort()
	check_eq(loaded_ids, expected_ids,
		"load_all() finds exactly the six expected terrain ids and no others")

	finish()
