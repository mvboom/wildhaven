extends QATestCase
## MINIMAL AVOIDS — Tier 1 row 9's thin form, driven for the first time as its own suite.
##
## gdd.md -> Avoids (row 9's thin form): mutual distance-keeping for one real pair, symmetric
## by construction, and never a move-in gate — copy frames it as "keeps its distance," never
## as threat (the operational predation ban). D-29 #4 ruled the two constants (5-tile avoid
## distance, re-pathing piggybacked on row 6's wander-pause cadence); `resident_roamer.gd` and
## `resident_presentation.gd` landed the build the same day. **No suite exercised any of it
## before this one** — `tier1-status.md` row 9's own `validation_status` said so explicitly
## ("Not yet exercised by a dedicated test_avoids_*.gd suite — that's QA's step 4").
##
## FOUR THINGS ARE PINNED HERE, matching the human's own brief line for line:
##
##   1. THE BIAS IS GENUINELY AWAY FROM AN AVOIDED SPECIES, not merely "a bias exists somewhere
##      near it." `_pick_angle()`'s own contract is exact: once a threat is within
##      `AVOID_DISTANCE_TILES`, the chosen angle is drawn from `away_angle ± HALF_ARC` (90° each
##      side), so it can NEVER exceed 90° of true "away" — a hard geometric bound, not a
##      tendency. This suite recovers the REALISED waypoint exactly (a roamer's own `position`
##      the instant it arrives IS `_target`, verbatim — see `ResidentRoamer.tick()`) and checks
##      that bound on every single pick made while a threat was in reach, never on an average.
##   2. THE SYMMETRIC UNION HOLDS EVEN WHEN ONLY ONE SIDE DECLARES IT. The fixture gives
##      `predator.avoids = ["prey"]` and `prey.avoids = []` — asymmetric DATA — and proves BOTH
##      residents bias away from each other anyway, because `ResidentPresentation.
##      _nearby_avoid_positions()` checks both directions regardless of which one is asking.
##   3. AVOIDS NEVER GATES A MOVE-IN. A separate, small, real-causal-path check: the shipped
##      rabbit/fox pair (already mutual avoiders in the roster) both qualify and land through
##      `HabitatSimulation`'s ordinary arrival predicate at adjacent, deliberately-close habitat
##      — proving proximity between avoid-partners has no effect on `capacity(h, S)` or the
##      arrival queue, which is a structurally separate mechanism (`HabitatSimulation`'s own
##      source is checked to name nothing "avoid" at all).
##   4. NO ADDED PER-FRAME COST. `HabitatSimulation.evaluations_run` must not move while an
##      avoid-pair wanders near each other on the real `Main.tscn` (the same zero-cost
##      discipline `test_event_driven_simulation.gd` already holds every other system to), and
##      the number of wander-pause transitions over a long run is far below the frame count —
##      confirming the provider rides the existing cadence rather than a new timer.
##
## SYNTHETIC WHERE THE GEOMETRY MATTERS (checks 1-2 use two throwaway species so the angles are
## exact and reproducible), REAL WHERE THE WIRING MATTERS (checks 3-4 use the shipped roster and
## `scenes/Main.tscn`).
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_avoids_distance_keeping.gd

const SEED: int = 20260801
const STEP_SECONDS: float = 0.1
const RUN_SECONDS: float = 240.0

## D-29 #4's decided value, read off the shipped constant rather than restated as a literal.
const AVOID_DISTANCE: float = 5.0

## Half-width of the away cone `_pick_angle()` draws from. The hard bound every biased pick
## must satisfy is `angle_to(away) <= HALF_ARC`, with a small epsilon for float comparison.
const HALF_ARC: float = PI * 0.5
const ANGLE_EPSILON: float = 0.01

## Home sites 3 tiles apart — comfortably inside `AVOID_DISTANCE` (5) so both roamers' discs
## keep the other in reach for most of the run, and comfortably inside a wide (radius 8) wander
## disc so the bias has real room to express itself.
const HOME_A := Vector2i(18, 18)
const HOME_B := Vector2i(21, 18)
const WIDE_RADIUS: int = 8

## Where the "stops beyond the distance" half of check 1 re-homes the threat, and the tighter
## wander radius used only there — tight enough that even both roamers reaching the very edge
## of their own wander discs at once still cannot bridge the gap back within `AVOID_DISTANCE`.
const FAR_AWAY := Vector2i(18, 2)
const FAR_CHECK_RADIUS: int = 3

