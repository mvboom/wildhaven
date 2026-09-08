extends QATestCase
## TIER 1 ROW 12 (POINTERS) — the first-time nudge, the ambient News Report cadence, the
## schema it reads, and the Gameplay Hints toggle that is a pillar invariant, not depth.
##
## SECTIONS:
##   1. THE SCHEMA GAP CLOSES. `AnimalDefinition.news_reports` exists, and the floor roster's
##      three `.tres` files carry real, checklist-passed copy — never the flagged-suspect fox
##      line, never a placeholder, and `validate()` stays clean either way (the field is
##      optional by design).
##   2. THE CLOCK. `NewsReportScheduler` fires the nudge at ~3 s (D-37), never before; the
##      ambient cadence only starts counting once the nudge has fired, and lands in 90-150 s
##      (D-37); the Hints toggle suppresses BOTH kinds of event on the very next `advance()`,
##      not just a control on screen; switching Hints off before the nudge fires retires it
##      forever, even across a later re-enable.
##   3. THE PICK. `NewsReportContent` tallies tags over a real grid in one pass, and its
##      terrain-bias weighting is measurably more likely to name a species whose habitat
##      already exists more of, without ever letting a species with none of it go completely
##      unreachable (gdd.md -> Discovery: "a hint is an invitation, not an assignment").
##      `hint_line()` then composes the report itself: an authored (or generic) opening plus
##      needs derived live from `HabitatRecipe`, so a divisor retune updates every report with
##      no copy edit, and no rendered report ever carries an imperative or a raw tag.
##   4. THE SETTING PERSISTS. `GameplaySettings` defaults ON, round-trips through its own
##      `user://` file independently of any world save, and `SettingsOverlay` reads/writes it
##      rather than keeping a second copy of the value.
##   5. THE TOAST. Non-modal, no Read-Aloud button (spec.md defers that), auto-dismisses, and
##      dismisses early on a tap.
##   6. THE WIRING, on the real `Main.tscn`. `GameUI` carries all three new nodes, the HUD's
##      Settings button is no longer permanently disabled, and `WorldRoot.is_new_world` is
##      true only for a `GameSession.request_new()` world — never the default "none" path
##      every other suite's `Main.tscn` instance already relies on being unaffected by.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_news_report.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"
const FOX_PATH: String = "res://data/animals/fox.tres"
const RABBIT_PATH: String = "res://data/animals/rabbit.tres"
const HUMAN_PATH: String = "res://data/animals/human.tres"

## A fixed seed so the cadence rolls this suite pins are reproducible.
const SEED: int = 20260809

var _world: WorldRoot = null
var _ui: GameUI = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("news report (row 12)")
	GameSession.clear()
	GameplaySettings.reset_for_test()

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

	_check_schema_field_exists()
	_check_discovery_openings_field_exists()
	_check_floor_roster_pools()
	_check_scheduler_nudge_timing()
	_check_scheduler_cadence_timing()
	_check_scheduler_hints_toggle_suppresses_live()
	_check_scheduler_hints_off_retires_nudge_forever()
	_check_scheduler_without_a_pacer_is_unchanged()
	_check_scheduler_with_a_pacer_uses_its_interval()
	_check_hints_off_silences_the_feed_at_every_pacer_state()
	_check_content_tag_tile_counts()
	_check_content_candidates_and_lines()
	_check_content_terrain_bias()
	# ORDER MATTERS: `_check_nothing_hosted_names_the_villager()` MUST run before any check that
	# calls `restore_hosted()`. `HomeSiteRegistry.restore_hosted()` is additive-only — it can
	# never clear an entry (gdd.md -> Economy: "Species Hosted (all-time, never decreases)") — so
	# once ANY check below hosts a species on this suite's shared `_world`, there is no way to get
	# back to `species_hosted_count() == 0` for the rest of this run. The villager gate only has
	# anything to prove while the count is still genuinely zero.
	_check_nothing_hosted_names_the_villager()
	_check_hosted_count_survives_a_round_trip()
	_check_ranking_prefers_species_not_yet_hosted()
	_check_the_same_species_is_never_picked_twice_running()
	_check_hint_line_composes_opening_and_needs()
	_check_authored_opening_is_preferred()
	_check_toast_and_card_state_the_same_numbers()
	_check_gameplay_settings_persistence()
	_check_settings_overlay_reads_and_writes_the_one_source_of_truth()
	_check_toast_behaviour()
	_check_wiring_on_the_real_scene()
	_check_presenter_fires_a_composed_hint()
	_check_activity_reaches_the_pacer()
	_check_coach_wiring_is_idempotent()
	_check_is_new_world()
	_check_help_button_opens_field_guide()

	GameplaySettings.reset_for_test()
	finish()
	return true


# --- 1. The schema gap closes ---------------------------------------------------------------

func _check_schema_field_exists() -> void:
	var fresh := AnimalDefinition.new()
	check(fresh.news_reports is Array, "`news_reports` exists and is an Array")
	check(fresh.news_reports.is_empty(), "...empty by default — no species is required to have copy yet")

	fresh.id = "critter"
	fresh.display_name = "Critter"
	# RE-POINTED 2026-09-04 (habitat-tiers ruling): `category()` is now part of `validate()`
	# (Task 3), and a legacy-field-only fixture with no building gate and no `HabitatLimit`
	# matches none of person/wild/domesticated. `"people"` added to `habitat_needs` is the
	# minimal fix — it makes this fixture Person, the same category a real needs-`people`
	# species like Pig resolves to — without touching what this check is actually about
	# (that `news_reports` stays optional).
	# `cover` RETIRED 2026-09-07 (habitat-tiers re-spec) — re-pointed to `open_grass`, an
	# equally arbitrary still-valid tag; this fixture's needs are otherwise unexamined here.
	fresh.habitat_needs = ["open_grass", "people"] as Array[String]
	fresh.model_scenes = [load("res://assets/placeholder/grass/Grass.tscn") as PackedScene]
	fresh.fact_text_pool = ["A critter fact."]
	check(fresh.validate().is_empty(),
		"validate() is clean with news_reports left at its empty default — the field is optional")


