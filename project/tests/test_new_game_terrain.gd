extends QATestCase
## THE PRESET-MIX GATE, driven end to end through the real New Game path — D-53.
##
## `test_terrain_scatter.gd` proves the generator and `WorldGrid.build()` are correct;
## `test_world_preset.gd` proves the shipped `.tres` files are well formed. Neither touches
## the one line that decides whether any of it happens:
##
##     var mix := preset.terrain_mix if (is_new_world and preset != null) else {}
##
## in `WorldRoot._ready()`. That gate carries the whole blast radius of D-53 in both
## directions, and BOTH directions are silent failures:
##
##   * Gate stuck OPEN — every one of this project's suites instantiates `Main.tscn` with no
##     intent, falls through to `WorldPreset.default_preset()` (which is `meadow_start`, which
##     now carries a mix), and would silently start on 40% meadow. Habitat, capacity and
##     economy assertions across the suite would shift under worlds nobody asked to change.
##   * Gate stuck SHUT — New Game builds tag-inert wild grass whatever card the player picked,
##     which is exactly the pre-D-53 behaviour the ruling exists to end, and every other test
##     in this feature still passes.
##
## So this suite asserts the gate from both sides, in one process, in that order.
##
## Run:
##   bash scripts/run-tests.sh new_game_terrain

const WORLD_PATH: String = "res://scenes/Main.tscn"

## Forested, not Meadow Start: its 60% forest is the largest single share any shipped preset
## declares, so a mix that silently failed to apply is unmistakable rather than a near miss.
const PRESET_ID: String = "forested_start"

## Non-zero and odd, matching what `NewGameScreen.new_seed()` guarantees — a seed of 0 is a
## sentinel in two other places and is not a value the New Game path can actually produce.
const SEED: int = 20260907 | 1

## EMPTY ON PURPOSE. `save_path` is taken straight from the intent, and `Autosave.attach()`
## writes the instant it attaches — a real path here would leave a save file behind in
## `user://` every time the suite runs. `Autosave.request()` declines on an empty path
## through its existing guard, which is the same state an editor F6 run is in.
const NO_SAVE_PATH: String = ""

## `WorldRoot._ready()` does NOT run at `add_child()` time from `_initialize()` — the main
## loop has not iterated yet, so `world.grid` is still null. Every suite in this project that
## instantiates `Main.tscn` waits frames for the same reason; this one waits between its two
## phases as well, because the second world is added after the first is freed.
const SETTLE_FRAMES: int = 3

var _packed: PackedScene = null
var _preset_res: WorldPreset = null
var _world: WorldRoot = null
var _phase: int = 0
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("new game terrain mix gate")

	_packed = load(WORLD_PATH) as PackedScene
	if not check(_packed != null, "%s loads" % WORLD_PATH):
		finish()
		return

	_preset_res = _preset(PRESET_ID)
	if not check(_preset_res != null, "the `%s` preset is on disk" % PRESET_ID):
		finish()
		return
	if not check(not _preset_res.terrain_mix.is_empty(), "`%s` carries a terrain mix" % PRESET_ID):
		finish()
		return

	# --- Gate OPEN: a real "new" intent gets the mix --------------------------------------
	GameSession.request_new(_preset_res, "Mix Gate", NO_SAVE_PATH, SEED)
	_world = _spawn(_packed)
	_setup_ok = _world != null
	if not _setup_ok:
		finish()


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	if _phase == 0:
		return _check_new_world()
	return _check_intentless_world()


