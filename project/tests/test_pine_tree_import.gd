extends QATestCase
## Import check — PineTree (Forest terrain, the 3rd tree pick added 2026-08-16 to give
## Forest a genuinely different silhouette from the 2 existing "common tree" picks). Static
## mesh: no animations, so this asserts scene load + instantiation only — same shape as
## test_common_tree_1_import.gd / test_common_tree_2_import.gd.

const MODEL_PATH: String = "res://assets/terrain/pine_tree/PineTree.tscn"


func _init() -> void:
	begin("PineTree import")

	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if not check(packed != null, "%s loads as PackedScene" % MODEL_PATH):
		finish()
		return

	var inst: Node = packed.instantiate()
	if not check(inst != null, "PineTree.tscn instantiates"):
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
