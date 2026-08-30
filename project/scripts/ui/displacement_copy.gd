class_name DisplacementCopy
extends RefCounted
## Gentle Displacement's player-facing strings — Tier 1 row 10's presentation half.
##
## **EVERY STRING IN THIS FILE IS CONTENT-WRITER'S, COPIED VERBATIM** from
## `docs/content/displacement-copy.md` (produced 2026-07-28 against gdd.md -> Systems in Play ->
## Gentle Displacement, and checklist-passed there). Nothing here was written by ui-engineer and
## nothing here may be edited without a content pass. The table below is the rendering layer's
## only vocabulary; `DisplacementNotice` composes, it never phrases.
##
## THIS IS AN INTERIM HOME AND SAYS SO. The handoff doc's "Where this should live" proposes a
## `SpeciesCopy` sub-resource on `AnimalDefinition`, which would close this file **and** the two
## homeless News Report pools with one schema row. `project/scripts/definitions/` and
## `project/data/animals/` are not this dispatch's directories, so the per-species lines sit here
## for now rather than staying homeless for a fourth dispatch. The resolvers below are keyed by
## `species_id`, which is exactly the key an `AnimalDefinition` lookup would use, so moving them
## is a body swap inside three functions and no caller changes.
##
## THE COMPOSITION RULE IS STRUCTURAL, NOT STYLISTIC. A warning is **one lead sentence, then one
## line per affected home**. content-writer built it that way so that "the lead carries the
## player's action and nothing else; no family's line contains the player's action at all" —
## which makes gdd.md's forbidden sentence (the player's tap and a family's hardship together)
## *unwriteable* rather than merely avoided. `warn_line()` therefore never returns a lead and
## `lead()` never returns a family line. Do not merge them.
##
## THE SOLO ONE-SENTENCE FORMS ARE DELIBERATELY ABSENT. The doc supplies them only "if the UI
## cannot render a lead-plus-list panel". It can (`DisplacementNotice`), and the split form is
## the doc's recommended shipping form for every case including a single home, so importing the
## solo forms would only create a second way to be wrong.
##
## REGISTER: **not** the News Report bulletin voice. gdd.md -> Discovery: "The displacement
## warning is deliberately **not** that voice; consent copy must never sound like flavor."
## Departure and relocation are the plain game voice. Nothing here says "please", "poor",
## "sadly" or "are you sure", nothing refers back to a warning afterwards, and no line names a
## habitat tag identifier, another species, or the Avoids relationship.

# --- The lead ------------------------------------------------------------------------------
#
# One per settled gesture. Each names the action and THE PLACE — never a family, never a loss,
# never a count. That is the whole of what the lead discloses; the specifics arrive in the home
# lines, which is what keeps the lead composable over 1..N families.

const LEAD_BUILD: String = "If you build here, this will be a different kind of place."
const LEAD_TERRAFORM: String = "If you change this land, this will be a different kind of place."
const LEAD_REMOVE: String = "If you take this away, this will be a different kind of place."
const LEAD_MIXED: String = "This will be a different kind of place."

## Mode keys for `lead()`. Strings rather than an enum because the mode has to survive the trip
## through a `Dictionary` payload the day `WorldRoot` starts sending one.
const MODE_BUILD: String = "build"
const MODE_TERRAFORM: String = "terraform"
const MODE_REMOVE: String = "remove"
const MODE_MIXED: String = "mixed"

## **`MODE_MIXED` IS WHAT SHIPS, AND THAT IS A DECISION THE COPY DOC ANTICIPATED.**
##
## The three conditional leads are written in the tense of gdd.md's exemplars ("If you build
## here…"), which reads correctly only if the panel opens at the moment of *targeting*. It does
## not: `GentleDisplacement` emits `displacement_warned` at **settlement**, after the grace
## window, and `warning` carries no mode (`{gesture_id, homes, species_ids, read_aloud}` — see
## `WorldRoot`). The doc's instruction for exactly this case: "If the UI fires the warning at
## settlement rather than at the moment of targeting, use `LEAD_MIXED` for every mode — it is
## tense-neutral and already written."
##
## So the shipped lead is tense-neutral, and it costs nothing structurally: `LEAD_MIXED` carries
## no family and no loss either, so the split that makes the forbidden sentence unwriteable is
## unchanged. The other three stay here, reachable and testable, because the day the payload
## carries a mode this is a one-argument change at the call site.
const SHIPPING_MODE: String = MODE_MIXED


