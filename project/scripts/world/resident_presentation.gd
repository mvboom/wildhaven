class_name ResidentPresentation
extends Node
## Everything a move-in puts on screen that the simulation itself does not need: the
## **waypoint wander** and the **home prop**. Tier 1 row 6's thin form names both.
##
## WHY THIS IS A SEPARATE NODE FROM `HabitatSimulation`. gdd.md -> Performance's CPU argument
## rests on an idle world doing zero habitat work, and `test_event_driven_simulation.gd`
## asserts that zero literally — `evaluations_run` must not move across a thousand simulated
## seconds. A wandering resident is presentation, not habitat simulation: it is not one of the
## four triggers, it never marks a neighbourhood dirty, and it must never be able to. Keeping
## the motion in a different node with a different `_process` is what makes that structural
## rather than a promise in a comment.
##
## THE HOME PROP (gdd.md -> Level & world design): "the move-in prop (den, burrow, nest) is
## decoration — no tiles, no collision, gone if the home relocates." All three hold here: the
## prop is parented to a plain visual root outside the tile grid, `Den.tscn` is three meshes
## with no collider, and `release()` frees it.
##
## **ONLY WILD ANIMALS GET A DEN**, and it takes two gates to say that (see
## `_spawn_home_prop()`). A House *is* a villager's home site and its own prop (buildings.md),
## so a burrow beside a house would be a second home for one family — that one is expressed
## against the DATA, and nothing here knows what a villager is. The second gate reads
## `AnimalDefinition.category()`, because a farm animal can settle on open ground too: Husky,
## Pig and Sheep each have one tier that gates on no building, and each was getting a mossy-log
## burrow on somebody's farm.
##
## **MINIMAL AVOIDS (row 9, D-29)** also lives here, because this is the one place that already
## holds every live `ResidentRoamer` — the roamer itself does not and should not know about the
## roster or about anyone else's position. `present()` resolves the new resident's species
## (needs `_roster`, optional — a caller that omits it just gets no avoids behaviour, same as
## before this row existed) and binds each roamer a `Callable` back to
## `_nearby_avoid_positions()`, which is the only place the symmetric union of two species'
## `avoids` lists is actually resolved.

## The move-in prop. One scene for every WILD species at the floor; per-species props (a nest
## for a bird, a burrow for a rabbit) are content, not a system, and are not scoped here.
const HOME_PROP_SCENE: String = "res://assets/props/den/Den.tscn"

## PLACEHOLDER — the human owns this. **A PURE PERFORMANCE BACKSTOP, NEVER A DESIGN TOOL**
## (gdd.md -> Level & world design: "The global roamer budget scales with revealed world size
## as a pure performance backstop, not a design tool: capacity limits population in play; a
## budget that binds regularly in playtest means capacity is tuned too rich.")
##
## Residents past the budget are throttled, not frozen — `tick()`'s ticked window rotates
## (see its own doc), so everyone still gets turns, but a world whose population exceeds this
## number runs EVERY roamer proportionally slower in wall-clock time (a roamer only advances
## its internal clock on the frames it is actually ticked, so at population P it experiences
## roughly `ROAMER_BUDGET / P` of real time — a "2-6 second" pause becomes minutes once P is a
## few hundred). Raised 2026-08-25 from 64 (64 -> 256) after a live playtest world well past 64
## residents showed exactly that: a whole farm cluster reading as permanently stuck mid-pause.
## 256 is still a flat, arbitrary ceiling — the human's number, not derived from anything — but
## the per-roamer cost `tick()` does under budget is cheap (vector math against an
## already-computed path; no navmesh query except once per wander cycle in `_begin_walk()`), so
## 256 roamers ticking every frame is not a real perf risk at the current world scale. It is
## deliberately set far above any population the floor's capacity values can produce, so that
## **if it ever binds, that is a signal about capacity tuning** and should be read as one. The
## scales-with-revealed-world-size half is row 13's (mist) and is not built: there is no reveal
## yet, so a flat cap is the honest thin form.
const ROAMER_BUDGET: int = 256


