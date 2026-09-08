extends QATestCase
## THE DERIVATION LAYER — habitat_needs -> emitted_tags -> palette button -> glyph, plus the
## copy, avoids, and starter-species selection built on top of it.
##
## The two arithmetic traps this suite exists to pin:
##   * a single source serving two of a species' needs must collapse to ONE chip, not two
##     (was: Rock emitting BOTH `cover` and `rocks` collapsed Stag's three legacy needs to
##     two chips — no longer exercisable by real data since `cover` was RETIRED 2026-09-07,
##     leaving Rock a single-tag terrain; `_check_rock_is_the_source_of_rocks()` below pins
##     the retirement itself, and `_check_stag_no_longer_dedupes_after_cover_retirement()`
##     pins that Stag's now-two legacy needs resolve to two DISTINCT chips instead);
##   * and a shared tile qualifies for both tags independently, so a merged chip's count is
##     `tiles_per_individual`, NOT doubled — still checked per-entry below even though no
##     shipped species currently exercises the merge itself.
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
const COW_PATH: String = "res://data/animals/cow.tres"
const SHEEP_PATH: String = "res://data/animals/sheep.tres"
const HUMAN_PATH: String = "res://data/animals/human.tres"
# Added 2026-09-08 for the counted-tile copy rewrite's own checks: Alpaca is the species
# whose card carried the defect verbatim, Bull and Villager are the roster's only cap-1
# tiers, Pug carries the second real multi-source gate (`house`), and Pig carries a
# resident-emitted need (`people`) that nothing in the palette can build.
const ALPACA_PATH: String = "res://data/animals/alpaca.tres"
const BULL_PATH: String = "res://data/animals/bull.tres"
const PUG_PATH: String = "res://data/animals/pug.tres"
const PIG_PATH: String = "res://data/animals/pig.tres"

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

	_check_rock_is_the_source_of_rocks()
	_check_stag_no_longer_dedupes_after_cover_retirement()
	_check_fox_reads_forest()
	_check_unsourced_need_is_unsatisfiable()
	_check_description_never_repeats_a_shared_source()
	_check_avoids_unions_both_directions()
	_check_starter_prefers_free_terrain()
	_check_starter_species_prefers_the_pinned_id_over_the_cost_score()
	_check_starter_species_falls_back_when_the_pinned_id_is_missing()
	_check_unsatisfiable_species_describes_honestly()
	_check_grouped_button_names_the_tag_carrying_member()
	_check_tiers_are_presented()
	_check_built_limit_reads_as_plain_english()
	_check_grasslands_tags_stay_distinct()
	_check_grouped_building_tags_name_the_carrying_member()
	_check_no_article_defects_across_the_roster()
	# The 2026-09-08 counted-tile copy rewrite — the Field Guide's tier lines becoming a
	# build list a six-year-old can act on. `_check_alpaca_reads_as_a_build_list()` is the
	# failing test the rewrite was written against; the four after it generalise its three
	# defects across the roster.
	_check_alpaca_reads_as_a_build_list()
	_check_rendered_counts_match_the_data()
	_check_cap_of_one_never_pluralizes()
	_check_multi_source_gate_reads_differently()
	_check_resident_needs_are_never_buildable()
	_check_upgrade_tiers_read_as_additions_only_when_they_are()

	finish()
	return true


## `cover` RETIRED 2026-09-07 (habitat-tiers re-spec moved every shipped consumer off it):
## Rock's job is now `rocks` alone. Pins both halves of the retirement — `rocks` still
## resolves, and `cover` resolves to nothing at all, not merely to an unconsumed tag.
func _check_rock_is_the_source_of_rocks() -> void:
	var sources: Dictionary = HabitatRecipe.tag_sources(_world)
	var rocks_entries: Array = sources.get("rocks", []) as Array
	if not check(not rocks_entries.is_empty(), "tag 'rocks' has a source"):
		return
	check_eq((rocks_entries[0] as Dictionary)["id"], "rock", "'rocks' resolves to the Rock button")
	check(rocks_entries.size() >= 2,
		"'rocks' has more than one source now (Rock and Scrub both emit it)")
	check(not sources.has("cover"), "'cover' no longer resolves to any source at all")


