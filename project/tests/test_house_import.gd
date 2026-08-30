extends QATestCase
## Import check — House (Houses_FirstAge_1_Level1). Static building: no animations, so
## this asserts scene load + footprint fits the 1x1 tile target only.

const MODEL_PATH: String = "res://assets/buildings/house/House.tscn"
const TILE_SIZE: float = 1.0


func _init() -> void:
	begin("House import")

	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if not check(packed != null, "%s loads as PackedScene" % MODEL_PATH):
		finish()
		return

	var house: Node = packed.instantiate()
	if not check(house != null, "House.tscn instantiates"):
		finish()
		return

	var mesh: MeshInstance3D = _find_mesh_instance(house)
	if not check(mesh != null, "model contains a MeshInstance3D"):
		house.free()
		finish()
		return

	var aabb: AABB = mesh.get_aabb()
	print("  mesh-local AABB size: %s" % aabb.size)
	check(aabb.size.x <= TILE_SIZE and aabb.size.z <= TILE_SIZE,
		"footprint fits within a %.1f-unit tile" % TILE_SIZE,
		"size=%s" % aabb.size)

	house.free()
	finish()


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null
