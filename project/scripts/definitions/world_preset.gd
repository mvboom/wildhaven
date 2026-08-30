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
## v1 ships exactly one preset. Open Question **#10** owns the real list; this file is the shape
## the answer gets authored into.
##
## `base_terrain_id` MUST name a terrain that emits no tags — see `test_world_preset.gd`.

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

## The terrain every tile starts as. Wild grass: visually grass-family, tag-inert, one free
## Terraform tap from true grass (gdd.md -> World Structure).
##
## **NOT YET APPLIED — declared, schema-validated, and read by nobody.** `WorldGrid.build()` fills
## every tile with `WorldGrid.START_TERRAIN_ID` unconditionally, so changing this value on the
## shipped preset changes NOTHING about the world a New Game produces. It is harmless today only
## because the two happen to be the same id. Whoever authors the second preset (Open Question
## **#10**) must wire it up first — deliberately not done here, because the obvious wiring puts
## ~1,296 `set_terrain()` calls into the `_ready()` that all 57 suites run through.
@export var base_terrain_id: String = WorldGrid.START_TERRAIN_ID


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
