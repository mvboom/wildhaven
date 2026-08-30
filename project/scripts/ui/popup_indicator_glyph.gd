class_name PopupIndicatorGlyph
extends Control
## Vector-drawn "this button has a long-press popup" glyph (style-picker refinement round,
## review fix). Replaces an earlier `Label` with `text = "▾"` (U+25BE) — the SAME bug class
## `rotate_icon.gd` already hit and fixed two days prior: `has_char()` is `false` for U+25BE in
## this project's bundled font (Godot's built-in Open Sans SemiBold; no custom font ships), so
## it only rendered correctly in this dev container because Godot's system-font fallback
## resolved it via an installed CJK font (`wqy-zenhei.ttc`) — a fallback that does not exist in
## the HTML5/Web export, which has no system fontconfig. A web build would have drawn a
## missing-glyph "tofu" box here instead of a triangle. Drawing it with
## `draw_colored_polygon()` instead means this can never depend on font glyph coverage on any
## export target — see `rotate_icon.gd`'s own header for the original, confirmed-via-screenshot
## instance of this same failure.
##
## Sized and positioned by its parent exactly the way `Number`'s badge is (a small anchored box
## in a palette button's corner, set by `game_hud.gd`'s `_decorate_button()`) — this only ever
## draws a downward-pointing triangle that fills whatever `size` those anchors/offsets resolve
## to, so it never needs its own size constants duplicated here.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var points := PackedVector2Array([
		Vector2(w * 0.15, h * 0.3),
		Vector2(w * 0.85, h * 0.3),
		Vector2(w * 0.5, h * 0.75),
	])
	draw_colored_polygon(points, UiPalette.BARK)
