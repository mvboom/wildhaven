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


## Bumped by every writer that changes what a tile emits. **Monotonic and never reset** — it
## is only ever compared for equality against a value someone cached earlier, never read as a
## count of anything.
##
## This exists for `RoamRegion` (game-design/roaming.md §4.4), which caches a set of tiles and
## needs to know in O(1) that the cache is stale. The bump lives in `_refresh_tag_mask()`
## rather than in each writer because that function's own doc already promises it is "called by
## every writer that changes what a tile holds" — making it the one seam a new writer cannot
## forget. `build()` (both its uniform-fill and mix-fill branches, in one bump after the
## `if`/`else` so a rebuild counts once, not per tile) and `grow()` write `_tile_tag_masks`
## directly rather than through `_refresh_tag_mask()`, so they bump explicitly instead.
var terrain_version: int = 0

var width: int = DEFAULT_WIDTH
var depth: int = DEFAULT_DEPTH

## Flat row-major stores, indexed `x * depth + z`. Flat rather than nested arrays because
## the capacity evaluator's hot path is one pass over a rectangle of tiles.
var _terrain_ids: PackedStringArray = PackedStringArray()

## PER-TILE CAPTURED STYLE, one entry per tile in lockstep with `_terrain_ids` (2026-09-08,
## human ruling: "when you switch the type of tree, ALL trees switch to that tree" — it must
## not). A style id here is the one the tile was PAINTED with; `WorldRoot.paint_tile()` stamps
## it from the style default current at that moment, and nothing rewrites it afterwards. Empty
## means "no captured style", which resolves exactly as it always did — `pick_variant()`'s
## per-tile hash (D-42).
##
## This is what replaced D-54's world-wide look setting (-> D-57), and after D-58 it is the ONLY
## thing deciding a tile's look. Under D-54 a style default was read at RENDER time, so changing
## it restyled ground already placed; it is read at PAINT time and stored now, so a style behaves
## like a brush — you pick what to put down and what you put down stays.
##
## NOT part of the tag mask and deliberately outside "THE ONE RULE" below: a style is purely
## cosmetic and emits nothing, so a write here never needs `_refresh_tag_mask()`.
var _tile_styles: PackedStringArray = PackedStringArray()

## PER-BUILDING CAPTURED STYLE, keyed by footprint ORIGIN rather than stored per tile — a
## building already anchors everything else it owns at its origin (`_building_origins`), and a
## footprint has one look, not one per covered tile. Same paint-time capture rule as
## `_tile_styles`; cleared by `clear_building()` so a freed origin cannot hand its look to
## whatever is built there next.
var _building_styles: Dictionary = {}   # Vector2i origin -> String style id
var _building_defs: Array = []          # PlaceableDefinition or null, per tile
var _building_origins: Array[Vector2i] = []  # footprint anchor, or Vector2i(-1, -1)

## Per-tile habitat-tag BITMASK, one bit per `AnimalDefinition.HABITAT_TAGS` entry, kept in
## lockstep with `_terrain_ids` / `_building_defs` by `_refresh_tag_mask()`.
##
## WHY IT EXISTS. `get_tile_tags()` is a String round trip — a `String` out of a
## `PackedStringArray`, then a `Dictionary` hash to resolve the `TerrainDefinition` — and the
## capacity evaluator runs it once per tile in radius, per tier, per species. Profiled at the
## 128x128 cap that single call was 56% of a full-roster evaluation. A tile's tags are a pure
## function of what occupies it (-> D-25), so the answer is derivable once per EDIT rather
## than once per READ, which is the same incremental-index bargain `_forest_tile_count` and
## `HomeSiteRegistry._structure_by_position` already make.
##
## The vocabulary is closed and human-gated, and `TerrainDefinition.validate()` /
## `PlaceableDefinition.validate()` both reject an `emitted_tags` entry outside it, so every
## shipped tag has a bit and no tag can go silently unrepresented.
##
## THE ONE RULE: every write to `_terrain_ids` or `_building_defs` must be followed by a
## `_refresh_tag_mask()` for the tiles it touched. There are five such writers and they are
## all in this file.
var _tile_tag_masks: PackedInt64Array = PackedInt64Array()

var _terrain_by_id: Dictionary = {}     # String id -> TerrainDefinition
var _terrain_defs: Array[TerrainDefinition] = []
var _forest_tile_count: int = 0

