extends QATestCase
## Import check — the 13 new Human look variants pulled from Quaternius's "Animated Men
## Characters" and "Animated Women Characters" (Feb 2019) packs, CC0.
##
## DELIBERATE DEVIATION from asset-import-pipeline.md step 4's one-file-per-item wording:
## this is ONE grouped suite covering 13 assets, not 13 near-identical copies of
## test_human_man_import.gd. It asserts strictly more per asset than that template does
## (load, instantiate, AnimationPlayer, both required clips, clip count, autoplay, and the
## scaled standing height), and it follows the grouping precedent
## test_house_variants_import.gd already set for a same-pack batch. Flagged here rather
## than left to be discovered — qa-engineer owns the call on whether to keep it.
##
## The five ALREADY-SHIPPED human variants keep their own per-file suites
## (test_human_man_import.gd + 4 siblings); this suite does not touch them.
##
## CLIP-NAME NOTE, measured not assumed: the men's pack names its clips
## `HumanArmature|Man_*` (NOT `Male_*`) — the same convention the already-shipped
## human_man/Man.glb uses. The women's pack uses `HumanArmature|Female_*`.

const EXPECTED_CLIP_COUNT: int = 11
const TILE_HEIGHT: float = 1.0
const HEIGHT_TOLERANCE: float = 0.05

## path -> clip-name prefix ("Man" or "Female")
const VARIANTS: Dictionary = {
	"res://assets/animals/human_male_longsleeve/MaleLongSleeve.tscn": "Man",
	"res://assets/animals/human_male_shirt/MaleShirt.tscn": "Man",
	"res://assets/animals/human_smooth_male_casual/SmoothMaleCasual.tscn": "Man",
	"res://assets/animals/human_smooth_male_longsleeve/SmoothMaleLongSleeve.tscn": "Man",
	"res://assets/animals/human_smooth_male_shirt/SmoothMaleShirt.tscn": "Man",
	"res://assets/animals/human_female_alternative/FemaleAlternative.tscn": "Female",
	"res://assets/animals/human_female_casual/FemaleCasual.tscn": "Female",
	"res://assets/animals/human_female_dress/FemaleDress.tscn": "Female",
	"res://assets/animals/human_female_tanktop/FemaleTankTop.tscn": "Female",
	"res://assets/animals/human_smooth_female_alternative/SmoothFemaleAlternative.tscn": "Female",
	"res://assets/animals/human_smooth_female_casual/SmoothFemaleCasual.tscn": "Female",
	"res://assets/animals/human_smooth_female_dress/SmoothFemaleDress.tscn": "Female",
	"res://assets/animals/human_smooth_female_tanktop/SmoothFemaleTankTop.tscn": "Female",
}


func _init() -> void:
	begin("Human character-pack variants import")

	check_eq(VARIANTS.size(), 13, "all 13 new variants are covered by this suite")
	for path: String in VARIANTS.keys():
		_check_variant(path, VARIANTS[path] as String)

	finish()


func _check_variant(path: String, prefix: String) -> void:
	var packed: PackedScene = load(path) as PackedScene
	if not check(packed != null, "%s loads as PackedScene" % path):
		return

	var instance: Node = packed.instantiate()
	if not check(instance != null, "%s instantiates" % path):
		return

	var player: AnimationPlayer = _find_animation_player(instance)
	if not check(player != null, "%s contains an AnimationPlayer" % path):
		instance.free()
		return

	var idle: String = "HumanArmature|%s_Idle" % prefix
	var walk: String = "HumanArmature|%s_Walk" % prefix
	check(player.has_animation(idle), "%s has required clip \"%s\"" % [path, idle])
	check(player.has_animation(walk), "%s has required clip \"%s\"" % [path, walk])
	check_eq(player.get_animation_list().size(), EXPECTED_CLIP_COUNT,
		"%s clip count" % path)
	check_eq(player.autoplay, idle, "%s AnimationPlayer autoplay is the idle clip" % path)

	# Scale guard: the wrapper's transform is scale = 1 / measured AABB height, so the
	# composed standing height must land on one tile. Catches a dropped or mistyped
	# transform, which is otherwise invisible headless.
	var world_aabb: AABB = _composed_aabb(instance, Transform3D.IDENTITY)
	print("  %s world-composed AABB size: %s" % [path, world_aabb.size])
	check(absf(world_aabb.size.y - TILE_HEIGHT) <= HEIGHT_TOLERANCE,
		"%s stands ~1 tile tall" % path,
		"height=%f, tolerance=%f" % [world_aabb.size.y, HEIGHT_TOLERANCE])

	instance.free()


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null


## Manually composes LOCAL transforms — global_transform silently returns IDENTITY on a
## freshly-instantiated, not-yet-tree-attached node under --script. Same helper (and same
## reasoning) as test_house_variants_import.gd.
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
