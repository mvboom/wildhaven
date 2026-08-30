extends QATestCase
## THE CAPACITY FORMULA, pinned exactly — Tier 1 row 6's core, and the arithmetic every
## other Tier-1 row reads (rows 3, 4 and 10 all consume it).
##
## gdd.md -> Systems in Play -> Habitat Suitability, verbatim:
##
##   capacity(h, S) = min( min over t ( floor(count_t / S.tiles_per_individual) ),
##                         S.max_individuals )
##
##   "The scarcest need caps the population — Liebig's law of the minimum. There is no
##    lower clamp: capacity can be 0, and 0 means unsuitable — a site short of
##    `tiles_per_individual` on any needed tag supports nobody."
##   "The predicate is the same function: qualifies(h, S) === capacity(h, S) >= 1, and an
##    arrival is enqueued only where capacity(h, S) >= population(h, S) + 1 — one read, not
##    two systems."
##
## EVERY SPECIES HERE IS SYNTHETIC, built in this file. That is deliberate: the assertions
## below state what the *formula* does, so retuning `rabbit.tres` or `fox.tres` must never
## move them. The shipped roster's own values are pinned in the per-species schema suites.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_capacity_formula.gd

## The sweep used for the qualifies-equivalence check. Fixed length, so the assertion count
## does not move with the data.
const SWEEP_MAX_ROCKS: int = 20


func _init() -> void:
	begin("capacity formula")

	_check_pure_formula()
	_check_liebig()
	_check_zero_is_expressible()
	_check_max_individuals_cap()
	_check_capacity_radius_is_consumed()
	_check_sentinel_follows_scout_radius()
	_check_degenerate_inputs()
	_check_qualifies_is_the_same_function()
	_check_arrival_predicate()

	note_expected_pending(
		"GENTLE DISPLACEMENT (row 10) LANDED 2026-07-28 — the fall is now consumed",
		"The old note here said nothing consumed a capacity that fell below population. That is "
		+ "no longer true: `GentleDisplacement` warns at settlement iff `capacity(h, S) < "
		+ "population(h, S)`, then relocates or departs. This suite still owns the FORMULA "
		+ "(including that capacity may be 0 with no lower clamp, which is the value row 10's "
		+ "trigger is stated to include); the trigger built on it is "
		+ "`test_gentle_displacement.gd`'s."
	)

	finish()


# --- The formula, with no world at all ---------------------------------------------------
# `capacity_from_counts()` is the formula separated from the tile walk, which is what lets it
# be checked against gdd.md's line rather than against a world's incidental contents.

func _check_pure_formula() -> void:
	var s: AnimalDefinition = _species("s", ["a", "b"] as Array[String], 4, 8)

	# floor(), not round() and not ceil(): 7/4 is one individual, not two.
	check_eq(CapacityEvaluator.capacity_from_counts({"a": 7, "b": 7}, s), 1,
		"floor(7 / 4) == 1 — the divisor floors")
	check_eq(CapacityEvaluator.capacity_from_counts({"a": 8, "b": 8}, s), 2,
		"floor(8 / 4) == 2")
	check_eq(CapacityEvaluator.capacity_from_counts({"a": 11, "b": 12}, s), 2,
		"min over needs picks the scarcer: floor(11/4)=2 beats floor(12/4)=3")

	# A divisor of 1 is legal and is what `human.tres` ships (roster.md: the House is the
	# scarce need and the floor House is a single tile).
	var one: AnimalDefinition = _species("one", ["house"] as Array[String], 1, 8)
	check_eq(CapacityEvaluator.capacity_from_counts({"house": 3}, one), 3,
		"tiles_per_individual == 1 is legal — count maps straight to individuals")


func _check_liebig() -> void:
	var s: AnimalDefinition = _species("liebig", ["a", "b"] as Array[String], 4, 8)

	# THE POINT OF THE WHOLE FORMULA. Abundance in one need buys nothing when another is
	# short — a site with a thousand of `a` and three of `b` supports nobody.
	check_eq(CapacityEvaluator.capacity_from_counts({"a": 1000, "b": 3}, s), 0,
		"LIEBIG: 1000 of one tag and 3 of the other is capacity 0 — the scarcest need caps it")
	check_eq(CapacityEvaluator.capacity_from_counts({"a": 3, "b": 1000}, s), 0,
		"LIEBIG, the other way round — the rule is symmetric across needs")
	check_eq(CapacityEvaluator.capacity_from_counts({"a": 1000, "b": 4}, s), 1,
		"one more tile of the scarce tag is the whole difference: 0 -> 1")

	# A missing key is zero, not "unconstrained". A need the world does not emit at all must
	# not silently drop out of the min.
	check_eq(CapacityEvaluator.capacity_from_counts({"a": 1000}, s), 0,
		"a habitat_need absent from the counts dictionary counts as 0, never as satisfied")


