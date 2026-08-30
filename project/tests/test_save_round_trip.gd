extends QATestCase
## THE COMPLETION TEST'S LAST CLAUSE. gdd.md's success criterion ends "quit -> load, world
## intact", and this suite is the headless half of that sentence.
##
## IT USES THE REAL CAUSAL PATH, not a hand-built world: paint rock beside grass, let capacity
## rise, let a rabbit actually arrive; place a House on grass beside a cultivated field and let
## a villager move in. A round trip over a world assembled by poking fields would prove only
## that the serializer talks to itself.
##
## AND IT USES THE REAL LOAD PATH. The restored world is not `WorldSnapshot.apply()` called by
## hand — the capture goes to disk through `SaveStore`, `GameSession.request_load()` records the
## intent, and a fresh `Main.tscn` instance builds itself from the file inside its own
## `_ready()`. That is the code a player's Load button will run, and it is the risky half of
## Task 6: `_ready()` is the constructor every other suite in this project comes through.
##
## THE NEGATIVE CONTROL IS PART OF THE SUITE, not a manual step: `_check_the_comparison_can_fail`
## mutates one tile in the captured dictionary and asserts the comparison notices. Without it,
## "every field matches" would also pass for two empty worlds.
##
## THE ROAM PRECONDITION IS ALSO PART OF THE SUITE. "Every resident stands exactly where it
## stood" is a claim about LIVE positions, and it is vacuous unless the residents have actually
## left their home tile centres — which is the weakness a review found in `test_world_snapshot`'s
## version of this assertion, where only ~2 frames of wander had elapsed. This suite drives
## `ResidentPresentation.tick()` until at least one resident is measurably away from home, and
## asserts that separation BEFORE comparing positions. If the roam precondition ever stops
## holding, this suite goes red rather than quietly comparing two identical tile centres.
##
## AND IT ASSERTS ON THE BYTES ON DISK, not only on the resulting world. Every refused-load
## check here reads the file back after the load attempt and compares it to what was written.
## That is the only shape of assertion that can see the branch's worst defect: a refused file
## being silently OVERWRITTEN with an empty default world by the autosave that attaches during
## the same `_ready()`. A suite that inspects only the world it got is blind to it, because the
## world it got is correct — it is the file that is gone.
##
## Run:
##   bash scripts/run-tests.sh save_round_trip

const WORLD_PATH: String = "res://scenes/Main.tscn"

## `SaveStore.SAVE_DIR` is a `static var` so a suite can redirect it. Never let this suite
## write into `user://saves` — that is a real player's directory. Restored before `finish()`.
const _REAL_SAVE_DIR: String = "user://saves"
const _TEST_SAVE_DIR: String = "user://test_saves_round_trip"

## The rabbit's habitat: a row of grass (`open_grass`) beside a row of rock (`cover`). Both
## needs must be present or capacity is 0 forever — `wild_grass`, the world's default tile, is
## deliberately tag-inert.
const GRASS_Z: int = 4
const GRASS_X_FROM: int = 4
const GRASS_X_TO: int = 10
const ROCK_Z: int = 6
const ROCK_X_FROM: int = 4
const ROCK_X_TO: int = 8

## The villager's habitat. The House's `allowed_terrain` is `["grass"]`, so the tile is painted
## first — exactly what a player does, and without it the placement silently declines.
const HOUSE_TILE := Vector2i(14, 14)
const FIELD_TILE := Vector2i(15, 14)

## Simulated seconds driven by hand, past the 20-60 s arrival delay, so no test waits on frames.
const ARRIVAL_TICKS: int = 200
const ARRIVAL_TICK_SECONDS: float = 1.0

## THE MID-FLIGHT STATE a child quits in (the 2026-08-02 ruling). Enough ticks to drain the
## dirty queue at `HabitatSimulation.MAX_EVALUATIONS_PER_FRAME` (4/frame) over ~11 painted
## tiles, and 1.5 simulated seconds in total — far short of `ARRIVAL_DELAY_MIN_SECONDS`, so the
## arrival is enqueued and has certainly not landed.
const UNSETTLED_DRAIN_TICKS: int = 30
const UNSETTLED_DRAIN_TICK_SECONDS: float = 0.05

## The New Game screen's seed generator, loaded as a script so its static function can be
## exercised without driving a scene change.
const NEW_GAME_SCRIPT: String = "res://scripts/menu/new_game_screen.gd"

## HOW MANY SEEDS THE GENERATOR IS ASKED FOR. Not a design value: it is the sample size that makes
## "no draw repeats the one before it" a real claim rather than a coincidence. The pre-fix
## generator repeated itself on ~42% of consecutive pairs, so 64 clean draws in a row is a ~1e-15
## event for it — while a correctly seeded RNG passes every time.
const SEED_DRAW_SAMPLES: int = 64

## THE ROAM PRECONDITION. `ResidentRoamer.ARRIVAL_EPSILON_TILES` is 0.02 — the distance at which
## a walk counts as finished — so anything at that scale is noise. Half a tile is unambiguously
## "this animal walked away from its den" while staying far inside the roamer's own 3-tile
## wander radius, so the loop below is not waiting on an unlikely draw. Not a design value: it
## exists so this suite cannot compare two identical tile centres and call it a pass.
const MIN_ROAM_SEPARATION_TILES: float = 0.5
const ROAM_TICK_SECONDS: float = 0.5

## A fixed warm-up first, so the separation this suite reports is the wander's NATURAL spread
## rather than whatever the first tick past the threshold happened to be. 120 x 0.5 s is 60
## simulated seconds against a 2-6 s pause and a 0.6 tile/s walk — several full wander cycles.
const ROAM_WARMUP_TICKS: int = 120

## ...and then, only if the warm-up's dice happened to leave everybody near home, keep going
## until somebody has moved. Fixing the setup, rather than weakening the assertion it protects.
const MAX_ROAM_TICKS: int = 600

## THE DISPLACEMENT BUDGET (D-32). A bound, not an expectation: the loop it governs stops at the
## outcome it cares about (no home over capacity) and this is only how long it is willing to wait.
## `SettlementWindow.GRACE_WINDOW_SECONDS` is 12, so 60 simulated seconds is five times over.
const DISPLACEMENT_TICK_SECONDS: float = 1.0
const MAX_DISPLACEMENT_TICKS: int = 60

var _source: WorldRoot = null
var _restored: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false
var _captured: Dictionary = {}
var _save_path: String = ""

## Measured, not assumed: the furthest any resident had roamed from its own home tile centre at
## the instant the world was captured. Reported in the log so the number cannot rot silently.
var _measured_separation: float = 0.0

## Measured, not assumed: `pending_evaluations()` on the restored world before anything ticked.
var _measured_pending: int = 0

## Measured, not assumed (D-32): how far `GentleDisplacement.reconcile_after_load()` moves
## `HabitatSimulation.evaluations_run`. It must be 0 — the reconcile reads `CapacityEvaluator`
## directly and enqueues nothing, so re-arming a window is not a fifth habitat trigger.
var _measured_reconcile_evaluations: int = -1

## Measured, not assumed (D-32): simulated seconds the restored world took to actually resolve
## the displacement that was pending when the file was written.
var _measured_resolve_seconds: float = -1.0


func _initialize() -> void:
	begin("save round trip")
	GameSession.clear()
	SaveStore.SAVE_DIR = _TEST_SAVE_DIR
	_clean_the_scratch_directory()

	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		_teardown()
		finish()
		return
	_source = packed.instantiate() as WorldRoot
	if not check(_source != null, "Main.tscn's root is a WorldRoot"):
		_teardown()
		finish()
		return
	root.add_child(_source)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		_teardown()
		finish()
		return true
	_frames += 1
	if _frames < 3:
		return false

	_check_the_default_path_is_unchanged()
	_check_the_session_hand_off()

	_build_a_world_through_the_real_causal_path()
	_roam_until_a_resident_has_measurably_left_home()
	_captured = WorldSnapshot.capture(_source, "Wildhaven", "meadow_start", 4242)

	_restore_through_the_real_load_path()
	_check_the_restored_world_knows_its_own_file()
	_check_every_field_matches()
	_check_the_comparison_can_fail()
	_check_a_pending_arrival_survives_a_reload_with_no_home_site_yet()
	_check_a_hand_edited_arrival_queue_loads_rather_than_throwing()
	_check_a_wrong_typed_field_loads_into_a_playable_world()
	_check_the_seed_repair_rule()
	_check_a_v1_file_still_loads_and_gains_a_stable_seed()
	_check_a_new_world_gets_a_real_seed()
	_check_a_refused_load_is_playable_and_leaves_the_file_untouched()
	_check_the_load_list_greys_what_this_build_cannot_open()
	_check_in_flight_state_is_re_derived_not_restored()
	_check_take_away_still_works_after_a_reload()
	_check_a_settlement_window_survives_a_reload()
	_check_a_world_with_no_residents_arms_no_gesture_on_load()
	_check_style_defaults_survive_a_reload()
	_check_an_old_save_with_no_style_defaults_falls_back_cleanly()
	_report_the_measurements()

	_teardown()
	finish()
	return true


# --- The compatibility rule ----------------------------------------------------------------

