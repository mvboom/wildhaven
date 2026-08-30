class_name NewsReportScheduler
extends RefCounted
## Tier 1 row 12 (Pointers) — the clock behind the first-time nudge and the ambient News
## Report cadence. gdd.md -> Player Interface & Controls, The First 60 Seconds beat 2; gdd.md
## -> Discovery: News Reports & the Field Guide.
##
## A PLAIN `RefCounted` DRIVEN BY `advance(delta)`, NOT A GODOT `Timer` NODE — the same idiom
## `ArrivalQueue` and `SettlementWindow` already use for exactly this reason: a headless suite
## calls `advance()` with a hand-picked `delta` and gets a deterministic answer on the same
## frame, instead of waiting on real wall-clock seconds inside a `SceneTree`. The presenter
## that owns one of these ticks it from its own `_process(delta)`.
##
## TWO CONSTANTS, BOTH DECIDED (2026-08-09 -> D-37), NEITHER GUESSED HERE:
##   * the first-time nudge fires ~3 s after a new world starts (gdd.md's own First 60
##     Seconds beat 2, "~0:03 — the first News Report fires", transcribed verbatim);
##   * after that, the ambient News Report cadence is 90-150 s, randomised, so reports never
##     fall into a noticeable lockstep.
## This row's `constants` cell in tier1-status.md records the reasoning; nothing here re-opens
## either number.
##
## THE HINTS TOGGLE IS A PILLAR INVARIANT (spec.md -> "Not depth axes"), enforced HERE rather
## than by hiding a control: `advance()` returns "" on every call while hints are off, so no
## caller can accidentally fire a nudge or a report by forgetting to check a flag first.
##
## THE NUDGE IS RETIRED PERMANENTLY THE MOMENT HINTS GO OFF, EVEN IF THEY COME BACK ON.
## gdd.md says so twice, verbatim: "The Gameplay Hints toggle disables it permanently" and
## beat 2's "the Hints toggle disables it forever." A first-time nudge that came back after
## being switched off would no longer be describing a first time, so `set_hints_enabled(false)`
## marks the nudge fired (without ever having shown it) if it had not fired yet. **The ambient
## cadence carries no such latch** — gdd.md only ever calls the nudge's suppression permanent;
## turning Hints back on mid-game resumes ordinary News Reports exactly where the paused clock
## left off.

const NUDGE_DELAY_SECONDS: float = 3.0
const CADENCE_MIN_SECONDS: float = 90.0
const CADENCE_MAX_SECONDS: float = 150.0

## What `advance()` returns on the frame each event fires. "" means nothing fired.
const EVENT_NUDGE: String = "nudge"
const EVENT_REPORT: String = "report"
const EVENT_NONE: String = ""

var hints_enabled: bool = true

var _nudge_fired: bool = false
var _nudge_remaining: float = NUDGE_DELAY_SECONDS
var _report_remaining: float = 0.0
var _rng := RandomNumberGenerator.new()


## `seed_value = 0` randomises, matching `ArrivalQueue`'s own convention — a headless suite
## wanting a reproducible cadence passes a non-zero seed.
func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value


## Advances the clock by `delta` seconds. Returns `EVENT_NUDGE`, `EVENT_REPORT`, or
## `EVENT_NONE` — at most one event per call, so a caller ticking once per frame can never miss
## one silently coalescing into the next.
func advance(delta: float) -> String:
	if not hints_enabled:
		return EVENT_NONE

	if not _nudge_fired:
		_nudge_remaining -= delta
		if _nudge_remaining > 0.0:
			return EVENT_NONE
		_nudge_fired = true
		_report_remaining = _next_cadence()
		return EVENT_NUDGE

	_report_remaining -= delta
	if _report_remaining > 0.0:
		return EVENT_NONE
	_report_remaining = _next_cadence()
	return EVENT_REPORT


## See the header note above: switching Hints off before the nudge has fired retires it for
## good. Switching them back on never un-retires it, because `_nudge_fired` only ever becomes
## `true` — there is no path back to `false`.
func set_hints_enabled(enabled: bool) -> void:
	if not enabled:
		# Reuses `retire_nudge()` rather than repeating its body — which is also what makes
		# sure `_report_remaining` gets armed with a fresh 90-150 s roll here too, not just
		# `_nudge_fired` flipped. Skipping that would leave the ambient cadence reading its
		# unset 0.0 default the moment Hints come back on, firing a report on the very next
		# `advance()` instead of waiting out a real window.
		retire_nudge()
	hints_enabled = enabled


func _next_cadence() -> float:
	return _rng.randf_range(CADENCE_MIN_SECONDS, CADENCE_MAX_SECONDS)


## Marks the one-time nudge as already spent, WITHOUT touching `hints_enabled` or the ambient
## cadence — for a session that starts past "brand-new save" (a loaded save, or a direct scene
## run outside the menu) rather than because Hints were switched off. gdd.md's nudge is scoped
## to "every brand-new save"; a loaded save simply never qualifies; nothing to explain, nothing
## to suppress.
func retire_nudge() -> void:
	if _nudge_fired:
		return
	_nudge_fired = true
	_report_remaining = _next_cadence()


# --- Introspection for headless assertions -------------------------------------------------

func nudge_fired() -> bool:
	return _nudge_fired


func nudge_remaining() -> float:
	return _nudge_remaining


func report_remaining() -> float:
	return _report_remaining
