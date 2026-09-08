extends QATestCase
## THE HOME PROP — Tier 1 row 6's thin form, second of its three clauses.
##
## gdd.md -> Level & world design: "the move-in prop (den, burrow, nest) is decoration —
## **no tiles, no collision**, gone if the home relocates." Every clause of that sentence is
## an assertion here, and one more that gdd.md leaves to buildings.md:
##
##   A DEN APPEARS at a wild species' home site the moment somebody moves in.
##   A VILLAGER GETS NONE — buildings.md: "A House is a home site with a fixed footprint",
##     so a House *is* the villager's prop and a burrow beside it would be a second home for
##     one family. **Asserted as a COUNT, not as an absence**: after a villager moves in the
##     prop count must be unchanged, which a "no den on the house tile" check would not catch
##     if the den had merely landed somewhere else.
##   IT IS DECORATION. No collider anywhere in its subtree, it occupies no tile, and it
##     changes neither `get_tile_tags()` nor capacity — measured across the `present()` call
##     itself, so nothing but the prop is in the frame.
##   GONE IF THE HOME RELOCATES. `release()` drops the prop and the roamers anchored to it.
##
## THE RULE IS EXPRESSED AGAINST THE DATA, NOT AGAINST THE SPECIES (`site.is_structure()`),
## and this suite asserts it that way: a synthetic structure site gets no prop even though
## nothing about it is a villager. A rule written as `if species_id == "human"` would pass a
## villager-shaped test and fail the first time a second building becomes a home.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_home_prop.gd

const WORLD_PATH: String = "res://scenes/Main.tscn"
const SEED: int = 20260728

## The rabbit's habitat — 12 rock tiles beside the starting meadow, the same cheapest-possible
## habitat `test_causality_end_to_end.gd` uses.
const ROCK_ORIGIN := Vector2i(6, 7)
const ROCK_W: int = 4
const ROCK_D: int = 3

## The villager's, deliberately out of the rabbit's radius.
const HOUSE_TILE := Vector2i(28, 28)
const FIELD_TILE := Vector2i(29, 28)

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false


func _initialize() -> void:
	begin("home prop")

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

	_check_the_prop_scene_is_pure_decoration()
	_check_prop_changes_nothing_about_the_tile()
	_check_structure_home_gets_no_prop_and_wild_home_does()
	_check_release_drops_the_prop()
	_check_counts_in_the_real_world()

	note_expected_pending(
		"`release()` HAS A CALLER NOW (row 10, 2026-07-28) — and the queue_free note is LIVE",
		"The old note here said nothing invoked `ResidentPresentation.release()`. That is no "
		+ "longer true: `GentleDisplacement._relocate()` calls `release()` and then `present()` "
		+ "for the SAME home site, and `_depart()` calls it when a home empties. **The hazard "
		+ "this note flagged for row 10 is therefore now real rather than hypothetical:** "
		+ "`release()` erases its dictionary entry immediately but frees the node with "
		+ "`queue_free()`, so a release-then-present inside one frame leaves the old den in the "
		+ "scene until end of frame while the new one is already there. It is a one-frame VISUAL "
		+ "artefact only — no tile, no collision, no capacity effect, and this suite's counts "
		+ "are unaffected because the dictionary entry is replaced correctly. Reported to "
		+ "gameplay-engineer, not patched here; the fix is a direct `free()` or a defer in "
		+ "`release()`."
	)
	note_expected_pending(
		"ONE DEN SCENE FOR EVERY SPECIES (content, not a system)",
		"`HOME_PROP_SCENE` is a single composed den (log + rock + bush) used for fox and rabbit "
		+ "alike. gdd.md names \"den, burrow, nest\" as three props; per-species props are "
		+ "content-pipeline work, not a row-6 system, and are correctly absent at the floor."
	)

	finish()
	return true


# --- Decoration: no collision anywhere ---------------------------------------------------------

func _check_the_prop_scene_is_pure_decoration() -> void:
	var packed: PackedScene = load(ResidentPresentation.HOME_PROP_SCENE) as PackedScene
	if not check(packed != null, "the home prop scene `%s` loads"
		% ResidentPresentation.HOME_PROP_SCENE):
		return
	var prop: Node3D = packed.instantiate() as Node3D
	if not check(prop != null, "...and instantiates as a Node3D"):
		return

	var colliders: Array[String] = []
	var counts: Array = [0]
	_collect(prop, colliders, counts)

	check(colliders.is_empty(),
		"NO COLLISION ANYWHERE in the prop's subtree — it is decoration, and a player tap must "
		+ "pass straight through it to the tile underneath",
		"found: %s" % str(colliders))
	check(counts[0] > 0,
		"...and it is not vacuously collision-free: the subtree really has %d visual mesh(es)"
			% counts[0])
	prop.free()