## TIER 1 ROW 13 (MIST). Set once, in `build()`, and NEVER recomputed from `width`/`depth`
## again — see `grow()`'s header for why a live recomputation would be a visible bug (every
## already-placed tile sliding half a growth-band sideways the instant the mist unfurls).
var _origin_offset: Vector2 = Vector2.ZERO


## Tag -> bit, built once from the shared vocabulary. `HABITAT_TAGS` is a `const`, so this
## table can never drift from it at runtime.
static var _tag_bits: Dictionary = _build_tag_bits()

## "This tile carries at least one tag OUTSIDE the shared vocabulary."
##
## The vocabulary is closed and both `TerrainDefinition.validate()` and
## `PlaceableDefinition.validate()` reject an entry outside it — but validation is a
## NON-FATAL report, not a load barrier, so a mis-authored `.tres` can still reach the
## simulation, and synthetic fixtures in the test suite use invented tags freely. Without
## this bit such a tag would map to no bit at all and be silently uncountable, turning a
## loud data error into a wrong capacity. With it, a tile carrying any unknown tag always
## survives the evaluator's early-out and is resolved against the real tag array instead.
##
## Bit 62, not 63: these masks live in a `PackedInt64Array`, whose values are signed.
const UNKNOWN_TAG_BIT: int = 1 << 62


static func _build_tag_bits() -> Dictionary:
	var out: Dictionary = {}
	var tags: PackedStringArray = AnimalDefinition.HABITAT_TAGS
	for i in tags.size():
		out[tags[i]] = 1 << i
	return out


## The single bit standing for `tag`, or 0 for a tag outside the vocabulary. A 0 bit can
## never match, which is the safe direction: an unknown tag counts for nothing rather than
## aliasing onto another tag's bit.
static func tag_bit(tag: String) -> int:
	return int(_tag_bits.get(tag, 0))


## The OR of every bit in `tags`, with `UNKNOWN_TAG_BIT` set if any entry is outside the
## vocabulary. Takes any string container (`Array[String]`, `PackedStringArray`) so callers
## need not convert.
static func tags_mask(tags) -> int:
	var mask: int = 0
	for tag: String in tags:
		var bit: int = int(_tag_bits.get(tag, 0))
		mask |= UNKNOWN_TAG_BIT if bit == 0 else bit
	return mask


func _ready() -> void:
	if _terrain_defs.is_empty():
		build(TerrainDefinition.load_all(), DEFAULT_WIDTH, DEFAULT_DEPTH)


## Builds (or rebuilds) the grid from a terrain roster. Every tile starts as
## `START_TERRAIN_ID`. Separated from `_ready()` so tests and tools can drive it directly.
## `terrain_mix` and `world_seed` DEFAULT TO THE PRE-D-53 BEHAVIOUR and must keep doing so: an
## empty mix takes the uniform `START_TERRAIN_ID` fill this function has always done, which is
## what leaves every suite's world — and the editor's F6 world — byte-identical. Only a real
## New Game passes a mix; see `WorldRoot._ready()`'s call.
func build(
	terrain_defs: Array,
	new_width: int = DEFAULT_WIDTH,
	new_depth: int = DEFAULT_DEPTH,
	terrain_mix: Dictionary = {},
	world_seed: int = 0
) -> void:
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
	_tile_styles = PackedStringArray()
	_tile_styles.resize(count)
	_building_styles = {}
	_building_defs = []
	_building_defs.resize(count)
	_building_origins = []
	_building_origins.resize(count)
	_tile_tag_masks = PackedInt64Array()
	_tile_tag_masks.resize(count)
	# Every tile starts as the same terrain with no building, so the mask is the same one
	# value everywhere — resolved once, not per tile.
	if terrain_mix.is_empty():
		var start_def: TerrainDefinition = terrain_definition(START_TERRAIN_ID)
		var start_mask: int = 0 if start_def == null else tags_mask(start_def.emitted_tags)
		for i in count:
			_terrain_ids[i] = START_TERRAIN_ID
			_building_defs[i] = null
			_building_origins[i] = Vector2i(-1, -1)
			_tile_tag_masks[i] = start_mask
		_forest_tile_count = 0
	else:
		_fill_from_mix(terrain_mix, count, world_seed)
	# Both branches above write `_tile_tag_masks` straight into the arrays rather than through
	# `_refresh_tag_mask()`, so a `build()` call — including a REBUILD of an already-live grid,
	# per this function's own header — needs its own bump. One bump here, after both branches,
	# rather than one inside each: a rebuild invalidates the whole grid once, not once per tile.
	terrain_version += 1


