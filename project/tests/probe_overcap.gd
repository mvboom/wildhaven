extends QATestCase
## THROWAWAY PROBE — minimal repro for the over-capacity finding.

func _init() -> void:
	begin("probe overcap")

	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 36, 36)
	var registry := HomeSiteRegistry.new()
	var arrivals := ArrivalQueue.new(20260728)
	var species := AnimalDefinition.new()
	species.id = "probe"
	species.display_name = "Probe"
	species.habitat_needs = ["cover"] as Array[String]
	species.tiles_per_individual = 4
	species.scout_radius = 8
	var sim := HabitatSimulation.new()
	sim.attach(grid, SpeciesRoster.new([species]), registry, arrivals, null)

	# Eight cover tiles in a row.
	var a := Vector2i(18, 18)
	for i in 8:
		grid.set_terrain(a.x + i, a.y, "rock")

	var site_a: HomeSite = registry.register(a, species.id, species.scout_radius)
	site_a.residents.append(null)
	site_a.residents.append(null)
	print("A at %s: cap=%d pop=%d" % [a, sim.capacity_at(a, species), sim.population_at(a, species)])

	# A prospective site strictly nearer to (most of) those tiles.
	var b := Vector2i(24, 18)
	print("B prospective at %s: cap=%d pop=%d" % [b, sim.capacity_at(b, species), sim.population_at(b, species)])

	# Register B (as an arrival would).
	var site_b: HomeSite = registry.register(b, species.id, species.scout_radius)
	site_b.residents.append(null)
	print("AFTER B registers:")
	print("  A: cap=%d pop=%d OVER=%s" % [
		sim.capacity_at(a, species), sim.population_at(a, species),
		str(sim.population_at(a, species) > sim.capacity_at(a, species))])
	print("  B: cap=%d pop=%d OVER=%s" % [
		sim.capacity_at(b, species), sim.population_at(b, species),
		str(sim.population_at(b, species) > sim.capacity_at(b, species))])

	# Does anything consume the fall?
	print("GentleDisplacement on A's settlement:")
	sim.free()
	grid.free()
	finish()
