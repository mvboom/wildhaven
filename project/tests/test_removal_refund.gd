extends QATestCase
## REMOVAL / UNDO & REFUND — Tier 1 row 3's own thin form, Open Question **#16**, driven through
## `WorldRoot`'s public API on the real `scenes/Main.tscn`. gdd.md -> Player Interface & Controls
## states the whole policy, and every clause of it is an assertion below:
##
##   "**Removal / undo & refund policy** (uniform across Terraform reverts and Build removals).
##    **Grace window** (~10-15 s after placement): removal refunds **100%** — accidental taps
##    cost nothing. After the grace window, removal refunds a flat recycle percentage
##    (placeholder ~50%, tunable) — 'recycling,' not a free take-back. Refunds are always in the
##    resource originally spent; **free natural terrain refunds nothing**."
##
## FIVE SECTIONS:
##   1. THE ARITHMETIC, in isolation: 100% inside, `floor(cost x 0.5)` outside, **floored and
##      not rounded**, with the grace boundary asserted on both sides of a single hundredth of
##      a second.
##   2. INSIDE THE WINDOW, THROUGH THE REAL API: an accidental tap really does cost nothing.
##   3. AFTER THE WINDOW: the flat recycle, and **a place/remove loop cannot mint Wood** — the
##      exploit the flooring exists to prevent, driven as a loop and measured.
##   4. FREE NATURAL TERRAIN REFUNDS NOTHING, and it is not a special case: a free tile's
##      receipt records a cost of 0 and 0 refunds 0 through the same arithmetic as everything
##      else.
##   5. A TAP THAT REMOVES NOTHING IS NOT AN ERROR (Pillar 1), and the one-receipt-per-tile
##      shape is pinned as the stated limit it is rather than discovered later as a bug.
##
## WHY THE CLOCK IS DRIVEN BY HAND. `RemovalLedger` is delta-driven (`tick(delta)`), so this
## suite takes `WoodLedger`, `RemovalLedger`, `HabitatSimulation` and `GentleDisplacement` off
## `_process` and advances only what it means to advance. Passive Wood accrual would otherwise
## drift every balance assertion here by an unpredictable amount.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_removal_refund.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

## gdd.md's cost table, and the constants the human still owns (#8, #16, #26).
const HOUSE_COST: int = 15
const FIELD_COST: int = 2
const EXPECTED_RECYCLE_FRACTION: float = 0.5

## `floor(15 x 0.5)` is 7. Rounding would give 8, and 8 is the number that would let a player
## farm Wood. Named so the difference is impossible to read past.
const HOUSE_RECYCLE_FLOORED: int = 7
const HOUSE_RECYCLE_IF_ROUNDED: int = 8

## Comfortably past the grace window in one hand-driven call.
const PAST_GRACE: float = SettlementWindow.GRACE_WINDOW_SECONDS + 1.0

## A patch of grass well away from anything, so nothing here can qualify a habitat by accident.
const BUILD_TILE := Vector2i(4, 4)
const PAINT_TILE := Vector2i(6, 4)
const FREE_TILE := Vector2i(8, 4)
const UNTOUCHED_TILE := Vector2i(20, 4)
const WILD_BUILD_TILE := Vector2i(10, 4)

## Section 3's loop length. Starting Wood is 50 and each after-grace House cycle costs 8, so
## four cycles is as far as the balance goes.
const MINT_CYCLES: int = 4

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false
var _wood_events: Array[int] = []
var _tile_events: Array[Vector2i] = []


