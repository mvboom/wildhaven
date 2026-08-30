extends QATestCase
## MIST REVEAL — Tier 1 row 13's thin form (D-38, decisions.md). Driven through `WorldRoot`'s
## public edit API on the real `scenes/Main.tscn`, the same way `test_removal_refund.gd` and
## `test_camera_rails.gd` exercise their own rows.
##
## EVERY CLAUSE OF THE ROW'S INVARIANTS/ACCEPTANCE CONDITION IS AN ASSERTION BELOW:
##   * building/terraforming within `MistReveal.REVEAL_PROXIMITY_TILES` of the mist edge
##     unfurls a new band `MistReveal.REVEAL_BAND_TILES` deeper, instantly, with no timer.
##   * the world is capped at `WorldRoot.MAX_SAVED_WORLD_TILES` (128, D-38 -> D-35, the same
##     number, ruled together on purpose).
##   * reveal is a deterministic function of `(world_seed, x, z)`.
##   * revealed land is always tag-inert wild grass, with no animals pre-placed.
##   * mist reveal is NEVER a qualification trigger (D-22) — it does not go through
##     `tile_changed`/`set_terrain()`, so it cannot reach `HabitatSimulation`'s four triggers.
##
## THE ONE DISCLOSED, DELIBERATE GAP THIS SUITE ALSO PINS DOWN: only the high-x ("east") and
## high-z ("north") edges can ever recede. `WorldGrid.grow()`'s own header explains why —
## append-only growth is what keeps `WorldSnapshot` (project/scripts/save/, outside this row's
## reserved directory) and every already-placed tile coordinate correct with zero changes to
## either. This is pinned as a stated limit, exactly the way `test_removal_refund.gd` pins
## "one receipt per tile" — a limit the human can see and revisit, not a bug found later.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_mist_reveal.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

## gdd.md -> World Structure's stated start size, unaffected by this row.
const EXPECTED_START := Vector2i(36, 36)

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false
var _grown_events: Array = []       # Array[Array[Vector2i]], one entry per `mist_revealed`
var _tile_events: Array[Vector2i] = []


func _initialize() -> void:
	begin("mist reveal (row 13, D-38)")

	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		finish()
		return
	_world = node as WorldRoot
	_world.mist_revealed.connect(
		func(new_tiles: Array[Vector2i]) -> void: _grown_events.append(new_tiles)
	)
	_world.tile_changed.connect(
		func(x: int, z: int) -> void: _tile_events.append(Vector2i(x, z))
	)
	root.add_child(_world)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	# Nothing here needs a live clock, and passive Wood accrual would otherwise complicate
	# nothing this suite checks — left on is harmless, but off matches the sibling suites'
	# convention of disabling what is not being exercised.
	_world.wood.set_process(false)
	_world.simulation.set_process(false)
	_world.displacement.set_process(false)
	_world.presentation.set_process(false)

	check_eq(_world.grid_size(), EXPECTED_START,
		"the world under test starts 36x36 (gdd.md -> World Structure)")

	_check_constants()
	_check_editing_away_from_any_edge_reveals_nothing()
	_check_edit_near_the_high_x_edge_unfurls_east()
	_check_edit_near_the_high_z_edge_unfurls_north()
	_check_a_corner_edit_grows_both_axes_in_one_band()
	_check_the_low_edges_are_a_permanent_boundary_not_mist()
	_check_existing_tiles_never_move_across_a_reveal()
	_check_reveal_is_never_a_qualification_trigger()
	_check_reveal_terrain_is_deterministic_and_inert()
	_check_growth_is_capped_at_the_world_cap()  # LAST: drives the grid to 128x128

	note_expected_pending(
		"THE CHIME ITSELF IS NOT WIRED — row 14 (the audio slice) has not landed",
		"`WorldRoot.mist_revealed` fires synchronously, once, at exactly the moment a chime "
		+ "would play (this suite listens to it directly above) — but no `AudioStreamPlayer` "
		+ "exists yet to attach to it. Row 14's own tier1-status.md cell already names this: "
		+ "'row 13's reveal chime and this row's confirmation SFX are one sound in the floor.'"
	)
	note_expected_pending(
		"ONLY TWO OF FOUR EDGES CAN EVER RECEDE — a stated limit, not a defect",
		"See this suite's own header and `WorldGrid.grow()`'s: append-only growth (the low "
		+ "corner never renumbers) is what keeps `WorldSnapshot`, `HomeSiteRegistry` and "
		+ "`RemovalLedger` — all outside this row's reserved directory — correct with zero "
		+ "changes to any of them. Flagged for the human under Proposals."
	)

	finish()
	return true


