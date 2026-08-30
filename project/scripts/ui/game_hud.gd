class_name GameHud
extends Control
## The persistent HUD (terraform bar rework) — spec.md -> Screen Layouts, "corner-anchored so
## the center stays clear for the world":
##
##   top-left       Resources plus the three species/population counters (Tier 1 row 11)
##   bottom-center  the palette row, ALWAYS visible — in Inspect, Terraform, and Build alike,
##                  never only while a mode is "active"
##   bottom-right   the two Rotate buttons, locked next to `LeaveOverlay`'s Exit button
##
## THE PALETTE ROW IS FIXED, NOT ASSIGNABLE. Earlier builds had a 5-slot Minecraft-style
## hotbar the player filled by dragging entries out of a separate browse window
## (`MenuWindow`'s old Terrain/Buildings tabs). Human decision (terraform-bar rework, 2026):
## with the v1 catalog at exactly 6 terrain entries + 1 placeable, there is no "browsing a
## larger set" to do — the whole catalog fits in one row, so it is simply always all there,
## and MenuWindow's Terrain/Buildings tabs and their drag-and-drop retire with it. Pressing a
## button sets Mode implicitly (terrain -> TERRAFORM, placeable -> BUILD), exactly as the old
## slot activation and the category buttons before that both did — there is still no fourth
## control and no second gesture.
##
## THE ROW READS LEFT TO RIGHT AS: Info (key 0, the Inspect quick-toggle) — every terrain and
## placeable the catalog reports (keys 1-9) — Erase (no key). Info and Erase are NOT catalog
## content; they are the two fixed tools that flank it, same role the old Remove slot always
## had, just with Info now given the same treatment (icon, number, name label) rather than
## living in its own separate corner.
##
## THE ROW IS STILL DATA-DRIVEN. `build_palettes()` reads `WorldRoot.terrain_options()` and
## `placeable_options()` and builds one button per catalog entry, in catalog order — nothing
## here hardcodes a terrain or placeable count. Adding a terrain is still a `.tres`; it just
## also needs an `_ICON_KIND_BY_ID` entry below or it renders with no glyph (name label and
## number still show).
##
## PLACEABLES BUTTON-GROUP BY `hotbar_category` (style-picker sub-project B2, Task 6). B1
## shipped 8 independent Farm Building `PlaceableDefinition`s (barn, small_barn, open_barn,
## chicken_coop, silo, windmill, water_tower, well), each with `hotbar_category =
## "farm_building"` — deliberately accepted at the time as one button per entry (9 placeable
## buttons: House + 8 farm buildings), to be closed by this task. It is closed here: every
## placeable is grouped by `hotbar_category` (falling back to its own id when that field is
## "", which is how House renders its own single-member group unchanged), and one button is
## built per GROUP, not per `PlaceableDefinition` — so the BUILD+TERRAFORM row totals 6 terrain
## + House + Farm Building = 8 buttons, not 15. A real group's button (`_placeable_group_row()`)
## shows and places whichever member `WorldRoot.get_style_default(group_key)` currently
## returns; `activate_palette_entry()` re-resolves that at TAP time (not at button-build time)
## so the group key, never a stale member id, is what a button's `pressed` binding carries.
## `refresh_palette_button()` is how Task 7's long-press popup repaints one grouped button
## after the player changes which member is the default, without rebuilding the whole row.
##
## THE COUNTERS NEVER FLASH. spec.md: "Resource counters are read-only indicators (Pillar 1).
## Never flash, never demand attention when low." `set_wood()` and row 11's three siblings
## below (`set_species_hosted()`, `set_currently_resident()`, `set_village_population()`) each
## assign a string and do nothing else — no tween, no colour change, no low-balance state,
## no threshold anywhere. That absence is the feature, and it is the same feature four times:
## gdd.md -> Economy names all four as "information, never a score", so the four setters are
## deliberately identical in shape.
##
## THIS SCENE HOLDS NO LIST. `GameUI` reads `WorldRoot.species_hosted_count()`,
## `total_residents() - population_of("human")` and `population_of("human")` and hands this
## file three plain integers — exactly how `set_wood()` already receives `wood_changed`'s
## payload. `GameHud` does not know a species id exists.

## The three modes of gdd.md -> Player Interface & Controls. Inspect is the default ("just
## enjoy the world"), which is also the "or none" in "pick a mode (or none), then tap".
enum Mode { INSPECT, TERRAFORM, BUILD }

signal mode_changed(mode: Mode)

## → D-44. A single discrete action per press — `Button.pressed`, not `button_down`/`button_up`.
signal rotate_cw_pressed()
signal rotate_ccw_pressed()

## DECIDED 2026-08-02 (playtest gate). How long the Inspect tile readout stays up, in seconds.
const READOUT_SECONDS: float = 4.0

## --- REMOVAL, AND WHY IT IS NOT A FOURTH MODE ------------------------------------------------
##
## `WorldRoot.remove_at()` exists and nothing reached it. gdd.md's input table lists **one**
## left-click for "Inspect / Terraform / Build / Harvest" and gives removal a *policy* — "uniform
## across Terraform reverts and Build removals" — but never a control.
##
## **It ships as a palette entry, not a mode.** The gesture the player learns is unchanged and
## unextended: gdd.md's own beat 3 is "Open Terraform, **pick a terrain**, tap a tile", so
## picking from the palette is already inside "pick a mode, then tap". A remove *tool* is one
## more thing to pick in a palette the player is already picking from; a remove *mode* would be a
## fourth button on the mode switch, which is the one control `GameHud` says at the top of this
## file must never grow. `GameHud.Mode` still has exactly three members and `TapRouter` still
## resolves exactly one gesture.
##
## **The entry appears in BOTH palettes and calls the same `remove_at()`** — which is the design
## document's word *uniform* made structural rather than promised: there is not a "revert" in
## Terraform and a "demolish" in Build, there is one tool that undoes whatever the player last
## did to the tile they tap, reachable from wherever they happen to be standing.
##
## **It is not a data entry and is not in `palette_option_ids()`.** That list is the data-driven
## content of a palette — the assertion that nothing here hardcodes a terrain list — and a tool
## is not content. `is_remove_selected()` reports this one instead.
##
## KNOWN LIMIT, NOT A BUG HERE: the priority rule ("an animal standing on a tappable tile always
## wins the tap") applies in every mode, so a tap on a resident standing on their own House opens
## their fact card instead of removing it. Residents roam, so the House is removable whenever
## nobody is on it, and the field around it always is. Reported rather than special-cased —
## carving an exception into the priority rule is a design escalation, not a UI decision.
const REMOVE_OPTION_ID: String = "__remove__"

