extends QATestCase
## Import check — Clover_1 (grass-family rework, 2026-09-08). Raw glTF piece, NOT a wrapper
## scene: this asset is consumed by the Grass variant scenes as an embedded MultiMesh source,
## the same "reuse the raw piece, not a sibling's wrapper" convention Scrub.tscn already uses
## for Grass_Wispy_Short. Static mesh, no animations, so this asserts load + instantiation
## only — same shape as test_pine_tree_import.gd.

const MODEL_PATH: String = "res://assets/terrain/clover_1/Clover_1.gltf"


func _init() -> void:
	begin("Clover_1 import")

	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if not check(packed != null, "%s loads as PackedScene" % MODEL_PATH):
		finish()
		return

	var inst: Node = packed.instantiate()
	if not check(inst != null, "Clover_1.gltf instantiates"):
		finish()
		return

	var mesh: MeshInstance3D = _find_mesh_instance(inst)
	if check(mesh != null, "model contains a MeshInstance3D"):
		check(mesh.mesh != null, "...and that MeshInstance3D carries a real mesh")

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
