extends QATestCase
## THE DERIVATION LAYER — habitat_needs -> emitted_tags -> palette button -> glyph, plus the
## copy, avoids, and starter-species selection built on top of it.
##
## The two arithmetic traps this suite exists to pin:
##   * Rock emits BOTH `cover` and `rocks`, so Stag's three needs must collapse to TWO
##     chips, not three;
##   * and a rock tile qualifies for both tags independently, so the merged chip's count is
##     `tiles_per_individual` (8), NOT double it.
##
## It also pins three more traps once `describe()`, `avoids_for()` and `easiest_species()`
## landed on top of `recipe_for()`:
##   * `describe()` must compose over the DEDUPED entries, not raw tags, or a shared source
##     like Rock gets named twice;
##   * `avoids_for()` must union BOTH directions of the relation even when the real roster's
##     authored pairs are all symmetric today, which is why one check below swaps in a
##     deliberately one-sided fixture roster rather than trusting fox.tres/rabbit.tres alone;
##   * and `easiest_species()` must rank by total weighted effort, not raw tile count, so a
##     cheap-looking `tiles_per_individual = 1` species that costs wood still loses to free
##     terrain.
##
## Run:
##   bash scripts/run-tests.sh habitat_recipe

const WORLD_PATH: String = "res://scenes/Main.tscn"
const FOX_PATH: String = "res://data/animals/fox.tres"
const STAG_PATH: String = "res://data/animals/stag.tres"
const DEER_PATH: String = "res://data/animals/deer.tres"
const HORSE_PATH: String = "res://data/animals/horse.tres"

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("habitat recipe")
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		finish()
		return
	_world = node as WorldRoot
	root.add_child(_world)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	_check_rock_is_the_source_of_both_its_tags()
	_check_stag_dedupes_to_two_chips_at_single_count()
	_check_fox_reads_forest_and_rock()
	_check_unsourced_need_is_unsatisfiable()
	_check_description_never_repeats_a_shared_source()
	_check_avoids_unions_both_directions()
	_check_starter_prefers_free_terrain()
	_check_unsatisfiable_species_describes_honestly()
	_check_grouped_button_names_the_resolved_member()
	_check_tiers_are_presented()
	_check_built_limit_reads_as_plain_english()
	_check_grasslands_tags_stay_distinct()

	finish()
	return true


func _check_rock_is_the_source_of_both_its_tags() -> void:
	var sources: Dictionary = HabitatRecipe.tag_sources(_world)
	for tag: String in ["cover", "rocks"]:
		var entries: Array = sources.get(tag, []) as Array
		if not check(not entries.is_empty(), "tag '%s' has a source" % tag):
			continue
		check_eq((entries[0] as Dictionary)["id"], "rock", "'%s' resolves to the Rock button" % tag)


func _check_stag_dedupes_to_two_chips_at_single_count() -> void:
	var stag: AnimalDefinition = load(STAG_PATH) as AnimalDefinition
	if not check(stag != null, "stag.tres loads"):
		return
	var recipe: Dictionary = HabitatRecipe.recipe_for(stag, _world)
	check(recipe["satisfiable"] as bool, "stag is satisfiable")
	var entries: Array = recipe["entries"] as Array
	check_eq(entries.size(), 2, "stag's 3 needs collapse to 2 chips (Rock serves two tags)")
	for entry: Dictionary in entries:
		check_eq(entry["count"], stag.tiles_per_individual,
			"chip '%s' counts tiles_per_individual, not a per-tag multiple" % entry["id"])
		if (entry["id"] as String) == "rock":
			check_eq((entry["tags"] as Array).size(), 2, "the Rock chip carries both its tags")


func _check_fox_reads_forest_and_rock() -> void:
	var fox: AnimalDefinition = load(FOX_PATH) as AnimalDefinition
	if not check(fox != null, "fox.tres loads"):
		return
	var recipe: Dictionary = HabitatRecipe.recipe_for(fox, _world)
	var ids: Array[String] = []
	for entry: Dictionary in (recipe["entries"] as Array):
		ids.append(entry["id"] as String)
	ids.sort()
	check_eq(ids, ["forest", "rock"] as Array[String], "fox resolves to Forest + Rock")


