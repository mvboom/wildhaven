class_name WorldSnapshot
extends RefCounted
## THE SAVE SCHEMA of Tier 1 row 1. Static-only; never instantiated.
##
## THIS FILE DOES NOT TOUCH THE DISK. `SaveStore` does that. The split is what lets the schema
## be exercised with no filesystem and the filesystem with no world.
##
## WHAT IS SAVED, AND WHAT IS NOT (human ruling 3, 2026-08-01, AMENDED 2026-08-02, AMENDED
## AGAIN AT v3). The file holds committed state — terrain, buildings, Wood, home sites and
## their residents' live positions AND LOOKS (v5), the all-time Species Hosted set, the header,
## the pending arrival queue, **and now removal receipts**. It still holds no other in-flight
## state: no open settlement gestures, no dirty queue, no fractional Wood.
##
## REMOVAL RECEIPTS JOINED AT v3 (reported bug fix): the original ruling grouped them with the
## other excluded in-flight state above, but those all either don't matter after a reload or
## get RE-DERIVED by `apply()` (the dirty queue via `mark_all_dirty()`, an open settlement
## gesture via `reconcile_after_load()`). Nothing re-derives "what was this tile before it was
## painted" — that information has no other source — so losing receipts silently turned every
## edit from an earlier session into one `remove_at()` could never undo again. See
## `RemovalLedger.to_save()`/`.restore()` for the schema and for why `issued_at` deliberately
## does not round-trip.
##
## AN OPEN SETTLEMENT GESTURE IS RE-ARMED, NOT SAVED (D-32, 2026-08-02). `apply()` closes by
## asking `GentleDisplacement` to open a fresh window for any home that is over capacity, which
## covers the pending-displacement case without a schema field — and self-heals an over-capacity
## home from any other cause too. See step 9 in `apply()`.
##
## THE ARRIVAL QUEUE WAS THE ONE EXCEPTION THAT DID NOT HOLD. Ruling 3 reasoned that an arrival
## is enqueued when a neighbourhood is marked dirty, so `apply()`'s closing `mark_all_dirty()`
## would re-derive the queue through the simulation's own event-driven path. It does not:
## `mark_all_dirty()` reaches `_mark_all_sites_dirty()`, which enqueues only ALREADY-REGISTERED
## home sites — and a habitat that qualifies but has nobody in it yet has no home site to
## enqueue. Measured: capacity 1, sites 0, capture, apply -> 0 residents after 600 simulated
## seconds, and 1 only after some further player edit. A child paints a rabbit meadow, quits
## inside the 20-60 s arrival delay, and the rabbit never comes. So the queue is now in the file
## (`save_version` 2), and the human ruling of 2026-08-02 partially reverses ruling 3.
##
## The dirty queue is still NOT saved, and that is a separate call: it drains at
## `MAX_EVALUATIONS_PER_FRAME` (4) per frame, ~240/s against a child's tap rate of a few per
## second, so no real backlog accumulates — and anything that was dirty has already been
## evaluated into either an arrival (now saved) or nothing.
##
## EVERY VALUE HERE IS JSON-NATIVE. `Vector2i` and `Vector3` do not survive `JSON.stringify`
## (they come back as strings), so positions are written as plain arrays and rebuilt on the way
## in. `test_world_snapshot.gd` asserts the round trip, which is what stops an engine type
## quietly entering the schema later.

