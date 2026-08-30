extends QATestCase
## THE WARNING PANEL NEVER EXCEEDS THE VIEWPORT — a bug report: with enough affected families
## in one settled gesture, the centred `%Warning` panel (which sizes itself to fit every line)
## grew past the top AND bottom of the screen, taking `%ButtonRow`'s dismiss control with it —
## an unreachable close button on a real desktop window.
##
## `displacement_notice.gd`'s `_clamp_lines_height()` caps `%LinesScroll` to the viewport at
## `show_warning()` time so `%ButtonRow` always stays on screen; a short warning still renders
## at its natural height (no forced empty space, no scrollbar).
##
## Run:
##   bash scripts/run-tests.sh displacement_notice

const NOTICE_PATH: String = "res://scenes/ui/DisplacementNotice.tscn"

var _notice: DisplacementNotice = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("displacement notice — warning panel stays on screen")
	var packed: PackedScene = load(NOTICE_PATH) as PackedScene
	if not check(packed != null, "%s loads" % NOTICE_PATH):
		finish()
		return
	var node: Node = packed.instantiate()
	if not check(node is DisplacementNotice, "%s's root is a DisplacementNotice" % NOTICE_PATH):
		finish()
		return
	_notice = node as DisplacementNotice
	root.add_child(_notice)
	_setup_ok = true


## Each `show_warning()` gets its own settled frame before its layout is measured — a
## Container's re-sort after its children change is deferred, so reading `.size` /
## `global_position` in the same frame `show_warning()` ran in would risk measuring the
## PREVIOUS warning's stale layout rather than the one just shown.
func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames == 3:
		_notice.show_warning(_warning_with(["cow"]))
		return false
	if _frames == 4:
		_check_one_family_fits_without_a_scrollbar()
		_notice.dismiss_warning()
		# The reported repro: six families named in one warning at once.
		_notice.show_warning(
			_warning_with(["cow", "rabbit", "deer", "bull", "alpaca", "horse"])
		)
		return false
	if _frames < 5:
		return false

	_check_many_families_keep_the_close_button_on_screen()
	finish()
	return true


func _check_one_family_fits_without_a_scrollbar() -> void:
	var lines_scroll: ScrollContainer = _notice.get_node("%LinesScroll") as ScrollContainer
	var lines: VBoxContainer = _notice.get_node("%Lines") as VBoxContainer
	check(
		is_equal_approx(lines_scroll.size.y, lines.get_combined_minimum_size().y),
		"ONE FAMILY: %LinesScroll renders at the list's own natural height, no forced empty space",
		"scroll height %s vs lines natural height %s" % [
			lines_scroll.size.y, lines.get_combined_minimum_size().y
		]
	)
	_assert_close_button_on_screen("ONE FAMILY")


func _check_many_families_keep_the_close_button_on_screen() -> void:
	check(
		_notice.warning_lines().size() == 6,
		"SIX FAMILIES: the warning still carries one line per affected home"
	)
	var warning_panel: PanelContainer = _notice.get_node("%Warning") as PanelContainer
	var viewport_height: float = _notice.get_viewport_rect().size.y
	check(
		warning_panel.size.y <= viewport_height,
		"SIX FAMILIES: %Warning's total height does not exceed the viewport",
		"panel height %s vs viewport height %s" % [warning_panel.size.y, viewport_height]
	)
	_assert_close_button_on_screen("SIX FAMILIES")
	_notice.dismiss_warning()


func _assert_close_button_on_screen(label: String) -> void:
	var close_button: Button = _notice.get_node("%CloseButton") as Button
	var viewport_size: Vector2 = _notice.get_viewport_rect().size
	var top: float = close_button.global_position.y
	var bottom: float = top + close_button.size.y
	check(
		top >= 0.0 and bottom <= viewport_size.y,
		"%s: %%CloseButton's dismiss control is fully within the viewport" % label,
		"button top %s, bottom %s, viewport height %s" % [top, bottom, viewport_size.y]
	)


func _warning_with(species_ids: Array) -> Dictionary:
	var homes: Array = []
	for species_id: String in species_ids:
		homes.append({
			"species_id": species_id,
			"display_name": species_id.capitalize(),
			"is_structure_home": false,
			"binding_need": "",
		})
	return {"mode": DisplacementCopy.SHIPPING_MODE, "homes": homes, "read_aloud": false}