## The name for the palette tool that undoes an edit — the button's icon (an eraser glyph),
## its name label, and its tooltip all read this. Human-decided (playtest feedback): "Take
## Away" read as unclear next to an eraser icon, so it is "Erase" — no longer a `[COPY]` stub.
const REMOVE_ENTRY_LABEL: String = "Erase"

## Shown where a tile has no habitat tags at all. A dash, not a sentence — the tile readout
## deliberately renders only data (terrain name, tags) so that no player-facing copy has to
## be invented here. Copy is the content-writer's.
const NO_TAGS_GLYPH: String = "—"

# --- Live neighborhood preview copy (row 6). CONTENT-WRITER'S, NOT THIS FILE'S. -----------
#
# One string per band of `NeighborhoodPreview`. They are gathered here, beside the other
# rendered strings, so replacing them is one diff and no logic moves.
#
# THE RULE THESE THREE HAVE TO KEEP (Pillar 1, and row 12's invariant): each is a statement
# **about a place**, never about the player. None may name a missing tag, suggest a next tap,
# or imply the spot is unfinished — "add more cover here" would turn a preview into a task
# list, which is the exact failure Open Question #27 flags for the numeric form as well.
# **Never numeric**: `NeighborhoodPreview` returns a band and no counts, so there is nothing to
# interpolate a fraction from even by accident.

## PROVISIONAL — gdd.md's own exemplar, verbatim (The First 60 Seconds, beat 4). Kept as
## written because it is the one preview string the design document actually supplies.
##
## **Caveat the content-writer needs:** in gdd.md this line lands at ~0:20, *before* anything
## qualifies — it is the near-miss voice, "becoming". Here it fires when the spot **already**
## suits somebody, because the near-miss summary does not exist yet (row 12). The words still
## read true, but the beat has shifted later than the document imagined it.
const PREVIEW_TEXT_WELCOMING: String = "this spot is getting cozy for someone"

## CONTENT-WRITER'S, approved 2026-07-28 — `docs/content/displacement-copy.md` -> Appendix,
## `PREVIEW_TEXT_WILD`, the ranked recommendation, verbatim. Deliberately plain: warmer drafts
## failed in both directions and both failures were prompts — "still wild"/"wild for now" reads
## as *not yet* (a deficiency and an instruction), "wild, just as it is" reads as *leave it
## alone* (the opposite instruction). A band that fires on "nobody could live here" says what is
## true of the place and stops.
##
## **AND IT KEEPS THE TAG-WORD RULE.** None of the ten habitat-tag words — `open`, `grass`,
## `quiet`, `cover`, `rocks`, `flowers`, `house`, `water`, `sand`, `forest` — may appear in a
## preview line, even innocently, or the preview starts teaching a vocabulary the player is never
## meant to manage. That is why the earlier stub's "wild, open land" could not ship: `open`.
const PREVIEW_TEXT_WILD: String = "this land is wild"

## CONTENT-WRITER'S, approved 2026-07-28 — same source, `PREVIEW_TEXT_HOME`, verbatim. Chosen to
## match the middle band's cadence exactly ("this spot is getting cozy for someone" / "this spot
## is somebody's home"), so the two read as one voice describing one place at two moments. Fires
## only on the home tile itself, not across the neighbourhood (see `NeighborhoodPreview`).
const PREVIEW_TEXT_HOME: String = "this spot is somebody's home"


## Catalog id -> `TileIcon.Kind`. The one place a new terrain/building's glyph is wired up —
## an id missing here still gets a real button (`display_name` as its tooltip), just no
## picture, so a content addition degrades gracefully instead of failing to load.
const _ICON_KIND_BY_ID: Dictionary = {
	"wild_grass": TileIcon.Kind.WILD_GRASS,
	"grass": TileIcon.Kind.GRASS,
	"water": TileIcon.Kind.WATER,
	"forest": TileIcon.Kind.FOREST,
	"rock": TileIcon.Kind.ROCK,
	"cultivated_field": TileIcon.Kind.FARM,
	"house": TileIcon.Kind.HOUSE,
}


## Set by `build_palettes()`. Needed at button-build time (and by `refresh_palette_button()`,
## called later by Task 7's popup) to resolve a grouped placeable button — e.g. Farm
## Building — to whichever real member id is currently the player's chosen default.
var _world: WorldRoot = null

## --- LONG-PRESS STYLE PICKER (style-picker sub-project B2, Task 7) -------------------------
##
## The 4 categories a long-press opens a style picker for. Forest and Wild Grass are TERRAIN
## ids used as-is (`_add_palette_button("terrain", row)` gives a terrain button `id == row["id"]
## == the terrain's own id — no group indirection); House and Farm Building are PLACEABLE
## GROUP keys (`_placeable_group_row()`'s own `id`, see that function's header). Both flavors
## flow through the SAME `_add_palette_button()` call, which is why one gating check here
## (against this list) — not a second wiring path split by `kind` — covers all 4: the other 5
## terrain ids (grass, water, rock, cultivated_field... whichever ship) and Erase are excluded
## simply by not appearing in this list, the same "absence is the answer" shape
## `_ICON_KIND_BY_ID` already uses for an unmapped id.
const _PICKER_CATEGORIES: Array[String] = ["forest", "wild_grass", "house", "farm_building"]

## PLACEHOLDER / TUNABLE — human's call, matching every other timing constant in this project
## (e.g. `READOUT_SECONDS` above). How long a picker-enabled palette button must be held
## before it counts as a long-press (opens the style picker) instead of a normal tap.
const LONG_PRESS_SECONDS: float = 0.45

const _STYLE_PICKER_SCENE: PackedScene = preload("res://scenes/ui/StylePickerPopup.tscn")

## `id` (one of `_PICKER_CATEGORIES`) -> its own one-shot long-press `Timer`, a child of this
## HUD. Rebuilt by `_build_palette_row()` alongside the buttons themselves so a fresh world's
## timers never point at a `queue_free()`'d button from a previous one.
var _long_press_timers: Dictionary = {}

## `id` -> `true` while a `pressed` this HUD must ignore is pending — set the instant a
## long-press is recognised (`_on_long_press_timeout()`). Consumed (erased) in EITHER of two
## places, because `Button` does not release the same way every time: `_on_palette_button_pressed()`
## erases it when `pressed` actually fires (an in-place release — `pressed` fires BEFORE
## `button_up` there, measured against the real engine, not assumed), and `_on_picker_button_up()`
## ALSO erases it unconditionally on every release, because a release with the pointer dragged
## off the button emits `button_up` with NO `pressed` at all — the popup opens directly above
## the button, so a drag-off release on the way to it is an entirely ordinary motion, not an
## edge case. Without the second erase, that path stranded this flag `true` forever and ate the
## next unrelated tap on the same button (fix round, 2026-08-27 review). Nothing here fights the
## engine's own click detection — this only decides whether a click's DOWNSTREAM action
## (`activate_palette_entry()`) also runs.
var _swallow_next_press: Dictionary = {}

