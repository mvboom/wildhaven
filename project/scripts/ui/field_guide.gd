class_name FieldGuide
extends Control
## Tier 1 row 11's second half — a discovery tracker screen. As of the Minecraft-style
## inventory window, reachable only as a tab of `MenuWindow` (press Tab to open the window,
## then its Field Guide tab) — there is no standalone top-right icon any more; spec.md ->
## Screen Layouts predates this change.
##
## SHOWS THE WHOLE ROSTER, NOT JUST WHAT'S BEEN HOSTED (revised, playability chrome
## overhaul — docs/superpowers/specs/2026-08-09-playability-chrome-overhaul-design.md,
## section 3). A row exists here for every `AnimalDefinition` in `world.roster.species()`,
## whether or not it has ever been hosted: a hosted species renders its real name, an
## undiscovered one renders `UNDISCOVERED_GLYPH` ("???") instead.
##
## THIS IS A DELIBERATE, LOGGED EXCEPTION to gdd.md -> Objectives & Progression's own rule —
## its exact words: "No completion percentage, total-species count, or finish-the-guide
## reward." Human ruling, this session, logged as `decisions.md`'s D-40 (amending D-34 #5 and
## #6): showing a species EXISTS is judged worth the cost of implicitly revealing how many
## species there are in total, specifically so a player is never encouraged to build a
## "perfect" habitat for a species that can never appear. THE EXCEPTION IS SCOPED TO EXISTENCE
## ONLY — no habitat tag, terrain preference, or hint of any kind is shown here or anywhere
## else by this change; `_check_field_guide_never_shows_a_habitat_preference()` in this file's
## test suite is the line that must never move.
##
## THE "hinted-at" COLUMN gdd.md -> Objectives & Progression still describes is unrelated
## to this exception and still does not exist: it needs row 12's per-species News Reports
## (`AnimalDefinition.news_reports`), which are content, not existence. When row 12 lands,
## that column is additive here; nothing on this file needs to change shape to receive it.
##
## THE INDICATOR TEST (Pillar 1), what still holds after the exception above:
##   * the list is FLAT and in roster order — never ranked, never checked off, discovered
##     rows and silhouette rows are not sorted apart from each other;
##   * `Species Hosted` renders a bare integer with no denominator anywhere — still true;
##   * there is no percentage, no progress bar, and no styling difference between a row
##     that has been discovered and one that hasn't beyond the name-vs-silhouette swap
##     the exception above exists for.
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

## Rendered in place of a species' name until it has been hosted at least once — permanent
## once true, exactly like `WorldRoot.species_hosted_ids()` itself. Not a stub: this is the
## deliberate, shipped display for "exists, not yet discovered" (see the header's
## exception note), not placeholder copy awaiting sign-off.
const UNDISCOVERED_GLYPH: String = "???"

@onready var _species_hosted_value: Label = %SpeciesHostedValue
@onready var _resident_list: VBoxContainer = %ResidentList
@onready var _empty_label: Label = %EmptyLabel


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
	var hosted_ids: Array[String] = world.species_hosted_ids()
	for species: AnimalDefinition in world.roster.species():
		_resident_list.add_child(_make_row(species.display_name, hosted_ids.has(species.id)))


func species_hosted_text() -> String:
	return "" if _species_hosted_value == null else _species_hosted_value.text


## The flat list's rendered text, top to bottom, in roster order — what a test reads
## instead of the screen. A discovered species renders its display name; an undiscovered
## one renders `UNDISCOVERED_GLYPH`.
func species_row_texts() -> Array[String]:
	var out: Array[String] = []
	if _resident_list == null:
		return out
	for row: Node in _resident_list.get_children():
		if row is Label:
			out.append((row as Label).text)
	return out


func is_empty_state_visible() -> bool:
	return _empty_label != null and _empty_label.visible


func _make_row(display_name: String, discovered: bool) -> Label:
	var row := Label.new()
	row.text = display_name if discovered else UNDISCOVERED_GLYPH
	row.add_theme_font_size_override("font_size", UiPalette.FONT_CARD_BODY)
	row.add_theme_color_override(
		"font_color", UiPalette.BARK if discovered else UiPalette.FIELD_GUIDE_SILHOUETTE_INK
	)
	return row


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
