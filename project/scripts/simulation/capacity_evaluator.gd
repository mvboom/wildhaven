class_name CapacityEvaluator
extends RefCounted
## The tiered capacity formula (habitat-tiers, 2026-09-04):
##
##   capacity(h, S) = max over tiers T of tier_capacity(h, S, T)
##
##   tier_capacity(h, S, T): T's limits GATE first (a violated limit zeroes the whole
##   tier, never scales it); T's GATE_ONLY needs GATE next (absent -> 0, present ->
##   contributes nothing to the min); then Liebig's min over T's remaining SCALING needs,
##   each against its OWN divisor and its OWN radius, capped by T.max_individuals.
##
## **There is no lower clamp: capacity can be 0, and 0 means unsuitable.**
##
## `count_t` is a plain count of tiles within a need's or limit's own radius whose OWN
## terrain (or building) emits its tag (spec.md -> Shared Patterns, the v1 tag model ->
## D-25). Tags do not spread, carry no emission radius beyond what the need/limit states,
## and have no distance weighting.
##
## ONE TIER, ONE WALK: `tag_counts()` walks the grid once per (site, tier) pair, out to
## that tier's `max_radius()`, and buckets each tile into every `(tag, radius)` pair the
## tier reads. This keeps the cost shape at `radius^2 * roster * tiers`, independent of
## world size — re-walking per need would be a Critical defect even though it computes the
## same answer.
##
## `S.max_individuals` moved to `HabitatTier.max_individuals` (per tier, not per species) —
## see `HabitatTier`. This file holds no tuning constant of its own.


## The counts-Dictionary key. Counts are per (tag, radius) pair, not per tag, because two
## needs in one tier may read the same tag over different distances — Horse's pair tier
## counts `open_grass` at 8 while its herd tier counts it at 14.
static func count_key(tag: String, radius: int) -> String:
	return "%s@%d" % [tag, radius]


## `count_t` for every (tag, radius) pair this TIER reads, over the tiles this candidate
## site may count.
##
## ONE WALK, NOT ONE PER NEED. The walk runs to `tier.max_radius()` and buckets each tile
## into every pair whose squared radius contains it. Radii per tier are few, so the inner
## bucket loop is cheaper than re-walking, and the cost shape stays `radius^2 * roster *
## tiers` — independent of world size, which is the property that matters.
##
## `tier` defaults to `null`, resolving to `species.legacy_tier()` — DEVIATION FROM THE TASK
## BRIEF'S REFERENCE SNIPPET, which shows `tier` as a required positional. A required `tier`
## would break `test_capacity_formula.gd`'s own direct 4-arg `tag_counts(grid, registry,
## origin, species)` calls (its `_check_capacity_radius_is_consumed()` and
## `_check_sentinel_follows_scout_radius()`), which that 409-line pinned suite is not to be
## edited. `legacy_tier()`'s cache is safe to read here (human ruling, 2026-09-04): its
## synthesised needs are left at `HabitatNeed.RADIUS_FOLLOWS_SCOUT` rather than a baked
## concrete radius, so retuning `scout_radius` between two calls does not go stale — see
## `legacy_tier()`'s own header. When `tier` resolves via the legacy fallback, each bucket
## ALSO seeds a bare-tag alias key (no `@radius` suffix) alongside its `count_key()` entry,
## so that suite's `.get("cover", ...)` reads keep returning exactly what they did before
## tiers existed. Every other caller in this codebase (this file's own
## `capacity()`/`best_tier()`, and every external caller updated for this task) always
## passes a real `HabitatTier` and never touches the alias path.
##
## `self_site` is the already-registered site being re-evaluated, or null for a PROSPECTIVE
## candidate (a tile the player just edited, which no one lives on yet).
static func tag_counts(
	grid: WorldGrid,
	registry: HomeSiteRegistry,
	origin: Vector2i,
	species: AnimalDefinition,
	tier: HabitatTier = null,
	self_site: HomeSite = null
) -> Dictionary:
	var counts: Dictionary = {}
	if grid == null or species == null:
		return counts

	var use_tier: HabitatTier = tier
	var legacy_mode: bool = false
	if use_tier == null:
		use_tier = species.legacy_tier()
		legacy_mode = true
	if use_tier == null:
		return counts

	var fallback: int = species.effective_capacity_radius()
	# Each bucket: the keys to accumulate into (radius-keyed, plus a bare-tag alias when
	# resolved via the legacy fallback above), the tag to match, and its squared radius.
	var buckets: Array[Dictionary] = []
	for need: HabitatNeed in use_tier.needs:
		var nr: int = need.effective_radius(fallback)
		var nkey: String = count_key(need.tag, nr)
		var nkeys: Array[String] = [nkey]
		counts[nkey] = 0
		if legacy_mode:
			counts[need.tag] = 0
			nkeys.append(need.tag)
		buckets.append({"keys": nkeys, "tag": need.tag, "r_squared": nr * nr})
	for limit: HabitatLimit in use_tier.limits:
		var lr: int = limit.effective_radius(fallback)
		var lkey: String = count_key(limit.tag, lr)
		var lkeys: Array[String] = [lkey]
		counts[lkey] = 0
		if legacy_mode:
			counts[limit.tag] = 0
			lkeys.append(limit.tag)
		buckets.append({"keys": lkeys, "tag": limit.tag, "r_squared": lr * lr})
	if buckets.is_empty():
		return counts

	var r: int = use_tier.max_radius(fallback)
	var r_squared: int = r * r
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var d_squared: int = dx * dx + dz * dz
			if d_squared > r_squared:
				continue
			var tile: Vector2i = origin + Vector2i(dx, dz)
			if not grid.tile_in_bounds(tile):
				continue
			if not _tile_counts_for(registry, tile, origin, d_squared, self_site, species):
				continue
			var tile_tags: Array = grid.get_tile_tags(tile.x, tile.y)
			# Resident-emitted tags, counted PER INDIVIDUAL. A house holding four villagers
			# contributes people=4. Counting this per-tile instead would silently turn
			# "one pug per five people" into "one pug per five houses".
			var resident_counts: Dictionary = {}
			if registry != null:
				for resident_site: HomeSite in registry.sites_at(tile):
					if resident_site == self_site:
						continue
					var population: int = resident_site.population()
					if population < 1:
						continue
					for emitted: String in resident_site.resident_tags:
						resident_counts[emitted] = int(resident_counts.get(emitted, 0)) + population
			for bucket: Dictionary in buckets:
				if d_squared > int(bucket["r_squared"]):
					continue
				var bucket_tag: String = bucket["tag"]
				var added: int = 0
				if tile_tags.has(bucket_tag):
					added += 1
				added += int(resident_counts.get(bucket_tag, 0))
				if added > 0:
					# Reaches EVERY key shape this bucket emits -- both the radius-keyed entry
					# and, in legacy mode, the bare-tag alias -- so a resident contribution is
					# never invisible to a legacy-mode caller.
					for key: String in (bucket["keys"] as Array[String]):
						counts[key] = int(counts[key]) + added
	return counts


