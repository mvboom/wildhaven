class_name TapCue
extends Control
## The soft cue — the whole of Wildhaven's "no" vocabulary.
##
## gdd.md -> Build Mode / buildings.md: an ineligible tile "simply does not accept the tap —
## **a soft cue, never an error**" (Pillar 1: no fail states, no error states, no penalties).
## `WorldRoot.paint_tile()` / `place_building()` already refuse silently and change nothing;
## what is left for the UI is to prove the tap was *received*, so the player learns "not
## here" instead of "the game is broken".
##
## The vocabulary is two rings and nothing else:
##   ACCEPTED — a leaf-green ring that expands and fades. A yes.
##   SOFT     — a smaller, warmer, quieter ring that fades without expanding. **Not red, not
##              an X, not a shake, no sound, no text.** It says "received, not here."
##
## Drawn in 2D at the tap position rather than in the world, deliberately: it needs no
## reach into `scripts/world/`, it works identically on a tile, on an animal and on empty
## space, and it costs nothing when idle — `_process` disables itself the moment the last
## cue expires.

## DECIDED 2026-08-02 (playtest gate). Seconds.
const ACCEPT_DURATION: float = 0.32
const SOFT_DURATION: float = 0.40

## DECIDED 2026-08-02 (playtest gate). Ring radii in pixels: an accepted tap grows from START to END;
## a soft cue holds at SOFT_RADIUS and only fades.
const ACCEPT_RADIUS_START: float = 14.0
const ACCEPT_RADIUS_END: float = 46.0
const SOFT_RADIUS: float = 22.0
const RING_WIDTH: float = 5.0

enum Kind { ACCEPTED, SOFT }

var _cues: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func accepted(screen_position: Vector2) -> void:
	_push(screen_position, Kind.ACCEPTED)


func soft(screen_position: Vector2) -> void:
	_push(screen_position, Kind.SOFT)


func active_cues() -> int:
	return _cues.size()


func _push(screen_position: Vector2, kind: Kind) -> void:
	_cues.append({"position": screen_position, "kind": kind, "age": 0.0})
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	var alive: Array[Dictionary] = []
	for cue: Dictionary in _cues:
		cue["age"] = (cue["age"] as float) + delta
		if (cue["age"] as float) < _duration(cue["kind"] as Kind):
			alive.append(cue)
	_cues = alive
	if _cues.is_empty():
		set_process(false)
	queue_redraw()


func _duration(kind: Kind) -> float:
	return ACCEPT_DURATION if kind == Kind.ACCEPTED else SOFT_DURATION


func _draw() -> void:
	for cue: Dictionary in _cues:
		var kind: Kind = cue["kind"] as Kind
		var progress: float = clampf((cue["age"] as float) / _duration(kind), 0.0, 1.0)
		var base: Color = UiPalette.CUE_ACCEPT if kind == Kind.ACCEPTED else UiPalette.CUE_SOFT
		var radius: float = SOFT_RADIUS
		if kind == Kind.ACCEPTED:
			radius = lerpf(ACCEPT_RADIUS_START, ACCEPT_RADIUS_END, progress)
		var colour := Color(base, base.a * (1.0 - progress))
		draw_arc(cue["position"] as Vector2, radius, 0.0, TAU, 32, colour, RING_WIDTH, true)
