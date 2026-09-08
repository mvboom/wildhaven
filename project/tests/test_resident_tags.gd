extends QATestCase
## Resident-emitted tags: `people` and `deer` are ordinary habitat tags contributed by
## RESIDENTS rather than by tiles.
##
## THE FIRST THREE CHECKS below are algebraic mirrors of the intended logic — they exercise
## `HomeSite.population()` and `resident_tags` directly, not `CapacityEvaluator.tag_counts()`
## itself. Kept for their own value (they pin the data shape), but they cannot catch a
## regression in the bucket-write loop `tag_counts()` actually runs. THE INTEGRATION CHECKS
## below close that gap by calling `tag_counts()` against a real `WorldGrid` +
## `HomeSiteRegistry`, the way `test_tile_exclusivity.gd` does.
##
## Run:
##   bash scripts/run-tests.sh resident_tags

func _init() -> void:
	begin("resident tags")
	_check_sites_at()
	_check_counted_per_individual()
	_check_absent_when_vacant()
	_check_tag_counts_counts_residents_per_individual()
	_check_tag_counts_reaches_both_key_shapes()
	_check_tag_counts_vacant_contributes_nothing()
	_check_tag_counts_self_site_skips_own_residents()
	finish()


func _check_sites_at() -> void:
	var registry := HomeSiteRegistry.new()
	var a: HomeSite = registry.register(Vector2i(4, 4), "human", 9)
	var b: HomeSite = registry.register(Vector2i(4, 4), "husky", 9)
	var found: Array[HomeSite] = registry.sites_at(Vector2i(4, 4))
	check_eq(found.size(), 2, "sites_at returns every site sharing a tile")
	check(found.has(a) and found.has(b), "both sites are returned")
	check_eq(registry.sites_at(Vector2i(9, 9)).size(), 0, "an empty tile returns none")


## The load-bearing assertion of this task.
func _check_counted_per_individual() -> void:
	var site := HomeSite.new(Vector2i(0, 0), "human", 9, 0)
	site.resident_tags = ["people"] as Array[String]
	for i in range(4):
		site.residents.append(Node3D.new())
	check_eq(site.population(), 4, "four villagers live here")
	var contributed: Dictionary = {}
	for tag: String in site.resident_tags:
		contributed[tag] = int(contributed.get(tag, 0)) + site.population()
	check_eq(
		int(contributed["people"]), 4,
		"ONE house with four villagers contributes people=4, NOT people=1"
	)
	for resident: Node3D in site.residents:
		resident.free()


func _check_absent_when_vacant() -> void:
	# species_id "" is what an unclaimed/vacated structure site actually looks like
	# (`HomeSite.is_vacant()` reads `species_id == ""`, not population) -- the real state
	# `HomeSiteRegistry.release()` leaves behind once the last resident departs a house.
	# `resident_tags` can still be stale from before that departure; population() gates it.
	var site := HomeSite.new(Vector2i(0, 0), "", 9, 0)
	site.resident_tags = ["people"] as Array[String]
	check_eq(site.population(), 0, "a vacant site has no residents")
	check(site.is_vacant(), "an empty house is vacant")
	# An empty house must NOT satisfy a dog's `people` need -- that is the whole point of
	# the resident-emitted mechanic over a plain `house` tag.
	check_eq(site.population() * site.resident_tags.size(), 0, "a vacant site contributes nothing")


# --- Integration: calls into CapacityEvaluator.tag_counts() itself -----------------------
# Everything below builds a real WorldGrid + HomeSiteRegistry (`test_tile_exclusivity.gd`'s
# own setup pattern) and calls the production bucket-write loop directly, so a regression
# there -- e.g. counting one per SITE instead of one per RESIDENT -- fails these, not just
# the algebraic checks above.

## THE LOAD-BEARING INTEGRATION CASE. A site four tiles away holds four residents and emits
## `people`; a dog-like candidate reading `people` at radius 6 must see 4, never 1.
func _check_tag_counts_counts_residents_per_individual() -> void:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 20, 20)

	var registry := HomeSiteRegistry.new()
	var home: HomeSite = registry.register(Vector2i(10, 10), "colony", 6)
	home.resident_tags = ["people"] as Array[String]
	var residents: Array[Node3D] = _spawn(home, 4)

	var dog: AnimalDefinition = _species("dog", ["people"], 1, 6)
	var tier: HabitatTier = _people_tier(6, 1)
	var origin := Vector2i(12, 10)  # distance^2 = 4, well inside radius 6

	var counts: Dictionary = CapacityEvaluator.tag_counts(grid, registry, origin, dog, tier)
	var key: String = CapacityEvaluator.count_key("people", 6)
	check_eq(
		int(counts.get(key, -1)), 4,
		"ONE house with four residents reads people=4 through tag_counts() itself, "
		+ "NOT people=1 -- the bug this whole task exists to prevent"
	)

	_free_all(residents)
	grid.free()


