extends QATestCase
## Unit coverage for WorldRoot.get_style_default()/set_style_default() — the validated
## accessor pair every picker category reads and writes through. Proves the SAME function
## correctly handles both style-id "flavors": a derived filename-slug (forest/wild_grass/
## house) and a real PlaceableDefinition id (farm_building) — no second code path.

const WORLD_PATH: String = "res://scenes/Main.tscn"

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("WorldRoot.style_defaults")
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	_world = packed.instantiate() as WorldRoot
	root.add_child(_world)
	_setup_ok = _world != null


func _process(_delta: float) -> bool:
	if not _setup_ok:
		finish()
		return true
	_frames += 1
	if _frames < 3:
		return false

	# --- never chosen: returns the category's first catalog entry ----------------------
	# RE-POINTED TWICE, AND THE RULE NEVER MOVED: "never chosen" has always read as
	# `valid_ids[0]`. It was "common_tree_1", then `mixed` when D-54 put that at the head of the
	# catalog, and it is "common_tree_1" again now that D-58 retired `mixed` outright. The
	# variety `mixed` used to provide is not gone — it moved to
	# `WorldRoot._randomise_initial_styles()`, which stamps a concrete id per tile at world
	# generation, so it is stored state rather than a re-rolled render decision.
	var forest_default: String = _world.get_style_default("forest")
	check_eq(forest_default, "common_tree_1",
		"forest, never chosen, returns the catalog's first REAL entry — no mode, just a tree")

	var farm_default: String = _world.get_style_default("farm_building")
	check_eq(farm_default, "barn",
		"farm_building, never chosen, returns the first id in catalog (alphabetical) order")

	# --- set to a valid id: returned as-is -----------------------------------------------
	_world.set_style_default("forest", "birch_tree")
	check_eq(_world.get_style_default("forest"), "birch_tree",
		"a validly-set style id round-trips through the getter unchanged")

	_world.set_style_default("farm_building", "silo")
	check_eq(_world.get_style_default("farm_building"), "silo",
		"same accessor, same behavior, for a real placeable id")

	# --- set to a stale/unresolvable id: degrades to first entry, never crashes --------
	_world.set_style_default("forest", "this_variant_does_not_exist")
	check_eq(_world.get_style_default("forest"), "common_tree_1",
		"an unresolvable stored id degrades to the first catalog entry, not a crash")

	_world.set_style_default("farm_building", "not_a_real_building")
	check_eq(_world.get_style_default("farm_building"), "barn",
		"same degradation for a stale placeable id")

	# --- wild_grass is back to a single real option (2026-08-27, Cactus/Palm unwired again
	# post-B2 human ruling — see wild_grass.tres's own header) -----------------------------
	# Cactus/Palm are no longer valid style ids at all: they're not in model_scenes, so
	# `style_ids_for_category("wild_grass")` no longer lists them. Setting either as the
	# stored default must degrade exactly like any other stale/unresolvable id.
	_world.set_style_default("wild_grass", "wild_grass_palm")
	check_eq(_world.get_style_default("wild_grass"), "wild_grass",
		"wild_grass_palm is no longer a valid style id (Cactus/Palm unwired from model_scenes again) — degrades to the sole catalog entry")
	_world.set_style_default("wild_grass", "wild_grass_cactus")
	check_eq(_world.get_style_default("wild_grass"), "wild_grass",
		"wild_grass_cactus is equally no longer valid — same degradation")
	_world.set_style_default("wild_grass", "this_variant_does_not_exist_either")
	check_eq(_world.get_style_default("wild_grass"), "wild_grass",
		"wild_grass also degrades a genuinely unknown stale stored id to its sole catalog entry (plain grass)")

	# --- house: never chosen returns the shipped default --------------------------------
	# RE-POINTED 2026-09-07 (house cull) — was "house". Before the cull, model_scenes[0] was
	# res://assets/buildings/house/House.tscn, whose filename "House" derives the style id
	# "house" (identical to the CATEGORY name, which made this assertion read as a tautology
	# it never was). The human's ruling cut the pool to three Houses_SecondAge_1_Level{1,2,3}
	# models renamed for the player, so index 0 is now HouseLarge.tscn -> "house_large".
	#
	# The second half of this check is the one the cull makes load-bearing rather than
	# hypothetical: EVERY save written before 2026-09-07 holds a house style id that no longer
	# exists ("house", "house_tower_firstage", "house_secondage_1_level_2", ...). The stale-id
	# fallback below is what makes those saves open and play with a House that renders, and it
	# is the entire migration — see house.tres's "LOOK POOL CUT" note for why no save-version
	# bump was written for this.
	check_eq(_world.get_style_default("house"), "house_large",
		"house, never chosen, returns model_scenes[0]'s derived id")
	_world.set_style_default("house", "house_secondage_1_level_2")
	check_eq(_world.get_style_default("house"), "house_large",
		"a REAL pre-cull id (house_secondage_1_level_2) degrades to the first catalog entry — "
		+ "the exact path every existing save takes now")
	_world.set_style_default("house", "not_a_real_house_variant")
	check_eq(_world.get_style_default("house"), "house_large",
		"house also degrades an arbitrary stale stored id to its first catalog entry, not a crash")

	# --- a category with zero picker options: "" always, never a crash -----------------
	# "rock" is a real terrain id, but not one of the 4 picker categories
	# `style_ids_for_category()` special-cases, so its catalog is empty by construction.
	# This is the untested branch review fix #2 flagged: `valid_ids.is_empty()` guarding
	# `valid_ids[0]` in `get_style_default()` had zero coverage until now.
	check_eq(_world.get_style_default("rock"), "",
		"a category with no picker catalog (e.g. an ordinary terrain id) returns \"\", never an index-out-of-bounds")
	check_eq(_world.get_style_default("not_a_category_at_all"), "",
		"a completely unknown category string is equally safe, not a crash")

	# --- a corrupted/hand-edited stored value: never a String, never a crash -----------
	# Regression coverage for review fix #1: `style_defaults` round-trips through
	# hand-editable save JSON (Task 4), so a stored value can be anything JSON allows —
	# not just a stale String. Writing directly into the Dictionary (bypassing
	# `set_style_default()`, which only ever stores what it's handed) simulates exactly
	# that: a loaded save whose JSON had `"forest": 7` or `"forest": null`.
	_world.style_defaults["forest"] = 7
	check_eq(_world.get_style_default("forest"), "common_tree_1",
		"a non-String stored value (int) degrades to the first catalog entry instead of raising an invalid-cast runtime error")
	_world.style_defaults["forest"] = null
	check_eq(_world.get_style_default("forest"), "common_tree_1",
		"a non-String stored value (null) is equally safe")

	# D-58 REGRESSION GUARD: a save written while `mixed` existed stores it as a real choice.
	# It is no longer in any catalog, so it must take the SAME stale-id road as any other
	# retired id — silently, with no migration and no crash.
	_world.style_defaults["forest"] = "mixed"
	check_eq(_world.get_style_default("forest"), "common_tree_1",
		"a save that stored the retired `mixed` id degrades to the first catalog entry")
	check(not _world.style_ids_for_category("forest").has("mixed"),
		"...and `mixed` is gone from the catalog entirely, not merely deprioritised")
	_world.style_defaults["farm_building"] = false
	check_eq(_world.get_style_default("farm_building"), "barn",
		"a non-String stored value (bool) is equally safe for the farm_building flavor too")

	finish()
	return true
