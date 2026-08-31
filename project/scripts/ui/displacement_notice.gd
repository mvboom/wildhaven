class_name DisplacementNotice
extends Control
## Gentle Displacement's face — Tier 1 row 10's presentation half.
##
## Three things, in the order the player meets them:
##
##   1. THE WARNING — one panel per `WorldRoot.displacement_warned`, summarising **every**
##      affected home: one lead sentence, then one line per family. Carries Read-Aloud 🔊.
##   2. THE MOVE MARKER — for a relocation, a fading trail from the old home to the new one, so
##      "the animal visibly moves its home" is visible even if the player is looking elsewhere
##      on screen; for a departure, a single ring at the home that fades outward.
##   3. THE MOMENT BANNER — the plain-game-voice line for each consequence, one at a time.
##
## **THE WARNING IS DISCLOSURE, NOT DETERRENCE, AND THAT IS AN ABSENCE YOU CAN AUDIT.** There is
## no confirm, no cancel, no "are you sure", and no channel back into the simulation — gdd.md
## rejects blocking the build outright ("a fail state") and calls the warning "disclosure, not
## deterrence … no plea, no judgment, no residue afterward". This class declares exactly one
## signal, `warning_dismissed`, which nothing in the game branches on. The player's undo is the
## ordinary one they already know: put the neighbourhood back and the arithmetic un-does it.
## **No new interaction pattern** — Pillar 3 is absolute, and a dialogue with two answers would
## be a sixth one.
##
## **IT IS NOT THE NEWS REPORT VOICE, AND IT DOES NOT LOOK LIKE ONE.** gdd.md -> Discovery:
## "consent copy must never sound like flavor." The distinction is made structurally, not by
## restraint: the warning is a **centred multi-line panel** with its own face colour and its own
## dismiss control, while the after-the-fact consequence lines use the **top-centre banner** —
## the toast register spec.md gives News Reports. They can never be mistaken for each other
## because they are not the same widget in the same place.
##
## **NO SCRIM, AND THE WORLD IS NEVER PAUSED.** Unlike `FactCard`, this panel puts no full-screen
## sheet over the world. gdd.md's design guarantees for the first sixty seconds: "no modal blocks
## the world." The player can pan, zoom, and edit around the panel while it is up — which is
## precisely what makes the undo path real rather than claimed, because it does not require
## dismissing the disclosure first.
##
## **NO RESIDUE AFTERWARD.** Dismissal frees the line labels, drops the queue's memory of the
## gesture, and leaves nothing: no badge, no counter, no history, no "you displaced 3 families"
## anywhere. `warning_text()` returns "" the moment it closes.
##
## COPY IS NOT THIS FILE'S. Every rendered word comes from `DisplacementCopy`, which is
## content-writer's `docs/content/displacement-copy.md` verbatim. This class composes and
## renders; it never phrases.

## Fires when the warning panel closes. Informational — nothing gates on it, and there is no
## "accepted"/"cancelled" distinction to carry because there is no choice being made.
signal warning_dismissed()

## PROPOSED — human owns this. How long one consequence line holds on the banner, in seconds.
## Sized for a fluent 8-year-old reading a one-sentence line twice, not once; spec.md gives no
## banner constant, and the News Report row (12) that will own the toast is unbuilt.
const MOMENT_SECONDS: float = 4.5

## PROPOSED — human owns this. Seconds the move marker takes to fade. Long enough that an eye
## already crossing the screen catches it, short enough that it is gone before the banner is.
const MARKER_SECONDS: float = 1.6

## PROPOSED — human owns this. **The consequence beat.** Consequence lines are held back while
## the warning panel is open and released when it is dismissed, so the player reads the
## disclosure first and the outcomes after — gdd.md's "warning first and acting after", supplied
## at the only layer that can supply it. The simulation emits both inside one settlement and this
## class cannot (and must not) delay it; what it can order is what the player is *told* and when.
## Set false to let banners run under an open warning panel.
const HOLD_MOMENTS_UNTIL_DISMISSED: bool = true

## PROPOSED — human owns this. A hard cap on the held queue, so a warning left open on screen
## can never accumulate an unbounded backlog of lines to play out later. Beyond it the OLDEST
## line is dropped: a stale line about a family that moved two gestures ago is the one with the
## least to say, and "no residue" argues against ever replaying it.
const MAX_QUEUED_MOMENTS: int = 8

