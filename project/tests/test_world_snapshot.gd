extends QATestCase
## THE SAVE SCHEMA, outbound. `capture()` only — `apply()` and the full round trip are
## `test_save_round_trip.gd`.
##
## THE DECISION THIS SUITE PINS (human ruling 3, 2026-08-01, AMENDED 2026-08-02, AMENDED AGAIN
## AT v3): the save holds committed state **plus the pending arrival queue and removal
## receipts**. Open settlement gestures, the dirty queue and Wood's fractional accumulator are
## still re-derived on load, never serialized — so those three remain absence assertions, and a
## future contributor adding one of them to the schema fails this suite and has to argue with the
## ruling rather than quietly widen the format.
##
## `"arrivals"` AND `"removals"` USED TO BE ON THAT FORBIDDEN LIST. Both moved for the same
## reason: the thing they name is supposed to be re-derived on load and provably was not.
## `mark_all_dirty()` enqueues only registered home sites, so a habitat a child painted but nobody
## has moved into yet lost its pending arrival on every reload (2026-08-02). Nothing re-derives
## "what was this tile before it was painted" at all — that has no other source — so every
## removal receipt from an earlier session was silently gone, and `remove_at()` could never undo
## an old edit again (reported bug, terraform-bar rework playtest). Both absence assertions are
## now presence assertions, in the same place, so both reversals are visible here.
##
## Run:
##   bash scripts/run-tests.sh world_snapshot

const WORLD_PATH: String = "res://scenes/Main.tscn"

## Keys that must NEVER appear. Each is in-flight state that the restore re-derives.
const FORBIDDEN_KEYS: Array[String] = [
	"gestures", "dirty", "wood_fraction", "wood_pending",
]

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("world snapshot (capture)")
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	_world = packed.instantiate() as WorldRoot
	root.add_child(_world)
	_setup_ok = _world != null


func _process(_delta: float) -> bool:
	if not _setup_ok:
		finish()
		return true
	_frames += 1
	if _frames < 3:
		return false

	_world.wood.set_process(false)
	_world.simulation.set_process(false)
	_world.displacement.set_process(false)
	_world.presentation.set_process(false)
	_world.removals.set_process(false)

	_check_header_fields()
	_check_terrain_and_buildings()
	_check_home_sites()
	_check_the_forbidden_keys_are_absent()
	_check_the_arrival_queue_is_captured_json_native()
	_check_a_hand_edited_arrival_queue_degrades_rather_than_throwing()
	_check_the_removal_ledger_is_captured_json_native()
	_check_style_defaults()
	_check_it_is_json_round_trippable()
	_check_version_gating()
	_check_the_v1_migration()
	_check_the_v2_migration()
	_check_unknown_content_degrades_rather_than_crashes()

	finish()
	return true


func _check_header_fields() -> void:
	var data: Dictionary = WorldSnapshot.capture(_world, "Wildhaven", "meadow_start", 12345)
	check_eq(int(data["save_version"]), WorldSnapshot.SAVE_VERSION, "save_version is stamped")
	check_eq(data["name"], "Wildhaven", "the world's name is stored")
	check_eq(data["preset_id"], "meadow_start", "the originating preset is recorded")
	check_eq(int(data["seed"]), 12345, "the seed is stored even though nothing reads it until row 13")
	check_eq(int(data["width"]), _world.grid.width, "width matches the live grid")
	check_eq(int(data["depth"]), _world.grid.depth, "depth matches the live grid")
	check(not data.has("mist"), "no mist extent at v2 — row 13 adds the key and bumps the version")


