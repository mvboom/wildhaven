extends QATestCase
## Proves FidelityProbe reads a real imported model correctly.
##
## Sheep is the fixture because its source values are known and measured:
## Sheep.gltf carries 2 materials (0.8 grey, 0.0374 black), COLOR_0 vertex colours,
## 6 animation clips, and no textures at all -- the Quaternius shape, where colour lives
## in vertex data rather than in an image.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_fidelity_probe.gd

const WRAPPER: String = "res://assets/animals/sheep/Sheep.tscn"

func _init() -> void:
	begin("fidelity probe")
	var m: Dictionary = FidelityProbe.probe(WRAPPER)
	check(not m.is_empty(), "probe returns a manifest")
	check_eq(m.get("materials", -1), 2, "Sheep has two runtime materials")
	check_eq(m.get("vertex_colors", false), true,
		"Sheep uses vertex colour as albedo -- false here is the flat-grey bug")
	check_eq(m.get("textures", ["x"]), [], "Sheep has no textures")
	check_eq(m.get("clips", []).size(), 6, "Sheep has six clips")
	check(m.get("joints", 0) > 0, "Sheep is rigged")
	check(m.get("vertices", 0) > 0, "Sheep has vertices")
	check_eq(m.get("base_colors", []).size(), 2, "two base colours, one per material")
	finish()
