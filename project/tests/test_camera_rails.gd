extends QATestCase
## THE THREE CAMERA SAFETY RAILS, RE-DERIVED FOR THE YAWED ORTHOGRAPHIC CAMERA
## (→ D-41, reverses D-33). Verified against the engine's own frustum test
## (`Camera3D.is_position_in_frustum()`), never against parallel arithmetic — the
## same reasoning the pre-D-33 version of this file gave, carried forward.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_camera_rails.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"
const EXPECTED_GRID := Vector2i(36, 36)

var _world: WorldRoot = null
var _rig: CameraRig = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("camera safety rails (iso orthographic)")
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

	var camera: Camera3D = root.get_viewport().get_camera_3d()
	if not check(camera is CameraRig, "the scene's active Camera3D is the CameraRig"):
		finish()
		return true
	_rig = camera as CameraRig
	_rig.initialize()

	check_eq(_world.grid_size(), EXPECTED_GRID, "the world under test is 36x36 tiles")

	_check_fixed_orientation()
	_check_rotation()
	_check_rail_1_pan_clamp()
	_check_rail_2_full_zoom_out_frames_everything()
	_check_rail_3_home_peek()
	_check_rails_hold_at_rotated_heading()
	_check_zoom_clamps()
	_check_real_input_paths()
	_check_rotation_real_input_paths()
	_check_sun_locks_to_camera_rotation()

	note_expected_pending(
		"CAMERA FEEL is not tested and cannot be — it is the human's playtest judgment",
		"Easing, framing polish, whether panning is pleasant. A headless frustum check "
		+ "says nothing about it."
	)
	finish()
	return true


func _check_fixed_orientation() -> void:
	check(
		_rig.rotation_degrees.is_equal_approx(IsoCameraFraming.rotation_degrees()),
		"camera sits at the fixed IsoCameraFraming rotation (yaw=45, pitch=-26.565)"
	)
	check(
		_rig.projection == Camera3D.PROJECTION_ORTHOGONAL, "camera is orthographic"
	)


## → D-44. `rotate_clockwise()` changes `rotation_degrees`, and four of them return exactly
## to the heading the rest of this suite assumes. Pan/zoom/peek must still preserve whatever
## heading is currently set — the old `_check_cannot_be_rotated()` this replaces asserted
## rotation was impossible at all; that's no longer true, so this checks the narrower thing
## that's still true instead: nothing BUT `rotate_clockwise()`/`rotate_counterclockwise()`
## ever changes `rotation_degrees`.
func _check_rotation() -> void:
	var before: Vector3 = _rig.rotation_degrees
	_rig.rotate_clockwise()
	check(
		not _rig.rotation_degrees.is_equal_approx(before),
		"rotate_clockwise() changes rotation_degrees"
	)
	check(
		_rig.rotation_degrees.is_equal_approx(IsoCameraFraming.rotation_degrees(90.0)),
		"rotate_clockwise() lands exactly on the +90° heading, not just A different one"
	)
	_rig.rotate_clockwise()
	_rig.rotate_clockwise()
	_rig.rotate_clockwise()
	check(
		_rig.rotation_degrees.is_equal_approx(before),
		"four rotate_clockwise() calls return to the original heading"
	)

	# pan/zoom/peek still preserve rotation_degrees at whatever heading is current.
	_rig.set_focus(_rig.focus() + Vector3(3.0, 0.0, -2.0))
	_rig.set_zoom_tiles(_rig.zoom_tiles() * 1.2)
	_rig.begin_map_peek()
	_rig.end_map_peek()
	check(
		_rig.rotation_degrees.is_equal_approx(before),
		"pan/zoom/peek preserve rotation_degrees (only rotate_clockwise/ccw change it)"
	)


func _check_rail_1_pan_clamp() -> void:
	var bounds: Rect2 = _rig.world_bounds()
	_rig.set_focus(Vector3(bounds.position.x - 1000.0, 0.0, bounds.position.y - 1000.0))
	var focus: Vector3 = _rig.focus()
	check(
		bounds.grow(0.001).has_point(Vector2(focus.x, focus.z)),
		"panning far outside the world (toward the min corner) clamps the focus back inside "
		+ "its bounds"
	)

	var max_x: float = bounds.position.x + bounds.size.x
	var max_z: float = bounds.position.y + bounds.size.y
	_rig.set_focus(Vector3(max_x + 1000.0, 0.0, max_z + 1000.0))
	var focus_far: Vector3 = _rig.focus()
	check(
		bounds.grow(0.001).has_point(Vector2(focus_far.x, focus_far.z)),
		"...and panning far outside toward the opposite (max) corner clamps back inside too, "
		+ "not just the min side"
	)


