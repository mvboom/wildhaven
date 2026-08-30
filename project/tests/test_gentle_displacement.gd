extends QATestCase
## GENTLE DISPLACEMENT — Tier 1 row 10, and a **pillar invariant**: gdd.md -> Scope says it
## ships whole and only presentation thins. The pillar, stated precisely in gdd.md ->
## Systems in Play:
##
##   "**animals are never killed, and nothing blinks out unexplained.** Any loss is the warned,
##    reversible result of the player's own settled choice, never the game's initiative ...
##    **The computable trigger:** an action warns iff, once its neighbourhood settles,
##    `capacity(h, S)` would fall below `population(h, S)` for any home site in range —
##    including to 0. **Frequency is bounded by settlement, not rate-limiting:** one warning per
##    settled gesture summarizing every affected home, and a warning is never suppressed while
##    its consequence proceeds. **Two gentle outcomes, in order: relocation** if a suitable spot
##    exists (`capacity >= population` there) ... otherwise **moving away** ... Species Hosted
##    and the Field Guide entry stay permanent. ... Rejected: **silent displacement** ...,
##    **blocking the build** (a fail state), and **capacity floors**."
##
## SEVEN SECTIONS, ONE PER CLAUSE:
##   1. THE TRIGGER IS EXACT. Swept across seven capacity values against a fixed population,
##      asserting warn **iff** `capacity < population`. **The boundary is the point**:
##      `capacity == population` must NOT warn, and `capacity == population - 1` must.
##   2. MODE-AGNOSTIC. Terraform, build and removal each displace through the same entry point,
##      which takes a tile and is not told which mode produced it.
##   3. ONE WARNING PER SETTLED GESTURE, SUMMARISING EVERY AFFECTED HOME. Three homes, two
##      species, one tap-burst, one warning.
##   4. WARNING FIRST, CONSEQUENCE AFTER — AND NEVER SUPPRESSED. Emission order is asserted on a
##      single shared log, and the consequence is shown to run with nobody listening at all.
##   5. RELOCATION PREFERRED, DEPARTURE OTHERWISE, with the destination rule's own boundary:
##      `capacity >= population` there relocates, one tile short departs.
##   6. SPECIES HOSTED IS PERMANENT. A departure removes residents and never removes a record.
##   7. NO FAIL STATE. The displacing edit is never blocked, returns success, and there is no
##      error/veto channel anywhere on the surface.
##
## SYNTHETIC WHERE THE NUMBERS MATTER, REAL WHERE THE WIRING MATTERS. Sections 1 and 3-6 drive a
## one-species (or two-species) synthetic roster so the arithmetic does not move when the shipped
## roster is retuned. Sections 2 and 7 additionally drive the real `scenes/Main.tscn` through
## `WorldRoot`'s public API and displace a **villager family by removing its House** — which
## gdd.md calls the floor's *likeliest* displacement ("Human's divisor is 1 against a 1x1 floor
## House"), and therefore the case the copy rules were decided in advance for.
##
## LAMBDA NOTE (a real trap, hit by the row 10 dispatch): **GDScript lambdas capture local
## `int`s by value**, so a counter closure over one never increments and every "expected 0"
## assertion built on it passes vacuously. Every counter here is an `Array` — a reference type —
## and each is shown non-empty at least once before any zero is claimed of it.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_gentle_displacement.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

## Comfortably past the grace window in one call.
const PAST_WINDOW: float = SettlementWindow.GRACE_WINDOW_SECONDS + 1.0

## Section 7's veto sweep. gdd.md rejects "blocking the build" outright as a fail state, so none
## of these may name anything on the row 10 surface.
const VETO_WORDS: PackedStringArray = [
	"block", "cancel", "confirm", "deny", "refuse", "reject", "veto", "abort", "forbid",
]

## The villager habitat for the real-world sections. 20+ tiles from anything else so no other
## neighbourhood can overlap it (both radii are 8, so a shared tile would need them within 16).
const HOUSE_TILE := Vector2i(28, 28)
const FIELD_TILE := Vector2i(29, 28)
const SECOND_FIELD := Vector2i(29, 27)
const SPARE_HOUSE := Vector2i(26, 28)

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false

## Real-world signal logs. Arrays, never ints — see the lambda note above.
var _warnings: Array[Dictionary] = []
var _events: Array[String] = []
var _departed: Array[Dictionary] = []
var _relocated: Array[Dictionary] = []


func _init() -> void:
	begin("gentle displacement")

	_check_the_trigger_is_exact()
	_check_the_trigger_includes_falling_to_zero()
	_check_mode_agnostic_in_the_simulation()
	_check_one_warning_summarises_every_affected_home()
	_check_warning_first_consequence_after_and_never_suppressed()
	_check_arrival_extends_to_a_competing_neighbour()
	_check_relocation_is_preferred_and_its_destination_rule()
	_check_species_hosted_is_permanent()
	_check_there_is_no_fail_state_on_the_surface()


func _initialize() -> void:
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads (the real-world fixture)" % WORLD_PATH):
		_finish_with_pendings()
		return
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		_finish_with_pendings()
		return
	_world = node as WorldRoot
	_world.displacement_warned.connect(func(w: Dictionary) -> void:
		_warnings.append(w)
		_events.append("warned"))
	_world.resident_departed.connect(
		func(sid: String, home: Vector2i, individuals: int, at: Vector3) -> void:
			_departed.append({"species_id": sid, "home": home, "individuals": individuals, "at": at})
			_events.append("departed"))
	_world.resident_relocated.connect(
		func(sid: String, from: Vector2i, to: Vector2i, at: Vector3) -> void:
			_relocated.append({"species_id": sid, "from": from, "to": to, "at": at})
			_events.append("relocated"))
	root.add_child(_world)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	_check_the_villager_moves_in()
	_check_all_three_edit_modes_arm_the_window_through_the_public_api()
	_check_removing_an_occupied_house_is_allowed_and_gentle()
	_check_rebuilding_after_a_departure_lets_the_species_return()

	_finish_with_pendings()
	return true


func _finish_with_pendings() -> void:
	note_expected_pending(
		"THE WARNING'S PLAYER-FACING COPY IS NOT WRITTEN — `copy_key`s only",
		"gdd.md decides the villager-displacement VOICE in the document (\"a displaced villager "
		+ "family is never described as losing a home, only as finding one\"; the copy may never "
		+ "put the player's action and the family's hardship in one sentence). What exists today "
		+ "is the closed key set — `displacement.warn.relocate` / `.depart` / `.depart.structure` "
		+ "— and `is_structure_home`, which selects the villager voice structurally with nothing "
		+ "special-casing a species. The English is content-writer's, and the tonal rules above "
		+ "are NOT machine-checkable: they are a human read at step 8."
	)
	note_expected_pending(
		"THE READ-ALOUD SLICE is asserted as a payload flag, not as a voice",
		"gdd.md: \"The warning carries the Read-Aloud emoji slice — consent must not require "
		+ "fluent reading.\" `warning[\"read_aloud\"]` is asserted true here. That a voice "
		+ "actually speaks the warning is `ReadAloud`'s, is unavailable headlessly, and is a "
		+ "human check on a real desktop."
	)
	note_expected_pending(
		"NO SHIPPED-CONTENT BUILD DISPLACEMENT EXISTS TO DRIVE (reported, not a defect)",
		"Mode-agnosticism is asserted three ways: behaviourally in the synthetic fixture (a "
		+ "building placed over cover, and a tag-emitting building removed), structurally on "
		+ "`GentleDisplacement.on_edit(tile)`, and through all three public `WorldRoot` entry "
		+ "points arming the window. What the FLOOR CONTENT cannot produce is a *build* that "
		+ "displaces: the only placeable is the House, `allowed_terrain = [\"grass\"]`, so it can "
		+ "never be put on the rock or field a resident depends on. That is a content limit, not "
		+ "a code one, and it disappears the moment a second placeable ships."
	)
	note_expected_pending(
		"WHETHER THE WARNING READS AS GENTLE TO A SIX-YEAR-OLD IS NOT A MACHINE CHECK",
		"This suite proves the trigger, the ordering, the outcomes and the absence of a fail "
		+ "state. \"Disclosure, not deterrence ... no plea, no judgment, no residue afterward\" "
		+ "is a step-5 kid-playtest judgment and nothing here substitutes for it."
	)
	finish()


