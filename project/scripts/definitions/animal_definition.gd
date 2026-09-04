@tool
class_name AnimalDefinition
extends Resource
## One species entry (villagers included) — see gdd.md -> Data Schemas / Content
## Architecture -> AnimalDefinition.
##
## This is SCHEMA SCAFFOLDING, not per-species content. Adding a species means
## authoring a `.tres` against this contract; it must never mean editing this file.
##
## Nothing here decides tuning. `scout_radius` carries a placeholder default at the
## midpoint of the GDD's stated band; per-species values live in the `.tres` and are
## the human's call.

## The `personality` domain, exactly as gdd.md states it: `Shy | Bold`.
##
## Stored as a self-documenting String rather than an int enum (human ruling, step-8):
## `personality = "Shy"` in a `.tres` reads without a lookup, which serves the GDD's
## "adding content means filling out a data entry, not writing code" promise.
##
## The tradeoff this accepts: a hand-authored `.tres` can hold any string at all, so the
## typo-safety the enum gave for free now has to be earned by `validate()` — see the
## PERSONALITIES check there. The editor dropdown only constrains editor-side authoring.
## Simulation code must compare against these constants, never against bare literals.
const PERSONALITY_SHY: String = "Shy"
const PERSONALITY_BOLD: String = "Bold"
const PERSONALITIES: PackedStringArray = [PERSONALITY_SHY, PERSONALITY_BOLD]

## The shared habitat tag vocabulary. Extending it is a system-wide design decision
## reserved for the human (gdd.md -> Content Pipelines -> Add-a-Terrain, "extra human
## gate"); this list is used only to REPORT unknown tags, never to reject or drop them.
##
## Extended 2026-09-04 by the habitat-tiers ruling. `quiet` was RETIRED: it had no source
## and no consumer, and a `built` limit does its job strictly better because it is actually
## enforced and needs no terrain to emit it.
const HABITAT_TAGS: PackedStringArray = [
	# Terrain-emitted
	"water", "forest", "open_grass", "browse", "cover", "flowers", "sand", "rocks",
	"cultivated", "snow",
	# Building-emitted
	"built", "house", "large_house", "barn", "large_barn", "stable", "coop", "silo", "mill",
	# Resident-emitted
	"people", "deer",
]

## The subset of HABITAT_TAGS emitted by placeables rather than terrain. Used by
## `category()` to tell a Domesticated species (which gates on a building) from a Wild one
## (which does not). `built` is deliberately included: it is emitted by every placeable.
const BUILDING_TAGS: PackedStringArray = [
	"built", "house", "large_house", "barn", "large_barn", "stable", "coop", "silo", "mill",
]

## Category names returned by `category()`.
const CATEGORY_PERSON: String = "person"
const CATEGORY_WILD: String = "wild"
const CATEGORY_DOMESTICATED: String = "domesticated"

## PLACEHOLDER pending Open Question #5 (tag-source mapping) — human owns this. The tags
## that UNTOUCHED revealed land emits.
##
## The inert-land invariant (gdd.md -> Data Schemas; -> D-22): no species may be
## satisfiable by land the player never made, or pushing the mist would hand out free
## habitat and break the no-reward pillar.
##
## MUST BECOME DERIVED. Once terrain definitions carry an emitted-tags mapping, compute
## this from that mapping instead of listing it here. A hardcoded copy silently rots the
## first time emission changes — which is the exact failure this invariant exists to
## prevent. `TerrainDefinition.derive_bare_tags()` is that derivation (over real data it
## returns EMPTY — wild_grass.tres emits nothing); this hardcoded set stays a strict
## SUPERSET of it, so the species-side check below is over-enforced, never under-enforced —
## the safe direction to err for a load-bearing pillar. Reconciling the two (making this
## field read the derivation) is Tier 1 row 6's work, not this task's (test_bare_tags_
## derivation.gd tracks it).
##
## `quiet` RETIRED 2026-09-04 by the habitat-tiers ruling (spec OQ-F): it had no source and
## no consumer, and a `built` `HabitatLimit` does its job strictly better. Retiring it here
## too keeps this constant a subset of `HABITAT_TAGS` — every entry in this array must
## resolve inside the shared vocabulary, and `quiet` no longer does.
const BARE_TAGS: PackedStringArray = ["open_grass"]

