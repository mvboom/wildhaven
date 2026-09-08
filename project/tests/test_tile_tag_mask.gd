extends QATestCase
## THE CACHE INVARIANT the capacity evaluator's speed rests on.
##
## `WorldGrid.tile_tag_mask()` is a cached bitmask of the same answer `get_tile_tags()`
## derives from scratch. The evaluator reads the cache once per tile, per tier, per species,
## and uses it to SKIP tiles entirely — so a stale mask is not a slow evaluation, it is a
## WRONG capacity, silently. `get_tile_tags()` stays the source of truth; this suite pins
## that the cache agrees with it after every kind of edit that can change a tile.
##
## The five writers are `build()`, `grow()`, `set_terrain()`, `set_building()` and
## `clear_building()`. Each is exercised below through the real public entry points a player
## drives, not by poking the array.
##
## Run:
##   bash scripts/run-tests.sh tile_tag_mask

const WORLD_PATH: String = "res://scenes/Main.tscn"


var _world: WorldRoot = null
var _setup_ok: bool = false


func _initialize() -> void:
	begin("tile tag mask cache")
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "Main.tscn loads"):
		finish()
		return
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		finish()
		return
	_world = node as WorldRoot
	root.add_child(_world)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_world.simulation.set_process(false)
	_world.presentation.set_process(false)
	var grid: WorldGrid = _world.grid

	_check_vocabulary_fits_the_mask()
	_check_agrees_everywhere(grid, "after build()")
	_check_a_paint_updates_the_mask(_world, grid)
	_check_a_building_suppresses_and_restores(_world, grid)
	_check_growth_keeps_both_halves_correct(_world, grid)
	_check_an_unknown_tag_is_never_silently_dropped()

	finish()
	return true


## Every vocabulary tag needs its own bit, and none may collide with the overflow bit.
func _check_vocabulary_fits_the_mask() -> void:
	var tags: PackedStringArray = AnimalDefinition.HABITAT_TAGS
	var seen: Dictionary = {}
	var collisions: int = 0
	for tag: String in tags:
		var bit: int = WorldGrid.tag_bit(tag)
		if bit == 0 or seen.has(bit) or bit == WorldGrid.UNKNOWN_TAG_BIT:
			collisions += 1
		seen[bit] = true
	check_eq(collisions, 0,
		"all %d vocabulary tags have a distinct bit, none colliding with UNKNOWN_TAG_BIT"
			% tags.size())
	check_eq(WorldGrid.tag_bit("not_a_real_tag"), 0,
		"a tag outside the vocabulary has no bit of its own")
	check(WorldGrid.tags_mask(["not_a_real_tag"]) == WorldGrid.UNKNOWN_TAG_BIT,
		"...and raises UNKNOWN_TAG_BIT instead, so it can never be silently uncountable")


## The whole-grid equivalence: cache == derivation, on every tile.
func _check_agrees_everywhere(grid: WorldGrid, when: String) -> void:
	var mismatches: int = 0
	var first: String = ""
	for z in grid.depth:
		for x in grid.width:
			var cached: int = grid.tile_tag_mask(x, z)
			var derived: int = WorldGrid.tags_mask(grid.get_tile_tags(x, z))
			if cached != derived:
				mismatches += 1
				if first == "":
					first = "(%d,%d): cached %d, derived %d" % [x, z, cached, derived]
	check(mismatches == 0,
		"the cache agrees with get_tile_tags() on all %d tiles %s"
			% [grid.width * grid.depth, when],
		first)


func _check_a_paint_updates_the_mask(world: WorldRoot, grid: WorldGrid) -> void:
	world.wood.reset(1000)
	var tile := Vector2i(5, 5)
	var before: int = grid.tile_tag_mask(tile.x, tile.y)
	if not check(world.paint_tile(tile.x, tile.y, "forest"), "SETUP: a tile can be painted forest"):
		return
	var after: int = grid.tile_tag_mask(tile.x, tile.y)
	check(after != before, "painting a tile changes its cached mask")
	check_eq(after, WorldGrid.tags_mask(grid.get_tile_tags(tile.x, tile.y)),
		"...and the new mask is exactly what get_tile_tags() now derives")
	check(after & WorldGrid.tag_bit("forest") != 0,
		"...and it carries the `forest` bit the terrain actually emits")
	_check_agrees_everywhere(grid, "after set_terrain()")