## PROPOSED — human owns this. Breathing room, in pixels, kept clear above and below the
## warning panel when clamping `%LinesScroll`'s height in `_clamp_lines_height()` — the panel
## must never touch the screen edges, let alone cross them. Same order of magnitude as the
## panel's own 32px content margin.
const SCREEN_MARGIN: float = 48.0

## PROPOSED — human owns this. The floor `%LinesScroll` is clamped to even when the viewport is
## too short to fit the rest of the dialogue (lead, rule, button row) plus `SCREEN_MARGIN` —
## so the list still shows at least a couple of lines and a working scrollbar rather than
## collapsing to nothing.
const MIN_LINES_HEIGHT: float = 72.0

## PROPOSED — human owns this. Pixels of `%Lead`/line text width `_clamp_lines_height()` gives
## up so a wrap-height estimate computed BEFORE `%LinesScroll` has ever shown a scrollbar still
## holds once one appears (a scrollbar narrows the usable text column, which can push one more
## word to the next line) — a slight over-estimate of height is a few harmless spare pixels; an
## under-estimate is clipped text.
const SCROLLBAR_WIDTH_ALLOWANCE: float = 24.0

## The glyphs. Deliberately the same two `FactCard` already uses, so the player meets one
## dismiss control and one Read-Aloud control in the whole game rather than two dialects —
## which is why the Read-Aloud speaker moved to `SpeakerIcon` (a vector Control on the
## button, `%Icon`) here at the same time it did there: it was text "🔊", a codepoint the
## bundled font lacks, so the web build drew a tofu box. `test_font_glyph_coverage.gd`
## guards both surfaces now. `×` (U+00D7) IS in the bundled font, so it stays text.
const DISMISS_GLYPH: String = "×"

## Marker shapes. PROPOSED — human owns these. Pixels.
const MARKER_RADIUS: float = 26.0
const MARKER_RADIUS_END: float = 54.0
const MARKER_WIDTH: float = 5.0
const MARKER_DASH: float = 14.0


var _spoken_text: String = ""
var _line_texts: Array[String] = []
var _moments: Array[String] = []
var _moment_clock: float = 0.0
var _markers: Array[Dictionary] = []

@onready var _warning: PanelContainer = %Warning
@onready var _stack: VBoxContainer = %Stack
@onready var _lead: Label = %Lead
@onready var _rule: HSeparator = %Rule
@onready var _lines_scroll: ScrollContainer = %LinesScroll
@onready var _lines: VBoxContainer = %Lines
@onready var _button_row: HBoxContainer = %ButtonRow
@onready var _read_aloud_button: Button = %ReadAloudButton
@onready var _close_button: Button = %CloseButton
@onready var _banner: PanelContainer = %Banner
@onready var _banner_label: Label = %BannerLabel


func _ready() -> void:
	# The root is a pass-through sheet: only the panel and its two buttons take the mouse, so
	# every tap that is not on the dialogue still reaches the world underneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warning.add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.NOTICE_FACE))
	_banner.add_theme_stylebox_override(
		"panel", UiPalette.panel_style(UiPalette.CREAM, UiPalette.CORNER_RADIUS_SMALL, 18)
	)
	_lead.add_theme_font_size_override("font_size", UiPalette.FONT_NOTICE_LEAD)
	_lead.add_theme_color_override("font_color", UiPalette.BARK)
	_banner_label.add_theme_font_size_override("font_size", UiPalette.FONT_BANNER)
	_banner_label.add_theme_color_override("font_color", UiPalette.BARK)

	_close_button.text = DISMISS_GLYPH
	UiPalette.paint_button(_read_aloud_button, false)
	UiPalette.paint_button(_close_button, false)
	_read_aloud_button.pressed.connect(read_aloud)
	_close_button.pressed.connect(dismiss_warning)

	_warning.visible = false
	_banner.visible = false
	set_process(false)


# --- 1. The warning ------------------------------------------------------------------------

