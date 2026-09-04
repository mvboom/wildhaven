extends QATestCase
## THE INERT-LAND INVARIANT AT ITS SOURCE (spec.md -> Shared Patterns).
##
## spec.md requires that `BARE_TAGS` — the tags untouched revealed land emits — be
## "derived from the tag-source mapping at validation time, never hardcoded", because a
## hardcoded copy silently rots the first time emission changes, which is the exact
## failure the invariant exists to prevent. `TerrainDefinition.derive_bare_tags()` is that
## derivation, and this suite is its gate.
##
## THE HAZARD THIS SUITE EXISTS FOR: `derive_bare_tags()` returns an empty array when no
## `wild_grass` entry is present (its own docstring says so and defers the check here).
## An empty result is also what a CORRECT derivation returns today. So "derive_bare_tags()
## is empty" on its own is a VACUOUSLY TRUE assertion — it would keep passing if
## wild_grass.tres were deleted tomorrow, and the invariant would be silently unguarded.
## The existence assertion below is what removes the vacuity, so it is asserted FIRST and
## the derivation assertion is meaningless without it.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_bare_tags_derivation.gd
##
## SCOPE: the SPECIES side of the invariant (no species' `habitat_needs` is a subset of
## BARE_TAGS) is test_inert_land_invariant.gd and is deliberately untouched here. This
## suite is the TERRAIN side — the structural construction that makes the species-side
## check cheap.

## 6 v1 terrains + the habitat-tiers ruling's 3 additions (Meadow, Scrub, Snowfield —
## task-8-brief.md). None of the 3 touch wild_grass.tres or the derivation itself.
const EXPECTED_TERRAIN_COUNT: int = 9


## True when `def.validate()` reports the inert-land invariant specifically.
##
## Substring-filtered rather than "validate() is non-empty": a synthetic definition
## legitimately reports other problems (an empty `model_scenes`, for one), so a bare
## non-empty check would pass for the WRONG reason and keep passing if the invariant
## check were deleted from the schema.
func _has_invariant_problem(def: TerrainDefinition) -> bool:
	for p: String in def.validate():
		if p.contains("inert-land invariant"):
			return true
	return false


## A TerrainDefinition built in memory. Never loaded from disk — these exist to prove the
## schema REJECTS what it should, which no shipped `.tres` can demonstrate.
func _make(terrain_id: String, tags: Array[String]) -> TerrainDefinition:
	var def := TerrainDefinition.new()
	def.id = terrain_id
	def.display_name = "Synthetic %s" % terrain_id
	def.emitted_tags = tags
	def.cost = 0
	return def


func _init() -> void:
	begin("BARE_TAGS derivation / inert-land invariant (terrain side)")

	var loaded: Array[TerrainDefinition] = TerrainDefinition.load_all()

	# --- 1. THE ANTI-VACUITY ASSERTION ----------------------------------------
	# Must come first and must be read first: every assertion after it is only meaningful
	# because a wild_grass entry actually exists to derive from.
	var wild: TerrainDefinition = TerrainDefinition.find_by_id(
		loaded, TerrainDefinition.WILD_GRASS_ID)
	var wild_exists: bool = check(wild != null,
		"a `%s` TerrainDefinition EXISTS on disk — without this the derivation below is vacuous"
			% TerrainDefinition.WILD_GRASS_ID,
		"find_by_id() over load_all() found nothing; %d terrain(s) loaded" % loaded.size())

	# --- 2. the derivation over real data is EMPTY ------------------------------
	var derived: PackedStringArray = TerrainDefinition.derive_bare_tags(loaded)
	check(derived.is_empty(),
		"derive_bare_tags(load_all()) is EMPTY — untouched revealed land emits nothing",
		"derived: %s" % str(derived))
	if wild_exists:
		check(wild.emitted_tags.is_empty(),
			"the wild_grass entry's own `emitted_tags` is empty (the derivation's source)",
			"got: %s" % str(wild.emitted_tags))
	else:
		check(false, "the wild_grass entry's own `emitted_tags` is empty (the derivation's source)",
			"no wild_grass entry to read")

	# --- 3. a wild_grass entry that emits ANYTHING is REJECTED -------------------
	# The half that proves the derivation is enforced and not merely observed. Without
	# this, a future edit adding `open_grass` to wild_grass.tres would change BARE_TAGS
	# silently and correctly, and hand the player finished habitat for pushing the mist.
	check(_has_invariant_problem(_make("wild_grass", ["open_grass"] as Array[String])),
		"a synthetic wild_grass emitting `open_grass` FAILS validate() (inert-land invariant)")
	check(_has_invariant_problem(_make("wild_grass", ["quiet", "cover"] as Array[String])),
		"a synthetic wild_grass emitting several tags FAILS validate()")
	check(not _has_invariant_problem(_make("wild_grass", [] as Array[String])),
		"a synthetic wild_grass emitting NOTHING passes the invariant check")
	check(not _has_invariant_problem(_make("grass", ["open_grass"] as Array[String])),
		"a synthetic GRASS emitting `open_grass` is fine — the rule binds wild grass only")

	# --- 4. the terrain set on disk is the expected size -------------------------
	check_eq(loaded.size(), EXPECTED_TERRAIN_COUNT,
		"load_all() finds exactly %d terrains" % EXPECTED_TERRAIN_COUNT)

	# --- positive control: the derivation actually READS its source --------------
	# `derive_bare_tags()` returning empty is the pass condition above, and a function
	# that always returned empty would satisfy it. These two assertions prove it does not:
	# feed it a wild_grass that emits, and the derived set must follow the data.
	var synthetic_set: Array[TerrainDefinition] = [
		_make("grass", ["open_grass"] as Array[String]),
		_make("wild_grass", ["quiet", "flowers"] as Array[String]),
	]
	check_eq(TerrainDefinition.derive_bare_tags(synthetic_set),
		PackedStringArray(["quiet", "flowers"]),
		"derive_bare_tags() FOLLOWS its source data — it is a derivation, not a constant")
	check(TerrainDefinition.derive_bare_tags([
			_make("grass", ["open_grass"] as Array[String])
		]).is_empty(),
		"derive_bare_tags() with NO wild_grass returns empty — the documented hazard, covered by assertion 1")

	# --- the still-hardcoded AnimalDefinition side -------------------------------
	# RE-POINTED 2026-09-04 (habitat-tiers ruling, spec OQ-F): `quiet` was RETIRED from
	# `HABITAT_TAGS` — a `built` `HabitatLimit` does its job strictly better — and BARE_TAGS
	# had to follow, because every entry there must resolve inside the shared vocabulary
	# (test_inert_land_invariant.gd asserts exactly that). Old value ["open_grass", "quiet"]
	# -> new value ["open_grass"]; still recorded, not asserted as a failure.
	check_eq(AnimalDefinition.BARE_TAGS, PackedStringArray(["open_grass"]),
		"AnimalDefinition.BARE_TAGS is still the hardcoded singleton (pinned so a change is deliberate)")
	note_expected_pending(
		"AnimalDefinition.BARE_TAGS is hardcoded and DISAGREES with the derivation",
		"animal_definition.gd holds [\"open_grass\"]; derive_bare_tags() over real data is []. "
		+ "The hardcoded set is a STRICT SUPERSET of the derived one, so the species-side subset check is "
		+ "OVER-enforced, never under-enforced — the safe direction to err for a pillar invariant. "
		+ "Reconciling them (making AnimalDefinition read the derivation) is Tier 1 row 6's work; "
		+ "tier1-status.md row 6 already names it a validation prerequisite. Not changed in this task.")

	finish()
