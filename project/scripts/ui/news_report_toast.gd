class_name NewsReportToast
extends Control
## Tier 1 row 12's face — the first-time nudge and every ambient News Report share this one
## widget, per gdd.md -> Discovery: "One narrator: News Reports and the first-time nudge share
## a single cheerful local-nature-bulletin voice."
##
## spec.md -> Screen Layouts: "News Report — a smaller, dismissable banner/toast (not a
## modal): slides in, never blocks input, auto-dismisses or is tapped away. The world keeps
## simulating." Every clause of that sentence is a decision this file holds to:
##   * NOT A MODAL — the root's `mouse_filter` is `IGNORE`, so only the banner panel itself
##     ever takes a click; everything else on screen keeps working while a toast is up.
##   * AUTO-DISMISSES — a plain clock in `_process()`, no Timer node, matching this row's own
##     `NewsReportScheduler` idiom of being drivable with a hand-picked `delta`.
##   * OR IS TAPPED AWAY — a tap anywhere on the banner itself dismisses it early.
##   * THE WORLD KEEPS SIMULATING — nothing here touches the tree's pause state, same as
##     `FactCard` and `DisplacementNotice`.
##
## NO READ-ALOUD BUTTON. spec.md is explicit: "The Read-Aloud button (🔊) is present on every
## fact card and on the displacement warning ... wider coverage (News Reports, Field Guide) is
## deferred (future.md)." Adding one here would be depth arriving early.
##
## ONE TOAST AT A TIME, FIFO. A queued line waits for the one on screen to finish rather than
## interrupting it — nothing in this row's cadence (a nudge, then one report every 90-150 s)
## should ever produce two at once, but the queue costs nothing and keeps the guarantee
## explicit instead of assumed.
##
## COPY IS NOT THIS FILE'S. `show_text()` renders whatever string it is handed — the nudge's
## `[COPY]`-marked placeholder or a species' own `news_reports` line — and phrases nothing.

signal shown(text: String)
signal dismissed()

## PROPOSED — human owns this. How long one line holds before auto-dismissing, in seconds.
## Sized the same way `DisplacementNotice.MOMENT_SECONDS` (4.5 s) was, then given headroom: a
## News Report line runs longer than a consequence line (the Discovery/hint lines in
## `docs/content/*-news-report-pool.md` run to two clauses), for a fluent 8-year-old reading it
## once while still glancing back at the world.
const DISPLAY_SECONDS: float = 7.0

var _queue: Array[String] = []
var _clock: float = 0.0

@onready var _banner: PanelContainer = %Banner
@onready var _label: Label = %BannerLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_stylebox_override(
		"panel", UiPalette.panel_style(UiPalette.CREAM, UiPalette.CORNER_RADIUS_SMALL, 18)
	)
	_label.add_theme_font_size_override("font_size", UiPalette.FONT_BANNER)
	_label.add_theme_color_override("font_color", UiPalette.BARK)
	_banner.gui_input.connect(_on_banner_input)
	_banner.visible = false
	set_process(false)


## Queues (or shows immediately if nothing is up) one line. Returns false for blank text —
## a species with an empty pool, or a caller passing "" on purpose, produces no toast rather
## than an empty one.
func show_text(text: String) -> bool:
	if text.strip_edges().is_empty():
		return false
	_queue.append(text)
	_pump()
	return true


func dismiss() -> void:
	if not _banner.visible:
		return
	_banner.visible = false
	_clock = 0.0
	dismissed.emit()
	_pump()


func is_showing() -> bool:
	return _banner.visible


func current_text() -> String:
	return "" if not _banner.visible else _label.text


func queued_count() -> int:
	return _queue.size()


func _pump() -> void:
	if _banner.visible or _queue.is_empty():
		set_process(_banner.visible)
		return
	_label.text = _queue.pop_front()
	_banner.visible = true
	_clock = 0.0
	set_process(true)
	shown.emit(_label.text)


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= DISPLAY_SECONDS:
		dismiss()


func _on_banner_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		dismiss()
		accept_event()
