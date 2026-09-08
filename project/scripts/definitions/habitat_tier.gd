@tool
class_name HabitatTier
extends Resource
## One way a species can qualify for a home site, with its own population cap.
##
## `capacity(h, S)` is the MAX over a species' tiers of this tier's own Liebig `min` —
## so "a barn and some grass gets you a pair; a stable, a wide tract and water gets you a
## herd" is one species with two tiers. See the spec § 4.
##
## ORDER IS PRESENTATIONAL ONLY. The formula takes a max, so authoring order must never be
## load-bearing.

## Internal identifier ("pair", "herd"). NOT player-facing — tier names were deliberately
## kept out of the Field Guide (spec § 13).
@export var id: String = ""

## The positive requirements. A tier with none is invalid: it would qualify on bare land.
@export var needs: Array[HabitatNeed] = []

## The exclusions. Optional.
@export var limits: Array[HabitatLimit] = []

## This tier's hard population cap — the outer `min` of the capacity formula.
@export_range(1, 64, 1) var max_individuals: int = 6

## How many individuals arrive together when this tier is the qualifying one.
@export_range(1, 16, 1) var arrival_group_size: int = 1


## The widest radius any need or limit in this tier counts over — the bound the tile walk
## uses, so one pass fills every bucket.
func max_radius(fallback_radius: int) -> int:
	var widest: int = fallback_radius
	for need: HabitatNeed in needs:
		widest = maxi(widest, need.effective_radius(fallback_radius))
	for limit: HabitatLimit in limits:
		widest = maxi(widest, limit.effective_radius(fallback_radius))
	return widest


## Non-fatal schema check, including every child need and limit. Empty array means clean.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if needs.is_empty():
		problems.append(
			"tier \"%s\" has no needs — a limits-only tier would qualify on bare land." % id
		)
	for i in range(needs.size()):
		if needs[i] == null:
			problems.append("tier \"%s\" `needs[%d]` is null." % [id, i])
			continue
		for problem: String in needs[i].validate():
			problems.append("tier \"%s\" needs[%d]: %s" % [id, i, problem])
	for i in range(limits.size()):
		if limits[i] == null:
			problems.append("tier \"%s\" `limits[%d]` is null." % [id, i])
			continue
		for problem: String in limits[i].validate():
			problems.append("tier \"%s\" limits[%d]: %s" % [id, i, problem])
	if max_individuals < 1:
		problems.append("tier \"%s\" `max_individuals` %d is below 1." % [id, max_individuals])
	if arrival_group_size < 1:
		problems.append("tier \"%s\" `arrival_group_size` %d is below 1." % [id, arrival_group_size])
	problems.append_array(_duplicate_bucket_problems())
	return problems


## THE DOUBLE-COUNT GUARD — final review finding #3 (2026-09-04). `CapacityEvaluator.
## tag_counts()` buckets every child into a `count_key(tag, resolved_radius)` slot, and
## `needs` and `limits` share that ONE bucket list — a limit's exclusion count and a need's
## scaling count walk the same tile the same way, so nothing stops a `(tag, radius)` pair
## from naming both a need and a limit, or two needs. Two children that resolve to the SAME
## bucket key both get credited for every matching tile independently during the walk,
## silently doubling (or worse) whatever count each of them reads back.
##
## Checked on the RAW `radius` field, not `effective_radius()`: `HabitatTier` carries no
## species to resolve `HabitatNeed.RADIUS_FOLLOWS_SCOUT` / `HabitatLimit.RADIUS_FOLLOWS_SCOUT`
## against. Two children BOTH left at that sentinel still collide for certain — they resolve
## against the same species' `scout_radius`/`capacity_radius` regardless of which species
## this tier ends up on, so the sentinel is one more ordinary radius value for this check's
## purposes, not a special case. Two children with different EXPLICIT radii that merely
## happen to equal a particular species' resolved fallback are a real but rarer case this
## function has no way to see from here — no live instance in the roster today.
func _duplicate_bucket_problems() -> Array[String]:
	var problems: Array[String] = []
	var seen: Dictionary = {}  # "tag@radius" -> true
	for need: HabitatNeed in needs:
		if need == null or need.tag.strip_edges().is_empty():
			continue
		var key: String = "%s@%d" % [need.tag, need.radius]
		if seen.has(key):
			problems.append(
				("tier \"%s\" has more than one need/limit reading \"%s\" at radius %d — "
				+ "they collapse into one bucket and double-count every matching tile.")
				% [id, need.tag, need.radius]
			)
		seen[key] = true
	for limit: HabitatLimit in limits:
		if limit == null or limit.tag.strip_edges().is_empty():
			continue
		var key: String = "%s@%d" % [limit.tag, limit.radius]
		if seen.has(key):
			problems.append(
				("tier \"%s\" has more than one need/limit reading \"%s\" at radius %d — "
				+ "they collapse into one bucket and double-count every matching tile.")
				% [id, limit.tag, limit.radius]
			)
		seen[key] = true
	return problems
