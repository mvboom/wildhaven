### Task 4: The tiered capacity formula

**Files:**
- Modify: `project/scripts/simulation/capacity_evaluator.gd`
- Test: `project/tests/test_tier_capacity.gd`

**Interfaces:**
- Consumes: `AnimalDefinition.effective_tiers()`, `legacy_tier()` (Task 2); `HabitatTier.max_radius()` (Task 1).
- Produces on `CapacityEvaluator`:
  - `static func count_key(tag: String, radius: int) -> String`
  - `static func tier_capacity_from_counts(counts: Dictionary, species: AnimalDefinition, tier: HabitatTier) -> int`
  - `static func tag_counts(grid, registry, origin, species, tier: HabitatTier, self_site = null) -> Dictionary` — **signature changes**, gaining `tier` before `self_site`
  - `static func best_tier(grid, registry, origin, species, self_site = null) -> HabitatTier`
  - `capacity()` and `qualifies()` keep their existing signatures.
  - `capacity_from_counts(counts, species)` keeps its existing signature and becomes a thin adapter — this is what keeps the 409-line `test_capacity_formula.gd` green without editing it.

**The one-walk rule:** do NOT walk the grid once per need. Walk once at `tier.max_radius()` and bucket each tile into every `(tag, radius)` pair whose squared radius it falls inside. Radii per tier are few (1–3), so the inner bucket loop is cheap and the tile walk stays a single pass.

- [ ] **Step 1: Write the failing test**

Create `project/tests/test_tier_capacity.gd`:

```gdscript
extends QATestCase
## The tiered capacity formula:
##
##   capacity(h, S) = max over tiers T of tier_capacity(h, S, T)
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/run-tests.sh tier_capacity`
Expected: FAIL — `Invalid call. Nonexistent function 'count_key' in base 'CapacityEvaluator'`.

- [ ] **Step 3: Write the implementation**

In `capacity_evaluator.gd`, add the key helper and the tiered formula, and rewrite `tag_counts`, `capacity` and `capacity_from_counts`:

```gdscript
## The counts-Dictionary key. Counts are per (tag, radius) pair, not per tag, because two
## needs in one tier may read the same tag over different distances — Horse's pair tier
## counts `open_grass` at 8 while its herd tier counts it at 14.
static func count_key(tag: String, radius: int) -> String:
	return "%s@%d" % [tag, radius]


## `count_t` for every (tag, radius) pair this TIER reads, over the tiles this candidate
## site may count.
##
## ONE WALK, NOT ONE PER NEED. The walk runs to `tier.max_radius()` and buckets each tile
## into every pair whose squared radius contains it. Radii per tier are few, so the inner
## bucket loop is cheaper than re-walking, and the cost shape stays `radius^2 * roster *
## tiers` — independent of world size, which is the property that matters.
##
## `self_site` is the already-registered site being re-evaluated, or null for a PROSPECTIVE
## candidate (a tile the player just edited, which no one lives on yet).
static func tag_counts(
	grid: WorldGrid,
	registry: HomeSiteRegistry,
	origin: Vector2i,
	species: AnimalDefinition,
	tier: HabitatTier,
	self_site: HomeSite = null
) -> Dictionary:
	var counts: Dictionary = {}
	if grid == null or species == null or tier == null:
		return counts

	var fallback: int = species.effective_capacity_radius()
	# Each bucket: the key to accumulate into, the tag to match, and its squared radius.
	var buckets: Array[Dictionary] = []
	for need: HabitatNeed in tier.needs:
		var nr: int = need.effective_radius(fallback)
		var nkey: String = count_key(need.tag, nr)
		counts[nkey] = 0
		buckets.append({"key": nkey, "tag": need.tag, "r_squared": nr * nr})
	for limit: HabitatLimit in tier.limits:
		var lr: int = limit.effective_radius(fallback)
		var lkey: String = count_key(limit.tag, lr)
		counts[lkey] = 0
		buckets.append({"key": lkey, "tag": limit.tag, "r_squared": lr * lr})
	if buckets.is_empty():
		return counts

	var r: int = tier.max_radius(fallback)
	var r_squared: int = r * r
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var d_squared: int = dx * dx + dz * dz
			if d_squared > r_squared:
				continue
			var tile: Vector2i = origin + Vector2i(dx, dz)
			if not grid.tile_in_bounds(tile):
				continue
			if not _tile_counts_for(registry, tile, origin, d_squared, self_site, species):
				continue
			var tile_tags: Array = grid.get_tile_tags(tile.x, tile.y)
			for bucket: Dictionary in buckets:
				if d_squared > int(bucket["r_squared"]):
					continue
				if tile_tags.has(bucket["tag"]):
					counts[bucket["key"]] = int(counts[bucket["key"]]) + 1
	return counts


