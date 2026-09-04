extends Control
## SAVED WORLDS — the unified Play/Create/Rename/Delete screen (playability chrome
## overhaul, section 5), replacing the `NewGameScreen`-or-`LoadGameScreen` split reached
## from the Title screen.
##
## REVERSES THE 2026-08-01 "read-only by construction" ruling (deliberate, this session —
## see docs/superpowers/plans/2026-08-09-main-menu-simplification.md's header):
## `SaveStore.rename()`/`SaveStore.delete()` now exist and this screen exposes both. Delete
## is irreversible and gated behind `%DeleteConfirmDialog`, the same `ConfirmationDialog`
## node `LeaveOverlay` already uses — this is the one screen in the game where a tap can
## destroy data outright, so it is also the one screen a confirmation dialog belongs on.
##
## SELECTING IS NOT LOADING. The old `LoadGameScreen` loaded a world the instant its row
## was clicked. Here, a single click on a row only selects it (and un-selects any other row —
## `toggle_mode` buttons in one list act as radio buttons by construction, since only one
## can hold `button_pressed = true` once `_refresh()` rewrites every row from `_selected_path`
## on every change) — Play/Rename/Delete then act on whichever entry is selected, matching
## the reference flow: pick a world, then choose what to do with it. The one shortcut on top
## of that: a DOUBLE-click on a readable row plays it outright (`_on_row_input()`), the same
## load `%PlayButton` runs, since "open this one" is the overwhelmingly common intent.
##
## NO CREATE BUTTON HERE (2026-08-24, title redesign). New Game is reached directly from the
## title screen now, not through this screen — `NewGameScreen`'s own preset/name/start flow
## (Tier 1 row 1) is unchanged, it's just no longer one level deeper in this flow.

const WORLD_SCENE: String = "res://scenes/Main.tscn"
const TITLE_SCENE: String = "res://scenes/TitleScreen.tscn"

@onready var _list: GridContainer = %SaveList
@onready var _empty_label: Label = %EmptyLabel
@onready var _play_button: Button = %PlayButton
@onready var _rename_button: Button = %RenameButton
@onready var _delete_button: Button = %DeleteButton
@onready var _back_button: Button = %BackButton
@onready var _rename_dialog: ConfirmationDialog = %RenameDialog
@onready var _rename_field: LineEdit = %RenameField
@onready var _delete_confirm: ConfirmationDialog = %DeleteConfirmDialog

var _entries: Array[Dictionary] = []
var _selected_path: String = ""


func _ready() -> void:
	_play_button.pressed.connect(_on_play_pressed)
	_rename_button.pressed.connect(_on_rename_pressed)
	_delete_button.pressed.connect(_on_delete_pressed)
	_back_button.pressed.connect(func() -> void: _go(TITLE_SCENE))
	_rename_dialog.confirmed.connect(_on_rename_confirmed)
	# Makes Enter in this field behave exactly like pressing the dialog's own OK button —
	# fires `confirmed` (already wired to `_on_rename_confirmed` above) AND hides the dialog.
	# A hand-rolled `text_submitted` lambda calling `_on_rename_confirmed()` directly would
	# write the rename but leave the dialog open, so its own Cancel button would then close
	# it without undoing anything — silently implying the rename never happened.
	_rename_dialog.register_text_enter(_rename_field)
	_delete_confirm.confirmed.connect(_on_delete_confirmed)
	_refresh()


func _refresh() -> void:
	for child: Node in _list.get_children():
		# `remove_child()` first, not just `queue_free()` alone: `queue_free()` defers actual
		# removal to end-of-frame, so `_select()` calling `_refresh()` again before the frame
		# ends would still see the stale rows via `get_children()` and double them up (same
		# bug fixed the same way in `field_guide.gd`'s `_clear_list()`).
		_list.remove_child(child)
		child.queue_free()
	_entries = SaveStore.list()
	_empty_label.visible = _entries.is_empty()

	var selected_button: Button = null
	var first_button: Button = null
	for entry: Dictionary in _entries:
		var button := Button.new()
		button.text = entry["name"] as String
		button.custom_minimum_size = Vector2(220, 56)
		button.toggle_mode = true
		var path: String = entry["path"] as String
		var is_selected: bool = path == _selected_path
		button.button_pressed = is_selected
		UiPalette.paint_button(button, is_selected)
		if not bool(entry["readable"]):
			button.disabled = true
			button.tooltip_text = "This world can't be opened."
		else:
			button.pressed.connect(func() -> void: _select(path))
			button.gui_input.connect(func(event: InputEvent) -> void: _on_row_input(event, path))
		_list.add_child(button)
		if first_button == null:
			first_button = button
		if is_selected:
			selected_button = button

	if _entries.is_empty():
		_back_button.grab_focus()
	elif selected_button != null:
		selected_button.grab_focus()
	elif first_button != null:
		first_button.grab_focus()
	_update_action_buttons()