func _check_a_building_suppresses_and_restores(world: WorldRoot, grid: WorldGrid) -> void:
	world.wood.reset(1000)
	var tile := Vector2i(9, 9)
	world.paint_tile(tile.x, tile.y, "grass")
	var ground: int = grid.tile_tag_mask(tile.x, tile.y)
	var options: Array = world.placeable_options()
	if not check(not options.is_empty(), "SETUP: at least one placeable exists"):
		return
	var def: PlaceableDefinition = options[0] as PlaceableDefinition
	if not check(world.place_building(tile.x, tile.y, def.id), "SETUP: a building can be placed"):
		return
	# REWRITTEN 2026-09-08 for centre-tile emission (WorldGrid.get_tile_tags()). This assertion used
	# to read "a footprint tile's mask carries `built`", which was true of EVERY covered tile and was
	# exactly the bug: a tag count is a count of tiles, so an N-tile building contributed N copies of
	# its tags. One building now emits ONCE, at its centre tile; every other tile it covers is
	# occupied and terrain-suppressed but emits nothing. Pinned here in both directions, because the
	# whole point is that the two halves differ.
	var centre: Vector2i = tile + (def.footprint - Vector2i.ONE) / 2
	var built: int = grid.tile_tag_mask(centre.x, centre.y)
	check(built & WorldGrid.tag_bit("built") != 0,
		"the footprint's CENTRE tile carries `built` while occupied")
	check_eq(built, WorldGrid.tags_mask(grid.get_tile_tags(centre.x, centre.y)),
		"...and matches get_tile_tags(), which a footprint suppresses to the building's tags")
	for covered: Vector2i in WorldGrid.footprint_tiles(tile, def):
		if covered == centre:
			continue
		check_eq(grid.tile_tag_mask(covered.x, covered.y), 0,
			"...while every OTHER footprint tile %s emits nothing — one building, one emission"
				% covered)
	_check_agrees_everywhere(grid, "after set_building()")

	if not check(world.remove_at(tile.x, tile.y), "SETUP: the building can be removed"):
		return
	var restored: int = grid.tile_tag_mask(tile.x, tile.y)
	check_eq(restored, ground,
		"removing the building restores the ground's mask exactly — terrain is suppressed, "
		+ "never destroyed")
	_check_agrees_everywhere(grid, "after clear_building()")


func _check_growth_keeps_both_halves_correct(world: WorldRoot, grid: WorldGrid) -> void:
	var old_width: int = grid.width
	var old_depth: int = grid.depth
	# A tile with a non-default mask, so a lost carry-over would be visible rather than
	# coincidentally equal to the default.
	world.wood.reset(1000)
	world.paint_tile(2, 2, "forest")
	var marked: int = grid.tile_tag_mask(2, 2)
	check(marked & WorldGrid.tag_bit("forest") != 0, "SETUP: a marked tile inside the old bounds")

	var grown: Array[Vector2i] = grid.grow(old_width + 6, old_depth + 6, 12345)
	if not check(not grown.is_empty(), "SETUP: the grid actually grew"):
		return
	check_eq(grid.tile_tag_mask(2, 2), marked,
		"a carried-over tile keeps its mask across growth")
	_check_agrees_everywhere(grid, "after grow()")


## The regression this suite exists to prevent a second time: a tag outside the vocabulary
## has no bit, and must therefore fall back to the real tag array rather than count as zero.
func _check_an_unknown_tag_is_never_silently_dropped() -> void:
	var terrain := TerrainDefinition.new()
	terrain.id = "invented_ground"
	terrain.display_name = "Invented Ground"
	terrain.emitted_tags = ["definitely_not_a_vocabulary_tag"] as Array[String]

	var mask: int = WorldGrid.tags_mask(terrain.emitted_tags)
	check_eq(mask, WorldGrid.UNKNOWN_TAG_BIT,
		"a tile emitting only an out-of-vocabulary tag still raises UNKNOWN_TAG_BIT")
	check(not terrain.validate().is_empty(),
		"...and validate() still reports it, so the data error stays loud")

	# Mixed: one real tag and one invented one. Both must survive.
	var mixed: int = WorldGrid.tags_mask(["water", "invented"] as Array[String])
	check(mixed & WorldGrid.tag_bit("water") != 0, "a mixed tile keeps its real tag's bit")
	check(mixed & WorldGrid.UNKNOWN_TAG_BIT != 0, "...and still flags the unknown one")
