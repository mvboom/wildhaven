class_name NewsReportPresenter
extends Node
## Tier 1 row 12 — wires `NewsReportScheduler` and `NewsReportContent` to a live
## `NewsReportToast`. Owns no visible node of its own; `GameUI` instances one alongside the
## toast, the same shape it already uses for every other single-purpose behaviour file
## (`TapRouter`, `TapCue`, …).

var _scheduler: NewsReportScheduler = null
var _toast: NewsReportToast = null
var _world: WorldRoot = null
var _content_rng := RandomNumberGenerator.new()
var _coach: OnboardingCoach = null

## Species a News Report has named this session, newest last. SESSION-ONLY — nothing here is
## saved or restored (see Proposals): a reload starts this empty again, which is honest given
## nothing persists it yet, rather than pretending a save-crossing memory that does not exist.
## Exposed so a future Field Guide "hinted at" column (gdd.md -> Objectives & Progression;
## `field_guide.gd`'s own header names this exact gap) has something to read without this file
## changing shape.
var _hinted_species_ids: Dictionary = {}


func _ready() -> void:
	_content_rng.randomize()
	set_process(false)


## Wires this presenter to a live world and the toast it renders through. Safe to call every
## frame the way `GameUI.bind_world()` already does for everything else — a repeat call with
## the same world is a no-op past updating the toast reference.
func bind(world: WorldRoot, toast: NewsReportToast) -> void:
	_toast = toast
	if world == null or world == _world:
		return
	_world = world
	_scheduler = NewsReportScheduler.new()
	_scheduler.set_hints_enabled(GameplaySettings.hints_enabled())
	if not world.is_new_world:
		# Only a brand-new save gets the first-time nudge (gdd.md -> Player Interface &
		# Controls: "every brand-new save shows one dismissable popup"). A loaded save, or a
		# scene opened directly (tests, F6 in the editor), starts straight into the ambient
		# cadence.
		_scheduler.retire_nudge()
	set_process(true)


## The Hints toggle's write path from `SettingsOverlay`. `GameplaySettings` already holds the
## persisted value; this hands the live scheduler the same one so a mid-session flip takes
## effect on the very next `advance()` rather than the next `bind()`.
func set_hints_enabled(enabled: bool) -> void:
	if _scheduler != null:
		_scheduler.set_hints_enabled(enabled)


func hinted_species_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in _hinted_species_ids.keys():
		out.append(id)
	return out


## `GameUI` hands the live coach over so the 3-second nudge beat (D-37, unchanged) starts the
## coach rather than firing a toast. ONE HINT AT A TIME: the coach's beat 1 replaces the old
## placeholder nudge toast, it does not accompany it.
func set_coach(coach: OnboardingCoach) -> void:
	_coach = coach


func _process(delta: float) -> void:
	if _scheduler == null or _toast == null:
		return
	match _scheduler.advance(delta):
		NewsReportScheduler.EVENT_NUDGE:
			if _coach != null:
				_coach.notice_nudge_due()
		NewsReportScheduler.EVENT_REPORT:
			_fire_report()


func _fire_report() -> void:
	if _world == null or _world.roster == null:
		return
	var candidates: Array[AnimalDefinition] = NewsReportContent.candidates_with_pools(_world.roster)
	var species: AnimalDefinition = NewsReportContent.pick_species(
		candidates, _world.grid, _content_rng
	)
	if species == null:
		return
	var line: String = NewsReportContent.pick_line(species, _content_rng)
	if _toast.show_text(line):
		_hinted_species_ids[species.id] = true