func _initialize() -> void:
	begin("removal & refund")

	_check_the_arithmetic_in_isolation()

	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		finish()
		return
	_world = node as WorldRoot
	# Arrays, not ints: a lambda over a local `int` captures by value and never increments, which
	# would make every "no signal fired" assertion below pass vacuously.
	_world.wood_changed.connect(func(amount: int) -> void: _wood_events.append(amount))
	_world.tile_changed.connect(func(x: int, z: int) -> void: _tile_events.append(Vector2i(x, z)))
	root.add_child(_world)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	# Everything that moves on its own is taken off `_process`, so the only clock in this suite
	# is the one it drives by hand.
	_world.wood.set_process(false)
	_world.removals.set_process(false)
	_world.simulation.set_process(false)
	_world.displacement.set_process(false)
	_world.presentation.set_process(false)

	_check_inside_the_grace_window_refunds_everything()
	_check_after_the_grace_window_refunds_the_flat_recycle()
	_check_a_place_remove_loop_cannot_mint_wood()
	_check_free_natural_terrain_refunds_nothing()
	_check_removing_nothing_is_not_an_error()
	_check_one_receipt_per_tile_is_the_stated_limit()
	_check_demolishing_a_building_built_on_wild_grass_reverts_to_grass()

	note_expected_pending(
		"BOTH numbers in this policy are PLACEHOLDERS (#16) — the human owns them",
		"gdd.md gives the grace window as ~10-15 s and the recycle as \"placeholder ~50%, "
		+ "tunable\". 12.0 s and 0.5 are pinned here so a retune is a visible edit. What is NOT "
		+ "a placeholder is the SHAPE: 100% inside, a flat fraction outside, floored, and 0 for "
		+ "anything that was free. Those hold at any values."
	)
	note_expected_pending(
		"ONE RECEIPT PER TILE — a ten-step undo stack is NOT built, and is not claimed to be",
		"`RemovalLedger` keys the last edit per tile, so removal undoes the last thing the "
		+ "player did there and not the thing before it. Asserted below as a pinned limit rather "
		+ "than left to be discovered as a bug. Deeper undo is a depth purchase (a stack per "
		+ "key instead of a value) and is a human call."
	)
	note_expected_pending(
		"WHETHER 12 s IS LONG ENOUGH TO NOTICE A MISTAKE IS NOT A MACHINE CHECK",
		"This suite proves the refund arithmetic and its boundary. Whether a six-year-old "
		+ "realises their mistake and taps again inside the window is the step-5 kid playtest's."
	)

	finish()
	return true


# --- 1. The arithmetic, in isolation -------------------------------------------------------------

