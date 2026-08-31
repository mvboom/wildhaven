class_name WorldRoot
extends Node3D
## The simulation spine's single public surface — the root node of `scenes/Main.tscn`.
##
## Everything the UI dispatch (rows 2, 7, 11, 12) needs is on this class. Nothing else in
## `project/scripts/world/`, `project/scripts/economy/` or `project/scripts/simulation/`
## needs to be reached into, and none of it should be: the wiring between the four
## subsystems is this file's business, and the causal chain
##
##   player edit -> tile changes -> neighbourhood dirty -> capacity re-evaluated
##                -> arrival enqueued -> delay -> re-check -> resident moves in
##
## runs entirely below this line.
##
## PUBLIC API (stable; the UI dispatch builds against exactly this):
##   paint_tile(x, z, terrain_id) -> bool
##   place_building(x, z, placeable_id) -> bool
##   remove_at(x, z) -> bool                           <- the third edit mode; see below
##   can_remove(x, z) -> bool
##   refund_preview(x, z) -> int
##   get_tile_terrain(x, z) -> String
##   get_wood() -> int
##   screen_to_grid(screen_position) -> Vector2i
##   resident_at(screen_position) -> Node3D            <- LIVE positions; residents roam
##   resident_record_at(screen_position) -> Dictionary
##   resident_species_id(resident) -> String
##   resident_home_tile(resident) -> Vector2i
##   total_residents() -> int / population_of(species_id) -> int    <- row 11's counters
##   resident_species_ids() / species_hosted_ids() / species_hosted_count()  <- row 11
##   signals: wood_changed(new_amount), tile_changed(x, z),
##            resident_arrived(species_id, world_position),
##            displacement_warned(warning),
##            resident_relocated(species_id, from_tile, to_tile, world_position),
##            resident_departed(species_id, home_tile, individuals, world_position),
##            mist_revealed(new_tiles)                        <- row 13
## plus the read-only helpers below (palettes, costs, eligibility) so no caller has to
## reach past this node to build a palette or a soft cue.
##
## **THE THREE EDIT ENTRY POINTS ARE ONE SHAPE.** `paint_tile`, `place_building` and
## `remove_at` each apply the edit immediately, mark the neighbourhood dirty immediately, and
## then hand the same tile to `GentleDisplacement.on_edit()`. Nothing about which mode the
## player was in survives past that call — gdd.md requires the displacement warning to be
## **mode-agnostic**, and this is where that is made true.

## The Wood balance changed. Read-only indicator, never a goal (Pillar 1) — the HUD must
## not flash it, and nothing may gate on its value.
signal wood_changed(new_amount: int)

## A tile's terrain or building occupancy changed. Grid coordinates, not world position.
signal tile_changed(x: int, z: int)

## A resident actually moved in. **This is what fires the fact card** (row 7). The position
## is the home site's world position, which is where the animal is standing.
signal resident_arrived(species_id: String, world_position: Vector3)

## GENTLE DISPLACEMENT (row 10) — re-emitted from `GentleDisplacement` so the UI never reaches
## past this node. Payload shapes are documented on that class, which is ground truth for them.
##
## **One warning per settled gesture, summarising every affected home.** The UI renders exactly
## one dialogue from it, carrying the Read-Aloud 🔊 slice (`warning["read_aloud"]` is always
## true at this row).
##
## **IT IS DISCLOSURE, NOT DETERRENCE.** There is deliberately no confirm/cancel channel back
## into the simulation, and no method here to accept or reject a displacement: gdd.md rejects
## blocking the build outright (it is a fail state) and calls the warning "disclosure, not
## deterrence ... no plea, no judgment, no residue afterward". The player's undo path is the
## ordinary one every other edit has — `remove_at()`, or painting it back — and it works
## because the grace window has not closed yet at the moment the warning is read.
signal displacement_warned(warning: Dictionary)

## A home actually moved. Fires after `displacement_warned`, once per relocated home.
signal resident_relocated(
	species_id: String, from_tile: Vector2i, to_tile: Vector2i, world_position: Vector3
)

## Residents actually left. Fires after `displacement_warned`, once per affected home.
## Species Hosted and the Field Guide entry are permanent and are **not** affected — see
## `HomeSiteRegistry.species_hosted_ids()`.
signal resident_departed(
	species_id: String, home_tile: Vector2i, individuals: int, world_position: Vector3
)

## TIER 1 ROW 13 (MIST). The world just grew — re-emitted from `WorldGrid.grown` so the UI/audio
## layer never reaches past this node, matching every other signal here. This is the row's
## "chime plays" hook: no audio asset is wired to it yet (row 14, the audio slice, has not
## landed), but the event a chime would attach to already fires at exactly the right moment —
## once, synchronously, right after the edit that triggered the reveal.
signal mist_revealed(new_tiles: Array[Vector2i])


## THE SAVE-DIMENSION BOUND (Tier 1 row 1). A grid size read out of a file is untrusted input:
## `WorldSnapshot.can_apply()` validates only `save_version`, so nothing else stands between a
## corrupt or hand-edited `"width"` and three arrays allocated at `width * depth`.
##
## **WHY A FALLBACK AND NOT A CLAMP.** A `width: 0` file used to produce a perfectly normal
## 36x36 world, because `_ready()` built unconditionally and `apply()` simply refused the
## mismatch. Sizing the grid from the file made that graceful degradation a broken one — the
## player landed in a 1x1 world while `push_error` told them "the world is the default one".
## An out-of-range dimension therefore falls back to the preset's, so the world the player
## actually gets is the one the error message describes.
##
## DECIDED 2026-08-09 (-> D-35; the cap decided together with row 13's identical number, D-38,
## "so the two never drift apart" — see `mist_reveal.gd`). Open Question **#18** ("start size
## (~36x36) and cap (~128x128)"), transcribed from gdd.md -> World structure: "starting ~36x36
## tiles and growing to a hard cap of ~128x128 (a performance ceiling; both tunable)". The
## floor is 1 because a 0- or negative-width world has no tiles to stand on;
## `WorldGrid.build()` already clamps to 1, which is exactly the silent 1x1 world this bound
## exists to make impossible.
const MIN_SAVED_WORLD_TILES: int = 1
const MAX_SAVED_WORLD_TILES: int = 128