## The lead sentence for a settled gesture's mode. Unknown or absent mode -> `LEAD_MIXED`.
static func lead(mode_key: String = SHIPPING_MODE) -> String:
	match mode_key:
		MODE_BUILD:
			return LEAD_BUILD
		MODE_TERRAFORM:
			return LEAD_TERRAFORM
		MODE_REMOVE:
			return LEAD_REMOVE
		_:
			return LEAD_MIXED


# --- Warning: one line per affected home ---------------------------------------------------
#
# Each names the home BY FAMILY, names the habitat, and names somewhere to go. None names the
# player, the player's action, a loss, or a tag identifier. "family" is the roster-wide register
# even at one individual (v1 arrivals are one individual, #7).

const WARN_FOX: String = "The fox family will look for a den with trees and rocks around it."
const WARN_RABBIT: String = (
	"The rabbit family will look for open grass with a cozy spot out of the wind."
)
const WARN_HUMAN_FIELD: String = "The farm family will look for better soil to grow in."
const WARN_HUMAN_HOUSE: String = (
	"The farm family will look for a house of their own with fields around it."
)
const WARN_HUMAN: String = "The farm family will look for a house with good soil around it."
const WARN_GENERIC: String = "The {display_name} family will look for a new home of their own."
const WARN_SHEEP: String = "The Sheep family makes its home in grassy fields and farmland."  # pipeline-generated (2026-08-30, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF
const WARN_PIG: String = "The Pig family's home is open ground with crops."  # pipeline-generated (2026-08-30, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF
const WARN_HORSE: String = "The Horse family lives in grassy fields and gardens."  # pipeline-generated (2026-08-17, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF
const WARN_DEER: String = "The Deer family lives here in open sunny spaces and in the trees."  # pipeline-generated (2026-08-17, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF
const WARN_SHIBA_INU: String = "The Shiba Inu family will need to find a home with open grassy space."  # pipeline-generated (2026-08-17, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF
const WARN_BULL: String = "The Bull family's home has open ground and growing space."  # pipeline-generated (2026-08-17, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF

## Binding-need keys for `warn_line()`'s optional third reading. **Nothing sends these today** —
## see `warn_line()`'s note. They are the habitat-need ids the capacity formula minimises over,
## and they are the only tag identifiers named anywhere in this file, in a lookup key that is
## never rendered.
const NEED_CULTIVATED: String = "cultivated"
const NEED_HOUSE: String = "house"

## The three species gdd.md calls the floor. A floor species falling through to `WARN_GENERIC`
## or `DEPART_GENERIC` is "a defect worth failing a test over" (the handoff doc), so
## `uncovered_floor_species()` exists to make that assertable rather than hoped for.
const FLOOR_SPECIES_IDS: Array[String] = ["human", "fox", "rabbit"]


## The warning line for one affected home.
##
## **`is_structure_home` selects the register, structurally and with no species special-casing.**
## It is true when the home *is* a building — which at the floor is a House, which is what a
## villager family lives in — so it is the condition gdd.md's decided villager voice actually
## keys off, and `DisplacementNotice` never asks what species a villager is.
##
## **`binding_need` IS NOT SENT BY ANYTHING TODAY, and that costs the floor its sharpest line.**
## The handoff doc splits Human three ways because capacity is min-over-needs, so which need fell
## short is computable — "better soil" is simply wrong when what was removed is the House. The
## warning payload exposes `capacity`, `population` and `is_structure_home` but **not the binding
## need**, and `is_structure_home` cannot recover it: it is true whether the family's field was
## cleared or their House was taken down. So the shipped line is `WARN_HUMAN`, which the doc
## names as "the safe fallback if the caller cannot say which need fell short", and it names both
## a house and good soil so it is true under either cause. Reported as an API gap:
## `GentleDisplacement._describe()` already computes the min and could return the argmin for
## free. Until then this argument is dead code kept live by tests, not decoration.
## **NO `if species_id == ...` APPEARS IN THIS FUNCTION.** Every species distinction is a table
## row, so adding a species is data and the villager voice is selected by the shape of its home
## rather than by anyone recognising a villager.
static func warn_line(
	species_id: String, display_name: String, is_structure_home: bool, binding_need: String = ""
) -> String:
	var need_key: String = "%s/%s" % [species_id, binding_need]
	if _WARN_BY_NEED.has(need_key):
		return _WARN_BY_NEED[need_key] as String
	var table: Dictionary = _WARN_STRUCTURE if is_structure_home else _WARN_HOME
	if table.has(species_id):
		return table[species_id] as String
	return _fill(WARN_GENERIC, display_name)