# --- 1. The trigger is exact -------------------------------------------------------------------
# "an action warns iff, once its neighbourhood settles, `capacity(h, S)` would fall below
# `population(h, S)` for any home site in range". STRICT, with no margin. A standing tolerance
# margin is Open Question #25, explicitly not v1.

func _check_the_trigger_is_exact() -> void:
	# Population fixed at 2; capacity swept by leaving `remaining` cover tiles behind.
	# capacity == floor(remaining / 4).
	var cases: Array[Dictionary] = [
		{"remaining": 12, "capacity": 3, "warn": false, "why": "capacity ABOVE population"},
		{"remaining": 11, "capacity": 2, "warn": false, "why": "capacity EQUALS population (THE BOUNDARY)"},
		{"remaining": 8, "capacity": 2, "warn": false, "why": "capacity EQUALS population, exactly divisible"},
		{"remaining": 7, "capacity": 1, "warn": true, "why": "capacity ONE BELOW population"},
		{"remaining": 4, "capacity": 1, "warn": true, "why": "capacity one below, exactly divisible"},
		{"remaining": 3, "capacity": 0, "warn": true, "why": "capacity 0 with residents present"},
		{"remaining": 0, "capacity": 0, "warn": true, "why": "every qualifying tile gone"},
	]

	var mismatches: PackedStringArray = PackedStringArray()
	var warned_count: int = 0
	var quiet_count: int = 0
	for c: Dictionary in cases:
		var result: Dictionary = _trigger_probe(int(c["remaining"]), 2)
		var label: String = "%d cover tiles -> capacity %d vs population 2 (%s)" % [
			c["remaining"], result["capacity"], c["why"]
		]
		if int(result["capacity"]) != int(c["capacity"]):
			mismatches.append("%s: capacity was %d, expected %d"
				% [label, result["capacity"], c["capacity"]])
		if bool(result["warned"]) != bool(c["warn"]):
			mismatches.append("%s: warned=%s, expected %s"
				% [label, result["warned"], c["warn"]])
		if bool(result["warned"]):
			warned_count += 1
		else:
			quiet_count += 1
		check_eq(bool(result["warned"]), bool(c["warn"]),
			"%s -> %s" % [label, "WARNS" if bool(c["warn"]) else "silent"])

	check(mismatches.is_empty(),
		"THE TRIGGER IS `capacity < population`, STRICT: warn IFF, across all %d swept cases"
			% cases.size(),
		"mismatches: %s" % str(mismatches))

	# NON-VACUITY, both directions. A machine that never warns, or one that always warns, would
	# each pass roughly half the sweep — so both halves are asserted to be non-empty.
	check(warned_count > 0 and quiet_count > 0,
		"NON-VACUITY: the sweep produced BOTH outcomes (%d warned, %d silent) — it is not a "
			% [warned_count, quiet_count]
		+ "machine stuck on one answer")

	# The boundary, stated once more on its own because it is the assertion an implementation
	# that used `<=` instead of `<` would fail and nothing else would catch.
	var at_boundary: Dictionary = _trigger_probe(8, 2)
	check_eq(int(at_boundary["capacity"]), 2, "AT THE BOUNDARY: capacity is exactly 2")
	check_eq(bool(at_boundary["warned"]), false,
		"...and `capacity == population` does NOT warn — the inequality is strict, and a "
		+ "tolerance margin is #25 and is explicitly not v1")
	var one_below: Dictionary = _trigger_probe(7, 2)
	check_eq(int(one_below["capacity"]), 1, "ONE TILE FURTHER: capacity is 1")
	check_eq(bool(one_below["warned"]), true,
		"...and ONE below population DOES warn — the boundary is where the document puts it")


func _check_the_trigger_includes_falling_to_zero() -> void:
	# "including to 0" is called out in gdd.md because 0 is where an implementation is most
	# tempted to treat the neighbourhood as invalid rather than as unsuitable.
	var f: Dictionary = _fixture()
	var displacement: GentleDisplacement = f["displacement"]
	var sim: HabitatSimulation = f["sim"]
	var home := Vector2i(10, 10)

	var warnings: Array[Dictionary] = []
	displacement.displacement_warned.connect(func(w: Dictionary) -> void: warnings.append(w))

	_lay_cover(f, home, 4)
	var site: HomeSite = _settle(f, home, f["species"], 1)
	for i in 4:
		_edit(f, Vector2i(10 + i, 10), "grass")

	check_eq(sim.capacity_at(home, f["species"]), 0, "capacity fell all the way to 0")
	displacement.tick(PAST_WINDOW)

	check_eq(warnings.size(), 1, "FALLING TO 0 WARNS — 0 is an ordinary capacity, not an error")
	var homes: Array = warnings[0]["homes"]
	check_eq(int(homes[0]["capacity"]), 0, "...and the warning reports capacity 0 verbatim")
	check_eq(int(homes[0]["population"]), 1, "...against a population of 1")
	check_eq(site.population(), 0, "...and the whole household is displaced")
	check_eq(bool(warnings[0]["read_aloud"]), true,
		"...and the warning carries the Read-Aloud slice (row 10 ships it)")

	_teardown(f)


# --- 2. Mode-agnostic ---------------------------------------------------------------------------
# "before any action whose settled effect would displace a resident — terraform, build, or
# removal alike, the warning being **mode-agnostic**". The likeliest displacement in the floor is
# a TERRAFORM (clearing the field beside a House), not a build.

