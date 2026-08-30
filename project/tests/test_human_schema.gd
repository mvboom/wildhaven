extends QATestCase
## Schema validation of res://data/animals/human.tres against the AnimalDefinition contract
## (spec.md -> Data Schemas) and roster.md's **already-decided** Human (Villager) row.
##
## VILLAGERS ARE JUST ANOTHER SPECIES (gdd.md -> Design Pillars). There is no people schema
## and no special case anywhere in the simulation, so this suite is deliberately shaped like
## `test_fox_schema.gd` and `test_rabbit_schema.gd` — if the villager ever needed a different
## kind of check, that would itself be the finding.
##
## OPEN QUESTION #31 CLOSED 2026-07-28. `fact_text` was a `PLACEHOLDER`-prefixed string, and
## the assertions here pinned that state deliberately so its closure would be a visible edit
## rather than a silent drift. Content-writer landed source-verified copy, so this suite is
## re-pointed to the shape `test_fox_schema.gd` and `test_rabbit_schema.gd` use for shipped
## copy: **exact-string equality**, a not-a-placeholder check, a banned-word sweep, and
## `validate()` clean. Exact equality is the point — the wording cleared all four checklist
## steps AS WRITTEN, so any drift, even a typo fix, invalidates that clearance and must fail
## loudly rather than pass a fuzzy "non-empty" check.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_human_schema.gd

const HUMAN_PATH: String = "res://data/animals/human.tres"
const MODEL_PATH: String = "res://assets/animals/human_adventurer/Adventurer.tscn"

## The species ids with an `AnimalDefinition` on disk today.
const KNOWN_IDS: PackedStringArray = ["fox", "human", "rabbit"]

## roster.md's decided values for the Human (Villager) row, transcribed, not proposed.
const EXPECTED_NEEDS: Array[String] = ["house", "cultivated"]
const EXPECTED_TILES_PER_INDIVIDUAL: int = 1

## PLACEHOLDER at the tight end of spec.md's ~8-12 band (#20) — no Human value is stated
## anywhere. Pinned so the human's eventual ruling is a visible edit.
const PROPOSED_SCOUT_RADIUS: int = 8

## Content-writer's option A, Content Pipeline step 5, source-verified per clause. Pinned as
## an EXACT string: the wording is what cleared verification, so any edit to it — including a
## typo fix — has to re-clear and must fail here first.
##
## RE-POINTED 2026-07-28 (second-source pass, #31). The card was single-sourced against Animal
## Diversity Web while Nat Geo's domain was unreachable; `education.nationalgeographic.org` is
## now in spec.md's approved set and the cross-check found a real factual error. Two clauses
## changed and the shipped string with them:
##   "About 10,000 years ago" -> "About 10,000 to 12,000 years ago" — the two most on-point NGS
##       Education pages both say 12,000 and a third gives 10,000-15,000, so a flat 10,000 sat
##       at the extreme low edge and was contradicted by its own sources.
##   "and that is when people began to settle down" -> "and little by little they settled down"
##       — "that is when" pinned a gradual process to a moment, which the sources explicitly
##       refuse ("the transition from wild harvesting was gradual").
## The per-clause sourcing is transcribed in human.tres's own header. This literal was COPIED
## from that file's `fact_text` line, not retyped: the range has no comma between "10,000 to
## 12,000" and "little by little" is easy to fumble.
const EXPECTED_FACT_TEXT: String = "Long ago, people moved from place to place instead of staying in one home. About 10,000 to 12,000 years ago they learned to grow their own food, and little by little they settled down in one place."

## The banned set for THIS card. `hunt*`/`prey`/`kill` are gdd.md's outright predation ban,
## which applies roster-wide. **`gather*` is here for a reason specific to this card** and is
## recorded in human.tres: ADW's sentence is "Ancient humans were nomadic hunter gatherers",
## and the copy rests on the conclusion instead of showing that work. Restoring the source
## wording is the likeliest future edit and the one this sweep must catch.
const BANNED_WORDS: PackedStringArray = [
	"hunt", "hunter", "hunters", "hunting", "hunts",
	"gather", "gatherer", "gatherers", "gathering", "gathers",
	"prey", "kill", "kills", "killing",
]


