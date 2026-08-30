class_name GentleDisplacement
extends Node
## GENTLE DISPLACEMENT — Tier 1 row 10, and a **pillar invariant**: it ships whole, only
## presentation thins. gdd.md states the pillar precisely: "animals are never killed, and
## nothing blinks out unexplained. Any loss is the warned, reversible result of the player's
## own settled choice, never the game's initiative."
##
## THE COMPUTABLE TRIGGER, verbatim from gdd.md: "an action warns iff, once its neighbourhood
## settles, `capacity(h, S)` would fall below `population(h, S)` for any home site in range —
## including to 0." So the predicate is `capacity < population`, **strict, with no margin**.
## (A standing tolerance margin for an already-settled neighbourhood is Open Question **#25**,
## explicitly still open and explicitly not v1. There is no "warning threshold" constant here
## and there must not be one.)
##
## MODE-AGNOSTIC. Terraform, build and removal are the same event to this class: `on_edit()`
## takes a tile and does not ask what changed it. That is not a convenience — gdd.md names the
## warning "mode-agnostic", and the likeliest displacement in the floor is a *terraform*
## (clearing the field beside a House), not a build.
##
## HOW THE REVERT RULE IS TRUE RATHER THAN CLAIMED. **Nothing about the pre-edit world is
## recorded anywhere.** The window (`SettlementWindow`) stores tiles and a countdown; every
## number in the warning is read out of the live world at settlement. So a player who puts a
## neighbourhood back — by `remove_at()`, or by painting it back by hand, or by re-placing the
## House — settles into a world where `capacity >= population`, the affected-home list comes
## back empty, and **no warning is emitted and no consequence runs**. "Reverting within the
## window means the displacement never happened" is then a property of the arithmetic, and it
## covers free terrain, where there is no refund transaction to hang an undo on.
##
## WHAT IS **NOT** GATED BY THE WINDOW — three things, and each of them is load-bearing:
##   1. **Capacity arithmetic.** Re-evaluated immediately on every edit by `HabitatSimulation`'s
##      dirty queue, exactly as before. This class does not move it and must not.
##   2. **Arrivals.** A move-in is a gift; gdd.md puts it "deliberately outside the window"
##      because gating it would let ordinary excited tapping defer the payoff past the
##      time-to-first-move-in ceiling. Nothing in this file touches the arrival queue.
##   3. **The player's own edit.** The tile changes instantly. Blocking a build is an
##      explicitly rejected alternative (it is a fail state).
##
## WHY THE SIGNALS LIVE HERE AND NOT ON `HabitatSimulation`. Displacement is not a fifth
## habitat trigger — it consumes the four that exist and adds none. Keeping it in its own node
## keeps that structural: `test_event_driven_simulation.gd` asserts `HabitatSimulation`'s
## trigger set is exactly four and its signal set exactly two, and both assertions stay true
## because this file exists.
##
## REJECTED ALTERNATIVES, recorded so nobody reinvents them (gdd.md): **silent displacement**
## (breaks "nothing unexplained"), **blocking the build** (a fail state), and **capacity
## floors** that make settled land un-losable (habitat goes decorative after move-in, and the
## USP requires live land).
##
## PRESENTATION IS NOT SIMULATION. This class moves records and calls `ResidentPresentation`;
## it plays no animation and waits for none. A leaving animation, a relocation walk, and the
## warning dialogue itself are all the view layer's, and they are free to take as long as they
## like after the signal — which is exactly why there is no "beat" constant here.

