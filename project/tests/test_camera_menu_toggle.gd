extends QATestCase
## TAB TOGGLES THE MENU WINDOW OPEN/CLOSED (→ D-41, reverses the old first-person merged
## "toggle pointer-capture AND open/close MenuWindow" gesture). The retired
## `_toggle_pointer_and_menu()`/`_pointer_captured` pair is gone along with the whole
## first-person camera — this fixed orthographic `CameraRig` never captures the mouse at all, so
## Tab's only remaining job is the much simpler `_toggle_menu()`: open or close whichever
## `MenuWindow` instance `GameUI` wired onto `CameraRig.menu_window`.
##
## Tab itself IS synthesized headlessly, via a synthetic `InputEventKey` fed through
## `_rig._unhandled_input()` (see `_check_real_tab_keypress_opens_menu()`) — there is no
## harness limit here. The claim this replaces (this suite could only drive `_toggle_menu()`
## directly, never the real keypress) was stale: `test_camera_rails.gd` already proves
## synthetic `InputEventKey`/`InputEventMouseButton`/`InputEventMouseMotion` events reach
## `_unhandled_input()` fine in this headless build. The actual measured harness limit was
## narrower — this build's `DisplayServer` silently refuses `Input.mouse_mode =
## MOUSE_MODE_CAPTURED` — and has no bearing on Tab/Home key handling at all. Most checks
## below still call `_toggle_menu()` directly where that is the simpler, equally-valid way to
## exercise the method under test; the real-keypress check exists specifically to confirm the
## wiring from Tab to that method, not to replace every call site.
##
## Run:
##   bash scripts/run-tests.sh camera_menu_toggle

const WORLD_PATH: String = "res://scenes/Main.tscn"

var _world: WorldRoot = null
var _ui: GameUI = null
var _rig: CameraRig = null
var _menu: MenuWindow = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("camera <-> menu window Tab toggle")
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		finish()
		return
	_world = node as WorldRoot
	root.add_child(_world)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	var ui_node: Node = _world.get_node_or_null("GameUI")
	if not check(ui_node is GameUI, "Main.tscn instances the GameUI shell"):
		finish()
		return true
	_ui = ui_node as GameUI
	_ui.bind_world()

	var camera: Camera3D = root.get_viewport().get_camera_3d()
	if not check(camera is CameraRig, "the scene's active Camera3D is the CameraRig"):
		finish()
		return true
	_rig = camera as CameraRig
	_rig.initialize()

	_menu = _world.get_node_or_null("GameUI/MenuWindow") as MenuWindow
	if not check(_menu != null, "GameUI.tscn instances a MenuWindow the rig can toggle"):
		finish()
		return true
	check(_rig.menu_window == _menu,
		"GameUI wires CameraRig.menu_window to that same MenuWindow instance")

	_check_starts_closed()
	_check_toggle_opens_and_closes()
	_check_toggle_does_not_move_or_zoom_the_camera()
	_check_direct_close_also_works()
	_check_real_tab_keypress_opens_menu()

	finish()
	return true


func _check_starts_closed() -> void:
	check(not _menu.is_open(), "the window starts closed")


func _check_toggle_opens_and_closes() -> void:
	_rig._toggle_menu()
	check(_menu.is_open(), "_toggle_menu() opens the window")

	_rig._toggle_menu()
	check(not _menu.is_open(), "...and a second call closes it again")


## The old first-person suite checked that closing the menu preserved the player's exact
## position and facing. There is no player any more — no `_player`/`CharacterBody3D` exists for
## this camera to preserve — so the camera-equivalent guarantee is that toggling the menu never
## nudges `focus()`/`zoom_tiles()`, the two pieces of state this camera actually owns.
func _check_toggle_does_not_move_or_zoom_the_camera() -> void:
	# Pan/zoom to a distinctive, non-default value FIRST. Right after initialize(), focus() is
	# already _bounds_centre() and zoom_tiles() is already ZOOM_DEFAULT_TILES — capturing
	# "before" state there would make an accidental reset-to-default inside _toggle_menu()
	# indistinguishable from "nothing moved", which is exactly the regression this check exists
	# to catch.
	_rig.set_focus(_rig.focus() + Vector3(3.0, 0.0, -2.0))
	_rig.set_zoom_tiles(CameraRig.ZOOM_DEFAULT_TILES * 0.5)
	var focus_before: Vector3 = _rig.focus()
	var zoom_before: float = _rig.zoom_tiles()

	_rig._toggle_menu()
	_rig._toggle_menu()

	check_eq(_rig.focus(), focus_before,
		"toggling the menu open and closed leaves the camera's focus exactly where it was")
	check_eq(_rig.zoom_tiles(), zoom_before,
		"...and leaves the camera's zoom exactly where it was too")


## Drives `MenuWindow.close()` directly — the same call both the × button's
## `_close_button.pressed.connect(close)` and the scrim's `_on_scrim_input()` make, not the Tab
## toggle. Unlike the retired first-person camera (which had to re-capture the pointer whenever
## the window closed by any path other than its own toggle — a real bug final review once
## caught), this camera never captures the mouse in the first place, so there is nothing left to
## keep in sync: closing this way should just close the window and leave the camera untouched.
func _check_direct_close_also_works() -> void:
	if not check(not _menu.is_open(), "setup: window closed before this check"):
		return

	_rig._toggle_menu()
	if not check(_menu.is_open(), "setup: the toggle opens the window"):
		return

	# Same reasoning as _check_toggle_does_not_move_or_zoom_the_camera(): pan/zoom away from the
	# default BEFORE capturing before_focus/before_zoom, so a state-reset regression could not
	# hide behind "already-at-default" coincidentally matching.
	_rig.set_focus(_rig.focus() + Vector3(-4.0, 0.0, 5.0))
	_rig.set_zoom_tiles(CameraRig.ZOOM_DEFAULT_TILES * 1.5)
	var focus_before: Vector3 = _rig.focus()
	var zoom_before: float = _rig.zoom_tiles()

	_menu.close()
	check(not _menu.is_open(), "close() (not the toggle) closes the window")
	check_eq(_rig.focus(), focus_before, "...and the camera's focus is unaffected")
	check_eq(_rig.zoom_tiles(), zoom_before, "...and the camera's zoom is unaffected")


## THE ACTUAL SHIPPING GESTURE: a synthetic Tab keydown fed through `_rig._unhandled_input()`,
## not `_toggle_menu()` the method called directly. Confirms Tab is really wired to the menu,
## not just that the method it calls works in isolation.
func _check_real_tab_keypress_opens_menu() -> void:
	if not check(not _menu.is_open(), "setup: window closed before the synthetic Tab check"):
		return

	_rig._unhandled_input(_key_event(KEY_TAB, true))
	check(
		_menu.is_open(),
		"a synthetic Tab KEYDOWN through _unhandled_input() opens the menu — the real "
		+ "shipping gesture, not just _toggle_menu() the method"
	)

	_rig._unhandled_input(_key_event(KEY_TAB, false))  # keyup: _toggle_menu() only fires on press
	check(_menu.is_open(), "...and Tab's KEYUP does not also toggle it (press-only, per source)")

	_rig._unhandled_input(_key_event(KEY_TAB, true))
	check(not _menu.is_open(), "a second synthetic Tab keydown closes it again")


func _key_event(keycode: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	return event
