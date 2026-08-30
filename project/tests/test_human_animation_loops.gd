extends QATestCase
## Every clip the game can actually PLAY on a villager must be a looping clip.
##
## THE BUG THIS PINS, twice observed. A clip imported with `loop_mode = LOOP_NONE` plays
## once, freezes on its last pose, and `ResidentRoamer._play()`'s "already this clip" guard
## then never re-fires it — while `tick()` keeps moving the resident, so it glides
## mid-stride. `resident_roamer.gd` names the real fix outright: `animation/loop_mode` set
## to Linear on every playable clip, in the asset's own `.import` file. `_ensure_playing()`
## is a safety net for a roaming resident, not a substitute — a resident standing at its
## home site simply freezes, and the net cannot help a clip that never restarts.
##
## It has now happened twice, both times on a fresh import (the 2026-08-29 asset-audit
## sweep's 13 character variants shipped with `_subresources={}` — no loop settings at
## all). A comment did not prevent the second occurrence, so this suite exists instead:
## it fails on ANY future human import that forgets the setting, at import time rather
## than when someone notices a frozen villager in a play session.
##
## PLAYABLE, precisely: this asserts exactly the set `ResidentRoamer` can select via
## `AnimalClips` — Idle, Walk and the optional Run/Eat/Wave, plus every non-denylisted
## idle variant `idle_variant_clips()` can roll. A combat or Death clip that never loops
## is correct and is deliberately NOT asserted; the denylist is the contract, and reusing
## `AnimalClips` here rather than re-listing names means the two can never disagree about
## what "playable" means.
##
## SCOPE: human models only, matching the reported defect. Nine animal species
## (alpaca, bull, cow, deer, donkey, horse, husky, shiba_inu, stag) currently carry the
## same defect on their Eating/Idle_2/Idle_Headlow flavor clips — intermittent rather than
## constant, since flavor is a minority of pauses. Fox and rabbit are clean. Widening this
## suite to the whole roster is a one-line change to MODEL_DIR_PREFIX plus the matching
## `.import` fixes; left as a deliberate follow-up rather than smuggled into a bug fix.

const ANIMALS_DIR: String = "res://assets/animals"
const MODEL_DIR_PREFIX: String = "human_"


func _init() -> void:
	begin("human animation loop modes")

	var dir: DirAccess = DirAccess.open(ANIMALS_DIR)
	if not check(dir != null, "%s opens" % ANIMALS_DIR):
		finish()
		return

	var model_dirs: PackedStringArray = dir.get_directories()
	model_dirs.sort()

	var checked: int = 0
	for model_dir: String in model_dirs:
		if not model_dir.begins_with(MODEL_DIR_PREFIX):
			continue
		var base: String = "%s/%s" % [ANIMALS_DIR, model_dir]
		var sub: DirAccess = DirAccess.open(base)
		if sub == null:
			continue
		for file_name: String in sub.get_files():
			if not file_name.ends_with(".tscn"):
				continue
			checked += 1
			_check_model("%s/%s" % [base, file_name], model_dir)

	# A resolver bug that silently matched nothing would make every assertion above vacuous,
	# so pin that the sweep actually found the models it is meant to cover.
	check(checked >= 18, "found at least the 18 wired human look variants (found %d)" % checked)
	finish()


func _check_model(path: String, model_dir: String) -> void:
	var packed: PackedScene = load(path) as PackedScene
	if not check(packed != null, "%s loads as PackedScene" % model_dir):
		return
	var inst: Node = packed.instantiate()
	if not check(inst != null, "%s instantiates" % model_dir):
		return
	var player: AnimationPlayer = AnimalClips.find_player(inst)
	if not check(player != null, "%s contains an AnimationPlayer" % model_dir):
		inst.free()
		return

	for clip: String in _playable_clips(player):
		var anim: Animation = player.get_animation(clip)
		if anim == null:
			check(false, "%s: clip \"%s\" resolves to an Animation" % [model_dir, clip])
			continue
		check(anim.loop_mode != Animation.LOOP_NONE,
			"%s: playable clip \"%s\" loops" % [model_dir, clip],
			"loop_mode is LOOP_NONE — set animation/loop_mode on this clip in the asset's .import")

	inst.free()


## Exactly what ResidentRoamer can select: the required pair, the optional flourishes, and
## every idle variant the denylist permits.
func _playable_clips(player: AnimationPlayer) -> Array[String]:
	var out: Array[String] = []
	var idle: String = AnimalClips.idle_clip(player)
	for clip: String in [
		idle,
		AnimalClips.walk_clip(player),
		AnimalClips.run_clip(player),
		AnimalClips.eat_clip(player),
		AnimalClips.wave_clip(player),
	]:
		if clip != "" and not out.has(clip):
			out.append(clip)
	for variant: String in AnimalClips.idle_variant_clips(player, idle):
		if not out.has(variant):
			out.append(variant)
	return out