## The real, adjacent-habitat fixture for check 3 (never gates a move-in). Rabbit and fox are
## the shipped mutual-avoid pair (fox.tres avoids rabbit; rabbit.tres avoids fox).
const RABBIT_ROCK_ORIGIN := Vector2i(6, 7)
const FOX_FOREST_ORIGIN := Vector2i(10, 7)   # 4 tiles from the rabbit block: inside AVOID_DISTANCE

var _grid: WorldGrid = null
var _props_root: Node3D = null
var _presentation: ResidentPresentation = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("avoids distance-keeping")

	_grid = WorldGrid.new()
	_grid.build(TerrainDefinition.load_all(), 36, 36)
	root.add_child(_grid)

	_props_root = Node3D.new()
	root.add_child(_props_root)

	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	_check_bias_is_bounded_and_symmetric_from_asymmetric_data()
	_check_bias_stops_beyond_the_avoid_distance()
	_check_avoids_never_gates_a_move_in()
	_check_no_added_per_frame_cost()

	finish()
	return true


# --- 1 + 2. The bias is genuinely away, and the union is symmetric from one-sided data -------------

func _check_bias_is_bounded_and_symmetric_from_asymmetric_data() -> void:
	var predator: AnimalDefinition = _species("predator", ["prey"] as Array[String])
	var prey: AnimalDefinition = _species("prey", [] as Array[String])  # ASYMMETRIC on purpose
	var roster := SpeciesRoster.new([predator, prey])

	var presentation := ResidentPresentation.new()
	presentation.attach(_grid, _props_root, SEED, roster)

	var site_a := HomeSite.new(HOME_A, "predator", WIDE_RADIUS, 0)
	var site_b := HomeSite.new(HOME_B, "prey", WIDE_RADIUS, 1)
	var node_a: Node3D = predator.model_scenes[0].instantiate() as Node3D
	node_a.position = _grid.tile_to_world(HOME_A.x, HOME_A.y)
	root.add_child(node_a)
	var node_b: Node3D = prey.model_scenes[0].instantiate() as Node3D
	node_b.position = _grid.tile_to_world(HOME_B.x, HOME_B.y)
	root.add_child(node_b)

	# Presented in this order deliberately: `roamer(0)` is the predator, `roamer(1)` is the prey,
	# and both are ticked BY HAND, individually, in that same order every step — so whichever one
	# reads the other's position (the provider is live, not cached) always reads a position this
	# suite can name exactly, rather than depending on `ResidentPresentation`'s own internal
	# iteration order.
	presentation.present(node_a, site_a)
	presentation.present(node_b, site_b)
	var predator_roamer: ResidentRoamer = presentation.roamer(0)
	var prey_roamer: ResidentRoamer = presentation.roamer(1)
	check(predator_roamer != null and prey_roamer != null, "both roamers were created")
	check_eq(predator_roamer.avoid_ids(), ["prey"] as Array[String],
		"the predator's OWN avoids list names the prey")
	check_eq(prey_roamer.avoid_ids(), [] as Array[String],
		"...and the prey's own avoids list is EMPTY — the asymmetric data this check is built on")

	var result: Dictionary = _drive_and_recover_picks(predator_roamer, prey_roamer, RUN_SECONDS)
	var predator_picks: Array[Dictionary] = result["a"]
	var prey_picks: Array[Dictionary] = result["b"]

	check(predator_picks.size() >= 10,
		"the predator made a real number of waypoint picks over the run (%d)" % predator_picks.size())
	check(prey_picks.size() >= 10,
		"...and so did the prey (%d)" % prey_picks.size())

	# CHECK 1: every pick made while the other was within AVOID_DISTANCE is bounded to the away
	# cone, EXACTLY — recovered from the roamer's own arrival position, not re-derived from the
	# implementation's `atan2` (which would share any sign error with it).
	_assert_all_picks_within_arc(predator_picks, "the predator (declares `avoids = [\"prey\"]`)")

	# CHECK 2: THE SYMMETRIC UNION. The prey's OWN avoids list is empty, so if the resolver only
	# ever consulted the requester's own list, the prey would pick uniformly at random and this
	# would fail close to half the time over enough samples. It does not: the prey biases away
	# from the predator too, purely because the PREDATOR's list names it — proving the union is
	# resolved both ways, exactly as `_nearby_avoid_positions()`'s own header states.
	_assert_all_picks_within_arc(prey_picks,
		"the prey (its OWN `avoids` list is empty — this is the symmetric union, not its own data)")

	node_a.free()
	node_b.free()
	presentation.free()


