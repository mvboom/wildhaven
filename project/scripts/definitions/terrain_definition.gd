@tool
class_name TerrainDefinition
extends Resource
## One terrain type — the tile-level surface the player paints in Terraform Mode
## (terrain.md -> What Terrain Is; spec.md -> Data Schemas).
##
## This is SCHEMA SCAFFOLDING, not per-terrain content. Adding a terrain type means
## authoring a `.tres` against this contract; it must never mean editing this file.
##
## WHY THIS RESOURCE EXISTS AT ALL (spec.md does not list it — this is the one schema of
## the four that is derived rather than transcribed):
##   1. spec.md's inert-land invariant requires that `BARE_TAGS` be "derived from the
##      tag-source mapping at validation time, never hardcoded". A derivation is only
##      possible if the mapping is DATA. `derive_bare_tags()` below is that derivation.
##   2. gdd.md -> Content Pipelines -> Add-a-Terrain has a data-entry step, and a step
##      with no artifact is a step that cannot be tracked or validated.
## Everything else here is transcribed from terrain.md's decided tables, not invented.
##
## Nothing here decides tuning. Every cost is a `.tres` value and the human's call
## (Open Question #8); the schema only refuses a negative one.

## Data-entry directory for terrain definitions. Used by `load_all()` so the derivation
## below has a single place to read from.
const DATA_DIR: String = "res://data/terrain"

## The id of the terrain that untouched revealed land is made of (gdd.md -> World
## Structure; terrain.md -> Already-Defined Terrain).
##
## LOAD-BEARING CONSTANT: `derive_bare_tags()` keys off it, so the inert-land invariant's
## automated check resolves through this id rather than through a hardcoded tag list.
const WILD_GRASS_ID: String = "wild_grass"

## Terrain the player paints for free. terrain.md's one pricing rule — "nature is free;
## construction costs materials" — is a DECIDED design rule, not a tuning number, so the
## schema states it; the per-terrain value still lives in the `.tres`.
const FREE_COST: int = 0


## Unique terrain id, in the shared lowercase-snake convention (`grass`, `wild_grass`).
@export var id: String = ""

## Player-facing name (`Wild grass`).
@export var display_name: String = ""

## Habitat tags every tile of this terrain emits, drawn from the shared vocabulary
## (`AnimalDefinition.HABITAT_TAGS`). **That is the whole declaration** — no radius, no
## weight, no threshold (the v1 tag model, -> D-25; terrain.md -> Tag emission).
##
## AN EMPTY ARRAY IS VALID AND LOAD-BEARING, not an unfinished entry: wild grass is
## tag-inert by design, and that emptiness is what makes the inert-land invariant
## structural rather than a rule someone has to remember. `validate()` therefore never
## complains about an empty `emitted_tags`.
@export var emitted_tags: Array[String] = []

## Wood cost to paint one tile of this terrain.
## Natural terrain is free by decided rule; the cultivated field's 2 Wood is DECIDED
## 2026-08-01 (-> D-29, #8 closed) at terrain.md's stated baseline.
@export var cost: int = FREE_COST

## The 1x1 tile visual(s) for this terrain. One entry is the common case (today, every
## `.tres` ships exactly one); more than one lets a follow-up asset/look pass give a
## terrain several interchangeable variants (multiple rock meshes, multiple tree species,
## …) without any new save-state — `pick_variant()` below picks a STABLE per-tile index
## from tile coordinates + `id`, never stored state (-> D-42).
@export var model_scenes: Array[PackedScene] = []

## Optional resource yield. `null` for every terrain that produces nothing — which is
## every v1 terrain except Forest, v1's sole harvestable (terrain.md).
##
## Typed as `HarvestableTileDefinition` rather than bare `Resource`: the two schemas have
## no cyclic dependency (harvestable_tile_definition.gd does not reference this file), so
## the editor gets correct filtering and a mistyped `.tres` fails loudly at load instead
## of silently arriving as untyped metadata. A null is legal and must stay legal.
@export var harvestable: HarvestableTileDefinition = null

## Whether an animal roaming this terrain must path AROUND a tile of it rather than through.
## Defaults false — most terrain (grass, water, cultivated field) stays crossable exactly as
## it always has been. Forest is the only v1 terrain with this set (data-entry decision, not
## a code default): see forest.tres. Read by `WorldNavigation` when rebuilding the navmesh;
## nothing in placement, cost, or capacity logic reads this field.
@export var blocks_movement: bool = false


## Normalizes a terrain id to the shared convention. Use at every lookup boundary so a
## hand-authored `"Wild Grass"` still resolves to `wild_grass` instead of silently missing.
static func normalize_id(raw_id: String) -> String:
	return raw_id.strip_edges().to_snake_case().to_lower()


