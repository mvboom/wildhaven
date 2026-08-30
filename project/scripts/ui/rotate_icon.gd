class_name RotateIcon
extends Control
## Vector-drawn rotate glyph for RotateCcwButton/RotateCwButton (GameUI.tscn). Replaces the
## previous Button `text = "↺"/"↻"` — those two Unicode circle-arrow codepoints (U+21BA/
## U+21BB) aren't covered by the bundled default font's glyph set in the HTML5/Web export,
## so the web build drew each as a missing-glyph "tofu" box instead of an arrow (human-
## reported, screenshot). Drawing the arrow with draw_arc()/draw_line() instead means it
## can never depend on font glyph coverage on any export target.
##
## Structurally parallel to crosshair.gd: a mouse-transparent Control layered over its
## parent (here, the Button itself) that only ever calls queue_redraw()/_draw().

## True draws a clockwise arrow (RotateCwButton), false draws counterclockwise (RotateCcwButton).
@export var clockwise: bool = true

const RADIUS: float = 16.0
const THICKNESS: float = 4.0
const ARROW_SIZE: float = 7.0
const SWEEP_DEGREES: float = 260.0
const ARROW_WING_ANGLE: float = 28.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var centre: Vector2 = size * 0.5
	var half_sweep: float = deg_to_rad(SWEEP_DEGREES) * 0.5
	var mid: float = deg_to_rad(-90.0)
	# draw_arc() sweeps start_rad -> end_rad by linear interpolation, so which one is larger
	# decides the on-screen sweep direction (Godot's Y axis points down, so increasing angle
	# reads as clockwise) — `direction` mirrors that same choice for the arrowhead tangent.
	var start_rad: float
	var end_rad: float
	var direction: float
	if clockwise:
		start_rad = mid - half_sweep
		end_rad = mid + half_sweep
		direction = 1.0
	else:
		start_rad = mid + half_sweep
		end_rad = mid - half_sweep
		direction = -1.0

	draw_arc(centre, RADIUS, start_rad, end_rad, 24, UiPalette.BARK, THICKNESS, true)

	var tip: Vector2 = centre + Vector2(cos(end_rad), sin(end_rad)) * RADIUS
	var travel: Vector2 = Vector2(-sin(end_rad), cos(end_rad)) * direction
	var back: Vector2 = -travel
	var wing_angle: float = deg_to_rad(ARROW_WING_ANGLE)
	var wing_a: Vector2 = tip + back.rotated(wing_angle) * ARROW_SIZE
	var wing_b: Vector2 = tip + back.rotated(-wing_angle) * ARROW_SIZE
	draw_line(tip, wing_a, UiPalette.BARK, THICKNESS, true)
	draw_line(tip, wing_b, UiPalette.BARK, THICKNESS, true)