## The opening pool is a SEPARATE field from `news_reports`, not a re-purposing of it.
## `fox.tres` mixes three discovery lines with six flavour lines in one flat array today —
## the exact interleaving `fox-news-report-pool.md` said "must not be drawn
## interchangeably". Composing a build list onto "A fox was spotted curled up in a sunbeam"
## is incoherent, so the registers get their own fields rather than one shared one.
func _check_discovery_openings_field_exists() -> void:
	var fox: AnimalDefinition = load(FOX_PATH) as AnimalDefinition
	if not check(fox != null, "fox.tres loads"):
		return
	check(fox.discovery_openings is Array, "`discovery_openings` exists and is an Array")
	check(fox.discovery_openings.is_empty(),
		"...and starts empty — authoring openings is follow-on work, outside this plan")
	check(not fox.news_reports.is_empty(),
		"...while `news_reports` keeps its existing flavour copy untouched")
	check_eq(fox.validate().size(), 0,
		"a species with an empty `discovery_openings` still validates clean")


func _check_floor_roster_pools() -> void:
	var fox: AnimalDefinition = load(FOX_PATH) as AnimalDefinition
	var rabbit: AnimalDefinition = load(RABBIT_PATH) as AnimalDefinition
	var human: AnimalDefinition = load(HUMAN_PATH) as AnimalDefinition
	check(fox != null and rabbit != null and human != null, "all three floor .tres load")

	for entry: Array in [[fox, "fox"], [rabbit, "rabbit"], [human, "human"]]:
		var species: AnimalDefinition = entry[0]
		var label: String = entry[1]
		check(not species.news_reports.is_empty(), "%s.tres carries News Report copy" % label)
		for line: String in species.news_reports:
			check(not line.strip_edges().is_empty(), "%s: no blank line in the pool" % label)
			check(not line.begins_with(AnimalDefinition.PLACEHOLDER_MARKER),
				"%s: no PLACEHOLDER-prefixed line shipped" % label)
		check(species.validate(["fox", "rabbit", "human"]).is_empty(),
			"%s.tres still validates clean with news_reports populated" % label)

	# THE SUSPECT LINE STAYS OUT. docs/content/fox-news-report-pool.md flags "The fox kits
	# were out tumbling in the leaves all morning" as factually suspect (fox activity is
	# nocturnal/crepuscular in every source) — shipping it would repeat the exact daytime-
	# activity error `fact_text` was rewritten to correct.
	var suspect := "tumbling in the leaves all morning"
	var found_suspect: bool = false
	for line: String in fox.news_reports:
		if line.contains(suspect):
			found_suspect = true
	check(not found_suspect, "the flagged-suspect fox ambient line was NOT shipped")

	# NON-VACUITY: the three pools really do differ, so "non-empty" above is not one shared list.
	check(fox.news_reports != rabbit.news_reports and rabbit.news_reports != human.news_reports,
		"the three species carry DIFFERENT copy, not one pool aliased three times")


# --- 2. The clock ------------------------------------------------------------------------------

func _check_scheduler_nudge_timing() -> void:
	var scheduler := NewsReportScheduler.new(SEED)
	check_eq(scheduler.hints_enabled, true, "hints default ON")
	check(not scheduler.nudge_fired(), "the nudge has not fired at t=0")

	check_eq(scheduler.advance(1.0), NewsReportScheduler.EVENT_NONE, "t=1s: nothing yet")
	check_eq(scheduler.advance(1.0), NewsReportScheduler.EVENT_NONE, "t=2s: still nothing")
	check(not scheduler.nudge_fired(), "...and the nudge has still not fired one tick before D-37's ~3s")

	check_eq(scheduler.advance(1.0), NewsReportScheduler.EVENT_NUDGE,
		"t=3s: the nudge fires exactly once it reaches D-37's ~3s delay")
	check(scheduler.nudge_fired(), "...and is marked fired")
	check_eq(scheduler.advance(0.01), NewsReportScheduler.EVENT_NONE,
		"...and does not fire a second time on the very next tick")


func _check_scheduler_cadence_timing() -> void:
	# Drive several independently-seeded schedulers straight through the nudge and confirm
	# every ambient report lands inside D-37's 90-150s band — never before, never stuck.
	var min_seen: float = INF
	var max_seen: float = -INF
	for trial in range(20):
		var scheduler := NewsReportScheduler.new(SEED + trial)
		scheduler.advance(NewsReportScheduler.NUDGE_DELAY_SECONDS) # spend the nudge
		var elapsed: float = 0.0
		var fired: bool = false
		# 200s ceiling: comfortably past the 150s worst case with margin, so a scheduler that
		# never fires (a real defect) fails instead of looping forever.
		while elapsed < 200.0 and not fired:
			var event: String = scheduler.advance(1.0)
			elapsed += 1.0
			if event == NewsReportScheduler.EVENT_REPORT:
				fired = true
		check(fired, "trial %d: an ambient report eventually fires after the nudge" % trial)
		min_seen = minf(min_seen, elapsed)
		max_seen = maxf(max_seen, elapsed)

	check(min_seen >= NewsReportScheduler.CADENCE_MIN_SECONDS - 1.0,
		"no report fired before D-37's 90s floor (measured min %.1fs)" % min_seen)
	check(max_seen <= NewsReportScheduler.CADENCE_MAX_SECONDS + 1.0,
		"no report ran past D-37's 150s ceiling (measured max %.1fs)" % max_seen)
	# NON-VACUITY: the 20 trials did not all land on the same tick.
	check(max_seen - min_seen > 5.0,
		"...and the trials actually spread across the band (not one lucky constant seed)")


func _check_scheduler_hints_toggle_suppresses_live() -> void:
	var scheduler := NewsReportScheduler.new(SEED)
	scheduler.set_hints_enabled(false)
	check_eq(scheduler.advance(1000.0), NewsReportScheduler.EVENT_NONE,
		"1000 simulated seconds with Hints OFF fires NOTHING — the layer is suppressed live, "
		+ "not just hidden behind a disabled control")
	# `nudge_fired()` reads true here too — turning Hints off before the nudge ever showed
	# RETIRES it (see the next check) — but the assertion above is the one that matters for
	# THIS check: no event of either kind ever reached a caller while Hints were off.