## The one popup instance, reused across every long-press (never re-instantiated) — a child
## of this HUD, added in `_ready()`, hidden until a long-press opens it.
var _style_picker: StylePickerPopup = null

var _mode: Mode = Mode.INSPECT
## Whichever of TERRAFORM/BUILD was picked most recently — what the Inspect quick-toggle
## returns to. Defaults to TERRAFORM so a fresh HUD has a sane category loaded before the
## player has picked one.
var _last_content_mode: Mode = Mode.TERRAFORM
var _selected_terrain_id: String = ""
var _selected_placeable_id: String = ""
var _remove_selected: bool = false

## Fires whenever the active brush, or the Remove-selected state, changes — the one thing the
## palette row needs to know to repaint itself. Data and view stay decoupled this way: this
## file owns the model and asks nothing about pixels.
signal palette_changed()

# id -> { display_name: String, cost: int } — catalog data only, no widgets.
var _terrain_entries: Dictionary = {}
var _placeable_entries: Dictionary = {}

## Every button the palette row shows, terrain then placeables, in catalog order —
## `{"kind": "terrain"|"placeable", "id": String}`. Index-aligned with `_palette_buttons`;
## also what the 1-9 number keys index into.
var _palette_order: Array[Dictionary] = []
var _palette_buttons: Array[Button] = []
var _remove_button: Button = null

var _readout_timer: Timer = null

@onready var _wood_value: Label = %WoodValue
@onready var _species_hosted_value: Label = %SpeciesHostedValue
@onready var _currently_resident_value: Label = %CurrentlyResidentValue
@onready var _village_population_value: Label = %VillagePopulationValue
@onready var _inspect_button: Button = %InspectButton
@onready var _rotate_ccw_button: Button = %RotateCcwButton
@onready var _rotate_cw_button: Button = %RotateCwButton
@onready var _palette_row: HBoxContainer = %PaletteRow
@onready var _tile_readout: PanelContainer = %TileReadout
@onready var _tile_readout_label: Label = %TileReadoutLabel
@onready var _preview_panel: PanelContainer = %PreviewPanel
@onready var _preview_label: Label = %PreviewLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# FINAL REVIEW FIX (ported forward): these are declared directly in GameUI.tscn with a
	# hardcoded `custom_minimum_size = Vector2(72, 72)` — unlike the dynamically-built palette
	# buttons below (which already read `UiPalette.scaled(...)`). Without this loop,
	# `UI_SCALE_FACTOR` moves every OTHER piece of HUD chrome and leaves these two fixed,
	# producing a visibly mismatched HUD the moment the dial is set to anything but 1.0.
	var toggle_size := Vector2(
		UiPalette.scaled(UiPalette.MODE_TOGGLE_SIZE), UiPalette.scaled(UiPalette.MODE_TOGGLE_SIZE)
	)
	for button: Button in [_inspect_button, _rotate_ccw_button, _rotate_cw_button]:
		button.custom_minimum_size = toggle_size

	_inspect_button.pressed.connect(toggle_inspect)
	_decorate_inspect_button()
	# Playtest feedback: Rotate's hover state (and Erase's — see `LeaveOverlay`'s Exit button
	# for the same fix) "did not hover well" next to every other button. `GameUI.tscn` only
	# ever gave them a `normal` stylebox — never `hover`/`pressed`/`focus` — so they fell back
	# to Godot's stock theme for those states instead of matching the HUD's own cream/sand
	# look. `paint_button(button, false)` gives them the real hover/pressed states every other
	# button already has; `false` because Rotate is never a "selected" toggle, just painted
	# once here rather than re-painted on every `_refresh_palette_rendering()` like Erase is.
	UiPalette.paint_button(_rotate_ccw_button, false)
	UiPalette.paint_button(_rotate_cw_button, false)
	_rotate_ccw_button.pressed.connect(func() -> void: rotate_ccw_pressed.emit())
	_rotate_cw_button.pressed.connect(func() -> void: rotate_cw_pressed.emit())
	palette_changed.connect(_refresh_palette_rendering)
	mode_changed.connect(func(_m: Mode) -> void: _refresh_palette_rendering())
	_build_remove_button()

	_style_picker = _STYLE_PICKER_SCENE.instantiate() as StylePickerPopup
	add_child(_style_picker)
	_style_picker.style_selected.connect(_on_style_picker_style_selected)

	_readout_timer = Timer.new()
	_readout_timer.one_shot = true
	_readout_timer.wait_time = READOUT_SECONDS
	_readout_timer.timeout.connect(hide_tile_readout)
	add_child(_readout_timer)

	hide_tile_readout()
	hide_neighborhood_preview()
	_refresh_mode_buttons()


# --- Wood (read-only indicator, Pillar 1) ------------------------------------------------

func set_wood(amount: int) -> void:
	if _wood_value != null:
		_wood_value.text = str(amount)


# --- The other three top-level counters (Tier 1 row 11) -----------------------------------
#
# gdd.md -> Economy: "Top-level counters: Resources, Species Hosted (all-time, never
# decreases), Currently Resident, Village Population — information, never a score." All four
# live in this one corner panel so "at all times, in both first-person and map-peek view" is
# true by construction — `GameHud` is never hidden or rebuilt when `CameraRig` swaps cameras
# for the peek, only the camera changes.
#
# **A bare integer, never a fraction.** gdd.md -> Objectives & Progression bans exactly one
# shape here: "No completion percentage, total-species count, or finish-the-guide reward" —
# read precisely, that is the ratio "N discovered of TOTAL species that exist", which would
# hand a six-year-old a target to chase. Showing the running tally alone, with no denominator
## anywhere in this file, is what the same sentence's "all-time, never decreases" explicitly
# keeps: a fact about the world's history, not a bar to fill.
#
# **Currently Resident counts individual animals, not distinct species, and never villagers**
# — `total_residents() - population_of("human")`, ruled by the human. (Row 10's build had
# instead read it as `resident_species_ids().size()`, inferred from
# `HomeSiteRegistry.resident_species_ids()`'s own doc comment; gdd.md's Economy line names
# the counter but does not disambiguate. That inference was wrong — this is the correction.)
# Village Population's individuals are subtracted out rather than double-counted into this
# counter too.

