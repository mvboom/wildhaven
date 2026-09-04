extends QATestCase
## The validation rules tiers introduce: vocabulary, radius band, category coherence,
## the inert-land invariant over POSITIVE needs only, and graph acyclicity.
##
## Run:
##   bash scripts/run-tests.sh habitat_validation

func _init() -> void:
	begin("habitat validation")
	_check_vocabulary()
	_check_radius_band()
	_check_categories()
	_check_inert_land_ignores_limits()
	_check_acyclicity()
	finish()


func _check_vocabulary() -> void:
	var tags: PackedStringArray = AnimalDefinition.HABITAT_TAGS
	for expected: String in ["built", "people", "deer", "browse", "snow", "large_house", "stable"]:
		check(tags.has(expected), "vocabulary contains \"%s\"" % expected)
	check(not tags.has("quiet"), "`quiet` was retired (human ruling OQ-F)")


func _check_radius_band() -> void:
	var def := _species("stag", ["forest"], 5)
	def.scout_radius = 14
	var problems: Array[String] = def.validate()
	for problem: String in problems:
		check(not problem.contains("scout_radius"), "radius 14 is legal under the 2-16 band")
	def.scout_radius = 40
	check(_mentions(def.validate(), "scout_radius"), "radius 40 is outside the 2-16 band")


func _check_categories() -> void:
	var villager := _species("human", ["house"], 1)
	villager.emits_tags = ["people"]
	check_eq(villager.category(), "person", "a species that EMITS people is Person")

	var pug := _species("pug", ["house"], 1)
	pug.tiers = [_tier("only", [_need("house", 0, HabitatNeed.GATE_ONLY), _need("people", 0, 5)], [])]
	check_eq(pug.category(), "person", "Person is checked before Domesticated")

	var deer := _species("deer", ["open_grass"], 5)
	deer.tiers = [_tier("few", [_need("open_grass", 0, 5)], [_limit("built", 0, 1)])]
	check_eq(deer.category(), "wild", "no building need plus a limit is Wild")

	var cow := _species("cow", ["open_grass"], 5)
	cow.tiers = [_tier("only", [_need("barn", 0, HabitatNeed.GATE_ONLY), _need("open_grass", 0, 5)], [])]
	check_eq(cow.category(), "domesticated", "a building gate with no limit is Domesticated")


func _check_inert_land_ignores_limits() -> void:
	# A limit must never be what makes a species non-bare.
	var bare := _species("ghost", ["open_grass"], 4)
	bare.tiers = [_tier("only", [_need("open_grass", 0, 4)], [_limit("built", 0, 0)])]
	check(
		_mentions(bare.validate(), "inert"),
		"a positive-needs-only-bare species is flagged even when it carries a limit"
	)


func _check_acyclicity() -> void:
	var human := _species("human", ["house"], 1)
	human.emits_tags = ["people"]
	var pug := _species("pug", ["people"], 5)
	var deer := _species("deer", ["open_grass"], 5)
	deer.emits_tags = ["deer"]
	var stag := _species("stag", ["deer"], 4)
	check(
		HabitatGraph.find_cycle([human, pug, deer, stag]).is_empty(),
		"the shipped graph (human->people, deer->deer) is acyclic"
	)

	var a := _species("a", ["b_tag"], 2)
	a.emits_tags = ["a_tag"]
	var b := _species("b", ["a_tag"], 2)
	b.emits_tags = ["b_tag"]
	check(
		not HabitatGraph.find_cycle([a, b]).is_empty(),
		"a mutual dependency is reported as a cycle"
	)


# --- helpers ------------------------------------------------------------------------

func _species(id: String, needs: Array[String], divisor: int) -> AnimalDefinition:
	var def := AnimalDefinition.new()
	def.id = id
	def.display_name = id
	var typed: Array[String] = []
	for tag: String in needs:
		typed.append(tag)
	def.habitat_needs = typed
	def.tiles_per_individual = divisor
	def.scout_radius = 9
	def.max_individuals = 6
	return def


func _need(tag: String, radius: int, divisor: int) -> HabitatNeed:
	var n := HabitatNeed.new()
	n.tag = tag
	n.radius = radius
	n.tiles_per_individual = divisor
	return n


func _limit(tag: String, radius: int, ceiling: int) -> HabitatLimit:
	var l := HabitatLimit.new()
	l.tag = tag
	l.radius = radius
	l.max_count = ceiling
	return l


func _tier(id: String, needs: Array, limits: Array) -> HabitatTier:
	var t := HabitatTier.new()
	t.id = id
	var typed_needs: Array[HabitatNeed] = []
	for n: HabitatNeed in needs:
		typed_needs.append(n)
	var typed_limits: Array[HabitatLimit] = []
	for l: HabitatLimit in limits:
		typed_limits.append(l)
	t.needs = typed_needs
	t.limits = typed_limits
	return t


func _mentions(problems: Array[String], fragment: String) -> bool:
	for problem: String in problems:
		if problem.contains(fragment):
			return true
	return false