## The **structure-home register**: the family's home *is* a building. `WARN_GENERIC`'s "a new
## home of their own" is already the right shape for it, which is why the fallback needs no
## variant of its own.
const _WARN_STRUCTURE: Dictionary = {
	"human": WARN_HUMAN,
	"fox": WARN_FOX,
	"rabbit": WARN_RABBIT,
	"bull": WARN_BULL,
	"shiba_inu": WARN_SHIBA_INU,
	"deer": WARN_DEER,
	"horse": WARN_HORSE,
	"pig": WARN_PIG,
	"sheep": WARN_SHEEP,
}

## The ordinary-home register: a den, a warren, a patch of ground.
const _WARN_HOME: Dictionary = {
	"human": WARN_HUMAN,
	"fox": WARN_FOX,
	"rabbit": WARN_RABBIT,
	"bull": WARN_BULL,
	"shiba_inu": WARN_SHIBA_INU,
	"deer": WARN_DEER,
	"horse": WARN_HORSE,
	"pig": WARN_PIG,
	"sheep": WARN_SHEEP,
}

## The refinement that only becomes reachable when the payload names the binding need. Keyed
## `"species_id/need"` so it stays a table too. Unreachable today — see `warn_line()`'s note.
const _WARN_BY_NEED: Dictionary = {
	"human/cultivated": WARN_HUMAN_FIELD,
	"human/house": WARN_HUMAN_HOUSE,
}


# --- Departure -----------------------------------------------------------------------------
#
# Plain game voice. "Framed as finding a home elsewhere, never as loss. Destination, not cause."
# Species Hosted and the Field Guide entry are permanent, so nothing here says goodbye. Every
# line names somewhere to go — "a departure string with no destination in it fails the villager
# doctrine and should fail a test."

const DEPART_FOX: String = "The fox family moved away to find a new den in the woods."
const DEPART_RABBIT: String = "The rabbit family moved away to find open grass of their own."
const DEPART_HUMAN: String = "The farm family went off to farm somewhere sunnier."
const DEPART_GENERIC: String = "The {display_name} family moved away to find a new home."
const DEPART_SHEEP: String = "The Sheep family found a home in the pasture."  # pipeline-generated (2026-08-30, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF
const DEPART_PIG: String = "The Pig family found a home with plenty of space and soft ground to explore."  # pipeline-generated (2026-08-30, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF
const DEPART_HORSE: String = "The Horse family found a new home where the grasslands and farmland meet."  # pipeline-generated (2026-08-17, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF
const DEPART_DEER: String = "The Deer family found a new home with tall trees and soft ground for grazing."  # pipeline-generated (2026-08-17, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF
const DEPART_SHIBA_INU: String = "The Shiba Inu family found a new home with a cozy shelter and lots of space to run and play."  # pipeline-generated (2026-08-17, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF
const DEPART_BULL: String = "The Bull family is heading to the Pastures."  # pipeline-generated (2026-08-17, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF

const _DEPART: Dictionary = {
	"fox": DEPART_FOX,
	"rabbit": DEPART_RABBIT,
	"human": DEPART_HUMAN,
	"bull": DEPART_BULL,
	"shiba_inu": DEPART_SHIBA_INU,
	"deer": DEPART_DEER,
	"horse": DEPART_HORSE,
	"pig": DEPART_PIG,
	"sheep": DEPART_SHEEP,
}


static func depart_line(species_id: String, display_name: String) -> String:
	if _DEPART.has(species_id):
		return _DEPART[species_id] as String
	return _fill(DEPART_GENERIC, display_name)


