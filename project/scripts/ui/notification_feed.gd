class_name NotificationFeed
extends Control
## The right-side rolling feed — Tier 1 rows 7 and 10's non-blocking presentation half.
## See docs/superpowers/specs/2026-08-23-notification-surfaces-design.md.
##
## Takes over two things that used to block input: repeat Fact Cards (every arrival after a
## species' first-ever one, and every Inspect-tap replay) and the Displacement Warning panel.
## A species' first-ever arrival still gets the big scrim'd `FactCard`, untouched — this widget
## never sees that case.
##
## UP TO MAX_VISIBLE_ENTRIES SHOWN AT ONCE, newest first, each aging independently. This is
## NOT the single-slot serial queue `NewsReportToast`/`DisplacementNotice`'s banner use — the
## whole point of a "TON of popups when animals come and go" is that serializing them one at a
## time just moves the bottleneck. A new entry past the cap evicts the OLDEST visible entry
## immediately rather than waiting for it to expire.
##
## NO EXPANSION. Per the design's human sign-off, a feed entry is the terminal UI for that
## event — so it renders the COMPLETE verified copy (never truncated) and offers only × in
## the top-right corner (dismiss early). NO 🔊 — Read-Aloud is the scrim'd first-arrival
## `FactCard`'s alone now (spec.md -> Screen Layouts); a nine-second entry that never
## auto-speaks was not a consent surface, and its button only ever stretched the row to the
## label's height. See `_make_entry()`.
##
## NO SCROLLABLE HISTORY. Expired means gone — this is what keeps Gentle Displacement's
## "no residue... no badge, no counter, no history" guarantee intact for warning entries.

signal entry_shown(text: String)
signal entry_dismissed(text: String)

## PROPOSED — human owns this. How many entries can be visible at once before the oldest is
## evicted to make room for a new one.
const MAX_VISIBLE_ENTRIES: int = 4

## PROPOSED — human owns this. Seconds an entry holds before auto-expiring. Longer than
## NewsReportToast's DISPLAY_SECONDS (7.0) since an entry here can carry a full fact-card body
## or a multi-family warning, not one toast line.
const ENTRY_HOLD_SECONDS: float = 9.0

## PROPOSED — human owns this. Pixels.
const ENTRY_WIDTH: float = 360.0

## PROPOSED — human owns this. Pixels of clear space between an entry's wrapped text and the
## × button overlaid in its top-right corner, so no line ever runs under the button.
const DISMISS_GUTTER: float = 12.0

const DISMISS_GLYPH: String = "×"

var _entries: Array[Dictionary] = []  # {"text": String, "node": PanelContainer, "age": float}

@onready var _stack: VBoxContainer = %Stack


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## A repeat Fact Card entry. `display_name`/`body` are the species' own data, composed
## identically to `FactCard.show_species()`'s internal `show_card()` call — this widget never
## phrases anything of its own.
func show_fact(display_name: String, body: String) -> bool:
	if body.strip_edges().is_empty():
		return false
	var text: String = "%s. %s" % [display_name, body] if not display_name.is_empty() else body
	return _push(text)


## A Displacement Warning entry. Same payload shape, same composition (lead + one line per
## affected home) `DisplacementNotice.show_warning()` uses — re-skinned into a compact card,
## not re-composed differently.
func show_warning(warning: Dictionary) -> bool:
	var homes: Array = warning.get("homes", []) as Array
	if homes.is_empty():
		return false
	var lines: Array[String] = [DisplacementCopy.lead(str(warning.get("mode", DisplacementCopy.SHIPPING_MODE)))]
	for home: Dictionary in homes:
		lines.append(DisplacementCopy.warn_line(
			str(home.get("species_id", "")),
			str(home.get("display_name", "")),
			bool(home.get("is_structure_home", false)),
			str(home.get("binding_need", ""))
		))
	return _push("\n".join(lines))


func entry_count() -> int:
	return _entries.size()


## Newest-first — index 0 is whatever just arrived.
func entry_texts() -> Array[String]:
	var texts: Array[String] = []
	for entry: Dictionary in _entries:
		texts.append(entry["text"] as String)
	return texts


