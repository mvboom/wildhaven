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


## PLACEHOLDER / GDD baseline — the human owns this (Open Question #26). gdd.md -> Economy:
## "The starting stockpile is ~50 Wood (floor ~35, sized to the 1x1 House plus a small
## field) and deliberately not a buffer". Sized to cover the first-time nudge's suggested
## build only; pacing begins at the second build.
const STARTING_WOOD: int = 50

## PLACEHOLDER / GDD baseline — the human owns this (Open Question #8). gdd.md -> Economy
## names this "v1's most load-bearing constant": "~1 Wood per Forest tile per 60 s".
## Expressed as seconds-per-Wood-per-forest-tile so the rate reads exactly as the GDD
## states it, rather than as a derived fraction nobody can check against the document.
const SECONDS_PER_WOOD_PER_FOREST_TILE: float = 60.0


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
func tick(delta: float) -> void:
	if _grid == null:
		return
	var forest_tiles: int = _grid.forest_tile_count()
	if forest_tiles <= 0:
		return
	_pending += float(forest_tiles) * delta / SECONDS_PER_WOOD_PER_FOREST_TILE
	if _pending < 1.0:
		return
	var whole: int = int(floor(_pending))
	_pending -= float(whole)
	add(whole)
