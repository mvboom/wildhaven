class_name MistReveal
extends RefCounted
## Tier 1 row 13's decided numbers and its one pure function — D-38 (2026-08-09), CLOSED. Do
## not re-derive or re-propose these; see decisions.md -> D-38 and tier1-status.md row 13's
## `constants` cell, which quotes this file verbatim.
##
## THE WORLD CAP IS DELIBERATELY NOT REDECLARED HERE. D-38 ruled it identical to row 1's own
## `WorldRoot.MAX_SAVED_WORLD_TILES` ("decided together so the two constants cannot drift
## apart") — `WorldGrid.grow()` reads that one directly rather than this file carrying a second
## copy that could silently diverge from it.

## gdd.md -> World Structure: "build or terraform within ~2 tiles of the mist" — also spec.md
## Open Question #19. DECIDED 2026-08-09 (-> D-38).
const REVEAL_PROXIMITY_TILES: int = 2

## gdd.md only said "a few tiles deeper," with no baseline; spec.md #19 left it fully open.
## Set equal to `REVEAL_PROXIMITY_TILES` rather than a second, independent number — DECIDED
## 2026-08-09 (-> D-38).
const REVEAL_BAND_TILES: int = 2


## THE deterministic reveal function the row's invariant names verbatim: "a pure function of
## (world_seed, x, y)." In v1 it is a CONSTANT function — every newly revealed tile becomes
## `WorldGrid.START_TERRAIN_ID` (wild grass), full stop. That is not a missed opportunity for
## variety; D-22's inert-land invariant already rules out anything else. No other shipped
## terrain is guaranteed tag-inert on its own — plain `grass` alone hands Rabbit its entire
## `open_grass` requirement (D-22's own corrected history) — so wild grass is the only value
## this function may ever return without re-opening that defect.
##
## `world_seed`/`x`/`z` are accepted, not ignored by omission: they are what makes the
## contract ("the same edit at the same seed always reveals the same land") a checkable
## function signature today, and the one call site a future terrain-variety pass would extend.
## Unused for now — that is the honest state, not a stub pretending otherwise.
static func reveal_terrain_id(_world_seed: int, _x: int, _z: int) -> String:
	return WorldGrid.START_TERRAIN_ID