## THE WARNING. **One per settled gesture, summarising every affected home** — not per tile,
## not rate-limited, and never suppressed while its consequence proceeds. Emitted immediately
## BEFORE the consequences run, which is gdd.md's "warning first and acting after".
##
## Payload — pure structured data, **no player-facing copy** (that is content-writer's, and
## `project/data/animals/` is not this dispatch's directory):
##   {
##     "gesture_id":  int,                 # stable across a burst; the UI's dedupe key
##     "homes":       Array[Dictionary],   # one entry per affected home, see below
##     "species_ids": Array[String],       # distinct, in first-affected order
##     "read_aloud":  bool,                # row 10 carries the Read-Aloud slice: always true
##   }
## and each home entry:
##   {
##     "home_tile":        Vector2i,       # where the home is NOW
##     "world_position":   Vector3,        # where to point the camera / anchor the dialogue
##     "species_id":       String,
##     "display_name":     String,         # from AnimalDefinition; data, not copy
##     "is_structure_home":bool,           # the home IS a building (a House). See the note below
##     "capacity":         int,            # capacity(h,S) as it now stands — may be 0
##     "population":       int,            # population(h,S)
##     "outcome":          "relocate" | "depart",
##     "individuals":      int,            # how many move (relocate: all) or leave (depart)
##     "destination_tile": Vector2i,       # relocation target, or Vector2i(-1,-1)
##     "copy_key":         String,         # which line the content pass supplies; see below
##   }
##
## `is_structure_home` is how the **decided villager-displacement voice** is selected without
## anyone special-casing a species. gdd.md decides that copy in the document ("a displaced
## villager family is never described as losing a home, only as finding one"), and the
## condition it actually keys off in the floor is structural: the home is a House. Nothing
## here knows what a villager is, which is the same rule `ResidentPresentation` uses to decide
## a House gets no den.
signal displacement_warned(warning: Dictionary)

## A home actually moved. Fires once per relocated home, after the warning.
signal resident_relocated(
	species_id: String, from_tile: Vector2i, to_tile: Vector2i, world_position: Vector3
)

## Residents actually left. Fires once per affected home, after the warning. `world_position`
## is where they were standing, so the view layer can play the leaving from the right place.
signal resident_departed(
	species_id: String, home_tile: Vector2i, individuals: int, world_position: Vector3
)


const OUTCOME_RELOCATE: String = "relocate"
const OUTCOME_DEPART: String = "depart"

## Copy keys the content pass fills. Named here so the UI is not guessing at strings and the
## content writer has a closed list. **No English lives in this file.**
const COPY_KEY_RELOCATE: String = "displacement.warn.relocate"
const COPY_KEY_DEPART: String = "displacement.warn.depart"
const COPY_KEY_DEPART_STRUCTURE: String = "displacement.warn.depart.structure"

## PLACEHOLDER — the human owns this. **No GDD or spec.md baseline exists**: gdd.md says only
## "relocation if a suitable spot exists (`capacity >= population` there)" and never bounds the
## search. 8 tiles is the low end of the #20 home-site radius band, chosen so a family
## relocates roughly within the neighbourhood the player was looking at rather than teleporting
## across the world — a relocation the player cannot see reads as a departure anyway.
##
## Cost note: this scan runs **only at settlement, and only for a home that is actually being
## displaced** — never on the edit path, never per frame, never for a home that is fine. It
## prunes every candidate no nearer than the best found so far, so once a near spot is found
## the remainder of the scan is a distance compare per tile and nothing more.
const RELOCATION_SEARCH_RADIUS_TILES: int = 8

## PROPOSED (2026-08-23) — max settled gestures actually resolved (`_settle()`'d) per
## `tick()` call. `_settle()` is expensive per gesture — a `CapacityEvaluator.capacity()`
## re-evaluation plus a relocation search (`RELOCATION_SEARCH_RADIUS_TILES`-square scan) per
## affected home — and `SettlementWindow.advance()` can return several gestures in one call
## when rapid terraforming across different neighbourhoods arms them all within roughly the
## same grace window, so they expire together. Settling all of them synchronously in one
## frame was a reported multi-second stall under WASM (Web export). Mirrors
## `HabitatSimulation.MAX_EVALUATIONS_PER_FRAME`'s existing bounded-drain pattern: gestures
## past the budget queue and settle on a later tick, still on the same GRACE_WINDOW_SECONDS
## timescale the player already expects.
const MAX_SETTLEMENTS_PER_TICK: int = 2

## PROPOSED (2026-08-23) — minimum real-time gap between settlement-drain batches.
## `tick()` runs every frame via `_process()`, with no throttle of its own — bounding the
## PER-CALL work (`MAX_SETTLEMENTS_PER_TICK` above) without also bounding how OFTEN that
## work runs still drains a large backlog on every single frame, back-to-back, with no gap
## for the browser to actually render/respond in between. Same total work as leaving it
## unbounded, just chunked into repeated stalls instead of one — reported as feeling WORSE,
## not better. Mirrors `TerrainChunkLod.LOD_REBUILD_CHECK_INTERVAL_SECONDS`'s throttle
## pattern: real elapsed seconds, not frame count, so pacing holds even when WASM makes
## individual frames slow.
const SETTLEMENT_DRAIN_INTERVAL_SECONDS: float = 0.5


