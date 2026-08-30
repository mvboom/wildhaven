extends QATestCase
## WAYPOINT WANDER — Tier 1 row 6's thin form, first of its three clauses.
##
## gdd.md -> Level & world design: "**Animals occupy no tiles** — they roam the walkable
## surface freely within their home neighbourhood's capacity." The floor this suite pins is
## that the world reads as ALIVE rather than as a diorama, and it is four separate claims:
##
##   1. A RESIDENT ACTUALLY MOVES over simulated time. Not "has a roamer object" — its
##      `position` changes, and it covers real ground.
##   2. IT NEVER LEAVES ITS HOME NEIGHBOURHOOD, asserted against **the home site's own
##      radius** rather than against a number copied out of `ResidentRoamer`. The wander
##      radius is clamped to the site's radius at construction, so the containment is
##      structural; this suite proves the clamp binds in BOTH directions — a tight site
##      (radius 2) shrinks the wander, a wide one (radius 8) leaves `WANDER_RADIUS_TILES`
##      in charge.
##   3. THE ANIMATION STATE SWITCHES between Walk and Idle, and **the clip names resolve for
##      every species in the shipped roster.** This is the assertion most likely to catch the
##      next species added: the three shipped models use three different naming conventions
##      (`Idle`, `Bunny|Bunny_idle`, `CharacterArmature|Idle`) and there is no shared contract
##      anywhere in the roster to lean on. It also proves every resolved locomotion clip
##      actually LOOPS (`_check_locomotion_clips_loop()`) — a resolved name that plays once and
##      freezes is the exact glide bug this clause exists to catch — and that a resident only
##      ever plays clips from ITS OWN allowed set, now widened per-species by whatever optional
##      Run and idle-flavor clips `AnimalClips` resolved for that model.
##   4. IT FACES ITS DIRECTION OF TRAVEL. The camera never rotates (gdd.md -> Player
##      Interface), so an animal walking backwards is not a subtlety — it is the most visible
##      possible defect. Checked against the node's OWN basis as the engine computed it, never
##      by re-running the implementation's `atan2`, which would share any bug with it.
##
## PRESENTATION, NOT SIMULATION. That wander cannot move `HabitatSimulation.evaluations_run`
## is asserted in `test_event_driven_simulation.gd`, where the rest of the CPU argument lives —
## including across natural `_process` frames. It is not re-asserted here.
##
## DRIVEN BY HAND, WITH A SEEDED RNG. `ResidentPresentation.tick()` is called directly with a
## fixed step and `attach(..., SEED)` fixes the waypoint dice, so every number below is
## reproducible rather than sampled from a lucky run.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_resident_wander.gd

## Fixes the waypoint dice. Every measurement in this suite is reproducible.
const SEED: int = 20260728

const STEP_SECONDS: float = 0.1
const RUN_SECONDS: float = 120.0

