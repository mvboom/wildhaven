class_name HabitatRecipe
extends RefCounted
## WHAT A PLAYER MUST BUILD TO INVITE A SPECIES — derived, never authored.
##
## Pure static selection over data, the same shape `NewsReportContent` uses: nothing here
## mutates a tile, a species or the roster, and nothing holds state. The Field Guide screen,
## the `[?]` route and the onboarding coach all render from this one file, so a roster or
## tag retune is a data edit with no code change anywhere.
##
## TWO GENERATIONS OF THIS FILE'S FUNCTIONS NOW COEXIST, and no live display path calls
## the flat one any more (final review finding C1, 2026-09-04):
##   * `recipe_for()` / `describe()` / `easiest_species()`, directly below, read a species'
##     FLAT fields (`habitat_needs` / `tiles_per_individual`). Retained for
##     `test_habitat_recipe.gd` / `test_field_guide_reachability.gd`, which pin their
##     behaviour directly, and because `AnimalDefinition.effective_tiers()`'s documented
##     migration path still synthesises a tier from those exact flat fields for any future
##     species shipped with no authored `tiers` — but no screen or coach reads them any more.
##   * `recipe_for_tier()` / `describe_tier_needs()` / `easiest_species_by_tier()` (this
##     file's "THE COACH'S OWN PATH" section, further down) and `describe_tiers()` (below
##     that) read `effective_tiers()` — the TIER data, which is what every shipped species'
##     `.tres` actually carries today. The Field Guide (`describe_tiers()`) and the
##     onboarding coach (`easiest_species_by_tier()` + friends) both render from these.
##
## THE ANSWER IS KEYED BY PALETTE BUTTON, NOT BY TAG, AND THAT IS LOAD-BEARING TWICE OVER:
##   * Rock emits both `cover` and `rocks`. Stag needs both, plus `forest`. Grouping by tag
##     would render three chips, two of them the same button.
##   * Capacity counts each tag independently and ONE rock tile qualifies for BOTH, so the
##     merged chip's count is `tiles_per_individual` — grouping by tag would also state a
##     requirement double the real one.
##
## THE COUNT IS EXACT, NOT AN ESTIMATE. Capacity is
## `min over t ( floor(count_t / tiles_per_individual) )`, so one individual needs
## `tiles_per_individual` tiles of EACH need. The copy says "about" for warmth.

## Final review finding #3 ruling: these are NOT independently marked with the `[COPY]`
## literal prefix, even though they are content-writer's and player-facing. Each value here is
## a FRAGMENT composed into `DESCRIBE_LEAD + _join_and(phrases) + "."` below, never rendered on
## its own — `DESCRIBE_LEAD` carries the approved lead-in for the whole assembled sentence,
## so marking the fragments too would put the literal `[COPY]` text once per source in the
## middle of a rendered line ("[COPY] Likes [COPY] woods and [COPY] rocky cover.") instead of
## once at the front of it. One marker per rendered sentence, not one per ingredient.
##
## [COPY] — content-writer's, one phrase per PALETTE BUTTON (not per tag; see the header).
## Keying by button is what keeps this sentence and the chips under it from ever disagreeing,
## and means waking a currently-inert building costs exactly one new entry here.
##
## BARE NOUNS ONLY — NO BAKED-IN ARTICLE ("house", never "a house"). Fix round 2 ruling: this
## dictionary used to hold whatever read naturally as the object of `describe()`'s "Likes "
## sentence, which doesn't care whether its object carries an article or not — so some
## entries got one baked in ("a house", "a farm field") and others didn't ("open grass",
## "woods"). `describe_tiers()`'s two templates DO care, and disagreed with each other: the
## scaling clause ("more X means room for more") never added an article, so a baked-in one
## produced nothing ("more a farm field..."); the gate clause (`_with_article()`) always adds
## one, so a baked-in one produced two ("needs an a house"). Two different bugs, same root
## cause: THE GRAMMAR IS THIS FILE'S JOB, NOT THE CONTENT WRITER'S — a phrase here is a noun,
## full stop, and each template decides for itself whether ITS sentence needs an article in
## front of it. `_need_phrase()` also normalizes any leading article off of whatever it
## returns (`_bare_noun()`), belt-and-suspenders against a future rewording that puts one
## back in here by habit; the entries below are meant to need no normalizing at all.
const SOURCE_PHRASES: Dictionary = {
	"grass": "open grass",
	"forest": "woods",
	"rock": "rocky cover",
	"cultivated_field": "farm field",
	"water": "water nearby",
	"house": "house",
}