## THE ASSERTION THE OTHER 55 SUITES DEPEND ON. `_source` was instantiated with no session
## intent, which is what a test and an editor F6 run both do, and on that path `_ready()` must
## build exactly the world it built before saves existed. Every other suite in this project
## asserts against that world without saying so; this says so.
func _check_the_default_path_is_unchanged() -> void:
	check_eq(_source.grid_size(), Vector2i(36, 36), "mode `none` still builds the 36x36 start (#18)")
	check_eq(
		_source.get_tile_terrain(0, 0), WorldGrid.START_TERRAIN_ID,
		"...still filled with tag-inert wild grass"
	)
	check_eq(_source.total_residents(), 0, "...still with nobody pre-placed")
	check_eq(_source.get_wood(), WoodLedger.STARTING_WOOD, "...and the starting Wood stockpile")
	check_eq(_source.save_path, "", "a world opened without a menu has NO file, so nothing autosaves over one")
	check_eq(_source.world_name, "Wildhaven", "...and falls back to the default name")
	check_eq(_source.preset_id, "meadow_start", "...built from the shipped default preset")


func _check_the_session_hand_off() -> void:
	var preset: WorldPreset = WorldPreset.default_preset()
	GameSession.request_new(preset, "Kid's World", "user://saves/kids-world.json", 987654321)
	var first: Dictionary = GameSession.consume()
	check_eq(first["mode"], "new", "a New Game intent survives to the world scene")
	check_eq(first["name"], "Kid's World", "...carrying the name the player typed")
	check_eq(first["path"], "user://saves/kids-world.json", "...and the file it will write to")
	check_eq(
		int(first["seed"]), 987654321,
		"...and the seed the menu drew, which is where a new world's seed comes from"
	)

	var second: Dictionary = GameSession.consume()
	check_eq(
		second["mode"], "none",
		"the intent is CONSUMED, so a second world scene builds a default world instead of "
		+ "silently re-opening the last save"
	)

	GameSession.request_load("user://saves/somewhere.json")
	GameSession.clear()
	check_eq(GameSession.consume()["mode"], "none", "`clear()` drops a pending intent")


# --- The real causal path -------------------------------------------------------------------

## Paint rock beside grass until a rabbit really moves in, then place a House and let a villager
## in beside a cultivated field — the two arrivals the vertical slice proved.
func _build_a_world_through_the_real_causal_path() -> void:
	# Driven by hand from here on, so nothing depends on how many real frames elapse.
	_source.wood.set_process(false)
	_source.simulation.set_process(false)
	_source.displacement.set_process(false)
	_source.presentation.set_process(false)

	for x in range(GRASS_X_FROM, GRASS_X_TO):
		_source.paint_tile(x, GRASS_Z, "grass")
	for x in range(ROCK_X_FROM, ROCK_X_TO):
		_source.paint_tile(x, ROCK_Z, "rock")

	# A House builds on grass only (buildings.md), and the world's default tile is `wild_grass`.
	# Terraforming first is what a player does; without it `place_building` declines silently and
	# the villager half of this round trip would test nothing.
	check(_source.paint_tile(HOUSE_TILE.x, HOUSE_TILE.y, "grass"), "the house site is terraformed to grass")
	check(_source.place_building(HOUSE_TILE.x, HOUSE_TILE.y, "house"), "the House places")
	check(
		_source.paint_tile(FIELD_TILE.x, FIELD_TILE.y, "cultivated_field"),
		"a cultivated field is painted beside it"
	)

	# Drive the simulation by hand past the arrival delay rather than waiting on frames.
	for _i in range(ARRIVAL_TICKS):
		_source.simulation.tick(ARRIVAL_TICK_SECONDS)
		_source.displacement.tick(ARRIVAL_TICK_SECONDS)

	check(
		_source.total_residents() > 0,
		"the source world has residents, so the round trip has something to prove",
		"if this fails the capacity constants moved; fix the setup, not the assertions"
	)
	check(
		_source.registry.sites().size() > 1,
		"...in more than one home site, so site ordering is actually exercised",
		"%d site(s)" % _source.registry.sites().size()
	)


## THE ROAM PRECONDITION — see the header. Advances the presentation layer ONLY (no simulation
## tick, so no new arrival can change the population underneath the capture) until some resident
## is measurably away from its home tile centre.
func _roam_until_a_resident_has_measurably_left_home() -> void:
	for i in range(MAX_ROAM_TICKS):
		_measured_separation = _furthest_resident_from_home(_source)
		if i >= ROAM_WARMUP_TICKS and _measured_separation >= MIN_ROAM_SEPARATION_TILES:
			return
		_source.presentation.tick(ROAM_TICK_SECONDS)
	_measured_separation = _furthest_resident_from_home(_source)


## Furthest XZ distance, in tiles, from any resident to its own home site's tile centre.
func _furthest_resident_from_home(world: WorldRoot) -> float:
	var furthest: float = 0.0
	for site: HomeSite in world.registry.sites():
		var home: Vector3 = world.grid.tile_to_world(site.position.x, site.position.y)
		for node: Node3D in site.residents:
			if node == null or not is_instance_valid(node):
				continue
			var d: Vector3 = node.position - home
			d.y = 0.0
			furthest = maxf(furthest, d.length())
	return furthest


# --- The real load path ---------------------------------------------------------------------

## Through the disk and through `WorldRoot._ready()`, not through a direct `apply()` call — this
## is the path the Load button will take.
func _restore_through_the_real_load_path() -> void:
	_save_path = SaveStore.unique_path_for("Round Trip")
	check_eq(SaveStore.write(_save_path, _captured), OK, "the capture writes to disk")
	check(not SaveStore.read(_save_path).is_empty(), "...and reads back as a JSON object")

	GameSession.request_load(_save_path)
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	_restored = packed.instantiate() as WorldRoot
	# `_ready()` fires here: it consumes the intent, reads the file, builds the grid at the
	# saved size and applies the snapshot. Nothing has ticked yet when this returns.
	root.add_child(_restored)

	# MEASURED BEFORE ANYTHING TICKS — see `_check_in_flight_state_is_re_derived_not_restored`.
	_measured_pending = _restored.simulation.pending_evaluations()

	_restored.wood.set_process(false)
	_restored.simulation.set_process(false)
	_restored.presentation.set_process(false)
	_restored.displacement.set_process(false)

	check_eq(
		GameSession.consume()["mode"], "none",
		"`_ready()` consumed the load intent, so the next world scene does not re-open this file"
	)


func _check_the_restored_world_knows_its_own_file() -> void:
	check_eq(_restored.save_path, _save_path, "the loaded world remembers the file it came from")
	check_eq(_restored.world_name, "Wildhaven", "...and the name stored inside it")
	check_eq(
		_restored.preset_id, "meadow_start",
		"...and the preset id from the FILE, not from today's default preset"
	)
	check_eq(
		_restored.world_seed, 4242,
		"...and the seed, which row 13's mist reveal is a deterministic function of"
	)


# --- The comparison ---------------------------------------------------------------------------

func _check_every_field_matches() -> void:
	check_eq(_restored.grid.width, _source.grid.width, "width matches")
	check_eq(_restored.grid.depth, _source.grid.depth, "depth matches")

	var mismatches: int = 0
	var first_mismatch: String = ""
	for z in range(_source.grid.depth):
		for x in range(_source.grid.width):
			if _restored.get_tile_terrain(x, z) != _source.get_tile_terrain(x, z):
				mismatches += 1
				if first_mismatch.is_empty():
					first_mismatch = "(%d,%d): %s vs %s" % [
						x, z, _source.get_tile_terrain(x, z), _restored.get_tile_terrain(x, z)
					]
	check_eq(
		mismatches, 0,
		"every one of the %d tiles matches" % (_source.grid.width * _source.grid.depth)
	)
	if mismatches > 0:
		print("        first mismatch %s" % first_mismatch)

	check(_restored.grid.get_building(HOUSE_TILE.x, HOUSE_TILE.y) != null, "the House came back")
	check_eq(_restored.get_wood(), _source.get_wood(), "the Wood balance came back")
	check_eq(_restored.total_residents(), _source.total_residents(), "the population came back")
	check_eq(
		_restored.registry.sites().size(), _source.registry.sites().size(),
		"every home site came back"
	)
	check_eq(
		_restored.species_hosted_count(), _source.species_hosted_count(),
		"the all-time Species Hosted count came back"
	)

	# THE ROAM PRECONDITION, asserted before the position comparison it protects.
	check(
		_measured_separation >= MIN_ROAM_SEPARATION_TILES,
		"at least one resident had measurably left its home tile centre before the capture "
		+ "(%.2f tiles), so the comparison below is not two identical tile centres"
			% _measured_separation,
		"drove the presentation layer for up to %.0f simulated seconds and the furthest any "
			% (MAX_ROAM_TICKS * ROAM_TICK_SECONDS)
		+ "resident got from home was %.4f tiles" % _measured_separation
	)

	# Residents roam, so this is the assertion that would catch a restore snapping them home.
	var source_sites: Array[HomeSite] = _source.registry.sites()
	var restored_sites: Array[HomeSite] = _restored.registry.sites()
	var positions_matched: int = 0
	for i in range(min(source_sites.size(), restored_sites.size())):
		check_eq(restored_sites[i].position, source_sites[i].position, "site %d is in the same place" % i)
		check_eq(restored_sites[i].species_id, source_sites[i].species_id, "site %d has the same species" % i)
		# RELATIVE ORDER, NOT THE ABSOLUTE NUMBER — and the difference is the whole assertion.
		#
		# `sequence` has exactly ONE consumer: `HomeSiteRegistry.rebuild_ownership()`'s
		# `site.sequence < current.sequence` tie-break, which reads only the `<` relation.
		# `capture()` writes sites sorted ascending and `restore_site()` renumbers from 0 in file
		# order, so the relabelling is strictly monotone and preserves every pairwise comparison
		# — the ownership map comes out identical (verified tile-by-tile in review).
		#
		# An earlier version of this suite asserted `restored[i].sequence == source[i].sequence`
		# and FLAKED at ~3% (4 of 30 instrumented runs): a Gentle Displacement departure during
		# the arrival phase this suite drives calls `unregister()`, which leaves a GAP in the
		# source world's sequence numbers that the restore closes. That is a lossy field, not a
		# broken world, and a CI gate going red for a non-defect is worse than no gate — it
		# trains people to re-run. Whether `restore_site()` should thread the saved value through
		# instead is a schema decision with the human; this suite asserts what tile exclusivity
		# actually requires, exactly as `test_restore_seams.gd` already does.
		if i > 0:
			check(
				restored_sites[i].sequence > restored_sites[i - 1].sequence,
				"site %d is still younger than site %d, so tie-breaks survive the reload" % [i, i - 1],
				"restored sequences %d then %d" % [restored_sites[i - 1].sequence, restored_sites[i].sequence]
			)
		for j in range(min(source_sites[i].residents.size(), restored_sites[i].residents.size())):
			var a: Node3D = source_sites[i].residents[j]
			var b: Node3D = restored_sites[i].residents[j]
			if a != null and b != null and a.position.distance_to(b.position) < 0.01:
				positions_matched += 1
	check(
		positions_matched == _source.total_residents(),
		"every resident stands exactly where it stood, not at its home tile centre",
		"%d of %d matched" % [positions_matched, _source.total_residents()]
	)