## Every shipped model's ACTUAL clip names (-> D-43, roster grew 3 -> 12). Still only THREE
## distinct conventions in practice: the nine D-43 species (Quaternius farm/woodland pack)
## share the fox's bare `Idle`/`Walk` names, so the non-vacuity check below still proves three
## genuinely different conventions rather than twelve. Pinned as exact strings so a re-import
## that renames a clip fails here rather than in play.
##
## `run` and `idle_flavors` pin the OPTIONAL clips `ResidentRoamer` may also play — a faster
## travel clip on a WALKING leg, or a variety clip (Eating/Wave/an idle variant) on a PAUSED
## one — resolved by `AnimalClips` from whatever each model actually carries. `""` / `[]` where
## a model has none (rabbit has neither); pinned exactly elsewhere so a roster addition or a
## clip rename is caught here.
const EXPECTED_CLIPS: Dictionary = {
	"fox": {
		"idle": "Idle", "walk": "Walk", "run": "Gallop",
		"idle_flavors": ["Eating", "Idle_2", "Idle_2_HeadLow"],
	},
	"rabbit": {"idle": "Bunny|Bunny_idle", "walk": "Bunny|Bunny_walk", "run": "", "idle_flavors": []},
	"human": {
		"idle": "CharacterArmature|Idle", "walk": "CharacterArmature|Walk", "run": "CharacterArmature|Run",
		"idle_flavors": ["CharacterArmature|Idle_Neutral", "CharacterArmature|Wave"],
	},
	"deer": {"idle": "Idle", "walk": "Walk", "run": "Gallop", "idle_flavors": ["Eating", "Idle_2", "Idle_Headlow"]},
	"stag": {"idle": "Idle", "walk": "Walk", "run": "Gallop", "idle_flavors": ["Eating", "Idle_2", "Idle_Headlow"]},
	"horse": {"idle": "Idle", "walk": "Walk", "run": "Gallop", "idle_flavors": ["Eating", "Idle_2", "Idle_Headlow"]},
	"donkey": {"idle": "Idle", "walk": "Walk", "run": "Gallop", "idle_flavors": ["Eating", "Idle_2", "Idle_Headlow"]},
	"cow": {"idle": "Idle", "walk": "Walk", "run": "Gallop", "idle_flavors": ["Eating", "Idle_2", "Idle_Headlow"]},
	"bull": {"idle": "Idle", "walk": "Walk", "run": "Gallop", "idle_flavors": ["Eating", "Idle_2", "Idle_Headlow"]},
	"alpaca": {"idle": "Idle", "walk": "Walk", "run": "Gallop", "idle_flavors": ["Eating", "Idle_2", "Idle_Headlow"]},
	"husky": {"idle": "Idle", "walk": "Walk", "run": "Gallop", "idle_flavors": ["Eating", "Idle_2", "Idle_2_HeadLow"]},
	"shiba_inu": {"idle": "Idle", "walk": "Walk", "run": "Gallop", "idle_flavors": ["Eating", "Idle_2", "Idle_2_HeadLow"]},
	"pig": {"idle": "Idle", "walk": "Walk", "run": "Run", "idle_flavors": []},
	"sheep": {"idle": "Idle", "walk": "Walk", "run": "Run", "idle_flavors": []},
}

## A wide site: `WANDER_RADIUS_TILES` is the binding constraint here.
const WIDE_SITE_RADIUS: int = 8
## A tight site: the SITE's radius is the binding constraint here.
const TIGHT_SITE_RADIUS: int = 2

var _grid: WorldGrid = null
var _props_root: Node3D = null
var _residents_root: Node3D = null
var _presentation: ResidentPresentation = null
var _roster: SpeciesRoster = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("resident wander")

	_roster = SpeciesRoster.new()
	# RE-POINTED (-> D-43, roster grew 3 -> 12): this suite's own claim (see the file header)
	# is "the clip names resolve for every species in the shipped roster", so it cares that
	# every `EXPECTED_CLIPS` entry actually loaded, not that the roster is any particular size.
	if not check(_roster.size() == EXPECTED_CLIPS.size(),
			"the shipped roster loaded (%d species, %d pinned in EXPECTED_CLIPS)"
				% [_roster.size(), EXPECTED_CLIPS.size()]):
		finish()
		return

	_grid = WorldGrid.new()
	_grid.name = "WorldGrid"
	_grid.build(TerrainDefinition.load_all(), 36, 36)
	root.add_child(_grid)

	_props_root = Node3D.new()
	_props_root.name = "HomeProps"
	root.add_child(_props_root)

	_residents_root = Node3D.new()
	_residents_root.name = "Residents"
	root.add_child(_residents_root)

	# NOT added to the tree: its `_process` would tick roamers behind this suite's back and
	# make every measurement below depend on frame timing. The natural-`_process` path is
	# asserted in `test_event_driven_simulation.gd` instead, where it belongs.
	_presentation = ResidentPresentation.new()
	_presentation.attach(_grid, _props_root, SEED)

	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 2:
		return false  # let the tree finish entering before AnimationPlayers are asked to play

	_check_clip_resolution_for_every_roster_species()
	_check_clip_resolver_edge_cases()
	_check_locomotion_clips_loop()
	_check_every_species_animates_through_the_roamer()
	_check_resident_moves_and_stays_home()
	_check_wander_radius_is_clamped_to_the_home_site()
	_check_animation_state_switches()
	_check_faces_direction_of_travel()

	note_expected_pending(
		"ROAM QUALITY IS PARTIALLY DEPTH STILL (spec.md -> What Deepening Buys)",
		"Obstacle avoidance and animal-animal separation were pulled forward (2026-08-24) — "
		+ "see test_resident_navigation.gd for that coverage, not here. Still absent: no "
		+ "personality bias (Shy animals do not hang back), no flocking, no turn easing beyond "
		+ "per-corner re-facing, and only Forest blocks movement (Rock does not, in this pass). "
		+ "Water still stays crossable — a rabbit CAN and does walk across a water tile inside "
		+ "its radius, unchanged, deliberate. None of that is a defect at the floor; all of it "
		+ "is what a further depth purchase buys."
	)
	note_expected_pending(
		"THE HOME PROP IS ONE SCENE FOR EVERY SPECIES",
		"`ResidentPresentation.HOME_PROP_SCENE` is a single den for fox, rabbit and villager "
		+ "alike (villagers get none — a House is its own prop). Per-species props (a burrow, a "
		+ "nest) are content, not a system. Prop behaviour is asserted in `test_home_prop.gd`."
	)

	_presentation.free()
	_presentation = null
	finish()
	return true


