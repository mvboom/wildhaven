extends QATestCase
## Schema contract for HabitatNeed / HabitatLimit / HabitatTier.
##
## Run:
##   bash scripts/run-tests.sh habitat_tier_schema

func _init() -> void:
	begin("habitat tier schema")
	_check_need_sentinel()
	_check_gate_only()
	_check_limit_defaults()
	_check_tier_max_radius()
	_check_validate_catches_bad_data()
	finish()


func _check_need_sentinel() -> void:
	var n := HabitatNeed.new()
	n.tag = "open_grass"
	n.radius = HabitatNeed.RADIUS_FOLLOWS_SCOUT
	check_eq(n.effective_radius(9), 9, "sentinel radius follows the fallback")
	n.radius = 14
	check_eq(n.effective_radius(9), 14, "explicit radius overrides the fallback")


func _check_gate_only() -> void:
	var gate := HabitatNeed.new()
	gate.tag = "stable"
	gate.tiles_per_individual = HabitatNeed.GATE_ONLY
	check(gate.is_gate_only(), "divisor 0 reads as GATE_ONLY")
	var scaling := HabitatNeed.new()
	scaling.tag = "open_grass"
	scaling.tiles_per_individual = 4
	check(not scaling.is_gate_only(), "divisor 4 does not read as GATE_ONLY")


func _check_limit_defaults() -> void:
	var l := HabitatLimit.new()
	l.tag = "built"
	check_eq(l.max_count, 0, "a limit defaults to allowing none at all")
	check_eq(l.effective_radius(11), 11, "limit sentinel radius follows the fallback")


func _check_tier_max_radius() -> void:
	var tier := HabitatTier.new()
	tier.id = "herd"
	var near := HabitatNeed.new()
	near.tag = "stable"
	near.radius = 5
	near.tiles_per_individual = HabitatNeed.GATE_ONLY
	var far := HabitatNeed.new()
	far.tag = "open_grass"
	far.radius = 14
	far.tiles_per_individual = 4
	var limit := HabitatLimit.new()
	limit.tag = "built"
	limit.radius = 16
	tier.needs = [near, far]
	tier.limits = [limit]
	check_eq(tier.max_radius(8), 16, "max_radius spans needs AND limits")
	check_eq(HabitatTier.new().max_radius(8), 8, "an empty tier falls back to the species radius")


func _check_validate_catches_bad_data() -> void:
	var empty_tag := HabitatNeed.new()
	check(not empty_tag.validate().is_empty(), "a need with no tag is a problem")

	var out_of_band := HabitatNeed.new()
	out_of_band.tag = "open_grass"
	out_of_band.radius = 30
	check(not out_of_band.validate().is_empty(), "radius 30 is outside the 2-16 band")

	var negative_limit := HabitatLimit.new()
	negative_limit.tag = "built"
	negative_limit.max_count = -1
	check(not negative_limit.validate().is_empty(), "a negative max_count is a problem")

	var no_needs := HabitatTier.new()
	no_needs.id = "empty"
	check(not no_needs.validate().is_empty(), "a tier with no needs is a problem")

	var good := HabitatTier.new()
	good.id = "pair"
	var n := HabitatNeed.new()
	n.tag = "open_grass"
	n.tiles_per_individual = 6
	good.needs = [n]
	check(good.validate().is_empty(), "a well-formed tier validates clean")
