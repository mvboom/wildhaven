extends QATestCase
## THE HELP PAGE — the one place Wildhaven explains itself in words, and the screen the
## Tutorial button's promise was folded into (2026-09-08).
##
## WHAT THIS SUITE IS REALLY GUARDING. Help and Tutorial shipped for two weeks as the same
## `coming_soon_screen.gd` placeholder, differing only in the word on the label. Nothing
## failed, because nothing asserted either had content. The checks below are shaped so that
## regressing to a placeholder — or half-deleting the Tutorial route — fails loudly:
##   * the Tutorial scene is GONE and no title-screen button points at it;
##   * the Help page renders real authored copy, not "Coming Soon" and not a `[COPY]` stub;
##   * Read-Aloud's script EQUALS the drawn copy, so spoken and visible words cannot drift.
##
## THE DRIFT CHECK IS THE POINT. `help_content.gd` derives `spoken_text()` by walking the same
## `Label` nodes the page draws, rather than keeping a second copy of the words — the same
## argument `test_fact_card.gd` makes for the fact card ("equality is what makes drift
## impossible"). Asserting containment per label is what holds that derivation honest: an
## author who adds a section and forgets Read-Aloud cannot, because there is nothing to forget.
##
## READ-ALOUD IS UNOBSERVABLE HEADLESSLY, and that is itself the assertion. There is no TTS
## voice in this container, so `ReadAloud.available()` is false, the button is hidden rather
## than dead (Pillar 1), and `read_aloud()` returns false without pushing an error. The words
## it WOULD speak are still checkable via `spoken_text()`, which is why that method is public.
##
## Waits a couple of frames after `add_child()` before asserting, same as
## `test_title_screen.gd` — `_ready()` has not necessarily run the instant a node enters
## the tree.
##
## Run:
##   bash scripts/run-tests.sh help_screen

const SCENE_PATH: String = "res://scenes/menu/HelpScreen.tscn"
const TITLE_PATH: String = "res://scenes/TitleScreen.tscn"
const RETIRED_TUTORIAL_PATH: String = "res://scenes/menu/TutorialScreen.tscn"

## Sections the page must actually carry. Deliberately checked by a distinctive phrase from
## each heading rather than by node name: a heading renamed into something that no longer
## answers the question it exists to answer should fail here, and a node rename should not.
const REQUIRED_HEADINGS: Array[String] = [
	"Welcome to Wildhaven",
	"How to play",
	"Moving around",
	"Nothing here can go wrong",
	"If nobody has moved in yet",
	"For grown-ups",
]

## The controls the page promises to explain. Every one is a real binding in
## `gdd.md` -> Player Interface & Controls; a control that ships without a line here is a
## control a stuck six-year-old cannot find.
const REQUIRED_CONTROLS: Array[String] = ["Tab", "Home", "wheel", "Erase", "Info"]

## Placeholder markers. `[COPY]` is this project's own awaiting-sign-off prefix (see
## `onboarding_coach.gd`'s beat text); "Coming Soon" is the literal string this very screen
## used to render.
const PLACEHOLDER_MARKERS: Array[String] = ["[COPY]", "Coming Soon", "TODO", "TBD", "Lorem"]

## Pillar 2's no-harm line, at the render surface — the same mechanized rule
## `test_fact_card.gd` applies to the villager's card. Help is the longest single block of
## player-facing prose in the game, so it is the likeliest place for one of these to slip in.
## NOT in this list, deliberately: "lose", "fail". The page says "There is no way to lose",
## which NAMES the absence -- banning the word would ban the reassurance Pillar 1 exists to
## give. What is banned is harm the game does not contain and must not describe.
const BANNED_WORDS: Array[String] = [
	"hunt", "hunts", "hunting", "kill", "kills", "prey", "predator", "predators",
	"trap", "traps", "cage", "cages", "die", "dies", "starve", "starves",
]

var _screen: Control = null
var _content: HelpContent = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("help screen")

	_check_tutorial_is_retired()

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

	_content = _screen.get_node("%HelpContent") as HelpContent
	if not check(_content != null, "HelpScreen embeds a HelpContent, not a Coming Soon label"):
		_screen.queue_free()
		finish()
		return true

	check(_screen.has_node("%BackButton"),
		"Help keeps the shared page chrome's Back button — it is reachable only from the "
		+ "title screen (D-50), so Back is the only way out")

	var labels: Array[Label] = _visible_copy()
	_check_page_has_real_copy(labels)
	_check_required_sections(labels)
	_check_copy_is_gentle(labels)
	_check_read_aloud_speaks_exactly_what_is_drawn(labels)
	_check_read_aloud_degrades_quietly()

	_screen.queue_free()
	GameplaySettings.reset_for_test()
	finish()
	return true