## The exclusivity test, O(1) per tile against the registry's ownership index.
##
## A tile counts for this candidate when it is unclaimed **in this candidate's scope**, when
## this candidate already owns it, or when this candidate is STRICTLY NEARER than the current
## owner in that same scope. The last case only ever fires for a prospective candidate — a
## registered site that were strictly nearer would already own the tile, because the
## ownership map applies the same rule. Equidistant loses, which is "ties to the older site"
## (a prospective candidate is younger than every registered one).
##
## SCOPE: `STRUCTURE_SCOPE` when this candidate is structure-associated (`self_site` is a
## structure site), else the querying species' own id — see `HomeSiteRegistry`'s scoping
## header. A structure candidate only ever contests other structures; every other candidate
## only ever contests its own species.
##
## THE ONE CARVE-OUT (2026-08-17): a genuinely PROSPECTIVE candidate (`self_site == null`) is,
## by construction, never itself structure-associated — `HabitatSimulation._site_for()` only
## ever resolves a non-null structure `self_site` when the candidate sits exactly ON that
## structure's own tile (`registry.vacant_site_at(position)`), so `self_site == null` proves
## this query is NOT a structure. Its scope therefore resolves to its own species, never
## `STRUCTURE_SCOPE` — which means, unguarded, it would never see a structure's otherwise-
## unbeatable (distance 0) ownership of ITS OWN tile, and could freely read that tile's tag
## (e.g. `house`) as if unclaimed. The old, unscoped ownership map closed this for free (the
## structure was always the global nearest owner of its own tile); scoping reopens it, so it
## is closed back up explicitly here: a prospective candidate never counts a STRUCTURE'S OWN
## tile, full stop, regardless of species-scope ownership. This is deliberately narrower than
## "never counts anything a structure owns" — `structure_site_at()` is a tile-EXACT check, so a
## field or a patch of grass a structure merely happens to be the nearest STRUCTURE_SCOPE
## owner of (within its radius, not its own footprint) stays freely shareable with a wild
## species that has no use for `house` at all.
static func _tile_counts_for(
	registry: HomeSiteRegistry,
	tile: Vector2i,
	origin: Vector2i,
	distance_squared: int,
	self_site: HomeSite,
	species: AnimalDefinition
) -> bool:
	if registry == null:
		return true
	var scope_key: String = (
		HomeSiteRegistry.STRUCTURE_SCOPE
		if self_site != null and self_site.is_structure()
		else species.id
	)
	if self_site == null and registry.structure_site_at(tile) != null:
		return false
	var owner: HomeSite = registry.owner_at(tile, scope_key)
	if owner == null or owner == self_site:
		return true
	return distance_squared < owner.distance_squared_to(tile)