## PROPOSED (2026-08-01) — the initial value tier1-status.md row 1 names as a constant this row
## owns. gdd.md -> Saves: "A `save_version` field ships from day one, so post-class growth
## handles old saves gracefully."
##
## v1 -> v2 (2026-08-02, one human ruling with two halves): `"arrivals"` joins the schema, and
## `"seed"` stops being a constant 0. `_migrate()` carries v1 files forward; see it for the two
## rules that make an old file behave.
##
## v2 -> v3 (bug fix, terraform-bar rework playtest): `"removals"` joins the schema — see the
## header's "REMOVAL RECEIPTS JOINED AT v3" note. `migrate()` supplies `{}` for a file that
## predates it, which `RemovalLedger.restore()` already treats as "no receipts", identical to
## today's actual (buggy) behavior — so an old file's removal is not retroactively fixed, but it
## is not made any worse either, and every save from here on carries the fix forward.
##
## v3 -> v4 (style-picker sub-project B2, Task 4): `"style_defaults"` joins the schema —
## `WorldRoot.style_defaults`, the player's chosen default style per hotbar picker category
## (forest/wild_grass/house/farm_building). No new migration logic is needed beyond the version
## bump: an absent key is exactly what `dict_field()` already treats as "no choices made", and
## `WorldRoot.get_style_default()` (Task 3) already falls through an empty/stale entry to that
## category's first catalog entry — so a pre-v4 file just plays as if nobody had opened a picker
## yet, which is the truth. (This retires the "row 13 -> v4" placeholder note that used to sit at
## the bottom of `migrate()`.)
##
## v4 -> v5 (villager-variety bug fix): a `home_sites[].residents[]` entry grows a FOURTH
## element — the `AnimalDefinition.model_scenes` index that resident is wearing. It went from
## `[x, y, z]` to `[x, y, z, variant_index]`.
##
## WHY THE SCHEMA HAD TO CHANGE, given the previous design leaned hard on it not having to.
## Before this, a resident's look was re-derived on load from its slot within its home site's
## `residents` array — zero save state, stable across a reload. It was also the variety bug:
## a slot index is not a global identity, so the first resident at EVERY home site derived the
## same look. Replacing the derivation with a shuffle bag (`VariantBag`) means the look is now
## a genuine random choice made once, at move-in — and a random choice that is not written down
## is re-rolled on every load. The 4th element is what keeps look stability across save/load,
## which was never optional.
##
## MIGRATION IS A VERSION BUMP AND NOTHING ELSE, for the same reason v3 -> v4 was. A 3-element
## entry is legal input forever: `apply()` reads a missing 4th element as
## `AnimalDefinition.NO_VARIANT`, and `HabitatSimulation.restore_site()` turns that into the
## OLD slot-index derivation — so a pre-v5 world loads with exactly the looks it already had.
## No error, no reshuffle, no worse than today. Nothing needs inventing at migration time, and
## inventing looks there would be actively wrong: it would change how an existing village looks
## the first time it is opened on the new build.
##
## v5 -> v6 (habitat-tiers, Task 6): `home_sites` is unchanged, but `arrivals[]` entries grow
## a `"count"` key — how many individuals this pending arrival lands as a group (deer as a
## small herd, a fox alone), read off the qualifying tier's `arrival_group_size`. PURE
## VERSION-BUMP BOOKKEEPING, same shape as v3 -> v4 and v4 -> v5: `ArrivalQueue.restore()`
## already reads a missing `"count"` as 1 — never 0, which would silently drop the pending
## arrival — and 1 is exactly what every pre-v6 file's implicit group size always was. No
## migration step invents anything; see `ArrivalQueue.restore()`'s own comment.
##
## (row 13's mist extent takes v7 — v6 is spent here on habitat-tiers group arrivals.)
const SAVE_VERSION: int = 6


