# project/tests/test_iso_camera_framing.gd
extends QATestCase
## Pure-math suite for IsoCameraFraming — no scene, no camera instantiation needed.
## Tested as INVARIANTS (translation-invariance, scale-linearity, margin-linearity),
## not against one hand-derived magic number — the same reasoning
## test_camera_rails.gd's own header gives for verifying against the engine rather
## than parallel arithmetic: a hardcoded expected value here could share an
## arithmetic mistake with the implementation and both would agree on a wrong
## answer.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_iso_camera_framing.gd

func _initialize() -> void:
	begin("iso camera framing math")
	_check_back_direction_is_unit_length()
	_check_back_direction_matches_derived_angle()
	_check_size_scales_with_bounds()
	_check_size_is_translation_invariant()
	_check_margin_is_linear()
	_check_position_for_uses_back_direction()
	_check_yaw_offset_rotates_back_direction()
	_check_yaw_offset_preserves_pitch_and_length()
	_check_yaw_offset_is_periodic_at_360()
	_check_yaw_offset_changes_rotation_degrees()
	_check_yaw_offset_threads_through_position_for()
	_check_square_bounds_size_is_yaw_invariant()
	_check_non_square_bounds_size_is_also_yaw_invariant()
	finish()


func _check_back_direction_is_unit_length() -> void:
	check(
		is_equal_approx(IsoCameraFraming.back_direction().length(), 1.0),
		"back_direction() is a unit vector"
	)


## The mockup generator's TILE_W=96/TILE_H=48 (an exact 2:1 diamond) implies pitch =
## atan(0.5) below horizontal — this is the number the whole design traces back to,
## so it is worth asserting directly rather than only trusting the constant's name.
func _check_back_direction_matches_derived_angle() -> void:
	var expected_pitch: float = rad_to_deg(atan(0.5))
	check(
		is_equal_approx(IsoCameraFraming.PITCH_DEGREES, -expected_pitch),
		"PITCH_DEGREES is -atan(0.5) in degrees (%.3f), not an arbitrary number" % expected_pitch
	)
	check_eq(IsoCameraFraming.YAW_DEGREES, 45.0, "YAW_DEGREES is exactly 45")


func _check_size_scales_with_bounds() -> void:
	var small := Rect2(-5.0, -5.0, 10.0, 10.0)
	var big := Rect2(-10.0, -10.0, 20.0, 20.0)
	var small_size: float = IsoCameraFraming.size_to_frame(small, 1.0)
	var big_size: float = IsoCameraFraming.size_to_frame(big, 1.0)
	check(
		is_equal_approx(big_size, small_size * 2.0),
		"doubling every bounds dimension doubles the required size (%.4f vs %.4f)" % [small_size, big_size]
	)


func _check_size_is_translation_invariant() -> void:
	var here := Rect2(-5.0, -5.0, 10.0, 10.0)
	var there := Rect2(995.0, 995.0, 10.0, 10.0)
	check(
		is_equal_approx(
			IsoCameraFraming.size_to_frame(here, 1.0), IsoCameraFraming.size_to_frame(there, 1.0)
		),
		"moving the bounds elsewhere in the world does not change the size needed to frame it"
	)


func _check_margin_is_linear() -> void:
	var bounds := Rect2(-5.0, -5.0, 10.0, 10.0)
	var no_margin: float = IsoCameraFraming.size_to_frame(bounds, 1.0, 1.0)
	var with_margin: float = IsoCameraFraming.size_to_frame(bounds, 1.0, 1.06)
	check(
		is_equal_approx(with_margin, no_margin * 1.06),
		"margin multiplies the result linearly"
	)


func _check_position_for_uses_back_direction() -> void:
	var focus := Vector3(3.0, 0.0, -7.0)
	var position: Vector3 = IsoCameraFraming.position_for(focus, 10.0)
	check(
		is_equal_approx((position - focus).length(), 10.0),
		"position_for() sits exactly `distance` from `focus`"
	)
	check(
		(position - focus).normalized().is_equal_approx(IsoCameraFraming.back_direction()),
		"position_for() sits along back_direction() from focus"
	)


## `yaw_offset_degrees` (added for 90°-step camera rotation, → D-44) moves `back_direction()`
## away from the canonical D-41 heading — the whole point of the parameter, so assert it
## actually does that rather than silently no-op.
func _check_yaw_offset_rotates_back_direction() -> void:
	var canonical: Vector3 = IsoCameraFraming.back_direction()
	var rotated: Vector3 = IsoCameraFraming.back_direction(90.0)
	check(
		not rotated.is_equal_approx(canonical),
		"back_direction(90.0) differs from the canonical back_direction()"
	)


