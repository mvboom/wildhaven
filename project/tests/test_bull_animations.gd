extends QATestCase
## Check — required-animations check on the Bull model.
##
## `Idle` and `Walk` are the hard requirement (Add-an-Animal pipeline, asset-audit step).
## The full clip set is asserted too, so a silent re-import that drops or renames clips
## fails loudly instead of degrading at runtime.

const MODEL_PATH: String = "res://assets/animals/bull/Bull.tscn"

## Animations the pipeline requires of every species.
const REQUIRED_CLIPS: PackedStringArray = ["Idle", "Walk"]

## Expected clip count from the tech-art audit.
const EXPECTED_CLIP_COUNT: int = 13


func _init() -> void:
	begin("Bull animations")

	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if not check(packed != null, "%s loads as PackedScene" % MODEL_PATH):
		finish()
		return

	var bull: Node = packed.instantiate()
	if not check(bull != null, "Bull.tscn instantiates"):
		finish()
		return

	var player: AnimationPlayer = _find_animation_player(bull)
	if not check(player != null, "model contains an AnimationPlayer"):
		bull.free()
		finish()
		return

	var clips: PackedStringArray = player.get_animation_list()
	print("  AnimationPlayer at %s exposes %d clip(s):" % [
		bull.get_path_to(player), clips.size()
	])
	for c: String in clips:
		var anim: Animation = player.get_animation(c)
		print("      - %-16s %.3fs loop=%s" % [c, anim.length, anim.loop_mode != Animation.LOOP_NONE])

	for required: String in REQUIRED_CLIPS:
		check(player.has_animation(required), "required clip \"%s\" is present" % required)

	check_eq(clips.size(), EXPECTED_CLIP_COUNT, "clip count")

	# Idle is what the spawn smoke test relies on, so assert it is actually playable.
	if player.has_animation("Idle"):
		var idle: Animation = player.get_animation("Idle")
		check(idle.length > 0.0, "Idle has non-zero length", "length=%f" % idle.length)
		check(idle.get_track_count() > 0, "Idle has animation tracks",
			"track_count=%d" % idle.get_track_count())

	check_eq(player.autoplay, "Idle", "AnimationPlayer autoplay is \"Idle\"")

	bull.free()
	finish()


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null
