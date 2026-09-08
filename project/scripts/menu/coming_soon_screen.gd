class_name ComingSoonScreen
extends Control
## Shared page chrome (sky background, title, Back-to-title button) for every screen the title
## screen's small-button row routes to. Originally a placeholder for all four (Tutorial/Help/
## Settings/Credits, 2026-08-24 redesign); NONE OF THEM ARE PLACEHOLDERS ANY MORE. Settings and
## Credits (2026-08-25) embed the real `SettingsOverlay`/`CreditsScreen` content above the Back
## button instead of a "Coming Soon" label, Help (2026-09-08) embeds `HelpContent`, and the
## Tutorial button was removed outright in that same pass rather than given content — see
## `title_screen.gd`'s own header for why. This script never cared what sat above the Back
## button, so nothing here changed to support any of it; the name is now historical.

const TITLE_SCENE: String = "res://scenes/TitleScreen.tscn"

@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_back_button.pressed.connect(func() -> void: _go(TITLE_SCENE))
	_back_button.grab_focus()


func _go(path: String) -> void:
	var err: int = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("ComingSoonScreen: failed to load %s (error %d)" % [path, err])