func _check_constants() -> void:
	check_eq(MistReveal.REVEAL_PROXIMITY_TILES, 2, "reveal proximity is 2 tiles (D-38)")
	check_eq(MistReveal.REVEAL_BAND_TILES, 2, "reveal band depth is 2 tiles (D-38)")
	check_eq(WorldRoot.MAX_SAVED_WORLD_TILES, 128,
		"the world cap is 128 (D-38, ruled identical to row 1's own MAX_SAVED_WORLD_TILES)")


func _check_editing_away_from_any_edge_reveals_nothing() -> void:
	var before: Vector2i = _world.grid_size()
	check(_world.paint_tile(10, 10, "grass"), "painted a tile well inside the world")
	check_eq(_world.grid_size(), before,
		"an edit far from every edge reveals nothing — no cost, no reward, no consequence "
		+ "beyond the paint itself")


func _check_edit_near_the_high_x_edge_unfurls_east() -> void:
	var before: Vector2i = _world.grid_size()
	var edge_x: int = before.x - MistReveal.REVEAL_PROXIMITY_TILES
	check(_world.paint_tile(edge_x, 15, "grass"),
		"painted a tile within reveal proximity of the current east edge")
	var after: Vector2i = _world.grid_size()
	check_eq(after, Vector2i(before.x + MistReveal.REVEAL_BAND_TILES, before.y),
		"the east edge unfurled by exactly one reveal band; the north/south edges are untouched")

	var wild_count: int = 0
	var inert_count: int = 0
	for x in range(before.x, after.x):
		for z in after.y:
			if _world.get_tile_terrain(x, z) == WorldGrid.START_TERRAIN_ID:
				wild_count += 1
			if _world.get_tile_tags(x, z).is_empty():
				inert_count += 1
	var expected: int = MistReveal.REVEAL_BAND_TILES * after.y
	check_eq(wild_count, expected, "every newly revealed tile is wild grass")
	check_eq(inert_count, expected, "...and every one of them is tag-inert (no habitat tags)")

	check(_world.can_paint(before.x, 15, "grass"),
		"the newly revealed land is already usable through the ordinary paint API")


func _check_edit_near_the_high_z_edge_unfurls_north() -> void:
	var before: Vector2i = _world.grid_size()
	var edge_z: int = before.y - MistReveal.REVEAL_PROXIMITY_TILES
	check(_world.paint_tile(18, edge_z, "grass"),
		"painted a tile within reveal proximity of the current north edge")
	var after: Vector2i = _world.grid_size()
	check_eq(after, Vector2i(before.x, before.y + MistReveal.REVEAL_BAND_TILES),
		"the north edge unfurled by exactly one reveal band; east/south are untouched")


func _check_a_corner_edit_grows_both_axes_in_one_band() -> void:
	var before: Vector2i = _world.grid_size()
	var edge_x: int = before.x - MistReveal.REVEAL_PROXIMITY_TILES
	var edge_z: int = before.y - MistReveal.REVEAL_PROXIMITY_TILES
	var events_before: int = _grown_events.size()
	check(_world.paint_tile(edge_x, edge_z, "grass"), "painted the north-east corner")
	var after: Vector2i = _world.grid_size()
	check_eq(after, before + Vector2i(MistReveal.REVEAL_BAND_TILES, MistReveal.REVEAL_BAND_TILES),
		"a single edit near BOTH high edges grows both axes")
	check_eq(_grown_events.size(), events_before + 1,
		"...in exactly one `mist_revealed` event, not two — instant, one chime, not a double one")


func _check_the_low_edges_are_a_permanent_boundary_not_mist() -> void:
	var before: Vector2i = _world.grid_size()
	check(_world.paint_tile(0, 22, "grass"), "painted the literal west edge tile (x = 0)")
	check(_world.paint_tile(22, 0, "grass"), "painted the literal south edge tile (z = 0)")
	check_eq(_world.grid_size(), before,
		"THE DISCLOSED LIMITATION: the low corner (x = 0, z = 0) never recedes in this thin "
		+ "form — WorldGrid.grow() is append-only, by design (see its own header)")


func _check_existing_tiles_never_move_across_a_reveal() -> void:
	var probe_origin: Vector3 = _world.grid_to_world(0, 0)
	var probe_interior: Vector3 = _world.grid_to_world(5, 5)
	var before: Vector2i = _world.grid_size()
	check(_world.paint_tile(before.x - MistReveal.REVEAL_PROXIMITY_TILES, 25, "grass"),
		"one more east-edge edit, to force another band")
	check(_world.grid_size().x > before.x, "...which really did grow the grid again (control)")
	check(_world.grid_to_world(0, 0).is_equal_approx(probe_origin),
		"tile (0, 0)'s WORLD POSITION is unchanged after growth — nothing already placed slides")
	check(_world.grid_to_world(5, 5).is_equal_approx(probe_interior),
		"...same for an ordinary interior tile")


