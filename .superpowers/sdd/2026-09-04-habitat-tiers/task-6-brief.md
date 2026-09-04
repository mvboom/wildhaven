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

