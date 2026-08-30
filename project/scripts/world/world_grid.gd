class_name WorldGrid
extends Node
## The world's tile data — Tier 1 row 3 (Terraform), thin form.
##
## Replaces the pilot-1 `grid_manager.gd` spike, which hardcoded a 16x16 grid and a
## one-way grass->forest recolor. Nothing here hardcodes a terrain list or a habitat tag:
## every terrain comes from `TerrainDefinition.load_all()`.
##
## WHAT A TILE HOLDS (spec.md -> Shared Patterns, the v1 tag model -> D-25):
##   * its `terrain_id`
##   * an optional reference to the building occupying it (`PlaceableDefinition` + origin)
## and NOTHING ELSE. In particular **a tile does not store tags.** A tile's tag set is a
## pure function of what occupies it, so it is DERIVED on read by `get_tile_tags()` — from
## the building's `emitted_tags` where a footprint suppresses the ground, otherwise from
## the terrain's. Caching tags on the tile would make the cache, not the data, the source
## of truth, and the first emission change would silently rot it.
##
## This node holds data only. Visuals and colliders are `TerrainView`'s job; cost, Wood and
## placement rules are `project/scripts/economy/`'s; qualification is
## `project/scripts/simulation/`'s. `WorldRoot` is the facade that wires the four together.

## Emitted whenever a tile's terrain or building occupancy changes. Carries grid
## coordinates, not a world position — the UI and the view layer each map it their own way.
signal tile_changed(x: int, z: int)

## TIER 1 ROW 13 (MIST). Emitted once per `grow()` call that actually added tiles, carrying
## every newly created coordinate. Deliberately separate from `tile_changed`: that signal fires
## per-tile against an ALREADY-SIZED grid (`TerrainView`'s per-tile refresh assumes the tile's
## body already exists), which a brand-new tile is not. Listeners that need to build something
## for new land connect here; `tile_changed` is never emitted for these tiles, and neither is
## any of the four habitat-qualification triggers — see `grow()`'s own header for why that
## silence is load-bearing (D-22).
signal grown(new_tiles: Array[Vector2i])


## DECIDED 2026-08-01 (-> D-29). 36x36, per gdd.md -> World Structure's stated "~36x36"
## baseline. The growth-to-cap half (gdd.md's "~128x128 performance ceiling") is row 13
## (mist) and IS built — see `grow()` — via `WorldRoot._maybe_unfurl_mist()`, which grows this
## grid up to `WorldRoot.MAX_SAVED_WORLD_TILES` (row 1's own bound, decided together with row
## 13's cap at D-38 so the two numbers cannot drift apart).
const DEFAULT_WIDTH: int = 36
const DEFAULT_DEPTH: int = 36

## Person-scale: one tile is one world unit (gdd.md -> Level & world design, "a villager
## stands ~1 tile tall"). Matches the grey-box tile slabs under assets/placeholder/.
const TILE_SIZE: float = 1.0

## Visual thickness of a tile slab. The grey-box scenes put their origin at the tile's TOP
## surface, so anything standing on a tile sits at y = 0.
const TILE_HEIGHT: float = 0.2

## The terrain every tile starts as.
##
## `wild_grass`, not `grass` — REVERSED 2026-08-01 (-> D-29), overriding the implementer's
## original pick of `grass` for gdd.md's "open meadow, not empty lot" read. The ruling: the
## player's starting world should read exactly like freshly-revealed mist land, tag-inert
## until the player acts on it (wild grass is what the MIST reveals, row 13, and emits
## nothing; true grass emits `open_grass`). This puts wild_grass's still-unresolved look-pass
## (Open Question #29 -- "must read as something to claim without reading as broken") on the
## very first frame the player sees, not just at the mist's edge -- a consequence surfaced by
## D-29, not resolved here. The authored varied starting world is #10.
const START_TERRAIN_ID: String = "wild_grass"

## The terrain the free-Forest recovery guarantee is about (gdd.md -> Economy: "Forest is
## free to paint and passively produces Wood, so a player at zero can always paint, wait,
## and build again"). Named here because two systems key off it — the guarantee assertion
## below and the economy's passive accrual.
const FOREST_TERRAIN_ID: String = "forest"


var width: int = DEFAULT_WIDTH
var depth: int = DEFAULT_DEPTH

## Flat row-major stores, indexed `x * depth + z`. Flat rather than nested arrays because
## the capacity evaluator's hot path is one pass over a rectangle of tiles.
var _terrain_ids: PackedStringArray = PackedStringArray()
var _building_defs: Array = []          # PlaceableDefinition or null, per tile
var _building_origins: Array[Vector2i] = []  # footprint anchor, or Vector2i(-1, -1)