## PROPOSED — human owns this. How much a wood cost outweighs raw tile count when ranking
## which species is cheapest to invite. High enough that free terrain always beats anything
## costing wood, so the coach names a starter a player can reach with no stockpile at all.
const WOOD_COST_WEIGHT: float = 10.0


## `{tag: String -> Array[Dictionary]}` — every source that emits each tag, in catalog order.
## A source is `{"id", "resolved_id", "kind", "display_name", "cost"}`. `id` is the PALETTE
## OPTION the player presses: a terrain's own id, or a placeable's `hotbar_category` when it
## has one (so a grouped button like Farm Building is named once, not once per member).
## `resolved_id` is the SPECIFIC thing that actually carries the tag — a terrain's own id
## again, or a specific placeable's own id inside a group. The two agree everywhere except a
## grouped placeable, where they can genuinely differ: `id` says which button to press,
## `resolved_id` says which real building answers this exact tag. `recipe_for()` (below) dedupes
## chips by `id`, matching the palette row's own button-per-press model; `describe_tiers()`
## dedupes by `resolved_id`, because two DIFFERENT buildings behind one button (Cow's `barn`
## and `silo`) must never collapse into a single mention.
##
## FINDING #7'S RULING REVERSED, 2026-09-04 (fix round 1, human-authorized). `display_name`/
## `cost` used to come from the group's CURRENT style default (`world.get_style_default()`),
## on the theory that the chip should describe what pressing the button does RIGHT NOW. That
## was survivable while it was purely a fixture-only edge case (no real placeable's
## `emitted_tags` diverged from its siblings). It stopped being survivable the moment
## `barn.tres`/`open_barn.tres`/`windmill.tres`/`farmhouse.tres` were given real, DIFFERENT
## tags: `farm_building`'s style default resolves alphabetically to Barn, so Horse's `stable`
## (only Open Barn carries it), Sheep's `mill` (only Windmill) and Human's `large_house`
## (only Farmhouse) all mislabeled as "a barn" — and worse, Cow's `barn` AND `silo` needs both
## resolved to the SAME group id and silently deduped to one, erasing the silo requirement
## outright. `display_name`/`cost` now come from the actual tag-emitting placeable, matching
## `resolved_id` — see `test_habitat_recipe.gd`'s `_check_grouped_button_names_the_resolved_member()`
## for the fixture this reverses (rewritten, not deleted, to pin the corrected reading).
static func tag_sources(world: WorldRoot) -> Dictionary:
	var out: Dictionary = {}
	if world == null:
		return out
	for terrain: TerrainDefinition in world.terrain_options():
		for tag: String in terrain.emitted_tags:
			_add_source(out, tag, {
				"id": terrain.id,
				"resolved_id": terrain.id,
				"kind": "terrain",
				"display_name": terrain.display_name,
				"cost": terrain.cost,
			})
	for placeable: PlaceableDefinition in world.placeable_options():
		var button_id: String = placeable.hotbar_category
		if button_id.is_empty():
			button_id = placeable.id
		for tag: String in placeable.emitted_tags:
			_add_source(out, tag, {
				"id": button_id,
				"resolved_id": placeable.id,
				"kind": "placeable",
				"display_name": placeable.display_name,
				"cost": placeable.cost,
			})
	return out


