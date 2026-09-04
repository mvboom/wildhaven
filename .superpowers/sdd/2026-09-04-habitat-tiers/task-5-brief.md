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

