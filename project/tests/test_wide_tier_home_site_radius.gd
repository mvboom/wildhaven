extends QATestCase
## Final whole-branch review finding I2 (2026-09-04) — a home site's radius must be the
## WIDEST any of its species' tiers reaches, not a bare `scout_radius` copy, and that radius
## must never shrink back down once claimed.
##
## `test_structure_home_site_tiers.gd:141-146` pins the radius only on a freshly-registered
## VACANT site. The two gaps that left open, both real live faults per the review:
##   * `HomeSiteRegistry.claim()` used to OVERWRITE `site.radius` unconditionally — a
##     structure site registered wide (across every species/tier it could serve) silently
##     narrowed the moment any one species actually claimed it. Horse/Open Barn is the
##     spec's own flagship example (§9: "digging more pond visibly buys more horses") and it
##     broke from the first horse's arrival onward.
##   * `HabitatSimulation._move_in()` used to register/claim a SETTLED (non-structure) site at
##     a bare `species.scout_radius`, even though a tier's own need or limit can reach wider
##     (`HabitatTier.max_radius()`) — Deer's herd tier counts `open_grass`/`forest`/`browse`
##     at 14 while `scout_radius` is 10, so grass or scrub painted 11-14 tiles out never
##     re-evaluated the herd tier at all (`HomeSiteRegistry.sites_covering()` -> `HomeSite.
##     covers()`, both keyed on `site.radius`).
##
## Run:
##   bash scripts/run-tests.sh wide_tier_home_site_radius

const DEER_PATH: String = "res://data/animals/deer.tres"
const PLACEHOLDER_MODEL: String = "res://assets/placeholder/grass/Grass.tscn"

const GRID_SIZE: int = 40


func _init() -> void:
	begin("wide-tier home site radius (finding I2)")
	_check_claim_never_narrows_a_site_registered_wider()
	_check_distant_edit_within_the_herd_tiers_radius_flips_the_winning_tier()
	finish()


## THE HORSE/OPEN BARN REGRESSION, ISOLATED: a structure site registered WIDE (standing in
## for `_home_site_radius_for()` having maxed across a wider species' tier alongside a
## narrower one, the way Open Barn's real `stable` tag does for Horse) must stay wide once a
## NARROWER species actually claims it, driven through the real `_move_in()` path (a genuine
## qualification -> enqueue -> due-time arrival), not by calling `HomeSiteRegistry.claim()`
## directly.
func _check_claim_never_narrows_a_site_registered_wider() -> void:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), GRID_SIZE, GRID_SIZE)

	var building := PlaceableDefinition.new()
	building.id = "big_barn"
	building.display_name = "Big Barn"
	building.footprint = Vector2i(1, 1)
	building.emitted_tags = ["built", "big_barn"] as Array[String]

	var origin := Vector2i(20, 20)
	check(grid.set_building(origin, building), "the synthetic Big Barn is placed")

	var registry := HomeSiteRegistry.new()
	# Registered directly at 14 -- standing in for `_home_site_radius_for()` having maxed a
	# WIDE species' tier alongside Shrew's narrow one below at the moment the building was
	# placed. Isolates the CLAIM-side behaviour this check exists to pin from the (already
	# separately covered) registration-side one.
	registry.register_structure(origin, building.emitted_tags, 14)
	var site: HomeSite = registry.vacant_site_at(origin)
	check(site != null and site.radius == 14, "SETUP: the site starts registered wide (14)")
	if site == null:
		grid.free()
		return

	var narrow := AnimalDefinition.new()
	narrow.id = "shrew"
	narrow.display_name = "Shrew"
	narrow.scout_radius = 3
	var need := HabitatNeed.new()
	need.tag = "big_barn"
	need.radius = 3  # narrower than the site's own registered radius (14)
	need.tiles_per_individual = HabitatNeed.GATE_ONLY
	var tier := HabitatTier.new()
	tier.id = "den"
	tier.needs = [need] as Array[HabitatNeed]
	tier.max_individuals = 2
	narrow.tiers = [tier] as Array[HabitatTier]
	narrow.model_scenes = [load(PLACEHOLDER_MODEL) as PackedScene]

	var arrivals := ArrivalQueue.new(20260904)
	var residents_root := Node3D.new()
	var sim := HabitatSimulation.new()
	sim.attach(grid, SpeciesRoster.new([narrow]), registry, arrivals, residents_root)

	# The real trigger path: mark the site's own tile dirty, drain the evaluation (enqueues
	# the arrival), then resolve it past the whole delay band in one call -- the same
	# `test_group_arrivals.gd` idiom.
	sim.on_terraform(origin)
	sim.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)

	check_eq(site.species_id, "shrew", "SETUP: Shrew actually claimed the site")
	check_eq(site.radius, 14,
		"the claim did NOT narrow the site's radius back down to Shrew's own (3) -- the "
		+ "Horse/Open Barn regression finding I2 reported")

	sim.free()
	grid.free()
	residents_root.free()


