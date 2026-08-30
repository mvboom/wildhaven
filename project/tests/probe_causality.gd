extends QATestCase
## THROWAWAY PROBE — not a suite. Named outside the runner's `test_*.gd` glob on purpose.
## Measures the post-D-27 rabbit behaviour so the re-pointed pins are derived, not guessed.

const WORLD_PATH: String = "res://scenes/Main.tscn"
const ROCK_ORIGIN := Vector2i(6, 7)
const ROCK_W: int = 4
const ROCK_D: int = 3
const RABBIT_SITE := Vector2i(8, 8)

var _world: WorldRoot = null
var _frames: int = 0
var _ok: bool = false
var _arrivals: Array[String] = []
var _positions: Array[Vector3] = []


func _initialize() -> void:
	begin("probe")
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var node: Node = packed.instantiate()
	_world = node as WorldRoot
	_world.resident_arrived.connect(func(sid: String, pos: Vector3) -> void:
		_arrivals.append(sid)
		_positions.append(pos))
	root.add_child(_world)
	_ok = true


func _process(_delta: float) -> bool:
	if not _ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	var rabbit: AnimalDefinition = _world.roster.by_id("rabbit")
	print("rabbit tpi=%d scout=%d cap_r=%d eff=%d max=%d" % [
		rabbit.tiles_per_individual, rabbit.scout_radius, rabbit.capacity_radius,
		rabbit.effective_capacity_radius(), rabbit.max_individuals])

	for dx in ROCK_W:
		for dz in ROCK_D:
			_world.paint_tile(ROCK_ORIGIN.x + dx, ROCK_ORIGIN.y + dz, "rock")

	print("capacity_at RABBIT_SITE after paint = %d" % _world.capacity_at(RABBIT_SITE.x, RABBIT_SITE.y, "rabbit"))

	_drain(60)
	print("queued arrivals after drain = %d" % _world.simulation.arrivals().size())
	print("residents before delay = %d" % _world.total_residents())

	_world.simulation.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)
	print("=== after first delay ===")
	_dump()

	_drain(60)
	_world.simulation.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)
	print("=== after second pass ===")
	_dump()

	# Villager half.
	var HOUSE_TILE := Vector2i(28, 28)
	var FIELD_TILE := Vector2i(29, 28)
	var wood_before: int = _world.get_wood()
	print("place house: %s, wood %d -> %d" % [
		_world.place_building(HOUSE_TILE.x, HOUSE_TILE.y, "house"), wood_before, _world.get_wood()])
	print("human capacity at house, no field = %d" % _world.capacity_at(HOUSE_TILE.x, HOUSE_TILE.y, "human"))
	_drain(60)
	print("residents after house-only drain = %d" % _world.total_residents())
	_world.paint_tile(FIELD_TILE.x, FIELD_TILE.y, "cultivated_field")
	print("human capacity with field = %d" % _world.capacity_at(HOUSE_TILE.x, HOUSE_TILE.y, "human"))
	_drain(60)
	_world.simulation.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)
	print("=== after villager ===")
	_dump()
	print("arrival order: %s" % str(_arrivals))
	print("population at HOUSE = %d" % _world.population_at(HOUSE_TILE.x, HOUSE_TILE.y, "human"))
	print("rabbit capacity at HOUSE = %d" % _world.capacity_at(HOUSE_TILE.x, HOUSE_TILE.y, "rabbit"))

	finish()
	return true


func _dump() -> void:
	print("  total_residents = %d, arrivals_seen = %s" % [_world.total_residents(), str(_arrivals)])
	print("  species ids = %s" % str(_world.resident_species_ids()))
	for site: HomeSite in _world.registry.sites():
		var cap: int = _world.capacity_at(site.position.x, site.position.y, site.species_id)
		var pop: int = _world.population_at(site.position.x, site.position.y, site.species_id)
		print("  SITE %s species=%s pop=%d capacity=%d radius=%d OVER=%s" % [
			site.position, site.species_id, pop, cap, site.radius, str(pop > cap)])
	for p: Vector3 in _positions:
		var t: Vector2i = _world.grid.world_to_tile(p)
		print("  arrival tile %s cap=%d" % [t, _world.capacity_at(t.x, t.y, "rabbit")])


func _drain(ticks: int) -> void:
	for _i in ticks:
		_world.simulation.tick(0.0)