var _grid: WorldGrid = null
var _props_root: Node3D = null
var _roster: SpeciesRoster = null
var _navigation: WorldNavigation = null
var _rng := RandomNumberGenerator.new()

var _roamers: Array[ResidentRoamer] = []
var _props: Dictionary = {}  # HomeSite -> Node3D

## Where `tick()`'s rotating window starts this frame. See `tick()`'s own doc for why this
## exists at all.
var _tick_cursor: int = 0


## `roster` is optional and used only to resolve a new resident's `avoids` list (row 9); a
## caller that omits it gets every roamer with an empty avoids list, which is exactly the old
## uniform-wander behaviour and not an error.
func attach(
	grid: WorldGrid,
	props_root: Node3D,
	seed_value: int = 0,
	roster: SpeciesRoster = null,
	navigation: WorldNavigation = null
) -> void:
	_grid = grid
	_props_root = props_root
	_roster = roster
	_navigation = navigation
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value


## Called by `HabitatSimulation` the moment a resident node exists. Gives it a wander and, for
## a wild species' non-structure home, a den.
##
## THE SPECIES IS RESOLVED FIRST because the prop now depends on it (`_spawn_home_prop()`), not
## only the roamer's avoids and region.
func present(resident: Node3D, site: HomeSite) -> void:
	if site == null:
		return
	var species: AnimalDefinition = null
	if _roster != null:
		species = _roster.by_id(site.species_id)
	_spawn_home_prop(site, species)
	if resident == null or not is_instance_valid(resident):
		return

	# NOT a ternary: `Array[String]` on one side and a bare `[]` on the other silently
	# resolves to plain `Array`, which then fails at runtime assigning into a typed variable.
	var avoid_ids: Array[String] = []
	if species != null:
		avoid_ids = species.normalized_avoids()

	# `mini(capacity_radius, site.radius)`: gdd.md bounds roaming by the home NEIGHBOURHOOD,
	# and `test_resident_wander.gd` asserts containment against `site.radius` specifically.
	# Every shipped species has `capacity_radius = 0` (follow scout), which already lands at or
	# under `site.radius`, so this clamp is not binding today — it is here so that stays true
	# by construction rather than by luck if a species ever sets an explicit capacity radius.
	#
	# The region needs both the grid and the species, and this is the only place that holds
	# both. A caller that passed no roster gets `species == null` and therefore no region,
	# which is the pre-terrain-awareness uniform disc — not an error.
	var roam_region: RoamRegion = null
	if species != null and _grid != null:
		roam_region = RoamRegion.new(
			_grid,
			_navigation,
			site.position,
			WorldGrid.tags_mask(species.habitat_needs),
			mini(species.effective_capacity_radius(), site.radius)
		)

	var roamer := ResidentRoamer.new(
		resident,
		_home_world(site),
		float(site.radius),
		_walkable_bounds(),
		_rng,
		site.species_id,
		avoid_ids,
		_navigation,
		roam_region
	)
	# Bound AFTER construction: the provider closes over `roamer`, which does not exist until
	# `ResidentRoamer.new()` returns.
	roamer.set_nearby_avoid_provider(Callable(self, "_nearby_avoid_positions").bind(roamer))
	roamer.set_nearby_resident_provider(
		Callable(self, "_nearby_resident_positions").bind(roamer)
	)
	_roamers.append(roamer)


## Drops a home's presentation — the prop and every roamer anchored to it. This is the "gone if
## the home relocates" half. **Relocation itself is row 10 (Gentle Displacement) and is
## unbuilt**, so nothing calls this yet; it exists so that when row 10 lands, a relocating home
## is one call and not a new subsystem.
func release(site: HomeSite) -> void:
	if site == null:
		return
	var had_prop: bool = _props.has(site)
	var prop: Node3D = _props.get(site, null) as Node3D
	if prop != null and is_instance_valid(prop):
		prop.queue_free()
	_props.erase(site)
	# KEYED ON WHETHER A PROP WAS ACTUALLY SPAWNED, not on `site.is_structure()`. The two
	# agreed while a structure home was the only thing that skipped the prop; now that a
	# non-wild species skips it too, re-deriving the condition here would clear a reservation
	# this site never made — and `set_den_tile_blocked(pos, false)` on a tile some OTHER den
	# holds would hand a neighbour's home tile back to the pathfinder.
	if _navigation != null and had_prop:
		_navigation.set_den_tile_blocked(site.position, false)

	var home: Vector3 = _home_world(site)
	var kept: Array[ResidentRoamer] = []
	for roamer: ResidentRoamer in _roamers:
		if roamer.is_valid() and not roamer.home().is_equal_approx(home):
			kept.append(roamer)
	_roamers = kept