## Gate OPEN. A real `"new"` intent must produce the preset's mix, exactly.
func _check_new_world() -> bool:
	var world: WorldRoot = _world
	var preset: WorldPreset = _preset_res
	if not check(world.grid != null, "the new world built a grid"):
		finish()
		return true

	check(world.is_new_world, "the `new` intent reached WorldRoot")
	var counts: Dictionary = _tally(world.grid)

	# The mix is applied, and applied EXACTLY — the same quota the generator would produce for
	# this preset's own dimensions, not merely "some forest showed up".
	var quotas: Dictionary = TerrainScatter.quotas(preset.terrain_mix, preset.width * preset.depth)
	for id: String in quotas:
		check_eq(
			int(counts.get(id, 0)),
			int(quotas[id]),
			"a New Game world holds exactly the `%s` quota" % id
		)

	# The derived index the economy reads, through the real construction path rather than a
	# hand-built grid — `_forest_tile_count` is maintained incrementally and never recomputed.
	check_eq(
		world.grid.forest_tile_count(),
		int(quotas.get("forest", -1)),
		"forest_tile_count() agrees with the world that was actually built"
	)

	# Navigation is rebuilt from the grid AFTER build() in `_ready()`. With 60% of the map
	# blocking movement that ordering stops being incidental: a navmesh built before the mix
	# would describe a world of open grass that no longer exists.
	check(world.navigation != null, "navigation exists on a mixed world")

	# Determinism, through the scene rather than the function: the seed the New Game screen
	# drew is what the world is made of, so the same seed must rebuild the same land.
	var expected: PackedStringArray = TerrainScatter.generate(
		preset.terrain_mix, preset.width, preset.depth, SEED
	)
	var matches: bool = true
	for x in world.grid.width:
		for z in world.grid.depth:
			if world.grid.get_terrain_id(x, z) != expected[x * world.grid.depth + z]:
				matches = false
	check(matches, "the built world is exactly what the world seed generates")

	_despawn(world)

	# --- Gate SHUT: no intent stays on the pre-D-53 world ----------------------------------
	# This is the path every other suite in the project takes. `GameSession.consume()` was
	# emptied by the world
	# above, so this instantiation sees mode "none" exactly as an editor F6 does — and
	# resolves to `meadow_start`, the preset that DOES carry a mix. That is the whole point:
	# the gate, not the absence of a mix, is what keeps this world plain.
	_world = _spawn(_packed)
	if _world == null:
		finish()
		return true
	_phase = 1
	_frames = 0
	return false


func _check_intentless_world() -> bool:
	var plain: WorldRoot = _world
	if not check(plain.grid != null, "the intentless world built a grid"):
		finish()
		return true

	check(not plain.is_new_world, "an intentless world is not a `new` world")
	var plain_counts: Dictionary = _tally(plain.grid)
	check_eq(plain_counts.size(), 1, "an intentless world is a single terrain")
	check_eq(
		int(plain_counts.get(WorldGrid.START_TERRAIN_ID, 0)),
		plain.grid.width * plain.grid.depth,
		"an intentless world is 100% wild grass — byte-identical to the pre-D-53 default"
	)
	check_eq(plain.grid.forest_tile_count(), 0, "an intentless world has no forest")

	_despawn(plain)

	finish()
	return true


func _preset(preset_id: String) -> WorldPreset:
	for preset: WorldPreset in WorldPreset.load_all():
		if preset.id == preset_id:
			return preset
	return null


## Instantiates `Main.tscn` into the tree. `_ready()` — and therefore the whole world build —
## does not run until the main loop iterates, so the caller must let `SETTLE_FRAMES` pass
## before reading anything off the returned node.
func _spawn(packed: PackedScene) -> WorldRoot:
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		if node != null:
			node.free()
		return null
	var world: WorldRoot = node as WorldRoot
	root.add_child(world)
	return world


## `WorldRoot` keeps a `_instance` singleton it clears in `_exit_tree`, so the first world
## must be fully gone before the second is added or the second would be building against a
## tree that still names the first.
func _despawn(world: WorldRoot) -> void:
	root.remove_child(world)
	world.free()


func _tally(grid: WorldGrid) -> Dictionary:
	var out: Dictionary = {}
	for x in grid.width:
		for z in grid.depth:
			var id: String = grid.get_terrain_id(x, z)
			out[id] = int(out.get(id, 0)) + 1
	return out
