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
## `tiles_per_individual` tiles of EACH need — and since 2026-09-08 the Field Guide's tier
## lines say the number out loud rather than hedging it ("5 tiles of open grass for each
## alpaca"). See `describe_tiers()`'s own header for the three defects that rewrite fixed;
## the short version is that a hedge a player cannot plan against is not warmth.
##
## NOTHING IN THIS FILE CARRIES THE `[COPY]` STUB MARKER ANY MORE. Every player-facing
## string here was ruled on: `DESCRIBE_LEAD` and `FieldGuide.HERE_TEMPLATE` on 2026-09-01,
## and `DESCRIBE_UNKNOWN` plus the whole `describe_tiers()` template on 2026-09-08.
## `test_habitat_recipe.gd`'s roster-wide scan asserts the marker never comes back.
##
## Content-writer's, one phrase per PALETTE BUTTON (not per tag; see the header).
## Keying by button is what keeps this sentence and the chips under it from ever disagreeing,
## and means waking a currently-inert building costs exactly one new entry here.
##
## BARE NOUNS ONLY — NO BAKED-IN ARTICLE ("house", never "a house"). Fix round 2 ruling: this
## dictionary used to hold whatever read naturally as the object of `describe()`'s "Likes "
## sentence, which doesn't care whether its object carries an article or not — so some
## entries got one baked in ("a house", "a farm field") and others didn't ("open grass",
## "woods"). `describe_tiers()`'s templates DO care: `_gate_line()` puts an article in front
## of what it gets (`_with_article()`), so a baked-in one produced two ("needs an a house"),
## and `_need_line()` puts a NUMBER in front of it, where an article is simply wrong.
## Same root cause both times: THE GRAMMAR IS THIS FILE'S JOB, NOT THE CONTENT WRITER'S — a
## phrase here is a noun, full stop, and each template decides for itself what belongs in
## front of it. `need_noun()` also normalizes any leading article off of whatever it returns
## (`_bare_noun()`), belt-and-suspenders against a future rewording that puts one back in
## here by habit; the entries below are meant to need no normalizing at all.
##
## THE COUNTED-TILE REWRITE (2026-09-08) CHANGED TWO ENTRIES, and the reason is the same for
## both: these nouns now appear inside "N tiles of X", not only inside "Likes X".
##   * `forest`: "woods" -> "forest". "4 tiles of woods" is not English; "4 tiles of forest"
##     is, and it matches the Terraform palette's own button label ("Forest") — which is the
##     thing a six-year-old has to go find and press. Costs `describe()` the slightly warmer
##     "Likes woods."; the build list is the screen that has to be actionable.
##   * `water`: "water nearby" -> "water". The baked-in "nearby" was a second grammar
##     smuggled into a bare-noun table ("3 tiles of water nearby for each cow"), and every
##     sentence that reads this table already says "nearby" itself when it means to.
const SOURCE_PHRASES: Dictionary = {
	"grass": "open grass",
	"forest": "forest",
	"rock": "rocky cover",
	"cultivated_field": "farm field",
	"water": "water",
	"house": "house",
}

