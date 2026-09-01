class_name MenuWindow
extends Control
## The browse shell (design spec section 2's original "one shell instead of three" framing).
## Hosts `FieldGuide`'s content as a tab — structurally still scrim, card, close button,
## tap-outside-dismiss, non-pausing (Pillar 1 — nothing here protects the player from
## anything).
##
## SETTINGS/CREDITS TABS RETIRED. Both moved to their own screens off the Title/Main screen
## (`scenes/menu/SettingsScreen.tscn`, `scenes/menu/CreditsScreen.tscn`), which now host the
## real `SettingsOverlay`/`CreditsScreen` content that used to live here — see those scenes'
## own scripts. Settings/Credits are no longer reachable mid-session; reaching them requires
## leaving to the title screen (`LeaveOverlay`), matching this human decision (2026-08-25).
##
## TERRAIN/BUILDINGS TABS RETIRED (terraform-bar rework). This window used to also host a
## "Terrain"/"Buildings" browse grid the player dragged catalog entries out of, into a 5-slot
## hotbar `GameHud` owned. `GameHud`'s palette row now shows every terrain and building
## permanently — the whole v1 catalog fits in one row — so there is nothing left to browse
## into and nothing left to drag. That whole seam (the two grids, the slot-row mirror, the
## `set_drag_forwarding()` wiring) is gone with it, not merely hidden.

## Final review finding #8 (ported forward): named in place of the magic tab-index literal
## this file used to repeat at every call site, so a future tab reorder fails loudly (wrong
## caption, wrong refresh target) instead of silently breaking.
const FIELD_GUIDE_TAB_INDEX: int = 0

## Final review finding #3: fires whenever this window closes, for ANY reason — the × button,
## a scrim tap, or a direct `close()` call from outside (e.g. a future save/load flow). Exists
## so `CameraRig` can re-capture the pointer when the window goes away by a path other than its
## own Tab toggle; see `CameraRig`'s `menu_window` setter and `_on_menu_window_closed()`.
signal closed()

@onready var _scrim: ColorRect = %Scrim
@onready var _tabs: TabContainer = %Tabs
@onready var _close_button: Button = %CloseButton
@onready var _field_guide: FieldGuide = %FieldGuide

var _world: WorldRoot = null


func _ready() -> void:
	visible = false
	_close_button.text = "×"
	UiPalette.paint_button(_close_button, false)
	_scrim.color = UiPalette.SCRIM
	_scrim.gui_input.connect(_on_scrim_input)
	_close_button.pressed.connect(close)
	_tabs.current_tab = 0
	# The node name "FieldGuide" (required so `%FieldGuide` resolves, both here and for
	# `MenuWindow`'s own test suite and `game_ui.gd`) doubles as the TabContainer's default tab
	# caption unless overridden — set explicitly here so the tab still reads "Field Guide"
	# rather than the bare node name.
	_tabs.set_tab_title(FIELD_GUIDE_TAB_INDEX, "Field Guide")
	_tabs.tab_changed.connect(_on_tab_changed)


## The Field Guide tab's list is a live document (its own header: "grows for as long as play
## continues"), so it is refreshed both on switching to it and on every `open()` —
## `refresh_from()` itself is idempotent and cheap (rebuilds from data already in memory), so
## there is no cost to calling it more often than strictly necessary.
func _on_tab_changed(_tab_index: int) -> void:
	if _tabs.current_tab == FIELD_GUIDE_TAB_INDEX:
		_field_guide.refresh_from(_world)


func open(world: WorldRoot) -> void:
	_world = world
	refresh_from(world)
	_tabs.current_tab = 0
	visible = true
	move_to_front()


## Opens the window with `tab_index` selected. `_on_tab_changed` refreshes the Field Guide
## tab's content, so this needs no refresh call of its own.
##
## ADAPTED FROM THE PLAN (Task 5): the brief's own sketch of this function took no `world`
## argument, but `open()` above has always required one — `MenuWindow` cannot refresh a tab
## against a world it was never handed. Taking `world` here, exactly as `open()` does, keeps
## this a thin wrapper rather than a second, divergent way to bind one.
func open_at_tab(world: WorldRoot, tab_index: int) -> void:
	open(world)
	_tabs.current_tab = tab_index


## Closes the window, if it was open, and emits `closed` — guarded on `visible` so a `close()`
## call against an already-closed window (e.g. `CameraRig`'s own toggle, which calls this
## unconditionally on every capture-side flip) is a no-op rather than a spurious signal.
func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


## Refreshes the hosted Field Guide tab against `world` — called on open and again whenever
## a resident arrives/departs while this window is open (`GameUI._on_resident_arrived()`/
## `_on_resident_departed()`), so "the list grows/shrinks live while open" (`field_guide.gd`'s
## own header) holds even when this window stays on screen across an arrival.
func refresh_from(world: WorldRoot) -> void:
	if _field_guide != null:
		_field_guide.refresh_from(world)


func _on_scrim_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		close()
		accept_event()
