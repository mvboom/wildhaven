extends QATestCase
## The PUBLIC walkability predicate, which `RoamRegion` shares so a roam waypoint can never
## land somewhere `find_path()` will not go (game-design/roaming.md §4.2). Asserted against
## all four reasons a tile is blocked, because a predicate that agrees with `_tile_blocked()`
## on only three of them is a bug that shows up as animals standing inside trees.

func _initialize() -> void:
	begin("tile walkable")
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 10, 10)
	root.add_child(grid)
	var navigation := WorldNavigation.new()

	grid.set_terrain(1, 1, "grass")
	check(navigation.is_tile_walkable(grid, 1, 1), "plain grass is walkable", "")

	grid.set_terrain(2, 2, "forest")
	check(not navigation.is_tile_walkable(grid, 2, 2),
		"forest is not walkable (blocks_movement)", "")

	navigation.set_den_tile_blocked(Vector2i(3, 3), true)
	check(not navigation.is_tile_walkable(grid, 3, 3),
		"a den reservation is not walkable", "")

	# Loaded directly rather than through a roster helper: `PlaceableDefinition` has NO
	# `load_all()` — that lives on `BuildingPlacement` — and a direct `load()` is what the
	# other suites in this repo do.
	var building: PlaceableDefinition = load("res://data/buildings/house.tres") as PlaceableDefinition
	check(building != null, "house.tres loads as a PlaceableDefinition", "")
	if building != null:
		grid.set_building(Vector2i(4, 4), building)
		check(not navigation.is_tile_walkable(grid, 4, 4),
			"an occupied tile is not walkable (is_occupied)", "")

	check(not navigation.is_tile_walkable(grid, -1, 0), "out of bounds is not walkable", "")
	check(not navigation.is_tile_walkable(null, 1, 1), "a null grid is not walkable", "")

	navigation.free_navigation()
	grid.queue_free()
	finish()
