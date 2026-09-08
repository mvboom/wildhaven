extends QATestCase
## Import check — Pebble_Round_1 (grass-family rework, 2026-09-08). Raw glTF piece consumed directly
## by a terrain variant scene as an instanced prop, NOT via a wrapper .tscn — the same "reference
## the raw piece, not a sibling's wrapper" convention Scrub.tscn already used. Static mesh, no
## animations, so this asserts load + instantiation + real geometry only.

const MODEL_PATH: String = "res://assets/terrain/pebble_round_1/Pebble_Round_1.gltf"


func _init() -> void:
	begin("Pebble_Round_1 import")

	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if not check(packed != null, "%s loads as PackedScene" % MODEL_PATH):
		finish()
		return

	var inst: Node = packed.instantiate()
	if not check(inst != null, "Pebble_Round_1.gltf instantiates"):
		finish()
		return

	var mesh: MeshInstance3D = _find_mesh_instance(inst)
	if check(mesh != null, "model contains a MeshInstance3D"):
		check(mesh.mesh != null, "...and that MeshInstance3D carries a real mesh")
		check(mesh.mesh.get_surface_count() >= 1, "...with at least one surface")

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
