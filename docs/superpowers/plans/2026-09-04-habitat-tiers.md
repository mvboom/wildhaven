# Habitat Tiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every species a distinct habitat signature by replacing the flat one-recipe habitat model with ordered tiers, per-need radii and divisors, exclusion limits, and resident-emitted tags.

**Architecture:** A species gains `tiers: Array[HabitatTier]`; each tier holds `needs` (tag + own radius + own divisor, where divisor 0 means "gate only"), `limits` (tag + radius + max count), its own `max_individuals`, and its own `arrival_group_size`. `capacity()` becomes `max` over tiers of the existing Liebig `min` within a tier. A species may also declare `emits_tags`, letting a *resident* contribute tags — which is how `people` and `deer` become ordinary habitat tags. Species with no `tiers` synthesise one from their existing flat fields, so the sixteen shipped `.tres` files convert one at a time and a half-converted roster still runs.

**Tech Stack:** Godot 4.7 (GDScript, statically typed), `.tres` Resource data files, headless `QATestCase` suites driven by `scripts/run-tests.sh`.

**Spec:** `docs/superpowers/specs/2026-09-04-habitat-tiers-design.md`

## Global Constraints

- **Local git only.** `.claude/CLAUDE.md` says *"The human runs all git"*, but the human lifted that in-session on 2026-09-04: **branching and local commits are authorised.** Each task ends with a local commit on the feature branch. **Still gated, and never without a fresh explicit ask:** `git push` (any branch, any flags), `gh pr create` / `gh pr merge`, merging or committing to `main`, pushing tags, rewriting pushed history. Also avoid `git stash -u` — it aborts on repo-root dotfiles and leaves untracked files staged, poisoning the next commit.
- **Commit message trailers.** End every commit message with:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01RpgoLMRdrQtz82xcABRPUf
  ```
- **All tuning values are the human's.** *"Agents propose with sources; the human decides."* Every number written into a `.tres` in Tasks 7–9 is a **proposal**. Each such file gets a header comment saying so, matching the existing convention in `project/data/animals/horse.tres` and `barn.tres`.
- **Validation is headless-only, and `--import` must run before `--script`.** A bare `--quit` is a parse check that reports false green. Use `bash scripts/run-tests.sh [filter]` — it runs the import pass itself. Never hand-roll the Godot invocation.
- **The engine binary** is `$GODOT_PATH`, defaulting to `godot/Godot_v4.7-stable_mono_linux.x86_64`.
- **Extending `HABITAT_TAGS` is a human gate** (stated in `animal_definition.gd`). Task 3 performs the extension the human ruled on 2026-09-04; do not add tags beyond that list.
- **`validate()` is non-fatal by contract.** It returns human-readable problem strings, never raises, never mutates, never rejects a load. Preserve that in every new check.
- **Sentinel convention:** `0` means *"follow the species radius"*, never *"a radius of zero"* — matching the existing `CAPACITY_RADIUS_FOLLOWS_SCOUT`. Always resolve through an `effective_*()` helper; never read the raw field.
- **Style:** static typing everywhere, typed loop variables (`for tag: String in ...`), `##` doc comments on every public member. Match the surrounding files.

---

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

### Task 3: Vocabulary extension, radius band replacement, and the new validation rules

**Files:**
- Modify: `project/scripts/definitions/animal_definition.gd`
- Create: `project/scripts/definitions/habitat_graph.gd`
- Test: `project/tests/test_habitat_validation.gd`

**Interfaces:**
- Consumes: `effective_tiers()` (Task 2).
- Produces:
  - Extended `AnimalDefinition.HABITAT_TAGS` (adds `built` `people` `deer` `browse` `snow` `barn` `large_barn` `large_house` `stable` `coop` `silo` `mill`; removes `quiet`)
  - `AnimalDefinition.BUILDING_TAGS: PackedStringArray` — the subset emitted by placeables
  - `AnimalDefinition.category() -> String` returning `"person"` / `"wild"` / `"domesticated"` / `""`
  - `HabitatGraph.find_cycle(species: Array[AnimalDefinition]) -> Array[String]` — the offending ids, empty when acyclic

**Category precedence (spec § 6.4), in this order:**
1. **Person** — needs **or emits** `people`. Checked first: Villager emits `people` without consuming it, and the dogs gate on `house*` so they would otherwise read as Domesticated.
2. **Wild** — no building tag in any need, and carries at least one limit.
3. **Domesticated** — at least one building tag as a `GATE_ONLY` need, and no `built` limit.

A species matching none returns `""` and is a **warning, not an error** — it means design intent is unclear, not that data is broken.

**Radius band:** delete the two `scout_radius` / `capacity_radius` 8–12 checks in `validate()` and replace with a `2–16` band applied to `scout_radius`, `capacity_radius` (sentinel exempt) and every per-need radius. This is the human's OQ-B ruling and is required — Stag counts at radius 14 and a barn gate counts at radius 4.

- [ ] **Step 1: Write the failing test**

Create `project/tests/test_habitat_validation.gd`:

```gdscript
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/run-tests.sh habitat_validation`
Expected: FAIL — `HabitatGraph` is not a declared global class, and `category()` does not exist.

- [ ] **Step 3: Write the implementation**

In `animal_definition.gd`, **replace** the `HABITAT_TAGS` const with:

```gdscript
## The shared habitat tag vocabulary. Extending it is a system-wide design decision
## reserved for the human (gdd.md -> Content Pipelines -> Add-a-Terrain, "extra human
## gate"); this list is used only to REPORT unknown tags, never to reject or drop them.
##
## Extended 2026-09-04 by the habitat-tiers ruling. `quiet` was RETIRED: it had no source
## and no consumer, and a `built` limit does its job strictly better because it is actually
## enforced and needs no terrain to emit it.
const HABITAT_TAGS: PackedStringArray = [
	# Terrain-emitted
	"water", "forest", "open_grass", "browse", "cover", "flowers", "sand", "rocks",
	"cultivated", "snow",
	# Building-emitted
	"built", "house", "large_house", "barn", "large_barn", "stable", "coop", "silo", "mill",
	# Resident-emitted
	"people", "deer",
]

## The subset of HABITAT_TAGS emitted by placeables rather than terrain. Used by
## `category()` to tell a Domesticated species (which gates on a building) from a Wild one
## (which does not). `built` is deliberately included: it is emitted by every placeable.
const BUILDING_TAGS: PackedStringArray = [
	"built", "house", "large_house", "barn", "large_barn", "stable", "coop", "silo", "mill",
]

## Category names returned by `category()`.
const CATEGORY_PERSON: String = "person"
const CATEGORY_WILD: String = "wild"
const CATEGORY_DOMESTICATED: String = "domesticated"
```

Add `category()` immediately after `effective_tiers()`:

```gdscript
## Which of the three design categories this species' DATA says it belongs to, or `""`
## when it matches none.
##
## PRECEDENCE MATTERS and is not arbitrary. Person is tested first because Villager emits
## `people` without consuming it, and because Pug and Shiba Inu gate on `house*` and would
## otherwise read as Domesticated. The categories are not disjoint sets; this is an ordered
## test.
func category() -> String:
	var tiers_to_read: Array[HabitatTier] = effective_tiers()
	var needs_people: bool = false
	var has_building_gate: bool = false
	var has_building_need: bool = false
	var has_limit: bool = false
	for tier: HabitatTier in tiers_to_read:
		for need: HabitatNeed in tier.needs:
			if need.tag == "people":
				needs_people = true
			if BUILDING_TAGS.has(need.tag):
				has_building_need = true
				if need.is_gate_only():
					has_building_gate = true
		if not tier.limits.is_empty():
			has_limit = true

	if needs_people or emits_tags.has("people"):
		return CATEGORY_PERSON
	if not has_building_need and has_limit:
		return CATEGORY_WILD
	if has_building_gate:
		return CATEGORY_DOMESTICATED
	return ""
```

