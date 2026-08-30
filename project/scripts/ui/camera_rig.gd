class_name CameraRig
extends Camera3D
## The one camera — Tier 1 row 2. Orthographic camera at pitch≈-26.565°, base yaw 45°,
## plus 90°-step yaw rotation (`rotate_clockwise()`/`rotate_counterclockwise()`, Q/E and two
## HUD buttons) — D-41 restored the fixed-heading pan/zoom camera; D-44 reopened its "never
## rotates" clause narrowly, to four fixed isometric headings, not free rotation.
##
## gdd.md → Player Interface & Controls: "Camera control lives on entirely separate
## inputs and never conflicts with gameplay taps." Unchanged here — this file only
## ever reads right-drag/WASD/arrows/wheel/Home; `TapRouter` only ever reads the
## left-click tap.
##
## THE THREE SAFETY RAILS, RE-DERIVED FOR THE YAWED CAMERA, NOT PORTED FROM D-13:
##   RAIL 1 — pan clamped. `_focus` is clamped to `world_bounds()` on every change.
##   RAIL 2 — full zoom-out frames everything. `_overview_size()` computes the exact
##            orthographic size via `IsoCameraFraming.size_to_frame()` — a direct
##            calculation, not the old perspective camera's frustum binary search
##            (orthographic framing has no need for one; see that file's header).
##   RAIL 3 — Home is one press away. Bound to the Home key (terraform-bar rework
##            retired the redundant on-screen Home button; the key still works).
##
## THE MAP PEEK folds into this same camera instead of swapping to a second one
## (unlike D-33's `OverviewCameraRig` swap): since this camera is already the same
## fixed-heading orthographic type the peek needs, holding Home just temporarily
## overrides zoom/focus to the rail-2 framing and restores them on release — no
## second `current` camera required.
##
## NO EASING, deliberately, matching every camera in this codebase's history.

## DECIDED, derived from the mockup's own 2:1 tile ratio (see IsoCameraFraming) —
## not a free playtest choice the way D-29's constants were for the old pitch.
const YAW_DEGREES: float = IsoCameraFraming.YAW_DEGREES
const PITCH_DEGREES: float = IsoCameraFraming.PITCH_DEGREES

## STARTING POINT, needs re-validation under orthographic (spec's open question #1)
## — carried over from gdd.md's existing continuum as the first thing to try, not
## assumed to transfer unchanged from the old perspective camera.
const ZOOM_MIN_TILES: float = 4.0
const ZOOM_DEFAULT_TILES: float = 14.0
const ZOOM_STEP: float = 1.15
const KEY_PAN_TILES_PER_SECOND: float = 16.0

## Slack added to the rail-2 overview size so the world's edge tiles are not flush
## against the screen edge. Carried over from the old camera's `OVERVIEW_MARGIN`.
const OVERVIEW_MARGIN: float = 1.06

## The fraction of the overview size at which the pannable rectangle starts
## shrinking toward the world centre, so "zoomed almost all the way out" still pans
## to the true edge rather than snapping straight to centred. Same role D-13's
## `RECENTRE_BEGIN` played.
const RECENTRE_BEGIN: float = 0.60

## How far back the camera sits per tile of `size` — a constant multiplier so
## `_distance_for_size()` never needs to clear the near plane regardless of zoom.
const DISTANCE_PER_SIZE: float = 4.0

const FALLBACK_BOUNDS: Rect2 = Rect2(-18.0, -18.0, 36.0, 36.0)

var _focus: Vector3 = Vector3.ZERO
var _size: float = 0.0
var _initialized: bool = false
var _dragging: bool = false
var _peeking: bool = false

## → D-44. How many 90° steps clockwise from the canonical yaw the player has rotated to,
## wrapped into [0,3] by `rotate_clockwise()`/`rotate_counterclockwise()`.
var _yaw_step: int = 0

## Saved so `end_map_peek()` can restore exactly where the player left off.
var _pre_peek_focus: Vector3 = Vector3.ZERO
var _pre_peek_size: float = 0.0

@onready var _thumbnail_viewport: SubViewport = %ThumbnailViewport as SubViewport
@onready var _thumbnail_camera: Camera3D = %ThumbnailCamera as Camera3D

