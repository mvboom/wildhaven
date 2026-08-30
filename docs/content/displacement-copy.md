# Gentle Displacement — copy

**Status: written, checklist-passed, and HOMELESS.** There is no schema field for any string
below. This is the **third** body of checklist-passed copy with nowhere to live — see
`fox-news-report-pool.md` and `rabbit-news-report-pool.md`, both of which have been waiting on
the same missing `AnimalDefinition` rows since pilot 3. A single schema change closes all
three; the proposal is in **Where this should live**, at the bottom.

Produced by `content-writer`, 2026-07-28, against gdd.md → Systems in Play → **Gentle
Displacement**, read as a specification, because it is one. Every constraint below is quoted
from it, not invented here.

## The register — read before touching a line

- **Not the News Report bulletin voice.** gdd.md → Discovery: *"The displacement warning is
  deliberately **not** that voice; consent copy must never sound like flavor."* Nothing here
  may borrow the cheerful-local-bulletin cadence of the two news pools ("Word has it…",
  "Rumor from the hedgerow…"). Departure and relocation are the **plain game voice**.
- **Disclosure, not deterrence.** Factual, upbeat, **no plea, no judgment, no residue
  afterward.** No "please", no "poor", no "sadly", no "are you sure", no later reference back
  to the warning.
- **The villager doctrine, decided in gdd.md and not re-opened here:** a displaced villager
  family is **never described as losing a home, only as finding one**; the warning **names the
  habitat, never the loss**; departure carries **the destination, not the cause**. The copy
  **may never** put the player's action and the family's hardship in one sentence, nor leave a
  family with nowhere named to go.
- **The warning carries the Read-Aloud 🔊 slice**, so every warning string is a complete
  sentence with no em dashes, parentheses, glyphs, or bare fragments. Consent must not require
  fluent reading — or a screen reader guessing at punctuation.

## The composition rule, and why it is also the tonal rule

gdd.md requires **one warning per settled gesture, summarising every affected home**. That
needs a form that composes over 1..N families.

The form below is **one lead sentence naming the player's action, then one line per affected
home**. That split is not just layout: it is what makes the villager doctrine structurally
safe rather than carefully-worded. **The lead carries the player's action and nothing else;
no family's line contains the player's action at all.** The forbidden sentence — the one that
puts the player's tap and a family's hardship together — becomes unwriteable rather than
merely avoided.

gdd.md's own villager exemplar (*"If you clear this field, the farm family won't have enough
to grow here — they'll look for better soil."*) sits inside the doctrine by its own reading —
"won't have enough to grow here" names the **habitat**, which the doctrine explicitly permits
— but it sits close to the line, in one sentence, behind an em dash the Read-Aloud voice will
not honour. The split form keeps a clean margin and reads aloud correctly. **Recommended as
the shipping form for every case, including a single affected home.** One-sentence solo forms
are supplied anyway, further down, in case the UI cannot do a two-part panel.

---

## Warning — lead sentences

