# Wildhaven — Roster

> Authoritative for what the roster is, what data every species (villagers included)
> carries, and which species are already decided. Split out of [gdd.md](gdd.md), which
> keeps only a summary and defers here for detail. Core cross-species mechanics that
> aren't roster-specific — the habitat-tag vocabulary, the carrying-capacity formula,
> qualification/arrival, and Gentle Displacement — stay in gdd.md under **Habitat
> Suitability** and **Gentle Displacement**, since [terrain.md](terrain.md) and
> [buildings.md](buildings.md) read them too; this document covers what varies **per
> species**. Visual/asset sourcing for the roster is [art.md](art.md)'s job, not this
> document's. Field-level schema ground truth is [spec.md](spec.md); nothing here
> overrides it.

## What the Roster Is

The roster is the set of species that can inhabit the world — wild animals and
villagers alike, since **villagers are just another species** (Pillar: Design Pillars
in [gdd.md](gdd.md)). Animals are pure data: a species is one `AnimalDefinition`
entry, so the roster is unlimited by architecture. It ships **15 species — floor: 3
(Human, Fox, Rabbit)** for the 7-week deadline. Adding a species is a repeatable
pipeline, not bespoke code (**Add-an-Animal**, in gdd.md → AI Architecture → Content
Pipelines).

## Attributes Required (AnimalDefinition)

One `AnimalDefinition` per species, villagers included (ground truth: [spec.md](spec.md) → Data Schemas):

| Field | Meaning |
|---|---|
| `id` | unique species id |
| `display_name` | player-facing name |
| `tiers` | **the live habitat data** (2026-09-04, → D-52) — an ordered `Array[HabitatTier]`. Capacity is the `max` over them. Empty is legal and means "synthesise one tier from the legacy flat fields below" |
| `emits_tags` | tags a **resident** of this species contributes to the tile it lives on, counted per individual. Only Human (`people`) and Deer (`deer`) emit anything |
| `habitat_needs` | **legacy, now inert** — `effective_tiers()` prefers `tiers` when non-empty. Retained on all 15 species so a rollback is a one-line edit rather than a re-authoring |
| `personality` | `Shy` \| `Bold` — a **visibility trait only**, stored as a String so the `.tres` self-documents; never gates whether an animal moves in |
| `avoids` | animal ids to keep mutual distance from (optional; symmetric). Stored as ids, never resource references — a bad id degrades to inert text rather than a hard load failure, which is behaviorally correct since avoids never gates a move-in |
| `farm_tolerant` | bool — can live on cultivated land |
| `scout_radius` | tiles; the fallback radius a need uses when it does not carry its own (band **2–16**, human ruling 2026-09-04; was ~8–12) |
| `capacity_radius` | tiles; default `CAPACITY_RADIUS_FOLLOWS_SCOUT` (0) meaning "equal to `scout_radius`", expressed as the relation rather than a copied number |
| `tiles_per_individual` | **legacy, now inert** — the per-need divisor lives on `HabitatNeed` instead. No lower clamp, so `capacity = 0` is still expressible |

**A tier** (`HabitatTier`) carries `needs`, `limits`, its own `max_individuals`, and its own
`arrival_group_size`. **A need** (`HabitatNeed`) carries `tag`, its own `radius` (0 = follow
the species) and its own `tiles_per_individual` (**0 = gate-only**: must be present,
contributes no population cap — which is what stops a one-tile Stable from capping a herd at
one horse). **A limit** (`HabitatLimit`) carries `tag`, `radius` and `max_count`: limits
**gate**, they never scale, so a violated limit zeroes its whole tier.
| `max_individuals` | hard per-home-site cap — a readability bound, never the normal-play limit |
| `model_scenes` | `Array[PackedScene]` — one or more interchangeable look variants, stably picked per resident by `pick_variant(index)` (2026-08-26; was the single-scene `model_scene`). `human.tres` ships 5 equal-weight villager looks; every other species ships one. See spec.md → Data Schemas for the stability contract |
| `fact_text` | fact-card copy |