## The live world as a JSON-native dictionary.
static func capture(
	world: WorldRoot, world_name: String, preset_id: String, seed_value: int
) -> Dictionary:
	var grid: WorldGrid = world.grid

	# Row-major, one entry per tile. A plain array rather than a dictionary of changed tiles:
	# at the ~36x36 start that is ~1,300 short strings, and the format stays readable to a
	# human opening the file, which is the stated requirement.
	var terrain: Array[String] = []
	for z in range(grid.depth):
		for x in range(grid.width):
			terrain.append(grid.get_terrain_id(x, z))

	# ONE ENTRY PER BUILDING, not per covered tile — recorded at the footprint origin, so a
	# future 2x2 House restores as one building rather than four.
	var buildings: Array[Dictionary] = []
	var seen_origins: Dictionary = {}
	for z in range(grid.depth):
		for x in range(grid.width):
			var def: PlaceableDefinition = grid.get_building(x, z)
			if def == null:
				continue
			var origin: Vector2i = grid.get_building_origin(x, z)
			if seen_origins.has(origin):
				continue
			seen_origins[origin] = true
			buildings.append({"origin": [origin.x, origin.y], "id": def.id})

	# SORTED BY SEQUENCE, and that is load-bearing: `HomeSiteRegistry.rebuild_ownership()`
	# breaks distance ties by lower sequence, so restoring in this order is what makes tile
	# exclusivity come out the same after a reload.
	var sites: Array[HomeSite] = world.registry.sites().duplicate()
	sites.sort_custom(func(a: HomeSite, b: HomeSite) -> bool: return a.sequence < b.sequence)

	var home_sites: Array[Dictionary] = []
	for site: HomeSite in sites:
		var residents: Array[Array] = []
		for node: Node3D in site.residents:
			# A null resident is a content defect (no model_scene), recorded honestly rather
			# than dropped — dropping it would silently change the population on reload.
			var p: Vector3 = Vector3.ZERO if node == null else node.position
			# FOURTH ELEMENT AT v5: which `model_scenes` entry this resident is wearing. Before
			# v5 a resident was `[x, y, z]` and its look was RE-DERIVED on load from its slot
			# index — which is the variety bug (`AnimalDefinition.legacy_variant_index()`), and
			# which cannot be fixed without the look becoming real save state. A null resident,
			# or one that predates tagging, writes `NO_VARIANT` (-1): "this file does not know",
			# read on load exactly the same way a missing 4th element is.
			residents.append([p.x, p.y, p.z, HomeSite.variant_of(node)])
		home_sites.append({
			"position": [site.position.x, site.position.y],
			"species_id": site.species_id,
			"radius": site.radius,
			"sequence": site.sequence,
			"structure_tags": site.structure_tags,
			"residents": residents,
		})

	# PENDING ARRIVALS, at v2 (human ruling, 2026-08-02) — see the header. Written last so a
	# capture of a world whose simulation is not attached (only a test does this) is still a
	# valid file rather than a crash.
	var arrivals: Array[Dictionary] = []
	if world.simulation != null and world.simulation.arrivals() != null:
		arrivals = world.simulation.arrivals().to_save()

	# REMOVAL RECEIPTS, at v3 — see the header's "REMOVAL RECEIPTS JOINED AT v3" note.
	var removals: Dictionary = {} if world.removals == null else world.removals.to_save()

	return {
		"save_version": SAVE_VERSION,
		"name": world_name,
		"preset_id": preset_id,
		# Written but unread until row 13. Reveal is specified as a deterministic function of
		# (world_seed, x, y); a seed absent from the first shipped files could not be recovered
		# for worlds created before row 13 lands. It is generated at New Game time
		# (`new_game_screen.gd`) and is never 0 for a world a player made — 0 is the sentinel
		# for "no seed chosen", which is the editor/test path only.
		"seed": seed_value,
		"width": grid.width,
		"depth": grid.depth,
		"terrain": terrain,
		"buildings": buildings,
		"wood": world.get_wood(),
		"home_sites": home_sites,
		"species_hosted": world.registry.species_hosted_ids(),
		"arrivals": arrivals,
		"removals": removals,
		# STYLE DEFAULTS, at v4 — see the header's "v3 -> v4" note. `.duplicate()` so the saved
		# dictionary is not the SAME object as `world.style_defaults`; nothing else in this file
		# hands out a live reference to caller-mutable world state.
		"style_defaults": world.style_defaults.duplicate(),
	}


## Whether this build can open this file at all. A file with no version, or one written by a
## LATER build, is refused rather than guessed at — a half-restored world is worse than a
## world that will not open, and the file is human-readable so nothing is lost.
##
## TYPE BEFORE CAST — see `is_number()`. This is the same guard the `width`/`depth` reads in
## `apply()` already carry, extended to the one field that hand-edited JSON reaches first:
## `SaveStore.list()` calls this for every file in the saves directory, on every visit to the
## Load screen, before the player has done anything. `{"oops": 1}` used to abort this function
## mid-cast with a `SCRIPT ERROR` merely by sitting on disk; `"two"` used to silently coerce to
## `0` and pass `0 <= SAVE_VERSION`, listing an unopenable file as `readable`. Both are now an
## ordinary refusal.
static func can_apply(data: Dictionary) -> bool:
	if not data.has("save_version"):
		return false
	if not is_number(data["save_version"]):
		return false
	return int(data["save_version"]) <= SAVE_VERSION


## Is this value from a save file a number this schema may cast with `int()`/`float()`?
##
## **SAVES ARE HAND-EDITABLE BY DESIGN** (gdd.md -> Saves), so a JSON object, array or string
## where a number belongs is anticipated input, not an impossibility. It matters because a bare
## `int(value)` on one of those is not a 0 — it is a runtime "Nonexistent 'int' constructor"
## error that aborts the enclosing function part-way through, skipping every check below the
## cast. Guarding with `typeof()` first turns that into an ordinary refusal.
##
## Both JSON number types are accepted: Godot's parser yields `TYPE_FLOAT` for `36.0` and
## `TYPE_INT` for `36`, and which one a hand-edited file carries is not the player's problem.
## A numeric *string* is deliberately NOT accepted — `"36"` is not what this schema writes.
static func is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


