extends QATestCase
## Proves FidelityProbe reads a real imported model correctly.
##
## Sheep is the fixture because its source values are known and measured:
## Sheep.gltf carries 2 materials (0.8 grey, 0.0374 black), COLOR_0 vertex colours,
## 6 animation clips, and no textures at all -- the Quaternius shape, where colour lives
## in vertex data rather than in an image.
##
## base_colors are expected in LINEAR space (glTF baseColorFactor / Blender BSDF Base
## Color's native space), matching the Python source readers. The runtime engine reads
## BaseMaterial3D.albedo_color back gamma-encoded (sRGB), so FidelityProbe converts with
## Color.srgb_to_linear() before rounding. A small tolerance is used instead of exact
## equality because srgb_to_linear(linear_to_srgb(x)) is a round trip through two power
## functions and is not guaranteed bit-identical to x.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_fidelity_probe.gd

const WRAPPER: String = "res://assets/animals/sheep/Sheep.tscn"
const COLOR_TOLERANCE: float = 0.001

## Stag is the MATERIAL-REUSE fixture, and the only model in the project that has one.
## Stag.gltf declares 5 materials across 6 primitives, refs [0,1,2,3,4,1] -- material 1
## is used twice. `materials` means UNIQUE materials, so the probe must report 5 while
## `surfaces` still reports 6. Appending one row per surface reported 6, which made a
## correct import fail two FAIL-level rules (materials and base_colors) against a source
## that counts 5.
const REUSE_WRAPPER: String = "res://assets/animals/stag/Stag.tscn"
const REUSE_MATERIALS: int = 5
const REUSE_SURFACES: int = 6

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
	var colors: Array = m.get("base_colors", [])
	check_eq(colors.size(), 2, "two base colours, one per material")
	var black: Array = [0.0374, 0.0374, 0.0374, 1.0]
	var grey: Array = [0.8, 0.8, 0.8, 1.0]
	check(colors.size() == 2 and _approx(colors[0], black, COLOR_TOLERANCE),
		"first base colour is linear black (~0.0374), matching the source manifest",
		"got %s" % [colors[0] if colors.size() > 0 else null])
	check(colors.size() == 2 and _approx(colors[1], grey, COLOR_TOLERANCE),
		"second base colour is linear grey (~0.8), matching the source manifest",
		"got %s" % [colors[1] if colors.size() > 1 else null])

	# A material used on two surfaces is ONE material. Deduplicated by resource
	# instance id, so two genuinely distinct materials that happen to share a base
	# colour are still two -- identity, not value.
	var s: Dictionary = FidelityProbe.probe(REUSE_WRAPPER)
	check(not s.is_empty(), "%s probes" % REUSE_WRAPPER)
	check_eq(s.get("surfaces", -1), REUSE_SURFACES,
		"Stag has six surfaces -- surfaces counts geometry and is NOT deduplicated")
	check_eq(s.get("materials", -1), REUSE_MATERIALS,
		"Stag's reused material counts ONCE: five unique materials over six surfaces")
	check_eq(s.get("base_colors", []).size(), REUSE_MATERIALS,
		"one base colour per UNIQUE material, not per surface")
	finish()


## Componentwise |a[i] - b[i]| <= tol for two 4-element [r,g,b,a] arrays.
func _approx(a: Array, b: Array, tol: float) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if absf(a[i] - b[i]) > tol:
			return false
	return true