## WITHOUT THIS, "every field matches" would pass for two empty worlds.
func _check_the_comparison_can_fail() -> void:
	var tampered: Dictionary = _captured.duplicate(true)
	var index: int = GRASS_Z * _source.grid.width + GRASS_X_FROM
	var was: String = (tampered["terrain"] as Array)[index] as String
	(tampered["terrain"] as Array)[index] = "water"
	check(was != "water", "the tile being tampered with was not already water", "was `%s`" % was)

	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var probe: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(probe)
	probe.simulation.set_process(false)
	probe.wood.set_process(false)
	probe.presentation.set_process(false)
	probe.displacement.set_process(false)
	WorldSnapshot.apply(probe, tampered)

	check_eq(
		probe.get_tile_terrain(GRASS_X_FROM, GRASS_Z), "water",
		"a tampered save produces a DIFFERENT world — the comparison above is real"
	)
	check(
		probe.get_tile_terrain(GRASS_X_FROM, GRASS_Z) != _source.get_tile_terrain(GRASS_X_FROM, GRASS_Z),
		"...and that difference is one the field comparison would have caught"
	)
	probe.queue_free()


## THE DEFECT THE 2026-08-02 RULING CLOSES (C-1), reproduced as a test.
##
## A child paints a rabbit meadow and quits inside the 20-60 s arrival delay. Nothing has moved
## in, so the registry holds NO home site for that meadow — and the old restore re-derived the
## arrival queue with `mark_all_dirty()`, which reaches `_mark_all_sites_dirty()` and enqueues
## only sites that already exist. Measured before the fix: 0 residents after 600 simulated
## seconds, and 1 only after some further player edit. The rabbit never came.
##
## SO THE SHAPE OF THIS TEST IS THE SHAPE OF THE BUG, and each clause matters:
##   * the habitat is built through the REAL causal path (painted terrain, real capacity), not
##     by hand-inserting a queue entry — a hand-inserted entry would prove only serialisation;
##   * `registry.sites().is_empty()` is ASSERTED, because with a site present the old code
##     passes and the test proves nothing;
##   * the world is driven AFTER the reload and the assertion is that a resident ARRIVES —
##     "the queue came back" is a weaker claim than "the rabbit comes".
func _check_a_pending_arrival_survives_a_reload_with_no_home_site_yet() -> void:
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	GameSession.clear()
	var unsettled: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(unsettled)
	_take_off_process(unsettled)

	for x in range(GRASS_X_FROM, GRASS_X_TO):
		unsettled.paint_tile(x, GRASS_Z, "grass")
	for x in range(ROCK_X_FROM, ROCK_X_TO):
		unsettled.paint_tile(x, ROCK_Z, "rock")

	# Enough ticks to DRAIN the dirty queue (4 evaluations/frame) but nowhere near enough
	# simulated time to spend the 20-60 s delay — which is exactly the state a child quits in.
	for _i in range(UNSETTLED_DRAIN_TICKS):
		unsettled.simulation.tick(UNSETTLED_DRAIN_TICK_SECONDS)

	check(
		unsettled.registry.sites().is_empty(),
		"the painted meadow has NO home site yet, so `mark_all_dirty()` has nothing to re-derive "
		+ "from — this is the precondition the whole check rests on",
		"%d site(s)" % unsettled.registry.sites().size()
	)
	var pending: Array[Dictionary] = unsettled.simulation.arrivals().to_save()
	if not check(
		pending.size() > 0,
		"...and an arrival IS pending: an animal is on its way to a home that does not exist yet",
		"if this fails the capacity constants moved; fix the setup, not the assertion"
	):
		unsettled.free()
		return
	var remaining_before: float = float(pending[0]["remaining"])
	var residents_before: int = unsettled.total_residents()
	check_eq(residents_before, 0, "...and nobody has actually moved in yet")

	# Quit: capture, to disk, and back in through the REAL load path.
	var captured: Dictionary = WorldSnapshot.capture(unsettled, "Painted and quit", "meadow_start", 4242)
	var path: String = SaveStore.unique_path_for("Painted and quit")
	check_eq(SaveStore.write(path, captured), OK, "the mid-flight world writes to disk")
	check_eq(
		(captured["home_sites"] as Array).size(), 0,
		"the file it wrote carries no home sites at all, only the pending arrival"
	)

	GameSession.request_load(path)
	var reloaded: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(reloaded)
	_take_off_process(reloaded)

	var restored: Array[Dictionary] = reloaded.simulation.arrivals().to_save()
	check_eq(restored.size(), pending.size(), "the pending arrival comes back on load")
	if restored.size() > 0:
		check_eq(restored[0]["species_id"], pending[0]["species_id"], "...for the same species")
		check(
			absf(float(restored[0]["remaining"]) - remaining_before) < 0.01,
			"...still carrying the delay it had already spent, not silently reset to a fresh "
			+ "%.0f-%.0f s wait" % [
				ArrivalQueue.ARRIVAL_DELAY_MIN_SECONDS, ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS
			],
			"saved %.3f s remaining, restored %.3f s" % [remaining_before, float(restored[0]["remaining"])]
		)

	# Driven one simulated second at a time and STOPPED AT THE FIRST LANDING, so the assertion
	# below is about the arrival that was pending — not about however many later ones a meadow
	# with spare capacity goes on to fill in over the remaining ticks.
	var elapsed: float = 0.0
	for _i in range(ARRIVAL_TICKS):
		reloaded.simulation.tick(ARRIVAL_TICK_SECONDS)
		reloaded.displacement.tick(ARRIVAL_TICK_SECONDS)
		elapsed += ARRIVAL_TICK_SECONDS
		if reloaded.total_residents() > 0:
			break

	check(
		reloaded.total_residents() > 0,
		"THE RULING: the animal that was on its way when the child quit ACTUALLY ARRIVES after "
		+ "the reload, into a habitat the file carries no home site for",
		"%d resident(s) in %d site(s) after %.0f simulated seconds" % [
			reloaded.total_residents(), reloaded.registry.sites().size(), elapsed
		]
	)
	# ...ONE animal, at the saved delay. Restoring the queue and then marking everything dirty must
	# not land two rabbits where one was pending. The guarantee is `enqueue()`'s `has_pending()`
	# no-op, NOT the step order in `apply()`: `mark_all_dirty()` enqueues nothing synchronously, so
	# the same holds with the two steps swapped. Label corrected 2026-08-02 — it used to credit the
	# ordering, which is a readability choice.
	check_eq(
		reloaded.total_residents(), 1,
		"...exactly one of it: `enqueue()` no-ops on `has_pending()`, so the dirty drain that "
		+ "follows the restore cannot double-enqueue it"
	)
	check(
		elapsed <= remaining_before + ARRIVAL_TICK_SECONDS + 0.001,
		"...and it arrived on the delay the file carried, not after a fresh one",
		"%.3f s remaining when saved, arrived %.0f simulated seconds after the load"
			% [remaining_before, elapsed]
	)

	unsettled.free()
	reloaded.free()
	GameSession.clear()


