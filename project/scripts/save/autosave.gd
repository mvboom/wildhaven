class_name Autosave
extends Node
## "NO SAVE BUTTON, EVER" (Pillar 1), made mechanical. Tier 1 row 1.
##
## gdd.md -> Saves: "Autosave is invisible (~1-2 min, plus the two events the completion test
## hangs on — a move-in and a mist reveal completing — each written under the modal or
## animation that opens at that instant, so the write is unseen — plus exiting to menu; no save
## button, no prompts)."
##
## THE VOCABULARY IS A CONSTANT, and that is the whole design of this file. Row 13 (Mist) is
## unbuilt, so `mist_reveal` has no caller yet; making the reasons a list means
## `test_autosave_triggers.gd` can iterate it and prove every one of them writes, so row 13
## adds a single call site and needs no new test. A fifth reason would be a deliberate
## departure from gdd.md's four, and the suite pins the count so it cannot happen quietly.
##
## DELTA-DRIVEN, NOT WALL-CLOCK — the same shape as `RemovalLedger` and `SettlementWindow`, so
## a headless run can drive ninety seconds in one call and `Engine.time_scale` means what it
## says. `Time.get_ticks_msec()` would be neither.
##
## THE ZERO (gdd.md -> Performance). Saving touches no habitat state and enqueues no
## evaluation; `test_autosave_triggers.gd` measures `evaluations_run` across twenty writes and
## requires it not to move.

signal saved(reason: String, path: String)

## gdd.md -> Saves, exactly. `mist_reveal` has NO CALLER until row 13 lands; that is recorded
## in tier1-status.md row 1's `human_gate` rather than hidden here.
const REASONS: Array[String] = ["interval", "move_in", "mist_reveal", "exit_to_menu"]

## PROPOSED (2026-08-01) — spec.md -> Pacing Constants gives "Autosave interval | ~1-2 min |
## implementation detail". 90 s is that band's midpoint. The human owns this number.
const INTERVAL_SECONDS: float = 90.0

var _world: WorldRoot = null
var _elapsed: float = 0.0
var _wrote_once: bool = false


func attach(world: WorldRoot) -> void:
	_world = world
	# THE INTERVAL FIRES AT ATTACH. A brand-new world has to exist on disk before its first
	# ninety seconds are up, or a kid who quits after thirty seconds finds nothing in Load —
	# and doing it this way keeps the vocabulary at gdd.md's four rather than inventing a
	# "new_world" reason for what is really just the first interval.
	request("interval")
	# A move-in is one of the two events the completion test hangs on. Connected here rather
	# than in `WorldRoot` so every trigger this class serves is visible in this file.
	if not _world.resident_arrived.is_connected(_on_resident_arrived):
		_world.resident_arrived.connect(_on_resident_arrived)


func _on_resident_arrived(_species_id: String, _world_position: Vector3) -> void:
	# The fact card opens on this same signal, so the write lands underneath it — which is what
	# gdd.md means by the write being unseen.
	request("move_in")


## Writes the world. Returns false when it declined, which is not an error: an unknown reason,
## no world, or a world with no file of its own (a scene opened directly in the editor, or a
## test) all decline rather than inventing a filename.
func request(reason: String) -> bool:
	if not REASONS.has(reason):
		push_error("Autosave: unknown reason `%s`." % reason)
		return false
	if _world == null or _world.save_path.is_empty():
		return false

	var data: Dictionary = WorldSnapshot.capture(
		_world, _world.world_name, _world.preset_id, _world.world_seed
	)
	var err: Error = SaveStore.write(_world.save_path, data)
	if err != OK:
		# Play continues. The next trigger retries. A kid never sees a dialog about a disk.
		push_error("Autosave: write failed for reason `%s` (error %d)." % [reason, err])
		return false

	# ANY write resets the interval, so a move-in is never chased by a redundant interval write
	# a few seconds later.
	_elapsed = 0.0
	_wrote_once = true
	saved.emit(reason, _world.save_path)
	return true


func wrote_at_least_once() -> bool:
	return _wrote_once


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if _world == null or _world.save_path.is_empty():
		return
	_elapsed += delta
	if _elapsed >= INTERVAL_SECONDS:
		request("interval")