## Stag's legacy `habitat_needs` used to be `["forest", "cover", "rocks"]`, and Rock's
## shared `cover`+`rocks` emission collapsed the last two into one chip. `cover` was
## RETIRED 2026-09-07, leaving Stag's legacy field `["forest", "rocks"]` — two needs with
## two DISTINCT terrain sources (Forest, Rock), so no dedup fires any more. This pins the
## new, un-collapsed shape rather than silently losing the regression coverage.
func _check_stag_no_longer_dedupes_after_cover_retirement() -> void:
	var stag: AnimalDefinition = load(STAG_PATH) as AnimalDefinition
	if not check(stag != null, "stag.tres loads"):
		return
	var recipe: Dictionary = HabitatRecipe.recipe_for(stag, _world)
	check(recipe["satisfiable"] as bool, "stag is satisfiable")
	var entries: Array = recipe["entries"] as Array
	check_eq(entries.size(), 2, "stag's 2 legacy needs resolve to 2 distinct chips (no shared source left)")
	for entry: Dictionary in entries:
		check_eq(entry["count"], stag.tiles_per_individual,
			"chip '%s' counts tiles_per_individual, not a per-tag multiple" % entry["id"])
		check_eq((entry["tags"] as Array).size(), 1,
			"chip '%s' carries exactly one tag — nothing is deduped any more" % entry["id"])


## Fox's legacy `habitat_needs` used to be `["forest", "cover"]`, resolving to Forest + Rock.
## `cover` was RETIRED 2026-09-07 (habitat-tiers re-spec), dropping it from this legacy field
## too, so Fox's legacy needs now resolve to Forest alone.
func _check_fox_reads_forest() -> void:
	var fox: AnimalDefinition = load(FOX_PATH) as AnimalDefinition
	if not check(fox != null, "fox.tres loads"):
		return
	var recipe: Dictionary = HabitatRecipe.recipe_for(fox, _world)
	var ids: Array[String] = []
	for entry: Dictionary in (recipe["entries"] as Array):
		ids.append(entry["id"] as String)
	ids.sort()
	check_eq(ids, ["forest"] as Array[String], "fox resolves to Forest alone")


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
	# Rock supplies stag's `rocks` need; its phrase must appear exactly once regardless.
	# (Before `cover`'s 2026-09-07 retirement, Rock supplied BOTH of stag's rock-ish legacy
	# needs from one tile — see `_check_stag_no_longer_dedupes_after_cover_retirement()` for
	# where that dedup-arithmetic coverage now lives.)
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


## THE STARTER PIN (human ruling, 2026-09-04): `starter_species()` names Rabbit explicitly
## via `PINNED_STARTER_SPECIES_ID` rather than deriving it from `easiest_species_by_tier()`'s
## cost score — real tier data scores Deer cheaper (free terrain vs. Rabbit's Wood-costing
## `cultivated` need), which is correct arithmetic but the wrong first animal (Deer is Shy;
## Rabbit is Bold and visible). Against the full, untouched live roster this must be Rabbit.
func _check_starter_species_prefers_the_pinned_id_over_the_cost_score() -> void:
	var starter: AnimalDefinition = HabitatRecipe.starter_species(_world)
	if not check(starter != null, "the pinned starter is derivable from the live roster"):
		return
	check_eq(starter.id, "rabbit",
		"starter_species() returns the pinned id ('%s'), not whatever the cost score "
		% [HabitatRecipe.PINNED_STARTER_SPECIES_ID]
		+ "currently favours")


## GRACEFUL DEGRADATION: a roster that does not carry `PINNED_STARTER_SPECIES_ID` (a typo
## in the constant, or the pinned species retired later) must never return `null` or crash —
## `starter_species()` falls back to `easiest_species_by_tier()`'s derived pick instead, so
## the onboarding path never hard-fails or shows an empty coach over a stale id. Swaps in a
## fixture roster that deliberately omits "rabbit" entirely.
func _check_starter_species_falls_back_when_the_pinned_id_is_missing() -> void:
	var deer: AnimalDefinition = load(DEER_PATH) as AnimalDefinition
	if not check(deer != null, "%s loads" % DEER_PATH):
		return

	var real_roster: SpeciesRoster = _world.roster
	_world.roster = SpeciesRoster.new([deer])

	var expected_fallback: AnimalDefinition = HabitatRecipe.easiest_species_by_tier(_world)
	var starter: AnimalDefinition = HabitatRecipe.starter_species(_world)

	_world.roster = real_roster

	check(expected_fallback != null,
		"the fallback roster (Deer only) still derives a species via the cost score")
	check_eq(starter, expected_fallback,
		"a roster missing the pinned id falls back to easiest_species_by_tier()'s pick "
		+ "instead of returning null")


func _check_unsatisfiable_species_describes_honestly() -> void:
	var ghost := AnimalDefinition.new()
	ghost.id = "ghost"
	ghost.display_name = "Ghost"
	ghost.habitat_needs = ["quiet"] as Array[String]
	check_eq(HabitatRecipe.describe(ghost, _world), HabitatRecipe.DESCRIBE_UNKNOWN,
		"an unsatisfiable species says so rather than describing a partial habitat")


