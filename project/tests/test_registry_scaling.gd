extends QATestCase
## THE REGISTRY MUST NOT GET SLOWER BECAUSE OF SITES THAT HAVE NOTHING TO DO WITH THE QUERY.
##
## Two hot paths in `HomeSiteRegistry` were plain linear work over `_sites`, which is what
## made a large world stutter (probe_frame_cost.gd, 2026-08-30):
##
##   * `structure_site_at()` scanned EVERY site. `CapacityEvaluator._tile_counts_for()` calls
##     it once per tile per species inside every evaluation, so at 110 residents it was 80%
##     of an evaluation's cost — and one tile paint runs 27 evaluations.
##   * `rebuild_ownership()` recomputed EVERY scope, and it fires on every register/claim/
##     release/relocate — i.e. on every single resident arrival (7ms at 110 residents).
##
## Both are asserted here as SCALING contracts rather than absolute timings, because an
## absolute microsecond budget is a tuning value (ground rules: "All tuning values are the
## human's") and would be machine-dependent. A ratio is neither: it measures the SHAPE of the
## cost curve, which is a correctness property of the data structure. The threshold is
## deliberately loose — the defect these replaced showed ratios of 30x and up, so a 4x gate
## has enormous headroom against timing noise while still failing loudly on a reintroduced
## linear scan.
##
## Correctness of the index itself is `test_ownership_index_integrity.gd`'s job, not this
## file's. This one only asserts the curve is flat.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_registry_scaling.gd

## Sites of the species actually under test. Held CONSTANT between the two measurements, so
## the only thing that changes is how many IRRELEVANT sites exist alongside them.
const SUBJECT_SITES: int = 20
## The irrelevant population, small and large. 30x apart, so a linear scan cannot hide.
const OTHERS_SMALL: int = 20
const OTHERS_LARGE: int = 600
const LOOKUPS: int = 4000
const MUTATIONS: int = 10
## Generous: a linear scan shows ~30x here, an indexed lookup ~1x.
const MAX_RATIO: float = 4.0

const SUBJECT_SPECIES: String = "rabbit"
## Distinct scope keys, mirroring a real roster's spread — `rebuild_ownership()` groups by
## scope, so a single-species population would make the scoped-rebuild claim vacuous.
const OTHER_SPECIES: Array[String] = [
	"deer", "fox", "badger", "hedgehog", "owl", "squirrel", "otter",
	"pig", "cow", "sheep", "goat", "donkey", "bull",
]


func _initialize() -> void:
	begin("registry scaling")
	_check_structure_lookup_is_indexed()
	_check_register_ignores_other_scopes()
	finish()


## `structure_site_at()` is a tile-EXACT lookup. Its cost must come from the tile, never from
## how many other sites happen to be registered.
func _check_structure_lookup_is_indexed() -> void:
	var small: float = _time_structure_lookups(OTHERS_SMALL)
	var large: float = _time_structure_lookups(OTHERS_LARGE)
	var ratio: float = large / maxf(small, 1.0)
	check(
		ratio <= MAX_RATIO,
		"structure_site_at() cost is flat as unrelated sites grow %dx (ratio %.1fx, limit %.1fx)"
			% [OTHERS_LARGE / OTHERS_SMALL, ratio, MAX_RATIO],
		"%d lookups took %.0fus with %d other sites and %.0fus with %d — that is a linear scan "
			% [LOOKUPS, small, OTHERS_SMALL, large, OTHERS_LARGE]
		+ "over `_sites`, not an index."
	)


## Registering a rabbit must not care how many badgers exist. `rebuild_ownership()` computes
## each scope independently, so only the touched scope can possibly change.
func _check_register_ignores_other_scopes() -> void:
	var small: float = _time_subject_mutations(OTHERS_SMALL)
	var large: float = _time_subject_mutations(OTHERS_LARGE)
	var ratio: float = large / maxf(small, 1.0)
	check(
		ratio <= MAX_RATIO,
		"register()/unregister() cost is flat as OTHER species' sites grow %dx (ratio %.1fx, limit %.1fx)"
			% [OTHERS_LARGE / OTHERS_SMALL, ratio, MAX_RATIO],
		"%d mutations took %.0fus with %d other-species sites and %.0fus with %d — ownership is "
			% [MUTATIONS, small, OTHERS_SMALL, large, OTHERS_LARGE]
		+ "being rebuilt for every scope, not just the one that changed."
	)


func _time_structure_lookups(other_count: int) -> float:
	var registry: HomeSiteRegistry = _build(other_count)
	# A tile that IS a structure and a tile that is not, alternating, so neither the hit nor
	# the miss path can be the only one measured.
	var hit := Vector2i(1, 1)
	var miss := Vector2i(999, 999)
	registry.register_structure(hit, ["house"] as Array[String], 8)

	var t0: int = Time.get_ticks_usec()
	for i in LOOKUPS:
		registry.structure_site_at(hit if (i & 1) == 0 else miss)
	return float(Time.get_ticks_usec() - t0)


func _time_subject_mutations(other_count: int) -> float:
	var registry: HomeSiteRegistry = _build(other_count)
	var t0: int = Time.get_ticks_usec()
	for i in MUTATIONS:
		# A fresh position each time, well clear of the seeded sites.
		var site: HomeSite = registry.register(Vector2i(400 + i, 400), SUBJECT_SPECIES, 8)
		registry.unregister(site)
	return float(Time.get_ticks_usec() - t0)


## `SUBJECT_SITES` rabbits (constant) plus `other_count` sites spread across every OTHER
## species (the variable). Positions are unique so nothing collapses into one site.
func _build(other_count: int) -> HomeSiteRegistry:
	var registry := HomeSiteRegistry.new()
	for i in SUBJECT_SITES:
		registry.register(Vector2i(i * 2, 0), SUBJECT_SPECIES, 8)
	for i in other_count:
		var species: String = OTHER_SPECIES[i % OTHER_SPECIES.size()]
		registry.register(Vector2i(i % 40, 2 + i / 40), species, 8)
	return registry