## Collects the names of every collision-bearing node, and counts meshes. A prop with no
## meshes at all would pass the collider check for the wrong reason.
func _collect(node: Node, colliders: Array[String], counts: Array) -> void:
	if node is CollisionObject3D or node is CollisionShape3D or node is Area3D:
		colliders.append("%s (%s)" % [node.name, node.get_class()])
	if node is MeshInstance3D:
		counts[0] = (counts[0] as int) + 1
	for child: Node in node.get_children():
		_collect(child, colliders, counts)


# --- Decoration: it occupies no tile -----------------------------------------------------------

func _check_prop_changes_nothing_about_the_tile() -> void:
	# A SYNTHETIC fixture, because the measurement has to bracket `present()` and NOTHING else.
	# On the real world an arrival also registers a home site, which legitimately reallocates
	# tiles and moves capacity — that would drown the thing being measured.
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 36, 36)
	root.add_child(grid)
	var props_root := Node3D.new()
	props_root.name = "PropsUnderTest"
	root.add_child(props_root)

	var presentation := ResidentPresentation.new()
	presentation.attach(grid, props_root, SEED)

	var registry := HomeSiteRegistry.new()
	var rabbit: AnimalDefinition = _world.roster.by_id("rabbit")
	var tile := Vector2i(18, 18)
	# RE-POINTED 2026-09-04 (habitat-tiers ruling): `CapacityEvaluator.capacity()` now reads
	# `AnimalDefinition.effective_tiers()`, which prefers the real `tiers` rabbit.tres now
	# carries — base tier needs `open_grass/4` + `cultivated/4`, not `cover`. This row used to
	# be `rock`; it is `cultivated_field` now.
	for i in 12:
		grid.set_terrain(tile.x - 6 + i, tile.y + 1, "cultivated_field")
	# RE-POINTED (-> D-29 #1, `WorldGrid.START_TERRAIN_ID` "grass" -> "wild_grass"): this
	# synthetic grid now starts all-`wild_grass`, tag-inert, so the rabbit's OTHER need
	# (`open_grass`) has to be painted explicitly too, or capacity never rises off 0 no matter
	# how much cultivated goes down. A row just south of the cultivated row supplies it.
	for i in 12:
		grid.set_terrain(tile.x - 6 + i, tile.y + 2, "grass")

	# The site is registered FIRST, so the only thing that happens between the two measurements
	# is the prop (and the roamer) appearing.
	var site: HomeSite = registry.register(tile, "rabbit", rabbit.scout_radius)
	var tags_before: Array[String] = grid.get_tile_tags(tile.x, tile.y)
	var terrain_before: String = grid.get_terrain_id(tile.x, tile.y)
	var occupied_before: bool = grid.is_occupied(tile.x, tile.y)
	var capacity_before: int = CapacityEvaluator.capacity(grid, registry, tile, rabbit, site)
	check(capacity_before >= 1,
		"the measurement tile is real habitat before the den lands (capacity %d)" % capacity_before)

	var resident := Node3D.new()
	resident.name = "PropTestResident"
	resident.position = grid.tile_to_world(tile.x, tile.y)
	root.add_child(resident)
	presentation.present(resident, site)

	check_eq(presentation.prop_count(), 1, "A DEN APPEARED at the wild species' home site")
	check_eq(grid.get_tile_tags(tile.x, tile.y), tags_before,
		"THE DEN EMITS NO TAGS — `get_tile_tags()` on its own tile is byte-for-byte unchanged")
	check_eq(grid.get_terrain_id(tile.x, tile.y), terrain_before,
		"...and the tile's terrain is unchanged")
	check_eq(grid.is_occupied(tile.x, tile.y), occupied_before,
		"...and the tile is NOT occupied — a den is not a building")
	check_eq(CapacityEvaluator.capacity(grid, registry, tile, rabbit, site), capacity_before,
		"THE DEN MOVES NO CAPACITY — the same %d before and after it appeared" % capacity_before)
	check(grid.set_terrain(tile.x, tile.y, "forest"),
		"...and the tile under the den is still fully editable (it paints)")
	grid.set_terrain(tile.x, tile.y, terrain_before)

	# Structure: the prop hangs off the visual props root, never off the tile grid and never off
	# the resident — the resident walks away from its den within seconds of arriving.
	var prop: Node3D = props_root.get_child(0) as Node3D
	check(prop != null and prop.get_parent() == props_root,
		"the prop is parented to the visual props root, not to the grid")
	check(prop != null and not resident.is_ancestor_of(prop),
		"...and not to the resident, which walks away from it")
	check(prop != null and prop.position.is_equal_approx(grid.tile_to_world(tile.x, tile.y)),
		"...and it stands on the home site's own world position")

	resident.free()
	presentation.free()
	props_root.free()
	grid.free()


