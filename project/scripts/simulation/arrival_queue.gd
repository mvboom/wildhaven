class_name ArrivalQueue
extends RefCounted
## Pending move-ins — gdd.md -> Habitat Suitability: "A qualifying spot enqueues an arrival
## ... on a short randomised delay, **re-checked when it comes due** since the land may have
## changed, so arrivals happen while the player is zoomed elsewhere."
##
## Two rules this class exists to hold:
##
## * **The enqueue happens on the edit itself, never at settlement.** The delay plus the
##   due-time re-check is what absorbs a tap burst, so no amount of excited tapping can
##   defer a move-in past the time-to-first-move-in ceiling.
## * **A pending arrival that de-qualifies before it comes due is silently dropped, never
##   warned.** Nothing had moved in, so there is nothing to explain — the no-unexplained-
##   vanish rule governs residents, not un-arrived animals. `due()` returns the candidates;
##   the caller re-checks and drops without a word.
##
## One pending arrival per (site, species) at a time. A neighbourhood with room for several
## therefore "fills gradually rather than all at once": each landing re-marks the
## neighbourhood dirty, which enqueues the next.

## PLACEHOLDER / GDD baseline — the human owns these (Open Question #28; spec.md -> Pacing
## Constants: "Arrival delay (qualification -> move-in): 20-60 s randomised (thin build may
## stretch to ~90 s)"). They are bounded from above by time-to-first-move-in, which is a
## validation criterion at the step-5 kid playtest, not a timer the player ever sees.
const ARRIVAL_DELAY_MIN_SECONDS: float = 20.0
const ARRIVAL_DELAY_MAX_SECONDS: float = 60.0


## Entries: { "position": Vector2i, "species_id": String, "remaining": float, "count": int }
var _pending: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value


func size() -> int:
	return _pending.size()


func is_empty() -> bool:
	return _pending.is_empty()


func has_pending(position: Vector2i, species_id: String) -> bool:
	var wanted: String = AnimalDefinition.normalize_id(species_id)
	for entry: Dictionary in _pending:
		if entry["position"] == position and entry["species_id"] == wanted:
			return true
	return false


## Enqueues an arrival of `count` individuals at `position`, on a randomised delay. No-op
## when one is already pending for this site and species.
##
## `count` comes from the qualifying tier's `arrival_group_size`, so deer arrive as a small
## group and a lone fox arrives alone. It is re-checked at due time and may land partially
## — see `HabitatSimulation._land_or_drop()`. Clamped to at least 1: a caller passing 0 or
## negative still gets one arrival, not a silently-vanished queue entry.
func enqueue(position: Vector2i, species_id: String, count: int = 1) -> bool:
	if has_pending(position, species_id):
		return false
	_pending.append({
		"position": position,
		"species_id": AnimalDefinition.normalize_id(species_id),
		"remaining": _rng.randf_range(ARRIVAL_DELAY_MIN_SECONDS, ARRIVAL_DELAY_MAX_SECONDS),
		"count": maxi(count, 1),
	})
	return true


## Advances every pending delay and REMOVES the ones that came due, returning them for the
## caller's re-check. Removal happens here so a due arrival cannot be resolved twice.
func advance(delta: float) -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	if _pending.is_empty():
		return ready
	var still_waiting: Array[Dictionary] = []
	for entry: Dictionary in _pending:
		entry["remaining"] = float(entry["remaining"]) - delta
		if float(entry["remaining"]) <= 0.0:
			ready.append(entry)
		else:
			still_waiting.append(entry)
	_pending = still_waiting
	return ready


## Drops every pending arrival for a site and species — used when a home site is removed.
func drop_for(position: Vector2i, species_id: String) -> void:
	var wanted: String = AnimalDefinition.normalize_id(species_id)
	var kept: Array[Dictionary] = []
	for entry: Dictionary in _pending:
		if entry["position"] == position and entry["species_id"] == wanted:
			continue
		kept.append(entry)
	_pending = kept


func clear() -> void:
	_pending = []


