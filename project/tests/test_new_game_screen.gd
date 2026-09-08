extends QATestCase
## NEW GAME SCREEN'S PRESET CARDS (2026-08-24) — Open Question #10 grew from one preset to
## three, rendered as selectable radio-style cards. This suite pins the two things that are
## genuinely new: the cards render in the curated order (not `WorldPreset.load_all()`'s own
## alphabetical order, which would put Barren before Meadow), and selecting one is a real
## radio — exactly one card is ever pressed.
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
	_check_meadow_is_the_default_selection()
	_check_selecting_a_card_is_a_real_radio()
	_check_copy_is_written()

	finish()
	return true


func _check_cards_render_in_curated_order() -> void:
	var row: HBoxContainer = _screen.get_node("%PresetRow") as HBoxContainer
	check_eq(row.get_child_count(), 3, "all three presets on disk got a card")

	var labels: Array[String] = []
	for i: int in row.get_child_count():
		labels.append((row.get_child(i) as Button).text)
	check_eq(labels, ["Meadow Start", "Barren", "Forested"],
		"cards render in the curated PRESET_ORDER, not WorldPreset.load_all()'s own "
		+ "alphabetical order (which would put Barren before Meadow)")


func _check_meadow_is_the_default_selection() -> void:
	var row: HBoxContainer = _screen.get_node("%PresetRow") as HBoxContainer
	var meadow: Button = row.get_child(0) as Button
	check(meadow.button_pressed, "Meadow (the first card) is pressed by default")
	for i: int in range(1, row.get_child_count()):
		check(not (row.get_child(i) as Button).button_pressed,
			"...and %s is not" % (row.get_child(i) as Button).text)


func _check_selecting_a_card_is_a_real_radio() -> void:
	var row: HBoxContainer = _screen.get_node("%PresetRow") as HBoxContainer
	var meadow: Button = row.get_child(0) as Button
	var barren: Button = row.get_child(1) as Button
	var forested: Button = row.get_child(2) as Button

	barren.pressed.emit()
	check(barren.button_pressed, "pressing Barren selects it")
	check(not meadow.button_pressed, "...and un-selects Meadow")
	check(not forested.button_pressed, "...Forested was never selected")

	forested.pressed.emit()
	check(forested.button_pressed, "pressing Forested selects it")
	check(not barren.button_pressed,
		"...and un-selects Barren — exactly one card is ever pressed, not an accumulating set")


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
