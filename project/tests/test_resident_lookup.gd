extends QATestCase
## THE GHOST HITBOX — the defect that lit this fuse, and the assertions that make it
## unrepeatable.
##
## gdd.md -> Inspect Mode: "an animal standing on a tappable tile always wins the tap —
## generous animal hitboxes beat ambiguous taps for young kids." That is a Pillar 3
## invariant, and it is **only true if the hitbox is where the animal actually is**. Residents
## wander now (row 6), so the UI's old arrival-time list (`ui/resident_index.gd`, deleted) was
## wrong from the animal's first step.
##
## THE SYMPTOM WAS NOT "THE ANIMAL STOPS BEING TAPPABLE", and that is why it needs asserting
## from both ends. Zoomed to `CameraRig.ZOOM_DEFAULT_TILES` (D-41's fixed pan/zoom camera; see
## `_aim_camera_at_habitat()` below), an animal is still a large fraction of the screen, so the
## effective tap radius is far past the 44 px floor and the floor never binds — ui-engineer
## originally measured ~110 px in a real window at the OLD first-person camera's street zoom;
## this suite measures the same relation live under the current camera instead (the number
## itself is not the point, since it depends on the zoom level chosen — see the assertion's own
## comment) and asserts the RELATION, that the radius exceeds the floor, rather than either
## number. An index
## keyed to the arrival point therefore left a **ghost hitbox standing over the empty den**: a
## tap on bare ground opened a fact card *and silently declined to paint the tile the player was
## aiming at*. So this suite asserts the negative directly — a tap at the stale point must
## **miss the resident AND perform the mode's action**. A "the live tap hits" assertion alone
## would pass with the ghost still standing.
##
## AND IT IS DETERMINISTIC, NOT TIME-LUCKY. ui-engineer reported the old failure as
## intermittent: in one run of three the rabbit wandered back inside the stale hitbox by
## t=120 s. Nothing here runs for a fixed duration and hopes. The waypoint dice are seeded, and
## the suite walks the resident until a **geometric** criterion holds — its live screen point is
## further from the stale one than the live tap radius — and only then taps. The criterion is
## re-checked at the instant of every single tap, so an animal that wandered back would fail
## the pre-condition loudly rather than flip an assertion silently.
##
## Wander is hand-driven here (`ResidentPresentation._process` is switched off) for the same
## reason: a frame-timing-dependent position would make every measurement below a sample.
##
## THE CAMERA (D-41, fixed pan/zoom). `screen_to_grid()` and `ResidentPicker.pick()` both read
## `get_viewport().get_camera_3d()` generically, so they work against ANY active camera
## unmodified. What this fixture needs from the camera is simply that the habitat and the
## animal's whole wander area stay IN FRAME for the suite's whole run — `_aim_camera_at_habitat()`
## below focuses/zooms the camera on the home site once (`set_focus()`/`set_zoom_tiles()`),
## which is enough: the projection maths below (`_screen_of()`/`_tap_radius()`) is unaffected by
## whether a point is inside the visible viewport rectangle, only by whether it is behind the
## camera (`is_position_behind()`, which is exactly what `ResidentPicker.pick()` itself guards
## on) — see that helper's own comment.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_resident_lookup.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"

## Fixes the waypoint dice, so "how far it had walked" is a reproducible number.
const SEED: int = 20260728

## The rabbit's habitat, put near the middle of the world — position no longer matters for
## "does the default camera frame it" (`CameraRig.initialize()`'s default focus/zoom does not
## start anywhere near this block by default), because `_aim_camera_at_habitat()` below
## explicitly focuses/zooms the camera onto it, the same "focus-and-tap" fixture pattern
## (D-41) every other rewritten suite uses.
const ROCK_ORIGIN := Vector2i(16, 17)
const ROCK_W: int = 4
const ROCK_D: int = 3

const WANDER_STEP_SECONDS: float = 0.1
## Cap on the wander loop, in steps. 6000 x 0.1 s = 600 simulated seconds — far more than the
## ~4-8 s the animal actually needs, and a hard bound so a stuck roamer fails instead of hangs.
const MAX_WANDER_STEPS: int = 6000

var _world: WorldRoot = null
var _ui: GameUI = null
var _hud: GameHud = null
var _router: TapRouter = null
var _card: FactCard = null
var _camera: Camera3D = null

