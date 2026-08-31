extends QATestCase
## NO UI TEXT MAY USE A CODEPOINT THE BUNDLED FONT LACKS.
##
## THE BUG CLASS THIS EXISTS TO END. This project ships no custom font, so every piece of
## text renders through Godot's bundled default (`ThemeDB.fallback_font` — Open Sans
## SemiBold). In the editor and in a desktop build, a codepoint that font lacks is quietly
## rescued by the OS's system-font fallback, so it looks correct on the machine that authored
## it. **The HTML5/Web export has no system fontconfig and no such rescue** — it draws a
## missing-glyph "tofu" box instead. The failure is therefore invisible everywhere except the
## one target players actually use.
##
## It has now happened three times:
##   1. `rotate_icon.gd`           — U+21BA/U+21BB "↺/↻", human-reported from a web screenshot
##   2. `popup_indicator_glyph.gd` — U+25BE "▾", caught in review
##   3. `fact_card.gd` / `displacement_notice.gd` — U+1F50A/U+1F507 "🔊/🔇", the Read-Aloud
##      button, human-reported ("the sound icon is broken on the web builds")
##
## Both earlier fixes were one-off: replace the glyph with a vector-drawn `Control` that calls
## `draw_*()` in `_draw()`, which cannot depend on font coverage on any export target. Neither
## left anything behind that would catch the NEXT one. This suite is that thing.
##
## WHY `ThemeDB.fallback_font.has_char()` IS THE RIGHT ORACLE: it reports the bundled font's
## own coverage and does NOT consult the OS fallback, so it answers the web export's question
## ("would this draw a tofu box?") while running in a container that has the system fonts which
## would otherwise mask the answer. Verified against the two already-fixed codepoints — see
## `_check_the_oracle_itself()`, which fails loudly if that ever stops being true.
##
## TWO PASSES, because a glyph can arrive by either route:
##   - RUNTIME: instantiate the affected scenes and walk the live tree, so text a script
##     assigns in `_ready()` is caught (this is how `fact_card.gd` sets its 🔊).
##   - AUTHORED: sweep every `text = "..."` literal in every `.tscn`, so a glyph typed
##     straight into a scene is caught even in a scene this suite does not instantiate.
##
## Run:
##   bash scripts/run-tests.sh font_glyph_coverage

## Scenes whose live tree is walked after `_ready()` has run. Add a scene here when it grows a
## script-assigned glyph; the authored sweep below already covers every scene in the project.
const RUNTIME_SCENES: Array[String] = [
	"res://scenes/ui/FactCard.tscn",
	"res://scenes/ui/DisplacementNotice.tscn",
]

const SCENE_DIRS: Array[String] = ["res://scenes"]

## Codepoints that are structural rather than drawn — no glyph is looked up for these.
const SKIPPED_CODEPOINTS: Array[int] = [0x09, 0x0A, 0x0D, 0x20]

## Already-fixed instances of this exact bug. The oracle must keep reporting these as
## uncovered; if it ever says they are fine, `has_char()` has started consulting a fallback
## this suite cannot see and every other assertion here has quietly become worthless.
const KNOWN_UNCOVERED: Dictionary = {
	0x21BA: "U+21BA ROTATE CCW — fixed by rotate_icon.gd",
	0x25BE: "U+25BE SMALL TRIANGLE DOWN — fixed by popup_indicator_glyph.gd",
}

var _font: Font = null


func _initialize() -> void:
	begin("font glyph coverage")

	_font = ThemeDB.fallback_font
	if not check(_font != null, "ThemeDB.fallback_font resolves"):
		finish()
		return
	print("  bundled font: %s" % _font.get_font_name())

	_check_the_oracle_itself()
	_check_runtime_scene_text()
	_check_authored_scene_text()

	finish()


## Guards the guard. See KNOWN_UNCOVERED.
func _check_the_oracle_itself() -> void:
	check(_font.has_char(0x41), "the oracle reports a plain letter as covered")
	for codepoint: int in KNOWN_UNCOVERED:
		check(
			not _font.has_char(codepoint),
			"the oracle still reports %s as uncovered" % KNOWN_UNCOVERED[codepoint],
			"has_char() started consulting a system fallback — every assertion in this suite "
			+ "is now unreliable, because the web export has no such fallback"
		)


func _check_runtime_scene_text() -> void:
	for scene_path: String in RUNTIME_SCENES:
		var packed: PackedScene = load(scene_path) as PackedScene
		if not check(packed != null, "%s loads" % scene_path):
			continue
		var instance: Node = packed.instantiate()
		root.add_child(instance)
		var offenders: PackedStringArray = PackedStringArray()
		_collect_uncovered_in_tree(instance, instance, offenders)
		check(
			offenders.is_empty(),
			"%s renders no codepoint the bundled font lacks" % scene_path.get_file(),
			"\n        ".join(offenders)
		)
		instance.queue_free()
		root.remove_child(instance)


func _collect_uncovered_in_tree(node: Node, scene_root: Node, offenders: PackedStringArray) -> void:
	var text: String = ""
	if node is Button:
		text = (node as Button).text
	elif node is Label:
		text = (node as Label).text
	elif node is RichTextLabel:
		text = (node as RichTextLabel).text
	if text != "":
		var where: String = str(scene_root.get_path_to(node))
		_report_uncovered(text, where, offenders)
	for child: Node in node.get_children():
		_collect_uncovered_in_tree(child, scene_root, offenders)


func _check_authored_scene_text() -> void:
	var scene_files: PackedStringArray = PackedStringArray()
	for dir_path: String in SCENE_DIRS:
		_collect_scene_files(dir_path, scene_files)
	check(scene_files.size() > 0, "%d scene files were swept" % scene_files.size())

	var offenders: PackedStringArray = PackedStringArray()
	for scene_file: String in scene_files:
		var handle: FileAccess = FileAccess.open(scene_file, FileAccess.READ)
		if handle == null:
			continue
		var line_number: int = 0
		while not handle.eof_reached():
			var line: String = handle.get_line()
			line_number += 1
			var stripped: String = line.strip_edges()
			if not stripped.begins_with("text = \""):
				continue
			var opening: int = stripped.find("\"")
			var closing: int = stripped.rfind("\"")
			if closing <= opening:
				continue
			var literal: String = stripped.substr(opening + 1, closing - opening - 1)
			_report_uncovered(literal, "%s:%d" % [scene_file, line_number], offenders)
		handle.close()

	check(
		offenders.is_empty(),
		"no .tscn authors a `text =` literal the bundled font lacks",
		"\n        ".join(offenders)
	)


func _collect_scene_files(dir_path: String, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect_scene_files(full, out)
		elif entry.ends_with(".tscn"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _report_uncovered(text: String, where: String, offenders: PackedStringArray) -> void:
	var seen: Dictionary = {}
	for i: int in text.length():
		var codepoint: int = text.unicode_at(i)
		if codepoint in SKIPPED_CODEPOINTS or seen.has(codepoint):
			continue
		seen[codepoint] = true
		if not _font.has_char(codepoint):
			offenders.append(
				"%s uses U+%04X (%s) — the bundled font has no glyph, so the web export "
				% [where, codepoint, char(codepoint)]
				+ "draws a tofu box. Draw it as a vector Control instead (see rotate_icon.gd)."
			)
