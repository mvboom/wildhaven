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

