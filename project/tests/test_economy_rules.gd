extends QATestCase
## THE ECONOMY'S RULES — Tier 1 row 5, driven through `WorldRoot`'s public API on the real
## `scenes/Main.tscn`.
##
## gdd.md -> Systems in Play -> Economy: Wood is "a material, not a score, and a pacer, not an
## economy". The one pricing rule is *"Nature is free; construction costs materials."*
##
## THREE THINGS, AND THE FIRST IS A PILLAR INVARIANT:
##   1. THE FREE-FOREST RECOVERY GUARANTEE. "No dead ends, by construction: Forest is free to
##      paint and passively produces Wood, so a player at zero can always paint, wait, and
##      build again." Asserted AT ZERO WOOD, which is the only balance at which the guarantee
##      is load-bearing.
##   2. COSTS ARE DEBITED, AND AN UNAFFORDABLE EDIT CHANGES NOTHING AND PRODUCES NO ERROR
##      STATE (Pillar 1: no fail states, no error states, no penalties). "No error state" is
##      asserted three ways: the tile is unchanged, the balance is unchanged, and NO SIGNAL
##      FIRES AT ALL — neither `wood_changed` nor `tile_changed` — because the whole public
##      signal surface is pinned here and contains nothing that could carry an error.
##   3. PASSIVE ACCRUAL SCALES WITH FOREST TILE COUNT, measured at 0, N and 2N tiles.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_economy_rules.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

## gdd.md -> Economy's cost table, and the constants the human still owns (#8, #26).
const EXPECTED_STARTING_WOOD: int = 50
const EXPECTED_CULTIVATED_COST: int = 2
const EXPECTED_HOUSE_COST: int = 15
## Includes the habitat-tiers ruling's 3 additions (Meadow, Scrub, Snowfield —
## task-8-brief.md) — all natural terrain, all free, per the same pricing rule.
const EXPECTED_FREE_TERRAINS: Array[String] = ["forest", "grass", "meadow", "rock", "scrub", "snowfield", "water", "wild_grass"]

## Forest tiles painted for the accrual measurement, and again for the doubling check.
const FOREST_BATCH: int = 5

var _world: WorldRoot = null
var _wood_events: Array[int] = []
var _tile_events: Array[Vector2i] = []
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("economy rules")

	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		finish()
		return
	_world = node as WorldRoot
	root.add_child(_world)
	_world.wood_changed.connect(func(amount: int) -> void: _wood_events.append(amount))
	_world.tile_changed.connect(func(x: int, z: int) -> void: _tile_events.append(Vector2i(x, z)))
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	_check_pricing_rule()
	_check_free_forest_guarantee_at_zero()
	_check_costs_are_debited()
	_check_unaffordable_edit_is_a_no_op_with_no_error_state()
	_check_passive_accrual_scales_with_forest()
	_check_wild_grass_converts_implicitly_on_placement()

	note_expected_pending(
		"the two economy constants are still PROPOSED (#8, #26)",
		"Starting stockpile 50 Wood and 1 Wood / forest tile / 60 s are gdd.md's stated "
		+ "baselines, pinned here so a silent drift fails — not because the human has ruled."
	)
	note_expected_pending(
		"REFUND / RECYCLE LANDED 2026-07-28 (#16) — it lives in its own suite",
		"The old note here said there was no removal path and therefore no refund to test. "
		+ "`WorldRoot.remove_at()` is that path and `RemovalLedger` is the policy: 100% inside "
		+ "the grace window, `floor(cost x 0.5)` after, 0 for anything that was free. All of it "
		+ "is asserted in `test_removal_refund.gd`, including that a place/remove loop cannot "
		+ "mint Wood. Kept out of this suite on purpose — this one owns the PRICING rule and the "
		+ "free-Forest guarantee, and refunds are a second policy on top of them."
	)
	note_expected_pending(
		"TAP-TO-TEND is row-5 DEPTH and is correctly absent",
		"The ~5 Wood active burst on a per-tile cooldown is not built; the floor is passive "
		+ "accrual only. Recorded so its absence reads as scope, not as a gap."
	)

	finish()
	return true


# --- "Nature is free; construction costs materials." -------------------------------------------