# --- Wild home yes, structure home no — and the rule reads the DATA ------------------------------

func _check_structure_home_gets_no_prop_and_wild_home_does() -> void:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 36, 36)
	root.add_child(grid)
	var props_root := Node3D.new()
	root.add_child(props_root)
	var presentation := ResidentPresentation.new()
	presentation.attach(grid, props_root, SEED)
	var registry := HomeSiteRegistry.new()

	check_eq(presentation.prop_count(), 0, "no home, no prop")

	# 1. A wild home site: prop count 0 -> 1.
	var wild_a: HomeSite = registry.register(Vector2i(8, 8), "rabbit", 8)
	presentation.present(_stub(grid, 8, 8), wild_a)
	check_eq(presentation.prop_count(), 1, "a WILD home site gets a den (0 -> 1)")

	# 2. A STRUCTURE home site through the identical call: the count must not move. This is the
	#    A/B control that makes the villager assertion below mean something.
	var structure: HomeSite = registry.register_structure(Vector2i(20, 8), ["house"] as Array[String], 8)
	check(structure.is_structure(), "the structure site reports `is_structure()`")
	presentation.present(_stub(grid, 20, 8), structure)
	check_eq(presentation.prop_count(), 1,
		"A STRUCTURE HOME SITE GETS NO DEN — the count is unchanged (1, not 2). The rule reads "
		+ "`site.is_structure()`, so nothing here knows what a villager is")
	check_eq(presentation.roamer_count(), 2,
		"...but its resident still wanders: no prop is not no presentation")

	# 3. A second wild home site: the count moves again, so step 2's zero was not the ceiling.
	var wild_b: HomeSite = registry.register(Vector2i(8, 26), "fox", 12)
	presentation.present(_stub(grid, 8, 26), wild_b)
	check_eq(presentation.prop_count(), 2,
		"CONTROL: a second wild home site DOES add a den (1 -> 2) — step 2 was the structure "
		+ "rule, not a saturated counter")

	# 4. Two residents at one wild home site share one den; a home is not a per-animal prop.
	presentation.present(_stub(grid, 8, 8), wild_a)
	check_eq(presentation.prop_count(), 2,
		"a SECOND resident at the same home site adds no second den (one home, one prop)")
	check_eq(presentation.roamer_count(), 4, "...though it does get its own wander")

	presentation.free()
	props_root.free()
	grid.free()


func _check_release_drops_the_prop() -> void:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 36, 36)
	root.add_child(grid)
	var props_root := Node3D.new()
	root.add_child(props_root)
	var presentation := ResidentPresentation.new()
	presentation.attach(grid, props_root, SEED)
	var registry := HomeSiteRegistry.new()

	var keep: HomeSite = registry.register(Vector2i(10, 10), "rabbit", 8)
	var drop: HomeSite = registry.register(Vector2i(26, 10), "rabbit", 8)
	presentation.present(_stub(grid, 10, 10), keep)
	presentation.present(_stub(grid, 26, 10), drop)
	check_eq(presentation.prop_count(), 2, "two homes, two dens")
	check_eq(presentation.roamer_count(), 2, "...and two roamers")

	var dropped_node: Node = props_root.get_node_or_null("Den_%d_%d" % [drop.position.x, drop.position.y])
	var kept_node: Node = props_root.get_node_or_null("Den_%d_%d" % [keep.position.x, keep.position.y])
	check(dropped_node != null and kept_node != null, "both dens are in the scene before release")

	presentation.release(drop)
	check_eq(presentation.prop_count(), 1,
		"GONE IF THE HOME RELOCATES: `release()` drops that home's den (2 -> 1)")
	check_eq(presentation.roamer_count(), 1,
		"...and the roamers anchored to it (2 -> 1)")
	# `release()` uses `queue_free()`, so the node leaves at the end of the frame rather than
	# inside the call. Asserted as "queued", which is the honest form — the point is that the
	# node is really being destroyed and not merely dropped from the dictionary.
	check(dropped_node.is_queued_for_deletion(),
		"...and THE NODE ITSELF is queued for deletion, not just erased from the prop map")
	check(not kept_node.is_queued_for_deletion(),
		"...while the other home's den is untouched — release is per-home, not a clear")

	# RELEASE-THEN-PRESENT IN ONE FRAME — row 10's actual relocation sequence
	# (`GentleDisplacement._relocate()` calls `release(site)`, moves the site, then `present()`).
	# The bookkeeping must be exactly right through it, which is what this asserts. The
	# scene-graph transient it exposes is measured and REPORTED in the pending note above rather
	# than failed here: it is a one-frame visual artefact in someone else's file.
	presentation.present(_stub(grid, 26, 10), drop)
	check_eq(presentation.prop_count(), 2,
		"RELEASE-THEN-PRESENT: the prop map is back to two dens — the dictionary entry for the "
		+ "re-presented home is replaced correctly, so no COUNT is ever wrong")
	var live_props: int = 0
	var live_at_drop: int = 0
	var drop_position: Vector3 = grid.tile_to_world(drop.position.x, drop.position.y)
	for child: Node in props_root.get_children():
		if child.is_queued_for_deletion():
			continue
		live_props += 1
		if (child as Node3D).position.is_equal_approx(drop_position):
			live_at_drop += 1
	check_eq(live_props, presentation.prop_count(),
		"...and the number of LIVE prop nodes matches the prop map (%d)" % live_props)
	check_eq(live_at_drop, 1, "...with exactly one live den standing at the re-presented home")
	print("  NOTE  props_root holds %d child node(s) this frame for %d live den(s); the "
		% [props_root.get_child_count(), live_props]
		+ "extra is the queue_free()'d predecessor, which also forces the replacement to take a "
		+ "mangled node name for the frame. Reported in the pending note above.")
	presentation.release(drop)

	presentation.release(keep)
	check_eq(presentation.prop_count(), 0, "releasing the other leaves nothing behind")
	presentation.release(null)
	check_eq(presentation.prop_count(), 0, "`release(null)` is a no-op, not an error")

	presentation.free()
	props_root.free()
	grid.free()