func set_species_hosted(count: int) -> void:
	if _species_hosted_value != null:
		_species_hosted_value.text = str(count)


func set_currently_resident(count: int) -> void:
	if _currently_resident_value != null:
		_currently_resident_value.text = str(count)


func set_village_population(count: int) -> void:
	if _village_population_value != null:
		_village_population_value.text = str(count)


func species_hosted_text() -> String:
	return "" if _species_hosted_value == null else _species_hosted_value.text


func currently_resident_text() -> String:
	return "" if _currently_resident_value == null else _currently_resident_value.text


func village_population_text() -> String:
	return "" if _village_population_value == null else _village_population_value.text


# --- Modes -------------------------------------------------------------------------------

func mode() -> Mode:
	return _mode


func last_content_mode() -> Mode:
	return _last_content_mode


## The Inspect quick-toggle's whole behavior: press it to look around, press it again to
## pick up exactly the brush you had before. Never a fourth mode — this only ever calls
## `set_mode()` with one of the existing three values.
func toggle_inspect() -> void:
	if _mode == Mode.INSPECT:
		set_mode(_last_content_mode)
	else:
		set_mode(Mode.INSPECT)


func set_mode(new_mode: Mode) -> void:
	if new_mode != Mode.INSPECT:
		_last_content_mode = new_mode
	_mode = new_mode
	# DECIDED 2026-08-02 (playtest gate) — approved as shipped; see tier1-status.md row 2
	# `constants` (cross-claim). Entering a mode always starts on that mode's content brush,
	# never on the remove tool. The alternative (remove is sticky across mode switches) means a
	# player who removed one tile, went to Build for a house and came back is holding a tool they
	# last used a minute ago — and the one tool whose taps are not free to be wrong.
	_remove_selected = false
	hide_tile_readout()
	hide_neighborhood_preview()
	_refresh_mode_buttons()
	mode_changed.emit(_mode)


func _refresh_mode_buttons() -> void:
	UiPalette.paint_button(_inspect_button, _mode == Mode.INSPECT)
	if _inspect_icon != null:
		_inspect_icon.active = _mode == Mode.INSPECT


# --- Palette row ---------------------------------------------------------------------------

## Every palette-row button splits the same way vertically: the icon fills the top, this many
## pixels of name-label ZONE take the bottom (playtest feedback: an icon alone did not say what
## a button was). Applied identically to Info, every catalog button, and Erase.
const _NAME_LABEL_ZONE_HEIGHT: float = 22.0

## The label's own box sits this many pixels clear of the zone's bottom edge — playtest
## feedback: text flush with the true bottom edge was half-covered by the button's own
## bottom border (`UiPalette.BORDER_BOTTOM`, drawn along that edge). Matching that constant
## exactly is what "clear of the border" means here, not a guessed number.
const _NAME_LABEL_BOTTOM_CLEARANCE: float = UiPalette.BORDER_BOTTOM

## Info's icon, kept directly (unlike a catalog button's, which `_refresh_palette_rendering()`
## re-finds structurally every time) because `_refresh_mode_buttons()` — a different signal
## path (`mode_changed`, not `palette_changed`) — is the one place that needs to flip it.
var _inspect_icon: TileIcon = null


## Attaches the icon/number/name-label chrome every palette-row button shares. `icon_kind` is
## `null` for a catalog id `_ICON_KIND_BY_ID` has no entry for — the button still gets a real
## name label and number (so it stays usable), just no picture, the same graceful-degradation
## shape `catalog_rows()`'s own docs already promise for an unmapped id. `number_text` is ""
## for a button with no keyboard shortcut (Erase). `has_popup_indicator` adds a small
## `PopupIndicator` glyph (style-picker refinement round) — the caller (`_add_palette_button()`,
## via `_has_style_choice()`) only passes `true` for a `_PICKER_CATEGORIES` button whose catalog
## currently holds MORE THAN ONE style, so the indicator never promises a choice a long-press
## popup would not actually offer. See that child's own comment below for placement/rendering.
## Returns the icon, or null if none was made.
func _decorate_button(
	button: Button,
	icon_kind: Variant,
	number_text: String,
	name_text: String,
	has_popup_indicator: bool = false
) -> TileIcon:
	var icon: TileIcon = null
	if icon_kind != null:
		icon = TileIcon.new()
		icon.name = "Icon"
		icon.kind = icon_kind as TileIcon.Kind
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_bottom = -_NAME_LABEL_ZONE_HEIGHT
		button.add_child(icon)
		icon.owner = _palette_row.owner

	if number_text != "":
		var number := Label.new()
		number.name = "Number"
		number.text = number_text
		number.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		# Inset further from the corner than a naive "hug the edge" placement would put it
		# (playtest feedback: the button's own border/rounded corner was clipping the digit).
		number.offset_left = -24.0
		number.offset_top = 4.0
		number.offset_right = -8.0
		number.offset_bottom = 20.0
		number.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		number.add_theme_font_size_override("font_size", UiPalette.FONT_HOTBAR_NUMBER)
		number.add_theme_color_override("font_color", UiPalette.BARK)
		button.add_child(number)
		number.owner = _palette_row.owner

	if has_popup_indicator:
		# A small "this button has a long-press popup" glyph — style-picker refinement round.
		# Top-LEFT, deliberately the opposite corner from `Number` (top-right): the bottom strip
		# is already `NameLabel`'s full-width zone, so a bottom corner would either collide with
		# it or need its own carve-out, while the two top corners are otherwise empty on every
		# button. Same small-badge FOOTPRINT as `Number` (same corner box size). REVIEW FIX
		# (2026-08-27): this was a `Label` with `text = "▾"` (U+25BE) — that codepoint is not
		# covered by this project's bundled font and only rendered in dev because of a
		# dev-container-only system-font fallback that the Web export does not have (tofu box on
		# HTML5 — the exact bug class `rotate_icon.gd` already hit and fixed). A
		# `PopupIndicatorGlyph` (vector-drawn via `draw_colored_polygon()`, see its own header)
		# replaces it so this can never depend on font glyph coverage on any export target.
		var indicator := PopupIndicatorGlyph.new()
		indicator.name = "PopupIndicator"
		indicator.set_anchors_preset(Control.PRESET_TOP_LEFT)
		indicator.offset_left = 6.0
		indicator.offset_top = 4.0
		indicator.offset_right = 22.0
		indicator.offset_bottom = 20.0
		indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(indicator)
		indicator.owner = _palette_row.owner

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = name_text
	name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_top = -_NAME_LABEL_ZONE_HEIGHT
	name_label.offset_bottom = -_NAME_LABEL_BOTTOM_CLEARANCE
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", UiPalette.FONT_HOTBAR_LABEL)
	name_label.add_theme_color_override("font_color", UiPalette.BARK)
	button.add_child(name_label)
	name_label.owner = _palette_row.owner

	return icon