static var _instance: WorldRoot = null

var grid: WorldGrid = null
var navigation: WorldNavigation = null
var view: TerrainView = null
var wood: WoodLedger = null
var buildings: BuildingPlacement = null
var simulation: HabitatSimulation = null
var roster: SpeciesRoster = null
var registry: HomeSiteRegistry = null
var presentation: ResidentPresentation = null
var displacement: GentleDisplacement = null
var removals: RemovalLedger = null
var autosave: Autosave = null

## Player-chosen default style per picker category ("forest", "wild_grass", "house",
## "farm_building"), saved per-world. A category with no entry here — or whose stored
## value no longer resolves against the category's current catalog — reads through
## get_style_default() as that category's first catalog entry, never a crash. See
## get_style_default()'s own doc comment for the full contract.
var style_defaults: Dictionary = {}

## SAVE IDENTITY (Tier 1 row 1). Set from `GameSession` at `_ready()`, and read by `Autosave`
## every time it writes. `save_path` empty means this world has no file — which happens only in
## tests and in a scene run directly from the editor, and `Autosave` declines to write rather
## than inventing a filename.
var world_name: String = "Wildhaven"
var save_path: String = ""
var preset_id: String = ""
var world_seed: int = 0

## TIER 1 ROW 12. True only when `GameSession`'s intent was `"new"` — gdd.md's first-time
## nudge is scoped to "every brand-new save", and neither a loaded save nor the `"none"` path
## (a test, or F6 in the editor) is one. Set once, in `_ready()`, from the same `intent` the
## save-identity fields above already read; never reassigned afterward.
var is_new_world: bool = false

var _residents_root: Node3D = null
var _props_root: Node3D = null


## The live world, or null outside a running world scene. Lets the UI reach the API without
## a hardcoded node path into a scene tree it does not own.
static func instance() -> WorldRoot:
	return _instance


func _enter_tree() -> void:
	_instance = self


func _exit_tree() -> void:
	if _instance == self:
		_instance = null
	if navigation != null:
		navigation.free_navigation()
		navigation = null