func _check_zero_is_expressible() -> void:
	var s: AnimalDefinition = _species("zero", ["a"] as Array[String], 4, 8)

	# NO LOWER CLAMP. `capacity == 0` is a real answer meaning "unsuitable", and it must
	# survive to the caller — a clamp to 1 would make every tile on the map habitable.
	check_eq(CapacityEvaluator.capacity_from_counts({"a": 0}, s), 0,
		"NO LOWER CLAMP: zero qualifying tiles is capacity 0, not 1")
	check_eq(CapacityEvaluator.capacity_from_counts({"a": 3}, s), 0,
		"below one individual's worth (3 < 4) is capacity 0 — not rounded up to 1")
	check(not CapacityEvaluator.qualifies(null, null, Vector2i.ZERO, s),
		"a species with no world does not qualify (capacity 0 is the unsuitable state)")


## RE-POINTED 2026-07-28 (-> D-27 #1). This block used to read the cap off
## `CapacityEvaluator.MAX_INDIVIDUALS_PER_HOME_SITE`, a module constant in the evaluator, and
## that constant is deleted — the parse error this suite failed with was the ruling landing.
## `max_individuals` is an `AnimalDefinition` @export now, so the checks below are about the
## cap coming FROM DATA, which the constant form could not express at all.
func _check_max_individuals_cap() -> void:
	var s: AnimalDefinition = _species("cap", ["a"] as Array[String], 1, 8)
	var cap: int = AnimalDefinition.DEFAULT_MAX_INDIVIDUALS

	check_eq(cap, 6, "DEFAULT_MAX_INDIVIDUALS is 6 (roster.md's stated ~6, #23) — the value did "
		+ "not move when it changed homes, only its owner did")
	check_eq(s.max_individuals, cap,
		"a species that omits the field inherits that default, so the floor is unchanged")
	check_eq(CapacityEvaluator.capacity_from_counts({"a": 100000}, s), cap,
		"the upper cap binds: an arbitrarily rich site still tops out at max_individuals")
	check_eq(CapacityEvaluator.capacity_from_counts({"a": cap - 1}, s), cap - 1,
		"just below the cap is not capped — the cap is a ceiling, not a target")

	# THE CAP IS READ FROM THE SPECIES, not from any constant. Both directions are checked, and
	# the ABOVE-the-old-constant case is the load-bearing one: while the cap was
	# `MAX_INDIVIDUALS_PER_HOME_SITE`, a species asking for 9 got 6 and no test could see it.
	var roomy: AnimalDefinition = _species("roomy", ["a"] as Array[String], 1, 8)
	roomy.max_individuals = 9
	check_eq(CapacityEvaluator.capacity_from_counts({"a": 100000}, roomy), 9,
		"max_individuals = 9 yields 9 — ABOVE the old uniform 6, which is what a module constant "
		+ "structurally could not do")
	var tight: AnimalDefinition = _species("tight", ["a"] as Array[String], 1, 8)
	tight.max_individuals = 2
	check_eq(CapacityEvaluator.capacity_from_counts({"a": 100000}, tight), 2,
		"max_individuals = 2 yields 2 — and below the old uniform 6 too")

	# NEGATIVE CONTROL. The three assertions above are only a measurement if the same counts
	# really do produce three different answers; had the evaluator kept a constant, all three
	# would read 6 and every check but one would still have passed.
	var answers: Array[int] = [
		CapacityEvaluator.capacity_from_counts({"a": 100000}, s),
		CapacityEvaluator.capacity_from_counts({"a": 100000}, roomy),
		CapacityEvaluator.capacity_from_counts({"a": 100000}, tight),
	]
	check(answers[0] != answers[1] and answers[1] != answers[2] and answers[0] != answers[2],
		"NEGATIVE CONTROL: identical counts give THREE DIFFERENT capacities (%s) purely because "
			% str(answers) + "the species differ — the cap is data, not a constant",
		"got %s; three equal values would mean max_individuals is being ignored" % str(answers))


# --- `capacity_radius` is a real radius, separate from `scout_radius` --------------------
# NEW 2026-07-28 (-> D-27 #1). `CapacityEvaluator` now walks `S.effective_capacity_radius()`
# where it used to walk `scout_radius`. The only way to prove that is to make the two radii
# DISAGREE and show the tile count follows the capacity one — a world where they are equal
# (which is every shipped `.tres` today) cannot distinguish the two code paths at all.
#
# This reproduces gameplay-engineer's measurement independently: 3 rock tiles at distance 10,
# `scout_radius` held at 8 throughout, counted 0 under the sentinel and 3 at capacity_radius 12.

