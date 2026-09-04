### Task 2: `AnimalDefinition` gains tiers, emitted tags, and legacy synthesis

**Files:**
- Modify: `project/scripts/definitions/animal_definition.gd`
- Test: `project/tests/test_animal_tiers.gd`

**Interfaces:**
- Consumes: `HabitatNeed`, `HabitatLimit`, `HabitatTier` (Task 1).
- Produces on `AnimalDefinition`:
  - `@export var tiers: Array[HabitatTier]`
  - `@export var emits_tags: Array[String]`
  - `effective_tiers() -> Array[HabitatTier]` — authored tiers, or a one-element array holding the synthesised legacy tier
  - `legacy_tier() -> HabitatTier` — the synthesised tier, or `null` when `tiles_per_individual < 1`

**The critical guard:** the old `capacity_from_counts()` returned `0` when `tiles_per_individual < 1`, and `test_capacity_formula.gd` pins that. Under the new schema divisor `0` means `GATE_ONLY`, which is the opposite meaning. `legacy_tier()` MUST return `null` for `tiles_per_individual < 1` so that behaviour survives. Getting this wrong silently converts "unsuitable" into "always qualifies".

- [ ] **Step 1: Write the failing test**

Create `project/tests/test_animal_tiers.gd`:

```gdscript
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/run-tests.sh animal_tiers`
Expected: FAIL — `Invalid call. Nonexistent function 'effective_tiers' in base 'Resource'`.

- [ ] **Step 3: Write the implementation**

In `project/scripts/definitions/animal_definition.gd`, add these two exports immediately after the existing `max_individuals` export:

```gdscript
## Ordered habitat tiers — the ways this species can qualify, each with its own needs,
## limits, population cap and arrival group size. `capacity()` takes the MAX over them.
##
## EMPTY IS LEGAL AND IS THE MIGRATION PATH: a species with no tiers synthesises one from
## the flat `habitat_needs` / `tiles_per_individual` / `max_individuals` fields above, so
## the shipped roster converts one `.tres` at a time and a half-converted roster still runs.
## Read through `effective_tiers()`; never read this array raw.
@export var tiers: Array[HabitatTier] = []

## Tags a RESIDENT of this species contributes to the tile it lives on.
##
## This is what makes `people` an ordinary habitat tag rather than a second mechanic: a
## villager emits `people`, so a pug needing `people/5` is counted by the same formula as
## a fox needing `forest/4`. Deer emit `deer`, which is what gates Stag.
##
## Tags are counted PER INDIVIDUAL, not per home tile — a house holding four villagers
## reads as `people = 4`. See `CapacityEvaluator.tag_counts()`.
##
## Every entry here adds an edge to the graph `HabitatGraph.find_cycle()` checks: a cycle
## would make capacity oscillate forever across the dirty queue.
@export var emits_tags: Array[String] = []
```

Then add these two methods immediately before `validate()`:

```gdscript
## The tiers capacity actually evaluates — authored tiers, or a single synthesised tier
## built from the legacy flat fields. **Every capacity read must go through this**, the
## same contract `effective_capacity_radius()` establishes for the radius sentinel.
##
## Returns an EMPTY array when the legacy fields cannot form a valid tier (see
## `legacy_tier()`), which correctly yields capacity 0.
func effective_tiers() -> Array[HabitatTier]:
	if not tiers.is_empty():
		return tiers
	var synthesised: HabitatTier = legacy_tier()
	if synthesised == null:
		return []
	return [synthesised]


## The single tier equivalent to this species' flat legacy fields, or `null` when they
## cannot form one.
##
## RETURNS NULL WHEN `tiles_per_individual < 1`, and that is load-bearing. The pre-tier
## `capacity_from_counts()` returned 0 for a sub-1 divisor, and `test_capacity_formula.gd`
## pins it. Under the new schema divisor 0 means `GATE_ONLY` — the OPPOSITE meaning — so
## synthesising a tier here would silently convert "unsuitable" into "always qualifies".
##
## Note the radius: every synthesised need counts over `effective_capacity_radius()`, not
## `scout_radius`. `capacity_radius` is what the pre-tier tile walk used, and this
## synthesis must reproduce the old behaviour exactly.
##
## Cached: the evaluator calls this inside the dirty-queue drain, so it must not allocate
## per call.
func legacy_tier() -> HabitatTier:
	if tiles_per_individual < 1:
		return null
	if _legacy_tier_cache != null:
		return _legacy_tier_cache
	var tier := HabitatTier.new()
	tier.id = "legacy"
	tier.max_individuals = max_individuals
	tier.arrival_group_size = 1
	var built: Array[HabitatNeed] = []
	for tag: String in habitat_needs:
		var need := HabitatNeed.new()
		need.tag = tag
		need.radius = effective_capacity_radius()
		need.tiles_per_individual = tiles_per_individual
		built.append(need)
	tier.needs = built
	_legacy_tier_cache = tier
	return _legacy_tier_cache


## Backing store for `legacy_tier()`. Not exported — it is derived, never authored.
var _legacy_tier_cache: HabitatTier = null
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/run-tests.sh animal_tiers`
Expected: PASS, 14 assertions.

Run: `bash scripts/run-tests.sh capacity_formula`
Expected: PASS — nothing in the formula has changed yet, so the existing 409-line suite must still be green.

- [ ] **Step 5: Commit**

```
project/scripts/definitions/animal_definition.gd   (modified)
project/tests/test_animal_tiers.gd                 (new)
```

---


---

## AMENDMENT — 2026-09-04, human ruling (supersedes the baked-radius instruction above)

`legacy_tier()` must set `need.radius = HabitatNeed.RADIUS_FOLLOWS_SCOUT`, **not**
`effective_capacity_radius()`. The original instruction to bake a concrete radius is
WITHDRAWN.

Why: baking a concrete value into a *cached* tier means a later `scout_radius` retune
stops being tracked. Task 4's review found three affected paths, the worst being
`capacity_from_counts()` rekeying with a live radius against a baked tier — every need
then reads 0, which surfaces as "unsuitable" rather than as an error. The sentinel
resolves identically everywhere (every consumer computes `fallback` fresh), so caching
becomes safe and no second uncached builder is needed.