In `validate()`, **delete** the two existing radius-band blocks (the `scout_radius < 8 or scout_radius > 12` check and the `capacity_radius` 8–12 check) and put in their place:

```gdscript
	# THE RADIUS BAND, replaced 2026-09-04 (spec OQ-B). The old 8-12 band predates
	# per-need radii and would hard-fail this design's own central cases: a barn gate at
	# radius 4 and Stag counting at radius 14. Cost scales as `max_radius^2 * roster *
	# tiers`, so RADIUS_MAX is the performance budget, not a style preference.
	if scout_radius < HabitatNeed.RADIUS_MIN or scout_radius > HabitatNeed.RADIUS_MAX:
		problems.append("`scout_radius` %d is outside the %d-%d band." % [
			scout_radius, HabitatNeed.RADIUS_MIN, HabitatNeed.RADIUS_MAX
		])
	if capacity_radius != CAPACITY_RADIUS_FOLLOWS_SCOUT and (
		capacity_radius < HabitatNeed.RADIUS_MIN or capacity_radius > HabitatNeed.RADIUS_MAX
	):
		problems.append("`capacity_radius` %d is outside the %d-%d band; use %d to follow `scout_radius`." % [
			capacity_radius, HabitatNeed.RADIUS_MIN, HabitatNeed.RADIUS_MAX,
			CAPACITY_RADIUS_FOLLOWS_SCOUT
		])
```

**Replace** the existing inert-land block with one that reads tiers and ignores limits:

```gdscript
	# THE INERT-LAND INVARIANT (gdd.md -> Data Schemas; -> D-22), now tier-aware.
	# POSITIVE NEEDS ONLY: a `HabitatLimit` may never be what makes a species non-bare,
	# because a limit describes what must be ABSENT and absence is what bare land is made of.
	for tier: HabitatTier in effective_tiers():
		if tier.needs.is_empty():
			continue
		var only_bare: bool = true
		for need: HabitatNeed in tier.needs:
			if not BARE_TAGS.has(need.tag):
				only_bare = false
				break
		if only_bare:
			problems.append(
				"tier \"%s\" is satisfiable by untouched revealed land (bare tags: %s) — breaks the inert-land invariant."
				% [tier.id, str(BARE_TAGS)]
			)
```

Add tier and category checks at the end of `validate()`, before the `known_ids` block:

```gdscript
	for tier: HabitatTier in effective_tiers():
		for problem: String in tier.validate():
			problems.append(problem)
		for need: HabitatNeed in tier.needs:
			if not HABITAT_TAGS.has(need.tag):
				problems.append("tier \"%s\" need tag \"%s\" is not in the shared vocabulary." % [tier.id, need.tag])
		for limit: HabitatLimit in tier.limits:
			if not HABITAT_TAGS.has(limit.tag):
				problems.append("tier \"%s\" limit tag \"%s\" is not in the shared vocabulary." % [tier.id, limit.tag])

	for tag: String in emits_tags:
		if not HABITAT_TAGS.has(tag):
			problems.append("`emits_tags` entry \"%s\" is not in the shared vocabulary." % tag)

	# A species matching no category is a WARNING, not an error: it means design intent is
	# unclear, not that the data is broken.
	if category() == "":
		problems.append(
			"matches none of person/wild/domesticated — design intent unclear (warning, not a defect)."
		)
```

Create `project/scripts/definitions/habitat_graph.gd`:

```gdscript
class_name HabitatGraph
extends RefCounted
## The acyclicity check over resident-emitted tags.
##
## Two real edges ship: `human -> people -> {pug, shiba_inu, husky, pig, sheep}` and
## `deer -> deer -> stag`. Neither closes a loop. This check exists so the THIRD one added
## does not: a cycle makes capacity oscillate forever across the dirty queue, because each
## species' arrival re-marks the neighbourhood dirty, which re-evaluates the other, which
## arrives, which re-marks... It is the one genuinely new failure mode tiers introduce.


## Species ids participating in a dependency cycle, or an empty array when the graph is
## acyclic. Ids are returned unsorted; callers use only emptiness and the names.
static func find_cycle(species: Array[AnimalDefinition]) -> Array[String]:
	# tag -> ids of species that EMIT it
	var emitters: Dictionary = {}
	for def: AnimalDefinition in species:
		if def == null:
			continue
		for tag: String in def.emits_tags:
			if not emitters.has(tag):
				emitters[tag] = [] as Array[String]
			(emitters[tag] as Array[String]).append(def.id)

	# id -> ids it depends on (it needs a tag they emit)
	var edges: Dictionary = {}
	for def: AnimalDefinition in species:
		if def == null:
			continue
		var depends_on: Array[String] = []
		for tier: HabitatTier in def.effective_tiers():
			for need: HabitatNeed in tier.needs:
				if not emitters.has(need.tag):
					continue
				for emitter_id: String in emitters[need.tag] as Array[String]:
					# Self-emission (deer needing `deer`) is a POPULATION THRESHOLD, not a
					# cycle: more deer make more deer possible, which terminates because
					# deer also need finite land. Only cross-species loops diverge.
					if emitter_id != def.id and not depends_on.has(emitter_id):
						depends_on.append(emitter_id)
		edges[def.id] = depends_on

	var offenders: Array[String] = []
	var permanent: Dictionary = {}
	var in_stack: Dictionary = {}
	for def: AnimalDefinition in species:
		if def == null or permanent.has(def.id):
			continue
		_visit(def.id, edges, permanent, in_stack, offenders)
	return offenders


## Depth-first visit. A node reached while already on the stack closes a cycle.
static func _visit(
	id: String,
	edges: Dictionary,
	permanent: Dictionary,
	in_stack: Dictionary,
	offenders: Array[String]
) -> void:
	if permanent.has(id):
		return
	if in_stack.has(id):
		if not offenders.has(id):
			offenders.append(id)
		return
	in_stack[id] = true
	for next_id: String in edges.get(id, [] as Array[String]) as Array[String]:
		_visit(next_id, edges, permanent, in_stack, offenders)
	in_stack.erase(id)
	permanent[id] = true
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/run-tests.sh habitat_validation`
Expected: PASS, 16 assertions.

Run: `bash scripts/run-tests.sh`
Expected: **Some existing suites will now FAIL**, and that is correct at this point — `quiet` left the vocabulary and the radius band moved. Record every failing suite name; Task 9 fixes the roster data that causes them. Do not "fix" a suite by widening the vocabulary back.

- [ ] **Step 5: Commit**

```
project/scripts/definitions/animal_definition.gd   (modified)
project/scripts/definitions/habitat_graph.gd       (new)
project/tests/test_habitat_validation.gd           (new)
```
Also report the list of suites that now fail, so the human can see the blast radius before Task 9 closes it.

---

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

### Task 5: Resident-emitted tags counted per individual

**Files:**
- Modify: `project/scripts/simulation/home_site.gd`
- Modify: `project/scripts/simulation/home_site_registry.gd`
- Modify: `project/scripts/simulation/capacity_evaluator.gd`
- Modify: `project/scripts/simulation/habitat_simulation.gd`
- Test: `project/tests/test_resident_tags.gd`

**Interfaces:**
- Consumes: `AnimalDefinition.emits_tags` (Task 2); `CapacityEvaluator.tag_counts()` (Task 4).
- Produces:
  - `HomeSite.resident_tags: Array[String]` — derived at claim/restore time, **never persisted**
  - `HomeSiteRegistry.sites_at(position: Vector2i) -> Array[HomeSite]`
  - `tag_counts()` adds resident contributions to the same buckets

**THE BUG THIS TASK EXISTS TO AVOID:** residents count **per individual, not per home tile**. A house holding four villagers must read `people = 4`. Counted per-tile, "one pug per five people" silently becomes "one pug per five houses" — it looks plausible in play and is wrong.

**Why `resident_tags` lives on the site:** `CapacityEvaluator` has no roster and therefore cannot map a `species_id` back to its `emits_tags`. Caching the tags on the site at claim time avoids threading the roster through every call. It is derived state, so it is re-derived on load rather than saved.

- [ ] **Step 1: Write the failing test**

Create `project/tests/test_resident_tags.gd`:

```gdscript
extends QATestCase
## Resident-emitted tags: `people` and `deer` are ordinary habitat tags contributed by
## RESIDENTS rather than by tiles.
##
## Run:
##   bash scripts/run-tests.sh resident_tags