func _check_pricing_rule() -> void:
	check_eq(_world.get_wood(), EXPECTED_STARTING_WOOD,
		"the world starts with %d Wood (#26)" % EXPECTED_STARTING_WOOD)
	check_eq(WoodLedger.STARTING_WOOD, EXPECTED_STARTING_WOOD,
		"...which is the ledger's declared constant, not an incidental value")

	var free_ids: Array[String] = []
	var priced: Array[String] = []
	for terrain: TerrainDefinition in _world.terrain_options():
		if terrain.cost == 0:
			free_ids.append(terrain.id)
		else:
			priced.append("%s=%d" % [terrain.id, terrain.cost])
	free_ids.sort()
	check_eq(free_ids, EXPECTED_FREE_TERRAINS,
		"every natural terrain is free — the pricing rule, read off the data")
	check_eq(priced, ["cultivated_field=%d" % EXPECTED_CULTIVATED_COST],
		"the cultivated field is the ONLY priced terrain in v1 (#8)")
	check_eq(_world.paint_cost("cultivated_field"), EXPECTED_CULTIVATED_COST,
		"paint_cost() agrees with the data entry")
	check_eq(_world.place_cost("house"), EXPECTED_HOUSE_COST,
		"the House costs %d Wood at the 1x1 floor form (#8, #26)" % EXPECTED_HOUSE_COST)


# --- 1. The free-Forest recovery guarantee, at zero ---------------------------------------------

func _check_free_forest_guarantee_at_zero() -> void:
	# The invariant asserted in code at grid-build time, read directly rather than inferred
	# from a log line.
	check(_world.grid.free_forest_guarantee_holds(),
		"WorldGrid's own free-Forest assertion holds")
	check_eq(_world.paint_cost("forest"), 0, "Forest costs 0 Wood")

	# Forest is always IN THE PALETTE, not merely affordable. A recovery path the player
	# cannot see is not a recovery path.
	var palette_ids: Array[String] = []
	for terrain: TerrainDefinition in _world.terrain_options():
		palette_ids.append(terrain.id)
	check(palette_ids.has("forest"),
		"Forest is present in the Terraform palette (`terrain_options()`)")

	_world.wood.reset(0)
	check_eq(_world.get_wood(), 0, "the player is stranded at ZERO Wood")

	check(_world.can_paint(2, 2, "forest"), "at zero Wood, Forest still reports as paintable")
	check(_world.paint_tile(2, 2, "forest"), "at zero Wood, Forest actually paints")
	check_eq(_world.get_tile_terrain(2, 2), "forest", "...and the tile converted")
	check_eq(_world.get_wood(), 0, "...and it cost nothing")

	# The other free terrains work at zero too, so the recovery path is not a single lucky
	# special case in the code.
	#
	# RE-POINTED (-> D-29 #1, `WorldGrid.START_TERRAIN_ID` "grass" -> "wild_grass"): tile (3, 3)
	# starts as `wild_grass` now, not `grass`, so the first paint below is a REAL conversion
	# (and itself free, since every natural terrain costs 0) — the genuine "grass onto grass is
	# a no-op" case this check is actually about has to be set up explicitly rather than found
	# already sitting there.
	check(_world.paint_tile(3, 3, "grass"), "painting grass onto wild_grass converts it (still free)")
	check(_world.paint_tile(3, 3, "grass") == false,
		"painting grass onto grass is a no-op (nothing changed), not a spend")
	check(_world.paint_tile(3, 3, "rock"), "at zero Wood, Rock also paints (nature is free)")
	check(not _world.can_paint(4, 4, "cultivated_field"),
		"...but the one PRICED terrain is correctly unaffordable at zero")


# --- 2a. Costs are debited ------------------------------------------------------------------------