## REWRITTEN, habitat-tiers Task 10 fix round 1 (human-ruled, not a silent adjustment — see
## the fix report). Final review finding #7 originally ruled that a grouped placeable's
## `display_name`/`cost` should come from `world.get_style_default(group_key)` — the group's
## CURRENT default — not from whichever member actually carries the tag being looked up,
## reasoning that the chip should describe what pressing the button does RIGHT NOW. That was
## survivable while it was purely a fixture-only edge case (no real placeable's
## `emitted_tags` diverged from its siblings). It stopped being survivable once
## `barn.tres`/`open_barn.tres`/`windmill.tres`/`farmhouse.tres` were given real, DIFFERENT
## tags: `farm_building`'s style default resolves alphabetically to Barn, so Horse's
## `stable` (only Open Barn carries it), Sheep's `mill` (only Windmill) and Human's
## `large_house` (only Farmhouse) all mislabeled as "a barn" — and Cow's `barn` AND `silo`
## needs, sharing the one group button, deduped to a single mention and silently DROPPED the
## silo requirement outright. `display_name`/`cost` now come from the actual tag-emitting
## placeable, and a new `resolved_id` field carries that placeable's own id for callers (like
## `HabitatRecipe.describe_tiers()`) that must dedupe by BUILDING, not by button. This fixture
## still proves the same two-tag-one-button shape (Barn, cost 30, carrying `farm_supply`;
## Silo, cost 15, carrying nothing; both `hotbar_category = "farm_building"`, with "silo" set
## as the group's current default) — only the expected reading changed.
##
## Verified by mutation (original finding #7 fix report, preserved for context): reverting
## `tag_sources()` to read `placeable.display_name`/`placeable.cost` directly (which is what
## this fix round 1 now does PERMANENTLY) used to turn this red under the OLD assertions;
## under the NEW ones below it is the correct, expected behaviour instead.
func _check_grouped_button_names_the_tag_carrying_member() -> void:
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
			"the PALETTE BUTTON is still the shared group key, unaffected by this fix")
		check_eq(entry["resolved_id"], "barn",
			"the RESOLVED BUILDING is Barn — the member that actually carries farm_supply")
		check_eq(entry["display_name"], "Barn",
			"the chip names Barn, the tag-carrying member, not Silo, the group's current "
			+ "default, whose emitted_tags never matched")
		check_eq(entry["cost"], 30,
			"...and prices it at Barn's real cost, not Silo's cheaper one")

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


