extends QATestCase
## Import check — Man (one of 5 Human look variants).
##
## Different rig/animation-name convention than its 4 siblings (HumanArmature|Man_* vs.
## CharacterArmature|*, 11 clips vs. 24) — a different, older Quaternius release measured
## and pinned here, not a defect to normalize away.

const MODEL_PATH: String = "res://assets/animals/human_man/Man.tscn"
const REQUIRED_CLIPS: PackedStringArray = ["HumanArmature|Man_Idle", "HumanArmature|Man_Walk"]
const EXPECTED_CLIP_COUNT: int = 11


func _init() -> void:
	begin("Man import")

	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if not check(packed != null, "%s loads as PackedScene" % MODEL_PATH):
		finish()
		return

	var inst: Node = packed.instantiate()
	if not check(inst != null, "Man.tscn instantiates"):
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
	check_eq(player.autoplay, "HumanArmature|Man_Idle", "AnimationPlayer autoplay is the idle clip")

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