var _site: HomeSite = null
var _resident: Node3D = null
var _roamer: ResidentRoamer = null
var _arrival_world: Vector3 = Vector3.ZERO
var _arrival_screen: Vector2 = Vector2.ZERO

var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("resident lookup (live positions)")

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

	_ui = _world.get_node_or_null("GameUI") as GameUI
	if not check(_ui != null, "Main.tscn instances the GameUI shell"):
		finish()
		return true
	_ui.bind_world()
	_hud = _ui.hud
	_router = _ui.tap_router
	_card = _ui.fact_card
	_camera = root.get_viewport().get_camera_3d()
	(_camera as CameraRig).initialize()

	_check_there_is_exactly_one_hit_test_in_the_build()
	if not _land_a_wandering_rabbit():
		finish()
		return true
	_check_the_hitbox_travels_with_the_animal()
	_check_priority_rule_while_moving_in_all_three_modes()
	_check_the_stale_point_misses_AND_the_action_lands()
	_check_control_with_the_resident_removed()

	note_expected_pending(
		"`resident_picker.gd`'s header still names the DELETED `ResidentIndex`",
		"scripts/world/resident_picker.gd:10-15 and :26-28 describe `project/scripts/ui/"
		+ "resident_index.gd` in the present tense (\"Its own header calls this out\", \"which is "
		+ "why that class is meant to be deleted rather than kept alongside this one\"). The file "
		+ "is gone. Documentation only — no behaviour depends on it — and NOT fixed here, because "
		+ "it is outside QA's test artifacts. Reported for gameplay-engineer."
	)
	note_expected_pending(
		"`WorldRoot` STILL HAS NO ROSTER ACCESSOR, so two UI files reach `world.roster` directly",
		"`tap_router.gd:247 species_definition()` and `neighborhood_preview.gd:152 species_ids()` "
		+ "both probe for a method that does not exist and then fall back to the public `roster` "
		+ "field. Both say so in their own headers and both keep ONE roster, which is the "
		+ "important part — but the public API in `world_root.gd`'s header does not list `roster`, "
		+ "so the UI depends on a surface the facade does not advertise. Reported, not fixed."
	)

	finish()
	return true


# --- One hit test, structurally -----------------------------------------------------------------

func _check_there_is_exactly_one_hit_test_in_the_build() -> void:
	# `ResidentIndex` is gone. Asserted against the project's own global class list rather than
	# against the filesystem, so a re-introduction under any path fails here.
	var names: Array[String] = []
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		names.append(entry["class"] as String)
	check(not names.has("ResidentIndex"),
		"`ResidentIndex` NO LONGER EXISTS as a class — there is one resident hit test in the "
		+ "build, so there is one copy of its constants and nothing to drift")
	check(names.has("ResidentPicker"),
		"...and `ResidentPicker` is the one that does (control: the list is really populated)")

	# The constants moved with it, verbatim. A second copy is the failure mode being prevented.
	check_eq(ResidentPicker.MIN_TAP_RADIUS_PIXELS, 44.0,
		"the tap-radius floor is 44 px — sized to the UI's own minimum hit target")
	check_eq(ResidentPicker.TAP_RADIUS_TILE_FRACTION, 0.8,
		"...and grows with zoom at 0.8 of a tile")


# --- Fixture: a real rabbit that has really walked ------------------------------------------------