var _terrain_by_id: Dictionary = {}     # String id -> TerrainDefinition
var _terrain_defs: Array[TerrainDefinition] = []
var _forest_tile_count: int = 0

## TIER 1 ROW 13 (MIST). Set once, in `build()`, and NEVER recomputed from `width`/`depth`
## again — see `grow()`'s header for why a live recomputation would be a visible bug (every
## already-placed tile sliding half a growth-band sideways the instant the mist unfurls).
var _origin_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	if _terrain_defs.is_empty():
		build(TerrainDefinition.load_all(), DEFAULT_WIDTH, DEFAULT_DEPTH)


## Builds (or rebuilds) the grid from a terrain roster. Every tile starts as
## `START_TERRAIN_ID`. Separated from `_ready()` so tests and tools can drive it directly.
func build(terrain_defs: Array, new_width: int = DEFAULT_WIDTH, new_depth: int = DEFAULT_DEPTH) -> void:
	width = max(1, new_width)
	depth = max(1, new_depth)

	_terrain_defs = []
	_terrain_by_id = {}
	for entry in terrain_defs:
		var def: TerrainDefinition = entry as TerrainDefinition
		if def == null:
			continue
		_terrain_defs.append(def)
		_terrain_by_id[TerrainDefinition.normalize_id(def.id)] = def

	_assert_free_forest_guarantee()

	_origin_offset = Vector2(-(width - 1) * TILE_SIZE * 0.5, -(depth - 1) * TILE_SIZE * 0.5)

	var count: int = width * depth
	_terrain_ids = PackedStringArray()
	_terrain_ids.resize(count)
	_building_defs = []
	_building_defs.resize(count)
	_building_origins = []
	_building_origins.resize(count)
	for i in count:
		_terrain_ids[i] = START_TERRAIN_ID
		_building_defs[i] = null
		_building_origins[i] = Vector2i(-1, -1)
	_forest_tile_count = 0


# --- Mist reveal (Tier 1 row 13, D-38) ---------------------------------------------------

## Grows the grid to at least `requested_width` x `requested_depth`, clamped to
## `WorldRoot.MAX_SAVED_WORLD_TILES` (the D-38 world cap, read from row 1's own constant rather
## than a second copy — see `mist_reveal.gd`'s header). Never shrinks: either argument below
## the current size is simply ignored for that axis. Returns every newly created tile
## coordinate, or an empty array when nothing changed (already at or above the request, or
## already at the cap).
##
## **APPEND-ONLY, BY DESIGN.** Tile `(0, 0)` never moves and no existing tile is ever
## renumbered — growth only ever RAISES `width`/`depth`. That is what lets `WorldSnapshot`'s
## existing `range(grid.width) x range(grid.depth)`, 0-based save/restore loop
## (`project/scripts/save/`, outside this row's reserved directory) keep working with zero
## changes, and what keeps every tile coordinate a `HomeSite`, a removal receipt, or a save
## file already holds valid and correctly positioned forever — nothing already on the grid is
## ever reindexed or shifted in world space (`_origin_offset` is fixed at `build()` time, see
## its own header).
##
## **THE DISCLOSED TRADE-OFF:** only the high-x ("east") and high-z ("north") edges can ever
## recede. The grid's low corner, `x == 0` / `z == 0`, is this thin form's permanent map
## boundary, not a mist edge — reindexing it to grow the OTHER way would mean renumbering every
## existing tile, which is exactly what the paragraph above rules out without reaching into
## `HomeSiteRegistry` / `RemovalLedger` (both outside this row's directory). Flagged for the
## human under Proposals, not hidden.
##
## **NEVER A QUALIFICATION TRIGGER (D-22).** This does not call `set_terrain()` — it writes
## straight into the arrays and emits `grown`, never `tile_changed`, so nothing here can reach
## `HabitatSimulation`'s four triggers by accident. `WorldRoot._maybe_unfurl_mist()` is the only
## caller, and it never calls `simulation.on_terraform()` / `on_building_changed()` for a
## reveal either.
func grow(requested_width: int, requested_depth: int, world_seed: int) -> Array[Vector2i]:
	var new_width: int = clampi(requested_width, width, WorldRoot.MAX_SAVED_WORLD_TILES)
	var new_depth: int = clampi(requested_depth, depth, WorldRoot.MAX_SAVED_WORLD_TILES)
	if new_width == width and new_depth == depth:
		return []

	var old_width: int = width
	var old_depth: int = depth
	var old_terrain: PackedStringArray = _terrain_ids
	var old_buildings: Array = _building_defs
	var old_origins: Array[Vector2i] = _building_origins

	width = new_width
	depth = new_depth
	var count: int = width * depth
	_terrain_ids = PackedStringArray()
	_terrain_ids.resize(count)
	_building_defs = []
	_building_defs.resize(count)
	_building_origins = []
	_building_origins.resize(count)

	var new_tiles: Array[Vector2i] = []
	for x in width:
		for z in depth:
			var i: int = _index(x, z)
			if x < old_width and z < old_depth:
				var old_i: int = x * old_depth + z
				_terrain_ids[i] = old_terrain[old_i]
				_building_defs[i] = old_buildings[old_i]
				_building_origins[i] = old_origins[old_i]
			else:
				# The revealed terrain is always wild grass (`MistReveal`'s own header explains
				# why), so it can never be Forest — no `_forest_tile_count` bookkeeping needed.
				_terrain_ids[i] = MistReveal.reveal_terrain_id(world_seed, x, z)
				_building_defs[i] = null
				_building_origins[i] = Vector2i(-1, -1)
				new_tiles.append(Vector2i(x, z))

	grown.emit(new_tiles)
	return new_tiles


