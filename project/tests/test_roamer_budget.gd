extends QATestCase
## THE ROAMER BUDGET MUST THROTTLE, NEVER PERMANENTLY FREEZE ANYONE.
##
## `ResidentPresentation.ROAMER_BUDGET` (gdd.md -> Level & world design: "The global roamer
## budget scales with revealed world size as a pure performance backstop, not a design
## tool... a budget that binds regularly in playtest means capacity is tuned too rich.")
## caps how many roamers get `tick()`ed in a single frame. Before this suite existed, that
## cap was applied to a FIXED PREFIX of `_roamers` (array order == arrival order) every
## single frame — so once the world holds more residents than the budget, everyone at index
## `ROAMER_BUDGET` or later never gets ticked again, ever. They stand exactly where they
## spawned (their own home/den tile) for the rest of the game, which reads to a player as
## "this animal is stuck at its den" — indistinguishable from a pathing bug, but nothing to
## do with pathing at all.
##
## THE FIX IS FAIRNESS, NOT A NEW NUMBER. `ROAMER_BUDGET` itself is the human's tuning call
## (ground rules: "All tuning values are the human's") and this suite does not touch it or
## assert a specific value. What it asserts is that the SAME set is never favored forever:
## the ticked window rotates frame to frame, so over enough frames every live roamer gets a
## turn, budget or no budget.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_roamer_budget.gd

const STEP_SECONDS: float = 0.1
## Comfortably more residents than `ResidentPresentation.ROAMER_BUDGET`, so this suite fails
## loudly if the constant is ever lowered without re-checking this file too.
const RESIDENT_COUNT: int = 300
## Enough ticks that, even throttled to `ROAMER_BUDGET` turns per frame, every resident gets
## several turns; each turn can walk up to `WALK_SPEED_TILES_PER_SECOND * STEP_SECONDS`.
const TICK_COUNT: int = 3000
## A resident that is genuinely being ticked covers real ground well past this within
## `TICK_COUNT` ticks even throttled — small enough that a single still-mid-pause cycle at
## the cutoff can't fail it, since that costs at most `PAUSE_MAX_SECONDS` of real movement-free
## time, a tiny fraction of `TICK_COUNT * STEP_SECONDS` (300 simulated seconds).
const MIN_PATH_LENGTH_TILES: float = 0.5

var _grid: WorldGrid = null
var _presentation: ResidentPresentation = null
var _registry: HomeSiteRegistry = null
var _residents: Array = []  # {node: Node3D, start: Vector3}


func _initialize() -> void:
	begin("roamer budget fairness")

	_grid = WorldGrid.new()
	_grid.name = "WorldGrid"
	_grid.build(TerrainDefinition.load_all(), 96, 96)
	root.add_child(_grid)

	var props_root := Node3D.new()
	props_root.name = "HomeProps"
	root.add_child(props_root)

	_presentation = ResidentPresentation.new()
	_presentation.attach(_grid, props_root, 20260825)

	_registry = HomeSiteRegistry.new()
	# Spread one-resident home sites across the grid so nobody boxes anybody in — this suite
	# is about tick fairness, not obstacle avoidance (test_resident_navigation.gd owns that).
	var i := 0
	var x := 2
	while i < RESIDENT_COUNT and x < 94:
		var z := 2
		while i < RESIDENT_COUNT and z < 94:
			var pos := Vector2i(x, z)
			var site: HomeSite = _registry.register(pos, "rabbit", 8)
			var node := Node3D.new()
			node.position = _grid.tile_to_world(pos.x, pos.y)
			root.add_child(node)
			_presentation.present(node, site)
			_residents.append({"node": node, "start": node.position})
			i += 1
			z += 3
		x += 3

	if not check(_residents.size() == RESIDENT_COUNT,
			"spawned %d residents (%d requested)" % [_residents.size(), RESIDENT_COUNT]):
		finish()
		return
	if not check(RESIDENT_COUNT > ResidentPresentation.ROAMER_BUDGET,
			"this suite's resident count (%d) really does exceed ROAMER_BUDGET (%d) — otherwise "
			% [RESIDENT_COUNT, ResidentPresentation.ROAMER_BUDGET]
			+ "the fairness claim below would be vacuous"):
		finish()
		return

	_setup_ok = true


var _setup_ok: bool = false
var _frames: int = 0


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 2:
		return false

	_check_nobody_is_permanently_frozen()

	_presentation.free()
	_presentation = null
	finish()
	return true


## NET DISPLACEMENT FROM SPAWN IS THE WRONG METRIC HERE: each resident's wander disc is only
## `WANDER_RADIUS_TILES` (3 tiles) across and never grows, so a genuinely-ticking resident's
## bounded random walk can, by pure chance, land back within a hair of its exact spawn point
## at whatever tick this suite happens to stop on — that is recurrence, not starvation, and an
## earlier version of this check flagged it as a false "never moved" failure. CUMULATIVE PATH
## LENGTH (summed step-to-step distance, never resets) is what actually distinguishes "ticked
## fairly, wandering normally" from "never advanced its own clock" — confirmed against a
## roamer pulled out of a real failure of the OLD check: single-stepped by hand, it was simply
## mid-pause at the cutoff and walked at exactly `WALK_SPEED_TILES_PER_SECOND` once its pause
## ended, i.e. working correctly the whole time.
func _check_nobody_is_permanently_frozen() -> void:
	var path_length: Dictionary = {}  # Node3D -> float
	var previous: Dictionary = {}  # Node3D -> Vector3
	for entry: Dictionary in _residents:
		var node: Node3D = entry["node"]
		path_length[node] = 0.0
		previous[node] = node.position

	for _i in TICK_COUNT:
		_presentation.tick(STEP_SECONDS)
		for entry: Dictionary in _residents:
			var node: Node3D = entry["node"]
			var prev: Vector3 = previous[node]
			path_length[node] = (path_length[node] as float) + prev.distance_to(node.position)
			previous[node] = node.position

	var frozen: Array = []
	for entry: Dictionary in _residents:
		var node: Node3D = entry["node"]
		if (path_length[node] as float) < MIN_PATH_LENGTH_TILES:
			frozen.append(node.name)

	check(frozen.is_empty(),
		"EVERY resident covered real ground (>= %.1f tiles cumulative) over %d ticks — the "
			% [MIN_PATH_LENGTH_TILES, TICK_COUNT]
		+ "budget throttles, it does not permanently freeze whoever arrived last (%d of %d "
			% [frozen.size(), _residents.size()] + "never moved: %s)" % [frozen.slice(0, 8)])