func _land_a_wandering_rabbit() -> bool:
	# Deterministic wander: re-seed the presentation's dice and take it off `_process`, so the
	# only thing that advances a roamer in this suite is this suite.
	var props_root: Node3D = _world.get_node_or_null("HomeProps") as Node3D
	if not check(props_root != null, "the world has a HomeProps root"):
		return false
	_world.presentation.attach(_world.grid, props_root, SEED)
	_world.presentation.set_process(false)
	_world.simulation.set_process(false)

	# RE-POINTED (-> D-29 #1, `WorldGrid.START_TERRAIN_ID` "grass" -> "wild_grass"): the rabbit
	# needs BOTH `open_grass` and `cover`, and `wild_grass` (the new default) supplies neither
	# implicitly — this border supplies the `open_grass` half the old ambient `grass` backdrop
	# used to give away for free.
	for x in range(ROCK_ORIGIN.x - 1, ROCK_ORIGIN.x + ROCK_W + 1):
		for z in range(ROCK_ORIGIN.y - 1, ROCK_ORIGIN.y + ROCK_D + 1):
			var inside_rock: bool = (
				x >= ROCK_ORIGIN.x and x < ROCK_ORIGIN.x + ROCK_W
				and z >= ROCK_ORIGIN.y and z < ROCK_ORIGIN.y + ROCK_D
			)
			if not inside_rock:
				_world.paint_tile(x, z, "grass")
	for dx in ROCK_W:
		for dz in ROCK_D:
			_world.paint_tile(ROCK_ORIGIN.x + dx, ROCK_ORIGIN.y + dz, "rock")
	for _i in 60:
		_world.simulation.tick(0.0)
	_world.simulation.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)

	# RE-DERIVED 2026-07-28 (-> D-27 #2). At the retuned divisor this block can qualify more than
	# one home site (see `test_causality_end_to_end.gd`'s pending note on fragmentation) — this
	# suite only needs ONE real resident to track through the wander/tap checks below, so it
	# takes any site that landed one rather than pinning the total.
	if not check(_world.total_residents() >= 1,
		"at least one rabbit moved in through the real causal path (%d residents)"
			% _world.total_residents()):
		return false
	# RE-POINTED (-> D-29 #1): picking "the first site in registry iteration order" used to be
	# arbitrary but harmless, because the old ambient `grass` backdrop only ever left ONE
	# prospective candidate on this exact block. Painting the habitat's `open_grass` half
	# explicitly (above) makes the border tiles themselves candidate positions too, so several
	# sites can now register across the painted block. Picking the one NEAREST `ROCK_ORIGIN` —
	# the centre of the habitat this fixture actually paints — is a deterministic, principled
	# choice rather than whichever one happened to register first.
	var best_distance: int = -1
	for site: HomeSite in _world.registry.sites():
		if site.population() <= 0:
			continue
		var d: int = site.distance_squared_to(ROCK_ORIGIN)
		if best_distance < 0 or d < best_distance:
			best_distance = d
			_site = site
			_resident = site.residents[0]
	if not check(_resident != null, "...and it has a resident node"):
		return false

	# RE-POINTED (-> D-29 #1): fragmentation (above) can land MORE than one resident on this
	# block, and this suite's checks below drive `_world.presentation.tick()` directly (not
	# through `_process`, which is off) — which advances EVERY roamer, not only the tracked
	# one. A second resident wandering near the tracked one's arrival point would make the
	# "stale point hits nobody" and "the live point hits nobody once the animal is removed"
	# checks false for a reason that has nothing to do with what they test. This suite's own
	# subject is ONE real rabbit that has really walked, so every OTHER site this fixture
	# produced is cleared here, deterministically, rather than tolerated as interference.
	for other: HomeSite in _world.registry.sites().duplicate():
		if other == _site:
			continue
		for resident: Node3D in other.residents.duplicate():
			if resident != null and is_instance_valid(resident):
				resident.queue_free()
		other.residents.clear()
		_world.presentation.release(other)
		_world.registry.unregister(other)
	check_eq(_world.total_residents(), 1,
		"every OTHER site this fixture produced is cleared — exactly one resident remains, the "
		+ "one this suite tracks")

	# RE-POINTED (-> D-29 #1): with several sites now able to register on this block (see above),
	# `roamer(0)` is not necessarily the tracked resident's own roamer any more — find the one
	# that actually belongs to `_resident`, by identity, rather than assuming index 0.
	var i: int = 0
	while true:
		var candidate: ResidentRoamer = _world.presentation.roamer(i)
		if candidate == null:
			break
		if candidate.resident() == _resident:
			_roamer = candidate
			break
		i += 1
	if not check(_roamer != null and _roamer.resident() == _resident,
		"...and a roamer of its own"):
		return false

	# The move-in fired row 7's card. Dismissed here so every tap below is measured against a
	# clean screen rather than against `TapRouter`'s card-is-open short circuit.
	check(_card.is_open(), "the move-in opened the fact card (row 7's signature moment)")
	_card.dismiss()
	check(not _card.is_open(), "...and it is dismissed before any tap is measured")

	# FOCUS-AND-TAP FIXTURE (D-41): focus/zoom the camera onto the home site, once, before any
	# screen-space measurement below. See the file header's THE CAMERA note for why one aim
	# covers the whole suite rather than needing to re-aim per check.
	_aim_camera_at_habitat(_site.position)

	_arrival_world = _resident.position
	_arrival_screen = _screen_of(_arrival_world)
	check(_arrival_world.is_equal_approx(_world.grid_to_world(_site.position.x, _site.position.y)),
		"the resident starts standing on its home site — this is the point the OLD index recorded")

	# The measurement the whole defect turns on. At the zoom this fixture uses, the tap target is
	# a large fraction of the screen, not the 44 px floor, which is why a stale point kept HITTING.
	var radius: float = _tap_radius(_arrival_world)
	check(radius > ResidentPicker.MIN_TAP_RADIUS_PIXELS,
		"AT THIS ZOOM (D-41's fixed pan/zoom camera): the effective tap radius is "
		+ "%.0f px, well past the %.0f px floor — a ghost hitbox here is a big target, not a pixel"
			% [radius, ResidentPicker.MIN_TAP_RADIUS_PIXELS])
	return true


