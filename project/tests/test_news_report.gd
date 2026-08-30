extends QATestCase
## TIER 1 ROW 12 (POINTERS) — the first-time nudge, the ambient News Report cadence, the
## schema it reads, and the Gameplay Hints toggle that is a pillar invariant, not depth.
##
## SECTIONS:
##   1. THE SCHEMA GAP CLOSES. `AnimalDefinition.news_reports` exists, and the floor roster's
##      three `.tres` files carry real, checklist-passed copy — never the flagged-suspect fox
##      line, never a placeholder, and `validate()` stays clean either way (the field is
##      optional by design).
##   2. THE CLOCK. `NewsReportScheduler` fires the nudge at ~3 s (D-37), never before; the
##      ambient cadence only starts counting once the nudge has fired, and lands in 90-150 s
##      (D-37); the Hints toggle suppresses BOTH kinds of event on the very next `advance()`,
##      not just a control on screen; switching Hints off before the nudge fires retires it
##      forever, even across a later re-enable.
##   3. THE PICK. `NewsReportContent` tallies tags over a real grid in one pass, and its
##      terrain-bias weighting is measurably more likely to name a species whose habitat
##      already exists more of, without ever letting a species with none of it go completely
##      unreachable (gdd.md -> Discovery: "a hint is an invitation, not an assignment").
##   4. THE SETTING PERSISTS. `GameplaySettings` defaults ON, round-trips through its own
##      `user://` file independently of any world save, and `SettingsOverlay` reads/writes it
##      rather than keeping a second copy of the value.
##   5. THE TOAST. Non-modal, no Read-Aloud button (spec.md defers that), auto-dismisses, and
##      dismisses early on a tap.
##   6. THE WIRING, on the real `Main.tscn`. `GameUI` carries all three new nodes, the HUD's
##      Settings button is no longer permanently disabled, and `WorldRoot.is_new_world` is
##      true only for a `GameSession.request_new()` world — never the default "none" path
##      every other suite's `Main.tscn` instance already relies on being unaffected by.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_news_report.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"
const FOX_PATH: String = "res://data/animals/fox.tres"
const RABBIT_PATH: String = "res://data/animals/rabbit.tres"
const HUMAN_PATH: String = "res://data/animals/human.tres"

## A fixed seed so the cadence rolls this suite pins are reproducible.
const SEED: int = 20260809

var _world: WorldRoot = null
var _ui: GameUI = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("news report (row 12)")
	GameSession.clear()
	GameplaySettings.reset_for_test()

	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		finish()
		return
	_world = node as WorldRoot
	root.add_child(_world)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	var ui_node: Node = _world.get_node_or_null("GameUI")
	if not check(ui_node is GameUI, "Main.tscn instances the GameUI shell"):
		finish()
		return true
	_ui = ui_node as GameUI
	_ui.bind_world()

	_check_schema_field_exists()
	_check_floor_roster_pools()
	_check_scheduler_nudge_timing()
	_check_scheduler_cadence_timing()
	_check_scheduler_hints_toggle_suppresses_live()
	_check_scheduler_hints_off_retires_nudge_forever()
	_check_content_tag_tile_counts()
	_check_content_candidates_and_lines()
	_check_content_terrain_bias()
	_check_gameplay_settings_persistence()
	_check_settings_overlay_reads_and_writes_the_one_source_of_truth()
	_check_toast_behaviour()
	_check_wiring_on_the_real_scene()
	_check_is_new_world()

	GameplaySettings.reset_for_test()
	finish()
	return true


# --- 1. The schema gap closes ---------------------------------------------------------------

func _check_schema_field_exists() -> void:
	var fresh := AnimalDefinition.new()
	check(fresh.news_reports is Array, "`news_reports` exists and is an Array")
	check(fresh.news_reports.is_empty(), "...empty by default — no species is required to have copy yet")

	fresh.id = "critter"
	fresh.display_name = "Critter"
	fresh.habitat_needs = ["cover"] as Array[String]
	fresh.model_scenes = [load("res://assets/placeholder/grass/Grass.tscn") as PackedScene]
	fresh.fact_text_pool = ["A critter fact."]
	check(fresh.validate().is_empty(),
		"validate() is clean with news_reports left at its empty default — the field is optional")