func _init() -> void:
	begin("resident tags")
	_check_sites_at()
	_check_counted_per_individual()
	_check_absent_when_vacant()
	finish()


func _check_sites_at() -> void:
	var registry := HomeSiteRegistry.new()
	var a: HomeSite = registry.register(Vector2i(4, 4), "human", 9)
	var b: HomeSite = registry.register(Vector2i(4, 4), "husky", 9)
	var found: Array[HomeSite] = registry.sites_at(Vector2i(4, 4))
	check_eq(found.size(), 2, "sites_at returns every site sharing a tile")
	check(found.has(a) and found.has(b), "both sites are returned")
	check_eq(registry.sites_at(Vector2i(9, 9)).size(), 0, "an empty tile returns none")


## The load-bearing assertion of this task.
func _check_counted_per_individual() -> void:
	var site := HomeSite.new(Vector2i(0, 0), "human", 9, 0)
	site.resident_tags = ["people"] as Array[String]
	for i in range(4):
		site.residents.append(Node3D.new())
	check_eq(site.population(), 4, "four villagers live here")
	var contributed: Dictionary = {}
	for tag: String in site.resident_tags:
		contributed[tag] = int(contributed.get(tag, 0)) + site.population()
	check_eq(
		int(contributed["people"]), 4,
		"ONE house with four villagers contributes people=4, NOT people=1"
	)
	for resident: Node3D in site.residents:
		resident.free()


func _check_absent_when_vacant() -> void:
	var site := HomeSite.new(Vector2i(0, 0), "human", 9, 0)
	site.resident_tags = ["people"] as Array[String]
	check_eq(site.population(), 0, "a vacant site has no residents")
	check(site.is_vacant(), "an empty house is vacant")
	# An empty house must NOT satisfy a dog's `people` need — that is the whole point of
	# the resident-emitted mechanic over a plain `house` tag.
	check_eq(site.population() * site.resident_tags.size(), 0, "a vacant site contributes nothing")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/run-tests.sh resident_tags`
Expected: FAIL — `Invalid set index 'resident_tags'` and `Nonexistent function 'sites_at'`.

- [ ] **Step 3: Write the implementation**

In `home_site.gd`, add beside the existing `structure_tags` declaration:

```gdscript
## Tags this site's RESIDENTS contribute to its tile, copied from the species'
## `emits_tags` when the site is claimed.
##
## DERIVED, NEVER PERSISTED. It is re-copied from the species on load, so a retuned
## `.tres` takes effect immediately rather than being frozen into old saves.
##
## Cached here rather than looked up because `CapacityEvaluator` holds no roster and so
## cannot map `species_id` back to an `AnimalDefinition`.
var resident_tags: Array[String] = []
```

In `home_site_registry.gd`, add beside `sites_covering()`:

```gdscript
## Every site whose position is exactly `position`, of any species.
##
## Distinct from `sites_covering()`, which returns sites whose RADIUS reaches a tile.
## Residents live at their site's own position, so resident-tag counting needs this
## tile-exact form.
func sites_at(position: Vector2i) -> Array[HomeSite]:
	var found: Array[HomeSite] = []
	for site: HomeSite in _sites:
		if site.position == position:
			found.append(site)
	return found
```

In `capacity_evaluator.gd`, inside `tag_counts()`, replace the bucket-accumulation block with one that also reads residents:

```gdscript
			var tile_tags: Array = grid.get_tile_tags(tile.x, tile.y)
			# Resident-emitted tags, counted PER INDIVIDUAL. A house holding four villagers
			# contributes people=4. Counting this per-tile instead would silently turn
			# "one pug per five people" into "one pug per five houses".
			var resident_counts: Dictionary = {}
			if registry != null:
				for resident_site: HomeSite in registry.sites_at(tile):
					if resident_site == self_site:
						continue
					var population: int = resident_site.population()
					if population < 1:
						continue
					for emitted: String in resident_site.resident_tags:
						resident_counts[emitted] = int(resident_counts.get(emitted, 0)) + population
			for bucket: Dictionary in buckets:
				if d_squared > int(bucket["r_squared"]):
					continue
				var bucket_tag: String = bucket["tag"]
				var added: int = 0
				if tile_tags.has(bucket_tag):
					added += 1
				added += int(resident_counts.get(bucket_tag, 0))
				if added > 0:
					counts[bucket["key"]] = int(counts[bucket["key"]]) + added
```

In `habitat_simulation.gd`, in `_move_in()`, set the tags right after the site is registered or claimed — replace:

```gdscript
	if site == null:
		site = _registry.register(position, species.id, species.scout_radius)
	elif site.is_vacant():
		_registry.claim(site, species.id, species.scout_radius)
```

with:

```gdscript
	if site == null:
		site = _registry.register(position, species.id, species.scout_radius)
	elif site.is_vacant():
		_registry.claim(site, species.id, species.scout_radius)
	# Derived, not persisted — re-copied here and in `restore_site()` so a retuned `.tres`
	# takes effect immediately instead of being frozen into an old save.
	site.resident_tags = species.emits_tags.duplicate()