## `{"satisfiable": bool, "entries": Array[Dictionary]}`, one entry per distinct palette
## button: `{"id", "kind", "display_name", "icon_kind", "count", "cost", "tags"}`.
##
## `satisfiable == false` means at least one need has NO source in this world's catalogs, and
## `entries` is then EMPTY BY DESIGN — a half-recipe is worse than an honest "we don't know
## how yet", because a player would build it and wait forever.
static func recipe_for(species: AnimalDefinition, world: WorldRoot) -> Dictionary:
	var result: Dictionary = {"satisfiable": true, "entries": [] as Array[Dictionary]}
	if species == null or world == null:
		result["satisfiable"] = false
		return result

	var sources: Dictionary = tag_sources(world)
	# GDScript dictionaries preserve insertion order, so first-seen catalog order survives
	# to the rendered chip order without a separate sort.
	var by_button: Dictionary = {}

	for tag: String in species.habitat_needs:
		var candidates: Array = sources.get(tag, []) as Array
		if candidates.is_empty():
			result["satisfiable"] = false
			result["entries"] = [] as Array[Dictionary]
			return result
		var chosen: Dictionary = _cheapest(candidates)
		var button_id: String = chosen["id"] as String
		if by_button.has(button_id):
			((by_button[button_id] as Dictionary)["tags"] as Array).append(tag)
			continue
		by_button[button_id] = {
			"id": button_id,
			"kind": chosen["kind"],
			"display_name": chosen["display_name"],
			"icon_kind": TileIcon.kind_for_id(button_id),
			"count": species.tiles_per_individual,
			"cost": chosen["cost"],
			"tags": [tag],
		}

	var entries: Array[Dictionary] = []
	for button_id: String in by_button:
		entries.append(by_button[button_id] as Dictionary)
	result["entries"] = entries
	return result


static func _add_source(out: Dictionary, tag: String, source: Dictionary) -> void:
	if not out.has(tag):
		out[tag] = []
	(out[tag] as Array).append(source)


## Cheapest wins; ties go to catalog order, since the comparison is strictly `<`.
static func _cheapest(candidates: Array) -> Dictionary:
	var best: Dictionary = candidates[0] as Dictionary
	for i in range(1, candidates.size()):
		var candidate: Dictionary = candidates[i] as Dictionary
		if (candidate["cost"] as int) < (best["cost"] as int):
			best = candidate
	return best


## [COPY] — content-writer's. Shown for a species whose needs no buildable thing supplies.
const DESCRIBE_UNKNOWN: String = "[COPY] We don't know how to invite these yet."

## [COPY] — content-writer's. `describe()`'s lead-in. The species name is deliberately absent:
## the card heading already says "Fox", and omitting it means `AnimalDefinition` needs no
## `plural_name` field purely so this sentence can conjugate. Carries the literal `[COPY]`
## prefix (final review finding #3) so the rendered sentence — lead-in plus the `SOURCE_PHRASES`
## fragments joined onto it — reads as an obvious stub rather than finished prose; see the
## `SOURCE_PHRASES` header comment for why the fragments themselves stay unmarked.
const DESCRIBE_LEAD: String = "Likes "

## [COPY] — content-writer's. `%s` is a comma-joined list of species display names. Two full
## sentences, not composed fragments (unlike `DESCRIBE_LEAD`), so each carries its own `[COPY]`
## marker directly.
const AVOIDS_TEMPLATE: String = "Keeps away from %s."


## "Likes woods and rocky cover." — composed over the DEDUPED recipe entries, so a source
## serving two of a species' needs is named once. See the class header.
static func describe(species: AnimalDefinition, world: WorldRoot) -> String:
	var recipe: Dictionary = recipe_for(species, world)
	if not (recipe["satisfiable"] as bool):
		return DESCRIBE_UNKNOWN
	var phrases: Array[String] = []
	for entry: Dictionary in (recipe["entries"] as Array):
		var id: String = entry["id"] as String
		var phrase: String = SOURCE_PHRASES.get(id, "") as String
		if phrase.is_empty():
			# A source with no authored phrase yet (a newly-woken building) degrades to its
			# own display name rather than dropping the requirement out of the sentence. This
			# emits unmarked player-facing text on its own ("barn"), but it sits inside the
			# sentence `DESCRIBE_LEAD` leads ("Likes barn."), so the rendered
			# line still reads as an obvious stub as a whole — final review finding #3, folded
			# into the same ruling as `SOURCE_PHRASES` above: one marker per sentence.
			phrase = (entry["display_name"] as String).to_lower()
		phrases.append(phrase)
	return DESCRIBE_LEAD + _join_and(phrases) + "."


