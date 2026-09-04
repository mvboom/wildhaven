@tool
class_name HabitatNeed
extends Resource
## One positive habitat requirement inside a `HabitatTier`.
##
## A need carries its OWN radius and its OWN divisor, which is what lets one recipe say
## "a stable right here, and a wide tract of grass" — see
## docs/superpowers/specs/2026-09-04-habitat-tiers-design.md § 3.

## "Follow the species' capacity radius" — the relation, not a copy of the number.
## Same convention as `AnimalDefinition.CAPACITY_RADIUS_FOLLOWS_SCOUT`, for the same
## reason: a copied number silently stops being equal the first time the species is
## retuned. Resolve through `effective_radius()`; never read `radius` raw.
const RADIUS_FOLLOWS_SCOUT: int = 0

## "Must be present; contributes no population cap."
##
## This exists because a 1-tile Stable with an ordinary divisor of 1 would cap a herd at
## one horse — exactly backwards. The stable is a PRECONDITION, not the thing that scales
## the herd.
const GATE_ONLY: int = 0

## The per-need radius band (human ruling, 2026-09-04, spec OQ-B), replacing the old
## 8-12 band that `AnimalDefinition.validate()` applied to every radius alike. Cost scales
## as `max_radius^2 * roster * tiers`, so RADIUS_MAX is the real performance budget.
const RADIUS_MIN: int = 2
const RADIUS_MAX: int = 16

## The habitat tag required, drawn from `AnimalDefinition.HABITAT_TAGS`.
@export var tag: String = ""

## Tiles from the home site over which this tag is counted.
## `RADIUS_FOLLOWS_SCOUT` (0) means "follow the species".
@export_range(0, RADIUS_MAX, 1) var radius: int = RADIUS_FOLLOWS_SCOUT

## Qualifying tiles needed to support one individual. `GATE_ONLY` (0) means
## "present or not, never scaling".
@export_range(0, 64, 1) var tiles_per_individual: int = GATE_ONLY


## The radius this need actually counts over, sentinel resolved.
func effective_radius(fallback_radius: int) -> int:
	if radius == RADIUS_FOLLOWS_SCOUT:
		return fallback_radius
	return radius


## Is this a precondition rather than a scaling need?
func is_gate_only() -> bool:
	return tiles_per_individual == GATE_ONLY


## Non-fatal schema check. Empty array means clean.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if tag.strip_edges().is_empty():
		problems.append("`tag` is empty.")
	if radius != RADIUS_FOLLOWS_SCOUT and (radius < RADIUS_MIN or radius > RADIUS_MAX):
		problems.append(
			"`radius` %d for tag \"%s\" is outside the %d-%d band; use %d to follow the species."
			% [radius, tag, RADIUS_MIN, RADIUS_MAX, RADIUS_FOLLOWS_SCOUT]
		)
	if tiles_per_individual < 0:
		problems.append("`tiles_per_individual` %d is negative." % tiles_per_individual)
	return problems
