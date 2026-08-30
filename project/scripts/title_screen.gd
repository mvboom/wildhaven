class_name TitleScreen
extends Control
## Title screen — Tier 1 row 1's front door.
##
## 2026-08-24 REDESIGN, from archive/images/mockups/01-title.svg (left-panel content only —
## the mockup's world diorama on the right is deferred). Reopens part of the playability
## chrome overhaul's "ONE ENTRY POINT" consolidation on purpose: New Game now jumps straight
## to `NewGameScreen`, Load Game opens `SavedWorldsScreen` (which still owns Play/Rename/
## Delete for existing saves) — human-ruled this session, not a silent reversal.
##
## Tutorial/Help still route to placeholder screens (`coming_soon_screen.gd`) — real content
## for those is out of scope here. Settings/Credits (2026-08-25) route to that same page
## chrome but now carry real content — the `SettingsOverlay`/`CreditsScreen` controls that
## used to be `MenuWindow` tabs, moved here since Settings/Credits are no longer reachable
## in-game. No Exit/Quit button: `get_tree().quit()` is a no-op on Web, which is this
## project's export target for this screen's own local testing, so the mockup's Exit slot is
## Settings instead.
##
## Interaction model: one pattern only — tap (left-click) a target. No drags, no hold, no
## gestures (gdd.md -> Controls & Interaction Model).

const NEW_GAME_SCENE: String = "res://scenes/menu/NewGameScreen.tscn"
const SAVED_WORLDS_SCENE: String = "res://scenes/menu/SavedWorldsScreen.tscn"
const TUTORIAL_SCENE: String = "res://scenes/menu/TutorialScreen.tscn"
const HELP_SCENE: String = "res://scenes/menu/HelpScreen.tscn"
const CREDITS_SCENE: String = "res://scenes/menu/CreditsScreen.tscn"
const SETTINGS_SCENE: String = "res://scenes/menu/SettingsScreen.tscn"

## Decided directly by the human this session (not a content-writer stub) — see the mockup
## conversation. Godot's own CheckButton draws the toggle glyph; this is the label beside it.
const SPEAKING_LABEL: String = "Read Text Aloud"

@onready var _new_game_button: Button = %NewGameButton
@onready var _load_game_button: Button = %LoadGameButton
@onready var _tutorial_button: Button = %TutorialButton
@onready var _settings_button: Button = %SettingsButton
@onready var _help_button: Button = %HelpButton
@onready var _credits_button: Button = %CreditsButton
@onready var _speaking_check: CheckButton = %SpeakingCheck
@onready var _build_tag: Label = %BuildTag


func _ready() -> void:
	_new_game_button.pressed.connect(func() -> void: _go(NEW_GAME_SCENE))
	_load_game_button.pressed.connect(func() -> void: _go(SAVED_WORLDS_SCENE))
	_tutorial_button.pressed.connect(func() -> void: _go(TUTORIAL_SCENE))
	_settings_button.pressed.connect(func() -> void: _go(SETTINGS_SCENE))
	_help_button.pressed.connect(func() -> void: _go(HELP_SCENE))
	_credits_button.pressed.connect(func() -> void: _go(CREDITS_SCENE))
	_new_game_button.grab_focus()

	# `BuildInfo.BUILD_TIMESTAMP` is stamped by scripts/build-game.sh at export time — see
	# that file's own header.
	_build_tag.text = "Built %s" % BuildInfo.BUILD_TIMESTAMP

	_speaking_check.text = SPEAKING_LABEL
	_speaking_check.button_pressed = GameplaySettings.speaking_enabled()
	# A control that cannot do anything is worse than no control (Pillar 1) — same rule
	# `FactCard`'s own 🔊 button follows for a machine with no TTS voice.
	_speaking_check.visible = ReadAloud.available()
	_speaking_check.toggled.connect(_on_speaking_toggled)


## The player's choice BEFORE the game even starts — writes straight through to
## `GameplaySettings`, the same one source of truth `FactCard`'s own toggle reads and writes.
func speaking_checked() -> bool:
	return _speaking_check.button_pressed


func _on_speaking_toggled(enabled: bool) -> void:
	GameplaySettings.set_speaking_enabled(enabled)


func _go(path: String) -> void:
	var err: int = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("TitleScreen: failed to load %s (error %d)" % [path, err])