# --- 3a. The clip names resolve for EVERY roster species ---------------------------------------

func _check_clip_resolution_for_every_roster_species() -> void:
	var resolved_idle: Array[String] = []
	for species: AnimalDefinition in _roster.species():
		var expected: Dictionary = EXPECTED_CLIPS.get(species.id, {}) as Dictionary
		if not check(not expected.is_empty(),
			"the roster species `%s` has an expected clip pair in this suite" % species.id,
			"a new species was added without pinning its clip names — that is exactly the "
			+ "regression this table exists to catch"):
			continue

		var node: Node3D = species.model_scenes[0].instantiate() as Node3D
		if not check(node != null, "`%s`'s model_scene instantiates" % species.id):
			continue
		var player: AnimationPlayer = AnimalClips.find_player(node)
		if not check(player != null, "`%s`'s model carries an AnimationPlayer" % species.id):
			node.free()
			continue

		var idle: String = AnimalClips.idle_clip(player)
		var walk: String = AnimalClips.walk_clip(player)
		check(idle != "", "`%s`: an Idle clip RESOLVES (not empty)" % species.id)
		check(walk != "", "`%s`: a Walk clip RESOLVES (not empty)" % species.id)
		check_eq(idle, expected["idle"], "`%s`: the resolved Idle clip is exact" % species.id)
		check_eq(walk, expected["walk"], "`%s`: the resolved Walk clip is exact" % species.id)
		check(player.has_animation(idle),
			"`%s`: the resolved Idle clip really exists on the player" % species.id)
		check(player.has_animation(walk),
			"`%s`: the resolved Walk clip really exists on the player" % species.id)
		resolved_idle.append(idle)
		node.free()

	check_eq(resolved_idle.size(), EXPECTED_CLIPS.size(),
		"every roster species resolved an Idle clip (%d)" % resolved_idle.size())
	# NON-VACUITY. If every model happened to share one convention, every assertion above would
	# pass on a resolver that simply returned "Idle". They do not — three distinct conventions
	# survive the roster growing from 3 to 12 (-> D-43) — and that is the point.
	var distinct: Dictionary = {}
	for name: String in resolved_idle:
		distinct[name] = true
	check_eq(distinct.size(), 3,
		"THE THREE CONVENTIONS REALLY DIFFER — %s. A resolver that assumed one name could not "
		% str(distinct.keys()) + "pass the assertions above")


func _check_clip_resolver_edge_cases() -> void:
	# Pass 1 (exact leaf) has to beat pass 2 (shortest containing), or the fox lands on `Idle_2`
	# and the villager on `CharacterArmature|Idle_Gun`.
	var fox: AnimalDefinition = _roster.by_id("fox")
	var node: Node3D = fox.model_scenes[0].instantiate() as Node3D
	var player: AnimationPlayer = AnimalClips.find_player(node)
	check(player.get_animation_list().has("Idle_2"),
		"the fox model really does carry a longer `Idle_2` beside `Idle` (the trap is real)")
	check_eq(AnimalClips.resolve(player, "idle"), "Idle",
		"an EXACT leaf beats a longer containing name — `Idle`, never `Idle_2`")
	check_eq(AnimalClips.resolve(player, "gallop"), "Gallop",
		"the resolver is following the player's own list, not a hardcoded answer")
	check_eq(AnimalClips.resolve(player, "swim"), "",
		"an unresolved clip returns \"\" — a missing clip is a content defect, never a crash")
	check_eq(AnimalClips.resolve(null, "idle"), "", "a null player resolves to \"\"")
	check(AnimalClips.find_player(null) == null, "`find_player(null)` is null, not an error")
	node.free()

	var human: AnimalDefinition = _roster.by_id("human")
	var h_node: Node3D = human.model_scenes[0].instantiate() as Node3D
	var h_player: AnimationPlayer = AnimalClips.find_player(h_node)
	check(h_player.get_animation_list().has("CharacterArmature|Idle_Gun"),
		"the villager model really does carry `Idle_Gun` beside `Idle` (the trap is real)")
	check_eq(AnimalClips.resolve(h_player, "idle"), "CharacterArmature|Idle",
		"...and the prefixed exact leaf still wins")
	h_node.free()


