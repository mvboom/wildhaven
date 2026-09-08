extends QATestCase
## TERRAIN SCATTER — the starting world's terrain mix (Open Question #10's second half).
##
## `TerrainScatter` is a pure static function with no node and no scene, so this suite
## exercises the generator directly rather than building a world. The four properties it
## asserts are the four the algorithm exists to guarantee:
##
##   1. EXACT COUNTS. Quotas sum to the tile count precisely and each terrain lands on the
##      floor or ceiling of its ideal share — the reason the generator is quota-fill and
##      not a per-tile weighted draw, which lands within a few percent and drifts per seed.
##   2. DETERMINISM. Same seed -> byte-identical grid; different seed -> a different one.
##   3. CLUMPING, measured rather than eyeballed: a uniform per-tile draw over the shipped
##      Meadow mix would give a same-terrain orthogonal-neighbour rate of ~0.26 (the sum of
##      the squared shares). Clumped output is far above that. A regression to confetti
##      would be invisible to a count check and is exactly what this catches.
##   4. GRACEFUL DEGRADATION. An unusable mix falls back to tag-INERT wild grass, never a
##      tag-emitting terrain — the same direction `WorldSnapshot.apply()` degrades in.
##
## Run:
##   bash scripts/run-tests.sh terrain_scatter

## The shipped Meadow Start mix, duplicated here ON PURPOSE. Reading meadow_start.tres
## instead would make this suite assert that the generator agrees with itself whatever the
## data says; the point is to pin the generator against a fixed mix so a data edit changes
## the world and not the test's meaning. `test_world_preset.gd` is what checks the shipped
## files.
const MIX: Dictionary = {
	"meadow": 0.40,
	"forest": 0.20,
	"scrub": 0.20,
	"wild_grass": 0.10,
	"water": 0.10,
}

const W: int = 36
const D: int = 36
const SEED_A: int = 987654321
const SEED_B: int = 123456789


func _initialize() -> void:
	begin("terrain scatter")

	var count: int = W * D
	var grid: PackedStringArray = TerrainScatter.generate(MIX, W, D, SEED_A)
	check_eq(grid.size(), count, "generate() fills every tile of the grid")

	# --- 1. Exact counts ---------------------------------------------------------------
	var counts: Dictionary = _tally(grid)
	var total: int = 0
	for id: String in counts:
		total += int(counts[id])
	check_eq(total, count, "the tallied tiles account for the whole grid")

	var quotas: Dictionary = TerrainScatter.quotas(MIX, count)
	var quota_total: int = 0
	for id: String in quotas:
		quota_total += int(quotas[id])
	check_eq(quota_total, count, "quotas sum to the tile count exactly, with no remainder lost")

	for id: String in MIX:
		var placed: int = int(counts.get(id, 0))
		check_eq(placed, int(quotas.get(id, -1)), "`%s` is placed exactly its quota" % id)
		# The quota itself must be the floor or ceiling of the ideal share — this is what
		# makes "exactly its quota" above mean "exactly the authored percentage".
		var ideal: float = float(MIX[id]) * float(count)
		check(
			absf(float(placed) - ideal) < 1.0,
			"`%s` lands within one tile of its %.0f%% share (%d vs %.1f)" % [
				id, float(MIX[id]) * 100.0, placed, ideal
			]
		)

	# Nothing outside the mix may appear — a stray wild_grass fallback leaking into a real
	# mix would silently hand the player inert land the preset never asked for.
	var stray: String = ""
	for id: String in counts:
		if not MIX.has(id):
			stray = id
	check_eq(stray, "", "every placed terrain is one the mix actually names")

	# --- 2. Determinism ----------------------------------------------------------------
	var repeat: PackedStringArray = TerrainScatter.generate(MIX, W, D, SEED_A)
	check(repeat == grid, "the same seed regenerates a byte-identical grid")

	var other: PackedStringArray = TerrainScatter.generate(MIX, W, D, SEED_B)
	check(other != grid, "a different seed gives a different grid")
	# ...but still the same counts. Layout is seeded; proportions are not.
	var other_counts: Dictionary = _tally(other)
	var proportions_held: bool = true
	for id: String in MIX:
		if int(other_counts.get(id, 0)) != int(counts.get(id, 0)):
			proportions_held = false
	check(proportions_held, "a different seed moves the terrain but keeps every count identical")

	# --- 3. Clumping -------------------------------------------------------------------
	# Expected rate for an independent per-tile draw is sum(share^2) = 0.26 for this mix.
	# The 0.50 threshold sits far above that and far below what clumped output measures, so
	# it fails loudly on a regression to confetti without being brittle about blob size.
	var uniform_rate: float = 0.0
	for id: String in MIX:
		uniform_rate += float(MIX[id]) * float(MIX[id])
	var clump_rate: float = _same_neighbour_rate(grid, W, D)
	check(
		clump_rate > 0.50,
		"terrain arrives in clumps, not confetti (%.2f same-neighbour vs %.2f if uniform)" % [
			clump_rate, uniform_rate
		],
		"a per-tile independent draw would score near %.2f; blobs score far higher" % uniform_rate
	)

	# --- 4. Degradation ----------------------------------------------------------------
	var empty: PackedStringArray = TerrainScatter.generate({}, W, D, SEED_A)
	check_eq(empty.size(), count, "an empty mix still fills the whole grid")
	check(
		_is_all(empty, WorldGrid.START_TERRAIN_ID),
		"an empty mix falls back to wild grass everywhere — today's exact starting world"
	)

	var junk: PackedStringArray = TerrainScatter.generate(
		{"forest": 0.0, "water": -1.0, "meadow": "lots"}, W, D, SEED_A
	)
	check(
		_is_all(junk, WorldGrid.START_TERRAIN_ID),
		"zero, negative and non-numeric weights degrade to tag-INERT wild grass",
		"degrading to a tag-emitting terrain would hand out capacity the player never made"
	)

	# --- Shape independence ------------------------------------------------------------
	# Non-square, and not 36 — `x * depth + z` indexing is easy to get right on a square and
	# wrong everywhere else, and the mist grows the grid to sizes no preset ever declares.
	var oblong: PackedStringArray = TerrainScatter.generate(MIX, 20, 31, SEED_A)
	check_eq(oblong.size(), 20 * 31, "a non-square grid is filled completely")
	var oblong_total: int = 0
	for id: String in _tally(oblong):
		oblong_total += int(_tally(oblong)[id])
	check_eq(oblong_total, 20 * 31, "a non-square grid's counts still account for every tile")

	_check_grid_wiring(quotas)

	finish()