func _check_floor_roster_pools() -> void:
	var fox: AnimalDefinition = load(FOX_PATH) as AnimalDefinition
	var rabbit: AnimalDefinition = load(RABBIT_PATH) as AnimalDefinition
	var human: AnimalDefinition = load(HUMAN_PATH) as AnimalDefinition
	check(fox != null and rabbit != null and human != null, "all three floor .tres load")

	for entry: Array in [[fox, "fox"], [rabbit, "rabbit"], [human, "human"]]:
		var species: AnimalDefinition = entry[0]
		var label: String = entry[1]
		check(not species.news_reports.is_empty(), "%s.tres carries News Report copy" % label)
		for line: String in species.news_reports:
			check(not line.strip_edges().is_empty(), "%s: no blank line in the pool" % label)
			check(not line.begins_with(AnimalDefinition.PLACEHOLDER_MARKER),
				"%s: no PLACEHOLDER-prefixed line shipped" % label)
		check(species.validate(["fox", "rabbit", "human"]).is_empty(),
			"%s.tres still validates clean with news_reports populated" % label)

	# THE SUSPECT LINE STAYS OUT. docs/content/fox-news-report-pool.md flags "The fox kits
	# were out tumbling in the leaves all morning" as factually suspect (fox activity is
	# nocturnal/crepuscular in every source) — shipping it would repeat the exact daytime-
	# activity error `fact_text` was rewritten to correct.
	var suspect := "tumbling in the leaves all morning"
	var found_suspect: bool = false
	for line: String in fox.news_reports:
		if line.contains(suspect):
			found_suspect = true
	check(not found_suspect, "the flagged-suspect fox ambient line was NOT shipped")

	# NON-VACUITY: the three pools really do differ, so "non-empty" above is not one shared list.
	check(fox.news_reports != rabbit.news_reports and rabbit.news_reports != human.news_reports,
		"the three species carry DIFFERENT copy, not one pool aliased three times")


# --- 2. The clock ------------------------------------------------------------------------------

func _check_scheduler_nudge_timing() -> void:
	var scheduler := NewsReportScheduler.new(SEED)
	check_eq(scheduler.hints_enabled, true, "hints default ON")
	check(not scheduler.nudge_fired(), "the nudge has not fired at t=0")

	check_eq(scheduler.advance(1.0), NewsReportScheduler.EVENT_NONE, "t=1s: nothing yet")
	check_eq(scheduler.advance(1.0), NewsReportScheduler.EVENT_NONE, "t=2s: still nothing")
	check(not scheduler.nudge_fired(), "...and the nudge has still not fired one tick before D-37's ~3s")

	check_eq(scheduler.advance(1.0), NewsReportScheduler.EVENT_NUDGE,
		"t=3s: the nudge fires exactly once it reaches D-37's ~3s delay")
	check(scheduler.nudge_fired(), "...and is marked fired")
	check_eq(scheduler.advance(0.01), NewsReportScheduler.EVENT_NONE,
		"...and does not fire a second time on the very next tick")


func _check_scheduler_cadence_timing() -> void:
	# Drive several independently-seeded schedulers straight through the nudge and confirm
	# every ambient report lands inside D-37's 90-150s band — never before, never stuck.
	var min_seen: float = INF
	var max_seen: float = -INF
	for trial in range(20):
		var scheduler := NewsReportScheduler.new(SEED + trial)
		scheduler.advance(NewsReportScheduler.NUDGE_DELAY_SECONDS) # spend the nudge
		var elapsed: float = 0.0
		var fired: bool = false
		# 200s ceiling: comfortably past the 150s worst case with margin, so a scheduler that
		# never fires (a real defect) fails instead of looping forever.
		while elapsed < 200.0 and not fired:
			var event: String = scheduler.advance(1.0)
			elapsed += 1.0
			if event == NewsReportScheduler.EVENT_REPORT:
				fired = true
		check(fired, "trial %d: an ambient report eventually fires after the nudge" % trial)
		min_seen = minf(min_seen, elapsed)
		max_seen = maxf(max_seen, elapsed)

	check(min_seen >= NewsReportScheduler.CADENCE_MIN_SECONDS - 1.0,
		"no report fired before D-37's 90s floor (measured min %.1fs)" % min_seen)
	check(max_seen <= NewsReportScheduler.CADENCE_MAX_SECONDS + 1.0,
		"no report ran past D-37's 150s ceiling (measured max %.1fs)" % max_seen)
	# NON-VACUITY: the 20 trials did not all land on the same tick.
	check(max_seen - min_seen > 5.0,
		"...and the trials actually spread across the band (not one lucky constant seed)")


