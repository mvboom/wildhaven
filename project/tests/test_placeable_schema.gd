extends QATestCase
## Schema validation of res://data/buildings/house.tres against the PlaceableDefinition
## contract (spec.md -> Data Schemas) and the human-decided value set for the House
## (buildings.md -> Already-Defined Buildings).
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_placeable_schema.gd

const HOUSE_PATH: String = "res://data/buildings/house.tres"

## The REAL imported asset, not the grey-box. A grey-box House does exist at
## res://assets/placeholder/house/House.tscn as a deliberate fallback (the imported
## model's facing under the fixed ~45 degree camera is still unconfirmed by a human), so
## the path is pinned: a silent swap in either direction is a look-pass decision, not a
## data-entry one, and must be visible in a diff.
const MODEL_PATH: String = "res://assets/buildings/house/House.tscn"

## buildings.md -> Already-Defined Buildings, floor (Tier 1) row: 1x1, grass only,
## ~15 Wood. `cost` and `footprint` are PLACEHOLDERS at those stated baselines (Open
## Questions #8/#26 and #18) — pinned so a silent drift is caught, not because the values
## are settled.
const EXPECTED_COST: int = 15
const EXPECTED_FOOTPRINT: Vector2i = Vector2i(1, 1)
const EXPECTED_ALLOWED_TERRAIN: PackedStringArray = ["grass"]
## RE-POINTED 2026-09-04 (habitat-tiers Task 7): was ["house"]. `built` now added
## alongside the already-decided `house` — `built` is emitted by EVERY placeable so one
## `HabitatLimit` on `built` excludes all of them, including buildings added later. See
## docs/superpowers/specs/2026-09-04-habitat-tiers-design.md § 8.
const EXPECTED_EMITTED_TAGS: PackedStringArray = ["built", "house"]

## Content Pipeline step 5, CLOSED 2026-08-06 (house.tres's own header). Pinned as an exact
## string, the same pattern `test_human_schema.gd` uses for human.tres's fact card: this is
## the wording that cleared sourcing, so any drift — even a typo fix — should be visible here
## rather than passing a fuzzy "non-empty" check.
const EXPECTED_FACT_TEXT: String = (
	"This simple house is ready to be someone's new home. Plant a field close by, and a "
	+ "family will settle in before long."
)

## Terrain ids that actually have a TerrainDefinition `.tres` on disk. Passed to
## validate() so `allowed_terrain` is checked against reality rather than against a list
## this file made up. Unlike AnimalDefinition.avoids, an unresolved entry here IS a defect:
## it makes the building unplaceable on ground the designer intended.
const KNOWN_TERRAIN_IDS: PackedStringArray = [
	"cultivated_field", "forest", "grass", "rock", "water", "wild_grass",
]