## The `terrain_mix` half of `build()` — a preset's starting terrain proportions, placed by
## `TerrainScatter` and written straight into the flat stores.
##
## NO `set_terrain()` CALLS. The obvious wiring — walk the grid calling the public setter — is
## ~1,296 signal emissions into a `TerrainView` that does not exist yet at this point in
## `WorldRoot._ready()`, plus 1,296 redundant tag-mask resolutions. Writing the stores directly
## is both correct and the only version that is cheap, and it is safe here specifically because
## `build()` owns the arrays outright: nothing is listening and no tile has a building on it yet.
##
## THE TAG MASK IS RESOLVED PER DISTINCT TERRAIN, not per tile. A mix has a handful of ids and
## a grid has thousands of tiles, and `tags_mask()` is a String round trip per call — the same
## reason `_tile_tag_masks` exists at all (see its header).
func _fill_from_mix(terrain_mix: Dictionary, count: int, world_seed: int) -> void:
	var ids: PackedStringArray = TerrainScatter.generate(terrain_mix, width, depth, world_seed)

	var mask_by_id: Dictionary = {}
	var is_forest_by_id: Dictionary = {}
	var forest_id: String = TerrainDefinition.normalize_id(FOREST_TERRAIN_ID)

	_forest_tile_count = 0
	for i in count:
		var id: String = ids[i]
		if not mask_by_id.has(id):
			var def: TerrainDefinition = terrain_definition(id)
			# An id the shipped terrain set does not carry contributes no tags rather than
			# taking the build down — the same non-fatal degradation `WorldSnapshot.apply()`
			# uses. `test_world_preset.gd` is what makes a mis-authored mix loud.
			mask_by_id[id] = 0 if def == null else tags_mask(def.emitted_tags)
			is_forest_by_id[id] = TerrainDefinition.normalize_id(id) == forest_id
		_terrain_ids[i] = id
		_building_defs[i] = null
		_building_origins[i] = Vector2i(-1, -1)
		_tile_tag_masks[i] = int(mask_by_id[id])
		if bool(is_forest_by_id[id]):
			_forest_tile_count += 1


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
	var old_styles: PackedStringArray = _tile_styles
	var old_buildings: Array = _building_defs
	var old_origins: Array[Vector2i] = _building_origins
	var old_masks: PackedInt64Array = _tile_tag_masks

	width = new_width
	depth = new_depth
	var count: int = width * depth
	_terrain_ids = PackedStringArray()
	_terrain_ids.resize(count)
	_tile_styles = PackedStringArray()
	_tile_styles.resize(count)
	_building_defs = []
	_building_defs.resize(count)
	_building_origins = []
	_building_origins.resize(count)
	_tile_tag_masks = PackedInt64Array()
	_tile_tag_masks.resize(count)

	var new_tiles: Array[Vector2i] = []
	for x in width:
		for z in depth:
			var i: int = _index(x, z)
			if x < old_width and z < old_depth:
				var old_i: int = x * old_depth + z
				_terrain_ids[i] = old_terrain[old_i]
				_tile_styles[i] = old_styles[old_i]
				_building_defs[i] = old_buildings[old_i]
				_building_origins[i] = old_origins[old_i]
				# A carried-over tile's occupancy is unchanged, so its mask is too.
				_tile_tag_masks[i] = old_masks[old_i]
			else:
				# The revealed terrain is always wild grass (`MistReveal`'s own header explains
				# why), so it can never be Forest — no `_forest_tile_count` bookkeeping needed.
				_terrain_ids[i] = MistReveal.reveal_terrain_id(world_seed, x, z)
				_tile_styles[i] = ""
				_building_defs[i] = null
				_building_origins[i] = Vector2i(-1, -1)
				_tile_tag_masks[i] = _tag_mask_for_tile(x, z)
				new_tiles.append(Vector2i(x, z))

	terrain_version += 1
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