func _ready() -> void:
	# TIER 1 ROW 1. The intent set by the menu, or "none" when this scene was opened directly
	# (a test, or F6 in the editor) — in which case a default world is built exactly as before.
	#
	# **THE "none" PATH MUST STAY BYTE-IDENTICAL TO THE PRE-SAVE BEHAVIOUR.** Every one of the
	# project's suites instantiates `Main.tscn` and comes through here, so a difference in the
	# default world is a difference in all of them. `saved` stays empty, `preset` resolves to
	# `meadow_start` (36x36, `wild_grass`), and the `grid.build()` below therefore receives the
	# same 36x36 the no-argument call used to default to.
	var intent: Dictionary = GameSession.consume()
	var saved: Dictionary = {}
	var preset: WorldPreset = null

	match intent["mode"]:
		"new":
			is_new_world = true
			preset = intent["preset"] as WorldPreset
			world_name = intent["name"] as String
			save_path = intent["path"] as String
			# GENERATED BY THE MENU (`new_game_screen.gd`), never here. `_ready()` runs for
			# every suite in this project and for the `"none"` path, so drawing a random seed
			# at this line would make world construction non-deterministic in all of them. The
			# `"none"` path does not reach this branch, and keeps seed 0.
			world_seed = int(intent["seed"])
		"load":
			# **`save_path` IS ASSIGNED ONLY ON THE SUCCESS PATH**, and that ordering is the whole
			# guarantee. `Autosave.attach()` writes the moment it attaches, so a `save_path`
			# pointing at a file this build just refused would stamp a fresh empty world over the
			# player's world within the same `_ready()` — losing more than a delete would, and
			# breaking the design's own promise that a refused file is left for a parent to open
			# and read. Empty `save_path` makes `Autosave.request()` decline through its existing
			# guard, which is the same state a scene opened directly in the editor is in.
			var requested_path: String = intent["path"] as String
			saved = SaveStore.read(requested_path)
			if saved.is_empty() or not WorldSnapshot.can_apply(saved):
				push_error(
					("WorldRoot: %s is unreadable or was written by a newer build; "
					+ "starting an UNSAVED default world instead. The file is untouched — "
					+ "nothing will be written over it.") % requested_path
				)
				saved = {}
			else:
				save_path = requested_path
				# TYPE BEFORE CAST — see `WorldSnapshot.text_or()`. This read happens BEFORE
				# `migrate()` is reached, so it is the first thing a hand-edited file touches
				# here: a bare `as String` on `"name": 42` aborted `_ready()` outright, leaving
				# grid, simulation and autosave all null and the scene unplayable. A non-String
				# name keeps the default rather than taking the world down.
				world_name = WorldSnapshot.text_or(saved.get("name", world_name), world_name)
	if preset == null:
		preset = WorldPreset.default_preset()
	if preset != null:
		preset_id = preset.id
	# THE FILE WINS over the default preset for identity, so a re-save does not quietly
	# re-stamp a loaded world with today's default preset id or drop the seed row 13's mist
	# reveal is a deterministic function of. `capture()` writes both; nothing else read them
	# back, which would have made the round trip lossy the second time round.
	#
	# MIGRATED FIRST, and that is not cosmetic: a v1 file carries `seed: 0` for every world ever
	# saved by that build, and `WorldSnapshot.migrate()` is what turns it into a stable per-world
	# value. Reading the raw file here would leave the running world on 0 while the migrated
	# dictionary `apply()` uses says otherwise. `migrate()` is idempotent, so applying it twice
	# is free.
	if not saved.is_empty():
		saved = WorldSnapshot.migrate(saved)
		# `preset_id` is guarded for the same reason `name` above is, and it is the same one-line
		# shape: a non-String here aborted `_ready()` with an unplayable scene.
		preset_id = WorldSnapshot.text_or(saved.get("preset_id", preset_id), preset_id)
		# THE BARE `int()` IS SAFE ONLY BECAUSE `migrate()` RAN ON THE LINE ABOVE. It repairs a
		# non-numeric `seed` at ANY save_version — see its body for why the repair lives there
		# rather than as a guard at this cast — so by here the field is always a number. Moving
		# this read above the migrate call, or dropping that repair, re-opens "Nonexistent 'int'
		# constructor" on a hand-edited `"seed": [1, 2]`, which aborts `_ready()` outright.
		world_seed = int(saved.get("seed", world_seed))

	roster = SpeciesRoster.new()
	registry = HomeSiteRegistry.new()

	grid = WorldGrid.new()
	grid.name = "WorldGrid"
	add_child(grid)
	var w: int = _dimension_from_save(saved, "width",
		preset.width if preset != null else WorldGrid.DEFAULT_WIDTH)
	var d: int = _dimension_from_save(saved, "depth",
		preset.depth if preset != null else WorldGrid.DEFAULT_DEPTH)
	grid.build(TerrainDefinition.load_all(), w, d)
	grid.tile_changed.connect(_on_tile_changed)
	grid.grown.connect(_on_grid_grown)  # Tier 1 row 13 (mist)

	navigation = WorldNavigation.new()
	navigation.rebuild_from_grid(grid)

	view = TerrainView.new()
	view.name = "TerrainView"
	add_child(view)
	# `self` is safe here despite being mid-`_ready()`: `TerrainChunkLod.attach()` below
	# synchronously refreshes every existing tile (forest/wild_grass resolution needs only
	# `grid`, already built above), and no building visual is refreshed until a real edit
	# or a save-restore later in this function — both well after `buildings` exists. See
	# `resolve_style_scene()`'s header on `WorldRoot` for the resolution this threads into.
	view.attach(grid, self)

	wood = WoodLedger.new()
	wood.name = "WoodLedger"
	add_child(wood)
	wood.attach(grid)
	wood.wood_changed.connect(func(amount: int) -> void: wood_changed.emit(amount))

	buildings = BuildingPlacement.new()
	buildings.name = "BuildingPlacement"
	add_child(buildings)
	buildings.attach(grid, wood)

	_residents_root = Node3D.new()
	_residents_root.name = "Residents"
	add_child(_residents_root)

	# Home props (dens/burrows/nests) are decoration with no tiles and no collision, so they
	# hang off their own visual root — never off the tile grid, and never off a resident, since
	# the resident walks away from its den within seconds of arriving.
	_props_root = Node3D.new()
	_props_root.name = "HomeProps"
	add_child(_props_root)

	# The view layer for residents: waypoint wander + the home prop. Its own node with its own
	# `_process`, so nothing it does can touch the habitat queue.
	presentation = ResidentPresentation.new()
	presentation.name = "ResidentPresentation"
	add_child(presentation)
	# `roster` is what lets `present()` resolve a new resident's `avoids` list (row 9).
	presentation.attach(grid, _props_root, 0, roster, navigation)

	simulation = HabitatSimulation.new()
	simulation.name = "HabitatSimulation"
	add_child(simulation)
	simulation.attach(grid, roster, registry, ArrivalQueue.new(), _residents_root, presentation)
	simulation.resident_arrived.connect(
		func(species_id: String, world_position: Vector3) -> void:
			resident_arrived.emit(species_id, world_position)
			# D-29 -> tier1-status.md row 6, "extend the arrival check": landing this
			# arrival already rebuilt the whole tile-exclusivity map (see
			# `HomeSiteRegistry.register()`/`claim()`), which can drop a NEIGHBOURING
			# home site below its own population. `displacement` is read here rather
			# than captured, so it resolves even though this connection is made before
			# the node below exists.
			if displacement != null and grid != null:
				displacement.on_arrival(grid.world_to_tile(world_position), species_id)
	)

	# Row 3's removal/refund receipts. Attached before the edit API can be called, because an
	# edit with nowhere to leave a receipt is an edit the player cannot take back.
	removals = RemovalLedger.new()
	removals.name = "RemovalLedger"
	add_child(removals)

	# Row 10. Its own node with its own `_process`, for the same reason `ResidentPresentation`
	# has one: displacement consumes the four habitat triggers and adds none, so it must not be
	# able to grow into a fifth. `HabitatSimulation` keeps exactly four triggers and exactly two
	# signals, and `test_event_driven_simulation.gd` asserts both.
	displacement = GentleDisplacement.new()
	displacement.name = "GentleDisplacement"
	add_child(displacement)
	displacement.attach(grid, roster, registry, simulation, presentation)
	displacement.displacement_warned.connect(
		func(warning: Dictionary) -> void: displacement_warned.emit(warning)
	)
	displacement.resident_relocated.connect(
		func(species_id: String, from_tile: Vector2i, to_tile: Vector2i, at: Vector3) -> void:
			resident_relocated.emit(species_id, from_tile, to_tile, at)
	)
	displacement.resident_departed.connect(
		func(species_id: String, home_tile: Vector2i, individuals: int, at: Vector3) -> void:
			resident_departed.emit(species_id, home_tile, individuals, at)
	)

	# TIER 1 ROW 1 — the restore, deliberately placed after every subsystem exists and before
	# anything has ticked. `WorldSnapshot.apply()` finishes by marking all neighbourhoods dirty,
	# which re-derives the arrival queue the save does not carry.
	#
	# ORDERING, MEASURED (2026-08-01, `test_save_round_trip.gd`). The design doc wanted the
	# terrain replay to run BEFORE `simulation.attach()` so that ~1,300 `set_terrain` calls could
	# not dirty the queue ~1,300 times. They cannot anyway: `grid.tile_changed` is connected to
	# `_on_tile_changed`, which only re-emits — nothing in the terrain path touches
	# `HabitatSimulation`, whose only entry points are its four triggers. The queue after a
	# restore therefore holds exactly one entry per restored home site (`mark_all_dirty()` ->
	# `_mark_all_sites_dirty()`), which the round-trip suite asserts as an equality so the bound
	# cannot silently regress into a per-tile one.
	if not saved.is_empty():
		if not WorldSnapshot.apply(self, saved):
			# THE SECOND HALF OF THE SAME GUARANTEE (see the `"load"` branch above). `can_apply()`
			# passed, so `save_path` was assigned — and it must be given back before `Autosave`
			# attaches below, or the default world this refusal just built gets written over the
			# file it refused. Dropping the path costs the player nothing they still have: this
			# world is not theirs, and theirs is still on disk exactly as they left it.
			push_error(
				("WorldRoot: %s could not be applied; this is an UNSAVED default world and the "
				+ "file is untouched — nothing will be written over it.") % save_path
			)
			save_path = ""

	autosave = Autosave.new()
	autosave.name = "Autosave"
	add_child(autosave)
	autosave.attach(self)

	print("[wildhaven] World ready: %dx%d tiles, %d terrains, %d species, %d Wood." % [
		grid.width, grid.depth, grid.terrain_definitions().size(), roster.size(), wood.get_wood()
	])


