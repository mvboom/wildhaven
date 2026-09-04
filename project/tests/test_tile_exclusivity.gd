extends QATestCase
## THE TILE-EXCLUSIVITY RULE — Tier 1 row 6's invariant, and the half that is easiest to get
## subtly wrong.
##
## gdd.md -> Systems in Play -> Habitat Suitability, verbatim: "A tile counts toward at most
## one home site. Where capacity radii overlap, each qualifying tile goes to the **nearest
## home site only, ties to the older site** — two fox dens in one wood split its `forest`
## tiles, and two Houses each keep their own `house` tile. The radius is a real
## land-allocation tradeoff; crowding home sites buys nothing."
##
## SCOPED EXCLUSIVITY (2026-08-17): those two worked examples are actually two different
## rules. "Two fox dens ... split its forest tiles" is SAME-SPECIES exclusivity — a Fox den
## and a Rabbit warren are not rivals and now freely coexist on the same land. "Two Houses
## each keep their own house tile" is exclusivity among STRUCTURES, pooled into one shared
## scope regardless of which species occupies which House. `HomeSiteRegistry.owner_at()`
## therefore takes a scope key: a species id for an ordinary (wild-den) query, or
## `HomeSiteRegistry.STRUCTURE_SCOPE` for a structure-associated one.
##
## Three halves, all asserted here:
##   OWNERSHIP  — `HomeSiteRegistry.rebuild_ownership()` assigns each tile to exactly one
##                site WITHIN A SCOPE: nearest wins, ties to the older (lower `sequence`).
##   ACCOUNTING — `CapacityEvaluator.tag_counts()` honours that assignment, so two
##                overlapping SAME-SCOPE sites SPLIT the contested tiles instead of both
##                counting them. Asserted as a conservation law (countA + countB == the tiles
##                owned), which catches double-counting and dropping in one assertion.
##   SCOPING    — two DIFFERENT-scope sites (different species, or a wild den beside an
##                unrelated structure) do NOT split anything: each counts its full radius
##                independently, and two structures pool into one scope regardless of the
##                species that ends up claiming each one.
##
## THE TIE CASE IS TESTED EXPLICITLY, AND IN BOTH REGISTRATION ORDERS, because "ties to the
## older" is only meaningful if the answer follows the site's AGE and not its position in the
## array or its coordinates.
##
## Run:
##   $GODOT_PATH --headless --path project --import
##   $GODOT_PATH --headless --path project --script res://tests/test_tile_exclusivity.gd

## Two sites 4 tiles apart on the x axis, radius 5 each, so their discs overlap and (12, 10)
## is exactly equidistant from both. Integer geometry throughout — the comparison is on
## squared tile distance, so an exact tie is exact, never a float near-miss.
const SITE_A := Vector2i(10, 10)
const SITE_B := Vector2i(14, 10)
const TIE_TILE := Vector2i(12, 10)
const NEAR_A := Vector2i(11, 10)
const NEAR_B := Vector2i(13, 10)
const RADIUS: int = 5


func _init() -> void:
	begin("tile exclusivity")

	_check_nearest_wins()
	_check_tie_goes_to_the_older_site()
	_check_overlapping_sites_split_the_tiles()
	_check_different_species_do_not_split_tiles()
	_check_prospective_candidate_loses_ties()
	_check_release_and_relocate_reallocate_the_tiles()

	note_expected_pending(
		"REMOVAL / UNDO & REFUND LANDED 2026-07-28 (#16) — there IS a removal API now",
		"The old note here said no player-facing path unregistered a home site, so the "
		+ "reallocation this suite covers could not be driven. That is no longer true: "
		+ "`WorldRoot.remove_at()` takes a building down, and row 10's "
		+ "`HomeSiteRegistry.release()` / `relocate()` move sites out and around. Both are now "
		+ "driven against the exclusivity rules below. The removal POLICY (grace window, "
		+ "recycle, free terrain) is `test_removal_refund.gd`'s."
	)

	finish()


# --- Nearest wins --------------------------------------------------------------------------

