class_name TileIcon
extends Control
## Vector-drawn glyphs for the terraform bar's buttons — one small pictogram per terrain,
## the House, the eraser (Take Away), and the Leave overlay's Exit "X". Same technique as
## `rotate_icon.gd` (draw_line/draw_arc/draw_polygon in `_draw()`, no image asset), so a
## reskin of any of these is a code diff, never an art re-import.
##
## MONOCHROME BY DESIGN. `UiPalette.paint_button()` already flips a selected button's font
## color to CREAM against a LEAF-green face — a two-tone icon (e.g. leaf-green grass blades)
## would vanish against that same green background the moment its button is selected. Every
## glyph here is drawn in one ink color that follows the same flip (`active` below), exactly
## like the button's own label text does, so it stays legible in both states without a
## second palette of icon-specific colors.

## THE ORDINALS ARE A SERIALISED CONTRACT — write them explicitly, and only ever APPEND.
##
## `kind` is an `@export`, so a scene that sets it stores the INTEGER, not the name:
## `GameUI.tscn`'s Field Guide button is `kind = 10` and `LeaveOverlay.tscn`'s Exit is
## `kind = 8`. Inserting FARM_BUILDING in the middle of this enum (2026-09-03) shifted every
## later member by one and silently repointed both — the Field Guide's "?" started drawing
## LOOK's arrow, and Leave's "X" drew the eraser block. Nothing failed; the glyphs just
## changed. The explicit values below are what makes that a diff you have to write on purpose
## rather than a side effect of where you happened to type a new name.
enum Kind {
	WILD_GRASS = 0,
	GRASS = 1,
	WATER = 2,
	FOREST = 3,
	ROCK = 4,
	FARM = 5,
	HOUSE = 6,
	ERASER = 7,
	EXIT = 8,
	LOOK = 9,
	HELP = 10,
	FARM_BUILDING = 11,
	# APPENDED, habitat-tiers Task 8b — never insert, see this enum's own header above.
	GRASS_FAMILY = 12,
}

## Palette option id -> glyph. Lives here rather than on `GameHud` because `HabitatRecipe`
## needs the same mapping to render a recipe chip, and two copies would silently diverge the
## first time a terrain is added.
const KIND_BY_ID: Dictionary = {
	"wild_grass": Kind.WILD_GRASS,
	"grass": Kind.GRASS,
	"water": Kind.WATER,
	"forest": Kind.FOREST,
	"rock": Kind.ROCK,
	"cultivated_field": Kind.FARM,
	"house": Kind.HOUSE,
	# The hotbar's Farm Building GROUP key, not a placeable id — that button's `icon_id` is
	# whichever member is currently the default (barn, silo, well...), and mapping eight
	# separate ids to one barn silhouette would claim each of them looks like a barn. The
	# group key earns one shared glyph instead; `GameHud._add_palette_button()` falls back to
	# it when the resolved member has no glyph of its own.
	"farm_building": Kind.FARM_BUILDING,
	# The hotbar's grass-family TERRAIN GROUP key (habitat-tiers Task 8b), same fallback role
	# as "farm_building" immediately above: `grass`/`wild_grass` already have their own glyphs
	# and keep using them when resolved as the group's current default, but `meadow`/`scrub`
	# have none of their own — without this fallback entry, the button would render with NO
	# glyph at all whenever one of those two is the resolved default (the exact "Barn button
	# looks blank" bug `_icon_kind_for()`'s own comment already documents for Farm Building).
	"grass_family": Kind.GRASS_FAMILY,
}


## The glyph for `id`, or `null` when nothing is mapped — callers decide whether a missing
## glyph is a chip without an icon or a skipped row.
static func kind_for_id(id: String) -> Variant:
	return KIND_BY_ID.get(id, null)


@export var kind: Kind = Kind.GRASS

## Mirrors the parent button's selected state (`GameHud._refresh_palette_rendering()` sets
## this alongside `UiPalette.paint_button()`) — Leave's Exit "X" never sets it, so it stays
## false there and the glyph stays `BARK`, matching that button's own unselected style.
@export var active: bool = false:
	set(value):
		active = value
		queue_redraw()

const THICKNESS: float = 3.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ink() -> Color:
	return UiPalette.CREAM if active else UiPalette.BARK


func _draw() -> void:
	var ink: Color = _ink()
	var c: Vector2 = size * 0.5
	match kind:
		Kind.WILD_GRASS:
			_draw_grass(ink, c, 3, 12.0)
		Kind.GRASS:
			_draw_grass(ink, c, 5, 15.0)
		Kind.WATER:
			_draw_water(ink, c)
		Kind.FOREST:
			_draw_forest(ink, c)
		Kind.ROCK:
			_draw_rock(ink, c)
		Kind.FARM:
			_draw_farm(ink, c)
		Kind.HOUSE:
			_draw_house(ink, c)
		Kind.FARM_BUILDING:
			_draw_farm_building(ink, c)
		Kind.GRASS_FAMILY:
			_draw_grass_family(ink, c)
		Kind.ERASER:
			_draw_eraser(ink, c)
		Kind.EXIT:
			_draw_exit(ink, c)
		Kind.LOOK:
			_draw_look(ink, c)
		Kind.HELP:
			_draw_help(ink, c)