## ---------------------------------------------------------------------------------------
## TIER DESCRIPTIONS — habitat-tiers Task 10.
##
## `describe_tiers()` gives one line per tier, in authoring order (cheapest/lowest-cap
## first by convention — see `HabitatTier`'s own "ORDER IS PRESENTATIONAL ONLY" note, which
## is exactly why order is safe to lean on here for presentation even though the capacity
## formula itself never does). Read together, line 1 is "what you have now" and line 2 is
## "what the NEXT tier on top of it needs" — the entire payoff of the habitat-tiers branch:
## without this, nothing tells a player that adding a stable turns a pair of horses into a
## herd (spec.md -> Screen Layouts).
##
## TIER IDS NEVER APPEAR. `HabitatTier.id` is "pair"/"herd" — internal only, because
## player-facing tier naming was explicitly ruled out of scope (spec § 13). Every line
## below describes REQUIREMENTS, never the tier's own name.
##
## KEYED BY THE RESOLVED BUILDING (`resolved_id`), NOT THE PALETTE BUTTON (`id`), WHEN A
## `world` IS AVAILABLE — `tag_sources()`'s own doc comment explains the distinction. This
## reads like `recipe_for()`'s "keyed by palette button" discipline (see this file's own
## header) for terrain, where the two agree, but deliberately DIVERGES from it for a grouped
## placeable: Rock supplies both `cover` and `rocks` from the SAME tile, so a tier needing
## both must read as ONE requirement, not two — but Cow needs both `barn` and `silo`, TWO
## DIFFERENT buildings that merely share one palette button, and those must never collapse
## into one. Deduping by `id` (the button) would silently drop the second — the exact
## regression fix round 1 found and this now avoids. `world` defaults to null because the
## one caller wired up so far (the Field Guide card) is not necessarily the only one — a
## future tooltip or a fixture-only test may have no `WorldRoot` to hand. Without one, each
## tag degrades to its own name, spaced out ("open_grass" -> "open grass") — readable, if
## less precise about which real building solves it.
##
## TERRAIN IS DELIBERATELY *NOT* MERGED INTO THE "Grasslands" PALETTE GROUP HERE, even
## though `game_hud.gd` merges Grass/Wild Grass/Meadow/Scrub behind one button to save
## palette-row space (`GameHud.TERRAIN_GROUP_ID`). That merge is COSMETIC, not data:
## `TerrainDefinition` itself carries no `hotbar_category` field the way `PlaceableDefinition`
## does (`game_hud.gd`'s own header: "ONE DELIBERATE DIFFERENCE"), so `tag_sources()` above
## never learns about it, and this function follows `tag_sources()`'s lead rather than
## re-deriving the merge from `GameHud`'s hardcoded id list. `open_grass` (Grass or Meadow)
## and `browse` (Scrub) are satisfied by placing DIFFERENT tiles even though they currently
## sit behind one button on the palette row — captioning both "Grasslands" would read
## identically for two requirements a player cannot actually solve the same way, which is a
## worse trap than the "three chips for Rock's two tags" one this file's header already
## warns about: Rock's two tags really are the same tile: Grass's and Scrub's are not. So
## Deer's herd tier (`open_grass` AND `browse` together) names both, distinctly, via two
## different resolved buttons — never the same button rendered twice, because at this
## layer they were never the same button to begin with.
##
## `built` NEVER NAMES A SPECIFIC BUILDING. It is the one tag every placeable emits (see
## `AnimalDefinition.BUILDING_TAGS`'s own comment), so a `built` LIMIT reads as "away from
## buildings", not "build one of every building" — see `_describe_limit()`.
##
## Every string this composes is NEW player-facing copy with no prior sign-off, hence the
## single `[COPY]` marker at the front of each line — one per rendered sentence, matching
## the ruling `SOURCE_PHRASES`' own header already established, not one per fragment.
static func describe_tiers(species: AnimalDefinition, world: WorldRoot = null) -> Array[String]:
	var lines: Array[String] = []
	if species == null:
		return lines
	for tier: HabitatTier in species.effective_tiers():
		lines.append(_describe_tier(tier, world))
	return lines


