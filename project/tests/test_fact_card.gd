extends QATestCase
## THE FACT CARD — Tier 1 row 7, thin form, driven on the real `scenes/Main.tscn`.
##
## gdd.md -> Core Loop step 4: the card is the payoff the whole loop exists to deliver.
## spec.md -> "Not depth axes" lists fact-card **tap-to-replay** explicitly: "Pillar 4
## delivers facts on success *and* on curiosity" — so the replay is an invariant, not depth.
##
## THE ASSERTION THAT MATTERS MOST: **every word on the card equals the species' own
## `AnimalDefinition` data, verbatim.** Not "non-empty", not "contains the name" — equal. A
## card that can render anything other than the roster's own copy can drift away from
## source-verified text, and source verification is the expensive, non-optional step
## (spec.md -> Fact-Card Content Checklist). Equality is what makes drift impossible.
##
## OPEN QUESTION #31 CLOSED 2026-07-28. This suite used to pin `human.tres`'s PLACEHOLDER copy
## rendering AS AUTHORED — correct while the gate was open, and the reason its closure showed up
## here as a failure rather than as a silent drift. The villager's card is now pinned the way
## every other species' is: exact-string equality against the shipped copy, plus the not-a-
## placeholder and banned-word checks the schema suite owns.
##
## THE CAMERA (D-41, fixed pan/zoom, no first-person). Every OTHER tap in this file targets a
## tile/species in front of wherever `CameraRig.initialize()`'s default placement (the world
## bounds' centre, at default zoom) happens to face, or is short-circuited before the camera
## matters at all (`_check_dismiss_routes()`'s tap lands on an OPEN card, which `handle_tap()`
## swallows before it ever queries a tile or a resident — the screen position there is inert by
## construction). TAP-TO-REPLAY is the one exception: it needs a resident actually in frame, so
## it re-focuses the camera on the resident (`set_focus()`/`set_zoom_tiles()`) before tapping the
## screen point it projects to — "focus-and-tap" (D-41), same fixture pattern
## `test_resident_lookup.gd` uses. (This replaces D-33's first-person "look-and-press": park the
## `Player`, `look_at()` the target, tap a fixed screen-centre crosshair — no `Player` exists any
## more.)
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_fact_card.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"
const HUMAN_PATH: String = "res://data/animals/human.tres"

var _world: WorldRoot = null
var _ui: GameUI = null
var _card: FactCard = null
var _hud: GameHud = null
var _router: TapRouter = null
var _camera: Camera3D = null
var _aimed_target: Vector3 = Vector3.ZERO
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("fact card")

	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	var node: Node = packed.instantiate()
	if not check(node is WorldRoot, "Main.tscn's root is a WorldRoot"):
		finish()
		return
	_world = node as WorldRoot
	root.add_child(_world)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	var ui_node: Node = _world.get_node_or_null("GameUI")
	if not check(ui_node is GameUI, "Main.tscn instances the GameUI shell"):
		finish()
		return true
	_ui = ui_node as GameUI
	_ui.bind_world()
	_card = _ui.fact_card
	_hud = _ui.hud
	_router = _ui.tap_router
	_camera = root.get_viewport().get_camera_3d()
	(_camera as CameraRig).initialize()

	_check_card_starts_closed()
	_check_fires_on_resident_arrived()
	_check_repeat_arrival_routes_to_feed()
	_check_text_equals_the_data_for_every_roster_species()
	_check_tap_to_replay_in_inspect()
	_check_dismiss_routes()
	_check_villager_card_renders_the_shipped_copy()
	_check_auto_speak_fires_on_open()
	_check_speaking_toggle_is_global_and_persists()

	note_expected_pending(
		"OPEN QUESTION #31 IS CLOSED; STEP 8 (human sign-off) IS NOT",
		"The villager's move-in card is a REAL fact card, not flavour (roster.md fixes the "
		+ "register), and gdd.md named it the floor's single point of failure with NO substitute "
		+ "path. Content-writer landed source-verified copy on 2026-07-28 and human.tres's header "
		+ "reads \"AWAITING STEP-8 SIGN-OFF\". A villager now moves in and the payoff card reads "
		+ "real copy; whether the sourcing satisfies the human is not a machine check."
	)
	note_expected_pending(
		"READ-ALOUD cannot be exercised headlessly — there is no voice in the container",
		"`ReadAloud.available()` is false here, so `FactCard` hides its 🔊 button and "
		+ "`read_aloud()` returns false without erroring. That degradation IS asserted below; "
		+ "that a voice actually speaks is a human check on a real desktop."
	)

	finish()
	return true


