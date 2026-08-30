extends QATestCase
## Check 1 (Rabbit) — schema validation of res://data/animals/rabbit.tres against the
## AnimalDefinition contract (gdd.md -> Data Schemas, gdd.md:518) and the human-decided
## value set for Rabbit (roster row gdd.md:324).

const RABBIT_PATH: String = "res://data/animals/rabbit.tres"
const MODEL_PATH: String = "res://assets/animals/rabbit/Rabbit.tscn"

## Species with a `.tres` on disk. Grows as the cleared pool gets design values.
const KNOWN_IDS: PackedStringArray = ["fox", "rabbit"]

## roster.md's decided values for the Rabbit row, transcribed, not proposed (-> D-27 #2 for
## `tiles_per_individual`; roster.md -> Floor placeholders for `max_individuals ~6`).
const EXPECTED_TILES_PER_INDIVIDUAL: int = 4
const EXPECTED_MAX_INDIVIDUALS: int = 6


func _init() -> void:
	begin("rabbit.tres schema")

	var res: Resource = load(RABBIT_PATH)
	if not check(res != null, "%s loads" % RABBIT_PATH):
		finish()
		return

	# Asserted before any field is touched: a .tres whose script_class fails to
	# resolve still loads as a plain Resource with the fields intact as metadata,
	# so a field-by-field check would pass green on a broken binding.
	if not check(res is AnimalDefinition, "binds to AnimalDefinition (not a bare Resource)",
			"got class %s / script %s" % [res.get_class(), res.get_script()]):
		finish()
		return
	var rabbit: AnimalDefinition = res as AnimalDefinition
	check(rabbit.get_script() != null, "has a script attached")

	# --- human-decided values -------------------------------------------------
	check_eq(rabbit.id, "rabbit", "id")
	check_eq(rabbit.display_name, "Rabbit", "display_name")
	# Rabbit gained `cover` on 2026-07-21 (-> D-22). `open_grass` alone was satisfiable by
	# untouched revealed land, which would have let rabbits settle ground the player never
	# made — see the inert-land invariant in animal_definition.gd.
	check_eq(rabbit.habitat_needs, ["open_grass", "cover"] as Array[String], "habitat_needs")
	check_eq(rabbit.personality, AnimalDefinition.PERSONALITY_BOLD, "personality == \"Bold\"")
	check_eq(rabbit.personality, "Bold", "personality is the literal string \"Bold\"")
	check(AnimalDefinition.PERSONALITIES.has(rabbit.personality),
		"personality is inside the declared domain %s" % str(AnimalDefinition.PERSONALITIES))
	check_eq(rabbit.avoids, ["fox"] as Array[String], "avoids")
	check_eq(rabbit.farm_tolerant, true, "farm_tolerant")
	check_eq(rabbit.scout_radius, 8, "scout_radius")

	# --- carrying capacity (2026-07-20 economy redesign; re-pointed by D-27) --------
	# RE-POINTED 2026-07-28. This block used to assert `tiles_per_individual ==
	# DEFAULT_TILES_PER_INDIVIDUAL` (12) as a placeholder pin. D-27 #2 ruled for roster.md's
	# decided table — Rabbit 4 — and called the drift LIVE rather than cosmetic: at 12 the
	# rabbit needed twelve `cover` tiles to reach capacity 1 where the design says four, so
	# time-to-first-move-in was being measured against a ~3x harder world than intended,
	# against a <=2 min target and 5 min hard ceiling. The pin now names the decided number,
	# which the old form could not — it went green if the default and the data drifted together.
	check_eq(typeof(rabbit.tiles_per_individual), TYPE_INT, "tiles_per_individual is int")
	check_eq(rabbit.tiles_per_individual, EXPECTED_TILES_PER_INDIVIDUAL,
		"tiles_per_individual is roster.md's decided 4 (-> D-27 #2), not the schema's placeholder")
	check(rabbit.tiles_per_individual != AnimalDefinition.DEFAULT_TILES_PER_INDIVIDUAL,
		"...and it is NO LONGER the shared default %d — the stub is not showing through"
		% AnimalDefinition.DEFAULT_TILES_PER_INDIVIDUAL)
	check(rabbit.tiles_per_individual >= 1,
		"tiles_per_individual is at least 1 (zero would mean infinite capacity)")

	# `capacity_radius` and `max_individuals` are real exported fields as of D-27 #1 — spec.md
	# and roster.md both listed them while the code carried the cap as a `CapacityEvaluator`
	# module constant and denied the radius existed. They are pinned here for the first time.
	check_eq(typeof(rabbit.capacity_radius), TYPE_INT, "capacity_radius is int")
	check_eq(rabbit.capacity_radius, AnimalDefinition.CAPACITY_RADIUS_FOLLOWS_SCOUT,
		"capacity_radius is the FOLLOWS_SCOUT sentinel (0), i.e. the data states v1's default "
		+ "as the RELATION spec.md states, not as a copied number")
	check_eq(rabbit.effective_capacity_radius(), rabbit.scout_radius,
		"...and it resolves to scout_radius (8), never to a radius of zero")
	check_eq(typeof(rabbit.max_individuals), TYPE_INT, "max_individuals is int")
	check_eq(rabbit.max_individuals, EXPECTED_MAX_INDIVIDUALS,
		"max_individuals is roster.md's floor placeholder 6, now carried by the DATA and not by "
		+ "a constant inside CapacityEvaluator (-> D-27 #1)")

	# --- types ----------------------------------------------------------------
	check_eq(typeof(rabbit.id), TYPE_STRING, "id is String")
	check_eq(typeof(rabbit.display_name), TYPE_STRING, "display_name is String")
	check_eq(typeof(rabbit.farm_tolerant), TYPE_BOOL, "farm_tolerant is bool")
	check_eq(typeof(rabbit.scout_radius), TYPE_INT, "scout_radius is int")
	check_eq(typeof(rabbit.personality), TYPE_STRING, "personality is String")
	check_eq(rabbit.habitat_needs.get_typed_builtin(), TYPE_STRING,
		"habitat_needs is a TYPED Array[String]")
	check_eq(rabbit.avoids.get_typed_builtin(), TYPE_STRING,
		"avoids is a TYPED Array[String]")

	for tag: String in rabbit.habitat_needs:
		check(AnimalDefinition.HABITAT_TAGS.has(tag),
			"habitat tag \"%s\" is in the shared vocabulary" % tag)

	check(rabbit.scout_radius >= 8 and rabbit.scout_radius <= 12,
		"scout_radius %d is inside the GDD ~8-12 band (gdd.md:354)" % rabbit.scout_radius)

	# Rabbit is the roster's farm-tolerant Bold counterweight to the Fox. Pinned
	# because the pair is what gives the roster its coverage (gdd.md:670).
	check(rabbit.farm_tolerant and not rabbit.personality == AnimalDefinition.PERSONALITY_SHY,
		"Rabbit is the Bold + farm-tolerant counterweight to the Shy Fox")

	# --- model_scene ----------------------------------------------------------
	check(rabbit.model_scenes[0] != null, "model_scene is set")
	check(rabbit.model_scenes[0] is PackedScene, "model_scene is a PackedScene")
	if rabbit.model_scenes[0] != null:
		check_eq(rabbit.model_scenes[0].resource_path, MODEL_PATH, "model_scene path")
		check(rabbit.model_scenes[0].can_instantiate(), "model_scene can instantiate")

	# --- fact_text ------------------------------------------------------------
	# Exact-string assertion, same rationale as the Fox: the wording cleared all four
	# checklist steps AS WRITTEN, so any drift invalidates that clearance and must
	# fail loudly rather than pass a fuzzy "non-empty" check.
	const FACT_TEXT: String = "Rabbits live together in a warren — a cozy maze of tunnels under the grass. One warren can be home to a whole group of rabbits."
	check(not rabbit.effective_fact_text().is_empty(), "fact_text is non-empty")
	check_eq(rabbit.effective_fact_text(), FACT_TEXT, "fact_text is the human-approved copy, verbatim")
	check(not rabbit.effective_fact_text().begins_with(AnimalDefinition.PLACEHOLDER_MARKER),
		"fact_text is not a placeholder")

	# Predation check, mechanized. For a prey species the banned set matters MORE than
	# it did for the fox: the tempting framing is "hunted by foxes". Word-boundary
	# matched, not substring, so "great"/"osprey" cannot false-fail.
	var lowered: String = rabbit.effective_fact_text().to_lower()
	for banned: String in ["fox", "foxes", "leopard", "predator", "predators",
			"prey", "hunt", "hunts", "hunted", "hunting", "escape", "eaten"]:
		var word_re := RegEx.new()
		word_re.compile("\\b%s\\b" % banned)
		check(word_re.search(lowered) == null,
			"fact_text avoids predation-adjacent word \"%s\"" % banned)

	# Roster-wide terminology rule (rabbit.tres header): "baby rabbits" only. "kits"
	# collides with the shipped Fox card. The roster-wide rule from D-19 stands
	# regardless of which species ship: baby rabbits are "baby rabbits," never kits.
	for collide: String in ["kit", "kits", "kitten", "kittens"]:
		var col_re := RegEx.new()
		col_re.compile("\\b%s\\b" % collide)
		check(col_re.search(lowered) == null,
			"fact_text avoids cross-species term \"%s\"" % collide)

	# --- avoids: every entry resolves --------------------------------------------
	# Rabbit carried a dangling "leopard" entry until 2026-07-27 (-> D-24). Leopard was
	# removed from the roster when the sourcing search closed with no cleared big-cat
	# asset, so the entry became permanent dead data and was dropped. Late-binding
	# Array[String] ids still make an unresolved entry non-fatal by design — that
	# contract is unchanged; there is simply nothing unresolved to exercise it here.
	var unresolved: Array[String] = rabbit.unresolved_avoids(KNOWN_IDS)
	check(unresolved.is_empty(),
		"unresolved_avoids() is empty — every avoids entry names a shipped species",
		"got: %s" % str(unresolved))
	check(not unresolved.has("fox"), "\"fox\" resolves — it has a .tres")

	# The fox<->rabbit pair is declared on BOTH sides. gdd.md:207 makes it symmetric at
	# runtime and says either side may declare it, so the redundancy is legal, not a
	# duplicate-data defect. Pinned so a future resolver that double-counts is caught.
	var fox_def: AnimalDefinition = load("res://data/animals/fox.tres") as AnimalDefinition
	if fox_def != null:
		check(rabbit.normalized_avoids().has("fox") and fox_def.normalized_avoids().has("rabbit"),
			"fox<->rabbit avoid pair is declared on both sides (legal per gdd.md:207)")

	# --- validate(): clean -------------------------------------------------------
	# Was "exactly ONE problem, the dangling leopard" until 2026-07-27 (-> D-24).
	# Fixed number of assertions regardless of validate()'s result — an earlier
	# per-element loop made the suite's assertion count data-dependent.
	var problems: Array[String] = rabbit.validate(KNOWN_IDS)
	print("  validate() returned %d problem(s):" % problems.size())
	for p: String in problems:
		print("      - %s" % p)

	check_eq(problems.size(), 0, "validate() reports no problems")
	var has_fact_problem: bool = false
	for p: String in problems:
		if p.contains("fact_text"):
			has_fact_problem = true
	check(not has_fact_problem, "validate() reports no fact_text problem")

	# With no roster passed, unresolved avoids are not evaluated at all, so the entry
	# must come back completely clean.
	var bare_problems: Array[String] = rabbit.validate()
	check(bare_problems.is_empty(),
		"validate() with no known_ids is CLEAN (zero problems)",
		"unexpected: %s" % str(bare_problems))

	finish()
