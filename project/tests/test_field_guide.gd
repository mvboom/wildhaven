extends QATestCase
## THE FIELD GUIDE'S DISCOVERED SET (playability chrome overhaul, section 3 —
## docs/superpowers/specs/2026-08-09-playability-chrome-overhaul-design.md).
##
## `HomeSiteRegistry._ever_hosted` (home_site_registry.gd) already records a species the
## moment it moves in and NEVER removes the record (`unregister()`'s own comment: "Species
## Hosted never decreases") — this suite proves `FieldGuide` actually reads that permanent
## record rather than the current-residents-only list.
##
## Run:
##   bash scripts/run-tests.sh field_guide

const WORLD_PATH: String = "res://scenes/Main.tscn"

var _world: WorldRoot = null
var _ui: GameUI = null
var _guide: FieldGuide = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("field guide")
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

	var ui_node: Node = _world.get_node_or_null("GameUI")
	if not check(ui_node is GameUI, "Main.tscn instances the GameUI shell"):
		finish()
		return true
	_ui = ui_node as GameUI
	_ui.bind_world()
	_guide = _ui.menu_window.get_node("%FieldGuide") as FieldGuide

	_check_departed_species_still_shows()
	_check_whole_roster_shows_real_names()
	_check_every_species_shows_its_recipe()
	_check_cow_names_both_barn_and_silo()

	finish()
	return true


func _check_departed_species_still_shows() -> void:
	var species: AnimalDefinition = _world.roster.by_id("rabbit")
	if not check(species != null, "the rabbit is in the roster"):
		return

	var tile := Vector2i(20, 20)
	var site: HomeSite = _world.registry.register(tile, "rabbit", species.scout_radius)
	_guide.refresh_from(_world)
	check(_guide.species_row_texts().has(species.display_name),
		"a freshly-registered rabbit shows in the guide",
		"got %s" % str(_guide.species_row_texts()))

	_world.registry.unregister(site)
	check_eq(_world.resident_species_ids().has("rabbit"), false,
		"the rabbit is no longer a CURRENT resident")
	check(_world.species_hosted_ids().has("rabbit"),
		"...but it IS still in the ALL-TIME hosted record (HomeSiteRegistry never forgets)")

	_guide.refresh_from(_world)
	check(_guide.species_row_texts().has(species.display_name),
		"THE FIX: the Field Guide still shows the rabbit after it departed — the list and "
		+ "the Species Hosted counter beside it now agree",
		"got %s" % str(_guide.species_row_texts()))


## The successor to `_check_whole_roster_shows_with_silhouettes()`. The `???` silhouette is
## retired: a player cannot decide "I want a Fox" if the guide will not say the word "Fox".
func _check_whole_roster_shows_real_names() -> void:
	var texts: Array[String] = _guide.species_row_texts()
	check_eq(texts.size(), _world.roster.species().size(), "one card per roster species")
	check(not texts.has(FieldGuide.UNDISCOVERED_GLYPH),
		"no card renders the retired '???' silhouette")
	for species: AnimalDefinition in _world.roster.species():
		check(texts.has(species.display_name),
			"%s is named outright, discovered or not" % species.id)


## The successor to `_check_field_guide_never_shows_a_habitat_preference()` — the line
## `field_guide.gd`'s old header called "the line that must never move". Moving it IS the
## change; the safety property it protected now lives in test_field_guide_reachability.gd.
##
## REWRITTEN, habitat-tiers Task 10 fix round 1 (human-ruled, not a silent adjustment — see
## the fix report). This used to compare `recipe_chip_texts_for()`'s rendered chips against
## `HabitatRecipe.recipe_for()`'s entries: correct at the time, but `recipe_for()` reads the
## flat, pre-tier `habitat_needs` field, which is byte-identical for Cow/Bull
## (`["cultivated","open_grass"]`) and for Horse/Alpaca (`["open_grass","cultivated"]`) — the
## exact "these species look the same" defect the whole habitat-tiers branch exists to fix,
## which a passing chip-vs-`recipe_for()` comparison could never catch because both sides of
## the comparison shared the same blind spot. `field_guide.gd` no longer renders those chips
## at all (see that file's own header for the full reasoning — a GATE_ONLY need has no tile
## count a chip's "×N" shape can honestly show, so the chip row was removed rather than
## repointed under this fix). This version reads the TIER lines back out of the LIVE SCENE
## TREE (`tier_line_texts_for()`) and compares them against `HabitatRecipe.describe_tiers()`
## — the function that actually reads `effective_tiers()`, not the flat field — so a
## rendering regression (a line silently not added, or the wrong text) turns this red, and a
## return of the old flat-field defect would too, since `describe_tiers()` is what Task 10
## exists to prove distinguishes these species. Verified by mutation: temporarily commented
## out `card.add_child(tier_box)` in field_guide.gd and reran this suite — every one of these
## checks failed as expected, then the line was restored and the suite went green again.
func _check_every_species_shows_its_recipe() -> void:
	for species: AnimalDefinition in _world.roster.species():
		var rendered: Array[String] = _guide.tier_line_texts_for(species.id)
		check(not rendered.is_empty(), "%s's card shows at least one tier line" % species.id)
		var expected: Array[String] = HabitatRecipe.describe_tiers(species, _world)
		check_eq(rendered, expected,
			"%s's rendered tier text matches describe_tiers() exactly" % species.id)


## THE REGRESSION FIX ROUND 1 EXISTS TO CATCH: Cow's real tiers need BOTH `barn` and `silo` —
## two different buildings that happen to share the "Farm Building" palette button — and the
## pre-fix dedup (keyed on the shared button, not the resolved building) silently dropped
## whichever was seen second. A player would build a Barn, wait, and nothing on screen would
## explain why no cow arrived. This asserts the rendered card actually names BOTH.
func _check_cow_names_both_barn_and_silo() -> void:
	var cow: AnimalDefinition = _world.roster.by_id("cow")
	if not check(cow != null, "the roster carries cow"):
		return
	var rendered: Array[String] = _guide.tier_line_texts_for("cow")
	if not check(not rendered.is_empty(), "cow's card shows at least one tier line"):
		return
	for line: String in rendered:
		check(line.contains("silo"), "cow's tier line names Silo, not just Barn: '%s'" % line)
