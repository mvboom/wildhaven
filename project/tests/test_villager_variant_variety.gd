extends QATestCase
## THE REPORTED BUG: "we pick a random character once, and every instantiation of a villager is
## that one." Every villager in the world wore the same model.
##
## ROOT CAUSE. `HabitatSimulation._move_in()` resolved a resident's look with
## `species.pick_variant(site.residents.size())` — a hash of the resident's slot within its OWN
## home site's `residents` array. That slot is not a global identity: the FIRST resident at every
## home site in the world hashed to the same number. Measured for the villager's 18 looks,
## `hash(i) % 18` for i in 0..9 is `[15, 4, 14, 10, 1, 9, 11, 17, 10, 14]`, and home sites
## typically hold one or two residents — so nearly every villager in the world was variant 15,
## and the hash collides inside those ten slots too (3 and 8 both -> 10, 2 and 9 both -> 14), so
## only 8 of the 18 looks were reachable there at all.
##
## THE FIX, and what this suite pins:
##   1. **The regression.** Residents spawned across several home sites get DISTINCT looks while
##      the count stays inside `model_scenes.size()`. This is the assertion that fails against
##      the pre-fix code: with two or more home sites, every site's slot-0 resident came out
##      identical.
##   2. **The requirement, not just the absence of the bug.** The human asked for "every villager
##      look before any look repeats" — a shuffle bag, not an independent roll per villager
##      (which repeats early by the birthday problem: with 18 looks a repeat is already
##      more-likely-than-not by the 6th villager). So exhaustion is asserted directly on
##      `VariantBag`: 18 draws cover all 18 exactly once, and the 19th opens a fresh bag.
##
## SAVE/LOAD STABILITY AND OLD-SAVE COMPATIBILITY are the other half of this fix and are pinned
## in `test_human_variant_save_stability.gd`, against the real `WorldSnapshot.capture()`/`apply()`
## path with a real `WorldRoot` — this suite is deliberately scene-free and headless.

## The villager's pool size at the time of the bug report. Used for the exhaustion check so the
## numbers in the header above are the numbers being asserted.
const VILLAGER_LOOKS: int = 18

## Fixture habitat. Four blocks of `cover`, far enough apart (20 tiles, against a scout radius
## of 8) that no two can share a tile — which is what guarantees SEVERAL home sites, and several
## home sites is the exact condition the bug needed to show itself.
const BLOCK_ORIGINS: Array[Vector2i] = [
	Vector2i(4, 4), Vector2i(4, 24), Vector2i(24, 4), Vector2i(24, 24),
]
const BLOCK_W: int = 4
const BLOCK_D: int = 3

## How long the fixture is driven. Each tick is handed more than a whole arrival delay so the
## queue resolves immediately instead of over real frames — the same shortcut
## `test_event_driven_simulation.gd` uses.
const TICKS: int = 400

## Six distinct grey-box scenes stand in for a species with six looks. Placeholder terrain
## scenes rather than the real human wrappers on purpose: this suite must keep asserting the
## same thing when the roster's content changes.
const FIXTURE_SCENES: Array[String] = [
	"res://assets/placeholder/grass/Grass.tscn",
	"res://assets/placeholder/forest/Forest.tscn",
	"res://assets/placeholder/rock/Rock.tscn",
	"res://assets/placeholder/water/Water.tscn",
	"res://assets/placeholder/wild_grass/WildGrass.tscn",
	"res://assets/placeholder/cultivated_field/CultivatedField.tscn",
]


func _init() -> void:
	begin("villager variant variety (shuffle bag)")
	_check_the_regression()
	_check_the_bag_exhausts_before_repeating()
	_check_a_single_variant_species_is_unaffected()
	finish()


# --- 1. The regression ---------------------------------------------------------------------

