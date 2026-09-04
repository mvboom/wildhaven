extends QATestCase
## Group arrivals: a tier may land several individuals at once, and lands PARTIALLY when
## the land changed between enqueue and due time.
##
## `_check_partial_landing_arithmetic()` is a placeholder — it only pins `mini()`'s own
## behaviour, not this codebase's. `_check_partial_landing_lands_exactly_what_fits()` below is
## the real coverage: it drives `ArrivalQueue` + `HabitatSimulation` against a real
## `WorldGrid` + `HomeSiteRegistry` (the fixture pattern `test_tile_exclusivity.gd` and
## `test_resident_tags.gd` use) and asserts a group of 3 landing into room for 2 actually
## lands 2 residents, not 3 and not 0.
##
## Run:
##   bash scripts/run-tests.sh group_arrivals

func _init() -> void:
	begin("group arrivals")
	_check_count_defaults_to_one()
	_check_count_round_trips()
	_check_missing_count_restores_as_one()
	_check_partial_landing_arithmetic()
	_check_partial_landing_lands_exactly_what_fits()
	finish()


func _check_count_defaults_to_one() -> void:
	var queue := ArrivalQueue.new(1)
	queue.enqueue(Vector2i(3, 3), "fox")
	var saved: Array[Dictionary] = queue.to_save()
	check_eq(saved.size(), 1, "one entry queued")
	check_eq(int(saved[0].get("count", 1)), 1, "an unspecified group size is one")


func _check_count_round_trips() -> void:
	var queue := ArrivalQueue.new(1)
	queue.enqueue(Vector2i(5, 5), "deer", 3)
	var saved: Array[Dictionary] = queue.to_save()
	check_eq(int(saved[0]["count"]), 3, "the group size is saved")

	var restored := ArrivalQueue.new(1)
	restored.restore(saved)
	check_eq(restored.size(), 1, "the entry restores")
	check_eq(int(restored.to_save()[0]["count"]), 3, "the group size survives a round trip")


func _check_missing_count_restores_as_one() -> void:
	# A save written before group arrivals existed. `position` is `[x, y]`, matching
	# `to_save()`'s own JSON-native shape (a bare `Vector2i` does not survive `JSON.stringify`
	# and `restore()` type-checks the field as an Array before ever casting it — see its
	# header) — the fixed brief snippet passed a `Vector2i` directly, which `restore()`
	# correctly rejects as malformed and would have made this check assert on a queue that
	# never restored anything at all.
	var legacy: Array = [{"position": [2, 2], "species_id": "rabbit", "remaining": 5.0}]
	var queue := ArrivalQueue.new(1)
	queue.restore(legacy)
	check_eq(queue.size(), 1, "a pre-group save still restores")
	check_eq(int(queue.to_save()[0]["count"]), 1, "a missing count reads as one, not zero")


## The partial-landing rule, stated as arithmetic so it can be checked without a world.
## PLACEHOLDER: this only pins `mini()`'s own behaviour. See
## `_check_partial_landing_lands_exactly_what_fits()` below for the real coverage.
func _check_partial_landing_arithmetic() -> void:
	check_eq(mini(3, 6 - 4), 2, "a group of 3 into room for 2 lands 2")
	check_eq(mini(3, 6 - 6), 0, "a group of 3 into no room lands none")
	check_eq(mini(3, 12 - 0), 3, "a group of 3 into an empty herd site lands all 3")


# --- Integration: drives ArrivalQueue + HabitatSimulation against a real grid/registry -------
# This is the check the brief's `_check_partial_landing_arithmetic()` cannot be: it exercises
# `HabitatSimulation._land_or_drop()`'s actual loop, re-checking capacity against the
# POPULATION EACH `_move_in()` JUST CHANGED, the way the real due-time re-check must.

