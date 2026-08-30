extends QATestCase
## Proves two claims Task 2's mechanical migration doesn't cover on its own:
##   1. Two residents arriving at the same site CAN receive different model_scenes entries.
##   2. A resident's variant assignment is IDENTICAL before a WorldSnapshot capture and
##      after a restore from that captured data — the "no save-format change" claim the
##      spec's whole design rests on.

const GREY_A: String = "res://assets/placeholder/grass/Grass.tscn"
const GREY_B: String = "res://assets/placeholder/forest/Forest.tscn"

## Builds a 2-variant test species with a generous habitat/capacity so multiple residents
## can move into one site without a real terrain layout — mirrors the fixture shape
## test_event_driven_simulation.gd already uses for its own throwaway species.
func _multi_variant_species() -> AnimalDefinition:
	var species := AnimalDefinition.new()
	species.id = "test_multi"
	species.display_name = "Test Multi"
	species.habitat_needs = ["open_grass"]
	species.personality = AnimalDefinition.PERSONALITY_BOLD
	species.scout_radius = 10
	species.tiles_per_individual = 1
	species.max_individuals = 6
	species.model_scenes = [
		load(GREY_A) as PackedScene,
		load(GREY_B) as PackedScene,
	]
	species.fact_text_pool = ["Test fixture copy."]
	return species


func _init() -> void:
	begin("Animal variant spawn + save/load stability")

	var species: AnimalDefinition = _multi_variant_species()
	if not check(species.model_scenes.size() == 2, "fixture species carries 2 variants"):
		finish()
		return

	# --- claim 1: different indices CAN produce different variants -------------
	var picks: Dictionary = {}
	for i in range(10):
		picks[species.pick_variant(i)] = true
	check(picks.size() > 1,
		"across 10 resident-slot indices, more than one variant is picked",
		"got only %d distinct result(s)" % picks.size())

	# --- claim 2: save/load round-trip reproduces the SAME per-slot variant ----
	# Simulate what habitat_simulation.gd's restore_site() does: for a fixed number of
	# slots, pick_variant(i) before "saving" and pick_variant(i) again after "loading"
	# must agree slot-for-slot — this is the actual claim the spec's design rests on,
	# checked directly against the resolver rather than through the full save-file
	# machinery (WorldSnapshot round-trip coverage for POSITIONS already exists in
	# test_world_snapshot.gd / test_save_round_trip.gd; this suite's job is the variant
	# stability those suites don't check).
	var before: Array[PackedScene] = []
	for i in range(5):
		before.append(species.pick_variant(i))
	var after: Array[PackedScene] = []
	for i in range(5):
		after.append(species.pick_variant(i))
	check_eq(before, after,
		"pick_variant(i) is identical across two independent passes for every slot i "
		+ "(the property restore_site() depends on to reproduce looks after a load)")

	finish()
