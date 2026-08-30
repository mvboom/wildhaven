extends CanvasLayer
## THE WAY OUT — Tier 1 row 1's `exit_to_menu` trigger, and the only affordance a player has
## for leaving a world without closing the window.
##
## ITS OWN CANVASLAYER, NOT PART OF GameUI (human ruling 5, 2026-08-01). `project/scripts/ui/`
## and `project/scenes/ui/` are claimed by rows 2, 7, 11, 12 and 15; keeping this separate is
## what leaves row 1 dispatchable alongside any of them. When row 15 builds the shared Settings
## overlay it folds this in and deletes one instance line from `Main.tscn`.
##
## THE SAVE HAPPENS BEFORE THE CONFIRM, NOT AFTER IT. gdd.md -> GUI & screens: in-game "Exit to
## Main Menu" autosaves then confirms — "a courtesy against a misclick, not a data-loss guard."
## By the time the question is on screen the world is already safe, so either answer is safe,
## which is the only version of a confirmation dialog Pillar 1 permits.

const TITLE_SCENE: String = "res://scenes/TitleScreen.tscn"

@onready var _leave_button: Button = %LeaveButton
@onready var _confirm: ConfirmationDialog = %ConfirmDialog


func _ready() -> void:
	# Playtest feedback: this button's hover state "did not hover well" next to the HUD's own
	# buttons — `LeaveOverlay.tscn` only ever gave it a `normal` stylebox, never `hover`/
	# `pressed`/`focus`, so it fell back to Godot's stock theme for those. `false` because this
	# button is never a "selected" toggle. Same fix as `GameHud`'s Rotate buttons — see that
	# file's `_ready()` for the fuller note.
	UiPalette.paint_button(_leave_button, false)
	_leave_button.pressed.connect(_on_leave_pressed)
	_confirm.confirmed.connect(_on_confirmed)


func _on_leave_pressed() -> void:
	# Save FIRST. The dialog below is a courtesy, and it is asked over a world already written.
	var world: WorldRoot = WorldRoot.instance()
	if world != null and world.autosave != null:
		world.autosave.request("exit_to_menu")
	_confirm.popup_centered()


func _on_confirmed() -> void:
	var err: int = get_tree().change_scene_to_file(TITLE_SCENE)
	if err != OK:
		push_error("LeaveOverlay: failed to load %s (error %d)" % [TITLE_SCENE, err])
