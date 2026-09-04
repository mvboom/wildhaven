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