func _init() -> void:
	begin("human.tres schema")

	# --- loads at all -------------------------------------------------------------
	var res: Resource = load(HUMAN_PATH)
	if not check(res != null, "%s loads" % HUMAN_PATH):
		finish()
		return

	# --- binds to the typed class, not a bare Resource ----------------------------
	# Asserted before any field is read: a `.tres` whose script_class failed to resolve loads
	# fine and arrives as untyped metadata, silently passing every field check below.
	if not check(res is AnimalDefinition, "binds to AnimalDefinition (not a bare Resource)",
			"got class %s / script %s" % [res.get_class(), res.get_script()]):
		finish()
		return
	var human: AnimalDefinition = res as AnimalDefinition
	check(human.get_script() != null, "has a script attached")

	# --- roster.md's decided values ------------------------------------------------
	check_eq(human.id, "human", "id")
	check_eq(human.display_name, "Villager", "display_name is the player-facing \"Villager\"")
	check_eq(human.habitat_needs, EXPECTED_NEEDS,
		"habitat_needs == [\"house\", \"cultivated\"] — a House plus the field beside it")
	check_eq(human.personality, AnimalDefinition.PERSONALITY_BOLD, "personality == \"Bold\"")
	check_eq(human.personality, "Bold",
		"personality is the literal string \"Bold\" (self-documenting on disk)")
	check(AnimalDefinition.PERSONALITIES.has(human.personality),
		"personality is inside the declared domain %s" % str(AnimalDefinition.PERSONALITIES))
	check_eq(human.farm_tolerant, true,
		"farm_tolerant — the villager lives ON cultivated land, so false would be self-contradictory")
	check_eq(human.tiles_per_individual, EXPECTED_TILES_PER_INDIVIDUAL,
		"tiles_per_individual == 1 (roster.md: the House is the scarce need and the floor House is one tile)")
	check_eq(human.scout_radius, PROPOSED_SCOUT_RADIUS,
		"scout_radius == %d (PROPOSED, #20)" % PROPOSED_SCOUT_RADIUS)

	# `capacity_radius` and `max_individuals` became real exported fields on 2026-07-28 (D-27 #1),
	# so they are pinned here for the first time. The sentinel is the interesting one: #20 is open
	# and WILL move `scout_radius`, and the whole reason the data says 0 rather than 8 is that a
	# copied 8 would silently stop being equal on that day.
	check_eq(typeof(human.capacity_radius), TYPE_INT, "capacity_radius is int")
	check_eq(human.capacity_radius, AnimalDefinition.CAPACITY_RADIUS_FOLLOWS_SCOUT,
		"capacity_radius is the FOLLOWS_SCOUT sentinel (0) — the RELATION spec.md states, not a "
		+ "copy of scout_radius's current number")
	check_eq(human.effective_capacity_radius(), human.scout_radius,
		"...and it resolves to scout_radius (%d), never to a radius of zero" % human.scout_radius)
	check_eq(typeof(human.max_individuals), TYPE_INT, "max_individuals is int")
	check_eq(human.max_individuals, AnimalDefinition.DEFAULT_MAX_INDIVIDUALS,
		"max_individuals is roster.md's floor placeholder 6, carried by the DATA now and not by a "
		+ "constant inside CapacityEvaluator (-> D-27 #1)")

	# --- NO avoids, and that closes a gate rather than leaving one open -------------
	# roster.md's structural predation check runs only for a species carrying an avoids entry.
	# Human carries none, so its predation risk is closed by DATA, not by copy — which matters
	# because the villager's card is the one piece of copy nobody has written yet (#31).
	check_eq(human.avoids, [] as Array[String], "avoids is EMPTY — the villager fears nobody")
	check(human.normalized_avoids().is_empty(), "...normalized too")
	check(human.unresolved_avoids(KNOWN_IDS).is_empty(),
		"...so there is no dangling avoid reference and no predation graph to check")

	# --- types ----------------------------------------------------------------------
	check_eq(typeof(human.id), TYPE_STRING, "id is String")
	check_eq(typeof(human.display_name), TYPE_STRING, "display_name is String")
	check_eq(typeof(human.farm_tolerant), TYPE_BOOL, "farm_tolerant is bool")
	check_eq(typeof(human.scout_radius), TYPE_INT, "scout_radius is int")
	check_eq(typeof(human.tiles_per_individual), TYPE_INT, "tiles_per_individual is int")
	check_eq(human.habitat_needs.get_typed_builtin(), TYPE_STRING,
		"habitat_needs is a TYPED Array[String]")
	check_eq(human.avoids.get_typed_builtin(), TYPE_STRING, "avoids is a TYPED Array[String]")

	# --- the shared vocabulary --------------------------------------------------------
	check(AnimalDefinition.HABITAT_TAGS.has("house"),
		"`house` is in the shared ten-tag vocabulary")
	check(AnimalDefinition.HABITAT_TAGS.has("cultivated"),
		"`cultivated` is in the shared ten-tag vocabulary")
	check(human.scout_radius >= 8 and human.scout_radius <= 12,
		"scout_radius %d is inside spec.md's ~8-12 band" % human.scout_radius)
	check(human.tiles_per_individual >= 1,
		"tiles_per_individual is at least 1 (zero would mean infinite capacity)")

	# --- the inert-land invariant --------------------------------------------------------
	# Neither of the villager's needs can come from untouched land: `house` has exactly one
	# source (the House) and `cultivated` exactly one (the painted field). So a villager can
	# only ever arrive on land the player made — which is precisely row 4's USP proof.
	var only_bare: bool = true
	for tag: String in human.habitat_needs:
		if not AnimalDefinition.BARE_TAGS.has(tag):
			only_bare = false
	check(not only_bare,
		"habitat_needs is NOT satisfiable by untouched revealed land (the inert-land invariant)")

	# --- model_scenes ------------------------------------------------------------------------
	# PINNED AT 18, in this exact order. Was 5 (Adventurer, Man, AnimatedWoman, HoodieCharacter,
	# Punk); the 2026-08-29 asset-audit sweep appended 13 Animated Men/Women character variants
	# (MaleLongSleeve..SmoothFemaleTankTop) to the tail. Equal weight, no ordering preference
	# (D-42 precedent) — the ORDER is pinned not because it means anything to the simulation
	# but because an exact ordered list is what makes an unreviewed content edit show up here
	# as a failure instead of landing silently. Re-point it deliberately, never relax it to a
	# `>=` or a prefix match. MODEL_PATH stays the Adventurer path and stays entry [0]: it is
	# art.md's recommended default, and "the shipped default stays first" is load-bearing for
	# saves and for world_root.gd's style defaults, so [0] gets its own assertion above and
	# beyond the list.
	check_eq(human.model_scenes.size(), 18, "18 human look variants")
	check_eq(human.model_scenes[0].resource_path, MODEL_PATH,
		"model_scenes[0] is STILL the Adventurer variant (art.md's recommended default), unchanged by the 2026-08-29 growth")
	var variant_paths: PackedStringArray = PackedStringArray()
	for scene: PackedScene in human.model_scenes:
		check(scene is PackedScene, "every model_scenes entry is a PackedScene")
		check(scene.can_instantiate(), "every model_scenes entry can instantiate")
		variant_paths.append(scene.resource_path)
	var expected_paths: PackedStringArray = [
		"res://assets/animals/human_adventurer/Adventurer.tscn",
		"res://assets/animals/human_man/Man.tscn",
		"res://assets/animals/human_woman/AnimatedWoman.tscn",
		"res://assets/animals/human_hoodie/HoodieCharacter.tscn",
		"res://assets/animals/human_punk/Punk.tscn",
		"res://assets/animals/human_male_longsleeve/MaleLongSleeve.tscn",
		"res://assets/animals/human_male_shirt/MaleShirt.tscn",
		"res://assets/animals/human_smooth_male_casual/SmoothMaleCasual.tscn",
		"res://assets/animals/human_smooth_male_longsleeve/SmoothMaleLongSleeve.tscn",
		"res://assets/animals/human_smooth_male_shirt/SmoothMaleShirt.tscn",
		"res://assets/animals/human_female_alternative/FemaleAlternative.tscn",
		"res://assets/animals/human_female_casual/FemaleCasual.tscn",
		"res://assets/animals/human_female_dress/FemaleDress.tscn",
		"res://assets/animals/human_female_tanktop/FemaleTankTop.tscn",
		"res://assets/animals/human_smooth_female_alternative/SmoothFemaleAlternative.tscn",
		"res://assets/animals/human_smooth_female_casual/SmoothFemaleCasual.tscn",
		"res://assets/animals/human_smooth_female_dress/SmoothFemaleDress.tscn",
		"res://assets/animals/human_smooth_female_tanktop/SmoothFemaleTankTop.tscn",
	]
	check_eq(variant_paths, expected_paths,
		"model_scenes lists exactly these 18 paths, in this order")
	var instance: Node = human.model_scenes[0].instantiate()
	check(instance is Node3D, "...as a Node3D, so a landed villager is a real node in the world")
	if instance != null:
		instance.free()

	# --- fact_text: the gate that CLOSED (#31, 2026-07-28) --------------------------------------
	# Exact-string assertion, same rationale as Fox and Rabbit. The predecessor state — a
	# `PLACEHOLDER`-prefixed string naming #31 — is recorded here so nobody reinstates it by
	# reverting a file: the placeholder was correct while the copy was unwritten, and is a
	# defect now that it is written.
	check(not human.effective_fact_text().is_empty(), "fact_text is non-empty")
	check_eq(human.effective_fact_text(), EXPECTED_FACT_TEXT,
		"fact_text is content-writer's source-verified copy, VERBATIM")
	check(not human.effective_fact_text().begins_with(AnimalDefinition.PLACEHOLDER_MARKER),
		"fact_text is NOT a placeholder any more — Open Question #31 is closed")
	check(not human.effective_fact_text().contains(AnimalDefinition.PLACEHOLDER_MARKER),
		"...and the marker does not appear anywhere inside it either")
	check(not human.effective_fact_text().contains("#31"),
		"...and the card no longer names an open question to the player")

	# BANNED VOCABULARY, mechanized. human.tres's own header records the rule: ADW's source
	# sentence reads "nomadic hunter gatherers" and this copy deliberately rests on the
	# CONCLUSION — people moved from place to place — instead of showing that work. A future
	# editor "restoring" the source wording is exactly what this sweep exists to catch, which is
	# why **`gather` is in the set** alongside the predation words gdd.md bans outright.
	#
	# Word-boundary matched, NOT substring: a bare `contains("prey")` false-fails on "osprey"
	# and `contains("hunt")` on a surname. A test that cries wolf on innocent copy gets
	# disabled, which is worse than no test.
	var lowered: String = human.effective_fact_text().to_lower()
	for banned: String in BANNED_WORDS:
		var word_re := RegEx.new()
		word_re.compile("\\b%s\\b" % banned)
		check(word_re.search(lowered) == null,
			"fact_text avoids banned word \"%s\"" % banned)

	# NEGATIVE CONTROL for the sweep itself. An all-passing word list proves nothing unless the
	# same matcher is shown to FIRE on copy that violates the rule — otherwise a broken regex,
	# an empty `BANNED_WORDS`, or a `check()` that silently no-ops would read as clean.
	var offending: String = (
		"Long ago people were nomadic hunter gatherers who moved from place to place."
	).to_lower()
	var caught: Array[String] = []
	for banned: String in BANNED_WORDS:
		var probe_re := RegEx.new()
		probe_re.compile("\\b%s\\b" % banned)
		if probe_re.search(offending) != null:
			caught.append(banned)
	caught.sort()
	check_eq(caught, ["gatherers", "hunter"] as Array[String],
		"NEGATIVE CONTROL: the same sweep run over ADW's own \"nomadic hunter gatherers\" "
		+ "wording FIRES on exactly the two words it should — so the clean result above is a "
		+ "measurement, not an empty search")

	# ROSTER-WIDE TERMINOLOGY (human.tres header; the D-19 "kits"/"kittens" lesson). "town" and
	# "village" were drafted and CUT: `display_name` is "Villager" and the HUD counter is
	# "Village Population", so a real-world claim carrying those words reads as a claim about
	# the GAME world — which the two-register rule forbids.
	for collide: String in ["town", "towns", "village", "villages", "villager", "villagers"]:
		var col_re := RegEx.new()
		col_re.compile("\\b%s\\b" % collide)
		check(col_re.search(lowered) == null,
			"fact_text avoids game-world term \"%s\" (the two-register rule)" % collide)

	# The copy names no other species — the predation graph stays closed by data (see `avoids`
	# above) and by copy.
	for other_id: String in KNOWN_IDS:
		if other_id == "human":
			continue
		check(not lowered.contains(other_id),
			"fact_text names no other roster species (\"%s\")" % other_id)

	# --- validate(): CLEAN, for the first time ---------------------------------------------------
	# Was "exactly ONE problem, the fact_text placeholder" until 2026-07-28. Zero is now the
	# correct baseline and any regression to a non-empty result must fail loudly.
	# FIXED-COUNT: problems are printed, never iterated with check().
	var problems: Array[String] = human.validate(KNOWN_IDS)
	print("  validate(KNOWN_IDS) returned %d problem(s):" % problems.size())
	for p: String in problems:
		print("      - %s" % p)

	check(problems.is_empty(),
		"validate(KNOWN_IDS) is CLEAN (zero problems)", "unexpected: %s" % str(problems))
	var fact_problems: int = 0
	for p: String in problems:
		if p.contains("fact_text"):
			fact_problems += 1
	check_eq(fact_problems, 0, "...and no fact_text problem in particular")

	var bare_problems: Array[String] = human.validate()
	check(bare_problems.is_empty(),
		"validate() with no known_ids is CLEAN too", "unexpected: %s" % str(bare_problems))

	# NEGATIVE CONTROL for `validate()`. "Zero problems" is only meaningful if this entry's
	# validator can still produce one — a clone with the placeholder put back must fail.
	var clone: AnimalDefinition = human.duplicate() as AnimalDefinition
	clone.fact_text_pool = ["%s villager copy pending (#31)" % AnimalDefinition.PLACEHOLDER_MARKER]
	var clone_problems: Array[String] = clone.validate(KNOWN_IDS)
	check(not clone_problems.is_empty(),
		"NEGATIVE CONTROL: put the PLACEHOLDER back on a clone and validate() reports a problem "
		+ "again — the clean result above is a real check, not a validator that never speaks",
		"clone unexpectedly clean")
	var clone_fact_problems: int = 0
	for p: String in clone_problems:
		if p.contains("fact_text"):
			clone_fact_problems += 1
	check_eq(clone_fact_problems, 1, "...and the problem it reports is the fact_text placeholder")

	# --- the roster actually loads it ------------------------------------------------------------
	# The simulation reaches species through `SpeciesRoster`, so a `.tres` that validates but
	# does not load through the roster would still never produce a villager.
	var roster := SpeciesRoster.new()
	# RE-POINTED (-> D-43, roster grew 3 -> 12): this section's claim is "the roster actually
	# loads human.tres", not any particular roster size — that a `.tres` that validates but
	# never reaches the simulation through `SpeciesRoster` is still a defect. `roster.size()`
	# growing past 3 is D-43's claim, not this suite's, so this only asserts the floor loaded.
	check(roster.size() >= 3, "SpeciesRoster loads at least the floor species (%d loaded)"
		% roster.size())
	check_eq(roster.by_id("human"), human,
		"...and `by_id(\"human\")` is THIS resource — one roster, shared with the simulation")
	check_eq(roster.by_id("Human"), human,
		"...and id normalisation resolves a hand-authored \"Human\" too")

	note_expected_pending(
		"OPEN QUESTION #31 IS CLOSED, but step 8 (human sign-off) is NOT",
		"gdd.md -> Known thinnesses called this the floor's single point of failure: \"the "
		+ "fact-card content (#31) has no substitute, because the register is fixed and no other "
		+ "species can carry row 4's proof.\" Content-writer landed source-verified copy on "
		+ "2026-07-28 and human.tres's header says \"AWAITING STEP-8 SIGN-OFF\". Machine checks "
		+ "(schema, exact string, banned words, register) are green; the human's read of the "
		+ "sourcing is not a thing this suite can perform."
	)
	note_expected_pending(
		"`scout_radius = 8` is PROPOSED, not decided (#20)",
		"spec.md gives the band ~8-12 and states no Human value. Pinned at 8 here so the "
		+ "human's ruling is a visible edit rather than a silent drift."
	)
	# --- the whole roster against roster.md's decided table (-> D-27 #2) ------------
	# This WAS a `note_expected_pending`: human.tres was authored at 1 per roster.md while
	# fox.tres and rabbit.tres still held the schema's uniform placeholder 12, so three species
	# ran off two sources of truth. D-27 #2 ruled for roster.md and the `.tres` files were
	# corrected, so the pending is CLOSED and becomes an assertion. It lives in the Human suite
	# rather than in either animal's because the defect was a CROSS-species inconsistency: the
	# per-species suites each pin their own number and none of them could see the disagreement.
	for row: Array in [["human", 1], ["fox", 5], ["rabbit", 4]] as Array[Array]:
		var species: AnimalDefinition = roster.by_id(row[0])
		if not check(species != null, "roster carries \"%s\"" % row[0]):
			continue
		check_eq(species.tiles_per_individual, row[1],
			"...and its `tiles_per_individual` is roster.md's decided %d, not the schema's "
			% row[1] + "placeholder %d" % AnimalDefinition.DEFAULT_TILES_PER_INDIVIDUAL)

	finish()
