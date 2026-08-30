extends QATestCase
## THE RIGHT-SIDE ROLLING FEED — Tier 1 rows 7 and 10's non-blocking presentation half for
## repeat Fact Cards and Displacement Warnings. See docs/superpowers/specs/
## 2026-08-23-notification-surfaces-design.md.
##
## Standalone: loads NotificationFeed.tscn directly, the same pattern
## test_displacement_notice.gd and test_news_report.gd's toast checks use — no WorldRoot
## needed, since the feed only ever renders strings handed to it by GameUI.
##
## Run:
##   bash scripts/run-tests.sh notification_feed

const FEED_PATH: String = "res://scenes/ui/NotificationFeed.tscn"

var _feed: NotificationFeed = null
var _setup_ok: bool = false


func _initialize() -> void:
	begin("notification feed")
	var packed: PackedScene = load(FEED_PATH) as PackedScene
	if not check(packed != null, "%s loads" % FEED_PATH):
		finish()
		return
	var node: Node = packed.instantiate()
	if not check(node is NotificationFeed, "%s's root is a NotificationFeed" % FEED_PATH):
		finish()
		return
	_feed = node as NotificationFeed
	root.add_child(_feed)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true

	_check_not_a_modal()
	_check_empty_inputs_produce_nothing()
	_check_fact_entry_renders_full_untruncated_text()
	_check_warning_entry_composes_lead_plus_lines()
	_check_cap_drops_oldest()
	_check_entries_expire()
	_check_tap_to_dismiss_early()
	_check_no_auto_speak()
	_check_no_read_aloud_button()

	finish()
	return true


func _check_not_a_modal() -> void:
	check_eq(_feed.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"NOT A MODAL: the feed's root ignores the mouse everywhere except its own entries")


func _check_empty_inputs_produce_nothing() -> void:
	check(not _feed.show_fact("Fox", ""), "an empty fact body produces no entry")
	check(not _feed.show_warning({"mode": "mixed", "homes": []}),
		"a warning with no homes produces no entry")
	check_eq(_feed.entry_count(), 0, "...and nothing is showing")


func _check_fact_entry_renders_full_untruncated_text() -> void:
	var body: String = "Foxes have excellent hearing and can rotate their ears toward quiet sounds."
	check(_feed.show_fact("Fox", body), "a real fact entry shows")
	check_eq(_feed.entry_count(), 1, "...one entry now on the stack")
	check_eq(_feed.entry_texts()[0], "Fox. %s" % body,
		"...rendering the COMPLETE body, title plus text, nothing truncated — there is no "
		+ "expand control, so the small entry has to be the whole thing")
	_clear_all()


func _check_warning_entry_composes_lead_plus_lines() -> void:
	var fox_home: Dictionary = {
		"species_id": "fox", "display_name": "Fox", "is_structure_home": false, "binding_need": ""
	}
	var rabbit_home: Dictionary = {
		"species_id": "rabbit", "display_name": "Rabbit", "is_structure_home": false, "binding_need": ""
	}
	var warning: Dictionary = {"mode": DisplacementCopy.MODE_BUILD, "homes": [fox_home, rabbit_home]}
	check(_feed.show_warning(warning), "a warning with affected homes shows")
	var text: String = _feed.entry_texts()[0]
	check(text.begins_with(DisplacementCopy.lead(DisplacementCopy.MODE_BUILD)),
		"...leading with the SAME lead sentence DisplacementCopy.lead() supplies")
	check(text.contains(DisplacementCopy.warn_line("fox", "Fox", false, "")),
		"...and the fox family's own line, composed the same way DisplacementNotice does")
	check(text.contains(DisplacementCopy.warn_line("rabbit", "Rabbit", false, "")),
		"...and the rabbit family's own line")
	_clear_all()


