class_name RemovalLedger
extends Node
## REMOVAL / UNDO & REFUND — Tier 1 row 3's own thin form, Open Question **#16**, and a stated
## thin-form obligation that had never been built. gdd.md -> Player Interface & Controls, in
## full because every clause is a rule here:
##
##   "**Removal / undo & refund policy** (uniform across Terraform reverts and Build
##    removals). **Grace window** (~10–15 s after placement): removal refunds **100%** —
##    accidental taps cost nothing. After the grace window, removal refunds a flat recycle
##    percentage (placeholder ~50%, tunable) — 'recycling,' not a free take-back. Refunds are
##    always in the resource originally spent; free natural terrain refunds nothing."
##
## WHAT THIS CLASS IS: a book of **receipts**. Every successful edit that could be undone
## leaves one — what was there before, what it cost, and when. `WorldRoot.remove_at()` reads a
## receipt, puts the world back, and hands the refund to `WoodLedger`. Nothing here touches the
## grid or the Wood balance itself.
##
## "FREE NATURAL TERRAIN REFUNDS NOTHING" IS NOT A SPECIAL CASE. A grass tile's receipt records
## a cost of 0, and 0 refunds 0 through the same arithmetic as everything else. There is no
## `if terrain_is_free` anywhere in this file, which is what stops the rule rotting the first
## time a price changes.
##
## THE 100% WINDOW IS **THE SAME WINDOW** AS THE SETTLEMENT RULE'S, because spec.md -> Pacing
## Constants gives them a single table row ("Grace window / settlement ... ~10–15 s"). This
## class reads `SettlementWindow.GRACE_WINDOW_SECONDS` rather than declaring its own, so the
## instant a player stops getting all their Wood back is exactly the instant their edit stops
## being reversible. The design binds them; if the human wants two numbers, this is the one
## line to split.
##
## TIME IS DELTA-DRIVEN, NOT WALL-CLOCK. `tick(delta)` advances an internal clock, the same
## shape as every other tickable in the build, so a headless run can drive a grace window past
## its end in one call and `Engine.time_scale` means what it says. `Time.get_ticks_msec()`
## would be neither.
##
## ONE RECEIPT PER TILE — the last edit, not a history. An accidental tap is undone; a
## ten-edit undo stack is not the floor and is not claimed to be. Deeper undo is a depth
## purchase, and this is the shape it would grow from (a stack per key instead of a value).
##
## NOT BUILT HERE, deliberately: what removal *means* for residents. A removal that drops a
## neighbourhood's capacity below its population is `GentleDisplacement`'s (row 10) — removal
## is one of the three edit modes its warning is agnostic to, and `WorldRoot` routes it there
## exactly like a paint or a build.

## DECIDED 2026-08-01 (-> D-29). gdd.md's "placeholder ~50%, tunable" (Open Question #16),
## ratified at 0.5.
##
## Applied as `floor(cost * RECYCLE_FRACTION)`, floored rather than rounded: a refund that
## rounded up would let a player farm Wood by placing and removing an odd-cost building, which
## turns a gentle take-back into an exploit and Wood into a score.
const RECYCLE_FRACTION: float = 0.5


## Monotonic seconds since this ledger was created. Advanced by `tick()`.
var _clock: float = 0.0

## Vector2i tile -> { "previous_terrain_id": String, "spent": int, "issued_at": float }
var _terrain: Dictionary = {}

## Vector2i footprint origin -> { "placeable_id": String, "spent": int, "issued_at": float }
var _buildings: Dictionary = {}


func _process(delta: float) -> void:
	tick(delta)


## Advances the clock. **This is one float addition and it is not simulation work** — it runs
## on an idle world and cannot move `HabitatSimulation.evaluations_run`, mark a neighbourhood
## dirty, or open a settlement window. It is unconditional because a receipt's age has to keep
## meaning something while the player does nothing, which is precisely the case the grace
## window exists for.
func tick(delta: float) -> void:
	_clock += delta


func now() -> float:
	return _clock


