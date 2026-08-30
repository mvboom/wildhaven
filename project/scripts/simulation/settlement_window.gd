class_name SettlementWindow
extends RefCounted
## THE SETTLEMENT RULE — gdd.md -> Player Interface & Controls, quoted because every clause
## of it is load-bearing:
##
##   "Capacity itself is re-evaluated **immediately, on every edit** ... What the grace window
##    gates is not the arithmetic but the **irreversible half of the consequences**: the
##    displacement warning's final trigger, and any relocation or departure. **Every further
##    edit inside an affected neighborhood restarts that neighborhood's window** ... Restarts
##    are deliberately uncapped, because the only thing a restart defers is a loss ...
##    Reverting within the window means the displacement never happened."
##
## THIS CLASS HOLDS ONLY THE TIMER. It knows nothing about capacity, species or residents:
## `GentleDisplacement` asks it "which gestures just settled?" and does all the arithmetic
## itself, at settlement, by re-reading the world. That split is what makes the revert rule
## literally true rather than bookkeeping — **nothing about the pre-edit world is recorded
## anywhere**, so a neighbourhood the player put back reads as unchanged when it settles and
## there is simply nothing to warn about. It is also why the rule covers free terrain, where
## there is no refund transaction to hang an undo on.
##
## WHAT A GESTURE IS. A gesture is a set of neighbourhoods being edited together under one
## timer. An edit joins an open gesture when it touches any neighbourhood that gesture already
## covers (merging gestures where it touches several), and restarts it; otherwise it opens a
## new one. That is "every further edit inside an affected neighbourhood restarts that
## neighbourhood's window", and it is what makes a six-year-old's burst of taps warn **once**,
## as one gesture, instead of once per tap (#17).
##
## THE ZERO (gdd.md -> Performance; `test_event_driven_simulation.gd`). A settlement timer must
## not create idle work. Two things guarantee it:
##   * `advance()` returns on its first line when no gesture is open, and
##   * a gesture is only ever opened for an edit that touches a neighbourhood **someone
##     actually lives in** — `GentleDisplacement` passes the keys, and an edit on empty land
##     passes none, so it opens nothing at all. A world with no residents never opens a window
##     in its life.
##
## Restarts are uncapped on purpose. A player who keeps tapping keeps deferring a loss, and
## deferring a loss is never the wrong answer (Pillar 1).

## DECIDED 2026-08-01 (-> D-29). spec.md -> Pacing Constants' "~10-15 s" band (Open
## Question #16), ratified at 12.0, the band's midpoint.
##
## **ONE NUMBER, TWO USES, BECAUSE spec.md GIVES THEM ONE TABLE ROW.** This same window is
## the 100%-refund grace period in gdd.md's Removal / undo & refund policy — `RemovalLedger`
## reads this constant rather than declaring a second one, so the moment a player stops
## getting a full refund is exactly the moment their edit becomes irreversible. Splitting
## them into two numbers is a human call, and a defensible one; they are bound here because
## the design document binds them.
const GRACE_WINDOW_SECONDS: float = 12.0


## Open gestures. Each: {
##   "id": int, "remaining": float,
##   "tiles": Dictionary,  # Vector2i -> true, the edited tiles
##   "keys": Dictionary,   # String   -> true, the neighbourhoods this gesture covers
## }
var _gestures: Array[Dictionary] = []
var _next_id: int = 1


## True when nothing is pending. **An idle world must satisfy this**, and a world with no
## residents satisfies it permanently.
func is_idle() -> bool:
	return _gestures.is_empty()


func pending_gestures() -> int:
	return _gestures.size()


## Records one player edit at `tile` affecting the neighbourhoods named by `keys`, and
## (re)starts their window. Returns the gesture id, or **-1 when `keys` is empty** — an edit
## that can displace nobody opens no window and costs nothing forever after.
##
## Merging is transitive by construction: every open gesture sharing a key with this edit is
## folded into one, which keeps the invariant that a neighbourhood belongs to at most one
## gesture and therefore appears in at most one warning.
func touch(tile: Vector2i, keys: Array[String]) -> int:
	if keys.is_empty():
		return -1

	var merged: Dictionary = {"id": 0, "remaining": 0.0, "tiles": {}, "keys": {}}
	var kept: Array[Dictionary] = []
	var found: bool = false

	for gesture: Dictionary in _gestures:
		if not _shares_key(gesture, keys):
			kept.append(gesture)
			continue
		# Keep the OLDEST id across a merge, so the id the UI saw on the first warning-worthy
		# tap of a burst is the id it still sees when the burst finally settles.
		if not found or int(gesture["id"]) < int(merged["id"]):
			merged["id"] = gesture["id"]
		found = true
		merged["tiles"].merge(gesture["tiles"])
		merged["keys"].merge(gesture["keys"])

	if not found:
		merged["id"] = _next_id
		_next_id += 1

	merged["tiles"][tile] = true
	for key: String in keys:
		merged["keys"][key] = true
	# THE RESTART. Uncapped, and deliberately so.
	merged["remaining"] = GRACE_WINDOW_SECONDS

	kept.append(merged)
	_gestures = kept
	return int(merged["id"])


## Seconds left on the gesture covering `key`, or -1.0 when none is open. For a preview or a
## countdown affordance; nothing in the simulation reads it.
func remaining_for(key: String) -> float:
	for gesture: Dictionary in _gestures:
		if (gesture["keys"] as Dictionary).has(key):
			return float(gesture["remaining"])
	return -1.0


## Advances every open gesture and REMOVES the ones that settled, returning them. Removal
## happens here so a settled gesture cannot be resolved twice.
func advance(delta: float) -> Array[Dictionary]:
	var settled: Array[Dictionary] = []
	if _gestures.is_empty():
		return settled  # THE ZERO: no pending gesture, no work.
	var still_open: Array[Dictionary] = []
	for gesture: Dictionary in _gestures:
		gesture["remaining"] = float(gesture["remaining"]) - delta
		if float(gesture["remaining"]) <= 0.0:
			settled.append(gesture)
		else:
			still_open.append(gesture)
	_gestures = still_open
	return settled


## The edited tiles of a settled gesture, in insertion order.
static func tiles_of(gesture: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for tile: Variant in (gesture.get("tiles", {}) as Dictionary).keys():
		out.append(tile as Vector2i)
	return out


func clear() -> void:
	_gestures = []


func _shares_key(gesture: Dictionary, keys: Array[String]) -> bool:
	var owned: Dictionary = gesture["keys"]
	for key: String in keys:
		if owned.has(key):
			return true
	return false
