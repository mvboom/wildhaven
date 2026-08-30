extends QATestCase
## THE PERFORMANCE GUARANTEE — Tier 1 row 6's invariant, and the assertion the whole CPU
## argument in gdd.md -> Technical Overview -> Performance rests on:
##
##   "The CPU side is no longer a scaling risk: habitat qualification is event-driven, so an
##    idle world does no simulation work, and a single player action costs
##    `scout_radius x roster size` — independent of world size. The dirty-neighbourhood queue
##    drains a bounded number of evaluations per frame; that queue *is* the CPU budget."
##
## Four things are pinned here:
##   1. AN IDLE WORLD DOES ZERO WORK — ticked repeatedly with no edits, `evaluations_run`
##      does not move at all. Not "little work"; zero.
##   2. THE TRIGGER SET IS EXACTLY FOUR — terraform, building add/remove, resident arrive,
##      resident depart. Asserted as a SET equality against the script's own method list, so
##      a fifth trigger (a mist reveal, a harvest, a timer) fails this suite by existing,
##      rather than being caught only if someone thought to test for it. -> D-22.
##   3. THE DRAIN IS BOUNDED — at most `MAX_EVALUATIONS_PER_FRAME` per tick, with the rest
##      left queued. The fallback when the budget is exceeded is a slower drain, never a
##      frame spike.
##   4. A PENDING ARRIVAL THAT DE-QUALIFIES BEFORE IT COMES DUE IS SILENTLY DROPPED — no
##      resident, and no warning of any kind. gdd.md: "nothing had moved in, so there is
##      nothing to explain — Pillar 1's no-unexplained-vanish rule governs residents, not
##      un-arrived animals."
##   6. **A SETTLEMENT TIMER IS NOT IDLE WORK EITHER** (added with row 10, 2026-07-28). Gentle
##      Displacement introduced the first countdown in the build, and a countdown is exactly the
##      shape that quietly reintroduces per-frame work. Two things keep the zero: `advance()`
##      returns on its first line when no gesture is open, and a gesture is only ever opened for
##      an edit touching a neighbourhood **someone actually lives in** — so a resident-free world
##      never opens one in its life. Both are driven here, and the second is verified
##      independently of the row 10 dispatch's own claim about it.
##   5. **A WANDERING RESIDENT IS NOT SIMULATION WORK.** Row 6's waypoint wander moves an
##      animal every frame of every idle world, and motion is PRESENTATION: a resident moving
##      is not one of the four triggers, so it must not mark a neighbourhood dirty and must
##      not move `evaluations_run` by one. If it ever did, the zero above would be
##      unreachable in any world that has a resident in it — which is every world after the
##      first minute of play — and gdd.md -> Performance's whole CPU argument would be void.
##
## CHECK 5 IS ASSERTED TWICE, AND THE SECOND WAY IS THE ONE THAT MATTERS. Hand-driving
## `ResidentPresentation.tick()` proves the roamer's own code is clean. But in the shipping
## build the motion is driven by the engine calling `_process` on `ResidentPresentation`, and
## the simulation's `_process` is running on the same frames — that is the arrangement that
## could regress silently, so it is measured directly, over **natural frames**, with nothing
## in this suite calling `tick()` at all during the window. `Engine.time_scale` buys simulated
## seconds inside a reasonable wall clock; every `_process` call in that window is the
## engine's own.
##
## Checks 1-4 are driven with a SYNTHETIC one-species roster so the assertions do not move when
## the shipped roster is retuned, and with `HabitatSimulation.tick()` called by hand so a whole
## arrival delay passes in one call instead of in real frames. Check 5 needs the real
## `Main.tscn`, because the coupling it is testing for is a wiring question.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_event_driven_simulation.gd

## gdd.md -> Habitat Suitability names these four and no others (-> D-22).
const EXPECTED_TRIGGERS: Array[String] = [
	"on_building_changed",
	"on_resident_arrived",
	"on_resident_departed",
	"on_terraform",
]

## How long an idle world is ticked before the zero is asserted. Deliberately long in
## simulated seconds (200 x 5 s ~= 16 minutes of world time) and cheap in wall clock.
const IDLE_TICKS: int = 200
const IDLE_TICK_SECONDS: float = 5.0

# --- Check 5's fixture: a real world with a real resident walking around in it ------------------

