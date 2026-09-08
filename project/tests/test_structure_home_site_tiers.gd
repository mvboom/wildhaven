extends QATestCase
## Task 9b — a Barn becomes a home site for a Cow, exactly the way a House becomes one for a
## Villager. Regression coverage for the gap that motivated this task.
##
## THE GAP: `HomeSite.serves()` and `HabitatSimulation._home_site_radius_for()` used to read
## the FLAT `AnimalDefinition.habitat_needs` array. The habitat-tiers branch moved every real
## species requirement into `tiers`, and Cow/Bull/Horse/Alpaca's retained legacy
## `habitat_needs` (`["cultivated", "open_grass"]` for Cow) names no building tag at all —
## their real gate (`barn`, `silo`, `stable`, `large_barn`) lives only inside `tiers`. Reading
## the flat array made `serves()` say no species needs a Barn, `_home_site_radius_for()`
## return 0, and `_sync_structure_site()` refuse to register the Barn as a home site at all.
## Villager/House happened to keep working by accident: Human's flat `habitat_needs` still
## happens to contain `"house"` even though its real gate also moved into `tiers`
## (`human.tres`) — which is exactly why this defect was invisible to a villager-only test.
##
## Both checks below drive the SAME path: `WorldGrid.set_building()` to place the building,
## then `HabitatSimulation.on_building_changed()` — the real trigger 2 — to run
## `_sync_structure_site()`. Nothing here calls `serves()` or `_home_site_radius_for()`
## directly; the whole real path is exercised the way `test_tile_exclusivity.gd` and
## `test_group_arrivals.gd` build their fixtures.
##
## Run:
##   bash scripts/run-tests.sh structure_home_site_tiers

const BARN_PATH: String = "res://data/buildings/barn.tres"
const HOUSE_PATH: String = "res://data/buildings/house.tres"
const COW_PATH: String = "res://data/animals/cow.tres"
const HUMAN_PATH: String = "res://data/animals/human.tres"

const ORIGIN := Vector2i(10, 10)
const GRID_SIZE: int = 30


func _init() -> void:
	begin("structure home site — tier-aware (task 9b)")

	_check_barn_becomes_a_home_site_for_cow()
	_check_house_still_becomes_a_home_site_for_villager()
	_check_radius_follows_the_matching_tiers_max_radius_not_just_scout_radius()
	_check_a_building_nobodys_tiers_gate_on_registers_no_site()

	finish()


## THE LOAD-BEARING CHECK. Before this task's fix, this failed: `_home_site_radius_for()`
## returned 0 (Cow's flat `habitat_needs` names no building tag), `_sync_structure_site()`
## bailed on "this building is nobody's habitat", and no site was ever registered here.
func _check_barn_becomes_a_home_site_for_cow() -> void:
	var fixture: Dictionary = _fixture(BARN_PATH, COW_PATH)
	var grid: WorldGrid = fixture["grid"]
	var sim: HabitatSimulation = fixture["sim"]
	var registry: HomeSiteRegistry = fixture["registry"]
	var building: PlaceableDefinition = fixture["building"]
	var species: AnimalDefinition = fixture["species"]

	check(building.emitted_tags.has("barn"),
		"SETUP: the real Barn really emits `barn` (the fixture's own precondition)")
	check(_matches_a_tier_need(species, "barn"),
		"SETUP: the real Cow really gates a tier on `barn` (the fixture's own precondition)")

	check(grid.set_building(ORIGIN, building), "the Barn is placed on the grid")
	sim.on_building_changed(ORIGIN)

	check(registry.any_site_at(ORIGIN),
		"A BARN BECOMES A HOME SITE the moment it is placed — same as a House — "
		+ "not only once a Cow has actually moved in")
	var site: HomeSite = registry.vacant_site_at(ORIGIN)
	check(site != null, "...and that site is vacant, ready for a Cow to claim")
	if site == null:
		_teardown(fixture)
		return
	check(site.is_structure(), "...and it is a STRUCTURE site (carries the Barn's emitted tags)")
	check(site.serves(species),
		"...and the Barn genuinely SERVES the Cow — `serves()` reads through `effective_tiers()`, "
		+ "not the flat `habitat_needs` that names no building tag at all")
	check(site.radius > 0,
		"...with a real, positive radius — the exact value the old flat-field read as 0")

	_teardown(fixture)


## THE COMPARISON CASE: the House/Villager pairing that never broke, run through the exact
## same fixture shape, so a reviewer can see both outcomes side by side rather than trust
## that the Barn case above is the only one exercised.
func _check_house_still_becomes_a_home_site_for_villager() -> void:
	var fixture: Dictionary = _fixture(HOUSE_PATH, HUMAN_PATH)
	var grid: WorldGrid = fixture["grid"]
	var sim: HabitatSimulation = fixture["sim"]
	var registry: HomeSiteRegistry = fixture["registry"]
	var building: PlaceableDefinition = fixture["building"]
	var species: AnimalDefinition = fixture["species"]

	check(grid.set_building(ORIGIN, building), "the House is placed on the grid")
	sim.on_building_changed(ORIGIN)

	check(registry.any_site_at(ORIGIN), "a House becomes a home site the moment it is placed")
	var site: HomeSite = registry.vacant_site_at(ORIGIN)
	check(site != null and site.serves(species), "...and the House serves the Villager")

	_teardown(fixture)


