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
	# Final review finding (deferred item folded in): `CoachChip.tscn` used to hardcode the
	# dismiss button's size (72) and the content's `margin_right` gutter (84 = 72 + 12) as pixel
	# literals — a `.tscn` cannot call a static method at author time, so it could not derive
	# them the way `notification_feed.gd::_make_entry()` does for the IDENTICAL layout (a
	# `PanelContainer` with a `MarginContainer` reserving room for a corner-anchored dismiss
	# button). `_ready()` can call statics, so it does the same derivation here instead of
	# carrying a second, independently-drifting copy of those two numbers.
	var button_size: float = UiPalette.scaled(UiPalette.HIT_TARGET)
	_dismiss.custom_minimum_size = Vector2(button_size, button_size)
	var content := _panel.get_node("Content") as MarginContainer
	content.add_theme_constant_override(
		"margin_right", int(button_size + NotificationFeed.DISMISS_GUTTER)
	)
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
		# Final review finding #2: `_panel.size` is read on the very first frame after
		# `visible = true`, before Godot's own layout pass has run over a panel that was just
		# made visible — so it reads last frame's (usually zero) size and the panel pops into its
		# real position one frame later. `get_combined_minimum_size()` asks the container to
		# compute its size on demand instead of waiting for the deferred layout pass, so it is
		# correct on frame one.
		var panel_size: Vector2 = _panel.get_combined_minimum_size()
		var target_x: float = rect.get_center().x - panel_size.x * 0.5
		var target_y: float = rect.position.y - panel_size.y - RING_MARGIN * 2.0
		# Beat 1 points at the `[?]` button, whose global centre (x=60) sits well inside the
		# panel's own half-width (>=140, from the 280px `custom_minimum_size` in
		# `CoachChip.tscn`) — left uncorrected, `target_x` goes negative and `Control` does not
		# clip children, so the panel (and its wrapped label) render partly off the left edge of
		# the viewport. Clamped to the viewport on both axes, leaving `RING_MARGIN` of breathing
		# room on every side the panel could otherwise overhang.
		var viewport_size: Vector2 = get_viewport_rect().size
		_panel.position = Vector2(
			clampf(target_x, RING_MARGIN, viewport_size.x - panel_size.x - RING_MARGIN),
			clampf(target_y, RING_MARGIN, viewport_size.y - panel_size.y - RING_MARGIN)
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
