extends QATestCase
## Load/instantiate check for the seven grey-box tile visuals under
## res://assets/placeholder/ (see that directory's README.md — authored in-repo from Godot
## primitives, no third-party source, nothing to attribute).
##
## WHY THIS SUITE EXISTS: `cultivated_field`, `water`, and `wild_grass` still point their
## `model_scene` at one of these (no real asset imported yet), so a broken grey-box is
## still a broken terrain definition for those three. `grass`, `forest`, and `rock` have
## been repointed at real imported art (see their `.tres` header comments) and no longer
## read these scenes at runtime; their three grey-boxes are kept and still validated here
## as the standby if the imported models' look pass fails, same rationale as `house`
## below. `--headless --path project --quit` is a PARSE check and would not catch a
## broken grey-box; only an actual load and instantiate does.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_placeholder_scenes.gd
##
## SCOPE: structural only. Colour, size and proportion are PLACEHOLDERS at stated
## baselines and are a human taste call (each scene's header comment says so) — this suite
## asserts nothing about them, and must not start to.

## Fixed literal, which is what keeps the assertion count fixed: 7 scenes x 3 checks.
## house/House.tscn is included and is the grey-box FALLBACK — data/buildings/house.tres
## ships the real imported asset. It is validated anyway because it is the standby if the
## imported model's facing fails its look pass.
const SCENES: PackedStringArray = [
	"res://assets/placeholder/cultivated_field/CultivatedField.tscn",
	"res://assets/placeholder/forest/Forest.tscn",
	"res://assets/placeholder/grass/Grass.tscn",
	"res://assets/placeholder/house/House.tscn",
	"res://assets/placeholder/rock/Rock.tscn",
	"res://assets/placeholder/water/Water.tscn",
	"res://assets/placeholder/wild_grass/WildGrass.tscn",
]


func _init() -> void:
	begin("placeholder grey-box scenes")

	for path: String in SCENES:
		var packed: PackedScene = load(path) as PackedScene
		if not check(packed != null, "%s loads as PackedScene" % path):
			continue

		# can_instantiate() is the cheap precondition; instantiate() is the one that
		# actually proves it, because a scene can report true and still fail on a missing
		# sub-resource. Both are asserted so a failure says which stage broke.
		check(packed.can_instantiate(), "%s can_instantiate()" % path)

		var node: Node = packed.instantiate()
		if check(node != null, "%s instantiates without error" % path):
			node.free()

	check_eq(SCENES.size(), 7, "all seven grey-box scenes are covered")

	finish()