func _select(path: String) -> void:
	_selected_path = path
	_refresh()


## A double-click on a readable row plays it outright — the same load `%PlayButton` runs,
## minus the select-then-press second step. The first click of the pair still lands on
## `pressed` above and selects the row; this fires only on the genuine second click.
func _on_row_input(event: InputEvent, path: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.double_click and mouse.button_index == MOUSE_BUTTON_LEFT:
		_selected_path = path
		_play()


func _selected_entry() -> Dictionary:
	for entry: Dictionary in _entries:
		if entry["path"] == _selected_path:
			return entry
	return {}


func _update_action_buttons() -> void:
	var has_selection: bool = not _selected_entry().is_empty()
	_play_button.disabled = not has_selection
	_rename_button.disabled = not has_selection
	_delete_button.disabled = not has_selection


func _on_play_pressed() -> void:
	_play()


func _play() -> void:
	if _selected_path == "":
		return
	GameSession.request_load(_selected_path)
	_show_wait_cursor()
	_go(WORLD_SCENE)


## Standard "that click registered" feedback for the one action in this screen that leaves it:
## the pointer becomes the OS wait cursor for as long as the world scene takes to come up.
##
## WHY A NODE AND NOT `Input.set_default_cursor_shape()`. That call only decides the shape for
## when the pointer is over nothing that states its own — and every `Control` states its own,
## because `mouse_default_cursor_shape` defaults to `CURSOR_ARROW`. The pointer is sitting on
## the save row the player just double-clicked, so that call on its own changes nothing you can
## see. A full-rect Control on top, carrying `CURSOR_WAIT` itself, is what actually puts the
## hourglass under the pointer.
##
## It draws nothing. Both its jobs are invisible: it owns the cursor shape, and
## `MOUSE_FILTER_STOP` makes it swallow any further click at the row underneath, so the screen
## visibly stops responding to a second impatient double-click instead of queueing one up.
##
## NOTHING RESETS IT, deliberately. The node is a child of this screen and is freed with it when
## `change_scene_to_file()` swaps in the world — so the cursor goes back to normal on its own,
## with no teardown to forget. That is the whole reason the shape lives on a node here rather
## than in `Input`'s global default, which would outlive this scene and follow the player into
## the world as a permanent hourglass.
func _show_wait_cursor() -> void:
	if has_node("WaitCursor"):
		return
	var blocker := Control.new()
	blocker.name = "WaitCursor"
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.mouse_default_cursor_shape = Control.CURSOR_WAIT
	add_child(blocker)


## Test-facing: true once the wait cursor is up.
func is_showing_wait_cursor() -> bool:
	return has_node("WaitCursor")


func _on_rename_pressed() -> void:
	var entry: Dictionary = _selected_entry()
	if entry.is_empty():
		return
	_rename_field.text = entry["name"] as String
	_rename_dialog.popup_centered()
	_rename_field.grab_focus()
	_rename_field.select_all()


func _on_rename_confirmed() -> void:
	var new_name: String = _rename_field.text.strip_edges()
	if new_name.is_empty() or _selected_path == "":
		return
	var err: Error = SaveStore.rename(_selected_path, new_name)
	if err != OK:
		push_error("SavedWorldsScreen: rename failed for %s (error %d)" % [_selected_path, err])
	# Always refresh so the list reflects reality either way — but a failure is never
	# treated as a success beyond that (SaveStore itself already logged the failure above).
	_refresh()


func _on_delete_pressed() -> void:
	if _selected_path == "":
		return
	var entry: Dictionary = _selected_entry()
	if not entry.is_empty():
		_delete_confirm.dialog_text = "[COPY] This can't be undone. (%s)" % entry["name"]
	_delete_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	if _selected_path == "":
		return
	var err: Error = SaveStore.delete(_selected_path)
	if err == OK:
		# Only clear the selection on an actual success — on failure the file (and its
		# selection) may still be exactly what it was, so leave it alone.
		_selected_path = ""
	else:
		push_error("SavedWorldsScreen: delete failed for %s (error %d)" % [_selected_path, err])
	_refresh()


func _go(path: String) -> void:
	var err: int = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SavedWorldsScreen: failed to load %s (error %d)" % [path, err])