func _check_terrain_and_buildings() -> void:
	# Edit the world through the real API, so the capture is of a world the player could make.
	_world.paint_tile(5, 5, "grass")
	_world.paint_tile(6, 5, "rock")
	# The House's `allowed_terrain` is ["grass"] and the grid's default tile is "wild_grass"
	# (WorldGrid.START_TERRAIN_ID), so a real player terraforms to grass before building —
	# this mirrors that, rather than relying on a default that would never let placement
	# succeed.
	_world.paint_tile(8, 8, "grass")
	check(_world.place_building(8, 8, "house"), "the house placement succeeds")

	var data: Dictionary = WorldSnapshot.capture(_world, "W", "meadow_start", 0)
	var terrain: Array = data["terrain"] as Array
	check_eq(terrain.size(), _world.grid.width * _world.grid.depth, "one terrain entry per tile")
	check_eq(terrain[5 * _world.grid.width + 5], "grass", "a painted tile is captured, row-major")
	check_eq(terrain[5 * _world.grid.width + 6], "rock", "and so is its neighbour")

	var buildings: Array = data["buildings"] as Array
	var found: bool = false
	for b: Dictionary in buildings:
		var origin: Array = b["origin"] as Array
		if int(origin[0]) == 8 and int(origin[1]) == 8:
			found = true
			check_eq(b["id"], "house", "the building's type is captured")
	check(found, "a placed building is captured at its footprint origin")
	check_eq(buildings.size(), 1, "a 1x1 building is captured ONCE, not once per covered tile")

	check_eq(int(data["wood"]), _world.get_wood(), "the Wood balance is captured")


func _check_home_sites() -> void:
	var site: HomeSite = _world.simulation.restore_site(
		Vector2i(12, 12), "rabbit", 4, [] as Array[String],
		[_world.grid.tile_to_world(12, 12)]
	)
	check(site != null, "a home site exists to capture")

	var data: Dictionary = WorldSnapshot.capture(_world, "W", "meadow_start", 0)
	var sites: Array = data["home_sites"] as Array
	var captured: Dictionary = {}
	for s: Dictionary in sites:
		var pos: Array = s["position"] as Array
		if int(pos[0]) == 12 and int(pos[1]) == 12:
			captured = s
	if not check(not captured.is_empty(), "the home site is captured"):
		return
	check_eq(captured["species_id"], "rabbit", "species is captured")
	check_eq(int(captured["radius"]), 4, "radius is captured")
	check_eq((captured["residents"] as Array).size(), 1, "resident count is captured")

	# Residents roam. Their LIVE position is what must be saved, not the home tile.
	var live: Vector3 = site.residents[0].position
	var saved: Array = (captured["residents"] as Array)[0] as Array
	check(
		abs(float(saved[0]) - live.x) < 0.001 and abs(float(saved[2]) - live.z) < 0.001,
		"a resident is captured at its LIVE position, not its home tile centre"
	)

	check(
		(data["species_hosted"] as Array).has("rabbit"),
		"the all-time Species Hosted set is captured"
	)
	# Sequence order is what makes tile exclusivity survive a reload.
	var seqs: Array[int] = []
	for s: Dictionary in sites:
		seqs.append(int(s["sequence"]))
	var sorted_seqs: Array[int] = seqs.duplicate()
	sorted_seqs.sort()
	check_eq(seqs, sorted_seqs, "home sites are captured in ascending sequence order")


func _check_the_forbidden_keys_are_absent() -> void:
	# Put real in-flight state into the world first, or this passes vacuously.
	_world.paint_tile(9, 9, "forest")          # opens a settlement gesture + a removal receipt
	_world.simulation.mark_all_dirty()          # dirties the queue
	check(_world.simulation.pending_evaluations() > 0, "the world really does have in-flight state")

	var data: Dictionary = WorldSnapshot.capture(_world, "W", "meadow_start", 0)
	for key: String in FORBIDDEN_KEYS:
		check(
			not data.has(key),
			"`%s` is absent — that in-flight state is re-derived, never saved (ruling 3)" % key
		)
	# ...and the two that moved to the other side of the line.
	check(
		data.has("arrivals"),
		"`arrivals` IS present — the re-derivation lost a pending arrival for a habitat with no "
		+ "home site yet, so the queue is saved (2026-08-02 ruling, partially reversing ruling 3)"
	)
	check(
		data.has("removals"),
		"`removals` IS present — nothing re-derives what a tile was before it was painted, so "
		+ "that receipt is saved too (v3, reversing the rest of ruling 3)"
	)
	var removals: Dictionary = data["removals"] as Dictionary
	var terrain_receipts: Array = removals["terrain"] as Array
	var found: bool = false
	for entry: Dictionary in terrain_receipts:
		var tile: Array = entry["tile"] as Array
		if int(tile[0]) == 9 and int(tile[1]) == 9:
			found = true
			check_eq(entry["previous_terrain_id"], "wild_grass",
				"...the forest paint's receipt is captured, naming what it painted over")
	check(found, "...specifically, the receipt this check just created is really in there")


