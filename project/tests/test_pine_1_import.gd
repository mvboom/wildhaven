extends QATestCase
## Import check — Pine_1 (Forest MegaKit standardisation, 2026-09-08): the narrow tapered conifer, restoring the silhouette the 2026-09-08 cull removed with the Poly Pizza PineTree.
##
## Asserts the hand-authored WRAPPER, not the raw glTF, because the wrapper is the only thing
## `forest.tres` ever references — the convention asset-import-pipeline.md states. Static mesh,
## no animations, so this is load + instantiation + real geometry, the same shape as
## test_pine_tree_import.gd.

const MODEL_PATH: String = "res://assets/terrain/pine_1/Pine1.tscn"


func _init() -> void:
	begin("Pine_1 import")

	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if not check(packed != null, "%s loads as PackedScene" % MODEL_PATH):
		finish()
		return

	var inst: Node = packed.instantiate()
	if not check(inst != null, "Pine1.tscn instantiates"):
		finish()
		return

	var mesh: MeshInstance3D = _find_mesh_instance(inst)
	if check(mesh != null, "the wrapper contains a MeshInstance3D"):
		check(mesh.mesh != null, "...and it carries a real mesh")

	# Every terrain wrapper groups its ground-level pieces under a node named exactly "Slab".
	# This WAS the OcclusionFader's fade exemption; that system was removed 2026-09-08 (D-59) and
	# no code looks the name up any more, so this is now a structural-consistency check rather
	# than a behavioural one — kept because all 33 scenes are built this way and a wrapper that
	# silently broke the pattern would be an odd one out.
	check(inst.get_node_or_null("Slab") != null,
		"the wrapper groups its ground-level pieces under the conventional \"Slab\" node")

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
