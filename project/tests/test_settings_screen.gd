extends QATestCase
## THE TITLE-SCREEN SETTINGS PAGE (2026-08-25 move off `MenuWindow`'s Tab popup). Confirms
## `scenes/menu/SettingsScreen.tscn` hosts the REAL `SettingsOverlay` control — Master Volume
## slider + Gameplay Hints toggle, reading/writing the one `GameplaySettings` source of truth —
## not the old `coming_soon_screen.gd` placeholder text this scene used to carry.
##
## Run:
##   bash scripts/run-tests.sh settings_screen

const SCENE_PATH: String = "res://scenes/menu/SettingsScreen.tscn"

var _screen: Control = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("settings screen (Title-reachable)")
	GameplaySettings.reset_for_test()

	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if not check(packed != null, "%s loads" % SCENE_PATH):
		finish()
		return
	_screen = packed.instantiate() as Control
	root.add_child(_screen)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 2:
		return false

	var overlay: SettingsOverlay = _screen.get_node_or_null("%SettingsOverlay") as SettingsOverlay
	check(overlay != null, "the page hosts a real SettingsOverlay instance")

	if overlay != null:
		check_eq(overlay.hints_checked(), GameplaySettings.hints_enabled(),
			"the hosted overlay paints its Hints checkbox from the live GameplaySettings value")

		overlay._on_hints_toggled(false)
		check_eq(GameplaySettings.hints_enabled(), false,
			"toggling Hints here writes straight through to GameplaySettings, the one source of "
			+ "truth — same shape as when this control lived inside MenuWindow")

	check(_screen.get_node_or_null("%BackButton") != null,
		"the page still offers a Back button to the Title screen")

	GameplaySettings.reset_for_test()
	_screen.queue_free()
	finish()
	return true