func _check_the_arithmetic_in_isolation() -> void:
	check_eq(RemovalLedger.RECYCLE_FRACTION, EXPECTED_RECYCLE_FRACTION,
		"RECYCLE_FRACTION is %.2f (gdd.md's \"placeholder ~50%%, tunable\", #16)"
			% EXPECTED_RECYCLE_FRACTION)

	var ledger := RemovalLedger.new()
	ledger.record_placement(Vector2i(0, 0), "house", HOUSE_COST)
	var receipt: Dictionary = ledger.placement_receipt(Vector2i(0, 0))

	check(ledger.within_grace(receipt), "a receipt starts inside the grace window")
	check_eq(ledger.refund_for(receipt), HOUSE_COST,
		"100%%: a %d Wood placement refunds all %d inside the window" % [HOUSE_COST, HOUSE_COST])

	# THE BOUNDARY, on both sides of one hundredth of a second. `within_grace` is `<=`, so the
	# instant the window closes is the last instant of the full refund.
	ledger.tick(SettlementWindow.GRACE_WINDOW_SECONDS)
	check(ledger.within_grace(ledger.placement_receipt(Vector2i(0, 0))),
		"AT the boundary (exactly %.1f s) the receipt is STILL inside the window"
			% SettlementWindow.GRACE_WINDOW_SECONDS)
	check_eq(ledger.refund_for(ledger.placement_receipt(Vector2i(0, 0))), HOUSE_COST,
		"...and still refunds 100%")

	ledger.tick(0.01)
	check(not ledger.within_grace(ledger.placement_receipt(Vector2i(0, 0))),
		"one hundredth of a second later it is OUT")
	check_eq(ledger.refund_for(ledger.placement_receipt(Vector2i(0, 0))), HOUSE_RECYCLE_FLOORED,
		"...and refunds the flat recycle: floor(%d x %.2f) = %d"
			% [HOUSE_COST, EXPECTED_RECYCLE_FRACTION, HOUSE_RECYCLE_FLOORED])
	check(ledger.refund_for(ledger.placement_receipt(Vector2i(0, 0))) != HOUSE_RECYCLE_IF_ROUNDED,
		"FLOORED, NOT ROUNDED: %d and not %d — rounding an odd cost UP is what would let a "
			% [HOUSE_RECYCLE_FLOORED, HOUSE_RECYCLE_IF_ROUNDED]
		+ "player farm Wood by placing and removing, which turns a gentle take-back into an "
		+ "exploit and Wood into a score")

	# Every odd cost floors. Asserted as a table because the flooring is the whole exploit guard.
	var floor_ledger := RemovalLedger.new()
	var expected: Dictionary = {0: 0, 1: 0, 2: 1, 3: 1, 5: 2, 7: 3, 15: 7, 99: 49}
	var wrong: PackedStringArray = PackedStringArray()
	for cost: int in expected.keys():
		floor_ledger.record_paint(Vector2i(cost, 0), "grass", cost)
		floor_ledger.tick(PAST_GRACE)
		var got: int = floor_ledger.refund_for(floor_ledger.paint_receipt(Vector2i(cost, 0)))
		if got != int(expected[cost]):
			wrong.append("cost %d -> %d, expected %d" % [cost, got, int(expected[cost])])
	check(wrong.is_empty(),
		"every cost floors: %s — never once rounded up" % str(expected),
		"wrong: %s" % str(wrong))
	# NON-VACUITY: half of that table would also pass if `refund_for` always returned 0.
	floor_ledger.record_paint(Vector2i(50, 0), "grass", 40)
	check_eq(floor_ledger.refund_for(floor_ledger.paint_receipt(Vector2i(50, 0))), 40,
		"NON-VACUITY: the same function still returns a FULL refund inside the window, so the "
		+ "floored values above are arithmetic and not a stuck zero")

	check_eq(ledger.refund_for({}), 0, "an absent receipt refunds 0 rather than erroring")
	ledger.free()
	floor_ledger.free()


# --- 2. Inside the grace window: accidental taps cost nothing --------------------------------------

func _check_inside_the_grace_window_refunds_everything() -> void:
	var start: int = _world.get_wood()
	check_eq(start, WoodLedger.STARTING_WOOD, "the world starts at %d Wood" % WoodLedger.STARTING_WOOD)

	# RE-POINTED (-> D-29 #1, `WorldGrid.START_TERRAIN_ID` "grass" -> "wild_grass"): the House's
	# `allowed_terrain` is `["grass"]` specifically (buildings.md), and the world's tiles now
	# start as `wild_grass`, not `grass`. Painted once, here, because `BUILD_TILE` is placed and
	# removed repeatedly through the rest of this suite and a building never changes the terrain
	# underneath it ("a building sits on terrain, it is not terrain") — so this one paint is all
	# `BUILD_TILE` ever needs. Free, so it does not disturb any Wood arithmetic below.
	_world.paint_tile(BUILD_TILE.x, BUILD_TILE.y, "grass")

	# A BUILD removal.
	check(_world.place_building(BUILD_TILE.x, BUILD_TILE.y, "house"), "a House is placed")
	check_eq(_world.get_wood(), start - HOUSE_COST, "...costing %d Wood" % HOUSE_COST)
	check_eq(_world.refund_preview(BUILD_TILE.x, BUILD_TILE.y), HOUSE_COST,
		"`refund_preview()` promises the whole %d back while the window is open" % HOUSE_COST)
	check(_world.can_remove(BUILD_TILE.x, BUILD_TILE.y), "...and `can_remove()` agrees")

	check(_world.remove_at(BUILD_TILE.x, BUILD_TILE.y), "the House comes down")
	check_eq(_world.get_wood(), start,
		"ACCIDENTAL TAPS COST NOTHING: the balance is back to exactly where it started")
	check(not _world.grid.is_occupied(BUILD_TILE.x, BUILD_TILE.y), "...and the tile is clear")

	# A TERRAFORM revert — "uniform across Terraform reverts and Build removals", which is why
	# it is one method and not two.
	check(_world.paint_tile(PAINT_TILE.x, PAINT_TILE.y, "cultivated_field"), "a field is painted")
	check_eq(_world.get_wood(), start - FIELD_COST, "...costing %d Wood" % FIELD_COST)
	check_eq(_world.refund_preview(PAINT_TILE.x, PAINT_TILE.y), FIELD_COST,
		"...and previewing a full refund")
	check(_world.remove_at(PAINT_TILE.x, PAINT_TILE.y), "the field is reverted")
	check_eq(_world.get_wood(), start, "...at no cost, by the same policy and the same method")
	# RE-POINTED (-> D-29 #1): `PAINT_TILE` was never explicitly painted before this, so its
	# "before" is the world's own new default, `wild_grass` — the point of this check (revert
	# restores the REAL prior terrain, not a hardcoded default) is unaffected by which one it is.
	check_eq(_world.get_tile_terrain(PAINT_TILE.x, PAINT_TILE.y), "wild_grass",
		"...and the ground is the wild_grass it was before, not a default")