## Telemetry, public so a headless check can assert on it instead of on log lines. Neither is
## a player-facing number and neither may ever be shown (Pillar 1's indicator test).
var settlements_resolved: int = 0
var warnings_raised: int = 0
var relocations: int = 0
var departures: int = 0

var _grid: WorldGrid = null
var _roster: SpeciesRoster = null
var _registry: HomeSiteRegistry = null
var _simulation: HabitatSimulation = null
var _presentation: ResidentPresentation = null
var _window: SettlementWindow = null
var _pending_settlements: Array[Dictionary] = []
var _drain_clock: float = 0.0


func attach(
	grid: WorldGrid,
	roster: SpeciesRoster,
	registry: HomeSiteRegistry,
	simulation: HabitatSimulation,
	presentation: ResidentPresentation = null,
	window: SettlementWindow = null
) -> void:
	_grid = grid
	_roster = roster
	_registry = registry
	_simulation = simulation
	_presentation = presentation
	_window = window if window != null else SettlementWindow.new()


func window() -> SettlementWindow:
	return _window


## True when no gesture is pending AND no already-settled gesture is still waiting for its
## turn under `MAX_SETTLEMENTS_PER_TICK` — an idle world satisfies both, and a world with no
## residents satisfies them permanently, because `on_edit()` opens nothing on empty land.
func is_idle() -> bool:
	return (_window == null or _window.is_idle()) and _pending_settlements.is_empty()


func pending_gestures() -> int:
	return 0 if _window == null else _window.pending_gestures()


# --- The edit path ----------------------------------------------------------------------

## Called by `WorldRoot` after **every** player edit — paint, place, or remove — once the
## world already reflects it. Mode-agnostic by construction: it takes a tile.
##
## Opens or restarts the window only for neighbourhoods **someone actually lives in**. An edit
## on empty land, or beside an empty House, names no neighbourhood and therefore opens no
## window at all: that is what keeps a settlement timer from being idle work.
func on_edit(tile: Vector2i) -> void:
	if _window == null or _registry == null:
		return
	_window.touch(tile, _occupied_neighbourhood_keys(tile))


## The identity of a home neighbourhood, for the window's merge/restart bookkeeping. Position
## plus species, because a site is per-species (two species on one tile are two homes).
static func neighbourhood_key(site: HomeSite) -> String:
	return "%d,%d,%s" % [site.position.x, site.position.y, site.species_id]


func _occupied_neighbourhood_keys(tile: Vector2i) -> Array[String]:
	var keys: Array[String] = []
	for site: HomeSite in _registry.sites_covering(tile):
		if site.population() > 0:
			keys.append(neighbourhood_key(site))
	return keys


# --- The arrival path (D-29 -> tier1-status.md row 6, "extend the arrival check") --------
#
# THE EDGE CASE. `HabitatSimulation`'s arrival predicate only ever asks whether the ARRIVING
# site still qualifies (`capacity >= population + 1`). Landing that arrival calls
# `HomeSiteRegistry.register()`/`claim()`, which rebuilds the WHOLE tile-exclusivity map
# (nearest site wins) — so a NEIGHBOURING home site can lose tiles it was counting on and
# fall below its own population, and nothing before this noticed: with several sites
# competing for the same ground, one could land at population 1 against capacity 0.
#
# THE FIX reuses the edit path's own mechanism rather than building a parallel one: every
# already-settled neighbour whose radius could reach the same tiles as the arriving site
# gets its settlement window armed exactly the way `on_edit()` arms it, so a real overshoot
# runs through the same warn-then-relocate-or-depart pipeline a player edit would trigger.
# The arriving site itself is excluded — `HabitatSimulation._land_or_drop()` already
# re-checked its own capacity at due time, immediately before the move-in that calls this.