func _check_reveal_is_never_a_qualification_trigger() -> void:
	var before: Vector2i = _world.grid_size()
	var edge_x: int = before.x - MistReveal.REVEAL_PROXIMITY_TILES
	var tile_events_before: int = _tile_events.size()
	check(_world.paint_tile(edge_x, 30, "grass"), "painted near the east edge once more")
	var after: Vector2i = _world.grid_size()
	check(after.x > before.x, "...which really did grow the grid (control)")
	check_eq(_tile_events.size(), tile_events_before + 1,
		"EXACTLY ONE `tile_changed` fired — the paint itself — even though dozens of new tiles "
		+ "were created: `WorldGrid.grow()` never routes new land through `tile_changed`, so it "
		+ "can never reach `HabitatSimulation`'s four triggers by accident (D-22)")
	check_eq(_world.simulation.arrivals().size(), 0,
		"...and the arrival queue is still empty — nothing has ever been enqueued purely by "
		+ "mist growth over the whole suite so far")


func _check_reveal_terrain_is_deterministic_and_inert() -> void:
	check_eq(MistReveal.reveal_terrain_id(1234, 50, 50), WorldGrid.START_TERRAIN_ID,
		"MistReveal.reveal_terrain_id() answers wild grass for an arbitrary (seed, x, z)")
	check_eq(MistReveal.reveal_terrain_id(1234, 50, 50), MistReveal.reveal_terrain_id(1234, 50, 50),
		"...deterministically: the same (seed, x, z) always answers the same")
	check_eq(MistReveal.reveal_terrain_id(9999, 1, 1), WorldGrid.START_TERRAIN_ID,
		"...true for a different seed too — there is only one safe answer, per D-22")

	var wild_grass: TerrainDefinition = _world.grid.terrain_definition(WorldGrid.START_TERRAIN_ID)
	if check(wild_grass != null, "wild_grass is a real, loaded TerrainDefinition"):
		check(wild_grass.emitted_tags.is_empty(),
			"CONTROL: wild grass itself emits no tags — this is WHY reveal can only ever answer "
			+ "wild grass without re-opening the inert-land defect D-22 fixed")


## A STANDALONE `WorldGrid`, deliberately not attached to `TerrainView`/`Main.tscn` — driving
## `_world.grid` all the way to the 128x128 cap would make `TerrainView` instantiate one real
## `StaticBody3D` + collider PER TILE (its own header: "Rendering LOD ... is deliberately
## absent ... a known cost at the ~128x128 cap"), and MEASURED doing exactly that here first
## exceeded Jolt's default physics body ceiling (10240) partway through — a real, pre-existing
## rendering/collision scalability gap (row 2/3's LOD depth, not this row's reveal logic) that
## this suite should not be the one to trip on every routine run. `WorldGrid.grow()`'s own
## clamp is pure data-layer arithmetic with no view attached, so it is tested in isolation here
## instead — see the PEND below for the finding this sidestep is reporting, not hiding.
func _check_growth_is_capped_at_the_world_cap() -> void:
	var standalone := WorldGrid.new()
	standalone.build(TerrainDefinition.load_all(), 40, 40)

	var new_tiles: Array[Vector2i] = standalone.grow(9999, 9999, 42)
	check_eq(Vector2i(standalone.width, standalone.depth),
		Vector2i(WorldRoot.MAX_SAVED_WORLD_TILES, WorldRoot.MAX_SAVED_WORLD_TILES),
		"grow() clamps to the D-38 world cap even when asked for far more than that")
	check(not new_tiles.is_empty(), "...and it genuinely DID grow (not a silent no-op)")

	var again: Array[Vector2i] = standalone.grow(9999, 9999, 42)
	check(again.is_empty(),
		"CONTROL: asking again once already at the cap is a real no-op — no new tiles")

	note_expected_pending(
		"MEASURED: THE 128x128 CAP EXCEEDS JOLT'S DEFAULT PHYSICS BODY CEILING WHEN VIEWED",
		"Growing `_world.grid` (the real `TerrainView`-attached grid) all the way to 128x128 in "
		+ "this same run hit 'Failed to create underlying Jolt Physics body ... Maximum number "
		+ "of bodies is currently set to 10240' partway through — 16384 tiles each getting a "
		+ "picking `StaticBody3D` (plus a second, blocking one on impassable/occupied tiles) "
		+ "is more collision bodies than Jolt's default project setting allows. This is "
		+ "`terrain_view.gd`'s own already-disclosed LOD absence ('a known cost at the ~128x128 "
		+ "cap, not at the ~36x36 start') becoming reachable for the first time now that row 13 "
		+ "can actually grow a world that far — not a defect in this row's reveal logic, but a "
		+ "real finding for the human: either raise the project's physics/3d/jolt_physics "
		+ "max body setting, or land row 2's rendering-LOD depth, before a real playthrough "
		+ "grows a world anywhere near the cap."
	)