## FIX ROUND 1, CRITICAL. `farm_building`'s style default resolves alphabetically to
## `barn.tres`, so before this fix ANY farm-building tag Barn does not itself carry
## mislabeled as "a barn" in the tier line — four real species were affected: Horse
## (`stable`, only Open Barn), Sheep (`mill`, only Windmill), Human (`large_house`, only
## Farmhouse), and worst of all Cow, whose tiers need BOTH `barn` AND `silo` — two DIFFERENT
## buildings sharing one palette button — which the old button-keyed dedup silently
## collapsed to one mention, erasing the silo requirement entirely rather than merely
## mislabeling it. This asserts all four read the ACTUAL building against real `.tres` data
## and the real world catalog, and that Cow specifically names both.
##
## COW'S "barn" TAG USED TO RESOLVE TO "open barn" AND SAY SO, WHICH WAS THE HONEST-LOOKING
## HALF OF A REAL DEFECT. THREE placeables carry `barn` (Barn cost 30, Small Barn and Open
## Barn both cost 15), and `_cheapest()` — this file's one consistent tie-break rule, used by
## `easiest_species()` and `recipe_for()` alike — picks the cheapest, ties broken by catalog
## order (`open_barn.tres` sorts before `small_barn.tres`). Naming that winner was fine as an
## ANSWER and wrong as a SENTENCE: "needs an open barn" told a child the Small Barn they had
## already built did not count. As of the 2026-09-08 counted-tile rewrite a gate need with
## several interchangeable sources reads "a barn (any kind)" — derived from the shared last
## word of the sources' display names, so nothing here is hand-listed — while a gate with
## exactly one real source still names it outright, because "a windmill (any kind)" would be
## a lie in the other direction. `_check_multi_source_gate_reads_differently()` below pins
## both halves of that distinction; this function keeps pinning WHICH BUILDING each of the
## four affected species resolves to.
func _check_grouped_building_tags_name_the_carrying_member() -> void:
	var horse: AnimalDefinition = load(HORSE_PATH) as AnimalDefinition
	var cow: AnimalDefinition = load(COW_PATH) as AnimalDefinition
	var sheep: AnimalDefinition = load(SHEEP_PATH) as AnimalDefinition
	var human: AnimalDefinition = load(HUMAN_PATH) as AnimalDefinition
	if not check(
		horse != null and cow != null and sheep != null and human != null,
		"horse.tres, cow.tres, sheep.tres and human.tres all load"
	):
		return

	var horse_lines: Array[String] = HabitatRecipe.describe_tiers(horse, _world)
	if check(horse_lines.size() >= 1, "horse presents at least one tier"):
		check(horse_lines[0].contains("open barn"),
			"Horse's gate need (stable) names Open Barn, the only real source: '%s'"
			% horse_lines[0])
		check(not horse_lines[0].contains("a barn"),
			"...and NOT the group's alphabetical default, Barn, which does not carry "
			+ "stable: '%s'" % horse_lines[0])

	var sheep_lines: Array[String] = HabitatRecipe.describe_tiers(sheep, _world)
	if check(sheep_lines.size() >= 2, "sheep presents its base and flock tiers"):
		check(sheep_lines[1].contains("windmill"),
			"Sheep's flock-tier gate need (mill) names Windmill, the only real source: '%s'"
			% sheep_lines[1])

	var human_lines: Array[String] = HabitatRecipe.describe_tiers(human, _world)
	if check(human_lines.size() >= 2, "human presents its single and family tiers"):
		check(human_lines[1].contains("farmhouse"),
			"Human's family-tier gate need (large_house) names Farmhouse, the only real "
			+ "source: '%s'" % human_lines[1])

	# COW: THE REGRESSION THIS FIX EXISTS TO CATCH. Both tiers need `barn` AND `silo` — two
	# different buildings behind the SAME "Farm Building" palette button. The pre-fix
	# button-keyed dedup silently dropped whichever was seen second; a child would build a
	# barn-family building, wait, and nothing on screen would explain why no cow arrived.
	#
	# SCOPED FROM "EVERY LINE" TO "EVERY STANDALONE LINE", 2026-09-08 (counted-tile copy
	# rewrite). Cow's herd tier is its pair tier plus `water/3` with every other number
	# unchanged, so it renders as an explicit addendum ("Add this too, and there's room for
	# up to 6:") instead of a second full recipe — the human-approved mock's own shape. The
	# silo is stated once, on the line above, and "add this TOO" is what carries it down;
	# re-asserting it here would force every tier to repeat a whole recipe, which is the
	# wordiness this rewrite removes. The property that actually matters is unchanged and
	# still checked: no line may READ AS A COMPLETE RECIPE while omitting the silo. See
	# `test_field_guide.gd`'s `_check_cow_names_both_barn_and_silo()`, which pins the same
	# reading against the live scene tree.
	var cow_lines: Array[String] = HabitatRecipe.describe_tiers(cow, _world)
	if check(cow_lines.size() >= 2, "cow presents its pair and herd tiers"):
		check(cow_lines[0].contains("silo"),
			"cow's standalone tier line names Silo — the requirement a button-keyed dedup "
			+ "would have silently erased: '%s'" % cow_lines[0])
		check(cow_lines[0].contains("barn"),
			"...and still names a barn-family building too — two different buildings, one "
			+ "button, BOTH rendered: '%s'" % cow_lines[0])
		var add_one: String = HabitatRecipe.LEAD_ADD_ONE.get_slice("%", 0)
		var add_many: String = HabitatRecipe.LEAD_ADD_MANY.get_slice("%", 0)
		for i in range(1, cow_lines.size()):
			var line: String = cow_lines[i]
			check(
				line.contains("silo")
					or line.begins_with(add_one)
					or line.begins_with(add_many),
				("cow's later tier line either names Silo itself or is visibly an addendum "
				+ "to the line above: '%s'") % line
			)