## THE OUTBOUND HALF of the 2026-08-02 ruling: what a pending arrival looks like on disk. The
## behavioural half — a rabbit that was on its way still arriving after a reload — is
## `test_save_round_trip.gd`, which builds the habitat through the real causal path.
func _check_the_arrival_queue_is_captured_json_native() -> void:
	var queue: ArrivalQueue = _world.simulation.arrivals()
	queue.clear()
	check(queue.enqueue(Vector2i(21, 7), "rabbit"), "an arrival is pending to capture")

	var data: Dictionary = WorldSnapshot.capture(_world, "W", "meadow_start", 0)
	var arrivals: Array = data["arrivals"] as Array
	if not check_eq(arrivals.size(), 1, "the pending arrival is captured"):
		return
	var entry: Dictionary = arrivals[0] as Dictionary
	check_eq(entry["species_id"], "rabbit", "...naming its species")
	check(
		typeof(entry["position"]) == TYPE_ARRAY,
		"...with `position` as a plain [x, z] array, because Vector2i does not survive JSON"
	)
	var pair: Array = entry["position"] as Array
	check(int(pair[0]) == 21 and int(pair[1]) == 7, "...at the right tile")
	check(
		typeof(entry["remaining"]) == TYPE_FLOAT,
		"...and `remaining` as a plain float, so the delay already spent is not thrown away"
	)

	# THE INBOUND HALF at the schema level: the same data restores to the same queue.
	var saved_remaining: float = float(entry["remaining"])
	queue.clear()
	queue.restore(arrivals)
	check_eq(queue.size(), 1, "the captured queue restores")
	check(queue.has_pending(Vector2i(21, 7), "rabbit"), "...to the same tile and species")
	# Round-tripped through JSON as well, since that is what actually sits between the two.
	var text: String = JSON.stringify(data)
	var back: Dictionary = JSON.parse_string(text) as Dictionary
	queue.clear()
	queue.restore(back["arrivals"] as Array)
	check_eq(queue.size(), 1, "...and still restores after a real JSON round trip")

	# `remaining` must survive. A silent reset would restart a 20-60 s wait a child had almost
	# finished — invisible in every other assertion here.
	queue.clear()
	queue.restore(arrivals)
	var due: Array[Dictionary] = queue.advance(saved_remaining + 0.001)
	check_eq(
		due.size(), 1,
		"the SAVED delay is what counts down, not a fresh one — the restored arrival comes due "
		+ "the instant its own remaining time is spent"
	)
	queue.clear()


## Saves are hand-editable by design, so every field of a restored arrival is untrusted input.
## The bug class this closes is specific: a bare `float()` on a String or Dictionary is not a 0,
## it is a runtime error that aborts the enclosing function part-way through. `run-tests.sh`
## fails any suite that prints one, so the absence of that error IS the assertion here; these
## check that the good entries still survive alongside the bad ones.
func _check_a_hand_edited_arrival_queue_degrades_rather_than_throwing() -> void:
	var queue: ArrivalQueue = _world.simulation.arrivals()
	queue.clear()
	queue.restore([
		{"position": [4, 4], "species_id": "rabbit", "remaining": "soon"},   # not a number
		{"position": [5, 5], "species_id": "rabbit"},                        # missing key
		{"position": [6], "species_id": "rabbit", "remaining": 10.0},        # short position
		{"position": "over there", "species_id": "rabbit", "remaining": 10.0},
		{"position": [7, 7], "remaining": 10.0},                             # no species
		{"position": [8, 8], "species_id": 42, "remaining": 10.0},           # species not a String
		{"position": [{"x": 9}, 9], "species_id": "rabbit", "remaining": 10.0},
		"not even an object",
		{"position": [10, 10], "species_id": "rabbit", "remaining": 12.5},   # the one good entry
		{"position": [10, 10], "species_id": "rabbit", "remaining": 30.0},   # a duplicate of it
	])
	check_eq(
		queue.size(), 1,
		"eight malformed arrivals and one duplicate are dropped; the one good entry survives"
	)
	check(
		queue.has_pending(Vector2i(10, 10), "rabbit"),
		"...and it is the good one, restored intact"
	)
	var due: Array[Dictionary] = queue.advance(12.6)
	check_eq(due.size(), 1, "...still carrying its own saved delay, not the duplicate's")
	queue.clear()


