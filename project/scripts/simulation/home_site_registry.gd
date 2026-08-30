class_name HomeSiteRegistry
extends RefCounted
## Every home site, plus **the tile-exclusivity index**.
##
## THE EXCLUSIVITY RULE (gdd.md -> Habitat Suitability): "A tile counts toward at most one
## home site. Where capacity radii overlap, each qualifying tile goes to the nearest home
## site only, ties to the older site — two fox dens in one wood split its `forest` tiles,
## and two Houses each keep their own `house` tile."
##
## Implemented as an ownership map rather than re-derived per evaluation. `owner_at()` is
## then O(1), which is what keeps a capacity evaluation "one pass over the tiles in radius
## tallying counters" (spec.md -> Shared Patterns, implementation note) instead of a nested
## loop over tiles x sites.
##
## The map is rebuilt whole whenever the registry changes. That is deliberately the dumb
## option: registry changes are placements, arrivals and departures — rare, player-visible
## events — and a full rebuild is obviously correct where an incremental patch is a class of
## bug (a stale claim silently deflates a neighbourhood's capacity, which the player would
## experience as an animal that inexplicably will not move in).

var _sites: Array[HomeSite] = []
var _next_sequence: int = 0

## SCOPING (2026-08-17): exclusivity is not global across every species in the game — it only
## applies between home sites that are genuinely rivals for the same land. gdd.md's own two
## worked examples are actually two DIFFERENT rules once you separate them: "two fox dens in
## one wood split its `forest` tiles" is same-species exclusivity, and "two Houses each keep
## their own `house` tile" is exclusivity among STRUCTURES regardless of occupant species. A
## Fox den and a Rabbit warren, or a Cow pasture and a Horse pasture, are not rivals and now
## freely coexist on the same land.
##
## Every structure site (`is_structure()`, i.e. `structure_tags` non-empty) — vacant or
## claimed, regardless of species — belongs to this one shared scope. That pooling is what
## keeps "two Houses each keep their own tile" true independent of who lives in each House:
## Human/Husky/Shiba Inu all need `house`, and the ONLY tag source for `house` is a placed
## House (terrain.md), so every one of their sites is, in practice, always a structure site.
## If structures were scoped by species instead, two Houses occupied by different species
## would stop competing for the same yard, breaking that invariant.
##
## Safe as a dictionary key because real species ids can never start with `_`
## (`AnimalDefinition.ID_PATTERN`).
const STRUCTURE_SCOPE: String = "__structure__"

## Every other ("wild den") site is scoped by its own `species_id` — same-species sites still
## split their radius; different species no longer compete at all.
static func _scope_key(site: HomeSite) -> String:
	return STRUCTURE_SCOPE if site.is_structure() else site.species_id

## scope key (String) -> Dictionary<Vector2i, HomeSite>. Absent tile within a scope means
## unclaimed IN THAT SCOPE — a tile can be simultaneously owned by a structure site and, in a
## different scope, by a same-species wild den; the two maps never interact.
var _owner: Dictionary = {}

## **SPECIES HOSTED, AND IT IS PERMANENT.** gdd.md -> Gentle Displacement: "Species Hosted and
## the Field Guide entry stay permanent" — "a departure never erases the record that the
## species was hosted", and gdd.md -> Economy: "Species Hosted (all-time, never decreases)".
##
## Written by `register()` and `claim()`; **read-only to everything else, and never erased by
## `release()` or `unregister()`.** That asymmetry is the whole point, so it is enforced by
## there being no removal path rather than by a rule someone has to remember.
##
## THE COUNTER ITSELF IS NOT BUILT — the HUD's Species Hosted readout is Tier 1 row 11
## (ui-engineer). This is the data the counter will read, landed with row 10 because row 10
## is what would otherwise silently lose the record.
var _ever_hosted: Dictionary = {}  # species_id -> true


func sites() -> Array[HomeSite]:
	return _sites


func is_empty() -> bool:
	return _sites.is_empty()


## The settled site for this exact position and species, or null. Never returns a vacant
## structure site — claiming one is a separate, guarded step (`claim()`).
func settled_site_at(position: Vector2i, species_id: String) -> HomeSite:
	var wanted: String = AnimalDefinition.normalize_id(species_id)
	for site: HomeSite in _sites:
		if site.position == position and site.species_id == wanted:
			return site
	return null


## The unclaimed structure site at a position, or null.
func vacant_site_at(position: Vector2i) -> HomeSite:
	for site: HomeSite in _sites:
		if site.position == position and site.is_vacant():
			return site
	return null


func any_site_at(position: Vector2i) -> bool:
	for site: HomeSite in _sites:
		if site.position == position:
			return true
	return false


