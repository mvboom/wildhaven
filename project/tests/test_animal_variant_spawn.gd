extends QATestCase
## Unit coverage for the OLD-SAVE derivation path, `AnimalDefinition.pick_variant()`.
##
## RE-SCOPED BY THE VILLAGER-VARIETY FIX. This suite used to close on "no save-format change":
## a resident's look was re-derived on load from its slot within its home site's `residents`
## array, so nothing had to be written down. That derivation was the reported bug — a slot index
## is not a global identity, so the first resident at every home site in the world derived the
## same look — and it no longer runs at spawn time. `VariantBag` deals looks now, and the look is
## real save state (`save_version` 5). See `test_villager_variant_variety.gd` for the regression
## and `test_human_variant_save_stability.gd` for the round trip.
##
## The two claims below still hold and are still worth pinning, but ONLY as properties of the
## legacy derivation that reads pre-v5 saves:
##   1. It does not collapse every index to one entry — a pre-fix save with several residents
##      at ONE site still restores them looking different from each other.
##   2. It is deterministic — the same slot always derives the same look, which is what makes an
##      old world reopen showing exactly what it showed before.

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
	begin("AnimalDefinition legacy (pre-v5) variant derivation")

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

	# The bound worth stating out loud, because it is the shape of the bug: varying with the
	# slot index is NOT the same as varying between villagers. Every home site starts at slot 0,
	# so slot 0's answer was every site's answer. Nothing here can see that — it takes several
	# home sites, which is `test_villager_variant_variety.gd`'s fixture.
	check_eq(species.pick_variant(0), species.pick_variant(0),
		"slot 0 derives ONE fixed look — the reason this derivation could not be the spawn rule")

	# --- claim 2: the legacy derivation is deterministic ----------------------
	# What `restore_site()` falls back to for a PRE-v5 save (a `residents` entry of 3 elements,
	# with no look in it): `legacy_variant_index(i)` must give the same answer every time, or an
	# old world would reshuffle its villagers on every open. Checked directly against the
	# resolver; the file-level round trip is `test_human_variant_save_stability.gd`'s.
	var before: Array[PackedScene] = []
	for i in range(5):
		before.append(species.pick_variant(i))
	var after: Array[PackedScene] = []
	for i in range(5):
		after.append(species.pick_variant(i))
	check_eq(before, after,
		"pick_variant(i) is identical across two independent passes for every slot i "
		+ "(the property restore_site()'s PRE-v5 fallback depends on to reproduce the looks "
		+ "an old world already had)")

	finish()