# --- 3. After the grace window: recycling, not a free take-back ------------------------------------

func _check_after_the_grace_window_refunds_the_flat_recycle() -> void:
	var start: int = _world.get_wood()

	check(_world.place_building(BUILD_TILE.x, BUILD_TILE.y, "house"), "a House is placed again")
	check_eq(_world.get_wood(), start - HOUSE_COST, "...costing %d Wood" % HOUSE_COST)

	# The window closes. Nothing else in the world moves — this is the only clock running.
	_world.removals.tick(PAST_GRACE)

	check_eq(_world.refund_preview(BUILD_TILE.x, BUILD_TILE.y), HOUSE_RECYCLE_FLOORED,
		"`refund_preview()` COUNTED DOWN across the boundary: %d now, not %d"
			% [HOUSE_RECYCLE_FLOORED, HOUSE_COST])
	check(_world.remove_at(BUILD_TILE.x, BUILD_TILE.y), "the House comes down")
	check_eq(_world.get_wood(), start - HOUSE_COST + HOUSE_RECYCLE_FLOORED,
		"RECYCLING, NOT A FREE TAKE-BACK: %d spent, %d back, %d Wood gone for good"
			% [HOUSE_COST, HOUSE_RECYCLE_FLOORED, HOUSE_COST - HOUSE_RECYCLE_FLOORED])
	check_eq(_world.get_wood(), start - (HOUSE_COST - HOUSE_RECYCLE_FLOORED),
		"...which is a net loss of exactly %d" % (HOUSE_COST - HOUSE_RECYCLE_FLOORED))
	check_eq(_world.get_wood(), start - HOUSE_COST + HOUSE_RECYCLE_FLOORED,
		"...and the balance is %d, NOT the %d a rounded-up refund of %d would have left"
			% [start - HOUSE_COST + HOUSE_RECYCLE_FLOORED,
				start - HOUSE_COST + HOUSE_RECYCLE_IF_ROUNDED, HOUSE_RECYCLE_IF_ROUNDED])

	# The same, on a priced terrain, so the policy is shown to be uniform rather than
	# building-shaped. floor(2 x 0.5) = 1.
	var before_paint: int = _world.get_wood()
	check(_world.paint_tile(PAINT_TILE.x, PAINT_TILE.y, "cultivated_field"), "a field is painted")
	_world.removals.tick(PAST_GRACE)
	check_eq(_world.refund_preview(PAINT_TILE.x, PAINT_TILE.y), 1,
		"a %d Wood field recycles for floor(%d x %.2f) = 1"
			% [FIELD_COST, FIELD_COST, EXPECTED_RECYCLE_FRACTION])
	check(_world.remove_at(PAINT_TILE.x, PAINT_TILE.y), "...and is reverted")
	check_eq(_world.get_wood(), before_paint - FIELD_COST + 1,
		"...for a net loss of 1 Wood — the same policy, the same method, a different mode")


