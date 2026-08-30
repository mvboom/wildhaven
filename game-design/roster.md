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
entry, so the roster is unlimited by architecture. It ships **8 species — floor: 3
(Human, Fox, Rabbit)** for the 7-week deadline. Adding a species is a repeatable
pipeline, not bespoke code (**Add-an-Animal**, in gdd.md → AI Architecture → Content
Pipelines).

## Attributes Required (AnimalDefinition)

One `AnimalDefinition` per species, villagers included (ground truth: [spec.md](spec.md) → Data Schemas):

| Field | Meaning |
|---|---|
| `id` | unique species id |
| `display_name` | player-facing name |
| `habitat_needs` | list of required habitat tags (drawn from the shared vocabulary — see gdd.md → Habitat Suitability) |
| `personality` | `Shy` \| `Bold` — a **visibility trait only**, stored as a String so the `.tres` self-documents; never gates whether an animal moves in |
| `avoids` | animal ids to keep mutual distance from (optional; symmetric). Stored as ids, never resource references — a bad id degrades to inert text rather than a hard load failure, which is behaviorally correct since avoids never gates a move-in |
| `farm_tolerant` | bool — can live on cultivated land |
| `scout_radius` | tiles; the radius over which habitat needs are scored (~8–12; Open Question #20) |
| `capacity_radius` | tiles; the radius over which carrying capacity counts tags (v1 default: equal to `scout_radius`; may diverge per species — Open Question #23) |
| `tiles_per_individual` | the capacity formula's divisor — no lower clamp, so `capacity = 0` is expressible (the formula itself lives in gdd.md → Habitat Suitability) |
| `max_individuals` | hard per-home-site cap — a readability bound, never the normal-play limit |
| `model_scenes` | `Array[PackedScene]` — one or more interchangeable look variants, stably picked per resident by `pick_variant(index)` (2026-08-26; was the single-scene `model_scene`). `human.tres` ships 5 equal-weight villager looks; every other species ships one. See spec.md → Data Schemas for the stability contract |
| `fact_text` | fact-card copy |

*(No field holds the model's world scale or footprint: scale lives in the model's own
wrapper scene, and animals occupy no tiles.)*

**Floor placeholders for the three tuning constants** (proposed from ecology, decided
by the human — tunable, #6 #20 #23): `capacity_radius` = `scout_radius` (~8–12 tiles);
`tiles_per_individual` — **Human 1**, Fox 5, Rabbit 4; `max_individuals` ~6. Human's
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
a house supports (floor: the 1×1 House supports one; the 2×2 form lets a broad farm
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
`cultivated`, exactly as a fox card keys off cover and quiet (Open Question #31).
Human's structural predation risk, by contrast, is already closed by data rather than
by copy: Human ships with no `avoids` entry, and the predation check runs only when a
species gains one.

## Already-Defined Roster

| Animal | Habitat needs | Personality | Avoids | Farm-tolerant | `tiles_per_individual` |
|---|---|---|---|---|---|
| **Rabbit** | **open_grass, cover** | **Bold** | **Fox** | **Yes** | **4** |
| **Fox** | **forest, cover** | **Shy** | **Rabbit** | **No** | **5** |
| **Human (Villager)** | **house, cultivated** | **Bold** | **—** | **Yes** | **1** |
| Chicken | cultivated, open_grass | Bold | — | Yes | *proposed* |
| Duck | water, cover | Bold | — | No | *proposed* |
| Deer | open_grass, forest | Shy | — | No | 6 |
| Stag | forest, cover, rocks | Shy | — | No | 8 |
| Horse | open_grass, cultivated | Bold | — | Yes | 5 |
| Donkey | cultivated, rocks | Bold | — | Yes | 4 |
| Cow | cultivated, open_grass | Bold | — | Yes | 5 |
| Bull | cultivated, open_grass | Bold | — | Yes | 6 |
| Alpaca | open_grass, cultivated | Bold | — | Yes | 5 |
| Husky | house, open_grass | Bold | Shiba Inu | Yes | 2 |
| Shiba Inu | house, open_grass | Shy | Husky | Yes | 2 |

*Bold rows are the floor roster; the Avoids column declares game-world relationships
only.* On the floor the Fox is the hardest habitat, two tags from two terrains (forest +
rock — see [terrain.md](terrain.md)). The nine cleared-pool rows below Chicken/Duck were
ruled 2026-08-16 (D-43) — decided design values, now built (`.tres` files landed);
`scout_radius`/`max_individuals` for each are 8/6 except Stag (12/**3**, a deliberate
rarity choice) and Deer (10/6) — see D-43 for full per-species rationale. **Alpaca's
`tiles_per_individual` was revised from D-43's original 3 to 5** by D-45
(2026-08-17), a live-playtest correction — see D-45 in [decisions.md](../decisions.md).

Chicken and Duck are designed but unbuilt: their assets resolve to a Synty SIMPLE purchase
that has not been made, and **whether to make it at all is a velocity-review call** now that
a free cleared pool exists (below).

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