## Spawns residents across several home sites through the REAL move-in path and asserts every
## look is distinct while the population is within the pool.
##
## Deliberately driven through `on_terraform()` + `tick()` rather than by calling `_move_in()`
## directly: the bug was in what the spawn path passed, so a test that hand-feeds the spawn path
## its argument would be testing the wrong thing.
func _check_the_regression() -> void:
	var fixture: Dictionary = _fixture(FIXTURE_SCENES.size())
	var sim: HabitatSimulation = fixture["sim"]
	var registry: HomeSiteRegistry = fixture["registry"]
	var residents_root: Node3D = fixture["residents"]

	_paint_habitat(fixture)
	for _i in TICKS:
		sim.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)

	# Preconditions. Without SEVERAL sites this assertion cannot see the bug at all, so a
	# fixture that quietly stopped producing them must fail loudly rather than pass vacuously.
	var settled: int = 0
	for site: HomeSite in registry.sites():
		if site.population() > 0:
			settled += 1
	if not check(settled >= 2,
			"precondition: residents settled at 2 or more DISTINCT home sites",
			"only %d settled site(s) — the fixture cannot see the bug" % settled):
		_teardown(fixture)
		return

	var looks: Array[String] = []
	for node: Node in residents_root.get_children():
		looks.append((node as Node3D).scene_file_path)
	if not check(looks.size() >= 3,
			"precondition: at least 3 residents spawned",
			"got %d" % looks.size()):
		_teardown(fixture)
		return

	# THE ASSERTION. While the population is inside the pool, no look may repeat.
	var window: int = mini(looks.size(), FIXTURE_SCENES.size())
	var seen: Dictionary = {}
	for i in window:
		seen[looks[i]] = true
	check(seen.size() == window,
		"the first %d villagers across %d home sites wear %d DISTINCT looks"
			% [window, settled, window],
		"got %d distinct look(s) from %d residents: %s"
			% [seen.size(), window, str(looks.slice(0, window))])

	# The pre-fix failure mode, named specifically, so a future regression reports the SYMPTOM
	# the human reported rather than only a count mismatch.
	check(seen.size() > 1,
		"...and in particular they are not all the SAME look (the reported bug)",
		"every resident in the world is wearing %s" % str(seen.keys()))

	_teardown(fixture)


# --- 2. The requirement: exhaustion before repetition ---------------------------------------

func _check_the_bag_exhausts_before_repeating() -> void:
	var bag := VariantBag.new()
	bag.set_rng_seed(20260830)

	var first_pass: Array[int] = []
	for _i in VILLAGER_LOOKS:
		first_pass.append(bag.next("human", VILLAGER_LOOKS))

	var seen: Dictionary = {}
	for value: int in first_pass:
		seen[value] = true
	check(seen.size() == VILLAGER_LOOKS,
		"%d draws from a %d-look bag cover every look EXACTLY ONCE" % [VILLAGER_LOOKS, VILLAGER_LOOKS],
		"got %d distinct of %d: %s" % [seen.size(), VILLAGER_LOOKS, str(first_pass)])

	var in_range: bool = true
	for value: int in first_pass:
		if value < 0 or value >= VILLAGER_LOOKS:
			in_range = false
	check(in_range, "...and every one of them is a real model_scenes index")

	check_eq(bag.remaining("human"), 0, "the bag is empty after %d draws" % VILLAGER_LOOKS)

	# The 19th draw opens a fresh bag rather than returning a sentinel or repeating forever.
	var nineteenth: int = bag.next("human", VILLAGER_LOOKS)
	check(nineteenth >= 0 and nineteenth < VILLAGER_LOOKS,
		"the 19th draw starts a NEW bag and is a real index")
	check_eq(bag.remaining("human"), VILLAGER_LOOKS - 1,
		"...and that new bag has the other %d looks still in it" % (VILLAGER_LOOKS - 1))

	# THE SEAM RULE — the conservative reading, and a PROPOSAL rather than a decided value (see
	# `VariantBag._fresh_bag()`): a look may not repeat back-to-back across a bag boundary.
	check(nineteenth != first_pass[VILLAGER_LOOKS - 1],
		"the first look of the new bag is not the last look of the old one (no back-to-back "
		+ "repeat across the seam)",
		"look %d was dealt twice in a row" % nineteenth)

	# Second pass is a permutation too — the bag is not simply cycling one fixed order.
	var second_pass: Array[int] = [nineteenth]
	for _i in VILLAGER_LOOKS - 1:
		second_pass.append(bag.next("human", VILLAGER_LOOKS))
	var seen_again: Dictionary = {}
	for value: int in second_pass:
		seen_again[value] = true
	check(seen_again.size() == VILLAGER_LOOKS,
		"the second bag is a full permutation as well, not a partial refill")


