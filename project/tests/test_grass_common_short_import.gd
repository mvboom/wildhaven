extends QATestCase
## Import check — GrassCommonShort (open_grass terrain dressing). Static mesh: no
## animations, so this asserts scene load + instantiation only.

const MODEL_PATH: String = "res://assets/terrain/grass_common_short/GrassCommonShort.tscn"


func _init() -> void:
	begin("GrassCommonShort import")

	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if not check(packed != null, "%s loads as PackedScene" % MODEL_PATH):
		finish()
		return

	var inst: Node = packed.instantiate()
	if not check(inst != null, "GrassCommonShort.tscn instantiates"):
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
