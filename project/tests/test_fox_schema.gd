extends QATestCase
## Check 1 — schema validation of res://data/animals/fox.tres against the
## AnimalDefinition contract (gdd.md -> Data Schemas / Content Architecture, gdd.md:518)
## and the human-decided value set for Fox (roster row gdd.md:329).

const FOX_PATH: String = "res://data/animals/fox.tres"
const MODEL_PATH: String = "res://assets/animals/fox/Fox.tscn"

## The roster ids that currently have an AnimalDefinition `.tres` on disk: fox and
## rabbit. Deliberately NOT the full GDD roster — the point of this list is what
## actually exists, so `unresolved_avoids()` reports the real gap.
##
## Rabbit landed in pilot 3b, which RESOLVED the fox's previously-dangling avoids
## entry. Fox's `validate()` is clean for the first time; the assertions below pin
## that as the new baseline rather than the old "exactly one problem" state.
const KNOWN_IDS: PackedStringArray = ["fox", "rabbit"]

## roster.md's decided values for the Fox row, transcribed, not proposed (-> D-27 #2 for
## `tiles_per_individual`; roster.md -> Floor placeholders for `max_individuals ~6`).
const EXPECTED_TILES_PER_INDIVIDUAL: int = 5
const EXPECTED_MAX_INDIVIDUALS: int = 6