func _check_scheduler_hints_toggle_suppresses_live() -> void:
	var scheduler := NewsReportScheduler.new(SEED)
	scheduler.set_hints_enabled(false)
	check_eq(scheduler.advance(1000.0), NewsReportScheduler.EVENT_NONE,
		"1000 simulated seconds with Hints OFF fires NOTHING — the layer is suppressed live, "
		+ "not just hidden behind a disabled control")
	# `nudge_fired()` reads true here too — turning Hints off before the nudge ever showed
	# RETIRES it (see the next check) — but the assertion above is the one that matters for
	# THIS check: no event of either kind ever reached a caller while Hints were off.


func _check_scheduler_hints_off_retires_nudge_forever() -> void:
	# Off BEFORE the nudge ever fires.
	var scheduler := NewsReportScheduler.new(SEED)
	scheduler.advance(1.0)
	scheduler.set_hints_enabled(false)
	check(scheduler.nudge_fired(),
		"switching Hints off before the nudge fires retires it immediately — "
		+ "gdd.md: \"the Hints toggle disables it forever\"")

	# Back on. gdd.md only calls the NUDGE's suppression permanent — the ambient cadence must
	# resume normally, and the nudge must never appear regardless.
	scheduler.set_hints_enabled(true)
	var saw_nudge: bool = false
	var saw_report: bool = false
	var elapsed: float = 0.0
	while elapsed < 200.0 and not saw_report:
		match scheduler.advance(1.0):
			NewsReportScheduler.EVENT_NUDGE:
				saw_nudge = true
			NewsReportScheduler.EVENT_REPORT:
				saw_report = true
		elapsed += 1.0
	check(not saw_nudge, "...re-enabling Hints never brings the nudge back")
	check(saw_report, "...but the ambient cadence resumes and a report still eventually fires")

	# Off AFTER the nudge fires — a normal pause, not a second retirement of anything.
	var mid_scheduler := NewsReportScheduler.new(SEED)
	mid_scheduler.advance(NewsReportScheduler.NUDGE_DELAY_SECONDS)
	check(mid_scheduler.nudge_fired(), "fixture: the nudge fired normally first")
	var remaining_before: float = mid_scheduler.report_remaining()
	mid_scheduler.set_hints_enabled(false)
	mid_scheduler.advance(50.0)
	mid_scheduler.set_hints_enabled(true)
	check(is_equal_approx(mid_scheduler.report_remaining(), remaining_before),
		"pausing mid-cadence and resuming leaves the SAME remaining wait — a pause, not a reset")


# --- 3. The pick -------------------------------------------------------------------------------

func _check_content_tag_tile_counts() -> void:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 6, 1)
	for x in range(6):
		grid.set_terrain(x, 0, "rock" if x < 4 else "grass")

	var counts: Dictionary = NewsReportContent.tag_tile_counts(grid)
	check_eq(int(counts.get("rocks", 0)), 4, "one pass over a 6x1 grid tallies 4 `rocks` tiles")
	check_eq(int(counts.get("open_grass", 0)), 2, "...and 2 `open_grass` tiles")
	check(NewsReportContent.tag_tile_counts(null).is_empty(),
		"a null grid degrades to an empty tally, not an error")
	# `WorldGrid extends Node`, not RefCounted — `test_settlement_window.gd`'s own `_teardown()`
	# frees its fixture grid for the same reason; an un-freed one is a leak, not a style choice.
	grid.free()


func _check_content_candidates_and_lines() -> void:
	var candidates: Array[AnimalDefinition] = NewsReportContent.candidates_with_pools(_world.roster)
	check_eq(candidates.size(), 3, "all three floor species carry a pool and are candidates")

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var fox: AnimalDefinition = _world.roster.by_id("fox")
	for i in range(10):
		var line: String = NewsReportContent.pick_line(fox, rng)
		check(fox.news_reports.has(line), "pick_line() only ever returns a line FROM the pool")

	var empty_species := AnimalDefinition.new()
	check_eq(NewsReportContent.pick_line(empty_species, rng), "",
		"a species with no pool degrades to \"\", not an error")
	check(NewsReportContent.pick_species([], null, rng) == null,
		"no candidates degrades to null, not an error")


