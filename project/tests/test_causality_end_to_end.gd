extends QATestCase
## THE USP, PROVEN END TO END — the single most important suite in the project.
##
## gdd.md -> Scope, row 6: "Animals move in *only because a real spot met their needs* —
## never scripted, never timed." Row 4: "**A villager moves in when its habitat is met**
## ships whole — the USP requires the proof, not the building."
##
## This suite instantiates the real `scenes/Main.tscn` and drives `WorldRoot`'s public API —
## `paint_tile()`, `place_building()`, `capacity_at()` — walking the whole causal chain:
##
##   player edit -> tile changes -> neighbourhood dirty -> capacity re-evaluated
##                -> arrival enqueued -> delay -> due-time re-check -> resident moves in
##
## twice: once for a WILD species (rabbit onto grass-near-boulders) and once for a VILLAGER
## (a family into the house-with-field). The second is row 4's USP proof and does not thin.
##
## AND THE NEGATIVE, which is the half that makes the positive mean anything: with no
## qualifying edit, no animal ever arrives, however long the world runs.
##
## The simulation is advanced by calling `HabitatSimulation.tick()` directly, so a 20-60 s
## arrival delay passes in one call. Nothing else about the path is faked: the roster, the
## terrain, the House and the capacity arithmetic are the shipped ones.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_causality_end_to_end.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

## The rabbit's habitat, painted as a 4x3 block of cultivated field. Rabbit needs `open_grass`
## + `cover` at 4 tiles per individual (roster.md's decided value, -> D-27 #2) on the LEGACY
## flat fields, so 12 tiles beside the starting meadow is THREE individuals' worth of the
## scarce need. It used to be exactly one, against the schema stub's 12; the block is
## unchanged and the arithmetic under it moved.
##
## RE-POINTED 2026-09-04 (habitat-tiers ruling): `capacity_at()` now reads
## `AnimalDefinition.effective_tiers()`, which prefers the real `tiers` rabbit.tres now
## carries. Rabbit's base tier needs `open_grass/4` + `cultivated/4` — `cover` is no longer
## consumed — so the scarce block below is painted `cultivated_field`, not `rock`, to stay
## the tag the arithmetic is actually about. Same block size, same divisor (4), so the "12
## tiles / 4 = 3" arithmetic is unchanged; only which terrain supplies the tag moved. Costs
## Wood now (`cultivated_field.cost == 2`), unlike free `rock`; the suite's 50-Wood starting
## budget comfortably covers this block plus the House/field fixture below (24 + 17 = 41).
##
## RE-DERIVED 2026-07-28 against the new divisor, and the re-derivation is not just a division:
## once one edit supports more than one individual, several candidate sites compete for the
## same tiles, and the suite's old "exactly one resident landed" pins had to become DELTA
## assertions. See `_check_wild_species_causality()` and the over-capacity pending note.
const ROCK_ORIGIN := Vector2i(6, 7)
const ROCK_W: int = 4
const ROCK_D: int = 3
const RABBIT_SITE := Vector2i(8, 8)

## The villager's habitat, deliberately 20 tiles away so the two neighbourhoods cannot
## overlap (both radii are 8, so a shared tile would need them within 16).
const HOUSE_TILE := Vector2i(28, 28)
const FIELD_TILE := Vector2i(29, 28)

## How long the world is left running, in simulated seconds, to prove nothing arrives
## unbidden. 200 x 5 s is ~16 minutes of world time against a 20-60 s arrival delay.
const IDLE_TICKS: int = 200
const IDLE_TICK_SECONDS: float = 5.0

var _world: WorldRoot = null
var _arrivals_seen: Array[String] = []
var _arrival_positions: Array[Vector3] = []
var _capacity_at_arrival: Array[int] = []
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("causality end to end")

	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		finish()
		return
	_world = node as WorldRoot
	_world.resident_arrived.connect(_on_resident_arrived)
	root.add_child(_world)
	_setup_ok = true