## Info, the Inspect quick-toggle — item 5 of the terraform-bar rework: an arrow glyph, "Info"
## underneath (human-decided rename from "Look" — playtest feedback), key 0 (read before key
## 1). `PaletteRow`'s `GameUI.tscn`-declared child, so this only adds the chrome; the button
## itself and its `pressed` wiring already exist.
func _decorate_inspect_button() -> void:
	_inspect_icon = _decorate_button(_inspect_button, TileIcon.Kind.LOOK, "0", "Info")


## The fixed Erase button — outside catalog content, always present, never itself assignable
## (design spec section 3's original "6th slot" framing, now just "the one tool button" that
## flanks the catalog on the right). Built once, at `_ready()`, independent of
## `build_palettes()` — Erase has no catalog data.
func _build_remove_button() -> void:
	_remove_button = Button.new()
	_remove_button.name = "RemoveButton"
	_remove_button.unique_name_in_owner = true
	_remove_button.custom_minimum_size = Vector2(
		UiPalette.scaled(UiPalette.HOTBAR_ICON_SIZE), UiPalette.scaled(UiPalette.HOTBAR_ICON_SIZE)
	)
	_remove_button.focus_mode = Control.FOCUS_NONE
	_remove_button.tooltip_text = REMOVE_ENTRY_LABEL
	_remove_button.pressed.connect(activate_remove)
	# Appended right after Info (`PaletteRow`'s only OTHER `GameUI.tscn`-declared child,
	# resolved before `_ready()` runs) — that is already Erase's correct final position: every
	# catalog button `_add_palette_button()` inserts later goes in BEFORE whichever child sits
	# at Erase's own index, so Erase stays the row's last child throughout.
	_palette_row.add_child(_remove_button)
	_remove_button.owner = _palette_row.owner
	_decorate_button(_remove_button, TileIcon.Kind.ERASER, "", REMOVE_ENTRY_LABEL)


## Builds one button per catalog entry (terrain, then one per PLACEABLE GROUP — see the
## `hotbar_category` header note above), inserted immediately before the Erase button every
## time — since Erase already exists, each newly-inserted button lands at
## `_remove_button.get_index()`, which keeps shifting right as more are inserted, producing
## catalog order without any index bookkeeping of its own. Idempotent: a second call (a fresh
## world bound to the same HUD) clears the previous set first rather than doubling it.
func _build_palette_row() -> void:
	for button: Button in _palette_buttons:
		button.queue_free()
	_palette_buttons.clear()
	_palette_order.clear()
	# Freed alongside the buttons they're bound to (Task 7) — a rebuilt row (a fresh world
	# bound to the same HUD) must not leave a stale Timer pointed at a `queue_free()`'d Button
	# in `_on_long_press_timeout()`'s bound argument.
	for id: String in _long_press_timers:
		var timer: Timer = _long_press_timers[id] as Timer
		if timer != null:
			timer.queue_free()
	_long_press_timers.clear()
	_swallow_next_press.clear()

	for row: Dictionary in catalog_rows(Mode.TERRAFORM):
		_add_palette_button("terrain", row)
	for group_key: String in _placeable_group_keys():
		_add_palette_button("placeable", _placeable_group_row(group_key))

	_refresh_palette_rendering()


## Every distinct `hotbar_category` (falling back to the placeable's own id when that field is
## "") among the currently-loaded `_placeable_entries`, in first-seen catalog order — House
## first (its own single-member "group"), then Farm Building. Dictionary key order in GDScript
## is insertion order, and `_placeable_entries` was populated in `world.placeable_options()`
## order, so this needs no separate sort.
func _placeable_group_keys() -> Array[String]:
	var seen: Dictionary = {}
	var out: Array[String] = []
	for id: String in _placeable_entries:
		var group_key: String = _placeable_entries[id]["category"] as String
		if not seen.has(group_key):
			seen[group_key] = true
			out.append(group_key)
	return out


## The catalog row for one placeable group's button. `group_key` is either a real placeable id
## (a single-member group, e.g. "house" — `_placeable_entries` has that key directly) or a true
## `hotbar_category` shared by several placeables (e.g. "farm_building" — no entry under that
## literal string exists, which is exactly how this tells the two cases apart). For a true
## category, the member actually shown/placed is `world.get_style_default(group_key)`'s current
## answer — the player's chosen default, re-resolved on every call rather than cached, so a
## rebuilt row (or a `refresh_palette_button()` call) always reflects the latest selection.
## `icon_id` carries that resolved member id separately from `id` (the group key itself, which
## is what stays bound to the button's `pressed` signal — see `activate_palette_entry()`).
func _placeable_group_row(group_key: String) -> Dictionary:
	var resolved_id: String = group_key
	if not _placeable_entries.has(group_key) and _world != null:
		resolved_id = _world.get_style_default(group_key)
	var entry: Dictionary = _placeable_entries.get(resolved_id, {})
	return {
		"id": group_key,
		"icon_id": resolved_id,
		"display_name": entry.get("display_name", "") as String,
		"cost": entry.get("cost", 0) as int,
	}


func _add_palette_button(kind: String, row: Dictionary) -> void:
	var id: String = row["id"] as String
	var icon_id: String = row.get("icon_id", id) as String
	var display_name: String = row["display_name"] as String
	var button := Button.new()
	button.name = "PaletteButton_%s" % id
	button.custom_minimum_size = Vector2(
		UiPalette.scaled(UiPalette.HOTBAR_ICON_SIZE), UiPalette.scaled(UiPalette.HOTBAR_ICON_SIZE)
	)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = display_name
	# Task 7: every button's `pressed` routes through the swallow check, not just the 4
	# picker-enabled ones — `_swallow_next_press` only ever gains an entry for an id in
	# `_PICKER_CATEGORIES` (only those get `_wire_long_press()` below), so this is a no-op
	# wrapper for every other button, indistinguishable from calling `activate_palette_entry()`
	# directly the way this line used to.
	button.pressed.connect(_on_palette_button_pressed.bind(kind, id))
	if id in _PICKER_CATEGORIES:
		_wire_long_press(button, id)
	_palette_row.add_child(button)
	button.owner = _palette_row.owner
	_palette_row.move_child(button, _remove_button.get_index())

	var icon_kind: Variant = _ICON_KIND_BY_ID[icon_id] if _ICON_KIND_BY_ID.has(icon_id) else null
	_decorate_button(
		button, icon_kind, str(_palette_order.size() + 1), display_name, _has_style_choice(id)
	)

	_palette_order.append({"kind": kind, "id": id})
	_palette_buttons.append(button)