## → D-44's sun-lock fix. Nullable: a scene with no sun (e.g. a future test fixture) still
## gets working rotation, just without the lighting-consistency fix.
@onready var _sun: DirectionalLight3D = get_node_or_null("%DirectionalLight3D") as DirectionalLight3D

## The sun's authored basis at the canonical (un-rotated) heading, cached once so every
## later rotation can compute `Basis(Vector3.UP, offset) * _sun_base_basis` from a fixed
## reference point instead of drifting via repeated relative rotations.
var _sun_base_basis: Basis = Basis.IDENTITY

## The Minecraft-style inventory window. Not owned by this node — set once by `GameUI`, the
## same way this file reaches its own child nodes via unique names. Tab toggles it open/closed
## directly — unlike the first-person version, there is no pointer-capture state to keep in
## sync with it, since this camera never captures the mouse at all.
var menu_window: MenuWindow = null


func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	keep_aspect = Camera3D.KEEP_HEIGHT
	rotation_degrees = IsoCameraFraming.rotation_degrees()
	current = true
	if _thumbnail_viewport != null:
		_thumbnail_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _sun != null:
		_sun_base_basis = _sun.global_transform.basis


func initialize() -> void:
	if _initialized:
		return
	if not is_inside_tree():
		return
	_initialized = true
	_focus = _bounds_centre()
	set_zoom_tiles(ZOOM_DEFAULT_TILES)


func _process(delta: float) -> void:
	if not _initialized:
		initialize()
	if not _peeking:
		_apply_keyboard_pan(delta)


# --- Public camera API (consumed by TapRouter's camera-agnostic code, tests, and
# the map peek/thumbnail below) --------------------------------------------------

func focus() -> Vector3:
	return _focus


func set_focus(world_position: Vector3) -> void:
	_focus = _clamp_focus(Vector3(world_position.x, 0.0, world_position.z))
	_apply_transform()


func zoom_tiles() -> float:
	return _size


func set_zoom_tiles(tiles: float) -> void:
	var far: float = _overview_size()
	_size = clampf(tiles, ZOOM_MIN_TILES, far)
	_focus = _clamp_focus(_focus)
	_apply_transform()


func world_bounds() -> Rect2:
	var world: WorldRoot = WorldRoot.instance()
	if world == null:
		return FALLBACK_BOUNDS
	var size: Vector2i = world.grid_size()
	if size.x <= 0 or size.y <= 0:
		return FALLBACK_BOUNDS
	var near: Vector3 = world.grid_to_world(0, 0)
	var far: Vector3 = world.grid_to_world(size.x - 1, size.y - 1)
	return Rect2(
		minf(near.x, far.x), minf(near.z, far.z),
		absf(far.x - near.x), absf(far.z - near.z)
	)


func _bounds_centre() -> Vector3:
	var rect: Rect2 = world_bounds()
	var mid: Vector2 = rect.position + rect.size * 0.5
	return Vector3(mid.x, 0.0, mid.y)


func _aspect() -> float:
	if not is_inside_tree():
		return 16.0 / 9.0
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return 16.0 / 9.0
	return viewport_size.x / viewport_size.y


## RAIL 2. The exact orthographic size that frames the whole world, computed
## directly via IsoCameraFraming — no search, unlike the old perspective camera.
##
## Threaded through the current yaw step for correctness/consistency with `rotation_degrees()`
## and `position_for()` below, both of which must use the SAME live heading. In practice this
## particular camera's four 90°-step headings (45°/135°/225°/315°) are all members of the same
## diagonal family, so the overview SIZE turns out to be yaw-invariant for any axis-aligned
## world — verified directly in `test_iso_camera_framing.gd`'s non-square invariance check —
## but that's a property of this specific yaw/pitch choice, not something to hardcode away;
## passing the true current heading through keeps this correct if either ever changes.
func _overview_size() -> float:
	return IsoCameraFraming.size_to_frame(
		world_bounds(), _aspect(), OVERVIEW_MARGIN, _yaw_offset_degrees()
	)