func _check_mode_agnostic_in_the_simulation() -> void:
	var outcomes: Array[String] = []

	# (a) TERRAFORM — a cover tile painted away.
	var terraform: Dictionary = _fixture()
	_lay_cover(terraform, Vector2i(10, 10), 8)
	var t_site: HomeSite = _settle(terraform, Vector2i(10, 10), terraform["species"], 2)
	_edit(terraform, Vector2i(17, 10), "grass")
	(terraform["displacement"] as GentleDisplacement).tick(PAST_WINDOW)
	check_eq((terraform["displacement"] as GentleDisplacement).warnings_raised, 1,
		"TERRAFORM displaces and warns")
	check(t_site.population() < 2, "...and the consequence ran")
	if (terraform["displacement"] as GentleDisplacement).warnings_raised == 1:
		outcomes.append("terraform")
	_teardown(terraform)

	# (b) BUILD — a building put down ON cover tiles, suppressing their tags.
	var build: Dictionary = _fixture()
	_lay_cover(build, Vector2i(10, 10), 8)
	var b_site: HomeSite = _settle(build, Vector2i(10, 10), build["species"], 2)
	var wall := _synthetic_placeable("wall", ["house"] as Array[String])
	for i in 2:
		var origin := Vector2i(16 + i, 10)
		(build["grid"] as WorldGrid).set_building(origin, wall)
		(build["sim"] as HabitatSimulation).on_building_changed(origin)
		(build["displacement"] as GentleDisplacement).on_edit(origin)
	check_eq((build["sim"] as HabitatSimulation).capacity_at(Vector2i(10, 10), build["species"]), 1,
		"a building over 2 cover tiles suppresses their tags: capacity 2 -> 1")
	(build["displacement"] as GentleDisplacement).tick(PAST_WINDOW)
	check_eq((build["displacement"] as GentleDisplacement).warnings_raised, 1,
		"BUILD displaces and warns — the same flow, with nothing told it was a build")
	check(b_site.population() < 2, "...and the consequence ran")
	if (build["displacement"] as GentleDisplacement).warnings_raised == 1:
		outcomes.append("build")
	_teardown(build)

	# (c) REMOVAL — a tag-EMITTING building taken down.
	var removal: Dictionary = _fixture()
	var shelter := _synthetic_placeable("shelter", ["cover"] as Array[String])
	_lay_cover(removal, Vector2i(10, 10), 4)                       # 4 cover tiles from terrain
	for i in 4:                                                     # + 4 from buildings = 8
		(removal["grid"] as WorldGrid).set_building(Vector2i(10 + i, 11), shelter)
	var r_site: HomeSite = _settle(removal, Vector2i(10, 10), removal["species"], 2)
	check_eq((removal["sim"] as HabitatSimulation).capacity_at(Vector2i(10, 10), removal["species"]), 2,
		"4 terrain cover tiles + 4 building cover tiles support 2")
	var gone := Vector2i(13, 11)
	(removal["grid"] as WorldGrid).clear_building(gone)
	(removal["sim"] as HabitatSimulation).on_building_changed(gone)
	(removal["displacement"] as GentleDisplacement).on_edit(gone)
	check_eq((removal["sim"] as HabitatSimulation).capacity_at(Vector2i(10, 10), removal["species"]), 1,
		"removing one of them drops capacity 2 -> 1")
	(removal["displacement"] as GentleDisplacement).tick(PAST_WINDOW)
	check_eq((removal["displacement"] as GentleDisplacement).warnings_raised, 1,
		"REMOVAL displaces and warns — removal is not a special case, it is the third mode")
	check(r_site.population() < 2, "...and the consequence ran")
	if (removal["displacement"] as GentleDisplacement).warnings_raised == 1:
		outcomes.append("removal")
	_teardown(removal)

	check_eq(outcomes, ["terraform", "build", "removal"] as Array[String],
		"MODE-AGNOSTIC: all three edit modes produced the identical warned displacement")

	# STRUCTURAL: the entry point cannot know which mode it was, because it is not told.
	var displacement := GentleDisplacement.new()
	var on_edit_args: Array = []
	for entry: Dictionary in displacement.get_script().get_script_method_list():
		if entry["name"] == "on_edit":
			on_edit_args = entry["args"]
	check_eq(on_edit_args.size(), 1,
		"`GentleDisplacement.on_edit()` takes exactly ONE argument — there is no mode parameter "
		+ "to branch on, so mode-agnosticism is structural rather than remembered")
	if on_edit_args.size() == 1:
		check_eq(int((on_edit_args[0] as Dictionary)["type"]), TYPE_VECTOR2I,
			"...and that argument is a tile (Vector2i), which is all an edit is to this class")
	displacement.free()


# --- 3. One warning per settled gesture, summarising every affected home ------------------------

func _check_one_warning_summarises_every_affected_home() -> void:
	# Three overlapping home sites, TWO species, each with exactly one cover tile of its own and
	# exactly one resident. One burst of taps takes all three tiles away.
	#
	# CAPACITY_RADIUS IS DELIBERATELY NARROWED, SEPARATELY FROM `scout_radius` (2026-08-17):
	# home-site exclusivity is now SCOPED per species (a Fox den and a Rabbit warren no longer
	# split the same land — see `home_site_registry.gd`'s header). `critter` (A, B) and `grazer`
	# (C) are different species, so they no longer compete for tiles AT ALL: each independently
	# counts everything within its OWN reach. With every home's `scout_radius` a generous 8 (so
	# the gesture-merge geometry below still holds — see `_reach_could_overlap()` /
	# `sites_covering()`, which are pure radius checks, unrelated to exclusivity), all three
	# tiles below sit inside every home's `scout_radius`, so an ungated `capacity_radius` would
	# let each site freely count the OTHER homes' tiles too, breaking the "exactly one resident"
	# boundary this check is built on. Narrowing `capacity_radius` (independent of
	# `scout_radius` by contract — animal_definition.gd) keeps each site's ACREAGE tight around
	# its own tile without touching the reach that makes the taps merge into one gesture.
	var f: Dictionary = _two_species_fixture()
	var displacement: GentleDisplacement = f["displacement"]
	var grid: WorldGrid = f["grid"]
	var critter: AnimalDefinition = f["critter"]
	var grazer: AnimalDefinition = f["grazer"]
	critter.capacity_radius = 2
	grazer.capacity_radius = 3

	var warnings: Array[Dictionary] = []
	displacement.displacement_warned.connect(func(w: Dictionary) -> void: warnings.append(w))

	var a_tile := Vector2i(11, 11)
	var b_tile := Vector2i(13, 11)
	var c_tile := Vector2i(12, 12)
	grid.set_terrain(a_tile.x, a_tile.y, "rock")
	grid.set_terrain(b_tile.x, b_tile.y, "rock")
	grid.set_terrain(c_tile.x, c_tile.y, "rock")

	var a: HomeSite = _settle(f, Vector2i(10, 10), critter, 1)
	var b: HomeSite = _settle(f, Vector2i(14, 10), critter, 1)
	var c: HomeSite = _settle(f, Vector2i(12, 14), grazer, 1)

	var sim: HabitatSimulation = f["sim"]
	check_eq(sim.capacity_at(a.position, critter), 1, "home A supports its one resident")
	check_eq(sim.capacity_at(b.position, critter), 1, "home B supports its one resident")
	check_eq(sim.capacity_at(c.position, grazer), 1, "home C supports its one resident")

	# THE BURST. Every tapped tile lies inside all three homes' `scout_radius`, so all three
	# neighbourhoods join one gesture — which is what "warns once and reverts as one gesture"
	# means. (Gesture membership is geometry-only, via `scout_radius` / `sites_covering()`, and
	# does not depend on the narrower `capacity_radius` acreage each site is now counting.)
	for tile: Vector2i in [a_tile, b_tile, c_tile]:
		_edit(f, tile, "grass")
	check_eq(displacement.pending_gestures(), 1,
		"three taps across three overlapping neighbourhoods merged into ONE gesture")

	displacement.tick(PAST_WINDOW)

	check_eq(warnings.size(), 1,
		"ONE WARNING, not one per home and not one per tile — frequency is bounded by settlement")
	var warning: Dictionary = warnings[0]
	var homes: Array = warning["homes"]
	check_eq(homes.size(), 3,
		"...and it SUMMARISES all three affected homes in a single payload")

	var named: Array[Vector2i] = []
	var capacity_ok: bool = true
	for home: Dictionary in homes:
		named.append(home["home_tile"] as Vector2i)
		if int(home["capacity"]) >= int(home["population"]):
			capacity_ok = false
	check(named.has(a.position) and named.has(b.position) and named.has(c.position),
		"...naming every one of them: %s" % str(named))
	check(capacity_ok,
		"...and EVERY entry really satisfies the trigger (capacity < population)")

	check_eq(warning["species_ids"], ["critter", "grazer"] as Array[String],
		"...with the distinct species listed once each, in first-affected order")
	check_eq(displacement.settlements_resolved, 1, "one settlement produced all of it")
	check_eq(displacement.departures, 3, "...and all three consequences ran off that one warning")

	# NON-VACUITY: two homes were the SAME species, so a `species_ids` that simply echoed the
	# homes list would have three entries, not two.
	check_eq(homes.size() - (warning["species_ids"] as Array).size(), 1,
		"NON-VACUITY: 3 homes but 2 species ids — the list is genuinely de-duplicated")

	_teardown(f)


# --- 4. Warning first, consequence after, and never suppressed ----------------------------------