func _check_costs_are_debited() -> void:
	_world.wood.reset(EXPECTED_STARTING_WOOD)
	var before: int = _world.get_wood()

	check(_world.paint_tile(10, 10, "cultivated_field"), "a cultivated field paints when affordable")
	check_eq(_world.get_wood(), before - EXPECTED_CULTIVATED_COST,
		"...and exactly %d Wood is debited" % EXPECTED_CULTIVATED_COST)

	# RE-POINTED (-> D-29 #1): a House's `allowed_terrain` is `["grass"]` specifically
	# (buildings.md), and the world's tiles now start as `wild_grass`, not `grass` — the old
	# ambient backdrop made these two tiles eligible for free; now it is stated explicitly.
	# Free (cost 0), so it does not disturb the Wood arithmetic this check is actually about.
	_world.paint_tile(12, 12, "grass")
	check(_world.place_building(12, 12, "house"), "a House places on grass when affordable")
	check_eq(_world.get_wood(), before - EXPECTED_CULTIVATED_COST - EXPECTED_HOUSE_COST,
		"...and exactly %d Wood is debited" % EXPECTED_HOUSE_COST)

	# Wood is a pacer, not a score: nothing anywhere gates on the balance, and it can be spent
	# to exactly zero without any state change beyond the number.
	_world.paint_tile(14, 14, "grass")
	_world.wood.reset(EXPECTED_HOUSE_COST)
	check(_world.place_building(14, 14, "house"), "a build that spends the last Wood succeeds")
	check_eq(_world.get_wood(), 0, "...leaving the balance at exactly zero, which is a legal state")


# --- 2b. The unaffordable edit --------------------------------------------------------------------

func _check_unaffordable_edit_is_a_no_op_with_no_error_state() -> void:
	_world.wood.reset(1)   # one below the cultivated field's cost
	_wood_events.clear()
	_tile_events.clear()

	var tile := Vector2i(20, 20)
	var terrain_before: String = _world.get_tile_terrain(tile.x, tile.y)

	check(not _world.can_paint(tile.x, tile.y, "cultivated_field"),
		"an unaffordable paint reports as not-paintable (for the soft cue)")
	check(not _world.paint_tile(tile.x, tile.y, "cultivated_field"),
		"...and paint_tile() returns false")
	check_eq(_world.get_tile_terrain(tile.x, tile.y), terrain_before,
		"THE TILE IS UNCHANGED — the edit simply did not happen")
	check_eq(_world.get_wood(), 1, "the balance is untouched — no partial spend, no debt")

	# NO ERROR STATE, asserted as an absence of any state change at all. A refusal is not an
	# event: nothing is notified, so nothing downstream can render it as a failure.
	check_eq(_wood_events.size(), 0, "no `wood_changed` fired for the refused edit")
	check_eq(_tile_events.size(), 0, "no `tile_changed` fired for the refused edit")

	# The same for a build.
	check(not _world.can_place(22, 22, "house"), "an unaffordable House reports as not-placeable")
	check(not _world.place_building(22, 22, "house"), "...and place_building() returns false")
	check(not _world.grid.is_occupied(22, 22), "THE TILE IS UNCHANGED — nothing was placed")
	check_eq(_wood_events.size() + _tile_events.size(), 0, "and still no signal of any kind fired")

	# And there is no error channel to fire on: the whole public signal surface, pinned.
	var world_signals: Array[String] = []
	for entry: Dictionary in _world.get_script().get_script_signal_list():
		world_signals.append(entry["name"])
	world_signals.sort()
	# Updated 2026-07-28 by the row 10 dispatch: Gentle Displacement added three public
	# signals. **The assertion's intent is unchanged** — it pins the whole surface so that an
	# error/failure channel cannot appear unnoticed — and the three new names are not one:
	# `displacement_warned` is disclosure (gdd.md: "disclosure, not deterrence ... no plea, no
	# judgment"), and the other two report a thing that happened, not a thing that went wrong.
	# There is still no signal anywhere that says an edit was refused.
	#
	# Updated 2026-08-09 by the row 13 dispatch: `mist_revealed` joined the surface — the mist
	# reveal's chime hook (row 14 has no audio asset yet to attach it to). Same category as the
	# row 10 additions: it reports land that was just revealed, never a refusal, and it is not
	# even reachable from this suite's refused-edit paths above (mist only ever grows FROM a
	# successful edit near the current edge; nothing here is near one).
	check_eq(world_signals, [
		"displacement_warned",
		"mist_revealed",
		"resident_arrived",
		"resident_departed",
		"resident_relocated",
		"tile_changed",
		"wood_changed",
	] as Array[String],
		"WorldRoot's whole public signal surface is pinned — none of it is an error/failure "
		+ "channel, and a refused edit still fires nothing at all")

	var ledger_signals: Array[String] = []
	for entry: Dictionary in _world.wood.get_script().get_script_signal_list():
		ledger_signals.append(entry["name"])
	check_eq(ledger_signals, ["wood_changed"] as Array[String],
		"WoodLedger declares exactly one signal — there is no `insufficient_funds` anywhere")

	# The control: restore the balance and the identical edit succeeds. Without this, every
	# assertion above would pass on a world where painting is simply broken.
	_world.wood.reset(EXPECTED_STARTING_WOOD)
	check(_world.paint_tile(tile.x, tile.y, "cultivated_field"),
		"CONTROL: with Wood in hand the very same edit succeeds")
	check_eq(_world.get_tile_terrain(tile.x, tile.y), "cultivated_field",
		"CONTROL: ...and the tile converted")