## Roster-wide id convention: lowercase bare species name, no spaces. `avoids` entries
## must match this form exactly so a pair resolves symmetrically (gdd.md:207).
const ID_PATTERN: String = "^[a-z][a-z0-9_]*$"

## Prefix marking a field as awaiting human/content-writer sign-off. Makes "clearly
## marked placeholder" machine-detectable so unfinished copy cannot ship silently.
const PLACEHOLDER_MARKER: String = "PLACEHOLDER"

## PLACEHOLDER / GDD baseline — human owns this. gdd.md:354 gives a ~8-12 tile band for
## the home-site scoring radius; 10 is its midpoint, used only when a `.tres` omits the
## field. Every species is expected to override it.
const DEFAULT_SCOUT_RADIUS: int = 10

## PLACEHOLDER — human owns this. Universal carrying capacity (gdd.md -> Habitat
## Suitability) derives local population from habitat: how many qualifying tiles inside
## `capacity_radius` support one individual. No GDD band exists yet, so this default is a
## neutral starting point and every species is expected to override it.
##
## The shipped roster does override it — roster.md's decided table is Human 1, Fox 5,
## Rabbit 4 (-> D-27 #2). This default now applies only to a `.tres` that omits the field.
##
## The habitat-to-individuals CURVE (linear vs. diminishing) is a system-wide decision
## belonging to the capacity evaluator, not to any species — deliberately not a field here.
const DEFAULT_TILES_PER_INDIVIDUAL: int = 12

## The `capacity_radius` value meaning **"follow `scout_radius`"** rather than a radius of
## zero. spec.md and roster.md state v1's default as a RELATION — "equal to `scout_radius`"
## — not as a number, and this constant is what lets the data say the relation instead of a
## copy of it. A copied number would silently stop being equal the first time `scout_radius`
## is retuned (#20 is open), which is the same rot D-26 called out for a hardcoded
## `BARE_TAGS`. Any value >= 1 is an explicit per-species radius and diverges deliberately.
##
## Resolve through `effective_capacity_radius()`; never read `capacity_radius` raw.
const CAPACITY_RADIUS_FOLLOWS_SCOUT: int = 0

## "This resident has no look on record" — a species with an empty `model_scenes`, or a save
## entry written before looks were persisted. Mirrors `VariantBag.NO_VARIANT`; the two are
## the same value on purpose so a bag result can be stored and read back without translation.
const NO_VARIANT: int = -1

## PLACEHOLDER / roster.md baseline — human owns this (#23). roster.md -> Floor
## placeholders: "`max_individuals` ~6". gdd.md calls it "a hard per-home-site cap — a
## readability bound, never the normal-play limit", so a uniform value across the roster is
## a defensible floor: it is not doing per-species tuning work.
##
## Lives here rather than in `CapacityEvaluator` (-> D-27 #1): the cap is a property of the
## species, and a module constant in the evaluator is exactly the code-overrules-contract
## defect that ruling closed.
const DEFAULT_MAX_INDIVIDUALS: int = 6

## Unique species id. Lowercase bare species name (`fox`, `rabbit`, `human`).
@export var id: String = ""

## Player-facing name (`Fox`).
@export var display_name: String = ""

## Required habitat tags, drawn from HABITAT_TAGS. All must be satisfied for a home
## site to score as suitable.
@export var habitat_needs: Array[String] = []

## Visibility trait. One of PERSONALITIES.
@export_enum("Shy", "Bold") var personality: String = PERSONALITY_SHY