# --- The free-Forest recovery guarantee -------------------------------------------------
# gdd.md -> Scope: "Pillar invariants don't tier ... if resources ship, the free-Forest
# no-dead-end guarantee ships". It is asserted here rather than described in a comment,
# because a comment cannot fail a build. If Forest ever stops existing or stops being free,
# a player at zero Wood has no path back and the game acquires a dead end — a Pillar 1
# violation that would otherwise surface only as a stuck child.

## True when Forest exists in the terrain roster and is free to paint. Public so a test can
## assert the invariant directly rather than inferring it from a log line.
func free_forest_guarantee_holds() -> bool:
	var forest: TerrainDefinition = terrain_definition(FOREST_TERRAIN_ID)
	return forest != null and forest.cost == TerrainDefinition.FREE_COST


func _assert_free_forest_guarantee() -> void:
	var forest: TerrainDefinition = terrain_definition(FOREST_TERRAIN_ID)
	if forest == null:
		push_error("free-Forest recovery guarantee BROKEN: no `%s` TerrainDefinition. A player at zero Wood would have no way back (gdd.md -> Economy, Pillar 1)." % FOREST_TERRAIN_ID)
	elif forest.cost != TerrainDefinition.FREE_COST:
		push_error("free-Forest recovery guarantee BROKEN: `%s` costs %d Wood, must be free (gdd.md -> Economy, Pillar 1)." % [FOREST_TERRAIN_ID, forest.cost])
	assert(free_forest_guarantee_holds(),
		"free-Forest recovery guarantee broken — see push_error above.")


# --- Lookups ----------------------------------------------------------------------------

