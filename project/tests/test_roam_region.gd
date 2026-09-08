extends QATestCase
## TERRAIN-AWARE ROAMING (game-design/roaming.md). A resident may only walk where its species
## belongs, and that area GROWS as the player paints more of the terrain it likes.
##
## THE FIXTURE IDIOM: `build(TerrainDefinition.load_all(), W, H)` with no mix fills everything
## with `wild_grass`, whose `emitted_tags` is deliberately empty. So a fresh grid qualifies
## NOTHING and every region below is built out of terrain the test painted itself. That makes
## each check state its own preconditions instead of inheriting them from world generation.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_roam_region.gd

const HOME := Vector2i(5, 5)
const RADIUS: int = 6

var _grid: WorldGrid = null
var _navigation: WorldNavigation = null


## A grid of `wild_grass` (no tags, so nothing qualifies) with `grass` painted over `rect`.
func _grid_with_grass(rect: Rect2i) -> WorldGrid:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 16, 16)
	root.add_child(grid)
	for x in range(rect.position.x, rect.end.x):
		for z in range(rect.position.y, rect.end.y):
			grid.set_terrain(x, z, "grass")
	return grid


func _grass_mask() -> int:
	return WorldGrid.tags_mask(["open_grass"] as Array[String])


func _initialize() -> void:
	begin("roam region")
	_navigation = WorldNavigation.new()

	_check_liked_tiles_are_included()
	_check_adjacent_tiles_are_included()
	_check_unliked_tiles_are_excluded()
	_check_blocked_tiles_are_excluded()
	_check_region_stays_within_radius()
	_check_region_is_contiguous()
	_check_home_is_always_present()
	_check_small_region_is_not_usable()
	_check_picked_points_land_inside_the_region()
	_check_region_grows_when_liked_terrain_is_painted()
	_check_an_untouched_world_never_rebuilds()
	_check_den_reservation_invalidates_the_region()
	_check_null_navigation_treats_everything_as_walkable()
	_check_points_are_biased_away_from_threats()
	_check_roamer_uses_the_region()

	_navigation.free_navigation()
	finish()


func _check_liked_tiles_are_included() -> void:
	var grid := _grid_with_grass(Rect2i(3, 3, 5, 5))
	var region := RoamRegion.new(grid, _navigation, HOME, _grass_mask(), RADIUS)
	check(region.has_tile(Vector2i(4, 4)), "a liked tile inside the patch is in the region", "")
	check(region.tile_count() >= 25, "the whole painted patch is reachable",
		"only %d tiles" % region.tile_count())
	grid.queue_free()


func _check_adjacent_tiles_are_included() -> void:
	# One grass tile beside home. The tile on its far side is NOT grass, but touches grass,
	# so the adjacency half of the predicate must let it in (roaming.md §3.2 — this is what
	# puts a fox on the forest fringe instead of leaving it with nowhere to go).
	var grid := _grid_with_grass(Rect2i(5, 5, 1, 1))
	var region := RoamRegion.new(grid, _navigation, HOME, _grass_mask(), RADIUS)
	check(region.has_tile(Vector2i(6, 5)),
		"a tile that merely TOUCHES liked terrain is in the region", "")
	grid.queue_free()


func _check_unliked_tiles_are_excluded() -> void:
	var grid := _grid_with_grass(Rect2i(5, 5, 1, 1))
	var region := RoamRegion.new(grid, _navigation, HOME, _grass_mask(), RADIUS)
	check(not region.has_tile(Vector2i(8, 5)),
		"a tile neither liked nor touching liked terrain is excluded", "")
	grid.queue_free()


func _check_blocked_tiles_are_excluded() -> void:
	# Forest emits `forest` and sets blocks_movement. Under a `open_grass` mask it is not
	# liked anyway, so paint grass around it and assert the BLOCK is what keeps it out.
	var grid := _grid_with_grass(Rect2i(3, 3, 5, 5))
	grid.set_terrain(6, 5, "forest")
	var region := RoamRegion.new(grid, _navigation, HOME, _grass_mask(), RADIUS)
	check(not region.has_tile(Vector2i(6, 5)),
		"a blocked tile is excluded even while surrounded by liked terrain", "")
	grid.queue_free()


func _check_region_stays_within_radius() -> void:
	var grid := _grid_with_grass(Rect2i(0, 0, 16, 16))
	var region := RoamRegion.new(grid, _navigation, HOME, _grass_mask(), RADIUS)
	var breaches: int = 0
	for tile: Vector2 in region.tiles():
		if Vector2i(int(tile.x), int(tile.y)).distance_squared_to(HOME) > RADIUS * RADIUS:
			breaches += 1
	check_eq(breaches, 0, "no region tile lies outside the radius")
	grid.queue_free()


