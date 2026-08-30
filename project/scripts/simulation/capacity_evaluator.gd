class_name CapacityEvaluator
extends RefCounted
## The capacity formula, exactly as gdd.md -> Habitat Suitability states it:
##
##   capacity(h, S) = min( min over t ( floor(count_t / S.tiles_per_individual) ),
##                         S.max_individuals )
##
## The scarcest need caps the population — **Liebig's law of the minimum**. **There is no
## lower clamp: capacity can be 0, and 0 means unsuitable.**
##
## `count_t` is a plain count of tiles within the species' radius whose OWN terrain (or
## building) emits `t` (spec.md -> Shared Patterns, the v1 tag model -> D-25). Tags do not
## spread, carry no emission radius, and have no distance weighting, so one pass over the
## tiles in radius tallying a small fixed set of counters is the whole computation.
##
## **BOTH `S.` TERMS ARE READ FROM THE `AnimalDefinition`** — `S.max_individuals` and
## `S.capacity_radius` are real exported fields as of D-27 #1, and this file holds no
## tuning constant of its own. The two spec/code contradictions this header used to carry
## are closed: spec.md is the field-level build contract, and code does not overrule it.
## Note the radius: the tile walk uses `S.effective_capacity_radius()`, which is what the
## field is FOR — `scout_radius` scores a home site, `capacity_radius` counts its acreage.
## v1's default makes them equal; the code no longer assumes they are.


## `count_t` for every tag in `species.habitat_needs`, over the tiles this candidate site
## may count.
##
## `self_site` is the already-registered site being re-evaluated, or null for a PROSPECTIVE
## candidate (a tile the player just edited, which no one lives on yet).
static func tag_counts(
	grid: WorldGrid,
	registry: HomeSiteRegistry,
	origin: Vector2i,
	species: AnimalDefinition,
	self_site: HomeSite = null
) -> Dictionary:
	var counts: Dictionary = {}
	if grid == null or species == null:
		return counts
	for tag: String in species.habitat_needs:
		counts[tag] = 0

	var r: int = species.effective_capacity_radius()
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
			for tag: String in grid.get_tile_tags(tile.x, tile.y):
				if counts.has(tag):
					counts[tag] = int(counts[tag]) + 1
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


## `capacity(h, S)`. Returns 0 for an unsuitable site — that is a real value, not a failure.
static func capacity(
	grid: WorldGrid,
	registry: HomeSiteRegistry,
	origin: Vector2i,
	species: AnimalDefinition,
	self_site: HomeSite = null
) -> int:
	if species == null or species.habitat_needs.is_empty():
		return 0
	if species.tiles_per_individual < 1:
		return 0
	var counts: Dictionary = tag_counts(grid, registry, origin, species, self_site)
	return capacity_from_counts(counts, species)


## The formula itself, separated from the tile walk so it can be checked against gdd.md
## line by line without a world.
static func capacity_from_counts(counts: Dictionary, species: AnimalDefinition) -> int:
	if species == null or species.habitat_needs.is_empty():
		return 0
	var divisor: int = species.tiles_per_individual
	if divisor < 1:
		return 0
	# The formula's outer `min`, straight off the species' own data.
	var result: int = species.max_individuals
	for tag: String in species.habitat_needs:
		var count: int = int(counts.get(tag, 0))
		# Integer division floors for non-negative operands; counts are never negative.
		var supported: int = count / divisor
		if supported < result:
			result = supported
	# NO LOWER CLAMP. `capacity == 0` is the unsuitable state and must survive to the caller.
	return max(result, 0)


## `qualifies(h, S) === capacity(h, S) >= 1` — the same function, not a second system.
static func qualifies(
	grid: WorldGrid,
	registry: HomeSiteRegistry,
	origin: Vector2i,
	species: AnimalDefinition,
	self_site: HomeSite = null
) -> bool:
	return capacity(grid, registry, origin, species, self_site) >= 1