func _assert_all_picks_within_arc(picks: Array[Dictionary], who: String) -> void:
	var in_reach: int = 0
	var violations: PackedStringArray = PackedStringArray()
	var worst: float = 0.0
	for pick: Dictionary in picks:
		if not bool(pick["in_reach"]):
			continue
		in_reach += 1
		var diff: float = absf(_angle_diff(float(pick["picked_angle"]), float(pick["away_angle"])))
		worst = maxf(worst, diff)
		if diff > HALF_ARC + ANGLE_EPSILON:
			violations.append("pick #%d: %.3f rad off (limit %.3f)" % [pick["index"], diff, HALF_ARC])

	check(in_reach > 0,
		"%s: NON-VACUITY — at least one pick happened while the other was within %.0f tiles (%d of %d)"
			% [who, AVOID_DISTANCE, in_reach, picks.size()])
	check(violations.is_empty(),
		"%s: EVERY in-reach pick is bounded to the away cone (<= %.3f rad of true away, worst %.3f)"
			% [who, HALF_ARC, worst],
		"violations: %s" % str(violations))

	# NON-VACUITY for the bound itself: the picks are not all sitting exactly on the away angle
	# (which a broken "always straight away, no randomisation" implementation would also pass
	# with zero violations) — the whole HALF_ARC cone is actually being sampled from.
	var spread: float = 0.0
	for pick: Dictionary in picks:
		if bool(pick["in_reach"]):
			spread = maxf(spread, absf(_angle_diff(float(pick["picked_angle"]), float(pick["away_angle"]))))
	check(spread > HALF_ARC * 0.25,
		"%s: ...and the cone is really sampled, not collapsed onto one exact angle (widest sample "
			% who + "%.3f rad off dead-away)" % spread)


# --- 1b. The bias stops beyond AVOID_DISTANCE_TILES -------------------------------------------------

func _check_bias_stops_beyond_the_avoid_distance() -> void:
	var predator: AnimalDefinition = _species("predator", ["prey"] as Array[String])
	var prey: AnimalDefinition = _species("prey", [] as Array[String])
	var roster := SpeciesRoster.new([predator, prey])

	var presentation := ResidentPresentation.new()
	presentation.attach(_grid, _props_root, SEED, roster)

	var site_a := HomeSite.new(HOME_A, "predator", FAR_CHECK_RADIUS, 0)
	var site_b := HomeSite.new(FAR_AWAY, "prey", FAR_CHECK_RADIUS, 1)  # far outside AVOID_DISTANCE
	check(float(HOME_A.distance_to(FAR_AWAY)) > AVOID_DISTANCE + float(FAR_CHECK_RADIUS) * 2.0,
		"the control site is placed well outside any reach the wander discs could bridge")

	var node_a: Node3D = predator.model_scenes[0].instantiate() as Node3D
	node_a.position = _grid.tile_to_world(HOME_A.x, HOME_A.y)
	root.add_child(node_a)
	var node_b: Node3D = prey.model_scenes[0].instantiate() as Node3D
	node_b.position = _grid.tile_to_world(FAR_AWAY.x, FAR_AWAY.y)
	root.add_child(node_b)
	presentation.present(node_a, site_a)
	presentation.present(node_b, site_b)
	var predator_roamer: ResidentRoamer = presentation.roamer(0)
	var prey_roamer: ResidentRoamer = presentation.roamer(1)

	var result: Dictionary = _drive_and_recover_picks(predator_roamer, prey_roamer, RUN_SECONDS)
	var predator_picks: Array[Dictionary] = result["a"]

	var never_in_reach: bool = true
	for pick: Dictionary in predator_picks:
		if bool(pick["in_reach"]):
			never_in_reach = false
	check(never_in_reach,
		"THE GATE HOLDS: with the prey re-homed outside %.0f tiles, NONE of the predator's %d "
			% [AVOID_DISTANCE, predator_picks.size()]
		+ "picks ever saw it as in-reach — the same predator, the same declared avoid, no bias "
		+ "left to apply")

	# And a fresh uniform sample (no provider bound at all) shows the UNBIASED distribution really
	# does put a meaningful fraction outside the away cone — proving the bound in check 1 was a
	# real constraint on a distribution that would otherwise violate it, not a coincidence of the
	# geometry.
	var uniform_violations: int = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for _i in 200:
		var away_angle: float = rng.randf_range(0.0, TAU)  # an arbitrary reference direction
		var sampled: float = rng.randf_range(0.0, TAU)     # true uniform pick, no bias
		if absf(_angle_diff(sampled, away_angle)) > HALF_ARC + ANGLE_EPSILON:
			uniform_violations += 1
	check(uniform_violations > 40,
		"CONTROL: a genuinely uniform pick lands outside the same %.3f rad cone often (%d of 200) — "
			% [HALF_ARC, uniform_violations]
		+ "so check 1's zero violations is a real bound holding, not a wide cone nothing could miss")

	node_a.free()
	node_b.free()
	presentation.free()