## The additive offset from the canonical `IsoCameraFraming.YAW_DEGREES` at the current
## heading (→ D-44) — what every `IsoCameraFraming` call below hands it as
## `yaw_offset_degrees`.
func _yaw_offset_degrees() -> float:
	return float(_yaw_step) * 90.0


## RAIL 1. Shrinks the pannable rectangle toward the world centre as `_size`
## approaches the overview size, exactly reaching the full world rect once zoomed
## all the way out — the same coupling D-13's `_pan_reach()` had, re-derived for
## the fixed yaw instead of ported.
func _pan_reach() -> Rect2:
	var bounds: Rect2 = world_bounds()
	var overview: float = _overview_size()
	var t: float = clampf(
		inverse_lerp(overview * RECENTRE_BEGIN, overview, _size), 0.0, 1.0
	)
	var centre: Vector2 = bounds.position + bounds.size * 0.5
	var half: Vector2 = bounds.size * 0.5 * (1.0 - t)
	return Rect2(centre - half, half * 2.0)


func _clamp_focus(candidate: Vector3) -> Vector3:
	var reach: Rect2 = _pan_reach()
	var clamped: Vector2 = Vector2(
		clampf(candidate.x, reach.position.x, reach.position.x + reach.size.x),
		clampf(candidate.z, reach.position.y, reach.position.y + reach.size.y),
	)
	return Vector3(clamped.x, 0.0, clamped.y)


func _distance_for_size(size: float) -> float:
	return maxf(1.0, size) * DISTANCE_PER_SIZE


func _apply_transform() -> void:
	size = _size
	rotation_degrees = IsoCameraFraming.rotation_degrees(_yaw_offset_degrees())
	position = IsoCameraFraming.position_for(
		_focus, _distance_for_size(_size), _yaw_offset_degrees()
	)


# --- 90°-step rotation, → D-44 (Q/E keys, HUD arrows) ---------------------------

## Steps the heading one quarter-turn clockwise and reapplies via `set_zoom_tiles()` —
## not a direct `_apply_transform()` call — so `_size`/`_focus` are re-clamped from a single
## path. The overview size itself is yaw-invariant at every heading here (see
## `_overview_size()`), so this isn't a required re-clamp, just defensive consistency.
func rotate_clockwise() -> void:
	_yaw_step = wrapi(_yaw_step + 1, 0, 4)
	set_zoom_tiles(_size)
	_apply_sun_rotation()


func rotate_counterclockwise() -> void:
	_yaw_step = wrapi(_yaw_step - 1, 0, 4)
	set_zoom_tiles(_size)
	_apply_sun_rotation()


## → D-44. Keeps the sun's bearing RELATIVE TO THE CAMERA constant across every heading —
## without this, `DirectionalLight3D`'s fixed world-space direction puts the sun at a
## different angle relative to the screen at each 90° turn, which is what the human's
## playtest screenshots showed as inconsistent lighting/shading between headings. Applies
## the identical rotation (same axis, same signed angle) to the light that
## `IsoCameraFraming.rotation_degrees()`'s `look_at_from_position()` construction already
## implicitly applies to the camera's own basis as `_yaw_offset_degrees()` changes — so the
## difference between the two stays invariant.
func _apply_sun_rotation() -> void:
	if _sun == null:
		return
	_sun.global_transform.basis = (
		Basis(Vector3.UP, deg_to_rad(_yaw_offset_degrees())) * _sun_base_basis
	)