func _init() -> void:
	begin("house.tres schema")

	# --- loads at all ---------------------------------------------------------
	var res: Resource = load(HOUSE_PATH)
	if not check(res != null, "%s loads" % HOUSE_PATH):
		finish()
		return

	# --- binds to the typed class, not a bare Resource ------------------------
	# Asserted before any field is read: a `.tres` whose script_class failed to resolve
	# still loads, but arrives as a plain Resource with the fields as untyped metadata,
	# which would pass a field-by-field check while the game reads nothing.
	if not check(res is PlaceableDefinition, "binds to PlaceableDefinition (not a bare Resource)",
			"got class %s / script %s" % [res.get_class(), res.get_script()]):
		finish()
		return
	var house: PlaceableDefinition = res as PlaceableDefinition
	check(house.get_script() != null, "has a script attached")

	# --- identity -------------------------------------------------------------
	check_eq(house.id, "house", "id")
	check_eq(house.display_name, "House", "display_name")
	check_eq(house.hotbar_category, "", "hotbar_category is empty — House stands alone")

	# --- human-decided values (buildings.md) ----------------------------------
	check_eq(house.cost, EXPECTED_COST, "cost is buildings.md's floor baseline (~15 Wood)")
	check_eq(house.footprint, EXPECTED_FOOTPRINT, "footprint == Vector2i(1, 1) — the Tier 1 floor form")
	check_eq(PackedStringArray(house.allowed_terrain), EXPECTED_ALLOWED_TERRAIN,
		"allowed_terrain == [\"grass\"] (\"houses build on grass only\")")
	check_eq(PackedStringArray(house.emitted_tags), EXPECTED_EMITTED_TAGS,
		"emitted_tags == [\"built\", \"house\"] — House is the `house` tag's only source, plus the universal `built` exclusion handle")

	# --- types ----------------------------------------------------------------
	check_eq(typeof(house.cost), TYPE_INT, "cost is int")
	check_eq(typeof(house.footprint), TYPE_VECTOR2I, "footprint is Vector2i")
	check_eq(house.allowed_terrain.get_typed_builtin(), TYPE_STRING,
		"allowed_terrain is a TYPED Array[String]")
	check_eq(house.emitted_tags.get_typed_builtin(), TYPE_STRING,
		"emitted_tags is a TYPED Array[String]")

	# --- the emitted tag is in the shared vocabulary --------------------------
	check(AnimalDefinition.HABITAT_TAGS.has("house"),
		"\"house\" is in the shared v1 vocabulary (AnimalDefinition.HABITAT_TAGS)")

	# --- allowed_terrain resolves against real terrain ------------------------
	var unresolved: Array[String] = house.unresolved_terrain(KNOWN_TERRAIN_IDS)
	check(unresolved.is_empty(),
		"every allowed_terrain entry resolves to a real TerrainDefinition",
		"unresolved: %s" % str(unresolved))

	# --- model_scenes ------------------------------------------------------------------------
	# PINNED AT 18. History: 1 -> 10 (Task 2, the 9 FirstAge/tower variants) -> 18, the
	# 2026-08-29 asset-audit sweep appending 8 RTS SecondAge house variants to the tail.
	# Exact-value pin on purpose: it is what makes an unreviewed content edit to house.tres
	# surface here as a failure. Re-point it deliberately when a sanctioned growth lands;
	# never relax it to a `>=`.
	#
	# 18 IS NOT "EVERY WRAPPER ON DISK", AND MUST NOT BECOME THAT ASSERTION. Two further
	# SecondAge wrappers exist under project/assets/buildings/ and are deliberately unwired:
	# house_secondage_2_level2 and house_secondage_2_level3 are multi-building compounds that
	# flatten below villager height when squeezed into a 1x1 footprint. A "wrappers on disk ==
	# model_scenes.size()" check would encode a false invariant and go red on a correct repo.
	#
	# [0] gets its own assertion beyond the count: "the shipped default stays first" is
	# load-bearing for saves and for world_root.gd's style defaults.
	check_eq(house.model_scenes.size(), 18, "18 house look variants")
	check_eq(house.model_scenes[0].resource_path, MODEL_PATH,
		"model_scenes[0] is STILL the shipped default (HousesFirstAge1Level1), unchanged by the 2026-08-29 growth")
	var variant_paths: PackedStringArray = PackedStringArray()
	for scene: PackedScene in house.model_scenes:
		check(scene is PackedScene, "every model_scenes entry is a PackedScene")
		check(scene.can_instantiate(), "every model_scenes entry can instantiate")
		variant_paths.append(scene.resource_path)

	# The ORDER is pinned for the same reason test_human_schema.gd pins human's: a count
	# plus an [0] check lets a reorder of entries 1..17 -- or a swap of one wrapper for
	# another at equal count -- land silently. Mirrors that file's existing pattern rather
	# than inventing a second shape. Re-point deliberately; never relax to a prefix match.
	var expected_paths: PackedStringArray = [
		"res://assets/buildings/house/House.tscn",
		"res://assets/buildings/house_firstage_1_level2/HouseFirstage1Level2.tscn",
		"res://assets/buildings/house_firstage_1_level3/HouseFirstage1Level3.tscn",
		"res://assets/buildings/house_firstage_2_level1/HouseFirstage2Level1.tscn",
		"res://assets/buildings/house_firstage_2_level2/HouseFirstage2Level2.tscn",
		"res://assets/buildings/house_firstage_2_level3/HouseFirstage2Level3.tscn",
		"res://assets/buildings/house_firstage_3_level1/HouseFirstage3Level1.tscn",
		"res://assets/buildings/house_firstage_3_level2/HouseFirstage3Level2.tscn",
		"res://assets/buildings/house_firstage_3_level3/HouseFirstage3Level3.tscn",
		"res://assets/buildings/house_tower_firstage/HouseTowerFirstage.tscn",
		"res://assets/buildings/house_secondage_1_level1/HouseSecondage1Level1.tscn",
		"res://assets/buildings/house_secondage_1_level2/HouseSecondage1Level2.tscn",
		"res://assets/buildings/house_secondage_1_level3/HouseSecondage1Level3.tscn",
		"res://assets/buildings/house_secondage_2_level1/HouseSecondage2Level1.tscn",
		"res://assets/buildings/house_secondage_3_level1/HouseSecondage3Level1.tscn",
		"res://assets/buildings/house_secondage_3_level2/HouseSecondage3Level2.tscn",
		"res://assets/buildings/house_secondage_3_level3/HouseSecondage3Level3.tscn",
		"res://assets/buildings/house_tower_secondage/HouseTowerSecondage.tscn",
	]
	check_eq(variant_paths, expected_paths,
		"model_scenes lists exactly these 18 paths, in this order")

	# --- validate(): must be clean, WITH the placeholder fact_text in place ----
	# FIXED-COUNT: problems are printed, never iterated with check().
	var problems: Array[String] = house.validate(KNOWN_TERRAIN_IDS)
	if not problems.is_empty():
		print("  validate() returned %d problem(s):" % problems.size())
		for p: String in problems:
			print("      - %s" % p)
	check(problems.is_empty(),
		"validate(KNOWN_TERRAIN_IDS) is CLEAN (zero problems)",
		"unexpected: %s" % str(problems))
	var bare_problems: Array[String] = house.validate()
	check(bare_problems.is_empty(),
		"validate() with no terrain roster is CLEAN (zero problems)",
		"unexpected: %s" % str(bare_problems))

	# --- fact_text: Content Pipeline step 5 CLOSED 2026-08-06 (RE-POINTED, was PLACEHOLDER) --
	# house.tres shipped real, source-verified flavor copy on 2026-08-06 (house.tres's own
	# header). The suite used to pin the PLACEHOLDER state; that state is gone, and pinning it
	# as an exact string (rather than a fuzzy "non-empty") is what makes a future silent drift
	# — even a typo fix — fail here instead of passing quietly.
	check(not house.fact_text.begins_with(AnimalDefinition.PLACEHOLDER_MARKER),
		"fact_text is no longer PLACEHOLDER-prefixed — Content Pipeline step 5 closed 2026-08-06")
	check_eq(house.fact_text, EXPECTED_FACT_TEXT,
		"fact_text is EXACTLY the shipped copy, verbatim")

	var no_fact_problem: bool = true
	for p: String in problems:
		if p.contains("fact_text"):
			no_fact_problem = false
	check(no_fact_problem, "validate() reports NO fact_text problem — the copy is clean")

	var pending: Array[String] = house.pending_signoff()
	if not pending.is_empty():
		print("  pending_signoff() returned %d item(s):" % pending.size())
		for p: String in pending:
			print("      - %s" % p)
	check(pending.is_empty(),
		"pending_signoff() is now EMPTY — the only thing it ever flagged (a placeholder "
		+ "fact_text) is gone",
		"got: %s" % str(pending))

	# NEGATIVE CONTROL for pending_signoff(): "empty" above is only meaningful if the same
	# function can still produce an item. A clone with the placeholder put back must be
	# flagged again.
	var placeholder_clone: PlaceableDefinition = house.duplicate() as PlaceableDefinition
	placeholder_clone.fact_text = "%s house copy pending (Content Pipeline step 5)" \
		% AnimalDefinition.PLACEHOLDER_MARKER
	var clone_pending: Array[String] = placeholder_clone.pending_signoff()
	check(clone_pending.size() == 1 and clone_pending[0].contains("fact_text"),
		"NEGATIVE CONTROL: put the PLACEHOLDER back on a clone and pending_signoff() flags "
		+ "fact_text again — the empty result above is a real check, not a function that "
		+ "never speaks",
		"got: %s" % str(clone_pending))
	var clone_problems: Array[String] = placeholder_clone.validate()
	var clone_no_fact_problem: bool = true
	for p: String in clone_problems:
		if p.contains("fact_text"):
			clone_no_fact_problem = false
	check(clone_no_fact_problem,
		"...and validate() STILL reports no fact_text problem for that clone — a placeholder "
		+ "is a legal in-flight state for a PlaceableDefinition, proven on a case that actually "
		+ "carries one")

	# The other half of the DELIBERATE divergence: PlaceableDefinition splits "is this entry
	# malformed?" (validate) from "may this ship?" (pending_signoff); AnimalDefinition folds
	# both into validate(). The SAME placeholder string is a validate() DEFECT there — proven
	# against a synthetic definition (not against house.fact_text, which is real copy now) so
	# the contrast stays proven rather than assumed, and a change to AnimalDefinition's posture
	# fails HERE with a name that says what broke.
	var synthetic := AnimalDefinition.new()
	synthetic.id = "testspecies"
	synthetic.display_name = "Test Species"
	synthetic.habitat_needs = ["forest", "cover"] as Array[String]
	synthetic.personality = AnimalDefinition.PERSONALITY_BOLD
	synthetic.scout_radius = 10
	synthetic.tiles_per_individual = 12
	synthetic.fact_text_pool = [placeholder_clone.fact_text]
	var animal_flags_placeholder: bool = false
	for p: String in synthetic.validate():
		if p.contains("fact_text"):
			animal_flags_placeholder = true
	check(animal_flags_placeholder,
		"the SAME placeholder string in an AnimalDefinition IS a validate() problem — the divergence is real and intended")

	note_expected_pending("house.tres `fact_text` copy is written, but step 8 (human sign-off) is NOT",
		"content-pipeline-status.md's `house` row: copy landed 2026-08-06, but step 6 "
		+ "(re-validation) and step 8 (copy sign-off) are recorded as still open. Machine "
		+ "checks (schema, exact string, not-a-placeholder) are green; whether the sourcing "
		+ "satisfies the human is not a machine check.")

	finish()
