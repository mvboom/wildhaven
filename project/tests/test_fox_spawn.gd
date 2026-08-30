extends QATestCase
## Check 3 — spawn smoke test: put the Fox into the pilot-1 world and confirm it
## loads, instantiates, stays in the tree, and plays Idle.
##
## SCOPE: roaming/AI behavior is NOT built and is NOT tested here. The bar is
## "loads, instantiates, sits there playing Idle" — nothing more.
##
## Runs the real SceneTree for a number of frames so the AnimationPlayer actually
## advances; a static instantiate() would not prove Idle is playing.

const WORLD_PATH: String = "res://scenes/Main.tscn"
const FOX_DEF_PATH: String = "res://data/animals/fox.tres"

## Frames to let the world tick before asserting. Enough to cover _ready(), autoplay
## kick-in, and measurable animation advance without making the test slow.
const FRAMES_TO_RUN: int = 30

var _world: Node = null
var _fox: Node3D = null
var _player: AnimationPlayer = null
var _frames: int = 0
var _pos_at_start: float = 0.0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("Fox spawn smoke test")

	var world_packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(world_packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	_world = world_packed.instantiate()
	if not check(_world != null, "Main.tscn instantiates"):
		finish()
		return
	# NOTE: nodes added to `root` from `_initialize()` are not actually in the tree
	# until the first frame ticks — `_ready()` has not run yet at this point. Tree
	# membership is therefore asserted in `_process`, not here.
	root.add_child(_world)

	var fox_def: AnimalDefinition = load(FOX_DEF_PATH) as AnimalDefinition
	if not check(fox_def != null, "fox.tres loads as AnimalDefinition"):
		finish()
		return

	# Spawn through the DEFINITION's model_scene, not a hardcoded path — this is the
	# path the real spawner will take, so it exercises the data binding too.
	var inst: Node = fox_def.model_scenes[0].instantiate()
	if not check(inst is Node3D, "fox model instantiates as Node3D",
			"got %s" % inst.get_class()):
		finish()
		return
	_fox = inst as Node3D
	_fox.name = "Fox_spawned"

	# Place it on a tile center. grid_manager.TILE_SIZE == 1.0 and the 16x16 grid is
	# centered on the origin, so the origin is a valid in-world tile position.
	_fox.position = Vector3(0.0, 0.0, 0.0)
	_world.add_child(_fox)

	check_eq(_fox.get_parent(), _world, "fox is parented to the world root")
	check(_world.has_node("Fox_spawned"), "fox is findable by name from the world root")

	_player = _find_animation_player(_fox)
	if not check(_player != null, "spawned fox has an AnimationPlayer"):
		finish()
		return

	_setup_ok = true
	print("  ... running %d frames" % FRAMES_TO_RUN)


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1

	if _frames == 2:
		# Tree membership is only real once a frame has ticked (see _initialize).
		check(_world.is_inside_tree(), "world is in the scene tree")
		check(_fox.is_inside_tree(), "fox is inside the scene tree")

		# Give autoplay one frame to engage, then sample.
		check(_player.is_playing(), "AnimationPlayer is playing after spawn")
		check_eq(_player.current_animation, "Idle", "current animation is \"Idle\"")
		_pos_at_start = _player.current_animation_position

	if _frames >= FRAMES_TO_RUN:
		# Idle must actually be ADVANCING, not merely assigned. A loop can wrap back
		# past the start sample, so a wrap counts as advance too.
		var pos_now: float = _player.current_animation_position
		var advanced: bool = pos_now != _pos_at_start
		check(advanced, "Idle playback advanced over %d frames" % FRAMES_TO_RUN,
			"position stuck at %f" % pos_now)
		print("  Idle position: %.4f -> %.4f (length %.3f)" % [
			_pos_at_start, pos_now, _player.get_animation("Idle").length])

		check(_player.is_playing(), "AnimationPlayer still playing at end of run")
		check(is_instance_valid(_fox) and _fox.is_inside_tree(),
			"fox survived %d frames in the tree" % FRAMES_TO_RUN)
		check_eq(_fox.position, Vector3.ZERO,
			"fox stayed put (no roaming built — this is expected)")

		finish()
		return true

	return false


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null
