class_name IsoCameraFraming
extends RefCounted
## Stateless math for the fixed yaw=45°/pitch≈-26.565° orthographic camera (→ D-41).
## Used by BOTH the live `CameraRig` (rail 2 "frame everything" + the Home-key map
## peek) and the hidden save-thumbnail camera, so "what ortho size + position frames
## this world" exists in exactly one place, not duplicated per camera instance.
##
## Orthographic framing is a CLOSED-FORM calculation, not a search: given a fixed
## yaw/pitch, an arbitrary world-space point's extent along the camera's own local
## right/up axes is just a basis-inverse projection, so "the smallest `size` that
## fits every corner" falls out directly — contrast the old perspective
## `OverviewCameraRig._overview_distance()` (git history), which needed a 24-step
## binary search because perspective framing has no such closed form.

## The mockup generator's own TILE_W=96/TILE_H=48 (an exact 2:1 diamond) is the
## standard pixel-art isometric ratio, which implies a camera pitched atan(0.5) below
## horizontal — shallower than the abandoned D-13 diorama's -45°, not steeper.
const YAW_DEGREES: float = 45.0
const PITCH_DEGREES: float = -26.565

## Unit vector from a focus point toward the camera. Spherical form: `theta` is
## elevation above the ground plane, `YAW_DEGREES` rotates it about the world Y axis.
##
## `yaw_offset_degrees` (90°-step camera rotation, → D-44) is added to the base
## `YAW_DEGREES` so a rotated heading is still this same closed form, not a second code
## path. Default 0.0 preserves D-41's original fixed-yaw behaviour exactly.
static func back_direction(yaw_offset_degrees: float = 0.0) -> Vector3:
	var theta: float = deg_to_rad(-PITCH_DEGREES)
	var yaw: float = deg_to_rad(YAW_DEGREES + yaw_offset_degrees)
	var horizontal: float = cos(theta)
	return Vector3(horizontal * sin(yaw), sin(theta), horizontal * cos(yaw))


## The camera's fixed orientation. NOT simply `Vector3(PITCH_DEGREES, YAW_DEGREES, 0)`
## — Godot's default Euler composition order applies yaw after pitch, which tilts
## the horizon once both are non-zero. Built via a throwaway, never-added-to-tree
## `Camera3D.look_at_from_position()` instead, which is correct for any yaw/pitch
## pair and needs no scene at all — unlike plain `look_at()`, which hard-requires
## `is_inside_tree()` and silently no-ops (leaving rotation at its zero default) on
## an off-tree node such as this throwaway probe.
static func rotation_degrees(yaw_offset_degrees: float = 0.0) -> Vector3:
	var probe := Camera3D.new()
	var probe_position: Vector3 = back_direction(yaw_offset_degrees) * 10.0
	probe.look_at_from_position(probe_position, Vector3.ZERO, Vector3.UP)
	var result: Vector3 = probe.rotation_degrees
	probe.free()
	return result


## The orthographic `size` (vertical frustum height, i.e. `Camera3D.KEEP_HEIGHT`'s
## meaning) that frames every corner of `bounds` (a world-space XZ rect), plus
## `margin` slack (1.0 = none, 1.06 = 6%, matching the old camera's
## `OVERVIEW_MARGIN`). Projects each corner into the camera's own local right/up
## axes and returns whichever of "size needed for height" or "size needed for
## width, given `aspect`" is larger — the same effective behaviour `KEEP_HEIGHT`
## has at runtime, computed directly instead of searched for.
static func size_to_frame(
	bounds: Rect2, aspect: float, margin: float = 1.0, yaw_offset_degrees: float = 0.0
) -> float:
	var corners: Array[Vector3] = [
		Vector3(bounds.position.x, 0.0, bounds.position.y),
		Vector3(bounds.position.x + bounds.size.x, 0.0, bounds.position.y),
		Vector3(bounds.position.x, 0.0, bounds.position.y + bounds.size.y),
		Vector3(bounds.position.x + bounds.size.x, 0.0, bounds.position.y + bounds.size.y),
	]
	var centre: Vector3 = Vector3(
		bounds.position.x + bounds.size.x * 0.5, 0.0, bounds.position.y + bounds.size.y * 0.5
	)
	var probe := Camera3D.new()
	probe.rotation_degrees = rotation_degrees(yaw_offset_degrees)
	var basis_inverse: Basis = probe.transform.basis.inverse()
	probe.free()

	var half_height: float = 0.0
	var half_width: float = 0.0
	for corner in corners:
		var local: Vector3 = basis_inverse * (corner - centre)
		half_height = maxf(half_height, absf(local.y))
		half_width = maxf(half_width, absf(local.x))

	var size_for_height: float = half_height * 2.0
	var size_for_width: float = (half_width * 2.0) / maxf(aspect, 0.0001)
	return maxf(size_for_height, size_for_width) * margin


## Where the camera sits to look at `focus` from `distance` away, along the fixed
## `back_direction()`.
##
## `yaw_offset_degrees` is NOT in the spike brief's explicit list (`back_direction()`,
## `rotation_degrees()`, `size_to_frame()`) but has to be threaded through here too:
## `CameraRig._apply_transform()` sets `position` via this function and `rotation_degrees`
## via `rotation_degrees()` separately, and both need the SAME heading or the camera would
## face a different direction than it is offset toward — the world would go off-centre the
## moment the player rotated. Default 0.0 keeps `capture_save_thumbnail()` (never passes
## this) on the canonical framing untouched.
static func position_for(focus: Vector3, distance: float, yaw_offset_degrees: float = 0.0) -> Vector3:
	return focus + back_direction(yaw_offset_degrees) * distance