func _check_unsourced_need_is_unsatisfiable() -> void:
	var ghost := AnimalDefinition.new()
	ghost.id = "ghost"
	ghost.display_name = "Ghost"
	ghost.habitat_needs = ["quiet"] as Array[String]
	var recipe: Dictionary = HabitatRecipe.recipe_for(ghost, _world)
	check(not (recipe["satisfiable"] as bool), "a need with no source is unsatisfiable")
	check_eq((recipe["entries"] as Array).size(), 0, "an unsatisfiable species shows no partial recipe")


func _check_description_never_repeats_a_shared_source() -> void:
	var stag: AnimalDefinition = load(STAG_PATH) as AnimalDefinition
	if not check(stag != null, "stag.tres loads"):
		return
	var text: String = HabitatRecipe.describe(stag, _world)
	# Rock supplies both of stag's rock-ish needs; its phrase must appear ONCE.
	var phrase: String = HabitatRecipe.SOURCE_PHRASES["rock"] as String
	check_eq(text.count(phrase), 1, "the Rock phrase appears once, not once per tag")
	# The `[COPY]` stub marker was retired 2026-09-01 when the human approved this wording.
	# Still asserted, because the lead-in is what `describe()` composes every sentence from.
	check(text.begins_with("Likes "), "description leads with the approved 'Likes '")
	check(not text.contains(stag.display_name), "description omits the species name")


func _check_avoids_unions_both_directions() -> void:
	var fox: AnimalDefinition = load(FOX_PATH) as AnimalDefinition
	if not check(fox != null and _world.roster != null, "fox.tres and the roster load"):
		return
	var rabbit: AnimalDefinition = _world.roster.by_id("rabbit")
	if not check(rabbit != null, "the roster carries rabbit"):
		return
	check(HabitatRecipe.avoids_for(fox, _world).has(rabbit.display_name),
		"fox's avoids names Rabbit")
	check(HabitatRecipe.avoids_for(rabbit, _world).has(fox.display_name),
		"rabbit's avoids names Fox from the OTHER direction of the relation")

	# The two checks above prove nothing about the reverse-direction SCAN: every avoids pair
	# authored in the real roster today is declared symmetrically on both sides (fox/rabbit,
	# husky/shiba_inu — see roster.md), so they'd pass identically against a broken
	# `avoids_for()` that only ever reads `species.avoids` directly and never scans the roster
	# for who names IT. `animal_definition.gd` explicitly permits declaring the relation on
	# either side alone, so swap in a deliberately ONE-SIDED fixture roster: only Hawk
	# declares `avoids`; Mouse stays silent. A one-directional implementation fails the
	# second assertion below, because it would never discover that Hawk named it.
	var hawk := AnimalDefinition.new()
	hawk.id = "hawk"
	hawk.display_name = "Hawk"
	hawk.avoids = ["mouse"] as Array[String]
	var mouse := AnimalDefinition.new()
	mouse.id = "mouse"
	mouse.display_name = "Mouse"
	# mouse.avoids is left empty on purpose — the one-sided half of the fixture.

	var real_roster: SpeciesRoster = _world.roster
	_world.roster = SpeciesRoster.new([hawk, mouse])
	check(HabitatRecipe.avoids_for(hawk, _world).has(mouse.display_name),
		"the declaring side (Hawk) names its target (Mouse)")
	check(HabitatRecipe.avoids_for(mouse, _world).has(hawk.display_name),
		"the SILENT side (Mouse) still names the declarer (Hawk) — fails if avoids_for() skips the reverse scan")
	# Restore the real roster: every check dispatched after this one in _process() expects it.
	_world.roster = real_roster


func _check_starter_prefers_free_terrain() -> void:
	var starter: AnimalDefinition = HabitatRecipe.easiest_species(_world)
	if not check(starter != null, "a starter species is derivable"):
		return
	var recipe: Dictionary = HabitatRecipe.recipe_for(starter, _world)
	for entry: Dictionary in (recipe["entries"] as Array):
		check_eq(entry["cost"], 0,
			"the starter's recipe is entirely free terrain (chip '%s')" % entry["id"])


