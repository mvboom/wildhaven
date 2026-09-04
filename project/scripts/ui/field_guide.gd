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
## given. Every card is text and the real palette glyphs on its recipe chips, nothing more.
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

## APPROVED 2026-09-01 by the human, replacing the `[COPY] here · %d` stub. `%d` is how many
## of this species are living in the world. Rendered only when that count is >= 1.
const HERE_TEMPLATE: String = "Resident · %d"

## Final review finding #3 ruling: NOT `[COPY]`-marked, and deliberately so, despite being
## player-facing. `"Forest ×5"` is a DATA FORMAT — a source's name and a target tile count —
## not prose awaiting a content-writer's approval. There is no alternate wording for a
## reviewer to sign off on; marking it as a stub would be marking a number format as
## unfinished copy, which it structurally cannot become.
## `%s` is a source's display name, `%d` its target tile count.
const CHIP_TEMPLATE: String = "%s ×%d"

## PROPOSED — human owns this. This screen's own type scale, deliberately NOT UiPalette's
## shared FONT_CARD_BODY/FONT_NOTICE_LINE/FONT_HUD_SECONDARY: those are also read by FactCard,
## NotificationFeed and DisplacementNotice, so shrinking them here would resize screens this
## change never touched. Human direction 2026-09-01: the list reads smaller; the window title
## and the Species Hosted header keep their existing size.
const FONT_SPECIES_NAME: int = 22
const FONT_SPECIES_BODY: int = 18
const FONT_SPECIES_COUNT: int = 16

## PROPOSED — human owns this. Pixels, pre-scale. Small enough to read as inline punctuation
## in a sentence rather than as a second hotbar.
const CHIP_ICON_SIZE: float = 22.0

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
	# Final review minor: both cleared/set UNCONDITIONALLY, above the empty-roster guard below.
	# The old order returned early on an empty/null roster before either ran, so a screen that
	# had shown real data and then lost its roster (or the very first refresh against a
	# config problem) kept showing the LAST non-empty count and the last recipe's chip ids —
	# stale in both directions, for as long as the guard kept tripping.
	_recipe_ids.clear()
	_species_hosted_value.text = str(0 if world == null else world.species_hosted_count())
	if world == null or world.roster == null or world.roster.species().is_empty():
		_set_empty_state(true)
		return

	_set_empty_state(false)
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


## Palette option ids of the chips on `species_id`'s card, in rendered order. TEST ACCESSOR
## ONLY: populated by `_make_species_card()` alongside the chips it describes, purely so this
## file's own suite can assert against the derived recipe without re-deriving it or walking
## the scene tree. No other caller — Task 7's coach targets buttons through its own
## `current_target_id()` plus `GameHud.palette_button_for()` and never reaches this method.
func recipe_button_ids_for(species_id: String) -> Array[String]:
	var out: Array[String] = []
	var ids: Variant = _recipe_ids.get(species_id, null)
	if ids != null:
		out.assign(ids as Array)
	return out


## Final review finding #5: `recipe_button_ids_for()` above mirrors `recipe_for()`'s entries by
## construction — `_recipe_ids` is written from the SAME loop that builds the chips, so a test
## comparing one against the other proves nothing about whether the chips actually rendered
## (delete the `chips.add_child()` call below and that comparison still passes). This accessor
## instead reads the chip `Label` TEXT back OUT OF THE LIVE SCENE TREE — the same discipline
## `species_row_texts()` already uses for the header — so a rendering regression (a chip that
## silently stops being added, or renders the wrong text) actually turns this red. TEST ACCESSOR
## ONLY, same as `recipe_button_ids_for()` above.
func recipe_chip_texts_for(species_id: String) -> Array[String]:
	var out: Array[String] = []
	if _resident_list == null:
		return out
	var card: Node = _resident_list.get_node_or_null(species_id)
	if card == null:
		return out
	for section: Node in card.get_children():
		if not (section is HFlowContainer):
			continue
		for chip: Node in section.get_children():
			for piece: Node in chip.get_children():
				if piece is Label:
					out.append((piece as Label).text)
	return out


func is_empty_state_visible() -> bool:
	return _empty_label != null and _empty_label.visible