## THE OTHER HALF OF THE FEATURE: `WorldGrid.build()` consuming a mix. Two things can go wrong
## here that the pure function cannot catch — the derived state `build()` maintains alongside
## `_terrain_ids` (`_forest_tile_count` and the per-tile tag masks) silently disagreeing with
## the terrain actually placed, and the default-argument path drifting away from the world every
## build before D-53 produced.
func _check_grid_wiring(quotas: Dictionary) -> void:
	var defs: Array[TerrainDefinition] = TerrainDefinition.load_all()

	# The no-mix path, which every suite and every editor F6 run takes. This must stay
	# byte-identical to the pre-D-53 behaviour; it is the reason `terrain_mix` defaults to `{}`
	# rather than to the default preset's own mix.
	var plain := WorldGrid.new()
	plain.build(defs, W, D)
	var plain_uniform: bool = true
	for x in W:
		for z in D:
			if plain.get_terrain_id(x, z) != WorldGrid.START_TERRAIN_ID:
				plain_uniform = false
	check(plain_uniform, "build() with no mix still fills 100% wild grass — the pre-D-53 world")
	check_eq(plain.forest_tile_count(), 0, "the no-mix world has no forest")
	plain.free()

	var grid := WorldGrid.new()
	grid.build(defs, W, D, MIX, SEED_A)

	# _forest_tile_count is an incremental index, not a derived read — if build() forgets to
	# seed it from the mix, the economy's free-Forest accrual is wrong from the first tick and
	# nothing else notices.
	check_eq(
		grid.forest_tile_count(),
		int(quotas.get("forest", -1)),
		"the grid's forest tile count matches the mix's forest quota"
	)

	# Tag masks are cached per tile at build time (see WorldGrid._tile_tag_masks). A meadow tile
	# whose mask is 0 would be invisible to the capacity evaluator while looking correct on
	# screen — the exact failure the cache's "one rule" exists to prevent.
	var meadow_bit: int = WorldGrid.tag_bit("flowers")
	var checked_meadow: bool = false
	var masks_agree: bool = true
	for x in W:
		for z in D:
			if grid.get_terrain_id(x, z) != "meadow":
				continue
			checked_meadow = true
			if grid.tile_tag_mask(x, z) & meadow_bit == 0:
				masks_agree = false
	check(checked_meadow, "the built world actually contains meadow to check")
	check(masks_agree, "every meadow tile's cached tag mask carries `flowers`")

	# Wild grass is in the mix precisely so some of the starting world stays claimable. If its
	# mask were non-zero the inert-land invariant would be broken by the terrain data, not by
	# D-53's deliberate exemption.
	var inert_holds: bool = true
	for x in W:
		for z in D:
			if grid.get_terrain_id(x, z) == WorldGrid.START_TERRAIN_ID:
				if grid.tile_tag_mask(x, z) != 0:
					inert_holds = false
	check(inert_holds, "wild grass tiles inside a mix are still tag-inert")

	grid.free()


func _tally(grid: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for id: String in grid:
		out[id] = int(out.get(id, 0)) + 1
	return out


func _is_all(grid: PackedStringArray, id: String) -> bool:
	for entry: String in grid:
		if entry != id:
			return false
	return true


## Share of orthogonally adjacent tile PAIRS that hold the same terrain. High for blobs,
## low for noise — the one number that separates "a pond" from "130 puddles".
func _same_neighbour_rate(grid: PackedStringArray, width: int, depth: int) -> float:
	var same: int = 0
	var pairs: int = 0
	for x in width:
		for z in depth:
			var here: String = grid[x * depth + z]
			if x + 1 < width:
				pairs += 1
				if grid[(x + 1) * depth + z] == here:
					same += 1
			if z + 1 < depth:
				pairs += 1
				if grid[x * depth + z + 1] == here:
					same += 1
	if pairs == 0:
		return 0.0
	return float(same) / float(pairs)
