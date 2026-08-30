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
	_check_whole_roster_shows_with_silhouettes()
	_check_field_guide_never_shows_a_habitat_preference()

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


func _check_whole_roster_shows_with_silhouettes() -> void:
	var roster_species: Array[AnimalDefinition] = _world.roster.species()
	if not check(roster_species.size() >= 2, "the roster has at least two species to test with"):
		return

	# A roster id nothing in this suite has hosted yet.
	var undiscovered: AnimalDefinition = null
	for species: AnimalDefinition in roster_species:
		if not _world.species_hosted_ids().has(species.id):
			undiscovered = species
			break
	if not check(undiscovered != null,
		"at least one roster species is still undiscovered at this point in the suite"):
		return

	_guide.refresh_from(_world)
	var rows: Array[String] = _guide.species_row_texts()

	check_eq(rows.size(), roster_species.size(),
		"THE EXCEPTION: the guide lists EVERY roster species, discovered or not")
	check(rows.has(FieldGuide.UNDISCOVERED_GLYPH),
		"an undiscovered species renders as the silhouette glyph, never its name",
		"got %s" % str(rows))
	check(not rows.has(undiscovered.display_name),
		"...specifically, %s's own name does not appear anywhere" % undiscovered.display_name)

	# Discover it, and its row switches from silhouette to its real name.
	_world.registry.register(Vector2i(22, 22), undiscovered.id, undiscovered.scout_radius)
	_guide.refresh_from(_world)
	var rows_after: Array[String] = _guide.species_row_texts()
	check(rows_after.has(undiscovered.display_name),
		"once hosted, the same species' row shows its real name")


func _check_field_guide_never_shows_a_habitat_preference() -> void:
	# THE SCOPE LIMIT (spec section 3): existence only. STRUCTURAL CHECK (the one that
	# actually has to hold): every rendered row's text is EXACTLY a roster species'
	# `display_name` or `UNDISCOVERED_GLYPH` — nothing appended, nothing substituted. A
	# substring scan against `HABITAT_TAGS` alone can't tell "leaks a tag word" apart from
	# "a species is legitimately named e.g. 'Forest Fox'", and would false-fail the day the
	# roster gains a display name that happens to contain a tag word; asserting exact set
	# membership can't be fooled either way.
	_guide.refresh_from(_world)
	var allowed_texts: Dictionary = {FieldGuide.UNDISCOVERED_GLYPH: true}
	for species: AnimalDefinition in _world.roster.species():
		allowed_texts[species.display_name] = true
	for row_text: String in _guide.species_row_texts():
		check(allowed_texts.has(row_text),
			("row '%s' is exactly a roster species' display_name or the undiscovered glyph, "
			+ "nothing else appended") % row_text)

	# Kept as a second, weaker signal alongside the structural check above: still catches a
	# tag word smuggled directly into a row's text (e.g. via a future format string), just
	# not one that arrives coincidentally inside a real display name.
	var tag_words: PackedStringArray = AnimalDefinition.HABITAT_TAGS
	for row_text: String in _guide.species_row_texts():
		for tag: String in tag_words:
			check(not row_text.contains(tag),
				"row '%s' does not leak the habitat tag word '%s'" % [row_text, tag])