# --- Writing receipts --------------------------------------------------------------------

## Records a completed paint. `previous_terrain_id` is what the tile was **before**; `spent` is
## what the player actually paid, which is 0 for every natural terrain.
func record_paint(tile: Vector2i, previous_terrain_id: String, spent: int) -> void:
	_terrain[tile] = {
		"previous_terrain_id": previous_terrain_id,
		"spent": maxi(spent, 0),
		"issued_at": _clock,
	}


## Records a completed placement, keyed by footprint origin.
func record_placement(origin: Vector2i, placeable_id: String, spent: int) -> void:
	_buildings[origin] = {
		"placeable_id": placeable_id,
		"spent": maxi(spent, 0),
		"issued_at": _clock,
	}


## Forgets a tile's paint receipt without refunding — used when the tile's history stops being
## meaningful (a building went up over it, or the revert has just been consumed).
func forget_paint(tile: Vector2i) -> void:
	_terrain.erase(tile)


func forget_placement(origin: Vector2i) -> void:
	_buildings.erase(origin)


func clear() -> void:
	_terrain = {}
	_buildings = {}


# --- Save/load (-> v3, fixes a reported bug: Take Away did nothing on a tile painted before a
# save/load) ---------------------------------------------------------------------------------
#
# RECEIPTS NOW ROUND-TRIP THROUGH A SAVE. `WorldSnapshot`'s original ruling (v1/v2) named
# removal receipts as deliberately NOT saved, grouped with other in-flight state (an open
# settlement gesture, the dirty queue) that either does not matter after a reload or gets
# RE-DERIVED by `apply()`. Receipts are neither: nothing re-derives "what was this tile before
# it was painted", so losing them silently turned every edit from an earlier session into one
# `remove_at()` could never undo again — reported as "Take Away does nothing after a load".
# `previous_terrain_id` (what a removal reverts TO) genuinely has no other source, so it has to
# round-trip; `spent` (what a removal refunds) is the same story one field over.

## `_terrain`/`_buildings`, JSON-native (`Vector2i` keys become `[x, z]` pairs — the same
## convention `WorldSnapshot.capture()` already uses for a building's footprint origin).
## `issued_at` is deliberately NOT included — see `restore()` for why.
func to_save() -> Dictionary:
	var terrain_out: Array[Dictionary] = []
	for tile: Vector2i in _terrain:
		var receipt: Dictionary = _terrain[tile] as Dictionary
		terrain_out.append({
			"tile": [tile.x, tile.y],
			"previous_terrain_id": receipt["previous_terrain_id"] as String,
			"spent": int(receipt["spent"]),
		})
	var buildings_out: Array[Dictionary] = []
	for origin: Vector2i in _buildings:
		var receipt: Dictionary = _buildings[origin] as Dictionary
		buildings_out.append({
			"origin": [origin.x, origin.y],
			"placeable_id": receipt["placeable_id"] as String,
			"spent": int(receipt["spent"]),
		})
	return {"terrain": terrain_out, "buildings": buildings_out}