## THE EXPLOIT THE FLOORING EXISTS TO PREVENT, driven as a loop rather than argued.
func _check_a_place_remove_loop_cannot_mint_wood() -> void:
	# (a) AFTER the window: every cycle must LOSE Wood, monotonically.
	var balances: Array[int] = [_world.get_wood()]
	var cycles_run: int = 0
	for _i in MINT_CYCLES:
		if not _world.place_building(BUILD_TILE.x, BUILD_TILE.y, "house"):
			break
		_world.removals.tick(PAST_GRACE)
		if not _world.remove_at(BUILD_TILE.x, BUILD_TILE.y):
			break
		balances.append(_world.get_wood())
		cycles_run += 1

	check(cycles_run >= 3, "%d place/remove cycles ran past the grace window" % cycles_run)
	var monotonic: bool = true
	var deltas: PackedStringArray = PackedStringArray()
	for i in range(1, balances.size()):
		deltas.append(str(balances[i] - balances[i - 1]))
		if balances[i] >= balances[i - 1]:
			monotonic = false
	check(monotonic,
		"A PLACE/REMOVE LOOP CANNOT MINT WOOD: the balance fell on EVERY cycle (%s), so no "
			% str(balances)
		+ "amount of tapping produces Wood")
	check_eq(balances[balances.size() - 1], balances[0] - cycles_run * (HOUSE_COST - HOUSE_RECYCLE_FLOORED),
		"...by exactly %d each time, which is the flooring doing its job (deltas %s)"
			% [HOUSE_COST - HOUSE_RECYCLE_FLOORED, str(deltas)])
	check(balances[balances.size() - 1] < balances[0],
		"...and %d Wood is gone in total" % (balances[0] - balances[balances.size() - 1]))

	# (b) INSIDE the window: neutral, and NEVER profitable. A 100% refund is deliberately
	# wood-neutral ("accidental taps cost nothing"), so the assertion here is a ceiling, not a
	# decrease — a loop that ever rose above the start would be the same exploit by another route.
	var neutral_start: int = _world.get_wood()
	var highest: int = neutral_start
	for _i in 20:
		if not _world.place_building(BUILD_TILE.x, BUILD_TILE.y, "house"):
			break
		_world.remove_at(BUILD_TILE.x, BUILD_TILE.y)
		highest = maxi(highest, _world.get_wood())
	check_eq(_world.get_wood(), neutral_start,
		"INSIDE the window, 20 place/remove cycles are exactly wood-NEUTRAL")
	check_eq(highest, neutral_start,
		"...and the balance never once rose above where it started, so the full refund is a "
		+ "take-back and not a source")


# --- 4. Free natural terrain refunds nothing --------------------------------------------------------

