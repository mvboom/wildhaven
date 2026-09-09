extends QATestCase
## THE FOOTPRINT IS ONE HOME (2026-09-08). Regression coverage for the defect that put a den
## prop beside a Farmhouse and seated eleven villagers in a house built for four.
##
## THE GAP. `WorldGrid.get_tile_tags()` emits a building's tags at its CENTRE tile (the
## 2026-09-08 "one building emits once" ruling), while `HabitatSimulation._sync_structure_site()`
## registers the building's home site at its ORIGIN. For a 2x2 those are the same tile and
## nothing showed; for the 3x3 Farmhouse and Large Barn they are not, and two tile-EXACT
## lookups then asked the wrong tile:
##
##   * `CapacityEvaluator._tile_counts_for()`'s structure shield checked
##     `structure_site_at(tile)`, which is null at the centre tile where `large_house`
##     actually lives — so any plain field tile in range counted the Farmhouse's own gate
##     and founded a WILD human home site, which gets a den (`ResidentPresentation`
##     spawns one for every non-structure site).
##   * `HabitatSimulation._site_for()` resolved a site only at the exact origin, so the
##     eight other footprint tiles each looked like virgin ground and registered sites of
##     their own.
##
## Measured before the fix, one Farmhouse at (24,24) with fields around it: three human sites
## (pop 4 + 3 + 4), three dens, and pig and pug sites squatting on the building's own tiles.
##
## Run:
##   bash scripts/run-tests.sh footprint_home_site

const FARMHOUSE_PATH: String = "res://data/buildings/farmhouse.tres"
const HOUSE_PATH: String = "res://data/buildings/house.tres"
const HUMAN_PATH: String = "res://data/animals/human.tres"

const ORIGIN := Vector2i(12, 12)
const GRID_SIZE: int = 30


func _init() -> void:
	begin("footprint home site — one building, one home (2026-09-08)")

	_check_anchor_maps_every_footprint_tile_to_the_origin()
	_check_a_field_tile_cannot_read_a_farmhouses_gate()
	_check_the_farmhouse_itself_still_qualifies_from_any_of_its_tiles()
	_check_one_farmhouse_registers_one_structure_site_and_no_den()
	_check_a_species_that_cannot_claim_the_building_gets_no_site_on_it()

	finish()


## THE PRIMITIVE the two fixes are built on. A footprint tile answers with the building's
## anchor; a bare tile answers with itself; an out-of-bounds tile answers with itself rather
## than the Vector2i(-1, -1) `get_building_origin()` returns, so a caller can pass the result
## straight to a registry lookup.
func _check_anchor_maps_every_footprint_tile_to_the_origin() -> void:
	var grid: WorldGrid = _grid()
	var farmhouse: PlaceableDefinition = load(FARMHOUSE_PATH) as PlaceableDefinition

	check_eq(farmhouse.footprint, Vector2i(3, 3),
		"SETUP: the real Farmhouse really is 3x3 — the case where centre != origin")
	check(grid.set_building(ORIGIN, farmhouse), "the Farmhouse is placed")

	var all_anchored: bool = true
	for dx in 3:
		for dz in 3:
			var tile: Vector2i = ORIGIN + Vector2i(dx, dz)
			if grid.home_site_anchor(tile.x, tile.y) != ORIGIN:
				all_anchored = false
	check(all_anchored,
		"EVERY ONE of the Farmhouse's nine tiles anchors to its origin — including the "
		+ "centre tile, which is where its `large_house` tag is actually emitted")

	var bare := Vector2i(2, 2)
	check_eq(grid.home_site_anchor(bare.x, bare.y), bare,
		"a tile with no building anchors to itself, so wild sites are unaffected")
	check_eq(grid.home_site_anchor(-1, -1), Vector2i(-1, -1),
		"an out-of-bounds tile anchors to itself, not to `get_building_origin()`'s sentinel")

	grid.free()


## THE LOAD-BEARING CHECK. Before the fix this field tile read capacity 1 and founded a wild
## human site — a family living in a furrow, with a den beside it — because the shield in
## `_tile_counts_for()` was looking at the origin while `large_house` sat on the centre.
func _check_a_field_tile_cannot_read_a_farmhouses_gate() -> void:
	var fixture: Dictionary = _fixture(FARMHOUSE_PATH)
	var grid: WorldGrid = fixture["grid"]
	var sim: HabitatSimulation = fixture["sim"]
	var human: AnimalDefinition = fixture["species"]

	sim.on_building_changed(ORIGIN)
	_sow_fields(grid, sim)

	var field := Vector2i(ORIGIN.x + 1, ORIGIN.y + 4)
	check_eq(grid.get_building(field.x, field.y), null,
		"SETUP: the tile under test is plain cultivated ground, off the footprint")
	check_eq(sim.capacity_at(field, human), 0,
		"a field tile beside the Farmhouse supports NO villager — a building's gate is "
		+ "readable only by a candidate that can claim the building itself")

	_teardown(fixture)


## THE OTHER HALF, and the reason the fix is an anchor rather than a blanket refusal: the
## Farmhouse must still be a home. Every one of its own tiles has to answer with the same
## site and the same capacity, because which footprint tile the dirty queue happens to
## evaluate is an implementation detail the player never sees.
func _check_the_farmhouse_itself_still_qualifies_from_any_of_its_tiles() -> void:
	var fixture: Dictionary = _fixture(FARMHOUSE_PATH)
	var grid: WorldGrid = fixture["grid"]
	var sim: HabitatSimulation = fixture["sim"]
	var human: AnimalDefinition = fixture["species"]

	sim.on_building_changed(ORIGIN)
	_sow_fields(grid, sim)

	var origin_capacity: int = sim.capacity_at(ORIGIN, human)
	check(origin_capacity >= 1,
		"the Farmhouse itself still houses a family",
		"capacity at the origin = %d" % origin_capacity)

	var uniform: bool = true
	for dx in 3:
		for dz in 3:
			var tile: Vector2i = ORIGIN + Vector2i(dx, dz)
			if sim.capacity_at(tile, human) != origin_capacity:
				uniform = false
	check(uniform,
		"...and all nine of its tiles report that SAME capacity, because all nine resolve "
		+ "to the one home site rather than to nine prospective candidates")

	_teardown(fixture)