## Content-writer's, one phrase per RESIDENT-EMITTED TAG — the tags `tag_sources()` can never
## resolve, because nothing in the terrain or placeable catalogs emits them. `people` and
## `deer` come from residents living on a tile (`AnimalDefinition.emits_tags`), so there is
## no button to press and no tile to paint: YOU CANNOT BUILD A VILLAGER. Keyed by tag rather
## than by palette button for exactly that reason.
##
## Two jobs, not one. Naming the noun is the obvious one. The other is telling
## `describe_tiers()` that this requirement is ALIVE, which changes two things in the
## rendered line: no "tiles of" (a villager is not a tile), and the whole tier's lead-in
## switches from "build these nearby" to "you'll need these nearby", because a sentence that
## tells a child to build a villager is simply false.
##
## "villagers", not "people" — the roster-wide terminology check (D-19's "kits"/"kittens"
## case). `human.tres`'s `display_name` is "Villager" and the Field Guide row directly above
## these lines says "Villager", so a tier line reading "3 people" would be the only place in
## the game that calls them anything else.
const RESIDENT_PHRASES: Dictionary = {
	"people": "villagers",
	"deer": "deer",
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


## Content-writer's, APPROVED 2026-09-08 (the `[COPY]` stub marker came off with the counted-
## tile rewrite; the wording itself is unchanged). Shown for a species whose needs no
## buildable thing supplies — and it is deliberately an admission rather than a guess: a
## half-recipe is worse than an honest "not yet", because a child would build it and wait
## forever (`recipe_for()`'s `satisfiable` flag, same reasoning). No fail framing, nothing
## the player did wrong, and "yet" keeps the door open.
const DESCRIBE_UNKNOWN: String = "We don't know what makes a good home for these yet."

## Content-writer's, approved 2026-09-01. `describe()`'s and `describe_tier_needs()`'s
## lead-in — still live on the onboarding coach's beat 2, which is why it is here and not
## retired with the rest of the flat-field path. The species name is deliberately absent: the
## card heading already says "Fox", and omitting it means `AnimalDefinition` needs no
## `plural_name` field purely so this sentence can conjugate — the same constraint
## `describe_tiers()`'s own cap sentence works around further down.
const DESCRIBE_LEAD: String = "Likes "

## Content-writer's, approved. `%s` is a comma-joined list of species display names.
##
## THE AVOIDS LINE IS THE ONE PLACE A PREDATOR-PREY DYAD COULD LEAK INTO PLAYER COPY, and it
## does not: it names only the subject species' own comfort ("Keeps away from Rabbit."),
## never an actor and a target, so Fox's card and Rabbit's card say the mirror-image of each
## other and neither says why. That is roster.md -> Compatibility's written position
## verbatim — "names only the relocating animal's own comfort" — and it is what the graph
## check asserts in voice, on top of the symmetry it asserts in data.
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
			# own display name rather than dropping the requirement out of the sentence —
			# "Likes barn." reads a little raw, but a silently-missing requirement is the
			# failure that actually strands a player. The fix for a raw one is one entry in
			# `SOURCE_PHRASES`, not code.
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
## ---------------------------------------------------------------------------------------
## THE COUNTED-TILE REWRITE, 2026-09-08 — human-ruled shape, replacing the one-sentence
## "[COPY] Up to 6: needs an open barn; more open grass and rocky cover means room for more."
## that shipped from Task 10. THREE DEFECTS, and every rule below exists to hold one shut.
##
## 1. IT READ AS "REQUIRED, PLUS SOME OPTIONAL EXTRAS", WHICH IS BACKWARDS. The old sentence
##    split on GATE_ONLY vs. scaling and gave the two halves different grammatical weight —
##    "needs X" against "more Y means room for more". But `CapacityEvaluator.
##    tier_capacity_from_counts()` takes a `min` over EVERY scaling need, and `floor(0 / 6)`
##    is 0: zero rock tiles means zero alpacas no matter how many barns are standing. The
##    old copy told a child the exact opposite of the arithmetic. THE FIX IS STRUCTURAL, not
##    a reword: every need — gate and scaling alike — is now one bullet in ONE list under
##    ONE lead-in ("build these nearby"), with no grammar anywhere that ranks them. There is
##    no "optional" register left in the template to fall into.
## 2. NO NUMBERS. "More" is unplannable. Every count is now rendered, and EVERY COUNT IS
##    INTERPOLATED FROM DATA — `need.tiles_per_individual` and `tier.max_individuals`,
##    never authored into a string. A retune is a `.tres` edit with no copy change, which is
##    the same property `SOURCE_PHRASES` gives tag naming.
## 3. IT NAMED THE CHEAPEST SOURCE AND IMPLIED IT WAS THE ONLY ONE. `_cheapest()` picks Open
##    Barn for `barn`, so Alpaca's card said "an open barn" — while Small Barn and Large Barn
##    work identically. See `_gate_line()` for how the two cases (one true source vs. several
##    interchangeable ones) are now told apart from `tag_sources()` data rather than assumed.
##
## THE COPY MUST BE TRUE TO `tier_capacity_from_counts()`, WHICH IS THE AUTHORITY:
##     capacity = min(tier.max_individuals, over scaling needs: floor(count / divisor))
##     ...and 0 if any limit is exceeded, or any GATE_ONLY need has count < 1.
## Read the rendered block back against that formula and each clause maps to one term: the
## bullets are the needs, "for each <animal>" is the divisor, the limit sentence is the
## zeroing gate, and the cap sentence is `max_individuals`.
##
## MULTI-LINE BY DESIGN — ONE STRING PER TIER, `\n`-SEPARATED. `field_guide.gd` renders one
## `Label` per returned string with `AUTOWRAP_WORD_SMART`, and a Godot `Label` honours a hard
## `\n` inside an autowrapped string, so a bulleted build list needs no UI change at all.
## Returning one string per BULLET instead was considered and rejected: `field_guide.gd`
## would then have no way to tell where one tier's block ends and the next begins, and
## `test_field_guide.gd` compares the rendered `Label` texts against this function's return
## element by element — one element per tier is what keeps that comparison meaningful.
##
## NO PLURAL OF THE SPECIES NAME IS EVER FORMED. `AnimalDefinition` carries no `plural_name`
## (see `DESCRIBE_LEAD`), and deriving one is a trap this roster is full of: sheep/sheep,
## deer/deer, fox/foxes, husky/huskies. Every sentence here is written to need the SINGULAR
## only — "for each sheep", "Room for up to 8 here." — which is why the cap sentence counts
## without naming, and why the human's mock line "Double everything for 2 alpacas" became
## the per-bullet "for each alpaca" instead. Reported as a deviation, not slipped in.
static func describe_tiers(species: AnimalDefinition, world: WorldRoot = null) -> Array[String]:
	var lines: Array[String] = []
	if species == null:
		return lines
	var tiers: Array[HabitatTier] = species.effective_tiers()
	for i in range(tiers.size()):
		# The PREVIOUS tier is passed in so `_describe_tier()` can tell an upgrade ("add a
		# windmill to what you already built") from an alternative ("or build a farmhouse
		# instead") — see `_upgrade_needs()`. `null` for the first tier, which is always a
		# standalone recipe.
		var previous: HabitatTier = null
		if i > 0:
			previous = tiers[i - 1]
		lines.append(_describe_tier(species, tiers[i], previous, world))
	return lines


## Content-writer's. `%s` is the species, articled — "an alpaca", "a shiba inu".
##
## THE LAND IS THE SUBJECT OF THIS SENTENCE, AND THAT IS THE WHOLE POINT (human ruling,
## 2026-09-08, replacing "To invite %s, build these nearby:"). Two problems with "invite".
## It is not the project's word: gdd.md's own success criterion is "an animal genuinely
## MOVES IN", Pillar 4 says "an animal moving in", buildings.md says "a villager moves in
## when its habitat is met", and `DisplacementCopy.MOVE_HUMAN` already ships "moved into a
## house with more room to grow" — the GDD spends "invitation" only on hints ("a hint is an
## invitation, not an assignment"), never on animals. And it inverts the agency the design
## runs on: an invitation makes the player the host and the animal a guest, when what
## actually happens is that the player shapes land and the animal decides. "A good home for
## an alpaca has" states a property of the place, which is what the player can actually
## change.
##
## "GOOD", NOT "RIGHT" — Pillar 1. "The right home" implies a wrong one, and this screen is
## a status indicator, never a target. It also chains into `CAP_MANY` ("Room for up to 6
## here.") as one thought about one place.
##
## ONE FORM, WHERE THERE USED TO BE TWO. The old pair existed solely because "build these
## nearby" is a lie for Husky/Pig/Pug/Sheep/Shiba Inu (`people`) and Stag (`deer`) — no
## amount of tapping the palette builds a villager — so a second lead-in said "you'll need"
## instead. "has" is true of a tile and a villager alike, so the branch is gone. What keeps
## the living requirements honest is `RESIDENT_PHRASES` and `_need_line()`'s "tiles of"
## suppression, which is where that check belonged all along; `test_habitat_recipe.gd`'s
## `_check_resident_needs_are_never_buildable()` still pins it there.
const LEAD: String = "A good home for %s has:"

## Content-writer's. A second tier that is NOT a superset of the first — Horse (its grass
## divisor changes, 6 each to 4 each), Villager (`house` becomes `large_house`), Deer (its
## `built` limit tightens). "Instead" is the load-bearing word: this is a whole separate
## recipe, not something to add on top, and a child who reads it as an addition would build
## the wrong thing.
##
## NO EM DASH, AND NOT FOR TASTE. Same reasoning as `BULLET` below: the project ships no font
## file, `FieldGuide.HERE_TEMPLATE` proves `·` has a glyph in Godot's built-in face, and
## nothing proves `—` does. Every rendered string in this file stays inside ASCII plus that
## one measured codepoint, so a full stop does the work the dash would have.
## Collapsed from a build/need pair for the same reason as `LEAD` above: "another kind of
## good home" is true whether the requirement is a tile or a villager. "Another KIND of"
## carries the load "instead" used to — a different home, not an extension of the one above.
const LEAD_ALT: String = "Or here's another kind of good home:"

## Content-writer's. A second tier that IS the first plus more, with every shared number
## unchanged — Cow (add water), Sheep (add a windmill), Rabbit (add flowers). `%d` is the new
## cap. The cap rides the lead-in here rather than getting its own sentence, because "add
## this AND you get up to six" is one thought, and splitting it invites the reader to treat
## the bullet as decoration again.
const LEAD_ADD_ONE: String = "Add this too, and there's room for up to %d:"
const LEAD_ADD_MANY: String = "Add these too, and there's room for up to %d:"

## Content-writer's. The cap sentence — `HabitatTier.max_individuals`, the outer term of the
## capacity formula. `CAP_ONE`'s `%s` is the bare singular species name.
##
## `CAP_ONE` IS NOT `CAP_MANY` WITH A 1 IN IT. A tier capped at one (Bull's pen, Villager's
## single) must never render "double it" arithmetic or a "for each" divisor, because there
## is no second individual to divide for — `_need_line()` drops the "for each" suffix at
## `max_individuals == 1` for the same reason. gdd.md Pillar 1's indicator test applies to
## both: these state what the land holds, and nothing reads them back or rewards reaching
## them.
const CAP_ONE: String = "Just 1 %s can live here."
const CAP_MANY: String = "Room for up to %d here."

## Content-writer's. One requirement, one bullet. `·` rather than `•` is deliberate and
## measured, not a stylistic preference: the project ships no font file at all, so every
## `Label` renders in Godot's built-in default face, and `FieldGuide.HERE_TEMPLATE`
## ("Resident · %d") is the standing proof that THIS codepoint has a glyph in it. A missing
## glyph would render as tofu at the front of every line on the screen.
const BULLET: String = "· "

## Content-writer's. `%d` is `HabitatNeed.tiles_per_individual` — read from data, never
## authored. `%s` are the noun and then the singular species name.
##
## THE SINGULAR/PLURAL SPLIT IS NOT COSMETIC. Villager's `cultivated/1` renders through
## `NEED_TILES_ONE`; "1 tiles of farm field" is the exact kind of stub-looking artefact that
## makes a child's parent stop trusting the screen.
const NEED_TILES_ONE: String = "1 tile of %s"
const NEED_TILES_MANY: String = "%d tiles of %s"

## Content-writer's. The same count for a RESIDENT-emitted need (`RESIDENT_PHRASES`), which
## has no tiles: "4 deer", "3 villagers". A count of 1 needs no special case here because
## `RESIDENT_PHRASES` is already plural where English wants it to be and invariant where it
## does not ("deer"), and no shipped tier asks for exactly one.
const NEED_LIVING: String = "%d %s"

## Content-writer's. Appended to a scaling bullet wherever the tier can hold more than one —
## this is where the divisor stops being a mystery. `%s` is the singular species name.
const NEED_EACH_SUFFIX: String = " for each %s"

## Content-writer's. The limit sentence, kept OUT of the bullet list on purpose: a bullet
## under "build these nearby" reads as a thing to place, and "build away from buildings" is
## nonsense. `%s` is `_describe_limit()`'s phrase, or several joined with "and".
const LIMIT_SENTENCE: String = "Pick a spot %s."


## One tier's whole block. `previous` is the tier rendered directly above this one, or `null`
## for the first — see `_upgrade_needs()` for what it is used for.
static func _describe_tier(
	species: AnimalDefinition, tier: HabitatTier, previous: HabitatTier, world: WorldRoot
) -> String:
	var noun: String = species.display_name.to_lower()
	var shows_each: bool = tier.max_individuals > 1

	# THE UPGRADE CASE, checked first because it renders a DIFFERENT (much shorter) block.
	# Runs against its OWN `seen` dictionary, deliberately: if it renders nothing (every added
	# need deduped away) this function falls through to the full render below, which must
	# start from a clean slate rather than from a half-consumed one.
	var upgrade: Array[HabitatNeed] = _upgrade_needs(tier, previous)
	if not upgrade.is_empty():
		var upgrade_seen: Dictionary = {}
		var added: Array[String] = []
		for need: HabitatNeed in upgrade:
			var bullet: String = _need_line(need, noun, shows_each, world, upgrade_seen)
			if not bullet.is_empty():
				added.append(BULLET + bullet)
		if not added.is_empty():
			var lead_add: String = LEAD_ADD_MANY
			if added.size() == 1:
				lead_add = LEAD_ADD_ONE
			return (lead_add % tier.max_individuals) + "\n" + "\n".join(added)

	# GATES FIRST, THEN SCALING NEEDS — a deliberate re-sort of authoring order (Sheep's
	# flock tier authors its `mill` gate last). A build list is read as an order of
	# operations by anyone under ten: place the one building, then paint the tiles around it.
	# Authoring order is documented as presentational only (`HabitatTier`'s own header), so
	# nothing downstream depends on it.
	var seen: Dictionary = {}
	var gates: Array[String] = []
	var scaling: Array[String] = []
	for need: HabitatNeed in tier.needs:
		var bullet: String = _need_line(need, noun, shows_each, world, seen)
		if bullet.is_empty():
			continue
		if need.is_gate_only():
			gates.append(BULLET + bullet)
		else:
			scaling.append(BULLET + bullet)

	if gates.is_empty() and scaling.is_empty():
		return DESCRIBE_UNKNOWN

	var lead: String = LEAD_ALT
	if previous == null:
		lead = LEAD % _with_article(noun)

	var block: Array[String] = [lead]
	block.append_array(gates)
	block.append_array(scaling)

	var limit_phrases: Array[String] = []
	for limit: HabitatLimit in tier.limits:
		limit_phrases.append(_describe_limit(limit))
	if not limit_phrases.is_empty():
		block.append(LIMIT_SENTENCE % _join_and(limit_phrases))

	if tier.max_individuals == 1:
		block.append(CAP_ONE % noun)
	else:
		block.append(CAP_MANY % tier.max_individuals)
	return "\n".join(block)


## One need, as one bullet's worth of text — no leading `BULLET`, no trailing period.
## Returns "" for a need whose source was already named by an earlier need in this tier
## (`seen`), which the caller drops rather than rendering the same requirement twice.
static func _need_line(
	need: HabitatNeed, noun: String, shows_each: bool, world: WorldRoot, seen: Dictionary
) -> String:
	if need.is_gate_only():
		return _gate_line(need.tag, world, seen)
	var resolved: Dictionary = _resolve_need(need.tag, world, seen)
	if not (resolved["ok"] as bool):
		return ""
	var phrase: String = resolved["phrase"] as String
	var body: String = ""
	if resolved["living"] as bool:
		body = NEED_LIVING % [need.tiles_per_individual, phrase]
	elif need.tiles_per_individual == 1:
		body = NEED_TILES_ONE % phrase
	else:
		body = NEED_TILES_MANY % [need.tiles_per_individual, phrase]
	# The divisor only means something where a second individual can exist; at a cap of one
	# "for each bull" is noise at best and a suggestion that a second bull is coming at worst.
	if not shows_each:
		return body
	return body + (NEED_EACH_SUFFIX % noun)


## THE GATE BULLET, AND THE HONESTY PROBLEM IT EXISTS TO SOLVE. A gate-only need is one
## specific thing to go and place, so unlike a scaling need it has to name a BUILDING — and
## naming the wrong one, or naming one of several as if it were the only one, is the defect
## that put "needs an open barn" on Alpaca's card while a Small Barn worked just as well.
##
## `tag_sources()` already carries everything needed to tell the two cases apart, so this is
## derived, never a hand-maintained list of which tags are "the special ones":
##   * ONE source ("stable" -> Open Barn alone, "mill" -> Windmill, "silo" -> Silo,
##     "large_house" -> Farmhouse): name it. Any hedge here would be a lie in the other
##     direction — nothing but a Windmill satisfies `mill`.
##   * SEVERAL sources sharing a last word ("barn" -> Open Barn, Small Barn, Large Barn):
##     "a barn (any kind)", the human's own wording from the approved mock. The shared word
##     is READ OFF the display names rather than authored, so a fourth barn shipping later
##     changes nothing here, and a tag whose sources do NOT share a word can never
##     accidentally fall into this branch.
##   * SEVERAL sources with nothing in common ("house" -> House, Farmhouse): list them all,
##     joined with "or". Complete and unambiguous; it only gets long if a future tag has
##     many unrelated sources, which no tag does today.
## Terrain-backed gates (none in the roster) fall through to the cheapest source's ordinary
## noun — a gate is a thing you place, and where that thing is a tile the material name is
## already the honest answer.
static func _gate_line(tag: String, world: WorldRoot, seen: Dictionary) -> String:
	var resolved: Dictionary = _resolve_need(tag, world, seen)
	if not (resolved["ok"] as bool):
		return ""
	var sources: Array = resolved["sources"] as Array
	var names: Array[String] = []
	var all_placeable: bool = not sources.is_empty()
	for source: Dictionary in sources:
		if (source["kind"] as String) != "placeable":
			all_placeable = false
			break
		var display: String = _bare_noun((source["display_name"] as String).to_lower())
		if not names.has(display):
			names.append(display)
	if not all_placeable or names.size() < 2:
		return _with_article(resolved["phrase"] as String)

	var shared: String = names[0].get_slice(" ", names[0].get_slice_count(" ") - 1)
	for display: String in names:
		if display.get_slice(" ", display.get_slice_count(" ") - 1) != shared:
			shared = ""
			break
	if not shared.is_empty():
		return "%s (any kind)" % _with_article(shared)

	var articled: Array[String] = []
	for display: String in names:
		articled.append(_with_article(display))
	return _join_or(articled)


## `{"ok", "phrase", "living", "sources"}` for one need's tag, deduped against `seen` by
## whichever identity actually decides whether two needs are solved the SAME way. Keyed on
## `resolved_id` (`tag_sources()`'s own doc comment), NOT `id` — a fix-round-1 correction:
## `id` is the palette BUTTON (e.g. "farm_building"), and Cow needs both `barn` and `silo`,
## two DIFFERENT buildings sharing that one button. Deduping on `id` silently dropped
## whichever of the two was seen second — the exact regression this file's own header warns
## about. `resolved_id` is the specific building (or terrain, where the two already agree),
## so two tags served by one Rock tile still collapse into one "rocky cover" bullet, while
## Cow's `barn` and `silo` — different buildings, same button — both survive.
##
## ONE THING TO WATCH NOW THAT COUNTS ARE VISIBLE: the collapse keeps the FIRST need's
## divisor and drops the second's. That was harmless while the copy said only "more X means
## room for more", and it is still correct for the case it was built for — two tags on one
## tile with the SAME divisor, which is the only shape the roster has ever shipped (Rock's
## retired `cover`+`rocks` pair). Two same-source needs with DIFFERENT divisors would now
## understate one of them. Flagged rather than defended: no live instance exists, and
## `HabitatTier._duplicate_bucket_problems()` already rejects the closest relative of it.
##
## `living` marks a RESIDENT-emitted tag (`RESIDENT_PHRASES`) — `people`, `deer` — which
## `tag_sources()` structurally cannot resolve because no terrain or placeable emits them.
## Falls back to the bare tag, spaced out, when there is no `world` and no resident phrase
## (an unsourced tag still deserves a readable line rather than a blank one; that honesty
## lives in `recipe_for()`'s `satisfiable` flag, not here).
static func _resolve_need(tag: String, world: WorldRoot, seen: Dictionary) -> Dictionary:
	var miss: Dictionary = {"ok": false, "phrase": "", "living": false, "sources": []}
	if world != null:
		var candidates: Array = (tag_sources(world) as Dictionary).get(tag, []) as Array
		if not candidates.is_empty():
			var chosen: Dictionary = _cheapest(candidates)
			var dedup_key: String = chosen["resolved_id"] as String
			if seen.has(dedup_key):
				return miss
			seen[dedup_key] = true
			var phrase: String = SOURCE_PHRASES.get(chosen["id"] as String, "") as String
			if phrase.is_empty():
				phrase = (chosen["display_name"] as String).to_lower()
			return {
				"ok": true,
				"phrase": _bare_noun(phrase),
				"living": false,
				"sources": candidates,
			}
	if seen.has(tag):
		return miss
	seen[tag] = true
	if RESIDENT_PHRASES.has(tag):
		return {
			"ok": true,
			"phrase": RESIDENT_PHRASES[tag] as String,
			"living": true,
			"sources": [],
		}
	return {
		"ok": true,
		"phrase": _bare_noun(tag.replace("_", " ")),
		"living": false,
		"sources": [],
	}


## The needs `tier` adds on top of `previous`, or EMPTY if `tier` is not a clean upgrade of
## it — which is the interesting half of this function, because getting it wrong ships a lie.
##
## "Add a windmill and you get eight sheep" is only true if everything ELSE about the two
## tiers is identical. Three of the roster's five two-tier species pass that bar (Cow adds
## water, Sheep adds a mill, Rabbit adds flowers) and three do not:
##   * HORSE re-tunes a shared need — `open_grass` goes from 6 tiles each to 4, and from
##     radius 8 to radius 14. "Add water" would leave a child building against the old
##     number.
##   * VILLAGER SWAPS a need — `house` becomes `large_house`. Nothing is added at all; a
##     House is replaced by a Farmhouse.
##   * DEER tightens a LIMIT — `built` goes from "at most 1" to "none at all". The needs
##     really are a superset, so a needs-only comparison would call this an upgrade and then
##     silently drop the one requirement that changed.
## So the test is exact on all three axes: same limits, and every previous need matched on
## (tag, radius, divisor) — radius included because Deer's herd tier keeps every divisor and
## moves every radius, which a (tag, divisor) comparison would wave straight through. A tier
## that fails any of it renders in full, under `LEAD_ALT`'s "another kind of good home".
static func _upgrade_needs(tier: HabitatTier, previous: HabitatTier) -> Array[HabitatNeed]:
	var none: Array[HabitatNeed] = []
	if previous == null or tier.max_individuals <= previous.max_individuals:
		return none
	if not _limits_match(tier, previous):
		return none

	var previous_keys: Dictionary = {}
	for need: HabitatNeed in previous.needs:
		previous_keys[_need_key(need)] = true
	var added: Array[HabitatNeed] = []
	var matched: int = 0
	for need: HabitatNeed in tier.needs:
		if previous_keys.has(_need_key(need)):
			matched += 1
		else:
			added.append(need)
	if matched < previous_keys.size():
		return none
	return added


static func _need_key(need: HabitatNeed) -> String:
	return "%s@%d/%d" % [need.tag, need.radius, need.tiles_per_individual]


static func _limits_match(tier: HabitatTier, previous: HabitatTier) -> bool:
	if tier.limits.size() != previous.limits.size():
		return false
	var keys: Dictionary = {}
	for limit: HabitatLimit in previous.limits:
		keys["%s@%d<=%d" % [limit.tag, limit.radius, limit.max_count]] = true
	for limit: HabitatLimit in tier.limits:
		if not keys.has("%s@%d<=%d" % [limit.tag, limit.radius, limit.max_count]):
			return false
	return true


## The bare noun for one tag, with no count, no article and no dedup — the counted-tile
## rewrite's one public seam, so `test_habitat_recipe.gd` can assert that the NUMBER rendered
## beside a noun matches `HabitatNeed.tiles_per_individual` without re-implementing (and
## therefore trivially agreeing with) the sentence templates it is supposed to be checking.
static func need_noun(tag: String, world: WorldRoot) -> String:
	return _resolve_need(tag, world, {})["phrase"] as String


## Strips a leading "a ", "an " or "the " (case-insensitively) off `phrase`, if present.
## Fix round 2's structural fix: `SOURCE_PHRASES` is documented as bare nouns, but this is
## the defensive half of that contract, applied at the one point every phrase passes
## through on its way into `describe_tiers()`'s templates — so a future rewording that puts
## an article back in (out of habit, since `describe()`'s "Likes X" sentence never minded
## one) still cannot reproduce the "needs an a house" defect, nor the counted-tile
## rewrite's own version of it, "5 tiles of a farm field".
## A no-op on every phrase this file produces today, which is already bare.
static func _bare_noun(phrase: String) -> String:
	var lower: String = phrase.to_lower()
	for article: String in ["a ", "an ", "the "]:
		if lower.begins_with(article):
			return phrase.substr(article.length())
	return phrase


## "a stable", "an open barn", "an alpaca" — the indefinite article a gate-only need, or a
## lead-in's species name, reads with. A plain first-letter-is-a-vowel heuristic, adequate
## for the tag and roster vocabulary this reads over; not a general-purpose English rule
## (it would say "an hour" wrong, and "a unicorn" wrong the other way — neither is a word
## this file can reach). Safe to apply unconditionally: every phrase it receives has already
## passed through `_resolve_need()`'s `_bare_noun()` normalization.
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
##
## Content-writer's, and returned as a BARE PHRASE that slots into `LIMIT_SENTENCE` ("Pick a
## spot %s.") — never a sentence of its own, and deliberately never a bullet: a bullet under
## "build these nearby" reads as a thing to go and place, and "build away from buildings" is
## nonsense. This is where the tier's zeroing condition goes, and it must not look optional
## any more than a need does.
static func _describe_limit(limit: HabitatLimit) -> String:
	if limit.tag == "built":
		return "far from any buildings" if limit.max_count == 0 else "away from buildings"
	return "with not much %s nearby" % limit.tag.replace("_", " ")


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


## THE SHARED SEAM — the starter tier's needs as bare prose phrases, for a caller that wants
## the card's numbers in a sentence rather than a bullet list (`NewsReportContent`).
##
## Reads `starter_tier()` — the cheapest way in — never a herd tier, because a hint's job is
## to name a reachable first step, not the best possible outcome.
##
## `shows_each` is FALSE: "4 tiles of forest for each fox, 5 tiles of open grass for each
## fox, 6 tiles of water for each fox" is technically the same information and unreadable as
## one sentence. The divisor is identical to the card's; only the suffix differs.
##
## `seen` threads through exactly as `_describe_tier()` does it, so Cow's `barn` and `silo`
## — two different buildings behind one palette button — both survive here too.
static func starter_need_phrases(species: AnimalDefinition, world: WorldRoot) -> Array[String]:
	var out: Array[String] = []
	if species == null:
		return out
	var tier: HabitatTier = starter_tier(species)
	if tier == null:
		return out
	var noun: String = species.display_name.to_lower()
	var seen: Dictionary = {}
	for need: HabitatNeed in tier.needs:
		var phrase: String = _need_line(need, noun, false, world, seen)
		if not phrase.is_empty():
			out.append(phrase)
	return out


## The starter tier's exclusions, as the same phrases the card's limit sentence is built
## from ("away from buildings", "far from any buildings"). Returned bare, WITHOUT
## `LIMIT_SENTENCE`'s "Pick a spot %s." wrapper, so a caller can fold them into a sentence
## of its own shape.
static func starter_limit_phrases(species: AnimalDefinition) -> Array[String]:
	var out: Array[String] = []
	if species == null:
		return out
	var tier: HabitatTier = starter_tier(species)
	if tier == null:
		return out
	for limit: HabitatLimit in tier.limits:
		out.append(_describe_limit(limit))
	return out


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


## `_join_and()`'s other half — "a house or a farmhouse". A gate need with several
## interchangeable sources is an OR, and rendering it with "and" would tell a child to build
## every one of them.
static func _join_or(parts: Array[String]) -> String:
	if parts.is_empty():
		return ""
	if parts.size() == 1:
		return parts[0]
	var head: Array[String] = parts.slice(0, parts.size() - 1)
	return ", ".join(head) + " or " + parts[parts.size() - 1]
