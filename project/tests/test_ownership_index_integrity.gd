extends QATestCase
## AN INDEX THAT DRIFTS IS WORSE THAN A LINEAR SCAN.
##
## `test_registry_scaling.gd` asserts that `structure_site_at()` and `rebuild_ownership()`
## stopped being linear work. That optimisation is only safe if the derived state it added
## stays in lockstep with `_sites` through EVERY mutation path — and `HomeSiteRegistry` has
## seven of them (`register`, `register_structure`, `restore_site`, `claim`, `release`,
## `relocate`, `unregister`), two of which (`claim`, `release`) MUTATE `site.species_id` and
## therefore move a site between scopes.
##
## So this suite never asserts a hand-written expectation. After each mutation it recomputes
## GROUND TRUTH the slow, obviously-correct way — a full scan of `sites()` for the structure
## lookup, a full unscoped `rebuild_ownership()` for the ownership map — and demands the fast
## path agree exactly. That makes the suite valid against the pre-optimisation code too
## (where it trivially holds), which is what proves the comparison itself is sound rather
## than accidentally asserting the bug.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_ownership_index_integrity.gd

## The tile window every comparison sweeps. Wide enough to cover every seeded site's radius.
const SWEEP_MIN: int = -4
const SWEEP_MAX: int = 24

var _registry: HomeSiteRegistry = null
var _scopes: Array[String] = []


func _initialize() -> void:
	begin("ownership index integrity")
	_seed()

	# Each step mutates, then demands the fast paths still match ground truth. They run in
	# sequence against ONE registry on purpose: drift is cumulative, and a bug that only
	# appears after a claim-then-release-then-relocate is exactly the kind an isolated
	# per-method test would miss.
	_after("seeding")

	var wild: HomeSite = _registry.register(Vector2i(5, 5), "fox", 9)
	_after("register() a wild den")

	var house: HomeSite = _registry.register_structure(
		Vector2i(9, 9), ["house"] as Array[String], 10)
	_after("register_structure() a House")

	_registry.claim(house, "villager", 10)
	_after("claim() the House — species_id changes, scope does not (still a structure)")

	var vacant: HomeSite = _registry.register_structure(
		Vector2i(14, 3), ["barn"] as Array[String], 8)
	_registry.claim(vacant, "cow", 8)
	_registry.release(vacant, true)
	_after("release(structure_remains = true) — site stays, species_id cleared")

	_registry.relocate(wild, Vector2i(18, 12))
	_after("relocate() the wild den")

	_registry.unregister(wild)
	_after("unregister() the wild den")

	_registry.release(house, false)
	_after("release(structure_remains = false) — the House leaves the registry entirely")

	var restored: HomeSite = _registry.restore_site(
		Vector2i(7, 16), "owl", 8, [] as Array[String])
	check(restored != null, "restore_site() returned a site")
	_after("restore_site() (the save-load path)")

	finish()


## A small mixed world: several species so the ownership map has several scopes, and a
## structure so the structure index has something in it from the start.
func _seed() -> void:
	_registry = HomeSiteRegistry.new()
	for i in 6:
		_registry.register(Vector2i(i * 3, 1), "rabbit", 8)
	for i in 4:
		_registry.register(Vector2i(i * 4, 8), "deer", 9)
	_registry.register_structure(Vector2i(2, 14), ["house"] as Array[String], 10)
	_scopes = [
		HomeSiteRegistry.STRUCTURE_SCOPE, "rabbit", "deer", "fox", "villager", "cow", "owl",
	]


func _after(label: String) -> void:
	_check_structure_lookup_matches_scan(label)
	_check_ownership_matches_full_rebuild(label)


## `structure_site_at()` vs the obviously-correct scan it replaced.
func _check_structure_lookup_matches_scan(label: String) -> void:
	var mismatches: Array[String] = []
	for x in range(SWEEP_MIN, SWEEP_MAX):
		for z in range(SWEEP_MIN, SWEEP_MAX):
			var tile := Vector2i(x, z)
			var fast: HomeSite = _registry.structure_site_at(tile)
			var truth: HomeSite = _scan_for_structure(tile)
			if fast != truth:
				mismatches.append("%s: fast=%s truth=%s" % [tile, fast, truth])
	check(
		mismatches.is_empty(),
		"structure_site_at() matches a full scan after %s" % label,
		"%d tile(s) disagree: %s" % [mismatches.size(), mismatches.slice(0, 5)]
	)


## The ownership map as it stands vs. the map a full, unscoped rebuild produces. Sampling
## every tile in every scope means a scoped rebuild that skipped a scope it should have
## touched shows up here as a concrete disagreeing tile, not as a vague suspicion.
func _check_ownership_matches_full_rebuild(label: String) -> void:
	var before: Dictionary = _snapshot_ownership()
	_registry.rebuild_ownership()  # no arguments = rebuild everything, the reference behaviour
	var after: Dictionary = _snapshot_ownership()

	var mismatches: Array[String] = []
	for key: String in before.keys():
		if before[key] != after[key]:
			mismatches.append("%s: had=%s full-rebuild=%s" % [key, before[key], after[key]])
	check(
		mismatches.is_empty(),
		"ownership map already equals a full rebuild after %s" % label,
		"%d tile/scope pair(s) were stale: %s" % [mismatches.size(), mismatches.slice(0, 5)]
	)


func _snapshot_ownership() -> Dictionary:
	var out: Dictionary = {}
	for scope: String in _scopes:
		for x in range(SWEEP_MIN, SWEEP_MAX):
			for z in range(SWEEP_MIN, SWEEP_MAX):
				var tile := Vector2i(x, z)
				out["%s@%s" % [scope, tile]] = _registry.owner_at(tile, scope)
	return out


func _scan_for_structure(position: Vector2i) -> HomeSite:
	for site: HomeSite in _registry.sites():
		if site.position == position and site.is_structure():
			return site
	return null
