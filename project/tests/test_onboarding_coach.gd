extends QATestCase
## THE FIRST-RUN COACH — two beats, and every way it gets out of the player's way.
##
## Driven by `advance(delta)` with hand-picked deltas, the same idiom `NewsReportScheduler`
## uses: a headless suite gets a deterministic answer on the same frame instead of waiting on
## real wall-clock seconds.
##
## Run:
##   bash scripts/run-tests.sh onboarding_coach

const IDLE: float = OnboardingCoach.IDLE_BEFORE_HINT + 1.0


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
	finish()


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