## REVIEW FIX (2026-08-27): `id in _PICKER_CATEGORIES` alone is no longer enough to promise a
## popup is worth opening. A separately-reviewed, separately-approved revert dropped Wild
## Grass's catalog back to a single `model_scenes` entry, so `style_ids_for_category(
## "wild_grass")` now returns exactly one id — long-pressing it would open a popup with one row,
## already highlighted as current, that changes nothing. Showing the indicator there would
## promise a choice that does not exist, a confusing affordance for the game's 6-10-year-old
## audience. Gating on the catalog's OWN current size (not a hardcoded assumption) means the
## indicator disappears today for Wild Grass and reappears automatically if its catalog ever
## grows past one entry again — no second fix needed either way.
func _has_style_choice(id: String) -> bool:
	if not (id in _PICKER_CATEGORIES) or _world == null:
		return false
	return _world.style_ids_for_category(id).size() > 1


## Repaints exactly one already-built palette button — its icon and its tooltip/name-label
## text — against `WorldRoot.get_style_default()`'s CURRENT answer for `category_or_id`,
## without touching any other button or rebuilding the row. Exposed for Task 7's long-press
## popup: after it writes a new `style_defaults` entry (`WorldRoot.set_style_default()`), this
## is how the Farm Building button's chrome catches up to the new selection. A no-op if
## `category_or_id` names no currently-built placeable button (nothing to repaint) or `_world`
## is unset (`build_palettes()` hasn't run).
func refresh_palette_button(category_or_id: String) -> void:
	if _world == null:
		return
	var index: int = -1
	for i in _palette_order.size():
		var entry: Dictionary = _palette_order[i]
		if (entry["kind"] as String) == "placeable" and (entry["id"] as String) == category_or_id:
			index = i
			break
	if index < 0:
		return

	var row: Dictionary = _placeable_group_row(category_or_id)
	var display_name: String = row["display_name"] as String
	var icon_id: String = row["icon_id"] as String
	var button: Button = _palette_buttons[index]
	button.tooltip_text = display_name
	var name_label: Label = button.get_node_or_null("NameLabel") as Label
	if name_label != null:
		name_label.text = display_name
	var icon: TileIcon = _icon_child_of(button)
	if icon != null and _ICON_KIND_BY_ID.has(icon_id):
		icon.kind = _ICON_KIND_BY_ID[icon_id] as TileIcon.Kind

	_refresh_palette_rendering()


## The `pressed` signal every palette button (picker-enabled or not) now routes through
## instead of `activate_palette_entry()` directly — see `_add_palette_button()`'s own comment.
## A long-press (`_on_long_press_timeout()`) marks `id` in `_swallow_next_press` the instant it
## opens the popup. MEASURED against the real engine (fix round, 2026-08-27 review): on an
## IN-PLACE release `Button` emits `pressed` BEFORE `button_up`, not after — so for that case
## this is where the flag actually gets consumed. It is NOT the only place it gets consumed,
## though: a release with the pointer dragged off the button emits `button_up` with NO
## `pressed` at all, which is why `_on_picker_button_up()` below ALSO erases the flag — see
## that function's own comment for why both are needed. Every press that never set the flag —
## every non-picker button, and every picker-enabled button's ordinary quick tap — finds
## nothing to consume and calls `activate_palette_entry()` exactly as before this task.
func _on_palette_button_pressed(kind: String, id: String) -> void:
	if _swallow_next_press.get(id, false):
		_swallow_next_press.erase(id)
		return
	activate_palette_entry(kind, id)


## Attaches one picker-enabled button's long-press machinery: a one-shot `Timer` at
## `LONG_PRESS_SECONDS`, started on `button_down` and stopped on `button_up` (a normal quick
## tap never lets the timer fire at all — see `_on_picker_button_up()`).
func _wire_long_press(button: Button, id: String) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = LONG_PRESS_SECONDS
	add_child(timer)
	_long_press_timers[id] = timer
	timer.timeout.connect(_on_long_press_timeout.bind(id, button))
	button.button_down.connect(_on_picker_button_down.bind(id))
	button.button_up.connect(_on_picker_button_up.bind(id))


func _on_picker_button_down(id: String) -> void:
	var timer: Timer = _long_press_timers.get(id)
	if timer != null:
		timer.start()


## Cancels `id`'s long-press timer on release — reached on EVERY release, long or short; if
## the timer already fired (and is therefore already stopped, being one-shot), `stop()` here
## is simply a no-op. For a normal quick tap this is the regression bar itself: the timer never
## got the chance to fire, `_swallow_next_press` never gained an entry for `id`, and `Button`'s
## own `pressed` (which fires BEFORE `button_up` on an in-place release — measured, not
## assumed, in the fix round below) already ran `activate_palette_entry()` exactly as it did
## before this task existed.
##
## CRITICAL FIX (2026-08-27 review, reproduced live against the real HUD): also erase
## `_swallow_next_press[id]` here, unconditionally. A long-press's release is not always
## in-place — the popup opens directly above the button, so the natural next motion is to
## slide toward it and lift, a drag-off release. `Button` does NOT emit `pressed` at all when
## the pointer leaves the button's rect before release (measured: `button_down`, `button_up`,
## no `pressed`) — so `_on_palette_button_pressed()` above, the ONLY other place this flag was
## ever cleared, never runs, and the flag stayed `true` forever, silently eating the next
## ordinary tap on that same button. Erasing here is harmless for the two cases that already
## worked (quick tap: never set; in-place long-press release: already erased) and is now the
## only place that clears it for the drag-off case.
func _on_picker_button_up(id: String) -> void:
	var timer: Timer = _long_press_timers.get(id)
	if timer != null and not timer.is_stopped():
		timer.stop()
	_swallow_next_press.erase(id)


## The Timer firing IS the long-press. Marks `id`'s next `pressed` to be swallowed and opens
## the style picker anchored to `button` — both happen here, together, so there is no window
## where one occurred without the other.
func _on_long_press_timeout(id: String, button: Button) -> void:
	_swallow_next_press[id] = true
	open_style_picker(id, button)


## Test-driving entry point (mirrors `_activate_palette_entry_by_number()`'s role): fires
## exactly what `id`'s long-press Timer firing does, without a real `LONG_PRESS_SECONDS` wait.
## A no-op if `id` isn't a currently-built picker-enabled button.
func simulate_long_press(id: String) -> void:
	if not _long_press_timers.has(id):
		return
	_on_long_press_timeout(id, palette_button_for(id))


