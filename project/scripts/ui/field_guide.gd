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
## given. Every card is text.
##
## NO RECIPE CHIPS AS OF TASK 10 FIX ROUND 1 (removed, not repointed — see
## `HabitatRecipe.describe_tiers()`'s own header for the full reasoning). The palette-glyph
## chips this screen used to show came from `HabitatRecipe.recipe_for()`, which reads the
## flat, legacy `habitat_needs`/`tiles_per_individual` fields — the SAME fields that made
## Horse/Cow/Bull/Alpaca render identically before the habitat-tiers branch, and Cow/Bull
## (`["cultivated","open_grass"]`) and Horse/Alpaca (`["open_grass","cultivated"]`) still do,
## directly above the tier block that exists specifically to fix that. Repointing the chips
## to per-tier data instead of removing them was considered and set aside: a GATE_ONLY need
## (a stable, present-or-not) has no meaningful tile COUNT the way a scaling need does, and
## `CHIP_TEMPLATE`'s "%s ×%d" shape assumes every requirement has one — inventing a second
## chip shape for gate needs under this fix is a UI decision, not a code fix, so this task
## dropped the chips rather than guess at one. The tier block (`describe_tiers()`) is now the
## sole on-screen recipe; it carries every requirement, correctly, in plain text — it just
## has no icon glyphs. Flagged as a proposal, not a decision, in the fix report.
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

## PROPOSED — human owns this. This screen's own type scale, deliberately NOT UiPalette's
## shared FONT_CARD_BODY/FONT_NOTICE_LINE/FONT_HUD_SECONDARY: those are also read by FactCard,
## NotificationFeed and DisplacementNotice, so shrinking them here would resize screens this
## change never touched. Human direction 2026-09-01: the list reads smaller; the window title
## and the Species Hosted header keep their existing size.
const FONT_SPECIES_NAME: int = 22
const FONT_SPECIES_BODY: int = 18
const FONT_SPECIES_COUNT: int = 16

## The name given to each card's tier-lines container, so `tier_line_texts_for()` can find it
## in the live scene tree by name rather than by position — same discipline `card.name =
## species.id` already uses one level up.
const TIER_BOX_NAME: String = "Tiers"

@onready var _species_hosted_value: Label = %SpeciesHostedValue
@onready var _resident_list: VBoxContainer = %ResidentList
@onready var _empty_label: Label = %EmptyLabel


## Rebuilds the list in place, without changing open/closed state — called on every arrival
## and departure while the screen happens to be open, so a resident moving in or out is
## reflected live rather than on next open (gdd.md's own "grows for as long as play
## continues" reads as a live document, not a snapshot).
func refresh_from(world: WorldRoot) -> void:
	_clear_list()
	# Final review minor: cleared/set UNCONDITIONALLY, above the empty-roster guard below. The
	# old order returned early on an empty/null roster before either ran, so a screen that had
	# shown real data and then lost its roster (or the very first refresh against a config
	# problem) kept showing the LAST non-empty count — stale, for as long as the guard kept
	# tripping.
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


## The tier lines rendered on `species_id`'s card, in rendered order. TEST ACCESSOR ONLY
## (Task 10 fix round 1, replacing the retired `recipe_button_ids_for()`/
## `recipe_chip_texts_for()` pair — see this file's own header for why the chips they read
## are gone). Reads the `Label` TEXT back OUT OF THE LIVE SCENE TREE, the same discipline
## `species_row_texts()` already uses for the header: this proves the card actually rendered
## `HabitatRecipe.describe_tiers()`'s output, not merely that the two would agree in theory.
func tier_line_texts_for(species_id: String) -> Array[String]:
	var out: Array[String] = []
	if _resident_list == null:
		return out
	var card: Node = _resident_list.get_node_or_null(species_id)
	if card == null:
		return out
	var tier_box: Node = card.get_node_or_null(TIER_BOX_NAME)
	if tier_box == null:
		return out
	for line: Node in tier_box.get_children():
		if line is Label:
			out.append((line as Label).text)
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
	# Named after the species id (final review finding #5) so `tier_line_texts_for()` below
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

	# NOTE: no flat `describe()` sentence and no `recipe_for()` chip row here any more (Task 10
	# fix round 1). Both read `species.habitat_needs`, the pre-tier flat field that still makes
	# Cow/Bull and Horse/Alpaca indistinguishable — see this file's own header for the full
	# reasoning. The tier block below (`describe_tiers()`) is the card's sole recipe display now.

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
	# As of fix round 1, this IS the card's recipe display (the flat `description`/`chips`
	# block that used to sit above it is gone — see this file's own header). Named
	# `TIER_BOX_NAME` so `tier_line_texts_for()` can find it in the live scene tree by name.
	var tier_lines: Array[String] = HabitatRecipe.describe_tiers(species, world)
	if not tier_lines.is_empty():
		var tier_box := VBoxContainer.new()
		tier_box.name = TIER_BOX_NAME
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
	# card/rule, and both `species_row_texts()` and `tier_line_texts_for()` index
	# `_resident_list`'s children as one-node-per-species.
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(rule)

	return card


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
