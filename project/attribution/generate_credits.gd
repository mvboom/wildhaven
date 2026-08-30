extends SceneTree

## Regenerates res://CREDITS.md from the AttributionEntry resources in
## res://attribution/sources/. The .tres files are the source of truth; CREDITS.md is
## a derived, human-readable view — never hand-edit it, it will be overwritten.
##
## Run:
##   godot --headless --path <project> --script res://attribution/generate_credits.gd
##
## Exit code 1 on any malformed entry, so this doubles as a compliance check QA can
## run: "does every source declare a license, and is every stated obligation spelled
## out?" A source that claims attribution_required but supplies no required_notice is
## a real defect — it means someone knows there is an obligation but not what it is.

const SOURCES_DIR := "res://attribution/sources"
const OUT_PATH := "res://CREDITS.md"

var _errors: PackedStringArray = PackedStringArray()


func _init() -> void:
	var entries := _load_entries()
	if entries.is_empty():
		printerr("No attribution entries found in %s" % SOURCES_DIR)
		quit(1)
		return
	_validate(entries)
	if not _errors.is_empty():
		for e in _errors:
			printerr("ATTRIBUTION DEFECT: %s" % e)
		quit(1)
		return
	var md := _render(entries)
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		printerr("Cannot write %s (err %d)" % [OUT_PATH, FileAccess.get_open_error()])
		quit(1)
		return
	f.store_string(md)
	f.close()
	var binding := 0
	for e in entries:
		if e.has_binding_obligation():
			binding += 1
	print("Wrote %s — %d source(s), %d with binding obligations." % [OUT_PATH, entries.size(), binding])
	quit()


func _load_entries() -> Array[AttributionEntry]:
	var out: Array[AttributionEntry] = []
	var dir := DirAccess.open(SOURCES_DIR)
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for n in names:
		# Exported/imported resources surface as .remap; normalise both.
		if not (n.ends_with(".tres") or n.ends_with(".tres.remap")):
			continue
		var path := "%s/%s" % [SOURCES_DIR, n.trim_suffix(".remap")]
		var res := ResourceLoader.load(path)
		if res is AttributionEntry:
			out.append(res)
		else:
			_errors.append("%s did not load as an AttributionEntry" % path)
	return out


func _validate(entries: Array[AttributionEntry]) -> void:
	var seen := {}
	for e in entries:
		var label := e.id if not e.id.is_empty() else e.source_name
		if e.id.is_empty():
			_errors.append("entry '%s' has no id" % e.source_name)
		elif seen.has(e.id):
			_errors.append("duplicate id '%s'" % e.id)
		else:
			seen[e.id] = true
		if e.creator.is_empty():
			_errors.append("[%s] no creator" % label)
		if e.license_name.is_empty():
			_errors.append("[%s] no license_name" % label)
		if e.attribution_required and e.required_notice.strip_edges().is_empty():
			_errors.append("[%s] attribution_required is true but required_notice is empty" % label)
		if e.per_file_licensing and e.assets.is_empty():
			_errors.append("[%s] per_file_licensing is true but assets is empty" % label)
		if not e.per_file_licensing and not e.assets.is_empty():
			_errors.append("[%s] has per-file assets but per_file_licensing is false" % label)
		for a in e.assets:
			if a == null:
				_errors.append("[%s] null entry in assets" % label)
				continue
			if a.license_name.is_empty():
				_errors.append("[%s/%s] no license_name" % [label, a.asset_name])
			if a.attribution_required and a.required_notice.strip_edges().is_empty():
				_errors.append("[%s/%s] attribution_required but no required_notice" % [label, a.asset_name])


func _link(text: String, url: String) -> String:
	return "[%s](%s)" % [text, url] if not url.is_empty() else text