```

In `habitat_simulation.gd`'s `restore_site()`, add the same assignment wherever the restored site's species definition is resolved, immediately after the site is obtained:

```gdscript
	site.resident_tags = species.emits_tags.duplicate()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/run-tests.sh resident_tags`
Expected: PASS, 8 assertions.

Run: `bash scripts/run-tests.sh capacity_formula` and `bash scripts/run-tests.sh tier_capacity`
Expected: PASS both — no species emits anything yet, so counts are unchanged.

- [ ] **Step 5: Commit**

```
project/scripts/simulation/home_site.gd             (modified)
project/scripts/simulation/home_site_registry.gd    (modified)
project/scripts/simulation/capacity_evaluator.gd    (modified)
project/scripts/simulation/habitat_simulation.gd    (modified)
project/tests/test_resident_tags.gd                 (new)
```

---

### Task 6: Group arrivals

**Files:**
- Modify: `project/scripts/simulation/arrival_queue.gd`
- Modify: `project/scripts/simulation/habitat_simulation.gd`
- Test: `project/tests/test_group_arrivals.gd`

**Interfaces:**
- Consumes: `HabitatTier.arrival_group_size` (Task 1); `CapacityEvaluator.best_tier()` (Task 4).
- Produces:
  - `ArrivalQueue.enqueue(position: Vector2i, species_id: String, count: int = 1) -> bool`
  - queue entries gain a `"count"` key, carried through `advance()`, `to_save()` and `restore()`
  - `HabitatSimulation._land_or_drop()` lands `min(count, capacity - population)`

**Partial landing is required, not optional.** If capacity dropped between enqueue and due time, the group lands with as many as fit rather than being dropped wholesale. All-or-nothing would make herds feel arbitrary and would interact badly with a tap burst.

**Save compatibility:** `restore()` must treat a missing `"count"` as `1`, so saves written before this change load cleanly. Bump `save_version` where the world snapshot declares it.

- [ ] **Step 1: Write the failing test**

Create `project/tests/test_group_arrivals.gd`:

```gdscript
extends QATestCase
## Group arrivals: a tier may land several individuals at once, and lands PARTIALLY when
## the land changed between enqueue and due time.
##
## Run:
##   bash scripts/run-tests.sh group_arrivals

func _init() -> void:
	begin("group arrivals")
	_check_count_defaults_to_one()
	_check_count_round_trips()
	_check_missing_count_restores_as_one()
	_check_partial_landing_arithmetic()
	finish()


func _check_count_defaults_to_one() -> void:
	var queue := ArrivalQueue.new(1)
	queue.enqueue(Vector2i(3, 3), "fox")
	var saved: Array[Dictionary] = queue.to_save()
	check_eq(saved.size(), 1, "one entry queued")
	check_eq(int(saved[0].get("count", 1)), 1, "an unspecified group size is one")


func _check_count_round_trips() -> void:
	var queue := ArrivalQueue.new(1)
	queue.enqueue(Vector2i(5, 5), "deer", 3)
	var saved: Array[Dictionary] = queue.to_save()
	check_eq(int(saved[0]["count"]), 3, "the group size is saved")

	var restored := ArrivalQueue.new(1)
	restored.restore(saved)
	check_eq(restored.size(), 1, "the entry restores")
	check_eq(int(restored.to_save()[0]["count"]), 3, "the group size survives a round trip")


func _check_missing_count_restores_as_one() -> void:
	# A save written before group arrivals existed.
	var legacy: Array = [{"position": Vector2i(2, 2), "species_id": "rabbit", "remaining": 5.0}]
	var queue := ArrivalQueue.new(1)
	queue.restore(legacy)
	check_eq(queue.size(), 1, "a pre-group save still restores")
	check_eq(int(queue.to_save()[0]["count"]), 1, "a missing count reads as one, not zero")


## The partial-landing rule, stated as arithmetic so it can be checked without a world.
func _check_partial_landing_arithmetic() -> void:
	check_eq(mini(3, 6 - 4), 2, "a group of 3 into room for 2 lands 2")
	check_eq(mini(3, 6 - 6), 0, "a group of 3 into no room lands none")
	check_eq(mini(3, 12 - 0), 3, "a group of 3 into an empty herd site lands all 3")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/run-tests.sh group_arrivals`
Expected: FAIL — `enqueue()` takes 2 arguments, 3 given.

- [ ] **Step 3: Write the implementation**

In `arrival_queue.gd`, change `enqueue` to accept and store a count:

```gdscript
## Queues an arrival of `count` individuals at `position`.
##
## `count` comes from the qualifying tier's `arrival_group_size`, so deer arrive as a small
## group and a lone fox arrives alone. It is re-checked at due time and may land partially
## — see `HabitatSimulation._land_or_drop()`.
func enqueue(position: Vector2i, species_id: String, count: int = 1) -> bool:
```

Inside it, add `"count": maxi(count, 1)` to the Dictionary it appends to `_pending`.

In `to_save()`, include `"count"` on each entry. In `restore()`, read it defensively:

```gdscript
		# A save written before group arrivals has no `count`. Read it as 1, never as 0 —
		# a 0 would silently drop the arrival on load.
		var count: int = int(entry.get("count", 1))
		if count < 1:
			count = 1
```

In `habitat_simulation.gd`, `_evaluate()` — enqueue the winning tier's group size:

```gdscript
		if cap >= population + 1:
			var tier: HabitatTier = CapacityEvaluator.best_tier(_grid, _registry, position, species, site)
			var group: int = 1 if tier == null else tier.arrival_group_size
			# Never queue more than the site can actually hold right now; the due-time
			# re-check may still trim it further.
			_arrivals.enqueue(position, species.id, mini(group, cap - population))
```

In `habitat_simulation.gd`, `_resolve_due_arrivals()` — pass the count through:

```gdscript
	for entry: Dictionary in _arrivals.advance(delta):
		_land_or_drop(
			entry["position"] as Vector2i,
			entry["species_id"] as String,
			int(entry.get("count", 1))
		)
```

And rewrite `_land_or_drop()` to land partially:

```gdscript
## The due-time re-check. The land may have changed since the enqueue, so capacity is read
## again — and if it no longer supports one more, the arrival is **silently dropped, never
## warned**. Nothing had moved in, so there is nothing to explain.
##
## PARTIAL LANDING IS DELIBERATE: a group of three into room for two lands two, not zero.
## All-or-nothing would make herds feel arbitrary, and would interact badly with the tap
## burst the arrival delay exists to absorb.
func _land_or_drop(position: Vector2i, species_id: String, count: int = 1) -> void:
	var species: AnimalDefinition = _roster.by_id(species_id)
	if species == null:
		return
	for i in range(maxi(count, 1)):
		var site: HomeSite = _site_for(position, species)
		var cap: int = CapacityEvaluator.capacity(_grid, _registry, position, species, site)
		var population: int = 0 if site == null else site.population()
		if cap < population + 1:
			return  # silently dropped — the rest of the group simply never arrives
		_move_in(position, species)
```

Finally, bump `save_version` wherever the world snapshot declares it (search for `save_version` in `project/scripts/`), and note the bump in that file's header comment.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/run-tests.sh group_arrivals`
Expected: PASS, 9 assertions.

Run: `bash scripts/run-tests.sh arrival` and `bash scripts/run-tests.sh save`
Expected: PASS — the `count` key is additive and old saves restore as `count = 1`.

- [ ] **Step 5: Commit**

```
project/scripts/simulation/arrival_queue.gd        (modified)
project/scripts/simulation/habitat_simulation.gd   (modified)
project/tests/test_group_arrivals.gd               (new)
<the file declaring save_version>                  (modified — version bump)
```

---

### Task 7: Building tags and the Farmhouse

**Files:**
- Modify: `project/data/buildings/house.tres`, `barn.tres`, `small_barn.tres`, `open_barn.tres`, `chicken_coop.tres`, `silo.tres`, `windmill.tres`, `water_tower.tres`, `well.tres` (locate exact paths with `find project -name '*.tres'`)
- Create: `project/data/buildings/farmhouse.tres`
- Test: `project/tests/test_building_tags.gd`

**Interfaces:**
- Consumes: extended `HABITAT_TAGS` (Task 3).
- Produces: the tag sources every species `.tres` in Task 9 depends on.

**Every placeable emits `built` in addition to its own tag.** That is the load-bearing rule: one `built` limit excludes every building, including buildings added later, without touching a single species file.