## `tag_counts()` writes a resident contribution into EVERY key shape a bucket emits: the
## radius-keyed entry always, and (on a `tier == null` legacy-mode call) the bare-tag alias
## too. A fix that only touched one of the two would leave a legacy-mode caller silently
## blind to residents.
func _check_tag_counts_reaches_both_key_shapes() -> void:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 20, 20)

	var registry := HomeSiteRegistry.new()
	var home: HomeSite = registry.register(Vector2i(10, 10), "colony", 6)
	home.resident_tags = ["people"] as Array[String]
	var residents: Array[Node3D] = _spawn(home, 4)

	var dog: AnimalDefinition = _species("dog", ["people"], 1, 6)
	var origin := Vector2i(12, 10)

	# No `tier` argument -> legacy mode -> `species.legacy_tier()`, whose synthesised need
	# sits at `HabitatNeed.RADIUS_FOLLOWS_SCOUT` and resolves to `scout_radius` (6) via
	# `effective_capacity_radius()`.
	var counts: Dictionary = CapacityEvaluator.tag_counts(grid, registry, origin, dog)
	var radius_key: String = CapacityEvaluator.count_key("people", 6)
	check_eq(
		int(counts.get(radius_key, -1)), 4, "residents reach the radius-keyed entry"
	)
	check_eq(
		int(counts.get("people", -1)), 4,
		"...AND the bare-tag alias in legacy mode -- a legacy caller reading `counts.get" +
		"(\"people\")` must see the same 4, not a silent 0"
	)

	_free_all(residents)
	grid.free()


## A house standing empty must satisfy nobody's `people` need. Checked through the real
## function, not through arithmetic on `population()` alone.
func _check_tag_counts_vacant_contributes_nothing() -> void:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 20, 20)

	var registry := HomeSiteRegistry.new()
	var home: HomeSite = registry.register(Vector2i(10, 10), "colony", 6)
	home.resident_tags = ["people"] as Array[String]  # no residents appended -- vacant

	var dog: AnimalDefinition = _species("dog", ["people"], 1, 6)
	var tier: HabitatTier = _people_tier(6, 1)
	var origin := Vector2i(12, 10)

	var counts: Dictionary = CapacityEvaluator.tag_counts(grid, registry, origin, dog, tier)
	var key: String = CapacityEvaluator.count_key("people", 6)
	check_eq(
		int(counts.get(key, -1)), 0,
		"a vacant house contributes 0 through tag_counts() -- needing `people` is not the "
		+ "same as needing `house`"
	)

	grid.free()


## THE SELF-COUNTING GUARD. A species that both emits and needs `people` must not bootstrap
## off its OWN residents when its own site is passed as `self_site` -- the exact scenario the
## brief warns about.
func _check_tag_counts_self_site_skips_own_residents() -> void:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 20, 20)

	var registry := HomeSiteRegistry.new()
	var colony: AnimalDefinition = _species("colony", ["people"], 1, 6)
	var home: HomeSite = registry.register(Vector2i(10, 10), "colony", 6)
	home.resident_tags = ["people"] as Array[String]
	var residents: Array[Node3D] = _spawn(home, 4)

	var tier: HabitatTier = _people_tier(6, 1)
	var counts: Dictionary = CapacityEvaluator.tag_counts(
		grid, registry, home.position, colony, tier, home
	)
	var key: String = CapacityEvaluator.count_key("people", 6)
	check_eq(
		int(counts.get(key, -1)), 0,
		"a site's own residents never count toward its own capacity for a species that "
		+ "both emits and needs the same tag -- otherwise it would bootstrap itself"
	)

	# NEGATIVE CONTROL: the SAME site, read by an UNRELATED species scope ("dog", never
	# "colony") from a nearby position, DOES see those residents -- proving the zero above is
	# specifically the self-site skip and not a broken counter. (Querying with "colony" again
	# from elsewhere would instead exercise the SAME-SPECIES exclusivity rule -- home is the
	# strictly-nearer owner of its own tile -- which is a different mechanism than the one
	# this check targets, so a different species scope is used to isolate self-counting.)
	var dog: AnimalDefinition = _species("dog", ["people"], 1, 6)
	var elsewhere := Vector2i(12, 10)
	var prospective_counts: Dictionary = CapacityEvaluator.tag_counts(
		grid, registry, elsewhere, dog, tier
	)
	check_eq(
		int(prospective_counts.get(key, -1)), 4,
		"...while an unrelated species querying nearby still counts that site's residents "
		+ "normally -- the counter itself works"
	)

	_free_all(residents)
	grid.free()


# --- helpers --------------------------------------------------------------------------------

func _species(id: String, needs: Array[String], divisor: int, radius: int) -> AnimalDefinition:
	var def := AnimalDefinition.new()
	def.id = id
	def.display_name = id
	def.habitat_needs = needs
	def.tiles_per_individual = divisor
	def.scout_radius = radius
	return def


func _people_tier(radius: int, divisor: int) -> HabitatTier:
	var need := HabitatNeed.new()
	need.tag = "people"
	need.radius = radius
	need.tiles_per_individual = divisor
	var tier := HabitatTier.new()
	tier.id = "people_tier"
	tier.needs = [need] as Array[HabitatNeed]
	tier.max_individuals = 10
	return tier


func _spawn(site: HomeSite, count: int) -> Array[Node3D]:
	var spawned: Array[Node3D] = []
	for i in range(count):
		var node := Node3D.new()
		site.residents.append(node)
		spawned.append(node)
	return spawned


func _free_all(nodes: Array[Node3D]) -> void:
	for node: Node3D in nodes:
		node.free()