## Opens the style picker for `category`, anchored to `anchor_button`. Public (not just
## reached via a long-press) so a future non-gesture entry point — or a test — can drive it
## directly. A no-op before `build_palettes()` has run.
func open_style_picker(category: String, anchor_button: Control) -> void:
	if _style_picker == null or _world == null:
		return
	_style_picker.open(_world, category, anchor_button)


func is_style_picker_open() -> bool:
	return _style_picker != null and _style_picker.is_open()


## Test-driving accessor — the popup instance itself, for a test that wants to inspect its
## rows directly rather than only through `GameHud`'s own surface.
func style_picker() -> StylePickerPopup:
	return _style_picker


## `StylePickerPopup.style_selected`'s only listener (Task 7, Step 4; generalized in the
## refinement round, 2026-08-27): writes the player's choice, then immediately SELECTS+ACTIVATES
## it — the exact same `activate_palette_entry()` an ordinary tap on any palette button calls —
## and repaints the one button that changed without touching any other or rebuilding the row.
##
## Picking a popup row is now indistinguishable, in its end effect, from tapping the button it
## belongs to: `category` is always either a terrain id used as-is (Forest/Wild Grass — see
## `_PICKER_CATEGORIES`'s own header) or a placeable id/group key (House/Farm Building), so
## `activate_palette_entry(_kind_for_category(category), category)` both switches Mode and sets
## the live selection correctly for all 4 categories in one call — including resolving a group
## key (Farm Building) to `get_style_default()`'s freshly-written answer, exactly the way a real
## tap on that button already does. This replaces the earlier narrow fix that only re-targeted
## `_selected_placeable_id` when Farm Building was ALREADY the active selection and left
## Forest/Wild Grass/House untouched; `activate_palette_entry()` already handles "was already
## selected" (a re-pick of the current default lands here too — see `_rebuild_rows()`'s own
## header) and "wasn't selected" uniformly, so there is nothing left for this function to
## special-case.
func _on_style_picker_style_selected(category: String, style_id: String) -> void:
	if _world != null:
		_world.set_style_default(category, style_id)
		activate_palette_entry(_kind_for_category(category), category)
	refresh_palette_button(category)


## `activate_palette_entry()`'s `kind` argument, derived from a picker category rather than
## passed in — Forest/Wild Grass are TERRAIN ids used as-is, House/Farm Building are PLACEABLE
## ids/group keys (see `_PICKER_CATEGORIES`'s own header for why those 4, and only those 4).
func _kind_for_category(category: String) -> String:
	return "terrain" if (category == "forest" or category == "wild_grass") else "placeable"


func _refresh_palette_rendering() -> void:
	for i in _palette_order.size():
		var entry: Dictionary = _palette_order[i]
		var button: Button = _palette_buttons[i]
		var is_active: bool = not _remove_selected and _is_entry_active(entry)
		UiPalette.paint_button(button, is_active)
		var icon: TileIcon = _icon_child_of(button)
		if icon != null:
			icon.active = is_active
	UiPalette.paint_button(_remove_button, _remove_selected)
	var remove_icon: TileIcon = _icon_child_of(_remove_button)
	if remove_icon != null:
		remove_icon.active = _remove_selected


## Not `unique_name_in_owner`-registered (would pollute the scene's `%`-lookup table with one
## entry per catalog id) — found structurally instead, the same way `_scan_controls()`-style
## checks elsewhere in this codebase walk a small, known-shallow child list.
func _icon_child_of(button: Button) -> TileIcon:
	for child: Node in button.get_children():
		if child is TileIcon:
			return child as TileIcon
	return null


func _is_entry_active(entry: Dictionary) -> bool:
	if entry["kind"] == "terrain":
		return _mode == Mode.TERRAFORM and (entry["id"] as String) == _selected_terrain_id
	# A grouped button's `entry["id"]` is the GROUP key (e.g. "farm_building"), never the real
	# member id `_selected_placeable_id` holds — so the currently-selected placeable's own group
	# key is what has to match, the same fallback-to-own-id rule `_placeable_group_keys()` used
	# to build the row in the first place (which is how House, a single-member group, still
	# compares equal on its own id).
	return (
		_mode == Mode.BUILD
		and _placeable_group_key_for(_selected_placeable_id) == (entry["id"] as String)
	)


## `id`'s `hotbar_category` (falling back to `id` itself when that field is "" — mirrors
## `_placeable_group_keys()`'s own rule). "" for an id `_placeable_entries` has never heard of.
func _placeable_group_key_for(id: String) -> String:
	if not _placeable_entries.has(id):
		return ""
	return _placeable_entries[id]["category"] as String


## The whole gesture: press a palette button. Sets Mode implicitly (terrain -> TERRAFORM,
## placeable -> BUILD) the same way the retired category buttons, and the slot model before
## this, both did.
##
## A placeable `id` may be a GROUP KEY rather than a real placeable id — `_add_palette_button()`
## binds a grouped button's `pressed` signal to its group key (e.g. "farm_building"), not to
## whichever member happened to be the default when the row was last built, so a tap always
## resolves against `WorldRoot.get_style_default()`'s answer AT TAP TIME. Everything downstream
## of this function (`_placeable_entries` lookup, the cost check, `WorldRoot.place_building()`)
## receives the real, resolved id — never the literal group key.
func activate_palette_entry(kind: String, id: String) -> void:
	_remove_selected = false
	if kind == "terrain":
		set_mode(Mode.TERRAFORM)
		_selected_terrain_id = id
	else:
		set_mode(Mode.BUILD)
		var real_id: String = id
		if not _placeable_entries.has(id) and _world != null:
			real_id = _world.get_style_default(id)
		_selected_placeable_id = real_id
	palette_changed.emit()


## Remove is a fixed tool button outside the catalog — reachable regardless of what was
## active last, never itself assignable.
func activate_remove() -> void:
	_remove_selected = true
	palette_changed.emit()


## Keyboard path for the 1-9 palette keys. Public and index-driven so a headless test can
## drive the exact activation a real keypress triggers, without a synthetic key event.
func _activate_palette_entry_by_number(number: int) -> void:
	if number < 1 or number > _palette_order.size():
		return
	var entry: Dictionary = _palette_order[number - 1]
	activate_palette_entry(entry["kind"] as String, entry["id"] as String)


## 0 is Info (the Inspect quick-toggle, item 5 of the terraform-bar rework — "read before key
## 1", not a catalog slot), 1-9 are palette entries.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var number: int = _number_for_keycode(key.keycode)
	if number < 0:
		return
	if number == 0:
		toggle_inspect()
	else:
		_activate_palette_entry_by_number(number)
	get_viewport().set_input_as_handled()