## A hand-edited arrival queue must not take the world down with it. `run-tests.sh` fails any
## suite that prints a runtime script error, so the absence of one IS half this assertion; the
## other half is that the well-formed entry beside the garbage still works.
func _check_a_hand_edited_arrival_queue_loads_rather_than_throwing() -> void:
	var corrupt: Dictionary = _captured.duplicate(true)
	corrupt["arrivals"] = [
		{"position": [4, 4], "species_id": "rabbit", "remaining": "soon"},
		{"position": [5], "species_id": "rabbit", "remaining": 10.0},
		{"position": [6, 6], "species_id": "rabbit"},
		{"position": {"x": 7}, "species_id": "rabbit", "remaining": 10.0},
		{"position": [8, 8], "species_id": "griffin", "remaining": 10.0},
		{"position": [GRASS_X_FROM, GRASS_Z], "species_id": "rabbit", "remaining": 15.0},
	]
	var path: String = SaveStore.unique_path_for("Hand edited arrivals")
	check_eq(SaveStore.write(path, corrupt), OK, "a hand-edited save is written")

	GameSession.request_load(path)
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var world: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(world)
	_take_off_process(world)

	check_eq(
		world.simulation.arrivals().size(), 1,
		"four malformed arrivals and one naming a species that is not in the roster are dropped; "
		+ "the well-formed one survives"
	)
	check(
		world.simulation.arrivals().has_pending(Vector2i(GRASS_X_FROM, GRASS_Z), "rabbit"),
		"...and it is the well-formed one"
	)
	check(world.paint_tile(2, 2, "grass"), "...and the world is still playable")

	world.free()
	GameSession.clear()


## THE CAST FAMILY — the branch's signature defect, given a negative control at last.
##
## `apply()` and `WorldRoot._ready()` read hand-edited JSON, and gdd.md -> Saves makes that
## ANTICIPATED input, not an exotic edge case. A bare `as Array` or `as String` on the wrong type
## is not an empty array or an empty string: it is a runtime cast error that ABORTS ITS ENCLOSING
## FUNCTION, and where it aborts decides how bad the day is:
##
##   * in `apply()` — after terrain, buildings, Wood, home sites and Species Hosted are already
##     in the LIVE world and before `mark_all_dirty()`. The child is left inside their own
##     half-restored world with an inert simulation (nothing dirty, so no arrival can ever
##     enqueue until their next edit) while `push_error` tells them it is an unsaved default one,
##     and `save_path` is dropped so their next hour of play goes nowhere.
##   * in `_ready()` — `name`, `preset_id` and `seed` are read there, and an abort leaves grid,
##     simulation and autosave all null: an unplayable scene from a one-character edit.
##
## SO THE ASSERTION IS "PLAYABLE AND STILL THEIRS", not "no error". The absence of a runtime error
## is enforced for free — `run-tests.sh` fails any suite that prints one — but a suite resting on
## that alone would still pass on the version of this bug that merely drops the save path.
##
## WHY THIS DOES NOT ASSERT THE BYTES ON DISK, unlike `_check_one_refused_load()`. These files are
## ACCEPTED — `can_apply()` passes, `apply()` succeeds on the good fields and degrades the bad one
## — so `Autosave.attach()` rewrites the file during `_ready()` BY DESIGN ("a brand-new world has
## to exist on disk before its first ninety seconds are up"). Byte-equality is the promise for a
## file this build REFUSED; for one it opened, the promise is that the child's world is still in
## there afterwards rather than a fresh default stamped over it, and that is what is asserted.
func _check_a_wrong_typed_field_loads_into_a_playable_world() -> void:
	# The five `as Array` sites in `apply()`, one wrong type each so no single cast can pass by
	# accident: `arrivals` was the new one, the other four were its unguarded siblings.
	_check_one_wrong_typed_field({"arrivals": "nope"}, "a string `arrivals`")
	_check_one_wrong_typed_field({"arrivals": {"a": 1}}, "an object `arrivals`")
	_check_one_wrong_typed_field({"arrivals": 7}, "a number `arrivals`")
	_check_one_wrong_typed_field({"terrain": "nope"}, "a string `terrain`")
	_check_one_wrong_typed_field({"buildings": 7}, "a number `buildings`")
	_check_one_wrong_typed_field({"home_sites": {"a": 1}}, "an object `home_sites`")
	_check_one_wrong_typed_field({"species_hosted": "rabbit"}, "a string `species_hosted`")
	# ...and the two `as String` / bare-`int()` sites `WorldRoot._ready()` reaches BEFORE `apply()`
	# is ever called, where the blast radius is the whole scene.
	_check_one_wrong_typed_field({"name": {"oops": 1}}, "an object `name`")
	_check_one_wrong_typed_field({"name": 42}, "a number `name`")
	# ...and the `name` read INSIDE `migrate()`, which only a v1 file reaches: the seed repair
	# derives its value from the name, so a non-string name aborted the migration and handed
	# `_ready()` an empty dictionary — at which point `apply()` was skipped entirely while
	# `save_path` was still set, and `Autosave.attach()` stamped an empty default world over the
	# child's file. Overwriting is worse than deleting; this is the case that reaches it.
	_check_one_wrong_typed_field(
		{"save_version": 1, "seed": 0, "name": {"oops": 1}},
		"a v1 file whose `name` is an object, which is what the seed repair reads"
	)
	_check_one_wrong_typed_field({"preset_id": 42}, "a number `preset_id`")
	_check_one_wrong_typed_field({"seed": [1, 2]}, "an array `seed` in a v2 file")
	_check_one_wrong_typed_field({"seed": "abc"}, "a string `seed` in a v2 file")
	# Every one of them at once, which is what a curious eight-year-old with a text editor
	# actually produces.
	_check_one_wrong_typed_field(
		{
			"arrivals": "nope", "terrain": 7, "buildings": "x", "home_sites": 1,
			"species_hosted": {"a": 1}, "name": 42, "preset_id": [], "seed": [1, 2],
			"wood": "lots",
		},
		"every wrong-typed field at once"
	)


func _check_one_wrong_typed_field(overrides: Dictionary, label: String) -> void:
	var corrupt: Dictionary = _captured.duplicate(true)
	for key: String in overrides:
		corrupt[key] = overrides[key]
	var path: String = SaveStore.unique_path_for("Hand edited - %s" % label)
	if not check_eq(SaveStore.write(path, corrupt), OK, "%s: the hand-edited save is written" % label):
		return

	GameSession.request_load(path)
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var world: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(world)

	# ASKED BEFORE ANYTHING TOUCHES THESE FIELDS, because an aborted `_ready()` leaves them null
	# and `_take_off_process()` would then take the rest of this suite down with it.
	var built: bool = world.grid != null and world.simulation != null and world.autosave != null
	if not check(
		built,
		"%s: `_ready()` runs to completion — grid, simulation and autosave all exist" % label,
		"grid %s, simulation %s, autosave %s" % [
			"ok" if world.grid != null else "NULL",
			"ok" if world.simulation != null else "NULL",
			"ok" if world.autosave != null else "NULL",
		]
	):
		world.free()
		GameSession.clear()
		return
	_take_off_process(world)

	# Read before the probe edit below, which would dirty a neighbourhood itself and mask this.
	var pending: int = world.simulation.pending_evaluations()
	var sites: int = world.registry.sites().size()

	check_eq(
		world.grid_size(), Vector2i(WorldGrid.DEFAULT_WIDTH, WorldGrid.DEFAULT_DEPTH),
		"%s: ...at the world's real %dx%d size" % [label, WorldGrid.DEFAULT_WIDTH, WorldGrid.DEFAULT_DEPTH]
	)
	check_eq(
		world.save_path, path,
		("%s: ...and it is STILL THE CHILD'S WORLD — the load kept the file, rather than dropping "
		+ "the path and leaving them playing into nothing while the log calls it a default world")
			% label
	)
	# THE INERT-SIMULATION HALF, and the reason "no runtime error" alone is not enough. When
	# `apply()` unwound at a cast it never reached `mark_all_dirty()`, so a world full of the
	# child's homes sat with NOTHING queued: no arrival could enqueue until their next edit.
	if sites > 0:
		check(
			pending > 0,
			("%s: ...with a LIVE simulation: the restore reached `mark_all_dirty()`, so its "
			+ "neighbourhoods are queued instead of the world sitting inert") % label,
			"%d home site(s), pending_evaluations() == %d" % [sites, pending]
		)

	# THE FILE WAS REALLY APPLIED, not skipped. `_ready()` builds a full default world before it
	# restores anything, so "playable" alone cannot tell a restored world from a fresh one wearing
	# the child's filename — and a fresh one wearing the child's filename is what `Autosave` then
	# writes over their save. Wood is the cheapest field that differs between the two.
	if not overrides.has("wood"):
		check_eq(
			world.get_wood(), int(_captured["wood"]),
			("%s: ...holding the CHILD'S Wood stockpile, so the save was applied rather than "
			+ "silently skipped in favour of an empty default world with their filename on it")
				% label
		)

	# THE FILE, substantively rather than byte-for-byte — see this function's header for why.
	var on_disk: Dictionary = SaveStore.read(path)
	check(not on_disk.is_empty(), "%s: ...and the file is still readable JSON afterwards" % label)
	check_eq(
		int(on_disk.get("wood", -1)), world.get_wood(),
		"%s: ...still holding the world the child was playing, not a fresh default stamped over it"
			% label
	)

	check(world.paint_tile(2, 2, "grass"), "%s: ...and the world is playable: an edit lands" % label)
	check_eq(world.get_tile_terrain(2, 2), "grass", "%s: ...and takes effect" % label)

	world.free()
	GameSession.clear()