# --- 3. Avoids never gates a move-in ----------------------------------------------------------------

func _check_avoids_never_gates_a_move_in() -> void:
	# STRUCTURAL: the simulation's own CODE (comments stripped, so a header note that merely
	# mentions row 9 in passing cannot satisfy or defeat this) names nothing "avoid" at all — the
	# coupling this row's `implementation_location` describes ("no change to `HabitatSimulation`
	# ... avoids never gates a move-in, so it never touches the qualification/arrival path") is
	# checked directly against the file, not taken on the build report's word.
	var sim_source: String = _strip_comments(
		(load("res://scripts/simulation/habitat_simulation.gd") as GDScript).source_code)
	check(not sim_source.to_lower().contains("avoid"),
		"`HabitatSimulation`'s own CODE names nothing \"avoid\" — the arrival predicate has no "
		+ "hook for it to gate through")
	var queue_source: String = _strip_comments(
		(load("res://scripts/simulation/arrival_queue.gd") as GDScript).source_code)
	check(not queue_source.to_lower().contains("avoid"),
		"...and neither does `ArrivalQueue`")

	# REAL, CAUSAL: the shipped rabbit/fox pair (already mutual avoiders — fox.tres avoids
	# rabbit, rabbit.tres avoids fox) both qualify and land through the ordinary arrival path at
	# DELIBERATELY adjacent habitat, closer together than `AVOID_DISTANCE_TILES` — proximity
	# between declared avoid-partners must cost neither of them a move-in.
	var packed: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	var world: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(world)
	world.presentation.set_process(false)
	world.simulation.set_process(false)

	var rabbit: AnimalDefinition = world.roster.by_id("rabbit")
	var fox: AnimalDefinition = world.roster.by_id("fox")
	check(rabbit.normalized_avoids().has("fox"), "the shipped rabbit avoids the shipped fox")
	check(fox.normalized_avoids().has("rabbit"), "...and the shipped fox avoids the shipped rabbit")

	for dx in 4:
		for dz in 3:
			world.paint_tile(RABBIT_ROCK_ORIGIN.x + dx, RABBIT_ROCK_ORIGIN.y + dz, "rock")
			world.paint_tile(RABBIT_ROCK_ORIGIN.x + dx, RABBIT_ROCK_ORIGIN.y + dz + 4, "grass")
	for dx in 4:
		for dz in 3:
			world.paint_tile(FOX_FOREST_ORIGIN.x + dx, FOX_FOREST_ORIGIN.y + dz, "forest")
			world.paint_tile(FOX_FOREST_ORIGIN.x + dx, FOX_FOREST_ORIGIN.y + dz + 4, "rock")

	check(world.capacity_at(RABBIT_ROCK_ORIGIN.x, RABBIT_ROCK_ORIGIN.y, "rabbit") >= 1,
		"the rabbit habitat qualifies on its own")
	check(world.capacity_at(FOX_FOREST_ORIGIN.x, FOX_FOREST_ORIGIN.y, "fox") >= 1,
		"...and the fox habitat, right beside it, qualifies too")
	check(float(RABBIT_ROCK_ORIGIN.distance_to(FOX_FOREST_ORIGIN)) < AVOID_DISTANCE,
		"...and the two sites are CLOSER than the avoid distance (%.1f tiles apart), so this is "
		% RABBIT_ROCK_ORIGIN.distance_to(FOX_FOREST_ORIGIN) + "the scenario avoids exists to keep gentle, not to prevent")

	for _i in 200:
		world.simulation.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)

	check(world.total_residents() >= 2, "at least two residents landed (%d)" % world.total_residents())
	var ids: Array[String] = world.resident_species_ids()
	check(ids.has("rabbit"), "...and a rabbit is among them — the fox nearby did not block it")
	check(ids.has("fox"), "...and a fox is among them — the rabbit nearby did not block it either")

	world.free()