func _check_rail_2_full_zoom_out_frames_everything() -> void:
	# CONTROL, before the real assertions: prove the frustum check can actually fail, not just
	# always pass. From the world's own centre at the closest zoom, a corner is far outside the
	# frame — if this ever reported "in frustum", every check below would be worthless.
	var bounds: Rect2 = _rig.world_bounds()
	var centre: Vector3 = Vector3(
		bounds.position.x + bounds.size.x * 0.5, 0.0, bounds.position.y + bounds.size.y * 0.5
	)
	_rig.set_focus(centre)
	_rig.set_zoom_tiles(CameraRig.ZOOM_MIN_TILES)
	check(
		not _rig.is_position_in_frustum(_world_corners()[0]),
		"CONTROL: at closest zoom from the world centre, a corner is NOT in frame — proves "
		+ "the frustum check can fail"
	)

	_rig.set_zoom_tiles(999999.0)  # clamps to whatever the overview size actually is
	for corner: Vector3 in _world_corners():
		check(
			_rig.is_position_in_frustum(corner),
			"world corner %s is inside the frustum at full zoom-out" % corner
		)
	_rig.set_zoom_tiles(CameraRig.ZOOM_DEFAULT_TILES)  # restore for later checks


func _world_corners() -> Array[Vector3]:
	var bounds: Rect2 = _rig.world_bounds()
	return [
		Vector3(bounds.position.x, 0.0, bounds.position.y),
		Vector3(bounds.position.x + bounds.size.x, 0.0, bounds.position.y),
		Vector3(bounds.position.x, 0.0, bounds.position.y + bounds.size.y),
		Vector3(bounds.position.x + bounds.size.x, 0.0, bounds.position.y + bounds.size.y),
	]


func _check_rail_3_home_peek() -> void:
	var before_focus: Vector3 = _rig.focus()
	var before_zoom: float = _rig.zoom_tiles()
	check(not _rig.is_peeking(), "not peeking before Home is pressed")
	_rig.begin_map_peek()
	check(_rig.is_peeking(), "is_peeking() true while Home is held")
	for corner: Vector3 in _world_corners():
		check(
			_rig.is_position_in_frustum(corner),
			"peek frames the whole world (corner %s visible)" % corner
		)
	_rig.end_map_peek()
	check(not _rig.is_peeking(), "not peeking after Home is released")
	check_eq(_rig.focus(), before_focus, "focus restored exactly after the peek")
	check_eq(_rig.zoom_tiles(), before_zoom, "zoom restored exactly after the peek")


## Rails 1/2/3 were only ever proven at the canonical (un-rotated) heading before rotation
## existed — this proves they still hold at a rotated one too, on this suite's own world
## fixture. Rail 2's overview size happens to be yaw-invariant on any world under this
## camera's specific 90°-step rotation scheme (verified in `test_iso_camera_framing.gd`'s
## `_check_non_square_bounds_size_is_also_yaw_invariant()`), so this scene-based re-check
## doesn't add anything rail 2 specifically — it still earns its keep for rails 1 and 3.
func _check_rails_hold_at_rotated_heading() -> void:
	_rig.rotate_clockwise()

	# Rail 1, rotated: panning far outside the world still clamps back inside its bounds.
	var bounds: Rect2 = _rig.world_bounds()
	_rig.set_focus(Vector3(bounds.position.x - 1000.0, 0.0, bounds.position.y - 1000.0))
	var focus: Vector3 = _rig.focus()
	check(
		bounds.grow(0.001).has_point(Vector2(focus.x, focus.z)),
		"rotated heading: panning far outside the world still clamps the focus back inside"
	)

	# Rail 2, rotated: full zoom-out still frames every corner.
	_rig.set_zoom_tiles(999999.0)
	for corner: Vector3 in _world_corners():
		check(
			_rig.is_position_in_frustum(corner),
			"rotated heading: world corner %s is inside the frustum at full zoom-out" % corner
		)
	_rig.set_zoom_tiles(CameraRig.ZOOM_DEFAULT_TILES)

	# Rail 3, rotated: Home peek still frames the whole world and restores exactly on release.
	var before_focus: Vector3 = _rig.focus()
	var before_zoom: float = _rig.zoom_tiles()
	_rig.begin_map_peek()
	for corner: Vector3 in _world_corners():
		check(
			_rig.is_position_in_frustum(corner),
			"rotated heading: peek frames the whole world (corner %s visible)" % corner
		)
	_rig.end_map_peek()
	check_eq(_rig.focus(), before_focus, "rotated heading: focus restored exactly after the peek")
	check_eq(_rig.zoom_tiles(), before_zoom, "rotated heading: zoom restored exactly after the peek")

	# Restore the canonical heading — every check after this one in the suite assumes it.
	_rig.rotate_counterclockwise()