## THE OUTBOUND HALF of the v3 reversal, mirroring `_check_the_arrival_queue_is_captured_json_
## native()` above. THE STALE-ISSUED-AT CONTRACT is the one behavioural half worth proving at
## this level (the rest — that `remove_at()` actually works again post-load — is
## `test_save_round_trip.gd`, which drives it through the real causal path): a receipt that was
## comfortably inside its grace window at capture time must NOT still read that way after a
## restore, because `RemovalLedger.restore()` deliberately does not round-trip `issued_at` — see
## that function's own header for why.
func _check_the_removal_ledger_is_captured_json_native() -> void:
	var ledger: RemovalLedger = _world.removals
	ledger.clear()
	ledger.record_paint(Vector2i(3, 3), "wild_grass", 2)
	check(ledger.within_grace(ledger.paint_receipt(Vector2i(3, 3))),
		"setup: the fresh receipt starts inside its own grace window")

	var data: Dictionary = WorldSnapshot.capture(_world, "W", "meadow_start", 0)
	var removals: Dictionary = data["removals"] as Dictionary
	var terrain_receipts: Array = removals["terrain"] as Array
	var captured: Dictionary = {}
	for entry: Dictionary in terrain_receipts:
		var tile: Array = entry["tile"] as Array
		if int(tile[0]) == 3 and int(tile[1]) == 3:
			captured = entry
	if not check(not captured.is_empty(), "the receipt is captured"):
		return
	check_eq(captured["previous_terrain_id"], "wild_grass", "...naming what it painted over")
	check_eq(int(captured["spent"]), 2, "...and what it cost")
	check(not captured.has("issued_at"), "...but NOT its grace-window timestamp — see restore()")

	# Round-tripped through JSON as well, since that is what actually sits between the two.
	var text: String = JSON.stringify(data)
	var back: Dictionary = JSON.parse_string(text) as Dictionary

	var restored := RemovalLedger.new()
	restored.restore(back["removals"] as Dictionary)
	var restored_receipt: Dictionary = restored.paint_receipt(Vector2i(3, 3))
	check_eq(restored_receipt["previous_terrain_id"], "wild_grass",
		"the restored ledger holds the same receipt after a real JSON round trip")
	check(
		not restored.within_grace(restored_receipt),
		"...but it reads as ALREADY PAST the grace window, even though the original receipt "
		+ "was captured well inside it — a save/load cycle takes real-world time that all but "
		+ "guarantees the real window already passed"
	)
	ledger.clear()


## THE OUTBOUND HALF of the v4 addition: what a chosen style default looks like on disk. The
## round trip through the real load path (and the pre-v4 fallback behavior) is
## `test_save_round_trip.gd`.
func _check_style_defaults() -> void:
	_world.set_style_default("forest", "birch_tree")
	var data: Dictionary = WorldSnapshot.capture(_world, "W", "meadow_start", 0)
	check_eq(int(data["save_version"]), 4, "save_version is now 4")
	check(data.has("style_defaults"), "style_defaults is captured")
	var captured: Dictionary = data["style_defaults"] as Dictionary
	check_eq(captured.get("forest", ""), "birch_tree",
		"the chosen forest default is captured verbatim")


func _check_it_is_json_round_trippable() -> void:
	var data: Dictionary = WorldSnapshot.capture(_world, "Wildhaven", "meadow_start", 7)
	var text: String = JSON.stringify(data, "\t")
	var back: Variant = JSON.parse_string(text)
	if not check(typeof(back) == TYPE_DICTIONARY, "the capture survives JSON"):
		return
	# Vector2i/Vector3 do NOT survive JSON — they must have been written as arrays already.
	check_eq(
		(back as Dictionary)["name"], "Wildhaven",
		"a JSON round trip preserves the capture, so no engine type leaked into the schema"
	)
	check(text.contains("\n"), "the JSON is pretty-printed and human-readable")


