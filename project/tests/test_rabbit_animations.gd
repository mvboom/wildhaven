extends QATestCase
## Check 2 (Rabbit) — required-animations check on the Rabbit model.
##
## PINS CURRENT REALITY, NOT THE HOPED-FOR CONVENTION. The Fox (Quaternius) ships
## twelve clips named `Idle` / `Walk`; this model (Sherkiz, via Poly Pizza) ships TWO,
## named `Bunny|Bunny_idle` / `Bunny|Bunny_walk` — the vendor's Blender action naming,
## carried through the .glb unchanged because the file is kept byte-identical to the
## upstream download for CC BY reasons.
##
## That asymmetry is a KNOWN OPEN ISSUE, not something this test papers over: there is
## no shared clip-name contract across species yet, so any future generic animal
## controller cannot assume `"Idle"` exists. See the report's GAPS section.

const MODEL_PATH: String = "res://assets/animals/rabbit/Rabbit.tscn"

## The rabbit's ACTUAL clip names. Not `Idle`/`Walk`.
const IDLE_CLIP: String = "Bunny|Bunny_idle"
const WALK_CLIP: String = "Bunny|Bunny_walk"
const REQUIRED_CLIPS: PackedStringArray = [IDLE_CLIP, WALK_CLIP]

## Two clips is the whole set. No reaction animations exist in this asset — an asset
## limitation, not a bundle defect; the spec's reaction pool cannot be populated from
## pack content.
const EXPECTED_CLIP_COUNT: int = 2

## The fox's convention, asserted ABSENT so the divergence is explicit and a future
## rename shows up as a test failure demanding a decision rather than passing silently.
const FOX_CONVENTION_CLIPS: PackedStringArray = ["Idle", "Walk"]


func _init() -> void:
	begin("Rabbit animations")

	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if not check(packed != null, "%s loads as PackedScene" % MODEL_PATH):
		finish()
		return

	var rabbit: Node = packed.instantiate()
	if not check(rabbit != null, "Rabbit.tscn instantiates"):
		finish()
		return

	var player: AnimationPlayer = _find_animation_player(rabbit)
	if not check(player != null, "model contains an AnimationPlayer"):
		rabbit.free()
		finish()
		return

	var clips: PackedStringArray = player.get_animation_list()
	print("  AnimationPlayer at %s exposes %d clip(s):" % [
		rabbit.get_path_to(player), clips.size()
	])
	for c: String in clips:
		var anim: Animation = player.get_animation(c)
		print("      - %-20s %.3fs loop=%s tracks=%d" % [
			c, anim.length, anim.loop_mode != Animation.LOOP_NONE, anim.get_track_count()])

	for required: String in REQUIRED_CLIPS:
		check(player.has_animation(required), "required clip \"%s\" is present" % required)

	check_eq(clips.size(), EXPECTED_CLIP_COUNT, "clip count")

	# The naming divergence, pinned explicitly.
	for fox_name: String in FOX_CONVENTION_CLIPS:
		check(not player.has_animation(fox_name),
			"fox-convention clip \"%s\" is ABSENT (known naming divergence)" % fox_name)

	if player.has_animation(IDLE_CLIP):
		var idle: Animation = player.get_animation(IDLE_CLIP)
		check(idle.length > 0.0, "idle has non-zero length", "length=%f" % idle.length)
		check(idle.get_track_count() > 0, "idle has animation tracks",
			"track_count=%d" % idle.get_track_count())
		check(idle.loop_mode != Animation.LOOP_NONE,
			"idle loops (required for a resting animal)",
			"loop_mode=%d" % idle.loop_mode)
		# tech-art described this as a "single-channel" idle (~10 deg neck rotation,
		# body motionless). The clip actually carries MANY tracks — most of them are
		# static, i.e. keyed but never changing value. Measured rather than assumed,
		# because "1 track" and "31 tracks of which 1 moves" are different facts and
		# only the second one is true.
		var moving: PackedStringArray = _moving_tracks(idle)
		print("  idle: %d track(s) total, %d carrying actual motion" % [
			idle.get_track_count(), moving.size()])
		for m: String in moving:
			print("      moves: %s" % m)
		check(moving.size() > 0, "idle has at least one track that actually moves",
			"every track is static — the idle would be visually frozen")

	check_eq(player.autoplay, IDLE_CLIP, "AnimationPlayer autoplay is the idle clip")

	rabbit.free()
	finish()


## Track paths whose keyed values are not all identical — i.e. tracks that produce
## visible motion, as opposed to tracks that merely pin a bone in place.
func _moving_tracks(anim: Animation) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for t: int in range(anim.get_track_count()):
		var key_count: int = anim.track_get_key_count(t)
		if key_count < 2:
			continue
		var first: Variant = anim.track_get_key_value(t, 0)
		var varies: bool = false
		for k: int in range(1, key_count):
			if anim.track_get_key_value(t, k) != first:
				varies = true
				break
		if varies:
			out.append("%s [%s]" % [
				str(anim.track_get_path(t)),
				"rot" if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D else "other"
			])
	return out


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null
