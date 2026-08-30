class_name SpeciesRoster
extends RefCounted
## Loads every `AnimalDefinition` on disk — the roster the qualification pass runs against.
##
## Lives here rather than as a static on `AnimalDefinition` on purpose:
## `project/scripts/definitions/` is the one directory the directory-disjointness
## precondition does not cover (tier1-status.md -> Directory claims), so the simulation adds
## nothing to it. The four schemas stay pure content contracts.
##
## No species is special-cased anywhere in the simulation. Villagers are just another
## species (gdd.md -> Design Pillars), so `human.tres` arrives through this same loader.

const DATA_DIR: String = "res://data/animals"


var _defs: Array[AnimalDefinition] = []
var _by_id: Dictionary = {}


func _init(defs: Array = []) -> void:
	var source: Array = defs
	if source.is_empty():
		source = load_all()
	for entry in source:
		var def: AnimalDefinition = entry as AnimalDefinition
		if def == null:
			continue
		_defs.append(def)
		_by_id[AnimalDefinition.normalize_id(def.id)] = def


## Every `AnimalDefinition` `.tres` in `dir_path`, sorted by filename for a stable order.
## Skips anything that does not bind rather than raising — one malformed `.tres` must not
## take the roster down (same non-fatal posture as `validate()`).
static func load_all(dir_path: String = DATA_DIR) -> Array[AnimalDefinition]:
	var out: Array[AnimalDefinition] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	var names: PackedStringArray = dir.get_files()
	names.sort()
	for file_name: String in names:
		if not (file_name.ends_with(".tres") or file_name.ends_with(".tres.remap")):
			continue
		var path: String = "%s/%s" % [dir_path, file_name.trim_suffix(".remap")]
		var def: AnimalDefinition = ResourceLoader.load(path) as AnimalDefinition
		if def != null:
			out.append(def)
	return out


func species() -> Array[AnimalDefinition]:
	return _defs


func by_id(species_id: String) -> AnimalDefinition:
	return _by_id.get(AnimalDefinition.normalize_id(species_id), null) as AnimalDefinition


func size() -> int:
	return _defs.size()
