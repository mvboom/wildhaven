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

## The species the early gate names while nothing at all is hosted. `human.tres`'s own id;
## its `display_name` is "Villager".
const VILLAGER_SPECIES_ID: String = "human"

## PROPOSED — human owns this. The population at which a species stops being worth hinting
## at: the player has visibly succeeded and does not need telling again.
const PLENTY_THRESHOLD: int = 3

## PROPOSED — human owns this. The three ranking tiers. The lowest is deliberately nonzero,
## for `BASELINE_WEIGHT`'s own reason: a species that can never be named again reads as a
## closed door, and gdd.md's Discovery layer is an invitation, not an assignment.
const WEIGHT_NEVER_HOSTED: float = 4.0
const WEIGHT_FEW_HOSTED: float = 1.0
const WEIGHT_PLENTY_HOSTED: float = 0.15


## A species' ranking multiplier: never hosted > hosted a little > hosted plenty.
## Reads only accessors that already exist and already survive a save round trip
## (`species_hosted_ids()`, `population_of()`), so this design adds NO new save state.
static func species_weight(species: AnimalDefinition, world: WorldRoot) -> float:
	if species == null or world == null or world.registry == null:
		return WEIGHT_NEVER_HOSTED
	if not world.species_hosted_ids().has(species.id):
		return WEIGHT_NEVER_HOSTED
	if world.registry.population_of(species.id) < PLENTY_THRESHOLD:
		return WEIGHT_FEW_HOSTED
	return WEIGHT_PLENTY_HOSTED


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
##
## `world` is OPTIONAL and defaults to null. A null `world` reproduces today's pre-ranking
## behaviour exactly (`species_weight()` returns `WEIGHT_NEVER_HOSTED` for every candidate, a
## flat multiplier that changes nothing relative to itself, and the early Villager gate never
## fires) — that is what keeps every pre-existing call site, and the suites written against
## them, a real check rather than one quietly rewritten by this change.
static func pick_species(
	candidates: Array[AnimalDefinition],
	grid: WorldGrid,
	rng: RandomNumberGenerator,
	world: WorldRoot = null,
	near_miss_summary: Dictionary = {},
	last_species_id: String = ""
) -> AnimalDefinition:
	if candidates.is_empty():
		return null

	# THE EARLY GATE — one branch. Nothing hosted at all means the player has not yet seen
	# the loop work once, so the hint names the cheapest thing in the game and nothing else.
	if world != null and world.species_hosted_count() == 0:
		for species: AnimalDefinition in candidates:
			if species.id == VILLAGER_SPECIES_ID:
				return species

	# Never the same species twice running (the Pillar 1 mitigation for the idle
	# multiplier). Dropped only when it would empty the field.
	var pool: Array[AnimalDefinition] = []
	for species: AnimalDefinition in candidates:
		if species.id != last_species_id:
			pool.append(species)
	if pool.is_empty():
		pool = candidates

	if pool.size() == 1:
		return pool[0]

	var tag_counts: Dictionary = {} if not near_miss_summary.is_empty() else tag_tile_counts(grid)
	var weights: Array[float] = []
	var total: float = 0.0
	for species: AnimalDefinition in pool:
		var weight: float = BASELINE_WEIGHT
		if not near_miss_summary.is_empty():
			weight += maxf(0.0, float(near_miss_summary.get(species.id, 0.0)))
		else:
			for tag: String in species.habitat_needs:
				weight += float(tag_counts.get(tag, 0))
		weight *= species_weight(species, world)
		weights.append(weight)
		total += weight

	if total <= 0.0:
		return pool[rng.randi_range(0, pool.size() - 1)]

	var roll: float = rng.randf() * total
	var cursor: float = 0.0
	for i in range(pool.size()):
		cursor += weights[i]
		if roll <= cursor:
			return pool[i]
	return pool[pool.size() - 1]


## One line from a species' pool, or "" if it has none (never errors on an empty pool — a
## species with no copy yet simply cannot be picked by `pick_species()` in the first place,
## via `candidates_with_pools()`, so this is a defensive fallback, not the expected path).
static func pick_line(species: AnimalDefinition, rng: RandomNumberGenerator) -> String:
	if species == null or species.news_reports.is_empty():
		return ""
	return species.news_reports[rng.randi_range(0, species.news_reports.size() - 1)]


## [COPY] — content-writer's. The opening for a species with no authored `discovery_openings`
## entry. `%s` is the species, articled. Deliberately the same shape as the authored
## openings so the composed sentence reads identically either way.
const GENERIC_OPENING: String = "Word has it %s is looking for a home"

## [COPY] — content-writer's. Joins the two halves. `%s` is the opening (no trailing
## punctuation), then the body — the needs clause, with `LIMIT_CLAUSE` already folded on if
## the starter tier carries one.
const HINT_TEMPLATE: String = "%s — it'd want %s."

## [COPY] — content-writer's. Fix round 1 finding #1: a limit is not a thing an animal can
## WANT, so it is never a member of the needs list `HINT_TEMPLATE`'s "it'd want" governs —
## "it'd want 4 tiles of forest ... and far from any buildings" doesn't parse. Appended as a
## trailing comma clause onto the needs sentence instead, the same shape a spoken aside takes
## ("...want three things, well away from the road."). `%s` is the limit phrase(s), already
## joined by `HabitatRecipe.join_and()` if there is more than one — no leading comma, this
## constant supplies it.
const LIMIT_CLAUSE: String = ", %s"


## THE COMPOSER — an authored opening plus needs derived live from `HabitatRecipe`.
##
## The derived half is generated per render rather than authored, so retuning a divisor
## updates every report in the game with no copy edit, and rewording an opening needs no code
## change. That split is the whole point of the design: the numbers have one source, shared
## with the Field Guide card.
##
## Returns "" only for a null species or one whose starter tier has no NEEDS at all — never
## for a species that merely lacks authored copy, which is the common case and the reason
## `GENERIC_OPENING` exists. A tier's LIMITS do not affect this guard even when needs are
## empty: a limit on its own ("far from any buildings") is not something a player can go and
## build, so a report with no need to name has nothing to invite the player toward.
static func hint_line(
	species: AnimalDefinition, world: WorldRoot, rng: RandomNumberGenerator
) -> String:
	if species == null:
		return ""
	var needs: Array[String] = HabitatRecipe.starter_need_phrases(species, world)
	if needs.is_empty():
		return ""
	var limits: Array[String] = HabitatRecipe.starter_limit_phrases(species)

	var body: String = HabitatRecipe.join_and(needs)
	if not limits.is_empty():
		body += LIMIT_CLAUSE % HabitatRecipe.join_and(limits)

	var opening: String = ""
	if not species.discovery_openings.is_empty():
		opening = species.discovery_openings[
			rng.randi_range(0, species.discovery_openings.size() - 1)
		]
	else:
		opening = GENERIC_OPENING % HabitatRecipe.with_article(species.display_name.to_lower())

	return HINT_TEMPLATE % [opening, body]
