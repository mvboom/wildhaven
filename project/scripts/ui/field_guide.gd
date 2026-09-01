class_name FieldGuide
extends Control
## Tier 1 row 11's second half — a discovery tracker screen. As of the Minecraft-style
## inventory window, reachable only as a tab of `MenuWindow` (press Tab to open the window,
## then its Field Guide tab) — there is no standalone top-right icon any more; spec.md ->
## Screen Layouts predates this change.
##
## EVERY ROSTER SPECIES SHOWS ITS REAL NAME AND ITS RECIPE, DISCOVERED OR NOT — superseding
## decision, this session, logged as `decisions.md` (amending D-40, which amended D-34 #5 and
## #6). D-40 traded the roster's total size for withholding *how to invite each species*; that
## trade is overturned here. The reasoning: this screen is PULLED, not PUSHED — a player opens
## it by tapping `[?]`, an action that is itself a request for help, not something dropped in
## front of them mid-play. gdd.md -> Objectives & Progression's "No completion percentage,
## total-species count, or finish-the-guide reward" is still honored: nothing here is a tally
## (see `HERE_TEMPLATE`'s zero-suppression below) or a checklist against the roster's size. The
## safety property D-40's exception used to protect — that nothing pushed at the player during
## play reveals a habitat preference — now lives in `test_field_guide_reachability.gd`, which
## proves every recipe this screen renders is actually buildable rather than checking that the
## screen stays silent about them.
##
## NO PORTRAITS. `AnimalDefinition` carries no portrait texture (only `model_scenes`, a 3D
## asset) — `FactCard`'s own "portrait" is an empty coloured frame, not an image, and this
## screen matches that precedent rather than inventing an art asset this dispatch was not
## given. A silhouette row is text (`UNDISCOVERED_GLYPH`), not a greyed-out image, for the
## same reason.
##
## NOT READ-ALOUD. spec.md -> Screen Layouts: "wider coverage (News Reports, Field Guide) is
## deferred (future.md)" — no 🔊 button here, by design, not omission.
##
## NOT PAUSED, NOT BLOCKING. Same non-pausing treatment as `FactCard` and the Settings overlay
## (Pillar 1: "there is nothing to protect the player from") — the world stays visible and
## simulating behind the panel. The scrim and "tap outside dismisses" behaviour used to live
## here; as of Task 5 (Minecraft-style inventory window), this screen is pure tab content
## hosted inside `MenuWindow`, which owns the one scrim and the one dismiss gesture for all of
## its tabs.

## [COPY] — content-writer's. Shown only if the roster itself has no species loaded at
## all — a data/config problem, not a "haven't played yet" state (every species now shows
## as a row regardless of discovery, so an empty list can only mean the roster failed to
## load). Marked and rendering visibly as a stub because no approved string exists yet.
const EMPTY_STATE_TEXT: String = "[COPY] No animals are configured yet."

## RETIRED as of the superseding decision in the header above: no card renders this any more,
## discovered or not — every species now shows its real name outright. Kept, unrendered, only
## because `test_field_guide.gd` asserts against it directly to prove the retirement stuck
## (`check(not texts.has(FieldGuide.UNDISCOVERED_GLYPH), ...)`); deleting the constant would
## just make that assertion uncompilable instead of meaningful.
const UNDISCOVERED_GLYPH: String = "???"

## [COPY] — content-writer's. `%d` is how many of this species are living in the world.
## Rendered only when that count is >= 1.
const HERE_TEMPLATE: String = "[COPY] here · %d"

## [COPY] — content-writer's. `%s` is a source's display name, `%d` its target tile count.
const CHIP_TEMPLATE: String = "%s ×%d"

## PROPOSED — human owns this. Pixels, pre-scale. Small enough to read as inline punctuation
## in a sentence rather than as a second hotbar.
const CHIP_ICON_SIZE: float = 28.0

@onready var _species_hosted_value: Label = %SpeciesHostedValue
@onready var _resident_list: VBoxContainer = %ResidentList
@onready var _empty_label: Label = %EmptyLabel

## `{species_id: String -> Array[String]}` — the palette option ids rendered on that species'
## card, in rendered order. Populated by `_make_species_card()` alongside the chips themselves
## so `recipe_button_ids_for()` never has to re-derive the recipe or walk the scene tree.
var _recipe_ids: Dictionary = {}


## Rebuilds the list in place, without changing open/closed state — called on every arrival
## and departure while the screen happens to be open, so a resident moving in or out is
## reflected live rather than on next open (gdd.md's own "grows for as long as play
## continues" reads as a live document, not a snapshot).
func refresh_from(world: WorldRoot) -> void:
	_clear_list()
	if world == null or world.roster == null or world.roster.species().is_empty():
		_set_empty_state(true)
		return

	_species_hosted_value.text = str(world.species_hosted_count())

	_set_empty_state(false)
	_recipe_ids.clear()
	for species: AnimalDefinition in world.roster.species():
		_resident_list.add_child(_make_species_card(species, world))


func species_hosted_text() -> String:
	return "" if _species_hosted_value == null else _species_hosted_value.text