## Capacity is sampled HERE, inside the signal, because it is a different number later. A site
## that qualified when its resident landed can be stripped of tiles by a competing site that
## registers afterwards (see `_note_capacity_is_not_a_binding_cap()` — measured, on this exact
## run, as 5 of 6 rabbit sites ending up over capacity), so "it settled where its needs were
## met" is a claim about the MOMENT OF ARRIVAL and has to be measured there. Reading it live at
## the end of the run measures something else, and on this world measures it wrong for every
## arrival but (maybe) the very last one — "landed first" does NOT mean "uncontested": a
## registered site can be stripped of tiles by a competitor that registers after it, regardless
## of arrival order, which is the whole mechanism this suite exists to surface.
func _on_resident_arrived(species_id: String, world_position: Vector3) -> void:
	_arrivals_seen.append(species_id)
	_arrival_positions.append(world_position)
	var tile: Vector2i = _world.grid.world_to_tile(world_position)
	_capacity_at_arrival.append(_world.capacity_at(tile.x, tile.y, species_id))


## Everything runs in one frame once the world's `_ready()` has been through: `tick()` is
## synchronous, so the whole causal chain is driven in order with no cross-frame ambiguity.
func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	_check_world_starts_inert()
	_check_negative_control_before_any_edit()
	_check_wild_species_causality()
	_check_villager_causality()
	_check_negative_control_after()

	_note_capacity_is_not_a_binding_cap()

	note_expected_pending(
		"GENTLE DISPLACEMENT (row 10) LANDED 2026-07-28 — the reverse direction is covered now",
		"The old note here said that painting over the rock under a settled rabbit produced no "
		+ "warning, relocation or departure. That is no longer true. This suite still owns the "
		+ "ARRIVAL direction of the causal chain; the de-qualification direction — warn at "
		+ "settlement iff `capacity < population`, then relocate or depart — is "
		+ "`test_gentle_displacement.gd`'s, which drives it on this same `Main.tscn` by removing "
		+ "an occupied House. The round trip — arrival AFTER a departure on the same spot, "
		+ "rebuilding the habitat and confirming the species comes back — is covered there too "
		+ "now, by `_check_rebuilding_after_a_departure_lets_the_species_return()`, which rebuilds "
		+ "the exact House that test's own earlier removal took down and confirms a fresh "
		+ "villager family lands through the ordinary queue."
	)
	note_expected_pending(
		"REMOVAL / UNDO & REFUND LANDED 2026-07-28 (#16) — reversibility is testable now",
		"The old note here said there was no way to un-paint or un-place through the public API. "
		+ "`WorldRoot.remove_at()` / `can_remove()` / `refund_preview()` are that way, and the "
		+ "policy is asserted in `test_removal_refund.gd`. This suite deliberately does not "
		+ "re-drive it: its subject is the causal chain, not the economy."
	)
	note_expected_pending(
		"TIME-TO-FIRST-MOVE-IN is NOT validated here (spec.md -> Pacing Constants)",
		"The <= 2 min target / 5 min ceiling is a step-5 kid-playtest criterion measured in real "
		+ "seconds. This suite advances the clock by hand, so it proves the causal chain, never "
		+ "the wait. Do not read a green here as the pacing bound being met."
	)

	finish()
	return true


# --- The starting world ---------------------------------------------------------------------