const WORLD_PATH: String = "res://scenes/Main.tscn"

## The rabbit's habitat, near the middle of the 36x36 start.
##
## RE-POINTED 2026-08-01 (-> D-29 #1, `WorldGrid.START_TERRAIN_ID` "grass" -> "wild_grass").
## This fixture used to rely on the world's old ambient `grass` backdrop to supply the
## `open_grass` half of the rabbit's `["open_grass", "cover"]` needs implicitly — painting only
## the `cover` (rock) block was enough because every OTHER tile in scout radius was already
## `grass`. `wild_grass` emits no tags at all (the inert-land invariant this same reversal is
## for), so that implicit supply is gone: with only rock painted, `open_grass` count is 0,
## capacity is `min(0, cover) / 4 == 0`, no rabbit ever qualifies, no arrival ever lands, and the
## natural-frame half below then dereferences a null `_resident` every frame — a stale
## assumption, not a defect in the D-29 change. Fixed by painting an explicit border of `grass`
## around the rock block, so the fixture states its own habitat rather than borrowing the
## world's default. The assertion this buys — wander must not move `evaluations_run` — is
## unchanged; only how the fixture gets a resident to wander is.
const WANDER_ROCK_ORIGIN := Vector2i(16, 17)
const WANDER_ROCK_W: int = 4
const WANDER_ROCK_D: int = 3
## Width of the explicit `grass` border painted around the rock block, in tiles. 1 tile all the
## way round a 4x3 rock block yields 18 grass tiles — comfortably above the 4 needed to clear
## `tiles_per_individual` for the `open_grass` need with margin to spare.
const WANDER_GRASS_MARGIN: int = 1

## Hand-driven wander: 120 simulated seconds at a fixed step.
const HAND_WANDER_STEP: float = 0.1
const HAND_WANDER_SECONDS: float = 120.0

## Natural-frame wander. `Engine.time_scale` scales the delta the engine hands `_process`, so
## these are real frames carrying more world time each — nothing here is hand-ticked.
const NATURAL_TIME_SCALE: float = 20.0
const NATURAL_TARGET_SECONDS: float = 120.0
const NATURAL_FRAME_CAP: int = 20000
## The control that stops the zero being vacuous: how many natural frames a dirtied
## neighbourhood is given to prove the simulation's own `_process` was live all along.
const CONTROL_FRAME_CAP: int = 300

var _world: WorldRoot = null
var _resident: Node3D = null
var _phase: int = 0
var _frames: int = 0

var _natural_frames: int = 0
var _natural_seconds: float = 0.0
var _natural_path: float = 0.0
var _natural_previous: Vector3 = Vector3.ZERO
var _natural_evaluations_at_start: int = 0
var _natural_evaluations_max: int = 0
var _natural_left_idle: int = 0
var _control_frames: int = 0
var _control_from: int = 0


func _init() -> void:
	begin("event-driven simulation")

	_check_idle_world_does_zero_work()
	_check_trigger_set_is_exactly_four()
	_check_mist_reveal_cannot_be_a_trigger()
	_check_drain_is_bounded()
	_check_dequalified_arrival_is_silently_dropped()
	_check_settlement_timers_are_not_idle_work()