*(No field holds the model's world scale or footprint: scale lives in the model's own
wrapper scene, and animals occupy no tiles.)*

**Radius band, ruled 2026-09-04:** per-need radii run **2–16**, replacing the old 8–12.
The band had to move because this design's own central cases sit outside it — a building
gate counting close in (the shipped stable gate is 5), and Stag counting at 14. Cost scales as `radius² × roster × tiers`, so the
ceiling is the performance budget; the widest radius the shipped roster actually uses is
**14**, and 47 of the 60 need/limit entries use the follow-scout sentinel rather than an
explicit number.

*Superseded floor placeholders, kept for history* (#6 #20 #23): `capacity_radius` =
`scout_radius`; `tiles_per_individual` — **Human 1**, Fox 5, Rabbit 4; `max_individuals` ~6. Human's
divisor is 1 because the House is the scarce need and the floor House is a single
tile; the 2×2 form supports up to four families, given fields to match.

### Personality: Shy vs. Bold

A **visibility trait only**; it never gates whether an animal moves in. Bold animals
spend more time visibly active in the open, Shy animals more in cover, so spotting a
Shy resident (the fox on the floor) feels meaningfully rarer and more rewarding, mirroring
real wildlife-watching. Finer visibility rules (time-of-day, sighting baselines) are
deferred — [future.md](future.md).

### Compatibility: the Avoids System

Some animals keep their distance from specific others: real, observable wariness with
none of nature's machinery beneath it (Pillar 2 — Gentle to the bone). An avoids entry
is **runtime behavior, not a move-in gate** — a resident periodically checks its
distance to nearby avoided animals and wanders off if too close, with no flee-steering
AI. **Avoid copy describes the game world, and in the game world it is simply true**
(the two-register rule, see Worldbuilding in gdd.md): there is no predation in the
model, so the copy describes the only mechanic that exists. Both coexist given room to
find comfortable distance — the spatial puzzle: *"Rabbits and foxes both want to live
here, but need their own space."*

**Avoids is mutual and symmetric by rule**, declared on either entry and treated as
mutual at runtime; the data model literally cannot express "hunts." Every avoids
string names both parties as equal subjects, or names only the relocating animal's own
comfort: *"Foxes and rabbits each like plenty of space of their own."* **Chronic
avoidance failure never causes a departure:** an animal that can never find comfortable
distance (#9) relocates — announced, as all relocations are — and if no suitable spot
exists it simply stays; moving away is exclusively an outcome of the warned
displacement flow (see Gentle Displacement in gdd.md). **Always on — no mode toggle**
(Harmony Mode was cut — see future.md). **The written position, when a child asks
why:** foxes and rabbits each like plenty of space of their own, and that is the whole
story — the approved answer for all player- and parent-facing copy. **The structural
predation check** inspects the avoid *graph*, not just the copy: a real-animal pair can
mirror a predator–prey dyad even when every line passes, so pairs must be symmetric in
data and in voice, and any real dyad ships with the written position beside it — run in
the Add-an-Animal pipeline whenever a species gains an `avoids` entry.

### Villagers: the People Species

Another entry in the animal system, no separate people/economy simulation. A villager
needs `house` plus carrying capacity: cultivated tiles in radius set how many families
a house supports (the 1×1 House supports one; a **Farmhouse** lets a broad farm
support several — see [buildings.md](buildings.md)). **No hunger, starvation, or
consumption mechanic** — the requirement is static, read when a family moves in or
out, never a draining stock (Pillar 1 intact). **Towns are emergent, not a system:**
clustered houses read as a village, and the game attaches no logic to it. **Village
Population** sits beside the wildlife counters — a fact, not a separate scoreboard.
Villagers exist for their own sake.

**The villager's move-in card is a real fact card, not flavor:** the two-register rule
does not bend for the one species the player happens to be, because bending it is
where "just another species" would quietly stop being true. That makes Human the one
Add-an-Animal run whose step-5 copy has no easy answer — the fact must be real,
source-verified, upbeat, and teach a six-year-old something they don't already know
about their own kind — so it keys off the villager's own habitat needs, `house` and
`cultivated`, exactly as a fox card keys off its own needs — `forest`, `open_grass` and
`water` since D-52 (Open Question #31).
Human's structural predation risk, by contrast, is already closed by data rather than
by copy: Human ships with no `avoids` entry, and the predation check runs only when a
species gains one.

## Already-Defined Roster

**Superseded 2026-09-04 (→ D-52).** The table below is the shipped roster after the
habitat-tiers ruling. It replaces the old flat-needs table, which listed 14 species with a
single recipe each — and in which **Horse, Cow, Bull and Alpaca all carried the identical
recipe `open_grass, cultivated`**. Since different species never compete for tiles (D-46),
one pasture attracted all four at once. That defect is what tiers exist to fix.

**Fifteen species ship, and each has a habitat signature no other species has.** `pig`,
`sheep` and `pug` were already built but had never been tabled here. **Chicken and Duck do
not ship** — their assets resolve to a purchase never made — so `coop` currently has no
consuming species.

Notation: `tag/divisor` is a scaling need · `tag*` is gate-only (must be present,
contributes no cap) · `!tag≤N` is an exclusion limit · `@n` is an explicit radius; needs
without one follow `scout_radius`.

| Animal | Base tier | Group tier | Personality | Avoids |
|---|---|---|---|---|
| **Rabbit** | `open_grass/4` `cultivated/4` `!built≤2` | warren: + `flowers/5`, arrive 4 | **Bold** | **Fox** |
| **Fox** | `forest/4` `open_grass/5` `water/6` `!built≤0` | — | **Shy** | **Rabbit** |
| **Human (Villager)** | `house*` `cultivated/1` | family: `large_house*` `cultivated/2`, max 4, arrive 3 | **Bold** | — |
| Deer | `open_grass/5` `forest/4` `!built≤1` | herd: `open_grass`/`forest`/`browse` all re-declared `@14`, `!built≤0`, arrive 3 | Shy | — |
| Stag | `open_grass/5` `forest/3` **`deer/4`** `!built≤0` `@14` | — (max 2) | Shy | — |
| Donkey | `browse/5` `rocks/4` `!built≤1` | — | Bold | — |
| Cow | `barn*` `silo*` `open_grass/5` | + `water/3`, arrive 2 | Bold | — |
| Bull | `large_barn*` `cultivated/6` | — (max 1) | Bold | — |
| Horse | `stable*` `open_grass/6` (max 2) | herd: `stable*` `open_grass/4@14` `water/2@12`, max 12, arrive 3 | Bold | — |
| Alpaca | `barn*` `open_grass/5` `rocks/6` | — | Bold | — |
| Pig | `cultivated/4` `people/2` | — | Bold | — |
| Sheep | `open_grass/4` `people/3` | flock: + `mill*`, arrive 4 | Bold | — |
| Husky | `snow/6` `people/2` | — | Bold | Shiba Inu |
| Pug | `house*` `people/5` | — | Bold | — |
| Shiba Inu | `house*` `rocks/4` `people/3` | — | Shy | Husky |

*Bold rows are the floor roster; the Avoids column declares game-world relationships only.*

**Two species emit tags of their own** — the mechanic that makes `people` and `deer`
ordinary habitat tags rather than a second system. **Human emits `people`**, which is how a
dog needs an actual person rather than an empty house, and how Pug's "one per five people"
is expressed as an ordinary divisor. **Deer emits `deer`**, which is what gates Stag: four
deer support one stag, so a stag cannot appear until a real deer population already lives
there. Rarity stopped being a hand-tuned `max_individuals` and became something the player
earns. Resident tags are counted **per individual, not per home tile** — a house holding
four villagers reads as `people = 4`.

**Every habitat value above is a PROPOSAL awaiting sign-off**, stated in each `.tres`
header, per the project rule that all tuning values are the human's. Suite-green confirms
the mechanics work as specified; it does not confirm the numbers are final.

The three categories are structurally checkable, not just labels — `AnimalDefinition.category()`
tests them in this order: **Person** (needs *or emits* `people`), **Wild** (no building tag
in any need, and carries a limit), **Domesticated** (a building tag as a gate-only need, no
`built` limit). Person is tested first because Villager emits `people` without consuming it,
and because the dogs gate on `house*` and would otherwise read as Domesticated.

The mix varies Bold/Shy, farm-tolerant/wild-only, and 2–3 habitat needs — at least two
tags each, since one would make single-brushstroke habitat, and the inert-land
invariant (see gdd.md → World Structure) keeps untouched land from satisfying anyone.

### The cleared pool — roster size is a purchase, not a target

**Nine species are imported, licence-cleared, attributed and import-tested:** Deer, Stag,
Horse, Donkey, Cow, Bull, Alpaca, Husky, Shiba Inu. Step 3 (design proposal → human
decision) is now closed for all nine — D-43, values in the Already-Defined Roster table
above. What's still open per species is step 4 (data entry into a `.tres`, gameplay-
engineer's), and for two of them, copy: Bull's `fact_text` is flagged provisional pending a
better-sourced bull-specific fact, and Shiba Inu has no `fact_text` at all yet (no approved
source cleared step 1 — see `docs/content/cleared-pool-fact-cards.md`). Sourcing detail:
[art.md](art.md); per-item pipeline state: [content-pipeline-status.md](content-pipeline-status.md).

What this changes: **the roster has no fixed target number.** It is a floor of three plus
whatever depth the hours buy, drawn from a pool that is already past the expensive gates.
Species that were once named and for which no cleared asset was ever found are not roster
members and are not tracked as gaps — the sourcing findings live in art.md as a watch-list
so the search is not repeated.

**Floor roster (Tier 1):** **Human, Fox, Rabbit.** Fox and Rabbit are cleared and shipped;
Human still faces both the asset audit (#4) and fact-card content (#31) gates and is the
floor's single point of failure. Everything beyond the three is depth (gdd.md → Scope,
row 8).

**Minimal Avoids (Tier 1):** one real pair, **Rabbit ↔ Fox**, already in the thin
roster, so mutual distance-keeping ships with it; symmetry rule and copy framing ship
whole (gdd.md → Scope, row 9). **The second pair is now decided too (D-43): Husky ↔
Shiba Inu**, mutual and symmetric, both domestic dogs (no predator/prey dyad — the
structural check stays clean the same way it does for Rabbit ↔ Fox). It still needs its
own written two-register position (the "foxes and rabbits each like their own space"
equivalent) before it ships, same as every avoids pair must.

### Cleared-pool step 3 — decided, D-43

Full ruling, per-species rationale (including the deliberate Stag rarity tuning, the
Horse/Donkey ecological split, the flagged thinness of Cow/Bull's distinction, and the
Husky/Shiba Inu personality split): [decisions.md](../decisions.md) → **D-43**. Values are
recorded in the Already-Defined Roster table above; `capacity_radius` is the
`CAPACITY_RADIUS_FOLLOWS_SCOUT` sentinel for all nine, matching Fox/Rabbit/Human's shipped
convention (#23 still open).

## Open Questions Touching the Roster

Full list and resolution paths: [spec.md](spec.md) → Open Questions.

- **#4** Final starter roster — Human's audit gate; step-3 proposals for the cleared pool
- **#7** Instance counts — individuals per species; Village Population vs. House count
- **#9** Avoids tuning — personal-space distance; avoidance-failure relocation threshold
- **#20** Home-site tuning — per-species suitability radius
- **#23** Capacity radius per species — per-species values, divergence from scout radius
- **#31** Villager fact-card content — the human fact itself, not the register (decided)