func in_bounds(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < width and z < depth


func tile_in_bounds(tile: Vector2i) -> bool:
	return in_bounds(tile.x, tile.y)


func _index(x: int, z: int) -> int:
	return x * depth + z


## Every loaded terrain definition, in `load_all()` order. The palette the UI reads.
func terrain_definitions() -> Array[TerrainDefinition]:
	return _terrain_defs


## The definition for a terrain id, or null. Ids are normalized, so a hand-authored
## `"Wild Grass"` still resolves.
func terrain_definition(terrain_id: String) -> TerrainDefinition:
	return _terrain_by_id.get(TerrainDefinition.normalize_id(terrain_id), null) as TerrainDefinition


func get_terrain_id(x: int, z: int) -> String:
	if not in_bounds(x, z):
		return ""
	return _terrain_ids[_index(x, z)]


func get_terrain(x: int, z: int) -> TerrainDefinition:
	return terrain_definition(get_terrain_id(x, z))


## The `PlaceableDefinition` occupying this tile, or null. This is the tile's "optional
## reference to the building occupying it" — every footprint tile holds it, not just the
## anchor, so tag derivation is a single lookup with no footprint walk.
func get_building(x: int, z: int) -> PlaceableDefinition:
	if not in_bounds(x, z):
		return null
	return _building_defs[_index(x, z)] as PlaceableDefinition


## The anchor tile of the building occupying this tile, or Vector2i(-1, -1).
func get_building_origin(x: int, z: int) -> Vector2i:
	if not in_bounds(x, z):
		return Vector2i(-1, -1)
	return _building_origins[_index(x, z)]


func is_occupied(x: int, z: int) -> bool:
	return get_building(x, z) != null


## THE TAG DERIVATION (spec.md -> Shared Patterns, -> D-25). A tile's tags are a pure
## function of what occupies it: the building's `emitted_tags` where a footprint suppresses
## the ground (buildings.md -> What a Building Is), otherwise the terrain's.
##
## Returns the definition's own array by reference for speed — the capacity pass runs this
## once per tile in radius per evaluation. **Callers must not mutate the result.**
func get_tile_tags(x: int, z: int) -> Array[String]:
	var building: PlaceableDefinition = get_building(x, z)
	if building != null:
		return building.emitted_tags
	var terrain: TerrainDefinition = get_terrain(x, z)
	if terrain == null:
		return []
	return terrain.emitted_tags


## Forest tiles currently on the map, maintained incrementally so the economy never scans
## the world. A building footprint suppresses the tile's terrain tags but does not remove
## the terrain, and Forest is not in the House's `allowed_terrain`, so this counts terrain.
func forest_tile_count() -> int:
	return _forest_tile_count


# --- Mutation (raw; cost and validation live in project/scripts/economy/) ----------------

## Sets a tile's terrain with no cost check. Returns false when nothing changed.
## `WorldRoot.paint_tile()` is the checked public entry point — call that, not this.
func set_terrain(x: int, z: int, terrain_id: String) -> bool:
	if not in_bounds(x, z):
		return false
	var def: TerrainDefinition = terrain_definition(terrain_id)
	if def == null:
		return false
	var normalized: String = TerrainDefinition.normalize_id(def.id)
	var i: int = _index(x, z)
	if _terrain_ids[i] == normalized:
		return false
	if _terrain_ids[i] == FOREST_TERRAIN_ID:
		_forest_tile_count -= 1
	if normalized == FOREST_TERRAIN_ID:
		_forest_tile_count += 1
	_terrain_ids[i] = normalized
	tile_changed.emit(x, z)
	return true


## Marks every tile of a footprint as occupied by `def`, anchored at `origin`. No cost or
## eligibility check — `BuildingPlacement.place()` is the checked entry point.
func set_building(origin: Vector2i, def: PlaceableDefinition) -> bool:
	if def == null:
		return false
	for tile: Vector2i in footprint_tiles(origin, def):
		if not tile_in_bounds(tile):
			return false
	for tile: Vector2i in footprint_tiles(origin, def):
		var i: int = _index(tile.x, tile.y)
		_building_defs[i] = def
		_building_origins[i] = origin
		tile_changed.emit(tile.x, tile.y)
	return true


## Clears the building anchored at `origin`, freeing its whole footprint. Returns false when
## nothing was there. No refund logic — `WorldRoot.remove_at()` is the checked entry point and
## `RemovalLedger` owns the arithmetic.
##
## **The terrain under a footprint is never destroyed**, only suppressed while occupied
## (gdd.md -> Habitat Suitability: "A tile under a building footprint stops emitting its
## terrain tags **while occupied**"), so removal restores the ground by doing nothing to it.
## That is what makes a Build removal and a Terraform revert the same gesture to the player.
func clear_building(origin: Vector2i) -> bool:
	var def: PlaceableDefinition = get_building(origin.x, origin.y)
	if def == null:
		return false
	for tile: Vector2i in footprint_tiles(origin, def):
		if not tile_in_bounds(tile):
			continue
		if get_building_origin(tile.x, tile.y) != origin:
			continue
		var i: int = _index(tile.x, tile.y)
		_building_defs[i] = null
		_building_origins[i] = Vector2i(-1, -1)
		tile_changed.emit(tile.x, tile.y)
	return true


## The tiles a footprint anchored at `origin` would cover. 1x1 in the Tier 1 floor form;
## the 2x2 full form (#18) needs no change here.
static func footprint_tiles(origin: Vector2i, def: PlaceableDefinition) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if def == null:
		return out
	var size: Vector2i = def.footprint
	for dx in max(1, size.x):
		for dz in max(1, size.y):
			out.append(origin + Vector2i(dx, dz))
	return out


# --- Coordinate mapping -----------------------------------------------------------------
# The grid is centered on the world origin AT `build()` TIME, matching the pilot-1 spike's
# framing so the existing camera and the shipped spawn tests keep their bearings. A later
# `grow()` call (Tier 1 row 13) does not re-center: `_origin_offset` is fixed once, so growth
# only ever extends the grid outward past its current high edge, never re-centers it.

func world_origin_offset() -> Vector2:
	return _origin_offset


## The world position of a tile's top surface center.
func tile_to_world(x: int, z: int) -> Vector3:
	var off: Vector2 = world_origin_offset()
	return Vector3(off.x + x * TILE_SIZE, 0.0, off.y + z * TILE_SIZE)


## The tile a world position falls on. May be out of bounds; check with `tile_in_bounds()`.
func world_to_tile(world_position: Vector3) -> Vector2i:
	var off: Vector2 = world_origin_offset()
	return Vector2i(
		int(round((world_position.x - off.x) / TILE_SIZE)),
		int(round((world_position.z - off.y) / TILE_SIZE))
	)
