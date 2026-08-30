class_name ComingSoonScreen
extends Control
## Shared page chrome (sky background, title, Back-to-title button) for every screen the title
## screen's small-button row routes to. Originally a placeholder for all four (Tutorial/Help/
## Settings/Credits, 2026-08-24 redesign) — Tutorial and Help still are. Settings and Credits
## (2026-08-25) now embed the real `SettingsOverlay`/`CreditsScreen` content above the Back
## button instead of a "Coming Soon" label — this script never cared what sat above the Back
## button, so nothing here changed to support that.

const TITLE_SCENE: String = "res://scenes/TitleScreen.tscn"

@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(func() -> void: _go(TITLE_SCENE))
	_back_button.grab_focus()


func _go(path: String) -> void:
	var err: int = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("ComingSoonScreen: failed to load %s (error %d)" % [path, err])
