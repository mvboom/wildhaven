@tool
class_name PlaceableDefinition
extends Resource
## One buildable (spec.md -> Data Schemas -> PlaceableDefinition; buildings.md ->
## Attributes Required). v1 ships one: the House.
##
## This is SCHEMA SCAFFOLDING, not per-building content. Adding a buildable means
## authoring a `.tres` against this contract; it must never mean editing this file.
##
## Nothing here decides tuning. `cost` and `footprint` carry placeholder defaults at the
## GDD's stated baselines (#8 costs, #18 footprints); per-building values live in the
## `.tres` and are the human's call.

## PLACEHOLDER / GDD baseline — human owns this (#18). buildings.md gives the House a 1x1
## floor form and a 2x2 full form; the floor form is what Tier 1 row 4 ships, so 1x1 is
## the default a `.tres` inherits when it omits the field.
const DEFAULT_FOOTPRINT: Vector2i = Vector2i(1, 1)


## Unique buildable id, in the shared lowercase-snake convention (`house`).
@export var id: String = ""

## Player-facing name (`House`).
@export var display_name: String = ""

## Wood cost to place one of these.
## TUNING — the human owns this (#8, #26). buildings.md's baselines: ~15 Wood at 1x1,
## ~30 at 2x2.
@export var cost: int = 0

## Tile footprint, in tiles (x by z). The building occupies its footprint exclusively:
## a tile under it stops emitting its terrain tags and emits `emitted_tags` instead
## (buildings.md -> What a Building Is).
## TUNING — the human owns this (#18).
@export var footprint: Vector2i = DEFAULT_FOOTPRINT

## Terrain ids the footprint may occupy, matching `TerrainDefinition.id`. The building
## goes only where EVERY footprint tile is allowed; ineligible tiles simply don't accept
## the tap (a soft cue, never an error — buildings.md -> Placement rules).
##
## Deliberately `Array[String]` and not `Array[TerrainDefinition]`, for the same reason
## `AnimalDefinition.avoids` stores ids: a `res://` reference to a not-yet-authored
## terrain is a hard load failure, whereas a bad id is inert text a lookup can report.
@export var allowed_terrain: Array[String] = []

## Habitat tags this building emits, drawn from the shared vocabulary
## (`AnimalDefinition.HABITAT_TAGS`). House -> `house`. Same per-tile model as terrain:
## no radius, no weight, no threshold (-> D-25).
@export var emitted_tags: Array[String] = []

## The 3D model scene variant(s) for this building. Unlike TerrainDefinition/
## AnimalDefinition, there is no pick_variant() here: every placed instance of a
## buildable shows the SAME look (one player-wide choice, sub-project B2's job — this
## schema only makes the data support more than one look; B1 always reads index 0).
@export var model_scenes: Array[PackedScene] = []

## Groups this buildable's hotbar button with every other buildable sharing the same
## non-empty value — sub-project B2 renders one button per distinct group, showing
## whichever member is the player's current style default, with the rest reachable via
## long-press. Empty (the default) means "stands alone" — one button, one buildable,
## exactly the behavior every placeable had before this field existed.
@export var hotbar_category: String = ""

## Inspect-tap flavor copy. Unlike a species fact card this is flavor, not a verified
## fact — but it still runs Content Pipeline step 5, so it is written by content-writer,
## not here.
@export_multiline var fact_text: String = ""


## Normalizes a buildable id to the shared convention.
static func normalize_id(raw_id: String) -> String:
	return raw_id.strip_edges().to_snake_case().to_lower()


## `allowed_terrain` normalized to the shared convention, de-duplicated.
func normalized_allowed_terrain() -> Array[String]:
	var out: Array[String] = []
	for entry: String in allowed_terrain:
		var norm: String = normalize_id(entry)
		if norm != "" and not out.has(norm):
			out.append(norm)
	return out