## THE TUTORIAL BUTTON'S REMOVAL, PINNED FROM BOTH ENDS. `future.md` deferred the standalone
## Tutorial screen past v1 ("v1's first-time nudge covers minimum onboarding on its own"), and
## gdd.md's title-screen paragraph never listed it. Deleting the scene without unwiring the
## button would leave a button that loads nothing; unwiring without deleting would leave a
## dead scene to rot. Both halves are checked.
func _check_tutorial_is_retired() -> void:
	check(not ResourceLoader.exists(RETIRED_TUTORIAL_PATH),
		"the standalone Tutorial scene is gone, not left behind as an orphan "
		+ "(future.md defers it past v1; its stuck-player content moved into Help)")

	var packed: PackedScene = load(TITLE_PATH) as PackedScene
	if not check(packed != null, "%s loads" % TITLE_PATH):
		return
	var title: Control = packed.instantiate() as Control
	check(title.find_child("TutorialButton", true, false) == null,
		"no Tutorial button survives on the title screen — the row is New Game / Load Game, "
		+ "then Settings / Help / Credits, exactly what gdd.md's title-screen paragraph lists")
	# The removed button sat mid-chain between Load Game and the small row. A NodePath pointing
	# at a node that no longer exists resolves to null and silently dead-ends keyboard focus,
	# which no layout check would catch.
	var dangling: PackedStringArray = []
	for control: Control in _all_controls(title):
		for side: String in [
			"focus_neighbor_top", "focus_neighbor_bottom",
			"focus_neighbor_left", "focus_neighbor_right",
		]:
			var path: NodePath = control.get(side)
			if path.is_empty():
				continue
			if control.get_node_or_null(path) == null:
				dangling.append("%s.%s -> %s" % [control.name, side, path])
	check(dangling.is_empty(),
		"every focus_neighbor on the title screen still resolves — removing the Tutorial "
		+ "button did not leave keyboard focus pointing into a hole",
		"dangling: %s" % str(dangling))
	title.queue_free()


func _check_page_has_real_copy(labels: Array[Label]) -> void:
	check(labels.size() >= 12,
		"the Help page carries a real page of copy, not a one-line placeholder",
		"non-empty labels: %d" % labels.size())

	var stubs: PackedStringArray = []
	for label: Label in labels:
		for marker: String in PLACEHOLDER_MARKERS:
			if label.text.contains(marker):
				stubs.append("%s: %s" % [label.name, label.text])
				break
	check(stubs.is_empty(),
		"no placeholder copy survives on the shipped Help page",
		"stubs: %s" % str(stubs))


func _check_required_sections(labels: Array[Label]) -> void:
	var page: String = _page_text(labels)
	for heading: String in REQUIRED_HEADINGS:
		check(page.contains(heading), "Help answers \"%s\"" % heading)
	for control: String in REQUIRED_CONTROLS:
		check(page.contains(control),
			"Help explains the \"%s\" control — every binding gdd.md lists is findable here"
			% control)


## Pillar 2 and Pillar 1 at the render surface: this page describes a game with no fail state,
## so it must not describe one. `\b` word boundaries, so "lose" fails but "closer" does not.
func _check_copy_is_gentle(labels: Array[Label]) -> void:
	var page: String = _page_text(labels).to_lower()
	for banned: String in BANNED_WORDS:
		var word_re := RegEx.new()
		word_re.compile("\\b%s\\b" % banned)
		var hit: RegExMatch = word_re.search(page)
		check(hit == null,
			"Help avoids the word \"%s\" — no fail states, no harm, in the copy either" % banned,
			"found in: %s" % page.substr(maxi(0, (hit.get_start() if hit != null else 0) - 40), 90))


## THE ANTI-DRIFT ASSERTION. Not "spoken text is non-empty" — every drawn word must be IN it,
## because the only way that can hold for a page nobody hand-syncs is if the spoken script is
## derived from the drawn labels rather than duplicated beside them.
func _check_read_aloud_speaks_exactly_what_is_drawn(labels: Array[Label]) -> void:
	var spoken: String = _content.spoken_text()
	check(not spoken.strip_edges().is_empty(),
		"the page has something to read aloud")

	var missing: PackedStringArray = []
	for label: Label in labels:
		if not spoken.contains(label.text.strip_edges()):
			missing.append(label.name)
	check(missing.is_empty(),
		"every drawn word is in Read-Aloud's script — spoken and visible copy cannot drift, "
		+ "because spoken_text() walks the same Labels the page draws",
		"labels missing from the spoken script: %s" % str(missing))

	check(not spoken.contains(HelpContent.READ_LABEL)
			and not spoken.contains(HelpContent.STOP_LABEL),
		"the Read-Aloud button's own label is NOT read aloud — it sits outside %Sections so "
		+ "the page does not announce its own button before its first sentence")


## Same quiet-degradation contract `FactCard` holds: no voice means a hidden button and a
## false return, never a dead control and never an error.
func _check_read_aloud_degrades_quietly() -> void:
	check_eq(ReadAloud.available(), false,
		"this headless container has no TTS voice — the premise of the two checks below")
	check_eq((_content.get_node("%ReadAloudButton") as Control).visible, false,
		"with no voice the Read-Aloud button is hidden, not offered and inert (Pillar 1)")
	check_eq(_content.read_aloud(), false,
		"read_aloud() reports it could not speak rather than erroring")
	check_eq(_content.is_reading(), false,
		"a speak that never started does not leave the button stuck in its Stop state")


func _visible_copy() -> Array[Label]:
	var out: Array[Label] = []
	_gather(_content.get_node("%Sections"), out)
	return out


func _gather(node: Node, into: Array[Label]) -> void:
	var label := node as Label
	if label != null and not label.text.strip_edges().is_empty():
		into.append(label)
	for child: Node in node.get_children():
		_gather(child, into)


func _page_text(labels: Array[Label]) -> String:
	var parts: PackedStringArray = []
	for label: Label in labels:
		parts.append(label.text)
	return "\n".join(parts)


func _all_controls(node: Node) -> Array[Control]:
	var out: Array[Control] = []
	_gather_controls(node, out)
	return out


func _gather_controls(node: Node, into: Array[Control]) -> void:
	var control := node as Control
	if control != null:
		into.append(control)
	for child: Node in node.get_children():
		_gather_controls(child, into)