func _make_species_card(species: AnimalDefinition, world: WorldRoot) -> VBoxContainer:
	var card := VBoxContainer.new()
	# Every node in a card ignores the mouse so a wheel tick lands on `ListScroll` instead of
	# being swallowed by whichever Label happens to be under the cursor. Without this the
	# event falls through to `CameraRig._unhandled_input()` and zooms the world while the
	# player is trying to scroll the list (human report, 2026-09-01).
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Named after the species id (final review finding #5) so `recipe_chip_texts_for()` below
	# can find THIS card in the live scene tree by id, rather than by position — every authored
	# id so far is a bare snake_case word, which Godot accepts as a node name outright.
	card.name = species.id

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = species.display_name
	name_label.add_theme_font_size_override("font_size", FONT_SPECIES_NAME)
	name_label.add_theme_color_override("font_color", UiPalette.BARK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	# THE COUNT IS OMITTED AT ZERO, deliberately (human ruling 2026-08-31). Fifteen stacked
	# "· 0"s render as an empty checklist — the exact texture Pillar 1 avoids. Absence is the
	# zero.
	var population: int = world.population_of(species.id)
	if population >= 1:
		var count_label := Label.new()
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_label.text = HERE_TEMPLATE % population
		count_label.add_theme_font_size_override("font_size", FONT_SPECIES_COUNT)
		count_label.add_theme_color_override("font_color", UiPalette.FIELD_GUIDE_SILHOUETTE_INK)
		header.add_child(count_label)
	card.add_child(header)

	var description := Label.new()
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.text = HabitatRecipe.describe(species, world)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", FONT_SPECIES_BODY)
	description.add_theme_color_override("font_color", UiPalette.BARK)
	card.add_child(description)

	var recipe: Dictionary = HabitatRecipe.recipe_for(species, world)
	var ids: Array[String] = []
	if recipe["satisfiable"] as bool:
		var chips := HFlowContainer.new()
		chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		avoids_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		avoids_label.text = HabitatRecipe.AVOIDS_TEMPLATE % ", ".join(avoided)
		avoids_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		avoids_label.add_theme_font_size_override("font_size", FONT_SPECIES_BODY)
		avoids_label.add_theme_color_override("font_color", UiPalette.FIELD_GUIDE_SILHOUETTE_INK)
		card.add_child(avoids_label)

	# TIER LINES — habitat-tiers Task 10, the payoff of the whole branch: what a site
	# satisfies now, and what the NEXT tier on top of it needs (a stable turning a pair of
	# horses into a herd). Every species presents at least one tier — `effective_tiers()`
	# synthesises one from the legacy flat fields when `tiers` is empty — so this renders
	# for the whole roster, not just the handful re-authored onto real tiers so far.
	# ADDITIVE, not a replacement of `description`/`chips` above: those two are still
	# pinned exactly by `test_field_guide.gd`'s `_check_every_species_shows_its_recipe()`
	# and by `test_habitat_recipe.gd`'s own `describe()` checks, and this file's job is to
	# extend the card, not to demolish tested rendering to make room.
	# DELIBERATELY a `VBoxContainer`, NOT an `HFlowContainer`: `recipe_chip_texts_for()`
	# (this file's own TEST ACCESSOR) reads Label text only out of HFlowContainer children
	# (see that method's own header) — a VBoxContainer here stays invisible to it, so this
	# addition cannot perturb that pinned exact-match check against `recipe_for()`.
	var tier_lines: Array[String] = HabitatRecipe.describe_tiers(species, world)
	if not tier_lines.is_empty():
		var tier_box := VBoxContainer.new()
		tier_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for line: String in tier_lines:
			var tier_label := Label.new()
			tier_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tier_label.text = line
			tier_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tier_label.add_theme_font_size_override("font_size", FONT_SPECIES_BODY)
			tier_label.add_theme_color_override("font_color", UiPalette.BARK)
			tier_box.add_child(tier_label)
		card.add_child(tier_box)

	# Human direction 2026-09-01: one rule per species, so the cards read as distinct
	# entries rather than one run-on column. Deliberately the LAST child of the card rather
	# than a sibling in `_resident_list`: a sibling would make the list's children alternate
	# card/rule, and both `species_row_texts()` and `recipe_chip_texts_for()` index
	# `_resident_list`'s children as one-node-per-species.
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(rule)

	return card


## One requirement: the real palette glyph, then "Forest ×5".
##
## CHIPS RATHER THAN ICONS INLINE IN A SENTENCE. `TileIcon` draws vectorially in `_draw()`
## with no backing texture, so it cannot go inside a `RichTextLabel` without inventing an art
## asset; an alternating Label/TileIcon HBox wraps badly. An `HFlowContainer` of chips wraps
## correctly, needs no art — and looks like the hotbar the player is being pointed at.
func _make_chip(entry: Dictionary) -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon_kind: Variant = entry["icon_kind"]
	if icon_kind != null:
		var icon := TileIcon.new()
		icon.kind = icon_kind as TileIcon.Kind
		icon.custom_minimum_size = Vector2(
			UiPalette.scaled(CHIP_ICON_SIZE), UiPalette.scaled(CHIP_ICON_SIZE)
		)
		chip.add_child(icon)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = CHIP_TEMPLATE % [entry["display_name"], entry["count"]]
	label.add_theme_font_size_override("font_size", FONT_SPECIES_BODY)
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