func _check_free_natural_terrain_refunds_nothing() -> void:
	var start: int = _world.get_wood()
	check_eq(_world.paint_cost("rock"), 0, "rock is free — nature costs nothing")

	check(_world.paint_tile(FREE_TILE.x, FREE_TILE.y, "rock"), "a free rock tile is painted")
	check_eq(_world.get_wood(), start, "...costing nothing, as data says it should")
	check_eq(_world.refund_preview(FREE_TILE.x, FREE_TILE.y), 0,
		"FREE NATURAL TERRAIN REFUNDS NOTHING: the preview is 0 Wood")
	check(_world.can_remove(FREE_TILE.x, FREE_TILE.y),
		"...and it is still REMOVABLE — a 0 refund is an ordinary answer, not a refusal")

	check(_world.remove_at(FREE_TILE.x, FREE_TILE.y), "the free tile is reverted")
	check_eq(_world.get_wood(), start, "...refunding 0, exactly as promised")
	# RE-POINTED (-> D-29 #1): `FREE_TILE` was never explicitly painted before this, so its
	# "before" is `wild_grass`, not `grass` — the point (the ground really goes back) holds either way.
	check_eq(_world.get_tile_terrain(FREE_TILE.x, FREE_TILE.y), "wild_grass",
		"...and the ground really went back — reversibility does not depend on a refund")

	# ...and it is still 0 after the window, because there is nothing to halve.
	check(_world.paint_tile(FREE_TILE.x, FREE_TILE.y, "water"), "a free water tile is painted")
	_world.removals.tick(PAST_GRACE)
	check_eq(_world.refund_preview(FREE_TILE.x, FREE_TILE.y), 0,
		"...and past the window it is still 0 — half of nothing is nothing")
	check(_world.remove_at(FREE_TILE.x, FREE_TILE.y), "...still removable")
	check_eq(_world.get_wood(), start, "...and still free")

	# NOT A SPECIAL CASE. The rule falls out of the receipt recording a cost of 0, which goes
	# through the same arithmetic as everything else — so a price change cannot rot it.
	var stripped: String = _strip_comments(
		load("res://scripts/economy/removal_ledger.gd").source_code)
	var branches: PackedStringArray = PackedStringArray()
	for line: String in stripped.split("\n"):
		var lowered: String = line.to_lower()
		if lowered.contains("natural") or lowered.contains("terrain_is_free") or lowered.contains("is_free"):
			branches.append(line.strip_edges())
	check(branches.is_empty(),
		"`RemovalLedger` contains no free/natural-terrain branch at all — the rule is the "
		+ "arithmetic, not an `if`",
		"found: %s" % str(branches))
	check(stripped.contains("RECYCLE_FRACTION"),
		"...while the same stripped source DOES contain `RECYCLE_FRACTION`, so the absence "
		+ "above is a measurement rather than an empty search")


# --- 5. A tap that removes nothing is not an error --------------------------------------------------

func _check_removing_nothing_is_not_an_error() -> void:
	var start: int = _world.get_wood()
	var wood_events: int = _wood_events.size()
	var tile_events: int = _tile_events.size()

	check(not _world.can_remove(UNTOUCHED_TILE.x, UNTOUCHED_TILE.y),
		"`can_remove()` is false on a tile in its original state")
	check(not _world.remove_at(UNTOUCHED_TILE.x, UNTOUCHED_TILE.y),
		"A TILE IN ITS ORIGINAL STATE IS NOT AN ERROR TO REMOVE — it is simply a tap that does "
		+ "nothing (Pillar 1: no fail states, no error states)")
	# RE-POINTED (-> D-29 #1): an untouched tile's terrain is now `wild_grass`, not `grass`.
	check_eq(_world.get_tile_terrain(UNTOUCHED_TILE.x, UNTOUCHED_TILE.y), "wild_grass",
		"...the tile is untouched")
	check_eq(_world.get_wood(), start, "...the balance is untouched")
	check_eq(_wood_events.size(), wood_events, "...`wood_changed` did NOT fire")
	check_eq(_tile_events.size(), tile_events, "...`tile_changed` did NOT fire either")
	check_eq(_world.refund_preview(UNTOUCHED_TILE.x, UNTOUCHED_TILE.y), 0,
		"...and the preview is a plain 0")

	# Out of bounds is the same non-event.
	check(not _world.can_remove(-1, -1), "out of bounds: `can_remove()` is false")
	check(not _world.remove_at(-1, -1), "...and `remove_at()` is a silent no-op")
	check_eq(_world.refund_preview(-1, -1), 0, "...previewing 0")
	check_eq(_wood_events.size(), wood_events, "...with still no signal of any kind")

	# NON-VACUITY: the signal log is live, so the two "did not fire" checks above are real.
	check(_world.paint_tile(UNTOUCHED_TILE.x, UNTOUCHED_TILE.y, "rock"),
		"NON-VACUITY CONTROL: a real edit on the same tile...")
	check(_tile_events.size() > tile_events,
		"...DOES fire `tile_changed`, so the silence above was measured and not assumed")
	_world.remove_at(UNTOUCHED_TILE.x, UNTOUCHED_TILE.y)