## Each card's heading name, top to bottom, in roster order — what a test reads instead of
## the screen. Every roster species now renders its real `display_name` here, discovered or
## not; there is no longer a silhouette state to distinguish.
func species_row_texts() -> Array[String]:
	var out: Array[String] = []
	if _resident_list == null:
		return out
	for card: Node in _resident_list.get_children():
		var header: Node = card.get_child(0)
		if header != null and header.get_child_count() > 0:
			var name_label: Node = header.get_child(0)
			if name_label is Label:
				out.append((name_label as Label).text)
	return out


## Palette option ids of the chips on `species_id`'s card, in rendered order. Test-driving
## entry point, and Task 7's coach reads it to learn which button to point at.
func recipe_button_ids_for(species_id: String) -> Array[String]:
	var out: Array[String] = []
	var ids: Variant = _recipe_ids.get(species_id, null)
	if ids != null:
		out.assign(ids as Array)
	return out


func is_empty_state_visible() -> bool:
	return _empty_label != null and _empty_label.visible


func _make_species_card(species: AnimalDefinition, world: WorldRoot) -> VBoxContainer:
	var card := VBoxContainer.new()

	var header := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = species.display_name
	name_label.add_theme_font_size_override("font_size", UiPalette.FONT_CARD_BODY)
	name_label.add_theme_color_override("font_color", UiPalette.BARK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	# THE COUNT IS OMITTED AT ZERO, deliberately (human ruling 2026-08-31). Fifteen stacked
	# "· 0"s render as an empty checklist — the exact texture Pillar 1 avoids. Absence is the
	# zero.
	var population: int = world.population_of(species.id)
	if population >= 1:
		var count_label := Label.new()
		count_label.text = HERE_TEMPLATE % population
		count_label.add_theme_font_size_override("font_size", UiPalette.FONT_HUD_SECONDARY)
		count_label.add_theme_color_override("font_color", UiPalette.FIELD_GUIDE_SILHOUETTE_INK)
		header.add_child(count_label)
	card.add_child(header)

	var description := Label.new()
	description.text = HabitatRecipe.describe(species, world)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", UiPalette.FONT_NOTICE_LINE)
	description.add_theme_color_override("font_color", UiPalette.BARK)
	card.add_child(description)

	var recipe: Dictionary = HabitatRecipe.recipe_for(species, world)
	var ids: Array[String] = []
	if recipe["satisfiable"] as bool:
		var chips := HFlowContainer.new()
		for entry: Dictionary in (recipe["entries"] as Array):
			chips.add_child(_make_chip(entry))
			ids.append(entry["id"] as String)
		card.add_child(chips)
	_recipe_ids[species.id] = ids

	# The single most useful line on this screen: the only place the game ever explains why a
	# correctly-built habitat stayed empty.
	var avoided: Array[String] = HabitatRecipe.avoids_for(species, world)
	if not avoided.is_empty():
		var avoids_label := Label.new()
		avoids_label.text = HabitatRecipe.AVOIDS_TEMPLATE % ", ".join(avoided)
		avoids_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		avoids_label.add_theme_font_size_override("font_size", UiPalette.FONT_NOTICE_LINE)
		avoids_label.add_theme_color_override("font_color", UiPalette.FIELD_GUIDE_SILHOUETTE_INK)
		card.add_child(avoids_label)

	return card


## One requirement: the real palette glyph, then "Forest ×5".
##
## CHIPS RATHER THAN ICONS INLINE IN A SENTENCE. `TileIcon` draws vectorially in `_draw()`
## with no backing texture, so it cannot go inside a `RichTextLabel` without inventing an art
## asset; an alternating Label/TileIcon HBox wraps badly. An `HFlowContainer` of chips wraps
## correctly, needs no art — and looks like the hotbar the player is being pointed at.
func _make_chip(entry: Dictionary) -> HBoxContainer:
	var chip := HBoxContainer.new()

	var icon_kind: Variant = entry["icon_kind"]
	if icon_kind != null:
		var icon := TileIcon.new()
		icon.kind = icon_kind as TileIcon.Kind
		icon.custom_minimum_size = Vector2(
			UiPalette.scaled(CHIP_ICON_SIZE), UiPalette.scaled(CHIP_ICON_SIZE)
		)
		chip.add_child(icon)

	var label := Label.new()
	label.text = CHIP_TEMPLATE % [entry["display_name"], entry["count"]]
	label.add_theme_font_size_override("font_size", UiPalette.FONT_NOTICE_LINE)
	label.add_theme_color_override("font_color", UiPalette.BARK)
	chip.add_child(label)

	return chip


func _clear_list() -> void:
	if _resident_list == null:
		return
	for child: Node in _resident_list.get_children():
		# `remove_child()` first, not just `queue_free()` alone: `queue_free()` defers
		# actual removal to end-of-frame, so a second `refresh_from()` in the same frame
		# (this screen's own test suite calls it several times per frame) would still see
		# the stale rows via `get_children()` and double them up.
		_resident_list.remove_child(child)
		child.queue_free()


func _set_empty_state(empty: bool) -> void:
	if _empty_label != null:
		_empty_label.text = EMPTY_STATE_TEXT
		_empty_label.visible = empty
	if _resident_list != null:
		_resident_list.visible = not empty
