extends QATestCase
## AUTOSAVE — Tier 1 row 1's "no save button, ever" (Pillar 1) made mechanical.
##
## THE MIST CONTRACT. Row 1's thin form names four triggers; row 13 (Mist) is unbuilt, so
## `mist_reveal` has **no caller in the build**. Rather than leave the clause untested until
## row 13 lands, the vocabulary is a constant and this suite iterates it — every reason in
## `Autosave.REASONS` must produce a file. Row 13 adds one call site and needs no new test, and
## a reason added to the vocabulary without a working write fails here immediately.
##
## THIS IS A CONTRACT, NOT COVERAGE, AND THE SUITE SAYS SO. The mist path is proven to write
## when asked; that it is asked at the right moment is row 13's to prove.
##
## THE ZERO (gdd.md -> Performance). An autosave must add nothing to the simulation's work.
## `evaluations_run` is measured across a full cycle and must not move.
##
## THE ATTACH-TIME WRITE, PROVEN AT THE ONLY MOMENT THAT PROVES IT (review fix, 2026-08-01).
## An earlier version of this suite set `save_path` at frame 3, AFTER `add_child()` — but
## `GameSession.clear()` puts `_ready()` on the "none" path, which never assigns `save_path`,
## so `attach()`'s `request("interval")` hit `Autosave`'s own empty-path guard and silently
## declined. `_wrote_once` then only flipped later, when
## `_check_every_reason_in_the_vocabulary_writes()`'s own loop over `REASONS` called
## `request("interval")` directly — which meant the "written at attach" assertion passed
## whether or not `attach()` contained a write at all. Removing `attach()`'s
## `request("interval")` line changed nothing, and that silence was the defect.
##
## The fix has two parts, and both are required: `save_path` is now assigned to a real scratch
## file BEFORE `add_child(_world)`, so `attach()` has somewhere to write once `_ready()` runs;
## and the assertion runs on the FIRST `_process()` frame this script observes, before any of
## this suite's own `request()` calls have a chance to write and mask a no-op. It checks
## `FileAccess.file_exists()` rather than `wrote_at_least_once()` — an actual file on disk is
## the guarantee this row promises a child who quits thirty seconds into a brand-new world, not
## a boolean the suite could flip on its own.
##
## MEASURED, NOT ASSUMED: an earlier draft of this fix put the assertion immediately after
## `add_child()`, inside `_initialize()`, on the theory that `_ready()` runs synchronously
## because `root` is a `SceneTree`'s own root and is trivially "already inside the tree". That
## theory was wrong here — instrumenting confirmed `_ready()`'s `NOTIFICATION_READY` (and
## therefore `attach()`'s write) is deferred past the point `add_child()` returns when called
## from `_initialize()`, before the tree's process loop has started. The check placed there
## failed even with `attach()`'s write fully intact, which would have been strictly worse than
## the defect it replaced — an assertion that could never pass. Moving it to the first
## `_process()` frame keeps it strictly before this suite's own writes (those wait for
## `_frames >= 3`) while actually being reachable.
##
## Run:
##   bash scripts/run-tests.sh autosave

const WORLD_PATH: String = "res://scenes/Main.tscn"

## The real directory a play session uses. Restored onto `SaveStore.SAVE_DIR` before `finish()`.
const _REAL_SAVE_DIR: String = "user://saves"

## An isolated scratch directory so this suite's writes — including the attach-time one, which
## now happens before this script controls anything else about the world — never touch a real
## player's save.
const _TEST_SAVE_DIR: String = "user://test_saves_autosave"

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false
var _made: Array[String] = []
var _events: Array[String] = []


func _initialize() -> void:
	begin("autosave triggers")
	GameSession.clear()
	SaveStore.SAVE_DIR = _TEST_SAVE_DIR
	_clean_the_scratch_directory()

	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		_teardown()
		finish()
		return
	_world = packed.instantiate() as WorldRoot

	# THE FIX: a real path BEFORE `add_child()`, or `attach()` has nowhere to write and its
	# `request("interval")` declines silently — see the class doc above.
	_world.save_path = SaveStore.unique_path_for("Autosave Suite")
	_made.append(_world.save_path)

	root.add_child(_world)
	_setup_ok = _world != null
	if not _setup_ok:
		_teardown()
		finish()
		return
	# NOT checked here. MEASURED, NOT ASSUMED: `_ready()` (and therefore `attach()`) does not
	# run synchronously inside this `add_child()` — the engine defers `NOTIFICATION_READY` past
	# the point `add_child()` returns when called from `_initialize()`, before the tree's own
	# process loop has started. A `FileAccess.file_exists()` check placed here was verified to
	# FAIL even with `attach()`'s write intact, which would have been a worse bug than the one
	# it replaced: a real, empty-headed assertion that could never pass. See the class doc.