func _check_world_starts_inert() -> void:
	check_eq(_world.grid_size(), Vector2i(36, 36), "the world is the 36x36 start (#18)")
	check_eq(_world.total_residents(), 0, "the world starts with NO residents — nothing is pre-placed")
	# RE-POINTED (-> D-43, roster grew 3 -> 12): this suite's causal chain only ever drives
	# human/fox/rabbit, so it cares that those three floor species are still in the roster,
	# not that the roster is exactly three species — the roster's total size is D-43's claim,
	# not this suite's.
	check(_world.roster.by_id("human") != null and _world.roster.by_id("fox") != null
			and _world.roster.by_id("rabbit") != null,
		"the floor species (human, fox, rabbit) are all present in the roster")
	# RE-POINTED (-> D-29 #1, `WorldGrid.START_TERRAIN_ID` "grass" -> "wild_grass"): the human
	# reversed the implementer's "grass" pick so the starting world reads exactly like freshly
	# revealed mist land — tag-inert until the player acts on it — rather than an already-tagged
	# meadow. gdd.md's own "mostly-grass meadow" First 60 Seconds line is about how it LOOKS, not
	# what it emits; the inert-land invariant this check exists to prove now runs the other way.
	check_eq(_world.get_tile_terrain(RABBIT_SITE.x, RABBIT_SITE.y), "wild_grass",
		"the starting world is untouched wild grass — tag-inert until the player acts on it")

	# The inert start, measured through the same read the simulation uses: an untouched meadow
	# qualifies nobody. If this were non-zero the rest of the suite would prove nothing.
	check_eq(_world.capacity_at(RABBIT_SITE.x, RABBIT_SITE.y, "rabbit"), 0,
		"rabbit capacity on untouched land is 0 — the meadow alone is not habitat")
	check_eq(_world.capacity_at(HOUSE_TILE.x, HOUSE_TILE.y, "human"), 0,
		"villager capacity on untouched land is 0 — there is no house and no field")
	check_eq(_world.capacity_at(RABBIT_SITE.x, RABBIT_SITE.y, "fox"), 0,
		"fox capacity on untouched land is 0 too")


func _check_negative_control_before_any_edit() -> void:
	# THE NEGATIVE. An animal must never arrive without a qualifying edit — not after a long
	# wait, not on a timer, not because the world felt like it.
	for _i in IDLE_TICKS:
		_world.simulation.tick(IDLE_TICK_SECONDS)

	check_eq(_world.total_residents(), 0,
		"NEGATIVE: %.0f simulated seconds with no edit -> still zero residents"
			% (IDLE_TICKS * IDLE_TICK_SECONDS))
	check_eq(_arrivals_seen.size(), 0, "...and `resident_arrived` never fired")
	check_eq(_world.simulation.evaluations_run, 0,
		"...and the simulation ran ZERO evaluations (an idle world does no work)")


# --- The wild species: rock beside grass ------------------------------------------------------