## The pitch (elevation above the ground plane) is fixed by `PITCH_DEGREES` alone —
## `yaw_offset_degrees` must rotate only about the world Y axis, never change how high the
## camera sits above the horizon. `back_direction().y` is exactly `sin(elevation)`, so this
## is the same invariant `_check_back_direction_matches_derived_angle()` pins at yaw 0, now
## checked to hold at a rotated heading too.
func _check_yaw_offset_preserves_pitch_and_length() -> void:
	var rotated: Vector3 = IsoCameraFraming.back_direction(90.0)
	check(is_equal_approx(rotated.length(), 1.0), "back_direction(90.0) is still a unit vector")
	check(
		is_equal_approx(rotated.y, IsoCameraFraming.back_direction().y),
		"a 90° yaw offset does not change the vertical (pitch) component"
	)


func _check_yaw_offset_is_periodic_at_360() -> void:
	check(
		IsoCameraFraming.back_direction(360.0).is_equal_approx(IsoCameraFraming.back_direction()),
		"a 360° yaw offset returns to the canonical back_direction()"
	)


func _check_yaw_offset_changes_rotation_degrees() -> void:
	var canonical: Vector3 = IsoCameraFraming.rotation_degrees()
	var rotated: Vector3 = IsoCameraFraming.rotation_degrees(90.0)
	check(
		not rotated.is_equal_approx(canonical),
		"rotation_degrees(90.0) differs from the canonical rotation_degrees()"
	)


## Mirrors `_check_position_for_uses_back_direction()` at a rotated heading — `position_for()`
## has to thread `yaw_offset_degrees` through to `back_direction()` itself, not just accept
## the parameter and ignore it.
func _check_yaw_offset_threads_through_position_for() -> void:
	var focus := Vector3(3.0, 0.0, -7.0)
	var position: Vector3 = IsoCameraFraming.position_for(focus, 10.0, 90.0)
	check(
		is_equal_approx((position - focus).length(), 10.0),
		"position_for() with a yaw offset still sits exactly `distance` from `focus`"
	)
	check(
		(position - focus).normalized().is_equal_approx(IsoCameraFraming.back_direction(90.0)),
		"position_for() with a yaw offset sits along that SAME offset's back_direction()"
	)


## A square world is rotationally symmetric under a 90° turn — the overview size needed to
## frame it must be identical at every one of the four headings. This is the precise
## invariant `CameraRig._overview_size()` relies on for a square world; the un-rotated case
## is already covered by `_check_size_scales_with_bounds()` etc., this is the one new fact
## rotation adds.
func _check_square_bounds_size_is_yaw_invariant() -> void:
	var square := Rect2(-8.0, -8.0, 16.0, 16.0)
	var at_0: float = IsoCameraFraming.size_to_frame(square, 1.0, 1.0, 0.0)
	for offset in [90.0, 180.0, 270.0]:
		var at_offset: float = IsoCameraFraming.size_to_frame(square, 1.0, 1.0, offset)
		check(
			is_equal_approx(at_offset, at_0),
			"size_to_frame() for a square world is unchanged at yaw offset %.0f" % offset,
			"got %.4f, want %.4f" % [at_offset, at_0]
		)


## The 90°-step camera rotation stays within the 45°-family of headings (45°/135°/225°/315°)
## — at every one of those four, the camera's screen-right/up axes weight world X and world Z
## by the SAME magnitude (only the sign pattern changes). Projecting an axis-aligned
## rectangle's corners onto those axes and taking absolute values (as `size_to_frame()` does)
## is therefore invariant to which sign pattern is live — for ANY rectangle, not just a square
## one (a stronger fact than `_check_square_bounds_size_is_yaw_invariant()` above states).
## Verified independently by hand (a direct Python re-derivation of this exact algorithm) before
## writing this test — not assumed.
func _check_non_square_bounds_size_is_also_yaw_invariant() -> void:
	var wide := Rect2(-16.0, -4.0, 32.0, 8.0)
	var at_0: float = IsoCameraFraming.size_to_frame(wide, 1.0, 1.0, 0.0)
	for offset in [90.0, 180.0, 270.0]:
		var at_offset: float = IsoCameraFraming.size_to_frame(wide, 1.0, 1.0, offset)
		check(
			is_equal_approx(at_offset, at_0),
			"size_to_frame() for a NON-square world is also unchanged at yaw offset %.0f" % offset,
			"got %.4f, want %.4f" % [at_offset, at_0]
		)
