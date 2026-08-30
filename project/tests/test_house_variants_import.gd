extends QATestCase
## Import check — the 9 new House look variants added by content-variety pass Task 2
## (Houses_FirstAge_{1,2,3}_Level{1,2,3} minus the already-covered HousesFirstAge1Level1,
## plus TowerHouse_FirstAge). Same shape as test_house_import.gd (which stays covering the
## original single variant): load as PackedScene, instantiate, find a MeshInstance3D,
## assert the footprint fits the 1x1 tile target. Static buildings, no animation clips to
## assert.

const TILE_SIZE: float = 1.0

const VARIANT_PATHS: Array[String] = [
	"res://assets/buildings/house_firstage_1_level2/HouseFirstage1Level2.tscn",
	"res://assets/buildings/house_firstage_1_level3/HouseFirstage1Level3.tscn",
	"res://assets/buildings/house_firstage_2_level1/HouseFirstage2Level1.tscn",
	"res://assets/buildings/house_firstage_2_level2/HouseFirstage2Level2.tscn",
	"res://assets/buildings/house_firstage_2_level3/HouseFirstage2Level3.tscn",
	"res://assets/buildings/house_firstage_3_level1/HouseFirstage3Level1.tscn",
	"res://assets/buildings/house_firstage_3_level2/HouseFirstage3Level2.tscn",
	"res://assets/buildings/house_firstage_3_level3/HouseFirstage3Level3.tscn",
	"res://assets/buildings/house_tower_firstage/HouseTowerFirstage.tscn",
]


func _init() -> void:
	begin("House variants import")

	for path: String in VARIANT_PATHS:
		_check_variant(path)

	finish()


func _check_variant(path: String) -> void:
	var packed: PackedScene = load(path) as PackedScene
	if not check(packed != null, "%s loads as PackedScene" % path):
		return

	var instance: Node = packed.instantiate()
	if not check(instance != null, "%s instantiates" % path):
		return

	var mesh: MeshInstance3D = _find_mesh_instance(instance)
	if not check(mesh != null, "%s contains a MeshInstance3D" % path):
		instance.free()
		return

	var world_aabb: AABB = _composed_aabb(instance, Transform3D.IDENTITY)
	print("  %s world-composed AABB size: %s" % [path, world_aabb.size])
	check(world_aabb.size.x <= TILE_SIZE and world_aabb.size.z <= TILE_SIZE,
		"%s footprint fits within a %.1f-unit tile" % [path, TILE_SIZE],
		"size=%s" % world_aabb.size)

	instance.free()


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null


## Manually composes each node's LOCAL `transform` from the instanced root down through
## every MeshInstance3D, then transforms each mesh's local AABB corners by the composed
## transform and unions the results. Deliberately does NOT use Node3D.global_transform: on
## a freshly-instantiated, not-yet-tree-attached node under --script, global_transform
## silently returns Transform3D.IDENTITY (see project/data/terrain/cultivated_field.tres's
## header for the full writeup of this exact gotcha).
func _composed_aabb(node: Node, parent_transform: Transform3D) -> AABB:
	var local_transform: Transform3D = parent_transform
	if node is Node3D:
		local_transform = parent_transform * (node as Node3D).transform

	var union: AABB = AABB()
	var have_union: bool = false

	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			union = _transform_aabb(mesh.get_aabb(), local_transform)
			have_union = true

	for child: Node in node.get_children():
		var child_aabb: AABB = _composed_aabb(child, local_transform)
		if child_aabb.size == Vector3.ZERO and child_aabb.position == Vector3.ZERO:
			continue
		if not have_union:
			union = child_aabb
			have_union = true
		else:
			union = union.merge(child_aabb)

	return union


func _transform_aabb(aabb: AABB, xform: Transform3D) -> AABB:
	var corners: Array[Vector3] = []
	for i in range(8):
		corners.append(aabb.position + Vector3(
			aabb.size.x * float(i & 1),
			aabb.size.y * float((i >> 1) & 1),
			aabb.size.z * float((i >> 2) & 1)
		))
	var result: AABB = AABB(xform * corners[0], Vector3.ZERO)
	for i in range(1, 8):
		result = result.expand(xform * corners[i])
	return result
