class_name TerrainScatter
extends RefCounted
## THE STARTING WORLD'S TERRAIN MIX — Open Question #10's second half, as a pure function.
##
## `WorldPreset.terrain_mix` says WHAT proportions a New Game starts with; this file says
## WHERE those tiles land. Deliberately shaped like `MistReveal`: a static function over
## (mix, width, depth, world_seed) with no node, no signal and no scene, so the whole
## generator is testable headless without building a world (`test_terrain_scatter.gd`).
##
## TWO PROPERTIES THE ALGORITHM EXISTS TO GUARANTEE, in this order:
##
## 1. **EXACT COUNTS, NOT APPROXIMATE ONES.** Weights become integer tile quotas by
##    largest-remainder before a single tile is placed, so a 10% water mix on a 36x36 is
##    exactly 130 tiles — never "about 130". That is what lets the suite assert counts
##    rather than tolerances, and it is why this is quota-fill rather than the obvious
##    per-tile weighted draw (which lands within a few percent and drifts per seed).
##
## 2. **CLUMPS, NOT CONFETTI.** A per-tile independent draw is the naive reading of
##    "randomized on where the content appears" and it looks wrong: 10% water at 36x36
##    scatters ~130 isolated one-tile puddles instead of a pond, and — because Forest sets
##    `blocks_movement` — a 60% forest start becomes uniform noise that walls villagers
##    into random pockets. Each terrain is instead ranked by its OWN noise field and takes
##    the highest-scoring tiles, and a noise field's high region is contiguous, so each
##    terrain arrives as blobs: woods, ponds, meadows.
##
## DETERMINISTIC FROM `world_seed` ALONE. Same seed, same mix, same dimensions -> the same
## grid, on every machine and every reload. Nothing here reads the clock or `randi()`. The
## world's terrain is written per-tile into the save (`WorldSnapshot.capture()`), so this
## determinism is not what makes a load correct — it is what makes the suite's "same seed
## twice" assertion meaningful and a reported world reproducible.

## Noise frequency, and therefore blob SIZE — lower is bigger, smoother regions; higher
## breaks the same quota into more, smaller patches. At 0.09 a 36x36 gets a handful of
## readable stands and ponds rather than one continent or a spray of specks.
##
## PROPOSED (2026-09-07), not decided — this is a tuning value and tuning values are the
## human's (`.claude/CLAUDE.md`). Ruling it needs eyes on a built world, not a test.
const CLUMP_FREQUENCY: float = 0.09


