class_name AttributionCatalog
extends RefCounted
## The one place that scans `res://attribution/sources/*.tres` into `AttributionEntry`
## resources. Shared by `generate_credits.gd` (the CREDITS.md generator) AND
## `credits_screen.gd` (the in-game Credits screen, Tier 1 row 15), so the two readers of
## this data cannot drift from each other's idea of what's on disk — only from the disk
## itself, which is a content problem, not a UI or tooling one.
##
## Previously this directory scan was hand-duplicated in `generate_credits.gd` and, again,
## in `tests/test_attribution.gd`'s own `_load_entries()`. This file replaces the first;
## the test's copy is left alone (a test asserting against a hand-rolled independent read
## of the same directory is a legitimate second opinion, not drift to fix).

const SOURCES_DIR: String = "res://attribution/sources"


## Every `AttributionEntry` on disk, sorted by filename for a stable, reviewable order.
static func load_entries() -> Array[AttributionEntry]:
	var out: Array[AttributionEntry] = []
	var dir := DirAccess.open(SOURCES_DIR)
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for n: String in names:
		# Exported/imported resources surface as .remap; normalise both, matching
		# generate_credits.gd's own original handling.
		if not (n.ends_with(".tres") or n.ends_with(".tres.remap")):
			continue
		var path := "%s/%s" % [SOURCES_DIR, n.trim_suffix(".remap")]
		var res: Resource = ResourceLoader.load(path)
		if res is AttributionEntry:
			out.append(res as AttributionEntry)
	return out


## Only the entries a license actually obliges us to credit — what the in-game Credits
## screen renders. `CREDITS.md` still lists everything (obligated AND courtesy); this is
## the player-facing subset the license condition itself is about.
static func binding_entries() -> Array[AttributionEntry]:
	var out: Array[AttributionEntry] = []
	for e in load_entries():
		if e.has_binding_obligation():
			out.append(e)
	return out
