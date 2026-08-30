extends QATestCase
## WORLD PRESET — Tier 1 row 1's "fixed preset", as data rather than code.
##
## WHY THIS IS A RESOURCE AND NOT A CONSTANT. Open Question **#10** (the exact New Game preset
## list) is undecided, and spec.md -> Tier 1 What Deepening Buys gives row 1's depth purchase as
## "preset variety". Making the preset a `.tres` means closing #10 later is authoring data, not
## editing code — the same shape as `TerrainDefinition` and `PlaceableDefinition`.
##
## THE ONE INVARIANT THAT IS NOT COSMETIC: `base_terrain_id` must be a terrain that emits no
## tags. A preset that started the world on real grass would hand the player a world whose
## carrying capacity is nonzero before they have touched anything, breaking the inert-land
## invariant (spec.md) from the first frame. That is asserted here against the live terrain
## data, not against a hardcoded id.
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

	finish()