func _check_unsatisfiable_species_describes_honestly() -> void:
	var ghost := AnimalDefinition.new()
	ghost.id = "ghost"
	ghost.display_name = "Ghost"
	ghost.habitat_needs = ["quiet"] as Array[String]
	check_eq(HabitatRecipe.describe(ghost, _world), HabitatRecipe.DESCRIBE_UNKNOWN,
		"an unsatisfiable species says so rather than describing a partial habitat")


## Final review finding #7: `tag_sources()` used to take a grouped placeable's `display_name`
## and `cost` from whichever MEMBER happened to emit the tag being looked up, rather than from
## the member `world.get_style_default(group_key)` says the player currently has selected —
## the same member `game_hud.gd::_placeable_group_row()` actually renders on the button and
## `TapRouter` actually places on a tap. LATENT with the real roster today (every
## `farm_building` member ships `emitted_tags = []`), so this is a fixture: Barn (cost 30,
## carrying the tag) and Silo (cost 15, carrying nothing) both share
## `hotbar_category = "farm_building"`, with "silo" set as the resolved default — the exact
## shape the header comment above predicts for "the day barn.tres gains an emitted_tags".
##
## Verified by mutation (see the final fix report): reverted `tag_sources()` to read
## `placeable.display_name`/`placeable.cost` directly instead of resolving through
## `_resolve_group_member()`, reran this suite, watched `display_name`/`cost` fail (both read
## back as Barn's), then restored the fix and reran to confirm green.
func _check_grouped_button_names_the_resolved_member() -> void:
	var barn := PlaceableDefinition.new()
	barn.id = "barn"
	barn.display_name = "Barn"
	barn.cost = 30
	barn.hotbar_category = "farm_building"
	barn.emitted_tags = ["farm_supply"] as Array[String]

	var silo := PlaceableDefinition.new()
	silo.id = "silo"
	silo.display_name = "Silo"
	silo.cost = 15
	silo.hotbar_category = "farm_building"
	silo.emitted_tags = [] as Array[String]

	var real_buildings: BuildingPlacement = _world.buildings
	var fixture_buildings := BuildingPlacement.new()
	fixture_buildings.attach(_world.grid, _world.wood, [barn, silo])
	_world.buildings = fixture_buildings

	var had_real_default: bool = _world.style_defaults.has("farm_building")
	var real_default: Variant = _world.style_defaults.get("farm_building", null)
	_world.style_defaults["farm_building"] = "silo"

	var sources: Dictionary = HabitatRecipe.tag_sources(_world)
	var entries: Array = sources.get("farm_supply", []) as Array
	if check(not entries.is_empty(), "the fixture farm_supply tag has a source"):
		var entry: Dictionary = entries[0] as Dictionary
		check_eq(entry["id"], "farm_building",
			"the source is keyed by the shared button, not by whichever member emitted the tag")
		check_eq(entry["display_name"], "Silo",
			"the chip names Silo — the player's CURRENT default — not Barn, whose emitted_tags "
			+ "happened to match")
		check_eq(entry["cost"], 15,
			"...and prices it at Silo's cost, not Barn's more expensive one")

	# Restore the real fixtures — every check dispatched after this one expects them.
	_world.buildings = real_buildings
	if had_real_default:
		_world.style_defaults["farm_building"] = real_default
	else:
		_world.style_defaults.erase("farm_building")
	# `BuildingPlacement extends Node`, never added to the tree here — `free()`, not
	# `queue_free()`, matching this suite's own `grid.free()` precedent elsewhere in this file
	# (this whole suite runs inside one `_process()` call, so a queued free would never run
	# before `finish()` quits the tree).
	fixture_buildings.free()


## Task 10's own failing test (habitat-tiers task-10-brief.md, Step 1): a species with two
## tiers must present BOTH — the one currently met, and the one above it — or nothing tells
## the player a stable would turn a pair into a herd.
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