## THE RADIUS RULE, ISOLATED. A synthetic species whose matching tier's need names an
## EXPLICIT radius wider than the species' own `scout_radius` — proving
## `_home_site_radius_for()` reads `HabitatTier.max_radius()` (which can diverge from
## `scout_radius`) and not just `scout_radius` itself.
func _check_radius_follows_the_matching_tiers_max_radius_not_just_scout_radius() -> void:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), GRID_SIZE, GRID_SIZE)

	var building := PlaceableDefinition.new()
	building.id = "stable"
	building.display_name = "Stable"
	building.footprint = Vector2i(1, 1)
	building.emitted_tags = ["built", "stable"] as Array[String]

	var species := AnimalDefinition.new()
	species.id = "pony"
	species.display_name = "Pony"
	species.scout_radius = 4  # deliberately NARROWER than the need's own radius below
	var need := HabitatNeed.new()
	need.tag = "stable"
	need.radius = 10  # explicit, inside HabitatNeed's 2-16 band, and > scout_radius (4)
	need.tiles_per_individual = HabitatNeed.GATE_ONLY
	var tier := HabitatTier.new()
	tier.id = "stabled"
	tier.needs = [need] as Array[HabitatNeed]
	tier.max_individuals = 2
	species.tiers = [tier] as Array[HabitatTier]

	var registry := HomeSiteRegistry.new()
	var sim := HabitatSimulation.new()
	var arrivals := ArrivalQueue.new(1)
	var residents_root := Node3D.new()
	sim.attach(grid, SpeciesRoster.new([species]), registry, arrivals, residents_root)

	check(grid.set_building(ORIGIN, building), "the synthetic Stable is placed")
	sim.on_building_changed(ORIGIN)

	var site: HomeSite = registry.vacant_site_at(ORIGIN)
	check(site != null, "the Stable registers a home site for Pony")
	if site != null:
		check_eq(site.radius, 10,
			"the site's radius is the NEED's explicit radius (10), not the narrower "
			+ "`scout_radius` (4) — proving `_home_site_radius_for()` reads "
			+ "`HabitatTier.max_radius()`, not a bare `species.scout_radius` lookup")

	sim.free()
	grid.free()
	residents_root.free()


## THE NEGATIVE CONTROL. A building whose tags match no species' tier at all must register no
## site — `_home_site_radius_for()` returning 0 must still gate `_sync_structure_site()`
## exactly as before this fix, so a shed or fence never silently becomes somebody's home.
func _check_a_building_nobodys_tiers_gate_on_registers_no_site() -> void:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), GRID_SIZE, GRID_SIZE)

	var building := PlaceableDefinition.new()
	building.id = "fence"
	building.display_name = "Fence"
	building.footprint = Vector2i(1, 1)
	building.emitted_tags = ["built", "fence"] as Array[String]

	var species := AnimalDefinition.new()
	species.id = "deer"
	species.display_name = "Deer"
	species.scout_radius = 6
	var need := HabitatNeed.new()
	need.tag = "forest"
	need.tiles_per_individual = 4
	var tier := HabitatTier.new()
	tier.id = "herd"
	tier.needs = [need] as Array[HabitatNeed]
	tier.max_individuals = 4
	species.tiers = [tier] as Array[HabitatTier]

	var registry := HomeSiteRegistry.new()
	var sim := HabitatSimulation.new()
	var arrivals := ArrivalQueue.new(1)
	var residents_root := Node3D.new()
	sim.attach(grid, SpeciesRoster.new([species]), registry, arrivals, residents_root)

	check(grid.set_building(ORIGIN, building), "the Fence is placed")
	sim.on_building_changed(ORIGIN)

	check_eq(registry.any_site_at(ORIGIN), false,
		"a building nobody's tiers gate on registers NO home site at all")

	sim.free()
	grid.free()
	residents_root.free()


# --- helpers --------------------------------------------------------------------------------

func _matches_a_tier_need(species: AnimalDefinition, tag: String) -> bool:
	for tier: HabitatTier in species.effective_tiers():
		for need: HabitatNeed in tier.needs:
			if need.tag == tag:
				return true
	return false


## A real grid + registry + simulation, loading the NAMED real `.tres` building and species
## through the ordinary `load()` path — same convention `test_gentle_displacement.gd`'s
## real-world sections use for its House/Villager fixture.
func _fixture(building_path: String, species_path: String) -> Dictionary:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), GRID_SIZE, GRID_SIZE)

	var building: PlaceableDefinition = load(building_path) as PlaceableDefinition
	var species: AnimalDefinition = load(species_path) as AnimalDefinition

	var registry := HomeSiteRegistry.new()
	var sim := HabitatSimulation.new()
	var arrivals := ArrivalQueue.new(1)
	var residents_root := Node3D.new()
	sim.attach(grid, SpeciesRoster.new([species]), registry, arrivals, residents_root)

	return {
		"grid": grid, "sim": sim, "registry": registry, "arrivals": arrivals,
		"building": building, "species": species, "residents": residents_root,
	}


func _teardown(fixture: Dictionary) -> void:
	(fixture["sim"] as HabitatSimulation).free()
	(fixture["grid"] as WorldGrid).free()
	(fixture["residents"] as Node3D).free()
