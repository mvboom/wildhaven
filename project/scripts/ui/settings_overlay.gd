class_name SettingsOverlay
extends Control
## Tier 1 row 12's minimal slice of the shared Settings screen.
##
## SETTINGS/CREDITS ARE NO LONGER REACHABLE IN-GAME (2026-08-25 human decision, superseding the
## gdd.md line this docstring used to quote about "reachable from title and in-game"). This
## Control is now hosted inside `scenes/menu/SettingsScreen.tscn`, reached only from the Title
## screen's Settings button — not `MenuWindow`, which used to host it as a tab. A player
## changes Hints/Master Volume between sessions rather than live mid-session; the values still
## round-trip through `GameplaySettings` exactly as before.
##
## THIS IS "THE EXISTING OVERLAY" tier1-status.md row 15's own thin_form already refers to:
## "Master volume + Hints toggle on the existing overlay." It is built now, by row 12, because
## the Hints toggle is a pillar invariant that ships whole with THIS row (spec.md -> "Not depth
## axes": "the Gameplay Hints toggle"), not something row 12 can leave for a later dispatch to
## invent from scratch. Row 15 EXTENDS this file with Master Volume below (additive, not a
## rewrite, matching `field_guide.gd`'s header's own precedent for its future hinted-at
## column) — the Credits link lives as its own screen instead (`CreditsScreen`, hosted in
## `scenes/menu/CreditsScreen.tscn`), a sibling screen rather than a link nested inside this
## one.
##
## NO LONGER PAUSES OR NON-PAUSES ANYTHING — it has no world to sit in front of any more. The
## scrim and "tap outside dismisses" behaviour used to live here; as of Task 5 (Minecraft-style
## inventory window) it moved to `MenuWindow`, and now this Control is plain page content
## inside `scenes/menu/SettingsScreen.tscn`'s own chrome instead.
##
## THE TOGGLE'S OWN STATE LIVES IN `GameplaySettings`, NOT HERE. This Control only ever reads
## it (to paint the checkbox, once, on `_ready()` — there is no more separate "open" moment to
## repaint from) and writes back through `GameplaySettings.set_hints_enabled()` — the same
## "one source of truth, many readers" shape the rest of the UI layer already uses for
## `WorldRoot`'s own state. Painting once at `_ready()` (i.e. app/world start, when this node is
## instanced as part of `MenuWindow`) still reads correctly from a reload, because this checkbox
## is the only writer of the setting this build has; nothing else can go stale against it
## mid-session.
##
## MASTER VOLUME (Tier 1 row 15) FOLLOWS THE SAME SHAPE — `GameplaySettings` owns the value
## and pushes it to the real `AudioServer` "Master" bus; this Control only paints the
## slider's starting position from `GameplaySettings.master_volume()` and writes changes
## back through `GameplaySettings.set_master_volume()`. It replaces the separable
## Ambient/SFX sliders tier1-status.md's row 15 invariant refers to — those never actually
## existed in this build (checked before writing this: no bus layout, no slider, no
## AudioServer reference anywhere in the codebase before this change), so there was nothing
## here to remove; Master Volume is simply the first and only volume control this build has.

signal hints_toggled(enabled: bool)

## [COPY] — content-writer's. The toggle's own on-screen label. Marked and rendering visibly
## as a stub because no approved string exists yet, matching `FieldGuide.EMPTY_STATE_TEXT`'s
## precedent for an unwritten player-facing word (`GameHud.REMOVE_ENTRY_LABEL` used to be the
## same kind of stub; it is human-decided text now, "Erase").
const HINTS_LABEL: String = "[COPY] Gameplay Hints"

## [COPY] — content-writer's. Same stub convention as `HINTS_LABEL` above.
const MASTER_VOLUME_LABEL: String = "[COPY] Master Volume"

## The slider's own scale — 0-100 integer "percent", not raw 0.0-1.0, because a whole
## number reads more plainly to this game's audience (gdd.md's fluent-reader-8-10 target)
## than a fraction would. `GameplaySettings.master_volume()`/`set_master_volume()` still
## trade in linear 0.0-1.0; this Control is the one place that converts between the two.
const VOLUME_SLIDER_MAX: float = 100.0

@onready var _hints_check: CheckButton = %HintsCheck
@onready var _master_volume_slider: HSlider = %MasterVolumeSlider
@onready var _master_volume_label: Label = %MasterVolumeLabel
@onready var _master_volume_value: Label = %MasterVolumeValue


func _ready() -> void:
	_hints_check.text = HINTS_LABEL
	_hints_check.button_pressed = GameplaySettings.hints_enabled()
	_hints_check.toggled.connect(_on_hints_toggled)

	_master_volume_label.text = MASTER_VOLUME_LABEL
	_master_volume_slider.min_value = 0.0
	_master_volume_slider.max_value = VOLUME_SLIDER_MAX
	_master_volume_slider.step = 1.0
	_master_volume_slider.value = roundf(GameplaySettings.master_volume() * VOLUME_SLIDER_MAX)
	_update_master_volume_value_label(_master_volume_slider.value)
	_master_volume_slider.value_changed.connect(_on_master_volume_changed)


func hints_checked() -> bool:
	return _hints_check.button_pressed


## The slider's current reading as the same 0-100 "percent" it displays — what a test reads
## instead of reaching into the slider node directly.
func master_volume_percent() -> int:
	return int(roundf(_master_volume_slider.value))


func _on_hints_toggled(enabled: bool) -> void:
	GameplaySettings.set_hints_enabled(enabled)
	hints_toggled.emit(enabled)


func _on_master_volume_changed(value: float) -> void:
	GameplaySettings.set_master_volume(value / VOLUME_SLIDER_MAX)
	_update_master_volume_value_label(value)


func _update_master_volume_value_label(value: float) -> void:
	if _master_volume_value != null:
		_master_volume_value.text = "%d%%" % int(roundf(value))
