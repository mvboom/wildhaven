class_name RoamRegion
extends RefCounted
## WHERE ONE RESIDENT MAY WALK — the terrain half of Tier 1 row 6's "Roam quality" bucket.
## Design and the reasoning behind every rule below: game-design/roaming.md.
##
## This is a separate class from `ResidentRoamer` on purpose. That file already carries wander
## cadence, avoids, separation, pathing and animation across 460+ dense lines; "which points
## are allowed" is a sixth responsibility and a self-contained one. Nothing here needs a
## roamer, an AnimationPlayer or a scene to test.
##
## PRESENTATION, NOT SIMULATION — same standing as `ResidentRoamer` itself. Nothing here marks
## a neighbourhood dirty or touches `HabitatSimulation.evaluations_run`.
##
## THE PREDICATE IS AN **OR** OVER `habitat_needs`, NOT AN AND. `CapacityEvaluator` scores
## those tags as an AND *over a radius*; no single terrain emits more than two of them, so a
## per-tile AND yields zero tiles for 7 of the 15 shipped species. See roaming.md §3.1.

## The four orthogonal steps. Diagonals are deliberately excluded: adjacency through a corner
## reads on screen as a gap, not a border.
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

## PLACEHOLDER — the human owns this. **No GDD or spec.md number exists for it.** Below this
## many tiles a region is not worth roaming and `ResidentRoamer` falls back to its disc.
##
## 6 because a measured fox region came out at 3 tiles on a randomly-mixed probe world, and an
## animal with 3 tiles is functionally stationary — a worse read than the uniform disc this
## replaces. The floor stops a species whose terrain has been painted away from collapsing
## into a pinned animal.
const MIN_REGION_TILES: int = 6


var _grid: WorldGrid = null
var _navigation: WorldNavigation = null
var _home_tile: Vector2i = Vector2i.ZERO
## `WorldGrid.tags_mask()` of the species' `habitat_needs`. Zero (a species with no needs, or
## only unrecognised ones) makes nothing liked, which collapses the region to the home tile
## and hands the roamer back to its disc — a safe degradation, not an error.
var _needs_mask: int = 0
var _radius: int = 0

## Tile COORDINATES, not world positions — 8 bytes each rather than 12, and the conversion is
## one multiply-add at the moment a point is actually picked.
var _tiles: PackedVector2Array = PackedVector2Array()
## The `WorldGrid.terrain_version` this set was built at. -1 means "never built", so the first
## read always builds.
var _built_version: int = -1

## How many full fills have actually run. Same shape and purpose as
## `WorldNavigation.rebuilds_run` and `HabitatSimulation.evaluations_run` — an exact work
## counter, so a test can assert that an untouched world does NO work rather than inferring it
## from a wall-clock number. Never reset by production code.
var rebuilds_run: int = 0


func _init(
	grid: WorldGrid,
	navigation: WorldNavigation,
	home_tile: Vector2i,
	needs_mask: int,
	radius: int
) -> void:
	_grid = grid
	_navigation = navigation
	_home_tile = home_tile
	_needs_mask = needs_mask
	_radius = maxi(0, radius)


func tiles() -> PackedVector2Array:
	_ensure_fresh()
	return _tiles


func tile_count() -> int:
	_ensure_fresh()
	return _tiles.size()


## Whether this region is worth roaming at all. `ResidentRoamer` asks before delegating.
func is_usable() -> bool:
	return tile_count() >= MIN_REGION_TILES


func has_tile(tile: Vector2i) -> bool:
	_ensure_fresh()
	return _tiles.has(Vector2(tile.x, tile.y))


## Rebuilds only when the world has changed under us. One integer compare, so the steady-state
## cost of holding a region is nothing.
func _ensure_fresh() -> void:
	if _grid != null and _built_version == _grid.terrain_version:
		return
	rebuild()


## Breadth-first from the home tile across qualifying tiles ONLY. Crossing only qualifying
## tiles is what makes the result contiguous and therefore reachable on foot — a patch of
## liked terrain cut off by water or buildings is correctly left out rather than sending a
## resident on a long detour to reach a waypoint inside it.
func rebuild() -> void:
	rebuilds_run += 1
	_tiles = PackedVector2Array()
	if _grid == null:
		_built_version = -1
		return
	_built_version = _grid.terrain_version
	if not _grid.in_bounds(_home_tile.x, _home_tile.y):
		return

	# The home tile is seeded UNCONDITIONALLY, walkable or not: a den tile carries a
	# navigation reservation and a House tile is occupied, and a resident must always be
	# allowed to stand on its own home.
	var seen: Dictionary = {_home_tile: true}
	var queue: Array[Vector2i] = [_home_tile]
	_tiles.append(Vector2(_home_tile.x, _home_tile.y))
	var reach: int = _radius * _radius

	while not queue.is_empty():
		var tile: Vector2i = queue.pop_back()
		for step: Vector2i in NEIGHBOURS:
			var next: Vector2i = tile + step
			if seen.has(next):
				continue
			seen[next] = true
			if not _grid.in_bounds(next.x, next.y):
				continue
			if next.distance_squared_to(_home_tile) > reach:
				continue
			if not _qualifies(next.x, next.y):
				continue
			_tiles.append(Vector2(next.x, next.y))
			queue.append(next)


## Walkable AND (liked, or touching something liked).
func _qualifies(x: int, z: int) -> bool:
	if _navigation != null and not _navigation.is_tile_walkable(_grid, x, z):
		return false
	if _likes(x, z):
		return true
	for step: Vector2i in NEIGHBOURS:
		if _likes(x + step.x, z + step.y):
			return true
	return false


## One AND against `WorldGrid`'s already-cached per-tile mask — the reason this whole system
## is affordable. Out of bounds reads 0 and so is never liked.
func _likes(x: int, z: int) -> bool:
	return (_grid.tile_tag_mask(x, z) & _needs_mask) != 0