One per settled gesture. Fires when, at settlement, `capacity(h, S)` would fall below
`population(h, S)` for any home site in range (gdd.md's computable trigger). **Mode-agnostic
by design** — terraform, build and removal all warn, so all three have a lead.

| id | Trigger | String |
|---|---|---|
| `LEAD_BUILD` | settled gesture was a Build | "If you build here, this will be a different kind of place." |
| `LEAD_TERRAFORM` | settled gesture was a Terraform | "If you change this land, this will be a different kind of place." |
| `LEAD_REMOVE` | settled gesture was a removal (build or terrain) | "If you take this away, this will be a different kind of place." |
| `LEAD_MIXED` | a settled gesture spanning more than one mode, or a mode the UI cannot attribute | "This will be a different kind of place." |

Deliberately parallel. Each names the action and **the place**, never a family, never a loss,
never a count. "A different kind of place" is the whole of the disclosure the lead carries;
the specifics arrive in the home lines, which is what keeps the lead composable.

**Open question for the human/UI, not decidable by copy** — the leads are written in the
conditional (*"If you build here…"*), matching gdd.md's exemplars verbatim. But gdd.md also
puts the **warning's final trigger** after the grace window, at settlement, where a
conditional tense is arguably a beat late. If the UI fires the warning at settlement rather
than at the moment of targeting, use `LEAD_MIXED` for every mode — it is tense-neutral and
already written. Copy is supplied for both readings; which moment the panel opens at is a
design/engineering call, not mine.

## Warning — home lines

**One per affected home**, appended under the lead in any order (recommend nearest home site
first, or roster order — the order is not load-bearing and no line may be phrased to explain
another's move). Each names the home **by family**, names the habitat, and names somewhere to
go. None names the player, the player's action, a loss, or a tag identifier.

| id | Species | String |
|---|---|---|
| `WARN_FOX` | Fox (`forest`, `cover`) | "The fox family will look for a den with trees and rocks around it." |
| `WARN_RABBIT` | Rabbit (`open_grass`, `cover`) | "The rabbit family will look for open grass with a cozy spot out of the wind." |
| `WARN_HUMAN_FIELD` | Human, `cultivated` is the binding need | "The farm family will look for better soil to grow in." |
| `WARN_HUMAN_HOUSE` | Human, `house` is the binding need | "The farm family will look for a house of their own with fields around it." |
| `WARN_HUMAN` | Human, binding need unknown to the caller | "The farm family will look for a house with good soil around it." |
| `WARN_GENERIC` | any species with no line of its own | "The {display_name} family will look for a new home of their own." |

Notes:

- **Rabbit's `cover` is framed as comfort, never safety.** "A cozy spot out of the wind" is
  spec.md's own approved phrasing for exactly this trap ("never as safety, hiding, or escape,
  which is precisely the predation-with-the-predation-removed trap"). Do not substitute
  "somewhere to hide", "somewhere safe", or "shelter".
- **Human has three variants because capacity is min-over-needs**, so the binding need is
  computable — and "better soil" is simply wrong when what was removed is the House.
  `WARN_HUMAN` is the safe fallback if the caller cannot say which need fell short.
- `WARN_GENERIC` covers the nine cleared-pool species, which have no copy of any kind yet. It
  interpolates `display_name`, so it is correct the day any of them ships and needs no
  content pass to be shippable. **It must not be reachable for Human, Fox or Rabbit** — those
  are the floor, and a floor species falling back to generic copy is a defect worth failing a
  test over.
- **"family" is the roster-wide register even at one individual** (v1 arrivals are one
  individual, #7). gdd.md says "the fox family's den"; the shipped news pools say "a fox
  family has settled in". This copy matches; it does not introduce a new noun.

## Warning — solo one-sentence forms (fallback only)

Use only if the UI cannot render a lead-plus-list panel. These fold the lead into the family's
sentence, which is exactly the margin the split form buys back, so they are the second choice.
Never use them when more than one home is affected — a gesture affecting two families must
produce one warning naming both.

| id | String |
|---|---|
| `SOLO_FOX` | "If you build here, the fox family's den will move, and they will look for trees and rocks somewhere else." |
| `SOLO_RABBIT` | "If you build here, the rabbit family's warren will move, and they will look for open grass somewhere else." |
| `SOLO_HUMAN` | "If you clear this field, the farm family will look for better soil to grow in." |
| `SOLO_GENERIC` | "If you build here, the {display_name} family will look for a new home of their own." |

Swap the opening clause for the mode: "If you build here," / "If you change this land," / "If
you take this away,".

`SOLO_HUMAN` is gdd.md's decided exemplar with its hardship clause removed rather than
rephrased — *"the farm family won't have enough to grow here"* is dropped, and the sentence
loses nothing a six-year-old needed. Recorded here because dropping a line the design document
supplies is a decision the human should see, not absorb.

## Departure

**Plain game voice.** Fires after the warning, when no suitable spot exists and the family
moves away. **Framed as finding a home elsewhere, never as loss. Destination, not cause.**
Species Hosted and the Field Guide entry are permanent, so nothing here says goodbye.

| id | Species | String |
|---|---|---|
| `DEPART_FOX` | Fox | "The fox family moved away to find a new den in the woods." |
| `DEPART_RABBIT` | Rabbit | "The rabbit family moved away to find open grass of their own." |
| `DEPART_HUMAN` | Human | "The farm family went off to farm somewhere sunnier." |
| `DEPART_GENERIC` | any other species | "The {display_name} family moved away to find a new home." |

`DEPART_HUMAN` is **gdd.md's decided line, verbatim.** It is the doctrine's own example of
destination-not-cause and there is no reason to improve on it. `DEPART_GENERIC` is likewise
gdd.md's fox exemplar generalised ("The fox family moved away to find a new home.").

Every line names somewhere to go. **A departure string with no destination in it fails the
villager doctrine and should fail a test.**

## Relocation

**Plain game voice.** Fires when a suitable spot exists (`capacity ≥ population` there) and
the animal visibly moves its home — the first of gdd.md's two gentle outcomes, and the one
that runs most often.

| id | Species | String |
|---|---|---|
| `MOVE_FOX` | Fox | "The fox family moved their den to a new spot in the woods." |
| `MOVE_RABBIT` | Rabbit | "The rabbit family moved their warren to a new patch of grass." |
| `MOVE_HUMAN` | Human | "The farm family moved into a house with more room to grow." |
| `MOVE_GENERIC` | any other species | "The {display_name} family moved their home to a new spot." |

**These are a different trigger from the avoidance-relocation lines already in
`fox-news-report-pool.md` and `rabbit-news-report-pool.md`** ("The fox found a quieter corner
of the woods…"). Same shape on purpose — every relocation should read alike to a player — but
they are **not interchangeable pools**, exactly as the fox pool warns about its own sub-pools.
Displacement relocation follows a warned player action; avoidance relocation follows nothing
the player did and is announced after the fact.

## Checklist log — every string above

| Step | Result |
|---|---|
| 1. Approved source | **N/A by design.** These strings describe the **game world** and assert nothing about the real one (gdd.md → Worldbuilding, the two-register rule: *"fact cards assert real-world facts … everything else describes the game world"*). The design source is gdd.md → Gentle Displacement, quoted throughout. |
| 2. 1–2 sentences | PASS — every string is one sentence; a composed warning is one lead sentence plus one sentence per affected home. |
| 3. Tone | PASS — factual, upbeat, warm; no plea, judgment, urgency, or residue. Nothing is snarky and nothing is fear-based. |
| 4. Predation | PASS — no predation, death, danger, diet, or fear anywhere. Rabbit's `cover` is framed as comfort ("out of the wind"), never as safety or hiding. |
| 5. Graph | PASS — **and it constrains this file.** Fox ↔ Rabbit is the roster's one avoids pair, and a single gesture can displace both at once. No line here names another species, and no composed warning may be ordered or phrased so one family's move appears to explain another's. **The displacement flow must never mention avoids at all** — avoidance never causes a departure (roster.md), so a displacement string implying it would be false in the model as well as unsafe in voice. |

**Roster-wide terminology check** (D-19's lesson — read other species' shipped copy, not just
the sources): "den" is fox-only, "warren" is rabbit-only, "family" and "home" are shared and
already shipped in both news pools and in gdd.md. No new noun is introduced. "kits",
"kittens" and "baby rabbits" do not appear — no young are named in displacement copy at all,
which is deliberate: a family moving is a family, not a headcount.

## Where this should live

**Nothing here has a home, and neither do the two news pools.** That is one gap, not three.

**Proposal A (recommended) — one `SpeciesCopy` sub-resource, referenced from
`AnimalDefinition`, closing all three at once.** spec.md already promises the field and does
not have it: *"News Report content is a per-animal (or general) text pool reusing the
fact-card pipeline."* Shape:

- `news_hint_pool`, `news_move_in_pool`, `news_ambient_pool`, `news_avoid_relocation_pool`,
  `avoids_framing_pool` — the two existing homeless pools land here unchanged
- `displacement_warning` (plus the Human need-keyed variants, or one string if the binding
  need is not exposed)
- `displacement_departure`
- `displacement_relocation`

One schema row on `AnimalDefinition` (`copy: SpeciesCopy`), and three files of verified copy
stop being at risk. Verified copy is this project's most expensive artifact per word
(verification measured at ~2.7× drafting cost in pilot 3); two pools have now been homeless
for eight days and this is the third.

**Proposal B (cheaper) — three plain `String` fields on `AnimalDefinition`** for the
displacement lines only. Lands this file, leaves the news pools homeless for a fourth
dispatch. Recorded as the minimum, not the recommendation.

**Either way:**

- The **leads** (`LEAD_*`) and the **generic fallbacks** are not species data. They belong
  beside the other rendered UI strings — the same place `PREVIEW_TEXT_*` lives today — owned
  by ui-engineer, sourced from this file.
- **Empty displacement copy on a floor species should be a `validate()` problem**, the way
  `fact_text` is. A cleared-pool species may legitimately fall through to `WARN_GENERIC` /
  `DEPART_GENERIC`; Human, Fox and Rabbit may not.
- `{display_name}` is the only interpolation used anywhere here, and it is never inflected —
  "The Shiba Inu family", "The Deer family". Verified readable for all nine cleared-pool
  display names.

## Known gaps

- **Warning tense vs. firing moment** is unresolved (see the lead table's note). Copy exists
  for both readings; the choice is the human's.
- **The binding-need split for Human** (`WARN_HUMAN_FIELD` / `WARN_HUMAN_HOUSE`) assumes the
  caller can say which need fell short. If it cannot, `WARN_HUMAN` ships and nothing is
  blocked — but the copy is measurably vaguer, and Human's divisor of 1 against a 1×1 House
  makes this the **likeliest displacement in the floor**, so it is worth the plumbing.
- **No plural form exists for two families of the same species.** v1 arrivals are one
  individual per home site (#7), and the composed warning lists homes, not individuals, so
  two fox home sites produce two identical `WARN_FOX` lines. Acceptable at the floor; if #7's
  packs land, this needs a second look.
- **No copy exists for a family that relocates and then relocates again**, or for the
  "chronic avoidance failure with no suitable spot, so it simply stays" case (roster.md) —
  the latter is correctly silent, and is noted only so nobody writes a line for it by reflex.

---

# Appendix — the two `[COPY]` preview band strings

**Not displacement copy.** Included here because the brief asked for it in one handoff doc,
and because both live under the same rule.

**Destination:** `project/scripts/ui/game_hud.gd`, constants `PREVIEW_TEXT_WILD` and
`PREVIEW_TEXT_HOME`. **ui-engineer's file — content-writer does not edit it.** (The dispatch
named `project/scripts/ui/ui_palette.gd`; the strings are not there, they are in
`game_hud.gd`.)

**The rule all three bands are held to:** a statement about **a place**, never naming a
missing tag and never naming a next tap — an invitation, never an assignment (Pillar 1). One
addition from the shared vocabulary: none of the ten tag words may appear as a word, so
`open`, `grass`, `quiet`, `cover`, `rocks`, `flowers`, `house`, `water`, `sand`, `forest` are
all out of bounds in a preview line even in innocent use, or the preview starts teaching a
tag vocabulary the player is never supposed to manage.

## `PREVIEW_TEXT_WILD` — fires on `BAND_WILD` (no species could settle here)

| Rank | Proposal |
|---|---|
| **Recommended** | "this land is wild" |
| alt A | "this spot is wild land, all its own" |
| alt B | "the wind has this land to itself" |

The recommended line is deliberately plain. Warmer drafts kept failing in one of two
directions, and both failures are prompts: **"this land is still wild" / "wild for now"** read
as *not yet* — a deficiency and an instruction; **"this land is wild, just as it is"** reads
as *leave it alone* — which is also an instruction, just the opposite one. A band that fires
on "nobody could live here" has to say only what is true of the place and stop. Also rejected:
"wild and free" (in Terraform mode it sits beside a Wood cost, where "free" means something
else) and "wild and quiet" (`quiet` is a habitat tag).

## `PREVIEW_TEXT_HOME` — fires on `BAND_HOME` (somebody's home is on this tile)

| Rank | Proposal |
|---|---|
| **Recommended** | "this spot is somebody's home" |
| alt A | "somebody lives right here" |

Recommended because it matches the middle band's cadence exactly — *"this spot is getting cozy
for someone"* / *"this spot is somebody's home"* — so the two bands read as one voice
describing one place at two moments. The stub's own words ("someone calls this spot home") are
fine and would pass; this is a cadence choice, not a correction.

## `PREVIEW_TEXT_WELCOMING` — the honest caveat, and what I propose

**Ship it unchanged today.** `game_hud.gd`'s comment is right that the beat moved: gdd.md
lands *"this spot is getting cozy for someone"* at ~0:20, in the near-miss voice — land that
is *becoming* suitable — while today it fires when a spot **already** qualifies, because the
near-miss summary is row 12 and unbuilt.

It still reads true, and slightly better than it reads in the document. At today's trigger the
spot suits somebody and **nobody has arrived yet** — `BAND_HOME` would have won otherwise — so
"getting cozy for someone" describes a place that is ready and waiting for a specific someone
who is, in fact, already enqueued on the arrival delay. It under-claims rather than
over-claims, which is the safe direction for a line that cannot promise an arrival.

**What I propose for the day row 12 lands** and `BAND_WILD` splits into "nearly" and "not at
all":

- *"this spot is getting cozy for someone"* moves to the **near-miss** band. That is the
  sentence's intended home, it is gdd.md's exemplar, and it should not be spent on a band that
  means "is".
- The qualifying band takes a line that says **is**, not *becoming*: **"this spot would suit
  somebody just fine"** (alt: "somebody could make a home right here"). Same rule — a
  statement about a place, no tag named, no tap named.
- `BAND_WILD` keeps "this land is wild" for the "not at all" half.

That is a proposal, not a change. The three-way split is row 12's design call, and copy should
not decide it in advance.
