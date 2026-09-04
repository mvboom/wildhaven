class_name HabitatSimulation
extends Node
## Habitat qualification and move-in — Tier 1 row 6, thin form. The heart of the USP:
## **animals move in only because a real spot met their needs.**
##
## EVENT-DRIVEN, NEVER A SCAN (gdd.md -> Habitat Suitability; -> D-22). There are exactly
## four triggers:
##   1. terraform            -> `on_terraform()`
##   2. building add/remove  -> `on_building_changed()`
##   3. resident arrives     -> `on_resident_arrived()`
##   4. resident departs     -> `on_resident_departed()`
##
## **Mist reveal is explicitly NOT a trigger** (row 13's invariant): revealed land is
## tag-inert wild grass, so a reveal cannot change any tag count, and treating it as an
## event would make pushing the mist look like progress. Harvesting is not a trigger either
## — tending never removes tags. Climate is static; Pillar 1 bans timers.
##
## Each trigger marks the affected neighbourhood dirty and enqueues re-evaluation; `tick()`
## drains a BOUNDED number of evaluations per frame. **That queue is the CPU budget**
## (gdd.md -> Performance), and the fallback if it is ever exceeded is simply a slower
## drain — invisible, because arrivals are already delayed.
##
## **An idle world does zero simulation work.** `tick()` returns on its first line when both
## queues are empty, and `evaluations_run` is public so a test can assert the zero rather
## than trust it.
##
## PRESENTATION IS NOT SIMULATION. Waypoint wander and the move-in prop live in
## `ResidentPresentation` (`scripts/world/resident_presentation.gd`), which this class calls
## once — at move-in — and then never again. A resident moving is deliberately **not** a fifth
## trigger: it marks nothing dirty, re-qualifies nothing, and cannot move `evaluations_run`.
## The optional `presentation` argument to `attach()` is the whole coupling, so a headless
## fixture that omits it gets the simulation with no view layer at all.
##
## NOT BUILT HERE, deliberately: Gentle Displacement (row 10) — the de-qualification half of
## this system. Capacity falling below population currently does nothing. That is a pillar
## invariant which must ship before any kid playtest; it is out of scope for the skeleton
## only. Also absent: the avoids distance-keeping (row 9) and Discovery's near-miss summary
## (row 12).

## Fires when a resident actually lands. This is what the fact card rides (row 7).
signal resident_arrived(species_id: String, world_position: Vector3)

## Fires when a home site's capacity is recomputed. Read-only telemetry for the HUD and,
## later, for the live neighborhood preview.
signal capacity_evaluated(position: Vector2i, species_id: String, capacity: int)


## PLACEHOLDER / GDD baseline — the human owns this (Open Question #28; spec.md -> Pacing
## Constants, "Dirty-queue drain budget: N evaluations/frame ... the CPU budget").
##
## One "evaluation" is one candidate position against the WHOLE roster, which is the
## `scout_radius x roster size` unit gdd.md -> Performance prices a player action at.
const MAX_EVALUATIONS_PER_FRAME: int = 4


var evaluations_run: int = 0

var _grid: WorldGrid = null
var _roster: SpeciesRoster = null
var _registry: HomeSiteRegistry = null
var _arrivals: ArrivalQueue = null
var _residents_root: Node3D = null
var _presentation: ResidentPresentation = null

var _dirty: Array[Vector2i] = []
var _dirty_set: Dictionary = {}

## Which look each newly arrived resident wears. Owned per simulation instance (see
## `VariantBag`'s header for why it is not global and why it is not saved).
var _variants: VariantBag = VariantBag.new()


## `presentation` is optional and view-only: pass it and residents wander and get a home prop,
## omit it and the simulation runs identically with nobody moving. Nothing in the qualification
## path reads it.
func attach(
	grid: WorldGrid,
	roster: SpeciesRoster,
	registry: HomeSiteRegistry,
	arrivals: ArrivalQueue,
	residents_root: Node3D,
	presentation: ResidentPresentation = null
) -> void:
	_grid = grid
	_roster = roster
	_registry = registry
	_arrivals = arrivals
	_residents_root = residents_root
	_presentation = presentation


func registry() -> HomeSiteRegistry:
	return _registry


func arrivals() -> ArrivalQueue:
	return _arrivals


## The look-assignment bag. Public for the same reason `arrivals()` is: a test needs to pin
## the permutation property, and a seeded bag is the only way to do that without disturbing
## the engine's global RNG. No simulation code outside this file should call it.
func variants() -> VariantBag:
	return _variants