func _check_scheduler_hints_off_retires_nudge_forever() -> void:
	# Off BEFORE the nudge ever fires.
	var scheduler := NewsReportScheduler.new(SEED)
	scheduler.advance(1.0)
	scheduler.set_hints_enabled(false)
	check(scheduler.nudge_fired(),
		"switching Hints off before the nudge fires retires it immediately — "
		+ "gdd.md: \"the Hints toggle disables it forever\"")

	# Back on. gdd.md only calls the NUDGE's suppression permanent — the ambient cadence must
	# resume normally, and the nudge must never appear regardless.
	scheduler.set_hints_enabled(true)
	var saw_nudge: bool = false
	var saw_report: bool = false
	var elapsed: float = 0.0
	while elapsed < 200.0 and not saw_report:
		match scheduler.advance(1.0):
			NewsReportScheduler.EVENT_NUDGE:
				saw_nudge = true
			NewsReportScheduler.EVENT_REPORT:
				saw_report = true
		elapsed += 1.0
	check(not saw_nudge, "...re-enabling Hints never brings the nudge back")
	check(saw_report, "...but the ambient cadence resumes and a report still eventually fires")

	# Off AFTER the nudge fires — a normal pause, not a second retirement of anything.
	var mid_scheduler := NewsReportScheduler.new(SEED)
	mid_scheduler.advance(NewsReportScheduler.NUDGE_DELAY_SECONDS)
	check(mid_scheduler.nudge_fired(), "fixture: the nudge fired normally first")
	var remaining_before: float = mid_scheduler.report_remaining()
	mid_scheduler.set_hints_enabled(false)
	mid_scheduler.advance(50.0)
	mid_scheduler.set_hints_enabled(true)
	check(is_equal_approx(mid_scheduler.report_remaining(), remaining_before),
		"pausing mid-cadence and resuming leaves the SAME remaining wait — a pause, not a reset")


## THE FALLBACK IS THE POINT. A scheduler with no pacer must behave EXACTLY as it does
## today — that is what keeps every pre-existing cadence assertion in this suite a real
## check rather than one quietly rewritten to match new behaviour. D-37's decided constants
## are not deleted; they stop being the ambient rule and become the no-pacer answer.
func _check_scheduler_without_a_pacer_is_unchanged() -> void:
	var scheduler := NewsReportScheduler.new(SEED)
	scheduler.advance(NewsReportScheduler.NUDGE_DELAY_SECONDS + 0.01)
	var remaining: float = scheduler.report_remaining()
	check(remaining >= NewsReportScheduler.CADENCE_MIN_SECONDS,
		"the no-pacer cadence still lands at or above D-37's floor (%.1f)" % remaining)
	check(remaining <= NewsReportScheduler.CADENCE_MAX_SECONDS,
		"...and at or below its ceiling (%.1f)" % remaining)


## With a pacer attached, the hosted count drives the interval instead.
func _check_scheduler_with_a_pacer_uses_its_interval() -> void:
	var scheduler := NewsReportScheduler.new(SEED)
	var pacer := HintPacer.new()
	scheduler.set_pacer(pacer)
	scheduler.set_hosted_count(0)
	scheduler.advance(NewsReportScheduler.NUDGE_DELAY_SECONDS + 0.01)
	var learning: float = scheduler.report_remaining()
	check_eq(learning, pacer.next_interval(0),
		"the learning band drives the interval verbatim (%.1f)" % learning)

	var settled := NewsReportScheduler.new(SEED)
	settled.set_pacer(HintPacer.new())
	settled.set_hosted_count(9)
	settled.advance(NewsReportScheduler.NUDGE_DELAY_SECONDS + 0.01)
	check(settled.report_remaining() > learning,
		"a player hosting nine species waits longer than one hosting none")


## PILLAR INVARIANT. The Hints toggle silences the feed regardless of pacer state — the
## pacer sits BELOW that gate and changes the interval, never whether an event may fire.
func _check_hints_off_silences_the_feed_at_every_pacer_state() -> void:
	for hosted: int in [0, 2, 4, 9]:
		var scheduler := NewsReportScheduler.new(SEED)
		scheduler.set_pacer(HintPacer.new())
		scheduler.set_hosted_count(hosted)
		scheduler.set_hints_enabled(false)
		var fired: bool = false
		for i in range(2000):
			if scheduler.advance(1.0) != NewsReportScheduler.EVENT_NONE:
				fired = true
				break
		check(not fired,
			"hints off fires nothing at hosted_count %d, over 2000 simulated seconds" % hosted)


# --- 3. The pick -------------------------------------------------------------------------------

func _check_content_tag_tile_counts() -> void:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 6, 1)
	for x in range(6):
		grid.set_terrain(x, 0, "rock" if x < 4 else "grass")

	var counts: Dictionary = NewsReportContent.tag_tile_counts(grid)
	check_eq(int(counts.get("rocks", 0)), 4, "one pass over a 6x1 grid tallies 4 `rocks` tiles")
	check_eq(int(counts.get("open_grass", 0)), 2, "...and 2 `open_grass` tiles")
	check(NewsReportContent.tag_tile_counts(null).is_empty(),
		"a null grid degrades to an empty tally, not an error")
	# `WorldGrid extends Node`, not RefCounted — `test_settlement_window.gd`'s own `_teardown()`
	# frees its fixture grid for the same reason; an un-freed one is a leak, not a style choice.
	grid.free()


func _check_content_candidates_and_lines() -> void:
	var candidates: Array[AnimalDefinition] = NewsReportContent.candidates_with_pools(_world.roster)
	check_eq(candidates.size(), 3, "all three floor species carry a pool and are candidates")

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var fox: AnimalDefinition = _world.roster.by_id("fox")
	for i in range(10):
		var line: String = NewsReportContent.pick_line(fox, rng)
		check(fox.news_reports.has(line), "pick_line() only ever returns a line FROM the pool")

	var empty_species := AnimalDefinition.new()
	check_eq(NewsReportContent.pick_line(empty_species, rng), "",
		"a species with no pool degrades to \"\", not an error")
	check(NewsReportContent.pick_species([], null, rng) == null,
		"no candidates degrades to null, not an error")