func roamer_count() -> int:
	return _roamers.size()


func prop_count() -> int:
	return _props.size()


## The roamer at index `i`, or null. Public only so a headless check can read a resident's
## animation state without reaching into the array.
func roamer(index: int) -> ResidentRoamer:
	if index < 0 or index >= _roamers.size():
		return null
	return _roamers[index]


func _process(delta: float) -> void:
	tick(delta)


## Advances up to `ROAMER_BUDGET` roamers. Public so a headless run can drive wander without
## waiting on real frames — the same shape as `HabitatSimulation.tick()`.
##
## THE TICKED WINDOW ROTATES. A world past the budget cannot tick everyone every frame — that
## is the backstop's whole point — but it must not always be the SAME everyone that loses out.
## `_roamers` never reorders itself (arrival order), so always ticking a fixed prefix of it
## (`_roamers[0..ROAMER_BUDGET]`) would permanently freeze whoever is at index `ROAMER_BUDGET`
## or later: not "moves less often", but never ticks again for the rest of the game, standing
## exactly at its own home/den tile forever — which reads to a player as a stuck, broken
## animal, not as a performance backstop. Advancing `_tick_cursor` by the number actually
## ticked each call spreads the throttling across everyone instead of concentrating all of it
## on whoever arrived last (`test_roamer_budget.gd`).
func tick(delta: float) -> void:
	if _roamers.is_empty():
		return
	var live: Array[ResidentRoamer] = []
	for roamer: ResidentRoamer in _roamers:
		if roamer.is_valid():
			live.append(roamer)
	_roamers = live
	if live.is_empty():
		return

	var count: int = mini(ROAMER_BUDGET, live.size())
	for i in count:
		var index: int = (_tick_cursor + i) % live.size()
		live[index].tick(delta)
	_tick_cursor = (_tick_cursor + count) % live.size()


## Every live roamer's current position that `requester` should keep `AVOID_DISTANCE_TILES`
## from — bound into `requester`'s own `_nearby_avoid_provider`, so this only ever runs at
## `requester`'s own wander-pause cadence, never per frame.
##
## THE SYMMETRIC UNION (gdd.md:207 via `AnimalDefinition.avoids`'s own doc: "may be declared
## on either species... the resolver must union both directions"): two roamers are mutual
## avoiders the moment EITHER one's `avoid_ids()` names the other's species — checked both
## ways, so a pair declared on only one side (or, as the floor roster actually ships it, on
## both) behaves identically regardless of which species' data happened to carry the entry.
func _nearby_avoid_positions(requester: ResidentRoamer) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if requester == null or not requester.is_valid():
		return out
	var origin: Vector3 = requester.resident().position
	var reach_squared: float = ResidentRoamer.AVOID_DISTANCE_TILES * ResidentRoamer.AVOID_DISTANCE_TILES
	for other: ResidentRoamer in _roamers:
		if other == requester or not other.is_valid():
			continue
		var mutual_avoid: bool = (
			requester.avoid_ids().has(other.species_id())
			or other.avoid_ids().has(requester.species_id())
		)
		if not mutual_avoid:
			continue
		var delta: Vector3 = other.resident().position - origin
		delta.y = 0.0
		if delta.length_squared() <= reach_squared:
			out.append(other.resident().position)
	return out


