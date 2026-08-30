class_name BuildingPlacement
extends Node
## Build Mode's rules — Tier 1 row 4 (Build), thin form: the House at 1x1, grass only.
##
## Two checks, in this order: **every footprint tile must be allowed terrain and empty**,
## then **the cost must be affordable**. A tile that fails either simply does not accept the
## placement — `place()` returns false and nothing happens. buildings.md -> Placement rules:
## "ineligible tiles don't accept the tap (a soft cue, never an error)". There is no error
## state anywhere in this file, and that is deliberate (Pillar 1).
##
## No rotation logic: every building has one fixed facing (buildings.md).
##
## NOT BUILT HERE, and deliberately: removal/refund and the grace window (#16), and Gentle
## Displacement (row 10). Displacement is a pillar invariant that must ship before any kid
## playtest — a build that drops a neighbourhood's capacity below its population must warn
## and then relocate. This skeleton places buildings without that flow.

## Data-entry directory for buildables.
const DATA_DIR: String = "res://data/buildings"


var _grid: WorldGrid = null
var _wood: WoodLedger = null
var _by_id: Dictionary = {}                    # String id -> PlaceableDefinition
var _defs: Array[PlaceableDefinition] = []


func attach(grid: WorldGrid, wood: WoodLedger, defs: Array = []) -> void:
	_grid = grid
	_wood = wood
	var source: Array = defs
	if source.is_empty():
		source = load_all()
	_defs = []
	_by_id = {}
	for entry in source:
		var def: PlaceableDefinition = entry as PlaceableDefinition
		if def == null:
			continue
		_defs.append(def)
		_by_id[PlaceableDefinition.normalize_id(def.id)] = def


## Every `PlaceableDefinition` `.tres` in `dir_path`, sorted by filename. Mirrors
## `TerrainDefinition.load_all()`; skips anything that does not bind, rather than raising.
static func load_all(dir_path: String = DATA_DIR) -> Array[PlaceableDefinition]:
	var out: Array[PlaceableDefinition] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	var names: PackedStringArray = dir.get_files()
	names.sort()
	for file_name: String in names:
		if not (file_name.ends_with(".tres") or file_name.ends_with(".tres.remap")):
			continue
		var path: String = "%s/%s" % [dir_path, file_name.trim_suffix(".remap")]
		var def: PlaceableDefinition = ResourceLoader.load(path) as PlaceableDefinition
		if def != null:
			out.append(def)
	return out


func definitions() -> Array[PlaceableDefinition]:
	return _defs


func definition(placeable_id: String) -> PlaceableDefinition:
	return _by_id.get(PlaceableDefinition.normalize_id(placeable_id), null) as PlaceableDefinition


func cost_of(placeable_id: String) -> int:
	var def: PlaceableDefinition = definition(placeable_id)
	return 0 if def == null else def.cost


## True when every footprint tile is in bounds, unoccupied, and on `allowed_terrain`.
## Deliberately separate from affordability so the UI can show an eligible-but-unaffordable
## tile differently from an ineligible one.
func terrain_allows(x: int, z: int, placeable_id: String) -> bool:
	var def: PlaceableDefinition = definition(placeable_id)
	if def == null or _grid == null:
		return false
	var allowed: Array[String] = def.normalized_allowed_terrain()
	for tile: Vector2i in WorldGrid.footprint_tiles(Vector2i(x, z), def):
		if not _grid.tile_in_bounds(tile):
			return false
		if _grid.is_occupied(tile.x, tile.y):
			return false
		if not allowed.has(_grid.get_terrain_id(tile.x, tile.y)):
			return false
	return true


## True when the placement would succeed right now. `place()` re-checks; this exists for
## previews and soft cues.
func can_place(x: int, z: int, placeable_id: String) -> bool:
	if not terrain_allows(x, z, placeable_id):
		return false
	return _wood != null and _wood.can_afford(cost_of(placeable_id))


## Places a building. Returns false — silently, with nothing changed — when the tile is
## ineligible or the player cannot afford it.
func place(x: int, z: int, placeable_id: String) -> bool:
	if not can_place(x, z, placeable_id):
		return false
	var def: PlaceableDefinition = definition(placeable_id)
	if not _wood.spend(def.cost):
		return false
	return _grid.set_building(Vector2i(x, z), def)