## The Array a save field names, or an empty one — `is_number()`'s doctrine for the second cast
## this schema makes on untrusted data.
##
## A bare `data.get(key, []) as Array` on a String, Dictionary or number is NOT an empty array. It
## is a runtime "Invalid cast: could not convert value to 'Array'" that aborts `apply()` PART-WAY
## THROUGH — after terrain, buildings, Wood, home sites and Species Hosted are already written
## into the live world, and BEFORE the re-derivation that makes the simulation run. The player is
## then sitting in a half-restored world with an inert simulation while `push_error` tells them
## they are in an unsaved default one. Every array read in `apply()` comes through here, so no
## sibling is left unguarded beside a guarded one.
##
## An ABSENT key is not a defect and says nothing; a wrong-typed one warns and reads as empty.
static func array_field(data: Dictionary, key: String) -> Array:
	var value: Variant = data.get(key, [])
	if typeof(value) == TYPE_ARRAY:
		return value as Array
	push_warning(
		"WorldSnapshot: `%s` is a %s, not an array; treated as empty."
		% [key, type_string(typeof(value))]
	)
	return []


## The Dictionary-typed twin of `array_field()`, same doctrine — see its doc comment for the
## bug class this closes. `"style_defaults"` (v4) is the one field this schema reads as a
## Dictionary rather than an Array; a bare `data.get("style_defaults", {}) as Dictionary` on a
## hand-edited String, Array or number is NOT an empty dictionary, it is a function-aborting
## "Invalid cast" SCRIPT ERROR — the exact bug class Task 3 already hit and fixed once, at
## `WorldRoot.get_style_default()`'s own `style_defaults.get(category, "")` read (fixed via
## `text_or()`). An ABSENT key is not a defect and says nothing; a wrong-typed one warns and
## reads as empty, and `WorldRoot.get_style_default()`'s existing stale/empty-entry fallback (to
## a category's first catalog entry) takes it from there — no further degradation logic needed.
static func dict_field(data: Dictionary, key: String) -> Dictionary:
	var value: Variant = data.get(key, {})
	if typeof(value) == TYPE_DICTIONARY:
		return value as Dictionary
	push_warning(
		"WorldSnapshot: `%s` is a %s, not a dictionary; treated as empty."
		% [key, type_string(typeof(value))]
	)
	return {}


## The String a value holds, or `fallback` when it is not one — the same doctrine for the third
## cast. `"name": 42` and `"name": {"oops": 1}` both used to abort their enclosing function on
## `as String`, which in `migrate()`'s case returned `Nil` into a caller that dereferenced it.
static func text_or(value: Variant, fallback: String) -> String:
	if typeof(value) == TYPE_STRING:
		return value as String
	return fallback