# --- 3a-bis. Every locomotion clip LOOPS ---------------------------------------------------------

func _check_locomotion_clips_loop() -> void:
	# THE GAP THAT LET THE GLIDE BUG THROUGH: resolving a clip NAME is not the same as it
	# looping. A non-looping Walk (or Gallop/Run) plays once, freezes on its last pose, and the
	# resident glides FROZEN while `tick()` keeps moving it — every species but fox/rabbit
	# shipped that way until this suite existed. Every clip a resident can be WALKING or
	# RUNNING to must loop; `_check_clip_resolution_for_every_roster_species()` above already
	# proves the NAMES resolve, this proves the RESOLVED CLIPS actually loop.
	for species: AnimalDefinition in _roster.species():
		var expected: Dictionary = EXPECTED_CLIPS.get(species.id, {}) as Dictionary
		if expected.is_empty():
			continue
		var node: Node3D = species.model_scenes[0].instantiate() as Node3D
		var player: AnimationPlayer = AnimalClips.find_player(node)
		if player == null:
			node.free()
			continue
		var locomotion_clips: Array = [expected["idle"], expected["walk"]]
		if expected["run"] != "":
			locomotion_clips.append(expected["run"])
		for clip_name: String in locomotion_clips:
			if not check(player.has_animation(clip_name),
					"`%s`: locomotion clip `%s` exists" % [species.id, clip_name]):
				continue
			var anim: Animation = player.get_animation(clip_name)
			check_eq(anim.loop_mode, Animation.LOOP_LINEAR,
				"`%s`: `%s` is set to loop (a one-shot locomotion clip IS the glide bug)"
					% [species.id, clip_name])
		node.free()


# --- 3b. Every species animates THROUGH THE ROAMER, ONLY WITH ITS OWN ALLOWED CLIPS -------------

func _check_every_species_animates_through_the_roamer() -> void:
	# The resolver being right is not the same as the roamer using it. One roamer per species,
	# ticked together, and each is required to be playing ONLY clips FROM ITS OWN ALLOWED SET —
	# its pinned Walk/Idle plus whichever optional Run and idle-flavor clips it resolved.
	var presentation := ResidentPresentation.new()
	presentation.attach(_grid, _props_root, SEED)

	var nodes: Array[Node3D] = []
	var ids: Array[String] = []
	var tile_x: int = 6
	for species: AnimalDefinition in _roster.species():
		var site := HomeSite.new(Vector2i(tile_x, 18), species.id, WIDE_SITE_RADIUS, tile_x)
		var node: Node3D = species.model_scenes[0].instantiate() as Node3D
		node.position = _grid.tile_to_world(tile_x, 18)
		_residents_root.add_child(node)
		presentation.present(node, site)
		nodes.append(node)
		ids.append(species.id)
		tile_x += 9

	check_eq(presentation.roamer_count(), _roster.size(),
		"one roamer per species (%d)" % presentation.roamer_count())

	var seen_walk: Dictionary = {}  # id -> Dictionary used as a set of clip names seen WALKING
	var seen_idle: Dictionary = {}  # id -> Dictionary used as a set of clip names seen PAUSED
	for id: String in ids:
		seen_walk[id] = {}
		seen_idle[id] = {}
	for _i in int(RUN_SECONDS / STEP_SECONDS):
		presentation.tick(STEP_SECONDS)
		for r in presentation.roamer_count():
			var roamer: ResidentRoamer = presentation.roamer(r)
			var id: String = ids[r]
			if roamer.state_name() == "Walk":
				(seen_walk[id] as Dictionary)[roamer.current_clip()] = true
			else:
				(seen_idle[id] as Dictionary)[roamer.current_clip()] = true

	var any_ran: bool = false
	var any_flavored: bool = false
	for r in ids.size():
		var id: String = ids[r]
		var expected: Dictionary = EXPECTED_CLIPS[id] as Dictionary
		var allowed_walk: Array = [expected["walk"]]
		if expected["run"] != "":
			allowed_walk.append(expected["run"])
		var allowed_idle: Array = [expected["idle"]]
		allowed_idle.append_array(expected["idle_flavors"] as Array)

		var walk_clips: Dictionary = seen_walk[id] as Dictionary
		var idle_clips: Dictionary = seen_idle[id] as Dictionary
		check(not walk_clips.is_empty(), "`%s` was seen WALKING at least once" % id)
		check(not idle_clips.is_empty(), "`%s` was seen PAUSED at least once" % id)
		for clip: String in walk_clips.keys():
			check(clip in allowed_walk,
				"`%s`: every WALKING clip is in its allowed set %s — saw `%s`"
					% [id, str(allowed_walk), clip])
		for clip: String in idle_clips.keys():
			check(clip in allowed_idle,
				"`%s`: every PAUSED clip is in its allowed set %s — saw `%s`"
					% [id, str(allowed_idle), clip])

		if expected["run"] != "" and walk_clips.has(expected["run"]):
			any_ran = true
		for flavor: String in (expected["idle_flavors"] as Array):
			if idle_clips.has(flavor):
				any_flavored = true

	# NON-VACUITY, at the ROSTER level rather than per-species: one species not rolling its
	# ~18%/~30% chance across 1200 steps is ordinary variance, not a defect. Across the WHOLE
	# roster, at least one resident ran and at least one played an idle flavor, or
	# `RUN_PROBABILITY`/`IDLE_FLAVOR_PROBABILITY` are being rolled by nothing.
	check(any_ran, "at least one species in the roster used its Run/Gallop clip at least once")
	check(any_flavored, "at least one species in the roster used an idle-flavor clip at least once")

	for node in nodes:
		node.free()
	presentation.free()


