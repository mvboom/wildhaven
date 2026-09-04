extends QATestCase
## The inert-land invariant (gdd.md -> Data Schemas; -> D-22): no species' `habitat_needs`
## may be a subset of BARE_TAGS — the tags untouched revealed land emits. A species that
## violated it would settle land the player never made, breaking both the mist no-reward
## pillar and the rule that every resident is something the player attracted.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_inert_land_invariant.gd

const ROSTER_DIR: String = "res://data/animals"


## A minimally-valid definition carrying the given needs. Other fields are filled only so
## the entry is otherwise sane; this test never asserts on them.
func _make(needs: Array[String]) -> AnimalDefinition:
	var def := AnimalDefinition.new()
	def.id = "testspecies"
	def.display_name = "Test Species"
	def.habitat_needs = needs
	def.personality = AnimalDefinition.PERSONALITY_BOLD
	def.scout_radius = 10
	def.tiles_per_individual = 12
	def.fact_text_pool = ["A harmless sentence for schema purposes."]
	return def


## True when validate() reports the invariant specifically. Filtering by substring keeps
## this independent of the other problems an incomplete definition legitimately reports
## (an unset `model_scene`, for one).
func _has_invariant_problem(def: AnimalDefinition) -> bool:
	for p: String in def.validate():
		if p.contains("inert-land invariant"):
			return true
	return false


func _init() -> void:
	begin("inert-land invariant")

	check(AnimalDefinition.BARE_TAGS.size() > 0, "BARE_TAGS is non-empty")
	for tag: String in AnimalDefinition.BARE_TAGS:
		check(AnimalDefinition.HABITAT_TAGS.has(tag),
			"BARE_TAG \"%s\" is in the shared vocabulary" % tag)

	# --- violations are caught -------------------------------------------------
	check(_has_invariant_problem(_make(["open_grass"] as Array[String])),
		"a species needing only `open_grass` is REJECTED (the original Rabbit bug)")

	# RE-POINTED 2026-09-04 (habitat-tiers ruling, spec OQ-F): `quiet` was RETIRED from
	# `HABITAT_TAGS` entirely — a `built` `HabitatLimit` does its job strictly better — and
	# `AnimalDefinition.BARE_TAGS` shrank from `["open_grass", "quiet"]` to `["open_grass"]`
	# to follow (every BARE_TAGS entry must resolve inside the shared vocabulary, asserted
	# above). A retired tag can never again be genuinely bare, so these two fixtures no
	# longer demonstrate a rejection BY THIS INVARIANT specifically — old expectation:
	# REJECTED; new: not flagged by the inert-land check (a species naming an unknown tag
	# is still reported, just under a different problem string, which this suite's
	# `_has_invariant_problem()` substring filter deliberately does not chase).
	check(not _has_invariant_problem(_make(["quiet"] as Array[String])),
		"a species needing only the RETIRED `quiet` tag is NOT flagged by the inert-land invariant specifically any more")
	check(not _has_invariant_problem(_make(["open_grass", "quiet"] as Array[String])),
		"...and pairing it with `open_grass` no longer trips the invariant either — `quiet` is no longer in BARE_TAGS, so `only_bare` cannot go true")

	# --- legitimate species pass ------------------------------------------------
	check(not _has_invariant_problem(_make(["open_grass", "cover"] as Array[String])),
		"the retuned Rabbit (`open_grass, cover`) is ACCEPTED")
	check(not _has_invariant_problem(_make(["forest", "cover"] as Array[String])),
		"Fox (`forest, cover`) is ACCEPTED")
	check(not _has_invariant_problem(_make(["cultivated", "open_grass"] as Array[String])),
		"Chicken (`cultivated, open_grass`) is ACCEPTED — `cultivated` is player-made")

	# --- every shipped .tres on disk obeys it -----------------------------------
	# The check that actually gates the roster: it walks real data, so a future species
	# authored in violation fails CI instead of shipping.
	var dir := DirAccess.open(ROSTER_DIR)
	if check(dir != null, "roster dir %s opens" % ROSTER_DIR):
		for file_name: String in dir.get_files():
			if not file_name.ends_with(".tres"):
				continue
			var path: String = "%s/%s" % [ROSTER_DIR, file_name]
			var def: AnimalDefinition = load(path) as AnimalDefinition
			if check(def != null, "%s loads as AnimalDefinition" % file_name):
				check(not _has_invariant_problem(def),
					"%s obeys the inert-land invariant" % file_name,
					"habitat_needs = %s" % str(def.habitat_needs))

	finish()