func _number_for_keycode(keycode: int) -> int:
	if keycode >= KEY_0 and keycode <= KEY_9:
		return keycode - KEY_0
	return -1


## Builds the palette row from the world's own data. Called once, after `WorldRoot` is ready.
func build_palettes(world: WorldRoot) -> void:
	_clear_palette_entries()
	_world = world
	if world == null:
		return
	for terrain: TerrainDefinition in world.terrain_options():
		_terrain_entries[terrain.id] = {"display_name": terrain.display_name, "cost": terrain.cost}
	for placeable: PlaceableDefinition in world.placeable_options():
		var group_key: String = (
			placeable.hotbar_category if placeable.hotbar_category != "" else placeable.id
		)
		_placeable_entries[placeable.id] = {
			"display_name": placeable.display_name, "cost": placeable.cost, "category": group_key
		}
	_build_palette_row()


func _clear_palette_entries() -> void:
	_terrain_entries.clear()
	_placeable_entries.clear()
	_selected_terrain_id = ""
	_selected_placeable_id = ""
	_remove_selected = false


func _entries_for_mode() -> Dictionary:
	match _mode:
		Mode.TERRAFORM:
			return _terrain_entries
		Mode.BUILD:
			return _placeable_entries
		_:
			return {}


func _select_terrain(terrain_id: String) -> void:
	_selected_terrain_id = terrain_id
	_remove_selected = false


func _select_placeable(placeable_id: String) -> void:
	_selected_placeable_id = placeable_id
	_remove_selected = false


func _select_remove() -> void:
	activate_remove()


## The selected terrain brush, or "" while the remove tool is held. Returning "" rather than the
## remembered brush is what keeps `TapRouter._tap_terraform()` structurally unable to paint on a
## remove tap, without it having to know the remove tool exists.
func selected_terrain_id() -> String:
	return "" if _remove_selected else _selected_terrain_id


func selected_placeable_id() -> String:
	return "" if _remove_selected else _selected_placeable_id


## True while the remove tool is the picked palette entry, in either Terraform or Build. The
## single question `TapRouter` asks before it asks the mode anything.
func is_remove_selected() -> bool:
	return _remove_selected


## Test/HUD-driving entry point: pick a palette option by id, whichever palette it is in.
## `REMOVE_OPTION_ID` selects the remove tool, so a headless check drives exactly the button the
## player presses. NOTE: unlike `activate_palette_entry()`, this does not change `mode()` — it
## only sets the brush, matching every existing caller's expectation (they set mode separately).
func select_palette_option(option_id: String) -> bool:
	if option_id == REMOVE_OPTION_ID:
		_select_remove()
		return true
	if _terrain_entries.has(option_id):
		_select_terrain(option_id)
		return true
	if _placeable_entries.has(option_id):
		_select_placeable(option_id)
		return true
	return false


## The **data-driven content** of the current palette: exactly what `WorldRoot.terrain_options()`
## / `placeable_options()` reported, in their order, and nothing else. The remove tool is a tool
## rather than content and is deliberately absent — `is_remove_selected()` and
## `REMOVE_OPTION_ID` are how it is observed. That keeps this list's guarantee ("nothing here
## hardcodes a terrain list") exactly as strong as it was.
func palette_option_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in _entries_for_mode():
		ids.append(id)
	return ids


## Every entry of `mode`'s catalog (Terraform or Buildings), in catalog order — what the
## palette row (and, for BUILD, the House button) renders. `cost` is a plain `int` here, not
## pre-formatted label text.
func catalog_rows(mode: Mode) -> Array[Dictionary]:
	var entries: Dictionary = _terrain_entries if mode == Mode.TERRAFORM else _placeable_entries
	var out: Array[Dictionary] = []
	for id: String in entries:
		var entry: Dictionary = entries[id]
		out.append({
			"id": id,
			"display_name": entry["display_name"] as String,
			"cost": entry["cost"] as int,
		})
	return out


## The button for `id`, or null if `build_palettes()` hasn't run or `id` isn't in the catalog.
## Test-driving entry point — mirrors the old `slot_contents()`'s role for headless checks.
func palette_button_for(id: String) -> Button:
	for i in _palette_order.size():
		if (_palette_order[i]["id"] as String) == id:
			return _palette_buttons[i]
	return null


# --- Inspect readout ---------------------------------------------------------------------

## "empty land does nothing, optionally showing its terrain/tags" (gdd.md -> Inspect Mode).
## Data only — a terrain's authored name and its tags — so no copy is invented here.
func show_tile_readout(terrain_name: String, tags: Array[String]) -> void:
	var tag_line: String = NO_TAGS_GLYPH if tags.is_empty() else " · ".join(tags)
	_tile_readout_label.text = "%s\n%s" % [terrain_name, tag_line]
	_tile_readout.visible = true
	if _readout_timer != null:
		_readout_timer.start(READOUT_SECONDS)


func hide_tile_readout() -> void:
	if _tile_readout != null:
		_tile_readout.visible = false


func tile_readout_text() -> String:
	return "" if _tile_readout_label == null else _tile_readout_label.text


func tile_readout_visible() -> bool:
	return _tile_readout != null and _tile_readout.visible


# --- Live neighborhood preview -----------------------------------------------------------

## Renders one band of `NeighborhoodPreview` as its line of copy.
##
## **No timer.** Unlike the Inspect readout, this panel stays up as long as the cursor is over
## land in Terraform or Build, and disappears the moment it is not — it tracks a state, it does
## not announce an event, so there is nothing for a countdown to be measuring.
func show_neighborhood_preview(band: String) -> void:
	if _preview_panel == null:
		return
	var text: String = _preview_text(band)
	if text == "":
		hide_neighborhood_preview()
		return
	_preview_label.text = text
	_preview_panel.visible = true


func hide_neighborhood_preview() -> void:
	if _preview_panel != null:
		_preview_panel.visible = false


func neighborhood_preview_text() -> String:
	return "" if _preview_label == null else _preview_label.text


func neighborhood_preview_visible() -> bool:
	return _preview_panel != null and _preview_panel.visible


## Band -> copy. An unknown band renders nothing rather than its own name: a band this file has
## no words for must not leak an identifier onto the screen.
func _preview_text(band: String) -> String:
	match band:
		NeighborhoodPreview.BAND_WILD:
			return PREVIEW_TEXT_WILD
		NeighborhoodPreview.BAND_WELCOMING:
			return PREVIEW_TEXT_WELCOMING
		NeighborhoodPreview.BAND_HOME:
			return PREVIEW_TEXT_HOME
		_:
			return ""
