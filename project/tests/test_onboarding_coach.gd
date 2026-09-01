extends QATestCase
## THE FIRST-RUN COACH — two beats, and every way it gets out of the player's way.
##
## Driven by `advance(delta)` with hand-picked deltas, the same idiom `NewsReportScheduler`
## uses: a headless suite gets a deterministic answer on the same frame instead of waiting on
## real wall-clock seconds.
##
## TWO PHASES, because `bind_content()` needs a real `WorldRoot` (it calls through to
## `HabitatRecipe`, which reads the live roster/terrain/placeable catalogs) while the rest of
## the state machine needs nothing at all. `_initialize()` runs every pure-logic check
## immediately, then kicks off loading `Main.tscn`; `_process()` waits a few frames for it to
## settle (the same two-phase shape `test_habitat_recipe.gd` and `test_field_guide.gd` use)
## before running the `bind_content()` checks and calling `finish()`.
##
## Run:
##   bash scripts/run-tests.sh onboarding_coach

const WORLD_PATH: String = "res://scenes/Main.tscn"
const IDLE: float = OnboardingCoach.IDLE_BEFORE_HINT + 1.0

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("onboarding coach")
	_check_nothing_shows_before_the_nudge_beat()
	_check_hints_off_shows_nothing()
	_check_loaded_save_shows_nothing()
	_check_beat_one_waits_out_the_idle_gate()
	_check_activity_inside_the_idle_window_suppresses()
	_check_self_directed_painting_ends_the_whole_coach()
	_check_guide_route_advances_to_beat_two()
	_check_dismiss_retires_permanently()
	_check_arrival_closes_it()
	_check_idle_survives_a_second_nudge_due_call()

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

	_check_bind_content_at_beat_one_names_no_species()
	_check_bind_content_at_beat_two_names_the_derived_starter()
	_check_bind_content_falls_through_to_done_when_unsatisfiable()

	finish()
	return true


## Every case below starts past D-37's 3-second nudge beat — `notice_nudge_due()` is what
## releases the idle clock, so a coach that never receives it never shows anything.
func _fresh(new_world: bool = true, hints: bool = true) -> OnboardingCoach:
	var coach := OnboardingCoach.new()
	coach.configure(new_world, hints)
	coach.notice_nudge_due()
	return coach


func _check_nothing_shows_before_the_nudge_beat() -> void:
	var coach := OnboardingCoach.new()
	coach.configure(true, true)
	coach.advance(IDLE * 3.0)
	check(not coach.is_showing(), "the idle clock does not run before the 3s nudge beat")


func _check_hints_off_shows_nothing() -> void:
	var coach: OnboardingCoach = _fresh(true, false)
	coach.advance(IDLE)
	check_eq(coach.current_beat(), OnboardingCoach.Beat.DONE,
		"hints off retires the coach without ever showing a chip")


func _check_loaded_save_shows_nothing() -> void:
	var coach: OnboardingCoach = _fresh(false, true)
	coach.advance(IDLE)
	check_eq(coach.current_beat(), OnboardingCoach.Beat.DONE,
		"a loaded save never sees the coach")


func _check_beat_one_waits_out_the_idle_gate() -> void:
	var coach: OnboardingCoach = _fresh()
	coach.advance(OnboardingCoach.IDLE_BEFORE_HINT * 0.5)
	check(not coach.is_showing(), "no chip before the idle gate elapses")
	coach.advance(IDLE)
	check(coach.is_showing(), "the chip appears once the player has been idle")
	check_eq(coach.current_beat(), OnboardingCoach.Beat.OPEN_GUIDE, "beat 1 points at the guide")


func _check_activity_inside_the_idle_window_suppresses() -> void:
	var coach: OnboardingCoach = _fresh()
	for i in range(10):
		coach.advance(OnboardingCoach.IDLE_BEFORE_HINT * 0.5)
		coach.notice_activity()
	check(not coach.is_showing(), "a player who keeps acting is never interrupted")


func _check_self_directed_painting_ends_the_whole_coach() -> void:
	var coach: OnboardingCoach = _fresh()
	coach.advance(IDLE)
	coach.notice_painted()
	check_eq(coach.current_beat(), OnboardingCoach.Beat.DONE,
		"painting without asking for help ends the coach — beat 2 never fires")


func _check_guide_route_advances_to_beat_two() -> void:
	var coach: OnboardingCoach = _fresh()
	coach.advance(IDLE)
	coach.notice_guide_opened()
	check(not coach.is_showing(), "opening the guide satisfies beat 1")
	coach.notice_guide_closed()
	coach.advance(IDLE)
	check_eq(coach.current_beat(), OnboardingCoach.Beat.BUILD, "beat 2 follows the guide closing")
	coach.notice_painted()
	check_eq(coach.current_beat(), OnboardingCoach.Beat.DONE, "the first paint satisfies beat 2")


func _check_dismiss_retires_permanently() -> void:
	var coach: OnboardingCoach = _fresh()
	coach.advance(IDLE)
	coach.dismiss()
	coach.advance(IDLE)
	check_eq(coach.current_beat(), OnboardingCoach.Beat.DONE, "x retires the coach for good")
	check(not coach.is_showing(), "and nothing brings it back")


