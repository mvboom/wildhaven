class_name ReadAloud
extends RefCounted
## The Read-Aloud (🔊) slice — Tier 1 row 7's thin form, via OS-level text-to-speech.
##
## gdd.md -> Pillar 5: the audience "spans pre-fluent to fluent readers, motivating the
## Read-Aloud slice on fact cards". spec.md -> Screen Layouts: "The Read-Aloud button (🔊) is
## present on every fact card and on the displacement warning — floor and full alike."
##
## **DEGRADES QUIETLY, NEVER ERRORS.** There is no voice at all in a headless container, and
## a real machine can have TTS disabled or no installed voice. Every entry point checks
## `available()` first and simply does nothing when it is false; `FactCard` hides its button
## in that case rather than offering a control that does nothing. Nothing here can push an
## error, and nothing gates on it — a silent machine must still be able to play the game.
##
## Open Question #13 ("Read-Aloud default state — on or off by default") was closed
## 2026-08-01 (-> D-29): cards now speak themselves on open, via `FactCard.AUTO_SPEAK = true`.
## This class itself is unchanged by that ruling — it still only ever speaks when something
## explicitly asks it to (the auto-speak call and the 🔊 button both go through the same
## `speak()` below); the switch lives on `FactCard`, not here. **Still open, and not this
## row's:** whether a future settings-level Master Volume mute should silence Read-Aloud too,
## or whether it needs its own toggle — Row 15 (Settings & Credits) scope.

## DECIDED 2026-08-01 (-> D-29). Godot's rate is 0.1–10.0 with 1.0 as normal; 0.9 is a touch
## under, for pre-fluent readers.
const SPEECH_RATE: float = 0.9

## DECIDED 2026-08-01 (-> D-29). Godot's volume range is 0–100.
const SPEECH_VOLUME: int = 80


## Is there a voice on this machine? False in headless, false with TTS switched off.
static func available() -> bool:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return false
	return not DisplayServer.tts_get_voices().is_empty()


## Speaks `text`, interrupting anything already speaking so a second tap does not queue a
## backlog. Returns false when there was nothing to speak with — never an error.
static func speak(text: String) -> bool:
	if text.strip_edges().is_empty():
		return false
	if not available():
		return false
	var voices: PackedStringArray = DisplayServer.tts_get_voices_for_language(
		OS.get_locale_language()
	)
	var voice: String = voices[0] if not voices.is_empty() else ""
	if voice.is_empty():
		var all: Array[Dictionary] = DisplayServer.tts_get_voices()
		if all.is_empty():
			return false
		voice = str(all[0].get("id", ""))
	if voice.is_empty():
		return false
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, voice, SPEECH_VOLUME, 1.0, SPEECH_RATE)
	return true


static func stop() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_stop()