## FIX ROUND 2, CRITICAL. `SOURCE_PHRASES` used to bake an article into some entries ("a
## house", "a farm field") because they were written for `describe()`'s "Likes X" sentence,
## which never minded either way. `describe_tiers()`'s templates DID mind, and disagreed
## with each other: the scaling clause never added its own article, so a baked-in one
## produced NOTHING ("more a farm field means room for more" — Human's cultivated scaling
## need, also Bull/Pig/Rabbit); the gate clause always adds one, so a baked-in one produced
## TWO ("needs an a house" — Human/Pug/Shiba Inu's `house`/`large_house` gate).
##
## Scans EVERY roster species' rendered tier lines for each symptom pattern, rather than
## pinning hardcoded strings — a single check that would also catch this defect reappearing
## for a species (or the fifteen-and-growing roster's sixteenth) that literals never would.
##
## THE SECOND PATTERN LIST WAS REPLACED, NOT DELETED, 2026-09-08 (counted-tile copy
## rewrite). `"more a "`/`"more an "` were the symptom of the OLD scaling clause ("more X
## means room for more"), which no longer exists — the clause is now a numbered bullet
## ("5 tiles of open grass for each alpaca"), so those two patterns became vacuous and would
## have gone on passing forever while checking nothing. What replaces them is the same idea
## re-derived for the new wording: the numbered-bullet template has its own three ways to
## produce a stub-looking artefact, and each is one substring away.
##   * `" 0 tiles"` — a GATE_ONLY need (`tiles_per_individual == 0`) leaking into the scaling
##     template. This is the STRUCTURAL half of the defect the rewrite exists to fix: a gate
##     is a building to place, never a quantity of tiles, and "0 tiles of barn" is what it
##     looks like when the two get crossed. Leading space so a future divisor of 10 cannot
##     false-positive off "10 tiles".
##   * `" 1 tiles"` — the singular/plural split failing. Villager's `cultivated/1` is the one
##     live need that exercises it (`NEED_TILES_ONE`), and it is exactly the kind of artefact
##     that makes a parent stop trusting the screen. Leading space for the same reason
##     ("11 tiles").
##   * `"_"` — a raw habitat tag reaching the player ("open_grass", "large_house"). No
##     authored string in this template contains an underscore, so this is a total check
##     rather than a list of the tags that happen to have one today; it is the same class of
##     defect `_check_built_limit_reads_as_plain_english()` pins for `built` specifically.
## `"[COPY]"` rides along for the same reason `test_new_game_screen.gd` scans for it: this
## copy was ruled on 2026-09-08 and the marker must never come back on a rendered line.
func _check_no_article_defects_across_the_roster() -> void:
	if not check(_world.roster != null and not _world.roster.species().is_empty(),
		"the roster loaded and is non-empty"):
		return
	var doubling_patterns: Array[String] = ["a a ", "a an ", "an a ", "an an "]
	var stub_patterns: Array[String] = [" 0 tiles", " 1 tiles", "_", "[COPY]"]
	for species: AnimalDefinition in _world.roster.species():
		for line: String in HabitatRecipe.describe_tiers(species, _world):
			for pattern: String in doubling_patterns:
				check(not line.contains(pattern),
					"%s's tier line has no article doubling ('%s'): '%s'"
					% [species.id, pattern, line])
			for pattern: String in stub_patterns:
				check(not line.contains(pattern),
					"%s's tier line has no stub artefact ('%s'): '%s'"
					% [species.id, pattern, line])


## THE DEFECT THE 2026-09-08 COUNTED-TILE REWRITE EXISTS TO FIX, pinned as a failing test
## first. Alpaca's card read:
##
##     [COPY] Up to 6: needs an open barn; more open grass and rocky cover means room for more.
##
## An adult could not answer "what do I actually need?" from that, three ways over, and every
## assertion below is one of them:
##   1. IT SPLIT THE NEEDS INTO REQUIRED AND OPTIONAL, BACKWARDS. "needs X" against "more Y
##      means room for more" gave the two halves different grammatical weight — but
##      `CapacityEvaluator.tier_capacity_from_counts()` takes a `min` over every scaling
##      need, and `floor(0 / 6) == 0`. Zero rock tiles means zero alpacas, barn or not. So no
##      line may carry the old "means room for more" register at all, and the alpaca line
##      must present its gate and BOTH scaling needs as one flat list of equals.
##   2. NO NUMBERS. `_check_rendered_counts_match_the_data()` below is the general form; here
##      it is enough to pin that Alpaca's two real divisors (5 and 6) actually appear.
##   3. IT NAMED THE CHEAPEST SOURCE AS THOUGH IT WERE THE ONLY ONE — "an open barn" while a
##      Small Barn or a Large Barn works identically.
func _check_alpaca_reads_as_a_build_list() -> void:
	var alpaca: AnimalDefinition = load(ALPACA_PATH) as AnimalDefinition
	if not check(alpaca != null, "%s loads" % ALPACA_PATH):
		return
	var lines: Array[String] = HabitatRecipe.describe_tiers(alpaca, _world)
	if not check(lines.size() == 1, "alpaca presents its one highland tier"):
		return
	var line: String = lines[0]

	check(not line.contains("means room for more"),
		"the optional-sounding scaling register is gone: '%s'" % line)
	check(not line.contains("needs "),
		"...and so is the 'needs X' clause that made the gate sound like the only rule: '%s'"
		% line)
	# One bullet per requirement: the `barn` gate and BOTH scaling needs, in one list under
	# one lead-in, with no grammar anywhere that ranks one above another.
	check_eq(line.count(HabitatRecipe.BULLET), 3,
		"all three of alpaca's requirements render as equal bullets: '%s'" % line)
	check(line.contains("5 tiles of open grass"),
		"open_grass's real divisor (5) is on screen: '%s'" % line)
	check(line.contains("6 tiles of rocky cover"),
		"rocks' real divisor (6) is on screen: '%s'" % line)
	check(not line.contains("an open barn"),
		("the `barn` gate no longer names the cheapest source as if it were the only one — "
		+ "Small Barn and Large Barn work identically: '%s'") % line)
	check(line.contains("barn"),
		"...but a barn is still named, because one is genuinely required: '%s'" % line)


