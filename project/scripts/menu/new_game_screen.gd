extends Control
## NEW GAME — Tier 1 row 1's "fixed preset -> name -> in".
##
## 2026-08-24: Open Question #10 grew from one preset to three (Meadow/Barren/Forested),
## rendered as selectable radio-style cards — human decision this session. Deliberately
## STILL DEFERRED: `base_terrain_id` differentiation. All three presets currently build the
## same tag-inert `wild_grass` start (see each `.tres`'s own header) — the cards are real and
## selectable today, but which terrain each one actually produces is a separate ruling.
##
## THE NAME FIELD IS PRE-FILLED so a six-year-old can press the big button without typing
## anything. Naming is never destructive: a colliding name auto-suffixes inside
## `SaveStore.unique_path_for()`, so there is no prompt, no overwrite, and no way to lose a
## world by retyping one.
##
## BACK GOES TO THE TITLE SCREEN, not Saved Worlds — New Game is now reached directly from
## the title screen (2026-08-24 title redesign), so its own Back mirrors that same entry
## point rather than a screen this flow no longer passes through.

const WORLD_SCENE: String = "res://scenes/Main.tscn"
const TITLE_SCENE: String = "res://scenes/TitleScreen.tscn"

## PROPOSED (2026-08-01) — the human owns player-facing copy; content-writer's checklist
## applies. Pre-filled so pressing straight through works.
const DEFAULT_WORLD_NAME: String = "Wildhaven"

## Display order for the preset cards — deliberately NOT `WorldPreset.load_all()`'s own
## alphabetical order (which would put Barren before Meadow). Any preset id not in this list
## still renders, appended after — future presets #10 might add later aren't silently lost,
## they just don't get a curated position yet.
const PRESET_ORDER: Array[String] = ["meadow_start", "barren_start", "forested_start"]

@onready var _preset_row: HBoxContainer = %PresetRow
@onready var _name_field: LineEdit = %NameField
@onready var _start_button: Button = %StartButton
@onready var _back_button: Button = %BackButton

var _presets: Array[WorldPreset] = []
var _selected_preset: WorldPreset = null


func _ready() -> void:
	_presets = _ordered_presets()
	if _presets.is_empty():
		push_error("NewGameScreen: no presets in %s." % WorldPreset.DATA_DIR)
		_start_button.disabled = true
		return

	_selected_preset = _presets[0]
	for preset: WorldPreset in _presets:
		_preset_row.add_child(_make_preset_card(preset))
	_refresh_preset_cards()

	_name_field.text = DEFAULT_WORLD_NAME
	_name_field.select_all()

	_start_button.pressed.connect(_on_start)
	_back_button.pressed.connect(func() -> void: _go(TITLE_SCENE))
	# Enter starts the world, so the keyboard path and the button path are the same path.
	_name_field.text_submitted.connect(func(_t: String) -> void: _on_start())

	_start_button.grab_focus()


## `WorldPreset.load_all()`'s own presets, reordered per `PRESET_ORDER` (any id not listed
## there is appended after, in whatever order `load_all()` already gave it — alphabetical).
func _ordered_presets() -> Array[WorldPreset]:
	var all: Array[WorldPreset] = WorldPreset.load_all()
	var by_id: Dictionary = {}
	for preset: WorldPreset in all:
		by_id[preset.id] = preset

	var ordered: Array[WorldPreset] = []
	for id: String in PRESET_ORDER:
		if by_id.has(id):
			ordered.append(by_id[id] as WorldPreset)
			by_id.erase(id)
	for preset: WorldPreset in all:
		if by_id.has(preset.id):
			ordered.append(preset)
	return ordered


func _make_preset_card(preset: WorldPreset) -> Button:
	var card := Button.new()
	card.text = preset.display_name
	card.toggle_mode = true
	card.custom_minimum_size = Vector2(140, 60)
	card.pressed.connect(func() -> void: _select_preset(preset))
	return card


func _select_preset(preset: WorldPreset) -> void:
	_selected_preset = preset
	_refresh_preset_cards()


## Radio-button behaviour: exactly one card's `button_pressed` is true, matching the same
## toggle-list pattern `SavedWorldsScreen`'s save rows already use.
func _refresh_preset_cards() -> void:
	for i: int in _preset_row.get_child_count():
		var card: Button = _preset_row.get_child(i) as Button
		var preset: WorldPreset = _presets[i]
		var is_selected: bool = preset == _selected_preset
		card.button_pressed = is_selected
		UiPalette.paint_button(card, is_selected)


func _on_start() -> void:
	if _selected_preset == null:
		return
	var world_name: String = _name_field.text.strip_edges()
	if world_name.is_empty():
		# An empty name is not an error message. It is the default.
		world_name = DEFAULT_WORLD_NAME

	GameSession.request_new(
		_selected_preset, world_name, SaveStore.unique_path_for(world_name), new_seed()
	)
	_go(WORLD_SCENE)


## ONE GENERATOR FOR THE PROCESS, randomized on first use and then ADVANCED per draw. It is not
## an optimisation; it is the whole correctness of `new_seed()` — see there.
static var _seed_rng: RandomNumberGenerator = null


## THE WORLD'S PERMANENT SEED, drawn once, here, at the instant the world is created.
##
## **HERE AND NOT IN `WorldRoot._ready()`**, which is where it looks like it belongs. That
## `_ready()` also runs for every headless suite in this project and for the `"none"` intent an
## editor F6 produces, so a random draw there would make world construction non-deterministic in
## all of them. New Game is the one code path that is only ever taken by a player pressing a
## button, so it is the only place a random draw costs nothing.
##
## NEVER 0. `ArrivalQueue._init()` reads a seed of 0 as "randomize" and `WorldSnapshot.migrate()`
## reads a non-numeric or v1 seed as "this file has no recoverable seed", so 0 is a sentinel in
## two places already. The `| 1` keeps every generated seed off it. Static so a test can exercise
## the generator without driving a scene change.
##
## **THE RNG IS SEEDED ONCE, NOT PER CALL.** The previous version built a fresh
## `RandomNumberGenerator` and called `randomize()` inside this function, which does not draw
## from a sequence at all — it re-seeds from the clock every time, so back-to-back calls inherit
## the clock's resolution instead of the generator's period. Measured across three independent
## processes: **41.7% / 41.9% / 43.7% of consecutive pairs identical**, and 7,292 repeats in
## 20,000 back-to-back draws, every one of them consecutive. Two worlds created in the same breath
## — which is exactly what an excited child does — would have shared row 13's mist reveal. A
## static generator advances its own state per draw, so consecutive calls cannot collide on timing.
static func new_seed() -> int:
	if _seed_rng == null:
		_seed_rng = RandomNumberGenerator.new()
		_seed_rng.randomize()
	return int(_seed_rng.randi()) | 1


func _go(path: String) -> void:
	var err: int = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("NewGameScreen: failed to load %s (error %d)" % [path, err])