## THE SEED REPAIR RULE, stated directly rather than only through a whole load — because getting
## it wrong in EITHER direction is a real defect, and only one of the two directions is a crash.
func _check_the_seed_repair_rule() -> void:
	var v2: Dictionary = _captured.duplicate(true)
	v2["save_version"] = 2
	v2["name"] = "Seed rule"
	v2["seed"] = [1, 2]
	var repaired: Variant = WorldSnapshot.migrate(v2)
	if not check(
		typeof(repaired) == TYPE_DICTIONARY,
		"migrate() returns a dictionary for a v2 file whose `seed` is an array, rather than "
		+ "aborting mid-cast and handing its caller a null to dereference"
	):
		return
	check(
		WorldSnapshot.is_number((repaired as Dictionary).get("seed", null)),
		"a NON-NUMERIC seed is repaired at ANY save_version, so the one bare `int()` that reads "
		+ "this field cannot abort `_ready()` and leave an unplayable scene",
		"seed came back as %s" % str((repaired as Dictionary).get("seed", null))
	)
	check_eq(
		int((repaired as Dictionary)["seed"]), WorldSnapshot.seed_from_name("Seed rule"),
		"...to the same stable name-derived value a v1 file gets"
	)

	# THE OTHER DIRECTION, and it is why the v1 rule was not simply hoisted out of `if version < 2`.
	var zero: Dictionary = _captured.duplicate(true)
	zero["save_version"] = 2
	zero["seed"] = 0
	check_eq(
		int((WorldSnapshot.migrate(zero) as Dictionary)["seed"]), 0,
		"...while a v2 `seed: 0` is LEFT EXACTLY AS IT IS: the editor/`none` path autosaves 0 and "
		+ "capture(..., 0) writes it, so that is a legitimate state and repairing it would be wrong"
	)

	# THE `name` GUARD (v1 path), which is where the repair reads its input from.
	var v1: Dictionary = _captured.duplicate(true)
	v1["save_version"] = 1
	v1["seed"] = 0
	v1["name"] = {"oops": 1}
	var migrated: Variant = WorldSnapshot.migrate(v1)
	if not check(
		typeof(migrated) == TYPE_DICTIONARY,
		"migrate() also survives a `name` that is not a string, which it reads to DERIVE the seed"
	):
		return
	check(
		WorldSnapshot.is_number((migrated as Dictionary).get("seed", null)),
		"...still handing back a usable seed, from the empty-string fallback",
		"seed came back as %s" % str((migrated as Dictionary).get("seed", null))
	)


## A FILE WRITTEN BY THE PREVIOUS BUILD. It has no `arrivals` key and its `seed` is the constant
## 0 that build wrote into every world it ever saved.
func _check_a_v1_file_still_loads_and_gains_a_stable_seed() -> void:
	var v1: Dictionary = _captured.duplicate(true)
	v1["save_version"] = 1
	v1["seed"] = 0
	v1["name"] = "Ada's World"
	v1.erase("arrivals")
	var path: String = SaveStore.unique_path_for("Ada's World")
	check_eq(SaveStore.write(path, v1), OK, "a v1 save is written")

	GameSession.request_load(path)
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var world: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(world)
	_take_off_process(world)

	check_eq(world.save_path, path, "a v1 file still opens — the migration carries it forward")
	check_eq(world.world_name, "Ada's World", "...as the world it was")
	check_eq(
		world.total_residents(), _source.total_residents(),
		"...with its population intact"
	)
	check_eq(
		world.simulation.arrivals().size(), 0,
		"...and an EMPTY arrival queue, because a v1 file could not have carried one and a "
		+ "migration must not invent arrivals in a child's world"
	)

	# THE SEED HALF. Every v1 file on disk says `seed: 0`, so leaving them there would give every
	# old world the same mist reveal and make 0 ambiguous forever.
	check(
		world.world_seed != 0,
		"a migrated v1 world runs on a REAL seed, not the constant 0 its file carries",
		"world_seed == %d" % world.world_seed
	)
	check_eq(
		world.world_seed, WorldSnapshot.seed_from_name("Ada's World"),
		"...derived from the world's name, which is the documented rule"
	)
	check_eq(
		int(WorldSnapshot.migrate(v1)["seed"]), world.world_seed,
		"...and migrating the same file again yields the SAME seed, so the world's mist does not "
		+ "reshuffle every time it is opened"
	)

	world.free()
	GameSession.clear()


## THE OTHER HALF OF I-3: a world made today gets a seed drawn at New Game time, and it reaches
## the file. Before the ruling, `seed` was a constant 0 in every save this build wrote.
func _check_a_new_world_gets_a_real_seed() -> void:
	var menu: GDScript = load(NEW_GAME_SCRIPT) as GDScript
	if not check(menu != null, "%s loads" % NEW_GAME_SCRIPT):
		return
	var first: int = int(menu.call("new_seed"))
	check(first != 0, "New Game draws a non-zero seed", "got %d" % first)

	# ONE PAIR PROVED NOTHING. The old generator built a fresh RNG and called `randomize()` per
	# call, so it inherited clock resolution rather than a sequence: measured at 41.7-43.7% of
	# consecutive pairs identical across three processes. A two-draw assertion passed on
	# interpreter warm-up timing, by a margin of about a microsecond — it claimed a property the
	# implementation did not have. At ~42% per pair, %d clean consecutive draws is ~1e-15.
	var draws: Array[int] = [first]
	var repeats: int = 0
	var zeros: int = 0 if first != 0 else 1
	var distinct: Dictionary = {first: true}
	for _i in range(SEED_DRAW_SAMPLES - 1):
		var drawn: int = int(menu.call("new_seed"))
		if drawn == 0:
			zeros += 1
		if drawn == draws[draws.size() - 1]:
			repeats += 1
		draws.append(drawn)
		distinct[drawn] = true
	check_eq(
		repeats, 0,
		"...and NO draw repeats the one immediately before it, across %d back-to-back draws: the "
			% SEED_DRAW_SAMPLES
		+ "generator is seeded ONCE and advanced per draw, not re-seeded from the clock on every "
		+ "call — two worlds made in the same breath must not share row 13's reveal"
	)
	check_eq(zeros, 0, "...and none of the %d draws is the 0 sentinel" % SEED_DRAW_SAMPLES)
	check_eq(
		distinct.size(), SEED_DRAW_SAMPLES,
		"...and all %d are distinct, not merely non-consecutive" % SEED_DRAW_SAMPLES
	)

	var path: String = SaveStore.unique_path_for("Seeded")
	GameSession.request_new(WorldPreset.default_preset(), "Seeded", path, first)
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var world: WorldRoot = packed.instantiate() as WorldRoot
	# `_ready()` consumes the intent AND `Autosave.attach()` writes the file, inside this call.
	root.add_child(world)
	_take_off_process(world)

	check_eq(world.world_seed, first, "the seed the menu drew reaches the world")
	var on_disk: Dictionary = SaveStore.read(path)
	check(not on_disk.is_empty(), "...and the new world reached disk")
	check_eq(int(on_disk["seed"]), first, "...and the file records that seed, not 0")
	check_eq(int(on_disk["save_version"]), WorldSnapshot.SAVE_VERSION, "...at the current save_version")

	world.free()
	GameSession.clear()


## Every world in this suite is driven by hand, so nothing depends on how many real frames pass.
func _take_off_process(world: WorldRoot) -> void:
	world.wood.set_process(false)
	world.simulation.set_process(false)
	world.presentation.set_process(false)
	world.displacement.set_process(false)
	if world.autosave != null:
		world.autosave.set_process(false)


