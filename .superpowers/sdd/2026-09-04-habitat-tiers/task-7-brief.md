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

