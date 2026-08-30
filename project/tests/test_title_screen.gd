extends QATestCase
## THE TITLE SCREEN'S SPEAKING TOGGLE — lets a player turn narration off before a game even
## starts, reading and writing the SAME `GameplaySettings.speaking_enabled()` flag `FactCard`'s
## own 🔊 button does (`test_fact_card.gd`'s `_check_speaking_toggle_is_global_and_persists()`),
## not a separate title-screen-only preference.
##
## Waits a couple of frames after `add_child()` before asserting anything, same as
## `test_saved_worlds_screen.gd` — `_ready()` (which paints the checkbox) has not necessarily
## run the instant the node enters the tree.
##
## Run:
##   bash scripts/run-tests.sh title_screen

const SCENE_PATH: String = "res://scenes/TitleScreen.tscn"

var _screen: TitleScreen = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("title screen")
	GameplaySettings.set_speaking_enabled(false)

	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if not check(packed != null, "%s loads" % SCENE_PATH):
		finish()
		return
	_screen = packed.instantiate() as TitleScreen
	root.add_child(_screen)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 2:
		return false

	_check_layout_is_not_collapsed()

	check_eq((_screen.get_node("%BuildTag") as Label).text, "Built %s" % BuildInfo.BUILD_TIMESTAMP,
		"the build tag reads BuildInfo.BUILD_TIMESTAMP live — scripts/build-game.sh stamps "
		+ "that constant at export time, this just renders whatever it holds")

	check_eq(_screen.speaking_checked(), false,
		"a freshly-instantiated title screen paints the checkbox from GameplaySettings' live value")

	_screen._on_speaking_toggled(true)
	check_eq(GameplaySettings.speaking_enabled(), true,
		"toggling the checkbox writes straight through to GameplaySettings — no second copy of "
		+ "the value, same shape as SettingsOverlay's Hints checkbox")

	check_eq((_screen.get_node("%SpeakingCheck") as Control).visible, false,
		"there is no TTS voice in this headless container, so the toggle degrades the same way "
		+ "FactCard's own 🔊 button does — hidden, not a dead control (Pillar 1)")

	_screen.queue_free()
	GameplaySettings.reset_for_test()
	finish()
	return true


## THE ZERO-HEIGHT LAYOUT BUG — a real regression: `%Layout`'s anchors were set via
## `anchors_preset` alone, with only one explicit `anchor_*` override alongside it. Godot
## does NOT derive the other three anchor values from `anchors_preset` at parse time — that
## property is an editor-only hint — so the unset anchors silently kept Control's own
## defaults (0.0), collapsing `%Layout` to a zero-height box pinned to the screen's bottom
## edge. Everything past the visual middle of the button stack (Load Game onward) rendered
## below the viewport, invisible, while only "New Game" happened to fit above the fold.
## Pixel color isn't checkable headlessly, but the collapsed RECT SIZE is — this check pins
## that regression at the layer that actually broke.
func _check_layout_is_not_collapsed() -> void:
	var layout: Control = _screen.get_node("%Layout") if _screen.has_node("%Layout") else null
	if layout == null:
		layout = _screen.find_child("Layout", true, false) as Control
	check(layout != null, "TitleScreen has a Layout container")
	if layout == null:
		return

	var viewport_size: Vector2 = _screen.get_viewport().get_visible_rect().size
	check(layout.size.y > viewport_size.y * 0.5,
		"%Layout's height is a real majority of the viewport, not collapsed to ~0",
		"layout height %s vs viewport height %s" % [layout.size.y, viewport_size.y])
	check(layout.size.x > 200.0,
		"%Layout's width comfortably fits a 320px-wide button, not collapsed to ~0",
		"layout width %s" % layout.size.x)

	# Every interactive control must actually be on screen (0 <= y < viewport height) — the
	# exact symptom the human reported: everything past "New Game" rendered off the bottom.
	var controls: Array[Control] = [
		_screen.get_node("%NewGameButton") as Control,
		_screen.get_node("%LoadGameButton") as Control,
		_screen.get_node("%TutorialButton") as Control,
		_screen.get_node("%HelpButton") as Control,
		_screen.get_node("%CreditsButton") as Control,
		_screen.get_node("%SettingsButton") as Control,
		_screen.get_node("%SpeakingCheck") as Control,
	]
	var off_screen: PackedStringArray = []
	for control: Control in controls:
		var top: float = control.global_position.y
		var bottom: float = top + control.size.y
		if top < 0.0 or bottom > viewport_size.y:
			off_screen.append("%s (top %s, bottom %s)" % [control.name, top, bottom])
	check(off_screen.is_empty(),
		"every title-screen button is fully within the viewport, none rendered below the fold",
		"off-screen: %s" % str(off_screen))