## Rebuilds every receipt from `to_save()`'s output, REPLACING whatever is here.
##
## EVERY RESTORED RECEIPT READS AS ALREADY PAST THE GRACE WINDOW — `issued_at` is set to a
## value `within_grace()` always reads as expired, rather than round-tripping the real one.
## A save/load cycle takes real-world time that all but guarantees the original ~10-15s window
## already passed by the time anyone could act on a reloaded world, so the flat recycle rate is
## the honest answer, not a degraded one; and the alternative (persisting a wall-clock moment to
## compare against) is exactly the kind of in-flight bookkeeping `WorldSnapshot`'s header says
## this schema does not chase (fractional Wood, the dirty queue, ...).
##
## **SAVES ARE HAND-EDITABLE BY DESIGN** (gdd.md -> Saves), so every field is untrusted — same
## posture as `ArrivalQueue.restore()`, which this mirrors.
func restore(data: Dictionary) -> void:
	_terrain = {}
	_buildings = {}
	var stale_issued_at: float = _clock - SettlementWindow.GRACE_WINDOW_SECONDS - 1.0

	for raw: Variant in (data.get("terrain", []) as Array):
		if typeof(raw) != TYPE_DICTIONARY:
			push_warning("RemovalLedger: a saved terrain receipt is not an object; skipped.")
			continue
		var entry: Dictionary = raw as Dictionary
		var tile: Variant = _xz_from(entry.get("tile", null))
		if tile == null:
			push_warning("RemovalLedger: a saved terrain receipt's `tile` is not [x, z]; skipped.")
			continue
		var previous_id: Variant = entry.get("previous_terrain_id", null)
		if typeof(previous_id) != TYPE_STRING:
			push_warning(
				"RemovalLedger: a saved terrain receipt has no `previous_terrain_id`; skipped."
			)
			continue
		_terrain[tile as Vector2i] = {
			"previous_terrain_id": previous_id as String,
			"spent": _spent_from(entry),
			"issued_at": stale_issued_at,
		}

	for raw: Variant in (data.get("buildings", []) as Array):
		if typeof(raw) != TYPE_DICTIONARY:
			push_warning("RemovalLedger: a saved building receipt is not an object; skipped.")
			continue
		var entry: Dictionary = raw as Dictionary
		var origin: Variant = _xz_from(entry.get("origin", null))
		if origin == null:
			push_warning("RemovalLedger: a saved building receipt's `origin` is not [x, z]; skipped.")
			continue
		var placeable_id: Variant = entry.get("placeable_id", null)
		if typeof(placeable_id) != TYPE_STRING:
			push_warning("RemovalLedger: a saved building receipt has no `placeable_id`; skipped.")
			continue
		_buildings[origin as Vector2i] = {
			"placeable_id": placeable_id as String,
			"spent": _spent_from(entry),
			"issued_at": stale_issued_at,
		}


## `[x, z]` (both numbers) -> `Vector2i`, or `null` — the one shape check both loops above need.
static func _xz_from(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		return null
	var pair: Array = value as Array
	if pair.size() < 2 or not WorldSnapshot.is_number(pair[0]) or not WorldSnapshot.is_number(pair[1]):
		return null
	return Vector2i(int(pair[0]), int(pair[1]))


static func _spent_from(entry: Dictionary) -> int:
	var raw: Variant = entry.get("spent", 0)
	return maxi(int(raw) if WorldSnapshot.is_number(raw) else 0, 0)


# --- Reading receipts --------------------------------------------------------------------

func has_paint_receipt(tile: Vector2i) -> bool:
	return _terrain.has(tile)


func has_placement_receipt(origin: Vector2i) -> bool:
	return _buildings.has(origin)


## The paint receipt for a tile, or `{}`. Read-only; `WorldRoot` consumes it with
## `forget_paint()` only once the world has actually been put back.
func paint_receipt(tile: Vector2i) -> Dictionary:
	return _terrain.get(tile, {}) as Dictionary


func placement_receipt(origin: Vector2i) -> Dictionary:
	return _buildings.get(origin, {}) as Dictionary


## THE POLICY, in one function so there is exactly one place it can be wrong.
##
##   * inside the grace window -> the whole cost back ("accidental taps cost nothing");
##   * after it                -> `floor(cost * RECYCLE_FRACTION)` ("recycling", not a free
##                                take-back);
##   * a cost of 0             -> 0, which is "free natural terrain refunds nothing".
func refund_for(receipt: Dictionary) -> int:
	if receipt.is_empty():
		return 0
	var spent: int = int(receipt.get("spent", 0))
	if spent <= 0:
		return 0
	if within_grace(receipt):
		return spent
	return int(floor(float(spent) * RECYCLE_FRACTION))


## True while the edit is still inside the grace window — which is also, by construction, while
## it is still reversible (see the class note).
func within_grace(receipt: Dictionary) -> bool:
	if receipt.is_empty():
		return false
	return (_clock - float(receipt.get("issued_at", 0.0))) <= SettlementWindow.GRACE_WINDOW_SECONDS
