class_name GameplaySettings
extends RefCounted
## App-level player preferences that outlive any one world — the Gameplay Hints toggle
## (Tier 1 row 12's pillar invariant) and, as of Tier 1 row 15, Master Volume.
##
## STATIC VARS, NOT AN AUTOLOAD — `GameSession`'s header already makes this project's case for
## the idiom: no `project.godot` change, no global node a headless test has to route around.
##
## PERSISTED SEPARATELY FROM A WORLD SAVE, DELIBERATELY. Both preferences are about the
## PLAYER, not about a world — gdd.md -> GUI & screens: "Settings is one shared screen
## reachable from title and in-game", i.e. the same value everywhere, not one per save.
## `project/scripts/save/` (Tier 1 row 1's directory) is untouched by this file for exactly
## that reason; a `user://settings.cfg` ConfigFile is its own small, separate concern.
##
## HINTS DEFAULT IS ON. gdd.md's First 60 Seconds hangs its second beat on the first-time
## nudge firing unprompted ("every brand-new save shows one dismissable popup") — a toggle
## that defaulted off would silently cancel that beat for every player who never finds
## Settings.
##
## MASTER VOLUME APPLIES TO `AudioServer`'S "Master" BUS ON LOAD, NOT ONLY WHEN THE SETTINGS
## TAB HAPPENS TO BE OPENED. `_static_init()` (Godot 4.3+) runs once when this script is
## first loaded — i.e. at the earliest point anything in this game could reference
## `GameplaySettings` at all — so a saved volume takes effect even if the player never opens
## Settings this session. No autoload, no scene wiring: the class itself guarantees this
## the moment it exists, matching this file's own "no global node" idiom above.
##
## DEFAULT VOLUME (`DEFAULT_MASTER_VOLUME`) IS A PROPOSED VALUE, NOT A FINAL ONE — flagged
## under Proposals; the human decides tuning values per this project's ground rule.

const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION: String = "gameplay"
const KEY_HINTS_ENABLED: String = "hints_enabled"
const KEY_MASTER_VOLUME: String = "master_volume"
const KEY_SPEAKING_ENABLED: String = "speaking_enabled"

## The name Godot gives bus 0 in every project by default — never renamed here, so no
## `default_bus_layout.tres` edit was needed to give Master Volume something real to
## control.
const MASTER_BUS_NAME: String = "Master"

## PROPOSED — human's call. 0.0-1.0 linear; 0.8 is "audible but not full blast" as a
## starting default, matched loosely to the -6 dB-ish headroom convention many games ship
## with. Untested against any actual mixed audio in this build (there is none yet — Tier 1
## row 15 wires the control and the bus; no sound content exists to tune this against).
const DEFAULT_MASTER_VOLUME: float = 0.8

## Below this linear volume, the bus is muted outright rather than driven toward -inf dB —
## `linear_to_db(0.0)` is `-inf`, which `AudioServer.set_bus_volume_db()` accepts but which
## reads as a wasted edge case next to the explicit mute flag `AudioServer` already offers.
const SILENCE_THRESHOLD: float = 0.001

static var _hints_enabled: bool = true
static var _master_volume: float = DEFAULT_MASTER_VOLUME
static var _speaking_enabled: bool = true
static var _loaded: bool = false


## Godot 4.3+ special static method: runs once, automatically, the first time this script
## is loaded — before any caller could have raced it. Guarantees the persisted (or default)
## Master Volume reaches the audio bus at the earliest possible moment, without depending on
## any particular scene having run its own `_ready()` first.
static func _static_init() -> void:
	_ensure_loaded()


static func hints_enabled() -> bool:
	_ensure_loaded()
	return _hints_enabled


static func set_hints_enabled(enabled: bool) -> void:
	_ensure_loaded()
	_hints_enabled = enabled
	_save()


## Linear 0.0-1.0. Read by the Settings tab's slider to paint its starting position and by
## nothing else today — there is no other audio content in this build yet to react to it.
static func master_volume() -> float:
	_ensure_loaded()
	return _master_volume


static func set_master_volume(volume: float) -> void:
	_ensure_loaded()
	_master_volume = clampf(volume, 0.0, 1.0)
	_apply_master_volume()
	_save()


## Whether Read-Aloud speaks at all — the ONE shared toggle `FactCard`'s own 🔊 button and the
## title screen's checkbox both read and write, so turning it off from either place is off
## everywhere until turned back on (never a per-card preference).
static func speaking_enabled() -> bool:
	_ensure_loaded()
	return _speaking_enabled


static func set_speaking_enabled(enabled: bool) -> void:
	_ensure_loaded()
	_speaking_enabled = enabled
	_save()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	# A missing or corrupt file is silent and keeps the defaults — a preferences file is
	# never load-bearing enough to be worth a warning a six-year-old would never see anyway.
	if config.load(SETTINGS_PATH) == OK:
		_hints_enabled = bool(config.get_value(SECTION, KEY_HINTS_ENABLED, true))
		_master_volume = float(config.get_value(SECTION, KEY_MASTER_VOLUME, DEFAULT_MASTER_VOLUME))
		_speaking_enabled = bool(config.get_value(SECTION, KEY_SPEAKING_ENABLED, true))
	_apply_master_volume()


## Pushes `_master_volume` onto the real `AudioServer` "Master" bus. Guarded on the bus
## existing at all — a headless test harness's `SceneTree` still has `AudioServer` available
## (it is a singleton, not scene-dependent), but this stays defensive rather than assume.
static func _apply_master_volume() -> void:
	var bus_index := AudioServer.get_bus_index(MASTER_BUS_NAME)
	if bus_index == -1:
		return
	var silent: bool = _master_volume < SILENCE_THRESHOLD
	AudioServer.set_bus_mute(bus_index, silent)
	if not silent:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(_master_volume))


static func _save() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SECTION, KEY_HINTS_ENABLED, _hints_enabled)
	config.set_value(SECTION, KEY_MASTER_VOLUME, _master_volume)
	config.set_value(SECTION, KEY_SPEAKING_ENABLED, _speaking_enabled)
	config.save(SETTINGS_PATH)


## Test-only reset, so one suite's toggle/volume state cannot leak into the next via the
## static vars OR the file on disk. Never called by the running game.
static func reset_for_test() -> void:
	_loaded = true
	_hints_enabled = true
	_master_volume = DEFAULT_MASTER_VOLUME
	_speaking_enabled = true
	_apply_master_volume()
	var config := ConfigFile.new()
	config.set_value(SECTION, KEY_HINTS_ENABLED, true)
	config.set_value(SECTION, KEY_MASTER_VOLUME, DEFAULT_MASTER_VOLUME)
	config.set_value(SECTION, KEY_SPEAKING_ENABLED, true)
	config.save(SETTINGS_PATH)
