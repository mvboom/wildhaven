class_name ResidentPicker
extends RefCounted
## **Which resident, if any, did the player just tap?** — resolved against LIVE positions.
##
## It exists because of the priority rule (gdd.md -> Inspect Mode): "an animal standing on a
## tappable tile always wins the tap — generous animal hitboxes beat ambiguous taps for young
## kids." That is a Pillar 3 invariant, and it is only true if the hitbox is where the animal
## actually is.
##
## THIS REPLACED ARRIVAL-TIME HIT-TESTING, and there is now exactly one hit-test in the build.
## The old `project/scripts/ui/resident_index.gd` built its list from the
## `resident_arrived(species_id, world_position)` signal and hit-tested the position captured at
## arrival — correct only while nobody moves. Once residents wandered, that list went stale on
## the first waypoint and left a ghost hitbox standing over the empty den. **That file is
## deleted**; `WorldRoot.resident_record_at()` is the query that replaced it, and it runs on this.
##
## The source of truth is `HomeSiteRegistry` — every settled resident node hangs off a
## `HomeSite`, so there is no second list to keep in sync and no way for one to drift.
##
## Hit-testing is in SCREEN SPACE, not world space, and deliberately so: "generous" has to mean
## generous *to the player's finger*, which is a pixel measurement. A far-zoom animal is a few
## pixels of world but still gets a full-size tap target.

## DECIDED 2026-07-28 (-> D-27 #3). The floor of the tap target, in pixels, however far out
## the camera is. Sized to the UI's own minimum hit target so an animal is never harder to hit
## than a button. (Carried across verbatim from the deleted `ResidentIndex.MIN_TAP_RADIUS_PIXELS`
## so there is one copy of it, not two. Kept unchanged by D-27 #3: the floor is for FAR zoom,
## where one tile is a handful of pixels, and that is exactly the case the cap below must not eat.)
const MIN_TAP_RADIUS_PIXELS: float = 44.0

## PLACEHOLDER — the human owns this. At close zoom the target grows with the animal: this
## fraction of one tile's on-screen width. A FEEL number — how generous the target is inside the
## structural bound below, which it can never exceed.
##
## **CURRENTLY PINNED AT THE BOUND, AND INERT (recorded 2026-08-02).** `_tap_radius()` takes
## `min(tile * 0.8, tile * MAX_TAP_RADIUS_TILE_FRACTION)`, and 0.8 > 0.5, so the cap binds at
## every zoom: this constant has NO effect on behaviour at its current value, and none at any
## value >= MAX_TAP_RADIUS_TILE_FRACTION. Read 0.8 as "as generous as the bound allows", not as
## a dial that is doing something.
##
## **Below the cap it is still not automatically live, because there are TWO gates, not one.**
## `MIN_TAP_RADIUS_PIXELS` is applied LAST, outside the min, so at far zoom the 44 px floor
## swallows the fraction even where the cap would have let it through: at a 50 px tile, fractions
## of 0.1 and 0.3 both return exactly 44 px. This constant only does something when
## `tile_pixels * fraction` clears BOTH the cap and the floor.
##
## Kept rather than collapsed into the cap, deliberately (human ruling, 2026-08-02): the bound is
## structural and the value inside it is taste, and merging them would leave nothing protecting
## the neighbouring tile if generosity were ever tuned back UP past one tile wide. Same shape as
## `ResidentRoamer`'s waypoint radius being clamped at construction to the home site's own radius.
const TAP_RADIUS_TILE_FRACTION: float = 0.8