## True when there is nothing at all to do. An idle world must satisfy this.
func is_idle() -> bool:
	return _dirty.is_empty() and (_arrivals == null or _arrivals.is_empty())


func pending_evaluations() -> int:
	return _dirty.size()


# --- The four triggers ------------------------------------------------------------------

## Trigger 1 — the player painted a tile.
func on_terraform(tile: Vector2i) -> void:
	_mark_neighbourhood_dirty(tile)


## Trigger 2 — a building was added or removed at `tile`.
##
## **A House is a home site** (buildings.md), registered here the moment it is placed rather
## than when someone moves in. That is not bookkeeping: a site in the registry owns its own
## tile under the exclusivity rule, which is what stops a villager settling on the field
## beside a house instead of in it, and it is what makes two adjacent Houses "each keep
## their own `house` tile".
func on_building_changed(tile: Vector2i) -> void:
	_sync_structure_site(tile)
	_mark_neighbourhood_dirty(tile)
	_mark_all_sites_dirty()


func _sync_structure_site(tile: Vector2i) -> void:
	if _grid == null or _registry == null:
		return
	var def: PlaceableDefinition = _grid.get_building(tile.x, tile.y)
	if def == null:
		var vacated: HomeSite = _registry.vacant_site_at(tile)
		if vacated != null:
			_registry.unregister(vacated)
		return
	var origin: Vector2i = _grid.get_building_origin(tile.x, tile.y)
	if _registry.any_site_at(origin):
		return
	var radius: int = _home_site_radius_for(def)
	if radius <= 0:
		return  # this building is nobody's habitat, so it is not a home site
	_registry.register_structure(origin, def.emitted_tags, radius)


## The radius a building's home site allocates over.
##
## ## RULE: for every species this building is actually a home for — that is, every
## `(species, tier)` pair where one of the tier's `needs` names one of this building's
## `emitted_tags` (`HomeSite.serves()`'s own test) — take that TIER's `max_radius()`, which
## spans every need's and limit's radius, falling back to the species' `scout_radius` where a
## need or limit follows it. The site's radius is the widest of those across every matching
## species and tier.
##
## Reads through `AnimalDefinition.effective_tiers()`, never raw `habitat_needs`, for the
## same reason `HomeSite.serves()` does — see its header.
##
## WHY THE TIER'S FULL `max_radius()` AND NOT JUST `scout_radius`: the site's radius is what
## `_mark_neighbourhood_dirty()` uses to decide which edits re-evaluate this site (via
## `HomeSiteRegistry.sites_covering()`), so a tier whose OWN need or limit reaches wider than
## the species' `scout_radius` (an authored radius, not the sentinel) needs the site to notice
## an edit out at that distance too — a narrower site radius would silently miss it. Every
## need/limit in the shipped roster today follows `scout_radius` via the sentinel, so this
## degrades to `scout_radius` in practice, but nothing here special-cases that.
##
## Derived from data rather than declared as a constant, deliberately. A "building home-site
## radius" constant would be a fourth tuning number for the human to rule on, and it would
## have no independent meaning: the only thing the radius is ever used for is evaluating the
## species that live there.
func _home_site_radius_for(def: PlaceableDefinition) -> int:
	var best: int = 0
	if _roster == null or def == null:
		return best
	for species: AnimalDefinition in _roster.species():
		for tier: HabitatTier in species.effective_tiers():
			var matches: bool = false
			for need: HabitatNeed in tier.needs:
				if def.emitted_tags.has(need.tag):
					matches = true
					break
			if matches:
				best = max(best, tier.max_radius(species.scout_radius))
	return best


## Trigger 3 — a resident landed. Its own neighbourhood is dirty (population changed), and
## so is every site whose owned tiles the new site took (the exclusivity rule reallocates).
func on_resident_arrived(site: HomeSite) -> void:
	if site == null:
		return
	_mark_neighbourhood_dirty(site.position)
	_mark_all_sites_dirty()


## Trigger 4 — a resident left. Same reallocation, in the other direction.
func on_resident_departed(site: HomeSite) -> void:
	if site == null:
		return
	_mark_neighbourhood_dirty(site.position)
	_mark_all_sites_dirty()


