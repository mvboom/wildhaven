extends QATestCase
## THE TITLE-SCREEN CREDITS PAGE (2026-08-25 move off `MenuWindow`'s Tab popup). Confirms
## `scenes/menu/CreditsScreen.tscn` hosts the REAL `CreditsScreen` control — EVERY attribution
## source read through `AttributionCatalog` (2026-08-25: widened from binding-only to all
## sources, so CC0 packs get thanked too, not just the one the license compels) — not the old
## `coming_soon_screen.gd` placeholder text this scene used to carry. Release-checklist Gate 2
## requires the binding Sherkiz credit be visible to the player somewhere in the shipped
## build; this is that somewhere, now alongside every courtesy credit too.
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

	_screen.queue_free()
	finish()
	return true