# --- 3. Passive accrual ------------------------------------------------------------------------------

func _check_passive_accrual_scales_with_forest() -> void:
	check_eq(WoodLedger.SECONDS_PER_WOOD_PER_FOREST_TILE, 60.0,
		"the passive rate is 1 Wood per forest tile per 60 s (#8)")

	# A forest-free stretch of the world does no work and pays nothing. `reset()` also clears
	# the sub-Wood carry, so each measurement below starts from a clean slate.
	var scratch := WorldGrid.new()
	scratch.build(TerrainDefinition.load_all(), 8, 8)
	var ledger := WoodLedger.new()
	ledger.attach(scratch)
	ledger.reset(0)
	check_eq(scratch.forest_tile_count(), 0, "the scratch world starts with no forest")
	ledger.tick(600.0)
	check_eq(ledger.get_wood(), 0,
		"ten minutes with zero forest tiles pays ZERO — accrual is not a background trickle")

	for i in FOREST_BATCH:
		scratch.set_terrain(i, 0, "forest")
	check_eq(scratch.forest_tile_count(), FOREST_BATCH,
		"%d forest tiles are counted incrementally (the economy never scans the world)" % FOREST_BATCH)
	ledger.reset(0)
	ledger.tick(60.0)
	check_eq(ledger.get_wood(), FOREST_BATCH,
		"%d forest tiles pay %d Wood over 60 s" % [FOREST_BATCH, FOREST_BATCH])

	for i in FOREST_BATCH:
		scratch.set_terrain(i, 1, "forest")
	check_eq(scratch.forest_tile_count(), FOREST_BATCH * 2, "the forest count doubled")
	ledger.reset(0)
	ledger.tick(60.0)
	check_eq(ledger.get_wood(), FOREST_BATCH * 2,
		"SCALES WITH TILE COUNT: twice the forest pays twice the Wood over the same 60 s")

	# Sub-Wood accrual is carried, not rounded away — a small forest still pays on schedule.
	ledger.reset(0)
	for _i in 6:
		ledger.tick(10.0)
	check_eq(ledger.get_wood(), FOREST_BATCH * 2,
		"six 10 s ticks pay the same as one 60 s tick — the fractional carry is not lost")

	# Painting forest away stops the payments, which is what makes the count the source of
	# truth rather than a one-time reading.
	for i in FOREST_BATCH * 2:
		scratch.set_terrain(i % FOREST_BATCH, i / FOREST_BATCH, "grass")
	check_eq(scratch.forest_tile_count(), 0, "the forest is gone")
	ledger.reset(0)
	ledger.tick(600.0)
	check_eq(ledger.get_wood(), 0, "...and accrual stops with it")

	ledger.free()
	scratch.free()


# --- Wild grass converts implicitly (and for free) under a placed building --------------------

