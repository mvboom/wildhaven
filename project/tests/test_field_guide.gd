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
## Final review finding #5: the old version of this check compared `FieldGuide.recipe_button_ids_for()`
## against `HabitatRecipe.recipe_for()` — but `_recipe_ids` is written FROM the same loop that
## builds the chips, so the two sides were guaranteed to agree regardless of whether a chip
## actually rendered (`card.add_child(chips)` could be deleted outright and this still passed).
## This version reads the chip `Label` text back out of the LIVE SCENE TREE
## (`recipe_chip_texts_for()`) and compares that against text independently rendered from
## `recipe_for()`'s entries via the same `CHIP_TEMPLATE`, so an actual rendering regression
## (a chip silently not added, or naming the wrong button — see finding #7) turns this red.
## Verified by mutation: temporarily commented out `card.add_child(chips)` in field_guide.gd
## and reran this suite — every one of these checks failed as expected (see the final fix
## report), then the line was restored and the suite went green again.
func _check_every_species_shows_its_recipe() -> void:
	for species: AnimalDefinition in _world.roster.species():
		var rendered: Array[String] = _guide.recipe_chip_texts_for(species.id)
		check(not rendered.is_empty(), "%s's card shows at least one recipe chip" % species.id)
		var expected: Array[String] = []
		for entry: Dictionary in (HabitatRecipe.recipe_for(species, _world)["entries"] as Array):
			expected.append(FieldGuide.CHIP_TEMPLATE % [entry["display_name"], entry["count"]])
		check_eq(rendered, expected,
			"%s's rendered chip text matches its derived recipe exactly" % species.id)