## Check 5 needs a running tree and real frames, so it lives out here rather than in `_init()`.
func _initialize() -> void:
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads (check 5's fixture)" % WORLD_PATH):
		_finish_with_pendings()
		return
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		_finish_with_pendings()
		return
	_world = node as WorldRoot
	root.add_child(_world)


func _process(_delta: float) -> bool:
	if _world == null:
		return true
	_frames += 1
	if _frames < 3:
		return false

	match _phase:
		0:
			if not _check_wander_is_not_simulation_work_hand_driven():
				# The precondition failed and was already reported via `check()` above; stop
				# here rather than entering the natural-frame phase with a null `_resident`
				# (see the hardening note on the function itself).
				Engine.time_scale = 1.0
				_finish_with_pendings()
				return true
			_begin_natural_window()
			_phase = 1
		1:
			if _accumulate_natural_frame(_delta):
				_check_wander_is_not_simulation_work_natural_frames()
				_begin_control_window()
				_phase = 2
		2:
			if _accumulate_control_frame():
				_check_the_simulation_was_awake_the_whole_time()
				_phase = 3
		_:
			Engine.time_scale = 1.0
			_finish_with_pendings()
			return true
	return false


func _finish_with_pendings() -> void:
	note_expected_pending(
		"MIST (Tier 1 row 13) is not built, so the non-trigger is asserted structurally",
		"There is no reveal to fire, so this suite pins the trigger SET (exactly four) and the "
		+ "structural reason a reveal could never matter: revealed land is wild grass, whose "
		+ "derived BARE_TAGS is empty. When row 13 lands, the trigger-set assertion is what "
		+ "stops a reveal being wired in as a fifth trigger."
	)
	note_expected_pending(
		"GENTLE DISPLACEMENT (row 10) LANDED 2026-07-28 — this suite now guards its CPU cost",
		"The old note here said row 10 was unbuilt and that a settled resident whose capacity "
		+ "fell got no warning. That is no longer true: the trigger, ordering, outcomes and "
		+ "absence of a fail state are covered by `test_gentle_displacement.gd` and "
		+ "`test_settlement_window.gd`. What stays THIS suite's is the performance question row "
		+ "10 raised — a countdown that must not become per-frame work — asserted in check 6. "
		+ "The de-qualification case here is still the *un-arrived* animal's silent drop, which "
		+ "is a different rule and is deliberately unchanged."
	)

	finish()


# --- 5. Wander is presentation, not simulation --------------------------------------------------

## Hand-driven half: the roamer's own code, ticked directly, cannot move the counter.
##
## HARDENING, ADDED WITH THE SAME D-29 RE-POINT: returns `false` the moment its own
## precondition (a resident actually moved in) fails, and `_process` below now checks that
## return rather than plunging into the natural-frame phase regardless. Before this, a failed
## precondition here still set `_phase = 1` unconditionally, `_resident` stayed null, and
## `_accumulate_natural_frame()` dereferenced it every single frame thereafter — the exact
## null-reference spin flagged before this dispatch's `wild_grass` default made this fixture's
## old implicit-`grass` assumption stop holding. This does not weaken any assertion above; every
## `check()` in this function still runs and still fails loudly. It only stops a *future*
## precondition failure (of any cause) from turning into an unbounded spin instead of a clean,
## fast red.
func _check_wander_is_not_simulation_work_hand_driven() -> bool:
	# Take both nodes off `_process` for this half, so the only thing advancing anything is this
	# function. The natural-frame half below puts them straight back.
	_world.presentation.set_process(false)
	_world.simulation.set_process(false)

	# RE-POINTED (-> D-29 #1, see WANDER_GRASS_MARGIN above): the rabbit needs BOTH
	# `open_grass` and `cover`, and `wild_grass` (the new default) supplies neither implicitly.
	# Paint the border first so it is present the instant the rock block completes, not painted
	# over rock that already qualified on `cover` alone.
	var lo_x: int = WANDER_ROCK_ORIGIN.x - WANDER_GRASS_MARGIN
	var lo_z: int = WANDER_ROCK_ORIGIN.y - WANDER_GRASS_MARGIN
	var hi_x: int = WANDER_ROCK_ORIGIN.x + WANDER_ROCK_W - 1 + WANDER_GRASS_MARGIN
	var hi_z: int = WANDER_ROCK_ORIGIN.y + WANDER_ROCK_D - 1 + WANDER_GRASS_MARGIN
	for x in range(lo_x, hi_x + 1):
		for z in range(lo_z, hi_z + 1):
			var inside_rock: bool = (
				x >= WANDER_ROCK_ORIGIN.x and x < WANDER_ROCK_ORIGIN.x + WANDER_ROCK_W
				and z >= WANDER_ROCK_ORIGIN.y and z < WANDER_ROCK_ORIGIN.y + WANDER_ROCK_D
			)
			if not inside_rock:
				_world.paint_tile(x, z, "grass")
	for dx in WANDER_ROCK_W:
		for dz in WANDER_ROCK_D:
			_world.paint_tile(WANDER_ROCK_ORIGIN.x + dx, WANDER_ROCK_ORIGIN.y + dz, "rock")
	for _i in 200:
		_world.simulation.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)

	# RE-POINTED (-> D-29 #5, `GentleDisplacement.on_arrival()`): painting a whole habitat block
	# in one batch dirties every one of its tiles as its OWN prospective home site, so — exactly
	# as D-29 #5 itself documents — more than one rabbit site can legitimately register out of
	# this single fixture before tile ownership settles, and one of them can end up over its own
	# capacity once the other claims tiles it was counting on. That is real, correct behaviour
	# (`test_gentle_displacement.gd` / `test_settlement_window.gd` own it), but it means a
	# resident grabbed via `roamer(0)` immediately after the loop above could be the very one a
	# just-armed settlement window is about to depart or relocate — which this check would then
	# see as its tracked node going `previously freed` mid-window, for a reason that has nothing
	# to do with wander or `evaluations_run`. Settling every pending gesture from THIS setup
	# before picking a resident to track means the one this check follows is the one that
	# actually survives contention.
	for _i in 40:
		if _world.simulation.is_idle() and _world.displacement.is_idle():
			break
		_world.simulation.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)
		_world.displacement.tick(SettlementWindow.GRACE_WINDOW_SECONDS + 1.0)
	check(_world.simulation.is_idle() and _world.displacement.is_idle(),
		"the habitat this setup carved out has fully converged — no pending evaluation and no "
		+ "pending settlement gesture — before tracking a resident")

	if not check(_world.total_residents() >= 1,
		"a real resident moved in and is wandering (%d residents)" % _world.total_residents()):
		return false
	var roamer: ResidentRoamer = _world.presentation.roamer(0)
	if not check(roamer != null, "...with a roamer of its own"):
		return false
	_resident = roamer.resident()

	# THE PRECONDITION. A world that was still busy would make any later zero meaningless.
	check(_world.simulation.is_idle(),
		"the world with a resident in it is IDLE — nothing queued, nothing pending")
	check_eq(_world.simulation.pending_evaluations(), 0, "...with an empty dirty queue")
	check(_world.displacement.is_idle(),
		"...and no settlement gesture is pending either — nothing left to displace this resident "
		+ "mid-check")

	var evaluations_before: int = _world.simulation.evaluations_run
	var start: Vector3 = _resident.position
	var path: float = 0.0
	var previous: Vector3 = start
	var steps: int = int(HAND_WANDER_SECONDS / HAND_WANDER_STEP)
	for _i in steps:
		_world.presentation.tick(HAND_WANDER_STEP)
		path += previous.distance_to(_resident.position)
		previous = _resident.position

	check(path > 5.0,
		"the resident walked %.1f tiles over %.0f simulated seconds — there IS motion to measure"
			% [path, HAND_WANDER_SECONDS])
	check_eq(_world.simulation.evaluations_run, evaluations_before,
		"HAND-DRIVEN: %.0f s of wander moved `evaluations_run` by EXACTLY 0"
			% HAND_WANDER_SECONDS)
	check_eq(_world.simulation.pending_evaluations(), 0,
		"...and enqueued nothing: a resident moving is not a fifth trigger")
	check(_world.simulation.is_idle(),
		"...and the world still reports IDLE with an animal walking around in it")
	return true