## Called by `WorldRoot` once a resident has actually landed (`HabitatSimulation.
## resident_arrived`), after the registry already reflects the new/claimed site.
func on_arrival(tile: Vector2i, species_id: String) -> void:
	if _window == null or _registry == null:
		return
	var site: HomeSite = _registry.settled_site_at(tile, species_id)
	if site == null:
		return
	for other: HomeSite in _registry.sites():
		if other == site or other.population() <= 0:
			continue
		if not _reach_could_overlap(site, other):
			continue
		# Touched at the NEIGHBOUR's own tile, not the arriving site's — `_affected_homes()`
		# re-derives sites from the gesture's tiles via `sites_covering()`, and a site always
		# covers its own position, so this is guaranteed to find `other` again at settlement
		# regardless of exactly which tiles changed hands.
		_window.touch(other.position, [neighbourhood_key(other)])


## True when two home sites' tile-counting reach could plausibly touch the same tile — the
## only geometry under which `HomeSiteRegistry.rebuild_ownership()`'s nearest-site
## reassignment (allocated over each site's `radius`) could move a tile from one site's own
## acreage (counted over its `capacity_radius`, which may differ — D-27 #1) to the other's.
## Deliberately generous rather than exact: over-including a neighbour costs one armed
## window that resolves to nothing at settlement; under-including one reproduces the defect.
func _reach_could_overlap(a: HomeSite, b: HomeSite) -> bool:
	var reach: int = _reach_of(a) + _reach_of(b)
	return a.distance_squared_to(b.position) <= reach * reach


func _reach_of(site: HomeSite) -> int:
	var reach: int = site.radius
	if _roster != null:
		var species: AnimalDefinition = _roster.by_id(site.species_id)
		if species != null:
			reach = maxi(reach, species.effective_capacity_radius())
	return reach


# --- The load path (D-32) ----------------------------------------------------------------
#
# THE DEFECT THIS EXISTS FOR. The grace window gates the IRREVERSIBLE half of a displacement —
# the warning's final trigger and any relocation or departure. Only `on_edit()` and
# `on_arrival()` ever open a gesture, and a restore reaches NEITHER: `WorldSnapshot.apply()`
# ends at `mark_all_dirty()`, which re-derives capacity arithmetic but opens no window. So a
# gesture that was open when the file was written was silently cancelled by the reload, and the
# home sat PERMANENTLY over capacity until some unrelated later edit near it happened to re-arm
# a window — at which point the displacement finally fired with no context for the child.
# Reproduced through the ordinary `exit_to_menu` path: make the displacing edit, read the
# warning, press Leave inside the 12 s window.
#
# THE RULING (D-32, human, 2026-08-02) is Option A: **re-arm from world state, do not persist
# the gesture.** No schema is added, so nothing about the pre-edit world is recorded and
# `SettlementWindow`'s "the revert rule is arithmetic, not a record" property stays true across
# a reload. The child gets a fresh 12 seconds, which the design document already calls "strictly
# more forgiving than never having quit". It also self-heals a home that is over capacity AT THE
# MOMENT OF THE LOAD, from any cause, rather than only from the gesture that happened to be
# pending at capture.
#
# WHAT IT DOES NOT COVER, stated because an earlier version of this comment credited it wrongly:
# a RESTORED ARRIVAL THAT LANDS AFTER THE RELOAD is not this function's doing and cannot be — it
# runs once, at load, before any arrival lands. That case goes through `WorldRoot`'s
# `resident_arrived` -> `on_arrival()` wiring, which pre-dates D-32 and is unchanged by it.

