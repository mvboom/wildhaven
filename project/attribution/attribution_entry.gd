@tool
class_name AttributionEntry
extends Resource

## One third-party SOURCE (an asset pack, a sound library, a font foundry) — not one
## asset and not one species. A single pack supplies many game entities, so the entry
## is pack-level and lists what we actually used from it.
##
## Two shapes, pick one per entry:
##
##   Uniform license   — whole source under one license (Quaternius pack = all CC0).
##                       Fill license_name/license_url/attribution_required, and list
##                       file names in assets_used. Leave assets empty.
##
##   Per-file license  — source licenses each file separately (freesound.org).
##                       Set per_file_licensing = true, leave assets_used empty, and
##                       add one AttributionAsset per file to assets. The source-level
##                       license fields then describe the SITE, not the files, and
##                       attribution_required is the OR of the per-file flags.
##
## Source of truth: these .tres files. CREDITS.md is generated from them — see
## res://attribution/generate_credits.gd.

## Stable machine id, e.g. "quaternius_ultimate_animated_animals".
@export var id: String = ""

## Creator / studio / site as it should appear on screen.
@export var creator: String = ""

## Pack or library name, e.g. "Ultimate Animated Animal Pack".
@export var source_name: String = ""

## Release or retrieval date, e.g. "July 2021". Free text — packs version informally.
@export var source_version: String = ""

@export_group("Links")
## Creator's home page.
@export var creator_url: String = ""
## Where the source was obtained, if different from creator_url.
@export var source_url: String = ""
## Optional support/donate link. Not an obligation — included when the creator asks
## for it, because it costs nothing. Quaternius asks for Patreon in its License.txt.
@export var support_url: String = ""

@export_group("License")
## e.g. "CC0 1.0 Universal", "CC BY 4.0", "Synty Store EULA".
@export var license_name: String = ""
@export var license_url: String = ""

## Res path to the license text preserved IN THIS REPO. Keep a copy — a link can rot,
## and a compliance review should be answerable offline.
@export var license_file: String = ""

## THE FIELD THAT MATTERS.
## FALSE = crediting is courtesy; we may ship without it (CC0, public domain).
## TRUE  = crediting is a license CONDITION; shipping without it is infringement.
## Never default this to true "to be safe" — a false claim of obligation is its own
## kind of wrong, and it hides the entries where the obligation is real.
@export var attribution_required: bool = false

## When attribution_required, the exact notice the license demands, verbatim.
@export_multiline var required_notice: String = ""

## Binding terms beyond attribution: redistribution limits, non-commercial,
## share-alike, seat/EULA restrictions. Empty means none. Synty and CC-BY-* land here.
@export_multiline var conditions: String = ""

@export_group("Assets used")
## Uniform-license sources: what we took. Grow this as more of the pack is used.
@export var assets_used: PackedStringArray = PackedStringArray()

## Per-file-license sources: set true and use `assets` instead of `assets_used`.
@export var per_file_licensing: bool = false

## Per-file entries. Only for per_file_licensing sources.
@export var assets: Array[AttributionAsset] = []

@export_group("Notes")
## Anything a future compliance review should know. Not shown on the Credits screen.
@export_multiline var notes: String = ""


## True when this entry, or anything inside it, imposes a real obligation.
func has_binding_obligation() -> bool:
	if attribution_required or not conditions.strip_edges().is_empty():
		return true
	for a in assets:
		if a != null and (a.attribution_required or not a.conditions.strip_edges().is_empty()):
			return true
	return false


## Flat list of asset names, whichever shape the entry uses.
func asset_names() -> PackedStringArray:
	if not per_file_licensing:
		return assets_used
	var out := PackedStringArray()
	for a in assets:
		if a != null:
			out.append(a.asset_name)
	return out
