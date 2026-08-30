class_name CreditsScreen
extends Control
## Tier 1 row 15's release blocker — the in-game Credits screen. The Sherkiz "Rabbit"
## model ships under CC BY 3.0, whose attribution condition requires the credit be visible
## **to the player**; `project/CREDITS.md` being complete does not satisfy that (it lives
## in the repo, not the shipped build). See release-checklist.md -> Gate 2 and
## `project/attribution/sources/sherkiz_rabbit.tres`.
##
## READS `AttributionEntry` .tres RESOURCES THROUGH `AttributionCatalog`, THE SAME LOADER
## `generate_credits.gd` READS THROUGH — not a hand-copied list of license strings. The two
## surfaces (this screen, CREDITS.md) can drift from each other only if the shared loader
## itself changes, never by one of them going stale against the source .tres files.
##
## SHOWS EVERY SOURCE (2026-08-25), not just the ones under a binding obligation. Originally
## this rendered only `AttributionCatalog.binding_entries()` — just the Sherkiz Rabbit — on
## the theory that a CC0 pack has no license condition to satisfy here and CREDITS.md already
## carries the full record. Human decision: the player-facing screen should thank every
## source, courtesy or not, not only the one the license compels; CREDITS.md and this screen
## now show the same set (`AttributionCatalog.load_entries()`), differing only in that
## CREDITS.md sections them into "Required" vs. "Acknowledgements" and this screen does not.
## The binding Sherkiz entry still stands out on its own: it is the only one carrying a
## `required_notice` line (see `_entry_text()`), so nothing about its release-blocker status
## (release-checklist.md -> Gate 2) is weakened by sitting in the same list as the others.
##
## Reachable from the Title screen's Credits button, hosted inside
## `scenes/menu/CreditsScreen.tscn` (2026-08-25 human decision) — no longer a `MenuWindow` tab;
## Settings/Credits both moved off the in-game Tab popup onto their own Title-screen-reachable
## pages, leaving Field Guide as `MenuWindow`'s only tab.

## [COPY] — content-writer's. Shown only if `attribution/sources/` has literally zero
## entries on disk — not the expected state today (seven sources currently ship), but a
## screen that silently renders nothing on an empty list would look broken rather than
## "nothing is owed right now."
const EMPTY_STATE_TEXT: String = "[COPY] Nothing to credit yet."

@onready var _entry_list: VBoxContainer = %EntryList
@onready var _empty_label: Label = %EmptyLabel


func _ready() -> void:
	refresh()


## Public and idempotent, matching `FieldGuide.refresh_from()`'s precedent — a test can
## rebuild the list without waiting on `_ready()`. Attribution data is load-once content,
## not live session state, so nothing in the running game needs to call this a second
## time, but the shape costs nothing and matches the rest of this window's tabs.
func refresh() -> void:
	_clear_list()
	var entries: Array[AttributionEntry] = AttributionCatalog.load_entries()
	if entries.is_empty():
		_set_empty_state(true)
		return
	_set_empty_state(false)
	for entry in entries:
		_entry_list.add_child(_make_entry_label(entry))


## The rendered text of every credited entry, top to bottom — what a test reads instead of
## walking scene nodes directly, matching `FieldGuide.species_row_texts()`'s precedent.
func entry_texts() -> Array[String]:
	var out: Array[String] = []
	if _entry_list == null:
		return out
	for child: Node in _entry_list.get_children():
		if child is Label:
			out.append((child as Label).text)
	return out


func is_empty_state_visible() -> bool:
	return _empty_label != null and _empty_label.visible


func _make_entry_label(entry: AttributionEntry) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", UiPalette.FONT_CARD_BODY)
	label.add_theme_color_override("font_color", UiPalette.BARK)
	label.text = _entry_text(entry)
	return label


## The exact required notice, verbatim from the .tres entry — never paraphrased, per the
## license condition itself (the same "exact-matched" standard test_attribution.gd already
## holds CREDITS.md to).
func _entry_text(entry: AttributionEntry) -> String:
	var lines := PackedStringArray()
	lines.append("%s — %s (%s)" % [entry.creator, entry.source_name, entry.license_name])
	if not entry.required_notice.strip_edges().is_empty():
		lines.append(entry.required_notice.strip_edges())
	# Per-file-licensed sources (freesound.org-style; none exist yet, but the schema
	# supports them — see attribution_entry.gd) carry their own per-asset notices rather
	# than one source-level notice.
	for asset in entry.assets:
		if asset != null and asset.attribution_required \
				and not asset.required_notice.strip_edges().is_empty():
			lines.append("%s — %s" % [asset.asset_name, asset.required_notice.strip_edges()])
	return "\n".join(lines)


func _clear_list() -> void:
	if _entry_list == null:
		return
	for child: Node in _entry_list.get_children():
		# `remove_child()` first, not just `queue_free()` alone — matches
		# `field_guide.gd`'s own `_clear_list()`, for the same reason: a second `refresh()`
		# in the same frame would otherwise still see the stale rows via `get_children()`.
		_entry_list.remove_child(child)
		child.queue_free()


func _set_empty_state(empty: bool) -> void:
	if _empty_label != null:
		_empty_label.text = EMPTY_STATE_TEXT
		_empty_label.visible = empty
	if _entry_list != null:
		_entry_list.visible = not empty