func _check_content_terrain_bias() -> void:
	# A tiny two-species roster where one need is plentiful and the other is entirely absent —
	# so the bias is unambiguous without needing the shipped roster's real numbers.
	var rich := AnimalDefinition.new()
	rich.id = "rich"
	rich.habitat_needs = ["rocks"] as Array[String]
	rich.news_reports = ["rich line"] as Array[String]

	var scarce := AnimalDefinition.new()
	scarce.id = "scarce"
	scarce.habitat_needs = ["sand"] as Array[String]
	scarce.news_reports = ["scarce line"] as Array[String]

	# A DELIBERATELY MODEST disparity (6 `rocks` tiles vs. 0 `sand` tiles, weights 7:1 once the
	# baseline is added), not an extreme one: an all-rock grid drives scarce's pick probability
	# under 1/400, which is more likely than not to land on exactly zero in any fixed number of
	# trials — a flaky assertion, not a broken feature. 7:1 keeps both "measurably favors" and
	# "never unreachable" comfortably observable in one fixed-seed run.
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 5, 2)
	var painted: int = 0
	for x in range(5):
		for z in range(2):
			if painted < 6:
				grid.set_terrain(x, z, "rock")
				painted += 1
			# the remaining 4 tiles stay wild_grass, which emits nothing (D-26) — never `sand`.

	var candidates: Array[AnimalDefinition] = [rich, scarce]
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var rich_picks: int = 0
	var scarce_picks: int = 0
	const TRIALS: int = 300
	for i in range(TRIALS):
		var picked: AnimalDefinition = NewsReportContent.pick_species(candidates, grid, rng)
		if picked == rich:
			rich_picks += 1
		elif picked == scarce:
			scarce_picks += 1
	check_eq(rich_picks + scarce_picks, TRIALS, "every trial picked one of the two candidates")
	check(rich_picks > scarce_picks * 3,
		"terrain bias measurably favors the species whose habitat actually exists (rich=%d, scarce=%d)"
			% [rich_picks, scarce_picks])
	check(scarce_picks > 0,
		"...but never makes the other UNREACHABLE — a hint stays an invitation, never an "
		+ "assignment toward only the land the player already has (rich=%d, scarce=%d)"
			% [rich_picks, scarce_picks])
	grid.free()


## THE RANKING. Never-hosted outranks hosted-a-little; hosted-a-little outranks
## hosted-at-or-past-`PLENTY_THRESHOLD`; and the bottom tier NEVER reaches zero —
## `BASELINE_WEIGHT` already documents why (gdd.md: "a hint is an invitation, not an
## assignment"), and a species that can never be named again reads as a closed door.
##
## THE THIRD TIER NEEDS A REAL POPULATION, NOT JUST `restore_hosted()`. Fix round 1 finding 1:
## `HomeSiteRegistry.restore_hosted()` only ever sets `_ever_hosted` (its own doc comment: it
## exists for the half of Species Hosted with no home site left) — it never touches
## `population_of()`, which stays 0 forever after it, always below `PLENTY_THRESHOLD`. A check
## that reaches the "hosted" tier only via `restore_hosted()` can therefore never observe
## `WEIGHT_PLENTY_HOSTED` or the `<` boundary at `PLENTY_THRESHOLD` at all — a
## `WEIGHT_FEW_HOSTED`/`WEIGHT_PLENTY_HOSTED` swap, or a `<` flipped to `<=`, would pass
## silently. `HomeSiteRegistry.register()` plus appending directly to `site.residents` is the
## same fixture idiom `test_capacity_formula.gd`
## (`site.residents.append(null)  # population 1, with no model needed`) and
## `test_resident_tags.gd` already use to give a site a real population without routing
## through the full move-in simulation — `null` residents are enough because `population()`
## only ever reads `residents.size()`.
func _check_ranking_prefers_species_not_yet_hosted() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var roster: Array[AnimalDefinition] = _world.roster.species()

	var never: float = NewsReportContent.species_weight(roster[0], _world)
	check(never > 0.0, "a never-hosted species carries real weight")

	# Host one via `restore_hosted()` alone (population stays 0) — the FEW tier.
	_world.registry.restore_hosted([roster[0].id] as Array[String])
	var few: float = NewsReportContent.species_weight(roster[0], _world)
	check(few < never,
		"hosting a species demotes it (%.2f < %.2f)" % [few, never])
	check(few > 0.0,
		"...but never to zero — the door stays open (%.2f)" % few)

	# A DIFFERENT species, driven to a REAL population of exactly `PLENTY_THRESHOLD` — the
	# PLENTY tier, genuinely exercised rather than inferred from the constants alone.
	var plenty_species: AnimalDefinition = roster[1]
	var site: HomeSite = _world.registry.register(
		Vector2i(1, 1), plenty_species.id, plenty_species.scout_radius
	)
	for i in range(NewsReportContent.PLENTY_THRESHOLD):
		site.residents.append(null)
	check_eq(_world.population_of(plenty_species.id), NewsReportContent.PLENTY_THRESHOLD,
		"fixture: the species has really reached PLENTY_THRESHOLD, not merely been hosted")

	var plenty: float = NewsReportContent.species_weight(plenty_species, _world)
	check(plenty < few,
		"a species AT the plenty threshold ranks below one merely hosted (%.2f < %.2f)"
			% [plenty, few])
	check(plenty > 0.0,
		"...but never to zero here either — the door stays open (%.2f)" % plenty)

	# THE `<` BOUNDARY ITSELF. One resident short of `PLENTY_THRESHOLD` must still rank as
	# FEW, not PLENTY — a `<` flipped to `<=` in `species_weight()` would pass every assertion
	# above (both populations tested so far sit strictly on one side of the boundary) but
	# fail this one.
	site.residents.pop_back()
	check_eq(_world.population_of(plenty_species.id), NewsReportContent.PLENTY_THRESHOLD - 1,
		"fixture: one resident short of the threshold")
	var just_under: float = NewsReportContent.species_weight(plenty_species, _world)
	check_eq(just_under, NewsReportContent.WEIGHT_FEW_HOSTED,
		"PLENTY_THRESHOLD - 1 residents still ranks as FEW, not PLENTY (%.2f)" % just_under)

	# THE FULL ORDERING, on the constants themselves.
	check(NewsReportContent.WEIGHT_NEVER_HOSTED > NewsReportContent.WEIGHT_FEW_HOSTED
			and NewsReportContent.WEIGHT_FEW_HOSTED > NewsReportContent.WEIGHT_PLENTY_HOSTED
			and NewsReportContent.WEIGHT_PLENTY_HOSTED > 0.0,
		"the full ordering holds: never (%.2f) > few (%.2f) > plenty (%.2f) > 0" % [
			NewsReportContent.WEIGHT_NEVER_HOSTED,
			NewsReportContent.WEIGHT_FEW_HOSTED,
			NewsReportContent.WEIGHT_PLENTY_HOSTED,
		])