## One grid dimension from an untrusted save, or `fallback` when the file does not carry it or
## carries something outside `MIN_SAVED_WORLD_TILES..MAX_SAVED_WORLD_TILES`.
##
## Returning the fallback rather than clamping is deliberate: a clamped 200 would give the
## player a 128x128 world that `WorldSnapshot.apply()` then refuses (its own dimension check
## compares against the file), leaving them in an empty world of a size they never chose. The
## fallback keeps the refusal and the world in agreement.
func _dimension_from_save(saved: Dictionary, key: String, fallback: int) -> int:
	if not saved.has(key):
		return fallback
	# **TYPE BEFORE RANGE.** Saves are hand-editable by design, so a JSON object or a string is
	# anticipated input here, not an impossibility — and `int({"oops": 1})` is not a 0, it is a
	# runtime "Nonexistent 'int' constructor" error that aborts this function mid-way and hands
	# `_ready()` a null. The bound below would then never run at all, which is how a non-numeric
	# value walked *around* `MIN_SAVED_WORLD_TILES` into a 1x36 world where `paint_tile()` fails.
	# The same guard sits on `WorldSnapshot.apply()`'s dimension read — see `is_number()` there.
	if not WorldSnapshot.is_number(saved[key]):
		push_error(
			"WorldRoot: save names %s as a non-numeric value; building the default %d instead."
			% [key, fallback]
		)
		return fallback
	var value: int = int(saved[key])
	if value < MIN_SAVED_WORLD_TILES or value > MAX_SAVED_WORLD_TILES:
		push_error(
			"WorldRoot: save names %s %d, outside %d..%d; building the default %d instead."
			% [key, value, MIN_SAVED_WORLD_TILES, MAX_SAVED_WORLD_TILES, fallback]
		)
		return fallback
	return value


func _on_tile_changed(x: int, z: int) -> void:
	tile_changed.emit(x, z)


func _on_grid_grown(new_tiles: Array[Vector2i]) -> void:
	if navigation != null:
		navigation.mark_dirty()
	mist_revealed.emit(new_tiles)


## TIER 1 ROW 13 (MIST, D-38). Called at the end of every edit entry point below — "the three
## edit entry points are one shape" applies to this trigger exactly the way it already applies
## to `GentleDisplacement.on_edit()`. Grows the grid by `MistReveal.REVEAL_BAND_TILES` on
## whichever high edge (east / north) `tile` landed within `MistReveal.REVEAL_PROXIMITY_TILES`
## of; `WorldGrid.grow()` clamps to the cap and no-ops once the grid is already there, so
## nothing here needs its own cap check. See `WorldGrid.grow()`'s header for the disclosed
## append-only trade-off (the low edges, x == 0 / z == 0, are a permanent boundary, not mist).
##
## **NOT a qualification trigger (D-22).** This never calls `simulation.on_terraform()` or
## `on_building_changed()` — the caller already did that for `tile` itself, and `grid.grow()`
## itself never touches `HabitatSimulation` either (see its own header).
func _maybe_unfurl_mist(tile: Vector2i) -> void:
	if grid == null:
		return
	var target_width: int = grid.width
	var target_depth: int = grid.depth
	if tile.x >= grid.width - MistReveal.REVEAL_PROXIMITY_TILES:
		target_width += MistReveal.REVEAL_BAND_TILES
	if tile.y >= grid.depth - MistReveal.REVEAL_PROXIMITY_TILES:
		target_depth += MistReveal.REVEAL_BAND_TILES
	if target_width != grid.width or target_depth != grid.depth:
		grid.grow(target_width, target_depth, world_seed)


# --- Public API: edits ------------------------------------------------------------------