func _check_warning_first_consequence_after_and_never_suppressed() -> void:
	var f: Dictionary = _fixture()
	var displacement: GentleDisplacement = f["displacement"]
	var home := Vector2i(10, 10)

	# ONE shared log for all three signals, so the ORDER is the thing being recorded and not
	# three independently plausible counts. An Array, not an int — see the lambda note.
	var order: Array[String] = []
	displacement.displacement_warned.connect(func(_w: Dictionary) -> void: order.append("warned"))
	displacement.resident_departed.connect(
		func(_s: String, _t: Vector2i, _n: int, _p: Vector3) -> void: order.append("departed"))
	displacement.resident_relocated.connect(
		func(_s: String, _f: Vector2i, _t: Vector2i, _p: Vector3) -> void: order.append("relocated"))

	_lay_cover(f, home, 4)
	var site: HomeSite = _settle(f, home, f["species"], 1)
	for i in 4:
		_edit(f, Vector2i(10 + i, 10), "grass")
	displacement.tick(PAST_WINDOW)

	check_eq(order, ["warned", "departed"] as Array[String],
		"WARNING FIRST, ACTING AFTER: the warning is emitted before a single resident moves")
	check_eq(site.population(), 0, "...and the consequence really followed it")

	# NEVER SUPPRESSED, part 1: a second displacement in the same world warns again. There is no
	# "already told them" state anywhere.
	_lay_cover(f, home, 8)
	var second: HomeSite = _settle(f, home, f["species"], 2)
	for i in 8:
		_edit(f, Vector2i(10 + i, 10), "grass")
	displacement.tick(PAST_WINDOW)
	check_eq(order, ["warned", "departed", "warned", "departed"] as Array[String],
		"...and a SECOND displacement warns again — a warning is never suppressed because one "
		+ "was already shown, and the order holds every time")
	check_eq(second.population(), 0, "...with its own consequence following it")

	_teardown(f)

	# NEVER SUPPRESSED, part 2: **with nobody listening at all**, the consequence still runs.
	# gdd.md's rule is that a warning is never suppressed *while its consequence proceeds* — the
	# converse trap is an implementation that only acts when someone is connected.
	var deaf: Dictionary = _fixture()
	var deaf_displacement: GentleDisplacement = deaf["displacement"]
	check_eq(deaf_displacement.displacement_warned.get_connections().size(), 0,
		"NOBODY IS LISTENING to `displacement_warned` in this fixture")
	_lay_cover(deaf, Vector2i(10, 10), 4)
	var deaf_site: HomeSite = _settle(deaf, Vector2i(10, 10), deaf["species"], 1)
	for i in 4:
		_edit(deaf, Vector2i(10 + i, 10), "grass")
	deaf_displacement.tick(PAST_WINDOW)
	check_eq(deaf_displacement.warnings_raised, 1,
		"...the warning is still RAISED — emission does not depend on an audience")
	check_eq(deaf_site.population(), 0,
		"...and the consequence still proceeds, so the two are not gated on each other")
	_teardown(deaf)


# --- D-29 #5. The arrival check extends to a competing neighbour --------------------------------
# gdd.md's arrival predicate only ever asks whether the ARRIVING site still qualifies. Landing
# that arrival rebuilds the whole tile-exclusivity map, which can drop a NEIGHBOURING home site
# below its own population without anyone asking it. D-29 #5 ruled the fix: extend the arrival
# check to re-evaluate neighbours and arm Gentle Displacement for any it drops below population —
# reusing this same class's own `on_edit()` mechanism rather than a parallel one. **No existing
# suite drove `GentleDisplacement.on_arrival()` directly before this test** — the phenomenon was
# only ever visible as a `note_expected_pending()` in `test_causality_end_to_end.gd`, which reports
# the overshoot but asserts nothing about whether it is consumed. This is that assertion.
#
# THE REPRO, sized exactly to the mechanism `on_arrival()`'s own header describes: an 8-tile row
# of cover from (18,18) to (25,18) at the synthetic species' divisor of 4.
#   1. Site A registers at (18,18) with radius 8, the ONLY site — it owns the whole row (8 tiles,
#      capacity 2) and is settled at population 2. Correct: capacity == population, no warning.
#   2. Site B's tile at (24,18) is marked dirty and its arrival runs the real `HabitatSimulation`
#      path. As a PROSPECTIVE candidate B counts only the tiles STRICTLY NEARER to it than to A —
#      x = 22..25, four tiles, capacity 1 — so `capacity 1 >= population 0 + 1` lands it for real.
#   3. B's registration rebuilds ownership: A's own four tiles (18..21) are all A keeps, so A's
#      OWN capacity, read live, is now 1 against its population of 2 — over capacity by one, and
#      A was never asked.
func _check_arrival_extends_to_a_competing_neighbour() -> void:
	var f: Dictionary = _fixture()
	var sim: HabitatSimulation = f["sim"]
	var grid: WorldGrid = f["grid"]
	var registry: HomeSiteRegistry = f["registry"]
	var displacement: GentleDisplacement = f["displacement"]
	var species: AnimalDefinition = f["species"]

	# Mirrors `WorldRoot`'s own wiring (`world_root.gd`, `simulation.resident_arrived.connect(...)`
	# calling `displacement.on_arrival()`) — this fixture is synthetic and bypasses `WorldRoot`, so
	# the one line of coupling has to be reproduced here rather than assumed.
	sim.resident_arrived.connect(func(species_id: String, world_position: Vector3) -> void:
		displacement.on_arrival(grid.world_to_tile(world_position), species_id))

	var home_a := Vector2i(18, 18)
	var home_b := Vector2i(24, 18)
	_lay_cover(f, home_a, 8)  # (18,18) .. (25,18) — covers home_b's tile too

	var site_a: HomeSite = _settle(f, home_a, species, 2)
	check_eq(sim.capacity_at(home_a, species), 2,
		"SETUP: site A owns the whole 8-tile row alone — capacity 2, matching its population")
	check(displacement.is_idle(),
		"SETUP: nothing is armed yet — settling A directly does not touch `on_edit()`/`on_arrival()`")

	# Land B for real, through the simulation's own arrival path (not `_settle()`, which bypasses
	# signals) — this is what actually calls `on_resident_arrived()` -> `_mark_all_sites_dirty()`
	# and, via the connection above, `GentleDisplacement.on_arrival()`.
	sim.on_terraform(home_b)
	sim.tick(0.0)
	check(sim.arrivals().size() > 0, "B's tile qualifies as a prospective site and enqueues an arrival")
	sim.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)

	var site_b: HomeSite = registry.settled_site_at(home_b, species.id)
	if not check(site_b != null and site_b.population() == 1,
		"B REALLY LANDED: a second site registered at %s with population 1" % str(home_b)):
		_teardown(f)
		return
	check_eq(sim.capacity_at(home_b, species), 1,
		"...counting exactly the four tiles strictly nearer to it than to A (capacity 1)")

	# THE OVERSHOOT, confirmed live rather than assumed from the header's arithmetic.
	check_eq(sim.capacity_at(home_a, species), 1,
		"B's registration took A's four nearest tiles: A's OWN capacity is now 1")
	check_eq(site_a.population(), 2,
		"...against a population that never changed — A is over capacity by one, and was never "
		+ "consulted by B's own arrival predicate")

	# THE FIX. Landing B's arrival already armed A's window — before this suite ticks the clock
	# forward at all, and before anything has settled.
	check(not displacement.is_idle(),
		"D-29 #5: LANDING B'S ARRIVAL ALREADY ARMED A NEIGHBOUR'S SETTLEMENT WINDOW — not left "
		+ "silently over capacity")
	check_eq(displacement.pending_gestures(), 1, "...exactly one gesture pending, for A's neighbourhood")

	var warnings: Array[Dictionary] = []
	displacement.displacement_warned.connect(func(w: Dictionary) -> void: warnings.append(w))
	displacement.tick(PAST_WINDOW)

	check_eq(warnings.size(), 1, "THE ARMED WINDOW RESOLVES: one warning, once the window closes")
	if warnings.size() == 1:
		var homes: Array = warnings[0]["homes"]
		check_eq(homes.size(), 1, "...naming exactly one affected home")
		if homes.size() == 1:
			var described: Dictionary = homes[0]
			check_eq(described["home_tile"], home_a, "...which is A, the neighbour B's arrival stole from")
			check_eq(int(described["capacity"]), 1, "...capacity read live at settlement (1)")
			check_eq(int(described["population"]), 2, "...against A's real population (2)")
	check_eq(site_a.population(), 1,
		"THE OVERSHOOT IS RESOLVED, NOT JUST REPORTED: A sheds exactly its one excess resident "
		+ "(relocate takes the whole household; here capacity 1 supports a departure of the "
		+ "overflow, leaving population == capacity)")
	check(displacement.is_idle(), "...and the world is idle again once it settles")

	# B ITSELF IS UNTOUCHED. The neighbour that stole the tiles is not the one that pays for it —
	# only the site the theft actually left over capacity is affected.
	check_eq(site_b.population(), 1, "B keeps its own resident throughout — B was never over capacity")

	_teardown(f)


