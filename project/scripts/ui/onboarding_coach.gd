class_name OnboardingCoach
extends RefCounted
## THE FIRST-RUN COACH — two beats, then gone forever.
##
## A plain `RefCounted` driven by `advance(delta)`, the idiom `NewsReportScheduler` and
## `ArrivalQueue` already use: a headless suite passes a hand-picked delta and gets a
## deterministic answer on the same frame. The presenter that owns one ticks it from
## `_process(delta)`.
##
## IT NAMES NO SPECIES AND NO TERRAIN. Beat 2's wording comes from
## `HabitatRecipe.starter_species()` + `describe_tier_needs()` + `recipe_for_tier()`
## — the TIER-AWARE path (final review finding C1, 2026-09-04; `HabitatRecipe`'s own
## "THE COACH'S OWN PATH" doc comment explains why this reads tiers and not the flat
## `easiest_species()` / `describe()` / `recipe_for()` above it) — so a roster or terrain
## retune still changes what the coach says without touching this file. `starter_species()`
## itself is pinned (human ruling, 2026-09-04): the tutorial's first species — Rabbit — is
## named explicitly in `HabitatRecipe.PINNED_STARTER_SPECIES_ID`, not derived from a cost
## score, only falling back to the derived pick if that id ever goes missing from the
## roster. See `HabitatRecipe`'s doc comment on that constant for why.
##
## FOUR WAYS OUT, and that is the whole non-intrusiveness contract:
##   * the guide route completes both beats;
##   * SELF-DIRECTED PAINTING ENDS IT AT BEAT 1 — someone who starts building without asking
##     for help has proved they do not need it, and following them with a second chip is
##     exactly the intrusion this design exists to avoid;
##   * `dismiss()` retires it;
##   * an arrival closes it (the payoff beat).
## There is no path back from DONE — every field below only ever moves one way.

enum Beat { OPEN_GUIDE, BUILD, DONE }

## PROPOSED — human owns this. Seconds of no tap, no mode change and no palette change before
## a chip appears. Long enough that a player mid-gesture is never interrupted.
const IDLE_BEFORE_HINT: float = 6.0

## [COPY] — content-writer's. Beat 1, anchored to the `[?]` button.
const BEAT_ONE_TEXT: String = "[COPY] Tap here to see what animals like."

## [COPY] — content-writer's. Beat 2. `%s` is the starter's name, then its description
## sentence, then the display name of the first thing to place.
const BEAT_TWO_TEMPLATE: String = "[COPY] %s are easiest. %s Tap %s, then tap the ground."

var _beat: Beat = Beat.OPEN_GUIDE
var _showing: bool = false
var _idle: float = 0.0
var _armed: bool = true
var _started: bool = false
var _text: String = ""
var _target_id: String = ""


## `new_world` is `WorldRoot.is_new_world`; `hints` is `GameplaySettings.hints_enabled()`.
## Either being false retires the coach immediately — the same two gates the first-time nudge
## already honours, including its permanent-retirement latch.
func configure(new_world: bool, hints: bool) -> void:
	if not new_world or not hints:
		_finish()


## `NewsReportScheduler.EVENT_NUDGE` — D-37's 3-second beat, unchanged. The idle clock does
## not run before this, so the nudge beat is the EARLIEST a chip can appear and the idle gate
## is counted from there. Two independent clocks would otherwise race: the scheduler's 3s and
## this file's own gate.
func notice_nudge_due() -> void:
	_started = true


## Ticks the idle clock. Returns the current beat so a caller can render on the frame it
## changes without re-reading state.
func advance(delta: float) -> int:
	if _beat == Beat.DONE or _showing or not _armed or not _started:
		return _beat
	_idle += delta
	if _idle >= IDLE_BEFORE_HINT:
		_showing = true
	return _beat


## Any tap, mode change or palette change. Resets the idle clock, so someone actively working
## never accumulates enough quiet for a chip to appear.
func notice_activity() -> void:
	_idle = 0.0


func notice_guide_opened() -> void:
	if _beat == Beat.OPEN_GUIDE:
		_showing = false
		_armed = false


func notice_guide_closed() -> void:
	if _beat == Beat.OPEN_GUIDE:
		_beat = Beat.BUILD
		_armed = true
		_idle = 0.0


## The first paint. Satisfies beat 2 — and ends the WHOLE coach if it arrives during beat 1.
func notice_painted() -> void:
	_finish()


func notice_arrival() -> void:
	_finish()


func dismiss() -> void:
	_finish()


func is_showing() -> bool:
	return _showing


func current_beat() -> int:
	return _beat


func current_text() -> String:
	return _text


## The palette option id the chip should point at — "" for beat 1, which anchors to the `[?]`
## button instead.
func current_target_id() -> String:
	return _target_id


## Composes beat 2's line and target from live data. Called by the presenter when the beat
## becomes BUILD; kept separate from `advance()` so the state machine stays testable without
## a `WorldRoot`.
func bind_content(world: WorldRoot) -> void:
	if _beat == Beat.OPEN_GUIDE:
		_text = BEAT_ONE_TEXT
		_target_id = ""
		return
	if _beat != Beat.BUILD:
		return
	var starter: AnimalDefinition = HabitatRecipe.starter_species(world)
	if starter == null:
		_finish()
		return
	var tier: HabitatTier = HabitatRecipe.starter_tier(starter)
	var recipe: Dictionary = HabitatRecipe.recipe_for_tier(tier, world)
	var entries: Array = recipe["entries"] as Array
	if entries.is_empty():
		_finish()
		return
	var first: Dictionary = entries[0] as Dictionary
	_target_id = first["id"] as String
	_text = BEAT_TWO_TEMPLATE % [
		starter.display_name,
		HabitatRecipe.describe_tier_needs(tier, world),
		first["display_name"],
	]


func _finish() -> void:
	_beat = Beat.DONE
	_showing = false
	_armed = false
	_text = ""
	_target_id = ""
