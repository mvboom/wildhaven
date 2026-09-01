class_name HabitatRecipe
extends RefCounted
## WHAT A PLAYER MUST BUILD TO INVITE A SPECIES — derived, never authored.
##
## Pure static selection over data, the same shape `NewsReportContent` uses: nothing here
## mutates a tile, a species or the roster, and nothing holds state. The Field Guide screen,
## the `[?]` route and the onboarding coach all render from this one file, so a roster or
## tag retune is a data edit with no code change anywhere.
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

## [COPY] — content-writer's, one phrase per PALETTE BUTTON (not per tag; see the header).
## Keying by button is what keeps this sentence and the chips under it from ever disagreeing,
## and means waking a currently-inert building costs exactly one new entry here.
const SOURCE_PHRASES: Dictionary = {
	"grass": "open grass",
	"forest": "woods",
	"rock": "rocky cover",
	"cultivated_field": "a farm field",
	"water": "water nearby",
	"house": "a house",
}

## PROPOSED — human owns this. How much a wood cost outweighs raw tile count when ranking
## which species is cheapest to invite. High enough that free terrain always beats anything
## costing wood, so the coach names a starter a player can reach with no stockpile at all.
const WOOD_COST_WEIGHT: float = 10.0


## `{tag: String -> Array[Dictionary]}` — every source that emits each tag, in catalog order.
## A source is `{"id", "kind", "display_name", "cost"}` where `id` is the PALETTE OPTION the
## player presses: a terrain's own id, or a placeable's `hotbar_category` when it has one
## (so a grouped button like Farm Building is named once, not once per member).
static func tag_sources(world: WorldRoot) -> Dictionary:
	var out: Dictionary = {}
	if world == null:
		return out
	for terrain: TerrainDefinition in world.terrain_options():
		for tag: String in terrain.emitted_tags:
			_add_source(out, tag, {
				"id": terrain.id,
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
## `plural_name` field purely so this sentence can conjugate.
const DESCRIBE_LEAD: String = "Likes "

## [COPY] — content-writer's. `%s` is a comma-joined list of species display names.
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
			# own display name rather than dropping the requirement out of the sentence.
			phrase = (entry["display_name"] as String).to_lower()
		phrases.append(phrase)
	return DESCRIBE_LEAD + _join_and(phrases) + "."


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


## "a", "a and b", "a, b and c" — Oxford-comma-free, matching the register of the rest of the
## player-facing copy.
static func _join_and(parts: Array[String]) -> String:
	if parts.is_empty():
		return ""
	if parts.size() == 1:
		return parts[0]
	var head: Array[String] = parts.slice(0, parts.size() - 1)
	return ", ".join(head) + " and " + parts[parts.size() - 1]