# --- 5. Relocation preferred; departure otherwise -----------------------------------------------
# "Two gentle outcomes, **in order: relocation** if a suitable spot exists (`capacity >=
# population` there), the animal visibly moving its home; otherwise **moving away**."

func _check_relocation_is_preferred_and_its_destination_rule() -> void:
	# THE DESTINATION RULE'S BOUNDARY. Population 2; a distant patch that is out of the home's
	# own radius but inside the relocation search, sized to support exactly 2, then exactly 1.
	var supported: Dictionary = _relocation_probe(8, 2)     # 8 tiles / 4 -> capacity 2 == population
	check_eq(supported["outcome"], GentleDisplacement.OUTCOME_RELOCATE,
		"RELOCATION IS PREFERRED: a spot where `capacity == population` takes the family")
	check_eq(int(supported["relocations"]), 1, "...`resident_relocated` fired once")
	check_eq(int(supported["departures"]), 0, "...and nobody departed")
	check_eq(int(supported["population_after"]), 2,
		"...the whole household moved — a relocation loses nobody")
	check(supported["moved_to"] != supported["moved_from"],
		"...and the home really is somewhere else now (%s -> %s)"
			% [supported["moved_from"], supported["moved_to"]])
	check(int(supported["destination_capacity"]) >= 2,
		"...at a destination that genuinely supports the whole family (capacity %d >= 2)"
			% int(supported["destination_capacity"]))

	# ONE TILE SHORT of the destination rule, and the outcome flips. This is the assertion that
	# makes `>=` mean `>=`: an implementation that relocated anywhere would pass the case above.
	var short: Dictionary = _relocation_probe(7, 2)         # 7 tiles / 4 -> capacity 1 < population
	check_eq(short["outcome"], GentleDisplacement.OUTCOME_DEPART,
		"NEGATIVE CONTROL: one tile short of supporting the family, the SAME world departs "
		+ "instead — `capacity >= population` at the destination is a real gate")
	check_eq(int(short["relocations"]), 0, "...nobody relocated")
	check_eq(int(short["departures"]), 1, "...`resident_departed` fired once")
	check_eq(int(short["population_after"]), 0, "...and the household left")

	# NO SUITABLE SPOT AT ALL -> departure, which is the other branch of "otherwise".
	var nowhere: Dictionary = _relocation_probe(0, 2)
	check_eq(nowhere["outcome"], GentleDisplacement.OUTCOME_DEPART,
		"with nowhere in the world to go, the family moves away — the second gentle outcome")
	check_eq(int(nowhere["departures"]), 1, "...departing exactly once, for the whole home")

	# The copy key the content pass fills is selected, and it is one of the closed set.
	var keys: Array[String] = [
		GentleDisplacement.COPY_KEY_RELOCATE,
		GentleDisplacement.COPY_KEY_DEPART,
		GentleDisplacement.COPY_KEY_DEPART_STRUCTURE,
	]
	check(keys.has(supported["copy_key"] as String),
		"the relocation warning carries a copy key from the closed set (%s)" % supported["copy_key"])
	check_eq(supported["copy_key"], GentleDisplacement.COPY_KEY_RELOCATE,
		"...and it is the relocate key")
	check_eq(short["copy_key"], GentleDisplacement.COPY_KEY_DEPART,
		"...while the departure carries the depart key — a den, not a structure")


# --- 6. Species Hosted is permanent -------------------------------------------------------------
# "Species Hosted and the Field Guide entry stay permanent", and gdd.md -> Economy: "Species
# Hosted (all-time, never decreases)".

func _check_species_hosted_is_permanent() -> void:
	var f: Dictionary = _fixture()
	var displacement: GentleDisplacement = f["displacement"]
	var registry: HomeSiteRegistry = f["registry"]
	var home := Vector2i(10, 10)

	check_eq(registry.species_hosted_count(), 0, "a fresh world has hosted nobody")

	_lay_cover(f, home, 4)
	var site: HomeSite = _settle(f, home, f["species"], 1)
	check_eq(registry.species_hosted_ids(), ["critter"] as Array[String],
		"settling records the species as hosted")
	check_eq(registry.resident_species_ids(), ["critter"] as Array[String],
		"...and as currently resident")

	for i in 4:
		_edit(f, Vector2i(10 + i, 10), "grass")
	displacement.tick(PAST_WINDOW)

	# THE CONTROL FIRST: the departure really happened, so the permanence below is not the
	# permanence of a thing that never changed.
	check_eq(site.population(), 0, "the family departed")
	check_eq(registry.total_residents(), 0, "...the world has no residents left")
	check_eq(registry.resident_species_ids(), [] as Array[String],
		"...and `resident_species_ids()` (the CURRENT counter) correctly dropped it")
	check(registry.is_empty(), "...and the emptied home site left the registry")

	# THE PERMANENCE.
	check_eq(registry.species_hosted_ids(), ["critter"] as Array[String],
		"SPECIES HOSTED IS PERMANENT: the all-time record survives the departure intact")
	check_eq(registry.species_hosted_count(), 1, "...and the all-time count did not decrease")

	# Enforced by there being no path that erases one, rather than by a rule someone remembers.
	var erasers: PackedStringArray = PackedStringArray()
	var registry_source: String = _strip_comments(
		load("res://scripts/simulation/home_site_registry.gd").source_code)
	for line: String in registry_source.split("\n"):
		if line.contains("_ever_hosted") and (line.contains("erase") or line.contains("clear")):
			erasers.append(line.strip_edges())
	check(erasers.is_empty(),
		"...and `HomeSiteRegistry` contains no line that erases or clears `_ever_hosted` at all",
		"found: %s" % str(erasers))
	check(registry_source.contains("_ever_hosted"),
		"...while the same stripped source DOES mention `_ever_hosted`, so the absence above is "
		+ "a measurement rather than an empty search")

	_teardown(f)


# --- 7. No fail state --------------------------------------------------------------------------
# gdd.md rejects **blocking the build** outright: "it is a fail state". Disclosure, not deterrence.

