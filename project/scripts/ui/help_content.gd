class_name HelpContent
extends Control
## The Help page's content — the one place the game explains itself in words.
##
## REPLACES THE TUTORIAL SCREEN, IT DOES NOT COMPLEMENT IT. `future.md` already deferred the
## standalone Tutorial screen past v1 ("a dedicated onboarding screen beyond v1's first-time
## nudge, which covers minimum onboarding on its own"), and `gdd.md`'s own title-screen
## paragraph lists New Game / Load Game primary with Settings, Help and Credits secondary —
## no Tutorial. Both screens were the same `coming_soon_screen.gd` placeholder; the button is
## now gone and the "if nobody has moved in yet" section below is where its content landed.
##
## THIS IS NOT A GATE AND NOT A LECTURE. Pillar 4 teaches through play, and the First 60
## Seconds guarantee says the pressure valve is content or the arrival delay, "never a forced
## tutorial". Nothing routes a player here, nothing blocks on it. It exists for the stuck
## moment and for the adult sitting next to the player.
##
## COPY LIVES IN `HelpContent.tscn`, NOT HERE. Every player-facing word is an authored
## `Label.text` in the scene, for two reasons: `test_font_glyph_coverage.gd`'s AUTHORED sweep
## already walks every `text = "..."` literal in every `.tscn`, so the page is covered by that
## suite for free; and `spoken_text()` below derives Read-Aloud's script by walking those same
## labels, so what is spoken cannot drift from what is drawn — the same "equality makes drift
## impossible" property `test_fact_card.gd` argues for the fact card's own copy.
##
## THE BUTTON IS PLAY/STOP, NOT `FactCard`'s MUTE TOGGLE. On a fact card the 🔊 button is the
## shared `GameplaySettings.speaking_enabled()` switch, because cards auto-speak on open and
## the only thing left to want is silence. This page deliberately does NOT auto-speak — a
## whole page reading itself at an adult who opened it to skim is exactly the intrusion the
## coach's non-intrusiveness contract avoids — so here the button has to be able to START it.
## A tap therefore reads the page; a tap while reading stops. A tap also turns the shared
## speaking flag back ON if a parent had muted it, because an explicit tap on a control
## labelled "Read this to me" is an explicit request, and a button that can do nothing is
## worse than no button (Pillar 1) — which is also why it is hidden outright when
## `ReadAloud.available()` is false.

## [COPY] The button's two states. Kept as constants rather than authored in the scene because
## the label has to change at runtime; every OTHER word on this page is authored copy.
const READ_LABEL: String = "Read this to me"
const STOP_LABEL: String = "Stop reading"

## Sentence-enders already carried by the authored copy. A collected label that ends in one of
## these is spoken as-is; anything else gets a period appended, so Read-Aloud pauses between
## sections instead of running two headings together into one breath.
const _SENTENCE_ENDERS: String = ".!?:,"

var _reading: bool = false

@onready var _sections: VBoxContainer = %Sections
@onready var _read_button: Button = %ReadAloudButton
@onready var _read_icon: SpeakerIcon = %Icon
@onready var _read_label: Label = %ReadAloudLabel


func _ready() -> void:
	UiPalette.paint_button(_read_button, false)
	_read_button.pressed.connect(_on_read_pressed)
	# A control that cannot do anything is worse than no control (Pillar 1) — the same rule
	# `FactCard` follows for a machine with no TTS voice. The page is otherwise identical.
	var available: bool = ReadAloud.available()
	_read_button.visible = available
	_read_label.visible = available
	set_process(false)
	_paint()


## Only ever runs while this page is the thing speaking, so the poll costs nothing on a page
## nobody asked to have read. Catches the speech ending on its own, which has no signal.
func _process(_delta: float) -> void:
	if _reading and not ReadAloud.speaking():
		_reading = false
		set_process(false)
		_paint()


## Every authored word on the page, in reading order, as one script for Read-Aloud. Derived
## from the live labels rather than duplicated, so spoken and drawn copy are the same copy.
## Public because it is the only way to observe Read-Aloud on a machine with no voices.
func spoken_text() -> String:
	var lines: PackedStringArray = []
	_collect(_sections, lines)
	return "\n".join(lines)


func is_reading() -> bool:
	return _reading


## Reads the page. Returns false when there was nothing to read it with — never an error.
func read_aloud() -> bool:
	if not ReadAloud.speak(spoken_text()):
		return false
	# An explicit tap on "Read this to me" outranks a muted shared flag: honour the request,
	# and leave speaking on so the next fact card speaks too (one flag, never a per-page one).
	# Written only once the speech actually started, so a machine with no voice never silently
	# flips a parent's setting on their behalf.
	GameplaySettings.set_speaking_enabled(true)
	_reading = true
	set_process(true)
	_paint()
	return true


func stop_reading() -> void:
	ReadAloud.stop()
	_reading = false
	set_process(false)
	_paint()


## The button's whole behaviour: start, or stop what this page started. Returns the new
## reading state, for tests.
func toggle_reading() -> bool:
	if _reading:
		stop_reading()
	else:
		read_aloud()
	return _reading


func _on_read_pressed() -> void:
	toggle_reading()


func _paint() -> void:
	_read_label.text = STOP_LABEL if _reading else READ_LABEL
	# The crossed-out speaker means "tap to silence", which is true exactly while this page is
	# the thing making noise — the same glyph `FactCard` uses for the same "a tap makes this
	# quiet" reading, arrived at from the other direction.
	_read_icon.muted = _reading


func _collect(node: Node, into: PackedStringArray) -> void:
	var label := node as Label
	if label != null:
		var text: String = label.text.strip_edges()
		if not text.is_empty():
			var last: String = text.substr(text.length() - 1, 1)
			into.append(text if _SENTENCE_ENDERS.contains(last) else text + ".")
	for child: Node in node.get_children():
		_collect(child, into)