## Renders one `WorldRoot.displacement_warned` payload as **one dialogue**: the lead, then one
## line per affected home, in the payload's own order.
##
## THE ORDER IS THE PAYLOAD'S AND IS NOT RE-SORTED. The handoff doc: "the order is not
## load-bearing and no line may be phrased to explain another's move." Re-ordering could only
## ever create the appearance of a causal sequence between two families, which is exactly what
## the Fox↔Rabbit avoids pair makes dangerous — so nothing here sorts.
##
## Returns false, showing nothing, for a payload with no affected homes. That case never reaches
## here (`GentleDisplacement` returns early on an empty list, which is the revert case), and an
## empty dialogue would be a warning about nothing.
func show_warning(warning: Dictionary) -> bool:
	var homes: Array = warning.get("homes", []) as Array
	if homes.is_empty():
		return false

	_clear_lines()
	_line_texts.clear()

	# ONE LEAD. It carries the player's action and nothing else; that split is what makes the
	# forbidden sentence unwriteable rather than merely avoided. See `DisplacementCopy`.
	_lead.text = DisplacementCopy.lead(str(warning.get("mode", DisplacementCopy.SHIPPING_MODE)))

	# ONE LINE PER FAMILY. Never merged into the lead, never merged with each other.
	for home: Dictionary in homes:
		var text: String = DisplacementCopy.warn_line(
			str(home.get("species_id", "")),
			str(home.get("display_name", "")),
			bool(home.get("is_structure_home", false)),
			str(home.get("binding_need", ""))
		)
		_line_texts.append(text)
		_lines.add_child(_make_line_label(text))

	# THE READ-ALOUD SLICE (spec.md: "present on every fact card and on the displacement
	# warning"). Consent must not require fluent reading — so the spoken form is the whole
	# dialogue, lead first, exactly as it reads. Every string is a complete sentence with no em
	# dashes, parentheses or glyphs, which is what lets a voice honour the punctuation.
	_spoken_text = " ".join([_lead.text] + _line_texts)

	var offered: bool = (
		bool(warning.get("read_aloud", true))
		and ReadAloud.available()
		and GameplaySettings.speaking_enabled()
	)
	# A control that cannot do anything is worse than no control (Pillar 1): with no voice on the
	# machine the button is simply absent, and the dialogue is otherwise identical. **Read-Aloud
	# degrading silently must never degrade the disclosure** — the text is always on screen.
	_read_aloud_button.visible = offered

	_clamp_lines_height()
	_warning.visible = true
	move_to_front()
	return true


## Closes the warning and leaves nothing behind.
func dismiss_warning() -> void:
	if not _warning.visible:
		return
	_warning.visible = false
	ReadAloud.stop()
	_clear_lines()
	_line_texts.clear()
	_spoken_text = ""
	_lead.text = ""
	_pump_moments()
	warning_dismissed.emit()


func warning_visible() -> bool:
	return _warning != null and _warning.visible


## The full dialogue as one string, lead first. "" when nothing is up — there is no residue.
func warning_text() -> String:
	return _spoken_text


## The lead sentence alone. Exposed so a check can prove the composition really is lead-plus-list
## and not one flattened sentence per family.
func lead_text() -> String:
	return "" if _lead == null else _lead.text


## One entry per affected home, in payload order.
func warning_lines() -> Array[String]:
	return _line_texts.duplicate()


## What 🔊 would speak. The only way to observe Read-Aloud on a machine with no voices.
func spoken_text() -> String:
	return _spoken_text


func read_aloud_offered() -> bool:
	return _read_aloud_button != null and _read_aloud_button.visible


func read_aloud() -> bool:
	return ReadAloud.speak(_spoken_text)


func _make_line_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", UiPalette.FONT_NOTICE_LINE)
	label.add_theme_color_override("font_color", UiPalette.BARK)
	return label


func _clear_lines() -> void:
	if _lines == null:
		return
	for child: Node in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()