func _check_one_receipt_per_tile_is_the_stated_limit() -> void:
	# ONE RECEIPT PER TILE — "the last edit, not a history". Pinned as the documented limit it
	# is, so a ten-step undo stack is a visible decision rather than something a player discovers
	# they do not have.
	# RE-POINTED (-> D-29 #1): `PAINT_TILE` reverted to `wild_grass` (not `grass`) at the end of
	# section 3 above, so that is the "before" this transition text now names.
	check(_world.paint_tile(PAINT_TILE.x, PAINT_TILE.y, "water"), "wild_grass -> water")
	check(_world.paint_tile(PAINT_TILE.x, PAINT_TILE.y, "rock"), "water -> rock")
	check(_world.remove_at(PAINT_TILE.x, PAINT_TILE.y), "one removal...")
	check_eq(_world.get_tile_terrain(PAINT_TILE.x, PAINT_TILE.y), "water",
		"...undoes the LAST edit, putting the tile back to water")
	check(not _world.can_remove(PAINT_TILE.x, PAINT_TILE.y),
		"...and there is no second step: the receipt was consumed, so the tile is done")
	check(not _world.remove_at(PAINT_TILE.x, PAINT_TILE.y),
		"...a second tap removes nothing, silently — the wild_grass underneath is not reachable")

	# Tidy up so the tile is not left as water for anything reading the world after this suite.
	_world.paint_tile(PAINT_TILE.x, PAINT_TILE.y, "grass")


# --- 6. Demolishing a building implicitly built on Wild grass ---------------------------------------

## `WorldRoot.place_building()` silently converts a Wild-grass footprint tile to Grass before
## placing a building whose `allowed_terrain` accepts Grass (the House's does). That conversion
## goes through `paint_tile()`, the same pipeline as an explicit Terraform tap, specifically so
## `remove_at()`'s removal-ledger revert needs no new state to track. Confirmed directly here,
## not assumed: demolishing the House must put the tile back at Grass — what it was actually
## painted to, moments before placement — and NOT at Wild grass, its state before that implicit
## conversion.
func _check_demolishing_a_building_built_on_wild_grass_reverts_to_grass() -> void:
	# The place/remove-loop sections above deliberately drain the balance to prove Wood cannot
	# be minted; topped back up here since this check is about terrain, not affordability.
	_world.wood.reset(1000)
	var start: int = _world.get_wood()
	check_eq(_world.get_tile_terrain(WILD_BUILD_TILE.x, WILD_BUILD_TILE.y), "wild_grass",
		"setup: this tile was never touched, so it is still the untouched default, wild_grass")

	# No explicit Terraform tap first — the House places directly on Wild grass.
	check(_world.place_building(WILD_BUILD_TILE.x, WILD_BUILD_TILE.y, "house"),
		"a House places directly on Wild grass")
	check_eq(_world.get_wood(), start - HOUSE_COST,
		"...costing exactly the House's %d Wood, no extra debit for the implicit conversion"
			% HOUSE_COST)
	check_eq(_world.get_tile_terrain(WILD_BUILD_TILE.x, WILD_BUILD_TILE.y), "grass",
		"...and the tile is Grass under the House, not left as Wild grass")

	check(_world.remove_at(WILD_BUILD_TILE.x, WILD_BUILD_TILE.y), "the House is demolished")
	check_eq(_world.get_wood(), start,
		"...inside the grace window, the full %d Wood comes back" % HOUSE_COST)
	check(not _world.grid.is_occupied(WILD_BUILD_TILE.x, WILD_BUILD_TILE.y),
		"...and the tile is unoccupied again")
	check_eq(_world.get_tile_terrain(WILD_BUILD_TILE.x, WILD_BUILD_TILE.y), "grass",
		"THE TILE REVERTS TO GRASS — what it was actually painted to just before placement — "
		+ "NOT back to wild_grass, its state before the implicit conversion")


# --- helpers -----------------------------------------------------------------------------------------

## Strips `#`-comments so a structural source check cannot be satisfied (or defeated) by prose.
func _strip_comments(source: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line: String in source.split("\n"):
		var hash_at: int = line.find("#")
		out.append(line if hash_at < 0 else line.substr(0, hash_at))
	return "\n".join(out)