func _begin_natural_window() -> void:
	# Hand off to the engine. From here until the assertions, this suite calls neither
	# `presentation.tick()` nor `simulation.tick()`: every `_process` below is Godot's own.
	_world.presentation.set_process(true)
	_world.simulation.set_process(true)
	Engine.time_scale = NATURAL_TIME_SCALE
	_natural_frames = 0
	_natural_seconds = 0.0
	_natural_path = 0.0
	_natural_previous = _resident.position
	_natural_evaluations_at_start = _world.simulation.evaluations_run
	_natural_evaluations_max = _world.simulation.evaluations_run
	_natural_left_idle = 0


## Returns true once the natural window has run long enough.
func _accumulate_natural_frame(delta: float) -> bool:
	_natural_frames += 1
	_natural_seconds += delta
	_natural_path += _natural_previous.distance_to(_resident.position)
	_natural_previous = _resident.position
	_natural_evaluations_max = maxi(_natural_evaluations_max, _world.simulation.evaluations_run)
	if not _world.simulation.is_idle():
		_natural_left_idle += 1
	return _natural_seconds >= NATURAL_TARGET_SECONDS or _natural_frames >= NATURAL_FRAME_CAP


func _check_wander_is_not_simulation_work_natural_frames() -> void:
	check(_natural_frames > 100,
		"NATURAL FRAMES: the engine drove %d real `_process` frames carrying %.0f simulated "
			% [_natural_frames, _natural_seconds]
		+ "seconds — not one giant hand-made delta")
	check(_natural_seconds >= NATURAL_TARGET_SECONDS,
		"...reaching the %.0f s target (%.0f s)" % [NATURAL_TARGET_SECONDS, _natural_seconds])
	check(_natural_path > 5.0,
		"...and the resident really walked during them: %.1f tiles, moved by "
			% _natural_path
		+ "`ResidentPresentation._process` and by nothing in this suite")

	# THE ASSERTION THE WHOLE CPU ARGUMENT RESTS ON.
	check_eq(_world.simulation.evaluations_run, _natural_evaluations_at_start,
		"THE ZERO SURVIVES A WORLD FULL OF MOTION: `evaluations_run` moved by EXACTLY 0 across "
		+ "%d engine-driven frames of a resident walking around" % _natural_frames)
	check_eq(_natural_evaluations_max, _natural_evaluations_at_start,
		"...and never spiked mid-window either — the counter was sampled every single frame, so "
		+ "a transient that drained again could not hide")
	check_eq(_natural_left_idle, 0,
		"...and the world reported IDLE on every one of those frames")
	check_eq(_world.simulation.pending_evaluations(), 0,
		"...with the dirty queue still empty at the end")


