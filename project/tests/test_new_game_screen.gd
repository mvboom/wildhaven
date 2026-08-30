extends QATestCase
## NEW GAME SCREEN'S PRESET CARDS (2026-08-24) — Open Question #10 grew from one preset to
## three, rendered as selectable radio-style cards. This suite pins the two things that are
## genuinely new: the cards render in the curated order (not `WorldPreset.load_all()`'s own
## alphabetical order, which would put Barren before Meadow), and selecting one is a real
## radio — exactly one card is ever pressed.
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
