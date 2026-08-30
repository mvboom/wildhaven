@tool
class_name HarvestableTileDefinition
extends Resource
## One resource-producing tile (spec.md -> Data Schemas -> HarvestableTileDefinition;
## terrain.md -> Harvestable terrain).
##
## This is SCHEMA SCAFFOLDING, not per-terrain content. Adding a harvestable means
## authoring a `.tres` against this contract; it must never mean editing this file.
##
## v1 has exactly one harvestable — Forest — and one resource — Wood. The schema is
## nevertheless written multi-valued, per spec.md's explicit instruction that
## `resource_type` "stays multi-valued for the deferred multi-resource system"; adding a
## second resource must be a `RESOURCE_TYPES` entry, not a refactor.
##
## Nothing here decides tuning. The passive Wood RATE (~1 Wood / forest tile / 60 s, #8)
## is deliberately not a field: it belongs to the economy evaluator (row 5), not to a
## per-tile definition, in the same way the habitat-to-individuals curve is deliberately
## not a field on AnimalDefinition.

## The v1 resource vocabulary. One entry today; the list is the extension point.
## Stored as a self-documenting lowercase String so a `.tres` reads without a lookup —
## the same ruling `AnimalDefinition.personality` carries, and with the same consequence:
## `validate()` is load-bearing, because the type system cannot reject a bad value.
const RESOURCE_WOOD: String = "wood"
const RESOURCE_TYPES: PackedStringArray = [RESOURCE_WOOD]

## The `land_use` domain, exactly as spec.md states it: `cultivated | wild`.
const LAND_USE_CULTIVATED: String = "cultivated"
const LAND_USE_WILD: String = "wild"
const LAND_USES: PackedStringArray = [LAND_USE_CULTIVATED, LAND_USE_WILD]


## Unique harvestable id, in the shared lowercase-snake convention (`forest_harvest`).
@export var id: String = ""

## Player-facing name (`Forest`).
@export var display_name: String = ""

## What this tile produces. One of RESOURCE_TYPES — `wood` in v1.
@export_enum("wood") var resource_type: String = RESOURCE_WOOD

## Whether the yield comes from cultivated or wild land. One of LAND_USES.
@export_enum("cultivated", "wild") var land_use: String = LAND_USE_WILD

## Does harvesting strip the tile's habitat tags?
##
## FALSE FOR FOREST, and that is a pillar obligation rather than a tuning value:
## terrain.md calls Forest "zero-downside by design", and gdd.md's free-Forest recovery
## guarantee (Tier 1 row 5) depends on a player never being punished for the one action
## that always earns Wood. A `true` here for Forest would break the no-dead-ends floor.
@export var removes_habitat_when_harvested: bool = false

## NO `model_scene` HERE — deliberately (human decision 2026-07-27, -> D-26).
##
## This resource describes a YIELD RULE, not a thing on the ground. The model belongs to
## the host TerrainDefinition, which is the only place that can own it: the moment two
## terrains share one yield rule (a future Old-Growth Forest also producing Wood on
## identical terms), a `model_scene` on the rule would have to be two models at once.
##
## That shared-rule case is the whole reason this is a separate resource rather than
## fields folded into TerrainDefinition. Growing the set of harvestables is an argument
## for keeping the split and AGAINST carrying a model here.


## Normalizes a harvestable id to the shared convention.
static func normalize_id(raw_id: String) -> String:
	return raw_id.strip_edges().to_snake_case().to_lower()


## Non-fatal schema check. Returns human-readable problems; an empty array means clean.
## Never raises and never mutates.
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

	# The only thing standing between a hand-authored typo ("Wood", "timber") and an
	# economy that silently accrues nothing.
	if not RESOURCE_TYPES.has(resource_type):
		problems.append("`resource_type` \"%s\" is not one of %s." % [resource_type, str(RESOURCE_TYPES)])

	if not LAND_USES.has(land_use):
		problems.append("`land_use` \"%s\" is not one of %s." % [land_use, str(LAND_USES)])

	return problems