## Species ids to keep mutual distance from, in ID_PATTERN form.
##
## Deliberately `Array[String]` and not `Array[AnimalDefinition]`: ids are late-bound by
## a roster lookup that tolerates a miss, so a reference to a species that has no `.tres`
## yet (or never gets one) is inert data, not a broken resource path. See
## `unresolved_avoids()`.
##
## The relation is symmetric at runtime and may be declared on either species (gdd.md:207)
## — the resolver must union both directions rather than trusting one side.
@export var avoids: Array[String] = []

## Can this species live on cultivated land?
@export var farm_tolerant: bool = false

## Radius in tiles over which habitat needs are scored when picking a home site
## (gdd.md:354). Species-specific: "a fox ranges wider than a rabbit".
## TUNING — the human owns the per-species value.
@export_range(1, 32, 1) var scout_radius: int = DEFAULT_SCOUT_RADIUS

## Radius in tiles over which carrying capacity counts qualifying tiles (spec.md ->
## Data Schemas; roster.md). Separate from `scout_radius` by contract — v1's default makes
## the two equal, but they are allowed to diverge per species (#23).
##
## `CAPACITY_RADIUS_FOLLOWS_SCOUT` (0) is the default and means "equal to `scout_radius`",
## expressed as the relation rather than as a duplicated number. Read it through
## `effective_capacity_radius()`.
## TUNING — the human owns the per-species value.
@export_range(0, 32, 1) var capacity_radius: int = CAPACITY_RADIUS_FOLLOWS_SCOUT

## Qualifying tiles inside `capacity_radius` needed to support one individual.
## TUNING — the human owns the per-species value (roster.md's decided table).
@export_range(1, 64, 1) var tiles_per_individual: int = DEFAULT_TILES_PER_INDIVIDUAL

## Hard per-home-site cap on individuals — "a readability bound, never the normal-play
## limit" (gdd.md -> Habitat Suitability). The second term of the capacity formula's outer
## `min`, and the reason an arbitrarily rich neighbourhood still reads legibly.
## TUNING — the human owns the per-species value.
@export_range(1, 64, 1) var max_individuals: int = DEFAULT_MAX_INDIVIDUALS

## Ordered habitat tiers — the ways this species can qualify, each with its own needs,
## limits, population cap and arrival group size. `capacity()` takes the MAX over them.
##
## EMPTY IS LEGAL AND IS THE MIGRATION PATH: a species with no tiers synthesises one from
## the flat `habitat_needs` / `tiles_per_individual` / `max_individuals` fields above, so
## the shipped roster converts one `.tres` at a time and a half-converted roster still runs.
## Read through `effective_tiers()`; never read this array raw.
@export var tiers: Array[HabitatTier] = []

## Tags a RESIDENT of this species contributes to the tile it lives on.
##
## This is what makes `people` an ordinary habitat tag rather than a second mechanic: a
## villager emits `people`, so a pug needing `people/5` is counted by the same formula as
## a fox needing `forest/4`. Deer emit `deer`, which is what gates Stag.
##
## Tags are counted PER INDIVIDUAL, not per home tile — a house holding four villagers
## reads as `people = 4`. See `CapacityEvaluator.tag_counts()`.
##
## Every entry here adds an edge to the graph `HabitatGraph.find_cycle()` checks: a cycle
## would make capacity oscillate forever across the dirty queue.
@export var emits_tags: Array[String] = []

## The 3D model scene variant(s) for this species. A species with one look (most of the
## current roster) carries a single-entry array; a species with several looks (e.g. the
## villager) carries several. Stably picked per resident by `pick_variant()` — never read
## this array directly at spawn time.
@export var model_scenes: Array[PackedScene] = []

## Fact-card copy pool (-> D-47, replacing the old singular `fact_text`). Each entry must
## clear the four-step checklist in gdd.md -> Fact-card content pipeline (approved source ->
## 1-2 sentences -> tone check -> predation check). The game currently reads only index 0
## (see `effective_fact_text()`) — no rotation/UI logic exists yet, so having more than one
## entry is inert until that ships; the field exists now so content generation has somewhere
## real to land in the meantime.
@export var fact_text_pool: Array[String] = []

