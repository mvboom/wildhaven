extends QATestCase
## Import check — AnimatedWoman (one of 5 Human look variants).

const MODEL_PATH: String = "res://assets/animals/human_woman/AnimatedWoman.tscn"
const REQUIRED_CLIPS: PackedStringArray = ["CharacterArmature|Idle", "CharacterArmature|Walk"]
const EXPECTED_CLIP_COUNT: int = 24


func _init() -> void:
	begin("AnimatedWoman import")

	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if not check(packed != null, "%s loads as PackedScene" % MODEL_PATH):
		finish()
		return

	var inst: Node = packed.instantiate()
	if not check(inst != null, "AnimatedWoman.tscn instantiates"):
		finish()
		return

	var player: AnimationPlayer = _find_animation_player(inst)
	if not check(player != null, "model contains an AnimationPlayer"):
		inst.free()
		finish()
		return

	var clips: PackedStringArray = player.get_animation_list()
	for required: String in REQUIRED_CLIPS:
		check(player.has_animation(required), "required clip \"%s\" is present" % required)
	check_eq(clips.size(), EXPECTED_CLIP_COUNT, "clip count")
	check_eq(player.autoplay, "CharacterArmature|Idle", "AnimationPlayer autoplay is the idle clip")

	inst.free()
	finish()


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null