## THE HOME-SITE ANCHOR of a tile: the footprint's own anchor where a building covers this
## tile, otherwise the tile itself.
##
## EXISTS BECAUSE A FOOTPRINT IS ONE HOME, NOT N. `HabitatSimulation` registers a building's
## home site at its ORIGIN, while `get_tile_tags()` above emits the building's tags at its
## CENTRE — for every footprint wider than 2x2 those are different tiles (3x3 -> origin+(1,1)),
## and any code that asks "which home site is this tile's?" tile-exactly gets `null` for eight
## of a 3x3 building's nine tiles. That gap let a villager found a SECOND, wild home site on a
## Farmhouse's own footprint — with a den prop beside the house — instead of moving into it.
## Routing every such lookup through here makes the whole footprint answer with the one site.
func home_site_anchor(x: int, z: int) -> Vector2i:
	var origin: Vector2i = get_building_origin(x, z)
	return Vector2i(x, z) if origin.x < 0 else origin


func is_occupied(x: int, z: int) -> bool:
	return get_building(x, z) != null


## THE TAG DERIVATION (spec.md -> Shared Patterns, -> D-25). A tile's tags are a pure
## function of what occupies it: the building's `emitted_tags` where a footprint suppresses
## the ground (buildings.md -> What a Building Is), otherwise the terrain's.
##
## Returns the definition's own array by reference for speed — the capacity pass runs this
## once per tile in radius per evaluation. **Callers must not mutate the result.**
## ONE BUILDING EMITS ONCE, AT ITS CENTRE TILE (2026-09-08, human ruling). A footprint tile
## that is not the centre is occupied and terrain-suppressed but emits NOTHING.
##
## WHY, and it is not a micro-optimisation: a tag count is a count of TILES, so before this
## change a building contributed one copy of its `emitted_tags` per tile it covered. That was
## invisible while every buildable was 1x1 and became wrong the moment they were not:
##   * `built` ceilings stopped meaning what they were ruled to mean — rabbit's `built <= 2`
##     ("a distant cottage is fine, a village is not") was silently a 4x tighter rule at 2x2
##     and 9x tighter next to the 3x3 barn, excluding rabbits from a single building.
##   * Well and Water Tower emit `water`, which is a SCALING need (cow 3/individual, horse 2,
##     fox 6) — a 2x2 tower quietly counted as four ponds.
##   * Worst: a scout founds a home site on any tile whose tags satisfy a tier, so all four
##     tiles of a 2x2 House passed the `house` gate and ONE HOUSE SEATED TWO VILLAGERS.
##     Measured, not theorised: capacity_at(28,28) and capacity_at(29,28) each read 1.
## Emitting once restores 1x1 semantics for every count at every footprint, so NO ruled
## constant had to move and none has to move again the next time a footprint does.
##
## CENTRE, NOT ORIGIN, because the tag's position is what radius checks measure to. The origin
## is a corner: on the 3x3 barn that is ~1.41 tiles off the building's visual centre, enough to
## push it outside the horse's radius-5 `stable` need when the barn plainly looks inside it.
## Integer division lands on the true centre for odd footprints (3x3 -> origin + (1,1), zero
## error) and on the origin for even ones (2x2 has no centre tile; the residual is 0.71 tiles,
## against radii of 5-14). 1x1 is unchanged in every respect.
func get_tile_tags(x: int, z: int) -> Array[String]:
	var building: PlaceableDefinition = get_building(x, z)
	if building != null:
		var origin: Vector2i = get_building_origin(x, z)
		var centre: Vector2i = origin + (building.footprint - Vector2i.ONE) / 2
		if Vector2i(x, z) != centre:
			return []
		return building.emitted_tags
	var terrain: TerrainDefinition = get_terrain(x, z)
	if terrain == null:
		return []
	return terrain.emitted_tags


## THE SAME DERIVATION AS `get_tile_tags()`, as a bitmask, read straight out of the cache.
##
## This is the form the capacity evaluator's tile walk uses: one array index and a bit test
## instead of a String lookup and an `Array.has()` per tag. Out-of-bounds reads 0, matching
## `get_tile_tags()`'s empty array — a tile that is not there emits nothing.
##
## `get_tile_tags()` stays the readable form and remains the source of truth for the mask
## (`_tag_mask_for_tile()` derives one from the other), so the two can never disagree about
## what a tile emits; `test_tile_tag_mask.gd` pins that equivalence over the whole grid.
func tile_tag_mask(x: int, z: int) -> int:
	if not in_bounds(x, z):
		return 0
	return _tile_tag_masks[_index(x, z)]