# --- Relocation ----------------------------------------------------------------------------
#
# Plain game voice, and the outcome that runs most often. **Not interchangeable with the
# avoidance-relocation lines in `fox-news-report-pool.md` / `rabbit-news-report-pool.md`** — same
# shape on purpose, different trigger: displacement relocation follows a warned player action,
# avoidance relocation follows nothing the player did.

const MOVE_FOX: String = "The fox family moved their den to a new spot in the woods."
const MOVE_RABBIT: String = "The rabbit family moved their warren to a new patch of grass."
const MOVE_HUMAN: String = "The farm family moved into a house with more room to grow."
const MOVE_GENERIC: String = "The {display_name} family moved their home to a new spot."
const MOVE_SHEEP: String = "The Sheep family found a new home in a pasture."  # pipeline-generated (2026-08-30, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF
const MOVE_PIG: String = "The Pig family found a new home in an open field."  # pipeline-generated (2026-08-30, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF
const MOVE_HORSE: String = "The horse family found a new pasture with plenty of room to roam."  # pipeline-generated (2026-08-17, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF
const MOVE_DEER: String = "The Deer family moved to the meadow."  # pipeline-generated (2026-08-17, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF
const MOVE_SHIBA_INU: String = "The Shiba Inu family has a new home with shelter and space to play."  # pipeline-generated (2026-08-17, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF
const MOVE_BULL: String = "The Bull family found their new home in a wide meadow."  # pipeline-generated (2026-08-17, scripts/style_guide_pipeline.py) -- AWAITING CONTENT-WRITER SIGN-OFF

const _MOVE: Dictionary = {
	"fox": MOVE_FOX,
	"rabbit": MOVE_RABBIT,
	"human": MOVE_HUMAN,
	"bull": MOVE_BULL,
	"shiba_inu": MOVE_SHIBA_INU,
	"deer": MOVE_DEER,
	"horse": MOVE_HORSE,
	"pig": MOVE_PIG,
	"sheep": MOVE_SHEEP,
}


static func relocate_line(species_id: String, display_name: String) -> String:
	if _MOVE.has(species_id):
		return _MOVE[species_id] as String
	return _fill(MOVE_GENERIC, display_name)


# --- Guards --------------------------------------------------------------------------------

## Floor species that would fall through to a `*_GENERIC` line, in `"species_id/where"` form.
## **Must be empty.** The handoff doc: `WARN_GENERIC` "must not be reachable for Human, Fox or
## Rabbit — those are the floor, and a floor species falling back to generic copy is a defect
## worth failing a test over." Exposed rather than asserted here so a headless suite owns it.
static func uncovered_floor_species() -> Array[String]:
	var gaps: Array[String] = []
	for species_id: String in FLOOR_SPECIES_IDS:
		var probe: String = "PROBE"
		if warn_line(species_id, probe, false).contains(probe):
			gaps.append("%s/warn" % species_id)
		if warn_line(species_id, probe, true).contains(probe):
			gaps.append("%s/warn_structure" % species_id)
		if depart_line(species_id, probe).contains(probe):
			gaps.append("%s/depart" % species_id)
		if relocate_line(species_id, probe).contains(probe):
			gaps.append("%s/relocate" % species_id)
	return gaps


## Every string this file can render, for a headless copy audit (no em dashes, no parentheses,
## no glyphs, no bare fragments — the Read-Aloud constraint the whole warning is held to).
static func all_lines() -> Array[String]:
	return [
		LEAD_BUILD, LEAD_TERRAFORM, LEAD_REMOVE, LEAD_MIXED,
		WARN_FOX, WARN_RABBIT, WARN_HUMAN_FIELD, WARN_HUMAN_HOUSE, WARN_HUMAN, WARN_GENERIC,
		DEPART_FOX, DEPART_RABBIT, DEPART_HUMAN, DEPART_GENERIC,
		MOVE_FOX, MOVE_RABBIT, MOVE_HUMAN, MOVE_GENERIC,
	] as Array[String]


## `{display_name}` is the only interpolation used anywhere in the handoff doc, and it is never
## inflected — "The Shiba Inu family", "The Deer family".
static func _fill(template: String, display_name: String) -> String:
	return template.format({"display_name": display_name})