func _begin_control_window() -> void:
	# NON-VACUITY, and it is the important half of this check: everything above would also pass
	# if `HabitatSimulation._process` were simply not running. One dirtied neighbourhood, no
	# hand ticks, and the counter must move on the engine's own frames.
	_control_frames = 0
	_control_from = _world.simulation.evaluations_run
	_world.simulation.on_terraform(Vector2i(4, 4))


func _accumulate_control_frame() -> bool:
	_control_frames += 1
	return (_world.simulation.evaluations_run > _control_from
		or _control_frames >= CONTROL_FRAME_CAP)


func _check_the_simulation_was_awake_the_whole_time() -> void:
	check(_world.simulation.evaluations_run > _control_from,
		"CONTROL: with wander still running, ONE dirtied neighbourhood moved `evaluations_run` "
		+ "on the engine's own frames (%d -> %d in %d frames) — so the simulation's `_process` "
			% [_control_from, _world.simulation.evaluations_run, _control_frames]
		+ "was live the whole time and the zero above is a real zero, not a disabled node")
	check(_control_frames < CONTROL_FRAME_CAP,
		"...within %d frames, so nothing is stalled" % CONTROL_FRAME_CAP)


# --- 1. The zero -----------------------------------------------------------------------------

func _check_idle_world_does_zero_work() -> void:
	var fixture: Dictionary = _fixture()
	var sim: HabitatSimulation = fixture["sim"]

	check_eq(sim.evaluations_run, 0, "a freshly attached simulation has run zero evaluations")
	check(sim.is_idle(), "a world with no edits reports idle")
	check_eq(sim.pending_evaluations(), 0, "...with an empty dirty queue")

	for _i in IDLE_TICKS:
		sim.tick(IDLE_TICK_SECONDS)

	check_eq(sim.evaluations_run, 0,
		"THE ZERO: %d ticks (%.0f simulated seconds) with no edits ran ZERO evaluations"
			% [IDLE_TICKS, IDLE_TICKS * IDLE_TICK_SECONDS])
	check(sim.is_idle(), "...and the world is still idle afterwards")

	# The counter is not simply stuck at zero: one edit moves it. Without this, the assertion
	# above passes on a simulation that never counts anything.
	sim.on_terraform(Vector2i(5, 5))
	sim.tick(0.0)
	check(sim.evaluations_run > 0,
		"...and a single edit DOES move the counter (the zero above is not a stuck counter)")

	# Back to zero work once the queue drains, so idleness is a recurring state and not just
	# the startup condition.
	for _i in 20:
		sim.tick(0.0)
	var settled: int = sim.evaluations_run
	for _i in IDLE_TICKS:
		sim.tick(IDLE_TICK_SECONDS)
	check_eq(sim.evaluations_run, settled,
		"after the queue drains the world goes idle again and does zero further work")

	_teardown(fixture)


# --- 2. The trigger set ----------------------------------------------------------------------