**Three subsumptions are deliberate:** a large barn *is* a barn (Barn emits both), an open-sided barn *is* a stable (OpenBarn emits both), a farmhouse *is* a house (Farmhouse emits both).

**Values are proposals.** Farmhouse's `cost` and `footprint` follow `buildings.md`'s stated 2×2 baseline of ~30 Wood. Add a header comment to `farmhouse.tres` saying so, matching `barn.tres`'s existing convention.

- [ ] **Step 1: Write the failing test**

Create `project/tests/test_building_tags.gd`:

```gdscript
extends QATestCase
## Every placeable's `emitted_tags`, pinned. These are the tag SOURCES the roster reads,
## so a silent change here would break species that look fine in isolation.
##
## Run:
##   bash scripts/run-tests.sh building_tags

const EXPECTED: Dictionary = {
	"house": ["built", "house"],
	"farmhouse": ["built", "house", "large_house"],
	"small_barn": ["built", "barn"],
	"barn": ["built", "barn", "large_barn"],
	"open_barn": ["built", "barn", "stable"],
	"chicken_coop": ["built", "coop"],
	"silo": ["built", "silo"],
	"windmill": ["built", "mill"],
	"well": ["built", "water"],
	"water_tower": ["built", "water"],
}


func _init() -> void:
	begin("building tags")
	var found: Dictionary = _load_placeables()
	for id: String in EXPECTED:
		var def: PlaceableDefinition = found.get(id, null)
		if not check(def != null, "placeable \"%s\" exists" % id):
			continue
		var expected: Array = EXPECTED[id]
		var actual: Array[String] = def.emitted_tags
		check_eq(actual.size(), expected.size(), "\"%s\" emits %d tag(s)" % [id, expected.size()])
		for tag: String in expected:
			check(actual.has(tag), "\"%s\" emits \"%s\"" % [id, tag])
		check(
			actual.has("built"),
			"\"%s\" emits `built` — the universal exclusion handle" % id
		)
		for tag: String in actual:
			check(
				AnimalDefinition.HABITAT_TAGS.has(tag),
				"\"%s\" tag \"%s\" is in the shared vocabulary" % [id, tag]
			)
	finish()


func _load_placeables() -> Dictionary:
	var found: Dictionary = {}
	for path: String in _tres_paths("res://data/buildings"):
		var res: Resource = load(path)
		if res is PlaceableDefinition:
			found[(res as PlaceableDefinition).id] = res
	return found


func _tres_paths(dir_path: String) -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			paths.append_array(_tres_paths("%s/%s" % [dir_path, entry]))
		elif entry.ends_with(".tres"):
			paths.append("%s/%s" % [dir_path, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	return paths
```