func _check_wild_species_causality() -> void:
	var rabbit: AnimalDefinition = _world.roster.by_id("rabbit")
	check(rabbit != null, "the rabbit is in the shipped roster")
	check_eq(rabbit.habitat_needs, ["open_grass", "cover"] as Array[String],
		"rabbit needs open_grass + cover — and rock, not forest, is the `cover` source")

	# RE-POINTED 2026-09-04 (habitat-tiers ruling): `capacity_at()` now reads
	# `AnimalDefinition.effective_tiers()`, which prefers the real `tiers` rabbit.tres now
	# carries — base tier needs `open_grass/4` + `cultivated/4` (`cover` is no longer
	# consumed). The border below still supplies `open_grass`, exactly the same fix
	# `test_event_driven_simulation.gd`'s wander fixture needed for the same reason
	# (`wild_grass`, the world default, emits no tags at all).
	var grass_painted: int = 0
	for x in range(ROCK_ORIGIN.x - 1, ROCK_ORIGIN.x + ROCK_W + 1):
		for z in range(ROCK_ORIGIN.y - 1, ROCK_ORIGIN.y + ROCK_D + 1):
			var inside_rock: bool = (
				x >= ROCK_ORIGIN.x and x < ROCK_ORIGIN.x + ROCK_W
				and z >= ROCK_ORIGIN.y and z < ROCK_ORIGIN.y + ROCK_D
			)
			if not inside_rock and _world.paint_tile(x, z, "grass"):
				grass_painted += 1
	check(grass_painted >= ROCK_W * ROCK_D,
		"painted %d grass border tiles — at least as many as the cultivated block, so cultivated "
		% grass_painted + "(not open_grass) stays the scarce need the divisor-4 arithmetic below is about")

	var painted: int = 0
	for dx in ROCK_W:
		for dz in ROCK_D:
			if _world.paint_tile(ROCK_ORIGIN.x + dx, ROCK_ORIGIN.y + dz, "cultivated_field"):
				painted += 1
	check_eq(painted, ROCK_W * ROCK_D,
		"%d cultivated tiles painted beside the meadow" % (ROCK_W * ROCK_D))
	check_eq(_world.get_tile_terrain(ROCK_ORIGIN.x, ROCK_ORIGIN.y), "cultivated_field",
		"the tiles really did convert")

	# CAUSE -> EFFECT, read through the same function the arrival predicate uses. This is the
	# assertion the whole suite exists for, and it is UNAFFECTED by anything the human may yet
	# rule about competing sites: it is the formula on one position, re-derived at divisor 4.
	check_eq(rabbit.tiles_per_individual, 4,
		"the rabbit's decided divisor is 4 (-> D-27 #2), so the re-derivation below is against "
		+ "the shipped value and not a number this suite chose")
	check_eq(_world.capacity_at(RABBIT_SITE.x, RABBIT_SITE.y, "rabbit"), 3,
		"capacity rose 0 -> 3 BECAUSE of the paint: 12 cultivated tiles / 4 per individual, against "
		+ "the tier's own divisor")

	_drain(60)
	check(_world.simulation.arrivals().size() > 0,
		"an arrival was enqueued off the edit itself (never at settlement)")
	check_eq(_world.total_residents(), 0, "...and nobody has landed yet — the delay is running")

	_world.simulation.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)

	# THE MOVE-IN. Asserted as a DELTA and a species, not as an absolute head count.
	#
	# WHY THIS IS NOT `check_eq(total_residents(), 1)` ANY MORE. That pin was correct while 12
	# cover tiles were one individual's worth: there was one qualifying site and the other
	# candidates de-qualified the moment it claimed the rock. At divisor 4 the same block is
	# three individuals' worth, several candidate sites compete for the same tiles, and the
	# settled head count is a number the human has not ruled on — see the over-capacity pending
	# note at the top of this file. Pinning today's count would pin a CONTESTED value as
	# intended, and it would have to be deleted the day the ruling lands. The delta, the
	# species, and "it settled where its needs were met" are true under every possible ruling,
	# so those are what this suite asserts.
	check(_world.total_residents() >= 1, "THE MOVE-IN: at least one resident landed",
		"total_residents() == %d" % _world.total_residents())
	check_eq(_world.resident_species_ids(), ["rabbit"] as Array[String],
		"...and every resident in the world is a rabbit — the paint attracted the species whose "
		+ "needs it met, and nobody else")
	check_eq(_arrivals_seen.size(), _world.total_residents(),
		"`resident_arrived` fired exactly once per resident — no silent landings, no double fire")
	check_eq(_arrivals_seen[0], "rabbit", "...with species_id == \"rabbit\" (row 7's card rides this)")

	# The resident is standing on a spot that actually qualified — the arrival is a consequence
	# of the land, not a spawn at an arbitrary position. Checked against the CAPTURED-AT-ARRIVAL
	# value, not a live read: a live read can be corrupted by a competitor that registers later
	# and steals the tile (see `_note_capacity_is_not_a_binding_cap()`), which is exactly what
	# happens to most of these sites on this run. "It settled where its needs were met" is a
	# claim about the instant it settled, so it has to be checked against that instant.
	var landed: Vector2i = _world.grid.world_to_tile(_arrival_positions[0])
	check(_world.has_tile(landed.x, landed.y), "the arrival position maps to a real tile %s" % landed)
	check(_capacity_at_arrival[0] >= 1,
		"the first arrival's tile had capacity >= 1 AT THE MOMENT IT ARRIVED — it settled where "
		+ "its needs were met",
		"tile %s capacity-at-arrival %d" % [landed, _capacity_at_arrival[0]])
	check(_world.population_at(landed.x, landed.y, "rabbit") >= 1,
		"...and it is counted as the population of that home site")

	# IT STOPS. Whatever the settled count is, a further pass with NO new player edit must add
	# nobody: population follows edits, never the clock. Asserted as a delta for the same reason
	# as above — this is the ruling-independent half of "12 tiles do not support twelve rabbits".
	var settled_after_first: int = _world.total_residents()
	_drain(60)
	_world.simulation.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)
	check_eq(_world.total_residents(), settled_after_first,
		"a second pass with no new edit adds NOBODY — the population reached a fixed point and "
		+ "does not creep upward on its own (settled at %d)" % settled_after_first)