func _check_trigger_set_is_exactly_four() -> void:
	var sim := HabitatSimulation.new()
	var triggers: Array[String] = []
	for entry: Dictionary in sim.get_script().get_script_method_list():
		var name: String = entry["name"]
		if name.begins_with("on_"):
			triggers.append(name)
	triggers.sort()

	check_eq(triggers, EXPECTED_TRIGGERS,
		"the trigger set is EXACTLY the four gdd.md names — no fifth, no missing one")
	check_eq(triggers.size(), 4, "...which is four triggers, counted")

	# Named individually too, so a failure above says which one moved.
	check(sim.has_method("on_terraform"), "trigger 1: terraform")
	check(sim.has_method("on_building_changed"), "trigger 2: building add/remove")
	check(sim.has_method("on_resident_arrived"), "trigger 3: resident arrives")
	check(sim.has_method("on_resident_departed"), "trigger 4: resident departs")

	# The simulation's whole signal surface, pinned. This is also what makes "no warning event"
	# assertable in check 4 below: there is no warning signal to fire.
	var signals: Array[String] = []
	for entry: Dictionary in sim.get_script().get_script_signal_list():
		signals.append(entry["name"])
	signals.sort()
	check_eq(signals, ["capacity_evaluated", "resident_arrived"] as Array[String],
		"the simulation declares exactly two signals — no warning/error signal exists at all")

	sim.free()


func _check_mist_reveal_cannot_be_a_trigger() -> void:
	# Row 13's invariant, asserted from the terrain data rather than from an unbuilt system:
	# revealed land is wild grass, wild grass emits nothing, so a reveal cannot change any
	# `count_t` and therefore cannot change any capacity. The non-trigger is structural.
	var bare: PackedStringArray = TerrainDefinition.derive_bare_tags(TerrainDefinition.load_all())
	check(bare.is_empty(),
		"BARE_TAGS derived from the tag-source mapping is EMPTY — a reveal cannot move a count",
		"got %s" % str(bare))

	# And nothing in the world data layer offers a reveal to wire up by accident.
	var grid := WorldGrid.new()
	var reveal_methods: Array[String] = []
	for entry: Dictionary in grid.get_script().get_script_method_list():
		var name: String = entry["name"]
		if name.contains("reveal") or name.contains("mist"):
			reveal_methods.append(name)
	check(reveal_methods.is_empty(),
		"WorldGrid exposes no reveal/mist method (row 13 is unbuilt, and unbuilt is honest)",
		"found %s" % str(reveal_methods))
	grid.free()


# --- 3. The bounded drain ---------------------------------------------------------------------

func _check_drain_is_bounded() -> void:
	var fixture: Dictionary = _fixture()
	var sim: HabitatSimulation = fixture["sim"]
	var budget: int = HabitatSimulation.MAX_EVALUATIONS_PER_FRAME

	check_eq(budget, 4, "MAX_EVALUATIONS_PER_FRAME is 4 (spec.md -> Pacing Constants, #28)")

	# Ten distinct neighbourhoods dirtied in one burst — more than two frames' worth.
	var burst: int = 10
	for i in burst:
		sim.on_terraform(Vector2i(i * 3, 20))
	check_eq(sim.pending_evaluations(), burst,
		"%d distinct edits queue %d evaluations" % [burst, burst])

	sim.tick(0.0)
	check_eq(sim.evaluations_run, budget,
		"one tick runs AT MOST the budget (%d), never the whole backlog" % budget)
	check_eq(sim.pending_evaluations(), burst - budget,
		"the remainder stays queued — the fallback is a slower drain, not a frame spike")

	sim.tick(0.0)
	check_eq(sim.evaluations_run, budget * 2, "a second tick runs the next %d" % budget)
	sim.tick(0.0)
	check_eq(sim.pending_evaluations(), 0, "a third tick clears the backlog")
	check_eq(sim.evaluations_run, burst, "and exactly %d evaluations ran in total" % burst)

	# A burst of taps on ONE neighbourhood coalesces: dirty is a set, not a log.
	var coalesce: HabitatSimulation = fixture["sim"]
	for _i in 25:
		coalesce.on_terraform(Vector2i(30, 30))
	check_eq(coalesce.pending_evaluations(), 1,
		"25 taps on the same neighbourhood coalesce into ONE queued evaluation")

	_teardown(fixture)