# --- Closed until something happens ------------------------------------------------------------

func _check_card_starts_closed() -> void:
	check(not _card.is_open(), "the card starts closed — nothing is showing at world start")
	check(not _card.show_species(null), "showing a null species produces no card, not a broken one")
	check(not _card.is_open(), "...and the card is still closed")


# --- Entry point 1: the move-in ------------------------------------------------------------------

func _check_fires_on_resident_arrived() -> void:
	# The wiring itself, so this suite fails if the connection is ever dropped rather than
	# passing on a card driven directly.
	check(_world.resident_arrived.is_connected(Callable(_ui, "_on_resident_arrived")),
		"the UI is connected to `WorldRoot.resident_arrived` — the card rides the real signal")

	var rabbit: AnimalDefinition = _world.roster.by_id("rabbit")
	check(rabbit != null, "the rabbit is in the roster the SIMULATION reads")

	_world.resident_arrived.emit("rabbit", _world.grid_to_world(9, 9))

	check(_card.is_open(), "a move-in OPENS the card — row 7's signature moment")
	check_eq(_species_name(), rabbit.display_name,
		"the card's title is the species' own `display_name`")
	check_eq(_body_text(), rabbit.effective_fact_text(),
		"the card's body is the species' own `fact_text`, VERBATIM — the card cannot drift")
	# The signal now does exactly ONE thing: fire the card. It used to also append to a UI-side
	# resident list (`ResidentIndex`), which hit-tested arrival-time positions and so broke the
	# priority rule as soon as residents began to wander. Asserted structurally — a second list
	# would have to be a property on `GameUI` — so re-introducing one fails here.
	var ui_property_names: PackedStringArray = PackedStringArray()
	for entry: Dictionary in _ui.get_property_list():
		ui_property_names.append(entry["name"] as String)
	check(not ui_property_names.has("residents"),
		"the UI keeps NO resident list of its own — tap-to-replay resolves live positions "
		+ "through `WorldRoot.resident_record_at()`")
	# NON-VACUITY (added by QA when reviewing this edit): an absence-of-a-name check passes for
	# free if the name list is empty. It is not — `GameUI`'s own declared members are in there,
	# so a re-introduced `residents` really would show up beside them.
	check(ui_property_names.has("_world") and ui_property_names.has("_camera"),
		"...and that name list really enumerates `GameUI`'s own members (%d properties), so the "
			% ui_property_names.size()
		+ "absence above is a measurement rather than an empty search")

	_card.dismiss()
	check(not _card.is_open(), "the card dismisses")


func _check_repeat_arrival_routes_to_feed() -> void:
	var feed: NotificationFeed = _ui.notification_feed
	check(feed != null, "GameUI wires a %NotificationFeed")
	var before_count: int = feed.entry_count()

	# "rabbit" already arrived once in _check_fires_on_resident_arrived() above. That test
	# fires a RAW signal emit, not a real simulation arrival, so the registry's own
	# species_hosted_ids() was never touched — what actually makes this second emit a REPEAT
	# is GameUI's own `_known_before_session` bookkeeping: `_on_resident_arrived()` appends a
	# species_id to that set the first time it sees it, specifically so a second arrival of
	# the same species routes differently without needing the registry to agree. That's the
	# behavior this check exercises.
	_world.resident_arrived.emit("rabbit", _world.grid_to_world(11, 11))

	check(not _card.is_open(), "a REPEAT arrival does NOT reopen the big card")
	check_eq(feed.entry_count(), before_count + 1, "...it goes to the feed instead, one new entry")
	var rabbit: AnimalDefinition = _world.roster.by_id("rabbit")
	check_eq(feed.entry_texts()[0], "%s. %s" % [rabbit.display_name, rabbit.effective_fact_text()],
		"...carrying the SAME verbatim copy the big card would have shown")


# --- The card is the data ---------------------------------------------------------------------------

