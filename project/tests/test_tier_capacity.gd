extends QATestCase
## The tiered capacity formula:
##
##   capacity(h, S) = max over tiers of tier_capacity(h, S, T)
##
##   tier_capacity: limits GATE (violated -> 0); GATE_ONLY needs GATE (absent -> 0);
##   scaling needs apply Liebig's min against their OWN divisor; capped by the TIER's
##   max_individuals. No lower clamp — 0 is a real value meaning unsuitable.
##
## Every species here is synthetic. These assertions state what the FORMULA does, so
## retuning any `.tres` must never move them.
##
## Run:
##   bash scripts/run-tests.sh tier_capacity

func _init() -> void:
	begin("tier capacity")
	_check_best_tier_wins()
	_check_gate_only_does_not_cap()
	_check_limits_gate()
	_check_per_need_divisors()
	_check_no_lower_clamp()
	_check_legacy_adapter_still_matches()
	finish()


## The spec's own worked example: a barn and some grass gets a pair; a stable, a wide
## tract and water gets a herd, with water binding.
func _check_best_tier_wins() -> void:
	var horse := _horse()
	var counts: Dictionary = {}
	counts[CapacityEvaluator.count_key("stable", 5)] = 1
	counts[CapacityEvaluator.count_key("open_grass", 8)] = 12
	counts[CapacityEvaluator.count_key("open_grass", 14)] = 48
	counts[CapacityEvaluator.count_key("water", 12)] = 8

	var pair: HabitatTier = horse.tiers[0]
	var herd: HabitatTier = horse.tiers[1]
	check_eq(
		CapacityEvaluator.tier_capacity_from_counts(counts, horse, pair), 2,
		"pair tier caps at its own max_individuals of 2"
	)
	check_eq(
		CapacityEvaluator.tier_capacity_from_counts(counts, horse, herd), 4,
		"herd tier: water at 8/2 binds below grass at 48/4 and below the cap of 12"
	)

	# More water, more herd — up to the grass ceiling, then the tier cap.
	counts[CapacityEvaluator.count_key("water", 12)] = 40
	check_eq(
		CapacityEvaluator.tier_capacity_from_counts(counts, horse, herd), 12,
		"with water abundant, grass 48/4 = 12 meets the tier cap of 12"
	)


func _check_gate_only_does_not_cap() -> void:
	var horse := _horse()
	var herd: HabitatTier = horse.tiers[1]
	var counts: Dictionary = {}
	counts[CapacityEvaluator.count_key("stable", 5)] = 1
	counts[CapacityEvaluator.count_key("open_grass", 14)] = 48
	counts[CapacityEvaluator.count_key("water", 12)] = 40
	check_eq(
		CapacityEvaluator.tier_capacity_from_counts(counts, horse, herd), 12,
		"ONE stable tile does not cap the herd at one horse — that is what GATE_ONLY is for"
	)
	counts[CapacityEvaluator.count_key("stable", 5)] = 0
	check_eq(
		CapacityEvaluator.tier_capacity_from_counts(counts, horse, herd), 0,
		"no stable at all means the tier does not qualify"
	)


func _check_limits_gate() -> void:
	var deer := _deer()
	var tier: HabitatTier = deer.tiers[0]
	var counts: Dictionary = {}
	counts[CapacityEvaluator.count_key("open_grass", 10)] = 25
	counts[CapacityEvaluator.count_key("forest", 10)] = 20
	counts[CapacityEvaluator.count_key("built", 12)] = 1
	check_eq(
		CapacityEvaluator.tier_capacity_from_counts(counts, deer, tier), 4,
		"one building is within the deer's tolerance of 1"
	)
	counts[CapacityEvaluator.count_key("built", 12)] = 2
	check_eq(
		CapacityEvaluator.tier_capacity_from_counts(counts, deer, tier), 0,
		"exceeding the limit zeroes the tier outright — limits gate, never scale"
	)