# --- 4. The silent drop ------------------------------------------------------------------------

func _check_dequalified_arrival_is_silently_dropped() -> void:
	var fixture: Dictionary = _fixture()
	var sim: HabitatSimulation = fixture["sim"]
	var grid: WorldGrid = fixture["grid"]
	var registry: HomeSiteRegistry = fixture["registry"]
	var arrivals: ArrivalQueue = fixture["arrivals"]
	var species: AnimalDefinition = fixture["species"]

	var arrived: Array[String] = []
	sim.resident_arrived.connect(func(sid: String, _p: Vector3) -> void: arrived.append(sid))

	var origin := Vector2i(10, 10)
	for i in 4:
		grid.set_terrain(origin.x + i, origin.y, "rock")   # 4 cover tiles / 4 -> capacity 1
	sim.on_terraform(origin)
	sim.tick(0.0)

	check_eq(sim.capacity_at(origin, species), 1, "the fresh habitat qualifies (capacity 1)")
	check_eq(arrivals.size(), 1, "one arrival is pending")
	check_eq(registry.total_residents(), 0, "nobody has moved in yet — the delay is running")

	# The player undoes the habitat before the arrival comes due.
	for i in 4:
		grid.set_terrain(origin.x + i, origin.y, "grass")
	sim.on_terraform(origin)
	check_eq(sim.capacity_at(origin, species), 0,
		"the land is un-made: capacity falls back to 0 (unsuitable)")

	# Past the whole arrival-delay band in one tick, so the pending entry definitely comes due.
	sim.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)

	check_eq(registry.total_residents(), 0,
		"SILENTLY DROPPED: the arrival came due, re-checked, and nobody moved in")
	check_eq(arrived.size(), 0,
		"...and `resident_arrived` never fired — no phantom resident to explain")
	check_eq(arrivals.size(), 0, "...and the pending entry is gone, not stuck in the queue")
	check(registry.is_empty(),
		"...and no home site was registered for the arrival that never happened")

	# The control: with the habitat left intact, the same path DOES land a resident. Without
	# this, every assertion above would pass on a simulation that can never move anyone in.
	var control: Dictionary = _fixture()
	var c_sim: HabitatSimulation = control["sim"]
	var c_grid: WorldGrid = control["grid"]
	var c_arrived: Array[String] = []
	c_sim.resident_arrived.connect(func(sid: String, _p: Vector3) -> void: c_arrived.append(sid))
	for i in 4:
		c_grid.set_terrain(origin.x + i, origin.y, "rock")
	c_sim.on_terraform(origin)
	c_sim.tick(0.0)
	c_sim.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)
	check_eq((control["registry"] as HomeSiteRegistry).total_residents(), 1,
		"CONTROL: leave the habitat alone and the identical path lands exactly one resident")
	check_eq(c_arrived, ["critter"] as Array[String],
		"CONTROL: `resident_arrived` fired once, for the synthetic species")

	_teardown(control)
	_teardown(fixture)


# --- 6. A settlement timer is not idle work ------------------------------------------------------
# Row 10 introduced the build's first countdown. gdd.md -> Performance's whole CPU argument is
# that "an idle world does no simulation work", and a countdown is the classic way that stops
# being true. **This is verified independently of the row 10 dispatch's own claim about it.**

