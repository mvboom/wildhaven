extends QATestCase
## FOREST VARIETY IS STAMPED STATE, NOT A RENDER-TIME MODE (-> D-58).
##
## THIS SUITE HAS OUTLIVED TWO DESIGNS AND THE CLAIM IT DEFENDS HAS NEVER CHANGED: a forest
## should not be one tree repeated across the whole map. What changed twice is HOW.
##
##   1. Originally every forest tile rendered CommonTree1, because `get_style_default()` never
##      returns "" — an unchosen category degrades to `valid_ids[0]`, so "unchosen" collapsed
##      onto "chose the first one" and `pick_variant()` was unreachable.
##   2. D-54 answered that with `mixed`: a style id that resolved to no scene, so the
##      `pick_variant()` fallback ran. That made a style a MODE — the player picked a tree and
##      the world kept showing an assortment — and it was rejected on sight once visible.
##   3. D-58 retired `mixed`. A new world now stamps a randomly-chosen CONCRETE style onto every
##      forest tile at generation (`WorldRoot._randomise_initial_styles()`), and after that a
##      style is purely a brush: you pick what to put down and what you put down stays (D-57).
##
## The difference that matters, and what this suite is really pinning: variety is now STORED. A
## tile holds a real style id it keeps forever, rather than a marker meaning "re-roll me every
## time you draw me". That is what makes a painted tree stay put and what makes the starting
## map's variety survive a save.
##
## A REAL `"new"` INTENT IS REQUIRED. `_randomise_initial_styles()` is gated on `is_new_world`,
## the same D-53 gate the terrain mix uses, so a bare `Main.tscn` instantiation (mode "none",
## which is every other suite and an editor F6) correctly stamps nothing. This suite therefore
## goes through `GameSession.request_new()` exactly as the menu does.
##
## Run:
##   bash scripts/run-tests.sh forest_variant_variety

const WORLD_PATH: String = "res://scenes/Main.tscn"
const PRESET_ID: String = "forested_start"
const SETTLE_FRAMES: int = 3
const SEED: int = 20260908
const NO_SAVE_PATH: String = ""