# --- The real world: the counts a player would see ----------------------------------------------

func _check_counts_in_the_real_world() -> void:
	var presentation: ResidentPresentation = _world.presentation
	if not check(presentation != null, "the live world owns a ResidentPresentation"):
		return
	var props_root: Node3D = _world.get_node_or_null("HomeProps") as Node3D
	check(props_root != null, "...and a `HomeProps` visual root separate from the tile grid")

	check_eq(presentation.prop_count(), 0, "the world starts with no dens — nothing is pre-placed")
	check_eq(_world.total_residents(), 0, "...and no residents")

	# THE WILD MOVE-IN.
	#
	# RE-DERIVED 2026-07-28 (-> D-27 #2). At the rabbit's decided divisor of 4 this same 12-tile
	# block is worth THREE individuals, not one, and `test_causality_end_to_end.gd`'s pending
	# note measures that several candidate sites end up competing for those tiles — 6 rabbit home
	# sites on one run of this exact paint pattern, not a clean 3. This suite's subject is prop
	# MECHANICS (one den per home site; none for a villager), not the fragmentation count, so it
	# asserts against the actual number of wild sites that hold a resident, whatever that number
	# turns out to be, rather than pinning an unruled-on head count a second time.
	# RE-POINTED (-> D-29 #1): the rabbit needs BOTH `open_grass` and `cover`, and `wild_grass`
	# (the new default) supplies neither implicitly — this border supplies the `open_grass` half
	# the old ambient `grass` backdrop used to give away for free.
	#
	# RE-POINTED AGAIN 2026-09-04 (habitat-tiers ruling): `capacity_at()` now reads
	# `AnimalDefinition.effective_tiers()`, which prefers the real `tiers` rabbit.tres now
	# carries — base tier needs `open_grass/4` + `cultivated/4`, not `cover`. The block below
	# is now painted `cultivated_field`, not `rock`.
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
			_world.paint_tile(ROCK_ORIGIN.x + dx, ROCK_ORIGIN.y + dz, "cultivated_field")
	_drain(60)
	_world.simulation.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)

	if not check(_world.total_residents() >= 1, "at least one rabbit moved in (%d residents)"
		% _world.total_residents()):
		return
	var wild_sites_with_residents: int = _wild_sites_with_residents()
	check(wild_sites_with_residents >= 1,
		"...across at least one wild home site (%d)" % wild_sites_with_residents)
	check_eq(presentation.prop_count(), wild_sites_with_residents,
		"A DEN APPEARED AT EVERY OCCUPIED WILD HOME — one per site (%d), not one per rabbit (%d)"
			% [wild_sites_with_residents, _world.total_residents()])
	check_eq(presentation.roamer_count(), _world.total_residents(),
		"...and every resident wanders — one roamer per rabbit, not per den")
	check_eq(props_root.get_child_count(), wild_sites_with_residents,
		"...and exactly that many prop nodes are in the scene")

	var den_site: HomeSite = _wild_site()
	if not check(den_site != null, "the rabbit's home site is in the registry"):
		return
	var den_tile: Vector2i = den_site.position
	check(not den_site.is_structure(), "the rabbit's home is NOT a structure site")

	# The den occupies no tile, measured on the live world through the public API.
	var terrain_id: String = _world.get_tile_terrain(den_tile.x, den_tile.y)
	var terrain: TerrainDefinition = _world.grid.terrain_definition(terrain_id)
	check_eq(_world.get_tile_tags(den_tile.x, den_tile.y), terrain.emitted_tags,
		"THE DEN TILE'S TAGS ARE EXACTLY ITS TERRAIN'S (`%s`) — the prop emits nothing"
			% terrain_id)
	check(not _world.grid.is_occupied(den_tile.x, den_tile.y),
		"...and the tile is unoccupied: a den is not a building and blocks no placement")
	check(_world.can_place(den_tile.x, den_tile.y, "house") == (terrain_id == "grass"),
		"...and buildability at the den tile is decided by its terrain alone, not by the prop")
	check(_world.can_paint(den_tile.x, den_tile.y, "forest"),
		"...and the tile under the den still paints")

	# THE VILLAGER — and the assertion this suite exists for. A DELTA against whatever the wild
	# section settled at, for the same reason as above: the rabbit head count is contested and
	# not this suite's to pin, but "exactly one more resident, and it gets no den" is true
	# regardless of how many rabbits arrived first.
	var props_before: int = presentation.prop_count()
	var residents_before_house: int = _world.total_residents()
	# RE-POINTED (-> D-29 #1): the House's `allowed_terrain` is `["grass"]` specifically
	# (buildings.md), and `HOUSE_TILE` is `wild_grass` under the new default, not `grass`.
	_world.paint_tile(HOUSE_TILE.x, HOUSE_TILE.y, "grass")
	_world.place_building(HOUSE_TILE.x, HOUSE_TILE.y, "house")
	_world.paint_tile(FIELD_TILE.x, FIELD_TILE.y, "cultivated_field")
	_drain(60)
	_world.simulation.tick(ArrivalQueue.ARRIVAL_DELAY_MAX_SECONDS + 1.0)

	if not check(_world.total_residents() == residents_before_house + 1,
		"exactly one villager moved in (%d -> %d residents)"
			% [residents_before_house, _world.total_residents()]):
		return
	check(_world.resident_species_ids().has("human"), "...and it really is a villager")
	check_eq(presentation.prop_count(), props_before,
		"A VILLAGER GETS NO DEN: the prop count is still %d after the move-in, not %d"
			% [props_before, props_before + 1])
	check_eq(props_root.get_child_count(), props_before,
		"...and no second prop node exists anywhere in the scene — a House IS its own prop")
	check_eq(presentation.roamer_count(), _world.total_residents(),
		"...while the villager does get a wander, like every other resident — one roamer per "
		+ "resident, whatever the total (%d)" % _world.total_residents())

	var house_site: HomeSite = _site_at(HOUSE_TILE)
	check(house_site != null and house_site.is_structure(),
		"the villager's home is the House's own STRUCTURE site — which is why it needs no prop")