## Q and E have to drive the SAME `rotate_counterclockwise()`/`rotate_clockwise()` this
## suite's other rotation checks call directly — proves the real input path is wired, not
## just the API shortcut. Matches this file's existing Home/wheel/drag checks in
## `_check_real_input_paths()`, and specifically checks the echo (held-key-repeat) guard the
## same way that file's Home check implicitly relies on `not key.echo`.
func _check_rotation_real_input_paths() -> void:
	var before: Vector3 = _rig.rotation_degrees
	_rig._unhandled_input(_key_event(KEY_E, true))
	check(
		not _rig.rotation_degrees.is_equal_approx(before),
		"a synthetic KEY_E keydown through _unhandled_input() rotates clockwise"
	)
	_rig._unhandled_input(_key_event(KEY_Q, true))
	check(
		_rig.rotation_degrees.is_equal_approx(before),
		"a synthetic KEY_Q keydown rotates back counterclockwise, to the original heading"
	)

	_rig._unhandled_input(_key_event(KEY_E, true))
	var after_first_press: Vector3 = _rig.rotation_degrees
	var echo_event := InputEventKey.new()
	echo_event.keycode = KEY_E
	echo_event.pressed = true
	echo_event.echo = true
	_rig._unhandled_input(echo_event)
	check(
		_rig.rotation_degrees.is_equal_approx(after_first_press),
		"an echoed KEY_E (held-key repeat) does not rotate again"
	)
	_rig._unhandled_input(_key_event(KEY_Q, true))  # restore the canonical heading

	check(
		_rig.rotation_degrees.is_equal_approx(before),
		"back at the canonical heading after the echo check"
	)


## → D-44's sun-lock fix. `DirectionalLight3D` (the world's one sun) has to rotate by the
## SAME delta as the camera whenever the camera rotates, so its bearing RELATIVE TO THE
## CAMERA never changes — otherwise each 90° turn puts the sun at a different angle relative
## to the screen, which is exactly what the human's playtest screenshots showed as
## inconsistent lighting/shading between headings (archive/images/mockups/original.png vs
## rotated.png). Checked as a relative-transform invariant, not a hardcoded expected
## Vector3/Basis — the same "invariant, not a magic number" reasoning this suite's other
## checks already use.
func _check_sun_locks_to_camera_rotation() -> void:
	# Looked up from `_world` (the Main.tscn instance), not `root` (this test's own node) —
	# `%Name` unique-name resolution only works within the same owner scope the unique node
	# was registered under, which is `_world`, the same scope `CameraRig`'s own `%`-based
	# onready vars (`_thumbnail_viewport`, and this task's new `_sun`) resolve against.
	var sun: DirectionalLight3D = _world.get_node_or_null("%DirectionalLight3D") as DirectionalLight3D
	if not check(sun != null, "setup: Main.tscn has a %DirectionalLight3D"):
		return

	var camera_basis_before: Basis = _rig.transform.basis
	var sun_basis_before: Basis = sun.global_transform.basis

	_rig.rotate_clockwise()

	var camera_delta: Basis = _rig.transform.basis * camera_basis_before.inverse()
	var sun_delta: Basis = sun.global_transform.basis * sun_basis_before.inverse()
	check(
		camera_delta.is_equal_approx(sun_delta),
		"the sun rotates by the SAME delta as the camera, so their relative bearing is unchanged"
	)

	_rig.rotate_counterclockwise()  # restore the canonical heading
	check(
		sun.global_transform.basis.is_equal_approx(sun_basis_before),
		"rotating back counterclockwise restores the sun to its original basis"
	)