func _render(entries: Array[AttributionEntry]) -> String:
	var s := "# Credits & Third-Party Licenses\n\n"
	s += "<!-- GENERATED FILE — do not edit by hand.\n"
	s += "     Source of truth: project/attribution/sources/*.tres\n"
	s += "     Regenerate: godot --headless --path project \\\n"
	s += "                   --script res://attribution/generate_credits.gd -->\n\n"
	s += "Wildhaven is built on third-party asset packs. This file is the auditable\n"
	s += "record of what we use and under what terms. A future in-game Credits screen reads\n"
	s += "the same `.tres` entries this file is generated from, so the two cannot drift.\n\n"

	var binding: Array[AttributionEntry] = []
	var courtesy: Array[AttributionEntry] = []
	for e in entries:
		if e.has_binding_obligation():
			binding.append(e)
		else:
			courtesy.append(e)

	s += "## Obligation summary\n\n"
	s += "| Source | License | Crediting |\n|---|---|---|\n"
	for e in entries:
		var duty := "**required by license**" if e.has_binding_obligation() else "courtesy only"
		s += "| %s — %s | %s | %s |\n" % [e.creator, e.source_name, e.license_name, duty]
	s += "\n"
	if binding.is_empty():
		s += "_No source currently imposes a binding condition. This will change the first\n"
		s += "time non-CC0 audio lands — freesound.org is mixed-license and its CC-BY entries\n"
		s += "carry enforceable per-file notices._\n\n"
	else:
		s += "**%d source(s) impose binding conditions — these cannot be cut.**\n\n" % binding.size()

	if not binding.is_empty():
		s += "## Required attributions (license conditions)\n\n"
		for e in binding:
			s += _render_entry(e)

	if not courtesy.is_empty():
		s += "## Acknowledgements (no obligation — credited because we want to)\n\n"
		for e in courtesy:
			s += _render_entry(e)
	return s


func _render_entry(e: AttributionEntry) -> String:
	var s := "### %s — %s\n\n" % [e.creator, _link(e.source_name, e.source_url)]
	if not e.source_version.is_empty():
		s += "- Version: %s\n" % e.source_version
	if not e.creator_url.is_empty():
		s += "- Creator: %s\n" % _link(e.creator_url, e.creator_url)
	s += "- License: %s\n" % _link(e.license_name, e.license_url)
	if not e.license_file.is_empty():
		s += "- License text in repo: `%s`\n" % e.license_file
	s += "- Crediting: %s\n" % ("**required by license**" if e.attribution_required else "not required; shown as courtesy")
	if not e.support_url.is_empty():
		s += "- Support the creator: %s\n" % _link(e.support_url, e.support_url)
	var names := e.asset_names()
	if not names.is_empty():
		s += "- Assets used: %s\n" % ", ".join(names)
	s += "\n"
	if not e.required_notice.strip_edges().is_empty():
		# Deliberately NOT labelled "verbatim": a required notice is sometimes quoted
		# from the author and sometimes constructed from creator/title/licence when the
		# author supplied none. The entry's `notes` records which. Do not reintroduce a
		# word here that asserts provenance this renderer cannot know.
		s += "Required credit line:\n\n> %s\n\n" % e.required_notice.strip_edges().replace("\n", "\n> ")
	if not e.conditions.strip_edges().is_empty():
		s += "Further binding conditions:\n\n> %s\n\n" % e.conditions.strip_edges().replace("\n", "\n> ")
	if e.per_file_licensing:
		s += "Per-file licensing — each asset below carries its own terms:\n\n"
		s += "| Asset | Author | License | Crediting |\n|---|---|---|---|\n"
		for a in e.assets:
			if a == null:
				continue
			var duty := "**required**" if a.attribution_required else "courtesy"
			s += "| %s | %s | %s | %s |\n" % [
				_link(a.asset_name, a.source_url), a.author,
				_link(a.license_name, a.license_url), duty]
		s += "\n"
		for a in e.assets:
			if a != null and a.attribution_required and not a.required_notice.strip_edges().is_empty():
				s += "- **%s** — required notice: %s\n" % [a.asset_name, a.required_notice.strip_edges()]
		s += "\n"
	return s
