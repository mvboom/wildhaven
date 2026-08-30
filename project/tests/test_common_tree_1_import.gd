extends QATestCase
## Import check — CommonTree1 (Forest terrain, one of 2 common tree picks). Static
## mesh: no animations, so this asserts scene load + instantiation only.

const MODEL_PATH: String = "res://assets/terrain/common_tree_1/CommonTree1.tscn"


func _init() -> void:
	begin("CommonTree1 import")

	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if not check(packed != null, "%s loads as PackedScene" % MODEL_PATH):
		finish()
		return

	var inst: Node = packed.instantiate()
	if not check(inst != null, "CommonTree1.tscn instantiates"):
		finish()
		return

	check(_find_mesh_instance(inst) != null, "model contains a MeshInstance3D")

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