func _check_region_is_contiguous() -> void:
	# Two grass patches separated by a wide band of wild_grass. Only the one containing home
	# may appear: the fill crosses qualifying tiles only, which is what makes every point in
	# the region reachable on foot (roaming.md §3.3).
	#
	# The gap must be at least 3 empty columns: under §4.2's predicate the column right next
	# to EACH patch already qualifies as fringe (touches a liked tile), so a 2-column gap has
	# both its columns independently qualify and, being adjacent to each other, bridge straight
	# through. A middle column with a non-qualifying neighbour on both sides is what actually
	# breaks the fill.
	var grid := _grid_with_grass(Rect2i(4, 4, 3, 3))
	for x in range(10, 13):
		for z in range(4, 7):
			grid.set_terrain(x, z, "grass")
	var region := RoamRegion.new(grid, _navigation, HOME, _grass_mask(), RADIUS)
	check(region.has_tile(Vector2i(5, 5)), "the home patch is in the region", "")
	check(not region.has_tile(Vector2i(10, 5)),
		"a disconnected patch of liked terrain is NOT in the region", "")
	grid.queue_free()


func _check_home_is_always_present() -> void:
	# A den tile carries a navigation reservation, so home is BLOCKED. The resident still
	# stands on it, so it must be in its own region regardless (roaming.md §4.3).
	var grid := _grid_with_grass(Rect2i(3, 3, 5, 5))
	_navigation.set_den_tile_blocked(HOME, true)
	var region := RoamRegion.new(grid, _navigation, HOME, _grass_mask(), RADIUS)
	check(region.has_tile(HOME), "the home tile is in the region even when blocked", "")
	_navigation.set_den_tile_blocked(HOME, false)
	grid.queue_free()


func _check_small_region_is_not_usable() -> void:
	# Nothing painted: only home qualifies. Too small to roam, so the roamer must fall back
	# to its disc rather than pin an animal to one tile (roaming.md §4.6).
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 16, 16)
	root.add_child(grid)
	var region := RoamRegion.new(grid, _navigation, HOME, _grass_mask(), RADIUS)
	check(region.tile_count() < RoamRegion.MIN_REGION_TILES,
		"an unpainted world yields a region below the usable floor",
		"got %d tiles" % region.tile_count())
	check(not region.is_usable(), "and it reports itself unusable", "")
	grid.queue_free()