## `mix` with its keys normalized and its junk dropped: non-numeric values, non-positive
## weights and empty ids are skipped, and two keys that normalize to the same terrain
## ("Forest" and "forest") have their weights summed rather than one silently winning.
##
## Weights are RELATIVE, never required to total 1.0 or 100 — the shipped presets are
## authored as fractions purely because that reads best in the `.tres`.
static func normalized_mix(mix: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in mix:
		var raw: Variant = mix[key]
		if not (raw is float or raw is int):
			continue
		var weight: float = float(raw)
		var id: String = TerrainDefinition.normalize_id(str(key))
		if id.is_empty() or weight <= 0.0:
			continue
		out[id] = float(out.get(id, 0.0)) + weight
	return out


## terrain id -> exact tile count, summing to `tile_count` precisely. Empty when the mix
## carries nothing usable, which is the caller's signal to fall back to a uniform fill.
##
## LARGEST REMAINDER, not per-terrain rounding: rounding each share independently
## overshoots or undershoots the grid, and the leftover has to go somewhere anyway. Ties in
## the remainder break on the id so the answer does not depend on `Dictionary` iteration
## order, which is insertion order and therefore an artifact of how the `.tres` was typed.
static func quotas(mix: Dictionary, tile_count: int) -> Dictionary:
	var weights: Dictionary = normalized_mix(mix)
	if weights.is_empty() or tile_count <= 0:
		return {}

	var ids: Array[String] = []
	var total_weight: float = 0.0
	for id: String in weights:
		ids.append(id)
		total_weight += float(weights[id])
	ids.sort()

	var out: Dictionary = {}
	var order: Array = []  # [fractional remainder, id]
	var assigned: int = 0
	for id: String in ids:
		var exact: float = float(weights[id]) / total_weight * float(tile_count)
		var floored: int = int(floor(exact))
		out[id] = floored
		assigned += floored
		order.append([exact - float(floored), id])

	order.sort_custom(func(a: Array, b: Array) -> bool:
		if float(a[0]) == float(b[0]):
			return String(a[1]) < String(b[1])
		return float(a[0]) > float(b[0]))

	# Largest remainder first. The `% size()` wrap can never be reached by largest-remainder
	# arithmetic (the shortfall is always < the number of terrains); it is there so a caller
	# that hands in a degenerate mix gets a full grid instead of a partly-empty one.
	var i: int = 0
	while assigned < tile_count:
		var id: String = String(order[i % order.size()][1])
		out[id] = int(out[id]) + 1
		assigned += 1
		i += 1
	return out


## The starting terrain for every tile, row-major in `WorldGrid`'s own `x * depth + z`
## order so the caller can copy it across without re-indexing.
##
## An unusable mix (empty, all-zero weights, non-numeric values) yields a full grid of
## `WorldGrid.START_TERRAIN_ID` — the tag-inert fallback, never a tag-emitting one, matching
## how `WorldSnapshot.apply()` degrades an unknown terrain id.
static func generate(mix: Dictionary, width: int, depth: int, world_seed: int) -> PackedStringArray:
	var w: int = maxi(1, width)
	var d: int = maxi(1, depth)
	var count: int = w * d

	var out: PackedStringArray = PackedStringArray()
	out.resize(count)

	var counts: Dictionary = quotas(mix, count)
	if counts.is_empty():
		for i in count:
			out[i] = WorldGrid.START_TERRAIN_ID
		return out

	# RAREST FIRST, background last. The largest share is pre-filled and every other terrain
	# carves out of it, so the rare features (a 10% pond) get first pick of their own noise
	# field's best region instead of whatever the common terrains left behind. The id
	# tie-break makes this a total order — `sort_custom` is not documented as stable, so two
	# terrains on equal quotas must not be allowed to swap between runs.
	var ids: Array[String] = []
	for id: String in counts:
		ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		if int(counts[a]) == int(counts[b]):
			return a < b
		return int(counts[a]) < int(counts[b]))

	var background: String = ids[ids.size() - 1]
	for i in count:
		out[i] = background

	var taken: PackedByteArray = PackedByteArray()
	taken.resize(count)

	for k in ids.size() - 1:
		var id: String = ids[k]
		var quota: int = int(counts[id])
		if quota <= 0:
			continue

		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = CLUMP_FREQUENCY
		noise.seed = _field_seed(world_seed, id)

		var scores: PackedFloat32Array = PackedFloat32Array()
		scores.resize(count)
		var free: Array[int] = []
		for x in w:
			for z in d:
				var i: int = x * d + z
				if taken[i] != 0:
					continue
				scores[i] = noise.get_noise_2d(float(x), float(z))
				free.append(i)

		# Highest noise first; the tile index breaks ties so two tiles that sample the same
		# value cannot trade places between runs.
		free.sort_custom(func(a: int, b: int) -> bool:
			if scores[a] == scores[b]:
				return a < b
			return scores[a] > scores[b])

		var claim: int = mini(quota, free.size())
		for n in claim:
			var i: int = free[n]
			out[i] = id
			taken[i] = 1

	return out


## A per-terrain noise seed, so two terrains in the same world do not share a field and
## stack their blobs on the same tiles. Masked to 31 bits because `FastNoiseLite.seed` is a
## 32-bit signed int and `world_seed` is not.
static func _field_seed(world_seed: int, terrain_id: String) -> int:
	return int((world_seed ^ hash(terrain_id)) & 0x7fffffff)
