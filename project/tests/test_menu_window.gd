extends QATestCase
## THE MENU WINDOW'S SHELL (terraform-bar rework). Terrain/Buildings browse grids and their
## drag-and-drop assignment retired with the old slot hotbar — see `menu_window.gd`'s own
## header. Settings/Credits tabs retired too (2026-08-25 — moved to their own Title-screen
## pages; see `test_title_screen.gd` and the credits/settings screen tests for those). This
## suite covers what remains: open/close, the sole Field Guide tab, and that it refreshes live.
##
## Run:
##   bash scripts/run-tests.sh menu_window

const WORLD_PATH: String = "res://scenes/Main.tscn"
const MENU_WINDOW_SCENE_PATH: String = "res://scenes/ui/MenuWindow.tscn"

var _world: WorldRoot = null
var _ui: GameUI = null
var _hud: GameHud = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("menu window shell")
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		finish()
		return
	_world = node as WorldRoot
	root.add_child(_world)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	var ui_node: Node = _world.get_node_or_null("GameUI")
	if not check(ui_node is GameUI, "Main.tscn instances the GameUI shell"):
		finish()
		return true
	_ui = ui_node as GameUI
	_ui.bind_world()
	_hud = _ui.hud

	_check_open_close()
	_check_defaults_to_field_guide_tab()
	_check_terrain_and_building_tabs_are_gone()
	_check_settings_and_credits_tabs_are_gone()
	_check_field_guide_is_a_hosted_tab()

	finish()
	return true


## Loads and instantiates the real `MenuWindow.tscn` — the same pattern every other
## scene-backed UI class's suite in this codebase already uses (e.g.
## `test_saved_worlds_screen.gd`'s own `packed.instantiate()`). `MenuWindow.new()` would only
## attach the script to a bare `Control`, with none of the `.tscn`'s authored `Scrim`/`Tabs`/
## `CloseButton` children, so `@onready var _scrim: ColorRect = %Scrim` (and its siblings)
## would have nothing to resolve.
func _make_menu_window() -> MenuWindow:
	var packed: PackedScene = load(MENU_WINDOW_SCENE_PATH) as PackedScene
	return packed.instantiate() as MenuWindow


func _check_open_close() -> void:
	var window := _make_menu_window()
	root.add_child(window)
	check(not window.is_open(), "a fresh MenuWindow starts closed")
	window.open(_world)
	check(window.is_open(), "open() opens it")
	window.close()
	check(not window.is_open(), "close() closes it")
	window.queue_free()


func _check_defaults_to_field_guide_tab() -> void:
	var window := _make_menu_window()
	root.add_child(window)
	window.open(_world)
	var tabs: TabContainer = window.get_node("%Tabs") as TabContainer
	check_eq(tabs.current_tab, MenuWindow.FIELD_GUIDE_TAB_INDEX,
		"the window opens on the Field Guide tab (index 0) — Terrain/Buildings retired, "
		+ "nothing browsable came before it any more")
	window.close()
	window.queue_free()


## THE RETIREMENT ITSELF. `GameHud`'s palette row now shows every terrain and building
## permanently, so the old browse-and-drag grids have nothing left to do — see
## `menu_window.gd`'s own header for why this is a removal, not a hide.
func _check_terrain_and_building_tabs_are_gone() -> void:
	var window := _make_menu_window()
	root.add_child(window)
	window.open(_world)
	check(window.get_node_or_null("%TerrainGrid") == null,
		"the retired Terrain browse grid no longer exists")
	check(window.get_node_or_null("%BuildingGrid") == null,
		"the retired Buildings browse grid no longer exists")
	check(window.get_node_or_null("%SlotRow") == null,
		"the retired slot-row mirror no longer exists")
	window.close()
	window.queue_free()


## THE RETIREMENT ITSELF (2026-08-25) — Settings and Credits moved off the in-game Tab popup
## onto their own Title-screen-reachable pages (`scenes/menu/SettingsScreen.tscn`,
## `scenes/menu/CreditsScreen.tscn`); see `test_settings_screen.gd`/`test_credits_screen.gd`
## for the real content living there now.
func _check_settings_and_credits_tabs_are_gone() -> void:
	var window := _make_menu_window()
	root.add_child(window)
	window.open(_world)
	check(window.get_node_or_null("%SettingsOverlay") == null,
		"the retired Settings tab no longer exists")
	check(window.get_node_or_null("%CreditsScreen") == null,
		"the retired Credits tab no longer exists")
	check((window.get_node("%Tabs") as TabContainer).get_tab_count() == 1,
		"Field Guide is the only tab left")
	window.close()
	window.queue_free()


func _check_field_guide_is_a_hosted_tab() -> void:
	var window := _make_menu_window()
	root.add_child(window)
	window.open(_world)

	var field_guide: FieldGuide = window.get_node_or_null("%FieldGuide") as FieldGuide
	check(field_guide != null, "the Field Guide tab hosts a real FieldGuide instance")
	if field_guide != null:
		check(field_guide.species_row_texts().size() > 0,
			"...and it has been refreshed against the live world on open()")

	window.close()
	window.queue_free()
