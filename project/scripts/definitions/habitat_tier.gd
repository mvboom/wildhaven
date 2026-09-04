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
	return problems
