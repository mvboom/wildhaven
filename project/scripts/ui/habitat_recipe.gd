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

## Final review finding #3 ruling: these are NOT independently marked with the `[COPY]`
## literal prefix, even though they are content-writer's and player-facing. Each value here is
## a FRAGMENT composed into `DESCRIBE_LEAD + _join_and(phrases) + "."` below, never rendered on
## its own — `DESCRIBE_LEAD` now carries the `[COPY]` marker for the whole assembled sentence,
## so marking the fragments too would put the literal `[COPY]` text once per source in the
## middle of a rendered line ("[COPY] Likes [COPY] woods and [COPY] rocky cover.") instead of
## once at the front of it. One marker per rendered sentence, not one per ingredient.
##
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
	# Final review finding #7: a grouped button's `display_name`/`cost` must come from the SAME
	# resolution `game_hud.gd::_placeable_group_row()` uses to paint the actual button — the
	# style the player currently has selected via `world.get_style_default(group_key)` — not
	# from whichever group member happened to emit the tag being looked up. Barn and Silo can
	# both carry `hotbar_category = "farm_building"`; if Silo is the resolved default, the
	# button reads "Silo" and places a silo, so the recipe chip must say "Silo ×5", never
	# "Barn ×5", regardless of which member's `emitted_tags` matched. Indexed by id once, up
	# front, so every placeable in this loop can resolve its group's CURRENT member in O(1)
	# rather than re-scanning `placeable_options()` per tag.
	var placeables_by_id: Dictionary = {}
	for placeable: PlaceableDefinition in world.placeable_options():
		placeables_by_id[placeable.id] = placeable

	for placeable: PlaceableDefinition in world.placeable_options():
		var button_id: String = placeable.hotbar_category
		if button_id.is_empty():
			button_id = placeable.id
		var shown: PlaceableDefinition = _resolve_group_member(
			world, button_id, placeables_by_id, placeable
		)
		for tag: String in placeable.emitted_tags:
			_add_source(out, tag, {
				"id": button_id,
				"kind": "placeable",
				"display_name": shown.display_name,
				"cost": shown.cost,
			})
	return out


## The placeable a grouped button actually shows/places right now — mirrors
## `game_hud.gd::_placeable_group_row()`'s own rule exactly (see that function's header):
## `button_id` is either a real placeable's own id (a single-member "group" — House today,
## `hotbar_category` left blank) or a true shared `hotbar_category` (Farm Building), and the
## two are told apart the identical way: a real id is a key in `placeables_by_id` directly, a
## true category is not, and resolves through `world.get_style_default(button_id)` instead.
## Falls back to `member` itself if resolution somehow lands on nothing (a category with no
## style default yet) rather than returning null into a caller that assumes a display name.
static func _resolve_group_member(
	world: WorldRoot, button_id: String, placeables_by_id: Dictionary, member: PlaceableDefinition = null
) -> PlaceableDefinition:
	var resolved_id: String = button_id
	if not placeables_by_id.has(button_id):
		resolved_id = world.get_style_default(button_id)
	var resolved: Variant = placeables_by_id.get(resolved_id, null)
	return (resolved as PlaceableDefinition) if resolved != null else member


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
const DESCRIBE_LEAD: String = "[COPY] Likes "

## [COPY] — content-writer's. `%s` is a comma-joined list of species display names. Two full
## sentences, not composed fragments (unlike `DESCRIBE_LEAD`), so each carries its own `[COPY]`
## marker directly.
const AVOIDS_TEMPLATE: String = "[COPY] Keeps away from %s."


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
			# sentence `DESCRIBE_LEAD` already marks ("[COPY] Likes barn."), so the rendered
			# line still reads as an obvious stub as a whole — final review finding #3, folded
			# into the same ruling as `SOURCE_PHRASES` above: one marker per sentence.
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