func _check_there_is_no_fail_state_on_the_surface() -> void:
	var displacement := GentleDisplacement.new()

	var signals: Array[String] = []
	for entry: Dictionary in displacement.get_script().get_script_signal_list():
		signals.append(entry["name"])
	signals.sort()
	check_eq(signals,
		["displacement_warned", "resident_departed", "resident_relocated"] as Array[String],
		"row 10's whole signal surface is three signals — a warning and two things that "
		+ "HAPPENED. None of them is an error or refusal channel")

	var methods: Array[String] = []
	for entry: Dictionary in displacement.get_script().get_script_method_list():
		methods.append(entry["name"])
	var veto_methods: PackedStringArray = PackedStringArray()
	for name: String in methods:
		for word: String in VETO_WORDS:
			if name.to_lower().contains(word):
				veto_methods.append(name)
	check(veto_methods.is_empty(),
		"...and nothing on it can veto an edit (no block/cancel/confirm/deny/refuse/reject)",
		"found: %s" % str(veto_methods))
	# NON-VACUITY: the method list really is populated, so the absence above is a measurement.
	check(methods.has("on_edit") and methods.has("tick"),
		"...and that method list really enumerates the class (%d methods), so the sweep above "
			% methods.size()
		+ "searched something")

	# There is no threshold constant either. A "warning threshold" would be #25 shipped early.
	var constants: Array[String] = []
	for key: Variant in displacement.get_script().get_script_constant_map().keys():
		constants.append(key as String)
	constants.sort()
	check_eq(constants, [
		"COPY_KEY_DEPART", "COPY_KEY_DEPART_STRUCTURE", "COPY_KEY_RELOCATE",
		"MAX_SETTLEMENTS_PER_TICK", "OUTCOME_DEPART", "OUTCOME_RELOCATE",
		"RELOCATION_SEARCH_RADIUS_TILES", "SETTLEMENT_DRAIN_INTERVAL_SECONDS",
	] as Array[String],
		"row 10 declares no tolerance/threshold constant — a standing margin is #25 and is "
		+ "explicitly not v1 (MAX_SETTLEMENTS_PER_TICK and SETTLEMENT_DRAIN_INTERVAL_SECONDS "
		+ "are a per-tick work budget and its throttle, unrelated to the capacity >= population "
		+ "trigger condition #25 guards)")

	displacement.free()

	# And the same for the public surface the UI sees: no accept/reject channel back in.
	var world_methods: PackedStringArray = PackedStringArray()
	for entry: Dictionary in load("res://scripts/world/world_root.gd").get_script_method_list():
		var name: String = entry["name"]
		for word: String in VETO_WORDS:
			if name.to_lower().contains(word):
				world_methods.append(name)
	check(world_methods.is_empty(),
		"`WorldRoot` offers the UI no way to accept or reject a displacement either — the "
		+ "warning is disclosure, and the undo path is the ordinary one every edit has",
		"found: %s" % str(world_methods))


# --- The real world: a villager family, which is the floor's likeliest displacement --------------

func _check_the_villager_moves_in() -> void:
	check_eq(_world.total_residents(), 0, "the real world starts with nobody in it")

	# RE-POINTED (-> D-29 #1, `WorldGrid.START_TERRAIN_ID` "grass" -> "wild_grass"): the House's
	# `allowed_terrain` is `["grass"]` specifically (buildings.md), and `HOUSE_TILE`/`SPARE_HOUSE`
	# now start as `wild_grass` under the new default, not `grass`. Painted explicitly, free.
	_world.paint_tile(HOUSE_TILE.x, HOUSE_TILE.y, "grass")
	_world.paint_tile(SPARE_HOUSE.x, SPARE_HOUSE.y, "grass")
	check(_world.place_building(HOUSE_TILE.x, HOUSE_TILE.y, "house"), "a House is built")
	check(_world.paint_tile(FIELD_TILE.x, FIELD_TILE.y, "cultivated_field"),
		"...with a field beside it")
	check_eq(_world.capacity_at(HOUSE_TILE.x, HOUSE_TILE.y, "human"), 1,
		"the habitat supports one villager family")

	for _i in 60:
		_world.simulation.tick(0.0)
	_world.simulation.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)

	check_eq(_world.population_at(HOUSE_TILE.x, HOUSE_TILE.y, "human"), 1,
		"a villager family moved in — the fixture the rest of this section needs")
	check_eq(_world.species_hosted_ids(), ["human"] as Array[String],
		"...and Species Hosted records it")

	# The window opened by the habitat-building edits settles harmlessly first: capacity equals
	# population, so nothing is displaced, and the phases below start from a clean slate.
	_world.displacement.tick(PAST_WINDOW)
	check(_warnings.is_empty(),
		"building the habitat displaced nobody (capacity == population, the boundary again)")
	check(_world.displacement.is_idle(), "...and no gesture is left pending")


func _check_all_three_edit_modes_arm_the_window_through_the_public_api() -> void:
	# gdd.md requires the warning to be mode-agnostic. On `WorldRoot` that is the claim that all
	# three public edit entry points hand the same tile to the same place — asserted by watching
	# the settlement clock reset from each of them in turn.
	var armed: Array[String] = []

	check(_world.paint_tile(SECOND_FIELD.x, SECOND_FIELD.y, "cultivated_field"),
		"TERRAFORM through `paint_tile()` inside the family's neighbourhood")
	if _world.settlement_seconds_remaining(HOUSE_TILE.x, HOUSE_TILE.y) > 0.0:
		armed.append("paint_tile")
	check(is_equal_approx(
			_world.settlement_seconds_remaining(HOUSE_TILE.x, HOUSE_TILE.y),
			SettlementWindow.GRACE_WINDOW_SECONDS),
		"...armed the neighbourhood's window to a full %.0f s"
			% SettlementWindow.GRACE_WINDOW_SECONDS)

	_world.displacement.tick(5.0)
	check(_world.settlement_seconds_remaining(HOUSE_TILE.x, HOUSE_TILE.y)
			< SettlementWindow.GRACE_WINDOW_SECONDS,
		"...the clock is running down (%.1f s left)"
			% _world.settlement_seconds_remaining(HOUSE_TILE.x, HOUSE_TILE.y))

	check(_world.place_building(SPARE_HOUSE.x, SPARE_HOUSE.y, "house"),
		"BUILD through `place_building()` inside the same neighbourhood")
	if is_equal_approx(
			_world.settlement_seconds_remaining(HOUSE_TILE.x, HOUSE_TILE.y),
			SettlementWindow.GRACE_WINDOW_SECONDS):
		armed.append("place_building")
	check(is_equal_approx(
			_world.settlement_seconds_remaining(HOUSE_TILE.x, HOUSE_TILE.y),
			SettlementWindow.GRACE_WINDOW_SECONDS),
		"...RESTARTED the same window to a full %.0f s"
			% SettlementWindow.GRACE_WINDOW_SECONDS)

	_world.displacement.tick(5.0)
	check(_world.remove_at(SPARE_HOUSE.x, SPARE_HOUSE.y),
		"REMOVAL through `remove_at()` inside the same neighbourhood")
	if is_equal_approx(
			_world.settlement_seconds_remaining(HOUSE_TILE.x, HOUSE_TILE.y),
			SettlementWindow.GRACE_WINDOW_SECONDS):
		armed.append("remove_at")
	check(is_equal_approx(
			_world.settlement_seconds_remaining(HOUSE_TILE.x, HOUSE_TILE.y),
			SettlementWindow.GRACE_WINDOW_SECONDS),
		"...restarted it once more")

	check_eq(armed, ["paint_tile", "place_building", "remove_at"] as Array[String],
		"MODE-AGNOSTIC ON THE SHIPPED API: all three public edit entry points arm the same "
		+ "neighbourhood's window, and nothing downstream is told which one it was")

	# NON-VACUITY: a tile with no occupied neighbourhood over it arms nothing, so the readings
	# above are the edits' doing and not a clock that is always full.
	check_eq(_world.settlement_seconds_remaining(2, 2), -1.0,
		"NON-VACUITY: a tile nobody lives near reports no pending settlement at all")

	# None of this displaced anybody — capacity is still 1 against a population of 1.
	_world.displacement.tick(PAST_WINDOW)
	check(_warnings.is_empty(), "...and none of the three edits displaced the family")