# --- 1 + 2. It moves, and it stays home --------------------------------------------------------

func _check_resident_moves_and_stays_home() -> void:
	var rabbit: AnimalDefinition = _roster.by_id("rabbit")
	var site := HomeSite.new(Vector2i(18, 18), "rabbit", WIDE_SITE_RADIUS, 0)
	var home: Vector3 = _grid.tile_to_world(site.position.x, site.position.y)

	var node: Node3D = rabbit.model_scenes[0].instantiate() as Node3D
	node.position = home
	_residents_root.add_child(node)
	_presentation.present(node, site)

	var roamer: ResidentRoamer = _presentation.roamer(0)
	if not check(roamer != null, "a roamer was created for the resident"):
		return

	var start: Vector3 = node.position
	var path_length: float = 0.0
	var max_from_home: float = 0.0
	var breaches: int = 0
	var previous: Vector3 = start
	var steps: int = int(RUN_SECONDS / STEP_SECONDS)
	for _i in steps:
		_presentation.tick(STEP_SECONDS)
		path_length += previous.distance_to(node.position)
		previous = node.position
		var from_home: float = Vector2(node.position.x - home.x, node.position.z - home.z).length()
		max_from_home = maxf(max_from_home, from_home)
		# CLAUSE 2, asserted against THE SITE'S OWN RADIUS — not a literal, and not the roamer's
		# constant either, so retuning `WANDER_RADIUS_TILES` upward can never quietly widen this.
		if from_home > float(site.radius) + ResidentRoamer.ARRIVAL_EPSILON_TILES:
			breaches += 1

	# CLAUSE 1: it moved.
	check(node.position != start,
		"THE RESIDENT MOVED: position changed over %.0f simulated seconds" % RUN_SECONDS,
		"start %s, end %s" % [start, node.position])
	check(path_length > 5.0,
		"...and it covered real ground: %.1f tiles of path in %.0f s" % [path_length, RUN_SECONDS])

	# CLAUSE 2: it never left the neighbourhood.
	check_eq(breaches, 0,
		"NEVER LEFT ITS HOME NEIGHBOURHOOD: %d of %d samples outside the home site's own radius "
		% [breaches, steps] + "(%d tiles); furthest reached %.2f" % [site.radius, max_from_home])

	# NON-VACUITY for clause 2: containment is not true merely because the animal barely moved.
	# It got most of the way to its wander boundary, so the bound was actually approached.
	check(max_from_home > roamer.wander_radius() * 0.5,
		"...and the containment is not vacuous — it reached %.2f tiles out, past half of its "
		% max_from_home + "%.2f-tile wander radius" % roamer.wander_radius())

	# Y never drifts: residents are anchored at ground level and this is a 2D walk.
	check(is_equal_approx(node.position.y, home.y),
		"the walk stays on the ground plane (y unchanged)")

	node.free()