## Opens a fresh settlement gesture for every home that is already over capacity. Called once,
## at the end of `WorldSnapshot.apply()`. Returns how many homes were armed.
##
## **THE ZERO IS THE POINT.** A healthy world — every home within capacity, residents or not —
## arms NOTHING here, so `pending_gestures()` is still 0 after a load and a settlement timer is
## still not idle work. gdd.md -> Performance and this file's own header both rest on that.
##
## Cost is one capacity read per EXISTING home site (single digits in a real world), not the
## full-world candidate sweep of tiles x roster.
##
## **NOT IDEMPOTENT, AND DELIBERATELY SO.** A second call on a still-over-capacity world re-touches
## the window and RESTARTS the 12 s countdown — the behaviour every other `touch()` caller has, and
## the one gdd.md rules deliberately uncapped for `on_edit()`/`on_arrival()`. Special-casing the
## load path would give `touch()` two meanings. It is safe because there is exactly one call site:
## the end of `WorldSnapshot.apply()`, once per load. A second call site would silently extend a
## child's grace window, so add one only with that in mind.
func reconcile_after_load() -> int:
	if _window == null or _registry == null or _roster == null or _grid == null:
		return 0
	var armed: int = 0
	for site: HomeSite in _registry.sites():
		if site.population() <= 0:
			continue
		var species: AnimalDefinition = _roster.by_id(site.species_id)
		if species == null:
			continue
		var capacity: int = CapacityEvaluator.capacity(
			_grid, _registry, site.position, species, site
		)
		# THE TRIGGER, the same strict `capacity < population` with no margin that `_settle()`
		# re-checks at the end of the window.
		if site.population() <= capacity:
			continue
		# Touched at the site's OWN tile with its OWN key, exactly as `on_arrival()` does, and
		# for the reason spelled out there: `_affected_homes()` re-derives sites from the
		# gesture's tiles via `sites_covering()`, and a site always covers its own position.
		_window.touch(site.position, [neighbourhood_key(site)])
		armed += 1
	return armed


# --- Settlement -------------------------------------------------------------------------

func _process(delta: float) -> void:
	tick(delta)


## Advances the window. Public so a headless run can settle a whole gesture in one call
## instead of waiting out the grace window in real frames — the same shape as
## `HabitatSimulation.tick()` and `WoodLedger.tick()`.
func tick(delta: float) -> void:
	# Window countdown always advances in real time — only the DRAINING of what's already
	# settled is throttled below, never the timing that decides WHEN something settles.
	if _window != null and not _window.is_idle():
		_pending_settlements.append_array(_window.advance(delta))
	if _pending_settlements.is_empty():
		_drain_clock = 0.0
		return  # THE ZERO: no pending gesture, no settled backlog, no work.

	# THROTTLED, LIKE TerrainChunkLod's update_camera() recheck: bounding the per-call work
	# (below) without also bounding how OFTEN a call actually drains still processes a large
	# backlog on every single frame back-to-back — same total cost, no gap for the browser to
	# breathe in between. Real elapsed seconds, so pacing holds even when WASM makes
	# individual frames slow.
	_drain_clock += delta
	if _drain_clock < SETTLEMENT_DRAIN_INTERVAL_SECONDS:
		return
	_drain_clock = 0.0

	# BOUNDED, LIKE HabitatSimulation's DRAIN: several gestures can expire on the same tick
	# (rapid terraforming across different neighbourhoods within one grace window) — settling
	# all of them synchronously here was the reported multi-second stall. Only up to
	# MAX_SETTLEMENTS_PER_TICK actually resolve per drain; the rest wait for the next one.
	var done: int = 0
	while done < MAX_SETTLEMENTS_PER_TICK and not _pending_settlements.is_empty():
		_settle(_pending_settlements.pop_front())
		done += 1


func _settle(gesture: Dictionary) -> void:
	settlements_resolved += 1
	var homes: Array[Dictionary] = _affected_homes(gesture)
	if homes.is_empty():
		# THE REVERT CASE, and it needs no special handling: the world settled with every
		# home still supported, so nothing was displaced and there is nothing to say.
		return

	var species_ids: Array[String] = []
	for home: Dictionary in homes:
		var sid: String = home["species_id"]
		if not species_ids.has(sid):
			species_ids.append(sid)

	# WARNING FIRST. Emitted before a single resident moves, and never suppressed — the
	# consequences below run whether or not anything is listening.
	warnings_raised += 1
	displacement_warned.emit({
		"gesture_id": gesture.get("id", 0),
		"homes": homes,
		"species_ids": species_ids,
		"read_aloud": true,
	})

	# ACTING AFTER.
	for home: Dictionary in homes:
		_apply(home)