func _check_nearest_wins() -> void:
	var registry := HomeSiteRegistry.new()
	# SAME species ("fox") — the header comment's "two fox dens" scenario, actually tested.
	var a: HomeSite = registry.register(SITE_A, "fox", RADIUS)
	var b: HomeSite = registry.register(SITE_B, "fox", RADIUS)

	check_eq(registry.owner_at(NEAR_A, "fox"), a, "a tile nearer site A is owned by A")
	check_eq(registry.owner_at(NEAR_B, "fox"), b, "a tile nearer site B is owned by B")
	check_eq(registry.owner_at(SITE_A, "fox"), a, "a site owns its own tile")
	check_eq(registry.owner_at(SITE_B, "fox"), b, "...and so does the other")

	# Only tiles inside SOME site's radius are claimed at all. Unclaimed is a real state, not
	# a default owner — a prospective candidate counts unclaimed tiles freely.
	check_eq(registry.owner_at(Vector2i(30, 30), "fox"), null,
		"a tile outside every radius is unowned (null), not assigned to the nearest site anyway")
	check_eq(registry.owner_at(Vector2i(10, 16), "fox"), null,
		"a tile just outside A's radius (distance 6 > 5) is unowned")


# --- The tie ------------------------------------------------------------------------------

func _check_tie_goes_to_the_older_site() -> void:
	# Order 1: A registered first, so A is older. Both sites are the SAME species ("fox") —
	# exclusivity only ever contests sites that actually share a scope.
	var forward := HomeSiteRegistry.new()
	var a1: HomeSite = forward.register(SITE_A, "fox", RADIUS)
	var b1: HomeSite = forward.register(SITE_B, "fox", RADIUS)
	check(a1.sequence < b1.sequence, "the first-registered site has the lower sequence")
	check_eq(a1.distance_squared_to(TIE_TILE), b1.distance_squared_to(TIE_TILE),
		"the tie tile really is EQUIDISTANT from both sites (the test is not vacuous)")
	check(forward.owner_at(TIE_TILE, "fox") == a1,
		"TIE -> the OLDER site (registered first) wins",
		"the tile went to the site with sequence %d; older is %d, younger is %d"
			% [forward.owner_at(TIE_TILE, "fox").sequence, a1.sequence, b1.sequence])

	# Order 2: the same two positions, registered the other way round. If the answer followed
	# coordinates, array order, or "the last one wins", this would come out the same as above.
	var reverse := HomeSiteRegistry.new()
	var b2: HomeSite = reverse.register(SITE_B, "fox", RADIUS)
	var a2: HomeSite = reverse.register(SITE_A, "fox", RADIUS)
	check(b2.sequence < a2.sequence, "reversed: the site at B is now the older one")
	check(reverse.owner_at(TIE_TILE, "fox") == b2,
		"TIE, reversed order -> the OLDER site wins again — age decides, not position",
		"the tile went to the site with sequence %d; older is %d, younger is %d"
			% [reverse.owner_at(TIE_TILE, "fox").sequence, b2.sequence, a2.sequence])
	check(reverse.owner_at(TIE_TILE, "fox") != reverse.owner_at(SITE_A, "fox"),
		"...and the two orders really do give different answers (the tie-break is load-bearing)")

	# STRUCTURE POOLING: two Houses, claimed by DIFFERENT species, still tie-break as ONE
	# shared scope — buildings.md's "two Houses each keep their own house tile" holds
	# independent of who lives in each House. A structure site is registered (and ages) from
	# the moment the building is placed, which is what makes the first-placed House the older
	# site here — not the arrival order of whoever eventually claims it.
	var mixed := HomeSiteRegistry.new()
	var house_a: HomeSite = mixed.register_structure(SITE_A, ["house"] as Array[String], RADIUS)
	var house_b: HomeSite = mixed.register_structure(SITE_B, ["house"] as Array[String], RADIUS)
	mixed.claim(house_a, "human", RADIUS)
	mixed.claim(house_b, "husky", RADIUS)
	check(house_a.sequence < house_b.sequence,
		"the first-placed House is older than the second, independent of who claims either")
	check_eq(mixed.owner_at(TIE_TILE, HomeSiteRegistry.STRUCTURE_SCOPE), house_a,
		"TIE between two Houses claimed by DIFFERENT species -> the OLDER House wins — "
		+ "structures pool into one shared scope regardless of occupant species")


# --- Splitting, not double-counting --------------------------------------------------------