# --- 4. No added per-frame cost ---------------------------------------------------------------------

func _check_no_added_per_frame_cost() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	var world: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(world)

	for dx in 4:
		for dz in 3:
			world.paint_tile(RABBIT_ROCK_ORIGIN.x + dx, RABBIT_ROCK_ORIGIN.y + dz, "rock")
			world.paint_tile(RABBIT_ROCK_ORIGIN.x + dx, RABBIT_ROCK_ORIGIN.y + dz + 4, "grass")
	for dx in 4:
		for dz in 3:
			world.paint_tile(FOX_FOREST_ORIGIN.x + dx, FOX_FOREST_ORIGIN.y + dz, "forest")
	for _i in 200:
		world.simulation.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)
	check(world.total_residents() >= 2,
		"the avoid-pair fixture landed at least two residents (%d) before the cost measurement"
			% world.total_residents())

	world.simulation.set_process(false)  # isolate: this check is about PRESENTATION's own cost
	var evaluations_before: int = world.simulation.evaluations_run
	var pending_before: int = world.simulation.pending_evaluations()

	var transitions: int = 0
	var steps: int = int(RUN_SECONDS / STEP_SECONDS)
	var roamer_count: int = world.presentation.roamer_count()
	var previous_states: Dictionary = {}
	for i in roamer_count:
		previous_states[i] = world.presentation.roamer(i).state_name()
	for _i in steps:
		world.presentation.tick(STEP_SECONDS)
		for i in roamer_count:
			var roamer: ResidentRoamer = world.presentation.roamer(i)
			var state: String = roamer.state_name()
			if state != previous_states.get(i, state):
				transitions += 1
			previous_states[i] = state

	check_eq(world.simulation.evaluations_run, evaluations_before,
		"%d steps of an avoid-pair wandering near each other moved `evaluations_run` by EXACTLY 0 "
			% steps + "— presentation, including the avoids bias, cannot mark a neighbourhood dirty")
	check_eq(world.simulation.pending_evaluations(), pending_before, "...and enqueued nothing")

	# The provider rides the EXISTING wander-pause cadence, not a new per-frame timer: over this
	# many steps the number of state transitions, summed across every roamer presentation is
	# tracking, is far below one-per-roamer-per-frame, which a per-frame re-evaluation would not
	# be. The bound is PER ROAMER (not a fixed constant): `roamer_count` depends on how many
	# residents this fixture's habitat can hold, which is no longer a fixed population once
	# home-site exclusivity is scoped per species (2026-08-17) — a Fox and a Rabbit next to each
	# other no longer compete for the same land, so more of both legitimately settle here than
	# the historical ~7. The cadence invariant is about each roamer's own transition rate, not
	# the headcount, so it is asserted per-roamer.
	check(transitions > 0, "wander really ran (%d Idle<->Walk transitions)" % transitions)
	check(roamer_count > 0, "the fixture actually has roamers to measure (%d)" % roamer_count)
	check(transitions < roamer_count * steps / 4,
		("THE PROVIDER PIGGYBACKS ON THE WANDER-PAUSE CADENCE, NOT A NEW TIMER: %d transitions "
			% transitions) + ("across %d frames and %d roamers (%.2f/roamer) — nowhere near one "
			% [steps, roamer_count, float(transitions) / roamer_count]) + "evaluation per roamer-frame")

	world.free()


# --- helpers ------------------------------------------------------------------------------------------

func _species(id: String, avoid_ids: Array[String]) -> AnimalDefinition:
	var species := AnimalDefinition.new()
	species.id = id
	species.display_name = id.capitalize()
	species.habitat_needs = ["cover"] as Array[String]
	species.tiles_per_individual = 4
	species.scout_radius = WIDE_RADIUS
	species.avoids = avoid_ids
	species.model_scenes = [load("res://assets/placeholder/grass/Grass.tscn") as PackedScene]
	return species


