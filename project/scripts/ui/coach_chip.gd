class_name CoachChip
extends Control
## The coach's one visible element: a small cream card anchored over a target button, with a
## soft ring pulsing around that button.
##
## THE RING REUSES `TapCue`'S VOCABULARY WITHOUT TOUCHING `TapCue`. That file owns the whole
## of the game's "yes"/"not here" language (a leaf-green expanding ring, a warmer quiet one);
## this draws in the same `UiPalette.CUE_ACCEPT` so a pointed-at button reads as the same
## affirmative, but the pulse loops rather than expiring, which is not a cue vocabulary and
## does not belong in that file.
##
## THE TARGET RECT IS RE-READ WHILE VISIBLE, never cached at show time — `UI_SCALE_FACTOR`,
## a resize, or a palette rebuild all move the button underneath us.

signal dismissed()

## PROPOSED — human owns this. Seconds per pulse. Slow enough to read as an invitation rather
## than an alarm.
const PULSE_PERIOD: float = 1.6

## PROPOSED — human owns this. Pixels of clearance between the ring and the button's edge.
const RING_MARGIN: float = 6.0

const DISMISS_GLYPH: String = "×"

var _target: Control = null
var _elapsed: float = 0.0

@onready var _panel: PanelContainer = %Panel
@onready var _label: Label = %Label
@onready var _dismiss: Button = %Dismiss


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override(
		"panel", UiPalette.panel_style(UiPalette.CREAM, UiPalette.CORNER_RADIUS_SMALL, 16)
	)
	_label.add_theme_color_override("font_color", UiPalette.BARK)
	_dismiss.text = DISMISS_GLYPH
	UiPalette.paint_button(_dismiss, false)
	_dismiss.pressed.connect(func() -> void: dismissed.emit())
	hide_chip()


## `target` may be null — the chip then centres itself and draws no ring.
func show_chip(text: String, target: Control) -> void:
	_label.text = text
	_target = target
	_elapsed = 0.0
	visible = true
	set_process(true)


func hide_chip() -> void:
	visible = false
	_target = null
	set_process(false)


func _process(delta: float) -> void:
	_elapsed += delta
	if _target != null and _target.is_inside_tree():
		var rect: Rect2 = _target.get_global_rect()
		_panel.position = Vector2(
			rect.get_center().x - _panel.size.x * 0.5,
			rect.position.y - _panel.size.y - RING_MARGIN * 2.0
		)
	queue_redraw()


func _draw() -> void:
	if _target == null or not _target.is_inside_tree():
		return
	var rect: Rect2 = _target.get_global_rect()
	var phase: float = fmod(_elapsed, PULSE_PERIOD) / PULSE_PERIOD
	var radius: float = maxf(rect.size.x, rect.size.y) * 0.5 + RING_MARGIN + phase * RING_MARGIN
	var colour := Color(UiPalette.CUE_ACCEPT, UiPalette.CUE_ACCEPT.a * (1.0 - phase))
	draw_arc(rect.get_center(), radius, 0.0, TAU, 32, colour, 4.0, true)
