class_name UiPalette
extends RefCounted
## The one place the UI's colours, corner radii and type sizes are written down.
##
## EVERY VALUE HERE IS A HUMAN DECISION (art.md -> Visual Style: "saturated but gentle …
## warm-leaning; no pure black or pure white"). They are gathered in one file specifically
## so the human's taste pass is a single diff, not a hunt through six scenes.
##
## The five colours are **not invented here** — they are lifted verbatim from the already
## human-reviewed `scenes/TitleScreen.tscn`, so the in-game HUD and the title screen are the
## same world. Anything the title screen did not already establish is marked NEW below.

## Bark brown — every border, and body type on light panels. (TitleScreen border_color.)
const BARK: Color = Color(0.42, 0.29, 0.169)

## Leaf green — the *selected* state, and nothing else. (TitleScreen PrimaryNormal.)
const LEAF: Color = Color(0.341, 0.596, 0.247)

## Brighter leaf — hover on a selected/primary control. (TitleScreen PrimaryHover.)
const LEAF_BRIGHT: Color = Color(0.404, 0.694, 0.294)

## Warm cream — every unselected panel and button face. (TitleScreen SecondaryNormal.)
const CREAM: Color = Color(1.0, 0.973, 0.906)

## Warm sand — hover on an unselected control. (TitleScreen SecondaryHover.)
const SAND: Color = Color(0.851, 0.784, 0.541)

## NEW — the fact card's scrim. Deliberately *very* light: spec.md requires the world stay
## "visible and simulating behind" the card, so this focuses the eye without dimming the
## world. Warm bark rather than black (art.md: no pure black).
const SCRIM: Color = Color(0.42, 0.29, 0.169, 0.16)

## NEW — the accepted-tap cue ring. Leaf green, the same "yes" colour as a selected mode.
const CUE_ACCEPT: Color = Color(0.404, 0.694, 0.294, 0.85)

## NEW — the Gentle Displacement warning panel's face (row 10). **Sand, not cream, on purpose.**
## It is the one panel in the game that is neither a fact card nor a News Report toast, and
## gdd.md requires consent copy to never read as flavour, so it is given the only other face
## colour the title screen already established rather than a new hue. It is warm and it is
## unmistakably a different panel from three feet away, which is the whole job.
const NOTICE_FACE: Color = SAND

## NEW — the displacement move marker: the ring at a home that moved, and the dashed trail to
## where it went. **Bark at low alpha, deliberately not `CUE_ACCEPT` or `CUE_SOFT`** — those two
## are the whole of the tap-feedback vocabulary ("yes" and "received, not here") and reusing
## either would teach one colour two meanings. This one says only "look here", quietly.
const MOVE_TRAIL: Color = Color(0.42, 0.29, 0.169, 0.55)

## NEW — the soft-cue ring for a tap the world did not accept. **Not a red, not an X, not a
## message** (Pillar 1): a quieter, cooler version of the same ring, which reads as "not
## here" rather than "wrong". Its only job is to prove the tap was received.
const CUE_SOFT: Color = Color(0.851, 0.784, 0.541, 0.7)

## NEW — Field Guide silhouette rows (undiscovered species; playability chrome overhaul,
## section 3). Bark at low alpha: legible as "present but unrevealed," not an error or a
## warning color, and not pure grey (art.md: no pure black or pure white).
const FIELD_GUIDE_SILHOUETTE_INK: Color = Color(0.42, 0.29, 0.169, 0.4)

## NEW — the crosshair's "yes, tap here" state (playability chrome overhaul, section 1).
## Reuses leaf green, the same "yes" meaning `CUE_ACCEPT` and a selected mode already
## carry, rather than inventing a fourth meaning for one hue.
const CROSSHAIR_VALID: Color = Color(0.341, 0.596, 0.247, 0.9)

## NEW — the crosshair's "not here" state. Bark at low alpha: quiet, matching `CUE_SOFT`'s
## "received, not here" register, deliberately not a warning color.
const CROSSHAIR_INVALID: Color = Color(0.42, 0.29, 0.169, 0.55)

## Corner radius on every panel and button. (TitleScreen: 28.)
const CORNER_RADIUS: int = 28

## A smaller radius for the compact in-world HUD chrome, where 28 on a 88px-tall button
## reads as a pill rather than a rounded rectangle. NEW — the title screen has no small
## controls to have decided this.
const CORNER_RADIUS_SMALL: int = 18

## Border weights. The heavier bottom edge is the title screen's "chunky picture-book"
## signature and is reproduced here so the two screens match.
const BORDER: int = 4
const BORDER_BOTTOM: int = 8

## Type scale. NEW at every size except the fact-card body, which is sized to spec.md's
## "large plain type, pre-fluent-friendly".
const FONT_HUD: int = 30
const FONT_MODE_BUTTON: int = 32
const FONT_PALETTE: int = 22
const FONT_PALETTE_COST: int = 18
const FONT_CARD_TITLE: int = 44
const FONT_CARD_BODY: int = 28

## NEW — row 11's three secondary HUD counters (Species Hosted, Currently Resident, Village
## Population). Smaller than `FONT_HUD` deliberately: four rows at 30px stacks taller than the
## corner spec.md sketches for a single Wood line, and Wood is read most often of the four, so
## it alone keeps the larger size. A **visual judgment call**, flagged under Proposals.
const FONT_HUD_SECONDARY: int = 22

## NEW — the live neighborhood preview's single line. Between the HUD counter and the fact
## card's body: it is a sentence to be read at a glance while the hand is busy, so it is larger
## than the Inspect readout's data line and smaller than the card the player has stopped for.
const FONT_PREVIEW: int = 26