# --- The hitbox travels with the animal -----------------------------------------------------------

func _check_the_hitbox_travels_with_the_animal() -> void:
	var steps: int = _walk_until_clear_of_the_ghost()
	check(steps > 0,
		"the resident walked clear of its arrival point in %d steps (%.1f simulated seconds)"
			% [steps, steps * WANDER_STEP_SECONDS],
		"it never got a full tap radius away within %d steps" % MAX_WANDER_STEPS)
	check(steps < MAX_WANDER_STEPS, "...well inside the step cap, so nothing is stuck")

	var separation: float = _screen_of(_resident.position).distance_to(_arrival_screen)
	check(separation > _tap_radius(_resident.position),
		"IT IS CLEAR OF ITS OWN GHOST: %.0f px of separation against a %.0f px tap radius"
			% [separation, _tap_radius(_resident.position)])
	check(_resident.position.distance_to(_arrival_world) > 0.0,
		"...having genuinely moved %.2f tiles from where it arrived"
			% _resident.position.distance_to(_arrival_world))

	# THE LIVE POSITION HITS.
	var live: Vector2 = _screen_of(_resident.position)
	var record: Dictionary = _world.resident_record_at(live)
	check(not record.is_empty(), "A TAP AT THE ANIMAL'S LIVE POSITION RESOLVES TO IT")
	check(record.get("node") == _resident, "...to that exact node")
	check_eq(record.get("species_id", ""), "rabbit", "...with its species id")
	check_eq(record.get("home_tile", Vector2i.ZERO), _site.position,
		"...and its home tile, which is what a capacity readout would be computed from")
	check(_world.resident_at(live) == _resident,
		"`resident_at()` and `resident_record_at()` agree — one query, two shapes")

	# THE ARRIVAL POSITION DOES NOT.
	check(_world.resident_record_at(_arrival_screen).is_empty(),
		"AND A TAP AT ITS ARRIVAL POSITION RESOLVES TO NOBODY — the ghost hitbox is gone")
	check(_world.resident_at(_arrival_screen) == null, "...through both entry points")

	# The lookups by node, and their misses.
	check_eq(_world.resident_species_id(_resident), "rabbit", "`resident_species_id()` resolves")
	check_eq(_world.resident_home_tile(_resident), _site.position, "`resident_home_tile()` resolves")
	check_eq(_world.resident_species_id(_world), "",
		"...and a node that is not a resident resolves to \"\", not to a wrong species")
	check_eq(_world.resident_home_tile(_world), Vector2i(-1, -1),
		"...and to Vector2i(-1, -1), not to a wrong tile")
	check_eq(_world.resident_species_id(null), "", "`resident_species_id(null)` is \"\"")


# --- The priority rule, WHILE THE ANIMAL IS MOVING, in all three modes -----------------------------