## "[COPY] Up to N: needs ...; more ... means room for more; away from buildings."
static func _describe_tier(tier: HabitatTier, world: WorldRoot) -> String:
	var seen: Dictionary = {}
	var gate_phrases: Array[String] = []
	var scaling_phrases: Array[String] = []
	for need: HabitatNeed in tier.needs:
		var phrase: String = _need_phrase(need.tag, world, seen)
		if phrase.is_empty():
			continue
		if need.is_gate_only():
			gate_phrases.append(_with_article(phrase))
		else:
			scaling_phrases.append(phrase)

	var clauses: Array[String] = []
	if not gate_phrases.is_empty():
		clauses.append("needs " + _join_and(gate_phrases))
	if not scaling_phrases.is_empty():
		clauses.append("more " + _join_and(scaling_phrases) + " means room for more")
	for limit: HabitatLimit in tier.limits:
		clauses.append(_describe_limit(limit))

	var body: String = "; ".join(clauses) if not clauses.is_empty() else "no requirements yet"
	return "[COPY] Up to %d: %s." % [tier.max_individuals, body]


## The readable phrase for one need's tag, deduped against `seen` by whichever identity
## actually decides whether two needs are solved the SAME way. Keyed on `resolved_id`
## (`tag_sources()`'s own doc comment), NOT `id` — a fix-round-1 correction: `id` is the
## palette BUTTON (e.g. "farm_building"), and Cow needs both `barn` and `silo`, two
## DIFFERENT buildings sharing that one button. Deduping on `id` silently dropped whichever
## of the two was seen second — the exact regression this file's own header now warns
## about. `resolved_id` is the specific building (or terrain, where the two already agree),
## so Rock's `cover` and `rocks` still collapse into one "rocky cover" phrase (both resolve
## to `resolved_id == "rock"`), while Cow's `barn` and `silo` — different buildings, same
## button — both survive. Falls back to the bare tag itself when there is no `world` to
## resolve against, or no source is catalogued for it (an unsourced tag still deserves a
## readable line rather than a blank one; that honesty lives in `recipe_for()`'s
## `satisfiable` flag, not here). Returns "" for an already-seen key, which the caller drops
## instead of rendering the same requirement twice.
static func _need_phrase(tag: String, world: WorldRoot, seen: Dictionary) -> String:
	if world != null:
		var candidates: Array = (tag_sources(world) as Dictionary).get(tag, []) as Array
		if not candidates.is_empty():
			var chosen: Dictionary = _cheapest(candidates)
			var dedup_key: String = chosen["resolved_id"] as String
			if seen.has(dedup_key):
				return ""
			seen[dedup_key] = true
			var phrase: String = SOURCE_PHRASES.get(chosen["id"] as String, "") as String
			if phrase.is_empty():
				phrase = (chosen["display_name"] as String).to_lower()
			return _bare_noun(phrase)
	if seen.has(tag):
		return ""
	seen[tag] = true
	return _bare_noun(tag.replace("_", " "))


## Strips a leading "a ", "an " or "the " (case-insensitively) off `phrase`, if present.
## Fix round 2's structural fix: `SOURCE_PHRASES` is documented as bare nouns, but this is
## the defensive half of that contract, applied at the one point every phrase passes
## through on its way into `describe_tiers()`'s two templates — so a future rewording that
## puts an article back in (out of habit, since `describe()`'s "Likes X" sentence never
## minded one) still cannot reproduce the "needs an a house" / "more a farm field" defects.
## A no-op on every phrase this file produces today, which is already bare.
static func _bare_noun(phrase: String) -> String:
	var lower: String = phrase.to_lower()
	for article: String in ["a ", "an ", "the "]:
		if lower.begins_with(article):
			return phrase.substr(article.length())
	return phrase


## "a stable", "an open barn" — the indefinite article a gate-only need reads with. A plain
## first-letter-is-a-vowel heuristic, adequate for the tag vocabulary this reads over; not a
## general-purpose English rule. Safe to apply unconditionally: every phrase it receives has
## already passed through `_need_phrase()`'s `_bare_noun()` normalization.
static func _with_article(phrase: String) -> String:
	if phrase.is_empty():
		return phrase
	var first: String = phrase.substr(0, 1).to_lower()
	var article: String = "an" if "aeiou".contains(first) else "a"
	return "%s %s" % [article, phrase]