func _init() -> void:
	begin("fox.tres schema")

	# --- loads at all ---------------------------------------------------------
	var res: Resource = load(FOX_PATH)
	if not check(res != null, "%s loads" % FOX_PATH):
		finish()
		return

	# --- binds to the typed class, not a bare Resource ------------------------
	# `res is AnimalDefinition` is the load-bearing assertion: a .tres whose
	# script_class failed to resolve still loads, but arrives as a plain Resource
	# with the fields as untyped metadata. That would silently pass a field-by-field
	# check, so it is asserted before anything else touches the fields.
	if not check(res is AnimalDefinition, "binds to AnimalDefinition (not a bare Resource)",
			"got class %s / script %s" % [res.get_class(), res.get_script()]):
		finish()
		return
	var fox: AnimalDefinition = res as AnimalDefinition
	check(fox.get_script() != null, "has a script attached")

	# --- human-decided values -------------------------------------------------
	check_eq(fox.id, "fox", "id")
	check_eq(fox.display_name, "Fox", "display_name")
	check_eq(fox.habitat_needs, ["forest", "cover"] as Array[String], "habitat_needs")
	check_eq(fox.personality, AnimalDefinition.PERSONALITY_SHY, "personality == \"Shy\"")
	check_eq(fox.personality, "Shy", "personality is the literal string \"Shy\" (self-documenting on disk)")
	check(AnimalDefinition.PERSONALITIES.has(fox.personality),
		"personality is inside the declared domain %s" % str(AnimalDefinition.PERSONALITIES))
	check_eq(fox.avoids, ["rabbit"] as Array[String], "avoids")
	check_eq(fox.farm_tolerant, false, "farm_tolerant")
	check_eq(fox.scout_radius, 12, "scout_radius")

	# --- carrying capacity (2026-07-20 economy redesign; re-pointed by D-27) --------
	# RE-POINTED 2026-07-28. This block used to assert `tiles_per_individual ==
	# DEFAULT_TILES_PER_INDIVIDUAL` (12) on the grounds that the value was a placeholder. D-27 #2
	# ruled that the uniform 12 was never a decision — only the schema stub showing through — and
	# that roster.md's decided table wins: Fox 5. So the pin moves from "still the default" to
	# THE DECIDED NUMBER, which is a stronger check: the old form went green if the default and
	# the data drifted together, and this one cannot.
	check_eq(typeof(fox.tiles_per_individual), TYPE_INT, "tiles_per_individual is int")
	check_eq(fox.tiles_per_individual, EXPECTED_TILES_PER_INDIVIDUAL,
		"tiles_per_individual is roster.md's decided 5 (-> D-27 #2), not the schema's placeholder")
	check(fox.tiles_per_individual != AnimalDefinition.DEFAULT_TILES_PER_INDIVIDUAL,
		"...and it is NO LONGER the shared default %d — the stub is not showing through"
		% AnimalDefinition.DEFAULT_TILES_PER_INDIVIDUAL)
	check(fox.tiles_per_individual >= 1,
		"tiles_per_individual is at least 1 (zero would mean infinite capacity)")

	# `capacity_radius` and `max_individuals` are real exported fields as of D-27 #1 — spec.md
	# and roster.md both listed them while the code carried the cap as a `CapacityEvaluator`
	# module constant and denied the radius existed. They are pinned here for the first time.
	check_eq(typeof(fox.capacity_radius), TYPE_INT, "capacity_radius is int")
	check_eq(fox.capacity_radius, AnimalDefinition.CAPACITY_RADIUS_FOLLOWS_SCOUT,
		"capacity_radius is the FOLLOWS_SCOUT sentinel (0), i.e. the data states v1's default "
		+ "as the RELATION spec.md states, not as a copied number")
	check_eq(fox.effective_capacity_radius(), fox.scout_radius,
		"...and it resolves to scout_radius (12), never to a radius of zero")
	check_eq(typeof(fox.max_individuals), TYPE_INT, "max_individuals is int")
	check_eq(fox.max_individuals, EXPECTED_MAX_INDIVIDUALS,
		"max_individuals is roster.md's floor placeholder 6, now carried by the DATA and not by "
		+ "a constant inside CapacityEvaluator (-> D-27 #1)")

	# --- types ----------------------------------------------------------------
	check_eq(typeof(fox.id), TYPE_STRING, "id is String")
	check_eq(typeof(fox.display_name), TYPE_STRING, "display_name is String")
	check_eq(typeof(fox.farm_tolerant), TYPE_BOOL, "farm_tolerant is bool")
	check_eq(typeof(fox.scout_radius), TYPE_INT, "scout_radius is int")
	check_eq(typeof(fox.personality), TYPE_STRING, "personality is String (not an enum ordinal)")
	check_eq(fox.habitat_needs.get_typed_builtin(), TYPE_STRING,
		"habitat_needs is a TYPED Array[String]")
	check_eq(fox.avoids.get_typed_builtin(), TYPE_STRING,
		"avoids is a TYPED Array[String]")

	# --- habitat tags are in the shared vocabulary ----------------------------
	for tag: String in fox.habitat_needs:
		check(AnimalDefinition.HABITAT_TAGS.has(tag),
			"habitat tag \"%s\" is in the shared vocabulary" % tag)

	# --- scout_radius inside the GDD band -------------------------------------
	check(fox.scout_radius >= 8 and fox.scout_radius <= 12,
		"scout_radius %d is inside the GDD ~8-12 band (gdd.md:354)" % fox.scout_radius)

	# --- model_scene ----------------------------------------------------------
	check(fox.model_scenes[0] != null, "model_scene is set")
	check(fox.model_scenes[0] is PackedScene, "model_scene is a PackedScene")
	if fox.model_scenes[0] != null:
		check_eq(fox.model_scenes[0].resource_path, MODEL_PATH, "model_scene path")
		check(fox.model_scenes[0].can_instantiate(), "model_scene can instantiate")

	# --- fact_text: content-writer option B2, post-verification ------------------
	# Asserted as an EXACT string. The wording passed all FOUR checklist steps as
	# written — including step 1, per-clause, against ADW and Nat Geo Kids — so any
	# drift, even a typo fix, invalidates that clearance and must fail loudly rather
	# than pass a fuzzy "non-empty" check.
	#
	# The predecessor (option B) shipped and then FAILED verification: "shares one
	# cozy den" is contradicted by ADW (the male does not enter the maternity den),
	# and "most of the day" is contradicted by every source placing fox activity at
	# night and twilight. Recorded so the reverted wording is never reinstated.
	const FACT_TEXT: String = "Fox parents both help raise their kits, and the young foxes stay with their family for months. At about four weeks old, the kits start peeking out of the den for the first time."
	check(not fox.effective_fact_text().is_empty(), "fact_text is non-empty")
	check_eq(fox.effective_fact_text(), FACT_TEXT, "fact_text is the human-approved copy, verbatim")
	check(not fox.effective_fact_text().begins_with(AnimalDefinition.PLACEHOLDER_MARKER),
		"fact_text is no longer a placeholder")

	# Predation check, mechanized: the one framing gdd.md:33 bans outright for this
	# species. Cheap to assert, and it guards future copy edits as much as this one.
	# Word-boundary matched, NOT substring: a bare `contains("eat")` false-fails on
	# "great" / "feathers", and `contains("prey")` on "osprey". A test that cries wolf
	# on innocent copy gets disabled, which is worse than no test.
	var lowered: String = fox.effective_fact_text().to_lower()
	for banned: String in ["rabbit", "rabbits", "prey", "hunt", "hunts", "hunting", "catch", "eat", "eats"]:
		var word_re := RegEx.new()
		word_re.compile("\\b%s\\b" % banned)
		check(word_re.search(lowered) == null,
			"fact_text avoids predation-adjacent word \"%s\"" % banned)

	# Checklist step 1 (approved source) is now SATISFIED. Sources were unblocked in
	# the firewall allowlist and every clause was verified per-claim:
	#   "both help raise"        -> ADW Vulpes vulpes; Nat Geo Kids Red Fox
	#   "stay with ... months"   -> ADW (young remain at least until autumn)
	#   "about four weeks old"   -> ADW (young leave the den at 4-5 weeks)
	# Register is US English roster-wide: "kits", never "cubs" (UK usage).
	check(not lowered.contains("cub"),
		"fact_text uses US register (\"kits\", not \"cubs\")")

	# --- avoids: now fully RESOLVED -------------------------------------------
	# `avoids: ["rabbit"]` was a deliberate dangling reference until pilot 3b. Rabbit
	# now has a .tres, so the reference resolves and `unresolved_avoids()` is empty.
	# The avoid PAIR itself is unchanged and still declared only on the fox side —
	# gdd.md:207 makes the relation symmetric at runtime, so the resolver must union
	# both directions. Rabbit independently declares "fox"; that redundancy is legal.
	var unresolved: Array[String] = fox.unresolved_avoids(KNOWN_IDS)
	check(unresolved.is_empty(),
		"unresolved_avoids() is EMPTY — \"rabbit\" now resolves",
		"still unresolved: %s" % str(unresolved))
	check_eq(fox.normalized_avoids(), ["rabbit"] as Array[String],
		"the fox->rabbit avoid pair is still declared")

	# --- validate(): fully clean, for the first time ---------------------------
	# fact_text cleared at step-8 sign-off; the dangling avoids entry cleared when
	# rabbit.tres landed. Zero problems is now the correct baseline, and any
	# regression to a non-empty result must fail loudly.
	var problems: Array[String] = fox.validate(KNOWN_IDS)
	print("  validate() returned %d problem(s):" % problems.size())
	for p: String in problems:
		print("      - %s" % p)

	# NOTE ON ASSERTION COUNTING: this block previously iterated `problems` and called
	# check() once per element, which made the suite's total assertion count
	# DATA-DEPENDENT — the total shifted by one as validate()'s result changed, with
	# no file edit. That is what produced the unexplained 44-vs-45 discrepancy. The
	# checks below are fixed in number so the count is now stable and diffable.
	check(problems.is_empty(),
		"validate(KNOWN_IDS) is CLEAN (zero problems)",
		"unexpected: %s" % str(problems))
	var has_fact_problem: bool = false
	for p: String in problems:
		if p.contains("fact_text"):
			has_fact_problem = true
	check(not has_fact_problem, "validate() reports no fact_text problem")

	# validate() with no roster passed must also be completely clean.
	var bare_problems: Array[String] = fox.validate()
	check(bare_problems.is_empty(),
		"validate() with no known_ids is CLEAN (zero problems)",
		"unexpected: %s" % str(bare_problems))

	finish()
