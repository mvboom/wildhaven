extends QATestCase

var _screen: Control = null
var _frames: int = 0

func _initialize() -> void:
	begin("diag")
	var packed: PackedScene = load("res://scenes/menu/CreditsScreen.tscn") as PackedScene
	_screen = packed.instantiate() as Control
	root.add_child(_screen)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	print("root size: ", root.size, " / ", root.get_visible_rect())
	var scroll: ScrollContainer = _find(_screen)
	print("scroll: ", scroll)
	print("  global_rect: ", scroll.get_global_rect())
	print("  mouse_filter: ", scroll.mouse_filter)
	print("  visible_in_tree: ", scroll.is_visible_in_tree())
	var bar := scroll.get_v_scroll_bar()
	print("  bar max/page/value: ", bar.max_value, " / ", bar.page, " / ", bar.value)
	print("  bar visible: ", bar.visible, " rect ", bar.get_global_rect())
	print("  scroll_vertical: ", scroll.scroll_vertical)
	print("  vertical_scroll_mode: ", scroll.vertical_scroll_mode)
	var center: Vector2 = scroll.get_global_rect().get_center()
	print("  center: ", center)
	# who does the viewport pick at that point?
	print("  gui pick: ", _pick(root, center))
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = center
	wheel.global_position = center
	root.push_input(wheel)
	print("  after push scroll_vertical: ", scroll.scroll_vertical, " bar.value ", bar.value)
	# try calling _gui_input directly
	scroll._gui_input(wheel)
	print("  after direct _gui_input: ", scroll.scroll_vertical)
	finish()
	return true

func _pick(node: Node, p: Vector2) -> String:
	var hits: Array[String] = []
	_pick_rec(node, p, hits)
	return ", ".join(hits)

func _pick_rec(node: Node, p: Vector2, hits: Array[String]) -> void:
	if node is Control:
		var c := node as Control
		if c.is_visible_in_tree() and c.get_global_rect().has_point(p):
			hits.append("%s(filter=%d)" % [c.name, c.mouse_filter])
	for ch in node.get_children():
		_pick_rec(ch, p, hits)

func _find(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for ch in node.get_children():
		var f = _find(ch)
		if f != null:
			return f
	return null