## END TO END, through the real triggers and the real arrival queue: one Farmhouse, one home
## site, and it is a STRUCTURE site — which is precisely what `ResidentPresentation` reads to
## decide a villager gets no den.
func _check_one_farmhouse_registers_one_structure_site_and_no_den() -> void:
	var fixture: Dictionary = _fixture(FARMHOUSE_PATH)
	var grid: WorldGrid = fixture["grid"]
	var sim: HabitatSimulation = fixture["sim"]
	var registry: HomeSiteRegistry = fixture["registry"]

	sim.on_building_changed(ORIGIN)
	_sow_fields(grid, sim)
	_settle(sim)

	var human_sites: Array[HomeSite] = []
	for site: HomeSite in registry.sites():
		if site.species_id == "human" or site.is_structure():
			human_sites.append(site)

	check_eq(human_sites.size(), 1,
		"one Farmhouse produces exactly ONE human home site — it produced three before "
		+ "this fix, one per footprint tile the dirty queue reached")
	if human_sites.size() == 1:
		var site: HomeSite = human_sites[0]
		check_eq(site.position, ORIGIN, "...anchored at the Farmhouse's own origin")
		check(site.is_structure(),
			"...and it is a STRUCTURE site, which is the one and only thing "
			+ "`ResidentPresentation._spawn_home_prop()` checks before spawning a den")
		check(site.population() >= 1, "...with the family actually moved in",
			"population = %d" % site.population())

	_teardown(fixture)


## THE SQUATTER CASE. A species with no use for the building still qualified ON its footprint
## when something else in range fed its needs — observed as pig and pug sites standing inside
## the Farmhouse, each with its own den. A candidate that resolves no home site cannot found
## one on ground a building already occupies.
func _check_a_species_that_cannot_claim_the_building_gets_no_site_on_it() -> void:
	var fixture: Dictionary = _fixture(HOUSE_PATH)
	var grid: WorldGrid = fixture["grid"]
	var sim: HabitatSimulation = fixture["sim"]

	sim.on_building_changed(ORIGIN)
	_sow_fields(grid, sim)

	# Gates on `cultivated` alone, so the fields sown above satisfy it everywhere in range —
	# including on the House's tiles, which is the only thing under test here.
	var grazer := AnimalDefinition.new()
	grazer.id = "grazer"
	grazer.display_name = "Grazer"
	grazer.scout_radius = 6
	var need := HabitatNeed.new()
	need.tag = "cultivated"
	need.tiles_per_individual = 2
	var tier := HabitatTier.new()
	tier.id = "herd"
	tier.needs = [need] as Array[HabitatNeed]
	tier.max_individuals = 3
	grazer.tiers = [tier] as Array[HabitatTier]

	var free_tile := Vector2i(ORIGIN.x + 1, ORIGIN.y + 4)
	check(sim.capacity_at(free_tile, grazer) >= 1,
		"SETUP: the Grazer really does qualify on the open field beside the House")
	check_eq(sim.capacity_at(ORIGIN, grazer), 0,
		"...but reads 0 standing on the House, which is not its home — so it founds no "
		+ "wild site, and no den, on somebody else's floor")

	_teardown(fixture)


# --- helpers --------------------------------------------------------------------------------

func _grid() -> WorldGrid:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), GRID_SIZE, GRID_SIZE)
	return grid


## A real grid + registry + simulation around the named real building and the real Villager,
## same shape as `test_structure_home_site_tiers.gd`'s fixture.
func _fixture(building_path: String) -> Dictionary:
	var grid: WorldGrid = _grid()
	var building: PlaceableDefinition = load(building_path) as PlaceableDefinition
	var species: AnimalDefinition = load(HUMAN_PATH) as AnimalDefinition

	var registry := HomeSiteRegistry.new()
	var sim := HabitatSimulation.new()
	var arrivals := ArrivalQueue.new(1)
	var residents_root := Node3D.new()
	sim.attach(grid, SpeciesRoster.new([species]), registry, arrivals, residents_root)
	grid.set_building(ORIGIN, building)

	return {
		"grid": grid, "sim": sim, "registry": registry, "arrivals": arrivals,
		"building": building, "species": species, "residents": residents_root,
	}


## Enough cultivated ground, clear of the footprint, for the `family` tier's divisor.
func _sow_fields(grid: WorldGrid, sim: HabitatSimulation) -> void:
	for dx in range(-2, 5):
		for dz in range(4, 7):
			var tile := ORIGIN + Vector2i(dx, dz)
			if grid.set_terrain(tile.x, tile.y, "cultivated_field"):
				sim.on_terraform(tile)


## Drains the dirty queue and lets every queued arrival come due, twice — a neighbourhood
## with room beyond the first group fills gradually, one landing per pass.
func _settle(sim: HabitatSimulation) -> void:
	for _pass in 2:
		for _i in 200:
			sim.tick(0.0)
		sim.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)


func _teardown(fixture: Dictionary) -> void:
	(fixture["sim"] as HabitatSimulation).free()
	(fixture["grid"] as WorldGrid).free()
	(fixture["residents"] as Node3D).free()