func _check_wander_radius_is_clamped_to_the_home_site() -> void:
	# BOTH DIRECTIONS OF THE CLAMP. `_radius = min(WANDER_RADIUS_TILES, home_radius)`, so:
	#   * a wide site leaves the constant in charge;
	#   * a tight site overrides it — and that is what makes "within their home neighbourhood"
	#     structural rather than a value someone has to keep in sync.
	var rabbit: AnimalDefinition = _roster.by_id("rabbit")
	var presentation := ResidentPresentation.new()
	presentation.attach(_grid, _props_root, SEED)

	var wide := HomeSite.new(Vector2i(10, 26), "rabbit", WIDE_SITE_RADIUS, 0)
	var tight := HomeSite.new(Vector2i(26, 26), "rabbit", TIGHT_SITE_RADIUS, 1)
	var wide_node: Node3D = rabbit.model_scenes[0].instantiate() as Node3D
	wide_node.position = _grid.tile_to_world(wide.position.x, wide.position.y)
	_residents_root.add_child(wide_node)
	var tight_node: Node3D = rabbit.model_scenes[0].instantiate() as Node3D
	tight_node.position = _grid.tile_to_world(tight.position.x, tight.position.y)
	_residents_root.add_child(tight_node)
	presentation.present(wide_node, wide)
	presentation.present(tight_node, tight)

	var wide_roamer: ResidentRoamer = presentation.roamer(0)
	var tight_roamer: ResidentRoamer = presentation.roamer(1)

	check(WIDE_SITE_RADIUS > ResidentRoamer.WANDER_RADIUS_TILES,
		"the wide site (%d) is wider than WANDER_RADIUS_TILES (%.1f), so the constant binds there"
			% [WIDE_SITE_RADIUS, ResidentRoamer.WANDER_RADIUS_TILES])
	check(TIGHT_SITE_RADIUS < ResidentRoamer.WANDER_RADIUS_TILES,
		"the tight site (%d) is tighter, so THE SITE binds there" % TIGHT_SITE_RADIUS)
	check_eq(wide_roamer.wander_radius(), ResidentRoamer.WANDER_RADIUS_TILES,
		"a wide home leaves the wander radius at the constant")
	check_eq(tight_roamer.wander_radius(), float(TIGHT_SITE_RADIUS),
		"A TIGHT HOME SHRINKS THE WANDER TO ITS OWN RADIUS — the clamp is real, not decorative")

	# And the tight one is measured, not just declared.
	var tight_home: Vector3 = _grid.tile_to_world(tight.position.x, tight.position.y)
	var tight_max: float = 0.0
	for _i in int(RUN_SECONDS / STEP_SECONDS):
		presentation.tick(STEP_SECONDS)
		tight_max = maxf(tight_max, Vector2(
			tight_node.position.x - tight_home.x, tight_node.position.z - tight_home.z
		).length())
	check(tight_max <= float(TIGHT_SITE_RADIUS) + ResidentRoamer.ARRIVAL_EPSILON_TILES,
		"...and the tight resident never got further than %d tiles out (max %.2f)"
			% [TIGHT_SITE_RADIUS, tight_max])
	check(tight_max > 0.5,
		"...having actually roamed inside it (max %.2f tiles), so the bound is not vacuous"
			% tight_max)

	wide_node.free()
	tight_node.free()
	presentation.free()


# --- 3c. Walk / Idle really alternate ----------------------------------------------------------

