extends QATestCase
## FOREST TILES MUST SHOW MORE THAN ONE TREE — the defect this suite was written against.
##
## THE BUG (reported 2026-09-08, found while looking at a Forested start): every forest tile in
## the world rendered CommonTree1. `forest.tres` ships EIGHT `model_scenes` — six trees plus
## Bush and BushBerries — and `TerrainDefinition.pick_variant()` hashes `(x, z, id)` to spread
## them across tiles (D-42), but that function was never reached.
##
## THE ROOT CAUSE, which is an interaction and not a broken function. `TerrainChunkLod.
## _resolve_variant()` routes the two picker categories (forest, wild_grass) through
## `WorldRoot.resolve_style_scene()` and falls back to `pick_variant()` only when that returns
## null. `resolve_style_scene()` asks `get_style_default()`, whose documented contract is that
## it NEVER returns "" — a category with no stored choice degrades to `valid_ids[0]`. So on a
## brand-new world, with the player having chosen nothing, forest resolved to the first
## catalog entry, every tile, and the `pick_variant()` fallback was unreachable code.
##
## Both halves were behaving as written. What was missing was a way to say *"no single tree —
## mix them"*, so "unchosen" collapsed onto "chose the first one".
##
## THE FIX: `WorldRoot.MIXED_STYLE_ID`, a real style id that leads the catalog for any picker
## category with more than one scene. It resolves to no scene, so `resolve_style_scene()`
## returns null by design and the `pick_variant()` fallback runs. `get_style_default()` is
## untouched — its "first catalog entry" rule now lands on `mixed`.
##
## Run:
##   bash scripts/run-tests.sh forest_variant_variety

const WORLD_PATH: String = "res://scenes/Main.tscn"
const SETTLE_FRAMES: int = 3

## Enough tiles that eight variants appearing only once each would still be overwhelming
## evidence of variety, and few enough to stay a cheap loop.
const SAMPLE: int = 400

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("forest variant variety")
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
	if _frames < SETTLE_FRAMES:
		return false

	var forest: TerrainDefinition = _world.grid.terrain_definition("forest")
	if not check(forest != null, "the forest terrain is loaded"):
		finish()
		return true
	if not check(forest.model_scenes.size() > 1, "forest ships more than one model_scenes entry"):
		finish()
		return true

	# --- The unchosen default is `mixed`, not a specific tree ------------------------------
	# This is the assertion that actually failed before the fix: it returned "common_tree_1".
	check_eq(
		_world.get_style_default("forest"),
		WorldRoot.MIXED_STYLE_ID,
		"a brand-new world's forest style is `mixed`, not the first tree in the catalog"
	)
	check(
		_world.resolve_style_scene("forest") == null,
		"`mixed` resolves to NO scene, which is what lets pick_variant() run",
		"a non-null here means every forest tile renders the same model again"
	)

	# --- ...and the tiles therefore differ -------------------------------------------------
	# Asserted through the same call TerrainChunkLod._resolve_variant() makes, so this measures
	# what the world actually renders rather than what pick_variant() would do in isolation.
	var seen: Dictionary = {}
	for i in SAMPLE:
		var x: int = i % _world.grid.width
		var z: int = i / _world.grid.width
		var scene: PackedScene = _resolve_as_the_view_does(forest, x, z)
		if scene != null:
			seen[scene.resource_path] = true
	check(
		seen.size() > 1,
		"forest tiles across the map show more than one model (%d distinct)" % seen.size(),
		"THE REPORTED BUG: one distinct model means every tree in the world is identical"
	)
	check_eq(
		seen.size(),
		forest.model_scenes.size(),
		"every one of forest's shipped variants appears somewhere in %d tiles" % SAMPLE
	)

	# --- An explicit choice still wins ------------------------------------------------------
	# The fix must not cost the player the picker. Choosing one tree still means one tree.
	_world.set_style_default("forest", "pine_tree")
	var chosen: PackedScene = _world.resolve_style_scene("forest")
	if check(chosen != null, "an explicitly chosen style still resolves to a scene"):
		check(
			chosen.resource_path.contains("PineTree"),
			"the chosen style is the one the player picked"
		)
	var uniform: Dictionary = {}
	for i in SAMPLE:
		var x: int = i % _world.grid.width
		var z: int = i / _world.grid.width
		var scene: PackedScene = _resolve_as_the_view_does(forest, x, z)
		if scene != null:
			uniform[scene.resource_path] = true
	check_eq(uniform.size(), 1, "with a style chosen, every forest tile shows that one model")

	# And `mixed` is reachable again — without this the picker is a one-way door.
	_world.set_style_default("forest", WorldRoot.MIXED_STYLE_ID)
	check(
		_world.resolve_style_scene("forest") == null,
		"the player can choose `mixed` back again after picking a specific tree"
	)

	# --- Wild grass is deliberately untouched ------------------------------------------------
	# It ships a single model_scenes entry, so there is nothing to mix and no `mixed` row is
	# offered. Its unchosen default stays the shipped id, exactly as test_style_defaults.gd
	# has always asserted.
	var wild: TerrainDefinition = _world.grid.terrain_definition("wild_grass")
	if check(wild != null, "the wild grass terrain is loaded"):
		if wild.model_scenes.size() == 1:
			check_eq(
				_world.get_style_default("wild_grass"),
				"wild_grass",
				"a single-variant category is NOT given a `mixed` row"
			)

	root.remove_child(_world)
	_world.free()
	finish()
	return true


## The exact resolution order `TerrainChunkLod._resolve_variant()` uses for a picker category:
## the chosen style first, `pick_variant()` when that resolves to nothing. Mirrored rather than
## called because that method is private to a node this suite does not build — if the two ever
## diverge, the divergence is the bug and this comment is where to start.
func _resolve_as_the_view_does(terrain: TerrainDefinition, x: int, z: int) -> PackedScene:
	var resolved: PackedScene = _world.resolve_style_scene(terrain.id)
	return resolved if resolved != null else terrain.pick_variant(x, z)