## RE-POINTED (-> D-29 #7): the priority rule stopped being uniform across the three modes.
## gdd.md's "an animal standing on a tappable tile always wins the tap" now holds ONLY in
## Inspect; in Terraform and Build the tile action under the cursor always wins instead, and
## `TapRouter.handle_tap()` never even runs the resident query there — so a tap on the MOVING
## animal in those two modes now performs the mode's action, exactly as it would over bare
## ground. Inspect's half of this function is untouched by the ruling; Terraform/Build are
## rewritten to assert the new rule rather than deleting coverage of the conflict D-29 #7
## exists to resolve.
func _check_priority_rule_while_moving_in_all_three_modes() -> void:
	# INSPECT — unchanged: the moving animal still wins the tap here.
	var live: Vector2 = _step_to_a_walking_tap()
	check_eq(_router.handle_tap(live), TapRouter.RESULT_RESIDENT,
		"INSPECT: a tap on the MOVING animal resolves to the animal")
	# REPOINTED (Task 5, notification-surfaces): the replay routes to the feed now, never the
	# big card — see `test_fact_card.gd`'s `_check_tap_to_replay_in_inspect()` for the same
	# pattern.
	check(not _card.is_open(), "...and does NOT reopen the big card — the replay routes to the feed instead")
	var feed: NotificationFeed = _ui.notification_feed
	var rabbit: AnimalDefinition = _world.roster.by_id("rabbit")
	check_eq(feed.entry_texts()[0], "%s. %s" % [rabbit.display_name, rabbit.effective_fact_text()],
		"...the feed gains the replay entry instead, with the same verbatim copy")

	# TERRAFORM — on a tile where the paint WOULD have succeeded, so a real conversion proves
	# the tile action ran rather than merely failing to find the resident.
	var before: Vector3 = _resident.position
	live = _step_to_a_walking_tap()
	check(_resident.position != before, "the animal moved again between taps (it is not parked)")
	var tile: Vector2i = _world.screen_to_grid(live)
	check(tile.x >= 0, "the tap point is over a real tile %s" % tile)
	_hud.set_mode(GameHud.Mode.TERRAFORM)
	check(_hud.select_palette_option("water"), "water is selected in the Terraform palette")
	check(_world.can_paint(tile.x, tile.y, "water"), "a Terraform tap here WOULD have succeeded")
	check(not _world.resident_record_at(live).is_empty(),
		"the resident really is standing at the tapped point before the tap")
	check_eq(_router.handle_tap(live), TapRouter.RESULT_PAINTED,
		"D-29 #7: TERRAFORM never runs the resident query — the tile action wins even though the "
		+ "MOVING animal stands on it")
	check_eq(_world.get_tile_terrain(tile.x, tile.y), "water",
		"...and the tile it was standing on WAS painted")
	check(not _card.is_open(), "...and no card fired — the resident query never ran")

	# BUILD — walked on until the animal stands somewhere a House really could go.
	before = _resident.position
	live = _step_to_a_walking_tap_on_buildable_ground()
	check(_resident.position != before, "the animal moved again before the Build tap")
	tile = _world.screen_to_grid(live)
	_hud.set_mode(GameHud.Mode.BUILD)
	check(_hud.select_palette_option("house"), "the House is selected in the Build palette")
	check(_world.can_place(tile.x, tile.y, "house"), "a Build tap here WOULD have succeeded")
	check(not _world.resident_record_at(live).is_empty(),
		"the resident really is standing at the tapped point before the tap")
	var wood_before: int = _world.get_wood()
	check_eq(_router.handle_tap(live), TapRouter.RESULT_PLACED,
		"D-29 #7: BUILD never runs the resident query — the tile action wins even though the "
		+ "MOVING animal stands on it")
	check(_world.grid.is_occupied(tile.x, tile.y), "...and the House WAS built on top of it")
	check(_world.get_wood() < wood_before, "...and Wood was spent")
	check(not _card.is_open(), "...and no card fired — the resident query never ran")


# --- The negative that names the real symptom -------------------------------------------------------

