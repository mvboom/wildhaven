@tool
class_name HabitatLimit
extends Resource
## An EXCLUSION inside a `HabitatTier`: "at most `max_count` of `tag` within radius."
##
## Limits GATE, they never scale. A violated limit makes its whole tier score 0; it never
## reduces capacity partially. This is what makes wild animals want genuinely wild land
## rather than merely a different quantity of the same land — see the spec § 8.
##
## The counting is identical to a `HabitatNeed`'s: same tile walk, same cache, inverted
## comparison. An exclusion costs nothing extra.

const RADIUS_FOLLOWS_SCOUT: int = HabitatNeed.RADIUS_FOLLOWS_SCOUT

## The habitat tag being limited. `built` is the intended common case: every placeable
## emits it, so one limit excludes every building — including buildings added later.
@export var tag: String = ""

## Tiles from the home site over which this tag is counted.
@export_range(0, HabitatNeed.RADIUS_MAX, 1) var radius: int = RADIUS_FOLLOWS_SCOUT

## The ceiling. `0` means "none at all"; `2` means "a distant cottage is fine, a village
## is not" — the kinder default for a six-year-old who built in the wrong spot.
@export_range(0, 64, 1) var max_count: int = 0


## The radius this limit actually counts over, sentinel resolved.
func effective_radius(fallback_radius: int) -> int:
	if radius == RADIUS_FOLLOWS_SCOUT:
		return fallback_radius
	return radius


## Non-fatal schema check. Empty array means clean.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if tag.strip_edges().is_empty():
		problems.append("`tag` is empty.")
	if radius != RADIUS_FOLLOWS_SCOUT and (radius < HabitatNeed.RADIUS_MIN or radius > HabitatNeed.RADIUS_MAX):
		problems.append(
			"`radius` %d for limit \"%s\" is outside the %d-%d band."
			% [radius, tag, HabitatNeed.RADIUS_MIN, HabitatNeed.RADIUS_MAX]
		)
	if max_count < 0:
		problems.append("`max_count` %d is negative." % max_count)
	return problems
