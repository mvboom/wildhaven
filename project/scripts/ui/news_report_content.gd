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

## THE ZERO-FOREST REPORT — the one report in the feed that names no species at all.
## spec.md:100 already scopes the pool as "a per-animal (or GENERAL) text pool"; this is the
## first general entry.
##
## WHY IT EARNS A SLOT IN A FEED THAT IS OTHERWISE ALL INVITATIONS: a world with no Forest
## tiles earns no Wood, ever — `WoodLedger.tick()` returns immediately on a zero count — and
## Forest is free to paint, so the fix costs the player nothing but knowing. That is the only
## state in v1 where the loop is genuinely stalled and the player has no way to read why off
## the HUD, which shows a Wood counter that simply never moves. It stays an invitation in
## register (gdd.md -> Discovery: "a hint is an invitation, not an assignment"): no warning
## colour, no error state, same toast as every other report.
##
## `NO_FOREST_ID` IS NOT A SPECIES AND MUST NEVER MATCH ONE. It is written into the
## presenter's `_last_species_id` after this line shows, which is what makes the feed
## ALTERNATE — see `NewsReportPresenter.compose_next_report()`. Double-underscored so no
## roster `.tres` id can collide with it; the ordinary no-repeat filter simply matches nothing
## on the cycle that follows, leaving the whole roster in the pool.
const NO_FOREST_ID: String = "__no_forest__"

## DECIDED 2026-09-08 by the human (-> D-63, amended). The stockpile below which a zero-Forest
## world is worth mentioning. ABOVE it the report stays quiet even with no tree in sight.
##
## WHY THE REPORT IS GATED ON WOOD AND NOT ON TIME: a brand-new world starts at
## `WoodLedger.STARTING_WOOD` (100), which is several builds — the player is not stuck, they
## are solvent, and the feed's job in that first stretch is to point them at a villager or an
## animal to build FOR, not at a supply problem they do not have yet. Gating on the balance
## makes that fall out with no new state and no "is this a new game" flag to keep in sync: a
## fresh world holds the gate shut by itself until the player has actually spent, and a LOADED
## save sitting at 5 Wood with no trees hears about it on the very next cycle, which is the
## case that genuinely needs saying.
##
## 30 IS TWO HOUSES' WORTH, and deliberately not the House price itself: the report should
## arrive while there is still one more build in the bank, as a heads-up, rather than after
## the player is already stalled and wondering why the counter stopped.
const LOW_WOOD_FLOOR: int = 30

## [COPY] — content-writer's, PROPOSED. Kids 6-10, plain vocabulary, upbeat, one sentence
## (spec.md -> the fact-card checklist, which News Report copy reuses). Says the state and the
## fix in the player's own verbs, and never scolds: the woodpile is not empty, it is waiting.
const NO_FOREST_REPORT: String = (
	"Nobody has spotted a tree in a while — plant a patch of forest and the woodpile will "
	+ "start growing again."
)

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
##
## Reads through `world`'s own three accessors throughout (`species_hosted_ids()`,
## `population_of()`), never `world.registry` directly, so every read here sits at the same
## abstraction level as the early gate in `pick_species()` (`species_hosted_count()`) — and
## gets the same registry-null safety `WorldRoot.population_of()` already provides for free.
static func species_weight(species: AnimalDefinition, world: WorldRoot) -> float:
	if species == null or world == null:
		return WEIGHT_NEVER_HOSTED
	if not world.species_hosted_ids().has(species.id):
		return WEIGHT_NEVER_HOSTED
	if world.population_of(species.id) < PLENTY_THRESHOLD:
		return WEIGHT_FEW_HOSTED
	return WEIGHT_PLENTY_HOSTED


## THE TAGS THE REPORT WILL ACTUALLY NAME — the starter tier's needs, read through the same
## `HabitatRecipe.starter_tier()` seam `hint_line()` composes its sentence from.
##
## NEVER `species.habitat_needs`. `HabitatRecipe`'s own header records that the flat fields are
## legacy and that no live display path reads them any more; they disagree with the tier data
## for 8 of the 15 shipped species, and for Husky the two sets share nothing at all (flat
## `house`/`open_grass` against the starter tier's `snow`/`people`). Ranking on one generation
## of the data while composing the sentence from the other is what silently broke gdd.md ->
## Discovery's promise that a species whose land the player already has floats up: the bias was
## weighing terrain the report would never go on to mention. The disagreement was inert only
## while `candidates_with_pools()` limited selection to three species; opening selection to the
## whole roster made this the one ordering signal beneath the hosted-tier multiplier.
static func starter_tags(species: AnimalDefinition) -> Array[String]:
	var tags: Array[String] = []
	if species == null:
		return tags
	var tier: HabitatTier = HabitatRecipe.starter_tier(species)
	if tier == null:
		return tags
	for need: HabitatNeed in tier.needs:
		if need != null and not need.tag.is_empty():
			tags.append(need.tag)
	return tags


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
##
## NO LONGER GATES SELECTION (Task 7). `hint_line()` composes its report live from
## `HabitatRecipe` rather than drawing from `news_reports`, so `NewsReportPresenter` now passes
## the WHOLE roster to `pick_species()` — which is what closes the gap that limited hinting to
## the three species (Fox, Human, Rabbit) that happened to carry authored flavour pools. Left
## here as a query in case something still wants "which species have flavour copy" specifically.
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

	# THE EARLY GATE — one branch. Nothing hosted at all means the player has not yet seen the
	# loop work once, so the hint names the Villager first. That is the OPERATOR'S RULING
	# (D-61 #4, "Villager first"), which reopened the pinned tutorial starter for this path
	# only — it is NOT a cost claim, and this comment used to make one it could not support:
	# the Villager is a 15-wood House plus a 2-wood cultivated tile (17 wood), against
	# Rabbit's 4 free wild-grass tiles plus 4 cultivated (8 wood). The ruling stands on its
	# own; the arithmetic never backed it.
	#
	# THE GATE YIELDS TO THE NO-REPEAT RULE BELOW, and that exception is the whole reason it
	# is written as a condition rather than an unconditional branch. Nothing-hosted is the
	# state a new player sits in LONGEST and the one with the least variety available: the
	# shortest interval in `HintPacer`, no authored `discovery_openings` anywhere in the
	# roster, and needs that render deterministically. An unconditional gate there replays one
	# identical sentence every cycle — the exact inverse of spec.md §10.1's requirement that
	# "an idle stretch reads as the world talking about different animals, not as one nag
	# repeated." Falling through hands the pick to the ordinary ranking, which the filter just
	# below has already stripped the Villager out of, so the feed alternates instead of looping
	# — and the gate's purpose survives intact, because every other cycle still lands on it.
	if (
		world != null
		and world.species_hosted_count() == 0
		and last_species_id != VILLAGER_SPECIES_ID
	):
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
			# `starter_tags()`, never the flat `habitat_needs` — see that function's own header
			# for why ranking on the other generation of the data made this bias a claim about
			# terrain the composed report would never go on to name.
			for tag: String in starter_tags(species):
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


## One line from a species' pool, or "" if it has none (never errors on an empty pool). DEAD
## IN PRODUCTION as of Task 7: `NewsReportPresenter._fire_report()` composes through
## `hint_line()` now, not this — `candidates_with_pools()` no longer gates what
## `pick_species()` can return (see that function's own header), so the old premise here
## ("a species with no copy yet simply cannot be picked in the first place") no longer holds.
## Kept for its own test coverage (`test_news_report.gd`), which is now its only caller.
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