func _check_the_stale_point_misses_AND_the_action_lands() -> void:
	# THE ASSERTION THIS SUITE EXISTS FOR. The old defect was not only "the animal is untappable
	# at its new spot": a tap on the empty den opened a card *and silently declined to paint*.
	# Both halves are asserted, at one screen point, in one tap.
	_walk_until_clear_of_the_ghost()
	var stale_tile: Vector2i = _world.screen_to_grid(_arrival_screen)
	check(stale_tile.x >= 0, "the stale point is over a real tile %s" % stale_tile)
	# D-41 NOTE: `_arrival_screen` is `_screen_of(_arrival_world)` — the screen point of the
	# animal's ELEVATED body-centre anchor, matching what `ResidentPicker` itself hit-tests
	# against. Under D-33's steeper first-person pitch, raycasting that same screen point back
	# to the ground (what `screen_to_grid()` does) landed back on the den's own tile; under
	# D-41's shallower, FIXED 26.565° pitch it does not — the ray continues
	# `BODY_CENTRE_HEIGHT / tan(26.565°) ≈ 0.9` world units further along the view direction,
	# which is more than half a tile, so it deterministically lands on the diagonal neighbour
	# instead (verified analytically, not a flaky projection — this holds at every zoom, since
	# it is an orthographic, zoom-independent shift). Ordinary isometric-camera behaviour, not a
	# defect. The shift is EXACT, not merely "nearby": at this fixture's fixed 45° yaw the 0.9-unit
	# world-space shift splits into `0.9 * cos(45°) ≈ 0.636` units along each of x and z, which
	# always crosses exactly one tile boundary on each axis in the SAME direction — never zero,
	# never two — so the landing tile is always the den's tile minus one on both axes, not merely
	# "within one tile" of it. Asserted as an exact equality so a regression in the framing math
	# (e.g. the wrong sign, or a shift that stops crossing a full tile) would actually fail this,
	# which a loose ±1 box would not have caught.
	check_eq(stale_tile, _site.position - Vector2i(1, 1),
		"...lands exactly one tile diagonally in from the den (%s vs den %s) — bare ground now"
			% [stale_tile, _site.position])

	check(_world.resident_record_at(_arrival_screen).is_empty(),
		"the stale point hits NO resident (checked at the instant of the tap, not at t=0)")

	_hud.set_mode(GameHud.Mode.TERRAFORM)
	_hud.select_palette_option("water")
	check(_world.can_paint(stale_tile.x, stale_tile.y, "water"),
		"a paint at the stale point WOULD succeed")
	var result: String = _router.handle_tap(_arrival_screen)
	check_eq(result, TapRouter.RESULT_PAINTED,
		"A TAP ON THE EMPTY DEN PERFORMS THE MODE'S ACTION — it paints, as the player aimed to")
	check_eq(_world.get_tile_terrain(stale_tile.x, stale_tile.y), "water",
		"...and the tile really converted (the silent decline is gone)")
	check(not _card.is_open(),
		"...and NO fact card opened over bare ground — no ghost animal to inspect")


func _check_control_with_the_resident_removed() -> void:
	# The control that makes every RESULT_RESIDENT above mean something: with the animal gone,
	# the identical live tap edits the tile. Without it, all of the above passes on a router
	# that never edits anything.
	#
	# Every OTHER site this fixture could have fragmented into was cleared in
	# `_land_a_wandering_rabbit()`, so "the world now has one fewer resident" is a clean 1 -> 0
	# here, not a delta against an unpinned total.
	#
	# RE-POINTED (-> D-29 #7): the earlier Terraform/Build checks now genuinely mutate the world
	# (they used to be no-ops under the old uniform priority rule), so the tracked resident's
	# wander area can contain a House it walked past or the water tile it stood on. Walk until it
	# is somewhere the control tap can actually land on — a plain, paintable, unoccupied tile —
	# so "a paint here WOULD succeed" is a real precondition rather than hopeful.
	var live: Vector2 = _screen_of(_resident.position)
	var tile: Vector2i = _world.screen_to_grid(live)
	for _step in MAX_WANDER_STEPS:
		if tile.x >= 0 and _world.can_paint(tile.x, tile.y, "water"):
			break
		_world.presentation.tick(WANDER_STEP_SECONDS)
		live = _screen_of(_resident.position)
		tile = _world.screen_to_grid(live)
	check(tile.x >= 0, "the control tap point is over a real tile %s" % tile)

	var residents_before_removal: int = _world.total_residents()
	_site.residents.clear()
	_resident.free()
	_resident = null
	check_eq(_world.total_residents(), residents_before_removal - 1,
		"the tracked resident is removed from the world (%d -> %d)"
			% [residents_before_removal, _world.total_residents()])
	check(_world.resident_record_at(live).is_empty(),
		"...and the live point now hits nobody either — the query follows the DATA, not a cache")

	_hud.set_mode(GameHud.Mode.TERRAFORM)
	_hud.select_palette_option("water")
	var expected_paint: bool = _world.can_paint(tile.x, tile.y, "water")
	check(expected_paint, "a paint at the control point would succeed")
	check_eq(_router.handle_tap(live), TapRouter.RESULT_PAINTED,
		"CONTROL: with the animal gone, the very same live tap paints")
	check_eq(_world.get_tile_terrain(tile.x, tile.y), "water",
		"CONTROL: ...and the tile converted — the animal really was what had blocked it")