func _check_version_gating() -> void:
	check(WorldSnapshot.can_apply({"save_version": WorldSnapshot.SAVE_VERSION}), "the current version applies")
	check(not WorldSnapshot.can_apply({}), "a file with no save_version is refused")
	check(
		not WorldSnapshot.can_apply({"save_version": WorldSnapshot.SAVE_VERSION + 1}),
		"a FUTURE save_version is refused rather than guessed at"
	)
	check(
		WorldSnapshot.can_apply({"save_version": 1}),
		"v1 still applies — the migration hook stopped being identity on 2026-08-02 and carries "
		+ "old files forward rather than refusing them"
	)
	# Regression (commit 1d2e13f's fix missed this field): a hand-edited save_version that is
	# not a number must be refused, not crash `int()` and not silently coerce to a passing value.
	check(
		not WorldSnapshot.can_apply({"save_version": {"oops": 1}}),
		"an object save_version is refused rather than throwing 'Nonexistent int constructor'"
	)
	check(
		not WorldSnapshot.can_apply({"save_version": "two"}),
		"a string save_version is refused rather than coercing via int() to 0 and passing"
	)


## THE v1 -> v3 STEP (a v1 file falls through BOTH migration rules in one `migrate()` call — it
## used to be identity; the 2026-08-02 and v3 rulings gave it work).
func _check_the_v1_migration() -> void:
	var v1: Dictionary = {"save_version": 1, "name": "Ada's World", "seed": 0}
	var migrated: Dictionary = WorldSnapshot.migrate(v1)

	check_eq(int(migrated["save_version"]), WorldSnapshot.SAVE_VERSION,
		"a v1 file migrates all the way to the current version in one call")
	check(migrated.has("arrivals"), "...gaining the `arrivals` key it could not have had")
	check_eq(
		(migrated["arrivals"] as Array).size(), 0,
		"...as an EMPTY queue, so a migration never invents an arrival in a child's world"
	)
	check(migrated.has("removals"), "...and the `removals` key it could not have had either")
	check_eq(migrated["removals"], {} as Dictionary,
		"...as an empty ledger, so a migration never invents a receipt in a child's world")
	check_eq(int(v1["seed"]), 0, "...without mutating the caller's dictionary")

	# The seed half. A v1 file's seed was a constant 0 in every world that build ever wrote.
	check(
		int(migrated["seed"]) != 0,
		"...and a real seed, because `seed: 0` in every file is as unrecoverable as no seed",
		"got %d" % int(migrated["seed"])
	)
	check_eq(
		int(WorldSnapshot.migrate(v1)["seed"]), int(migrated["seed"]),
		"migrating the SAME file twice yields the same seed, so a world's mist does not reshuffle "
		+ "every time it is opened"
	)
	var other: Dictionary = WorldSnapshot.migrate(
		{"save_version": 1, "name": "Ben's World", "seed": 0}
	)
	check(
		int(other["seed"]) != int(migrated["seed"]),
		"two differently-named worlds migrate to DIFFERENT seeds, so they do not share a reveal",
		"`Ada's World` -> %d, `Ben's World` -> %d" % [int(migrated["seed"]), int(other["seed"])]
	)
	# HONESTLY LABELLED: `seed_from_name()`'s `| 1` is a structural guarantee, not something this
	# assertion proves — `"".hash()` is already non-zero, so this passes with or without the `| 1`
	# (verified by reverting it). It is here because an unnamed world must not land on the
	# sentinel, not because it is a negative-controlled test of that operator.
	check(
		WorldSnapshot.seed_from_name("") != 0,
		"even an unnamed world migrates off 0, which is a sentinel in two other places"
	)

	check(WorldSnapshot.can_apply({"save_version": 2}), "v2 still applies — the v2 -> v3 step "
		+ "carries it forward the same way the v1 -> v2 step carries v1 forward")


