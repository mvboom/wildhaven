class_name FactCard
extends Control
## The signature move-in card, and the curious tap's replay — Tier 1 row 7, thin form.
##
## Two entry points, and **both are floor, not depth**:
##   1. `WorldRoot.resident_arrived` fires it. That is the payoff the whole loop is built
##      around (gdd.md -> Core Loop step 4).
##   2. An Inspect tap on a resident replays it. spec.md -> "Not depth axes" lists
##      fact-card **tap-to-replay** explicitly: "Pillar 4 delivers facts on success *and* on
##      curiosity."
##
## LAYOUT is spec.md -> Screen Layouts verbatim: a centred card that **never fills the
## screen** (the world stays visible and simulating behind it), portrait, species name plus
## the 🔊 button, a rule, the 1–2 sentence body in large plain type, a dismiss control — and
## tapping anywhere outside dismisses too.
##
## COPY IS NOT THIS FILE'S. Every player-facing word on the card comes from the species'
## `AnimalDefinition` (`display_name`, `effective_fact_text()` — index 0 of `fact_text_pool`,
## -> D-47). A species whose pool holds a `PLACEHOLDER`-prefixed entry renders it exactly as
## authored — surfacing that the content gate is still open is the correct behaviour, and
## quietly substituting nicer words would hide it.
##
## THE WORLD IS NEVER PAUSED behind the card (Pillar 1: "there is nothing to protect the
## player from"). Nothing in this file touches the tree's pause state.

## Emitted whenever the card closes, by either dismiss route.
signal dismissed()

## REVERSED 2026-08-01 (-> D-29), closing Open Question #13 (Read-Aloud default state).
## `true` makes every card read itself aloud the moment it appears (`show_card()` below),
## through the same `ReadAloud.speak()` path the 🔊 button uses — gated, as of the speaking
## toggle below, on `GameplaySettings.speaking_enabled()` too, so a player who mutes it does
## not get talked over on the next card.
const AUTO_SPEAK: bool = true

## The glyphs spec.md's layout draws. Isolated here because the engine's default font almost
## certainly has no 🔊 — see the build report; swapping these for icon textures is a
## one-line change plus a tech-art asset, and nothing else in the file assumes text.
const READ_ALOUD_GLYPH: String = "🔊"
const MUTED_GLYPH: String = "🔇"
const DISMISS_GLYPH: String = "×"


var _spoken_text: String = ""

@onready var _scrim: ColorRect = %Scrim
@onready var _species_name: Label = %SpeciesName
@onready var _body: Label = %Body
@onready var _read_aloud_button: Button = %ReadAloudButton
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	_read_aloud_button.text = READ_ALOUD_GLYPH
	_close_button.text = DISMISS_GLYPH
	UiPalette.paint_button(_read_aloud_button, false)
	UiPalette.paint_button(_close_button, false)
	_scrim.color = UiPalette.SCRIM
	_scrim.gui_input.connect(_on_scrim_input)
	_read_aloud_button.pressed.connect(_on_speaking_toggle_pressed)
	_close_button.pressed.connect(dismiss)
	# A control that cannot do anything is worse than no control (Pillar 1): on a machine
	# with no voice the button is simply not there, and the card is otherwise identical.
	_read_aloud_button.visible = ReadAloud.available()
	_paint_speaking_toggle()


## Shows the card for a species definition. Null-safe: a species with no definition yet
## produces no card rather than a broken one.
func show_species(species: AnimalDefinition) -> bool:
	if species == null:
		return false
	return show_card(species.display_name, species.effective_fact_text())


## Shows the card from raw strings. Public so the future building-flavour card (gdd.md ->
## Inspect Mode) and the row-10 warning can reuse the same panel without a second layout.
func show_card(title: String, body: String) -> bool:
	if title.strip_edges().is_empty() and body.strip_edges().is_empty():
		return false
	_species_name.text = title
	_body.text = body
	_spoken_text = "%s. %s" % [title, body] if not title.is_empty() else body
	visible = true
	move_to_front()
	_paint_speaking_toggle()
	if AUTO_SPEAK and GameplaySettings.speaking_enabled():
		ReadAloud.speak(_spoken_text)
	return true


func dismiss() -> void:
	if not visible:
		return
	visible = false
	ReadAloud.stop()
	dismissed.emit()


func is_open() -> bool:
	return visible


## The text the 🔊 button would speak. Exposed for tests; there is no other way to observe
## Read-Aloud on a machine with no voices.
func spoken_text() -> String:
	return _spoken_text


func read_aloud() -> bool:
	return ReadAloud.speak(_spoken_text)


## The 🔊 button IS the speaking toggle — not a separate replay control — so a tap flips the
## ONE shared `GameplaySettings.speaking_enabled()` flag every card and the title screen read.
## Turning speaking back on replays the open card immediately, as audible confirmation the
## setting took effect. Returns the new state, for tests.
func toggle_speaking() -> bool:
	var enabled: bool = not GameplaySettings.speaking_enabled()
	GameplaySettings.set_speaking_enabled(enabled)
	_paint_speaking_toggle()
	if enabled:
		read_aloud()
	else:
		ReadAloud.stop()
	return enabled


func _paint_speaking_toggle() -> void:
	_read_aloud_button.text = READ_ALOUD_GLYPH if GameplaySettings.speaking_enabled() else MUTED_GLYPH


func _on_speaking_toggle_pressed() -> void:
	toggle_speaking()


## "tap anywhere outside also dismisses" (spec.md). The scrim covers the whole screen and
## the card sits on top of it, so any press the card itself did not take lands here.
func _on_scrim_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		dismiss()
		accept_event()