## Every home this settled gesture displaces, each already resolved to relocate-or-depart.
##
## Recomputed from the gesture's TILES rather than from a list captured at edit time, so a
## home that arrived, moved or vanished during the window is handled correctly and a stale
## record can never drive a warning.
func _affected_homes(gesture: Dictionary) -> Array[Dictionary]:
	var homes: Array[Dictionary] = []
	if _registry == null or _roster == null:
		return homes
	var seen: Array[HomeSite] = []

	for tile: Vector2i in SettlementWindow.tiles_of(gesture):
		for site: HomeSite in _registry.sites_covering(tile):
			if seen.has(site) or site.population() <= 0:
				continue
			seen.append(site)
			var species: AnimalDefinition = _roster.by_id(site.species_id)
			if species == null:
				continue
			var population: int = site.population()
			var capacity: int = CapacityEvaluator.capacity(
				_grid, _registry, site.position, species, site
			)
			# THE TRIGGER. Strict, no margin, and 0 is an ordinary value here.
			if capacity >= population:
				continue
			homes.append(_describe(site, species, capacity, population))
	return homes


## One home's entry in the warning, including which of the two gentle outcomes it faces.
## gdd.md -> "Two gentle outcomes, **in order**: relocation if a suitable spot exists
## (`capacity >= population` there) ... otherwise moving away."
func _describe(
	site: HomeSite, species: AnimalDefinition, capacity: int, population: int
) -> Dictionary:
	var is_structure: bool = site.is_structure()
	var destination: Vector2i = _find_relocation(site, species, population)
	var relocating: bool = destination != Vector2i(-1, -1)

	var copy_key: String = COPY_KEY_RELOCATE
	if not relocating:
		copy_key = COPY_KEY_DEPART_STRUCTURE if is_structure else COPY_KEY_DEPART

	return {
		"home_tile": site.position,
		"world_position": _world_of(site.position),
		"species_id": site.species_id,
		"display_name": species.display_name,
		"is_structure_home": is_structure,
		"capacity": capacity,
		"population": population,
		"outcome": OUTCOME_RELOCATE if relocating else OUTCOME_DEPART,
		# A relocation moves the whole home; a departure sheds only the overflow, so a
		# neighbourhood that still supports two of three keeps two. `capacity` is clamped
		# because it is allowed to be 0 and never below.
		"individuals": population if relocating else population - maxi(capacity, 0),
		"destination_tile": destination,
		"copy_key": copy_key,
		"_site": site,
	}


func _apply(home: Dictionary) -> void:
	var site: HomeSite = home["_site"]
	if home["outcome"] != OUTCOME_RELOCATE:
		_depart(site, int(home["individuals"]))
		return

	# Destinations were chosen for the whole gesture before any of them moved, so an earlier
	# relocation in this same settlement could have taken this one's spot. Re-search if so —
	# but **never downgrade to a departure here**, because the warning the player already read
	# said "moves", and a warning is not allowed to be contradicted by what follows it.
	var destination: Vector2i = home["destination_tile"]
	if _registry != null and _registry.any_site_at(destination):
		var species: AnimalDefinition = _roster.by_id(site.species_id)
		var retry: Vector2i = _find_relocation(site, species, site.population())
		if retry != Vector2i(-1, -1):
			destination = retry
	_relocate(site, destination)


# --- Relocation -------------------------------------------------------------------------

## The nearest spot that supports the WHOLE household, or `Vector2i(-1, -1)` for none.
##
## **A structure home cannot move**, because the home *is* the building: a House with a family
## in it relocates only into another House that would have them. That is not a species rule —
## it falls out of what a structure home site is — and it is why the floor's likeliest
## displacement (a villager family whose field was cleared) usually ends in a departure, which
## is precisely the case gdd.md decides the copy for in advance.
func _find_relocation(site: HomeSite, species: AnimalDefinition, population: int) -> Vector2i:
	if _grid == null or _registry == null:
		return Vector2i(-1, -1)
	if site.is_structure():
		return _find_vacant_structure(site, species, population)

	var best: Vector2i = Vector2i(-1, -1)
	var best_distance: int = -1
	var r: int = RELOCATION_SEARCH_RADIUS_TILES
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var d_squared: int = dx * dx + dz * dz
			if d_squared == 0 or d_squared > r * r:
				continue
			if best_distance >= 0 and d_squared >= best_distance:
				continue  # already have something nearer
			var candidate: Vector2i = site.position + Vector2i(dx, dz)
			if not _grid.tile_in_bounds(candidate):
				continue
			if _registry.any_site_at(candidate) or _grid.is_occupied(candidate.x, candidate.y):
				continue  # somebody's home already; crowding home sites buys nothing
			# `site` is passed as `self_site` because the home is MOVING: the tiles it
			# currently owns are its own to take with it.
			if CapacityEvaluator.capacity(_grid, _registry, candidate, species, site) < population:
				continue
			best = candidate
			best_distance = d_squared
	return best