# --- The villager: row 4's USP proof -----------------------------------------------------------

func _check_villager_causality() -> void:
	var human: AnimalDefinition = _world.roster.by_id("human")
	check(human != null, "the villager is in the roster — a villager is just another species")
	check_eq(human.habitat_needs, ["house", "cultivated"] as Array[String],
		"a villager needs `house` + `cultivated` — no separate people system")

	# Every head count in this section is a DELTA against whatever the rabbit half settled at —
	# the villager's arrival is row 4's proof and it must not be hostage to the rabbit
	# population, which is the contested number (see the over-capacity pending note).
	var residents_before_house: int = _world.total_residents()
	var arrivals_before_house: int = _arrivals_seen.size()

	# RE-POINTED (-> D-29 #1): the House's `allowed_terrain` is `["grass"]` specifically
	# (buildings.md — houses build on grass only), and `wild_grass` (the new default) is not
	# that. The old ambient `grass` backdrop made this tile eligible for free; now it has to be
	# stated explicitly, same as the Build-mode fixtures in `test_mode_tap_model.gd`.
	_world.paint_tile(HOUSE_TILE.x, HOUSE_TILE.y, "grass")
	var wood_before: int = _world.get_wood()
	check(_world.place_building(HOUSE_TILE.x, HOUSE_TILE.y, "house"),
		"the House places on grass")
	check_eq(_world.get_wood(), wood_before - 15, "...and costs 15 Wood")
	# RE-POINTED 2026-09-04 (habitat-tiers Task 7): was ["house"]. `built` now added
	# alongside `house` — the universal exclusion handle every placeable emits. See
	# docs/superpowers/specs/2026-09-04-habitat-tiers-design.md § 8.
	check_eq(_world.get_tile_tags(HOUSE_TILE.x, HOUSE_TILE.y), ["built", "house"] as Array[String],
		"the footprint suppresses the ground's tags and emits `built` + `house` instead")

	# THE HOUSE ALONE IS NOT ENOUGH. This is the assertion that makes the villager's arrival a
	# habitat result rather than a building side effect.
	check_eq(_world.capacity_at(HOUSE_TILE.x, HOUSE_TILE.y, "human"), 0,
		"a House with no field is capacity 0 — building does not summon a villager")
	_drain(60)
	check_eq(_world.total_residents(), residents_before_house, "...and nobody moved into it")

	check(_world.paint_tile(FIELD_TILE.x, FIELD_TILE.y, "cultivated_field"),
		"a cultivated field is painted beside the house")
	check_eq(_world.get_wood(), wood_before - 15 - 2, "...and costs 2 Wood")
	check_eq(_world.capacity_at(HOUSE_TILE.x, HOUSE_TILE.y, "human"), 1,
		"capacity rose 0 -> 1 BECAUSE of the field: house 1/1, cultivated 1/1")

	_drain(60)
	_world.simulation.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)

	check_eq(_world.total_residents(), residents_before_house + 1,
		"THE USP PROOF: EXACTLY ONE more resident landed after the field was painted")
	check(_world.resident_species_ids().has("human"), "...and it is a villager")
	check_eq(_arrivals_seen.size(), arrivals_before_house + 1,
		"`resident_arrived` fired exactly once more")
	check_eq(_arrivals_seen[_arrivals_seen.size() - 1], "human",
		"...with species_id == \"human\" — the villager is the LATEST arrival, caused by the field")
	check_eq(_world.population_at(HOUSE_TILE.x, HOUSE_TILE.y, "human"), 1,
		"the villager lives in the house's own home site, not on the field beside it")

	# The villager arrived through the same loader, the same formula and the same queue as the
	# rabbit. Nothing in the simulation special-cases it.
	check_eq(_world.capacity_at(HOUSE_TILE.x, HOUSE_TILE.y, "rabbit"), 0,
		"the rabbit does not qualify at the house — species share one system, not one outcome")


