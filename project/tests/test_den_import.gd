extends QATestCase
## Import check — Den, the move-in prop (den/burrow/nest). Static composition: no
## animations, so this asserts scene load + expected node structure only.

const MODEL_PATH: String = "res://assets/props/den/Den.tscn"
const EXPECTED_PIECES: PackedStringArray = ["Log", "Rock", "Bush"]


func _init() -> void:
	begin("Den import")

	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if not check(packed != null, "%s loads as PackedScene" % MODEL_PATH):
		finish()
		return

	var den: Node = packed.instantiate()
	if not check(den != null, "Den.tscn instantiates"):
		finish()
		return

	for piece_name: String in EXPECTED_PIECES:
		var piece: Node = den.get_node_or_null(piece_name)
		if check(piece != null, "\"%s\" piece is present" % piece_name):
			check(_find_mesh_instance(piece) != null,
				"\"%s\" piece contains a MeshInstance3D" % piece_name)

	den.free()
	finish()


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null