## THE EARLY GATE, ruled 2026-09-08: one branch, not a two-stage sequence. With nothing
## hosted the hint names the Villager, the cheapest thing in the game (a 15-wood house plus
## one farm tile). After that the ordinary ranking runs unmodified, and "then whatever is
## cheapest" falls out of it via the existing terrain bias rather than needing its own state.
##
## MUST RUN BEFORE ANY CHECK THAT CALLS `restore_hosted()` (see the call-order comment in
## `_process()` above) — `HomeSiteRegistry.restore_hosted()` is additive-only per its own doc
## comment ("Species Hosted (all-time, never decreases)"), so once another check hosts a
## species on this suite's shared `_world`, `species_hosted_count()` can never return to 0
## again for the rest of this run and this check's own fixture assertion below would fail.
func _check_nothing_hosted_names_the_villager() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	check_eq(_world.species_hosted_count(), 0, "the fixture world hosts nothing yet")
	for i in range(12):
		var picked: AnimalDefinition = NewsReportContent.pick_species(
			_world.roster.species(), _world.grid, rng, _world
		)
		if not check(picked != null, "a species is picked"):
			return
		if not check_eq(picked.id, NewsReportContent.VILLAGER_SPECIES_ID,
			"with nothing hosted the pick is always the villager (attempt %d)" % i):
			return


## SPEC §11's ROUND-TRIP CHECK. The decay driver was chosen over a wall clock precisely
## because it already survives a save; that is only true if the restored count actually
## reaches the pacer. `restore_hosted()` is the same path `world_snapshot.gd` uses on load.
##
## `expected` is computed from a PRE-restore snapshot of `species_hosted_ids()`, never from a
## post-restore read of `species_hosted_count()` — reading both sides of the comparison off
## the same post-restore call was tautological (fixed 2026-09-08, round-1 review):
## `HintPacer.next_interval()` is deterministic on `(hosted_count, _since_activity)` with no
## RNG, so two schedulers fed the SAME number always agree with each other whether or not
## `restore_hosted()` actually worked — a broken restore that silently left the count at 0
## would still pass. Deriving `expected` independently of the post-restore state is what lets
## this check actually fail when restore misbehaves.
##
## MUST RUN AFTER `_check_nothing_hosted_names_the_villager()` (see that check's own ordering
## note) — `restore_hosted()` is additive-only, so this check must not run before the villager
## gate's own `species_hosted_count() == 0` fixture assertion.
##
## THE IDS BELOW MUST STAY DISJOINT FROM WHATEVER `_check_ranking_prefers_species_not_yet_
## hosted()` PICKS UP BY POSITION (`roster[0]`/`roster[1]` off `_world.roster.species()`,
## filename-sorted — `alpaca`/`bull` today): that check relies on those two species going from
## unhosted to hosted, so if this check's `ids` ever collided with them first, that check's
## `few == never` comparison would fail — loudly, since `species_weight()` returns discrete
## tier constants rather than degrading quietly. This check still has to run first regardless,
## because of the villager-gate ordering above; this note exists so a future reorder finds the
## constraint here instead of rediscovering it from a failing assertion.
func _check_hosted_count_survives_a_round_trip() -> void:
	var before_ids: Array[String] = _world.species_hosted_ids()
	var ids: Array[String] = ["human", "rabbit", "fox", "deer"] as Array[String]
	var newly_hosted: int = 0
	for id: String in ids:
		if not before_ids.has(id):
			newly_hosted += 1
	var expected: int = before_ids.size() + newly_hosted

	_world.registry.restore_hosted(ids)
	check_eq(_world.species_hosted_count(), expected,
		"restoring %d never-before-hosted ids raises the count from %d to %d (observed %d)"
			% [newly_hosted, before_ids.size(), expected, _world.species_hosted_count()])

	var from_memory := NewsReportScheduler.new(SEED)
	from_memory.set_pacer(HintPacer.new())
	from_memory.set_hosted_count(expected)
	from_memory.advance(NewsReportScheduler.NUDGE_DELAY_SECONDS + 0.01)

	var from_restore := NewsReportScheduler.new(SEED)
	from_restore.set_pacer(HintPacer.new())
	from_restore.set_hosted_count(_world.species_hosted_count())
	from_restore.advance(NewsReportScheduler.NUDGE_DELAY_SECONDS + 0.01)

	check_eq(from_restore.report_remaining(), from_memory.report_remaining(),
		"the restored count paces identically to the same count held in memory")


## The Pillar 1 mitigation for the idle multiplier: an idle stretch must read as the world
## talking about different animals, not one nag repeated.
func _check_the_same_species_is_never_picked_twice_running() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_world.registry.restore_hosted([NewsReportContent.VILLAGER_SPECIES_ID] as Array[String])
	var previous: String = ""
	for i in range(30):
		var picked: AnimalDefinition = NewsReportContent.pick_species(
			_world.roster.species(), _world.grid, rng, _world, {}, previous
		)
		if not check(picked != null, "a species is picked on attempt %d" % i):
			return
		if not check(picked.id != previous,
			"attempt %d picked '%s' twice running" % [i, picked.id]):
			return
		previous = picked.id