## `built` is emitted by EVERY placeable (`AnimalDefinition.BUILDING_TAGS`'s own comment),
## so a `built` limit is a "how close is too close to ANY building" rule, never a specific
## building's name — resolving it through `tag_sources()`/a palette button the way a NEED
## does would name just one placeable (whichever the catalog happens to list first), which
## reads as "build one of every building" levels of wrong for a rule that is actually about
## keeping distance from all of them. `max_count == 0` (Deer's herd tier — genuinely wild
## land) reads stricter than `max_count >= 1` (Deer's base tier — "a distant cottage is
## tolerated"), because a six-year-old parsing "at most 1" gets no mental picture at all.
## A non-`built` limit (none in the roster today) degrades to a generic phrase naming its
## own tag, since there is no real content yet to justify a bespoke one.
static func _describe_limit(limit: HabitatLimit) -> String:
	if limit.tag == "built":
		return "far from any buildings" if limit.max_count == 0 else "away from buildings"
	return "not too much %s nearby" % limit.tag.replace("_", " ")


## Display names of every species this one keeps distance from, BOTH directions unioned —
## `AnimalDefinition.avoids`' own docstring: "The relation is symmetric at runtime and may be
## declared on either species ... the resolver must union both directions rather than
## trusting one side." Sorted, so the rendered line is stable across runs.
static func avoids_for(species: AnimalDefinition, world: WorldRoot) -> Array[String]:
	var out: Array[String] = []
	if species == null or world == null or world.roster == null:
		return out
	var self_id: String = AnimalDefinition.normalize_id(species.id)
	var ids: Dictionary = {}
	for raw: String in species.avoids:
		ids[AnimalDefinition.normalize_id(raw)] = true
	for other: AnimalDefinition in world.roster.species():
		var other_id: String = AnimalDefinition.normalize_id(other.id)
		if other_id == self_id:
			continue
		for raw: String in other.avoids:
			if AnimalDefinition.normalize_id(raw) == self_id:
				ids[other_id] = true
	for id: String in ids:
		var def: AnimalDefinition = world.roster.by_id(id)
		# A dangling id is inert data, not an error (see `unresolved_avoids()`), so it is
		# simply not named rather than rendered as a raw id the player has never seen.
		if def != null:
			out.append(def.display_name)
	out.sort()
	return out


## The cheapest species to invite — total tiles to place, weighted by what each source costs.
##
## THE ONLY PLACE THIS GAME RANKS SPECIES, and it feeds the coach alone, never the Field
## Guide's list. gdd.md licenses exactly this: the stated pressure valve if kids stall in the
## first 60 seconds is "a more directive nudge, a lower-requirement starter species".
static func easiest_species(world: WorldRoot) -> AnimalDefinition:
	if world == null or world.roster == null:
		return null
	var best: AnimalDefinition = null
	var best_effort: float = INF
	for candidate: AnimalDefinition in world.roster.species():
		var recipe: Dictionary = recipe_for(candidate, world)
		if not (recipe["satisfiable"] as bool):
			continue
		var effort: float = 0.0
		for entry: Dictionary in (recipe["entries"] as Array):
			var count: float = float(entry["count"] as int)
			effort += count * (1.0 + float(entry["cost"] as int) * WOOD_COST_WEIGHT)
		# Strictly `<`, so a tie keeps the earlier roster entry — deterministic run to run.
		if effort < best_effort:
			best_effort = effort
			best = candidate
	return best