## News Report copy pool (Tier 1 row 12; spec.md:78 — "a per-animal (or general) text pool
## reusing the fact-card pipeline"). THE SCHEMA GAP tier1-status.md row 12 named: fox, rabbit
## and human copy was written and checklist-passed against `docs/content/*-news-report-pool.md`
## well before this field existed, and had nowhere to live. It lives here now.
##
## Deliberately ONE FLAT POOL, not the four sub-pools (Discovery/hint, Move-in, Ambient,
## Avoidance-relocation, Symmetric-avoids) those source docs organize by firing moment — row
## 12's own Tier 1 depth line ("Per-species pools") names splitting them back out as a later
## purchase, not the floor. Every line here is drawn from the Discovery/hint and Ambient/flavor
## sub-pools only: Move-in already has its own channel (the fact card, row 7), and
## Avoidance-relocation / Symmetric-avoids describe a different trigger (row 9/10's Avoids
## flow) that nothing in this row's thin form fires. Empty is legal — `validate()` does not
## require this field, so a species with no News Report copy yet degrades to simply never
## being pickable by the hint layer, not to a load error.
@export var news_reports: Array[String] = []


## Normalizes a species id to the roster convention. Use at every lookup boundary so a
## hand-authored `"Rabbit"` still resolves to `rabbit` instead of silently missing.
static func normalize_id(raw_id: String) -> String:
	return raw_id.strip_edges().to_snake_case().to_lower()


## The radius carrying capacity actually counts over — `capacity_radius` resolved against
## the sentinel. **Every capacity read must go through this**, never through the raw field,
## or the "follow `scout_radius`" case degrades to a radius of zero (capacity 0 everywhere,
## which reads as "nothing is habitat" rather than as a bug).
func effective_capacity_radius() -> int:
	if capacity_radius == CAPACITY_RADIUS_FOLLOWS_SCOUT:
		return scout_radius
	return capacity_radius


## The fact-card copy the game actually shows — `fact_text_pool[0]`, or `""` if the pool is
## empty. **Every caller must go through this**, never read `fact_text_pool` raw, the same
## contract `effective_capacity_radius()` establishes above (-> D-47).
func effective_fact_text() -> String:
	return fact_text_pool[0] if not fact_text_pool.is_empty() else ""


## `avoids` normalized to the roster convention.
func normalized_avoids() -> Array[String]:
	var out: Array[String] = []
	for entry: String in avoids:
		var norm: String = normalize_id(entry)
		if norm != "" and not out.has(norm):
			out.append(norm)
	return out


