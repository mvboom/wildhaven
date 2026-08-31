class_name FidelityProbe
extends RefCounted
## Turns a live imported scene into the same manifest shape scripts/assetpipe/
## fingerprint.py produces for a source file, so the two can be compared field by field.
##
## RefCounted, NOT QATestCase: every test in this project IS a SceneTree (see
## run-tests.sh's header), and a second SceneTree cannot be instantiated inside a running
## one. A plain helper can be called from any suite.

## Rounded to 4dp to match fingerprint.round4 -- comparison is exact, not epsilon-based.
static func _r4(v: float) -> float:
	return snappedf(v, 0.0001)


static func probe(wrapper_path: String) -> Dictionary:
	var packed: PackedScene = load(wrapper_path) as PackedScene
	if packed == null:
		return {}
	var root: Node = packed.instantiate()
	if root == null:
		return {}

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)

	var rows: Array = []
	var textures: Dictionary = {}
	var surfaces: int = 0
	var vertices: int = 0
	var vcol: bool = false
	var extent: Vector3 = Vector3.ZERO

	for mi: MeshInstance3D in meshes:
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		surfaces += mesh.get_surface_count()
		# NOTE: deliberately NOT scaled by mi.global_transform.basis.get_scale().
		# mesh.get_aabb() already returns raw, unscaled local-space mesh bounds, matching
		# the Python source readers (glTF accessor min/max are pre-node-transform; Blender's
		# o.dimensions is object-local). The wrapper .tscn's 0.09 scale is a presentation
		# choice for the game world, not a property of the asset -- applying it here would
		# make every animal's runtime aabb ~11x smaller than its source and warn on all of
		# them. See task-5 brief resolution.
		extent = extent.max(mesh.get_aabb().size)
		for i: int in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(i)
			if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
				vertices += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			# The override wins if the wrapper set one; otherwise the imported material.
			var mat: Material = mi.get_active_material(i)
			var base: BaseMaterial3D = mat as BaseMaterial3D
			if base == null:
				continue
			if base.vertex_color_use_as_albedo:
				vcol = true
			# BaseMaterial3D.albedo_color reads back gamma-encoded (sRGB) relative to the
			# glTF/Blender source, which is linear -- glTF's baseColorFactor and Blender's
			# BSDF Base Color are both natively linear. Convert back to linear here so the
			# manifest matches the Python source readers; metallic/roughness are scalar
			# material properties, not colours, and are NOT gamma-encoded, so they are left
			# untouched. See task-5 fix round 1.
			var c: Color = base.albedo_color.srgb_to_linear()
			rows.append([[_r4(c.r), _r4(c.g), _r4(c.b), _r4(c.a)],
				_r4(base.metallic), _r4(base.roughness)])
			var tex: Texture2D = base.albedo_texture
			if tex != null and not tex.resource_path.is_empty():
				textures[tex.resource_path.get_file()] = true

	rows.sort_custom(func(a: Array, b: Array) -> bool: return _color_lt(a[0], b[0]))

	var player: AnimationPlayer = _find_player(root)
	var clips: Array = []
	if player != null:
		for name: String in player.get_animation_list():
			clips.append(name)
	clips.sort()

	var skel: Skeleton3D = _find_skeleton(root)
	var tex_names: Array = textures.keys()
	tex_names.sort()

	var out: Dictionary = {
		"materials": rows.size(),
		"base_colors": rows.map(func(r: Array) -> Array: return r[0]),
		"metallic": rows.map(func(r: Array) -> float: return r[1]),
		"roughness": rows.map(func(r: Array) -> float: return r[2]),
		"vertex_colors": vcol,
		"textures": tex_names,
		"surfaces": surfaces,
		"vertices": vertices,
		"clips": clips,
		"joints": 0 if skel == null else skel.get_bone_count(),
		"aabb": [_r4(extent.x), _r4(extent.y), _r4(extent.z)],
	}
	root.free()
	return out


## Lexicographic on [r,g,b,a], matching Python's list comparison in fingerprint.py.
static func _color_lt(a: Array, b: Array) -> bool:
	for i: int in 4:
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


static func _collect_meshes(node: Node, into: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		into.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_meshes(child, into)


static func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var f: AnimationPlayer = _find_player(child)
		if f != null:
			return f
	return null


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var f: Skeleton3D = _find_skeleton(child)
		if f != null:
			return f
	return null
