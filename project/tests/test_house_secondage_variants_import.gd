extends QATestCase
## Import check — the 10 SecondAge House look variants (Houses_SecondAge_{1,2,3}_
## Level{1,2,3} plus TowerHouse_SecondAge), Quaternius "Ultimate Fantasy RTS", CC0.
##
## DELIBERATE DEVIATION from asset-import-pipeline.md step 4's one-file-per-item wording:
## this is ONE grouped suite covering 10 assets, not 10 near-identical files. It follows
## the shape the existing test_house_variants_import.gd already set for the FirstAge
## batch (same helper, same footprint assertion), so the deviation is a continuation of
## in-repo precedent, not a new pattern. qa-engineer owns the call on whether to keep it.
##
## Static buildings: load + instantiate + a MeshInstance3D + the world-composed footprint
## fits the 1x1 tile. No animation clips to assert.

const TILE_SIZE: float = 1.0

const VARIANT_PATHS: Array[String] = [
	"res://assets/buildings/house_secondage_1_level1/HouseSecondage1Level1.tscn",
	"res://assets/buildings/house_secondage_1_level2/HouseSecondage1Level2.tscn",
	"res://assets/buildings/house_secondage_1_level3/HouseSecondage1Level3.tscn",
	"res://assets/buildings/house_secondage_2_level1/HouseSecondage2Level1.tscn",
	"res://assets/buildings/house_secondage_2_level2/HouseSecondage2Level2.tscn",
	"res://assets/buildings/house_secondage_2_level3/HouseSecondage2Level3.tscn",
	"res://assets/buildings/house_secondage_3_level1/HouseSecondage3Level1.tscn",
	"res://assets/buildings/house_secondage_3_level2/HouseSecondage3Level2.tscn",
	"res://assets/buildings/house_secondage_3_level3/HouseSecondage3Level3.tscn",
	"res://assets/buildings/house_tower_secondage/HouseTowerSecondage.tscn",
]


func _init() -> void:
	begin("House SecondAge variants import")

	check_eq(VARIANT_PATHS.size(), 10, "all 10 SecondAge variants are covered by this suite")
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