## A REFUSED SAVE MUST DEGRADE GRACEFULLY *AND* SURVIVE ON DISK.
##
## Two separate promises, and until 2026-08-01 only the first was tested:
##
##   1. THE WORLD IS PLAYABLE. `WorldSnapshot.can_apply()` validates only `save_version`, so
##      `"width"` reaches `_ready()` as untrusted input and three arrays are allocated at
##      `width * depth`. Measured failures this guards:
##        * `width: 0` -> `WorldGrid.build()` clamps to 1 and the player lands in a ONE-TILE
##          world while `push_error` tells them "the world is the default one".
##        * `width: 200` -> 40,000 tiles, past gdd.md's ~128x128 ceiling; Jolt refuses bodies.
##        * `width: {"oops": 1}` -> a bare `int()` on a Dictionary is not a 0, it is a runtime
##          "Nonexistent 'int' constructor" error that aborts `_dimension_from_save()` before
##          the bound can run, giving a 1x36 world where `paint_tile(5,5,"grass")` returns
##          false. The suite has no assertion for "no SCRIPT ERROR" because it does not need
##          one: `scripts/run-tests.sh` fails any suite that prints one, even on exit 0.
##
##   2. THE PLAYER'S FILE IS STILL THERE. This is the half a review found missing, and the
##      defect it was missing was the worst on the branch: `_ready()` assigned `save_path`
##      BEFORE reading the file, so a refusal left the path pointing at a world this build had
##      just declined to open — and `Autosave.attach()`'s interval write stamped a fresh empty
##      36x36 world over it inside the same `_ready()`. A real file named "Ada's World" holding
##      999 Wood came back as "Wildhaven" with 50. **Overwriting is worse than deleting**, and
##      the design's failure table promises a refused file is left for a parent to open and
##      read. So the assertions below are about THE BYTES ON DISK, not about the world: an
##      assertion that only inspects the resulting world cannot see this defect at all.
func _check_a_refused_load_is_playable_and_leaves_the_file_untouched() -> void:
	_check_one_refused_load({"width": 0}, "a zero width")
	_check_one_refused_load({"width": 200}, "a width past the ~128x128 ceiling")
	_check_one_refused_load({"depth": -5}, "a negative depth")
	_check_one_refused_load(
		{"save_version": WorldSnapshot.SAVE_VERSION + 1}, "a save from a NEWER build"
	)
	# Both dimensions non-numeric, and of two different wrong types, so neither cast site can
	# pass by accident.
	_check_one_refused_load(
		{"width": {"oops": 1}, "depth": "thirty-six"}, "a non-numeric width and depth"
	)


## Writes a corrupted copy of the captured world, opens it through the REAL load path, and
## asserts both promises above. `overrides` is applied over a full valid capture, so the only
## thing wrong with the file is the thing being tested.
func _check_one_refused_load(overrides: Dictionary, label: String) -> void:
	var corrupt: Dictionary = _captured.duplicate(true)
	for key: String in overrides:
		corrupt[key] = overrides[key]
	var path: String = SaveStore.unique_path_for("Refused - %s" % label)
	if not check_eq(SaveStore.write(path, corrupt), OK, "%s: the corrupt save is written" % label):
		return

	# THE BYTES, BEFORE. Held as a string rather than compared field-by-field because the promise
	# is that the file is *untouched* — a re-serialisation that happened to round-trip equal would
	# still be a write onto a file this build said it could not open.
	var before: String = FileAccess.get_file_as_string(path)

	GameSession.request_load(path)
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var world: WorldRoot = packed.instantiate() as WorldRoot
	# `_ready()` runs synchronously inside this call (the parent is already in the tree and the
	# process loop is running — unlike `_initialize()`, see `test_autosave_triggers.gd`'s class
	# doc). So by the time it returns, the file has been read, refused, a default world built,
	# and `Autosave.attach()` has had its one chance to write. This is the frame the defect
	# happened in.
	root.add_child(world)
	world.wood.set_process(false)
	world.simulation.set_process(false)
	world.presentation.set_process(false)
	world.displacement.set_process(false)

	_check_the_file_is_unchanged(path, before, "%s: the refused file is byte-for-byte unchanged "
		% label + "after the load attempt, so a parent can still open and read it")

	# ...and it stays that way, because the world holds no path to write to. Asserted separately
	# from the bytes: the bytes prove the attach-time write did not land, this proves no LATER
	# autosave — interval, move-in or exit-to-menu — can find the file either.
	check_eq(
		world.save_path, "",
		"%s: the refused world holds NO file path, so nothing it does can reach that file" % label
	)
	check(
		not world.autosave.request("interval"),
		"%s: an explicit autosave DECLINES rather than inventing a default world over the file"
			% label
	)
	_check_the_file_is_unchanged(path, before,
		"%s: ...and the bytes are still unchanged after that autosave attempt" % label)

	# THE PLAYABILITY HALF: a default-SIZED world, not a 1x1, not a 200x200, not a 1x36.
	# `push_error` says "an UNSAVED default world"; this is that claim.
	check_eq(
		world.grid_size(), Vector2i(WorldGrid.DEFAULT_WIDTH, WorldGrid.DEFAULT_DEPTH),
		"%s falls back to the default %dx%d world, matching what push_error says happened"
			% [label, WorldGrid.DEFAULT_WIDTH, WorldGrid.DEFAULT_DEPTH]
	)
	check_eq(
		world.get_tile_terrain(0, 0), WorldGrid.START_TERRAIN_ID,
		"...made of real terrain"
	)
	check(world.paint_tile(5, 5, "grass"), "...and still playable: an edit lands")
	check_eq(world.get_tile_terrain(5, 5), "grass", "...and takes effect")

	# `free()`, NOT `queue_free()`, and it is not a style choice. Every world here is ~1,296
	# `StaticBody3D` tiles and this whole suite runs inside ONE `_process()` call, so a queued
	# free releases nothing until every world has already been built: at five refused loads plus
	# the source, restored and probe worlds, the live body count crosses Jolt's 10,240 default and
	# the log fills with "Failed to create underlying Jolt Physics body". Those are real ERROR
	# lines, and drowning the log in them erodes the signal `run-tests.sh` scans for.
	world.free()
	GameSession.clear()


## Compared by content, reported by length and hash — a mismatch detail must not dump ~1,300
## tiles of JSON into the log.
func _check_the_file_is_unchanged(path: String, before: String, label: String) -> void:
	var after: String = FileAccess.get_file_as_string(path)
	check(
		after == before, label,
		"%d bytes -> %d bytes; sha256 %s -> %s" % [
			before.length(), after.length(),
			before.sha256_text().substr(0, 12), after.sha256_text().substr(0, 12)
		]
	)


## THE LOAD SCREEN MUST GREY WHAT THIS BUILD CANNOT OPEN — not merely what it cannot parse.
##
## `SaveStore.list()` used to set `readable` on JSON-parse success alone, which greys the wrong
## predicate: a file written by a LATER build, and one with no `save_version` at all, both parse
## perfectly and are both refused by `WorldRoot._ready()`. They drew as ordinary clickable rows
## whose only effect was to drop the child into an empty default world. The list and the load
## now ask the same question, `WorldSnapshot.can_apply()`.
func _check_the_load_list_greys_what_this_build_cannot_open() -> void:
	var openable: String = SaveStore.unique_path_for("Listed - openable")
	check_eq(SaveStore.write(openable, _captured), OK, "an openable save is written")

	var future: Dictionary = _captured.duplicate(true)
	future["save_version"] = WorldSnapshot.SAVE_VERSION + 1
	var future_path: String = SaveStore.unique_path_for("Listed - future version")
	check_eq(SaveStore.write(future_path, future), OK, "a newer-build save is written")

	var versionless: Dictionary = _captured.duplicate(true)
	versionless.erase("save_version")
	var versionless_path: String = SaveStore.unique_path_for("Listed - no version")
	check_eq(SaveStore.write(versionless_path, versionless), OK, "a version-less save is written")

	var readable_by_path: Dictionary = {}
	for entry: Dictionary in SaveStore.list():
		readable_by_path[entry["path"] as String] = bool(entry["readable"])

	# LISTED, NOT HIDDEN — the other half of the same rule, and it must not regress into hiding.
	check(
		readable_by_path.has(openable) and readable_by_path.has(future_path)
			and readable_by_path.has(versionless_path),
		"all three appear in the list, because a world silently vanishing is worse than one "
			+ "that will not open"
	)
	check_eq(readable_by_path.get(openable, false), true, "a save this build can open is offered")
	check_eq(
		readable_by_path.get(future_path, true), false,
		"a save written by a NEWER build is greyed, not offered as an ordinary row that opens "
			+ "an empty world when a child taps it"
	)
	check_eq(
		readable_by_path.get(versionless_path, true), false,
		"...and so is one with no `save_version` at all, which `can_apply()` also refuses"
	)
	check(
		FileAccess.file_exists(future_path) and FileAccess.file_exists(versionless_path),
		"...and listing an unopenable world never deletes it"
	)


func _check_in_flight_state_is_re_derived_not_restored() -> void:
	# The queue IS in the file as of 2026-08-02 — see
	# `_check_a_pending_arrival_survives_a_reload_with_no_home_site_yet` for why it had to be.
	check(_captured.has("arrivals"), "the save carries the pending arrival queue")
	check(
		not _captured.has("dirty"),
		"...but NOT the dirty queue, which really does re-derive: it drains at %d evaluations "
			% HabitatSimulation.MAX_EVALUATIONS_PER_FRAME
		+ "per frame, and anything that was dirty has already become an arrival or nothing"
	)
	# And a restored world that qualifies for a species still enqueues through the ordinary
	# event-driven path, because `apply()` marks every neighbourhood dirty after the restore.
	check(
		_measured_pending > 0,
		"a freshly restored world has evaluations queued, so the queue re-derives itself",
		"pending_evaluations() == %d immediately after _ready()" % _measured_pending
	)

	# THE ORDERING BOUND, MEASURED. The design doc wanted the terrain replay moved ahead of
	# `simulation.attach()` on the theory that ~1,300 `set_terrain` calls would dirty the queue
	# ~1,300 times. They do not: `grid.tile_changed` reaches only `WorldRoot._on_tile_changed`,
	# which re-emits and nothing more, and `HabitatSimulation` has no entry point but its four
	# triggers. So the queue after a restore is exactly `mark_all_dirty()`'s output — one entry
	# per restored home site. Asserted as an EQUALITY so that a future change which does start
	# dirtying per tile fails here instead of quietly costing a loading world 1,300 evaluations.
	check_eq(
		_measured_pending, _restored.registry.sites().size(),
		"the restore queues exactly one evaluation per home site, not one per tile"
	)
	check(
		_measured_pending < _restored.grid.width * _restored.grid.depth,
		"...which is far below the %d-tile grid — the restore is not a full-grid re-scan"
			% (_restored.grid.width * _restored.grid.depth),
		"pending %d" % _measured_pending
	)