## Every OTHER live roamer's current position within `SEPARATION_DISTANCE_TILES` of
## `requester` — ANY species, unlike `_nearby_avoid_positions()`'s mutual-`avoids` filter.
## Feeds `ResidentRoamer`'s per-tick separation steering, so — unlike the avoid query, which
## only runs at `requester`'s own wander-pause cadence — this is expected to run every tick
## a resident is WALKING.
func _nearby_resident_positions(requester: ResidentRoamer) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if requester == null or not requester.is_valid():
		return out
	var origin: Vector3 = requester.resident().position
	var reach_squared: float = (
		ResidentRoamer.SEPARATION_DISTANCE_TILES * ResidentRoamer.SEPARATION_DISTANCE_TILES
	)
	for other: ResidentRoamer in _roamers:
		if other == requester or not other.is_valid():
			continue
		var delta: Vector3 = other.resident().position - origin
		delta.y = 0.0
		if delta.length_squared() <= reach_squared:
			out.append(other.resident().position)
	return out


func _home_world(site: HomeSite) -> Vector3:
	if _grid == null:
		return Vector3.ZERO
	return _grid.tile_to_world(site.position.x, site.position.y)


## The walkable surface in world XZ, so a waypoint can never fall off the world.
func _walkable_bounds() -> Rect2:
	if _grid == null:
		return Rect2()
	var min_corner: Vector3 = _grid.tile_to_world(0, 0)
	var max_corner: Vector3 = _grid.tile_to_world(_grid.width - 1, _grid.depth - 1)
	return Rect2(
		Vector2(min_corner.x, min_corner.z),
		Vector2(max_corner.x - min_corner.x, max_corner.z - min_corner.z)
	)


## One prop per home site, and **only for a WILD species living outside a structure**.
##
## TWO GATES, and they exclude different things:
##
##   * `site.is_structure()` — a House or a Barn IS its own prop, so a burrow beside it would
##     be a second home for one family.
##   * `species.category() != CATEGORY_WILD` — a den beside the farm was the same mistake one
##     step out. Husky, Pig and Sheep each carry ONE tier that gates on no building
##     (`companion`, `sty`, `base`), so they could found a home on open ground and got a
##     mossy-log den for it, which reads as a wild animal's burrow on a farm animal. Only
##     `CATEGORY_WILD` — Fox, Rabbit, Deer, Stag, Donkey — moves into a den.
##
## READ FROM `category()`, NOT FROM A NEW FIELD, deliberately: the taxonomy already exists and
## is already derived from each species' own tiers, so nothing new has to be authored per
## species and nothing can drift out of step with the habitat data. The cost is that the line
## is drawn at wild-vs-not, not at size — a Deer gets the same den a Rabbit does. A per-species
## prop (a nest for a bird, a burrow for a rabbit) is the finer-grained version of this and is
## still content, not a system; it would replace this gate rather than sit beside it.
##
## AN UNRESOLVED SPECIES GETS NO PROP. `attach()`'s roster is optional and a caller that omits
## it still gets working roamers, but it cannot get a den — the rule above is unanswerable
## without the species, and guessing "yes" would put the old behaviour back for exactly the
## callers that cannot see it. `WorldRoot` always passes the roster.
func _spawn_home_prop(site: HomeSite, species: AnimalDefinition) -> void:
	if _props_root == null or site.is_structure() or _props.has(site):
		return
	if species == null or species.category() != AnimalDefinition.CATEGORY_WILD:
		return
	var packed: PackedScene = load(HOME_PROP_SCENE) as PackedScene
	if packed == null:
		push_warning("Home prop scene `%s` is missing; residents move in without one." % HOME_PROP_SCENE)
		return
	var prop: Node3D = packed.instantiate() as Node3D
	if prop == null:
		return
	prop.name = "Den_%d_%d" % [site.position.x, site.position.y]
	prop.position = _home_world(site)
	_props_root.add_child(prop)
	_props[site] = prop
	# NAVIGATION-ONLY reservation — deliberately NOT `WorldGrid.is_occupied()`/
	# `set_building()`. A den blocks OTHER residents' pathing without affecting building
	# placement or capacity math.
	if _navigation != null:
		_navigation.set_den_tile_blocked(site.position, true)
