extends QATestCase
## NEW GAME SCREEN'S PRESET CARDS (2026-08-24) — Open Question #10 grew from one preset to
## three, rendered as selectable radio-style cards. This suite pins the two things that are
## genuinely new: the cards render in `NewGameScreen.PRESET_ORDER`, not `WorldPreset.load_all()`'s
## own alphabetical order, and selecting one is a real radio — exactly one card is ever pressed.
##
## THE CURATED ORDER IS READ, NOT RESTATED (2026-09-08). This suite used to hardcode
## `["Meadow", "Barren", "Forested"]`, so the human reordering `PRESET_ORDER` in the screen's own
## source — which is where that decision belongs, and whose first entry is also the default
## selection — failed this suite for doing exactly what it is for. Every check below now derives
## its expectation from `PRESET_ORDER` and the cards' own text. What stays pinned is the
## PROPERTY: the row follows the curated list, the first card starts selected, and pressing one
## releases the others.
##
## ALSO PINNED (2026-09-08): this screen's player-facing copy is WRITTEN, not stubbed. Both
## captions shipped as `[COPY]` placeholders — the marker this project uses for text the human
## has not ruled on — and a playtester would have read "[COPY] choose a starting land" on
## screen. `_check_copy_is_written()` below asserts the marker is gone rather than asserting the
## exact wording: the words are the human's to change at any time, the placeholder state is not
## something to drift back into. Same posture, opposite direction, to
## `test_neighborhood_preview.gd`'s assertion that ITS two band strings are still stubs.
##
## Run:
##   bash scripts/run-tests.sh new_game_screen

const SCENE_PATH: String = "res://scenes/menu/NewGameScreen.tscn"

var _screen: Control = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("new game screen")
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if not check(packed != null, "%s loads" % SCENE_PATH):
		finish()
		return
	_screen = packed.instantiate() as Control
	root.add_child(_screen)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 2:
		return false

	_check_cards_render_in_curated_order()
	_check_the_first_curated_card_is_the_default_selection()
	_check_selecting_a_card_is_a_real_radio()
	_check_copy_is_written()

	finish()
	return true


func _check_cards_render_in_curated_order() -> void:
	var row: HBoxContainer = _screen.get_node("%PresetRow") as HBoxContainer
	check_eq(row.get_child_count(), 3, "all three presets on disk got a card")

	# The expectation is BUILT FROM `PRESET_ORDER` itself, mapped through each preset's own
	# `display_name` — the same two sources the screen builds the row from, read independently
	# rather than copied. A card order that ignored the curated list (alphabetical, or
	# `load_all()`'s raw order) still fails this; a human reordering the curated list does not.
	var by_id: Dictionary = {}
	for preset: WorldPreset in WorldPreset.load_all():
		by_id[preset.id] = preset.display_name
	# `new_game_screen.gd` declares no `class_name`, so the constant is read off the live
	# screen's own script rather than through a global type — same object under test, no second
	# copy of the list anywhere in this file.
	var order: Array = (
		_screen.get_script().get_script_constant_map().get("PRESET_ORDER", []) as Array
	)
	if not check(not order.is_empty(), "NewGameScreen.PRESET_ORDER is readable and non-empty"):
		return
	var expected: Array[String] = []
	for id: String in order:
		if by_id.has(id):
			expected.append(by_id[id] as String)

	var labels: Array[String] = []
	for i: int in row.get_child_count():
		labels.append((row.get_child(i) as Button).text)
	check_eq(labels, expected,
		"cards render in NewGameScreen.PRESET_ORDER, not WorldPreset.load_all()'s own "
		+ "alphabetical order")


## The default selection is `_presets[0]` — whichever preset the human put FIRST in
## `PRESET_ORDER`, not a named one. Asserted positionally for that reason.
func _check_the_first_curated_card_is_the_default_selection() -> void:
	var row: HBoxContainer = _screen.get_node("%PresetRow") as HBoxContainer
	var first: Button = row.get_child(0) as Button
	check(first.button_pressed,
		"%s (the first card in the curated order) is pressed by default" % first.text)
	for i: int in range(1, row.get_child_count()):
		check(not (row.get_child(i) as Button).button_pressed,
			"...and %s is not" % (row.get_child(i) as Button).text)


func _check_selecting_a_card_is_a_real_radio() -> void:
	var row: HBoxContainer = _screen.get_node("%PresetRow") as HBoxContainer
	# Positional, and named that way: which preset sits in which slot is `PRESET_ORDER`'s
	# business (the human's), while "exactly one card is ever pressed" is this check's.
	var first: Button = row.get_child(0) as Button
	var second: Button = row.get_child(1) as Button
	var third: Button = row.get_child(2) as Button

	second.pressed.emit()
	check(second.button_pressed, "pressing %s selects it" % second.text)
	check(not first.button_pressed, "...and un-selects %s" % first.text)
	check(not third.button_pressed, "...%s was never selected" % third.text)

	third.pressed.emit()
	check(third.button_pressed, "pressing %s selects it" % third.text)
	check(not second.button_pressed,
		"...and un-selects %s — exactly one card is ever pressed, not an accumulating set"
			% second.text)


## THE COPY IS RULED. Asserts the `[COPY]` marker is absent from every Label on this screen —
## not that any specific string is present. Wording is the human's call and may change without
## touching this suite; regressing to a placeholder, or adding a new stubbed caption, may not.
func _check_copy_is_written() -> void:
	var labels: Array[Node] = []
	_collect_labels(_screen, labels)
	check(not labels.is_empty(), "the screen has captions to check")
	for node: Node in labels:
		var label: Label = node as Label
		check(
			not label.text.contains("[COPY]"),
			"`%s` reads as finished copy, not a placeholder" % label.name,
			"on screen a player would literally read: %s" % label.text
		)


func _collect_labels(node: Node, out: Array[Node]) -> void:
	if node is Label:
		out.append(node)
	for child: Node in node.get_children():
		_collect_labels(child, out)