# --- v3: removal receipts survive a reload (reported bug fix) -------------------------------
#
# THE REPORTED DEFECT. `remove_at()` on a painted tile reads `RemovalLedger.paint_receipt()` to
# know what to revert to; before v3, `WorldSnapshot` deliberately did not save receipts (they
# were grouped with other in-flight state that gets re-derived on load), but nothing actually
# re-derives "what was this tile before it was painted" — there is no other source for it. So
# every tile painted before a save/load became permanently un-removable: Take Away did nothing,
# silently, on any edit from an earlier session. `_source` painted real grass and rock tiles
# through the ordinary API above (`_build_a_world_through_the_real_causal_path()`), which is
# exactly the scenario the report describes; this checks the ACTUAL bug through the REAL load
# path, not just that the schema round-trips (`test_world_snapshot.gd` already covers that).

func _check_take_away_still_works_after_a_reload() -> void:
	var tile := Vector2i(GRASS_X_FROM, GRASS_Z)
	check_eq(_restored.get_tile_terrain(tile.x, tile.y), "grass",
		"setup: the reloaded tile is the grass this suite painted through the real causal path")

	check(_restored.can_remove(tile.x, tile.y),
		"THE FIX: can_remove() is true on a tile painted in the session that was saved, not just "
		+ "one painted in the current session")
	check(_restored.remove_at(tile.x, tile.y),
		"...and remove_at() actually removes it — this used to return false, silently, which is "
		+ "the reported bug")
	check_eq(_restored.get_tile_terrain(tile.x, tile.y), WorldGrid.START_TERRAIN_ID,
		"...reverting to the terrain it was painted over, exactly as an in-session removal would")


# --- D-32: the settlement window across a reload ----------------------------------------------
#
# THE DEFECT. `GentleDisplacement`'s grace window gates the IRREVERSIBLE half of a displacement,
# and only `on_edit()` and `on_arrival()` ever open a gesture. A restore reaches NEITHER, so a
# gesture that was open when the file was written was silently cancelled by the reload and the
# home sat PERMANENTLY over capacity — until some unrelated later edit near it re-armed a window
# and the displacement finally fired with no context for the child. Reachable through the
# ordinary `exit_to_menu` path: make the displacing edit, read the warning, press Leave inside
# the 12 s window.
#
# THE RULING (human, 2026-08-02) is Option A: re-arm from world state at load, do not persist
# the gesture. The three checks below are the reproduction, and the two zeros the fix must not
# cost — because a settlement timer that armed on every load would be exactly the idle work
# gdd.md -> Performance and `SettlementWindow`'s own header forbid.

func _check_a_settlement_window_survives_a_reload() -> void:
	var source: WorldRoot = _build_a_villager_in_a_house()
	if not check(
		source.total_residents() > 0,
		"a villager has moved into the House beside its cultivated field",
		"if this fails the capacity constants moved; fix the setup, not the assertions"
	):
		source.free()
		GameSession.clear()
		return

	_check_a_healthy_world_arms_no_gesture_on_load(source)
	_check_a_pending_displacement_is_re_armed_and_actually_resolves(source)

	source.free()
	GameSession.clear()


## THE ZERO, AND IT IS NOT VACUOUS — this world genuinely holds a settled resident. If every load
## armed a timer, "a world with no residents never opens a settlement window in its life" would
## be gone and so would the reason `SettlementWindow` is free when idle.
func _check_a_healthy_world_arms_no_gesture_on_load(source: WorldRoot) -> void:
	check_eq(
		_homes_over_capacity(source), 0,
		"the settled world is within capacity at every home before the quit"
	)

	var reloaded: WorldRoot = _reload_through_the_real_load_path(source, "Healthy villager")
	# Read before anything ticks: this is the state `_ready()` left behind.
	var armed_on_load: int = reloaded.displacement.pending_gestures()
	check(
		reloaded.total_residents() > 0,
		"THE ZERO IS NOT VACUOUS: the restored healthy world really does hold a settled resident",
		"%d resident(s) in %d home site(s)" % [
			reloaded.total_residents(), reloaded.registry.sites().size()
		]
	)
	check_eq(
		armed_on_load, 0,
		"THE ZERO: a restored world whose homes are all within capacity opens NO settlement gesture"
	)

	# ...and asking again is free, in the one sense that matters: it never touches the habitat
	# queue. `reconcile_after_load()` reads `CapacityEvaluator` directly and enqueues nothing, so
	# it cannot become a fifth habitat trigger.
	var before: int = reloaded.simulation.evaluations_run
	check_eq(reloaded.displacement.reconcile_after_load(), 0, "...and asking it again arms nothing")
	check_eq(
		reloaded.simulation.evaluations_run, before,
		"...at zero cost to `evaluations_run`: the reconcile reads capacity directly and never "
		+ "enqueues a habitat evaluation"
	)

	reloaded.free()


## THE REPRODUCTION, through the real API and the real load path. Fails on the pre-fix code at
## the "re-armed" assertion, and again at the outcome one.
func _check_a_pending_displacement_is_re_armed_and_actually_resolves(source: WorldRoot) -> void:
	# The child clears the field beside the House — a terraform, which is the likeliest
	# displacement in the floor, and mode-agnostic to `on_edit()`.
	check(
		source.paint_tile(FIELD_TILE.x, FIELD_TILE.y, WorldGrid.START_TERRAIN_ID),
		"the cultivated field beside the House is cleared back to wild grass"
	)
	check(
		source.displacement.pending_gestures() >= 1,
		"...which arms the %.0f s grace window" % SettlementWindow.GRACE_WINDOW_SECONDS,
		"%d gesture(s)" % source.displacement.pending_gestures()
	)
	check(
		_homes_over_capacity(source) >= 1,
		"...and the House really is over capacity: this world has something to displace",
		"%d home(s) over capacity" % _homes_over_capacity(source)
	)

	# The child now presses Leave, inside the window. Capture, to disk, and back in.
	var reloaded: WorldRoot = _reload_through_the_real_load_path(source, "Pending displacement")
	var armed_on_load: int = reloaded.displacement.pending_gestures()
	var over_on_load: int = _homes_over_capacity(reloaded)
	check(
		armed_on_load >= 1,
		"THE RULING (D-32): the displacement that was pending when the child quit is armed AGAIN "
		+ "after the reload, rather than silently cancelled",
		"%d gesture(s) immediately after the restore" % armed_on_load
	)
	check(
		over_on_load >= 1,
		"...over a home that really is still over capacity, so the gesture is not decoration",
		"%d home(s) over capacity" % over_on_load
	)

	# THE OUTCOME, not a timer value. Bounded, and it stops the instant the condition holds.
	# NOTHING calls `reconcile_after_load()` by hand before this point, deliberately: the drive
	# below must be resolving the gesture the RESTORE opened, or the negative control for the two
	# assertions after it would be satisfied by the test's own call.
	var elapsed: float = 0.0
	for _i in range(MAX_DISPLACEMENT_TICKS):
		reloaded.displacement.tick(DISPLACEMENT_TICK_SECONDS)
		elapsed += DISPLACEMENT_TICK_SECONDS
		if _homes_over_capacity(reloaded) == 0:
			break
	_measured_resolve_seconds = elapsed
	check_eq(
		_homes_over_capacity(reloaded), 0,
		"...and it RESOLVES: past the grace window the restored world has no home over capacity, "
		+ "which is the invariant the reload used to break permanently"
	)
	check(
		reloaded.displacement.warnings_raised >= 1,
		"...having WARNED first, so nothing about the child's world blinked out unexplained",
		"%d warning(s) after %.0f simulated seconds" % [
			reloaded.displacement.warnings_raised, elapsed
		]
	)
	reloaded.free()

	# THE COST, measured on a SECOND reload of the same world rather than on the one above —
	# calling `reconcile_after_load()` by hand there would have re-armed the window and made the
	# resolution assertion pass even with the fix removed.
	var probe: WorldRoot = _reload_through_the_real_load_path(source, "Reconcile cost probe")
	var before: int = probe.simulation.evaluations_run
	check(
		probe.displacement.reconcile_after_load() >= 1,
		"the reconcile is what finds an over-capacity home, walking one capacity read per home site"
	)
	_measured_reconcile_evaluations = probe.simulation.evaluations_run - before
	check_eq(
		probe.simulation.evaluations_run, before,
		"...still at zero cost to `evaluations_run`, even when it arms a window: it reads "
		+ "CapacityEvaluator directly and enqueues nothing"
	)
	probe.free()


