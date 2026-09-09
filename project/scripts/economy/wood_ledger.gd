class_name WoodLedger
extends Node
## Wood — Tier 1 row 5 (Economy), thin form.
##
## gdd.md -> Economy: Wood is "a material, not a score, and a pacer, not an economy".
## Everything punitive is deliberately absent: **an edit the player cannot afford simply
## does not happen** — no error, no flash, no penalty, no debt (Pillar 1). Callers get a
## plain `false` and are expected to do nothing with it but skip.
##
## The thin form is passive accrual from Forest only. Tap-to-tend's ~5 Wood burst is row-5
## depth (spec.md -> What Deepening Buys) and is not built here.

## Emitted on every balance change. The HUD's read-only counter (spec.md -> Screen Layouts)
## binds to this.
signal wood_changed(new_amount: int)


## DECIDED 2026-09-08 by the human (-> D-62), raised from the GDD's ~50 baseline. Open
## Question #26's *value* is settled; its stated sizing principle ("covers the nudge's first
## build only ... pacing begins at the second build") is NOT what 100 buys and is left open
## for the human to restate -- see decisions.md D-62. The raise answers D-60: footprints grew
## to 2x2/3x3 while costs stayed put, so wood-per-tile-claimed fell.
const STARTING_WOOD: int = 100

## PLACEHOLDER / GDD baseline — the human owns this (Open Question #8). gdd.md -> Economy
## names this "v1's most load-bearing constant": "~1 Wood per Forest tile per 60 s".
## Expressed as seconds-per-Wood-per-forest-tile so the rate reads exactly as the GDD
## states it, rather than as a derived fraction nobody can check against the document.
const SECONDS_PER_WOOD_PER_FOREST_TILE: float = 60.0

## DECIDED 2026-09-08 by the human (-> D-63). The stockpile above which passive accrual is
## throttled to a trickle, and the trickle's own rate.
##
## WHY A THROTTLE EXISTS AT ALL: gdd.md -> Economy calls the passive rate "v1's most
## load-bearing constant" and Wood "a pacer, not an economy". A pacer only paces while it is
## scarce, and Wood's supply is unbounded in the one direction that matters — Forest is free
## to paint (the recovery guarantee), so a player who paints a hundred tiles of it earns a
## hundred Wood a minute and the cost of every building stops meaning anything. The throttle
## is the ceiling that keeps the pacer a pacer: past `THROTTLE_THRESHOLD_WOOD` the world still
## pays, so nothing is ever taken away and no edit is ever refused (Pillar 1), but it pays at
## a rate a large forest cannot out-scale.
##
## DELIBERATELY A CLIFF, NOT A TAPER. A ramp would be smoother on a graph and invisible in
## play: nobody watching a counter can tell a 40%-throttled rate from an untuned one, so the
## ramp would cost a constant nobody could ever check the game against. One threshold is a
## number the human can read off the HUD.
const THROTTLE_THRESHOLD_WOOD: int = 1000
const THROTTLED_SECONDS_PER_WOOD: float = 60.0


var _wood: int = STARTING_WOOD

## Sub-Wood accrual carried between ticks. Kept as a float so a 3-tile forest still pays
## out on schedule instead of rounding to nothing every frame.
var _pending: float = 0.0

var _grid: WorldGrid = null


func attach(grid: WorldGrid) -> void:
	_grid = grid


func get_wood() -> int:
	return _wood


func can_afford(amount: int) -> bool:
	return amount <= _wood


## Spends `amount` if it is affordable. Returns false and changes nothing otherwise — the
## caller's edit simply does not happen (Pillar 1: no fail state, no punishment).
func spend(amount: int) -> bool:
	if amount < 0:
		return false
	if amount > _wood:
		return false
	if amount == 0:
		return true
	_wood -= amount
	wood_changed.emit(_wood)
	return true


func add(amount: int) -> void:
	if amount <= 0:
		return
	_wood += amount
	wood_changed.emit(_wood)


## Resets the balance. For New Game and (later) save load, not for gameplay.
func reset(amount: int = STARTING_WOOD) -> void:
	_wood = amount
	_pending = 0.0
	wood_changed.emit(_wood)


func _process(delta: float) -> void:
	tick(delta)


## Advances passive accrual. Public so a headless test can drive 60 s in one call instead
## of waiting for real frames.
##
## Reads the forest-tile count off the grid, which maintains it incrementally — the economy
## never scans the world, and a world with no forest does no work at all.
##
## THE THROTTLE IS SAMPLED ONCE PER CALL, not integrated across the span. At frame deltas the
## distinction does not exist; it only shows up in a headless test that drives a single
## enormous `delta` ACROSS `THROTTLE_THRESHOLD_WOOD`, which pays the pre-crossing rate for the
## whole span. Sub-stepping that away would buy a test-only exactness at a per-frame cost in
## the real game, so the seam is documented instead: a suite measuring throttled accrual
## starts the ledger already above the threshold (`reset(THROTTLE_THRESHOLD_WOOD)`).
func tick(delta: float) -> void:
	if _grid == null:
		return
	var forest_tiles: int = _grid.forest_tile_count()
	if forest_tiles <= 0:
		return
	_pending += _accrual_gain(forest_tiles, delta)
	if _pending < 1.0:
		return
	var whole: int = int(floor(_pending))
	_pending -= float(whole)
	add(whole)


## The Wood accrued over `delta`, at the current balance. The whole throttle is this function:
## ONE integer comparison per tick — no timer, no queue, no scan, and strictly less work than
## before whenever it binds, since `_pending` then crosses 1.0 far less often.
## `forest_tile_count()` is already maintained incrementally by `WorldGrid`, so a world with a
## thousand Forest tiles costs exactly what a world with three does.
##
## RETURNS A GAIN, NOT A RATE, AND THE UNTHROTTLED EXPRESSION IS BYTE-FOR-BYTE THE ORIGINAL
## ONE. Factoring it as `(tiles / 60.0) * delta` is algebraically identical and numerically is
## not: dividing first rounds once more, and the error accumulates across a carry until a
## 10-tile forest pays 9 Wood over six 10 s ticks instead of 10. That is a real assertion in
## `test_economy_rules.gd`, and it caught exactly this. Multiply first.
##
## `minf`, NOT A BRANCH THAT REPLACES THE GAIN: the throttle may only ever SLOW accrual. A
## single Forest tile already pays 1 Wood per 60 s, which is the throttled rate exactly — an
## unguarded replacement would hand a one-tile forest at 1 200 Wood the same income as a
## hundred-tile one, and (were the two constants ever tuned apart) could pay a small forest
## MORE for being rich. Taking the minimum makes "the cap never speeds anything up" a property
## of the code rather than of the two constants happening to be equal today.
func _accrual_gain(forest_tiles: int, delta: float) -> float:
	var gain: float = float(forest_tiles) * delta / SECONDS_PER_WOOD_PER_FOREST_TILE
	if _wood >= THROTTLE_THRESHOLD_WOOD:
		return minf(gain, delta / THROTTLED_SECONDS_PER_WOOD)
	return gain