func _check_capacity_radius_is_consumed() -> void:
	var grid: WorldGrid = _grid()
	var empty := HomeSiteRegistry.new()
	var origin := Vector2i(18, 18)

	# Three cover tiles at exactly distance 10 — outside a radius of 8, inside one of 12.
	for tile: Vector2i in [
		origin + Vector2i(10, 0), origin + Vector2i(-10, 0), origin + Vector2i(0, 10)
	] as Array[Vector2i]:
		grid.set_terrain(tile.x, tile.y, "rock")

	# Divisor 1 so the count reads straight off as capacity and nothing is hidden by flooring.
	var far: AnimalDefinition = _species("far", ["cover"] as Array[String], 1, 8)
	far.capacity_radius = 12
	var near: AnimalDefinition = _species("near", ["cover"] as Array[String], 1, 8)
	# `near` keeps the sentinel, so it counts over scout_radius = 8.

	var near_counts: Dictionary = CapacityEvaluator.tag_counts(grid, empty, origin, near)
	var far_counts: Dictionary = CapacityEvaluator.tag_counts(grid, empty, origin, far)

	check_eq(int(near_counts.get("cover", -1)), 0,
		"scout_radius 8, capacity_radius following it: the three tiles at distance 10 count 0")
	check_eq(int(far_counts.get("cover", -1)), 3,
		"capacity_radius 12 with scout_radius STILL 8: the same three tiles count 3 — a tile "
		+ "inside capacity_radius but outside scout_radius is counted")
	check_eq(near.scout_radius, far.scout_radius,
		"...and scout_radius was held identical across those two reads (%d), so capacity_radius "
			% far.scout_radius + "is the only thing that moved")
	check_eq(CapacityEvaluator.capacity(grid, empty, origin, near), 0,
		"...which carries through the formula: capacity 0 under the sentinel")
	check_eq(CapacityEvaluator.capacity(grid, empty, origin, far), 3,
		"...and capacity 3 at capacity_radius 12")

	# NEGATIVE CONTROL, and the reason this section exists: an assertion that passes whether or
	# not `capacity_radius` is consumed is worthless. If the evaluator still walked scout_radius,
	# these two counts would be equal — so the INEQUALITY is the actual measurement.
	check(int(near_counts.get("cover", -1)) != int(far_counts.get("cover", -1)),
		"NEGATIVE CONTROL: the two counts DIFFER (0 vs 3) on one identical world at one identical "
		+ "origin — an evaluator still walking scout_radius would return the same number twice",
		"near=%s far=%s" % [str(near_counts), str(far_counts)])

	# THE OTHER DIRECTION, which the case above does not cover: a tile inside `scout_radius` but
	# OUTSIDE `capacity_radius` must NOT count. Without this, an evaluator that took the max of
	# the two radii, or the union, would pass everything above.
	var wide_scout: AnimalDefinition = _species("widescout", ["cover"] as Array[String], 1, 12)
	wide_scout.capacity_radius = 8
	check_eq(int(CapacityEvaluator.tag_counts(grid, empty, origin, wide_scout).get("cover", -1)), 0,
		"scout_radius 12 but capacity_radius 8: the distance-10 tiles count 0 — capacity does not "
		+ "quietly widen to scout_radius, and the walk is not a union of the two")

	grid.free()