## The affected neighbourhood of an edit at `tile`:
##   * the tile itself, as a PROSPECTIVE home site — this is how a fresh habitat gets
##     discovered at all, and it is why the cost of one player action is one radius pass
##     per species rather than one per tile in radius;
##   * every already-registered home site whose radius covers the tile, because its counts
##     just changed.
func _mark_neighbourhood_dirty(tile: Vector2i) -> void:
	_enqueue(tile)
	if _registry == null:
		return
	for site: HomeSite in _registry.sites_covering(tile):
		_enqueue(site.position)


func _mark_all_sites_dirty() -> void:
	if _registry == null:
		return
	for site: HomeSite in _registry.sites():
		_enqueue(site.position)


## A burst of taps on one neighbourhood coalesces into one evaluation, because a
## neighbourhood is either dirty or it isn't (gdd.md -> the settlement rule).
func _enqueue(tile: Vector2i) -> void:
	if _dirty_set.has(tile):
		return
	_dirty_set[tile] = true
	_dirty.append(tile)


# --- Draining ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	tick(delta)


## Advances the simulation. Public so a headless test can drive a whole arrival delay in one
## call instead of waiting for real frames.
func tick(delta: float) -> void:
	if is_idle():
		return  # THE ZERO. An idle world does no simulation work.
	_drain(MAX_EVALUATIONS_PER_FRAME)
	_resolve_due_arrivals(delta)


func _drain(budget: int) -> void:
	var done: int = 0
	while done < budget and not _dirty.is_empty():
		var tile: Vector2i = _dirty.pop_front()
		_dirty_set.erase(tile)
		_evaluate(tile)
		done += 1


## The home site a species would occupy at this position, or null for a prospective
## candidate. A vacant structure site counts only for a species the structure is a home for
## (`serves()`), so a rabbit cannot take a House's home site by qualifying on the grass
## around it.
func _site_for(position: Vector2i, species: AnimalDefinition) -> HomeSite:
	if _registry == null or species == null:
		return null
	var settled: HomeSite = _registry.settled_site_at(position, species.id)
	if settled != null:
		return settled
	var vacant: HomeSite = _registry.vacant_site_at(position)
	if vacant != null and vacant.serves(species):
		return vacant
	return null


## `capacity(h, S)` at a position, resolving the home site the same way an evaluation does.
##
## Public because the readouts must not re-derive it: the resident inspect line and the live
## neighborhood preview (spec.md -> Screen Layouts; gdd.md -> Performance) have to agree with
## the number the arrival predicate used, or the player is shown a lie. Reading through
## `_site_for()` is what makes a placed-but-empty House report its real capacity instead of 0.
func capacity_at(position: Vector2i, species: AnimalDefinition) -> int:
	if species == null:
		return 0
	return CapacityEvaluator.capacity(_grid, _registry, position, species, _site_for(position, species))


## `population(h, S)` at a position — settled residents only; a vacant House reports 0.
func population_at(position: Vector2i, species: AnimalDefinition) -> int:
	var site: HomeSite = _site_for(position, species)
	return 0 if site == null else site.population()


## One evaluation: this candidate position against the whole roster.
##
## Reads `CapacityEvaluator.evaluate()` ONCE per species, not `capacity()` then `best_tier()`
## — that pairing would run `species.effective_tiers()`'s `tag_counts()` grid walk twice per
## species, doubling the cost of this hot path for no new information (`capacity()` IS
## `tier_capacity(best_tier)`). See `CapacityEvaluator.evaluate()`'s header.
func _evaluate(position: Vector2i) -> void:
	if _grid == null or _roster == null:
		return
	evaluations_run += 1
	for species: AnimalDefinition in _roster.species():
		var site: HomeSite = _site_for(position, species)
		var result: Dictionary = CapacityEvaluator.evaluate(_grid, _registry, position, species, site)
		var cap: int = int(result["capacity"])
		capacity_evaluated.emit(position, species.id, cap)
		var population: int = 0 if site == null else site.population()
		# THE ARRIVAL PREDICATE, gdd.md verbatim: "an arrival is enqueued only where
		# capacity(h, S) >= population(h, S) + 1 — one read, not two systems."
		if cap >= population + 1:
			var tier: HabitatTier = result["tier"] as HabitatTier
			var group: int = 1 if tier == null else tier.arrival_group_size
			# Never queue more than the site can actually hold right now; the due-time
			# re-check may still trim it further (`_land_or_drop()`'s partial landing).
			_arrivals.enqueue(position, species.id, mini(group, cap - population))


func _resolve_due_arrivals(delta: float) -> void:
	if _arrivals == null:
		return
	for entry: Dictionary in _arrivals.advance(delta):
		_land_or_drop(
			entry["position"] as Vector2i,
			entry["species_id"] as String,
			int(entry.get("count", 1))
		)


