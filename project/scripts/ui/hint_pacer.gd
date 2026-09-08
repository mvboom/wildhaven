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
## predicate and are never summed. A player who built inside the window waits half as long;
## one who did not waits twice as long.
const BUILT_RECENTLY_MULTIPLIER: float = 0.5
const IDLE_MULTIPLIER: float = 2.0

## PROPOSED — human owns this. How long a placement counts as "just built". Long enough to
## span one deliberate build gesture. Deliberately NOT `SettlementWindow.GRACE_WINDOW_SECONDS`
## (12 s): that number gates irreversible consequences and refunds, a different concern that
## happens to be a duration too.
const BUILT_RECENTLY_SECONDS: float = 30.0

## Seconds since the last placement. CLAMPED at `BUILT_RECENTLY_SECONDS` — this is the
## Pillar 1 mitigation, not an optimisation. gdd.md says "hints never expire or repeat with
## urgency"; letting this grow unbounded would be the first step toward a rate that climbs
## the longer a child hesitates. It saturates instead: an hour of idleness paces exactly like
## a moment of it.
var _since_activity: float = BUILT_RECENTLY_SECONDS


## Any placement — the same call sites that already feed `OnboardingCoach.notice_painted()`.
func notice_activity() -> void:
	_since_activity = 0.0


## Ticks the idle clock. Saturating, per `_since_activity`'s own note.
func advance(delta: float) -> void:
	_since_activity = minf(_since_activity + delta, BUILT_RECENTLY_SECONDS)


func built_recently() -> bool:
	return _since_activity < BUILT_RECENTLY_SECONDS


## Seconds until the next hint should fire. A negative or nonsense count reads as the
## learning band rather than erroring — a hint layer that throws is worse than one that is
## briefly too generous.
func next_interval(hosted_count: int) -> float:
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