## Older files, brought forward. Never mutates the caller's dictionary — `apply()` takes the
## return value, and the file on disk is not rewritten until the next ordinary autosave.
##
## **v2 -> v3** (bug fix, terraform-bar rework playtest): `"removals"` did not exist before v3,
## so an older file supplies `{}` — `RemovalLedger.restore({})` leaves the ledger empty, which
## is exactly today's (buggy) behavior for that file, not a regression.
##
## **v1 -> v2** (2026-08-02), two rules:
##
##   1. `"arrivals"` did not exist at v1, so a v1 file supplies `[]`. A v1 world therefore
##      behaves on load exactly as it does today — no crash, and no invented arrivals put in a
##      child's world by a migration.
##
##   2. `"seed"` was written as a CONSTANT 0 in every v1 file, which is exactly as unrecoverable
##      as absent. Row 13 specifies mist reveal as a deterministic function of
##      `(world_seed, x, y)`, so leaving every old world on 0 would give them all an identical
##      reveal pattern and make `seed: 0` ambiguous forever. THE RULE: derive the seed from the
##      world's NAME. It is stable (the same file always migrates to the same seed, so a world's
##      mist does not shuffle every time it is opened), it is distinct (two differently-named
##      worlds do not collide), and it needs nothing the file does not already carry.
##
## **THE SEED REPAIR IS NOT CONFINED TO THE v1 STEP.** A v2 file's `seed: 0` is left alone — it
## is a legitimate value there — but a v2 `seed` that is not a NUMBER is repaired the same way a
## v1 one is, because the alternative is `WorldRoot._ready()` aborting on `int()`. See the body.
##
## PUBLIC because `WorldRoot._ready()` reads `preset_id` and `seed` out of the file BEFORE it
## calls `apply()` — a migration those two reads could not see would leave a migrated world
## running on the un-migrated seed. Idempotent: a v2 dictionary passes straight through, so
## `apply()` calling it again costs nothing.
static func migrate(data: Dictionary) -> Dictionary:
	var version: int = int(data["save_version"]) if is_number(data.get("save_version", null)) else 0
	var out: Dictionary = data.duplicate(true)

	if version < 2:
		if not out.has("arrivals"):
			out["arrivals"] = []
		out["save_version"] = 2

	if version < 3:
		if not out.has("removals"):
			out["removals"] = {}
		out["save_version"] = 3

	# v3 -> v4 (style-picker sub-project B2, Task 4): no field needs inventing here, unlike the
	# two steps above. An absent `"style_defaults"` is exactly what `dict_field()` already reads
	# as "no choices made" with no warning, and `WorldRoot.get_style_default()` already falls an
	# empty/stale entry through to that category's first catalog entry (Task 3) — so this step is
	# pure version-bump bookkeeping, kept for the same reason the other two steps stamp their own
	# number: a caller inspecting the migrated dictionary (a test, or a future step chained after
	# this one) should see the CURRENT version, not whatever number the file was written with.
	if version < 4:
		out["save_version"] = 4

	# v4 -> v5 (villager-variety bug fix): pure version-bump bookkeeping, for the same reason
	# the step above is. The new information — which look each resident wears — is one that an
	# OLD FILE GENUINELY DOES NOT CONTAIN, and the only correct answer for a resident whose look
	# is unrecorded is the derivation that produced what that world was already showing. That
	# derivation lives at the read site (`apply()` -> `restore_site()` -> `legacy_variant_index`),
	# where it can see the species' `model_scenes` — which a dictionary-to-dictionary migration
	# cannot, having no roster. Writing looks in here would need the roster AND would freeze a
	# guess into the file; leaving the entries at 3 elements keeps the fallback honest and keeps
	# `migrate()` idempotent.
	if version < 5:
		out["save_version"] = 5

	# v5 -> v6 (habitat-tiers, Task 6): pure version-bump bookkeeping, for the same reason the
	# two steps above are. `arrivals[].count` is additive and `ArrivalQueue.restore()` already
	# reads a missing one as 1, which is exactly what a pre-v6 file's group size always was —
	# uniformly 1, before `HabitatTier.arrival_group_size` existed. Nothing needs inventing here.
	if version < 6:
		out["save_version"] = 6

	# THE SEED IS REPAIRED AT ANY VERSION, and the rule differs by version on purpose:
	#
	#   * **At v1**, `seed` was written as a constant 0 in every file that build ever saved, so
	#     absent, 0 and non-numeric all mean the same thing there — no recoverable seed. All three
	#     are repaired from the world's name (see `seed_from_name()`).
	#   * **At v2 and later**, `seed: 0` is a LEGITIMATE state: the `"none"`/editor path autosaves
	#     0, and `capture(..., 0)` is used directly in tests. Migrating that would be wrong, so
	#     only a seed that is not a number AT ALL is repaired.
	#
	# The v2 half is not hypothetical. `WorldRoot._ready()` casts this field with a bare `int()`,
	# and `int([1, 2])` is not a 0 — it is a runtime "Nonexistent 'int' constructor" that aborts
	# `_ready()` outright, leaving grid, simulation and autosave all null and the scene unplayable.
	# Saves are hand-editable by design, so that is a one-character edit away.
	#
	# **REPAIRED HERE RATHER THAN GUARDED AT THE CAST SITE**, deliberately, and that is the choice
	# between the two available fixes: this is the one place BOTH readers of the field
	# (`WorldRoot._ready()` and `apply()`, which calls `migrate()` again) come through, and it
	# leaves the world running on a real name-derived seed instead of on 0 — the sentinel D-31
	# exists to eliminate. Guarding the cast alone would keep the world playable but silently put
	# it back on the ambiguous value.
	var seed_value: Variant = out.get("seed", null)
	var repair_seed: bool = not is_number(seed_value)
	if version < 2 and not repair_seed and int(seed_value) == 0:
		repair_seed = true
	if repair_seed:
		# TYPE BEFORE CAST on `name` too — see `text_or()`. A non-String name used to abort this
		# function mid-cast, and a `-> Dictionary` that aborts hands its caller an EMPTY dictionary
		# (measured; not a Nil). `WorldRoot._ready()` then took the `saved.is_empty()` branch, never
		# called `apply()` at all, and built a default world while `save_path` was still pointing at
		# the child's file — so `Autosave.attach()` wrote that default world over it. Overwriting is
		# worse than deleting, which is the exact failure an earlier fix wave on this row closed.
		out["seed"] = seed_from_name(text_or(out.get("name", ""), ""))

	# (row 13 adds "mist" and its own migration step here — a v6 -> v7, now that v4 is taken by
	# style_defaults, v5 by the resident-look field of the villager-variety fix, and v6 by
	# habitat-tiers' arrival-group-size count field)
	return out


