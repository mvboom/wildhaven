extends QATestCase
## THE DISPLACEMENT WARNING'S 🔊 BUTTON RESPECTS THE SHARED SPEAKING TOGGLE TOO.
##
## `test_gentle_displacement.gd` owns the GentleDisplacement payload itself and deliberately
## never touches this UI scene (see that file's own pending notes). This suite owns exactly the
## one thing this change adds to it: `DisplacementNotice.show_warning()` must offer 🔊 only when
## `GameplaySettings.speaking_enabled()` is on — the same global mute `FactCard`'s own toggle
## writes (`test_fact_card.gd`) — so turning speaking off silences EVERY Read-Aloud surface, not
## just fact cards.
##
## STRUCTURAL, same reason as `test_fact_card.gd`'s `_check_auto_speak_fires_on_open()`: there
## is no TTS voice in this headless container, so `ReadAloud.available()` is always false and
## the button is always hidden regardless of the setting — observation alone cannot distinguish
## "no voice" from "speaking turned off". What CAN be pinned is that `show_warning()`'s own body
## reads the shared setting when deciding whether to offer the button.
##
## Run:
##   bash scripts/run-tests.sh displacement_notice_speaking

const SCRIPT_PATH: String = "res://scripts/ui/displacement_notice.gd"


func _initialize() -> void:
	begin("displacement notice speaking toggle")

	var source: String = (load(SCRIPT_PATH) as GDScript).source_code
	var start: int = source.find("func show_warning(")
	check(start >= 0, "displacement_notice.gd declares show_warning()")
	var next_func: int = source.find("\nfunc ", start + 1)
	var body: String = source.substr(start, (next_func if next_func >= 0 else source.length()) - start)
	check(body.contains("GameplaySettings.speaking_enabled()"),
		"show_warning()'s own body reads the shared speaking setting when deciding whether to "
		+ "offer the 🔊 button")

	finish()
