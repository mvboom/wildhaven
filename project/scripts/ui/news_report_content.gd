class_name NewsReportContent
extends RefCounted
## Tier 1 row 12 — WHICH species a News Report names, and which line it speaks. Pure
## selection: nothing here mutates a species, a tile, or the roster. gdd.md -> Discovery:
## "Discovery reads the simulation; it never drives it" — every function below takes data in
## and returns a String or an AnimalDefinition out.
##
## THE WEIGHTING GDD ACTUALLY ASKS FOR DOES NOT EXIST YET. gdd.md -> Discovery: "Qualification
## produces a near-miss summary as a byproduct of checks it already runs ... which Discovery
## reads to weight which species gets hinted. ... An empty or stale summary degrades to plain
## terrain bias, so the hint layer ships independently." Row 6's own build note confirms the
## summary itself is unbuilt (tier1-status.md row 6: "the near-miss summary ... does not
## exist"). `pick_species()` below accepts one as an OPTIONAL, already-degraded input for the
## day it lands — pass a non-empty `species_id -> float` score map and it is used verbatim,
## never touched or renormalised here — but until then every call passes the default `{}`,
## which is what routes every pick through `_terrain_bias()`.
##
## `_terrain_bias()` IS A ONE-PASS SCAN, NOT AN INCREMENTAL COUNTER, AND THAT IS A JUDGMENT
## CALL FLAGGED UNDER PROPOSALS. `WorldGrid.forest_tile_count()`'s own header explains the
## house style this departs from: "maintained incrementally so the economy never scans the
## world." A News Report cycle is 90-150 s apart (D-37), never per-frame and never per edit,
## so one O(width x height) pass per cycle — at the ~128x128 performance ceiling, 16 384 tile
## reads roughly every two minutes — is a different order of cost entirely from the per-edit,
## per-neighbourhood work the incremental-counter style protects. Still worth a second look
## from whoever owns `WorldGrid` next, which is why it is named here rather than left quiet.

## Baseline weight every candidate keeps regardless of how much of its habitat exists yet —
## PROPOSED, human owns this. Zero baseline would make a species with no matching terrain at
## all unreachable by the hint layer, which reads as an assignment toward land the player
## already has rather than an invitation toward land they do not (gdd.md -> Discovery: "a hint
## is an invitation, not an assignment").
const BASELINE_WEIGHT: float = 1.0


## Tallies every habitat tag over the WHOLE revealed grid, one pass, into `{tag: String ->
## count: int}`. `AnimalDefinition.HABITAT_TAGS` order is not assumed; a tag nobody's roster
## needs is counted and simply never read back.
static func tag_tile_counts(grid: WorldGrid) -> Dictionary:
	var counts: Dictionary = {}
	if grid == null:
		return counts
	for x in range(grid.width):
		for z in range(grid.depth):
			for tag: String in grid.get_tile_tags(x, z):
				counts[tag] = int(counts.get(tag, 0)) + 1
	return counts


## Every roster species carrying at least one usable News Report line.
static func candidates_with_pools(roster: SpeciesRoster) -> Array[AnimalDefinition]:
	var out: Array[AnimalDefinition] = []
	if roster == null:
		return out
	for species: AnimalDefinition in roster.species():
		if not species.news_reports.is_empty():
			out.append(species)
	return out


## Picks one species to hint at. `near_miss_summary` empty (the only case that exists today)
## routes through terrain bias; a future non-empty summary is trusted as already-computed
## per-species weight and used directly, per the header note above.
static func pick_species(
	candidates: Array[AnimalDefinition],
	grid: WorldGrid,
	rng: RandomNumberGenerator,
	near_miss_summary: Dictionary = {}
) -> AnimalDefinition:
	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		return candidates[0]

	var tag_counts: Dictionary = {} if not near_miss_summary.is_empty() else tag_tile_counts(grid)
	var weights: Array[float] = []
	var total: float = 0.0
	for species: AnimalDefinition in candidates:
		var weight: float = BASELINE_WEIGHT
		if not near_miss_summary.is_empty():
			weight += maxf(0.0, float(near_miss_summary.get(species.id, 0.0)))
		else:
			for tag: String in species.habitat_needs:
				weight += float(tag_counts.get(tag, 0))
		weights.append(weight)
		total += weight

	if total <= 0.0:
		return candidates[rng.randi_range(0, candidates.size() - 1)]

	var roll: float = rng.randf() * total
	var cursor: float = 0.0
	for i in range(candidates.size()):
		cursor += weights[i]
		if roll <= cursor:
			return candidates[i]
	return candidates[candidates.size() - 1]


## One line from a species' pool, or "" if it has none (never errors on an empty pool — a
## species with no copy yet simply cannot be picked by `pick_species()` in the first place,
## via `candidates_with_pools()`, so this is a defensive fallback, not the expected path).
static func pick_line(species: AnimalDefinition, rng: RandomNumberGenerator) -> String:
	if species == null or species.news_reports.is_empty():
		return ""
	return species.news_reports[rng.randi_range(0, species.news_reports.size() - 1)]