func _check_cap_drops_oldest() -> void:
	for i: int in range(NotificationFeed.MAX_VISIBLE_ENTRIES):
		_feed.show_fact("Species %d" % i, "Fact %d." % i)
	check_eq(_feed.entry_count(), NotificationFeed.MAX_VISIBLE_ENTRIES,
		"the stack holds exactly MAX_VISIBLE_ENTRIES after filling it")

	_feed.show_fact("Newcomer", "One more fact.")
	check_eq(_feed.entry_count(), NotificationFeed.MAX_VISIBLE_ENTRIES,
		"...and adding one more does NOT grow past the cap")
	check(_feed.entry_texts().has("Newcomer. One more fact."), "...the newest entry is present")
	check(not _feed.entry_texts().has("Species 0. Fact 0."),
		"...and the OLDEST entry was the one dropped to make room")
	_clear_all()


func _check_entries_expire() -> void:
	_feed.show_fact("Fox", "A quick fact.")
	check_eq(_feed.entry_count(), 1, "an entry shows")
	# AUTO-EXPIRE, exercised without waiting real seconds. `_process(delta)` is a plain method
	# despite the underscore — calling it directly with a hand-picked delta is the same idiom
	# test_news_report.gd uses for NewsReportToast.DISPLAY_SECONDS.
	_feed._process(NotificationFeed.ENTRY_HOLD_SECONDS - 0.5)
	check_eq(_feed.entry_count(), 1, "...still up half a second before its own hold time")
	_feed._process(1.0)
	check_eq(_feed.entry_count(), 0, "...and gone once ENTRY_HOLD_SECONDS has elapsed")


func _check_tap_to_dismiss_early() -> void:
	_feed.show_fact("Fox", "A quick fact.")
	check_eq(_feed.entry_count(), 1, "an entry shows")
	var dismiss_button: Button = _find_dismiss_button()
	check(dismiss_button != null, "...and its dismiss control is reachable")
	dismiss_button.pressed.emit()
	check_eq(_feed.entry_count(), 0, "...tapping dismiss removes it early, before ENTRY_HOLD_SECONDS")


func _check_no_auto_speak() -> void:
	# STRUCTURAL, same reason test_fact_card.gd's own auto-speak check and
	# test_news_report.gd's "NO READ-ALOUD BUTTON" check are structural: there is no TTS voice
	# in this headless container, so ReadAloud.speak() cannot be observed to actually fire.
	# What CAN be pinned is that `_push()` — the one function both show_fact() and
	# show_warning() funnel through — never calls ReadAloud.speak() itself; only a per-entry
	# button's own `pressed` handler does, so a burst of arrivals cannot talk over itself.
	var source: String = (load("res://scripts/ui/notification_feed.gd") as GDScript).source_code
	var start: int = source.find("func _push(")
	check(start >= 0, "notification_feed.gd declares _push()")
	var next_func: int = source.find("\nfunc ", start + 1)
	var body: String = source.substr(start, (next_func if next_func >= 0 else source.length()) - start)
	check(not body.contains("ReadAloud.speak"),
		"_push()'s own body never calls ReadAloud.speak() — no entry reads itself aloud on arrival")


func _check_no_read_aloud_button() -> void:
	# NO 🔊 ON A FEED ENTRY. Read-Aloud is the scrim'd first-arrival FactCard's alone now; a
	# nine-second, never-auto-speaking entry is not a consent surface. Observational, not
	# structural: an entry's whole node tree is built in _make_entry(), so a real scan for a
	# Button carrying the 🔊 glyph is decisive here (unlike the auto-speak check above).
	_feed.show_fact("Fox", "A quick fact.")
	check_eq(_feed.entry_count(), 1, "an entry shows")
	var has_read_aloud: bool = false
	for child: Node in _feed.find_children("*", "Button", true, false):
		if (child as Button).text == "🔊":
			has_read_aloud = true
	check(not has_read_aloud, "...and it carries NO 🔊 button — only the corner × dismiss")
	_clear_all()


func _find_dismiss_button() -> Button:
	for child: Node in _feed.find_children("*", "Button", true, false):
		if (child as Button).text == NotificationFeed.DISMISS_GLYPH:
			return child as Button
	return null


func _clear_all() -> void:
	while _feed.entry_count() > 0:
		var button: Button = _find_dismiss_button()
		if button == null:
			break
		button.pressed.emit()