## `built` is emitted by EVERY placeable (nine buildings and counting — see
## `AnimalDefinition.BUILDING_TAGS`), so a `built` limit must read as a place a player
## avoids, never a specific building, and Deer's real two tiers use two different
## tolerances (`max_count` 1, then 0) that must read as two different sentences, not the
## same "built <= N" formula with the number swapped — the human-readability half of Task
## 10's brief.
func _check_built_limit_reads_as_plain_english() -> void:
	var deer: AnimalDefinition = load(DEER_PATH) as AnimalDefinition
	if not check(deer != null, "deer.tres loads"):
		return
	var lines: Array[String] = HabitatRecipe.describe_tiers(deer)
	check_eq(lines.size(), 2, "deer presents its base and herd tiers")
	if lines.size() != 2:
		return
	for line: String in lines:
		check(not line.contains("built"), "the raw tag 'built' never reaches '%s'" % line)
		check(line.contains("buildings"), "the limit reads as a place, not a formula: '%s'" % line)
	check(lines[0].contains("away from buildings"),
		"the base tier (max_count 1, a distant cottage is tolerated) reads as tolerant: '%s'"
		% lines[0])
	check(lines[1].contains("far from any buildings"),
		"the herd tier (max_count 0, genuinely wild land) reads stricter than the base "
		+ "tier: '%s'" % lines[1])


## Grass, Wild Grass, Meadow and Scrub now share one palette button ("Grasslands" —
## `GameHud.TERRAIN_GROUP_ID`), but `open_grass` (Grass/Meadow) and `browse` (Scrub) remain
## DIFFERENT terrain underneath: placing one never satisfies the other. A tier line must
## therefore never collapse the two into the same generic "Grasslands" wording, and a tier
## needing BOTH (Deer's real herd tier does exactly this) must name both rather than
## silently dropping one as "already covered by Grasslands".
func _check_grasslands_tags_stay_distinct() -> void:
	var grass_species := AnimalDefinition.new()
	grass_species.id = "grass_test"
	grass_species.display_name = "Grass Test"
	var grass_tier := HabitatTier.new()
	grass_tier.id = "only"
	grass_tier.max_individuals = 4
	var grass_need := HabitatNeed.new()
	grass_need.tag = "open_grass"
	grass_need.tiles_per_individual = 5
	grass_tier.needs = [grass_need]
	grass_species.tiers = [grass_tier]

	var browse_species := AnimalDefinition.new()
	browse_species.id = "browse_test"
	browse_species.display_name = "Browse Test"
	var browse_tier := HabitatTier.new()
	browse_tier.id = "only"
	browse_tier.max_individuals = 4
	var browse_need := HabitatNeed.new()
	browse_need.tag = "browse"
	browse_need.tiles_per_individual = 5
	browse_tier.needs = [browse_need]
	browse_species.tiers = [browse_tier]

	var grass_lines: Array[String] = HabitatRecipe.describe_tiers(grass_species, _world)
	var browse_lines: Array[String] = HabitatRecipe.describe_tiers(browse_species, _world)
	if not check(grass_lines.size() == 1 and browse_lines.size() == 1,
		"both single-need fixtures present exactly one tier"):
		return
	check(not grass_lines[0].contains("Grasslands"),
		"the cosmetic palette-group name never leaks into the line: '%s'" % grass_lines[0])
	check(not browse_lines[0].contains("Grasslands"),
		"the cosmetic palette-group name never leaks into the line: '%s'" % browse_lines[0])
	check(grass_lines[0] != browse_lines[0],
		"open_grass and browse read as different requirements even though both currently "
		+ "sit behind the same palette button")

	# A tier needing BOTH open_grass and browse must name both — Deer's real herd tier is
	# exactly this shape.
	var both_species := AnimalDefinition.new()
	both_species.id = "both_test"
	both_species.display_name = "Both Test"
	var both_tier := HabitatTier.new()
	both_tier.id = "only"
	both_tier.max_individuals = 4
	var need_a := HabitatNeed.new()
	need_a.tag = "open_grass"
	need_a.tiles_per_individual = 5
	var need_b := HabitatNeed.new()
	need_b.tag = "browse"
	need_b.tiles_per_individual = 5
	both_tier.needs = [need_a, need_b]
	both_species.tiers = [both_tier]
	var both_lines: Array[String] = HabitatRecipe.describe_tiers(both_species, _world)
	if check(both_lines.size() == 1, "the combined fixture presents one tier"):
		check(both_lines[0].contains("scrub"),
			("browse's only real source (Scrub) is still named when open_grass is ALSO "
			+ "needed: '%s'") % both_lines[0])
		check(both_lines[0] != browse_lines[0],
			"the combined line is not just the browse-only line with open_grass silently "
			+ "dropped: '%s'" % both_lines[0])
