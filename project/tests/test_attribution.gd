extends QATestCase
## Attribution compliance regression test.
##
## WHY THIS EXISTS AS A TEST, not just a manual step: as of pilot 3b the project has
## its FIRST binding license obligation (Sherkiz "Rabbit", CC BY 3.0). Shipping the
## build without a visible credit for that model is infringement. `generate_credits.gd`
## already fails closed on an under-documented source, but nothing until now asserted
## that the obligation actually SURVIVES into the rendered CREDITS.md, nor that the
## generator's output is stable.
##
## This test reads the generated artifact and the source entries. It does not run the
## generator (a SceneTree script cannot cleanly invoke another one); run that first:
##   --script res://attribution/generate_credits.gd
## then this. The `check_credits_fresh` assertion below catches a stale artifact.

const SOURCES_DIR: String = "res://attribution/sources"
const CREDITS_PATH: String = "res://CREDITS.md"

## The CC BY 3.0 credit line that must reach the player. Exact-matched: this is a
## license condition, so paraphrase is not compliance.
const REQUIRED_NOTICE_FRAGMENT: String = "\"Rabbit\" by Sherkiz, licensed under CC BY 3.0, via Poly Pizza"


func _init() -> void:
	begin("attribution compliance")

	# --- source entries load and are well-formed ------------------------------
	var entries: Array = _load_entries()
	# 10 -> 12 (SecondAge/character-pack import run): two NEW packs were recorded,
	# quaternius_animated_men_characters and quaternius_animated_women_characters. This
	# count is a deliberate ratchet — it is supposed to fail when an entry lands, so that
	# adding a source is a decision and not a side effect. Bumped here because the two
	# entries are part of the same run, not to silence it.
	check_eq(entries.size(), 13, "13 attribution sources on disk")

	var binding: Array = []
	var by_id: Dictionary = {}
	for e in entries:
		by_id[e.id] = e
		if e.has_binding_obligation():
			binding.append(e)

	check_eq(binding.size(), 1, "exactly 1 source carries a binding obligation")
	check(by_id.has("sherkiz_rabbit"), "sherkiz_rabbit entry exists")
	check(by_id.has("quaternius_ultimate_animated_animals"), "quaternius entry exists")
	check(by_id.has("quaternius_animated_men_characters"),
		"quaternius_animated_men_characters entry exists")
	check(by_id.has("quaternius_animated_women_characters"),
		"quaternius_animated_women_characters entry exists")

	# The corrected Man attribution, asserted so it cannot silently revert: Man belongs to
	# the Animated Men Characters pack (as Male_Casual), NOT to the standalone
	# poly.pizza-download entry it used to sit in. CC0 both ways, so this is a
	# truthfulness check on the record, not a compliance check.
	if by_id.has("quaternius_poly_pizza_characters"):
		var pp = by_id["quaternius_poly_pizza_characters"]
		var pp_names: PackedStringArray = pp.asset_names()
		check(not pp_names.has("Man"),
			"\"Man\" no longer listed under the standalone poly.pizza entry",
			"assets_used=%s" % pp_names)
	if by_id.has("quaternius_animated_men_characters"):
		var men = by_id["quaternius_animated_men_characters"]
		var men_names: PackedStringArray = men.asset_names()
		var has_casual: bool = false
		for n: String in men_names:
			if n.begins_with("Male_Casual"):
				has_casual = true
		check(has_casual, "Male_Casual (the shipped Man.glb) is listed under its real pack",
			"assets_used=%s" % men_names)
		check(FileAccess.file_exists(men.license_file),
			"men's pack license_file exists on disk: %s" % men.license_file)
	if by_id.has("quaternius_animated_women_characters"):
		var women = by_id["quaternius_animated_women_characters"]
		check(FileAccess.file_exists(women.license_file),
			"women's pack license_file exists on disk: %s" % women.license_file)

	if by_id.has("sherkiz_rabbit"):
		var s = by_id["sherkiz_rabbit"]
		check(s.attribution_required, "Sherkiz entry is marked attribution_required")
		check(s.has_binding_obligation(), "Sherkiz entry reports a binding obligation")
		check(not s.required_notice.strip_edges().is_empty(),
			"Sherkiz entry supplies a required_notice")
		check(s.license_name.contains("CC BY 3.0"), "Sherkiz license is CC BY 3.0",
			"got: %s" % s.license_name)
		# The license text must be in-repo and readable, not just referenced by URL —
		# creativecommons.org was unreachable from this container.
		check(not s.license_file.is_empty(), "Sherkiz entry names a license_file")
		check(FileAccess.file_exists(s.license_file),
			"license_file exists on disk: %s" % s.license_file)

	if by_id.has("quaternius_ultimate_animated_animals"):
		var q = by_id["quaternius_ultimate_animated_animals"]
		check(not q.has_binding_obligation(),
			"Quaternius (CC0) carries no binding obligation")

	# --- the obligation reaches the generated artifact -------------------------
	check(FileAccess.file_exists(CREDITS_PATH), "CREDITS.md exists")
	var f: FileAccess = FileAccess.open(CREDITS_PATH, FileAccess.READ)
	if not check(f != null, "CREDITS.md is readable"):
		finish()
		return
	var credits: String = f.get_as_text()
	f.close()

	check(credits.contains("## Required attributions"),
		"CREDITS.md has a Required attributions section")
	check(credits.contains("## Acknowledgements"),
		"CREDITS.md has an Acknowledgements section")
	check(credits.contains(REQUIRED_NOTICE_FRAGMENT),
		"the CC BY 3.0 credit line appears VERBATIM in CREDITS.md",
		"missing: %s" % REQUIRED_NOTICE_FRAGMENT)

	# Placement matters: a binding obligation filed under "no obligation" would be
	# actively misleading to whoever builds the Credits screen.
	var req_at: int = credits.find("## Required attributions")
	var ack_at: int = credits.find("## Acknowledgements")
	var sherkiz_at: int = credits.find("### Sherkiz")
	var quat_at: int = credits.find("### Quaternius")
	check(req_at != -1 and ack_at != -1 and sherkiz_at > req_at and sherkiz_at < ack_at,
		"Sherkiz is filed under Required attributions")
	check(quat_at > ack_at, "Quaternius is filed under Acknowledgements")

	# --- the artifact is not stale --------------------------------------------
	# Every source's creator + license must appear somewhere in the rendered file. A
	# newly-added entry that was never regenerated fails here.
	for e in entries:
		check(credits.contains(e.creator),
			"CREDITS.md mentions source creator \"%s\" (not stale)" % e.creator)
		check(credits.contains(e.license_name),
			"CREDITS.md states license for \"%s\"" % e.creator)

	finish()


func _load_entries() -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(SOURCES_DIR)
	if dir == null:
		return out
	var names: PackedStringArray = dir.get_files()
	names.sort()
	for n: String in names:
		if not (n.ends_with(".tres") or n.ends_with(".tres.remap")):
			continue
		var res: Resource = ResourceLoader.load("%s/%s" % [SOURCES_DIR, n.trim_suffix(".remap")])
		if res != null and res is AttributionEntry:
			out.append(res)
	return out