## The subset of `allowed_terrain` with no matching entry in `known_terrain_ids`.
##
## Unlike `AnimalDefinition.unresolved_avoids()`, a non-empty result here IS a defect,
## not a legal forward reference: `allowed_terrain` gates placement, so an id that
## resolves to nothing makes the building unplaceable on ground the designer intended.
## `validate()` reports it when a roster of terrain ids is supplied.
func unresolved_terrain(known_terrain_ids: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	for entry: String in normalized_allowed_terrain():
		if not known_terrain_ids.has(entry):
			out.append(entry)
	return out


## Fields still awaiting a human/content-writer sign-off, reported SEPARATELY from
## `validate()`.
##
## Deliberate divergence from AnimalDefinition, which folds its placeholder `fact_text`
## check into `validate()`: there, a placeholder is a defect because the fact card is
## Pillar 4's payload and must never ship unsigned. Here the copy is inspect-tap flavor
## whose Content Pipeline step 5 has not been dispatched yet, so a `PLACEHOLDER`-prefixed
## string is a legitimate in-flight state, not a malformed entry — the schema check and
## the ship gate are two different questions and are answered by two different functions.
##
## Release gating reads THIS; a non-empty result must block a release build.
func pending_signoff() -> Array[String]:
	var pending: Array[String] = []
	if fact_text.begins_with(AnimalDefinition.PLACEHOLDER_MARKER):
		pending.append("`fact_text` is still a placeholder — awaiting Content Pipeline step 5.")
	return pending


## Non-fatal schema check. Returns human-readable problems; an empty array means clean.
## Never raises and never mutates.
##
## `known_terrain_ids` is optional; pass the terrain roster's ids to also surface
## `allowed_terrain` entries that resolve to nothing.
func validate(known_terrain_ids: PackedStringArray = PackedStringArray()) -> Array[String]:
	var problems: Array[String] = []

	var regex := RegEx.new()
	regex.compile(AnimalDefinition.ID_PATTERN)
	if id.is_empty():
		problems.append("`id` is empty.")
	elif regex.search(id) == null:
		problems.append("`id` \"%s\" breaks the id convention (lowercase, snake_case)." % id)

	if display_name.is_empty():
		problems.append("`display_name` is empty.")

	if cost < 0:
		problems.append("`cost` %d is negative — building can never pay the player." % cost)

	if footprint.x < 1 or footprint.y < 1:
		problems.append("`footprint` %s must be at least 1x1." % str(footprint))

	if allowed_terrain.is_empty():
		problems.append("`allowed_terrain` is empty — the building could never be placed.")
	for entry: String in allowed_terrain:
		if normalize_id(entry) != entry:
			problems.append("`allowed_terrain` entry \"%s\" is not in id form (expected \"%s\")." % [
				entry, normalize_id(entry)
			])

	# Vocabulary is read from AnimalDefinition, never re-declared here — see the same note
	# in terrain_definition.gd. Four copies of the ten tags is four things to drift.
	var seen: PackedStringArray = PackedStringArray()
	for tag: String in emitted_tags:
		if not AnimalDefinition.HABITAT_TAGS.has(tag):
			problems.append("`emitted_tags` tag \"%s\" is not in the shared vocabulary." % tag)
		if seen.has(tag):
			problems.append("`emitted_tags` lists \"%s\" more than once." % tag)
		else:
			seen.append(tag)

	if model_scenes.is_empty():
		problems.append("`model_scenes` is empty.")
	else:
		for i in model_scenes.size():
			if model_scenes[i] == null:
				problems.append("`model_scenes[%d]` is null." % i)

	# Empty is a defect; PLACEHOLDER-prefixed is not — see `pending_signoff()`.
	if fact_text.is_empty():
		problems.append("`fact_text` is empty.")

	if not known_terrain_ids.is_empty():
		for entry: String in unresolved_terrain(known_terrain_ids):
			problems.append("`allowed_terrain` entry \"%s\" has no TerrainDefinition." % entry)

	return problems