## Paints one tile. Returns false — silently, changing nothing — when the tile is out of
## bounds, already that terrain, occupied by a building, or unaffordable.
##
## **An edit the player cannot afford simply does not happen**: no error state, no message,
## no penalty (Pillar 1). Painting Forest is always free and always available, which is the
## recovery guarantee `WorldGrid` asserts at build time.
func paint_tile(x: int, z: int, terrain_id: String) -> bool:
	if grid == null or not grid.in_bounds(x, z):
		return false
	if grid.is_occupied(x, z):
		return false
	var def: TerrainDefinition = grid.terrain_definition(terrain_id)
	if def == null:
		return false
	var previous: String = grid.get_terrain_id(x, z)
	if previous == TerrainDefinition.normalize_id(def.id):
		return false
	if not wood.spend(def.cost):
		return false
	if not grid.set_terrain(x, z, def.id):
		return false
	var tile := Vector2i(x, z)
	if removals != null:
		removals.record_paint(tile, previous, def.cost)
	simulation.on_terraform(tile)  # trigger 1
	if navigation != null:
		navigation.mark_dirty()
	if displacement != null:
		displacement.on_edit(tile)  # arms the settlement window; arithmetic already ran
	_maybe_unfurl_mist(tile)  # Tier 1 row 13
	return true


## Places a building. Returns false — silently — when any footprint tile is ineligible or
## the cost is unaffordable. Ineligible tiles simply do not accept the placement
## (buildings.md: "a soft cue, never an error").
##
## A placed building suppresses its footprint tiles' terrain tags and emits its own
## `emitted_tags` instead; and **a House is a home site**, registered here so villagers can
## settle it.
##
## WILD GRASS -> GRASS, IMPLICIT AND FREE. No `PlaceableDefinition.allowed_terrain` names
## `"wild_grass"` — a building must never visually sit on unconverted wild land — but a
## building that DOES accept Grass may still land on a footprint that currently has Wild
## grass in it: `_convert_wild_grass_footprint()` below converts exactly those tiles to Grass
## first, through `paint_tile()` (the same pipeline a player's own Terraform tap would use),
## before `buildings.place()` runs. Both terrains cost 0, so the conversion is free and
## silent — no wood spent, no extra confirmation. Routing through `paint_tile()` rather than a
## raw `grid.set_terrain()` is what keeps `remove_at()`'s removal-ledger revert correct with no
## new state to track: a demolished building's footprint goes back to Grass (what it was
## actually painted to, moments before), not back to Wild grass.
func place_building(x: int, z: int, placeable_id: String) -> bool:
	if buildings == null:
		return false
	var origin := Vector2i(x, z)
	_convert_wild_grass_footprint(origin, placeable_id)
	var cost: int = buildings.cost_of(placeable_id)
	if not buildings.place(x, z, placeable_id):
		return false
	if removals != null:
		removals.record_placement(origin, placeable_id, cost)
	simulation.on_building_changed(origin)  # trigger 2
	if navigation != null:
		navigation.mark_dirty()
	if displacement != null:
		displacement.on_edit(origin)
	_maybe_unfurl_mist(origin)  # Tier 1 row 13
	return true


## The wild-grass-conversion half of `place_building()`, split out so the public method keeps
## the same "check, place, wire up triggers" shape as the other two edit entry points.
##
## VALIDATES BEFORE MUTATING: eligibility is checked with the hypothetical conversion already
## applied (a Wild-grass tile counts as eligible only when `allowed` also accepts Grass), and
## nothing is painted unless the WHOLE footprint would pass AND the building itself is
## affordable right now. A footprint that would still be refused for some other reason (out of
## bounds, occupied, a tile on neither Grass nor Wild grass, e.g. Rock or Water, or simply not
## enough Wood for the building) is left untouched — `buildings.place()`'s own checks then
## correctly refuse it, exactly as before this method existed, and a failed placement attempt
## cannot leave a wild-grass-converted tile (or a stray `tile_changed`) as a side effect. The
## affordability half matters here specifically: painting is itself an edit that would otherwise
## fire `tile_changed` even though the building placement as a whole is about to fail, which
## `test_economy_rules.gd`'s "an unaffordable edit fires no signal at all" assertion catches.
func _convert_wild_grass_footprint(origin: Vector2i, placeable_id: String) -> void:
	if grid == null or buildings == null or wood == null:
		return
	var def: PlaceableDefinition = buildings.definition(placeable_id)
	if def == null:
		return
	if not wood.can_afford(buildings.cost_of(placeable_id)):
		return
	var allowed: Array[String] = def.normalized_allowed_terrain()
	if not allowed.has("grass"):
		return
	var footprint: Array[Vector2i] = WorldGrid.footprint_tiles(origin, def)
	for tile: Vector2i in footprint:
		if not grid.tile_in_bounds(tile):
			return
		if grid.is_occupied(tile.x, tile.y):
			return
		var terrain_id: String = grid.get_terrain_id(tile.x, tile.y)
		if terrain_id == TerrainDefinition.WILD_GRASS_ID:
			continue
		if not allowed.has(terrain_id):
			return
	for tile: Vector2i in footprint:
		if grid.get_terrain_id(tile.x, tile.y) == TerrainDefinition.WILD_GRASS_ID:
			paint_tile(tile.x, tile.y, "grass")


