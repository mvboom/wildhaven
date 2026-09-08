extends QATestCase
## THROWAWAY PROBE — not a suite, not a gate, deliberately named so `run-tests.sh`'s
## `test_*.gd` glob skips it. Delete when the question it answers is answered.
##
## QUESTION: does an arrival-caused displacement oscillate? Reported from a real build as a
## deer moving between two spots and back every few seconds, with nobody touching the game.
## The hypothesis from the code read: a home relocates, its VACATED neighbourhood re-qualifies,
## an arrival lands there, the relocated home loses ground again, and it relocates back.
##
## Method: paint a band of habitat, then tick the world for simulated minutes with NO further
## player input at all, logging every relocation with its from/to tiles. If the same site
## bounces between two positions, the log shows it directly.
##
## Run:
##   $GODOT_PATH --headless --path project --script res://tests/probe_oscillation.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"
const SIMULATED_SECONDS: float = 900.0
const STEP: float = 0.25

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false
var _moves: Array[String] = []
var _relocations: int = 0
var _departures: int = 0
var _arrivals: int = 0
var _landed_broken: int = 0
var _landed_ok: int = 0
var _shortfall: Dictionary = {}
var _warn_player: int = 0
var _warn_ambient: int = 0
var _warn_player_after_paint: int = 0
var _paint_done_at: float = -1.0
var _clock: float = 0.0


func _initialize() -> void:
	begin("probe: displacement oscillation")
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var node: Node = packed.instantiate()
	_world = node as WorldRoot
	root.add_child(_world)
	_setup_ok = _world != null