func _check_content_terrain_bias() -> void:
	# A tiny two-species roster where one need is plentiful and the other is entirely absent —
	# so the bias is unambiguous without needing the shipped roster's real numbers.
	var rich := AnimalDefinition.new()
	rich.id = "rich"
	rich.habitat_needs = ["rocks"] as Array[String]
	rich.news_reports = ["rich line"] as Array[String]

	var scarce := AnimalDefinition.new()
	scarce.id = "scarce"
	scarce.habitat_needs = ["sand"] as Array[String]
	scarce.news_reports = ["scarce line"] as Array[String]

	# A DELIBERATELY MODEST disparity (6 `rocks` tiles vs. 0 `sand` tiles, weights 7:1 once the
	# baseline is added), not an extreme one: an all-rock grid drives scarce's pick probability
	# under 1/400, which is more likely than not to land on exactly zero in any fixed number of
	# trials — a flaky assertion, not a broken feature. 7:1 keeps both "measurably favors" and
	# "never unreachable" comfortably observable in one fixed-seed run.
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 5, 2)
	var painted: int = 0
	for x in range(5):
		for z in range(2):
			if painted < 6:
				grid.set_terrain(x, z, "rock")
				painted += 1
			# the remaining 4 tiles stay wild_grass, which emits nothing (D-26) — never `sand`.

	var candidates: Array[AnimalDefinition] = [rich, scarce]
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var rich_picks: int = 0
	var scarce_picks: int = 0
	const TRIALS: int = 300
	for i in range(TRIALS):
		var picked: AnimalDefinition = NewsReportContent.pick_species(candidates, grid, rng)
		if picked == rich:
			rich_picks += 1
		elif picked == scarce:
			scarce_picks += 1
	check_eq(rich_picks + scarce_picks, TRIALS, "every trial picked one of the two candidates")
	check(rich_picks > scarce_picks * 3,
		"terrain bias measurably favors the species whose habitat actually exists (rich=%d, scarce=%d)"
			% [rich_picks, scarce_picks])
	check(scarce_picks > 0,
		"...but never makes the other UNREACHABLE — a hint stays an invitation, never an "
		+ "assignment toward only the land the player already has (rich=%d, scarce=%d)"
			% [rich_picks, scarce_picks])
	grid.free()


# --- 4. The setting persists ---------------------------------------------------------------

func _check_gameplay_settings_persistence() -> void:
	GameplaySettings.reset_for_test()
	check_eq(GameplaySettings.hints_enabled(), true, "Hints default ON")

	GameplaySettings.set_hints_enabled(false)
	check_eq(GameplaySettings.hints_enabled(), false, "set_hints_enabled(false) reads back false")

	# Reload from disk by resetting the in-memory cache without touching the file — a fresh
	# app launch reading the same file back.
	GameplaySettings._loaded = false
	check_eq(GameplaySettings.hints_enabled(), false,
		"...and the OFF value survives a reload from `user://settings.cfg`, independent of any "
		+ "world save")

	GameplaySettings.reset_for_test()
	check_eq(GameplaySettings.hints_enabled(), true, "reset_for_test() leaves the ON default for later suites")


## Task 5 retired `SettingsOverlay.open()`/`close()`/`is_open()`. As of the 2026-08-25 move off
## `MenuWindow` onto `scenes/menu/SettingsScreen.tscn`, there is no long-lived in-game instance
## left to check against at all — this proves the guarantee ("a fresh checkbox never shows
## stale state") against a freshly-instantiated `SettingsOverlay.tscn` directly, read at the
## point it actually gets painted: `_ready()`.
func _check_settings_overlay_reads_and_writes_the_one_source_of_truth() -> void:
	GameplaySettings.set_hints_enabled(false)
	var packed: PackedScene = load("res://scenes/ui/SettingsOverlay.tscn") as PackedScene
	var overlay: SettingsOverlay = packed.instantiate() as SettingsOverlay
	root.add_child(overlay)
	check_eq(overlay.hints_checked(), false,
		"a freshly-instantiated overlay paints the checkbox from GameplaySettings' live value")

	overlay._on_hints_toggled(true)
	check_eq(GameplaySettings.hints_enabled(), true,
		"toggling the checkbox writes straight through to GameplaySettings — no second copy of the value")

	overlay.queue_free()
	GameplaySettings.reset_for_test()


# --- 5. The toast ------------------------------------------------------------------------------