## REMOVAL — the third edit mode, and the one Pillar 1's word *reversible* rests on.
## gdd.md -> Removal / undo & refund policy; Open Question **#16**.
##
## **Uniform across Terraform reverts and Build removals**, which is why it is one method and
## not two: the player taps a tile and whatever they last did there comes undone.
##   * a building on the tile -> the building comes down (whole footprint), refunded by policy;
##   * otherwise               -> the tile goes back to the terrain it was painted over,
##                                refunded by policy.
## Refunds are 100% inside the grace window and `floor(cost x RECYCLE_FRACTION)` after it, in
## the resource originally spent. **Free natural terrain refunds nothing** — not as a rule
## here, but because its receipt records a cost of 0.
##
## Returns false — silently, changing nothing — when there is nothing to remove: no building,
## and no record of the player ever having painted this tile. **A tile in its original state is
## not an error to remove**, it is simply a tap that does nothing (Pillar 1).
##
## A removal is an edit like any other: it marks the neighbourhood dirty immediately and arms
## the settlement window. **Removing a House with a family in it is allowed** — that is exactly
## the case Gentle Displacement exists for, and refusing it would be a fail state.
func remove_at(x: int, z: int) -> bool:
	if grid == null or not grid.in_bounds(x, z):
		return false

	# Buildings first: on a footprint tile, "remove" means the building, never the ground.
	if grid.is_occupied(x, z):
		var origin: Vector2i = grid.get_building_origin(x, z)
		var receipt: Dictionary = {} if removals == null else removals.placement_receipt(origin)
		if not grid.clear_building(origin):
			return false
		if removals != null:
			wood.add(removals.refund_for(receipt))
			removals.forget_placement(origin)
		simulation.on_building_changed(origin)  # trigger 2
		if navigation != null:
			navigation.mark_dirty()
		if displacement != null:
			displacement.on_edit(origin)
		_maybe_unfurl_mist(origin)  # Tier 1 row 13
		return true

	var tile := Vector2i(x, z)
	var paint: Dictionary = {} if removals == null else removals.paint_receipt(tile)
	if paint.is_empty():
		return false
	if not grid.set_terrain(x, z, paint["previous_terrain_id"] as String):
		return false
	wood.add(removals.refund_for(paint))
	removals.forget_paint(tile)
	simulation.on_terraform(tile)  # trigger 1
	if navigation != null:
		navigation.mark_dirty()
	if displacement != null:
		displacement.on_edit(tile)
	_maybe_unfurl_mist(tile)  # Tier 1 row 13
	return true


## Would `remove_at()` do anything here? For soft cues and palette state only; `remove_at()`
## re-checks, so the two can never disagree.
func can_remove(x: int, z: int) -> bool:
	if grid == null or not grid.in_bounds(x, z) or removals == null:
		return false
	if grid.is_occupied(x, z):
		return true
	return removals.has_paint_receipt(Vector2i(x, z))


## What removing this tile would refund right now, in Wood. 0 is the ordinary answer for free
## natural terrain and is not a failure. Recomputed on read, so it counts down across the
## grace-window boundary exactly as the refund will.
func refund_preview(x: int, z: int) -> int:
	if grid == null or not grid.in_bounds(x, z) or removals == null:
		return 0
	if grid.is_occupied(x, z):
		return removals.refund_for(removals.placement_receipt(grid.get_building_origin(x, z)))
	return removals.refund_for(removals.paint_receipt(Vector2i(x, z)))


## Seconds left before this tile's neighbourhood settles, or -1.0 when nothing is pending for
## it. Read-only; nothing in the simulation consumes it. **Not a countdown to show a child** —
## it exists so a UI can decide whether to offer "undo" prominently, and Pillar 1 forbids
## presenting it as a timer.
func settlement_seconds_remaining(x: int, z: int) -> float:
	if displacement == null or registry == null:
		return -1.0
	var longest: float = -1.0
	for site: HomeSite in registry.sites_covering(Vector2i(x, z)):
		if site.population() <= 0:
			continue
		var left: float = displacement.window().remaining_for(
			GentleDisplacement.neighbourhood_key(site)
		)
		longest = maxf(longest, left)
	return longest


# --- Public API: reads ------------------------------------------------------------------

func get_tile_terrain(x: int, z: int) -> String:
	return "" if grid == null else grid.get_terrain_id(x, z)


func get_tile_tags(x: int, z: int) -> Array[String]:
	return [] if grid == null else grid.get_tile_tags(x, z)


func get_wood() -> int:
	return 0 if wood == null else wood.get_wood()


func grid_size() -> Vector2i:
	return Vector2i.ZERO if grid == null else Vector2i(grid.width, grid.depth)


func has_tile(x: int, z: int) -> bool:
	return grid != null and grid.in_bounds(x, z)


## The Terraform palette, straight from data — nothing hardcodes a terrain list.
func terrain_options() -> Array[TerrainDefinition]:
	return [] if grid == null else grid.terrain_definitions()


## The Build palette, straight from data.
func placeable_options() -> Array[PlaceableDefinition]:
	return [] if buildings == null else buildings.definitions()


## The validated, resolved style id for `category`. Never returns "" (unless the
## category genuinely has zero options, which none of the 4 picker categories can — each
## always has at least its own shipped/original entry) and never raises. Handles BOTH
## style-id "flavors" identically: a derived model_scenes filename-slug
## (forest/wild_grass/house) and a real PlaceableDefinition id (farm_building) — callers
## never need to know which.
func get_style_default(category: String) -> String:
	# `WorldSnapshot.text_or()`, not a bare `as String` cast: `style_defaults` round-trips
	# through hand-editable save JSON (Task 4), and a corrupted/hand-edited entry
	# (`null`, an int, a bool, an Array...) makes `Dictionary.get(k, "") as String` raise a
	# function-aborting "Invalid cast" SCRIPT ERROR — exactly the crash this function's own
	# doc comment promises never happens. `text_or()` treats anything non-String as absent,
	# which falls through to the normal stale-id degradation below.
	var candidate: String = WorldSnapshot.text_or(style_defaults.get(category, ""), "")
	var valid_ids: PackedStringArray = style_ids_for_category(category)
	if valid_ids.has(candidate):
		return candidate
	return valid_ids[0] if not valid_ids.is_empty() else ""