func _check_removing_an_occupied_house_is_allowed_and_gentle() -> void:
	check_eq(_world.population_at(HOUSE_TILE.x, HOUSE_TILE.y, "human"), 1,
		"the family is still in its House")
	check(_world.can_remove(HOUSE_TILE.x, HOUSE_TILE.y),
		"`can_remove()` says yes on an OCCUPIED House — the game does not pre-refuse")

	# NO FAIL STATE. gdd.md: "Removing a House with a family in it is allowed — that is exactly
	# the case Gentle Displacement exists for, and refusing it would be a fail state."
	check(_world.remove_at(HOUSE_TILE.x, HOUSE_TILE.y),
		"NOT BLOCKED: removing an occupied House SUCCEEDS")
	check(not _world.grid.is_occupied(HOUSE_TILE.x, HOUSE_TILE.y),
		"...the House really came down")
	check_eq(_world.population_at(HOUSE_TILE.x, HOUSE_TILE.y, "human"), 1,
		"...and the family is still there, because only the irreversible half waits")
	check(_warnings.is_empty(), "...with no warning yet — the window is open and this is undoable")

	_world.displacement.tick(PAST_WINDOW)

	check_eq(_warnings.size(), 1, "ONE warning for the settled gesture")
	check_eq(_events, ["warned", "departed"] as Array[String],
		"WARNING FIRST, DEPARTURE AFTER — on the real signal surface the UI binds to")

	var warning: Dictionary = _warnings[0]
	check_eq(bool(warning["read_aloud"]), true,
		"the warning carries the Read-Aloud slice — consent must not require fluent reading")
	check_eq(warning["species_ids"], ["human"] as Array[String], "...and names the species")
	var homes: Array = warning["homes"]
	check_eq(homes.size(), 1, "...summarising the one affected home")
	var home: Dictionary = homes[0]
	check_eq(home["home_tile"], HOUSE_TILE, "...at the House's tile")
	check_eq(home["species_id"], "human", "...species_id `human`")
	check_eq(home["display_name"], "Villager",
		"...carrying the roster's own `display_name`, which is data and not copy")
	check_eq(bool(home["is_structure_home"]), true,
		"...flagged `is_structure_home`, which is how gdd.md's DECIDED villager-displacement "
		+ "voice is selected without anything special-casing a species")
	check_eq(int(home["capacity"]), 0, "...capacity 0 (the House was the whole `house` supply)")
	check_eq(int(home["population"]), 1, "...against a population of 1")
	check_eq(home["outcome"], GentleDisplacement.OUTCOME_DEPART,
		"...departing, because a structure home can only relocate into another empty House and "
		+ "there is none — gdd.md calls this the floor's likeliest displacement")
	check_eq(home["copy_key"], GentleDisplacement.COPY_KEY_DEPART_STRUCTURE,
		"...with the structure-departure copy key, so content-writer knows which line to fill")
	check_eq(int(home["individuals"]), 1, "...one family leaving")

	check_eq(_departed.size(), 1, "`resident_departed` fired once")
	check_eq((_departed[0] as Dictionary)["species_id"], "human", "...for the villager")
	check_eq(_relocated.size(), 0, "...and nobody relocated")

	check_eq(_world.total_residents(), 0, "the world has no residents left")
	check_eq(_world.resident_species_ids(), [] as Array[String],
		"...and the CURRENT counter dropped the villager")
	check_eq(_world.species_hosted_ids(), ["human"] as Array[String],
		"SPECIES HOSTED IS PERMANENT: the all-time record survives on the real public API")
	check_eq(_world.species_hosted_count(), 1, "...and the all-time count did not decrease")

	# NO RESIDUE: the world is quiet again, and nothing is pending.
	check(_world.displacement.is_idle(), "no gesture is left pending afterwards")
	check_eq(_world.displacement.warnings_raised, 1, "exactly one warning was ever raised")


# --- The round trip: arrival AFTER a departure, on the same spot --------------------------------
# THE GAP THIS CLOSES. `test_causality_end_to_end.gd` names row 10's own arrival direction and
# `_check_species_hosted_is_permanent()` above proves the all-time record outlives a departure —
# but nothing anywhere had ever driven the two back to back: rebuild the SAME habitat a departed
# resident just left, and confirm a fresh resident of the SAME species actually arrives again
# through the ordinary `HabitatSimulation` qualification path, rather than being blocked by some
# leftover `HomeSiteRegistry` state (a stale claim on the tile, an un-released exclusivity entry,
# `_ever_hosted` bleeding into "currently resident"). Picks up the real `WorldRoot` fixture exactly
# where `_check_removing_an_occupied_house_is_allowed_and_gentle()` left it — the villager family
# departed and the House came down — because the villager IS the floor's structure home site, and
# a structure's departure takes the `unregister()` branch of `HomeSiteRegistry.release()` (the
# House was already gone when the family left, so `structure_remains` read false): the exact
# branch that removes a site from the registry outright rather than merely un-claiming it, and
# therefore the sharpest version of "is anything left behind" to ask.

func _check_rebuilding_after_a_departure_lets_the_species_return() -> void:
	check_eq(_world.total_residents(), 0,
		"SETUP: still nobody in the world, picking up from the departure above")
	check(not _world.grid.is_occupied(HOUSE_TILE.x, HOUSE_TILE.y), "SETUP: the House tile is bare")

	# THE MECHANISM, CONFIRMED LIVE: the departed structure home site left the registry
	# entirely, exactly as `registry.is_empty()` proves for the synthetic wild-species case in
	# `_check_species_hosted_is_permanent()`. There is no vacant, no claimed, no anything at
	# this tile for a rebuild to trip over.
	check(not _world.registry.any_site_at(HOUSE_TILE),
		"THE DEPARTED HOME SITE LEFT THE REGISTRY: nothing at all is registered at the House's "
		+ "old tile — no stale claim, vacant or settled, for a rebuild to inherit")

	# REBUILD. A brand new House on the exact tile the old one departed from. The field beside
	# it (`FIELD_TILE`) was never touched by the removal above, so only the House is rebuilt.
	var new_arrivals: Array[String] = []
	_world.resident_arrived.connect(
		func(species_id: String, _world_position: Vector3) -> void: new_arrivals.append(species_id))

	check(_world.place_building(HOUSE_TILE.x, HOUSE_TILE.y, "house"),
		"REBUILD: a new House goes up on the tile the departed family's House stood on")
	check(_world.registry.any_site_at(HOUSE_TILE),
		"...a FRESH structure home site registers there — through the ordinary "
		+ "`place_building()` -> `on_building_changed()` -> `_sync_structure_site()` path, the "
		+ "same one every House gets, not a resurrection of the one that departed")
	check_eq(_world.capacity_at(HOUSE_TILE.x, HOUSE_TILE.y, "human"), 1,
		"...capacity reads 1 again: the field beside it never left, so house 1/1, cultivated "
		+ "1/1, exactly like the very first time")

	# SETTLE, through the real `ArrivalQueue` timing — no shortcut through `_settle()` or a
	# direct registry write, because the thing being proven is that the ORDINARY path works.
	for _i in 60:
		_world.simulation.tick(0.0)
	_world.simulation.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)

	check_eq(_world.total_residents(), 1,
		"THE ROUND TRIP: a fresh villager family moved back in on its own — nothing about the "
		+ "earlier departure blocked the ordinary qualification path")
	check_eq(_world.resident_species_ids(), ["human"] as Array[String],
		"...the same species returning, `human`, arriving the ordinary way")
	check_eq(new_arrivals, ["human"] as Array[String],
		"...`resident_arrived` fired exactly once for the NEW family — a real arrival through "
		+ "the queue, not the departed household reappearing")
	check_eq(_world.population_at(HOUSE_TILE.x, HOUSE_TILE.y, "human"), 1,
		"...counted as the population of the rebuilt House's own home site")

	# SPECIES HOSTED IS STILL PERMANENT, AND STILL EXACTLY ONE. The all-time record must not
	# decrease (already proven above) and a species RETURNING to a home it already hosted must
	# not be counted as hosting a second species — `_ever_hosted` is a set, not a tally of
	# arrivals, and this is the assertion that would catch it counting one.
	check_eq(_world.species_hosted_ids(), ["human"] as Array[String],
		"Species Hosted still names exactly `human` — the return added no second entry")
	check_eq(_world.species_hosted_count(), 1,
		"...and the all-time count is still 1: hosting the same species again is not a new one")

	# NO RESIDUE, AGAIN. The round trip itself displaced nobody and left nothing pending.
	check(_world.displacement.is_idle(), "no displacement gesture is pending after the round trip")
	check_eq(_world.displacement.warnings_raised, 1,
		"...and the warning count is unchanged since the departure earlier in this section — "
		+ "rebuilding and re-arriving is not itself a displacement")


# --- probes ---------------------------------------------------------------------------------------