## Caps `%LinesScroll`'s height so `%Warning` — a centred panel that otherwise grows to fit
## every line, symmetrically in both directions — can never push `%ButtonRow` (and the dismiss
## control inside it) past the top or bottom of the viewport when a settlement affects many
## families at once. A short list still renders at its natural height (no empty space, no
## scrollbar); a long one is clamped and scrolls.
##
## MEASURES TEXT DIRECTLY VIA `Font.get_multiline_string_size()`, NOT `Control.
## get_combined_minimum_size()`. `%Lead` and each `%Lines` label are added/populated the same
## call as this method runs, and an autowrap `Label`'s reported minimum height is only correct
## once a real layout pass has assigned it its actual width — which, for a panel that has been
## `visible = false` since `_ready()` (true for every FIRST warning of a session), has not
## happened yet. Measuring the font directly against `%Warning`'s own known, layout-independent
## content width sidesteps that race rather than chasing it with a deferred call (which would
## also mean showing the wrongly-sized panel for one visible frame first).
func _clamp_lines_height() -> void:
	if _lines_scroll == null or _lines == null or _stack == null:
		return
	var font: Font = _lead.get_theme_font("font")
	var content_width: float = _lines_content_width()
	var chrome_height: float = (
		_multiline_height(font, _lead.text, content_width, UiPalette.FONT_NOTICE_LEAD)
		+ _rule.get_combined_minimum_size().y
		+ _button_row.get_combined_minimum_size().y
		+ _stack.get_theme_constant("separation") * 3.0
		+ _panel_vertical_margin(_warning) * 2.0
	)
	var natural_height: float = 0.0
	for text: String in _line_texts:
		natural_height += _multiline_height(font, text, content_width, UiPalette.FONT_NOTICE_LINE)
	if _line_texts.size() > 1:
		natural_height += _lines.get_theme_constant("separation") * float(_line_texts.size() - 1)
	var viewport_height: float = get_viewport_rect().size.y
	var available_height: float = viewport_height - chrome_height - SCREEN_MARGIN
	_lines_scroll.custom_minimum_size.y = minf(natural_height, maxf(available_height, MIN_LINES_HEIGHT))


## `%Warning`'s content width, independent of any container sort: its horizontal size is a fixed
## `custom_minimum_size` (never shrink-wrapped), so this is reliable at any point in the
## lifecycle. A little narrower than the panel's own content box, as headroom for the vertical
## scrollbar `%LinesScroll` may or may not end up showing.
func _lines_content_width() -> float:
	return _warning.custom_minimum_size.x - _panel_horizontal_margin(_warning) - SCROLLBAR_WIDTH_ALLOWANCE


func _panel_horizontal_margin(panel: PanelContainer) -> float:
	var style: StyleBox = panel.get_theme_stylebox("panel")
	return style.content_margin_left + style.content_margin_right


func _panel_vertical_margin(panel: PanelContainer) -> float:
	var style: StyleBox = panel.get_theme_stylebox("panel")
	return style.content_margin_top + style.content_margin_bottom


func _multiline_height(font: Font, text: String, width: float, font_size: int) -> float:
	return font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, -1,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	).y


# --- 2 & 3. The consequences ---------------------------------------------------------------

## `WorldRoot.resident_relocated` — the first of gdd.md's two gentle outcomes, and the one that
## runs most often. The home visibly moves: a trail from where it was to where it is now, plus
## the plain-game-voice line.
func note_relocation(
	species_id: String, display_name: String, from_position: Vector3, to_position: Vector3
) -> void:
	_push_marker(from_position, to_position)
	_push_moment(DisplacementCopy.relocate_line(species_id, display_name))


## `WorldRoot.resident_departed` — the second outcome. **Framed as finding a home elsewhere,
## never as loss**, and the copy carries a destination in every case, so nothing here needs to
## soften anything. Species Hosted and the Field Guide entry are permanent and untouched.
func note_departure(species_id: String, display_name: String, world_position: Vector3) -> void:
	_push_marker(world_position, world_position)
	_push_moment(DisplacementCopy.depart_line(species_id, display_name))