## THE DERIVATION spec.md's inert-land invariant requires: the tags that UNTOUCHED
## revealed land emits, read from the tag-source mapping instead of hardcoded.
##
## Untouched revealed land is wild grass (gdd.md -> World Structure), so the bare-tag set
## is exactly the wild-grass entry's `emitted_tags` — empty today, and automatically
## whatever it becomes if that entry ever changes. A hardcoded copy silently rots the
## first time emission changes, which is the exact failure this invariant exists to
## prevent.
##
## Returns EMPTY when no `wild_grass` entry is present. That is deliberately not an error
## here — this function never raises and never decides policy — but it does mean an
## absent entry would make the invariant vacuously true. **The validation suite must
## assert separately that a `wild_grass` definition exists on disk**; use `find_by_id()`.
static func derive_bare_tags(defs: Array) -> PackedStringArray:
	var wild: TerrainDefinition = find_by_id(defs, WILD_GRASS_ID)
	if wild == null:
		return PackedStringArray()
	var out: PackedStringArray = PackedStringArray()
	for tag: String in wild.emitted_tags:
		if not out.has(tag):
			out.append(tag)
	return out


## The definition in `defs` whose `id` matches, or null. Ids are compared normalized so a
## hand-authored capitalisation still resolves.
static func find_by_id(defs: Array, wanted_id: String) -> TerrainDefinition:
	var wanted: String = normalize_id(wanted_id)
	for entry in defs:
		var def: TerrainDefinition = entry as TerrainDefinition
		if def != null and normalize_id(def.id) == wanted:
			return def
	return null


## Every TerrainDefinition `.tres` in `dir_path`, sorted by filename for a stable order.
## Exists so `derive_bare_tags()` has something real to derive FROM — a derivation that
## only works against a hand-built array is not a derivation.
##
## Skips anything that does not bind to this class rather than raising: one malformed
## `.tres` must not take down a load (same non-fatal posture as `validate()`).
static func load_all(dir_path: String = DATA_DIR) -> Array[TerrainDefinition]:
	var out: Array[TerrainDefinition] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	var names: PackedStringArray = dir.get_files()
	names.sort()
	for file_name: String in names:
		if not (file_name.ends_with(".tres") or file_name.ends_with(".tres.remap")):
			continue
		var path: String = "%s/%s" % [dir_path, file_name.trim_suffix(".remap")]
		var def: TerrainDefinition = ResourceLoader.load(path) as TerrainDefinition
		if def != null:
			out.append(def)
	return out


## Stably picks which of `model_scenes` a given tile shows. Returns `null` if
## `model_scenes` is empty; returns the sole entry directly (no hashing) if there is
## exactly one. Otherwise hashes `(x, z, id)` into an index that is deterministic and
## reproducible on every reload — SAME tile + SAME terrain id always yields the SAME
## variant, with no per-tile state stored anywhere (no save-data change, -> D-42).
## Repainting a tile to a different terrain, or back to this one, is free to land on a
## different variant than before; that is expected, not a bug.
func pick_variant(x: int, z: int) -> PackedScene:
	if model_scenes.is_empty():
		return null
	if model_scenes.size() == 1:
		return model_scenes[0]
	var key: String = "%d_%d_%s" % [x, z, id]
	var index: int = hash(key) % model_scenes.size()
	return model_scenes[index]


## Non-fatal schema check. Returns human-readable problems; an empty array means clean.
## Never raises and never mutates — a bad entry degrades to a reported warning so one
## malformed `.tres` cannot take down a load.
func validate() -> Array[String]:
	var problems: Array[String] = []

	var regex := RegEx.new()
	regex.compile(AnimalDefinition.ID_PATTERN)
	if id.is_empty():
		problems.append("`id` is empty.")
	elif regex.search(id) == null:
		problems.append("`id` \"%s\" breaks the id convention (lowercase, snake_case)." % id)

	if display_name.is_empty():
		problems.append("`display_name` is empty.")

	# Vocabulary is read from AnimalDefinition, never re-declared here: four files holding
	# four copies of the ten tags is four things to keep in sync, and extending the
	# vocabulary is a system-wide human decision (terrain.md -> Tag emission), so a local
	# copy could also quietly authorise one.
	var seen: PackedStringArray = PackedStringArray()
	for tag: String in emitted_tags:
		if not AnimalDefinition.HABITAT_TAGS.has(tag):
			problems.append("`emitted_tags` tag \"%s\" is not in the shared vocabulary." % tag)
		if seen.has(tag):
			problems.append("`emitted_tags` lists \"%s\" more than once." % tag)
		else:
			seen.append(tag)

	# NOTE: an EMPTY `emitted_tags` is deliberately not reported. See the field's comment.

	# The inert-land invariant, enforced at its structural source (spec.md -> Shared
	# Patterns). Wild grass emitting anything at all would hand the player finished
	# habitat for pushing the mist — the single failure the invariant exists to prevent —
	# and would do it by changing data, with no code review to catch it.
	if normalize_id(id) == WILD_GRASS_ID and not emitted_tags.is_empty():
		problems.append(
			"`%s` emits %s — untouched revealed land must be tag-inert (inert-land invariant)." % [
				WILD_GRASS_ID, str(emitted_tags)
			]
		)

	if cost < 0:
		problems.append("`cost` %d is negative — painting terrain can never pay the player." % cost)

	if model_scenes.is_empty():
		problems.append("`model_scenes` is empty.")
	else:
		for i in model_scenes.size():
			if model_scenes[i] == null:
				problems.append("`model_scenes[%d]` is null." % i)

	if harvestable != null:
		for p: String in harvestable.validate():
			problems.append("`harvestable`: %s" % p)

	return problems