## EVERY NUMBER ON THE CARD IS READ FROM DATA, NEVER AUTHORED — the property that makes a
## divisor retune a `.tres` edit with no copy change, exactly as `SOURCE_PHRASES` makes a
## tag rename one.
##
## Deliberately NOT written as "rebuild the expected sentence from the template constants and
## compare": that reduces to `template == template` and would pass against any arithmetic at
## all. Instead it takes the one thing the template does NOT decide — the noun, via the
## public `HabitatRecipe.need_noun()` seam — finds that noun in the rendered line, and reads
## back whatever number sits immediately in front of it. That number has to equal
## `HabitatNeed.tiles_per_individual`. Off-by-one, a hardcoded literal, or a count taken from
## the wrong need all turn this red.
##
## GATE-ONLY NEEDS ARE SKIPPED, not asserted at zero: a gate has no count by definition
## (`HabitatNeed.GATE_ONLY`), and the "no `0 tiles` anywhere" scan above is what pins that it
## never grows one. `max_individuals` is checked separately, since the cap sentence names no
## noun to anchor on.
func _check_rendered_counts_match_the_data() -> void:
	if not check(_world.roster != null and not _world.roster.species().is_empty(),
		"the roster loaded and is non-empty"):
		return
	for species: AnimalDefinition in _world.roster.species():
		var tiers: Array[HabitatTier] = species.effective_tiers()
		var lines: Array[String] = HabitatRecipe.describe_tiers(species, _world)
		if lines.size() != tiers.size():
			check(false, "%s renders one line per tier" % species.id)
			continue
		for i in range(tiers.size()):
			var line: String = lines[i]
			for need: HabitatNeed in tiers[i].needs:
				if need.is_gate_only():
					continue
				var noun: String = HabitatRecipe.need_noun(need.tag, _world)
				if noun.is_empty() or not line.contains(noun):
					# A need whose source was already named by an earlier need in the same
					# tier renders once, not twice (`_resolve_need()`'s dedup), and an upgrade
					# tier restates nothing it inherits from the tier above. Neither is a
					# missing count. Every roster tag's noun is plain lowercase words, so it
					# is safe to drop straight into the pattern below unescaped.
					continue
				var re := RegEx.new()
				re.compile("(\\d+) (?:tiles? of )?" + noun)
				var hit: RegExMatch = re.search(line)
				if not check(hit != null,
					"%s tier %d renders a number in front of '%s': '%s'"
					% [species.id, i, noun, line]):
					continue
				check_eq(hit.get_string(1).to_int(), need.tiles_per_individual,
					"%s tier %d's '%s' count is tiles_per_individual (%d), read from data"
					% [species.id, i, noun, need.tiles_per_individual])
			check(line.contains(str(tiers[i].max_individuals)),
				"%s tier %d states its own max_individuals (%d): '%s'"
				% [species.id, i, tiers[i].max_individuals, line])


## A CAP OF ONE MUST NEVER GROW PLURAL ARITHMETIC. Bull's pen tier and Villager's single tier
## both cap at 1, and `AnimalDefinition` carries no `plural_name` (see
## `HabitatRecipe.DESCRIBE_LEAD`), so any "double it for 2 bulls" phrasing would be both
## un-formable and false — `tier_capacity_from_counts()` caps at `max_individuals` outright.
## The "for each <animal>" divisor suffix is the live form of that hazard: it is correct
## everywhere a second individual can exist and meaningless where one cannot.
func _check_cap_of_one_never_pluralizes() -> void:
	var bull: AnimalDefinition = load(BULL_PATH) as AnimalDefinition
	var human: AnimalDefinition = load(HUMAN_PATH) as AnimalDefinition
	if not check(bull != null and human != null, "bull.tres and human.tres load"):
		return

	var bull_lines: Array[String] = HabitatRecipe.describe_tiers(bull, _world)
	if check(bull_lines.size() == 1, "bull presents its one pen tier"):
		check(not bull_lines[0].contains("for each"),
			"a tier capped at 1 renders no per-individual divisor: '%s'" % bull_lines[0])
		check(not bull_lines[0].to_lower().contains("double"),
			"...and no doubling arithmetic either: '%s'" % bull_lines[0])
		check(bull_lines[0].contains(HabitatRecipe.CAP_ONE % "bull"),
			"...it says outright that just one lives here: '%s'" % bull_lines[0])

	# Villager's SINGLE tier caps at 1 and its FAMILY tier at 4 — the same species proving
	# the suffix is driven by the tier's own cap, not by the species.
	var human_lines: Array[String] = HabitatRecipe.describe_tiers(human, _world)
	if check(human_lines.size() == 2, "villager presents its single and family tiers"):
		check(not human_lines[0].contains("for each"),
			"villager's cap-1 tier renders no divisor: '%s'" % human_lines[0])
		check(human_lines[1].contains("for each villager"),
			"villager's cap-4 tier does render one: '%s'" % human_lines[1])


