class_name Crosshair
extends Control
## The persistent aim point (playability chrome overhaul, section 1). Structurally
## parallel to `TapCue`: drawn in 2D at a fixed screen point, the viewport centre — D-33's
## original convention, from back when `TapRouter` tracked a fixed screen-centre crosshair
## position of its own. D-41 replaced that with real-cursor tracking (`TapRouter` now follows
## the actual mouse position, no stored crosshair point to reuse), so this control is the last
## piece still drawn at a fixed centre point; it is not wired to `TapRouter`'s cursor position
## at all. Permanently dark under the new camera regardless: `_is_shown()` below gates on
## `Input.mouse_mode == MOUSE_MODE_CAPTURED`, which nothing sets any more.
##
## TWO INDEPENDENT REASONS TO BE OFF SCREEN, kept as two separate flags rather than one:
##   * the pointer is not captured (Tab was pressed) — `_captured`, this file's own read of
##     `Input.mouse_mode`, the same global property `TapRouter`/`CameraRig` read directly
##     rather than a bespoke signal (see `camera_rig.gd`'s own comment on that choice).
##   * an overlay the player opened deliberately is up (a FactCard or `MenuWindow` — which,
##     as of the Minecraft-style inventory window, is the one shell hosting the browse grids,
##     the Field Guide, and Settings as tabs, replacing the standalone Catalog panel this
##     comment used to name separately) — `_suppressed`, set externally by `GameUI`, which is
##     the one place that already knows about every overlay.
## Both must be false for the reticle to draw.

var _valid: bool = false
var _suppressed: bool = false
var _captured: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if captured != _captured:
		_captured = captured
		queue_redraw()


func set_valid(valid: bool) -> void:
	if valid == _valid:
		return
	_valid = valid
	queue_redraw()


func is_valid() -> bool:
	return _valid


func set_suppressed(suppressed: bool) -> void:
	if suppressed == _suppressed:
		return
	_suppressed = suppressed
	queue_redraw()


func is_suppressed() -> bool:
	return _suppressed


func _is_shown() -> bool:
	return _captured and not _suppressed


func _draw() -> void:
	if not _is_shown():
		return
	var centre: Vector2 = get_viewport_rect().size * 0.5
	var colour: Color = UiPalette.CROSSHAIR_VALID if _valid else UiPalette.CROSSHAIR_INVALID
	var gap: float = UiPalette.CROSSHAIR_GAP
	var arm: float = UiPalette.CROSSHAIR_ARM_LENGTH
	var thickness: float = UiPalette.CROSSHAIR_THICKNESS
	draw_line(centre + Vector2(gap, 0.0), centre + Vector2(gap + arm, 0.0), colour, thickness)
	draw_line(centre + Vector2(-gap, 0.0), centre + Vector2(-gap - arm, 0.0), colour, thickness)
	draw_line(centre + Vector2(0.0, gap), centre + Vector2(0.0, gap + arm), colour, thickness)
	draw_line(centre + Vector2(0.0, -gap), centre + Vector2(0.0, -gap - arm), colour, thickness)
