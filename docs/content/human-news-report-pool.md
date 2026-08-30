# Human (Villager) — News Report copy pool

**Status: written, checklist-passed, and HOMELESS.** `AnimalDefinition` has no field for News
Report copy — the same schema gap `fox-news-report-pool.md` and `rabbit-news-report-pool.md`
are waiting on (tier1-status.md row 12: "copy exists and is homeless... No nudge, no toggle,
no Discovery layer built"). This is now the **third** species of copy with nowhere to live.
Move it into data once the schema gains a field.

Produced by `content-writer`, 2026-08-06, filling the gap tier1-status.md row 12 names
explicitly: fox and rabbit have a pool, human does not.

## Sourcing status — read before shipping any of this

**No new sourcing was performed for this file**, and none was needed. spec.md line 78: "News
Report content is a per-animal text pool reusing the fact-card pipeline" — the pipeline, not
a second verification pass. The fact card in `project/data/animals/human.tres` is already
double-sourced per clause (ADW + four Nat Geo Society Education pages) and human-signed-off
(D-28, 2026-07-28). Every line below either restates one of that card's two habitat needs in
bulletin voice (`house`, `cultivated` — `human.tres` line 157:
`habitat_needs = Array[String](["house", "cultivated"])`) or describes ordinary, unremarkable
village life with no factual claim at all (checklist step 1 is trivially satisfied for
flavor lines the same way it is for fox's "curled up in a sunbeam" — no claim, nothing to
source). **No line makes a new real-world assertion.** If a future line ever wants to, it must
re-enter the fact-card pipeline at step 1, not borrow this file's clearance.

## Species note: no separate sourcing question

Unlike Rabbit (European rabbit vs. cottontail, a load-bearing species choice) there is no
species-identity decision to make here — roster.md → Villagers: "Another entry in the animal
system, no separate people/economy simulation." The register question was already fully
litigated on the fact card (`human.tres` header, lines 112–131) and is carried forward below,
not re-opened.

## Avoids: does not apply — stated, not omitted

`avoids: []` in `human.tres` (line 159) and roster.md's Already-Defined Roster table lists
Human's Avoids column as "—". Per gdd.md → Compatibility, "the structural predation check runs
only when a species gains an `avoids` entry" — human.tres's own header says the same thing
verbatim (line 19: "Human's predation risk is closed by data, not by copy"). **Both
Avoidance-relocation and Symmetric-avoids sub-pools are therefore N/A for this species, not
silently skipped:** there is no second party to name, no relocation shape to mirror, and no
symmetric line to write. This is a closed gate, the same conclusion the fact card already
reached, restated here because the checklist's step 5 (graph check) asks the question of every
species and the honest answer for Human is "the graph has no edge here."

**A related, easily confused system is out of scope for this file, not missing from it.**
Human capacity-based departure/relocation (Gentle Displacement, not Avoids) already has
dedicated, checklist-passed copy in `docs/content/displacement-copy.md`
(`WARN_HUMAN_FIELD`/`WARN_HUMAN_HOUSE`/`WARN_HUMAN`, `DEPART_HUMAN`, `MOVE_HUMAN`) — but gdd.md
→ Discovery is explicit that the displacement warning "is deliberately **not** that
[bulletin] voice; consent copy must never sound like flavor." That is a different system in a
different voice with its own file. Nothing here duplicates or contradicts it.

## Register decisions carried forward from the fact card

- **"family" / "families", never a bare capacity number.** roster.md → Villagers: "cultivated
  tiles in radius set how many **families** a house supports"; displacement-copy.md's shipped
  strings all say "the **farm family**" (`WARN_HUMAN_FIELD`, `DEPART_HUMAN`, `MOVE_HUMAN`,
  etc.). Matching that noun across all three homeless pools (fact card, displacement copy, this
  pool) is the D-19 lesson applied proactively rather than found by later audit — read what the
  roster already says before shipping a fourth pool with its own word for the same people.
- **"house"/"field", never "town" or "village" as a bare noun, in every line below** — for a
  different reason than the fact card's. The fact card cut "town"/"village" because a
  *real-world* claim carrying the game's own HUD words (`display_name` "Villager", "Village
  Population" counter) would misread as a claim about the game world — the two-register rule
  cuts the other way here. Bulletin copy is *already* about the game world, so that specific
  hazard doesn't apply. The reason to still avoid "town"/"village" in this pool is
  mechanical and pool-generic instead: a Discovery/hint or Move-in line must read correctly
  whether it fires for the very first House on the floor (one family, no town by any
  definition) or the twentieth, and "town" oversells a single move-in the way an `X / Y`
  fraction oversells capacity (gdd.md #27). "House" and "field" scale from one to many without
  lying either way.
- **US English**, per spec.md's roster-wide register rule — no change needed; nothing below
  used non-US spelling.

## The "settled in" question — resolved deliberately, not avoided by luck

Fox and rabbit's Move-in sub-pools both ship a "has settled in" line (fox: "a fox family has
settled in and made a den among the trees"; rabbit: "a group of rabbits has settled in — and
there are more of them than you'd think"). Human's fact card independently uses "settled" —
"and little by little they settled down in one place" — and content-pipeline-status.md records
that a **near-miss was already found and cleared** for that exact word choice: "the new
'settled in' near-miss against fox/rabbit News Report copy, cleared and recorded." The `.tres`
header spells out why it cleared: "unlike 'town'/'village', 'settled' is not a HUD label but
ordinary narrative verb, and the clause is anchored by 'Long ago' and a date, which fixes the
register before the verb arrives. **Had the card said 'the first people settled in', it would
NOT have cleared.**"

That cleared near-miss was about one specific hazard: the bulletin sense of "settled in"
(a single family, arriving now, as a discrete event — exactly what a move-in is) contaminating
the fact register's very different claim (a multi-millennia, gradual, species-wide transition
that the sources explicitly refuse to pin to a moment). The fix put on the fact card was a time
anchor ("Long ago… About 10,000 to 12,000 years ago") that keeps the two senses apart.

**Decision: reuse "settled in" in this pool's Move-in sub-pool, matching the fox/rabbit idiom
exactly, because a Move-in announcement is the one context where the bulletin sense of
"settled in" is not just safe but the *most accurate available word* — it is describing a
single, discrete, just-happened event (this family, this house, right now), which is precisely
what the bulletin sense has always meant ("moved into your world" — the register the fact-card
near-miss review used to clear it in the first place). The word is not being reused toward a
*contradictory* framing (a gradual claim dressed as a momentary one, which is the actual near-
miss shape); it is being used a second time toward the *same* framing it already carries
everywhere else it ships. **What this pool will not do:** carry "little by little" (the fact
card's gradualness marker) into the Move-in sub-pool, where a discrete event needs a discrete
verb — that combination, not "settled" alone, is what would recreate the near-miss. The one
place "little by little" appears below is the Ambient sub-pool, describing something that
really is gradual in-game (more houses accumulating over many separate move-ins) — a
reinforcement of the fact card's own gradualness claim, not a collision with it. See the
retrieval log for the specific line.

## Sub-pools

These fire at different moments and must not be drawn interchangeably, matching the fox/rabbit
files' own rule.

### Discovery / hint — fires pre-move-in, soft-hints `house` + `cultivated`

- "Word has it a family is looking for a new home — somewhere with room for a house and good soil close by to grow their own food…"
- "A family has been spotted looking over an empty patch of ground, picturing a house there and a field beside it."
- "Rumor down the lane: a family wants a snug house with a little farmland close by, room enough to grow what they need…"

### Move-in announcement

- "A family has moved into the new house down the road! They've got a roof overhead and a field close by to grow what they need."
- "Good news from down the lane: a family has settled in, with a house to call home and a field to keep them fed."

### Ambient / flavor — also usable as welcome-back lines

- "Smoke's been curling from the chimney most evenings this week."
- "Someone's been out working the field again this morning, whistling while they go."
- "A family brought a basket of vegetables in from the field today."
- "There's a new fence post out by the field that wasn't there last week."
- "More families have been moving in around here, little by little."
- "Whoever visited today says every family seems to have a look all its own." — pairs with the five imported model variants (Adventurer, Punk, Man, HoodieCharacter, AnimatedWoman); reads correctly regardless of which variant a given family renders as.

**Cut during drafting, recorded so the reasoning survives:** *"The family has been keeping
watch over the field, hoping nothing gets in."* Nothing named is a threat, and no source was
even consulted for it — but "keeping watch, hoping nothing gets in" imports a worry into an
otherwise placid scene, the same shape as the ears-as-early-warning trope Rabbit's pool cut:
real-sounding vigilance with the cause left conveniently offscreen. Community life gets the
same predation-framing-equivalent check diet/danger copy gets. Cut rather than softened.

### Avoidance relocation — N/A (see "Avoids: does not apply" above)

### Symmetric avoids framing — N/A (see "Avoids: does not apply" above)

## Retrieval log

Per-line traceability: the query that produced the line, the exact source chunk retrieved, and
the resulting output.

| # | Sub-pool | Query | Retrieved chunk (source, quoted exactly) | Output line |
|---|---|---|---|---|
| 1 | Discovery/hint | "human habitat needs, bulletin hint pattern" | `human.tres:157` `habitat_needs = Array[String](["house", "cultivated"])`; pattern from `fox-news-report-pool.md:28` "Word has it a fox is looking for a new home — somewhere with plenty of trees and quiet places to tuck into…" | "Word has it a family is looking for a new home — somewhere with room for a house and good soil close by to grow their own food…" |
| 2 | Discovery/hint | "pre-move-in sighting, sizing-up idiom, non-collision check" | Pattern from `rabbit-news-report-pool.md:37` "A rabbit was seen out in the meadow, sizing it up as if measuring it for tunnels." (idiom borrowed generically, not the exact phrase — checked against roster for collision, none found) | "A family has been spotted looking over an empty patch of ground, picturing a house there and a field beside it." |
| 3 | Discovery/hint | "rumor-register hint opener + cultivated need without invoking the fact card's historical claim" | Pattern from `fox-news-report-pool.md:30` "Rumor from the treetops: a fox family would like a shady stretch of forest…"; need-content from `human.tres:157` `cultivated` — deliberately scoped to *this* family's present need, not the species-history claim in `human.tres:166` | "Rumor down the lane: a family wants a snug house with a little farmland close by, room enough to grow what they need…" |
| 4 | Move-in | "move-in announcement pattern + habitat needs restated in-world" | Pattern from `rabbit-news-report-pool.md:42` "Rabbits have moved into the meadow! They've started a warren under the grass."; needs from `human.tres:157` | "A family has moved into the new house down the road! They've got a roof overhead and a field close by to grow what they need." |
| 5 | Move-in | "'settled in' reuse — resolved per the dedicated section above, not avoided" | `fox-news-report-pool.md:35` "Good news from the woods: a fox family has settled in and made a den among the trees."; `rabbit-news-report-pool.md:43` "Good news from the open grass: a group of rabbits has settled in…"; cleared against `human.tres:119-127`'s near-miss note and `content-pipeline-status.md:194`'s "the new 'settled in' near-miss... cleared and recorded" | "Good news from down the lane: a family has settled in, with a house to call home and a field to keep them fed." |
| 6 | Ambient | "unremarkable daily-life flavor, no factual claim, no predation-adjacent framing" | No source needed (flavor, not fact) — checked for tone only against gdd.md → World & Cast tone rules | "Smoke's been curling from the chimney most evenings this week." |
| 7 | Ambient | "unremarkable daily-life flavor" | No source needed — pattern parallels `fox-news-report-pool.md:43` "A fox stood very still at dawn..." (mundane daily-life beat, no claim) | "Someone's been out working the field again this morning, whistling while they go." |
| 8 | Ambient | "cultivated-need callback in ambient register" | `human.tres:157` `cultivated`; roster.md:91 "cultivated tiles in radius set how many families a house supports" (concept only, not phrasing) | "A family brought a basket of vegetables in from the field today." |
| 9 | Ambient | "gradual growth of settled land, ambient register" | No new claim — visual continuity flavor, parallel to `rabbit-news-report-pool.md:49` "There's a new tunnel entrance out in the meadow that wasn't there last week." | "There's a new fence post out by the field that wasn't there last week." |
| 10 | Ambient | "'little by little' reuse — checked for direction-of-gradualness match, not just word match" | `human.tres:166` `fact_text`: "...and little by little they settled down in one place." Reused because the framing direction matches (in-game population accumulating gradually over many separate move-ins is itself gradual, not a contradiction of the fact card's gradualness claim) — see "The 'settled in' question" above for why this is reinforcement, not collision | "More families have been moving in around here, little by little." |
| 11 | Ambient | "variation-seed / model-variant pairing line, mirroring fox/rabbit's coat-tint pairing device" | `content-pipeline-status.md:190` "5 standalone Quaternius character glbs (Adventurer, Punk, Man, HoodieCharacter, AnimatedWoman)"; device pattern from `fox-news-report-pool.md:45` "Whoever saw the fox today says its coat has a color all its own." and `rabbit-news-report-pool.md:52`'s equivalent | "Whoever visited today says every family seems to have a look all its own." |
| 12 | Cut (not shipped) | "watching-the-field flavor, predation-framing-equivalent check" | Predation-framing-equivalent check pattern from `spec.md:84`'s "hard predation-framing check" and `rabbit-news-report-pool.md:54-57`'s cut ears-line reasoning | *(cut)* "The family has been keeping watch over the field, hoping nothing gets in." |

## Known gaps

- **Pool size is a guess**, exactly as fox and rabbit's files flag — News Report fire rate is
  still unset (tier1-status.md row 12: "not started — nudge trigger delay, News Report
  cadence"). Two hints, two move-in lines, and six ambient lines will repeat quickly once
  cadence is set; size later.
- **The 2×2 House / multi-family form has no dedicated copy.** Every line above is written to
  read correctly for the floor's 1×1 House (one family) and is generic enough not to break for
  a larger farm, but nothing here specifically celebrates "several families, one farm" the way
  roster.md's 2×2 note implies is possible. Worth a line if/when that form ships.
- **No line here is species-identity-load-bearing the way Rabbit's European-rabbit-vs-
  cottontail choice was** — recorded as an explicit non-finding so a future editor doesn't go
  looking for an equivalent decision that doesn't exist for this species.
- **Schema-homeless, same as fox and rabbit** — tier1-status.md row 12 is unchanged by this
  file landing; it still reads "no nudge, no toggle, no Discovery layer built." This file only
  removes the "human isn't even mentioned" gap the assignment brief named. See "Proposals for
  the human" for where this pool should land once the schema gains a field.
