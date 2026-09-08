extends QATestCase
## THE TITLE-SCREEN CREDITS PAGE (2026-08-25 move off `MenuWindow`'s Tab popup). Confirms
## `scenes/menu/CreditsScreen.tscn` hosts the REAL `CreditsScreen` control — EVERY attribution
## source read through `AttributionCatalog` (2026-08-25: widened from binding-only to all
## sources, so CC0 packs get thanked too, not just the one the license compels) — not the old
## `coming_soon_screen.gd` placeholder text this scene used to carry. Release-checklist Gate 2
## requires the binding Sherkiz credit be visible to the player somewhere in the shipped
## build; this is that somewhere, now alongside every courtesy credit too.
##
## ALSO GUARDS THE LIST'S MOUSE-WHEEL REACHABILITY (2026-09-08 bug). The credits list
## renders more entries than fit, so its `ScrollContainer` is the only way a player reads
## the bottom of it. The container shipped with `mouse_filter = 2` (MOUSE_FILTER_IGNORE),
## which takes it out of the viewport's GUI hit test entirely — the wheel event never
## reaches `_gui_input()` and the list is frozen no matter where you click first. Nothing
## about that is visible in a static read of the rendered text, hence the live wheel event
## pushed through the viewport below. `FieldGuide.tscn`'s identically-shaped ListScroll
## sets `mouse_filter = 0` and is the working reference.
##
## Run:
##   bash scripts/run-tests.sh credits_screen

const SCENE_PATH: String = "res://scenes/menu/CreditsScreen.tscn"

var _screen: Control = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("credits screen (Title-reachable)")

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

	var credits: CreditsScreen = _screen.get_node_or_null("%CreditsScreen") as CreditsScreen
	check(credits != null, "the page hosts a real CreditsScreen instance")

	if credits != null:
		var all_entries: Array[AttributionEntry] = AttributionCatalog.load_entries()
		check_eq(credits.is_empty_state_visible(), all_entries.is_empty(),
			"the hosted CreditsScreen's empty-state visibility matches whether ANY source "
			+ "exists on disk at all")
		if not all_entries.is_empty():
			check_eq(credits.entry_texts().size(), all_entries.size(),
				"...and every source is rendered — CC0 courtesy packs included, not just the "
				+ "one binding Sherkiz entry")

		var binding: Array[AttributionEntry] = AttributionCatalog.binding_entries()
		var rendered: Array[String] = credits.entry_texts()
		for entry in binding:
			var found: bool = false
			for text: String in rendered:
				if text.contains(entry.required_notice.strip_edges()):
					found = true
			check(found,
				"the binding %s entry's exact required_notice still appears somewhere in the rendered list, unweakened by sitting alongside the courtesy entries" % entry.id)

	check(_screen.get_node_or_null("%BackButton") != null,
		"the page still offers a Back button to the Title screen")

	if credits != null:
		_check_wheel_scrolls(credits)

	_screen.queue_free()
	finish()
	return true


## The wheel must actually move the list. Asserted as a real `InputEventMouseButton` pushed
## through the viewport rather than a direct `_gui_input()` call, because the defect this
## guards is purely in the HIT TEST — a `MOUSE_FILTER_IGNORE` container still scrolls fine
## when its `_gui_input()` is invoked by hand, so calling it directly would report green on
## exactly the broken screen.
func _check_wheel_scrolls(credits: CreditsScreen) -> void:
	var scroll: ScrollContainer = _find_scroll(credits)
	if not check(scroll != null, "the credits list is hosted in a ScrollContainer"):
		return

	check(scroll.mouse_filter != Control.MOUSE_FILTER_IGNORE,
		"the credits ScrollContainer takes part in mouse hit-testing (not MOUSE_FILTER_IGNORE)",
		"MOUSE_FILTER_IGNORE removes it from the viewport's GUI pick, so no wheel event "
		+ "can ever reach it")

	var bar: VScrollBar = scroll.get_v_scroll_bar()
	if bar == null or bar.max_value <= bar.page:
		note_expected_pending("wheel actually scrolls the credits list",
			"list content currently fits the viewport, so there is nothing to scroll")
		return

	var before: int = scroll.scroll_vertical
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = scroll.get_global_rect().get_center()
	wheel.global_position = wheel.position
	# `true` = the position is ALREADY in viewport coordinates. Without it `push_input()`
	# treats the position as embedder/screen space and divides it through the window's
	# content scale — headless runs with a 64x64 window against a 1152-wide viewport, an
	# 18x factor that throws the event clean off the list and reports a false red.
	root.push_input(wheel, true)

	check(scroll.scroll_vertical > before,
		"a mouse wheel event over the credits list scrolls it",
		"scroll_vertical stayed at %d" % before)


func _find_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node as ScrollContainer
	for child: Node in node.get_children():
		var found: ScrollContainer = _find_scroll(child)
		if found != null:
			return found
	return null