## The structure site (vacant OR claimed) whose OWN position is exactly `position`, or null.
##
## EXISTS FOR ONE REASON: `CapacityEvaluator._tile_counts_for()` uses it to stop a genuinely
## PROSPECTIVE candidate (`self_site == null` — by construction never itself structure-
## associated, since `HabitatSimulation._site_for()` only ever resolves a non-null structure
## self_site when the candidate sits exactly ON that structure's own tile) from reading a
## structure's own emitted tag (e.g. `house`) at all, regardless of which species-scope it is
## querying under. Tags a building emits exist ONLY at the building's own tile (buildings.md:
## "the footprint suppresses the ground's tags and emits its own"), so this is a narrow,
## tile-exact check — it does NOT withhold every tile a structure happens to be the nearest
## STRUCTURE_SCOPE owner of (a field or a patch of grass beside a House stays freely shareable
## with a wild species that has no use for `house`), only the structure's own footprint tile.
## Without this, a prospective candidate resolves its scope from `species.id` (never
## `STRUCTURE_SCOPE`, since it has no self_site to test `is_structure()` on) and so never sees
## the structure's OWN, otherwise-unbeatable (distance 0) ownership of that tile — which the
## old, unscoped map enforced for free. See `capacity_evaluator.gd`'s caller note.
func structure_site_at(position: Vector2i) -> HomeSite:
	for site: HomeSite in _sites:
		if site.position == position and site.is_structure():
			return site
	return null


## `population(h, S)` in the capacity formula — 0 where no settled site exists yet.
func population_at(position: Vector2i, species_id: String) -> int:
	var site: HomeSite = settled_site_at(position, species_id)
	return 0 if site == null else site.population()


## Registers a settled site. Its sequence is higher than every existing one, so it loses
## every distance tie — "ties to the older site".
func register(position: Vector2i, species_id: String, radius: int) -> HomeSite:
	var existing: HomeSite = settled_site_at(position, species_id)
	if existing != null:
		return existing
	var site := HomeSite.new(
		position, AnimalDefinition.normalize_id(species_id), radius, _next_sequence
	)
	_next_sequence += 1
	_sites.append(site)
	_ever_hosted[site.species_id] = true
	rebuild_ownership()
	return site


## Registers a building's home site, unclaimed. Called the moment the building is placed —
## buildings.md: "A House is a home site with a fixed footprint."
func register_structure(position: Vector2i, emitted_tags: Array[String], radius: int) -> HomeSite:
	var existing: HomeSite = vacant_site_at(position)
	if existing != null:
		return existing
	var site := HomeSite.new(position, "", radius, _next_sequence, emitted_tags)
	_next_sequence += 1
	_sites.append(site)
	rebuild_ownership()
	return site


## SAVE RESTORE (Tier 1 row 1). Creates a site exactly as saved — one call for both shapes,
## because a House with a family is a structure site AND a claimed one, and `register()` /
## `register_structure()` each build only half of that.
##
## SEQUENCE IS ASSIGNED IN CALL ORDER, and `WorldSnapshot` writes sites sorted by sequence, so
## restoring in file order reproduces the original ordering. That is not tidiness:
## `rebuild_ownership()` breaks distance ties by lower sequence, so a different order is a
## different map of which home owns which tile.
##
## Unlike `register()`, this does NOT look for an existing site first. A save is authoritative;
## deduplicating against a world that is supposed to be empty would hide a real bug.
func restore_site(
	position: Vector2i, species_id: String, radius: int, structure_tags: Array[String]
) -> HomeSite:
	var normalized: String = AnimalDefinition.normalize_id(species_id)
	var site := HomeSite.new(position, normalized, radius, _next_sequence, structure_tags)
	_next_sequence += 1
	_sites.append(site)
	# A vacant structure site has no species, and "" must never enter the hosted record.
	if normalized != "":
		_ever_hosted[normalized] = true
	rebuild_ownership()
	return site


## SAVE RESTORE (Tier 1 row 1) for the half of Species Hosted that has no home site left.
## gdd.md -> Economy: "Species Hosted (all-time, never decreases)". A species that moved in and
## later departed leaves no site behind, so restoring sites alone would silently erase the
## record — the exact loss `_ever_hosted`'s no-removal-path design exists to prevent.
## Additive only: it can never clear an entry, for the same reason.
func restore_hosted(species_ids: Array[String]) -> void:
	for id: String in species_ids:
		var normalized: String = AnimalDefinition.normalize_id(id)
		if normalized != "":
			_ever_hosted[normalized] = true


## A species moves into a vacant structure site. The site keeps its sequence — it has been
## a home site since the building was placed, and its age is what makes the exclusivity
## tie-break come out right.
func claim(site: HomeSite, species_id: String, radius: int) -> void:
	if site == null or not site.is_vacant():
		return
	site.species_id = AnimalDefinition.normalize_id(species_id)
	site.radius = radius
	_ever_hosted[site.species_id] = true
	rebuild_ownership()


func unregister(site: HomeSite) -> void:
	if site == null:
		return
	_sites.erase(site)
	rebuild_ownership()


