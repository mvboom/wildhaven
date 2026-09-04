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