func _push(text: String) -> bool:
	# Oldest is always the LAST element (newest is inserted at index 0 below), so eviction
	# targets the end of the array, not the front.
	while _entries.size() >= MAX_VISIBLE_ENTRIES:
		_remove_entry(_entries.size() - 1)
	var panel: PanelContainer = _make_entry(text)
	_stack.add_child(panel)
	_stack.move_child(panel, 0)
	_entries.insert(0, {"text": text, "node": panel, "age": 0.0})
	entry_shown.emit(text)
	set_process(true)
	return true


## One feed entry: the COMPLETE copy in a full-width label, with the × dismiss button laid
## over its top-right corner. No 🔊 (see the class header).
##
## LAYOUT. `PanelContainer` fits every child to its whole content rect, so the × cannot be a
## direct child of it without being stretched panel-tall — the exact bug this rework removes.
## Instead the panel holds two overlapping children: a `MarginContainer` whose right margin
## reserves a `HIT_TARGET`-wide gutter for the button (so no wrapped line runs under it), and
## a transparent, mouse-ignoring `Control` of zero minimum size (it never affects how the
## panel sizes to the label) that hosts the button, anchored into its own top-right corner.
func _make_entry(text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ENTRY_WIDTH, 0.0)
	panel.add_theme_stylebox_override(
		"panel", UiPalette.panel_style(UiPalette.CREAM, UiPalette.CORNER_RADIUS_SMALL, 16)
	)
	# The root's own MOUSE_FILTER_IGNORE (_ready()) does not propagate to children — each
	# entry's own nodes default to STOP and would otherwise wall off a gameplay tap that lands
	# on the label or the panel's padding, not just the dismiss button.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var button_size: float = UiPalette.scaled(UiPalette.HIT_TARGET)

	var content := MarginContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("margin_right", int(button_size + DISMISS_GUTTER))
	panel.add_child(content)

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", UiPalette.FONT_NOTICE_LINE)
	label.add_theme_color_override("font_color", UiPalette.BARK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(label)

	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(overlay)

	var dismiss := Button.new()
	dismiss.text = DISMISS_GLYPH
	dismiss.custom_minimum_size = Vector2(button_size, button_size)
	dismiss.anchor_left = 1.0
	dismiss.anchor_right = 1.0
	dismiss.anchor_top = 0.0
	dismiss.anchor_bottom = 0.0
	dismiss.offset_left = -button_size
	dismiss.offset_top = 0.0
	dismiss.offset_right = 0.0
	dismiss.offset_bottom = button_size
	UiPalette.paint_button(dismiss, false)
	dismiss.pressed.connect(func() -> void: _dismiss_node(panel))
	overlay.add_child(dismiss)

	return panel


func _dismiss_node(panel: PanelContainer) -> void:
	for i: int in range(_entries.size()):
		if (_entries[i]["node"] as PanelContainer) == panel:
			_remove_entry(i)
			return


func _remove_entry(index: int) -> void:
	var entry: Dictionary = _entries[index]
	var node: PanelContainer = entry["node"]
	var text: String = entry["text"]
	_entries.remove_at(index)
	# Detach synchronously, not just `queue_free()`: `queue_free()` alone defers removal
	# from the tree to end-of-frame idle time, so a `find_children()` scan run again
	# before that idle pass (as the headless test's tight dismiss-loop does) would still
	# find this same node, click it again, and no-op forever against an entry already
	# gone from `_entries`.
	_stack.remove_child(node)
	node.queue_free()
	entry_dismissed.emit(text)


func _process(delta: float) -> void:
	var expired: Array[int] = []
	for i: int in range(_entries.size()):
		var age: float = (_entries[i]["age"] as float) + delta
		_entries[i]["age"] = age
		if age >= ENTRY_HOLD_SECONDS:
			expired.append(i)
	# Highest index first, so removing one doesn't shift the indices still queued for removal.
	for i: int in range(expired.size() - 1, -1, -1):
		_remove_entry(expired[i])
	if _entries.is_empty():
		set_process(false)
