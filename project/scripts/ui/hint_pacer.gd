class_name HintPacer
extends RefCounted
## HOW OFTEN a News Report build hint fires — never whether one may.
##
## Split out of `NewsReportScheduler` deliberately. That file owns two things this design
## must not disturb: D-37's decided `NUDGE_DELAY_SECONDS`, and the Hints-toggle invariant
## (`advance()` returns "" for every call while hints are off, enforced there specifically so
## no caller can fire an event by forgetting a flag). The nudge is a first-run, one-shot
## concern with a permanent-retirement latch; only the ambient cadence is adaptive. Keeping
## them apart means this file can be tested against hand-fed deltas without dragging that
## latch into every fixture, and means a scheduler with NO pacer still behaves exactly as it
## does today.
##
## Reads no world state of its own: the caller passes `hosted_count`, which
## `HomeSiteRegistry.species_hosted_count()` already provides and `world_snapshot.gd` already
## round-trips. NO NEW SAVE STATE.

## PROPOSED — human owns this. Seconds between hints, by how many species are hosted.
## The learning band sits BELOW D-37's 90 s floor on purpose: a player who has attracted
## nothing is the case this whole design exists for. The upper bands sit inside and beyond
## D-37's 90-150 s, which becomes the no-pacer fallback rather than the ambient rule.
const BAND_LEARNING: float = 60.0    # 0 hosted
const BAND_EARLY: float = 120.0      # 1-2
const BAND_SETTLED: float = 240.0    # 3-5
const BAND_RARE: float = 480.0       # 6+

## PROPOSED — human owns this. The band boundaries above.
const EARLY_MAX_HOSTED: int = 2
const SETTLED_MAX_HOSTED: int = 5

## PROPOSED — human owns this. Exactly one of these always applies; they are two sides of one
## predicate and are never summed. Named for the STATE each applies to, not for their value —
## do not infer direction from the name alone; read the comment on each constant.
##
## BUILT_RECENTLY_MULTIPLIER lengthens the interval: an engaged player — one who placed
## something inside the window — is left alone, hearing from News Report less often.
const BUILT_RECENTLY_MULTIPLIER: float = 2.0
## IDLE_MULTIPLIER shortens the interval: a player who has NOT placed anything inside the
## window is the one the whole feature exists to help, so they are offered a hint sooner.
const IDLE_MULTIPLIER: float = 0.5

## PROPOSED — human owns this. How long a placement counts as "just built". Long enough to
## span one deliberate build gesture. Deliberately NOT `SettlementWindow.GRACE_WINDOW_SECONDS`
## (12 s): that number gates irreversible consequences and refunds, a different concern that
## happens to be a duration too.
const BUILT_RECENTLY_SECONDS: float = 30.0

## PROPOSED — human owns this. Seconds until a brand-new world's FIRST hint, used exactly once
## in place of the ordinary bands above. Operator ruling, 2026-09-08: "For a new game, the
## first suggested villager build should come even faster than the first 30-60s" — a direction,
## not a number, so 12.0 is proposed here awaiting the operator's own figure. Today the first
## ambient report is armed at `BAND_LEARNING` (30 s, idle) once the ~3 s nudge fires, landing
## the first hint ~33 s in; 12.0 would land it ~15 s in.
const FIRST_HINT_SECONDS: float = 12.0

## One-shot latch for `FIRST_HINT_SECONDS`. Default OFF: a pacer nobody arms behaves exactly as
## it always has — only `arm_first_hint()` can ever set this true, and only `next_interval()`
## can ever clear it again, once, on the very next call. See that method's own note for why the
## bands and multipliers above are never touched by this at all.
var _first_hint_armed: bool = false

## Arms the one-shot: the VERY NEXT `next_interval()` call returns `FIRST_HINT_SECONDS` instead
## of the ordinary band, then the latch clears and every call after behaves exactly as it does
## today, forever. Call this ONLY for a brand-new world (`WorldRoot.is_new_world`) — see
## `NewsReportPresenter.bind()`'s own note on where in that method this has to happen, and why
## a loaded save must never call it.
func arm_first_hint() -> void:
	_first_hint_armed = true


## Seconds since the last placement. Clamped at `BUILT_RECENTLY_SECONDS` as hygiene, so an
## internal counter does not grow without bound across a long session — that is all this
## clamp is. It is NOT where the Pillar 1 "cannot compound" guarantee lives: once
## `_since_activity` reaches `BUILT_RECENTLY_SECONDS`, `built_recently()` already reads false,
## so the clamp is unobservable through the only accessor that consults this field. See
## `next_interval()` for where the real guarantee is enforced.
var _since_activity: float = BUILT_RECENTLY_SECONDS


## Any placement — the same call sites that already feed `OnboardingCoach.notice_painted()`.
func notice_activity() -> void:
	_since_activity = 0.0


## Ticks the idle clock. Saturating per `_since_activity`'s own note — bounds an internal
## counter, nothing more; see `next_interval()` for the Pillar 1 guarantee itself.
func advance(delta: float) -> void:
	_since_activity = minf(_since_activity + delta, BUILT_RECENTLY_SECONDS)


func built_recently() -> bool:
	return _since_activity < BUILT_RECENTLY_SECONDS


## Seconds until the next hint should fire. A negative or nonsense count reads as the
## learning band rather than erroring — a hint layer that throws is worse than one that is
## briefly too generous.
##
## PILLAR 1 GUARANTEE lives HERE, not in `advance()`'s clamp: `multiplier` is always set by
## this single if/else to exactly one of `BUILT_RECENTLY_MULTIPLIER` or `IDLE_MULTIPLIER`,
## never accumulated across calls and never summed with the other. That exclusivity — not
## the saturation of `_since_activity` — is what keeps the boost from stacking toward an
## arbitrarily fast rate. spec §10.1: "the idle boost is capped, not compounding."
##
## THE ONE-SHOT IS CHECKED FIRST AND RETURNS EARLY, before the bands or multiplier below are
## even read — so an armed first hint touches neither, and every call after this one (the
## latch having cleared) computes the band/multiplier exactly as it always has.
func next_interval(hosted_count: int) -> float:
	if _first_hint_armed:
		_first_hint_armed = false
		return FIRST_HINT_SECONDS
	var band: float = BAND_RARE
	if hosted_count <= 0:
		band = BAND_LEARNING
	elif hosted_count <= EARLY_MAX_HOSTED:
		band = BAND_EARLY
	elif hosted_count <= SETTLED_MAX_HOSTED:
		band = BAND_SETTLED
	var multiplier: float = IDLE_MULTIPLIER
	if built_recently():
		multiplier = BUILT_RECENTLY_MULTIPLIER
	return band * multiplier