func _check_overlapping_sites_split_the_tiles() -> void:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 36, 36)

	# Paint the whole union of both discs as rock, so EVERY tile either site could count is a
	# `cover` tile. Any double-count or drop then shows up as an arithmetic discrepancy.
	var union: Array[Vector2i] = _union_tiles()
	for tile: Vector2i in union:
		grid.set_terrain(tile.x, tile.y, "rock")

	var registry := HomeSiteRegistry.new()
	# SAME species — two dens of one species really do split the land (gdd.md's "two fox
	# dens"). The species id matches the `AnimalDefinition` below, since exclusivity for a
	# non-structure site scopes on `species_id`.
	var a: HomeSite = registry.register(SITE_A, "splitter", RADIUS)
	var b: HomeSite = registry.register(SITE_B, "splitter", RADIUS)
	# Divisor 1 so the counts are readable directly as capacity too.
	var species: AnimalDefinition = _species("splitter", ["cover"] as Array[String], 1, RADIUS)

	var count_a: int = _cover_count(grid, registry, SITE_A, species, a)
	var count_b: int = _cover_count(grid, registry, SITE_B, species, b)

	# The conservation law: every tile in the union belongs to exactly one of them.
	check_eq(count_a + count_b, union.size(),
		"the two sites' counts SUM to the union exactly — no tile counted twice, none dropped")
	check(count_a < union.size(),
		"site A does not count the whole union on its own (it really is sharing)")
	check(count_b < union.size(),
		"site B does not count the whole union on its own")

	# The overlap is non-empty, or the conservation law above would hold trivially.
	var overlap: int = _overlap_tiles().size()
	check(overlap > 0, "the two discs really do overlap (%d contested tiles)" % overlap)

	# A lone site with the same radius over the same painted land counts MORE than it does
	# with a same-species neighbour present. That is the land-allocation tradeoff, measured.
	var solo := HomeSiteRegistry.new()
	var solo_a: HomeSite = solo.register(SITE_A, "splitter", RADIUS)
	var solo_count: int = _cover_count(grid, solo, SITE_A, species, solo_a)
	check(solo_count > count_a,
		"crowding costs: A counts %d alone but only %d beside B — the radius is a real tradeoff"
			% [solo_count, count_a])
	check_eq(solo_count - count_a, _overlap_owned_by(registry, b),
		"exactly the tiles B took (%d of the %d contested) are the ones A lost"
			% [_overlap_owned_by(registry, b), overlap])

	grid.free()


# --- Different species share the land -------------------------------------------------------
# The other half of the scoping rule: species that are NOT rivals for the same purpose (a Fox
# den and a Rabbit warren, or a Cow pasture and a Horse pasture) no longer compete at all, even
# sitting on the exact same overlapping ground the same-species case above splits.

func _check_different_species_do_not_split_tiles() -> void:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 36, 36)
	var union: Array[Vector2i] = _union_tiles()
	for tile: Vector2i in union:
		grid.set_terrain(tile.x, tile.y, "rock")

	var registry := HomeSiteRegistry.new()
	var a: HomeSite = registry.register(SITE_A, "cow", RADIUS)
	var b: HomeSite = registry.register(SITE_B, "horse", RADIUS)
	var cow: AnimalDefinition = _species("cow", ["cover"] as Array[String], 1, RADIUS)
	var horse: AnimalDefinition = _species("horse", ["cover"] as Array[String], 1, RADIUS)

	var count_a: int = _cover_count(grid, registry, SITE_A, cow, a)
	var count_b: int = _cover_count(grid, registry, SITE_B, horse, b)

	# Reference: what each site counts entirely alone, with no other site registered at all.
	var solo_registry_a := HomeSiteRegistry.new()
	var solo_a: HomeSite = solo_registry_a.register(SITE_A, "cow", RADIUS)
	var solo_count_a: int = _cover_count(grid, solo_registry_a, SITE_A, cow, solo_a)

	var solo_registry_b := HomeSiteRegistry.new()
	var solo_b: HomeSite = solo_registry_b.register(SITE_B, "horse", RADIUS)
	var solo_count_b: int = _cover_count(grid, solo_registry_b, SITE_B, horse, solo_b)

	check_eq(count_a, solo_count_a,
		"a Cow site counts exactly as much land beside a Horse site as it would completely "
		+ "alone — different species do not contest the same tiles at all")
	check_eq(count_b, solo_count_b,
		"...and the Horse site is unaffected by the Cow site the same way")
	check(count_a + count_b > union.size(),
		("the two counts exceed the union (%d + %d > %d) — proof of double-counting THE SAME "
			+ "LAND, which is exactly what sharing (not splitting) looks like")
			% [count_a, count_b, union.size()])

	# The same tile, queried in each species' own scope, independently belongs to each site —
	# not a shared owner, not unclaimed, two genuinely separate answers for one tile.
	check_eq(registry.owner_at(TIE_TILE, "cow"), a,
		"in the Cow scope, the tie tile belongs to the (only) Cow site")
	check_eq(registry.owner_at(TIE_TILE, "horse"), b,
		"...and in the Horse scope, the SAME tile independently belongs to the (only) Horse "
		+ "site — two different, non-competing owners for the same ground")

	grid.free()


