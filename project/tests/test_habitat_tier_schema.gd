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
	_check_validate_catches_duplicate_buckets()
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


## Final review finding #3 (2026-09-04): `needs` and `limits` share one bucket list in
## `CapacityEvaluator.tag_counts()` (keyed by tag + resolved radius), so two children that
## resolve to the same key double-count every matching tile. `validate()` cannot resolve the
## sentinel (no species to hand it a fallback), so this checks the guard's actual, narrower
## contract: two children left at the SAME raw radius (including both at the sentinel, which
## always resolves equal for whichever species ends up owning this tier) are caught.
func _check_validate_catches_duplicate_buckets() -> void:
	# Two NEEDS, same tag, same explicit radius — the plainest double-count shape.
	var dup_needs := HabitatTier.new()
	dup_needs.id = "dup_needs"
	var need_a := HabitatNeed.new()
	need_a.tag = "open_grass"
	need_a.radius = 8
	need_a.tiles_per_individual = 4
	var need_b := HabitatNeed.new()
	need_b.tag = "open_grass"
	need_b.radius = 8
	need_b.tiles_per_individual = 6
	dup_needs.needs = [need_a, need_b]
	check(not dup_needs.validate().is_empty(),
		"two needs sharing a tag AND an explicit radius is a problem")

	# A NEED and a LIMIT, same tag, BOTH left at the sentinel — collide for every species,
	# regardless of which one ends up owning this tier, since both resolve against the same
	# fallback.
	var dup_sentinel := HabitatTier.new()
	dup_sentinel.id = "dup_sentinel"
	var sentinel_need := HabitatNeed.new()
	sentinel_need.tag = "built"
	sentinel_need.radius = HabitatNeed.RADIUS_FOLLOWS_SCOUT
	sentinel_need.tiles_per_individual = 4
	var sentinel_limit := HabitatLimit.new()
	sentinel_limit.tag = "built"
	sentinel_limit.radius = HabitatLimit.RADIUS_FOLLOWS_SCOUT
	dup_sentinel.needs = [sentinel_need]
	dup_sentinel.limits = [sentinel_limit]
	check(not dup_sentinel.validate().is_empty(),
		"a need and a limit sharing a tag, both left at the sentinel radius, is a problem — "
		+ "they resolve to the same fallback for every species")

	# The NEGATIVE CONTROL: same tag, DIFFERENT radii, must not false-positive.
	var different_radii := HabitatTier.new()
	different_radii.id = "clean"
	var near := HabitatNeed.new()
	near.tag = "open_grass"
	near.radius = 8
	near.tiles_per_individual = 4
	var far := HabitatNeed.new()
	far.tag = "open_grass"
	far.radius = 14
	far.tiles_per_individual = 4
	different_radii.needs = [near, far]
	check(different_radii.validate().is_empty(),
		"the same tag at two DIFFERENT radii resolves to two DIFFERENT bucket keys — no "
		+ "double-count, so this must not be flagged")
