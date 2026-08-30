extends QATestCase
## THE RESTORE SEAMS — the two public methods Tier 1 row 1 adds to row 6's files.
##
## THE ASSERTION THAT MATTERS MOST IS A NEGATIVE: restoring a resident must **not** emit
## `resident_arrived`. That signal is what fires the fact card (row 7). If restore used the
## ordinary move-in path, loading a world with six residents would open six fact cards over a
## world the player has not touched yet — the loudest possible violation of "Load restores
## faithfully". Restore therefore reuses the spawn and presentation code and stops short of the
## arrival announcement, and that boundary is pinned here.
##
## SEQUENCE ORDER IS LOAD-BEARING, not bookkeeping. `HomeSiteRegistry.rebuild_ownership()`
## breaks distance ties by lower sequence, so tile exclusivity depends on the order sites were
## created. Restoring sites in saved order preserves it; restoring in arbitrary order would
## silently rearrange which home owns a contested tile, which is a different world.
##
## Run:
##   bash scripts/run-tests.sh restore_seams

const WORLD_PATH: String = "res://scenes/Main.tscn"

var _world: WorldRoot = null
var _frames: int = 0
var _setup_ok: bool = false
var _arrivals: Array[String] = []


func _initialize() -> void:
	begin("restore seams")
	var packed: PackedScene = load(WORLD_PATH) as PackedScene
	if not check(packed != null, "%s loads" % WORLD_PATH):
		finish()
		return
	_world = packed.instantiate() as WorldRoot
	if not check(_world != null, "Main.tscn's root is a WorldRoot"):
		finish()
		return
	# Array, not int: a lambda capturing a local int copies it and never increments, which would
	# make the "no fact card" assertion pass vacuously.
	_world.resident_arrived.connect(func(id: String, _p: Vector3) -> void: _arrivals.append(id))
	root.add_child(_world)
	_setup_ok = true


func _process(_delta: float) -> bool:
	if not _setup_ok:
		return true
	_frames += 1
	if _frames < 3:
		return false

	_world.wood.set_process(false)
	_world.simulation.set_process(false)
	_world.displacement.set_process(false)
	_world.presentation.set_process(false)
	_world.removals.set_process(false)

	_check_restore_site_creates_a_populated_home()
	_check_restore_does_not_fire_a_fact_card()
	_check_restore_preserves_sequence_order()
	_check_restore_hosted_keeps_departed_species()
	_check_mark_all_dirty_reaches_every_site()

	finish()
	return true


func _check_restore_site_creates_a_populated_home() -> void:
	var at := Vector2i(10, 10)
	var world_pos: Vector3 = _world.grid.tile_to_world(at.x, at.y)
	var site: HomeSite = _world.simulation.restore_site(
		at, "rabbit", 4, [] as Array[String], [world_pos]
	)
	if not check(site != null, "restore_site returns a site"):
		return
	check_eq(site.position, at, "the site is at the restored position")
	check_eq(site.species_id, "rabbit", "the site carries the restored species")
	check_eq(site.radius, 4, "the site carries the restored radius")
	check_eq(site.population(), 1, "one resident was spawned")
	check(
		_world.registry.species_hosted_ids().has("rabbit"),
		"a restored resident counts as hosted"
	)
	# The resident is a live node the tap path can find, not a bookkeeping entry.
	check(site.residents[0] != null, "the resident is a real node")
	check(
		site.residents[0].position.distance_to(world_pos) < 0.01,
		"the resident stands where it was saved, not at the tile centre by default"
	)


func _check_restore_does_not_fire_a_fact_card() -> void:
	# THE NEGATIVE THAT MATTERS. One site was restored above; no card may have opened.
	check_eq(_arrivals.size(), 0, "restoring a resident fires NO resident_arrived")
	check_eq(
		_world.simulation.pending_evaluations(), 0,
		"restoring a resident does not dirty the queue by itself"
	)


func _check_restore_preserves_sequence_order() -> void:
	var first: HomeSite = _world.simulation.restore_site(
		Vector2i(20, 20), "rabbit", 4, [] as Array[String], []
	)
	var second: HomeSite = _world.simulation.restore_site(
		Vector2i(22, 20), "rabbit", 4, [] as Array[String], []
	)
	check(
		first.sequence < second.sequence,
		"sites restored in order keep ascending sequence, so tie-breaks survive a reload"
	)
	# A structure site restores vacant and keeps its tags — a House whose family left.
	var house: HomeSite = _world.simulation.restore_site(
		Vector2i(30, 30), "", 3, ["house"] as Array[String], []
	)
	check(house.is_vacant(), "a structure site with no species restores vacant")
	check(house.structure_tags.has("house"), "a structure site keeps its emitted tags")
	check(
		not _world.registry.species_hosted_ids().has(""),
		"a vacant site never records the empty string as a hosted species"
	)


func _check_restore_hosted_keeps_departed_species() -> void:
	# Species Hosted is all-time and never decreases (gdd.md -> Economy). A species that was
	# hosted and then departed has NO home site to restore, so it must come back some other way.
	_world.registry.restore_hosted(["fox"] as Array[String])
	check(
		_world.registry.species_hosted_ids().has("fox"),
		"a species with no surviving home site is still recorded as hosted"
	)
	check(
		not _world.resident_species_ids().has("fox"),
		"...and is NOT counted as currently resident"
	)


func _check_mark_all_dirty_reaches_every_site() -> void:
	check_eq(_world.simulation.pending_evaluations(), 0, "queue starts drained")
	_world.simulation.mark_all_dirty()
	check(
		_world.simulation.pending_evaluations() >= _world.registry.sites().size(),
		"mark_all_dirty enqueues at least one evaluation per home site"
	)