## THE COMPOSER. An authored opening plus needs derived live, so a divisor retune updates
## every report with no copy edit. A species with NO authored opening still produces a whole,
## grammatical report — which is what lets the hint layer cover all fifteen species today: zero
## species carry `discovery_openings` copy yet (that field is separate from, and much sparser
## than, the `news_reports` ambient-flavour pool three species already carry), so every hint
## line rendered right now runs through `GENERIC_OPENING`, and the composer has to make that
## fallback read as a whole sentence on its own.
func _check_hint_line_composes_opening_and_needs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	var fox: AnimalDefinition = load(FOX_PATH) as AnimalDefinition
	if not check(fox != null, "fox.tres loads"):
		return
	var line: String = NewsReportContent.hint_line(fox, _world, rng)
	check(not line.is_empty(), "a species with no authored opening still yields a report")
	check(line.contains("fox"), "the report names the species: '%s'" % line)
	check(line.contains("4 tiles of forest"), "...and carries the real divisor: '%s'" % line)
	check(line.contains("far from any buildings"),
		"...and the starter tier's limit: '%s'" % line)
	check(line.ends_with("."), "the report is a finished sentence: '%s'" % line)

	# The register rules from the spec, on real roster data. Word-boundary regexes, not
	# substring checks — five species (deer, donkey, fox, rabbit, stag) render the limit
	# phrase "away from buildings" / "far from any buildings", and a plain
	# `.contains("build")` substring check flags the NOUN "buildings" as if it were the
	# imperative verb "build". `\bbuild\b` / `\btap\b` catch the verb without ever matching
	# inside a longer word.
	var imperative_patterns: Dictionary = {
		"build": RegEx.new(),
		"tap": RegEx.new(),
	}
	for word: String in imperative_patterns:
		(imperative_patterns[word] as RegEx).compile("\\b%s\\b" % word)

	for species: AnimalDefinition in _world.roster.species():
		var rendered: String = NewsReportContent.hint_line(species, _world, rng)
		check(not rendered.is_empty(), "%s renders a report" % species.id)
		check(not rendered.contains("_"),
			"%s's report leaks no raw tag: '%s'" % [species.id, rendered])
		var lowered: String = rendered.to_lower()
		for word: String in imperative_patterns:
			var pattern: RegEx = imperative_patterns[word]
			check(pattern.search(lowered) == null,
				"%s's report carries no imperative ('%s'): '%s'" % [species.id, word, rendered])
		check(not lowered.contains("you should"),
			"%s's report carries no imperative ('you should'): '%s'" % [species.id, rendered])


## An authored opening is used verbatim as the first half; the generic one is used only when
## the species has none.
func _check_authored_opening_is_preferred() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var ghost := AnimalDefinition.new()
	ghost.id = "ghost"
	ghost.display_name = "Ghost"
	ghost.discovery_openings = ["Word has it a ghost is looking for somewhere quiet"] as Array[String]
	var tier := HabitatTier.new()
	tier.id = "only"
	tier.max_individuals = 4
	var need := HabitatNeed.new()
	need.tag = "open_grass"
	need.tiles_per_individual = 5
	tier.needs = [need]
	ghost.tiers = [tier]

	var line: String = NewsReportContent.hint_line(ghost, _world, rng)
	check(line.begins_with("Word has it a ghost is looking for somewhere quiet"),
		"the authored opening leads the sentence verbatim: '%s'" % line)
	check(line.contains("5 tiles of open grass"),
		"...and the derived half follows it: '%s'" % line)


## THE PROPERTY THE WHOLE DESIGN RESTS ON. The toast and the Field Guide card must state the
## SAME number for the same need, because they are two renderings of one derivation. If this
## ever fails, someone has added a second source of truth for a divisor — the exact defect
## the counted-tile rewrite paid for once already.
##
## Anchors on the DATA, not on a rebuilt sentence: for each starter-tier need, the divisor in
## `tiles_per_individual` must appear in front of that need's noun in BOTH surfaces. Rebuild
## a sentence and compare, and the test passes by construction while proving nothing.
##
## Does not host anything, so it has no ordering dependency on `_check_nothing_hosted_names_
## the_villager()`'s `species_hosted_count() == 0` fixture assertion — but it is placed after
## it anyway, alongside the rest of the composer checks it belongs with.
func _check_toast_and_card_state_the_same_numbers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for species: AnimalDefinition in _world.roster.species():
		var tier: HabitatTier = HabitatRecipe.starter_tier(species)
		if tier == null:
			continue
		var toast: String = NewsReportContent.hint_line(species, _world, rng)
		var card_lines: Array[String] = HabitatRecipe.describe_tiers(species, _world)
		if not check(not card_lines.is_empty(), "%s renders a card" % species.id):
			continue
		var card: String = card_lines[0]
		for need: HabitatNeed in tier.needs:
			if need.is_gate_only():
				continue
			var noun: String = HabitatRecipe.need_noun(need.tag, _world)
			if noun.is_empty():
				continue
			var expected: String = "%d %s" % [need.tiles_per_individual, noun]
			var expected_tiles: String = "%d tiles of %s" % [need.tiles_per_individual, noun]
			var expected_one: String = "1 tile of %s" % noun
			var wanted: bool = (
				toast.contains(expected)
				or toast.contains(expected_tiles)
				or toast.contains(expected_one)
			)
			check(wanted,
				"%s's toast states %s's real divisor (%d): '%s'"
				% [species.id, noun, need.tiles_per_individual, toast])
			check(
				card.contains(expected)
				or card.contains(expected_tiles)
				or card.contains(expected_one),
				"...and %s's card states the same one: '%s'" % [species.id, card])


# --- 4. The setting persists ---------------------------------------------------------------

func _check_gameplay_settings_persistence() -> void:
	GameplaySettings.reset_for_test()
	check_eq(GameplaySettings.hints_enabled(), true, "Hints default ON")

	GameplaySettings.set_hints_enabled(false)
	check_eq(GameplaySettings.hints_enabled(), false, "set_hints_enabled(false) reads back false")

	# Reload from disk by resetting the in-memory cache without touching the file — a fresh
	# app launch reading the same file back.
	GameplaySettings._loaded = false
	check_eq(GameplaySettings.hints_enabled(), false,
		"...and the OFF value survives a reload from `user://settings.cfg`, independent of any "
		+ "world save")

	GameplaySettings.reset_for_test()
	check_eq(GameplaySettings.hints_enabled(), true, "reset_for_test() leaves the ON default for later suites")