func _check_picked_points_land_inside_the_region() -> void:
	var grid := _grid_with_grass(Rect2i(3, 3, 5, 5))
	var region := RoamRegion.new(grid, _navigation, HOME, _grass_mask(), RADIUS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260908
	var outside: int = 0
	for _i in 400:
		var point: Vector3 = region.pick_point(rng)
		if not region.has_tile(grid.world_to_tile(point)):
			outside += 1
	check_eq(outside, 0, "400 picked points all land on region tiles")
	grid.queue_free()


## THE GROWTH PROPERTY, stated the way the player feels it: paint more of what a species
## likes, and it roams there. This is the whole point of the feature (roaming.md §1).
func _check_region_grows_when_liked_terrain_is_painted() -> void:
	var grid := _grid_with_grass(Rect2i(4, 4, 3, 3))
	var region := RoamRegion.new(grid, _navigation, HOME, _grass_mask(), RADIUS)
	var before: int = region.tile_count()
	check(not region.has_tile(Vector2i(8, 5)), "the far tile is outside the region to start", "")

	for x in range(7, 10):
		grid.set_terrain(x, 5, "grass")

	check(region.tile_count() > before,
		"painting liked terrain grows the region without anyone invalidating it",
		"%d tiles before, %d after" % [before, region.tile_count()])
	check(region.has_tile(Vector2i(8, 5)), "and the newly painted ground is now roamable", "")
	grid.queue_free()


## THE OTHER HALF OF LAZY REBUILDING, and the one worth an exact work counter: a world nobody
## edited must do NO work at all. Asserted against `rebuilds_run` rather than against the tile
## count, because a rebuild that happened to produce the same tiles would pass a count check
## while quietly costing 0.3 ms per wander cycle forever.
func _check_an_untouched_world_never_rebuilds() -> void:
	var grid := _grid_with_grass(Rect2i(3, 3, 5, 5))
	var region := RoamRegion.new(grid, _navigation, HOME, _grass_mask(), RADIUS)
	region.tile_count()  # first read builds
	var after_first: int = region.rebuilds_run
	check(after_first > 0, "the first read builds the region", "")

	for _i in 50:
		region.tile_count()
	check_eq(region.rebuilds_run, after_first,
		"50 reads of an unedited world cost zero rebuilds")

	# `set_terrain` early-returns when the terrain is already what was asked for, so the
	# version does not move and this must STILL not rebuild.
	grid.set_terrain(4, 4, "grass")
	check_eq(region.rebuilds_run, after_first,
		"a no-op terrain write does not move the version, so nothing rebuilds")

	grid.set_terrain(4, 4, "meadow")
	region.tile_count()
	check(region.rebuilds_run > after_first, "a real edit does rebuild, once", "")
	grid.queue_free()


## A DEN RESERVATION MOVES THE PREDICATE WITHOUT MOVING `terrain_version`.
## `WorldNavigation.set_den_tile_blocked()` only calls `mark_dirty()` — it never bumps
## `WorldGrid.terrain_version`, which is the only thing the OLD `_ensure_fresh()` compared
## (roaming.md §4.4). This proves the region notices anyway, via `WorldNavigation.rebuilds_run`,
## with nobody calling `rebuild()` explicitly — `has_tile()` alone must pick it up.
func _check_den_reservation_invalidates_the_region() -> void:
	var grid := _grid_with_grass(Rect2i(3, 3, 5, 5))
	# Registers `grid` with `_navigation` so `set_den_tile_blocked()`'s `mark_dirty()` has
	# something to flush — same precondition `test_navigation_rebuild_coalescing.gd` relies on.
	# `RoamRegion` itself never reads this internal state; it always passes `grid` explicitly.
	_navigation.rebuild_from_grid(grid)
	var region := RoamRegion.new(grid, _navigation, HOME, _grass_mask(), RADIUS)
	var target := Vector2i(4, 4)
	check(region.has_tile(target), "the target tile starts in the region", "")

	_navigation.set_den_tile_blocked(target, true)
	# Forces the deferred navmesh flush synchronously, exactly as
	# `test_navigation_rebuild_coalescing.gd` does — no frame gets pumped under
	# `--headless --script`, so a read is what settles the pending edit.
	_navigation.find_path(grid.tile_to_world(0, 0), grid.tile_to_world(1, 1))

	check(not region.has_tile(target),
		"a den reservation removes the tile from the region with no explicit rebuild() call", "")

	_navigation.set_den_tile_blocked(target, false)
	_navigation.find_path(grid.tile_to_world(0, 0), grid.tile_to_world(1, 1))
	check(region.has_tile(target), "releasing the reservation restores the tile", "")
	grid.queue_free()


## `_qualifies()` treats a null `_navigation` as EVERYTHING walkable — correct as a degradation
## (the same idiom as a roamer with no `world_navigation`), but surprising enough to pin: a fox
## bound to a region with no navigation would roam inside the trees. Unreachable in production —
## `ResidentPresentation` always supplies a live `WorldNavigation` — but worth a test regardless.
func _check_null_navigation_treats_everything_as_walkable() -> void:
	# Same fixture as `_check_blocked_tiles_are_excluded()`, but with no `WorldNavigation` bound.
	var grid := _grid_with_grass(Rect2i(3, 3, 5, 5))
	grid.set_terrain(6, 5, "forest")
	var region := RoamRegion.new(grid, null, HOME, _grass_mask(), RADIUS)
	check(region.has_tile(Vector2i(6, 5)),
		"with no navigation bound, a normally-blocked tile is treated as walkable", "")
	grid.queue_free()


## Row 9's avoids distance-keeping (D-29) used to live in `ResidentRoamer._pick_angle()`,
## which biased the ANGLE drawn from a disc. With waypoints drawn from a tile list there is no
## angle being chosen, so the behaviour has to be re-expressed here or it is silently lost.
func _check_points_are_biased_away_from_threats() -> void:
	var grid := _grid_with_grass(Rect2i(0, 0, 16, 16))
	var region := RoamRegion.new(grid, _navigation, HOME, _grass_mask(), RADIUS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260908

	# A threat sitting well to the +X side of home. Points should skew to -X.
	var threat: Vector3 = grid.tile_to_world(HOME.x + 4, HOME.y)
	var home_world: Vector3 = grid.tile_to_world(HOME.x, HOME.y)
	var toward_threat: int = 0
	var away_from_threat: int = 0
	for _i in 400:
		var point: Vector3 = region.pick_point(rng, [threat] as Array[Vector3])
		if point.x > home_world.x:
			toward_threat += 1
		elif point.x < home_world.x:
			away_from_threat += 1
	check(away_from_threat > toward_threat * 2,
		"points skew away from a nearby avoided species",
		"%d away vs %d toward" % [away_from_threat, toward_threat])
	grid.queue_free()


## The roamer must actually USE the region, and must degrade to its disc without one — the
## same idiom the file already uses for a null `world_navigation` (roaming.md §4.6).
func _check_roamer_uses_the_region() -> void:
	var grid := _grid_with_grass(Rect2i(3, 3, 5, 5))
	var region := RoamRegion.new(grid, _navigation, HOME, _grass_mask(), RADIUS)
	var home_world: Vector3 = grid.tile_to_world(HOME.x, HOME.y)

	var node := Node3D.new()
	node.position = home_world
	root.add_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260908
	var roamer := ResidentRoamer.new(
		node, home_world, float(RADIUS), Rect2(), rng, "rabbit", [] as Array[String], null, region
	)

	var outside: int = 0
	for _i in 200:
		var waypoint: Vector3 = roamer._pick_waypoint()
		if not region.has_tile(grid.world_to_tile(waypoint)):
			outside += 1
	check_eq(outside, 0, "a region-equipped roamer only picks waypoints inside its region")

	# No region: the disc, exactly as before.
	var bare := ResidentRoamer.new(node, home_world, float(RADIUS), Rect2(), rng)
	check_eq(bare.wander_radius(), ResidentRoamer.WANDER_RADIUS_TILES,
		"a roamer with no region still reports the disc radius")
	grid.queue_free()