var _packed: PackedScene = null
var _preset_res: WorldPreset = null
var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("forest variant variety")
	_packed = load(WORLD_PATH) as PackedScene
	if not check(_packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	_preset_res = _preset(PRESET_ID)
	if not check(_preset_res != null, "the `%s` preset is on disk" % PRESET_ID):
		finish()
		return
	GameSession.request_new(_preset_res, "Variety", NO_SAVE_PATH, SEED)
	_world = _spawn()
	_setup_ok = _world != null
	if not _setup_ok:
		finish()


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false

	var forest: TerrainDefinition = _world.grid.terrain_definition("forest")
	if not check(forest != null, "the forest terrain is loaded"):
		finish()
		return true
	if not check(forest.model_scenes.size() > 1, "forest ships more than one model_scenes entry"):
		finish()
		return true

	_check_mixed_is_gone()
	_check_a_new_world_stamps_varied_concrete_styles()
	_check_the_same_seed_reproduces_the_same_styles()
	_check_a_chosen_style_governs_new_paint_only()

	finish()
	return true


## `mixed` is retired, not merely demoted. Asserted on the catalog rather than on a constant,
## because the constant itself is gone — a test naming it would not compile.
func _check_mixed_is_gone() -> void:
	var ids: PackedStringArray = _world.style_ids_for_category("forest")
	check(not ids.has("mixed"), "`mixed` is absent from the forest catalog entirely")
	check(ids.size() >= 2, "...and the catalog is still the real trees (%d of them)" % ids.size())
	for id: String in ids:
		if not check(_world.resolve_style_scene_id("forest", id) != null,
				"every catalog id resolves to a real scene — `%s`" % id):
			return


## THE CLAIM: a freshly generated world's forest is varied, AND every one of those tiles holds a
## concrete style id rather than the absence that used to stand in for variety.
func _check_a_new_world_stamps_varied_concrete_styles() -> void:
	var seen: Dictionary = {}
	var forest_tiles: int = 0
	var unstamped: int = 0
	for x in _world.grid.width:
		for z in _world.grid.depth:
			if _world.grid.get_terrain_id(x, z) != "forest":
				continue
			forest_tiles += 1
			var style: String = _world.grid.get_tile_style(x, z)
			if style.is_empty():
				unstamped += 1
			else:
				seen[style] = true
	if not check(forest_tiles > 0, "setup: the `forested` preset generated forest tiles (%d)"
			% forest_tiles):
		return
	check_eq(unstamped, 0,
		"every forest tile on a new map carries a CONCRETE style (%d of %d had none)"
			% [unstamped, forest_tiles])
	check(seen.size() > 1,
		"...and they are not all the same one (%d distinct styles across %d tiles)"
			% [seen.size(), forest_tiles],
		"1 distinct style is the original bug: a forest of one repeated tree")
	# Stamped ids must be real catalog entries, or they would silently fall through to
	# `pick_variant()` and the stamping would be doing nothing while appearing to work.
	var catalog: PackedStringArray = _world.style_ids_for_category("forest")
	var bogus: String = ""
	for style: String in seen:
		if not catalog.has(style):
			bogus = style
	check_eq(bogus, "", "every stamped style is a real catalog id")


## Determinism: the same seed must rebuild the same world, which is the guarantee `MistReveal`
## and the terrain mix already keep. Without it a save's stored styles and a regenerated
## world would drift apart.
func _check_the_same_seed_reproduces_the_same_styles() -> void:
	var first: Dictionary = {}
	for x in _world.grid.width:
		for z in _world.grid.depth:
			if _world.grid.get_terrain_id(x, z) == "forest":
				first[Vector2i(x, z)] = _world.grid.get_tile_style(x, z)

	_world.queue_free()
	_world = null
	GameSession.request_new(_preset_res, "Variety Again", NO_SAVE_PATH, SEED)
	var again: WorldRoot = _spawn()
	if not check(again != null, "a second world spawns on the same seed"):
		return
	# `_ready()` has run synchronously enough for the grid by the time `_spawn()` returns in
	# every other suite that does this; the styles are stamped inside `_ready()` itself.
	var mismatches: int = 0
	var compared: int = 0
	for tile: Vector2i in first:
		if not again.grid.in_bounds(tile.x, tile.y):
			continue
		compared += 1
		if again.grid.get_tile_style(tile.x, tile.y) != first[tile]:
			mismatches += 1
	check(compared > 0, "setup: there are tiles to compare (%d)" % compared)
	check_eq(mismatches, 0,
		"the same seed stamps the same styles (%d of %d tiles differed)" % [mismatches, compared])
	_world = again


## The brush contract (D-57), re-asserted here against a stamped world: choosing a style changes
## what the NEXT paint puts down and has no authority over ground already generated.
func _check_a_chosen_style_governs_new_paint_only() -> void:
	var before: Dictionary = {}
	for x in _world.grid.width:
		for z in _world.grid.depth:
			if _world.grid.get_terrain_id(x, z) == "forest":
				before[Vector2i(x, z)] = _world.grid.get_tile_style(x, z)

	_world.set_style_default("forest", "twisted_tree_1")
	var changed: int = 0
	for tile: Vector2i in before:
		if _world.grid.get_tile_style(tile.x, tile.y) != before[tile]:
			changed += 1
	check_eq(changed, 0,
		"choosing a style leaves every already-generated forest tile alone (%d changed)" % changed)

	# ...and a tile painted afterwards is exactly that choice.
	var target := Vector2i(-1, -1)
	for x in _world.grid.width:
		for z in _world.grid.depth:
			if _world.grid.get_terrain_id(x, z) != "forest" and not _world.grid.is_occupied(x, z):
				target = Vector2i(x, z)
				break
		if target.x >= 0:
			break
	if not check(target.x >= 0, "setup: a non-forest tile exists to paint"):
		return
	if not check(_world.paint_tile(target.x, target.y, "forest"), "it paints to forest"):
		return
	check_eq(_world.grid.get_tile_style(target.x, target.y), "twisted_tree_1",
		"a tile painted after the choice carries exactly that style — no re-rolling")


func _preset(id: String) -> WorldPreset:
	for preset: WorldPreset in WorldPreset.load_all():
		if preset.id == id:
			return preset
	return null


func _spawn() -> WorldRoot:
	var node: Node = _packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		if node != null:
			node.free()
		return null
	var world: WorldRoot = node as WorldRoot
	root.add_child(world)
	return world
