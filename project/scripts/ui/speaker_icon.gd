class_name SpeakerIcon
extends Control
## Vector-drawn speaker glyph for the Read-Aloud buttons (FactCard.tscn,
## DisplacementNotice.tscn). Replaces `Button.text = "🔊"/"🔇"` — U+1F50A/U+1F507 are not
## covered by the bundled default font's glyph set (Godot's built-in Open Sans SemiBold; no
## custom font ships), so the web build drew each as a missing-glyph "tofu" box instead of a
## speaker (human-reported: "the sound icon is broken on the web builds").
##
## THE THIRD INSTANCE of this same bug class, after `rotate_icon.gd` (U+21BA/U+21BB) and
## `popup_indicator_glyph.gd` (U+25BE) — and, unlike those two, `fact_card.gd`'s own header
## had predicted it in a comment. It renders correctly in the editor and in a desktop build
## only because Godot's system-font fallback resolves the emoji from an installed system font;
## the HTML5/Web export has no fontconfig and no such fallback. Drawing the speaker with
## `draw_rect()`/`draw_colored_polygon()`/`draw_arc()`/`draw_line()` instead means it can never
## depend on font glyph coverage on any export target.
##
## `test_font_glyph_coverage.gd` now guards the whole class of bug, so there should not be a
## fourth instance.
##
## Structurally parallel to `rotate_icon.gd`: a mouse-transparent Control layered over its
## parent (here, the Button itself) that only ever calls `queue_redraw()`/`_draw()`.

## True draws the muted speaker (body plus a cross where the waves would be), false draws the
## speaking one (body plus two sound waves). `fact_card.gd` flips this from the shared
## `GameplaySettings.speaking_enabled()` toggle; `displacement_notice.gd` leaves it false,
## because that surface hides its button outright rather than showing a muted state.
@export var muted: bool = false:
	set(value):
		if muted == value:
			return
		muted = value
		queue_redraw()

## Geometry as fractions of the icon's shortest side, so the glyph scales with whatever size
## the parent Button's anchors resolve to rather than pinning pixels the way a font size would.
## The cone's mouth sits at CONE_FRONT_X; the waves are arcs centred there.
const BODY_LEFT: float = 0.16
const BODY_RIGHT: float = 0.36
const BODY_HALF_HEIGHT: float = 0.12
const CONE_BACK_X: float = 0.34
const CONE_FRONT_X: float = 0.56
const CONE_HALF_HEIGHT: float = 0.30
const THICKNESS: float = 0.06
const WAVE_INNER_RADIUS: float = 0.13
const WAVE_OUTER_RADIUS: float = 0.23
const WAVE_HALF_SWEEP_DEGREES: float = 34.0
const WAVE_POINTS: int = 16
const CROSS_NEAR_X: float = 0.64
const CROSS_FAR_X: float = 0.86
const CROSS_HALF_HEIGHT: float = 0.13


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# The shortest side drives every dimension, and the glyph is centred in the long one, so a
	# non-square button (the fact card's is 88x72) gets an undistorted speaker rather than a
	# stretched one.
	var scale: float = minf(size.x, size.y)
	var centre: Vector2 = size * 0.5
	var thickness: float = THICKNESS * scale

	# The body is drawn as a rectangle plus a separate convex trapezoid rather than one
	# concave polygon: `draw_colored_polygon()` triangulates, and a convex piece is the shape
	# it is guaranteed to get right. They overlap by (BODY_RIGHT - CONE_BACK_X) so no seam
	# shows between them.
	draw_rect(
		Rect2(
			centre + Vector2(BODY_LEFT - 0.5, -BODY_HALF_HEIGHT) * scale,
			Vector2(BODY_RIGHT - BODY_LEFT, BODY_HALF_HEIGHT * 2.0) * scale
		),
		UiPalette.BARK
	)
	draw_colored_polygon(
		PackedVector2Array([
			centre + Vector2(CONE_BACK_X - 0.5, -BODY_HALF_HEIGHT) * scale,
			centre + Vector2(CONE_FRONT_X - 0.5, -CONE_HALF_HEIGHT) * scale,
			centre + Vector2(CONE_FRONT_X - 0.5, CONE_HALF_HEIGHT) * scale,
			centre + Vector2(CONE_BACK_X - 0.5, BODY_HALF_HEIGHT) * scale,
		]),
		UiPalette.BARK
	)

	var mouth: Vector2 = centre + Vector2((CONE_FRONT_X - 0.5) * scale, 0.0)
	if muted:
		var near_x: float = centre.x + (CROSS_NEAR_X - 0.5) * scale
		var far_x: float = centre.x + (CROSS_FAR_X - 0.5) * scale
		var high_y: float = centre.y - CROSS_HALF_HEIGHT * scale
		var low_y: float = centre.y + CROSS_HALF_HEIGHT * scale
		draw_line(Vector2(near_x, high_y), Vector2(far_x, low_y), UiPalette.BARK, thickness, true)
		draw_line(Vector2(near_x, low_y), Vector2(far_x, high_y), UiPalette.BARK, thickness, true)
		return

	var half_sweep: float = deg_to_rad(WAVE_HALF_SWEEP_DEGREES)
	for radius: float in [WAVE_INNER_RADIUS, WAVE_OUTER_RADIUS]:
		draw_arc(
			mouth, radius * scale, -half_sweep, half_sweep, WAVE_POINTS,
			UiPalette.BARK, thickness, true
		)