## Drives one complete trigger case: lay 12 cover tiles, settle `population` residents, edit the
## world down to `remaining` cover tiles as ONE gesture, settle it, and report what happened.
func _trigger_probe(remaining: int, population: int) -> Dictionary:
	var f: Dictionary = _fixture()
	var displacement: GentleDisplacement = f["displacement"]
	var grid: WorldGrid = f["grid"]
	var home := Vector2i(10, 10)

	var warnings: Array[Dictionary] = []
	displacement.displacement_warned.connect(func(w: Dictionary) -> void: warnings.append(w))

	# A 6x2 block, every tile inside radius 8 of the home.
	var block: Array[Vector2i] = []
	for dz in 2:
		for dx in 6:
			block.append(Vector2i(home.x + dx, home.y + dz))
	for tile: Vector2i in block:
		grid.set_terrain(tile.x, tile.y, "rock")

	_settle(f, home, f["species"], population)

	if remaining >= block.size():
		# Nothing to take away, so the gesture is armed by an edit that changes no tag the
		# species cares about — which is itself the honest shape of "an edit that displaces
		# nobody must still settle silently".
		_edit(f, Vector2i(home.x, home.y + 6), "water")
	else:
		for i in range(remaining, block.size()):
			_edit(f, block[i], "grass")

	var capacity: int = (f["sim"] as HabitatSimulation).capacity_at(home, f["species"])
	displacement.tick(PAST_WINDOW)
	var result: Dictionary = {
		"warned": not warnings.is_empty(),
		"capacity": capacity,
		"settled": displacement.settlements_resolved,
	}
	_teardown(f)
	return result


## Drives one relocation case. The home's own cover is destroyed outright; `remote_cover` cover
## tiles sit 10 tiles away — outside the home's radius (8) but reachable by a candidate inside
## the relocation search radius (8). Reports the outcome the warning chose and what followed.
func _relocation_probe(remote_cover: int, population: int) -> Dictionary:
	var f: Dictionary = _fixture()
	var displacement: GentleDisplacement = f["displacement"]
	var grid: WorldGrid = f["grid"]
	var sim: HabitatSimulation = f["sim"]
	var home := Vector2i(10, 10)

	var warnings: Array[Dictionary] = []
	var relocations: Array[Vector2i] = []
	var departures: Array[Vector2i] = []
	displacement.displacement_warned.connect(func(w: Dictionary) -> void: warnings.append(w))
	displacement.resident_relocated.connect(
		func(_s: String, _from: Vector2i, to: Vector2i, _p: Vector3) -> void:
			relocations.append(to))
	displacement.resident_departed.connect(
		func(_s: String, tile: Vector2i, _n: int, _p: Vector3) -> void: departures.append(tile))

	# The home's own habitat: a 4x2 block, 8 cover tiles -> capacity 2.
	var own: Array[Vector2i] = []
	for dz in 2:
		for dx in 4:
			own.append(Vector2i(home.x + dx, home.y + dz))
	for tile: Vector2i in own:
		grid.set_terrain(tile.x, tile.y, "rock")

	# The distant patch, at z = 20: 10 tiles from the home, so it is invisible to the home
	# itself and visible only from a candidate that has moved toward it.
	for i in remote_cover:
		grid.set_terrain(home.x + i, 20, "rock")

	var site: HomeSite = _settle(f, home, f["species"], population)
	var from: Vector2i = site.position

	for tile: Vector2i in own:
		_edit(f, tile, "grass")
	displacement.tick(PAST_WINDOW)

	var homes: Array = [] if warnings.is_empty() else warnings[0]["homes"]
	var entry: Dictionary = {} if homes.is_empty() else homes[0]
	var destination: Vector2i = site.position
	var result: Dictionary = {
		"warned": not warnings.is_empty(),
		"outcome": entry.get("outcome", ""),
		"copy_key": entry.get("copy_key", ""),
		"relocations": relocations.size(),
		"departures": departures.size(),
		"population_after": site.population(),
		"moved_from": from,
		"moved_to": destination,
		"destination_capacity": sim.capacity_at(destination, f["species"]),
	}
	_teardown(f)
	return result


# --- fixtures --------------------------------------------------------------------------------------

## A world with no scene, one SYNTHETIC species: `cover`, 4 tiles per individual, radius 8.
func _fixture() -> Dictionary:
	return _build_fixture([_species("critter", "Critter", 4)])


## Two synthetic species, both needing `cover` at ONE tile per individual, so a single tile is a
## whole household's habitat and three homes can be displaced by three taps.
func _two_species_fixture() -> Dictionary:
	var critter: AnimalDefinition = _species("critter", "Critter", 1)
	var grazer: AnimalDefinition = _species("grazer", "Grazer", 1)
	var f: Dictionary = _build_fixture([critter, grazer])
	f["critter"] = critter
	f["grazer"] = grazer
	return f


func _species(id: String, display_name: String, tiles_per_individual: int) -> AnimalDefinition:
	var species := AnimalDefinition.new()
	species.id = id
	species.display_name = display_name
	species.habitat_needs = ["cover"] as Array[String]
	species.tiles_per_individual = tiles_per_individual
	species.scout_radius = 8
	species.model_scenes = [load("res://assets/placeholder/grass/Grass.tscn") as PackedScene]
	return species


func _build_fixture(species_list: Array[AnimalDefinition]) -> Dictionary:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 36, 36)

	var roster := SpeciesRoster.new(species_list)
	var registry := HomeSiteRegistry.new()
	var arrivals := ArrivalQueue.new(20260728)
	var residents_root := Node3D.new()

	var sim := HabitatSimulation.new()
	sim.attach(grid, roster, registry, arrivals, residents_root)

	var displacement := GentleDisplacement.new()
	displacement.attach(grid, roster, registry, sim, null, SettlementWindow.new())

	return {
		"grid": grid, "roster": roster, "registry": registry, "sim": sim,
		"displacement": displacement, "species": species_list[0], "residents": residents_root,
	}


func _teardown(f: Dictionary) -> void:
	(f["displacement"] as GentleDisplacement).free()
	(f["sim"] as HabitatSimulation).free()
	(f["grid"] as WorldGrid).free()
	(f["residents"] as Node3D).free()


## A grey-box placeable, so a build/removal can move a tag count without needing shipped content
## that happens to allow it.
func _synthetic_placeable(id: String, emitted_tags: Array[String]) -> PlaceableDefinition:
	var def := PlaceableDefinition.new()
	def.id = id
	def.display_name = id.capitalize()
	def.cost = 0
	def.footprint = Vector2i(1, 1)
	def.allowed_terrain = ["grass", "rock"] as Array[String]
	def.emitted_tags = emitted_tags
	return def


## One player edit, in exactly the order `WorldRoot` applies one.
func _edit(f: Dictionary, tile: Vector2i, terrain_id: String) -> void:
	(f["grid"] as WorldGrid).set_terrain(tile.x, tile.y, terrain_id)
	(f["sim"] as HabitatSimulation).on_terraform(tile)
	(f["displacement"] as GentleDisplacement).on_edit(tile)


func _lay_cover(f: Dictionary, home: Vector2i, count: int) -> void:
	var grid: WorldGrid = f["grid"]
	for i in count:
		grid.set_terrain(home.x + i, home.y, "rock")


func _settle(
	f: Dictionary, home: Vector2i, species: AnimalDefinition, population: int
) -> HomeSite:
	var registry: HomeSiteRegistry = f["registry"]
	var site: HomeSite = registry.register(home, species.id, species.scout_radius)
	while site.population() < population:
		var resident := Node3D.new()
		resident.name = "%s_%d_%d_%d" % [species.id, home.x, home.y, site.population()]
		(f["residents"] as Node3D).add_child(resident)
		site.residents.append(resident)
	return site


## Strips `#`-comments so a structural source check cannot be satisfied (or defeated) by prose.
func _strip_comments(source: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line: String in source.split("\n"):
		var hash_at: int = line.find("#")
		out.append(line if hash_at < 0 else line.substr(0, hash_at))
	return "\n".join(out)