## Every tile in the world starts as `wild_grass` (`WorldGrid.START_TERRAIN_ID`), and no
## building's `allowed_terrain` names `"wild_grass"` (buildings.md — a building must never
## visually sit on unconverted wild land). Instead `WorldRoot.place_building()` silently
## converts exactly the Wild-grass tiles in the footprint to Grass first, through the same
## free `paint_tile()` pipeline a player's own Terraform tap would use, and only then places
## the building. `grass.tres` and `wild_grass.tres` both cost 0, so the conversion never shows
## up as a Wood debit distinct from the building's own cost.
func _check_wild_grass_converts_implicitly_on_placement() -> void:
	_world.wood.reset(1000)

	# 1. A FOOTPRINT THAT IS ENTIRELY WILD GRASS: no explicit Terraform tap first, unlike every
	# other placement in this suite.
	var solo_tile := Vector2i(24, 2)
	check_eq(_world.get_tile_terrain(solo_tile.x, solo_tile.y), "wild_grass",
		"setup: the tile starts as the untouched default, wild_grass")
	var wood_before_solo: int = _world.get_wood()
	check(_world.place_building(solo_tile.x, solo_tile.y, "house"),
		"a House places directly on Wild grass — no separate Terraform tap needed")
	check_eq(_world.get_tile_terrain(solo_tile.x, solo_tile.y), "grass",
		"...and the tile silently converted to Grass, not left as Wild grass under the House")
	check_eq(_world.get_wood(), wood_before_solo - EXPECTED_HOUSE_COST,
		"...costing exactly the House's %d Wood — the free conversion added no extra debit"
			% EXPECTED_HOUSE_COST)

	# 2. A MIXED 2x2 FOOTPRINT (Barn): one tile pre-painted to Grass, the other three left as
	# the Wild-grass default — only the three Wild-grass tiles should convert.
	var barn_origin := Vector2i(24, 6)
	var barn_tiles: Array[Vector2i] = [
		barn_origin, barn_origin + Vector2i(1, 0),
		barn_origin + Vector2i(0, 1), barn_origin + Vector2i(1, 1),
	]
	_world.paint_tile(barn_origin.x, barn_origin.y, "grass")
	for tile: Vector2i in barn_tiles:
		var expected: String = "grass" if tile == barn_origin else "wild_grass"
		check_eq(_world.get_tile_terrain(tile.x, tile.y), expected,
			"setup: %s starts as %s" % [tile, expected])
	var wood_before_barn: int = _world.get_wood()
	var barn_cost: int = _world.place_cost("barn")
	check(_world.place_building(barn_origin.x, barn_origin.y, "barn"),
		"a Barn places across a footprint mixing Grass and Wild grass")
	for tile: Vector2i in barn_tiles:
		check_eq(_world.get_tile_terrain(tile.x, tile.y), "grass",
			("...and every reserved tile (%s) is Grass now, including the ones that were "
				+ "already Grass before") % tile)
	check_eq(_world.get_wood(), wood_before_barn - barn_cost,
		"...costing exactly the Barn's %d Wood — converting three Wild-grass tiles cost nothing"
			% barn_cost)

	# 3. A FOOTPRINT INCLUDING A NON-GRASS, NON-WILD-GRASS TILE (Rock): placement must still be
	# refused, and REFUSED WITH NO SIDE EFFECT — the Wild-grass tiles in the same footprint must
	# NOT have been converted just because the placement attempt touched them. This is the
	# "validate before mutating" requirement: a failed placement leaves no trace.
	var blocked_origin := Vector2i(24, 10)
	var blocked_tiles: Array[Vector2i] = [
		blocked_origin, blocked_origin + Vector2i(1, 0),
		blocked_origin + Vector2i(0, 1), blocked_origin + Vector2i(1, 1),
	]
	var rock_tile: Vector2i = blocked_origin + Vector2i(1, 1)
	_world.paint_tile(rock_tile.x, rock_tile.y, "rock")
	for tile: Vector2i in blocked_tiles:
		var expected: String = "rock" if tile == rock_tile else "wild_grass"
		check_eq(_world.get_tile_terrain(tile.x, tile.y), expected,
			"setup: %s starts as %s" % [tile, expected])
	var wood_before_blocked: int = _world.get_wood()
	check(not _world.place_building(blocked_origin.x, blocked_origin.y, "barn"),
		"a Barn is refused when its footprint covers Rock, exactly as before this feature")
	for tile: Vector2i in blocked_tiles:
		var expected: String = "rock" if tile == rock_tile else "wild_grass"
		check_eq(_world.get_tile_terrain(tile.x, tile.y), expected,
			("...and %s is UNCHANGED — a failed placement converted nothing, not even the "
				+ "Wild-grass tiles it looked at") % tile)
	check(not _world.grid.is_occupied(blocked_origin.x, blocked_origin.y),
		"...no building actually landed")
	check_eq(_world.get_wood(), wood_before_blocked, "...and not one Wood moved")