func _check_settlement_timers_are_not_idle_work() -> void:
	var fixture: Dictionary = _fixture()
	var sim: HabitatSimulation = fixture["sim"]
	var grid: WorldGrid = fixture["grid"]
	var registry: HomeSiteRegistry = fixture["registry"]
	var roster: SpeciesRoster = SpeciesRoster.new([fixture["species"]])

	var displacement := GentleDisplacement.new()
	displacement.attach(grid, roster, registry, sim, null, SettlementWindow.new())

	# Reference types, never a captured local `int` — a lambda over one never increments, and
	# every zero below would then be vacuous.
	var warnings: Array[Dictionary] = []
	displacement.displacement_warned.connect(func(w: Dictionary) -> void: warnings.append(w))

	# (a) A RESIDENT-FREE WORLD NEVER OPENS A WINDOW. Fifty real edits, none of them near anybody.
	check(displacement.is_idle(), "a fresh world has no settlement gesture pending")
	for i in 50:
		var tile := Vector2i(2 + (i % 20), 2 + int(i / 20.0))
		grid.set_terrain(tile.x, tile.y, "rock")
		sim.on_terraform(tile)
		displacement.on_edit(tile)
	check(displacement.is_idle(),
		"50 edits on a resident-free world opened NO settlement gesture — a window is only ever "
		+ "opened for a neighbourhood someone actually lives in")
	check_eq(displacement.pending_gestures(), 0, "...zero pending gestures")

	# (b) 500 TICKS OVER IT RESOLVE NOTHING. Independently driven, not taken on report.
	var evaluations_before: int = sim.evaluations_run
	for _i in 500:
		displacement.tick(1.0)
	check_eq(displacement.settlements_resolved, 0,
		"500 displacement ticks (%.0f simulated seconds) on a resident-free world resolved "
			% 500.0
		+ "NOTHING — `advance()` returns on its first line when nothing is open")
	check_eq(warnings.size(), 0, "...and warned nobody")
	check_eq(displacement.relocations + displacement.departures, 0, "...and moved nobody")
	check_eq(sim.evaluations_run, evaluations_before,
		"...and moved `evaluations_run` by EXACTLY 0: a settlement tick cannot mark a "
		+ "neighbourhood dirty, so the timer is off the CPU budget entirely")

	# (c) THE SAME ZERO WITH A GESTURE ACTUALLY PENDING. A settled gesture that displaces nobody
	# must also cost nothing afterwards, or the world would never return to idle once played in.
	var home := Vector2i(25, 25)
	for i in 8:
		grid.set_terrain(home.x + i - 4, home.y, "rock")
	var site: HomeSite = registry.register(home, "critter", 8)
	var resident := Node3D.new()
	(fixture["residents"] as Node3D).add_child(resident)
	site.residents.append(resident)

	displacement.on_edit(home)
	check_eq(displacement.pending_gestures(), 1,
		"NON-VACUITY: with someone actually living there, the same call DOES open a gesture — "
		+ "the zeros above are emptiness, not a dead `on_edit()`")

	var before_settle: int = sim.evaluations_run
	displacement.tick(SettlementWindow.GRACE_WINDOW_SECONDS + 1.0)
	check_eq(displacement.settlements_resolved, 1, "...which settles once the window closes")
	check_eq(warnings.size(), 0, "...displacing nobody, because capacity still covers population")
	check(displacement.is_idle(), "...and leaves the world idle again")
	check_eq(sim.evaluations_run, before_settle,
		"...having run zero evaluations of its own — settlement re-reads the world, it does not "
		+ "enqueue")

	for _i in 500:
		displacement.tick(1.0)
	check_eq(displacement.settlements_resolved, 1,
		"THE ZERO IS RECURRING: another 500 ticks after the gesture settled resolve nothing "
		+ "further, so idleness is a state the world returns to and not just how it started")

	displacement.free()
	_teardown(fixture)


# --- fixture -----------------------------------------------------------------------------------

## A world with no scene: real grid, real registry, real queue, and a one-species SYNTHETIC
## roster whose only need is `cover` at 4 tiles per individual.
func _fixture() -> Dictionary:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 36, 36)

	var species := AnimalDefinition.new()
	species.id = "critter"
	species.display_name = "Critter"
	species.habitat_needs = ["cover"] as Array[String]
	species.tiles_per_individual = 4
	species.scout_radius = 8
	# A grey-box stands in for the model. Not cosmetic: a species with no `model_scene` makes
	# `_move_in()` push a warning, and this suite asserts on the ABSENCE of noise, so it must
	# not manufacture any of its own.
	species.model_scenes = [load("res://assets/placeholder/grass/Grass.tscn") as PackedScene]

	var registry := HomeSiteRegistry.new()
	var arrivals := ArrivalQueue.new(20260727)
	var residents_root := Node3D.new()
	var sim := HabitatSimulation.new()
	sim.attach(grid, SpeciesRoster.new([species]), registry, arrivals, residents_root)

	return {
		"grid": grid, "sim": sim, "registry": registry, "arrivals": arrivals,
		"species": species, "residents": residents_root,
	}


func _teardown(fixture: Dictionary) -> void:
	(fixture["sim"] as HabitatSimulation).free()
	(fixture["grid"] as WorldGrid).free()
	(fixture["residents"] as Node3D).free()