# --- The prospective candidate --------------------------------------------------------------
# A tile the player just edited is evaluated as a home site nobody lives on yet. It is younger
# than every registered site by construction, so it must lose every distance tie — otherwise a
# player could bleed a settled neighbourhood dry just by tapping next to it. This only applies
# within the candidate's own scope: it contests same-species sites (or, if structure-
# associated, other structures), never an unrelated species' sites.

func _check_prospective_candidate_loses_ties() -> void:
	var grid := WorldGrid.new()
	grid.build(TerrainDefinition.load_all(), 36, 36)
	grid.set_terrain(TIE_TILE.x, TIE_TILE.y, "rock")   # equidistant from A and the candidate
	grid.set_terrain(NEAR_B.x, NEAR_B.y, "rock")       # strictly nearer the candidate

	var registry := HomeSiteRegistry.new()
	# SAME species as the candidate's query — a prospective candidate only ever contests its
	# own species' scope (or the structure scope, if structure-associated).
	var a: HomeSite = registry.register(SITE_A, "prospect", RADIUS)
	var species: AnimalDefinition = _species("prospect", ["cover"] as Array[String], 1, RADIUS)

	var registered: int = _cover_count(grid, registry, SITE_A, species, a)
	var prospective: int = _cover_count(grid, registry, SITE_B, species, null)

	check_eq(registered, 2,
		"the registered site counts both rock tiles — it owns them")
	check_eq(prospective, 1,
		"the prospective candidate counts ONLY the tile it is strictly nearer to")
	check_eq(registry.owner_at(TIE_TILE, "prospect"), a,
		"the contested tile is still owned by the registered site")
	# The tile the candidate counted is inside A's radius and currently owned by A. Counting it
	# is correct and is not theft: STRICTLY nearer wins, and if the candidate ever becomes a
	# real site, `rebuild_ownership()` reassigns that tile to it under the same rule. The
	# asymmetry that matters is the tie, asserted immediately above.
	check_eq(registry.owner_at(NEAR_B, "prospect"), a,
		"the strictly-nearer tile is currently A's — the candidate takes it only by being NEARER")
	check(a.distance_squared_to(NEAR_B) > (SITE_B - NEAR_B).length_squared(),
		"...and it really is strictly nearer the candidate (%d vs %d)"
			% [(SITE_B - NEAR_B).length_squared(), a.distance_squared_to(NEAR_B)])

	# Sanity in the other direction: with no registry at all, the candidate counts everything
	# in radius. Without this, the check above could pass because the counter is simply broken.
	var unclaimed: int = _cover_count(grid, HomeSiteRegistry.new(), SITE_B, species, null)
	check_eq(unclaimed, 2,
		"with no sites registered the same candidate counts BOTH tiles (the counter works)")

	grid.free()


# --- Row 10's two registry moves, against the same rules ---------------------------------------
# `release()` (a family moves away) and `relocate()` (a family moves its home) are the only two
# ways a settled site leaves or changes position. Both must rebuild ownership, or a stale claim
# silently deflates a neighbourhood's capacity — which the player experiences as an animal that
# inexplicably will not move in.