func _check_text_equals_the_data_for_every_roster_species() -> void:
	# RE-POINTED (-> D-43, roster grew 3 -> 12): this check's own claim is "EVERY roster
	# species", so it cares that the roster is non-trivially larger than one, not that it is
	# any particular size — a fixed magic number here would just go stale at the next roster
	# change the way `3` just did.
	check(_world.roster.size() > 1, "the roster has more than one species (%d)"
		% _world.roster.size())

	var mismatches: PackedStringArray = PackedStringArray()
	for species: AnimalDefinition in _world.roster.species():
		_card.show_species(species)
		if _species_name() != species.display_name:
			mismatches.append("%s: title %s != %s" % [species.id, _species_name(), species.display_name])
		if _body_text() != species.effective_fact_text():
			mismatches.append("%s: body does not equal fact_text" % species.id)
		if _card.spoken_text() != "%s. %s" % [species.display_name, species.effective_fact_text()]:
			mismatches.append("%s: spoken text does not equal name + fact_text" % species.id)
		_card.dismiss()

	check(mismatches.is_empty(),
		"EVERY roster species renders its own display_name and fact_text exactly",
		"mismatches: %s" % str(mismatches))

	# Not vacuous: the roster species really do have different copy, so a card that showed the
	# same thing every time could not pass the check above.
	var texts: PackedStringArray = PackedStringArray()
	for species: AnimalDefinition in _world.roster.species():
		texts.append(species.effective_fact_text())
	check_eq(texts.size(), _world.roster.size(),
		"%d fact texts were compared" % texts.size())
	var distinct_texts: Dictionary = {}
	for text: String in texts:
		distinct_texts[text] = true
	check_eq(distinct_texts.size(), texts.size(),
		"...and every one of them is different copy (the equality check above is not vacuous)")

	# Read-Aloud degrades quietly rather than erroring where there is no voice.
	_card.show_species(_world.roster.by_id("fox"))
	check_eq(ReadAloud.available(), false, "there is no TTS voice in the headless container")
	check_eq(_card.read_aloud(), false, "...so read_aloud() returns false, and does not error")
	check(_card.is_open(), "...and the card is unaffected — a silent machine still plays")
	_card.dismiss()


# --- Entry point 2: tap-to-replay in Inspect (a pillar invariant, not depth) --------------------------

func _check_tap_to_replay_in_inspect() -> void:
	var rabbit: AnimalDefinition = _world.roster.by_id("rabbit")
	var tile := Vector2i(20, 20)
	var anchor: Vector3 = _world.grid_to_world(tile.x, tile.y)

	# A REAL resident in the live HomeSiteRegistry, same fixture setup as before.
	var site: HomeSite = _world.registry.register(tile, "rabbit", rabbit.scout_radius)
	var resident := Node3D.new()
	resident.name = "ReplayResident"
	resident.position = anchor
	_world.add_child(resident)
	site.residents.append(resident)

	# FOCUS-AND-TAP (D-41): same fixture pattern as before.
	_aim_camera_at(anchor + Vector3(0.0, ResidentPicker.BODY_CENTRE_HEIGHT, 0.0))
	var screen: Vector2 = _crosshair()

	_hud.set_mode(GameHud.Mode.INSPECT)
	check(not _card.is_open(), "the card is closed before the replay tap")
	var feed: NotificationFeed = _ui.notification_feed
	var before_count: int = feed.entry_count()

	check_eq(_router.handle_tap(screen), TapRouter.RESULT_RESIDENT,
		"TAP-TO-REPLAY: an Inspect tap on a resident resolves to that resident")
	check(not _card.is_open(),
		"...and the BIG card does NOT open — replay routes to the feed, not the payoff card")
	check_eq(feed.entry_count(), before_count + 1, "...the feed gains one entry")
	check_eq(feed.entry_texts()[0], "%s. %s" % [rabbit.display_name, rabbit.effective_fact_text()],
		"...with the same verbatim copy — one composition path, so the two entry points cannot diverge")

	# Replayable forever, not once.
	_router.handle_tap(screen)
	check_eq(feed.entry_count(), before_count + 2,
		"the replay works a second time — Pillar 4 does not run out")

	site.residents.clear()
	_world.registry.unregister(site)
	resident.queue_free()


