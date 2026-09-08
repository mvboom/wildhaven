class_name WorldPreset
extends Resource
## A New Game starting world — Tier 1 row 1's "fixed preset", as data.
##
## gdd.md -> World Structure: "**World presets** ('Jungle Start,' ...) set starting terrain
## only, **never content gates**: every animal is eligible everywhere, gated purely by habitat
## tags — a Jungle-start player can dig a lake and get ducks." There is therefore deliberately
## **no species field, no unlock field and no gate field on this resource**, and adding one
## would be a pillar-level change, not a data change.
##
## Open Question **#10** owns the preset list. Its first half (which presets exist) closed
## 2026-08-24 with three cards; its second half (what terrain each one actually builds) closed
## 2026-09-07 -> **D-53**, which is `terrain_mix` below. Before D-53 all three presets built the
## same tag-inert wild grass and the difference between the cards was a label.
##
## `base_terrain_id` MUST name a terrain that emits no tags — see `test_world_preset.gd`.
## `terrain_mix` deliberately need not; see its own comment.

const DATA_DIR: String = "res://data/presets"

## The preset `default_preset()` prefers when it exists — the one every fallback path (an
## editor F6 run, a world opened with no menu at all) should build, regardless of how many
## other presets #10 adds. 2026-08-24: #10 grew from one preset to three (New Game screen's
## selectable Meadow/Barren/Forested cards); before that, "default" and "only" were the same
## preset by construction and this constant didn't need to exist.
const DEFAULT_PRESET_ID: String = "meadow_start"

@export var id: String = ""
@export var display_name: String = ""
@export var width: int = WorldGrid.DEFAULT_WIDTH
@export var depth: int = WorldGrid.DEFAULT_DEPTH

## The terrain a tile starts as when `terrain_mix` is empty. Wild grass: visually
## grass-family, tag-inert, one free Terraform tap from true grass (gdd.md -> World Structure).
##
## MUST STAY TAG-INERT (`test_world_preset.gd`). `terrain_mix` below is the field that may
## name tag-emitting terrain; this one is the floor a preset falls back to, and a preset whose
## FLOOR emits tags would hand the player capacity on frame one with nothing to fall back to.
@export var base_terrain_id: String = WorldGrid.START_TERRAIN_ID

## THE STARTING TERRAIN MIX — terrain id -> relative weight. Open Question **#10**'s second
## half, closed 2026-09-07 (-> D-53).
##
## **EMPTY IS THE DEFAULT AND IS LOAD-BEARING**, not an unfinished entry: an empty mix means
## "`base_terrain_id` everywhere", which is byte-identical to the world every build before this
## one produced. `barren_start` ships empty deliberately, and so does every preset a test or an
## editor F6 run resolves to, because `WorldRoot` applies the mix ONLY on a real `"new"` intent
## — see the comment at its `grid.build()` call for why that gate is not optional.
##
## Weights are RELATIVE. The shipped presets are authored as fractions because that reads best
## in the `.tres`, but nothing requires them to total 1.0; `TerrainScatter.quotas()` normalizes.
##
## WHERE the tiles land is `TerrainScatter`'s job, not this file's — clumped by a seeded noise
## field, so a share arrives as ponds and stands rather than scattered single tiles.
##
## **THIS FIELD MAY NAME TAG-EMITTING TERRAIN, AND THAT IS THE POINT.** It is the one place in
## the project where the inert-land invariant is deliberately not in force: D-53 ruled that a
## Meadow or Forested start hands the player live habitat from frame one (Rabbit can qualify on
## the meadow, the water species on the ponds) because "choose a starting land" is meaningless
## if every choice builds the same tag-inert grass. The invariant still holds everywhere it was
## written for — revealed mist land (`MistReveal`), `wild_grass` itself
## (`TerrainDefinition.validate()`), and `base_terrain_id` above.
@export var terrain_mix: Dictionary = {}


static func load_all() -> Array[WorldPreset]:
	var out: Array[WorldPreset] = []
	var dir: DirAccess = DirAccess.open(DATA_DIR)
	if dir == null:
		push_error("WorldPreset: cannot open %s" % DATA_DIR)
		return out
	for filename: String in dir.get_files():
		# Godot exports .tres as .tres.remap; strip it or an exported build finds nothing.
		var name: String = filename.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var res: Resource = load("%s/%s" % [DATA_DIR, name])
		if res is WorldPreset:
			out.append(res as WorldPreset)
	out.sort_custom(func(a: WorldPreset, b: WorldPreset) -> bool: return a.id < b.id)
	return out


## The preset every fallback path builds when nothing more specific was requested. Prefers
## `DEFAULT_PRESET_ID` ("meadow_start") if it exists on disk; falls back to whatever
## `load_all()` sorts first (alphabetically) only if it doesn't — e.g. a dev checkout that
## deleted meadow_start.tres, not a case this project ships. The New Game screen itself does
## NOT call this — it orders and defaults its own cards explicitly (`NewGameScreen.
## PRESET_ORDER`), independent of whatever this function returns.
static func default_preset() -> WorldPreset:
	var all: Array[WorldPreset] = load_all()
	if all.is_empty():
		return null
	for preset: WorldPreset in all:
		if preset.id == DEFAULT_PRESET_ID:
			return preset
	return all[0]