## THE PERMANENT ZERO. A world with nobody in it opens no settlement window in its life, and a
## reload is not an exception to that.
func _check_a_world_with_no_residents_arms_no_gesture_on_load() -> void:
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	GameSession.clear()
	var empty: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(empty)
	_take_off_process(empty)
	check_eq(empty.total_residents(), 0, "the default world holds nobody")

	var reloaded: WorldRoot = _reload_through_the_real_load_path(empty, "Nobody home")
	var armed_on_load: int = reloaded.displacement.pending_gestures()
	check_eq(reloaded.total_residents(), 0, "...and it restores holding nobody")
	check_eq(
		armed_on_load, 0,
		"THE PERMANENT ZERO: a world with no residents opens no settlement window on load either"
	)

	empty.free()
	reloaded.free()
	GameSession.clear()


## A House on terraformed grass beside a cultivated field, driven by hand until a villager
## actually moves in — the real causal path, stopped at the first landing.
func _build_a_villager_in_a_house() -> WorldRoot:
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	GameSession.clear()
	var world: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(world)
	_take_off_process(world)

	check(world.paint_tile(HOUSE_TILE.x, HOUSE_TILE.y, "grass"), "the house site is terraformed")
	check(world.place_building(HOUSE_TILE.x, HOUSE_TILE.y, "house"), "the House places")
	check(
		world.paint_tile(FIELD_TILE.x, FIELD_TILE.y, "cultivated_field"),
		"a cultivated field is painted beside it"
	)

	for _i in range(ARRIVAL_TICKS):
		world.simulation.tick(ARRIVAL_TICK_SECONDS)
		world.displacement.tick(ARRIVAL_TICK_SECONDS)
		if world.total_residents() > 0:
			break
	return world


## How many settled homes are over their own capacity right now — the condition the pillar
## invariant is about, computed the same way `GentleDisplacement._affected_homes()` computes it.
func _homes_over_capacity(world: WorldRoot) -> int:
	var over: int = 0
	for site: HomeSite in world.registry.sites():
		if site.population() <= 0:
			continue
		var species: AnimalDefinition = world.roster.by_id(site.species_id)
		if species == null:
			continue
		var capacity: int = CapacityEvaluator.capacity(
			world.grid, world.registry, site.position, species, site
		)
		if site.population() > capacity:
			over += 1
	return over


## Capture -> disk -> `GameSession.request_load()` -> a fresh `Main.tscn` building itself in its
## own `_ready()`. The same path the Load button takes; never a direct `apply()` call.
func _reload_through_the_real_load_path(world: WorldRoot, label: String) -> WorldRoot:
	var captured: Dictionary = WorldSnapshot.capture(world, label, "meadow_start", 4242)
	var path: String = SaveStore.unique_path_for(label)
	check_eq(SaveStore.write(path, captured), OK, "%s: the capture writes to disk" % label)

	GameSession.request_load(path)
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var reloaded: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(reloaded)
	_take_off_process(reloaded)
	GameSession.clear()
	return reloaded


# --- v4: style_defaults survive a reload ------------------------------------------------------
#
# THE OUTBOUND HALF (what a chosen style default looks like on disk) is `test_world_snapshot.gd`.
# This is the inbound half, through the REAL load path, plus the compatibility promise: a save
# written before `style_defaults` existed must still open, falling back to each picker category's
# first catalog entry rather than raising — the same degradation `WorldRoot.get_style_default()`
# already gives a stale or corrupted entry (`test_style_defaults.gd`).

func _check_style_defaults_survive_a_reload() -> void:
	# A non-default choice, or this check would pass even if the restore always fell back to the
	# category's first catalog entry.
	_source.set_style_default("forest", "birch_tree")
	var captured: Dictionary = WorldSnapshot.capture(_source, "Styled", "meadow_start", 4242)
	check_eq(
		(captured["style_defaults"] as Dictionary).get("forest", ""), "birch_tree",
		"setup: the non-default forest choice is captured"
	)

	var path: String = SaveStore.unique_path_for("Styled")
	check_eq(SaveStore.write(path, captured), OK, "the styled world writes to disk")

	GameSession.request_load(path)
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var reloaded: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(reloaded)
	_take_off_process(reloaded)

	check_eq(
		reloaded.get_style_default("forest"), "birch_tree",
		"the chosen forest default survives the real load path, not just the catalog's first entry"
	)
	# ...and a category never touched still falls through to its own first catalog entry, exactly
	# as it does in a fresh world — the restore does not invent a choice for a category the child
	# never opened.
	check_eq(
		reloaded.get_style_default("farm_building"), "barn",
		"...while a category with no stored choice still resolves to its first catalog entry"
	)

	reloaded.free()
	GameSession.clear()


## THE COMPATIBILITY HALF. A file written before `style_defaults` existed (`save_version: 3`, no
## `"style_defaults"` key at all) must still apply cleanly — `dict_field()` reads the absent key
## as `{}`, which `get_style_default()` already treats as "nothing chosen yet" for every picker
## category, per Task 3's contract.
func _check_an_old_save_with_no_style_defaults_falls_back_cleanly() -> void:
	var old: Dictionary = _captured.duplicate(true)
	old["save_version"] = 3
	old.erase("style_defaults")
	check(not old.has("style_defaults"), "setup: the hand-built file really carries no key at all")

	var path: String = SaveStore.unique_path_for("Pre-style-defaults")
	check_eq(SaveStore.write(path, old), OK, "a pre-style_defaults v3 save is written")

	GameSession.request_load(path)
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var world: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(world)
	_take_off_process(world)

	check_eq(world.save_path, path, "the v3 file still opens — the migration carries it forward")
	# THE FALLBACK, one per picker "flavor" (a derived filename-slug and a real placeable id —
	# see `WorldRoot.get_style_default()`'s own doc comment), each category's FIRST catalog entry,
	# not a crash and not an invented choice.
	check_eq(world.get_style_default("forest"), "common_tree_1",
		"...falling back to the forest category's first catalog entry")
	check_eq(world.get_style_default("wild_grass"), "wild_grass",
		"...and the wild_grass category's first catalog entry")
	check_eq(world.get_style_default("house"), "house",
		"...and the house category's first catalog entry")
	check_eq(world.get_style_default("farm_building"), "barn",
		"...and the farm_building category's first catalog entry, the other id \"flavor\"")
	check(world.paint_tile(2, 2, "grass"), "...and the world is still playable: an edit lands")

	world.free()
	GameSession.clear()


## The three numbers the assertions above are built on, printed live rather than transcribed
## into a comment that could rot. Not assertions — each of them already has one.
func _report_the_measurements() -> void:
	# WHETHER THE FLAKE PATH WAS EXERCISED ON THIS RUN. A Gentle Displacement departure during
	# the arrival phase calls `unregister()` and gaps the source world's sequence numbers, which
	# the restore closes. That is what made the old absolute-equality assertion fail ~3% of runs.
	# Printed rather than asserted, because whether it happens is a dice roll — a run over a
	# loop can then count how many runs actually took the gapped path instead of assuming.
	var source_seqs: Array[int] = []
	for site: HomeSite in _source.registry.sites():
		source_seqs.append(site.sequence)
	var restored_seqs: Array[int] = []
	for site: HomeSite in _restored.registry.sites():
		restored_seqs.append(site.sequence)
	var gapped: bool = not source_seqs.is_empty() and source_seqs[source_seqs.size() - 1] != source_seqs.size() - 1

	note_expected_pending(
		"MEASURED ON THIS RUN (Task 6's ordering decision and roam precondition)",
		"%d resident(s) in %d home site(s); furthest roam from a home tile centre %.4f tiles "
			% [_source.total_residents(), _source.registry.sites().size(), _measured_separation]
		+ "(threshold %.2f); pending_evaluations() immediately after the restore's _ready() was "
			% MIN_ROAM_SEPARATION_TILES
		+ "%d, against a %d-tile grid — so the restore stays AFTER simulation.attach(), and "
			% [_measured_pending, _restored.grid.width * _restored.grid.depth]
		+ "WorldSnapshot.apply() is NOT split into apply_terrain()/apply_sites(). "
		+ "SEQUENCES source %s -> restored %s [%s]"
			% [str(source_seqs), str(restored_seqs), "GAPPED" if gapped else "contiguous"]
	)
	note_expected_pending(
		"MEASURED ON THIS RUN (D-32, the settlement window across a reload)",
		"reconcile_after_load() moved HabitatSimulation.evaluations_run by %d; the restored "
			% _measured_reconcile_evaluations
		+ "world resolved its pending displacement in %.0f simulated seconds against a %.0f s "
			% [_measured_resolve_seconds, SettlementWindow.GRACE_WINDOW_SECONDS]
		+ "grace window and a %.0f s budget"
			% (MAX_DISPLACEMENT_TICKS * DISPLACEMENT_TICK_SECONDS)
	)


# --- Scratch directory ------------------------------------------------------------------------

func _teardown() -> void:
	_clean_the_scratch_directory()
	SaveStore.SAVE_DIR = _REAL_SAVE_DIR


## Safe to be this blunt only because `SaveStore.SAVE_DIR` points at this suite's own scratch
## directory for its whole lifetime — never at a real player's `user://saves`.
func _clean_the_scratch_directory() -> void:
	var dir: DirAccess = DirAccess.open(SaveStore.SAVE_DIR)
	if dir == null:
		return
	for filename: String in dir.get_files():
		dir.remove(filename)