## The due-time re-check. The land may have changed since the enqueue, so capacity is read
## again — and if it no longer supports one more, the arrival is **silently dropped, never
## warned**. Nothing had moved in, so there is nothing to explain.
##
## PARTIAL LANDING IS DELIBERATE: a group of three into room for two lands two, not zero.
## All-or-nothing would make herds feel arbitrary, and would interact badly with the tap
## burst the arrival delay exists to absorb. The re-check happens INSIDE the loop, once per
## individual, because each `_move_in()` changes the population the next iteration tests
## against — checking capacity once outside the loop would land the whole group or none of
## it, which is exactly the all-or-nothing behaviour this rule forbids.
func _land_or_drop(position: Vector2i, species_id: String, count: int = 1) -> void:
	var species: AnimalDefinition = _roster.by_id(species_id)
	if species == null:
		return
	for i in range(maxi(count, 1)):
		var site: HomeSite = _site_for(position, species)
		var cap: int = CapacityEvaluator.capacity(_grid, _registry, position, species, site)
		var population: int = 0 if site == null else site.population()
		if cap < population + 1:
			return  # silently dropped — the rest of the group simply never arrives
		_move_in(position, species)


## Lands exactly one individual. `_land_or_drop()` calls this once per member of a landing
## group (habitat-tiers, `HabitatTier.arrival_group_size`) — a lone fox arrives alone, a
## small deer group lands together, each `_move_in()` re-checked against the population it
## just changed. A neighbourhood with room for more beyond the group also fills gradually:
## landing re-marks the neighbourhood dirty, which enqueues the next arrival.
func _move_in(position: Vector2i, species: AnimalDefinition) -> void:
	var site: HomeSite = _site_for(position, species)
	if site == null:
		site = _registry.register(position, species.id, species.scout_radius)
	elif site.is_vacant():
		_registry.claim(site, species.id, species.scout_radius)
	# Derived, not persisted -- re-copied here and in `restore_site()` so a retuned `.tres`
	# takes effect immediately instead of being frozen into an old save.
	site.resident_tags = species.emits_tags.duplicate()
	var world_position: Vector3 = _grid.tile_to_world(position.x, position.y)

	# WHICH LOOK THIS VILLAGER WEARS. Dealt from the per-species shuffle bag, so every look in
	# `model_scenes` appears before any look repeats (the human's stated requirement).
	#
	# THIS USED TO BE `species.pick_variant(site.residents.size())` AND THAT WAS THE BUG: the
	# argument is a resident's slot within its OWN site, not a global identity, so the first
	# resident at every home site in the world hashed to the same look and a world of one- and
	# two-resident homes was almost entirely one variant. See
	# `AnimalDefinition.legacy_variant_index()`.
	var node: Node3D = null
	var variant_index: int = _variants.next(species.id, species.model_scenes.size())
	var variant: PackedScene = species.variant_scene(variant_index)
	if variant != null:
		node = variant.instantiate() as Node3D
	if node != null:
		node.name = "%s_%d_%d_%d" % [species.id, position.x, position.y, site.population()]
		node.position = world_position
		# Tagged BEFORE the tree add so the node is never briefly in the world untagged —
		# `WorldSnapshot.capture()` can run on any frame, including this one.
		HomeSite.tag_variant(node, variant_index)
		if _residents_root != null:
			_residents_root.add_child(node)
		site.residents.append(node)
	else:
		# No model is a content defect, not a simulation one. The resident still exists, so
		# capacity arithmetic stays honest and the fact card still fires.
		push_warning("Species `%s` has no model_scenes; resident is invisible." % species.id)
		site.residents.append(null)

	# The view layer's one and only entry point: a wander for the resident, and a den for the
	# home unless the home is already a building (a House is its own prop). One call at
	# move-in; nothing here is polled, and nothing it does can feed back into qualification.
	if _presentation != null:
		_presentation.present(node, site)

	on_resident_arrived(site)
	resident_arrived.emit(species.id, world_position)