## A TAG WITH SEVERAL INTERCHANGEABLE SOURCES MUST NOT READ LIKE ONE WITH A SINGLE SOURCE.
## This is defect 3 of the counted-tile rewrite, generalised past Alpaca: `_cheapest()` picks
## one winner per tag, and naming that winner as though it were the only answer is wrong for
## `barn` (Open Barn, Small Barn and Large Barn all carry it) and RIGHT for `silo`, `mill`,
## `stable` and `large_house` (one real source each — hedging those would be a lie in the
## other direction). Cow is the fixture that carries one of each in a single tier line.
##
## Checked as a CONTRAST rather than as two literals: the multi-source gate and the
## single-source gate on the same line must not render the same shape. A regression that
## dropped the distinction — going back to naming the cheapest everywhere, or "(any kind)"-ing
## everything — fails one half or the other.
func _check_multi_source_gate_reads_differently() -> void:
	var cow: AnimalDefinition = load(COW_PATH) as AnimalDefinition
	var pug: AnimalDefinition = load(PUG_PATH) as AnimalDefinition
	if not check(cow != null and pug != null, "cow.tres and pug.tres load"):
		return

	var sources: Dictionary = HabitatRecipe.tag_sources(_world)
	check((sources.get("barn", []) as Array).size() >= 2,
		"the fixture holds: `barn` really does have several sources")
	check_eq((sources.get("silo", []) as Array).size(), 1,
		"...and `silo` really does have exactly one")

	var cow_lines: Array[String] = HabitatRecipe.describe_tiers(cow, _world)
	var pug_lines: Array[String] = HabitatRecipe.describe_tiers(pug, _world)
	if not check(not cow_lines.is_empty() and not pug_lines.is_empty(),
		"cow and pug each present at least one tier"):
		return

	# Cow's pair tier carries BOTH gates, so one line proves the contrast: exactly one of the
	# two hedges, and the silo named flat.
	var cow_line: String = cow_lines[0]
	check(cow_line.contains("barn (any kind)"),
		"cow's multi-source `barn` gate says any of them will do: '%s'" % cow_line)
	check_eq(cow_line.count("(any kind)"), 1,
		"...and exactly one requirement on the line is hedged that way: '%s'" % cow_line)
	check(cow_line.contains("a silo"),
		"...the single-source `silo` gate is named flat, with no hedge: '%s'" % cow_line)

	# `house` is the other real multi-source gate (House and Farmhouse), and its sources share
	# no common word, so it takes the other branch: name them all, joined with "or".
	check((sources.get("house", []) as Array).size() >= 2, "`house` has several sources too")
	var pug_line: String = pug_lines[0]
	check(pug_line.contains("house") and pug_line.contains("farmhouse"),
		"pug's `house` gate names both real sources rather than only the cheaper: '%s'"
		% pug_line)
	check(pug_line.contains(" or "),
		"...joined as alternatives, not as a list of things to build: '%s'" % pug_line)