## `blade_count` blades fanned evenly across a baseline, each a short bent line. Wild grass
## uses fewer, uneven-height blades than Grass — "untended" reads as sparser, not a different
## color (see the monochrome note above).
func _draw_grass(ink: Color, c: Vector2, blade_count: int, height: float) -> void:
	var span: float = 22.0
	for i in blade_count:
		var t: float = (float(i) / float(blade_count - 1)) - 0.5 if blade_count > 1 else 0.0
		var base: Vector2 = c + Vector2(t * span, 10.0)
		var lean: float = t * 6.0
		var tip: Vector2 = base + Vector2(lean, -height)
		var bend: Vector2 = base + Vector2(lean * 0.5, -height * 0.55)
		draw_polyline(PackedVector2Array([base, bend, tip]), ink, THICKNESS, true)


## A bold FILLED droplet — a circle plus a triangle sharing its widest diameter as a base,
## reading unambiguously as "water" even at icon size. REPLACES a thin-wavy-line version
## (playtest: "no icon" — three hairline waves were too faint to register at 72px).
func _draw_water(ink: Color, c: Vector2) -> void:
	var centre: Vector2 = c + Vector2(0.0, 6.0)
	var radius: float = 12.0
	draw_circle(centre, radius, ink)
	var top := PackedVector2Array([
		c + Vector2(0.0, -16.0),
		centre + Vector2(-radius, 0.0),
		centre + Vector2(radius, 0.0),
	])
	draw_colored_polygon(top, ink)


func _draw_forest(ink: Color, c: Vector2) -> void:
	var trunk_top: Vector2 = c + Vector2(0.0, 6.0)
	var trunk_bottom: Vector2 = c + Vector2(0.0, 16.0)
	draw_line(trunk_top, trunk_bottom, ink, THICKNESS, true)
	var canopy := PackedVector2Array([
		c + Vector2(0.0, -18.0),
		c + Vector2(14.0, 8.0),
		c + Vector2(-14.0, 8.0),
	])
	draw_colored_polygon(canopy, ink)


## Three overlapping filled circles read as a boulder cluster at this size — no outline
## needed, the overlap alone reads as one irregular rock shape.
func _draw_rock(ink: Color, c: Vector2) -> void:
	draw_circle(c + Vector2(-6.0, 4.0), 10.0, ink)
	draw_circle(c + Vector2(7.0, 5.0), 8.0, ink)
	draw_circle(c + Vector2(0.0, -4.0), 9.0, ink)


## Three bold FILLED furrow rows plus small filled sprout triangles above the top one.
## REPLACES a thin-line version (playtest: "no icon" — hairline furrows plus 6px ticks were
## too faint to register at 72px, same failure as the original Water glyph).
func _draw_farm(ink: Color, c: Vector2) -> void:
	var row_width: float = 30.0
	var row_height: float = 5.0
	# Furrows sit BELOW centre and the sprouts occupy the space above them — the glyph as a
	# whole is centred, but its filled mass is not, so the rows start at centre rather than
	# above it (without this the top sprout clipped the icon rect's top edge).
	for row in 3:
		var y: float = c.y - 5.0 + float(row) * 10.0
		draw_rect(
			Rect2(Vector2(c.x - row_width * 0.5, y - row_height * 0.5), Vector2(row_width, row_height)),
			ink
		)
	for i in 3:
		var x: float = c.x - 10.0 + float(i) * 10.0
		var base_y: float = c.y - 10.0
		var sprout := PackedVector2Array([
			Vector2(x, base_y - 7.0),
			Vector2(x - 3.0, base_y),
			Vector2(x + 3.0, base_y),
		])
		draw_colored_polygon(sprout, ink)


## Hollow walls (so a filled door reads against them) plus a filled roof triangle.
func _draw_house(ink: Color, c: Vector2) -> void:
	var wall_top: float = c.y - 2.0
	var wall_bottom: float = c.y + 16.0
	var wall_left: float = c.x - 13.0
	var wall_right: float = c.x + 13.0
	draw_rect(Rect2(Vector2(wall_left, wall_top), Vector2(wall_right - wall_left, wall_bottom - wall_top)),
		ink, false, THICKNESS * 0.8)
	var roof := PackedVector2Array([
		Vector2(c.x, c.y - 18.0),
		Vector2(wall_right + 4.0, wall_top + 2.0),
		Vector2(wall_left - 4.0, wall_top + 2.0),
	])
	draw_colored_polygon(roof, ink)
	draw_rect(Rect2(Vector2(c.x - 3.0, wall_bottom - 8.0), Vector2(6.0, 8.0)), ink)