## The deterministic seed a v1 world gets, derived from its name. Public so the migration rule
## is testable directly rather than only through a whole load.
##
## NEVER 0. `ArrivalQueue._init()` treats a seed of 0 as "randomize", so 0 is a sentinel
## elsewhere in this codebase and reintroducing it here would recreate the ambiguity this
## migration exists to remove. `String.hash()` is deterministic across runs and builds; the
## `| 1` is what keeps an unnamed world (or a name that happens to hash to 0) off the sentinel
## while changing nothing else about the value's distribution.
static func seed_from_name(world_name: String) -> int:
	return int(world_name.hash()) | 1


## Restores `data` into `world`.
##
## THE ORDER IS THE DESIGN, and it must not be rearranged casually:
##
##   1. Terrain and buildings go in FIRST, while `HabitatSimulation` is still detached, so
##      replaying ~1,300 tiles emits `tile_changed` into a world with no listener instead of
##      dirtying the queue ~1,300 times.
##   2. Home sites go in NEXT, in saved (sequence) order, so tile exclusivity tie-breaks come
##      out as they did before the quit.
##   3. PENDING ARRIVALS go in before `mark_all_dirty()`. **THE ORDER IS FOR THE READER, NOT FOR
##      CORRECTNESS** — a claim an earlier version of this comment got wrong, so it is stated
##      plainly. What stops the re-derivation from double-enqueueing is `ArrivalQueue.enqueue()`
##      no-opping on `has_pending(position, species_id)`, and that is ORDER-INDEPENDENT.
##      `mark_all_dirty()` enqueues ZERO arrivals synchronously: it only marks neighbourhoods
##      dirty, and the enqueue happens in a later `tick()` drain, by which point `restore()` has
##      run either way. Swapping steps 3 and 4 was measured to leave both suites green. The order
##      stays as written because restore-then-re-derive reads in the direction the data flows.
##   4. `mark_all_dirty()` re-derives everything the file does not otherwise carry — the dirty
##      queue itself — through the simulation's own event-driven path.
##   5. `GentleDisplacement.reconcile_after_load()` goes LAST, because `mark_all_dirty()` does
##      NOT re-derive an open settlement gesture: the only two paths that open one are
##      `on_edit()` and `on_arrival()`, and a restore reaches neither. See step 9 in the body.
##
## REMOVAL RECEIPTS (v3) ARE NOT PART OF THIS ORDERING AT ALL — `RemovalLedger.restore()` (step
## 3 in the body) neither reads nor is read by any of the five steps above, so it is placed
## right after the grid state it refers to (terrain/buildings) and stays there for a reader's
## sake, not because moving it would break anything.
##
## Called from `WorldRoot._ready()` between building the grid and attaching the simulation.
static func apply(world: WorldRoot, data: Dictionary) -> bool:
	if not can_apply(data):
		push_error("WorldSnapshot: refusing save_version %s" % str(data.get("save_version", "<none>")))
		return false
	data = migrate(data)

	var grid: WorldGrid = world.grid
	# TYPE BEFORE CAST — see `is_number()`. A non-numeric dimension is REFUSED rather than
	# defaulted to the grid's own size, which would silently accept the file and replay its
	# terrain array at a size the file never actually named. That is exactly the half-restored
	# world this function's `save_version` check exists to prevent, arriving by another door.
	if not is_number(data.get("width", grid.width)) or not is_number(data.get("depth", grid.depth)):
		push_error(
			"WorldSnapshot: save names a non-numeric width or depth (%s x %s); refusing rather "
			% [str(data.get("width", "<none>")), str(data.get("depth", "<none>"))]
			+ "than guessing at the grid size."
		)
		return false
	var width: int = int(data.get("width", grid.width))
	var depth: int = int(data.get("depth", grid.depth))
	if width != grid.width or depth != grid.depth:
		push_error("WorldSnapshot: save is %dx%d but the grid is %dx%d." % [
			width, depth, grid.width, grid.depth
		])
		return false

	# EVERY READ BELOW IS TYPE-CHECKED BEFORE ITS CAST — see `array_field()`, `text_or()` and
	# `is_number()`. Saves are hand-editable by design (gdd.md -> Saves), so a String where an
	# array belongs is anticipated input, and an unguarded `as Array` here does not yield an empty
	# array: it aborts this function part-way through, leaving the child in a half-restored world
	# whose simulation never runs while the error text claims they are in a default one.
	# A malformed PART degrades (skipped, with a warning) instead of taking the world down.

	# 1. Terrain. An id no longer in the shipped terrain set falls back to wild grass — the
	#    tag-INERT default, never a tag-emitting one, or a removed terrain would hand the
	#    player capacity they never made. A NON-STRING id takes that same road: `text_or()`
	#    yields "", which matches no shipped terrain, so one warning and one fallback cover both.
	var terrain: Array = array_field(data, "terrain")
	for z in range(depth):
		for x in range(width):
			var index: int = z * width + x
			if index >= terrain.size():
				continue
			var id: String = text_or(terrain[index], "")
			if grid.terrain_definition(id) == null:
				push_warning("Save names unknown terrain `%s`; falling back to wild grass." % id)
				id = WorldGrid.START_TERRAIN_ID
			grid.set_terrain(x, z, id)

	# 2. Buildings, one per footprint origin.
	for entry: Variant in array_field(data, "buildings"):
		if typeof(entry) != TYPE_DICTIONARY:
			push_warning("Save holds a building entry that is not an object; skipped.")
			continue
		var b: Dictionary = entry as Dictionary
		var origin_raw: Array = array_field(b, "origin")
		if origin_raw.size() < 2 or not is_number(origin_raw[0]) or not is_number(origin_raw[1]):
			push_warning("Save holds a building whose `origin` is not [x, z]; skipped.")
			continue
		var origin := Vector2i(int(origin_raw[0]), int(origin_raw[1]))
		var def: PlaceableDefinition = world.buildings.definition(text_or(b.get("id", ""), ""))
		if def == null:
			push_warning("Save names unknown building `%s`; skipped." % str(b.get("id", "")))
			continue
		grid.set_building(origin, def)

	# 3. Removal receipts (v3, bug fix) — see the header's "REMOVAL RECEIPTS JOINED AT v3" note.
	#    Independent of every ordering concern this function's header discusses (nothing else
	#    reads or re-derives a receipt), so it can slot in here, right after the grid state the
	#    receipts refer to is in place, without disturbing steps 4-9 below.
	if world.removals != null:
		var removals_raw: Variant = data.get("removals", {})
		world.removals.restore(removals_raw as Dictionary if typeof(removals_raw) == TYPE_DICTIONARY else {})

	# STYLE DEFAULTS (v4). Same independence as removal receipts above — nothing in the 1-9
	# ordering this function's header documents reads or is read by `style_defaults`, so it slots
	# in here rather than earning its own numbered step. `dict_field()`, not a bare
	# `data.get("style_defaults", {}) as Dictionary`: the latter raises a function-aborting
	# "Invalid cast" on a hand-edited String/Array/number where the dictionary belongs, which is
	# exactly the bug class the rest of this function guards against everywhere else (see
	# `dict_field()`'s own doc comment). A missing or wrong-typed key naturally reads as `{}`,
	# which `WorldRoot.get_style_default()` already treats as "nothing chosen yet" — no further
	# degradation logic is needed here.
	world.style_defaults = dict_field(data, "style_defaults")

	# 4. Wood. `reset` rather than `add`, so a reload is not affected by the starting stockpile.
	#    A non-numeric amount reads as the starting stockpile — the same as an absent key, and the
	#    only harmless answer: refusing the whole file over one field would cost the child a world.
	var wood_raw: Variant = data.get("wood", WoodLedger.STARTING_WOOD)
	if not is_number(wood_raw):
		push_warning("Save names a non-numeric `wood`; the starting stockpile is used instead.")
	world.wood.reset(int(wood_raw) if is_number(wood_raw) else WoodLedger.STARTING_WOOD)

	# 5. Home sites, in saved order — see the sequence note above.
	for entry: Variant in array_field(data, "home_sites"):
		if typeof(entry) != TYPE_DICTIONARY:
			push_warning("Save holds a home site entry that is not an object; skipped.")
			continue
		var s: Dictionary = entry as Dictionary
		var pos_raw: Array = array_field(s, "position")
		if pos_raw.size() < 2 or not is_number(pos_raw[0]) or not is_number(pos_raw[1]):
			push_warning("Save holds a home site whose `position` is not [x, z]; skipped.")
			continue
		var tags: Array[String] = []
		for t: Variant in array_field(s, "structure_tags"):
			if typeof(t) != TYPE_STRING:
				push_warning("Save holds a non-string structure tag; skipped.")
				continue
			tags.append(t as String)
		var positions: Array = []
		# Parallel to `positions`, one entry each, appended in lockstep so a skipped malformed
		# entry cannot shift the looks of every resident after it by one.
		var variants: Array = []
		for p: Variant in array_field(s, "residents"):
			if typeof(p) != TYPE_ARRAY:
				push_warning("Save holds a resident position that is not an array; skipped.")
				continue
			var xyz: Array = p as Array
			if xyz.size() < 3 or not is_number(xyz[0]) or not is_number(xyz[1]) or not is_number(xyz[2]):
				continue
			positions.append(Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2])))
			# A 3-ELEMENT ENTRY IS A PRE-v5 SAVE and is legal forever: it reads as
			# `NO_VARIANT`, which `restore_site()` turns into the old slot-index derivation, so
			# an existing world keeps loading and keeps the looks it already had. A non-numeric
			# 4th element (saves are hand-editable by design) degrades the same way rather than
			# throwing on `int()` — the rule `wood` and `save_version` already follow.
			var look: int = AnimalDefinition.NO_VARIANT
			if xyz.size() >= 4 and is_number(xyz[3]):
				look = int(xyz[3])
			variants.append(look)
		var radius_raw: Variant = s.get("radius", 0)
		world.simulation.restore_site(
			Vector2i(int(pos_raw[0]), int(pos_raw[1])),
			text_or(s.get("species_id", ""), ""),
			int(radius_raw) if is_number(radius_raw) else 0,
			tags,
			positions,
			variants
		)

	# 6. Species Hosted — including species with no surviving home, which sites alone would lose.
	var hosted: Array[String] = []
	for id: Variant in array_field(data, "species_hosted"):
		if typeof(id) != TYPE_STRING:
			push_warning("Save holds a non-string entry in `species_hosted`; skipped.")
			continue
		hosted.append(id as String)
	world.registry.restore_hosted(hosted)

	# 7. PENDING ARRIVALS (v2). BEFORE the re-derivation below — see the ordering note above.
	#
	#    An arrival naming a species no longer in the shipped roster is DROPPED with a warning,
	#    the same degradation rule unknown terrain and unknown buildings already follow: a
	#    partial world beats a crash for a kid, and the warning is how the developer finds out.
	#    Left in, it would reach `_land_or_drop()`, whose `_roster.by_id()` returns null and
	#    which then silently returns — so the drop costs nothing and says so out loud.
	var arrivals: Array = []
	for entry: Variant in array_field(data, "arrivals"):
		if typeof(entry) == TYPE_DICTIONARY:
			var species_id: Variant = (entry as Dictionary).get("species_id", null)
			if typeof(species_id) == TYPE_STRING and world.roster.by_id(species_id as String) == null:
				push_warning("Save names unknown species `%s` in the arrival queue; dropped." % species_id)
				continue
		arrivals.append(entry)
	if world.simulation.arrivals() != null:
		world.simulation.arrivals().restore(arrivals)

	# 8. THE RE-DERIVATION. Everything the file deliberately does not carry is rebuilt here,
	#    through the path an ordinary edit uses: capacity is re-evaluated for every
	#    neighbourhood, and any that supports one more enqueues an arrival — which is a no-op
	#    for a neighbourhood whose arrival step 7 just restored.
	world.simulation.mark_all_dirty()

	# 9. THE SETTLEMENT WINDOW, RE-ARMED (D-32, human ruling 2026-08-02). This is here because
	#    the restore reaches NEITHER of the two paths that ever open a gesture — `on_edit()` and
	#    `on_arrival()` — and step 8 above does not either: `mark_all_dirty()` re-derives capacity
	#    arithmetic and enqueues arrivals, but it opens no window. Without this call a
	#    displacement that was pending when the child quit is silently CANCELLED by the reload,
	#    and the home sits permanently over capacity until some unrelated later edit near it
	#    happens to re-arm a window.
	#
	#    The gesture is NOT in the file; it is re-derived from world state, which is why this is
	#    a call and not a schema field. A healthy world arms nothing — see
	#    `GentleDisplacement.reconcile_after_load()` for the zero this must preserve.
	if world.displacement != null:
		world.displacement.reconcile_after_load()
	return true
