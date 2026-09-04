extends QATestCase
## THE UNIFIED SAVED WORLDS SCREEN (playability chrome overhaul, section 5 —
## docs/superpowers/specs/2026-08-09-playability-chrome-overhaul-design.md). Replaces
## `LoadGameScreen`; this suite exercises the scene directly rather than through
## `change_scene_to_file()`, the same way other UI suites drive `GameUI` directly once
## instantiated.
##
## Redirects `SaveStore.SAVE_DIR` to an isolated scratch directory, same discipline as
## `test_save_store.gd` — never touches a real player's save.
##
## Run:
##   bash scripts/run-tests.sh saved_worlds_screen

const SCENE_PATH: String = "res://scenes/menu/SavedWorldsScreen.tscn"
const _REAL_SAVE_DIR: String = "user://saves"
const _TEST_SAVE_DIR: String = "user://test_saved_worlds_screen"

var _screen: Control = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("saved worlds screen")
	SaveStore.SAVE_DIR = _TEST_SAVE_DIR
	_clean()

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

	_check_selecting_enables_actions()
	_check_rename_flow()
	_check_delete_flow()
	# BEFORE `_check_double_click_loads()`: that check double-clicks too, so it also raises the
	# wait cursor, and this one's opening assertion is that the cursor is NOT already up.
	_check_double_click_shows_the_wait_cursor()
	_check_double_click_loads()

	_clean()
	GameSession.clear()
	SaveStore.SAVE_DIR = _REAL_SAVE_DIR
	finish()
	return true


func _clean() -> void:
	var dir: DirAccess = DirAccess.open(SaveStore.SAVE_DIR)
	if dir == null:
		return
	for filename: String in dir.get_files():
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path("%s/%s" % [SaveStore.SAVE_DIR, filename])
		)


func _check_selecting_enables_actions() -> void:
	var play: Button = _screen.get_node("%PlayButton") as Button
	var rename: Button = _screen.get_node("%RenameButton") as Button
	var delete: Button = _screen.get_node("%DeleteButton") as Button

	check(play.disabled and rename.disabled and delete.disabled,
		"with no saves and no selection, Play/Rename/Delete all start disabled")

	var path: String = SaveStore.unique_path_for("Selectable")
	SaveStore.write(path, {"save_version": 1, "name": "Selectable"})
	_screen.call("_refresh")

	_screen.call("_select", path)
	check(not play.disabled and not rename.disabled and not delete.disabled,
		"selecting a readable save enables all three actions")


func _check_rename_flow() -> void:
	var path: String = SaveStore.unique_path_for("Before")
	SaveStore.write(path, {"save_version": 1, "name": "Before"})
	_screen.call("_refresh")
	_screen.call("_select", path)

	var rename_field: LineEdit = _screen.get_node("%RenameField") as LineEdit
	_screen.call("_on_rename_pressed")
	check_eq(rename_field.text, "Before", "the rename field pre-fills with the current name")

	rename_field.text = "After"
	_screen.call("_on_rename_confirmed")
	check_eq(SaveStore.read(path).get("name", ""), "After",
		"confirming the rename dialog writes the new name to disk")

	# Driving `_on_rename_confirmed()` directly (rather than through the dialog's own OK
	# button) writes the rename but never hides `%RenameDialog` — in real use, AcceptDialog
	# hides itself as part of handling its OK button. Close it explicitly so it isn't still
	# an exclusive child window when `_check_delete_flow()` pops `%DeleteConfirmDialog` next.
	var rename_dialog: ConfirmationDialog = _screen.get_node("%RenameDialog") as ConfirmationDialog
	rename_dialog.hide()


func _check_delete_flow() -> void:
	var path: String = SaveStore.unique_path_for("Doomed")
	SaveStore.write(path, {"save_version": 1, "name": "Doomed"})
	_screen.call("_refresh")
	_screen.call("_select", path)

	_screen.call("_on_delete_pressed")
	check(FileAccess.file_exists(path),
		"pressing Delete alone only opens the confirmation dialog — nothing is deleted yet")

	_screen.call("_on_delete_confirmed")
	check(not FileAccess.file_exists(path), "confirming delete removes the file")

	var play: Button = _screen.get_node("%PlayButton") as Button
	check(play.disabled, "...and the selection clears, so Play is disabled again")