## Drives two roamers by hand, individually, in a fixed order (`a` then `b` every step), and
## recovers every waypoint EXACTLY: a roamer's `position` the instant it transitions Walk -> Idle
## (arrival) is `_target` itself, verbatim (`ResidentRoamer.tick()` snaps to it on arrival rather
## than approaching asymptotically) — so the "picked angle" is read off the engine's own state,
## never re-derived from the implementation's own formula.
##
## Returns `{"a": Array[Dictionary], "b": Array[Dictionary]}`, one entry per REALISED pick for
## each roamer: `{"index": int, "in_reach": bool, "picked_angle": float, "away_angle": float}`.
func _drive_and_recover_picks(a: ResidentRoamer, b: ResidentRoamer, run_seconds: float) -> Dictionary:
	var picks_a: Array[Dictionary] = []
	var picks_b: Array[Dictionary] = []
	var pending_a: Dictionary = {}
	var pending_b: Dictionary = {}
	var state_a: String = a.state_name()
	var state_b: String = b.state_name()

	var steps: int = int(run_seconds / STEP_SECONDS)
	for _i in steps:
		# `a` first: its provider reads `b`'s position exactly as it stands right now, before `b`
		# has moved this step. `in_reach` is measured from `a`'s OWN CURRENT position — exactly
		# what `ResidentPresentation._nearby_avoid_positions()` measures from (`origin =
		# requester.resident().position`), which is generally NOT `a.home()`: a resident can be
		# anywhere in its own wander disc when the next pick happens. The AWAY ANGLE, separately,
		# really is relative to home — `_pick_angle()`'s own `_home.x - threat.x` term — so this
		# helper deliberately uses two different reference points for the two different numbers,
		# matching the two different reference points the implementation itself uses.
		var a_position_before: Vector3 = a.resident().position
		var b_position: Vector3 = b.resident().position
		a.tick(STEP_SECONDS)
		var new_state_a: String = a.state_name()
		if state_a == "Idle" and new_state_a == "Walk":
			var distance: float = Vector2(
				a_position_before.x - b_position.x, a_position_before.z - b_position.z
			).length()
			pending_a = {
				"in_reach": distance <= AVOID_DISTANCE,
				"away_angle": _away_angle(a.home(), b_position),
			}
		if state_a == "Walk" and new_state_a == "Idle" and not pending_a.is_empty():
			picks_a.append({
				"index": picks_a.size(),
				"in_reach": pending_a["in_reach"],
				"away_angle": pending_a["away_angle"],
				"picked_angle": _angle_of(a.home(), a.resident().position),
			})
			pending_a = {}
		state_a = new_state_a

		# `b` second: its provider now reads `a`'s ALREADY-UPDATED position for this step, which
		# is exactly what a live world would show it too. Same two-reference-point rule as above.
		var b_position_before: Vector3 = b.resident().position
		var a_position: Vector3 = a.resident().position
		b.tick(STEP_SECONDS)
		var new_state_b: String = b.state_name()
		if state_b == "Idle" and new_state_b == "Walk":
			var distance_b: float = Vector2(
				b_position_before.x - a_position.x, b_position_before.z - a_position.z
			).length()
			pending_b = {
				"in_reach": distance_b <= AVOID_DISTANCE,
				"away_angle": _away_angle(b.home(), a_position),
			}
		if state_b == "Walk" and new_state_b == "Idle" and not pending_b.is_empty():
			picks_b.append({
				"index": picks_b.size(),
				"in_reach": pending_b["in_reach"],
				"away_angle": pending_b["away_angle"],
				"picked_angle": _angle_of(b.home(), b.resident().position),
			})
			pending_b = {}
		state_b = new_state_b

	return {"a": picks_a, "b": picks_b}


## The angle from `home` to `point`, in the same (x -> cos, z -> sin) convention
## `ResidentRoamer._pick_waypoint()` itself uses.
func _angle_of(home: Vector3, point: Vector3) -> float:
	return atan2(point.z - home.z, point.x - home.x)


## `_pick_angle()`'s own "away" direction: from the threat toward home.
func _away_angle(home: Vector3, threat: Vector3) -> float:
	return atan2(home.z - threat.z, home.x - threat.x)


## Signed shortest angular difference, wrapped to (-PI, PI].
func _angle_diff(a: float, b: float) -> float:
	return wrapf(a - b, -PI, PI)


## Strips `#`-comments so a structural source check cannot be satisfied (or defeated) by prose —
## the same helper `test_gentle_displacement.gd` and `test_removal_refund.gd` already use for the
## same reason.
func _strip_comments(source: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line: String in source.split("\n"):
		var hash_at: int = line.find("#")
		out.append(line if hash_at < 0 else line.substr(0, hash_at))
	return "\n".join(out)
