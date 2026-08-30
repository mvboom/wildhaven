extends QATestCase
## Check 3 (Rabbit) — spawn smoke test: put the Rabbit into the pilot-1 world and
## confirm it loads, instantiates, stays in the tree, and plays its idle.
##
## SCOPE: roaming/AI is NOT built and NOT tested. The bar is "loads, instantiates,
## sits there playing idle".
##
## The advancement assertion is kept from the fox suite deliberately: asserting that
## playback ADVANCES, not merely that a clip is assigned, is what makes this a real
## check. It is measured on `current_animation_position`, which is driven by the
## AnimationPlayer's own clock — so it is INDEPENDENT of how much the clip actually
## moves the mesh. The rabbit's idle being a single ~10 deg neck channel therefore
## does not make this flaky: a one-track clip advances its playhead exactly like a
## twelve-track one. (Had the assertion been written against bone transforms, the
## tiny motion would have mattered.)

const WORLD_PATH: String = "res://scenes/Main.tscn"
const RABBIT_DEF_PATH: String = "res://data/animals/rabbit.tres"
const IDLE_CLIP: String = "Bunny|Bunny_idle"

const FRAMES_TO_RUN: int = 30

var _world: Node = null
var _rabbit: Node3D = null
var _player: AnimationPlayer = null
var _frames: int = 0
var _pos_at_start: float = 0.0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("Rabbit spawn smoke test")

	var world_packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(world_packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	_world = world_packed.instantiate()
	if not check(_world != null, "Main.tscn instantiates"):
		finish()
		return
	# Nodes added to `root` from `_initialize()` are not in the tree until the first
	# frame ticks — `_ready()` has not run yet. Tree membership is asserted in
	# `_process`, not here.
	root.add_child(_world)

	var rabbit_def: AnimalDefinition = load(RABBIT_DEF_PATH) as AnimalDefinition
	if not check(rabbit_def != null, "rabbit.tres loads as AnimalDefinition"):
		finish()
		return

	# Spawn through the DEFINITION's model_scene, not a hardcoded path, so this
	# exercises the data binding as well as the model.
	var inst: Node = rabbit_def.model_scenes[0].instantiate()
	if not check(inst is Node3D, "rabbit model instantiates as Node3D",
			"got %s" % inst.get_class()):
		finish()
		return
	_rabbit = inst as Node3D
	_rabbit.name = "Rabbit_spawned"

	# grid_manager.TILE_SIZE == 1.0 and the 16x16 grid is centered on the origin, so
	# the origin is a valid in-world tile position. Offset from the fox's spawn point
	# so both can be eyeballed together at step-8 if the human wants.
	_rabbit.position = Vector3(2.0, 0.0, 0.0)
	_world.add_child(_rabbit)

	check_eq(_rabbit.get_parent(), _world, "rabbit is parented to the world root")
	check(_world.has_node("Rabbit_spawned"), "rabbit is findable by name from the world root")

	_player = _find_animation_player(_rabbit)
	if not check(_player != null, "spawned rabbit has an AnimationPlayer"):
		finish()
		return

	_setup_ok = true
	print("  ... running %d frames" % FRAMES_TO_RUN)


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1

	if _frames == 2:
		check(_world.is_inside_tree(), "world is in the scene tree")
		check(_rabbit.is_inside_tree(), "rabbit is inside the scene tree")
		check(_player.is_playing(), "AnimationPlayer is playing after spawn")
		check_eq(_player.current_animation, IDLE_CLIP, "current animation is the idle clip")
		_pos_at_start = _player.current_animation_position

	if _frames >= FRAMES_TO_RUN:
		var pos_now: float = _player.current_animation_position
		# A loop can wrap past the start sample, so a wrap counts as advance too.
		var advanced: bool = pos_now != _pos_at_start
		check(advanced, "idle playback advanced over %d frames" % FRAMES_TO_RUN,
			"position stuck at %f" % pos_now)
		print("  idle position: %.4f -> %.4f (length %.3f)" % [
			_pos_at_start, pos_now, _player.get_animation(IDLE_CLIP).length])

		check(_player.is_playing(), "AnimationPlayer still playing at end of run")
		check(is_instance_valid(_rabbit) and _rabbit.is_inside_tree(),
			"rabbit survived %d frames in the tree" % FRAMES_TO_RUN)
		check_eq(_rabbit.position, Vector3(2.0, 0.0, 0.0),
			"rabbit stayed put (no roaming built — this is expected)")

		# The material fix is the point of the .tscn wrapper (metallic 0.4 -> 0.0 so
		# fur is not shiny). Asserted on the live spawned instance, because a wrapper
		# override that silently stops applying is invisible until someone looks.
		_check_material_overrides()

		finish()
		return true

	return false


## Confirms the surface overrides survived instancing with metallic zeroed.
func _check_material_overrides() -> void:
	var mesh: MeshInstance3D = _find_mesh_instance(_rabbit)
	if not check(mesh != null, "spawned rabbit has a MeshInstance3D"):
		return
	var found: int = 0
	var shiny: Array[String] = []
	for i: int in range(mesh.get_surface_override_material_count()):
		var mat: Material = mesh.get_surface_override_material(i)
		if mat is StandardMaterial3D:
			found += 1
			var std: StandardMaterial3D = mat as StandardMaterial3D
			if std.metallic != 0.0:
				shiny.append("%s=%f" % [std.resource_name, std.metallic])
	check(found == 3, "all 3 surface material overrides are present on the spawned mesh",
		"found %d" % found)
	check(shiny.is_empty(), "every override has metallic == 0.0 (no sheen on fur)",
		"non-zero: %s" % str(shiny))


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).get_surface_override_material_count() > 0:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null