func _check_negative_control_after() -> void:
	var residents_before: int = _world.total_residents()
	var arrivals_before: int = _arrivals_seen.size()
	for _i in IDLE_TICKS:
		_world.simulation.tick(IDLE_TICK_SECONDS)
	check_eq(_world.total_residents(), residents_before,
		"NEGATIVE: another %.0f simulated seconds with no edit adds nobody"
			% (IDLE_TICKS * IDLE_TICK_SECONDS))
	check_eq(_arrivals_seen.size(), arrivals_before,
		"...and `resident_arrived` did not fire again")
	check(_world.simulation.is_idle(), "...and the world is idle, doing no work at all")


# --- The finding: capacity is not a binding cap once sites compete ---------------------------

## RECORDED, NOT ASSERTED — and the distinction is the whole point of this function.
##
## gameplay-engineer measured this and it could not fire before D-27 #2: at divisor 12 the 4x3
## rock block was one individual's worth, so there was never a second qualifying site to compete
## with the first. At divisor 4 the same block is three individuals' worth, several candidate
## sites qualify off the same tiles, and the end state has home sites whose POPULATION EXCEEDS
## THEIR OWN CAPACITY the instant they register.
##
## THE MECHANISM, confirmed at unit scale on a synthetic species (divisor 4, scout_radius 8,
## eight cover tiles in a row from (18,18) to (25,18)):
##   1. Site A at (18,18) owns all eight tiles -> capacity 2, and holds population 2. Correct.
##   2. A PROSPECTIVE site B at (24,18) is evaluated. `CapacityEvaluator._tile_counts_for()`
##      lets a prospective candidate count any tile it is STRICTLY NEARER to than the current
##      owner, so B counts the four tiles at x=22..25 -> capacity 1.
##   3. The arrival predicate asks only about B: `capacity 1 >= population 0 + 1`. True, so B is
##      enqueued and lands.
##   4. B registers. Ownership rebuilds, A loses those four tiles -> A is capacity 1 against a
##      population of 2. **A is over capacity by one the instant B registers.**
##
## RULED 2026-08-01 (-> D-29 #5) AND BUILT THE SAME DAY: this is no longer left unconsumed. The
## arrival predicate itself is still unchanged (it only ever asks about the ARRIVING site), but
## landing B's arrival now also calls `GentleDisplacement.on_arrival()`, which re-checks every
## already-settled neighbour B's registration could plausibly reach and, for A, arms A's own
## settlement window exactly as a player edit would — so the overshoot measured below is armed
## for A, not silently uncounted for. **Why this suite still reports the overshoot rather than
## asserting it away:** `GentleDisplacement`'s window needs real (or scaled) time to close before
## anything actually relocates or departs, and this suite advances the clock only through
## `HabitatSimulation.tick()`, never `GentleDisplacement.tick()` or a real frame — so within this
## run's own lifetime A's window is armed but never settles, and the overshoot below is real and
## observable at the instant this note reads it. That the window DOES resolve it given time is
## `test_gentle_displacement.gd` / `test_settlement_window.gd`'s own proof, not this suite's; this
## suite's subject is the arrival direction of the causal chain, and it is not this file's place
## to re-drive settlement to make the number below tidier.
##
## WHY THERE IS STILL NO `check()` HERE. Nobody is displaced and nothing bad happens on screen
## DURING THIS RUN, so this is not a pillar violation caught red-handed — but the numbers below
## are measured live from this run rather than transcribed, so this note cannot go stale against
## the build the way a hardcoded repro would, even as what happens to an armed window next
## continues to be decided and built elsewhere.
func _note_capacity_is_not_a_binding_cap() -> void:
	var over: PackedStringArray = PackedStringArray()
	var sites: int = 0
	var total_capacity: int = 0
	var total_population: int = 0
	for site: HomeSite in _world.registry.sites():
		if site.species_id != "rabbit":
			continue
		sites += 1
		var cap: int = _world.capacity_at(site.position.x, site.position.y, site.species_id)
		var pop: int = _world.population_at(site.position.x, site.position.y, site.species_id)
		total_capacity += cap
		total_population += pop
		if pop > cap:
			over.append("%s pop %d vs capacity %d" % [site.position, pop, cap])

	note_expected_pending(
		"CAPACITY IS NOT A BINDING POPULATION CAP THE INSTANT SITES COMPETE — ARMED, not settled, "
		+ "in this run (-> D-29 #5)",
		"REPRO, from this run: paint the %dx%d cultivated block at %s (12 cultivated tiles) on "
			% [ROCK_W, ROCK_D, str(ROCK_ORIGIN)]
		+ "the shipped 36x36 start and let every arrival come due. 12 cultivated tiles at the "
		+ "rabbit's decided divisor of 4 is three individuals' worth, and `capacity_at%s` reads 3. "
			% str(RABBIT_SITE)
		+ "MEASURED END STATE: %d rabbit home sites holding %d residents against %d total "
			% [sites, total_population, total_capacity]
		+ "capacity, with %d site(s) OVER capacity: %s. "
			% [over.size(), str(over)]
		+ "MECHANISM (confirmed separately at unit scale, and written up in full above this "
		+ "function): a prospective site counts tiles it is strictly nearer to than the current "
		+ "owner, so it can qualify on tiles somebody else is already living off; when it "
		+ "registers, ownership rebuilds and the older neighbour loses them. The arrival "
		+ "predicate itself still checks only the ARRIVING site's `capacity >= population + 1`. "
		+ "WHAT IS DIFFERENT SINCE D-29 #5: landing that arrival now also calls "
		+ "`GentleDisplacement.on_arrival()`, which arms every affected neighbour's own settlement "
		+ "window the same way a player edit would — so every overshoot measured above is armed, "
		+ "not silently uncounted. It has not SETTLED by the time this note reads the numbers, "
		+ "because this suite advances the clock only through `HabitatSimulation.tick()`, never "
		+ "`GentleDisplacement.tick()` or a real frame; whether an armed window here resolves the "
		+ "overshoot is `test_gentle_displacement.gd` / `test_settlement_window.gd`'s own proof, "
		+ "not re-driven here. NOT A PILLAR VIOLATION WITHIN THIS RUN: nobody is displaced, "
		+ "nothing vanishes, and no unexplained thing happens on screen — the head counts in "
		+ "`_check_wild_species_causality()` stay deltas because which sites end up over capacity "
		+ "is a contested, not a ruled-on, number."
	)


## Drains the dirty queue. The budget is deliberately small (4 evaluations/frame), so a burst
## of edits needs several ticks — driven with a zero delta so no arrival can come due while
## the queue is still being worked.
func _drain(ticks: int) -> void:
	for _i in ticks:
		_world.simulation.tick(0.0)