## A habitat with room for 3 (`cover` at 12 tiles / 4 per individual), one resident already
## settled, and a group of 3 enqueued to land there. Only 2 more fit — the group must land
## exactly 2, not all 3 and not 0.
func _check_partial_landing_lands_exactly_what_fits() -> void:
	var fixture: Dictionary = _fixture()
	var sim: HabitatSimulation = fixture["sim"]
	var grid: WorldGrid = fixture["grid"]
	var registry: HomeSiteRegistry = fixture["registry"]
	var arrivals: ArrivalQueue = fixture["arrivals"]
	var species: AnimalDefinition = fixture["species"]
	var residents_root: Node3D = fixture["residents"]
	var origin: Vector2i = fixture["origin"]

	check_eq(CapacityEvaluator.capacity(grid, registry, origin, species), 3,
		"the painted habitat supports 3 -- the fixture's own precondition")

	# One resident already settled, registered directly (bypassing the arrival delay) so the
	# scenario starts at population 1 without depending on a prior arrival resolving.
	var site: HomeSite = registry.register(origin, species.id, species.scout_radius)
	var already_here := Node3D.new()
	residents_root.add_child(already_here)
	site.residents.append(already_here)
	check_eq(site.population(), 1, "one resident is already home -- room for 2 more, not 3")

	var arrived: Array[String] = []
	sim.resident_arrived.connect(func(sid: String, _p: Vector3) -> void: arrived.append(sid))

	# Enqueued directly at group size 3 -- what a herd tier's `arrival_group_size` would have
	# produced -- rather than through `_evaluate()`, so this check pins `_land_or_drop()`'s
	# partial-landing loop in isolation from the qualification predicate.
	check(arrivals.enqueue(origin, species.id, 3), "a group of 3 is enqueued")
	check_eq(int(arrivals.to_save()[0]["count"]), 3, "...carrying count 3")

	# Past the whole arrival-delay band in one tick, so the pending entry comes due and
	# `_land_or_drop()` runs its per-individual re-check loop.
	sim.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)

	check_eq(site.population(), 3,
		"PARTIAL LANDING: a group of 3 into room for 2 landed 2 -- population is 3 (1 + 2), "
		+ "not 4 (all 3 landed) and not 1 (the whole group dropped)")
	check_eq(arrived.size(), 2,
		"`resident_arrived` fired exactly twice -- once per individual that actually landed")
	check_eq(arrivals.size(), 0, "the pending entry is gone, not stuck half-resolved in the queue")

	_teardown(fixture)


# --- fixture -----------------------------------------------------------------------------------

## A world with no scene: real grid, real registry, real queue, and a one-species SYNTHETIC
## roster whose only need is `cover` at 4 tiles per individual — the same shape
## `test_event_driven_simulation.gd`'s fixture uses. A 3x4 block of rock (12 tiles, all well
## inside the 8-tile scout radius) supports exactly 3 individuals: `12 / 4 == 3`.
func _fixture() -> Dictionary:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 36, 36)

	var species := AnimalDefinition.new()
	species.id = "critter"
	species.display_name = "Critter"
	species.habitat_needs = ["cover"] as Array[String]
	species.tiles_per_individual = 4
	species.scout_radius = 8
	# A grey-box stands in for the model -- a species with no `model_scenes` would push a
	# warning on every move-in, which would make this check's own noise indistinguishable
	# from a real defect.
	species.model_scenes = [load("res://assets/placeholder/grass/Grass.tscn") as PackedScene]

	var origin := Vector2i(10, 10)
	for dx in range(1, 4):
		for dz in range(1, 5):
			grid.set_terrain(origin.x + dx, origin.y + dz, "rock")

	var registry := HomeSiteRegistry.new()
	var arrivals := ArrivalQueue.new(20260904)
	var residents_root := Node3D.new()
	var sim := HabitatSimulation.new()
	sim.attach(grid, SpeciesRoster.new([species]), registry, arrivals, residents_root)

	return {
		"grid": grid, "sim": sim, "registry": registry, "arrivals": arrivals,
		"species": species, "residents": residents_root, "origin": origin,
	}


func _teardown(fixture: Dictionary) -> void:
	(fixture["sim"] as HabitatSimulation).free()
	(fixture["grid"] as WorldGrid).free()
	(fixture["residents"] as Node3D).free()