func set_style_default(category: String, style_id: String) -> void:
	style_defaults[category] = style_id


## Every valid style id for `category`, in the order a fresh save's "first entry" default
## should follow. Forest/Wild Grass/House: one id per model_scenes entry, derived from
## its scene's filename (see `_style_id_from_scene_path()`). Farm Building: every
## PlaceableDefinition.id whose hotbar_category == "farm_building", in placeable_options()
## order. Any other category (rock, water, cultivated_field, an animal id) returns an
## empty array — get_style_default() on a non-picker category correctly returns "" and
## callers outside this file never call it for one.
##
## PUBLIC (style-picker sub-project B2, Task 7): the popup needs to enumerate every valid
## style id for a category, which is exactly this function's own existing return shape —
## same pattern Task 5 used for `resolve_style_scene()` (expose a purpose-built method
## rather than a raw private primitive), applied here by simply dropping the leading
## underscore rather than adding a second wrapper that would just call this one.
func style_ids_for_category(category: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if category == "farm_building":
		for placeable: PlaceableDefinition in placeable_options():
			if placeable.hotbar_category == "farm_building":
				out.append(placeable.id)
		return out
	for scene: PackedScene in _model_scenes_for_category(category):
		out.append(_style_id_from_scene_path(scene))
	return out


## The raw `model_scenes` array behind `category` — "house" reads the House
## PlaceableDefinition's own `model_scenes`, "forest"/"wild_grass" read the matching
## TerrainDefinition's. Shared by `style_ids_for_category()` (id derivation) and
## `resolve_style_scene()` (id-to-scene lookup) so the two can never disagree about which
## scenes a category draws from. Empty for "farm_building" (its ids are
## PlaceableDefinition ids, not scene-derived — see `style_ids_for_category()`) and for
## any category outside the four picker ones.
func _model_scenes_for_category(category: String) -> Array[PackedScene]:
	if category == "house":
		for placeable: PlaceableDefinition in placeable_options():
			if placeable.id == "house":
				return placeable.model_scenes
		return []
	if category == "forest" or category == "wild_grass":
		var terrain: TerrainDefinition = grid.terrain_definition(category) if grid != null else null
		return terrain.model_scenes if terrain != null else []
	return []


## Resolves `category`'s player-chosen style default (`get_style_default()`) to the
## matching `PackedScene` from that category's own `model_scenes` list — the ONLY place
## outside this file that ever needs to reason about style-id-to-scene matching.
## `TerrainChunkLod` (forest/wild_grass tiles) and `TerrainView` (the House visual) call
## this instead of deriving ids themselves, which keeps `_style_id_from_scene_path()`
## private to this file — see this task's report for why that option was chosen over
## making it public.
##
## Returns `null` when `category` has no model_scenes at all (rock/water/
## cultivated_field, "farm_building" — resolved elsewhere, at placement time, by a later
## task — or any id outside the four picker categories) or — defensively, should be
## unreachable if `get_style_default()`'s own contract holds — when nothing matches.
## **Callers own their own fallback** (`pick_variant()` for terrain,
## `model_scenes[0]` for a building) exactly as they did before this feature existed, so a
## null here degrades to that pre-existing behaviour rather than to a missing visual.
func resolve_style_scene(category: String) -> PackedScene:
	var scenes: Array[PackedScene] = _model_scenes_for_category(category)
	if scenes.is_empty():
		return null
	var style_id: String = get_style_default(category)
	for scene: PackedScene in scenes:
		if _style_id_from_scene_path(scene) == style_id:
			return scene
	return null


## Derives a stable style id from a model_scenes entry's own resource path — the
## filename, snake_cased, extension stripped. "BirchTree.tscn" -> "birch_tree". No
## authored field anywhere carries this; it's computed fresh every call, which is
## deliberate (it self-heals if a scene is ever renamed on disk in a way that changes
## the derived id — the OLD id then simply degrades via get_style_default()'s normal
## stale-id fallback, rather than needing a migration).
##
## TRAP: a derived id is NOT always the same string as its asset directory name.
## `to_snake_case()` inserts an underscore before an embedded digit even mid-word, so
## "HouseFirstage1Level2.tscn" derives "house_firstage_1_level_2" — but the file actually
## lives in "assets/buildings/house_firstage_1_level2/" (no underscore before the trailing
## "2"). Never reconstruct a scene path from an id string; a caller that needs id -> scene
## must go through this same derivation, iterating a category's model_scenes and comparing
## each entry's own derived id against the target (see `style_ids_for_category()`).
func _style_id_from_scene_path(scene: PackedScene) -> String:
	if scene == null:
		return ""
	var path: String = scene.resource_path
	var filename: String = path.get_file().get_basename()
	return filename.to_snake_case()


func paint_cost(terrain_id: String) -> int:
	var def: TerrainDefinition = null if grid == null else grid.terrain_definition(terrain_id)
	return 0 if def == null else def.cost


func place_cost(placeable_id: String) -> int:
	return 0 if buildings == null else buildings.cost_of(placeable_id)


## Would this paint succeed right now? For soft cues and previews only — `paint_tile()`
## re-checks, so there is no window where the two can disagree.
func can_paint(x: int, z: int, terrain_id: String) -> bool:
	if grid == null or not grid.in_bounds(x, z) or grid.is_occupied(x, z):
		return false
	var def: TerrainDefinition = grid.terrain_definition(terrain_id)
	if def == null:
		return false
	if grid.get_terrain_id(x, z) == TerrainDefinition.normalize_id(def.id):
		return false
	return wood.can_afford(def.cost)


func can_place(x: int, z: int, placeable_id: String) -> bool:
	return buildings != null and buildings.can_place(x, z, placeable_id)


## Screen position -> grid coordinates, or `Vector2i(-1, -1)` on a miss.
##
## Exposed here so the UI never re-derives the camera/ray/collider chain — one
## implementation of "which tile did the player tap", in one place.
func screen_to_grid(screen_position: Vector2) -> Vector2i:
	return Vector2i(-1, -1) if view == null else view.screen_to_grid(screen_position)


## Distance from the camera to whatever the crosshair is over, or -1.0 on a miss. See
## `TerrainView.hit_distance()` — exposed here for the same reason `screen_to_grid()` is:
## the UI never re-derives the camera/ray/collider chain.
##
## **NOT WHAT INSPECT USES FOR A PICKED RESIDENT** (2026-08-09 final review, Finding #1). This
## is a terrain RAYCAST — it travels straight past a resident (`ResidentPicker` hit-tests in
## screen space against a point raised to `ResidentPicker.BODY_CENTRE_HEIGHT`, with no collider
## of its own there) to whatever ground is behind it, which reads as roughly double the
## resident's real distance or worse. `TapRouter.handle_tap()` / `_resolve_crosshair_state()`
## use `distance_to()` below against the resident's own `world_position` instead, whenever
## `resident_record_at()` finds one; this stays the measure for bare land and for Terraform/
## Build, where there is no resident position to prefer.
func crosshair_distance(screen_position: Vector2) -> float:
	return -1.0 if view == null else view.hit_distance(screen_position)


## Straight-line distance from the camera to an arbitrary world position, or -1.0 when there is
## no live camera. Unlike `crosshair_distance()`, this raycasts nothing — it measures a position
## the caller already has (e.g. a resident's own `world_position` from `resident_record_at()`),
## which is what Inspect's range check needs for a picked resident (see that method's note).
func distance_to(world_position: Vector3) -> float:
	if not is_inside_tree():
		return -1.0
	var camera: Camera3D = get_viewport().get_camera_3d()
	return -1.0 if camera == null else camera.global_position.distance_to(world_position)


func grid_to_world(x: int, z: int) -> Vector3:
	return Vector3.ZERO if grid == null else grid.tile_to_world(x, z)


# --- Public API: residents (the priority rule's other half) ------------------------------
# gdd.md -> Inspect Mode: "an animal standing on a tappable tile always wins the tap."
# Resolve the resident FIRST, and only fall back to `screen_to_grid()` when this returns null.
#
# **These resolve against live positions.** Residents roam, so anything that hit-tests a
# position captured at arrival time (`resident_arrived`'s payload) is wrong the moment the
# animal takes its first step.

## The resident under a screen position, or null. Uses the viewport's current 3D camera, the
## same way `screen_to_grid()` does, so no caller has to hold one.
func resident_at(screen_position: Vector2) -> Node3D:
	var record: Dictionary = resident_record_at(screen_position)
	return null if record.is_empty() else record["node"] as Node3D


## `resident_at()` plus everything a tap needs in one read, so the UI does not pay for three
## lookups: `{ "node": Node3D, "species_id": String, "home_tile": Vector2i,
## "world_position": Vector3 }`, or `{}` on a miss.
##
## `home_tile` is what the resident inspect readout's capacity line is computed from —
## `capacity_at(home_tile.x, home_tile.y, species_id)` and `population_at(...)`.
func resident_record_at(screen_position: Vector2) -> Dictionary:
	if registry == null or not is_inside_tree():
		return {}
	return ResidentPicker.pick(registry, screen_position, get_viewport().get_camera_3d())


## The species id of a resident node, or `""` when the node is not a resident.
func resident_species_id(resident: Node) -> String:
	var site: HomeSite = ResidentPicker.site_of(registry, resident)
	return "" if site == null else site.species_id


## The home site tile of a resident node, or `Vector2i(-1, -1)`.
func resident_home_tile(resident: Node) -> Vector2i:
	var site: HomeSite = ResidentPicker.site_of(registry, resident)
	return Vector2i(-1, -1) if site == null else site.position


# --- Public API: simulation readouts (row 11's counters read these) ----------------------

## `capacity(h, S)` at an arbitrary tile for a species id. 0 means unsuitable, and that is a
## real answer, not a failure.
##
## This is the same read the arrival predicate uses — one function, so the number a readout
## shows can never disagree with the number the simulation acted on.
func capacity_at(x: int, z: int, species_id: String) -> int:
	if roster == null or simulation == null:
		return 0
	return simulation.capacity_at(Vector2i(x, z), roster.by_id(species_id))


func population_at(x: int, z: int, species_id: String) -> int:
	if roster == null or simulation == null:
		return 0
	return simulation.population_at(Vector2i(x, z), roster.by_id(species_id))


func total_residents() -> int:
	return 0 if registry == null else registry.total_residents()


## Individuals of one species, across every home site — Village Population reads this with
## `species_id = "human"` rather than `total_residents()`, which would sum wildlife in too.
func population_of(species_id: String) -> int:
	return 0 if registry == null else registry.population_of(species_id)


func resident_species_ids() -> Array[String]:
	return [] if registry == null else registry.resident_species_ids()


## **Species Hosted — all-time, and it never decreases** (gdd.md -> Economy; Gentle
## Displacement: "Species Hosted and the Field Guide entry stay permanent"). A departure
## removes residents and never removes a record, which is enforced by there being no path in
## `HomeSiteRegistry` that erases one. The counter and the Field Guide entry that read this are
## Tier 1 row 11 (ui-engineer) and are not built; the data they need is.
func species_hosted_ids() -> Array[String]:
	return [] if registry == null else registry.species_hosted_ids()


func species_hosted_count() -> int:
	return 0 if registry == null else registry.species_hosted_count()
