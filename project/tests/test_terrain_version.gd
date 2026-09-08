extends QATestCase
## THE INVALIDATION SIGNAL for `RoamRegion` (game-design/roaming.md §4.4).
##
## `terrain_version` exists so a cached view of the world can tell, in one integer compare,
## that it is stale. Its whole value is that NO WRITER CAN BYPASS IT — which is why the bump
## lives in `_refresh_tag_mask()`, the one function every tile writer already calls. These
## checks are that claim, one writer at a time.

func _initialize() -> void:
	begin("terrain version")

	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 10, 10)
	root.add_child(grid)

	var after_build: int = grid.terrain_version

	grid.set_terrain(2, 2, "grass")
	check(grid.terrain_version > after_build, "set_terrain bumps the version", "")

	var after_terrain: int = grid.terrain_version
	grid.set_terrain(2, 2, "grass")
	check_eq(grid.terrain_version, after_terrain,
		"painting the SAME terrain again does not bump (set_terrain early-returns)")

	# Loaded directly rather than through a roster helper: `PlaceableDefinition` has NO
	# `load_all()` — that lives on `BuildingPlacement` — and a direct `load()` is what the
	# other suites in this repo do.
	var building: PlaceableDefinition = load("res://data/buildings/house.tres") as PlaceableDefinition
	check(building != null, "house.tres loads as a PlaceableDefinition", "")
	if building != null:
		grid.set_building(Vector2i(4, 4), building)
		check(grid.terrain_version > after_terrain, "set_building bumps the version", "")
		var after_building: int = grid.terrain_version
		grid.clear_building(Vector2i(4, 4))
		check(grid.terrain_version > after_building, "clear_building bumps the version", "")

	var before_grow: int = grid.terrain_version
	grid.grow(12, 12, 1)
	check(grid.terrain_version > before_grow, "grow bumps the version", "")

	# `build()`'s uniform-fill branch (empty mix, exercised above) and its mix-fill branch
	# both write `_tile_tag_masks` directly and share one bump after the `if`/`else` — this
	# is the mix branch's coverage.
	var before_mix_rebuild: int = grid.terrain_version
	grid.build(TerrainDefinition.load_all(), 10, 10, {"grass": 1.0})
	check(grid.terrain_version > before_mix_rebuild,
		"build() with a non-empty terrain mix bumps the version too", "")

	finish()