## NEW — the Gentle Displacement warning (row 10). The lead sits between the preview line and the
## fact-card title: it is the sentence the whole dialogue hangs on and it is read once, carefully.
## The family lines match the preview's size, because they are the same kind of sentence — a
## statement about what a family will do, read at a glance — and because a stack of four of them
## at lead size would push the panel past "never fills the screen".
const FONT_NOTICE_LEAD: int = 32
const FONT_NOTICE_LINE: int = 26

## NEW — the consequence banner. Matched to the preview line deliberately: both are one plain
## sentence in the game's own voice, and they should read as the same register.
const FONT_BANNER: int = 26

## Minimum hit target. spec.md -> Screen Layouts: "large touch-friendly hit areas even on
## desktop, per Pillar 3". REVISED (playability chrome overhaul) from 88 to 72 — still well
## clear of Apple's 44pt HIG minimum and Google's 48dp Material minimum at typical DPI; 88
## was generous rather than minimum, and "buttons are too big" was a direct human complaint.
## THE actual floor now, not just a name for one (final review fix): `HOTBAR_ICON_SIZE` and
## `MODE_TOGGLE_SIZE` derive from this constant below rather than repeating 72 as three
## independent literals that merely happened to agree — change this value and both follow.
const HIT_TARGET: int = 72

## PROPOSED — human's call. One dial for the whole HUD's chrome size, multiplied in at each
## read site (GDScript consts cannot call functions, so this can't be baked into the
## constants below). 1.0 changes nothing; this plan's job is to make the dial exist and
## apply it to the elements it touches (the hotbar, the mode/Inspect toggles, and — final
## review fix — the seven static HUD buttons `GameHud._ready()` now sizes off
## `MODE_TOGGLE_SIZE`), not to retune it — a human playtest across window sizes is what
## that needs.
##
## `static var`, not `const` (final review fix): a GDScript const cannot be reassigned, and
## `test_hud_hotbar.gd` needs to drive this to a non-default value and back to prove the
## dial is actually load-bearing rather than merely present. Nothing shipped ever writes to
## it; it stays 1.0 outside that one test, which restores it before it finishes.
static var UI_SCALE_FACTOR: float = 1.0

static func scaled(value: float) -> float:
	return value * UI_SCALE_FACTOR

## NEW — the hotbar's icon-only buttons (replaces the old 148x96 labeled palette buttons).
## Derives from `HIT_TARGET` (final review fix) rather than repeating its literal value —
## see that constant's comment.
const HOTBAR_ICON_SIZE: float = HIT_TARGET

## NEW — the Inspect toggle and the Terrain/Build category switch (replaces the old 200x88
## labeled mode buttons). Derives from `HIT_TARGET` (final review fix) rather than
## repeating its literal value — see that constant's comment.
const MODE_TOGGLE_SIZE: float = HIT_TARGET

## NEW — icon-only chrome reads smaller than a labeled button at the same font size did;
## this is for whatever short label still appears under a hotbar/toggle icon.
const FONT_HOTBAR: int = 18

## NEW — the small shortcut-number badge in a palette button's corner (terraform bar rework).
## Deliberately smaller than FONT_HOTBAR: it is a keyboard hint, not the button's label.
const FONT_HOTBAR_NUMBER: int = 14

## NEW — the name label under a palette button's icon (playtest feedback: an icon alone did
## not say what a button was). Small on purpose — "helpful, not the headline" — but a touch
## smaller than `FONT_HOTBAR_NUMBER` is not the goal here; legibility of an actual word is.
const FONT_HOTBAR_LABEL: int = 12

## NEW — reticle geometry in pixels: a small plus-mark with a gap at the centre so it
## never fully occludes whatever it is aimed at.
const CROSSHAIR_ARM_LENGTH: float = 10.0
const CROSSHAIR_GAP: float = 4.0
const CROSSHAIR_THICKNESS: float = 3.0


## A filled, rounded, bark-bordered panel — the one shape every piece of chrome uses.
static func panel_style(
	fill: Color,
	radius: int = CORNER_RADIUS,
	pad: int = 20
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = BARK
	box.border_width_left = BORDER
	box.border_width_top = BORDER
	box.border_width_right = BORDER
	box.border_width_bottom = BORDER_BOTTOM
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.content_margin_left = pad
	box.content_margin_top = pad
	box.content_margin_right = pad
	box.content_margin_bottom = pad
	return box


## Paints a Button as either the resting (cream) or the selected (leaf) state.
##
## Selection is carried by **fill colour plus font colour**, never by colour alone at the
## same value — the current mode has to be obvious to a six-year-old across the room.
static func paint_button(button: Button, selected: bool, radius: int = CORNER_RADIUS_SMALL) -> void:
	var face: Color = LEAF if selected else CREAM
	var hover: Color = LEAF_BRIGHT if selected else SAND
	var ink: Color = CREAM if selected else BARK
	button.add_theme_stylebox_override("normal", panel_style(face, radius, 14))
	button.add_theme_stylebox_override("hover", panel_style(hover, radius, 14))
	button.add_theme_stylebox_override("pressed", panel_style(hover, radius, 14))
	button.add_theme_stylebox_override("focus", panel_style(Color(face, 0.0), radius, 14))
	button.add_theme_stylebox_override("disabled", panel_style(Color(CREAM, 0.6), radius, 14))
	button.add_theme_color_override("font_color", ink)
	button.add_theme_color_override("font_hover_color", ink)
	button.add_theme_color_override("font_pressed_color", ink)
	button.add_theme_color_override("font_focus_color", ink)