func _check_toast_behaviour() -> void:
	var toast: NewsReportToast = _ui.news_report_toast
	check(toast.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"NOT A MODAL: the toast's root ignores the mouse everywhere except its own banner")
	check(not toast.is_showing(), "the toast starts hidden")
	check(not toast.show_text(""), "an empty string produces no toast")
	check(not toast.is_showing(), "...and nothing is showing")

	check(toast.show_text("A fox has moved into the forest!"), "a real line shows")
	check(toast.is_showing(), "...and the toast is up")
	check_eq(toast.current_text(), "A fox has moved into the forest!", "...with the exact text handed to it")

	# TAPPED AWAY. spec.md: "auto-dismisses or is tapped away."
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	toast._on_banner_input(tap)
	check(not toast.is_showing(), "a tap on the banner dismisses it early")

	# AUTO-DISMISS, exercised without waiting real seconds. `_process(delta)` is a plain method
	# despite the underscore — calling it directly with a hand-picked delta is the same idiom
	# `NewsReportScheduler.advance(delta)` uses, applied to a Control instead of a RefCounted.
	toast.show_text("Rumor from the hedgerow…")
	check(toast.is_showing(), "a second line shows")
	toast._process(NewsReportToast.DISPLAY_SECONDS - 0.5)
	check(toast.is_showing(), "...still up a half-second before its own display duration")
	toast._process(1.0)
	check(not toast.is_showing(), "...and gone once DISPLAY_SECONDS has elapsed")

	# NO READ-ALOUD BUTTON. spec.md defers "wider [Read-Aloud] coverage (News Reports, Field
	# Guide)" — structural check, the same shape `test_fact_card.gd` uses for its OWN absence
	# assertions.
	var found_read_aloud_button: bool = false
	for child: Node in toast.find_children("*", "Button", true, false):
		found_read_aloud_button = true
	check(not found_read_aloud_button, "the toast has NO Button at all — no Read-Aloud, no dismiss button; tap-the-banner is the whole gesture")

	# QUEUEING. Two lines shown back to back: the second waits.
	toast.show_text("first")
	toast.show_text("second")
	check_eq(toast.current_text(), "first", "the first of two queued lines shows first")
	check_eq(toast.queued_count(), 1, "...and the second is queued, not dropped or shown early")
	toast.dismiss()
	check_eq(toast.current_text(), "second", "...and shows once the first is dismissed")
	toast.dismiss()
	check_eq(toast.queued_count(), 0, "the queue is empty once both have shown")


# --- 6. The wiring, on the real scene --------------------------------------------------------

func _check_wiring_on_the_real_scene() -> void:
	check(_ui.news_report_toast is NewsReportToast, "GameUI carries a NewsReportToast")
	check(_ui.menu_window is MenuWindow, "GameUI carries a MenuWindow")
	check(_ui.news_report_presenter is NewsReportPresenter, "GameUI carries a NewsReportPresenter")

	# Settings moved off MenuWindow entirely (2026-08-25) onto its own Title-screen-reachable
	# page — there is no in-game SettingsOverlay instance left for the live presenter to listen
	# to. What still has to hold is the other half of the contract: `bind()` reads whatever
	# `GameplaySettings.hints_enabled()` says AT BIND TIME, so a value changed between sessions
	# (from the Title screen) is picked up the moment the next session's world binds — not
	# `_ui.bind_world()` on the SAME world again, which is a documented no-op past the toast
	# reference (`news_report_presenter.gd`'s own `bind()` header), so this exercises a genuinely
	# fresh presenter against a genuinely fresh world instead, same fixture shape as
	# `_check_is_new_world()` below.
	GameplaySettings.set_hints_enabled(false)
	var fresh_presenter := NewsReportPresenter.new()
	root.add_child(fresh_presenter)
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var fresh_world: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(fresh_world)
	fresh_presenter.bind(fresh_world, _ui.news_report_toast)
	check_eq(fresh_presenter._scheduler.hints_enabled, false,
		"a freshly-bound presenter reads GameplaySettings.hints_enabled() at bind time, so an "
		+ "off-session change (made from the Title screen's Settings page) is picked up by the "
		+ "next session")
	fresh_presenter.free()
	fresh_world.free()
	GameplaySettings.reset_for_test()


func _check_is_new_world() -> void:
	check_eq(_world.is_new_world, false,
		"a Main.tscn opened directly (this suite's own fixture, the \"none\" path every other "
		+ "suite already relies on) is NOT a new world")

	GameSession.request_new(WorldPreset.default_preset(), "News Report Test", "", SEED)
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var second: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(second)
	check_eq(second.is_new_world, true,
		"a world opened through GameSession.request_new() IS a new world")
	# `free()`, not `queue_free()` — this whole suite runs inside one `_process()` call (see
	# `test_save_round_trip.gd`'s identical note), so a queued free would never actually run
	# before `finish()` quits the tree, leaking the second world's ~1,296 tiles.
	second.free()
	GameSession.clear()