## SAVE RESTORE (Tier 1 row 1) — the move-in path with the announcement removed.
##
## It reuses `_move_in`'s spawn and presentation steps deliberately (a second copy would drift
## the first time move-in changes) and stops short of two things `_move_in` does:
##
##   * `resident_arrived.emit(...)` — that signal fires the fact card (row 7). Loading a world
##     with six residents must not open six fact cards over a world the player has not touched.
##   * `on_resident_arrived(site)` — restore marks everything dirty once, at the end, via
##     `mark_all_dirty()`. Per-site dirtying here would do the same work N times.
##
## `resident_positions` holds saved world positions, one per resident. They are used verbatim:
## residents roam, so a resident is almost never at its home tile's centre, and snapping them
## home on load would visibly teleport the whole neighbourhood.
##
## `resident_variants` holds the saved LOOK per resident, parallel to `resident_positions`
## (`AnimalDefinition.NO_VARIANT` where the save does not say). It is optional and defaults to
## empty, which means every entry reads as "not recorded" — that is the pre-save_version-5
## file, and the whole shape of the backward-compatibility story:
##
##   * a look the file names is used VERBATIM. No re-roll, and the bag is not dealt from —
##     re-rolling on load is precisely what index-keyed derivation was protecting against, and
##     that protection has to survive the fix that removed the derivation.
##   * a look the file does NOT name (an old save, or an index the species no longer has after
##     a `.tres` lost a variant) falls back to `legacy_variant_index(i)` — the pre-fix
##     derivation. That reproduces exactly what that old world already showed on screen, so an
##     existing village looks no worse than it did and does not visibly reshuffle. It also does
##     not look BETTER: an old save keeps its sameness until its residents turn over. That is
##     the honest outcome — the file simply does not contain the information.
##
## The restored look is then `consume()`d from the bag so the next NEW arrival in this session
## does not immediately repeat a look already standing in the loaded world.
func restore_site(
	position: Vector2i,
	species_id: String,
	radius: int,
	structure_tags: Array[String],
	resident_positions: Array,
	resident_variants: Array = []
) -> HomeSite:
	var site: HomeSite = _registry.restore_site(position, species_id, radius, structure_tags)
	if site.is_vacant():
		return site  # a House standing empty: no residents to spawn

	var species: AnimalDefinition = _roster.by_id(site.species_id)
	if species == null:
		push_warning("Save names unknown species `%s`; its home is dropped." % species_id)
		_registry.unregister(site)
		return null
	# Derived, not persisted -- a save loaded without this re-derivation would silently
	# drop every `people`/`deer` contribution until the next move-in.
	site.resident_tags = species.emits_tags.duplicate()

	for i in resident_positions.size():
		var entry: Variant = resident_positions[i]
		var world_position: Vector3 = entry as Vector3
		var node: Node3D = null

		var variant_index: int = AnimalDefinition.NO_VARIANT
		if i < resident_variants.size():
			variant_index = int(resident_variants[i])
		if variant_index < 0 or variant_index >= species.model_scenes.size():
			variant_index = species.legacy_variant_index(i)

		var variant: PackedScene = species.variant_scene(variant_index)
		if variant != null:
			node = variant.instantiate() as Node3D
		if node == null:
			push_warning("Species `%s` has no model_scenes; resident is invisible." % species.id)
			site.residents.append(null)
			continue
		node.name = "%s_%d_%d_%d" % [species.id, position.x, position.y, site.population()]
		node.position = world_position
		HomeSite.tag_variant(node, variant_index)
		_variants.consume(species.id, species.model_scenes.size(), variant_index)
		if _residents_root != null:
			_residents_root.add_child(node)
		site.residents.append(node)
		if _presentation != null:
			_presentation.present(node, site)

	return site


## SAVE RESTORE (Tier 1 row 1). Public because restore is the one caller outside this file that
## legitimately needs every neighbourhood re-evaluated at once.
##
## **THIS IS NOT WHAT RE-DERIVES THE ARRIVAL QUEUE, and it never could be** — an earlier version
## of this comment said it was, which is exactly the reasoning D-31 overturned. `_mark_all_sites_
## dirty()` enqueues only ALREADY-REGISTERED home sites, and a habitat that qualifies but has
## nobody in it yet has no home site to mark; the pending queue is carried in the save file
## (`save_version` 2, `ArrivalQueue.to_save()`/`restore()`) for that reason.
##
## What this DOES re-derive is the state the file deliberately omits: removal receipts and the
## dirty-neighbourhood queue itself, both rebuilt through the ordinary event-driven path. It marks
## neighbourhoods dirty and enqueues **zero** arrivals synchronously — the enqueue happens in a
## later `tick()` drain — which is why `WorldSnapshot.apply()`'s restore-then-mark order is a
## readability choice rather than a correctness one.
func mark_all_dirty() -> void:
	_mark_all_sites_dirty()