func _process(_delta: float) -> bool:
	if not _setup_ok:
		finish()
		return true
	_frames += 1
	if _frames < 3:
		return false

	_world.resident_relocated.connect(
		func(sid: String, from_tile: Vector2i, to_tile: Vector2i, _p: Vector3) -> void:
			_relocations += 1
			_moves.append("%s %s->%s" % [sid, from_tile, to_tile])
			# THE MEASUREMENT THAT MATTERS: this fires INSIDE `_relocate()`, so the world here is
			# the live post-move state. `_find_relocation()` promised `capacity >= population` at
			# this destination — was that still true by the time the family actually got there?
			var species: AnimalDefinition = _world.roster.by_id(sid)
			if species != null:
				var cap: int = _world.simulation.capacity_at(to_tile, species)
				var pop: int = _world.simulation.population_at(to_tile, species)
				if cap < pop:
					_landed_broken += 1
					var short: int = pop - cap
					_shortfall[short] = int(_shortfall.get(short, 0)) + 1
				else:
					_landed_ok += 1
	)
	_world.resident_departed.connect(
		func(_s: String, _h: Vector2i, _i: int, _p: Vector3) -> void: _departures += 1
	)
	# THE DISCRIMINATING MEASUREMENT: how many warnings arrive flagged player_caused, and how
	# many of those arrive AFTER every gesture the initial paint could have opened has settled?
	# Painting is the only player input in this probe, and it all happens at t=0, so a
	# player-caused warning later than GRACE_WINDOW_SECONDS means the flag is spreading.
	_world.displacement_warned.connect(
		func(w: Dictionary) -> void:
			if bool(w.get("player_caused", false)):
				_warn_player += 1
				if _paint_done_at >= 0.0 and _clock > _paint_done_at + SettlementWindow.GRACE_WINDOW_SECONDS:
					_warn_player_after_paint += 1
			else:
				_warn_ambient += 1
	)
	_world.resident_arrived.connect(
		func(_s: String, _p: Vector3) -> void: _arrivals += 1
	)

	# A band of habitat wide enough for several competing home sites, painted once. This is the
	# ONLY player input in the whole probe. Rabbit's base tier needs BOTH `open_grass` (grass)
	# and `cultivated` (cultivated_field), so the band alternates them.
	_world.wood.add(999999)
	var painted: int = 0
	for x: int in range(6, 30):
		for z: int in range(6, 30):
			var id: String = "grass" if (z % 4) < 2 else "cultivated_field"
			if _world.paint_tile(x, z, id):
				painted += 1
	print("  tiles painted       : %d" % painted)
	print("  wood left           : %d" % _world.get_wood())

	_paint_done_at = 0.0
	var elapsed: float = 0.0
	var bucket_start_reloc: int = 0
	var bucket_start_arr: int = 0
	var buckets: Array[String] = []
	while elapsed < SIMULATED_SECONDS:
		_world.simulation.tick(STEP)
		_world.displacement.tick(STEP)
		elapsed += STEP
		_clock = elapsed
		if int(elapsed) % 60 == 0 and is_equal_approx(elapsed - float(int(elapsed)), 0.0):
			buckets.append("    minute %2d: %4d relocations, %2d arrivals, %d sites" % [
				int(elapsed / 60.0), _relocations - bucket_start_reloc,
				_arrivals - bucket_start_arr, _world.registry.sites().size(),
			])
			bucket_start_reloc = _relocations
			bucket_start_arr = _arrivals
	print("  RELOCATIONS THAT LANDED ALREADY-BROKEN: %d of %d (%.1f%%)" % [
		_landed_broken, _landed_broken + _landed_ok,
		0.0 if (_landed_broken + _landed_ok) == 0
			else 100.0 * float(_landed_broken) / float(_landed_broken + _landed_ok),
	])
	var keys: Array = _shortfall.keys()
	keys.sort()
	for k: Variant in keys:
		print("      short by %d: %d relocations" % [k, _shortfall[k]])
	# THE LOAD PATH, reproduced without a save file: `WorldSnapshot.apply()` ends by calling
	# `reconcile_after_load()`, which arms a window for every home that is over capacity AT THE
	# MOMENT OF THE LOAD, from any cause. This world has been left exactly as a real one would be.
	var armed: int = _world.displacement.reconcile_after_load()
	_warn_player = 0
	_warn_ambient = 0
	var t: float = 0.0
	while t < 30.0:
		_world.simulation.tick(STEP)
		_world.displacement.tick(STEP)
		t += STEP
	print("  --- SIMULATED RELOAD ---")
	print("  homes re-armed by reconcile_after_load: %d" % armed)
	print("  warnings it produced, PLAYER-CAUSED   : %d   <-- a panel each" % _warn_player)
	print("  warnings it produced, silent          : %d" % _warn_ambient)
	print("  --- end reload ---")
	print("  WARNINGS flagged player_caused      : %d" % _warn_player)
	print("  WARNINGS flagged ambient (silent)   : %d" % _warn_ambient)
	print("  PLAYER-CAUSED AFTER PAINT SETTLED   : %d   <-- must be 0" % _warn_player_after_paint)
	print("  per-minute:")
	for line: String in buckets:
		print(line)

	print("  arrivals            : %d" % _arrivals)
	print("  relocations         : %d" % _relocations)
	print("  departures          : %d" % _departures)
	print("  warnings raised     : %d" % _world.displacement.warnings_raised)
	print("  consequences skipped: %d" % _world.displacement.consequences_skipped)
	print("  settlements resolved: %d" % _world.displacement.settlements_resolved)
	print("  simulated minutes   : %.1f" % (SIMULATED_SECONDS / 60.0))

	# Which sites moved, and did any of them move back to where they started?
	var seen: Dictionary = {}
	var repeats: Dictionary = {}
	for move: String in _moves:
		seen[move] = int(seen.get(move, 0)) + 1
		if int(seen[move]) > 1:
			repeats[move] = seen[move]
	print("  distinct moves      : %d" % seen.size())
	print("  REPEATED moves      : %d distinct" % repeats.size())
	for move: String in repeats.keys():
		print("      %s  x%d" % [move, repeats[move]])
	print("  first 25 moves in order:")
	for i: int in range(mini(25, _moves.size())):
		print("      %s" % _moves[i])

	finish()
	return true