func _check_dismiss_routes() -> void:
	_card.show_species(_world.roster.by_id("fox"))
	check(_card.is_open(), "the card is open")

	# The scripted tap path: a tap while a card is open dismisses it and does nothing else —
	# no paint, no place, whatever mode is active.
	_hud.set_mode(GameHud.Mode.TERRAFORM)
	_hud.select_palette_option("water")
	var tile := Vector2i(30, 6)
	var terrain_before: String = _world.get_tile_terrain(tile.x, tile.y)
	var screen: Vector2 = _camera.unproject_position(_world.grid_to_world(tile.x, tile.y))
	check_eq(_router.handle_tap(screen), TapRouter.RESULT_CARD_OPEN,
		"a tap while the card is open is swallowed by the card")
	check(not _card.is_open(), "...the card dismissed")
	check_eq(_world.get_tile_terrain(tile.x, tile.y), terrain_before,
		"...and the tile behind it was NOT painted")

	# No timeout, no auto-dismiss: the card stays until the player closes it. spec.md ->
	# Screen Layouts gives the card a dismiss control and an outside tap and NOTHING ELSE,
	# because a card that vanishes on its own is a timer (Pillar 1). Asserted structurally —
	# there is no per-frame callback and no Timer anywhere in the card that could close it.
	var card_methods: Array[String] = []
	for entry: Dictionary in _card.get_script().get_script_method_list():
		card_methods.append(entry["name"])
	check(not card_methods.has("_process") and not card_methods.has("_physics_process"),
		"FactCard has no per-frame callback — nothing counts down while the card is up")
	var timers: int = 0
	for child: Node in _card.find_children("*", "Timer", true, false):
		timers += 1
	check_eq(timers, 0, "...and the card scene contains no Timer — there is no auto-dismiss")

	_card.show_species(_world.roster.by_id("fox"))
	check(_card.is_open(), "the card stays open until the player closes it")
	_card.dismiss()


# --- The villager's card: the gate that closed (#31) ------------------------------------------------------
# The card that carries row 4's USP proof — the one species the player builds a habitat FOR.
# Its copy is asserted rendered, as a literal, because this is the only suite that puts the
# string through the actual Label a playtester reads.

## Content-writer's shipped copy, transcribed. `test_human_schema.gd` pins the same literal
## against the `.tres`; this one pins what the CARD shows. Two independent pins on purpose: a
## card that rendered its own copy would still pass a `_body_text() == human.effective_fact_text()` check.
##
## RE-POINTED 2026-07-28 for the second-source correction to #31 (the "10,000 to 12,000" range
## and "little by little"; the reasoning is in test_human_schema.gd and human.tres). Copied from
## `human.tres`'s `fact_text` line, not retyped.
const VILLAGER_FACT_TEXT: String = "Long ago, people moved from place to place instead of staying in one home. About 10,000 to 12,000 years ago they learned to grow their own food, and little by little they settled down in one place."


