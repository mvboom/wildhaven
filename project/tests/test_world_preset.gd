extends QATestCase
## WORLD PRESET — Tier 1 row 1's "fixed preset", as data rather than code.
##
## WHY THIS IS A RESOURCE AND NOT A CONSTANT. Open Question **#10** (the exact New Game preset
## list) is undecided, and spec.md -> Tier 1 What Deepening Buys gives row 1's depth purchase as
## "preset variety". Making the preset a `.tres` means closing #10 later is authoring data, not
## editing code — the same shape as `TerrainDefinition` and `PlaceableDefinition`.
##
## THE ONE INVARIANT THAT IS NOT COSMETIC: `base_terrain_id` must be a terrain that emits no
## tags. A preset that FELL BACK to real grass would hand the player a world whose carrying
## capacity is nonzero before they have touched anything, with nothing underneath it. That is
## asserted here against the live terrain data, not against a hardcoded id.
##
## **`terrain_mix` IS EXEMPT FROM THAT INVARIANT AND ONLY IT** (D-53, 2026-09-07). A Meadow or
## Forested start deliberately emits tags from frame one — that is what makes "choose a starting
## land" a choice rather than a label. `_check_terrain_mixes()` below asserts the exemption's
## exact scope: mixes may emit, `base_terrain_id` may not, and Barren emits nothing at all.
##
## `display_name = "Meadow Start"` is PROPOSED (2026-08-01) — a placeholder until #10 rules.
## Not enforced here beyond "non-empty"; the human's decision replaces the string, not the test.
##
## Run:
##   bash scripts/run-tests.sh world_preset

func _initialize() -> void:
	begin("world preset")

	var presets: Array[WorldPreset] = WorldPreset.load_all()
	check(presets.size() >= 1, "at least one preset exists on disk")

	var meadow: WorldPreset = WorldPreset.default_preset()
	if not check(meadow != null, "there is a default preset"):
		finish()
		return

	# #10 now has three presets on disk (meadow_start, barren_start, forested_start —
	# 2026-08-24, New Game screen redesign). default_preset() stays pinned to
	# WorldPreset.DEFAULT_PRESET_ID ("meadow_start") specifically rather than drifting to
	# whatever sorts alphabetically first, since every fallback path that calls it (an editor
	# F6 run, a world opened with no menu) still needs a stable answer. NewGameScreen itself
	# does NOT call this — it orders and defaults its own cards explicitly, independent of it.
	check_eq(meadow.id, "meadow_start", "default_preset() stays pinned to meadow_start")
	check(not meadow.display_name.is_empty(), "the preset has a display name for the card")
	check_eq(meadow.width, WorldGrid.DEFAULT_WIDTH, "preset width matches the shipped grid")
	check_eq(meadow.depth, WorldGrid.DEFAULT_DEPTH, "preset depth matches the shipped grid")

	# The inert-land invariant, checked against real terrain data rather than an id literal.
	var base: TerrainDefinition = null
	for def: TerrainDefinition in TerrainDefinition.load_all():
		if def.id == meadow.base_terrain_id:
			base = def
	if not check(base != null, "base_terrain_id `%s` resolves to real terrain" % meadow.base_terrain_id):
		finish()
		return
	check(
		base.emitted_tags.is_empty(),
		"the preset's base terrain emits NO tags",
		"a preset starting on tag-emitting terrain gives the player capacity they did not make"
	)

	# Every preset on disk, not just the default — the check must not rot when #10 adds more.
	for preset: WorldPreset in presets:
		check(not preset.id.is_empty(), "preset has an id")
		check(preset.width > 0 and preset.depth > 0, "preset %s has positive dimensions" % preset.id)

	_check_terrain_mixes(presets)

	finish()


## THE `terrain_mix` SCHEMA (D-53), asserted against live terrain data rather than a list of
## id literals — a mix naming a terrain that was renamed or deleted must fail here, not
## degrade quietly into a grid of untagged tiles at run time.
##
## `WorldPreset` has no `validate()` of its own (unlike TerrainDefinition/PlaceableDefinition),
## and this suite is where its invariants have always lived. Kept that way deliberately: the
## resource is loaded on exactly one code path, so a suite assertion catches a mis-authored
## preset at the same moment a `validate()` call would.
func _check_terrain_mixes(presets: Array[WorldPreset]) -> void:
	var known: Dictionary = {}
	for def: TerrainDefinition in TerrainDefinition.load_all():
		known[TerrainDefinition.normalize_id(def.id)] = def

	for preset: WorldPreset in presets:
		for key: Variant in preset.terrain_mix:
			var id: String = TerrainDefinition.normalize_id(str(key))
			check(
				known.has(id),
				"%s's mix entry `%s` resolves to shipped terrain" % [preset.id, str(key)],
				"an unresolvable id silently contributes no tags instead of failing loudly"
			)
			var weight: Variant = preset.terrain_mix[key]
			check(
				(weight is float or weight is int) and float(weight) > 0.0,
				"%s's `%s` weight is a positive number" % [preset.id, str(key)]
			)

		# Whatever the shares are, they must fill the grid exactly — the property the whole
		# quota-fill design exists for, checked here against the preset's own dimensions
		# rather than the suite's assumed 36x36.
		if not preset.terrain_mix.is_empty():
			var count: int = preset.width * preset.depth
			var quotas: Dictionary = TerrainScatter.quotas(preset.terrain_mix, count)
			var total: int = 0
			for id: String in quotas:
				total += int(quotas[id])
			check_eq(total, count, "%s's mix quotas fill its %d tiles exactly" % [preset.id, count])

	# BARREN IS THE REFERENCE WORLD. D-53 gave Meadow and Forested live terrain and left this
	# one on the pre-D-53 uniform wild grass, which makes it the control: if its mix ever gains
	# an entry, "what the game built before D-53" stops being reachable from the menu at all.
	var barren: WorldPreset = null
	for preset: WorldPreset in presets:
		if preset.id == "barren_start":
			barren = preset
	if check(barren != null, "the Barren card is on disk"):
		check(
			barren.terrain_mix.is_empty(),
			"Barren ships an EMPTY mix — 100% tag-inert wild grass, the pre-D-53 world",
			"Barren is the control for the mix gating in WorldRoot._ready()"
		)

	# D-53's scope, stated as an assertion: the mix may emit tags, `base_terrain_id` may not.
	# The default preset's base is checked above; this covers the other cards, which no
	# assertion reached before D-53 made their `.tres` files differ.
	for preset: WorldPreset in presets:
		var base: TerrainDefinition = known.get(
			TerrainDefinition.normalize_id(preset.base_terrain_id), null
		) as TerrainDefinition
		if check(base != null, "%s's base_terrain_id resolves" % preset.id):
			check(
				base.emitted_tags.is_empty(),
				"%s's base terrain is tag-inert" % preset.id,
				"terrain_mix is where a preset may emit tags; the fallback floor is not"
			)