func _push_moment(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	_moments.append(text)
	while _moments.size() > MAX_QUEUED_MOMENTS:
		_moments.pop_front()
	_pump_moments()


## Starts the next banner line if the floor is free. The gate is the whole of the beat: while the
## warning is up, consequence lines wait.
func _pump_moments() -> void:
	if _banner == null:
		return
	if HOLD_MOMENTS_UNTIL_DISMISSED and warning_visible():
		return
	if _banner.visible or _moments.is_empty():
		_wake()
		return
	_banner_label.text = _moments.pop_front()
	_banner.visible = true
	_moment_clock = 0.0
	_wake()


func banner_visible() -> bool:
	return _banner != null and _banner.visible


func banner_text() -> String:
	return "" if _banner == null or not _banner.visible else _banner_label.text


func queued_moments() -> int:
	return _moments.size()


## Drains the banner queue instantly. For headless checks, and for a future "skip" the game does
## not have; nothing in the running game calls it.
func clear_moments() -> void:
	_moments.clear()
	if _banner != null:
		_banner.visible = false


func _push_marker(from_position: Vector3, to_position: Vector3) -> void:
	_markers.append({"from": from_position, "to": to_position, "age": 0.0})
	_wake()


func _wake() -> void:
	var banner_up: bool = _banner != null and _banner.visible
	set_process(not _markers.is_empty() or banner_up or not _moments.is_empty())
	queue_redraw()


func _process(delta: float) -> void:
	if _banner.visible:
		_moment_clock += delta
		if _moment_clock >= MOMENT_SECONDS:
			_banner.visible = false
			_moment_clock = 0.0
			_pump_moments()

	if not _markers.is_empty():
		var alive: Array[Dictionary] = []
		for marker: Dictionary in _markers:
			marker["age"] = (marker["age"] as float) + delta
			if (marker["age"] as float) < MARKER_SECONDS:
				alive.append(marker)
		_markers = alive
		queue_redraw()

	_wake()


## The move marker. Drawn in 2D over the world, projecting live world positions through the live
## camera every frame, so it stays anchored to the ground while the player pans — the same reason
## `TapCue` draws in 2D rather than reaching into `scripts/world/`.
##
## **It is not a `TapCue`.** That class is "the whole of Wildhaven's *no* vocabulary", two rings
## and nothing else, and borrowing its green "yes" ring for a relocation would teach a colour to
## mean two things. This is its own quieter mark in `UiPalette.MOVE_TRAIL`.
func _draw() -> void:
	if _markers.is_empty():
		return
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	for marker: Dictionary in _markers:
		var progress: float = clampf(
			(marker["age"] as float) / MARKER_SECONDS, 0.0, 1.0
		)
		var from_world: Vector3 = marker["from"]
		var to_world: Vector3 = marker["to"]
		if camera.is_position_behind(from_world) or camera.is_position_behind(to_world):
			continue
		var from_screen: Vector2 = camera.unproject_position(from_world)
		var to_screen: Vector2 = camera.unproject_position(to_world)
		var colour := Color(UiPalette.MOVE_TRAIL, UiPalette.MOVE_TRAIL.a * (1.0 - progress))

		if from_screen.distance_to(to_screen) < 1.0:
			# A DEPARTURE has no destination on screen, so the mark is a single ring opening
			# outward — "off they go", not a cross and not a puff of dust.
			var radius: float = lerpf(MARKER_RADIUS, MARKER_RADIUS_END, progress)
			draw_arc(from_screen, radius, 0.0, TAU, 32, colour, MARKER_WIDTH, true)
			continue

		draw_arc(from_screen, MARKER_RADIUS, 0.0, TAU, 32, colour, MARKER_WIDTH, true)
		draw_arc(to_screen, MARKER_RADIUS, 0.0, TAU, 32, colour, MARKER_WIDTH, true)
		_draw_dashed(from_screen, to_screen, colour)


func _draw_dashed(from_screen: Vector2, to_screen: Vector2, colour: Color) -> void:
	var span: Vector2 = to_screen - from_screen
	var length: float = span.length()
	if length <= MARKER_RADIUS * 2.0:
		return
	var step: Vector2 = span / length * MARKER_DASH
	var travelled: float = MARKER_RADIUS
	var index: int = 0
	while travelled < length - MARKER_RADIUS:
		if index % 2 == 0:
			var a: Vector2 = from_screen + step * (travelled / MARKER_DASH)
			var b_travel: float = minf(travelled + MARKER_DASH, length - MARKER_RADIUS)
			var b: Vector2 = from_screen + step * (b_travel / MARKER_DASH)
			draw_line(a, b, colour, MARKER_WIDTH * 0.6, true)
		travelled += MARKER_DASH
		index += 1