# --- helpers ---------------------------------------------------------------------------------------

## FOCUS FIXTURE (D-41): centres the pan/zoom camera on the home site at a zoom
## wide enough to keep the whole wander area (waypoint radius, → D-29/tier1-status
## row 6) in frame for the suite's whole run, replacing the old "park the Player
## and look_at()" fixture — the new camera has a real zoom continuum, so "wide
## enough to see the wander area" is a zoom level, not a standoff distance.
func _aim_camera_at_habitat(site_tile: Vector2i) -> void:
	var focus: Vector3 = _world.grid_to_world(site_tile.x, site_tile.y)
	var rig := _camera as CameraRig
	rig.set_focus(focus)
	rig.set_zoom_tiles(CameraRig.ZOOM_DEFAULT_TILES)


## The screen point a tap has to land on to hit a resident standing at `world_position` — the
## same body-centre anchor `ResidentPicker` projects.
func _screen_of(world_position: Vector3) -> Vector2:
	return _camera.unproject_position(
		world_position + Vector3(0.0, ResidentPicker.BODY_CENTRE_HEIGHT, 0.0)
	)


## `ResidentPicker`'s own radius rule, in pixels, at a given world anchor.
func _tap_radius(anchor: Vector3) -> float:
	var here: Vector2 = _camera.unproject_position(anchor)
	var east: Vector2 = _camera.unproject_position(anchor + Vector3(1.0, 0.0, 0.0))
	return maxf(
		ResidentPicker.MIN_TAP_RADIUS_PIXELS,
		here.distance_to(east) * ResidentPicker.TAP_RADIUS_TILE_FRACTION
	)


## Walks the resident until its live screen point is further from the arrival point than one
## whole tap radius — a GEOMETRIC criterion, evaluated fresh, so the result cannot be an
## artefact of how long the suite happened to run. Returns the number of steps taken, or 0.
func _walk_until_clear_of_the_ghost() -> int:
	for step in MAX_WANDER_STEPS:
		if _screen_of(_resident.position).distance_to(_arrival_screen) > _tap_radius(_resident.position):
			return step + 1
		_world.presentation.tick(WANDER_STEP_SECONDS)
	return 0


## Walks until the resident is mid-WALK *and* clear of its ghost, then returns its live screen
## point. Both conditions are re-checked here rather than assumed from an earlier call.
func _step_to_a_walking_tap() -> Vector2:
	for _step in MAX_WANDER_STEPS:
		_world.presentation.tick(WANDER_STEP_SECONDS)
		if _roamer.state_name() != "Walk":
			continue
		var live: Vector2 = _screen_of(_resident.position)
		if live.distance_to(_arrival_screen) > _tap_radius(_resident.position):
			return live
	check(false, "the resident reached a walking, ghost-clear position within the step cap")
	return _screen_of(_resident.position)


## As above, and additionally on ground a House could actually be placed on — so the Build
## assertion's "the tap WOULD have succeeded" is true rather than hopeful.
func _step_to_a_walking_tap_on_buildable_ground() -> Vector2:
	for _step in MAX_WANDER_STEPS:
		_world.presentation.tick(WANDER_STEP_SECONDS)
		if _roamer.state_name() != "Walk":
			continue
		var live: Vector2 = _screen_of(_resident.position)
		if live.distance_to(_arrival_screen) <= _tap_radius(_resident.position):
			continue
		var tile: Vector2i = _world.screen_to_grid(live)
		if tile.x >= 0 and _world.can_place(tile.x, tile.y, "house"):
			return live
	check(false, "the resident reached a walking, ghost-clear, buildable position within the cap")
	return _screen_of(_resident.position)
