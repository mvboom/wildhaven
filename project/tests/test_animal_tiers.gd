extends QATestCase
## `AnimalDefinition.effective_tiers()` — authored tiers, and the legacy synthesis that
## lets the sixteen shipped `.tres` files convert one at a time.
##
## Run:
##   bash scripts/run-tests.sh animal_tiers

func _init() -> void:
	begin("animal tiers")
	_check_legacy_synthesis()
	_check_legacy_divisor_guard()
	_check_authored_tiers_win()
	_check_emits_tags_default()
	finish()


func _check_legacy_synthesis() -> void:
	var def := _legacy_species("rabbit", ["open_grass", "cover"], 4, 9, 6)
	var tiers: Array[HabitatTier] = def.effective_tiers()
	check_eq(tiers.size(), 1, "a legacy species synthesises exactly one tier")
	var tier: HabitatTier = tiers[0]
	check_eq(tier.needs.size(), 2, "one need per legacy habitat_needs entry")
	check_eq(tier.max_individuals, 6, "legacy max_individuals carries over")
	check_eq(tier.arrival_group_size, 1, "legacy arrivals stay one at a time")
	check_eq(tier.limits.size(), 0, "a legacy species has no limits")
	check_eq(tier.needs[0].tag, "open_grass", "legacy need keeps its tag")
	check_eq(tier.needs[0].tiles_per_individual, 4, "legacy divisor applies to every need")
	# The legacy radius is capacity_radius, NOT scout_radius — pin it explicitly.
	check_eq(
		tier.needs[0].effective_radius(0), def.effective_capacity_radius(),
		"legacy need radius is the species' capacity radius"
	)


func _check_legacy_divisor_guard() -> void:
	var broken := _legacy_species("broken", ["open_grass"], 0, 9, 6)
	check(broken.legacy_tier() == null, "divisor 0 yields NO legacy tier, not a GATE_ONLY tier")
	check_eq(broken.effective_tiers().size(), 0, "no tier means no way to qualify")
	var negative := _legacy_species("negative", ["open_grass"], -3, 9, 6)
	check(negative.legacy_tier() == null, "a negative divisor yields no legacy tier either")


func _check_authored_tiers_win() -> void:
	var def := _legacy_species("horse", ["open_grass"], 6, 9, 2)
	var herd := HabitatTier.new()
	herd.id = "herd"
	var grass := HabitatNeed.new()
	grass.tag = "open_grass"
	grass.radius = 14
	grass.tiles_per_individual = 4
	herd.needs = [grass]
	herd.max_individuals = 12
	herd.arrival_group_size = 3
	def.tiers = [herd]
	var tiers: Array[HabitatTier] = def.effective_tiers()
	check_eq(tiers.size(), 1, "authored tiers are returned as-is")
	check_eq(tiers[0].id, "herd", "the authored tier is the one returned, not a synthesis")
	check_eq(tiers[0].arrival_group_size, 3, "authored group size survives")


func _check_emits_tags_default() -> void:
	var def := _legacy_species("fox", ["forest"], 5, 9, 3)
	check(def.emits_tags.is_empty(), "most species emit nothing")
	def.emits_tags = ["people"]
	check_eq(def.emits_tags[0], "people", "emits_tags round-trips")


func _legacy_species(
	id: String, needs: Array[String], divisor: int, radius: int, cap: int
) -> AnimalDefinition:
	var def := AnimalDefinition.new()
	def.id = id
	def.display_name = id
	var typed: Array[String] = []
	for tag: String in needs:
		typed.append(tag)
	def.habitat_needs = typed
	def.tiles_per_individual = divisor
	def.scout_radius = radius
	def.max_individuals = cap
	return def