## THE DEER REGRESSION, END TO END, against REAL `deer.tres` data. A deer settles via its
## BASE tier (`open_grass/5` + `forest/4`, both following `scout_radius` (10)); the site must
## nonetheless register at 14 -- the HERD tier's own `max_radius()` (`open_grass`/`forest`/
## `browse` all @14) -- even though the herd tier is not the one currently qualifying. Once
## settled, painting `browse` (Scrub) 11-14 tiles out -- distance the OLD `scout_radius`-only
## site would never have noticed -- must actually re-evaluate the site and flip its winning
## tier to "herd".
func _check_distant_edit_within_the_herd_tiers_radius_flips_the_winning_tier() -> void:
	var deer: AnimalDefinition = load(DEER_PATH) as AnimalDefinition
	if not check(deer != null, "deer.tres loads"):
		return
	check_eq(deer.scout_radius, 10, "SETUP: deer.tres's scout_radius is still 10")

	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), GRID_SIZE, GRID_SIZE)
	var origin := Vector2i(20, 20)

	# BASE TIER'S OWN MINIMUM, well inside scout_radius (10): 5 open_grass + 4 forest, on two
	# arms so neither run overlaps the other.
	for dx in range(1, 6):
		grid.set_terrain(origin.x + dx, origin.y, "grass")
	for dx in range(1, 5):
		grid.set_terrain(origin.x - dx, origin.y, "forest")

	var registry := HomeSiteRegistry.new()
	var arrivals := ArrivalQueue.new(20260904)
	var residents_root := Node3D.new()
	var sim := HabitatSimulation.new()
	sim.attach(grid, SpeciesRoster.new([deer]), registry, arrivals, residents_root)

	sim.on_terraform(origin)
	sim.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)
	# FULLY SETTLES the world before the discriminating phase below: `on_resident_arrived()`
	# broadcasts `_mark_all_sites_dirty()`, which re-enqueues the deer's OWN site regardless of
	# distance -- if that leftover entry were still pending when the distant-edit loop below
	# starts, draining it would fire `capacity_evaluated` for origin/deer for a reason that has
	# NOTHING to do with `sites_covering()`'s distance check, and the discriminating assertion
	# below would pass identically whether or not this fix is in (it did, the first time this
	# test was written -- caught by deliberately running it against the pre-fix source).
	while not sim.is_idle():
		sim.tick(0.0)
	check_eq(sim.pending_evaluations(), 0,
		"SETUP: the world is fully settled -- nothing left over to contaminate the "
		+ "distant-edit discriminator below")

	var site: HomeSite = registry.settled_site_at(origin, "deer")
	if not check(site != null, "SETUP: a deer settled at the origin via its base tier"):
		_teardown(grid, sim, residents_root)
		return

	check_eq(site.radius, 14,
		"the site registers at 14 -- the HERD tier's own max_radius() -- even though only "
		+ "the BASE tier (scout_radius 10) is what actually qualified it")

	var before: Dictionary = CapacityEvaluator.evaluate(grid, registry, origin, deer, site)
	var before_tier: HabitatTier = before["tier"] as HabitatTier
	check_eq(before_tier.id, "base", "SETUP: before the distant edit, base is the winning tier")

	# THE DISTANT EDIT: extra open_grass/forest (so the herd tier's shared divisors are not
	# the bottleneck) plus browse -- ALL 11-14 tiles out, painted through the REAL
	# `on_terraform()` trigger, exactly as a player's tap would. Placed on arms that do not
	# cross the base-tier tiles above or each other; distances below are all checked to fall
	# in [11, 14].
	#
	# THE DISCRIMINATING ASSERTION lives on `capacity_evaluated`, not on a follow-up direct
	# `CapacityEvaluator.evaluate()` call: `evaluate()` reads `tier.max_radius()` itself and
	# would report "herd" regardless of whether the SIMULATION's own dirty queue ever
	# re-enqueued the site — so calling it manually after the edits would pass identically
	# whether or not this fix is in, proving nothing about the actual bug (the site never
	# being marked dirty). Watching the SIGNAL `HabitatSimulation._evaluate()` emits is what
	# proves `sim.tick()`'s own dirty-queue drain actually re-ran this site's evaluation.
	# A one-element Array, not a bare `bool` -- GDScript lambdas capture a value-type local by
	# VALUE (a snapshot at closure-creation time), so an assignment inside the closure would
	# never be visible out here; an Array is a reference type (the same reason
	# `test_group_arrivals.gd`'s `arrived.append(...)` closure works), so mutating element 0
	# in place is.
	var reevaluated_origin_for_deer: Array[bool] = [false]
	sim.capacity_evaluated.connect(func(pos: Vector2i, sid: String, _cap: int) -> void:
		if pos == origin and sid == "deer":
			reevaluated_origin_for_deer[0] = true
	)

	for k in range(5):
		var tile := Vector2i(origin.x + 12, origin.y + k)  # distance ~= 12.0-12.65
		grid.set_terrain(tile.x, tile.y, "grass")
		sim.on_terraform(tile)
	for k in range(4):
		var tile := Vector2i(origin.x - 12, origin.y + k)  # distance ~= 12.0-12.37
		grid.set_terrain(tile.x, tile.y, "forest")
		sim.on_terraform(tile)
	for k in range(-6, 6):
		var tile := Vector2i(origin.x + k, origin.y + 12)  # distance ~= 12.0-13.42
		grid.set_terrain(tile.x, tile.y, "scrub")
		sim.on_terraform(tile)

	# Drains whatever the edits above enqueued (each edit tile itself, plus the deer site,
	# re-enqueued but de-duplicated by `_dirty_set`) without waiting on the arrival delay --
	# no NEW arrival is expected here, only a re-evaluation of the existing site.
	for i in range(10):
		sim.tick(0.0)

	check(reevaluated_origin_for_deer[0],
		"an edit 11-14 tiles out actually re-enqueued and re-evaluated the deer site -- "
		+ "pre-fix, `sites_covering()` never included this site at that distance (site.radius "
		+ "was 10), so `capacity_evaluated` would never fire again for it at all")
	check_eq(site.radius, 14, "the site's radius is unchanged by the distant edits")

	# The OUTCOME of that re-evaluation, checked separately: the herd tier is now the winner.
	var after: Dictionary = CapacityEvaluator.evaluate(grid, registry, origin, deer, site)
	var after_tier: HabitatTier = after["tier"] as HabitatTier
	check(after_tier != null and after_tier.id == "herd",
		"...and the winning tier is now herd, the tier the distant edit actually unlocked")

	_teardown(grid, sim, residents_root)


func _teardown(grid: WorldGrid, sim: HabitatSimulation, residents_root: Node3D) -> void:
	sim.free()
	grid.free()
	residents_root.free()
