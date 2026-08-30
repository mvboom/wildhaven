@tool
class_name AttributionAsset
extends Resource

## One individually-licensed asset within a source.
##
## Only needed when a source licenses its files INDIVIDUALLY rather than under one
## blanket license — freesound.org is the motivating case: two sounds from the same
## site can be CC0 and CC-BY, and the CC-BY one carries an enforceable per-file
## notice naming that specific uploader.
##
## For a uniformly-licensed source (Quaternius: whole pack is CC0), do NOT use this —
## list the file names in AttributionEntry.assets_used instead.

## File or asset name as used in-game, e.g. "Fox" or "forest_ambience_dawn.ogg".
@export var asset_name: String = ""

## Res path of the imported asset, if useful for auditing. Optional.
@export var asset_path: String = ""

## Who made THIS file (uploader/creator), when it differs from the source's creator.
@export var author: String = ""

## Direct link to this file's page on the source site.
@export var source_url: String = ""

## e.g. "CC BY 4.0", "CC0 1.0", "CC BY-NC 3.0".
@export var license_name: String = ""
@export var license_url: String = ""

## TRUE when this file's license legally obliges us to credit it.
## This is the field that must be honest — see AttributionEntry.attribution_required.
@export var attribution_required: bool = false

## The exact credit line the license demands, verbatim, when attribution_required.
## Leave empty when nothing is required.
@export_multiline var required_notice: String = ""

## Anything else binding: non-commercial clauses, share-alike, no-derivatives,
## modification disclosure. Empty means no further conditions.
@export_multiline var conditions: String = ""