# --- 3. The rest of the roster is untouched --------------------------------------------------

## Most of the roster has exactly one look. That case must stay free — no bag allocated, no RNG
## drawn, always index 0 — which is also what keeps `pick_variant()` correct for those species.
func _check_a_single_variant_species_is_unaffected() -> void:
	var bag := VariantBag.new()
	var all_zero: bool = true
	for _i in 20:
		if bag.next("fox", 1) != 0:
			all_zero = false
	check(all_zero, "a single-variant species always draws index 0")
	check_eq(bag.remaining("fox"), 0, "...and never allocates a bag for it")

	check_eq(bag.next("ghost", 0), VariantBag.NO_VARIANT,
		"a species with NO model_scenes draws NO_VARIANT rather than inventing an index")

	var single := AnimalDefinition.new()
	single.model_scenes = [load(FIXTURE_SCENES[0]) as PackedScene]
	check_eq(single.pick_variant(0), single.model_scenes[0],
		"AnimalDefinition.pick_variant() still answers for a single-variant species")
	check_eq(single.pick_variant(41), single.model_scenes[0], "...at any index")


# --- fixture ----------------------------------------------------------------------------------

## A scene-free world: real grid, real registry, real queue, and a one-species synthetic roster
## whose only need is `cover`. Mirrors `test_event_driven_simulation.gd`'s fixture, with a
## multi-look species in place of its single grey box.
func _fixture(look_count: int) -> Dictionary:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 36, 36)

	var species := AnimalDefinition.new()
	species.id = "villager_fixture"
	species.display_name = "Villager Fixture"
	species.habitat_needs = ["cover"] as Array[String]
	species.personality = AnimalDefinition.PERSONALITY_BOLD
	species.tiles_per_individual = 4
	species.scout_radius = 8
	species.max_individuals = 6
	species.fact_text_pool = ["Test fixture copy."]
	var scenes: Array[PackedScene] = []
	for i in look_count:
		scenes.append(load(FIXTURE_SCENES[i]) as PackedScene)
	species.model_scenes = scenes

	var registry := HomeSiteRegistry.new()
	var arrivals := ArrivalQueue.new(20260830)
	var residents_root := Node3D.new()
	var sim := HabitatSimulation.new()
	sim.attach(grid, SpeciesRoster.new([species]), registry, arrivals, residents_root)
	# Pinned so a red here is reproducible rather than a one-in-N shuffle.
	sim.variants().set_rng_seed(20260830)

	return {
		"grid": grid, "sim": sim, "registry": registry, "arrivals": arrivals,
		"species": species, "residents": residents_root,
	}


func _paint_habitat(fixture: Dictionary) -> void:
	var grid: WorldGrid = fixture["grid"]
	var sim: HabitatSimulation = fixture["sim"]
	for origin: Vector2i in BLOCK_ORIGINS:
		for dx in BLOCK_W:
			for dz in BLOCK_D:
				var x: int = origin.x + dx
				var z: int = origin.y + dz
				grid.set_terrain(x, z, "rock")
				sim.on_terraform(Vector2i(x, z))


func _teardown(fixture: Dictionary) -> void:
	(fixture["sim"] as HabitatSimulation).free()
	(fixture["grid"] as WorldGrid).free()
	(fixture["residents"] as Node3D).free()