## `tier_capacity(h, S, T)` — the formula for ONE tier, separated from the tile walk so it
## can be checked line by line without a world.
##
## Order is deliberate: limits gate first (cheapest rejection), then GATE_ONLY needs, then
## Liebig's min over the scaling needs against the TIER's cap.
static func tier_capacity_from_counts(
	counts: Dictionary, species: AnimalDefinition, tier: HabitatTier
) -> int:
	if species == null or tier == null or tier.needs.is_empty():
		return 0
	var fallback: int = species.effective_capacity_radius()

	for limit: HabitatLimit in tier.limits:
		var lr: int = limit.effective_radius(fallback)
		if int(counts.get(count_key(limit.tag, lr), 0)) > limit.max_count:
			return 0

	var result: int = tier.max_individuals
	for need: HabitatNeed in tier.needs:
		var nr: int = need.effective_radius(fallback)
		var count: int = int(counts.get(count_key(need.tag, nr), 0))
		if need.is_gate_only():
			if count < 1:
				return 0
			continue
		# Integer division floors for non-negative operands; counts are never negative.
		var supported: int = count / need.tiles_per_individual
		if supported < result:
			result = supported
	# NO LOWER CLAMP. `capacity == 0` is the unsuitable state and must survive to the caller.
	return max(result, 0)


## `capacity(h, S)` AND the tier that produced it, in ONE pass over `species.effective_tiers()`
## — one `tag_counts()` grid walk per tier, not two.
##
## `capacity()` and `best_tier()` below are this exact loop, run separately, because each
## existed before the other. A caller that needs both (`HabitatSimulation._evaluate()`, the
## whole dirty-queue hot path) must NOT call them back to back — that would walk the grid
## twice per tier for the one answer this function computes once. Call `evaluate()` instead
## and read both keys off the result.
static func evaluate(
	grid: WorldGrid,
	registry: HomeSiteRegistry,
	origin: Vector2i,
	species: AnimalDefinition,
	self_site: HomeSite = null
) -> Dictionary:
	var result: Dictionary = {"capacity": 0, "tier": null}
	if species == null:
		return result
	var best: int = 0
	var winner: HabitatTier = null
	for tier: HabitatTier in species.effective_tiers():
		var counts: Dictionary = tag_counts(grid, registry, origin, species, tier, self_site)
		var value: int = tier_capacity_from_counts(counts, species, tier)
		if value > best:
			best = value
			winner = tier
	result["capacity"] = best
	result["tier"] = winner
	return result


## `capacity(h, S) = max over tiers of tier_capacity(h, S, T)`. Returns 0 for an unsuitable
## site — that is a real value, not a failure.
##
## A thin adapter onto `evaluate()`, kept as its own entry point because most callers (every
## readout, `qualifies()`) want only the number and never the tier.
static func capacity(
	grid: WorldGrid,
	registry: HomeSiteRegistry,
	origin: Vector2i,
	species: AnimalDefinition,
	self_site: HomeSite = null
) -> int:
	return int(evaluate(grid, registry, origin, species, self_site)["capacity"])


## The tier that produced `capacity()`'s value, or null when nothing qualifies.
##
## Needed by callers that must know WHICH tier won, not just the number — `HabitatRecipe`
## shows the player which tier they are on. `HabitatSimulation` does NOT call this: it needs
## both the tier and the capacity in its hot path, so it calls `evaluate()` directly instead
## of pairing this with `capacity()` and doubling the grid walk.
static func best_tier(
	grid: WorldGrid,
	registry: HomeSiteRegistry,
	origin: Vector2i,
	species: AnimalDefinition,
	self_site: HomeSite = null
) -> HabitatTier:
	return evaluate(grid, registry, origin, species, self_site)["tier"] as HabitatTier


## THE PRE-TIER ENTRY POINT, kept because `test_capacity_formula.gd` pins gdd.md's stated
## formula against it and takes bare-tag keys. It is now a thin adapter onto the tiered
## formula rather than a second copy of it — one formula, two key shapes.
##
## The re-key is exact: `legacy_tier()` leaves every synthesised need's radius at
## `HabitatNeed.RADIUS_FOLLOWS_SCOUT`, which `tier_capacity_from_counts()` resolves against
## `fallback = species.effective_capacity_radius()` — the same value used to build `r`
## here, so the rekeyed dictionary's keys line up with what the tier's needs look up.
static func capacity_from_counts(counts: Dictionary, species: AnimalDefinition) -> int:
	if species == null:
		return 0
	var tier: HabitatTier = species.legacy_tier()
	if tier == null:
		return 0
	var r: int = species.effective_capacity_radius()
	var rekeyed: Dictionary = {}
	for tag: String in counts:
		rekeyed[count_key(tag, r)] = counts[tag]
	return tier_capacity_from_counts(rekeyed, species, tier)


## `qualifies(h, S) === capacity(h, S) >= 1` — the same function, not a second system.
static func qualifies(
	grid: WorldGrid,
	registry: HomeSiteRegistry,
	origin: Vector2i,
	species: AnimalDefinition,
	self_site: HomeSite = null
) -> bool:
	return capacity(grid, registry, origin, species, self_site) >= 1