func _check_zoom_clamps() -> void:
	_rig.set_zoom_tiles(0.0)
	check_eq(_rig.zoom_tiles(), CameraRig.ZOOM_MIN_TILES, "zoom cannot go below the close floor")

	_rig.set_zoom_tiles(999999.0)
	var overview: float = _rig.zoom_tiles()
	check(
		overview < 999999.0 and overview > CameraRig.ZOOM_MIN_TILES,
		"zoom clamps at a finite overview size well below what was asked for, got %f" % overview
	)
	_rig.set_zoom_tiles(CameraRig.ZOOM_DEFAULT_TILES)


## THE ACTUAL SHIPPING GESTURES, not the API shortcuts every check above uses. Confirms Home,
## wheel zoom, and right-drag pan are actually WIRED to `begin_map_peek()`/`set_zoom_tiles()`/
## `set_focus()` via real `InputEvent`s fed through `_unhandled_input()` — the same entry point
## the engine calls for a genuine keypress/scroll/drag. There is no harness limit stopping this:
## the pre-D-41 version of this file (`git show <old-rev>:project/tests/test_camera_rails.gd`)
## already drove synthetic `InputEventKey`/`InputEventMouseButton`/`InputEventMouseMotion`
## through `_unhandled_input()` successfully in this same headless build. The one thing that
## build genuinely could not do — force `Input.mouse_mode = MOUSE_MODE_CAPTURED` — has no
## bearing on Home/Tab/wheel/right-drag, none of which touch mouse-mode at all.
func _check_real_input_paths() -> void:
	# Home: begin/end the peek via a synthetic keydown/keyup, not begin_map_peek()/
	# end_map_peek() called directly.
	check(not _rig.is_peeking(), "setup: not peeking before the synthetic Home keydown")
	_rig._unhandled_input(_key_event(KEY_HOME, true))
	check(_rig.is_peeking(), "a synthetic Home KEYDOWN through _unhandled_input() begins the peek")
	_rig._unhandled_input(_key_event(KEY_HOME, false))
	check(not _rig.is_peeking(), "...and the matching KEYUP ends it")

	# Wheel zoom: a real InputEventMouseButton, not set_zoom_tiles() called directly.
	_rig.set_zoom_tiles(CameraRig.ZOOM_DEFAULT_TILES)
	var zoom_before: float = _rig.zoom_tiles()
	_rig._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	check(
		_rig.zoom_tiles() > zoom_before,
		"a synthetic wheel-DOWN event zooms out through the real input path",
		"got %f, was %f" % [_rig.zoom_tiles(), zoom_before]
	)
	var zoomed_out: float = _rig.zoom_tiles()
	_rig._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	check(_rig.zoom_tiles() < zoomed_out, "...and a synthetic wheel-UP event zooms back in")

	# Right-drag pan: a real button-down InputEventMouseButton followed by a real
	# InputEventMouseMotion, not _pan_by_screen_delta() called directly.
	_rig.set_zoom_tiles(CameraRig.ZOOM_DEFAULT_TILES)
	var focus_before: Vector3 = _rig.focus()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = Vector2(500.0, 500.0)
	_rig._unhandled_input(press)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(100.0, 0.0)
	_rig._unhandled_input(drag)
	check(
		not _rig.focus().is_equal_approx(focus_before),
		"a synthetic right-drag (button-down + motion) through _unhandled_input() pans the focus"
	)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = Vector2(600.0, 500.0)
	_rig._unhandled_input(release)
	var focus_after_release: Vector3 = _rig.focus()
	var stray_motion := InputEventMouseMotion.new()
	stray_motion.relative = Vector2(100.0, 0.0)
	_rig._unhandled_input(stray_motion)
	check(
		_rig.focus().is_equal_approx(focus_after_release),
		"...and releasing the button stops the pan — motion after release does not move it"
	)

	_rig.set_zoom_tiles(CameraRig.ZOOM_DEFAULT_TILES)


func _key_event(keycode: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	return event


func _wheel(button: int) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = Vector2(576.0, 576.0)
	return event