## THE DEPARTURE HALF of Gentle Displacement (row 10): an emptied home leaves the registry.
##
## A **structure** home site is different, and the difference matters: a House is a home site
## from the moment it is placed (buildings.md), so a family moving away leaves the House
## standing and available for the next family. Pass `structure_remains = true` and the site is
## un-claimed rather than removed, keeping its sequence — which keeps the exclusivity
## tie-break correct, since the House really has been a home site since it was built.
##
## **`_ever_hosted` is deliberately untouched.** Species Hosted never decreases.
func release(site: HomeSite, structure_remains: bool) -> void:
	if site == null:
		return
	if site.is_structure() and structure_remains:
		site.species_id = ""
		rebuild_ownership()
		return
	unregister(site)


## THE RELOCATION HALF: the same home, somewhere else. gdd.md -> Gentle Displacement:
## "relocation if a suitable spot exists ... the animal visibly moving its home."
##
## The site keeps its identity, its residents and its **sequence** — this is one family that
## moved, not a family that vanished and a new one that appeared, and the counters must not
## read it as either.
func relocate(site: HomeSite, destination: Vector2i) -> void:
	if site == null or site.position == destination:
		return
	site.position = destination
	rebuild_ownership()


## The site that owns a tile WITHIN `scope_key`'s scope, or null when no site in that scope
## claims it. `scope_key` is `STRUCTURE_SCOPE` for a query on behalf of a structure-associated
## candidate, or a `species_id` otherwise — see `_scope_key()` and the caller note in
## `capacity_evaluator.gd`.
func owner_at(tile: Vector2i, scope_key: String) -> HomeSite:
	if not _owner.has(scope_key):
		return null
	var scoped: Dictionary = _owner[scope_key]
	return scoped.get(tile, null) as HomeSite


## Recomputes the whole ownership map: `_sites` is grouped by scope key (`_scope_key()`), and
## the existing nearest-wins/ties-to-the-older-sequence algorithm runs independently within
## each group. The algorithm itself is unchanged — only its grouping is new — so a tile can
## simultaneously be owned by a structure site in the structure scope AND by an unrelated
## same-species wild den in that species' own scope; the two scopes never contest each other.
## Only tiles inside some site's radius are claimed at all.
func rebuild_ownership() -> void:
	_owner = {}
	var groups: Dictionary = {}  # scope key -> Array[HomeSite]
	for site: HomeSite in _sites:
		var key: String = _scope_key(site)
		if not groups.has(key):
			groups[key] = [] as Array[HomeSite]
		(groups[key] as Array[HomeSite]).append(site)

	for key: Variant in groups.keys():
		var scoped: Dictionary = {}
		for site: HomeSite in (groups[key] as Array[HomeSite]):
			var r: int = site.radius
			for dx in range(-r, r + 1):
				for dz in range(-r, r + 1):
					if dx * dx + dz * dz > r * r:
						continue
					var tile: Vector2i = site.position + Vector2i(dx, dz)
					var current: HomeSite = scoped.get(tile, null) as HomeSite
					if current == null:
						scoped[tile] = site
						continue
					var mine: int = site.distance_squared_to(tile)
					var theirs: int = current.distance_squared_to(tile)
					if mine < theirs or (mine == theirs and site.sequence < current.sequence):
						scoped[tile] = site
		_owner[key] = scoped


## Every site whose radius covers `tile` — the "affected neighbourhood" of an edit at that
## tile, and exactly the set that has to be re-evaluated when it changes.
func sites_covering(tile: Vector2i) -> Array[HomeSite]:
	var out: Array[HomeSite] = []
	for site: HomeSite in _sites:
		if site.covers(tile):
			out.append(site)
	return out


func total_residents() -> int:
	var total: int = 0
	for site: HomeSite in _sites:
		total += site.population()
	return total


## Individuals of exactly one species, summed across every home site — the read Village
## Population (row 11) needs and `total_residents()` cannot give: a world with two farm
## families has two `human` sites, and the HUD counter has to add them, not pick one.
func population_of(species_id: String) -> int:
	var wanted: String = AnimalDefinition.normalize_id(species_id)
	var total: int = 0
	for site: HomeSite in _sites:
		if site.species_id == wanted:
			total += site.population()
	return total


## Every species that has EVER been resident in this world, in first-hosted order. Feeds the
## all-time "Species Hosted" counter and the Field Guide's permanent entry (row 11), and is
## the reason a departure is a loss of residents and never a loss of record.
func species_hosted_ids() -> Array[String]:
	var out: Array[String] = []
	for key: Variant in _ever_hosted.keys():
		out.append(key as String)
	return out


func species_hosted_count() -> int:
	return _ever_hosted.size()


## Distinct species currently resident. NOT the source of the HUD's "Currently Resident"
## counter (row 11) despite the name overlap — that counter is
## `total_residents() - population_of("human")` in `game_ui.gd`. This is currently only
## read by tests and `WorldRoot.resident_species_ids()`'s own callers.
func resident_species_ids() -> Array[String]:
	var out: Array[String] = []
	for site: HomeSite in _sites:
		if site.population() > 0 and not out.has(site.species_id):
			out.append(site.species_id)
	return out