func _process(_delta: float) -> bool:
	if not _setup_ok:
		finish()
		return true
	_frames += 1

	if _frames == 1:
		# ASSERTED on the first process frame this script observes — the earliest point
		# `_ready()` (and therefore `attach()`) is guaranteed to have run, and still strictly
		# before any `request()` call this suite makes itself (those wait for `_frames >= 3`
		# below). This is what proves `attach()` wrote, rather than a later call in this suite
		# masking a no-op — see the class doc for the defect this replaced.
		check(
			FileAccess.file_exists(_world.save_path),
			"the world was written once at attach, so it exists in Load from the first moment"
		)

	if _frames < 3:
		return false

	_world.wood.set_process(false)
	_world.simulation.set_process(false)
	_world.displacement.set_process(false)
	_world.presentation.set_process(false)
	_world.removals.set_process(false)
	_world.autosave.set_process(false)

	_world.autosave.saved.connect(func(reason: String, _p: String) -> void: _events.append(reason))

	_check_every_reason_in_the_vocabulary_writes()
	_check_the_vocabulary_is_exactly_the_gdd_four()
	_check_the_interval_fires_and_resets()
	_check_a_world_with_no_path_declines_rather_than_inventing_one()
	_check_move_in_triggers_a_write()
	_check_autosave_costs_the_simulation_nothing()

	_teardown()
	finish()
	return true


# --- Scratch directory -------------------------------------------------------------------

func _teardown() -> void:
	for path: String in _made:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
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


## THE MIST CONTRACT, and the reason this suite exists in this shape.
func _check_every_reason_in_the_vocabulary_writes() -> void:
	for reason: String in Autosave.REASONS:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_world.save_path))
		var wrote: bool = _world.autosave.request(reason)
		check(wrote, "reason `%s` performs a write" % reason)
		check(FileAccess.file_exists(_world.save_path), "reason `%s` leaves a real file" % reason)
		var data: Dictionary = SaveStore.read(_world.save_path)
		check(
			WorldSnapshot.can_apply(data),
			"reason `%s` writes a file this build can open" % reason
		)
	check(
		Autosave.REASONS.has("mist_reveal"),
		"`mist_reveal` is in the vocabulary though row 13 has not built its caller"
	)
	note_expected_pending(
		"mist_reveal has no call site in the build",
		"row 13 adds `autosave.request(\"mist_reveal\")`; that it fires at the right moment is row 13's to prove"
	)


func _check_the_vocabulary_is_exactly_the_gdd_four() -> void:
	# gdd.md -> Saves: "~1-2 min, plus the two events ... plus exiting to menu". Pinned so a
	# fifth reason is a deliberate design change rather than a quiet one.
	check_eq(Autosave.REASONS.size(), 4, "there are exactly four reasons")
	for expected: String in ["interval", "move_in", "mist_reveal", "exit_to_menu"]:
		check(Autosave.REASONS.has(expected), "`%s` is a reason" % expected)
	check(not _world.autosave.request("whenever"), "an unknown reason is refused, not written")


func _check_the_interval_fires_and_resets() -> void:
	# The attach-time write itself is asserted on the FIRST `_process()` frame — NOT in
	# `_initialize()` immediately after `add_child()`, where the class doc records it was proven
	# never to pass, because `_ready()` (and so `attach()`) is deferred past the point
	# `add_child()` returns when called from `_initialize()`. Either way it runs strictly before
	# this suite's own `request()` calls, which wait for `_frames >= 3` and would otherwise mask a
	# no-op with a write of their own — see the class doc for why re-checking
	# `wrote_at_least_once()` here would be vacuous by this point in the run.
	_events.clear()
	_world.autosave.tick(Autosave.INTERVAL_SECONDS - 1.0)
	check_eq(_events.size(), 0, "the interval has not fired one second early")
	_world.autosave.tick(2.0)
	check_eq(_events.size(), 1, "the interval fires once it elapses")
	check_eq(_events[0], "interval", "...with reason `interval`")

	# A reason-triggered write resets the interval, so a move-in is not chased by a redundant
	# interval write seconds later.
	_events.clear()
	_world.autosave.tick(Autosave.INTERVAL_SECONDS - 1.0)
	_world.autosave.request("move_in")
	check_eq(_events.size(), 1, "the move_in write happened")
	_world.autosave.tick(2.0)
	check_eq(_events.size(), 1, "the interval did NOT also fire — the write reset it")


func _check_a_world_with_no_path_declines_rather_than_inventing_one() -> void:
	var remembered: String = _world.save_path
	_world.save_path = ""
	check(
		not _world.autosave.request("interval"),
		"a world with no save file declines to write rather than inventing a filename"
	)
	_world.save_path = remembered


func _check_move_in_triggers_a_write() -> void:
	_events.clear()
	# Fire the real signal the real way — a restored site does not announce, so use the
	# simulation's own arrival path via a direct emit on the world's public signal.
	_world.resident_arrived.emit("rabbit", Vector3.ZERO)
	check_eq(_events.size(), 1, "a move-in writes a save")
	check_eq(_events[0], "move_in", "...with reason `move_in`")


func _check_autosave_costs_the_simulation_nothing() -> void:
	var before: int = _world.simulation.evaluations_run
	for i in range(20):
		_world.autosave.request("interval")
	check_eq(
		_world.simulation.evaluations_run, before,
		"20 autosaves move `evaluations_run` by ZERO — saving is not simulation work"
	)