## DECIDED 2026-08-02 (playtest gate). The structural cap: the tap target may
## never reach further than this fraction of a tile from the animal.
##
## **WHY IT EXISTS.** `TAP_RADIUS_TILE_FRACTION` is applied as a RADIUS, so 0.8 produced a
## target 1.6 tiles WIDE — wider than the tile the animal stands on. Measured at street zoom:
## 162.8 px of radius against a ~203 px tile. The consequence was a live conflict between two
## pillar invariants: a villager standing on its House won the tap on the ADJACENT field tile,
## so the floor's likeliest displacement was unreachable while the family was home —
## intermittently, because residents roam. The human ruled that **the priority rule is correct
## and its input was wrong**, rejecting the alternative (exempting the remove tool), because
## that would carve a mode-shaped hole in a Pillar 3 invariant to compensate for a sizing bug.
##
## 0.5 makes the target exactly one tile wide **wherever this cap is what binds**: an animal
## still wins every tap on its own tile, and never one on a neighbour's. That is the whole of
## the fix. **At far zoom the cap is not what binds** — `MIN_TAP_RADIUS_PIXELS` is applied last
## and is deliberately allowed to exceed a tile there, which is the only reason a far-zoom
## animal stays reachable at all. See the fraction's note above for the two-gate picture.
##
## **This is a separate constant from the fraction above on purpose**, and not a retune of it,
## for the same reason `ResidentRoamer`'s waypoint radius is clamped at construction to the
## home site's own radius: the bound is structural and the value inside it is taste. However the
## human tunes generosity DOWNWARD, the hitbox cannot grow back over the neighbouring tile
## **wherever this cap binds** — and upward it cannot move at all, because this cap is what
## binds today (see the fraction's own note above). **Where the 44 px floor binds instead, at
## far zoom, the target genuinely does exceed one tile — measured at ~3.7 tiles wide against a
## 23.5 px tile at full zoom-out — and that is the floor doing its job, not the cap failing.**
##
## **TUNE AGAINST THE RELATION, NOT AN ABSOLUTE.** The operative pixel radius is
## viewport-dependent — ui-engineer measured ~110 px in a real window against 64 px headless
## at the same zoom — so the meaningful quantity is tiles, which is what this is expressed in.
const MAX_TAP_RADIUS_TILE_FRACTION: float = 0.5

## DECIDED 2026-08-02 (playtest gate). Residents are anchored at ground level; the tap point is
## raised to roughly body-centre height so the target sits on the animal, not at its feet.
const BODY_CENTRE_HEIGHT: float = 0.45


## The nearest resident within its tap radius of `screen_position`, or `{}`.
##
## Returns `{ "node": Node3D, "species_id": String, "home_tile": Vector2i,
##            "world_position": Vector3 }`.
##
## Nearest-wins matters where a home site holds several individuals: the tap resolves to one of
## them deterministically instead of flickering between cards.
static func pick(
	registry: HomeSiteRegistry, screen_position: Vector2, camera: Camera3D
) -> Dictionary:
	if registry == null or camera == null or not camera.is_inside_tree():
		return {}
	var best: Dictionary = {}
	var best_distance: float = INF
	for site: HomeSite in registry.sites():
		for resident: Node3D in site.residents:
			if resident == null or not is_instance_valid(resident):
				continue
			var anchor: Vector3 = resident.global_position
			var target: Vector3 = anchor + Vector3(0.0, BODY_CENTRE_HEIGHT, 0.0)
			if camera.is_position_behind(target):
				continue
			var distance: float = camera.unproject_position(target).distance_to(screen_position)
			if distance > _tap_radius(anchor, camera) or distance >= best_distance:
				continue
			best_distance = distance
			best = {
				"node": resident,
				"species_id": site.species_id,
				"home_tile": site.position,
				"world_position": anchor,
			}
	return best


## The home site a resident node belongs to, or null. O(residents), which is fine: it runs on a
## tap, never per frame.
static func site_of(registry: HomeSiteRegistry, resident: Node) -> HomeSite:
	if registry == null or resident == null:
		return null
	for site: HomeSite in registry.sites():
		if site.residents.has(resident):
			return site
	return null


## The tap radius for a resident, measured by projecting a one-tile step next to it — so the
## radius tracks zoom exactly without this class knowing anything about the camera's maths.
##
## Three terms, and the ORDER of the last two is load-bearing: grow with zoom, cap at one
## tile wide, then floor. Flooring last is what keeps `MIN_TAP_RADIUS_PIXELS` a real floor at
## far zoom — capping after it would let a tiny on-screen tile pull the target back under 44 px
## and hand a far-zoom animal a hitbox smaller than a button.
static func _tap_radius(anchor: Vector3, camera: Camera3D) -> float:
	var here: Vector2 = camera.unproject_position(anchor)
	var one_tile_east: Vector2 = camera.unproject_position(anchor + Vector3(1.0, 0.0, 0.0))
	var tile_pixels: float = here.distance_to(one_tile_east)
	var grown: float = tile_pixels * TAP_RADIUS_TILE_FRACTION
	var capped: float = minf(grown, tile_pixels * MAX_TAP_RADIUS_TILE_FRACTION)
	return maxf(MIN_TAP_RADIUS_PIXELS, capped)