# --- helpers -------------------------------------------------------------------------------------

## A bare stand-in resident. The prop rules do not depend on the model, and using one here
## would make this suite fail for animation reasons.
func _stub(grid: WorldGrid, x: int, z: int) -> Node3D:
	var node := Node3D.new()
	node.name = "Stub_%d_%d" % [x, z]
	node.position = grid.tile_to_world(x, z)
	root.add_child(node)
	return node


func _wild_site() -> HomeSite:
	for site: HomeSite in _world.registry.sites():
		if not site.is_structure() and site.population() > 0:
			return site
	return null


## How many DISTINCT wild home sites currently hold at least one resident. Not the same as
## `total_residents()`: a fragmented block (see the wild-move-in comment above) can produce
## several sites each holding one resident, which is exactly the count `prop_count()` must match
## — one den per occupied site, never one per resident.
func _wild_sites_with_residents() -> int:
	var n: int = 0
	for site: HomeSite in _world.registry.sites():
		if not site.is_structure() and site.population() > 0:
			n += 1
	return n


func _site_at(tile: Vector2i) -> HomeSite:
	for site: HomeSite in _world.registry.sites():
		if site.position == tile:
			return site
	return null


func _drain(ticks: int) -> void:
	for _i in ticks:
		_world.simulation.tick(0.0)