**Before running:** confirm the buildings directory path with `find project -name 'barn.tres'` and correct `res://data/buildings` in the test if it differs.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/run-tests.sh building_tags`
Expected: FAIL — every building reports 0 tags where 2–3 are expected, and `farmhouse` does not exist.

- [ ] **Step 3: Write the implementation**

For each of the nine existing files, set `emitted_tags` per the table in the test, e.g. in `open_barn.tres`:

```
emitted_tags = Array[String](["built", "barn", "stable"])
```

Add a note to each file's header comment:

```
; emitted_tags SET 2026-09-04 by the habitat-tiers ruling. Previously `[]` — every farm
; building was placeable decoration with no simulation meaning. `built` is emitted by
; EVERY placeable so one `HabitatLimit` on `built` excludes all of them, including
; buildings added later. See docs/superpowers/specs/2026-09-04-habitat-tiers-design.md § 8.
```

Create `project/data/buildings/farmhouse.tres` modelled on `house.tres`, reusing one of the already-imported larger house models (`project/assets/buildings/house_secondage_1_level3/HouseSecondage1Level3.tscn` or similar — pick by visual size, and record which and why in the header):

```
; Farmhouse — NEW PlaceableDefinition (habitat-tiers ruling, 2026-09-04).
;
; WHY IT EXISTS: the human ruled that a villager FAMILY needs "a larger house plus
; cultivated land at >= 2 tiles per person" (spec OQ-D). "Larger house" has to be a TAG,
; and house.tres is a single placeable, so buildings.md's "House at 2x2" form becomes a
; distinct placeable here. `large_house` is what Villager's family tier gates on.
;
; A FARMHOUSE IS A HOUSE: it emits `house` as well as `large_house`, so it still shelters
; dogs and single villagers. Same subsumption as Barn -> `barn` + `large_barn`.
;
; PROPOSALS AWAITING HUMAN SIGN-OFF — cost and footprint follow buildings.md's stated 2x2
; baseline ("~30 Wood"); neither is a decided value.
[gd_resource type="Resource" script_class="PlaceableDefinition" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/definitions/placeable_definition.gd" id="1_schema"]
[ext_resource type="PackedScene" path="res://assets/buildings/house_secondage_1_level3/HouseSecondage1Level3.tscn" id="2_model"]

[resource]
script = ExtResource("1_schema")
id = "farmhouse"
display_name = "Farmhouse"
hotbar_category = "farm_building"
cost = 30
footprint = Vector2i(2, 2)
allowed_terrain = Array[String](["grass"])
emitted_tags = Array[String](["built", "house", "large_house"])
model_scenes = Array[PackedScene]([ExtResource("2_model")])
fact_text = "PLACEHOLDER — flavor copy for the Farmhouse pending Content Pipeline step 5."
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/run-tests.sh building_tags`
Expected: PASS.

Run: `bash scripts/run-tests.sh placeable` and `bash scripts/run-tests.sh house`
Expected: PASS — existing placeable schema suites must still be green.

- [ ] **Step 5: Commit**

List all nine modified `.tres` paths plus `farmhouse.tres` (new) and `project/tests/test_building_tags.gd` (new). Flag explicitly for the human that Farmhouse's `cost`, `footprint` and chosen model are proposals.

---

### Task 8: The three new terrains

**Files:**
- Create: `project/data/terrain/meadow.tres`, `scrub.tres`, `snowfield.tres` (match the existing terrain `.tres` directory)
- Create: terrain model wrapper scenes under `project/assets/terrain/` following the existing `pine_tree` pattern
- Modify: `project/attribution/sources/` entries if a new pack is touched
- Test: `project/tests/test_new_terrains.gd`

**Interfaces:**
- Consumes: extended `HABITAT_TAGS` (Task 3).
- Produces: the `browse`, `flowers` and `snow` tag sources Task 9's roster reads.

**Art is already cleared — do not source anything new.** Snowfield draws on the Ultimate Nature Pack's snow variant set (`BirchTree_Snow_*`, `Bush_Snow_*` under `source-content/assets/Ultimate Nature Pack - Jun 2019-.../`). Meadow and Scrub draw on the Stylized Nature MegaKit (`Flower_3_Group`, `Flower_4_Group`, `Bush_Common_Flowers`, `Fern_1`, `Grass_Common_Tall`, `Grass_Wispy_Short`). Both packs are already imported and have attribution `.tres` entries (`quaternius_ultimate_nature_pack.tres`, `quaternius_stylized_nature_megakit.tres`). Follow `game-design/asset-import-pipeline.md` for the import procedure.

**Snowfield may border grass.** The human ruled this explicitly (spec OQ-E): the game is not restricted to real-world climate adjacency. Do not add placement restrictions.

- [ ] **Step 1: Write the failing test**

Create `project/tests/test_new_terrains.gd`:

```gdscript
extends QATestCase
## The three terrains the habitat-tiers ruling added, and their tag emissions.
##
## Run:
##   bash scripts/run-tests.sh new_terrains

const EXPECTED: Dictionary = {
	"meadow": ["open_grass", "flowers"],
	"scrub": ["browse", "rocks"],
	"snowfield": ["snow"],
}


func _init() -> void:
	begin("new terrains")
	var found: Dictionary = _load_terrains()
	for id: String in EXPECTED:
		var def: TerrainDefinition = found.get(id, null)
		if not check(def != null, "terrain \"%s\" exists" % id):
			continue
		var expected: Array = EXPECTED[id]
		check_eq(def.emitted_tags.size(), expected.size(), "\"%s\" emits %d tag(s)" % [id, expected.size()])
		for tag: String in expected:
			check(def.emitted_tags.has(tag), "\"%s\" emits \"%s\"" % [id, tag])
			check(AnimalDefinition.HABITAT_TAGS.has(tag), "\"%s\" is in the shared vocabulary" % tag)
		check_eq(def.cost, 0, "\"%s\" is natural terrain and free to paint" % id)
		check(not def.model_scenes.is_empty(), "\"%s\" has at least one model" % id)
		check(def.validate().is_empty(), "\"%s\" validates clean" % id)

	# The inert-land invariant must be untouched: wild grass still emits nothing.
	var bare: PackedStringArray = TerrainDefinition.derive_bare_tags()
	check(bare.is_empty(), "wild grass still emits nothing — the inert-land invariant holds")
	finish()


func _load_terrains() -> Dictionary:
	var found: Dictionary = {}
	for path: String in _tres_paths("res://data/terrain"):
		var res: Resource = load(path)
		if res is TerrainDefinition:
			found[(res as TerrainDefinition).id] = res
	return found


func _tres_paths(dir_path: String) -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			paths.append_array(_tres_paths("%s/%s" % [dir_path, entry]))
		elif entry.ends_with(".tres"):
			paths.append("%s/%s" % [dir_path, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	return paths
```

**Before running:** confirm the terrain directory path and `TerrainDefinition.derive_bare_tags()`'s exact signature with `grep -n "derive_bare_tags" project/scripts/definitions/terrain_definition.gd`, and correct the test if either differs.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/run-tests.sh new_terrains`
Expected: FAIL — none of the three terrains exist.

- [ ] **Step 3: Write the implementation**

Import the models per `game-design/asset-import-pipeline.md`, then create each `.tres` modelled on the existing `grass.tres`. For example `scrub.tres`:

```
; Scrub — NEW TerrainDefinition (habitat-tiers ruling, 2026-09-04).
;
; WHY IT EXISTS: the second grazing terrain. `browse` vs `open_grass` is the real
; ecological browser/grazer split, which is what separates Donkey and the Deer herd tier
; from every grass-eater. It is also the "wild grass with tags" the human described —
; wild_grass.tres itself stays deliberately inert and is NOT changed.
;
; Free to paint, matching every other natural terrain ("nature is free").
[gd_resource type="Resource" script_class="TerrainDefinition" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/definitions/terrain_definition.gd" id="1_schema"]
[ext_resource type="PackedScene" path="res://assets/terrain/scrub/Scrub.tscn" id="2_model"]

[resource]
script = ExtResource("1_schema")
id = "scrub"
display_name = "Scrub"
emitted_tags = Array[String](["browse", "rocks"])
cost = 0
model_scenes = Array[PackedScene]([ExtResource("2_model")])
```

`meadow.tres` emits `["open_grass", "flowers"]`; `snowfield.tres` emits `["snow"]`. Match whatever additional fields the existing terrain `.tres` files carry (check `grass.tres` for the full field set, including `harvestable` if present).

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/run-tests.sh new_terrains`
Expected: PASS.

Run: `bash scripts/run-tests.sh terrain`
Expected: PASS — existing terrain suites still green, and `derive_bare_tags()` still returns empty.

- [ ] **Step 5: Commit**

List the three new `.tres` files, the new wrapper scenes and imported model files, any attribution file touched, and the new test. Note that Meadow/Scrub/Snowfield have no `fact_text` copy yet — that is Content Pipeline step 5 and is out of scope here.

---

### Task 9: Re-spec the roster

**Files:**
- Modify: all sixteen species `.tres` under `project/data/animals/` — `deer`, `stag`, `fox`, `rabbit`, `donkey`, `cow`, `bull`, `horse`, `alpaca`, `chicken` (if present), `human`, `pig`, `sheep`, `husky`, `pug`, `shiba_inu`
- Test: `project/tests/test_roster_signatures.gd`

**Interfaces:**
- Consumes: everything from Tasks 1–8.
- Produces: the shipped roster's habitat data.

**Every value here is a PROPOSAL.** Put a header comment on each modified file saying so and citing the spec, exactly as `horse.tres` and `barn.tres` already do. The human rules these; a `.tres` is where a proposal waits, not where a decision is recorded.

**The full table is in the spec, § 9.** Transcribe it; do not re-derive it. Notation: `tag/divisor` is a scaling need, `tag*` is `GATE_ONLY`, `!tag≤N` is a limit, `@n` is an explicit radius.

**Two species carry `emits_tags`:** `human.tres` gets `emits_tags = Array[String](["people"])` and `deer.tres` gets `emits_tags = Array[String](["deer"])`. Nothing else emits.

- [ ] **Step 1: Write the failing test**

Create `project/tests/test_roster_signatures.gd`:

```gdscript
extends QATestCase
## THE DISTINCTNESS GUARANTEE. Sixteen species, sixteen distinct habitat signatures —
## the defect this whole design exists to fix was four species sharing one recipe
## (`open_grass, cultivated` on Horse, Cow, Bull and Alpaca alike).
##
## This suite asserts STRUCTURE, not tuning: that signatures differ, that categories are
## coherent, that the graph is acyclic. Individual divisors are the human's and may move
## freely without touching this file.
##
## Run:
##   bash scripts/run-tests.sh roster_signatures

func _init() -> void:
	begin("roster signatures")
	var roster: Array[AnimalDefinition] = _load_roster()
	check(roster.size() >= 16, "the roster has at least sixteen species (found %d)" % roster.size())
	_check_all_validate(roster)
	_check_signatures_are_distinct(roster)
	_check_categories(roster)
	_check_emitters(roster)
	_check_graph_acyclic(roster)
	finish()


func _check_all_validate(roster: Array[AnimalDefinition]) -> void:
	var ids: PackedStringArray = []
	for def: AnimalDefinition in roster:
		ids.append(def.id)
	for def: AnimalDefinition in roster:
		var problems: Array[String] = def.validate(ids)
		check(problems.is_empty(), "\"%s\" validates clean" % def.id, "\n        ".join(problems))


## The whole point of the design, asserted directly.
func _check_signatures_are_distinct(roster: Array[AnimalDefinition]) -> void:
	var seen: Dictionary = {}
	for def: AnimalDefinition in roster:
		var signature: String = _signature(def)
		if seen.has(signature):
			check(false, "\"%s\" has a distinct signature" % def.id,
				"identical to \"%s\": %s" % [seen[signature], signature])
		else:
			seen[signature] = def.id
			check(true, "\"%s\" has a distinct signature" % def.id)


func _check_categories(roster: Array[AnimalDefinition]) -> void:
	for def: AnimalDefinition in roster:
		check(
			def.category() != "",
			"\"%s\" matches a design category" % def.id,
			"neither person, wild, nor domesticated"
		)


func _check_emitters(roster: Array[AnimalDefinition]) -> void:
	var emitters: Dictionary = {}
	for def: AnimalDefinition in roster:
		for tag: String in def.emits_tags:
			emitters[tag] = def.id
	check_eq(emitters.get("people", ""), "human", "the villager is what emits `people`")
	check_eq(emitters.get("deer", ""), "deer", "the deer is what emits `deer`")
	check_eq(emitters.size(), 2, "exactly two species emit anything")


func _check_graph_acyclic(roster: Array[AnimalDefinition]) -> void:
	var cycle: Array[String] = HabitatGraph.find_cycle(roster)
	check(cycle.is_empty(), "the shipped dependency graph is acyclic", str(cycle))


## A canonical, order-independent string form of a species' habitat requirements.
func _signature(def: AnimalDefinition) -> String:
	var parts: Array[String] = []
	for tier: HabitatTier in def.effective_tiers():
		var tier_parts: Array[String] = []
		for need: HabitatNeed in tier.needs:
			tier_parts.append("%s/%d@%d" % [need.tag, need.tiles_per_individual, need.radius])
		for limit: HabitatLimit in tier.limits:
			tier_parts.append("!%s<=%d@%d" % [limit.tag, limit.max_count, limit.radius])
		tier_parts.sort()
		parts.append("|".join(tier_parts))
	parts.sort()
	return "//".join(parts)


func _load_roster() -> Array[AnimalDefinition]:
	var found: Array[AnimalDefinition] = []
	for path: String in _tres_paths("res://data/animals"):
		var res: Resource = load(path)
		if res is AnimalDefinition:
			found.append(res as AnimalDefinition)
	return found


func _tres_paths(dir_path: String) -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			paths.append_array(_tres_paths("%s/%s" % [dir_path, entry]))
		elif entry.ends_with(".tres"):
			paths.append("%s/%s" % [dir_path, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	return paths
```

**Before running:** confirm the animals directory path with `find project -name 'horse.tres'` and correct `res://data/animals` if it differs.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/run-tests.sh roster_signatures`
Expected: FAIL — the four-species collision is reported directly (`"cow" has a distinct signature — identical to "horse"`), plus category failures for species with no limits and no building gate.

- [ ] **Step 3: Write the implementation**

A `.tres` holds tiers as sub-resources. The pattern, shown in full for `horse.tres` — every other species follows it:

```
; Horse — RE-SPEC 2026-09-04 (habitat tiers).
;
; PROPOSAL, NOT A DECISION. Every divisor, radius and cap below is this design's own
; first-pass proposal awaiting human sign-off, per the project rule that all tuning values
; are the human's. Source: docs/superpowers/specs/2026-09-04-habitat-tiers-design.md § 9.
;
; The legacy flat fields (habitat_needs / tiles_per_individual / max_individuals) are LEFT
; IN PLACE and are now inert: `effective_tiers()` prefers `tiers` when non-empty. They are
; retained so a rollback is a one-line edit rather than a re-authoring.
;
; WHY TWO TIERS: this is the design's worked example. A stable and some grass gets a pair;
; a stable, a wide tract and water gets a herd, with `water/2` binding the herd size — so
; digging more pond visibly buys more horses.
[gd_resource type="Resource" script_class="AnimalDefinition" load_steps=9 format=3]

[ext_resource type="Script" path="res://scripts/definitions/animal_definition.gd" id="1_schema"]
[ext_resource type="Script" path="res://scripts/definitions/habitat_need.gd" id="2_need"]
[ext_resource type="Script" path="res://scripts/definitions/habitat_tier.gd" id="3_tier"]
[ext_resource type="PackedScene" path="res://assets/animals/horse/Horse.tscn" id="4_model"]

[sub_resource type="Resource" id="need_pair_stable"]
script = ExtResource("2_need")
tag = "stable"
radius = 5
tiles_per_individual = 0

[sub_resource type="Resource" id="need_pair_grass"]
script = ExtResource("2_need")
tag = "open_grass"
radius = 8
tiles_per_individual = 6

[sub_resource type="Resource" id="tier_pair"]
script = ExtResource("3_tier")
id = "pair"
needs = Array[Resource]([SubResource("need_pair_stable"), SubResource("need_pair_grass")])
limits = Array[Resource]([])
max_individuals = 2
arrival_group_size = 1

[sub_resource type="Resource" id="need_herd_stable"]
script = ExtResource("2_need")
tag = "stable"
radius = 5
tiles_per_individual = 0

[sub_resource type="Resource" id="need_herd_grass"]
script = ExtResource("2_need")
tag = "open_grass"
radius = 14
tiles_per_individual = 4

[sub_resource type="Resource" id="need_herd_water"]
script = ExtResource("2_need")
tag = "water"
radius = 12
tiles_per_individual = 2

[sub_resource type="Resource" id="tier_herd"]
script = ExtResource("3_tier")
id = "herd"
needs = Array[Resource]([SubResource("need_herd_stable"), SubResource("need_herd_grass"), SubResource("need_herd_water")])
limits = Array[Resource]([])
max_individuals = 12
arrival_group_size = 3

[resource]
script = ExtResource("1_schema")
id = "horse"
display_name = "Horse"
habitat_needs = Array[String](["open_grass", "cultivated"])
tiers = Array[Resource]([SubResource("tier_pair"), SubResource("tier_herd")])
emits_tags = Array[String]([])
personality = "Bold"
avoids = Array[String]([])
farm_tolerant = true
scout_radius = 8
capacity_radius = 0
tiles_per_individual = 5
max_individuals = 6
model_scenes = Array[PackedScene]([ExtResource("4_model")])
fact_text_pool = Array[String](["A newborn foal can already stand up on its own in about an hour, and it can walk just a few hours after that."])
news_reports = Array[String]([])
```

A limit sub-resource (needed by all five Wild species) looks like:

```
[ext_resource type="Script" path="res://scripts/definitions/habitat_limit.gd" id="5_limit"]

[sub_resource type="Resource" id="limit_built"]
script = ExtResource("5_limit")
tag = "built"
radius = 12
max_count = 1
```

Work through the spec's § 9 table species by species, running `bash scripts/run-tests.sh roster_signatures` after each one so a mistake is attributed to the file that caused it. **Convert `deer.tres` and `human.tres` last** — they carry `emits_tags`, and doing them last means the graph check has the fullest picture when it first runs green.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/run-tests.sh roster_signatures`
Expected: PASS — sixteen distinct signatures, every species categorised, graph acyclic.

Run: `bash scripts/run-tests.sh`
Expected: **FULL SUITE GREEN.** Every suite that Task 3 broke must now be closed. If a per-species schema suite still fails because it pins an old habitat need, update that suite's expectation to the new value and say so in the report — but never widen the vocabulary or the radius band to make a suite pass.

- [ ] **Step 5: Commit**

List all sixteen `.tres` paths, the new test, and any per-species suite whose expectations were updated. **Flag prominently that every habitat value in all sixteen files is a proposal awaiting the human's ruling.**

---

### Task 10: Show the tier in the habitat recipe UI

**Files:**
- Modify: `project/scripts/ui/habitat_recipe.gd`
- Test: `project/tests/test_habitat_recipe.gd` (extend the existing suite)

**Interfaces:**
- Consumes: `CapacityEvaluator.best_tier()` (Task 4); `HabitatTier` (Task 1).
- Produces: no new public API required beyond whatever the existing recipe view exposes.

**What the player must be able to see:** which tier a site currently satisfies, and what the *next* tier would need. That second half is what makes the whole design legible — without it, a player has no way to discover that a stable turns a pair of horses into a herd. Read `habitat_recipe.gd` first and follow its existing presentation conventions rather than inventing a new panel.

**Tier ids stay internal.** `id` is `"pair"` / `"herd"`, not player copy. Display the *requirements*, not the tier name — player-facing tier naming was explicitly ruled out of scope (spec § 13).

**Confirm the class name before writing the test.** This plan assumes `habitat_recipe.gd` declares `class_name HabitatRecipe` and that `describe_tiers()` can be a static on it. Verify with `head -5 project/scripts/ui/habitat_recipe.gd`; if it declares a different name, or is a `Control` that must be instantiated rather than called statically, adapt both the test and the helper's placement accordingly — the behaviour asserted does not change, only where the function lives.

- [ ] **Step 1: Write the failing test**

Append to `project/tests/test_habitat_recipe.gd` (add the call in `_init()`):

```gdscript
## A species with two tiers must present BOTH: the one currently met, and the one above it
## — otherwise nothing tells the player a stable would turn a pair into a herd.
func _check_tiers_are_presented() -> void:
	var horse := AnimalDefinition.new()
	horse.id = "horse"
	horse.display_name = "Horse"
	horse.scout_radius = 8

	var pair := HabitatTier.new()
	pair.id = "pair"
	pair.max_individuals = 2
	var stable := HabitatNeed.new()
	stable.tag = "stable"
	stable.tiles_per_individual = HabitatNeed.GATE_ONLY
	var grass := HabitatNeed.new()
	grass.tag = "open_grass"
	grass.tiles_per_individual = 6
	pair.needs = [stable, grass]

	var herd := HabitatTier.new()
	herd.id = "herd"
	herd.max_individuals = 12
	var wide := HabitatNeed.new()
	wide.tag = "open_grass"
	wide.radius = 14
	wide.tiles_per_individual = 4
	var water := HabitatNeed.new()
	water.tag = "water"
	water.radius = 12
	water.tiles_per_individual = 2
	herd.needs = [stable, wide, water]

	horse.tiers = [pair, herd]

	check_eq(horse.effective_tiers().size(), 2, "the horse presents two tiers")
	var lines: Array[String] = HabitatRecipe.describe_tiers(horse)
	check_eq(lines.size(), 2, "one description line per tier")
	check(lines[1].contains("water"), "the herd line names water, the need that unlocks it")
	check(not lines[0].contains("herd"), "internal tier ids never reach player copy")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/run-tests.sh habitat_recipe`
Expected: FAIL — `Nonexistent function 'describe_tiers'`.

- [ ] **Step 3: Write the implementation**

Add to `project/scripts/ui/habitat_recipe.gd`, matching the file's existing formatting helpers:

```gdscript
## One player-facing line per tier, in authoring order.
##
## TIER IDS NEVER APPEAR. `id` is "pair"/"herd" — internal only, because player-facing tier
## naming was ruled out of scope (spec § 13). The line describes the REQUIREMENTS, which is
## what actually tells a player that a stable and some water would turn a pair into a herd.
static func describe_tiers(species: AnimalDefinition) -> Array[String]:
	var lines: Array[String] = []
	if species == null:
		return lines
	for tier: HabitatTier in species.effective_tiers():
		var parts: Array[String] = []
		for need: HabitatNeed in tier.needs:
			if need.is_gate_only():
				parts.append(need.tag)
			else:
				parts.append("%s (%d per animal)" % [need.tag, need.tiles_per_individual])
		for limit: HabitatLimit in tier.limits:
			if limit.max_count == 0:
				parts.append("no buildings nearby")
			else:
				parts.append("at most %d buildings nearby" % limit.max_count)
		lines.append("Up to %d: %s" % [tier.max_individuals, ", ".join(parts)])
	return lines
```

Then wire `describe_tiers()` into wherever the recipe view currently renders a species' needs, replacing the flat `habitat_needs` rendering.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/run-tests.sh habitat_recipe`
Expected: PASS.

- [ ] **Step 5: Commit**

```
project/scripts/ui/habitat_recipe.gd     (modified)
project/tests/test_habitat_recipe.gd     (modified)
```

---

### Task 11: Full-suite verification and the documentation fold-back list

**Files:**
- Test: no new files
- Report only

**Interfaces:** consumes everything.

This task produces no code. It produces the evidence that the work is done and the list of design-doc edits the human needs to make.

- [ ] **Step 1: Run the entire suite**

Run: `bash scripts/run-tests.sh`
Expected: every suite PASS, exit 0.

If anything fails, fix the cause — never the assertion — and re-run. Do not report completion on a red suite.

- [ ] **Step 2: Verify the two invariants that no single task owns**

Run: `bash scripts/run-tests.sh new_terrains`
Confirm in the output: `wild grass still emits nothing — the inert-land invariant holds`.

Run: `bash scripts/run-tests.sh roster_signatures`
Confirm in the output: `the shipped dependency graph is acyclic` and sixteen distinct-signature PASS lines.

- [ ] **Step 3: Verify Gentle Displacement survives tiers**

Spec § 11 states two consequences no single task owns. Check both:

Run: `bash scripts/run-tests.sh gentle_displacement`
Expected: PASS. Tiers change what `capacity()` returns, and the displacement trigger reads
`capacity(h, S) < population(h, S)` — so this suite is the regression gate on the whole
formula rewrite, not just on displacement.

Then report these two as **human playtest items**, since neither is headless-checkable:
- **A tier fall is a thinning, not a vanishing.** Dropping from a herd tier to a pair tier
  should warn once and remove the surplus, not evict the site. Copy should read like
  *"the herd will thin to a pair — the rest will find a wider field."*
- **Two-level cascades coalesce into ONE warning.** `deer → stag` and
  `human → people → dogs` both mean a single settled gesture can displace two species.
  The settlement rule should summarise them together; a chain of separate popups would
  break the "one warning per settled gesture" rule the GDD states.

- [ ] **Step 4: Capture the numbers the human asked to watch**

Report, from the suite output:
- total suites run and total assertions passed
- the roster's widest per-need radius actually used (grep the `.tres` files for `radius = `) — this is the performance budget the human ruled at 16

- [ ] **Step 5: Write the documentation fold-back list**

The design docs are still stale. Produce a list, for the human, of exactly which files need which edits — do **not** edit them, since `decisions.md` entries and GDD changes are the human's:

- `game-design/gdd.md` → Habitat Suitability: the capacity formula is now max-over-tiers; `quiet` left the vocabulary; residents emit tags
- `game-design/roster.md` → the Already-Defined Roster table is superseded by spec § 9; sixteen species, not fourteen (`pig`, `sheep`, `pug` were already shipped but untabled)
- `game-design/terrain.md` → three new terrains; the tag-source mapping table
- `game-design/buildings.md` → nine buildings now emit tags; Farmhouse is a new placeable; the "House at 2×2 form" line is superseded
- `game-design/spec.md` → Open Questions #5, #7, #20, #23 are all affected; the radius band changed
- `decisions.md` → a new `D-NN` recording the habitat-tiers ruling and the six OQ rulings of 2026-09-04

- [ ] **Step 6: Report**

Report the full-suite result, the two invariant confirmations, the numbers from Step 3, and the fold-back list. Remind the human that **every habitat value in the sixteen species `.tres` files and in `farmhouse.tres` is a proposal awaiting their sign-off**, and that no git command has been run.
