### Task 1: The three new habitat resources

**Files:**
- Create: `project/scripts/definitions/habitat_need.gd`
- Create: `project/scripts/definitions/habitat_limit.gd`
- Create: `project/scripts/definitions/habitat_tier.gd`
- Test: `project/tests/test_habitat_tier_schema.gd`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `HabitatNeed` — `tag: String`, `radius: int`, `tiles_per_individual: int`; `const RADIUS_FOLLOWS_SCOUT: int = 0`, `const GATE_ONLY: int = 0`; `effective_radius(fallback_radius: int) -> int`, `is_gate_only() -> bool`, `validate() -> Array[String]`
  - `HabitatLimit` — `tag: String`, `radius: int`, `max_count: int`; `effective_radius(fallback_radius: int) -> int`, `validate() -> Array[String]`
  - `HabitatTier` — `id: String`, `needs: Array[HabitatNeed]`, `limits: Array[HabitatLimit]`, `max_individuals: int`, `arrival_group_size: int`; `max_radius(fallback_radius: int) -> int`, `validate() -> Array[String]`
  - `const RADIUS_MIN: int = 2`, `const RADIUS_MAX: int = 16` on `HabitatNeed` (the human's OQ-B ruling)

**Note on `effective_radius(fallback_radius: int)`:** it deliberately takes an `int`, not an `AnimalDefinition`. `AnimalDefinition` will hold `Array[HabitatTier]`, so a back-reference would make the three classes mutually dependent for no gain.

- [ ] **Step 1: Write the failing test**

Create `project/tests/test_habitat_tier_schema.gd`:

```gdscript
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/run-tests.sh habitat_tier_schema`
Expected: FAIL — the import pass reports that `HabitatNeed`, `HabitatLimit` and `HabitatTier` are not declared global classes.

- [ ] **Step 3: Write the implementation**

`project/scripts/definitions/habitat_need.gd`:

```gdscript
@tool
class_name HabitatNeed
extends Resource
## One positive habitat requirement inside a `HabitatTier`.
##
## A need carries its OWN radius and its OWN divisor, which is what lets one recipe say
## "a stable right here, and a wide tract of grass" — see
## docs/superpowers/specs/2026-09-04-habitat-tiers-design.md § 3.

## "Follow the species' capacity radius" — the relation, not a copy of the number.
## Same convention as `AnimalDefinition.CAPACITY_RADIUS_FOLLOWS_SCOUT`, for the same
## reason: a copied number silently stops being equal the first time the species is
## retuned. Resolve through `effective_radius()`; never read `radius` raw.
const RADIUS_FOLLOWS_SCOUT: int = 0

## "Must be present; contributes no population cap."
##
## This exists because a 1-tile Stable with an ordinary divisor of 1 would cap a herd at
## one horse — exactly backwards. The stable is a PRECONDITION, not the thing that scales
## the herd.
const GATE_ONLY: int = 0

## The per-need radius band (human ruling, 2026-09-04, spec OQ-B), replacing the old
## 8-12 band that `AnimalDefinition.validate()` applied to every radius alike. Cost scales
## as `max_radius^2 * roster * tiers`, so RADIUS_MAX is the real performance budget.
const RADIUS_MIN: int = 2
const RADIUS_MAX: int = 16

## The habitat tag required, drawn from `AnimalDefinition.HABITAT_TAGS`.
@export var tag: String = ""

## Tiles from the home site over which this tag is counted.
## `RADIUS_FOLLOWS_SCOUT` (0) means "follow the species".
@export_range(0, RADIUS_MAX, 1) var radius: int = RADIUS_FOLLOWS_SCOUT

## Qualifying tiles needed to support one individual. `GATE_ONLY` (0) means
## "present or not, never scaling".
@export_range(0, 64, 1) var tiles_per_individual: int = GATE_ONLY


## The radius this need actually counts over, sentinel resolved.
func effective_radius(fallback_radius: int) -> int:
	if radius == RADIUS_FOLLOWS_SCOUT:
		return fallback_radius
	return radius


## Is this a precondition rather than a scaling need?
func is_gate_only() -> bool:
	return tiles_per_individual == GATE_ONLY


## Non-fatal schema check. Empty array means clean.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if tag.strip_edges().is_empty():
		problems.append("`tag` is empty.")
	if radius != RADIUS_FOLLOWS_SCOUT and (radius < RADIUS_MIN or radius > RADIUS_MAX):
		problems.append(
			"`radius` %d for tag \"%s\" is outside the %d-%d band; use %d to follow the species."
			% [radius, tag, RADIUS_MIN, RADIUS_MAX, RADIUS_FOLLOWS_SCOUT]
		)
	if tiles_per_individual < 0:
		problems.append("`tiles_per_individual` %d is negative." % tiles_per_individual)
	return problems
```

`project/scripts/definitions/habitat_limit.gd`:

```gdscript
@tool
class_name HabitatLimit
extends Resource
## An EXCLUSION inside a `HabitatTier`: "at most `max_count` of `tag` within radius."
##
## Limits GATE, they never scale. A violated limit makes its whole tier score 0; it never
## reduces capacity partially. This is what makes wild animals want genuinely wild land
## rather than merely a different quantity of the same land — see the spec § 8.
##
## The counting is identical to a `HabitatNeed`'s: same tile walk, same cache, inverted
## comparison. An exclusion costs nothing extra.

const RADIUS_FOLLOWS_SCOUT: int = HabitatNeed.RADIUS_FOLLOWS_SCOUT

## The habitat tag being limited. `built` is the intended common case: every placeable
## emits it, so one limit excludes every building — including buildings added later.
@export var tag: String = ""

## Tiles from the home site over which this tag is counted.
@export_range(0, HabitatNeed.RADIUS_MAX, 1) var radius: int = RADIUS_FOLLOWS_SCOUT

## The ceiling. `0` means "none at all"; `2` means "a distant cottage is fine, a village
## is not" — the kinder default for a six-year-old who built in the wrong spot.
@export_range(0, 64, 1) var max_count: int = 0


## The radius this limit actually counts over, sentinel resolved.
func effective_radius(fallback_radius: int) -> int:
	if radius == RADIUS_FOLLOWS_SCOUT:
		return fallback_radius
	return radius


## Non-fatal schema check. Empty array means clean.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if tag.strip_edges().is_empty():
		problems.append("`tag` is empty.")
	if radius != RADIUS_FOLLOWS_SCOUT and (radius < HabitatNeed.RADIUS_MIN or radius > HabitatNeed.RADIUS_MAX):
		problems.append(
			"`radius` %d for limit \"%s\" is outside the %d-%d band."
			% [radius, tag, HabitatNeed.RADIUS_MIN, HabitatNeed.RADIUS_MAX]
		)
	if max_count < 0:
		problems.append("`max_count` %d is negative." % max_count)
	return problems
```

`project/scripts/definitions/habitat_tier.gd`:

```gdscript
@tool
class_name HabitatTier
extends Resource
## One way a species can qualify for a home site, with its own population cap.
##
## `capacity(h, S)` is the MAX over a species' tiers of this tier's own Liebig `min` —
## so "a barn and some grass gets you a pair; a stable, a wide tract and water gets you a
## herd" is one species with two tiers. See the spec § 4.
##
## ORDER IS PRESENTATIONAL ONLY. The formula takes a max, so authoring order must never be
## load-bearing.

## Internal identifier ("pair", "herd"). NOT player-facing — tier names were deliberately
## kept out of the Field Guide (spec § 13).
@export var id: String = ""

## The positive requirements. A tier with none is invalid: it would qualify on bare land.
@export var needs: Array[HabitatNeed] = []

## The exclusions. Optional.
@export var limits: Array[HabitatLimit] = []

## This tier's hard population cap — the outer `min` of the capacity formula.
@export_range(1, 64, 1) var max_individuals: int = 6

## How many individuals arrive together when this tier is the qualifying one.
@export_range(1, 16, 1) var arrival_group_size: int = 1


## The widest radius any need or limit in this tier counts over — the bound the tile walk
## uses, so one pass fills every bucket.
func max_radius(fallback_radius: int) -> int:
	var widest: int = fallback_radius
	for need: HabitatNeed in needs:
		widest = maxi(widest, need.effective_radius(fallback_radius))
	for limit: HabitatLimit in limits:
		widest = maxi(widest, limit.effective_radius(fallback_radius))
	return widest


## Non-fatal schema check, including every child need and limit. Empty array means clean.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if needs.is_empty():
		problems.append(
			"tier \"%s\" has no needs — a limits-only tier would qualify on bare land." % id
		)
	for i in range(needs.size()):
		if needs[i] == null:
			problems.append("tier \"%s\" `needs[%d]` is null." % [id, i])
			continue
		for problem: String in needs[i].validate():
			problems.append("tier \"%s\" needs[%d]: %s" % [id, i, problem])
	for i in range(limits.size()):
		if limits[i] == null:
			problems.append("tier \"%s\" `limits[%d]` is null." % [id, i])
			continue
		for problem: String in limits[i].validate():
			problems.append("tier \"%s\" limits[%d]: %s" % [id, i, problem])
	if max_individuals < 1:
		problems.append("tier \"%s\" `max_individuals` %d is below 1." % [id, max_individuals])
	if arrival_group_size < 1:
		problems.append("tier \"%s\" `arrival_group_size` %d is below 1." % [id, arrival_group_size])
	return problems
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/run-tests.sh habitat_tier_schema`
Expected: PASS, 13 assertions.

- [ ] **Step 5: Commit**

Report the changed paths, then commit them locally on the feature branch:
```
project/scripts/definitions/habitat_need.gd      (new)
project/scripts/definitions/habitat_limit.gd     (new)
project/scripts/definitions/habitat_tier.gd      (new)
project/tests/test_habitat_tier_schema.gd        (new)
```

---

