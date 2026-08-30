class_name NeighborhoodPreview
extends RefCounted
## **The live neighborhood preview** — Tier 1 row 6's third thin-form clause, computed.
##
## gdd.md -> The First 60 Seconds, beat 4: "Cause becomes visible. The live preview gives a
## qualitative read (*'this spot is getting cozy for someone'*) — never an `X / Y` fraction,
## which a child reads as a container to fill (#27)."
##
## THIS CLASS CANNOT SHOW A NUMBER, STRUCTURALLY. Open Question #27 decides that the thin
## build ships **qualitative**, and the safest way to honour that is to make the numeric form
## unreachable rather than merely unused: `read()` returns a **band string and nothing else**.
## Capacities and populations are read here, compared here, and discarded here. No caller — no
## label, no future refactor — can render "4 / 6" from what this returns, because the count
## never leaves the function that computed it. That is the point of the design, not an
## accident of it.
##
## THE COST BOUND IS THE OTHER HALF OF THE FEATURE (gdd.md -> Performance: "The live
## neighborhood preview rides the same bound: at cursor rate it computes … touching only home
## sites whose capacity radius contains the cursor — the same `radius × roster` cost shape,
## **never a re-scan**"). Three things enforce it:
##   1. every query this class makes uses **the cursor tile as its origin** — never a sweep, so
##      the tiles touched are `roster × (2r+1)²` and are independent of world size;
##   2. `update()` returns early when the cursor is on the same tile as last time and nothing
##      has changed, so a still cursor costs nothing at all;
##   3. `queries_run` and `last_query_origins` are **public and observable**, the same way
##      `HabitatSimulation.evaluations_run` is, so the bound can be *measured* by a headless
##      check rather than trusted.
##
## IT DESCRIBES THE LAND; IT NEVER ASSIGNS (Pillar 1). The bands below are all statements about
## a place. None of them names a missing tag, a species to aim for, or a next step — a preview
## that said "add three more rock tiles" would be a task list, and this row's invariant is that
## a hint is an invitation.
##
## WHAT IT CANNOT SAY, AND WHY (reported, not faked). gdd.md says the preview "reads the
## qualification system's near-miss summary", which is what makes it meaningful *before*
## anywhere qualifies. **That summary does not exist** — it is row 12 (Discovery) work. With
## `capacity_at()` alone the honest bands are "somewhere here would suit someone" and "not
## yet"; the *interesting* middle — "you are one tile of cover away" — is exactly the
## information the summary carries and is not inferable from a capacity of 0, which reports
## the same 0 for a spot missing one tile and a spot missing everything. `BAND_WILD` is
## therefore deliberately flat, and gets richer for free the day row 12 lands.

## No read yet, or the cursor is not over the world. Nothing is shown.
const BAND_NONE: String = "none"

## No species could make a home here. **This is the band the near-miss summary would split**
## into "nearly" and "not at all"; today it is one flat band (see the header).
const BAND_WILD: String = "wild"

## At least one species could settle here — `capacity(h, S) >= 1`, the qualification
## predicate itself, so the preview and the arrival that follows it can never disagree.
const BAND_WELCOMING: String = "welcoming"

## Somebody's home is already right here.
const BAND_HOME: String = "home"


## Cumulative count of `WorldRoot` reads this preview has made. Public purely so the cost bound
## above can be asserted rather than asserted-about. Never used by the UI.
var queries_run: int = 0

## The tile origins passed to `WorldRoot` during the most recent `read()`. Every entry must be
## the cursor tile; anything else would mean the preview had started scanning.
var last_query_origins: Array[Vector2i] = []

var _tile: Vector2i = Vector2i(-1, -1)
var _band: String = BAND_NONE
var _stale: bool = true


func band() -> String:
	return _band


func tile() -> Vector2i:
	return _tile


## Forgets the current read. Called when the cursor leaves the world or the mode changes, so
## the next hover recomputes instead of showing a stale place's band.
func clear() -> void:
	_tile = Vector2i(-1, -1)
	_band = BAND_NONE
	_stale = true


## Marks the current read out of date without recomputing. Wired to `WorldRoot.tile_changed`:
## a paint under a resting cursor must change what the preview says (beat 4 is exactly that
## moment), but the recompute happens on the next poll, not inside the edit.
func invalidate() -> void:
	_stale = true


## Recomputes the band for `tile` if it needs to be. Returns **true only when the displayed
## band actually changed**, so the HUD is touched on a change and never per poll.
##
## Doing nothing when the tile is unchanged and nothing is stale is what makes "at cursor rate"
## affordable: a cursor resting on a tile costs one Dictionary comparison per poll.
func update(world: WorldRoot, target: Vector2i) -> bool:
	if world == null:
		return false
	if target == _tile and not _stale:
		return false
	_tile = target
	_stale = false
	var next: String = read(world, target)
	if next == _band:
		return false
	_band = next
	return true


## The whole computation: one band, for one tile. **Returns no counts** — see the header.
func read(world: WorldRoot, target: Vector2i) -> String:
	last_query_origins.clear()
	if world == null or not world.has_tile(target.x, target.y):
		return BAND_NONE

	# A world with nobody in it skips the population half entirely — which is the state the
	# First 60 Seconds runs in, so beat 4 pays for capacity only.
	var anyone_home: bool = world.total_residents() > 0
	var welcoming: bool = false

	for species_id: String in species_ids(world):
		if anyone_home:
			_note(target)
			if world.population_at(target.x, target.y, species_id) > 0:
				return BAND_HOME
		elif welcoming:
			# Nobody lives anywhere, so no later species can raise the band above welcoming, and
			# capacity has already answered. Stop — this is the First 60 Seconds' state, and it
			# is the one that must be cheapest.
			break
		if welcoming:
			continue  # the band is settled; skip the expensive half for the rest of the roster
		_note(target)
		if world.capacity_at(target.x, target.y, species_id) >= 1:
			welcoming = true

	return BAND_WELCOMING if welcoming else BAND_WILD


## Every species the simulation qualifies against.
##
## REPORTED API GAP (the same shape as `TapRouter.species_definition()`): `WorldRoot` exposes
## `resident_species_ids()` — the species *already living somewhere* — but nothing that lists
## the roster. The preview needs the roster: at zero residents the resident list is empty, and
## a preview that consulted it would be blank during exactly the beat gdd.md wrote it for.
## Reading `world.roster` (a public field of `world_root.gd`) is the smallest reach that keeps
## **one** roster — a second loader in the UI could disagree with the simulation about which
## species exist. Replace this body with the real accessor when it exists.
static func species_ids(world: WorldRoot) -> Array[String]:
	var out: Array[String] = []
	if world == null:
		return out
	if world.has_method("species_ids"):
		return world.call("species_ids") as Array[String]
	if world.roster == null:
		return out
	for species: AnimalDefinition in world.roster.species():
		out.append(species.id)
	return out


func _note(origin: Vector2i) -> void:
	queries_run += 1
	last_query_origins.append(origin)