## YOU CANNOT BUILD A VILLAGER. `people` and `deer` are RESIDENT-emitted
## (`AnimalDefinition.emits_tags`), so `tag_sources()` structurally cannot resolve them and
## no palette button places one. Two things follow, and both are copy correctness rather than
## polish: the tier's lead-in must not tell a child to build one, and the count must not be
## measured in tiles.
##
## `"villagers"`, not `"people"`, is the roster-wide terminology check — `human.tres`'s
## `display_name` is "Villager" and the Field Guide row directly above these lines says
## "Villager", so a tier line reading "3 people" would be the only place in the game calling
## them anything else. Stag's `deer/4` is the other half: a species requirement on another
## species, rendered as company rather than as anything a stag does to a deer.
func _check_resident_needs_are_never_buildable() -> void:
	var stag: AnimalDefinition = load(STAG_PATH) as AnimalDefinition
	var pig: AnimalDefinition = load(PIG_PATH) as AnimalDefinition
	if not check(stag != null and pig != null, "stag.tres and pig.tres load"):
		return

	var pig_lines: Array[String] = HabitatRecipe.describe_tiers(pig, _world)
	var stag_lines: Array[String] = HabitatRecipe.describe_tiers(stag, _world)
	if not check(not pig_lines.is_empty() and not stag_lines.is_empty(),
		"pig and stag each present at least one tier"):
		return

	var pig_line: String = pig_lines[0]
	check(pig_line.contains("2 villagers"),
		"pig's `people/2` need names villagers, the roster's own word: '%s'" % pig_line)
	check(not pig_line.contains("people"),
		"...and never the raw tag: '%s'" % pig_line)
	check(not pig_line.contains("tiles of villagers"),
		"...and is not measured in tiles: '%s'" % pig_line)
	# Compared against the WHOLE rendered lead-in, not a prefix: both lead-ins open "To
	# invite ", so a prefix comparison would pass against either one and check nothing.
	check(pig_line.begins_with(HabitatRecipe.LEAD_NEED % "a pig"),
		"a species needing villagers is told it NEEDS them, not that it can build them: '%s'"
		% pig_line)
	check(not pig_line.contains(HabitatRecipe.LEAD_BUILD % "a pig"),
		"...and never carries the buildable lead-in: '%s'" % pig_line)

	var stag_line: String = stag_lines[0]
	check(stag_line.contains("4 deer"),
		"stag's `deer/4` need renders its real divisor: '%s'" % stag_line)
	check(not stag_line.contains("tiles of deer"),
		"...and is not measured in tiles either: '%s'" % stag_line)


## THE UPGRADE READING — the payoff of the whole habitat-tiers branch, restated for the
## counted-tile copy. A second tier is one of two completely different things, and telling a
## child the wrong one makes them build the wrong thing:
##   * COW's herd tier is its pair tier plus `water/3`, every other need and number identical,
##     so it reads as an ADDITION ("Add this too, and there's room for up to 6").
##   * VILLAGER's family tier SWAPS `house` for `large_house` and re-tunes `cultivated` from
##     1 tile each to 2, so it reads as an ALTERNATIVE ("...build these nearby instead").
##     Rendering that as "add a farmhouse" would leave a child building against the old
##     number and wondering why nobody came.
## Deer is the third shape and the trap a needs-only comparison falls into: its herd tier's
## needs really are a superset of its base tier's, but its `built` limit tightens from "at
## most 1" to "none at all", so it must NOT read as an addition either.
func _check_upgrade_tiers_read_as_additions_only_when_they_are() -> void:
	var cow: AnimalDefinition = load(COW_PATH) as AnimalDefinition
	var human: AnimalDefinition = load(HUMAN_PATH) as AnimalDefinition
	var deer: AnimalDefinition = load(DEER_PATH) as AnimalDefinition
	if not check(cow != null and human != null and deer != null,
		"cow.tres, human.tres and deer.tres load"):
		return

	var add_one: String = HabitatRecipe.LEAD_ADD_ONE.get_slice("%", 0)
	var add_many: String = HabitatRecipe.LEAD_ADD_MANY.get_slice("%", 0)

	var cow_lines: Array[String] = HabitatRecipe.describe_tiers(cow, _world)
	if check(cow_lines.size() == 2, "cow presents two tiers"):
		check(cow_lines[1].begins_with(add_one) or cow_lines[1].begins_with(add_many),
			"cow's herd tier reads as an addition to the pair tier: '%s'" % cow_lines[1])
		check(cow_lines[1].contains("3 tiles of water"),
			"...and names the one need that unlocks it, with its real divisor: '%s'"
			% cow_lines[1])

	var human_lines: Array[String] = HabitatRecipe.describe_tiers(human, _world)
	if check(human_lines.size() == 2, "villager presents two tiers"):
		check(not human_lines[1].begins_with(add_one)
			and not human_lines[1].begins_with(add_many),
			("villager's family tier swaps a gate and re-tunes a divisor, so it must NOT "
			+ "read as an addition: '%s'") % human_lines[1])
		check(human_lines[1].contains("2 tiles of farm field"),
			("...it restates the RE-TUNED cultivated divisor (2, not the single tier's 1): "
			+ "'%s'") % human_lines[1])

	var deer_lines: Array[String] = HabitatRecipe.describe_tiers(deer, _world)
	if check(deer_lines.size() == 2, "deer presents two tiers"):
		check(not deer_lines[1].begins_with(add_one)
			and not deer_lines[1].begins_with(add_many),
			("deer's herd tier is a needs-superset but tightens its `built` limit, so it "
			+ "must NOT read as an addition: '%s'") % deer_lines[1])