# --- Input: right-drag pan, wheel zoom, WASD/arrow pan, Home peek ---------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mouse.pressed
			get_viewport().set_input_as_handled()
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom_tiles(_size / ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom_tiles(_size * ZOOM_STEP)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_pan_by_screen_delta((event as InputEventMouseMotion).relative)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.keycode == KEY_HOME and not key.echo:
			if key.pressed:
				begin_map_peek()
			else:
				end_map_peek()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_TAB and not key.echo:
			if key.pressed:
				_toggle_menu()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_Q and not key.echo:
			if key.pressed:
				rotate_counterclockwise()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_E and not key.echo:
			if key.pressed:
				rotate_clockwise()
			get_viewport().set_input_as_handled()


## Tab's only remaining job: open/close `MenuWindow` directly. No pointer-capture side
## effect — unlike the retired first-person camera, this camera never captures the mouse,
## so there is nothing to keep in sync when the window closes some other way (× button,
## scrim tap).
func _toggle_menu() -> void:
	if menu_window == null:
		return
	if menu_window.is_open():
		menu_window.close()
	else:
		menu_window.open(WorldRoot.instance())


## Drags the focus opposite the mouse motion, converted from screen pixels to world
## units via the same size/viewport-height ratio orthographic projection uses.
func _pan_by_screen_delta(screen_delta: Vector2) -> void:
	var viewport_height: float = maxf(1.0, get_viewport().get_visible_rect().size.y)
	var world_units_per_pixel: float = _size / viewport_height
	var right: Vector3 = transform.basis.x
	var flat_up: Vector3 = Vector3(transform.basis.y.x, 0.0, transform.basis.y.z)
	if flat_up.length() > 0.0001:
		flat_up = flat_up.normalized()
	## `flat_up` is a ground-plane unit vector, but only `IsoCameraFraming.back_direction().y`
	## (sin(26.565°) ≈ 0.4472) of it actually projects onto on-screen vertical motion once
	## the camera's fixed pitch is accounted for — unlike `right`, which tracks the cursor
	## 1:1 horizontally. Dividing by that same factor here restores 1:1 cursor tracking on
	## the vertical axis too, so a diagonal drag moves equal world-distance per screen-pixel
	## on both axes.
	var vertical_correction: float = IsoCameraFraming.back_direction().y
	var move: Vector3 = (
		-right * screen_delta.x + flat_up * (screen_delta.y / vertical_correction)
	) * world_units_per_pixel
	set_focus(_focus + move)


func _apply_keyboard_pan(delta: float) -> void:
	var forward_amount: float = 0.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		forward_amount += 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		forward_amount -= 1.0
	var right_amount: float = 0.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		right_amount += 1.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		right_amount -= 1.0
	if forward_amount == 0.0 and right_amount == 0.0:
		return
	var right: Vector3 = transform.basis.x
	var flat_forward: Vector3 = Vector3(transform.basis.y.x, 0.0, transform.basis.y.z)
	if flat_forward.length() > 0.0001:
		flat_forward = flat_forward.normalized()
	var scale: float = KEY_PAN_TILES_PER_SECOND * (_size / ZOOM_DEFAULT_TILES) * delta
	var move: Vector3 = (flat_forward * forward_amount + right * right_amount) * scale
	set_focus(_focus + move)


# --- The map peek (rail 3's held-Home behaviour) --------------------------------

func begin_map_peek() -> void:
	if _peeking:
		return
	_peeking = true
	_pre_peek_focus = _focus
	_pre_peek_size = _size
	_focus = _bounds_centre()
	_size = _overview_size()
	_apply_transform()


func end_map_peek() -> void:
	if not _peeking:
		return
	_peeking = false
	_focus = _pre_peek_focus
	_size = _pre_peek_size
	_apply_transform()


func is_peeking() -> bool:
	return _peeking


# --- Save-thumbnail capture (Task 3 wires the actual body) ----------------------

func capture_save_thumbnail() -> Image:
	if _thumbnail_viewport == null or _thumbnail_camera == null:
		return null
	_thumbnail_camera.rotation_degrees = IsoCameraFraming.rotation_degrees()
	_thumbnail_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_thumbnail_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	## Uses the ThumbnailViewport's own fixed 480x270 (16:9) aspect, not `_overview_size()`'s
	## `_aspect()` (the main game window's aspect) — the thumbnail is a separate fixed-size
	## render target and must be framed to its own aspect regardless of what shape the
	## player's window happens to be.
	var thumbnail_aspect: float = float(_thumbnail_viewport.size.x) / float(_thumbnail_viewport.size.y)
	var overview: float = IsoCameraFraming.size_to_frame(world_bounds(), thumbnail_aspect, OVERVIEW_MARGIN)
	_thumbnail_camera.size = overview
	_thumbnail_camera.position = IsoCameraFraming.position_for(
		_bounds_centre(), _distance_for_size(overview)
	)
	_thumbnail_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame
	return _thumbnail_viewport.get_texture().get_image()