## The sentinel, on its own. `capacity_radius = 0` means "follow `scout_radius`" and must never
## be taken as a radius of zero — that failure mode is nasty precisely because it does not crash:
## every site reports capacity 0, which reads as "nothing is habitat yet" rather than as a bug.
##
## The retune case is why the sentinel exists at all rather than a copied number. #20 is open and
## will move `scout_radius`; a `.tres` holding a literal 8 would silently stop tracking it.
func _check_sentinel_follows_scout_radius() -> void:
	var grid: WorldGrid = _grid()
	var empty := HomeSiteRegistry.new()
	var origin := Vector2i(18, 18)
	for tile: Vector2i in [
		origin + Vector2i(10, 0), origin + Vector2i(-10, 0), origin + Vector2i(0, 10)
	] as Array[Vector2i]:
		grid.set_terrain(tile.x, tile.y, "rock")

	var s: AnimalDefinition = _species("sentinel", ["cover"] as Array[String], 1, 8)
	check_eq(s.capacity_radius, AnimalDefinition.CAPACITY_RADIUS_FOLLOWS_SCOUT,
		"the schema default IS the sentinel, so a `.tres` that omits the field follows scout")
	check_eq(AnimalDefinition.CAPACITY_RADIUS_FOLLOWS_SCOUT, 0,
		"...and the sentinel's value is literally 0")
	check_eq(s.effective_capacity_radius(), 8,
		"a raw 0 resolves to scout_radius (8), NOT to a radius of zero")

	# A radius of zero would count only the origin tile. Painting the origin itself is what
	# separates "resolved to scout_radius" from "took the 0 at face value": under a true zero the
	# count would be exactly 1 (the origin) no matter what else is on the map.
	grid.set_terrain(origin.x, origin.y, "rock")
	grid.set_terrain(origin.x + 3, origin.y, "rock")
	var counts: Dictionary = CapacityEvaluator.tag_counts(grid, empty, origin, s)
	check_eq(int(counts.get("cover", -1)), 2,
		"the sentinel counts the origin AND the tile 3 away (2 tiles) — a literal radius of zero "
		+ "would have counted only the origin, and the distance-10 tiles stay out at radius 8")

	# THE RETUNE. Move `scout_radius` and the sentinel must move with it, in the SAME object,
	# with `capacity_radius` untouched at 0 throughout. This is the property a copied number
	# cannot have and the whole reason spec.md states the default as a relation.
	s.scout_radius = 12
	check_eq(s.capacity_radius, AnimalDefinition.CAPACITY_RADIUS_FOLLOWS_SCOUT,
		"capacity_radius is STILL the untouched sentinel after the retune")
	check_eq(s.effective_capacity_radius(), 12,
		"...and effective_capacity_radius() followed scout_radius to 12 — the relation held")
	check_eq(int(CapacityEvaluator.tag_counts(grid, empty, origin, s).get("cover", -1)), 5,
		"...and the tile walk followed too: the three distance-10 tiles are now IN, 2 -> 5")

	# NEGATIVE CONTROL for the retune. If `effective_capacity_radius()` had baked scout_radius in
	# at construction, or if the evaluator cached a radius, the count would not have moved.
	s.scout_radius = 8
	check_eq(int(CapacityEvaluator.tag_counts(grid, empty, origin, s).get("cover", -1)), 2,
		"NEGATIVE CONTROL: retuning scout_radius back to 8 puts the count back to 2 — the "
		+ "sentinel tracks the field live in both directions, and nothing is cached")

	grid.free()


func _check_degenerate_inputs() -> void:
	# These are not edge-case trivia: each one is a data-entry mistake that would otherwise
	# read as "infinite capacity everywhere" rather than as a broken `.tres`.
	var no_needs: AnimalDefinition = _species("noneeds", [] as Array[String], 4, 8)
	check_eq(CapacityEvaluator.capacity_from_counts({}, no_needs), 0,
		"a species with NO habitat_needs has capacity 0, never unbounded")

	var zero_divisor: AnimalDefinition = _species("zerodiv", ["a"] as Array[String], 4, 8)
	zero_divisor.tiles_per_individual = 0
	check_eq(CapacityEvaluator.capacity_from_counts({"a": 100}, zero_divisor), 0,
		"tiles_per_individual == 0 yields 0, not a division blow-up or infinite capacity")

	check_eq(CapacityEvaluator.capacity_from_counts({"a": 100}, null), 0,
		"a null species is capacity 0")


# --- qualifies(h, S) === capacity(h, S) >= 1 ---------------------------------------------