func _check_per_need_divisors() -> void:
	var cow := AnimalDefinition.new()
	cow.id = "cow"
	cow.display_name = "Cow"
	var tier := HabitatTier.new()
	tier.id = "only"
	tier.max_individuals = 6
	tier.needs = [
		_need("barn", 0, HabitatNeed.GATE_ONLY),
		_need("silo", 0, HabitatNeed.GATE_ONLY),
		_need("open_grass", 0, 5),
	]
	cow.tiers = [tier]
	cow.scout_radius = 9

	var counts: Dictionary = {}
	counts[CapacityEvaluator.count_key("barn", 9)] = 1
	counts[CapacityEvaluator.count_key("silo", 9)] = 1
	counts[CapacityEvaluator.count_key("open_grass", 9)] = 17
	check_eq(
		CapacityEvaluator.tier_capacity_from_counts(counts, cow, tier), 3,
		"17 grass at 5 per cow floors to 3"
	)
	counts[CapacityEvaluator.count_key("silo", 9)] = 0
	check_eq(
		CapacityEvaluator.tier_capacity_from_counts(counts, cow, tier), 0,
		"a missing gate zeroes the tier regardless of abundant grass"
	)


func _check_no_lower_clamp() -> void:
	var deer := _deer()
	var counts: Dictionary = {}
	counts[CapacityEvaluator.count_key("open_grass", 10)] = 2
	counts[CapacityEvaluator.count_key("forest", 10)] = 2
	counts[CapacityEvaluator.count_key("built", 12)] = 0
	check_eq(
		CapacityEvaluator.tier_capacity_from_counts(counts, deer, deer.tiers[0]), 0,
		"too little of everything is 0, not a clamped 1"
	)


## The pre-tier entry point must keep behaving identically, because
## `test_capacity_formula.gd` pins gdd.md's formula against it and is not being edited.
func _check_legacy_adapter_still_matches() -> void:
	var legacy := AnimalDefinition.new()
	legacy.id = "rabbit"
	legacy.display_name = "Rabbit"
	legacy.habitat_needs = ["open_grass", "cover"] as Array[String]
	legacy.tiles_per_individual = 4
	legacy.max_individuals = 6
	legacy.scout_radius = 9

	var bare_counts: Dictionary = {"open_grass": 17, "cover": 9}
	check_eq(
		CapacityEvaluator.capacity_from_counts(bare_counts, legacy), 2,
		"legacy bare-tag counts still work: cover 9/4 = 2 binds"
	)
	legacy.tiles_per_individual = 0
	check_eq(
		CapacityEvaluator.capacity_from_counts(bare_counts, legacy), 0,
		"a sub-1 legacy divisor is still 0, NOT a GATE_ONLY reinterpretation"
	)


# --- fixtures -----------------------------------------------------------------------

func _horse() -> AnimalDefinition:
	var def := AnimalDefinition.new()
	def.id = "horse"
	def.display_name = "Horse"
	def.scout_radius = 8

	var pair := HabitatTier.new()
	pair.id = "pair"
	pair.max_individuals = 2
	pair.needs = [_need("stable", 5, HabitatNeed.GATE_ONLY), _need("open_grass", 8, 6)]

	var herd := HabitatTier.new()
	herd.id = "herd"
	herd.max_individuals = 12
	herd.arrival_group_size = 3
	herd.needs = [
		_need("stable", 5, HabitatNeed.GATE_ONLY),
		_need("open_grass", 14, 4),
		_need("water", 12, 2),
	]
	def.tiers = [pair, herd]
	return def


func _deer() -> AnimalDefinition:
	var def := AnimalDefinition.new()
	def.id = "deer"
	def.display_name = "Deer"
	def.scout_radius = 10
	var tier := HabitatTier.new()
	tier.id = "few"
	tier.max_individuals = 4
	tier.needs = [_need("open_grass", 10, 5), _need("forest", 10, 4)]
	var limit := HabitatLimit.new()
	limit.tag = "built"
	limit.radius = 12
	limit.max_count = 1
	tier.limits = [limit]
	def.tiers = [tier]
	return def


func _need(tag: String, radius: int, divisor: int) -> HabitatNeed:
	var n := HabitatNeed.new()
	n.tag = tag
	n.radius = radius
	n.tiles_per_individual = divisor
	return n