# --- Persistence (Tier 1 row 1, human ruling of 2026-08-02) -------------------------------
#
# THE QUEUE IS IN THE SAVE FILE, and it was not always. D-30 ruling 3 said the file holds
# committed state only and the queue re-derives itself on load. It does not: `apply()`'s
# `mark_all_dirty()` reaches `_mark_all_sites_dirty()`, which enqueues only ALREADY-REGISTERED
# home sites — and a habitat that qualifies but has nobody in it yet has no home site at all.
# Measured: capacity 1, sites 0, capture, apply -> 0 residents after 600 simulated seconds, 1
# after any further player edit. A child paints a rabbit meadow, quits inside the 20-60 s
# arrival delay, and the rabbit never comes. So arrivals are persisted; gestures, receipts, the
# dirty queue and fractional Wood are still re-derived.
#
# WHAT KEEPS THE RESTORE FROM DOUBLE-ENQUEUEING IS `enqueue()`'s `has_pending()` NO-OP, and it is
# ORDER-INDEPENDENT. An earlier version of this header presented `apply()`'s "restore before
# `mark_all_dirty()`" as the guarantee; it is not. `mark_all_dirty()` enqueues zero arrivals
# synchronously — it only marks neighbourhoods dirty, and the enqueue happens in a later `tick()`
# drain, by which point `restore()` has run under either ordering. Swapping the two steps was
# measured to leave both suites green. The order in `apply()` stands for readability alone.


## The pending queue as JSON-native data — `[x, z]` arrays, Strings and floats only. No engine
## type may enter the schema (`Vector2i` does not survive `JSON.stringify`; it comes back as a
## String), which `test_world_snapshot.gd` asserts on the whole captured dictionary.
func to_save() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _pending:
		var position: Vector2i = entry["position"] as Vector2i
		out.append({
			"position": [position.x, position.y],
			"species_id": entry["species_id"] as String,
			"remaining": float(entry["remaining"]),
			"count": int(entry.get("count", 1)),
		})
	return out


## Rebuilds the queue from `to_save()` output, REPLACING whatever is pending.
##
## **SAVES ARE HAND-EDITABLE BY DESIGN** (gdd.md -> Saves), so every field here is untrusted:
## a missing key, a `remaining` of `"soon"`, a `position` of `[4]` are all anticipated input,
## not impossibilities. A bare `float()` on a String or Dictionary is not a 0 — it is a runtime
## "Nonexistent 'float' constructor" error that aborts the enclosing function part-way through,
## which is the exact bug class two earlier fixes on this row closed. So each entry is
## TYPE-CHECKED BEFORE ANY CAST through `WorldSnapshot.is_number()`, the same helper the
## `save_version` and `width`/`depth` reads already use, and a malformed entry is dropped with
## a warning rather than taking the rest of the queue down with it.
##
## The one-per-(site, species) invariant is enforced here too: a hand-edited file naming the
## same arrival twice restores as one, exactly as `enqueue()` would have produced.
func restore(entries: Array) -> void:
	_pending = []
	for raw: Variant in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			push_warning("ArrivalQueue: a saved arrival is not an object; skipped.")
			continue
		var entry: Dictionary = raw as Dictionary

		var position_raw: Variant = entry.get("position", null)
		if typeof(position_raw) != TYPE_ARRAY:
			push_warning("ArrivalQueue: a saved arrival has no `position` array; skipped.")
			continue
		var pair: Array = position_raw as Array
		if pair.size() < 2 or not WorldSnapshot.is_number(pair[0]) or not WorldSnapshot.is_number(pair[1]):
			push_warning("ArrivalQueue: a saved arrival's `position` is not [x, z]; skipped.")
			continue

		var species_raw: Variant = entry.get("species_id", null)
		if typeof(species_raw) != TYPE_STRING:
			push_warning("ArrivalQueue: a saved arrival has no `species_id` string; skipped.")
			continue

		var remaining_raw: Variant = entry.get("remaining", null)
		if not WorldSnapshot.is_number(remaining_raw):
			push_warning("ArrivalQueue: a saved arrival's `remaining` is not a number; skipped.")
			continue

		var position := Vector2i(int(pair[0]), int(pair[1]))
		var species_id: String = AnimalDefinition.normalize_id(species_raw as String)
		if has_pending(position, species_id):
			push_warning("ArrivalQueue: a saved arrival is a duplicate of one already restored; skipped.")
			continue

		# A save written before group arrivals has no `count`. Read it as 1, never as 0 — a 0
		# would silently drop the arrival on load, exactly the class of bug this file's header
		# warns against.
		var count: int = int(entry.get("count", 1))
		if count < 1:
			count = 1

		# A saved delay is honoured as saved — clamping it up to the fresh 20-60 s band would
		# silently restart a wait the child had already spent most of.
		_pending.append({
			"position": position,
			"species_id": species_id,
			"remaining": maxf(0.0, float(remaining_raw)),
			"count": count,
		})