func _check_double_click_loads() -> void:
	GameSession.clear()
	var path: String = SaveStore.unique_path_for("DblClick")
	SaveStore.write(path, {"save_version": 1, "name": "DblClick"})
	_screen.call("_refresh")

	var row: Button = _row_button_named("DblClick")
	if not check(row != null, "the readable save has a clickable row button"):
		return

	# A single click only selects — nothing loads until Play is pressed.
	row.pressed.emit()
	check_eq((GameSession.consume().get("mode", "none") as String), "none",
		"a single click on a row loads nothing on its own — selecting is not loading")

	# `pressed.emit()` above rebuilt the list via `_select()`, so re-fetch the live row.
	row = _row_button_named("DblClick")
	var double: InputEventMouseButton = InputEventMouseButton.new()
	double.button_index = MOUSE_BUTTON_LEFT
	double.pressed = true
	double.double_click = true
	row.gui_input.emit(double)

	# `_play()` also fires `change_scene_to_file(Main.tscn)`; the harness flushes it, so a
	# "World ready" line prints after this check. Harmless (test_menu_window.gd instantiates
	# Main.tscn on purpose too) and it happens after every assertion here has run.
	var intent: Dictionary = GameSession.consume()
	check_eq((intent.get("mode", "none") as String), "load",
		"double-clicking a readable row loads it outright — no need to then press Play")
	check_eq((intent.get("path", "") as String), path,
		"...and it loads that row's own save, not some other")
	GameSession.clear()


## THE CLICK FEEDBACK (2026-09-03). Opening a saved world is the one action on this screen that
## leaves it, and it used to give no sign the double-click had registered at all.
##
## WHY THIS ASSERTS A NODE AND NOT `Input.get_current_cursor_shape()`: the shape actually under
## the pointer is decided by whichever `Control` is under it, and `mouse_default_cursor_shape`
## defaults to `CURSOR_ARROW` on every one of them — including the save row that was just
## double-clicked. So `Input.set_default_cursor_shape()` alone would leave the pointer an arrow
## and still "pass" a check of Input's own default. What has to be true is that something on
## top is claiming the shape, which is what this checks.
func _check_double_click_shows_the_wait_cursor() -> void:
	GameSession.clear()
	var path: String = SaveStore.unique_path_for("Cursor")
	SaveStore.write(path, {"save_version": 1, "name": "Cursor"})
	_screen.call("_refresh")

	var row: Button = _row_button_named("Cursor")
	if not check(row != null, "the save has a row to double-click"):
		return
	check(not (_screen.call("is_showing_wait_cursor") as bool),
		"the pointer is normal before the tap — the wait cursor is not simply always on")

	row.pressed.emit()
	row = _row_button_named("Cursor")
	var double: InputEventMouseButton = InputEventMouseButton.new()
	double.button_index = MOUSE_BUTTON_LEFT
	double.pressed = true
	double.double_click = true
	row.gui_input.emit(double)

	if not check(_screen.call("is_showing_wait_cursor") as bool,
			"THE FIX: a double-click turns the pointer into the OS wait cursor"):
		return
	var blocker: Control = _screen.get_node_or_null("WaitCursor") as Control
	check_eq(blocker.mouse_default_cursor_shape, Control.CURSOR_WAIT,
		"...the hourglass shape specifically, claimed by a Control on top so the row underneath "
		+ "cannot keep overriding it with CURSOR_ARROW")
	check_eq(blocker.mouse_filter, Control.MOUSE_FILTER_STOP,
		"...and it swallows further clicks, so the screen visibly stops responding")
	check_eq(blocker.anchor_right, 1.0,
		"...across the whole screen, not just where the pointer happened to be")
	GameSession.clear()


func _row_button_named(name: String) -> Button:
	var list: GridContainer = _screen.get_node("%SaveList") as GridContainer
	for child: Node in list.get_children():
		if child is Button and (child as Button).text == name:
			return child as Button
	return null
