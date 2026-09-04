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