## A structure home's only relocation: another building of the right kind, standing empty,
## that would support the whole family.
func _find_vacant_structure(
	site: HomeSite, species: AnimalDefinition, population: int
) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_distance: int = -1
	var reach: int = RELOCATION_SEARCH_RADIUS_TILES * RELOCATION_SEARCH_RADIUS_TILES
	for other: HomeSite in _registry.sites():
		if other == site or not other.is_vacant() or not other.serves(species):
			continue
		var d_squared: int = site.distance_squared_to(other.position)
		if d_squared > reach:
			continue
		if best_distance >= 0 and d_squared >= best_distance:
			continue
		if CapacityEvaluator.capacity(_grid, _registry, other.position, species, other) < population:
			continue
		best = other.position
		best_distance = d_squared
	return best


func _relocate(site: HomeSite, destination: Vector2i) -> void:
	var from: Vector2i = site.position
	var species_id: String = site.species_id

	# Trigger 4, while the site still stands at its OLD position: the old neighbourhood's
	# counts really are changing, and the exclusivity map has to be told before the move.
	if _simulation != null:
		_simulation.on_resident_departed(site)

	# "gone if the home relocates" (gdd.md -> Level & world design) — the den at the old spot.
	if _presentation != null:
		_presentation.release(site)

	var target: HomeSite = _registry.vacant_site_at(destination)
	if target != null and target.is_structure():
		# Moving into a standing building: the family takes over that home site, and the one
		# it left goes back to being an empty House (or disappears, if it was a den).
		_registry.claim(target, species_id, site.radius)
		var moving: Array[Node3D] = site.residents.duplicate()
		site.residents = []
		target.residents = moving
		_registry.release(site, _grid != null and _grid.get_building(from.x, from.y) != null)
		site = target
	else:
		_registry.relocate(site, destination)

	var world_position: Vector3 = _world_of(site.position)
	for resident: Node3D in site.residents:
		if resident != null and is_instance_valid(resident):
			resident.position = world_position
		if _presentation != null:
			_presentation.present(resident, site)

	relocations += 1
	# Trigger 3, now that the site stands at its new position.
	if _simulation != null:
		_simulation.on_resident_arrived(site)
	resident_relocated.emit(species_id, from, site.position, world_position)


# --- Departure --------------------------------------------------------------------------

## "otherwise **moving away**, a visible departure framed as finding a home elsewhere —
## Species Hosted and the Field Guide entry stay permanent."
##
## The permanence is structural: `HomeSiteRegistry._ever_hosted` has no removal path, so
## nothing here could erase the record even by mistake.
func _depart(site: HomeSite, individuals: int) -> void:
	var count: int = clampi(individuals, 0, site.population())
	if count <= 0:
		return
	var species_id: String = site.species_id
	var world_position: Vector3 = _world_of(site.position)
	var home_tile: Vector2i = site.position

	for _i in count:
		var resident: Node3D = site.residents.pop_back()
		if resident != null and is_instance_valid(resident):
			resident.queue_free()

	if site.population() == 0:
		if _presentation != null:
			_presentation.release(site)
		# A House left standing stays a home site, ready for the next family. A House the
		# player just removed does not — `structure_remains` reads the world, not the record.
		var structure_remains: bool = (
			_grid != null and _grid.get_building(home_tile.x, home_tile.y) != null
		)
		_registry.release(site, structure_remains)

	departures += 1
	if _simulation != null:
		_simulation.on_resident_departed(site)  # trigger 4
	resident_departed.emit(species_id, home_tile, count, world_position)


func _world_of(tile: Vector2i) -> Vector3:
	return Vector3.ZERO if _grid == null else _grid.tile_to_world(tile.x, tile.y)