## ---------------------------------------------------------------------------------------
## THE COACH'S OWN PATH — final review finding C1 (2026-09-04), NOT a rewrite of
## `recipe_for()` / `describe()` / `easiest_species()` above.
##
## Those three still read `species.habitat_needs` / `species.tiles_per_individual` — the
## flat fields — and stay that way ON PURPOSE: `effective_tiers()`'s documented migration
## path is that a species with NO authored `tiers` synthesises one from those exact flat
## fields (`AnimalDefinition.legacy_tier()`), so the flat fields are still load-bearing for
## any future species that ships without tiers, and `test_habitat_recipe.gd` /
## `test_field_guide_reachability.gd` pin `recipe_for()`'s current behaviour directly.
## Every shipped species today DOES carry authored `tiers`, so rewriting those three
## functions in place would silently change what they mean for every existing caller and
## test at once, not just the coach's — out of scope for this fix. This section is new
## code with no legacy behaviour to preserve, built on `effective_tiers()` from the start.
##
## THE BASE TIER, NOT EVERY TIER. `HabitatTier`'s own header documents authoring order as
## "cheapest/lowest-cap first by convention" (the same convention `describe_tiers()` already
## relies on for presentation), so `effective_tiers()[0]` is the cheapest way in — the one
## worth teaching a first-time player, not a wider/pricier tier further requirements unlock.
##
## 2026-09-04 UPDATE: the coach no longer calls `easiest_species_by_tier()` directly to pick
## WHICH species to teach — it calls `starter_species()`, further down, which prefers the
## human-pinned `PINNED_STARTER_SPECIES_ID` (Rabbit) and only falls back to this function's
## derived ranking if the pinned id goes missing from the roster. `starter_tier()` /
## `recipe_for_tier()` / `describe_tier_needs()` below are unchanged and still do all of the
## actual "what does this species need" work, for whichever species is chosen either way.

## The tier the coach should teach — a species' cheapest (first) tier, or `null` if it has
## none.
static func starter_tier(species: AnimalDefinition) -> HabitatTier:
	if species == null:
		return null
	var tiers: Array[HabitatTier] = species.effective_tiers()
	if tiers.is_empty():
		return null
	return tiers[0]


## `recipe_for()`'s exact shape (satisfiable + deduped, palette-button-keyed entries), over
## a TIER's `needs` instead of a species' flat fields. Deliberately ignores `HabitatLimit`s,
## the same scope `recipe_for()` has always had — a "what to place" answer, not a "where not
## to place it" one; the coach's beat 2 teaches one placement, not an avoidance rule.
static func recipe_for_tier(tier: HabitatTier, world: WorldRoot) -> Dictionary:
	var result: Dictionary = {"satisfiable": true, "entries": [] as Array[Dictionary]}
	if tier == null or world == null or tier.needs.is_empty():
		result["satisfiable"] = false
		return result

	var sources: Dictionary = tag_sources(world)
	var by_button: Dictionary = {}

	for need: HabitatNeed in tier.needs:
		var candidates: Array = sources.get(need.tag, []) as Array
		if candidates.is_empty():
			result["satisfiable"] = false
			result["entries"] = [] as Array[Dictionary]
			return result
		var chosen: Dictionary = _cheapest(candidates)
		var button_id: String = chosen["id"] as String
		if by_button.has(button_id):
			((by_button[button_id] as Dictionary)["tags"] as Array).append(need.tag)
			continue
		by_button[button_id] = {
			"id": button_id,
			"kind": chosen["kind"],
			"display_name": chosen["display_name"],
			"icon_kind": TileIcon.kind_for_id(button_id),
			"count": need.tiles_per_individual,
			"cost": chosen["cost"],
			"tags": [need.tag],
		}

	var entries: Array[Dictionary] = []
	for button_id: String in by_button:
		entries.append(by_button[button_id] as Dictionary)
	result["entries"] = entries
	return result


## `describe()`'s exact "Likes X and Y." composition, over a TIER's needs instead of a
## species' flat fields — same dedup-by-button entries, same `SOURCE_PHRASES` lookup, same
## lead-in, so the coach's wording never drifts from the Field Guide's register.
static func describe_tier_needs(tier: HabitatTier, world: WorldRoot) -> String:
	var recipe: Dictionary = recipe_for_tier(tier, world)
	if not (recipe["satisfiable"] as bool):
		return DESCRIBE_UNKNOWN
	var phrases: Array[String] = []
	for entry: Dictionary in (recipe["entries"] as Array):
		var id: String = entry["id"] as String
		var phrase: String = SOURCE_PHRASES.get(id, "") as String
		if phrase.is_empty():
			phrase = (entry["display_name"] as String).to_lower()
		phrases.append(phrase)
	return DESCRIBE_LEAD + _join_and(phrases) + "."