## Task 5 retired `SettingsOverlay.open()`/`close()`/`is_open()`. As of the 2026-08-25 move off
## `MenuWindow` onto `scenes/menu/SettingsScreen.tscn`, there is no long-lived in-game instance
## left to check against at all — this proves the guarantee ("a fresh checkbox never shows
## stale state") against a freshly-instantiated `SettingsOverlay.tscn` directly, read at the
## point it actually gets painted: `_ready()`.
func _check_settings_overlay_reads_and_writes_the_one_source_of_truth() -> void:
	GameplaySettings.set_hints_enabled(false)
	var packed: PackedScene = load("res://scenes/ui/SettingsOverlay.tscn") as PackedScene
	var overlay: SettingsOverlay = packed.instantiate() as SettingsOverlay
	root.add_child(overlay)
	check_eq(overlay.hints_checked(), false,
		"a freshly-instantiated overlay paints the checkbox from GameplaySettings' live value")

	overlay._on_hints_toggled(true)
	check_eq(GameplaySettings.hints_enabled(), true,
		"toggling the checkbox writes straight through to GameplaySettings — no second copy of the value")

	overlay.queue_free()
	GameplaySettings.reset_for_test()


# --- 5. The toast ------------------------------------------------------------------------------

func _check_toast_behaviour() -> void:
	var toast: NewsReportToast = _ui.news_report_toast
	check(toast.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"NOT A MODAL: the toast's root ignores the mouse everywhere except its own banner")
	check(not toast.is_showing(), "the toast starts hidden")
	check(not toast.show_text(""), "an empty string produces no toast")
	check(not toast.is_showing(), "...and nothing is showing")

	check(toast.show_text("A fox has moved into the forest!"), "a real line shows")
	check(toast.is_showing(), "...and the toast is up")
	check_eq(toast.current_text(), "A fox has moved into the forest!", "...with the exact text handed to it")

	# TAPPED AWAY. spec.md: "auto-dismisses or is tapped away."
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	toast._on_banner_input(tap)
	check(not toast.is_showing(), "a tap on the banner dismisses it early")

	# AUTO-DISMISS, exercised without waiting real seconds. `_process(delta)` is a plain method
	# despite the underscore — calling it directly with a hand-picked delta is the same idiom
	# `NewsReportScheduler.advance(delta)` uses, applied to a Control instead of a RefCounted.
	toast.show_text("Rumor from the hedgerow…")
	check(toast.is_showing(), "a second line shows")
	toast._process(NewsReportToast.DISPLAY_SECONDS - 0.5)
	check(toast.is_showing(), "...still up a half-second before its own display duration")
	toast._process(1.0)
	check(not toast.is_showing(), "...and gone once DISPLAY_SECONDS has elapsed")

	# NO READ-ALOUD BUTTON. spec.md defers "wider [Read-Aloud] coverage (News Reports, Field
	# Guide)" — structural check, the same shape `test_fact_card.gd` uses for its OWN absence
	# assertions.
	var found_read_aloud_button: bool = false
	for child: Node in toast.find_children("*", "Button", true, false):
		found_read_aloud_button = true
	check(not found_read_aloud_button, "the toast has NO Button at all — no Read-Aloud, no dismiss button; tap-the-banner is the whole gesture")

	# QUEUEING. Two lines shown back to back: the second waits.
	toast.show_text("first")
	toast.show_text("second")
	check_eq(toast.current_text(), "first", "the first of two queued lines shows first")
	check_eq(toast.queued_count(), 1, "...and the second is queued, not dropped or shown early")
	toast.dismiss()
	check_eq(toast.current_text(), "second", "...and shows once the first is dismissed")
	toast.dismiss()
	check_eq(toast.queued_count(), 0, "the queue is empty once both have shown")


# --- 6. The wiring, on the real scene --------------------------------------------------------

func _check_wiring_on_the_real_scene() -> void:
	check(_ui.news_report_toast is NewsReportToast, "GameUI carries a NewsReportToast")
	check(_ui.menu_window is MenuWindow, "GameUI carries a MenuWindow")
	check(_ui.news_report_presenter() is NewsReportPresenter, "GameUI carries a NewsReportPresenter")

	# Settings moved off MenuWindow entirely (2026-08-25) onto its own Title-screen-reachable
	# page — there is no in-game SettingsOverlay instance left for the live presenter to listen
	# to. What still has to hold is the other half of the contract: `bind()` reads whatever
	# `GameplaySettings.hints_enabled()` says AT BIND TIME, so a value changed between sessions
	# (from the Title screen) is picked up the moment the next session's world binds — not
	# `_ui.bind_world()` on the SAME world again, which is a documented no-op past the toast
	# reference (`news_report_presenter.gd`'s own `bind()` header), so this exercises a genuinely
	# fresh presenter against a genuinely fresh world instead, same fixture shape as
	# `_check_is_new_world()` below.
	GameplaySettings.set_hints_enabled(false)
	var fresh_presenter := NewsReportPresenter.new()
	root.add_child(fresh_presenter)
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var fresh_world: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(fresh_world)
	fresh_presenter.bind(fresh_world, _ui.news_report_toast)
	check_eq(fresh_presenter._scheduler.hints_enabled, false,
		"a freshly-bound presenter reads GameplaySettings.hints_enabled() at bind time, so an "
		+ "off-session change (made from the Title screen's Settings page) is picked up by the "
		+ "next session")
	fresh_presenter.free()
	fresh_world.free()
	GameplaySettings.reset_for_test()