## A barn — the Farm Building group's glyph. Deliberately NOT a second cottage: a gambrel
## (two-slope) roof that overhangs the walls, and one wide double door with a centre split,
## are what separate it from `_draw_house()`'s pitched roof and single narrow door at 72px.
func _draw_farm_building(ink: Color, c: Vector2) -> void:
	var wall_top: float = c.y - 1.0
	var wall_bottom: float = c.y + 16.0
	var wall_left: float = c.x - 14.0
	var wall_right: float = c.x + 14.0
	draw_rect(Rect2(Vector2(wall_left, wall_top), Vector2(wall_right - wall_left, wall_bottom - wall_top)),
		ink, false, THICKNESS * 0.8)
	var roof := PackedVector2Array([
		Vector2(wall_left - 3.0, wall_top + 1.0),
		Vector2(wall_left + 1.0, c.y - 11.0),
		Vector2(c.x, c.y - 17.0),
		Vector2(wall_right - 1.0, c.y - 11.0),
		Vector2(wall_right + 3.0, wall_top + 1.0),
	])
	draw_colored_polygon(roof, ink)
	var door_top: float = wall_bottom - 11.0
	draw_rect(Rect2(Vector2(c.x - 7.0, door_top), Vector2(14.0, 11.0)), ink, false, THICKNESS * 0.6)
	draw_line(Vector2(c.x, door_top), Vector2(c.x, wall_bottom), ink, THICKNESS * 0.6, true)


## The grass-family TERRAIN GROUP's glyph (habitat-tiers Task 8b) — shown when the button's
## resolved default is `meadow` or `scrub`, neither of which has a glyph of its own (see
## `KIND_BY_ID`'s own comment for the fallback mechanism). A shorter grass fan than GRASS's own
## (reads as "some kind of grass", not a specific one) plus a small filled flower — meadow's
## own defining feature (`flowers` habitat tag) — is what separates this from both GRASS and
## WILD_GRASS at a glance, the same "distinguish by silhouette, not colour" rule every other
## glyph here follows (see this file's own monochrome note).
func _draw_grass_family(ink: Color, c: Vector2) -> void:
	_draw_grass(ink, c, 3, 12.0)
	var petal_centre: Vector2 = c + Vector2(9.0, -10.0)
	var petal_radius: float = 3.2
	for i in 5:
		var angle: float = TAU * float(i) / 5.0
		draw_circle(petal_centre + Vector2(petal_radius, 0.0).rotated(angle), petal_radius, ink)
	draw_circle(petal_centre, petal_radius * 0.7, ink)


## A plain outlined block with one divider line — the classic two-tone eraser silhouette,
## in one ink color per the monochrome note above.
func _draw_eraser(ink: Color, c: Vector2) -> void:
	var rect := Rect2(c + Vector2(-14.0, -9.0), Vector2(28.0, 18.0))
	draw_rect(rect, ink, false, THICKNESS * 0.8)
	draw_line(c + Vector2(-14.0, 1.0), c + Vector2(14.0, 1.0), ink, THICKNESS * 0.6, true)


func _draw_exit(ink: Color, c: Vector2) -> void:
	var arm: float = 12.0
	draw_line(c + Vector2(-arm, -arm), c + Vector2(arm, arm), ink, THICKNESS, true)
	draw_line(c + Vector2(-arm, arm), c + Vector2(arm, -arm), ink, THICKNESS, true)


## A plain diagonal arrow (shaft + arrowhead), the same wing-rotation technique
## `rotate_icon.gd` already uses for its arrowheads — the Inspect/"Look" button's glyph.
func _draw_look(ink: Color, c: Vector2) -> void:
	var tail: Vector2 = c + Vector2(-11.0, 11.0)
	var tip: Vector2 = c + Vector2(11.0, -11.0)
	draw_line(tail, tip, ink, THICKNESS, true)
	var back: Vector2 = (tail - tip).normalized()
	var wing_angle: float = deg_to_rad(28.0)
	var wing_a: Vector2 = tip + back.rotated(wing_angle) * 8.0
	var wing_b: Vector2 = tip + back.rotated(-wing_angle) * 8.0
	draw_line(tip, wing_a, ink, THICKNESS, true)
	draw_line(tip, wing_b, ink, THICKNESS, true)


## A question mark — the hook, then the dot. Same vector technique as EXIT and LOOK, so this
## costs no art import and follows the same ink flip as every other glyph.
func _draw_help(ink: Color, c: Vector2) -> void:
	var r: float = minf(size.x, size.y) * 0.18
	draw_arc(c + Vector2(0.0, -r * 1.4), r, PI, TAU + PI * 0.35, 24, ink, THICKNESS, true)
	draw_line(c + Vector2(0.0, -r * 0.1), c + Vector2(0.0, r * 0.8), ink, THICKNESS, true)
	draw_circle(c + Vector2(0.0, r * 1.8), THICKNESS * 0.7, ink)