## The subset of `avoids` with no matching entry in `known_ids`.
##
## A non-empty result is EXPECTED and legal: a species may declare an avoid-pair against
## a species not yet authored. Callers treat these as no-ops, never as errors — the
## avoids check is runtime spacing behavior, never a move-in gate (gdd.md:203).
func unresolved_avoids(known_ids: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	for entry: String in normalized_avoids():
		if not known_ids.has(entry):
			out.append(entry)
	return out


## The entry in `model_scenes` at `variant_index`, or `null` when there is no such entry.
##
## THE ONE WAY A SPAWNED RESIDENT GETS ITS SCENE. The index comes from `VariantBag` at
## move-in, or from the save file at load — never from a derivation here. Out of range and
## `NO_VARIANT` both return `null` rather than wrapping, so a caller holding a stale index
## (a `.tres` that lost a look since the save was written) is forced to decide what to do
## about it instead of silently being handed somebody else's outfit.
func variant_scene(variant_index: int) -> PackedScene:
	if variant_index < 0 or variant_index >= model_scenes.size():
		return null
	return model_scenes[variant_index]


## THE PRE-FIX DERIVATION, kept alive for exactly one caller: restoring a save written before
## looks were persisted per resident (`WorldSnapshot` save_version < 5, whose `residents`
## entries are 3-element `[x, y, z]` arrays with no look in them).
##
## **Do not use this for anything else.** It is the bug: `index` is a resident's slot within
## its OWN home site's `residents` array, not a global identity, so the first resident at every
## home site in the world derives the same look. With 18 human looks the sequence is
## `0->15, 1->4, 2->14, 3->10, 4->1, 5->9, 6->11, 7->17, 8->10, 9->14` — nearly every villager
## in a world of one- and two-resident homes came out as variant 15, and only 8 of the 18 were
## reachable in the first ten slots at all. `VariantBag` replaced it at the spawn site.
##
## It survives here because an OLD SAVE HAS NO OTHER ANSWER. Re-deriving with it reproduces
## exactly the looks that world already had on screen, which is the only migration that does
## not visibly reshuffle a child's village the first time they open it on the new build.
func legacy_variant_index(index: int) -> int:
	if model_scenes.is_empty():
		return NO_VARIANT
	if model_scenes.size() == 1:
		return 0
	return hash(index) % model_scenes.size()


## Stably picks which of `model_scenes` a resident at `index` shows.
##
## STILL CORRECT, STILL USED, but its meaning narrowed with the variety fix: for a
## single-variant species (most of the roster) it is the whole answer, and for a multi-variant
## species it is now only the OLD-SAVE derivation — see `legacy_variant_index()` for why that
## derivation must not be used at spawn time any more.
##
## Returns `null` if `model_scenes` is empty; returns the sole entry directly (no hashing)
## if there is only one — same two guard clauses as `TerrainDefinition.pick_variant(x, z)`,
## for the same reason (a single-variant species should never pay a hash for a foregone
## conclusion). `TerrainDefinition`'s per-tile hashing is untouched by this fix and remains
## correct: a tile's coordinates ARE its global identity, which is precisely what a resident's
## per-site slot was not.
##
## Placed here, immediately before `validate()`, to mirror `TerrainDefinition`'s own
## ordering exactly — and so this file keeps its fields-then-functions organization rather
## than interrupting the `@export` block mid-way.
func pick_variant(index: int) -> PackedScene:
	return variant_scene(legacy_variant_index(index))


## The tiers capacity actually evaluates — authored tiers, or a single synthesised tier
## built from the legacy flat fields. **Every capacity read must go through this**, the
## same contract `effective_capacity_radius()` establishes for the radius sentinel.
##
## Returns an EMPTY array when the legacy fields cannot form a valid tier (see
## `legacy_tier()`), which correctly yields capacity 0.
func effective_tiers() -> Array[HabitatTier]:
	if not tiers.is_empty():
		return tiers
	var synthesised: HabitatTier = legacy_tier()
	if synthesised == null:
		return []
	return [synthesised]


## Which of the three design categories this species' DATA says it belongs to, or `""`
## when it matches none.
##
## PRECEDENCE MATTERS and is not arbitrary. Person is tested first because Villager emits
## `people` without consuming it, and because Pug and Shiba Inu gate on `house*` and would
## otherwise read as Domesticated. The categories are not disjoint sets; this is an ordered
## test.
func category() -> String:
	var tiers_to_read: Array[HabitatTier] = effective_tiers()
	var needs_people: bool = false
	var has_building_gate: bool = false
	var has_building_need: bool = false
	var has_limit: bool = false
	for tier: HabitatTier in tiers_to_read:
		for need: HabitatNeed in tier.needs:
			if need.tag == "people":
				needs_people = true
			if BUILDING_TAGS.has(need.tag):
				has_building_need = true
				if need.is_gate_only():
					has_building_gate = true
		if not tier.limits.is_empty():
			has_limit = true

	if needs_people or emits_tags.has("people"):
		return CATEGORY_PERSON
	if not has_building_need and has_limit:
		return CATEGORY_WILD
	if has_building_gate:
		return CATEGORY_DOMESTICATED
	return ""


## The single tier equivalent to this species' flat legacy fields, or `null` when they
## cannot form one.
##
## RETURNS NULL WHEN `tiles_per_individual < 1`, and that is load-bearing. The pre-tier
## `capacity_from_counts()` returned 0 for a sub-1 divisor, and `test_capacity_formula.gd`
## pins it. Under the new schema divisor 0 means `GATE_ONLY` — the OPPOSITE meaning — so
## synthesising a tier here would silently convert "unsuitable" into "always qualifies".
##
## Note the radius: every synthesised need is left at `HabitatNeed.RADIUS_FOLLOWS_SCOUT`
## (the sentinel), NOT a baked `effective_capacity_radius()`. This is what makes the cache
## below safe: every consumer of a `HabitatNeed` (`CapacityEvaluator.tag_counts()`,
## `tier_capacity_from_counts()`, and `capacity_from_counts()`'s rekey) resolves the
## sentinel by computing its OWN `fallback` fresh as `effective_capacity_radius()` at call
## time, so a baked concrete radius would go stale the moment `scout_radius` (or
## `capacity_radius`) is retuned after the cache is first populated — and the sentinel
## resolves to exactly the value the pre-tier tile walk used, so behaviour is unchanged.
##
## Cached: the evaluator calls this inside the dirty-queue drain, so it must not allocate
## per call. The sentinel radius is what makes that caching safe rather than stale.
func legacy_tier() -> HabitatTier:
	if tiles_per_individual < 1:
		return null
	if _legacy_tier_cache != null:
		return _legacy_tier_cache
	var tier := HabitatTier.new()
	tier.id = "legacy"
	tier.max_individuals = max_individuals
	tier.arrival_group_size = 1
	var built: Array[HabitatNeed] = []
	for tag: String in habitat_needs:
		var need := HabitatNeed.new()
		need.tag = tag
		need.radius = HabitatNeed.RADIUS_FOLLOWS_SCOUT
		need.tiles_per_individual = tiles_per_individual
		built.append(need)
	tier.needs = built
	_legacy_tier_cache = tier
	return _legacy_tier_cache


## Backing store for `legacy_tier()`. Not exported — it is derived, never authored.
var _legacy_tier_cache: HabitatTier = null


## Non-fatal schema check. Returns human-readable problems; an empty array means clean.
## Never raises and never mutates — a bad entry degrades to a reported warning so one
## malformed `.tres` cannot take down a load.
##
## `known_ids` is optional; pass the roster's ids to also surface unresolved avoids.
func validate(known_ids: PackedStringArray = PackedStringArray()) -> Array[String]:
	var problems: Array[String] = []

	var regex := RegEx.new()
	regex.compile(ID_PATTERN)
	if id.is_empty():
		problems.append("`id` is empty.")
	elif regex.search(id) == null:
		problems.append("`id` \"%s\" breaks the roster convention (lowercase bare species name)." % id)

	if display_name.is_empty():
		problems.append("`display_name` is empty.")

	# Now that `personality` is a free-form String on disk, this is the only thing
	# standing between a hand-authored typo ("shy", "Timid") and silently wrong
	# simulation behavior. It was structurally impossible under the int enum.
	if not PERSONALITIES.has(personality):
		problems.append("`personality` \"%s\" is not one of %s." % [personality, str(PERSONALITIES)])

	if habitat_needs.is_empty():
		problems.append("`habitat_needs` is empty — every species needs at least one tag.")
	for tag: String in habitat_needs:
		if not HABITAT_TAGS.has(tag):
			problems.append("`habitat_needs` tag \"%s\" is not in the shared vocabulary." % tag)

	# THE INERT-LAND INVARIANT (gdd.md -> Data Schemas; -> D-22), now tier-aware.
	# POSITIVE NEEDS ONLY: a `HabitatLimit` may never be what makes a species non-bare,
	# because a limit describes what must be ABSENT and absence is what bare land is made of.
	for tier: HabitatTier in effective_tiers():
		if tier.needs.is_empty():
			continue
		var only_bare: bool = true
		for need: HabitatNeed in tier.needs:
			if not BARE_TAGS.has(need.tag):
				only_bare = false
				break
		if only_bare:
			problems.append(
				"tier \"%s\" is satisfiable by untouched revealed land (bare tags: %s) — breaks the inert-land invariant."
				% [tier.id, str(BARE_TAGS)]
			)

	for entry: String in avoids:
		if normalize_id(entry) != entry:
			problems.append("`avoids` entry \"%s\" is not in id form (expected \"%s\")." % [
				entry, normalize_id(entry)
			])
	if normalized_avoids().has(normalize_id(id)):
		problems.append("`avoids` lists this species itself.")

	# THE RADIUS BAND, replaced 2026-09-04 (spec OQ-B). The old 8-12 band predates
	# per-need radii and would hard-fail this design's own central cases: a barn gate at
	# radius 4 and Stag counting at radius 14. Cost scales as `max_radius^2 * roster *
	# tiers`, so RADIUS_MAX is the performance budget, not a style preference.
	if scout_radius < HabitatNeed.RADIUS_MIN or scout_radius > HabitatNeed.RADIUS_MAX:
		problems.append("`scout_radius` %d is outside the %d-%d band." % [
			scout_radius, HabitatNeed.RADIUS_MIN, HabitatNeed.RADIUS_MAX
		])
	if capacity_radius != CAPACITY_RADIUS_FOLLOWS_SCOUT and (
		capacity_radius < HabitatNeed.RADIUS_MIN or capacity_radius > HabitatNeed.RADIUS_MAX
	):
		problems.append("`capacity_radius` %d is outside the %d-%d band; use %d to follow `scout_radius`." % [
			capacity_radius, HabitatNeed.RADIUS_MIN, HabitatNeed.RADIUS_MAX,
			CAPACITY_RADIUS_FOLLOWS_SCOUT
		])
	if capacity_radius < 0:
		problems.append("`capacity_radius` %d is negative." % capacity_radius)

	if tiles_per_individual < 1:
		problems.append("`tiles_per_individual` %d is below 1 — a species cannot have infinite capacity." % tiles_per_individual)

	if max_individuals < 1:
		problems.append("`max_individuals` %d is below 1 — no home site could hold anybody." % max_individuals)

	if model_scenes.is_empty():
		problems.append("`model_scenes` is empty.")
	else:
		for i in model_scenes.size():
			if model_scenes[i] == null:
				problems.append("`model_scenes[%d]` is null." % i)

	if fact_text_pool.is_empty():
		problems.append("`fact_text_pool` is empty.")
	else:
		for i in range(fact_text_pool.size()):
			if fact_text_pool[i].begins_with(PLACEHOLDER_MARKER):
				problems.append("`fact_text_pool[%d]` is still a placeholder — awaiting step-8 sign-off." % i)

	for tier: HabitatTier in effective_tiers():
		for problem: String in tier.validate():
			problems.append(problem)
		for need: HabitatNeed in tier.needs:
			if not HABITAT_TAGS.has(need.tag):
				problems.append("tier \"%s\" need tag \"%s\" is not in the shared vocabulary." % [tier.id, need.tag])
		for limit: HabitatLimit in tier.limits:
			if not HABITAT_TAGS.has(limit.tag):
				problems.append("tier \"%s\" limit tag \"%s\" is not in the shared vocabulary." % [tier.id, limit.tag])

	for tag: String in emits_tags:
		if not HABITAT_TAGS.has(tag):
			problems.append("`emits_tags` entry \"%s\" is not in the shared vocabulary." % tag)

	# A species matching no category is a WARNING, not an error: it means design intent is
	# unclear, not that the data is broken.
	if category() == "":
		problems.append(
			"matches none of person/wild/domesticated — design intent unclear (warning, not a defect)."
		)

	if not known_ids.is_empty():
		for entry: String in unresolved_avoids(known_ids):
			problems.append("`avoids` entry \"%s\" has no AnimalDefinition yet (non-fatal)." % entry)

	return problems