## The cheapest species to invite, ranked over each species' OWN starter tier —
## `easiest_species()`'s ranking (total tiles weighted by what each source costs), reading
## real tier requirements instead of the flat fields. THE ONLY PLACE THE COACH ranks
## species; feeds beat 2 alone, never the Field Guide's list — `easiest_species()`'s own
## scope note applies here unchanged.
##
## A GATE-ONLY need (`HabitatNeed.GATE_ONLY`, e.g. Horse's `stable`) counts as ONE tile for
## this ranking, not zero: `tiles_per_individual == 0` means "present or not, never
## scaling", not "free". Scoring it at its literal 0 would let an expensive gate building
## (a stable, a barn) vanish from the effort total entirely, understating a domesticated
## species' true cost against a wild one built from free terrain alone — `maxi(..., 1)`
## charges it the one tile it actually costs to place. PROPOSED — human owns this scoring
## call, same as `WOOD_COST_WEIGHT` above.
static func easiest_species_by_tier(world: WorldRoot) -> AnimalDefinition:
	if world == null or world.roster == null:
		return null
	var best: AnimalDefinition = null
	var best_effort: float = INF
	for candidate: AnimalDefinition in world.roster.species():
		var tier: HabitatTier = starter_tier(candidate)
		if tier == null:
			continue
		var recipe: Dictionary = recipe_for_tier(tier, world)
		if not (recipe["satisfiable"] as bool):
			continue
		var effort: float = 0.0
		for entry: Dictionary in (recipe["entries"] as Array):
			var count: float = float(maxi(entry["count"] as int, 1))
			effort += count * (1.0 + float(entry["cost"] as int) * WOOD_COST_WEIGHT)
		# Strictly `<`, so a tie keeps the earlier roster entry — deterministic run to run.
		if effort < best_effort:
			best_effort = effort
			best = candidate
	return best


## THE TUTORIAL'S STARTER SPECIES — human ruling 2026-09-04, named here in data rather than
## derived from `easiest_species_by_tier()`'s cost score.
##
## Real tier data makes Deer the cost-cheapest starter (its tier's needs are free terrain;
## Rabbit's `cultivated` need costs 2 Wood/tile) — correct scoring, wrong lesson. The human's
## reasoning, so a future maintainer honours the intent and not just the id:
##   * Rabbit is Bold; Deer is Shy. A Shy species deliberately spends more time in cover, so a
##     Deer starter would make a child's very first animal the hard one to actually see — a
##     first success has to be visible.
##   * Deer's base tier carries a `!built<=1` limit, teaching a CONSTRAINT first. Rabbit's base
##     tier teaches something purely additive: paint grass, paint a field.
##   * A derived starter silently changes whenever tuning moves (exactly what just happened
##     here) — the tutorial's first species is a design decision and should read as one, not
##     fall out of a score nobody meant to be reading as a curriculum choice.
##
## PROPOSED id, same status as `WOOD_COST_WEIGHT` above: the human owns which species this
## names, not just that one is named. Deliberately a plain roster id, not a `.tres` field or
## a new resource type — `WorldPreset.DEFAULT_PRESET_ID`'s exact shape (a named-default
## constant living beside the code that resolves it), which is the convention this codebase
## already uses for "the one a designer would look here to change."
const PINNED_STARTER_SPECIES_ID: String = "rabbit"


## The species the onboarding coach should teach — `PINNED_STARTER_SPECIES_ID` when the live
## roster still has it, so beat 2 never silently drifts to whatever the cost score currently
## favours. Falls back to `easiest_species_by_tier()`'s derived pick if the pinned id is
## missing (a typo, or the species retired from the roster) — the onboarding path must never
## hard-fail or show an empty coach over a stale id.
static func starter_species(world: WorldRoot) -> AnimalDefinition:
	if world == null or world.roster == null:
		return null
	var pinned: AnimalDefinition = world.roster.by_id(PINNED_STARTER_SPECIES_ID)
	if pinned != null:
		return pinned
	return easiest_species_by_tier(world)


## "a", "a and b", "a, b and c" — Oxford-comma-free, matching the register of the rest of the
## player-facing copy.
static func _join_and(parts: Array[String]) -> String:
	if parts.is_empty():
		return ""
	if parts.size() == 1:
		return parts[0]
	var head: Array[String] = parts.slice(0, parts.size() - 1)
	return ", ".join(head) + " and " + parts[parts.size() - 1]