func _check_qualifies_is_the_same_function() -> void:
	var grid: WorldGrid = _grid()
	var registry := HomeSiteRegistry.new()
	# 4 rock tiles per individual, so the sweep crosses the qualification boundary at 4.
	var s: AnimalDefinition = _species("sweep", ["cover"] as Array[String], 4, 8)
	var origin := Vector2i(18, 18)

	var mismatches: PackedStringArray = PackedStringArray()
	var saw_true: bool = false
	var saw_false: bool = false
	for n in SWEEP_MAX_ROCKS + 1:
		if n > 0:
			grid.set_terrain(origin.x + n - 1, origin.y, "rock")
		var cap: int = CapacityEvaluator.capacity(grid, registry, origin, s)
		var q: bool = CapacityEvaluator.qualifies(grid, registry, origin, s)
		if q != (cap >= 1):
			mismatches.append("%d rocks: capacity=%d qualifies=%s" % [n, cap, q])
		if q:
			saw_true = true
		else:
			saw_false = true

	check(mismatches.is_empty(),
		"qualifies() === capacity() >= 1 across a %d-step sweep — one function, not two systems"
			% (SWEEP_MAX_ROCKS + 1),
		"mismatches: %s" % str(mismatches))
	# Without these two, the check above passes vacuously if the sweep never crosses the
	# boundary — a green test that cannot fail.
	check(saw_false, "the sweep really did include NON-qualifying states (not vacuous)")
	check(saw_true, "the sweep really did include qualifying states (not vacuous)")

	# The exact boundary, spelled out: 3 rocks is nobody, 4 rocks is one.
	var boundary: WorldGrid = _grid()
	var empty := HomeSiteRegistry.new()
	for i in 3:
		boundary.set_terrain(10 + i, 10, "rock")
	check_eq(CapacityEvaluator.capacity(boundary, empty, Vector2i(10, 10), s), 0,
		"3 cover tiles at divisor 4: capacity 0, does not qualify")
	check(not CapacityEvaluator.qualifies(boundary, empty, Vector2i(10, 10), s),
		"...and qualifies() agrees")
	boundary.set_terrain(13, 10, "rock")
	check_eq(CapacityEvaluator.capacity(boundary, empty, Vector2i(10, 10), s), 1,
		"the 4th cover tile makes it capacity 1")
	check(CapacityEvaluator.qualifies(boundary, empty, Vector2i(10, 10), s),
		"...and qualifies() agrees")

	grid.free()
	boundary.free()


# --- The arrival predicate: capacity >= population + 1 -----------------------------------

func _check_arrival_predicate() -> void:
	var grid: WorldGrid = _grid()
	var registry := HomeSiteRegistry.new()
	var arrivals := ArrivalQueue.new(20260727)
	var species: AnimalDefinition = _species("predicate", ["cover"] as Array[String], 4, 8)
	var sim := HabitatSimulation.new()
	sim.attach(grid, SpeciesRoster.new([species]), registry, arrivals, null)

	var origin := Vector2i(18, 18)
	# 8 cover tiles at divisor 4 -> capacity 2. Chosen so the predicate can be exercised at
	# population 1 (enqueues) and population 2 (does not) without touching the land between.
	for i in 8:
		grid.set_terrain(origin.x - 4 + i, origin.y, "rock")

	var site: HomeSite = registry.register(origin, species.id, species.scout_radius)
	site.residents.append(null)  # population 1, with no model needed

	check_eq(sim.capacity_at(origin, species), 2, "site capacity is 2 (8 cover tiles / 4)")
	check_eq(sim.population_at(origin, species), 1, "site population is 1")

	sim.on_terraform(origin)
	sim.tick(0.0)
	check_eq(arrivals.size(), 1,
		"capacity 2 >= population 1 + 1 -> exactly one arrival enqueued")
	check(arrivals.has_pending(origin, species.id),
		"the pending arrival is for this site and this species")

	arrivals.clear()
	site.residents.append(null)  # population 2, capacity still 2
	sim.on_terraform(origin)
	sim.tick(0.0)
	check_eq(sim.capacity_at(origin, species), 2, "capacity is unchanged at 2")
	check_eq(sim.population_at(origin, species), 2, "population is now 2")
	check_eq(arrivals.size(), 0,
		"capacity 2 >= population 2 + 1 is FALSE -> nothing enqueued (a full site does not grow)")

	# And the predicate is strict, not >=: one more cover tile does not help, four do.
	grid.set_terrain(origin.x + 4, origin.y, "rock")   # 9 tiles -> still capacity 2
	sim.on_terraform(origin)
	sim.tick(0.0)
	check_eq(arrivals.size(), 0, "a 9th cover tile still yields capacity 2 — no arrival")
	for i in 3:
		grid.set_terrain(origin.x + 5 + i, origin.y, "rock")  # 12 tiles -> capacity 3
	sim.on_terraform(origin)
	sim.tick(0.0)
	check_eq(sim.capacity_at(origin, species), 3, "12 cover tiles / 4 == capacity 3")
	check_eq(arrivals.size(), 1, "capacity 3 >= population 2 + 1 -> one arrival enqueued")

	sim.free()
	grid.free()


# --- helpers ------------------------------------------------------------------------------

## A synthetic species. Built here, never loaded, so the formula's assertions are independent
## of every `.tres` on disk.
func _species(id: String, needs: Array[String], divisor: int, radius: int) -> AnimalDefinition:
	var def := AnimalDefinition.new()
	def.id = id
	def.display_name = id
	def.habitat_needs = needs
	def.tiles_per_individual = divisor
	def.scout_radius = radius
	return def


func _grid() -> WorldGrid:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 36, 36)
	return grid