## END TO END ON THE REAL SCENE. The presenter must compose a hint (not a flavour line),
## keep the pacer fed with the live hosted count, and remember the last species so the
## no-repeat rule has something to work with.
func _check_presenter_fires_a_composed_hint() -> void:
	var presenter: NewsReportPresenter = _ui.news_report_presenter()
	if not check(presenter != null, "GameUI exposes its presenter"):
		return
	var line: String = presenter.compose_next_report()
	check(not line.is_empty(), "the presenter composes a report")
	check(line.contains("tiles of") or line.contains("a house") or line.contains("villager"),
		"...and it is a build hint, not a bare flavour line: '%s'" % line)
	check(not line.contains("_"), "...with no raw tag: '%s'" % line)


## Activity reaches the pacer from the same call site the coach already uses
## (`TapRouter.tile_painted`), so there is no second input path to keep in sync. Fires the
## REAL signal — `_ui.tap_router.tile_painted.emit()` — rather than calling
## `presenter.notice_activity()` directly, because a direct call only proves the presenter's
## own method chain works; it cannot catch `game_ui.gd`'s wiring being dropped or its closure
## capturing a stale presenter. Round-1 fix (2026-09-08): confirmed non-vacuous by temporarily
## deleting the `notice_activity()` call from `game_ui.gd`'s `tile_painted` lambda, seeing this
## check fail, then restoring it — see task-7-report.md.
func _check_activity_reaches_the_pacer() -> void:
	var presenter: NewsReportPresenter = _ui.news_report_presenter()
	if not check(presenter != null, "GameUI exposes its presenter"):
		return
	_ui.tap_router.tile_painted.emit()
	check(presenter.built_recently(),
		"a placement marks the player as building for pacing purposes")


## TASK 7's RE-ENTRANCY GUARD. `GameUI._process()` calls `bind_world()` every frame until both
## `_camera` and `_world` resolve — the setup at the top of this suite already made ONE such
## call (line `_ui.bind_world()` above). `OnboardingCoach` construction and every signal
## connection built alongside it in `bind_world()` sit behind a single `_coach == null` guard;
## that guard is what stands between "built once per session" and "a fresh coach every frame,
## with a fresh duplicate connection stacked onto every wired signal on top of the last one" —
## the literal brief sketch's bug, done as `bind_world()` calling out to build the coach
## unconditionally.
##
## Snapshots each signal's connection count BEFORE two further `bind_world()` calls, then
## checks it is UNCHANGED afterward, rather than asserting a hardcoded "1" — several of these
## signals (`mode_changed`, `help_pressed`) already carry an unrelated permanent connection
## from `GameUI._ready()`, so the coach's own contribution to the count is "stays flat", not
## "is exactly one". A guard-less `bind_world()` would grow every count by one per extra call;
## this fails immediately if that happens.
func _check_coach_wiring_is_idempotent() -> void:
	var coach_after_first_bind: OnboardingCoach = _ui._coach
	if not check(coach_after_first_bind != null,
		"bind_world() constructs a coach the first time it sees a bound world"):
		return

	var wires: Array = [
		[_ui.coach_chip.dismissed, "CoachChip.dismissed"],
		[_ui.tap_router.tile_painted, "TapRouter.tile_painted"],
		[_ui.hud.mode_changed, "GameHud.mode_changed"],
		[_ui.hud.palette_changed, "GameHud.palette_changed"],
		[_ui.hud.help_pressed, "GameHud.help_pressed"],
		[_ui.menu_window.closed, "MenuWindow.closed"],
		[_world.resident_arrived, "WorldRoot.resident_arrived"],
	]
	var before: Array[int] = []
	for wire: Array in wires:
		before.append((wire[0] as Signal).get_connections().size())

	# Two further calls, mirroring the repeated-frame case `_process()` actually drives while
	# `_camera`/`_world` are still resolving — one call alone would not distinguish "guarded"
	# from "happened to run exactly twice already".
	_ui.bind_world()
	_ui.bind_world()

	check(_ui._coach == coach_after_first_bind,
		"two further bind_world() calls do not replace the coach — same instance throughout")

	for i: int in range(wires.size()):
		var sig: Signal = wires[i][0]
		var label: String = wires[i][1]
		var message: String = (
			"%s's connection count is unchanged after two more bind_world() calls" % label
		)
		check_eq(sig.get_connections().size(), before[i], message)


## Final review finding #6: `GameHud.help_pressed`, `GameHud.help_button()`,
## `MenuWindow.open_at_tab()` and `GameUI._on_help_pressed()`'s null-world guard all shipped
## with Task 5 unasserted end to end — nothing proved the `[?]` button actually opens the Field
## Guide tab. This suite already has `_ui`, `_world`, and a bound `MenuWindow` in scope from the
## setup above, so wiring the real button's `pressed` signal (rather than calling
## `_on_help_pressed()` directly) exercises the exact path a player's tap drives.
func _check_help_button_opens_field_guide() -> void:
	check(not _ui.menu_window.is_open(), "fixture: the menu window starts closed")
	_ui.hud.help_button().pressed.emit()
	check(_ui.menu_window.is_open(), "the [?] button opens MenuWindow")
	# `%Tabs`, the same unique-name path `test_menu_window.gd::_check_defaults_to_field_guide_tab()`
	# already reads, rather than reaching into `MenuWindow`'s private `_tabs`.
	var tabs: TabContainer = _ui.menu_window.get_node("%Tabs") as TabContainer
	check_eq(tabs.current_tab, MenuWindow.FIELD_GUIDE_TAB_INDEX,
		"...on the Field Guide tab specifically, not just whichever tab was last open")
	_ui.menu_window.close()


func _check_is_new_world() -> void:
	check_eq(_world.is_new_world, false,
		"a Main.tscn opened directly (this suite's own fixture, the \"none\" path every other "
		+ "suite already relies on) is NOT a new world")

	GameSession.request_new(WorldPreset.default_preset(), "News Report Test", "", SEED)
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	var second: WorldRoot = packed.instantiate() as WorldRoot
	root.add_child(second)
	check_eq(second.is_new_world, true,
		"a world opened through GameSession.request_new() IS a new world")
	# `free()`, not `queue_free()` — this whole suite runs inside one `_process()` call (see
	# `test_save_round_trip.gd`'s identical note), so a queued free would never actually run
	# before `finish()` quits the tree, leaking the second world's ~1,296 tiles.
	second.free()
	GameSession.clear()