func _check_release_and_relocate_reallocate_the_tiles() -> void:
	var registry := HomeSiteRegistry.new()
	var a: HomeSite = registry.register(SITE_A, "fox", RADIUS)
	var b: HomeSite = registry.register(SITE_B, "fox", RADIUS)

	var a_before: int = _overlap_owned_by(registry, a)
	var b_before: int = _overlap_owned_by(registry, b)
	check(a_before > 0 and b_before > 0,
		"the two overlapping sites start with the contested tiles split %d / %d"
			% [a_before, b_before])
	check_eq(registry.owner_at(TIE_TILE, "fox"), a, "...and the tie tile belongs to the older site")

	# RELEASE — B's family moves away. `structure_remains` is false because a den is not a
	# building, so the site leaves the registry entirely and every tile it held goes back.
	registry.release(b, false)
	check_eq(registry.sites().size(), 1, "RELEASE: the emptied site left the registry")
	var a_after_release: int = _overlap_owned_by(registry, a)
	check(a_after_release > a_before,
		"...and A took over the tiles B was holding (%d -> %d contested tiles)"
			% [a_before, a_after_release])
	check_eq(registry.owner_at(NEAR_B, "fox"), a,
		"...including the tile that used to be strictly nearer B — no stale claim survives")

	# RELOCATE — A moves its home. The site keeps its identity and sequence, and ownership
	# follows it: this is one family that moved, not one that vanished and another that appeared.
	var moved := Vector2i(SITE_A.x, SITE_A.y + 8)
	var sequence_before: int = a.sequence
	registry.relocate(a, moved)
	check_eq(a.position, moved, "RELOCATE: the site is at its new position")
	check_eq(a.sequence, sequence_before,
		"...keeping its sequence, so the tie-break still reads it as the same, older site")
	check_eq(registry.owner_at(SITE_A, "fox"), null,
		"...and the tile it used to stand on is unclaimed again — ownership moved with it")
	check_eq(registry.owner_at(moved, "fox"), a, "...while its new tile is claimed")

	# NON-VACUITY: `owner_at()` still answers for tiles that ARE claimed, so the null above is a
	# reallocation and not a broken index.
	check(registry.owner_at(moved + Vector2i(1, 0), "fox") == a,
		"...and the map is live around it, so the unclaimed reading is a measurement")

	# A structure home is the documented exception: a House left standing stays a home site,
	# ready for the next family, so its tiles are NOT released. It lives in the shared
	# structure scope, not the "fox" scope the two dens above used.
	var house: HomeSite = registry.register_structure(SITE_B, ["house"] as Array[String], RADIUS)
	registry.claim(house, "human", RADIUS)
	check(not house.is_vacant(), "a claimed House is a settled structure home site")
	registry.release(house, true)
	check(registry.any_site_at(SITE_B),
		"RELEASE with the building still standing keeps the site — a House outlives its family")
	check(house.is_vacant(), "...un-claimed rather than removed, and ready for the next family")
	check_eq(registry.owner_at(SITE_B, HomeSiteRegistry.STRUCTURE_SCOPE), house,
		"...still owning its own `house` tile, which is what stops the next villager settling "
		+ "on the field beside it")


# --- helpers --------------------------------------------------------------------------------

func _union_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(SITE_A.x - RADIUS, SITE_B.x + RADIUS + 1):
		for z in range(SITE_A.y - RADIUS, SITE_A.y + RADIUS + 1):
			var tile := Vector2i(x, z)
			if _covers(SITE_A, tile) or _covers(SITE_B, tile):
				out.append(tile)
	return out


func _overlap_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for tile: Vector2i in _union_tiles():
		if _covers(SITE_A, tile) and _covers(SITE_B, tile):
			out.append(tile)
	return out


## Counts tiles this SITE owns within the overlap, resolving the scope key the same way the
## registry itself does (`HomeSiteRegistry._scope_key()`), so this helper never drifts out of
## step with the production scoping rule.
func _overlap_owned_by(registry: HomeSiteRegistry, site: HomeSite) -> int:
	var scope_key: String = HomeSiteRegistry._scope_key(site)
	var total: int = 0
	for tile: Vector2i in _overlap_tiles():
		if registry.owner_at(tile, scope_key) == site:
			total += 1
	return total


func _covers(centre: Vector2i, tile: Vector2i) -> bool:
	var d: Vector2i = tile - centre
	return d.x * d.x + d.y * d.y <= RADIUS * RADIUS


## `cover`'s tile count for a legacy-fielded species (habitat-tiers, task 4): `tag_counts()`
## gained a `tier` parameter, so every call site here resolves the species' own
## `legacy_tier()` and reads back the radius-keyed `count_key()` entry it produces.
## Centralises that boilerplate so the exclusivity assertions below read the same as before.
func _cover_count(
	grid: WorldGrid, registry: HomeSiteRegistry, origin: Vector2i,
	species: AnimalDefinition, self_site: HomeSite
) -> int:
	var counts: Dictionary = CapacityEvaluator.tag_counts(
		grid, registry, origin, species, species.legacy_tier(), self_site
	)
	var key: String = CapacityEvaluator.count_key("cover", species.effective_capacity_radius())
	return int(counts.get(key, -1))


func _species(id: String, needs: Array[String], divisor: int, radius: int) -> AnimalDefinition:
	var def := AnimalDefinition.new()
	def.id = id
	def.display_name = id
	def.habitat_needs = needs
	def.tiles_per_individual = divisor
	def.scout_radius = radius
	return def