func _check_arrival_closes_it() -> void:
	var coach: OnboardingCoach = _fresh()
	coach.advance(IDLE)
	coach.notice_arrival()
	check_eq(coach.current_beat(), OnboardingCoach.Beat.DONE, "an arrival is the payoff and the end")


## THE GAP EVERY OTHER CHECK ABOVE MISSES: each one calls `notice_nudge_due()` exactly once,
## immediately after `configure()`, before any `advance()` — so `_idle` is always `0.0` at
## that moment and none of them can tell "releases the clock" apart from "resets the clock".
## A regression where `notice_nudge_due()` also zeroed `_idle` (the earlier draft's mistake —
## it called `notice_activity()` instead, which does exactly that) would be a silent no-op
## against all nine and pass unchanged.
##
## This one accumulates idle FIRST, calls `notice_nudge_due()` a SECOND time mid-accumulation,
## then advances the remaining fraction and checks the gate still trips — which only happens
## if the second call left `_idle` alone.
func _check_idle_survives_a_second_nudge_due_call() -> void:
	var coach := OnboardingCoach.new()
	coach.configure(true, true)
	coach.notice_nudge_due()
	coach.advance(OnboardingCoach.IDLE_BEFORE_HINT * 0.75)
	coach.notice_nudge_due()
	coach.advance(OnboardingCoach.IDLE_BEFORE_HINT * 0.25 + 0.1)
	check(coach.is_showing(),
		"idle time accumulated before a second notice_nudge_due() call survives that call")


## Beat 1 anchors to the `[?]` button, not a palette entry — `bind_content()` must not touch
## `HabitatRecipe` (or even look at `world`) while `_beat` is `OPEN_GUIDE`.
func _check_bind_content_at_beat_one_names_no_species() -> void:
	var coach := OnboardingCoach.new()
	coach.configure(true, true)
	coach.bind_content(_world)
	check_eq(coach.current_text(), OnboardingCoach.BEAT_ONE_TEXT,
		"beat 1's text is the [?]-anchored copy stub")
	check_eq(coach.current_target_id(), "",
		"beat 1 targets nothing — it anchors to the [?] button, not a palette option")


## Beat 2's whole design promise is that it NAMES NO SPECIES OR TERRAIN IN CODE — the words
## come entirely from `HabitatRecipe`, live, so a later roster retune changes what the coach
## says with no code change here. Asserting against `HabitatRecipe`'s own answer (rather than
## hardcoding "rabbit"/"grass") is what keeps this test honoring that same promise, and what
## keeps it passing the day the human retunes the roster.
func _check_bind_content_at_beat_two_names_the_derived_starter() -> void:
	var starter: AnimalDefinition = HabitatRecipe.easiest_species(_world)
	if not check(starter != null, "a starter species is derivable from the live roster"):
		return
	var recipe: Dictionary = HabitatRecipe.recipe_for(starter, _world)
	var entries: Array = recipe["entries"] as Array
	if not check(not entries.is_empty(), "the starter's recipe has at least one chip"):
		return
	var first: Dictionary = entries[0] as Dictionary

	var coach: OnboardingCoach = _fresh()
	coach.advance(IDLE)
	coach.notice_guide_opened()
	coach.notice_guide_closed()
	coach.bind_content(_world)

	check_eq(coach.current_target_id(), first["id"] as String,
		"beat 2 targets the same first palette button HabitatRecipe.recipe_for() derives")
	check(coach.current_text().contains(starter.display_name),
		"beat 2's text names the derived starter's display name")
	check(coach.current_text().contains(HabitatRecipe.describe(starter, _world)),
		"beat 2's text carries HabitatRecipe.describe()'s own sentence verbatim")
	check(coach.current_text().contains(first["display_name"] as String),
		"beat 2's text names the derived first palette button's display name")


## A roster where nothing is satisfiable makes `HabitatRecipe.easiest_species()` return
## `null` — `bind_content()` must retire the coach to `DONE` rather than leave it showing a
## chip with empty/broken text. Swaps a fixture roster onto the live `_world` the way
## `test_habitat_recipe.gd`'s avoids check does, and restores the real one afterward since
## nothing else in this suite runs after this check.
func _check_bind_content_falls_through_to_done_when_unsatisfiable() -> void:
	var ghost := AnimalDefinition.new()
	ghost.id = "ghost"
	ghost.display_name = "Ghost"
	ghost.habitat_needs = ["quiet"] as Array[String]

	var real_roster: SpeciesRoster = _world.roster
	_world.roster = SpeciesRoster.new([ghost])

	var coach: OnboardingCoach = _fresh()
	coach.advance(IDLE)
	coach.notice_guide_opened()
	coach.notice_guide_closed()
	coach.bind_content(_world)
	check_eq(coach.current_beat(), OnboardingCoach.Beat.DONE,
		"an unsatisfiable roster ends the coach rather than showing broken beat-2 text")

	_world.roster = real_roster