func _check_villager_card_renders_the_shipped_copy() -> void:
	var human: AnimalDefinition = load(HUMAN_PATH) as AnimalDefinition
	check(human != null, "%s loads as an AnimalDefinition" % HUMAN_PATH)
	check(not human.effective_fact_text().begins_with(AnimalDefinition.PLACEHOLDER_MARKER),
		"human.tres's fact_text is no longer PLACEHOLDER-prefixed — #31 closed 2026-07-28")

	check(_card.show_species(human), "the villager's card shows")
	check_eq(_species_name(), "Villager", "...titled \"Villager\", the authored display_name")
	check_eq(_body_text(), human.effective_fact_text(),
		"...and the body is the data's own `fact_text`, VERBATIM — the card cannot drift")
	check_eq(_body_text(), VILLAGER_FACT_TEXT,
		"...and that text is content-writer's source-verified copy, asserted as a LITERAL so a "
		+ "card and a `.tres` cannot drift together")
	check(not _body_text().begins_with(AnimalDefinition.PLACEHOLDER_MARKER),
		"...so a playtester no longer sees the word PLACEHOLDER on the villager's move-in card")
	check(not _body_text().contains("#31"),
		"...and no open-question number is rendered to the player either")

	# The banned-word rule, at the render surface. `test_human_schema.gd` owns the full sweep
	# against the data; this checks the one word the whole rule turns on — human.tres records
	# that ADW's source sentence reads "nomadic hunter gatherers" and the copy deliberately does
	# not — because a card is where a restored source wording would actually reach a child.
	var lowered: String = _body_text().to_lower()
	for banned: String in ["hunt", "hunter", "hunters", "hunting", "gather", "gatherer", "gatherers", "prey", "kill"]:
		var word_re := RegEx.new()
		word_re.compile("\\b%s\\b" % banned)
		check(word_re.search(lowered) == null,
			"the RENDERED villager card avoids banned word \"%s\"" % banned)

	# NON-VACUITY: the same matcher over the source wording the copy refuses to use.
	var probe := RegEx.new()
	probe.compile("\\bgatherers\\b")
	check(probe.search("nomadic hunter gatherers") != null,
		"NEGATIVE CONTROL: the same matcher DOES fire on \"nomadic hunter gatherers\", so the "
		+ "clean sweep above is a measurement rather than a broken regex")

	# The whole roster carries real copy now — no placeholder is reachable through the card at
	# all. Asserted over the roster the SIMULATION reads, so a fourth species added with
	# placeholder copy fails here on the day it lands.
	var placeholders: PackedStringArray = PackedStringArray()
	for species: AnimalDefinition in _world.roster.species():
		_card.show_species(species)
		if _body_text().begins_with(AnimalDefinition.PLACEHOLDER_MARKER):
			placeholders.append(species.id)
		_card.dismiss()
	check(placeholders.is_empty(),
		"NO roster species renders placeholder copy on its card — the content gate is shut",
		"still placeholder: %s" % str(placeholders))

	_card.show_species(human)
	_card.dismiss()


# --- Read-Aloud fires itself on open (-> D-29 #2, closing Open Question #13) -----------------

## `AUTO_SPEAK` flipped `false` -> `true` on 2026-08-01. A previous pass here PINNED the old
## value as a `note_expected_pending()` rather than asserting it, so the flip landed silently —
## re-pointed to a real assertion, not weakened, since there is now a ruled decision to hold it
## to. `ReadAloud.speak()` itself cannot be observed to actually fire headlessly (there is no
## voice in the container, so it is a no-op and its return value cannot distinguish "asked to
## speak and declined" from "never asked") — so the wiring is confirmed structurally, the same
## way this project already confirms other headless-unobservable behaviour (e.g. the
## free/natural-terrain branch check in `test_removal_refund.gd`).
func _check_auto_speak_fires_on_open() -> void:
	check_eq(FactCard.AUTO_SPEAK, true,
		"AUTO_SPEAK is true (-> D-29 #2, closing Open Question #13) — cards speak themselves on "
		+ "open, with no manual tap needed")

	# STRUCTURAL: `show_card()` — the one function both entry points funnel through — calls
	# `ReadAloud.speak()` guarded by `AUTO_SPEAK`, through the exact same path the visible 🔊
	# button's `read_aloud()` uses. Isolated to `show_card()`'s own body so this cannot be
	# satisfied by the two symbols merely coexisting somewhere else in the file.
	var source: String = (load("res://scripts/ui/fact_card.gd") as GDScript).source_code
	var start: int = source.find("func show_card(")
	check(start >= 0, "`fact_card.gd` declares `show_card()`")
	var next_func: int = source.find("\nfunc ", start + 1)
	var body: String = source.substr(start, (next_func if next_func >= 0 else source.length()) - start)
	check(body.contains("AUTO_SPEAK"),
		"`show_card()`'s own body reads `AUTO_SPEAK` — the guard is inside the function that "
		+ "makes the card visible, not bolted on elsewhere")
	check(body.contains("ReadAloud.speak(_spoken_text)"),
		"...and calls `ReadAloud.speak(_spoken_text)` — the identical call `read_aloud()` (the "
		+ "button's handler) makes, so auto-speak and the manual button read the same text "
		+ "through the same path")
	check(body.contains("GameplaySettings.speaking_enabled()"),
		"...and auto-speak is ALSO gated on the shared speaking toggle, not just AUTO_SPEAK — a "
		+ "player who turns speaking off does not get talked over on the very next card")

	# The text AUTO_SPEAK would hand to `ReadAloud.speak()` is exactly the card's own title +
	# body — asserted live, on a real species, so a wrong pairing (auto-speaking stale or empty
	# text) would show here even though the TTS call itself cannot be observed.
	var species: AnimalDefinition = _world.roster.by_id("rabbit")
	check(species != null, "the rabbit is in the roster")
	check(_card.show_species(species), "a card opens for the rabbit")
	check_eq(_card.spoken_text(), "%s. %s" % [species.display_name, species.effective_fact_text()],
		"...and the text AUTO_SPEAK reads aloud is exactly the card's own title + body, the "
		+ "moment `show_species()` makes it visible — not a second, separate string")
	_card.dismiss()