## `tier_capacity(h, S, T)` — the formula for ONE tier, separated from the tile walk so it
## can be checked line by line without a world.
##
## Order is deliberate: limits gate first (cheapest rejection), then GATE_ONLY needs, then
## Liebig's min over the scaling needs against the TIER's cap.
static func tier_capacity_from_counts(
	counts: Dictionary, species: AnimalDefinition, tier: HabitatTier
) -> int:
	if species == null or tier == null or tier.needs.is_empty():
		return 0
	var fallback: int = species.effective_capacity_radius()

	for limit: HabitatLimit in tier.limits:
		var lr: int = limit.effective_radius(fallback)
		if int(counts.get(count_key(limit.tag, lr), 0)) > limit.max_count:
			return 0

	var result: int = tier.max_individuals
	for need: HabitatNeed in tier.needs:
		var nr: int = need.effective_radius(fallback)
		var count: int = int(counts.get(count_key(need.tag, nr), 0))
		if need.is_gate_only():
			if count < 1:
				return 0
			continue
		# Integer division floors for non-negative operands; counts are never negative.
		var supported: int = count / need.tiles_per_individual
		if supported < result:
			result = supported
	# NO LOWER CLAMP. `capacity == 0` is the unsuitable state and must survive to the caller.
	return max(result, 0)


## `capacity(h, S) = max over tiers of tier_capacity(h, S, T)`. Returns 0 for an unsuitable
## site — that is a real value, not a failure.
static func capacity(
	grid: WorldGrid,
	registry: HomeSiteRegistry,
	origin: Vector2i,
	species: AnimalDefinition,
	self_site: HomeSite = null
) -> int:
	if species == null:
		return 0
	var best: int = 0
	for tier: HabitatTier in species.effective_tiers():
		var counts: Dictionary = tag_counts(grid, registry, origin, species, tier, self_site)
		var value: int = tier_capacity_from_counts(counts, species, tier)
		if value > best:
			best = value
	return best


## The tier that produced `capacity()`'s value, or null when nothing qualifies.
##
## Needed by two callers that must know WHICH tier won, not just the number:
## `HabitatSimulation` reads `arrival_group_size` off it, and `HabitatRecipe` shows the
## player which tier they are on.
static func best_tier(
	grid: WorldGrid,
	registry: HomeSiteRegistry,
	origin: Vector2i,
	species: AnimalDefinition,
	self_site: HomeSite = null
) -> HabitatTier:
	if species == null:
		return null
	var best: int = 0
	var winner: HabitatTier = null
	for tier: HabitatTier in species.effective_tiers():
		var counts: Dictionary = tag_counts(grid, registry, origin, species, tier, self_site)
		var value: int = tier_capacity_from_counts(counts, species, tier)
		if value > best:
			best = value
			winner = tier
	return winner


## THE PRE-TIER ENTRY POINT, kept because `test_capacity_formula.gd` pins gdd.md's stated
## formula against it and takes bare-tag keys. It is now a thin adapter onto the tiered
## formula rather than a second copy of it — one formula, two key shapes.
##
## The re-key is exact: `legacy_tier()` sets every synthesised need's radius to
## `effective_capacity_radius()`, which is the radius used here.
static func capacity_from_counts(counts: Dictionary, species: AnimalDefinition) -> int:
	if species == null:
		return 0
	var tier: HabitatTier = species.legacy_tier()
	if tier == null:
		return 0
	var r: int = species.effective_capacity_radius()
	var rekeyed: Dictionary = {}
	for tag: String in counts:
		rekeyed[count_key(tag, r)] = counts[tag]
	return tier_capacity_from_counts(rekeyed, species, tier)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/run-tests.sh tier_capacity`
Expected: PASS, 11 assertions.

Run: `bash scripts/run-tests.sh capacity_formula`
Expected: **PASS, unchanged.** This is the key regression gate for the task — if this suite moved, the legacy adapter is wrong. Do not edit the suite to make it pass.

- [ ] **Step 5: Commit**

```
project/scripts/simulation/capacity_evaluator.gd   (modified)
project/tests/test_tier_capacity.gd                (new)
```

---