func _check_animation_state_switches() -> void:
	var rabbit: AnimalDefinition = _roster.by_id("rabbit")
	var presentation := ResidentPresentation.new()
	presentation.attach(_grid, _props_root, SEED)
	var site := HomeSite.new(Vector2i(14, 8), "rabbit", WIDE_SITE_RADIUS, 0)
	var node: Node3D = rabbit.model_scenes[0].instantiate() as Node3D
	node.position = _grid.tile_to_world(site.position.x, site.position.y)
	_residents_root.add_child(node)
	presentation.present(node, site)
	var roamer: ResidentRoamer = presentation.roamer(0)

	var walk_frames: int = 0
	var idle_frames: int = 0
	var transitions: int = 0
	var walk_clip_wrong: int = 0
	var idle_clip_wrong: int = 0
	var previous: String = roamer.state_name()
	var expected: Dictionary = EXPECTED_CLIPS["rabbit"] as Dictionary

	for _i in int(RUN_SECONDS / STEP_SECONDS):
		presentation.tick(STEP_SECONDS)
		var state: String = roamer.state_name()
		if state != previous:
			transitions += 1
			previous = state
		if state == "Walk":
			walk_frames += 1
			if roamer.current_clip() != expected["walk"]:
				walk_clip_wrong += 1
		else:
			idle_frames += 1
			if roamer.current_clip() != expected["idle"]:
				idle_clip_wrong += 1

	check(walk_frames > 0, "the resident spent time WALKING (%d frames)" % walk_frames)
	check(idle_frames > 0, "...and time IDLE (%d frames)" % idle_frames)
	check(transitions >= 4,
		"the state switched back and forth %d times — it is a cycle, not a one-shot" % transitions)
	check_eq(walk_clip_wrong, 0,
		"the Walk clip played on EVERY walking frame (%d frames, %d wrong)"
			% [walk_frames, walk_clip_wrong])
	check_eq(idle_clip_wrong, 0,
		"the Idle clip played on EVERY idle frame (%d frames, %d wrong)"
			% [idle_frames, idle_clip_wrong])

	node.free()
	presentation.free()


# --- 4. It faces where it is going -------------------------------------------------------------

func _check_faces_direction_of_travel() -> void:
	var rabbit: AnimalDefinition = _roster.by_id("rabbit")
	var presentation := ResidentPresentation.new()
	presentation.attach(_grid, _props_root, SEED)
	var site := HomeSite.new(Vector2i(28, 10), "rabbit", WIDE_SITE_RADIUS, 0)
	var node: Node3D = rabbit.model_scenes[0].instantiate() as Node3D
	node.position = _grid.tile_to_world(site.position.x, site.position.y)
	_residents_root.add_child(node)
	presentation.present(node, site)
	var roamer: ResidentRoamer = presentation.roamer(0)

	var samples: int = 0
	var worst_error: float = 0.0
	var backwards: int = 0
	var headings: Dictionary = {}

	for _i in int(RUN_SECONDS / STEP_SECONDS):
		var was_walking: bool = roamer.state_name() == "Walk"
		var before: Vector3 = node.position
		presentation.tick(STEP_SECONDS)
		if not was_walking:
			continue
		var travel := Vector2(node.position.x - before.x, node.position.z - before.z)
		if travel.length() < 1e-4:
			continue
		samples += 1
		# Read the model's forward off the NODE'S OWN BASIS as the engine computed it. glTF 2.0
		# fixes +Z as the front of an asset, and `FACING_YAW_OFFSET_RADIANS` is 0 for that reason.
		# Deliberately not re-deriving `atan2` here: a test that recomputed the implementation's
		# own expression would share any sign error with it and pass anyway.
		var forward := Vector2(node.global_transform.basis.z.x, node.global_transform.basis.z.z)
		var error: float = absf(forward.normalized().angle_to(travel.normalized()))
		worst_error = maxf(worst_error, error)
		if forward.normalized().dot(travel.normalized()) <= 0.0:
			backwards += 1
		headings[snappedf(travel.angle(), 0.1)] = true

	check(samples > 50, "%d walking samples measured" % samples)
	check_eq(backwards, 0,
		"NEVER WALKS BACKWARDS: %d of %d walking samples had the model facing away from travel"
			% [backwards, samples])
	check(worst_error < 0.001,
		"the model's +Z is aligned with the direction of travel on every sample (worst error "
		+ "%.6f rad)" % worst_error)
	check_eq(ResidentRoamer.FACING_YAW_OFFSET_RADIANS, 0.0,
		"the facing offset is 0 — the glTF 2.0 \"front faces +Z\" convention, not a taste value")

	# NON-VACUITY: the animal really turned. A single fixed heading would satisfy every
	# assertion above on a roamer that never rotates at all.
	check(headings.size() >= 3,
		"...across %d distinct headings, so the facing is tracking rather than constant"
			% headings.size())

	node.free()
	presentation.free()
