extends QATestCase
## STALL-PROOF WANDER — a WALKING resident must ALWAYS either arrive or give the leg up.
##
## THE BUG THIS SUITE PINS (found 2026-09-08). `ResidentRoamer._separation_nudge()` summed an
## uncapped push from every neighbour within `SEPARATION_DISTANCE_TILES`, and
## `SEPARATION_STRENGTH_TILES_PER_SECOND` is the same 0.6 as `WALK_SPEED_TILES_PER_SECOND`. Two
## or three neighbours therefore cancelled the forward step exactly. Because a PAUSED resident
## is never nudged itself, a cluster of standing animals is an immovable wall, so the
## cancellation is a STABLE equilibrium rather than a transient jostle — and because `tick()`'s
## WALKING branch had no exit but arrival, the leg never ended.
##
## The visible symptom was the worst possible shape: `AnimationPlayer` runs off the engine's
## clock, not off `tick()`, so the walk clip kept looping at full speed over a position frozen
## to the bit. An animal marching on the spot forever.
##
## Measured before the fix: three stationary neighbours on the target corner froze the walker
## at x=1.740591, IDENTICAL at t=100s through t=600s of simulated time.
##
## TWO INDEPENDENT GUARANTEES, and this suite asserts each on its own:
##   1. `SEPARATION_MAX_STEP_FRACTION` caps the summed push strictly below the travel step, so
##      net progress toward the corner is arithmetically guaranteed. Fixes the known cause.
##   2. The no-progress watchdog abandons a leg that stops advancing whatever the reason. A
##      backstop against causes nobody has found yet — the same defence-in-depth shape
##      `_ensure_playing()` already has against a frozen locomotion clip.
##
## Check 3 exists so the fix cannot be "delete the feature": soft steering must still visibly
## steer.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_roamer_stall.gd

const STEP_SECONDS: float = 1.0 / 60.0

## 60 simulated seconds. Enormously longer than any honest leg (the whole wander disc is 3
## tiles and walk speed is 0.6 tiles/second, so a full-diameter leg is ~10s), so a roamer still
## WALKING at the end is stuck, not slow.
const RUN_SECONDS: float = 60.0
const TICKS: int = int(RUN_SECONDS / STEP_SECONDS)

const CORNER := Vector3(2.0, 0.0, 0.0)

var _neighbours: Array[Vector3] = []


func _provider() -> Array[Vector3]:
	return _neighbours


func _make_roamer(at: Vector3) -> ResidentRoamer:
	var node := Node3D.new()
	node.position = at
	root.add_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260908
	var roamer := ResidentRoamer.new(node, Vector3.ZERO, 3.0, Rect2(), rng)
	roamer.set_nearby_resident_provider(Callable(self, "_provider"))
	return roamer


## Puts the roamer on a known straight leg, bypassing the pause dice so every measurement below
## is about the WALKING branch and nothing else. Reaches past the public API deliberately:
## `_begin_walk()` picks its waypoint at random, and a random corner cannot pin a deadlock.
func _force_walk(roamer: ResidentRoamer, corner: Vector3) -> void:
	roamer._path = PackedVector3Array([corner])
	roamer._path_index = 0
	roamer._state = ResidentRoamer.State.WALKING
	roamer._travel_speed = ResidentRoamer.WALK_SPEED_TILES_PER_SECOND


## Ticks until the roamer leaves WALKING or `TICKS` runs out. Returns the tick count reached.
func _walk_until_done(roamer: ResidentRoamer) -> int:
	for i in TICKS:
		roamer.tick(STEP_SECONDS)
		if roamer.state_name() != "Walk":
			return i + 1
	return TICKS


func _initialize() -> void:
	begin("test_roamer_stall")

	# --- 1. The deadlock itself ----------------------------------------------------------
	# Three stationary neighbours clustered on the target corner: the exact geometry that
	# froze a walker forever. A den with an arrival group standing around it IS this shape.
	_neighbours = [
		Vector3(2.0, 0.0, 0.0), Vector3(2.15, 0.0, 0.2), Vector3(2.15, 0.0, -0.2)
	] as Array[Vector3]
	var crowded := _make_roamer(Vector3.ZERO)
	_force_walk(crowded, CORNER)
	var crowded_ticks: int = _walk_until_done(crowded)
	check(
		crowded_ticks < TICKS,
		"a walker crowded by three stationary neighbours finishes its leg",
		"still WALKING after %.0fs at %s" % [RUN_SECONDS, crowded.resident().position]
	)
	check(
		crowded.resident().position.distance_to(CORNER) <= ResidentRoamer.ARRIVAL_EPSILON_TILES,
		"it finishes by ARRIVING, not by timing out",
		"ended %.4f tiles from the corner" % crowded.resident().position.distance_to(CORNER)
	)

	# --- 2. The uncrowded control is untouched -------------------------------------------
	_neighbours = [] as Array[Vector3]
	var clear := _make_roamer(Vector3.ZERO)
	_force_walk(clear, CORNER)
	var clear_ticks: int = _walk_until_done(clear)
	check(clear_ticks < TICKS, "an uncrowded walker still arrives", "")
	check(
		clear.resident().position.is_equal_approx(CORNER),
		"and lands exactly on its corner",
		str(clear.resident().position)
	)

	# --- 3. Soft steering still steers ---------------------------------------------------
	# The cap must not be so tight that separation stops doing its job. One neighbour offset
	# from the straight line should visibly bend the path around it.
	_neighbours = [Vector3(1.0, 0.0, 0.3)] as Array[Vector3]
	var steered := _make_roamer(Vector3.ZERO)
	_force_walk(steered, CORNER)
	var max_deviation: float = 0.0
	for i in TICKS:
		steered.tick(STEP_SECONDS)
		max_deviation = maxf(max_deviation, absf(steered.resident().position.z))
		if steered.state_name() != "Walk":
			break
	check(
		max_deviation > 0.05,
		"separation still visibly pushes a walker off a straight line",
		"max perpendicular deviation was only %.4f tiles" % max_deviation
	)

	# --- 4. The watchdog, on a leg that is hopeless for ANY reason ------------------------
	# Progress is denied outright here — the node is pinned back to its start after every
	# tick. No separation is involved at all; this asserts the backstop, not the cap. A
	# roamer must give the leg up and go back to Idle rather than march on the spot.
	_neighbours = [] as Array[Vector3]
	var pinned := _make_roamer(Vector3.ZERO)
	_force_walk(pinned, CORNER)
	var gave_up_after: float = -1.0
	for i in TICKS:
		pinned.tick(STEP_SECONDS)
		pinned.resident().position = Vector3.ZERO  # something, anything, prevents movement
		if pinned.state_name() != "Walk":
			gave_up_after = float(i + 1) * STEP_SECONDS
			break
	check(
		gave_up_after >= 0.0,
		"a walker that cannot make progress gives the leg up instead of marching in place",
		"still WALKING after %.0f simulated seconds" % RUN_SECONDS
	)
	if gave_up_after >= 0.0:
		print("      gave up after %.2fs (timeout is %.2fs)" % [
			gave_up_after, ResidentRoamer.STALL_TIMEOUT_SECONDS
		])

	finish()
