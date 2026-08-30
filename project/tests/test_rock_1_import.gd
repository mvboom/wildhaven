extends QATestCase
## Import check — Rock1 (Rock terrain: emits cover + rocks, load-bearing for Fox/Rabbit
## habitat). Static mesh: no animations, so this asserts scene load + a footprint check.

const MODEL_PATH: String = "res://assets/terrain/rock_1/Rock1.tscn"
const TILE_SIZE: float = 1.0


func _init() -> void:
	begin("Rock1 import")

	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if not check(packed != null, "%s loads as PackedScene" % MODEL_PATH):
		finish()
		return

	var inst: Node = packed.instantiate()
	if not check(inst != null, "Rock1.tscn instantiates"):
		finish()
		return

	var mesh: MeshInstance3D = _find_mesh_instance(inst)
	if not check(mesh != null, "model contains a MeshInstance3D"):
		inst.free()
		finish()
		return

	var aabb: AABB = mesh.get_aabb()
	check(aabb.size.x <= TILE_SIZE and aabb.size.z <= TILE_SIZE,
		"footprint fits within a %.1f-unit tile" % TILE_SIZE,
		"size=%s" % aabb.size)

	inst.free()
	finish()


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null
