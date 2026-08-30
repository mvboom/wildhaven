class_name AnimalClips
extends RefCounted
## Finds a model's Idle and Walk clips **by meaning, not by literal name.**
##
## THERE IS NO SHARED CLIP-NAME CONTRACT ACROSS THE ROSTER, and pretending otherwise is how
## a generic roam controller silently stops animating. The three shipped models disagree:
##
##   Fox         (Quaternius)  ->  "Idle"                      "Walk"
##   Rabbit      (Sherkiz)     ->  "Bunny|Bunny_idle"          "Bunny|Bunny_walk"
##   Adventurer  (Quaternius)  ->  "CharacterArmature|Idle"    "CharacterArmature|Walk"
##
## `test_rabbit_animations.gd` already pins that divergence as a known open issue and even
## asserts the fox convention ABSENT from the rabbit. So this class resolves the clip rather
## than assuming it, in two passes:
##
##   1. the clip whose leaf name (after the last `|`) EQUALS the wanted word, case-insensitive
##      — this is what keeps `CharacterArmature|Idle` from losing to `CharacterArmature|Idle_Gun`;
##   2. failing that, the SHORTEST leaf name that merely CONTAINS the word — which is what
##      finds `Bunny_idle`.
##
## An unresolved clip returns `""` and the caller simply does not animate. A missing clip is
## a content defect (the Add-an-Animal pipeline's asset-audit step requires Idle and Walk),
## never a reason for the resident to stop moving.

## The two clips every roster model is required to carry.
const IDLE: String = "idle"
const WALK: String = "walk"

## OPTIONAL clips: present on some models, absent on others (rabbit has neither). A resolver
## returning "" for these is normal roster variance, not a content defect the way a missing
## Idle/Walk would be.
const RUN: String = "run"
const GALLOP: String = "gallop"
const EAT: String = "eat"
const WAVE: String = "wave"

## Keywords that keep a clip OUT of any random-flavor pool (idle variety, future additions)
## even when it would otherwise match on name. Wildhaven is a cozy game — Attack/HitReact/Death
## and the human rig's weapon/combat set exist in the shipped Quaternius packs but are never
## roaming flavor. Matched as a substring of the lowercased leaf name, so `Idle_HitReact1`
## (which DOES contain "idle") is still caught — as is `Jump_toIdle`, a landing TRANSITION
## into idle, not a standalone pose, which `idle_variant_clips()`'s substring match would
## otherwise wrongly treat as one.
const FLAVOR_DENYLIST: Array[String] = [
	"attack", "hit", "death", "kick", "punch", "sword", "gun", "roll", "jump",
]


## The first AnimationPlayer anywhere under `node`, or null. Same walk the animation test
## suites do, so "the model has a player" means the same thing in both places.
static func find_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = find_player(child)
		if found != null:
			return found
	return null


static func idle_clip(player: AnimationPlayer) -> String:
	return resolve(player, IDLE)


static func walk_clip(player: AnimationPlayer) -> String:
	return resolve(player, WALK)


## A faster locomotion clip, or "". The roster spells this two different ways — the Quaternius
## quadruped/canine pack ships `Gallop`, the human rig ships `Run` — so both are tried.
static func run_clip(player: AnimationPlayer) -> String:
	var run: String = _resolve_flavor(player, RUN)
	if run != "":
		return run
	return _resolve_flavor(player, GALLOP)


static func eat_clip(player: AnimationPlayer) -> String:
	return _resolve_flavor(player, EAT)


static func wave_clip(player: AnimationPlayer) -> String:
	return _resolve_flavor(player, WAVE)


## `resolve()`, but candidates on `FLAVOR_DENYLIST` are skipped DURING the search rather than
## filtered from its result. That distinction is load-bearing: `"Death".contains("eat")` is
## true (d-EAT-h), so a plain `resolve(player, EAT)` can return `Death` instead of `Eating` on
## any model that ships both — filtering the result afterward would just turn that into a lost
## `Eating` match instead of a wrong one. Skipping denylisted names during the search lets the
## real match still be found.
static func _resolve_flavor(player: AnimationPlayer, wanted: String) -> String:
	if player == null:
		return ""
	var target: String = wanted.to_lower()
	var loose: String = ""
	for clip: String in player.get_animation_list():
		var leaf: String = _leaf(clip).to_lower()
		if _is_denylisted(leaf):
			continue
		if leaf == target:
			return clip
		if leaf.contains(target) and (loose == "" or clip.length() < loose.length()):
			loose = clip
	return loose


## Every OTHER clip on `player` that reads as an idle variant by name (contains "idle") but
## isn't `primary_idle` and isn't on `FLAVOR_DENYLIST` — e.g. the quadruped pack's `Idle_2` and
## `Idle_Headlow` beside its `Idle`. Order matches `AnimationPlayer.get_animation_list()`.
static func idle_variant_clips(player: AnimationPlayer, primary_idle: String) -> Array[String]:
	var out: Array[String] = []
	if player == null:
		return out
	for clip: String in player.get_animation_list():
		if clip == primary_idle:
			continue
		var leaf: String = _leaf(clip).to_lower()
		if not leaf.contains(IDLE):
			continue
		if _is_denylisted(leaf):
			continue
		out.append(clip)
	return out


static func _is_denylisted(lowercase_leaf: String) -> bool:
	for word: String in FLAVOR_DENYLIST:
		if lowercase_leaf.contains(word):
			return true
	return false


## The clip name matching `wanted`, or `""`.
static func resolve(player: AnimationPlayer, wanted: String) -> String:
	if player == null:
		return ""
	var target: String = wanted.to_lower()
	var loose: String = ""
	for clip: String in player.get_animation_list():
		var leaf: String = _leaf(clip).to_lower()
		if leaf == target:
			return clip  # pass 1 — an exact leaf always wins
		if leaf.contains(target) and (loose == "" or clip.length() < loose.length()):
			loose = clip  # pass 2 — shortest containing name
	return loose


## The part of a clip name after the last `|` — glTF carries the exporter's armature/action
## naming through unchanged, and that prefix is the only thing that differs between the fox's
## `Walk` and the villager's `CharacterArmature|Walk`.
static func _leaf(clip: String) -> String:
	var cut: int = clip.rfind("|")
	return clip if cut < 0 else clip.substr(cut + 1)