# --- The speaking toggle is a GLOBAL setting, not a per-card one ----------------------------
# The player request this closes: "if disabled it is disabled until turned back on, not just
# for that specific card." The card's 🔊 button IS the toggle (not a separate replay control) —
# it reads and writes `GameplaySettings.speaking_enabled()`, the same flag the title screen's
# own checkbox uses (`test_title_screen.gd`).

func _check_speaking_toggle_is_global_and_persists() -> void:
	GameplaySettings.reset_for_test()
	check_eq(GameplaySettings.speaking_enabled(), true, "speaking defaults ON")

	_card.show_species(_world.roster.by_id("fox"))
	check_eq(_toggle_is_muted(), false,
		"the toggle shows the speaking speaker while speaking is enabled")

	check_eq(_card.toggle_speaking(), false, "toggling flips the setting off, returning the new state")
	check_eq(GameplaySettings.speaking_enabled(), false,
		"...and GameplaySettings — the ONE source of truth — reads it back off")
	check_eq(_toggle_is_muted(), true, "...and the button repaints muted")

	# GLOBAL, NOT PER-CARD: a second, independently-opened card starts muted too.
	_card.dismiss()
	_card.show_species(_world.roster.by_id("rabbit"))
	check_eq(_toggle_is_muted(), true,
		"a freshly-opened card reads the shared setting, not a fresh per-card default")

	check_eq(_card.toggle_speaking(), true, "toggling again flips it back on")
	check_eq(GameplaySettings.speaking_enabled(), true, "...and GameplaySettings reads it back on")
	check_eq(_toggle_is_muted(), false, "...and the button repaints speaking")
	_card.dismiss()

	# PERSISTS ACROSS A RELOAD — the same `user://settings.cfg` round-trip
	# `test_news_report.gd`'s `_check_gameplay_settings_persistence()` proves for Hints, pinned
	# here for this key specifically so a forgotten `_save()`/`_ensure_loaded()` wire fails here.
	GameplaySettings.set_speaking_enabled(false)
	GameplaySettings._loaded = false
	check_eq(GameplaySettings.speaking_enabled(), false,
		"speaking_enabled OFF survives a reload from user://settings.cfg")

	GameplaySettings.reset_for_test()


# --- helpers --------------------------------------------------------------------------------------------------
# Read through the scene's unique names rather than the script's private @onready refs, so
# these assert what a player would actually see rendered.

## The toggle's painted state. It reads the `SpeakerIcon` on the button rather than the
## button's `text`, because the speaker is no longer a font glyph — U+1F50A/U+1F507 are not in
## the bundled font, so the web export drew tofu boxes and both were replaced by a vector
## Control (`scripts/ui/speaker_icon.gd`; `test_font_glyph_coverage.gd` guards the class of
## bug). What is pinned below is unchanged: the button repaints between speaking and muted.
func _toggle_is_muted() -> bool:
	return (_card.get_node("%Icon") as SpeakerIcon).muted


func _species_name() -> String:
	return (_card.get_node("%SpeciesName") as Label).text


func _body_text() -> String:
	return (_card.get_node("%Body") as Label).text


## FOCUS-AND-TAP FIXTURE (D-41): centres the pan/zoom camera on `target` at close
## zoom, then taps the screen point `target` itself projects to — the fixed-camera
## equivalent of the old first-person "park and look_at()" fixture.
func _aim_camera_at(target: Vector3) -> void:
	_aimed_target = target
	var rig := _camera as CameraRig
	rig.set_focus(target)
	rig.set_zoom_tiles(CameraRig.ZOOM_MIN_TILES)


func _crosshair() -> Vector2:
	return _camera.unproject_position(_aimed_target)
