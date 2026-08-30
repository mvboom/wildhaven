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

## The shared habitat tag vocabulary (gdd.md -> Data Schemas -> Shared patterns).
## Extending this vocabulary is a system-wide design decision reserved for the human
## (gdd.md -> Content Pipelines -> Add-a-Terrain, "extra human gate"), so this list is
## used only to REPORT unknown tags — never to reject or drop them at load.
const HABITAT_TAGS: PackedStringArray = [
	"water",
	"forest",
	"open_grass",
	"quiet",
	"cover",
	"flowers",
	"sand",
	"rocks",
	"cultivated",
	"house",
]

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
## prevent.
##
## `quiet` is included deliberately while OQ#5 is open: if bare land turns out not to emit
## it, the invariant is merely stricter than necessary, which is the safe direction to err
## for a load-bearing pillar.
const BARE_TAGS: PackedStringArray = ["open_grass", "quiet"]

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


## Stably picks which of `model_scenes` a resident at `index` shows — the SAME pattern
## `TerrainDefinition.pick_variant(x, z)` uses for tiles, keyed on a resident's index
## within its home site's `residents` array instead of tile coordinates (see this
## species's callers in `habitat_simulation.gd` for why that index is stable across a
## resident's lifetime, including save/load).
##
## Returns `null` if `model_scenes` is empty; returns the sole entry directly (no hashing)
## if there is only one — same two guard clauses as the terrain sibling, for the same
## reason (a single-variant species should never pay a hash for a foregone conclusion).
##
## Placed here, immediately before `validate()`, to mirror `TerrainDefinition`'s own
## ordering exactly — and so this file keeps its fields-then-functions organization rather
## than interrupting the `@export` block mid-way.
func pick_variant(index: int) -> PackedScene:
	if model_scenes.is_empty():
		return null
	if model_scenes.size() == 1:
		return model_scenes[0]
	return model_scenes[hash(index) % model_scenes.size()]


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

	# The inert-land invariant (gdd.md -> Data Schemas; -> D-22). A species whose needs are
	# ALL satisfiable by untouched revealed land would settle ground the player never made,
	# breaking the mist no-reward pillar and the rule that every resident was attracted.
	if not habitat_needs.is_empty():
		var only_bare: bool = true
		for tag: String in habitat_needs:
			if not BARE_TAGS.has(tag):
				only_bare = false
				break
		if only_bare:
			problems.append(
				"`habitat_needs` %s is satisfiable by untouched revealed land (bare tags: %s) — breaks the inert-land invariant." % [str(habitat_needs), str(BARE_TAGS)]
			)

	for entry: String in avoids:
		if normalize_id(entry) != entry:
			problems.append("`avoids` entry \"%s\" is not in id form (expected \"%s\")." % [
				entry, normalize_id(entry)
			])
	if normalized_avoids().has(normalize_id(id)):
		problems.append("`avoids` lists this species itself.")

	if scout_radius < 8 or scout_radius > 12:
		problems.append("`scout_radius` %d sits outside the GDD's ~8-12 tile band (gdd.md:354)." % scout_radius)

	# `capacity_radius` is checked against the SAME band as `scout_radius`, because the band is
	# a statement about how far a neighborhood reaches, not about which system is reading it.
	# The sentinel is exempt: it resolves to `scout_radius`, which is banded one check above.
	if capacity_radius != CAPACITY_RADIUS_FOLLOWS_SCOUT and (capacity_radius < 8 or capacity_radius > 12):
		problems.append("`capacity_radius` %d sits outside the GDD's ~8-12 tile band (gdd.md:354); use %d to follow `scout_radius`." % [
			capacity_radius, CAPACITY_RADIUS_FOLLOWS_SCOUT
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

	if not known_ids.is_empty():
		for entry: String in unresolved_avoids(known_ids):
			problems.append("`avoids` entry \"%s\" has no AnimalDefinition yet (non-fatal)." % entry)

	return problems