## Derives one tile's mask from `get_tile_tags()` — the one place the two representations
## are tied together.
func _tag_mask_for_tile(x: int, z: int) -> int:
	return tags_mask(get_tile_tags(x, z))


## Recomputes one tile's cached mask. Called by every writer that changes what a tile holds.
func _refresh_tag_mask(x: int, z: int) -> void:
	if not in_bounds(x, z):
		return
	var i: int = _index(x, z)
	if i < _tile_tag_masks.size():
		_tile_tag_masks[i] = _tag_mask_for_tile(x, z)
	terrain_version += 1


## Forest tiles currently on the map, maintained incrementally so the economy never scans
## the world. A building footprint suppresses the tile's terrain tags but does not remove
## the terrain, and Forest is not in the House's `allowed_terrain`, so this counts terrain.
func forest_tile_count() -> int:
	return _forest_tile_count


# --- Mutation (raw; cost and validation live in project/scripts/economy/) ----------------

## Sets a tile's terrain with no cost check. Returns false when nothing changed.
## `WorldRoot.paint_tile()` is the checked public entry point — call that, not this.
func set_terrain(x: int, z: int, terrain_id: String, style_id: String = "") -> bool:
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
	# THE STYLE IS WRITTEN HERE, BEFORE THE SIGNAL, AND THAT ORDER IS THE WHOLE REASON THIS
	# PARAMETER EXISTS. `tile_changed` below is emitted SYNCHRONOUSLY and is what makes
	# `TerrainView` build the tile's visual, so a caller that set the style on the next line
	# stamped it too late: the tile was already drawn, with an empty style, through
	# `pick_variant()`. That shipped as "it still cycles through different tree styles randomly
	# when I select and place trees" — the player picked a tree, placed a row, and got an
	# assortment. Passing the style in is what makes the write and the draw atomic.
	#
	# It also subsumes the old "clear on repaint" rule: a caller that supplies no style clears
	# it, which is correct, because a stored id belongs to the terrain that was here and must not
	# survive onto a different one.
	_tile_styles[i] = style_id
	_refresh_tag_mask(x, z)
	tile_changed.emit(x, z)
	return true


## The style id `(x, z)` was painted with, or "" when it carries none (every tile of a terrain
## with no picker, every tile of a pre-D-57 save, and every mist-revealed tile). Read by
## `TerrainChunkLod._resolve_variant()`, where "" means "fall through to `pick_variant()`".
## After D-58 an empty FOREST tile means a pre-v7 save, not a design — a new map's tiles are
## stamped with concrete ids by `WorldRoot._randomise_initial_styles()`.
func get_tile_style(x: int, z: int) -> String:
	if not in_bounds(x, z):
		return ""
	return _tile_styles[_index(x, z)]


## Stamps `(x, z)`'s captured style. Called by `WorldRoot.paint_tile()` immediately after a
## successful `set_terrain()`; nothing else should write this, because "captured at paint time"
## is the whole contract (-> D-57).
func set_tile_style(x: int, z: int, style_id: String) -> void:
	if in_bounds(x, z):
		_tile_styles[_index(x, z)] = style_id


## The style the building anchored at `origin` was PLACED with, or "" for none.
func get_building_style(origin: Vector2i) -> String:
	return WorldSnapshot.text_or(_building_styles.get(origin, ""), "")


## Stamps a placed building's captured style. Same paint-time-only contract as tile styles.
func set_building_style(origin: Vector2i, style_id: String) -> void:
	if style_id.is_empty():
		_building_styles.erase(origin)
	else:
		_building_styles[origin] = style_id


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
		_refresh_tag_mask(tile.x, tile.y)
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
	_building_styles.erase(origin)
	for tile: Vector2i in footprint_tiles(origin, def):
		if not tile_in_bounds(tile):
			continue
		if get_building_origin(tile.x, tile.y) != origin:
			continue
		var i: int = _index(tile.x, tile.y)
		_building_defs[i] = null
		_building_origins[i] = Vector2i(-1, -1)
		_refresh_tag_mask(tile.x, tile.y)
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