## THE v2 -> v3 STEP: only `removals` is new here, so this is the narrow slice
## `_check_the_v1_migration()`'s cascade does not isolate on its own — everything ELSE about a
## v2 file (its own real seed, its own real arrival queue) must be left alone by this step,
## exactly as the v1 seed-repair rule is scoped to v1 only.
##
## ONE `migrate()` CALL CASCADES THROUGH EVERY LATER STEP TOO (same as the v1 check above), so a
## v2 file handed to `migrate()` today comes back at the CURRENT version, not frozen at v3 — the
## v3 -> v4 (`style_defaults`) step runs in the same call. That step invents no field (see its own
## comment in `migrate()`), so it leaves every assertion below about v2's own fields undisturbed.
func _check_the_v2_migration() -> void:
	var v2: Dictionary = {
		"save_version": 2, "name": "Ada's World", "seed": 777,
		"arrivals": [{"position": [1, 2], "species_id": "rabbit", "remaining": 5.0}],
	}
	var migrated: Dictionary = WorldSnapshot.migrate(v2)

	check_eq(int(migrated["save_version"]), WorldSnapshot.SAVE_VERSION,
		"a v2 file migrates all the way to the current version in one call, same as a v1 file")
	check(migrated.has("removals"), "...gaining the `removals` key it could not have had")
	check_eq(migrated["removals"], {} as Dictionary,
		"...as an empty ledger, so a migration never invents a receipt in a child's world")
	check_eq(int(migrated["seed"]), 777, "...without touching a v2 file's own real seed")
	check_eq(
		(migrated["arrivals"] as Array).size(), 1,
		"...or its own real arrival queue"
	)
	check(not migrated.has("style_defaults"),
		"...and the v3 -> v4 step invents no `style_defaults` either — an old file just plays as "
		+ "if nobody had opened a style picker yet")
	check_eq(int(v2["save_version"]), 2, "...and without mutating the caller's dictionary")

	# A v3 file (already carrying real removals) passes through untouched — migrate() is
	# idempotent, same guarantee the v1 step already gives.
	var v3: Dictionary = {
		"save_version": 3, "name": "Cy's World", "seed": 42, "arrivals": [],
		"removals": {"terrain": [{"tile": [1, 1], "previous_terrain_id": "grass", "spent": 0}],
			"buildings": []},
	}
	var passed_through: Dictionary = WorldSnapshot.migrate(v3)
	check_eq(
		((passed_through["removals"] as Dictionary)["terrain"] as Array).size(), 1,
		"a v3 file's own real removals survive an idempotent re-migration"
	)


func _check_unknown_content_degrades_rather_than_crashes() -> void:
	# A world saved with content that has since been removed must still open. A partial world
	# beats a crash for a kid, and the warning is how the developer finds out.
	var data: Dictionary = WorldSnapshot.capture(_world, "Broken", "meadow_start", 0)
	(data["terrain"] as Array)[0] = "terrain_that_does_not_exist"
	(data["home_sites"] as Array).append({
		"position": [15, 15], "species_id": "unicorn", "radius": 4,
		"sequence": 999, "structure_tags": [], "residents": [[15.0, 0.0, 15.0]],
	})
	(data["buildings"] as Array).append({"origin": [17, 17], "id": "castle"})
	data["arrivals"] = [
		{"position": [19, 19], "species_id": "unicorn", "remaining": 12.0},
		{"position": [20, 20], "species_id": "rabbit", "remaining": 12.0},
	]

	var applied: bool = WorldSnapshot.apply(_world, data)
	check(applied, "a save naming removed content still loads")
	check_eq(
		_world.get_tile_terrain(0, 0), WorldGrid.START_TERRAIN_ID,
		"an unknown terrain falls back to tag-inert wild grass, never to a tag-emitting default"
	)
	check(
		not _world.resident_species_ids().has("unicorn"),
		"an unknown species' home is dropped rather than half-created"
	)
	check(_world.grid.get_building(17, 17) == null, "an unknown building is skipped")
	check(
		not _world.simulation.arrivals().has_pending(Vector2i(19, 19), "unicorn"),
		"an arrival naming a species that is no longer in the roster is DROPPED — the same "
		+ "degradation rule unknown terrain and unknown buildings already follow"
	)
	check(
		_world.simulation.arrivals().has_pending(Vector2i(20, 20), "rabbit"),
		"...and the load continues: the arrival beside it is still pending"
	)
