# Habitat Tiers, Per-Need Radii, Exclusions, and Resident-Emitted Tags

**Date:** 2026-09-04
**Status:** Design approved in brainstorm; all open questions ruled 2026-09-04 (§12).
Not yet ruled as a `D-NN` decision
**Supersedes in spirit:** the flat single-tier habitat model in `game-design/gdd.md`
→ Habitat Suitability

> **Standing caveat.** The human explicitly lifted the "abide by the GDD and the
> Fox/Rabbit/Human floor" constraint during this brainstorm (2026-09-04): *"We do not
> have to abide by our gdd or any specified rules we may have had in the past."* This
> spec therefore re-specs floor species freely. Folding it back into `gdd.md`,
> `roster.md`, `terrain.md` and `buildings.md`, and logging it as a `D-NN`, is a
> follow-up the human gates.
>
> **Every number in this document is a proposal, not a decision** (project rule: *all
> tuning values are the human's*).

---

## 1. Why

The shipped roster has a measurable distinctness defect. Four species carry *identical*
habitat needs:

| Horse | Cow | Bull | Alpaca |
|---|---|---|---|
| `open_grass, cultivated` | `cultivated, open_grass` | `cultivated, open_grass` | `open_grass, cultivated` |

D-46 makes this worse than it appears: *"Different species never compete for the same
land."* A tile counts for every species at once. So a single pasture does not attract
*one* of those four — it attracts **all four, stacked on the same ground**.

Separately, eight farm buildings — Barn, SmallBarn, OpenBarn, ChickenCoop, Silo,
Windmill, WaterTower, Well — are imported, licence-cleared, costed, hotbar-categorised
and **emit nothing** (`emitted_tags = []` in every one). They are placeable decoration
with zero simulation meaning.

This design fixes both: it gives species distinct habitat signatures, and it gives the
eight buildings a job.

## 2. What changes, in one paragraph

A species stops having *one* habitat recipe and gains an ordered list of **tiers**, each
with its own needs, its own population cap, and its own group-arrival size. Each need
carries its **own radius and its own divisor**, so "a barn right here" and "a wide tract
of grass" are expressible in one recipe. A tier may also carry **limits** — *"at most N
of tag X nearby"* — which is what makes wild animals want genuinely wild land rather
than merely a different quantity of the same land. Finally, a **resident** may emit a
tag, which makes `people` an ordinary habitat tag and lets a dog need an actual person
rather than an empty house.

---

## 3. Data model

Three new `Resource` classes, plus two new fields on `AnimalDefinition`.

```gdscript
# scripts/definitions/habitat_need.gd
class_name HabitatNeed extends Resource
    tag: String                  # from the shared vocabulary
    radius: int                  # 0 = RADIUS_FOLLOWS_SCOUT sentinel
    tiles_per_individual: int    # 0 = GATE_ONLY: must be present, contributes no cap

# scripts/definitions/habitat_limit.gd
class_name HabitatLimit extends Resource
    tag: String
    radius: int                  # 0 = RADIUS_FOLLOWS_SCOUT sentinel
    max_count: int               # "at most this many within radius"; 0 = none at all

# scripts/definitions/habitat_tier.gd
class_name HabitatTier extends Resource
    id: String                   # "pair", "herd" — internal only, NOT player-facing
    needs: Array[HabitatNeed]
    limits: Array[HabitatLimit]
    max_individuals: int
    arrival_group_size: int      # default 1
```

```gdscript
# scripts/definitions/animal_definition.gd — additions
    tiers: Array[HabitatTier] = []      # empty => synthesise one tier from legacy fields
    emits_tags: Array[String] = []      # tags a RESIDENT of this species contributes
```

### Sentinel conventions

`radius = 0` means **"follow `scout_radius`"** and reuses the exact convention already
established by `CAPACITY_RADIUS_FOLLOWS_SCOUT` in `animal_definition.gd`. Most needs
leave it blank; only deliberate outliers carry a number. Resolve through a
`effective_radius(species)` helper, never by reading the raw field — same contract as
the existing `effective_capacity_radius()`.

`tiles_per_individual = 0` means **`GATE_ONLY`**. This exists because a 1-tile Stable
with an ordinary divisor of 1 would cap a herd at one horse, which is exactly backwards:
the stable is a *precondition*, not the thing that scales the herd.

### Tier ordering

`tiers` is authored best-last by convention, but the formula takes a `max`, so order is
presentational only. It must not be load-bearing.

---

## 4. The formula

```
capacity(h, S) = max over tiers T in S.tiers of tier_capacity(h, S, T)

tier_capacity(h, S, T):
    for L in T.limits:                                  # limits GATE, never scale
        if count(L.tag, effective_radius(L, S)) > L.max_count:
            return 0
    c = T.max_individuals
    for N in T.needs:
        n = count(N.tag, effective_radius(N, S))
        if N.tiles_per_individual == GATE_ONLY:
            if n < 1: return 0
        else:
            c = min(c, floor(n / N.tiles_per_individual))
    return c
```

Properties this deliberately preserves:

- **Liebig's law of the minimum survives intact *inside* each tier.** The scarcest need
  still caps the population, which is the part that actually teaches something.
- **`qualifies(h, S) ≡ capacity(h, S) ≥ 1` is still one function**, so the GDD's
  "one read, not two systems" invariant holds unchanged.
- **Capacity can still be 0, and 0 still means unsuitable.** No lower clamp.
- A species can fall from a better tier to a worse one rather than to nothing — which is
  what gives Gentle Displacement its best available copy (§9).

### Counting: tiles *and* residents

`count(tag, radius)` sums two sources:

1. **Tile tags** — terrain `emitted_tags`, or the building's `emitted_tags` where a
   footprint occupies the tile (unchanged rule).
2. **Resident tags** — for every resident within radius whose species declares
   `emits_tags`, add its tags.

**Residents count per individual, not per home tile.** A house holding four villagers
must read as `people = 4`. If this is implemented per-tile, "one pug per five people"
silently becomes "one pug per five houses," which is the single most likely
implementation bug in this design.

### Group arrivals

`arrival_group_size` enqueues N individuals rather than one. At due time the arrival is
**re-checked and partially satisfiable**: if capacity has since dropped, it lands with as
many as fit rather than being dropped wholesale. All-or-nothing would make herds feel
arbitrary and would interact badly with a tap burst.

---

## 5. Migration

Every existing `.tres` — a flat `habitat_needs` plus one `tiles_per_individual`, one
`max_individuals`, one `capacity_radius` — **is exactly a one-tier species**. When
`tiers` is empty, synthesise a single `HabitatTier` from the legacy fields at load.

This is not risk insurance (the floor constraint was lifted); it is so the sixteen
existing `.tres` files can be converted **one at a time**, and so a half-converted roster
is always in a runnable state.

Legacy fields stay on the schema. They are not deprecated in this pass.

---

## 6. Validation rules

Added to `AnimalDefinition.validate()`. All are cheap and all report rather than reject,
matching the file's existing non-fatal contract.

1. **The emission/need graph must be acyclic.** Two real edges ship in this design:
   `human → people → {pug, shiba_inu, husky, pig, sheep}` and `deer → deer → stag`.
   Neither closes a loop, and the check exists so the third one added doesn't. A cycle
   makes capacity oscillate forever across the dirty queue — the one genuinely new
   failure mode this design introduces.
2. **The inert-land invariant counts positive needs only.** A `HabitatLimit` may never be
   what makes a species non-bare. `BARE_TAGS` stays derived from `wild_grass.tres` via
   `TerrainDefinition.derive_bare_tags()` — do not reintroduce a hardcoded copy.
3. **Per-need radius gets its own band, separate from `scout_radius`.** Proposed **2–16**.
   The current `validate()` hard-fails anything outside 8–12, which this design must
   replace: radius 4 ("a barn right there") and radius 14 ("a wide tract") are both
   central to it. Cost scales as `max_radius² × roster × tiers`; 16 is ~2.5× the area of
   10. **Human ruling required.**
4. **Category coherence** — checkable, and worth checking because the categories are the
   whole point:

   | Category | Signature | Precedence |
   |---|---|---|
   | Person | needs **or emits** `people` | checked **first** |
   | Wild | no building tag in any need; carries a `built` limit | second |
   | Domesticated | ≥1 building tag as a `GATE_ONLY` need; no `built` limit | last |

   Three subtleties the categories must survive, all found in self-review:
   **Villager** consumes no `people` but *emits* it, which is why the Person test reads
   "needs or emits". **Pug and Shiba Inu** match the Domesticated signature too (they
   gate on `house*`), which is why Person is checked first rather than the categories
   being treated as disjoint. And a species matching **no** category is a validation
   warning, not an error — it means the design intent is unclear, not that the data is
   broken.

5. Every tag in every need and limit must exist in the shared vocabulary.
6. A tier with no needs at all is invalid (a limits-only tier would qualify on bare land).

---

## 7. Tag vocabulary

`HABITAT_TAGS` currently lives as a hardcoded `const` in `animal_definition.gd`, and
extending it is explicitly reserved as a human gate. This design extends it.

**Retained:** `water` `forest` `open_grass` `cover` `flowers` `rocks` `cultivated` `house`
**Retired:** `quiet` — the `built` limit does its job strictly better, is actually
enforced, and needs no terrain to source it. (`sand` stays: free to keep, still dormant.)
**Added:** `built` `people` `deer` `browse` `snow` `barn` `large_barn` `large_house`
`stable` `coop` `silo` `mill`

`people` and `deer` are **resident-emitted**, not tile-emitted — the only two so far.
The convention is that a species emits a tag named after itself; nothing stops a third,
but each one adds an edge the acyclicity check (§6.1) must clear.

`built` is the load-bearing addition. **Every placeable emits `built` in addition to its
own tag.** That means a wild species carries one limit rather than enumerating nine
building tags, and any building added later automatically participates in every wild
species' exclusion without touching a single species file.

`browse` vs `open_grass` is the real ecological browser/grazer split — a Pillar 4 win
rather than a game-ism. Tag ids are internal, never player-facing.

---

## 8. Tag sources

### Buildings — nine existing files, one line each

| Building | Footprint | `emitted_tags` |
|---|---|---|
| House | 1×1 | `built` `house` |
| **Farmhouse** *(new)* | 2×2 | `built` `house` `large_house` |
| SmallBarn | 1×1 | `built` `barn` |
| Barn | 2×2 | `built` `barn` `large_barn` |
| OpenBarn | 1×1 | `built` `barn` `stable` |
| ChickenCoop | 1×1 | `built` `coop` |
| Silo | 1×1 | `built` `silo` |
| Windmill | 1×1 | `built` `mill` |
| Well | 1×1 | `built` `water` |
| WaterTower | 1×1 | `built` `water` |

Three subsumptions do real work. **A large barn is a barn**, so Barn satisfies both
`barn` and `large_barn`. **An open-sided barn is a stable**, so OpenBarn satisfies both
`barn` and `stable` — one building, cows or horses. **A farmhouse is a house**, so a
Farmhouse still houses dogs and single villagers while also unlocking families (§9).

The Farmhouse replaces `buildings.md`'s "House at 2×2" *form* with a distinct placeable,
which is what lets `large_house` exist as a requirement at all. Nine-plus house models are
already imported (`house_firstage_*`, `house_secondage_*`, `house_tower_secondage`), so
the asset is on hand.

Well and WaterTower emitting `water` is what delivers "a pond and/or a water tower" with
**no new tag**: a lake and a tower satisfy the same need, trading tiles against Wood.

### Terrain — three new, six unchanged

| Terrain | `emitted_tags` | Cost | Note |
|---|---|---|---|
| Wild grass | *(none)* | free | unchanged — deliberately inert |
| Grass | `open_grass` | free | unchanged |
| **Meadow** *(new)* | `open_grass` `flowers` | free | rich grazing; finally sources the dormant `flowers` tag |
| **Scrub** *(new)* | `browse` `rocks` | free | rough grazing — the "wild grass" concept *given tags*, while real wild grass stays inert |
| **Snowfield** *(new)* | `snow` | free | |
| Forest | `forest` | free | unchanged; sole harvestable |
| Rock | `cover` `rocks` | free | unchanged |
| Water | `water` | free | unchanged |
| Cultivated field | `cultivated` | ~2 Wood | unchanged |

**Art is already cleared.** Snowfield draws on the Ultimate Nature Pack's complete snow
variant set (`BirchTree_Snow_*`, `Bush_Snow_*`); Meadow and Scrub draw on the Stylized
Nature MegaKit (`Flower_*`, `Bush_Common_Flowers`, `Fern_1`, `Grass_Common_Tall`,
`Grass_Wispy_*`). Both packs are already imported and attributed. **No new sourcing gate.**

---

## 9. The roster

Notation: `tag/divisor` · `tag*` = `GATE_ONLY` · `!tag≤N` = limit · `@n` = explicit radius.
Unmarked radii follow `scout_radius`. **All values are proposals.**

### Wild — no building need; carries a `built` limit

| Species | Base tier | Group tier |
|---|---|---|
| Deer | `open_grass/5` `forest/4` `!built≤1` | + `browse/6`, wider radii, `!built≤0`, arrive **3** |
| Stag | `open_grass/5` `forest/3` **`deer/4`** `!built≤0` `@14` | — max **2** |
| Fox | `forest/4` `open_grass/5` `water/6` `!built≤0` | — |
| Rabbit | `open_grass/4` `cultivated/4` `!built≤2` | warren: + `flowers/5`, arrive **4** |
| Donkey | `browse/5` `rocks/4` `!built≤1` | — |

Donkey is treated as feral here, matching its placement in the human's own grouping.

**Stag is the design's best argument for itself.** Its `deer/4` need is an ordinary
habitat need pointing at a resident-emitted tag, so no new machinery was required at all
— yet it means a stag cannot appear until four deer already live there, and a fifth stag
would need twenty deer. Rarity stops being a hand-tuned `max_individuals` and becomes a
thing the player earns by building a real deer population first. `rocks` was dropped from
the original proposal: with the deer gate doing the distinguishing work, a fourth
requirement made stags near-unreachable rather than rare.

### Domesticated — ≥1 building gate; no `built` limit

| Species | Base tier | Group tier |
|---|---|---|
| Cow | `barn*` `silo*` `open_grass/5` | + `water/3`, arrive 2 |
| Bull | `large_barn*` `cultivated/6` | — max 1 |
| Horse | `stable*` `open_grass/6` — max **2** | `stable*` `open_grass/4@14` `water/2@12` — max **12**, arrive 3 |
| Alpaca | `barn*` `open_grass/5` `rocks/6` | highland; `rocks` is its distinguisher. The `barn*` gate was added in self-review — the original proposal had no building need and so failed its own Domesticated category test |
| Chicken | `coop*` `cultivated/4` | *(asset unpurchased — see roster.md)* |

The Horse row is the design's own worked example: **a barn and some grass gets you a
pair; a stable, a wide tract and water gets you a herd**, with water binding the herd
size, so digging more pond visibly buys more horses.

### Person — requires `people`

| Species | Base tier | Group tier |
|---|---|---|
| Villager | `house*` `cultivated/1` — max **1** | family: `large_house*` `cultivated/2` — max **4**, arrive **3** |
| Pig | `cultivated/4` `people/2` | |
| Sheep | `open_grass/4` `people/3` | flock: + `mill`, arrive 4 |
| Husky | `snow/6` `people/2` | |
| Pug | `house*` `people/5` | the "1 per 5 people" case, literally |
| Shiba Inu | `house*` `rocks/4` `people/3` | |

**Sixteen species, sixteen distinct habitat signatures.** No two share a recipe.

---

## 10. Code changes

| File | Change |
|---|---|
| `scripts/definitions/habitat_need.gd` | **new** |
| `scripts/definitions/habitat_limit.gd` | **new** |
| `scripts/definitions/habitat_tier.gd` | **new** |
| `scripts/definitions/animal_definition.gd` | `tiers`, `emits_tags`; legacy-tier synthesis; extended `HABITAT_TAGS`; replace the 8–12 radius band; the six new `validate()` rules |
| `scripts/definitions/placeable_definition.gd` | none — schema already supports `emitted_tags` |
| `scripts/definitions/terrain_definition.gd` | none — schema already supports `emitted_tags` |
| `scripts/simulation/capacity_evaluator.gd` | max-over-tiers; per-need radius; `GATE_ONLY`; limits |
| `scripts/simulation/habitat_simulation.gd` | resident-emitted tags in the count; per-(tag, radius) caching; group arrivals |
| `scripts/ui/habitat_recipe.gd` | show the current tier and what the next one would need |
| 9 building `.tres` | fill `emitted_tags` |
| 3 terrain `.tres` | **new** — Meadow, Scrub, Snowfield |
| 16 species `.tres` | re-spec to tiers, incrementally |
| `tests/test_capacity_formula.gd` | tiers, gates, limits, resident counting |
| `tests/test_habitat_recipe.gd` | tier display |

---

## 11. Interaction with existing systems

**Gentle Displacement.** Tiers give it the best copy it has ever had. Falling from a herd
tier to a pair tier is a *thinning*, not a vanishing: *"the herd will thin to a pair —
the rest will find a wider field."* Building a barn in a deer meadow trips a `built`
limit and reads as *"the deer will move deeper into the woods."* Both land squarely in
the established voice with no strain. **Cascades are new, though:** villagers leave →
dogs de-qualify → dogs displaced, producing a chain of warnings within one settled
gesture. **`deer → stag` is a second such chain**, and a more visible one: clearing a deer
meadow can cost the stag too. The settlement rule should coalesce these into one warning;
verify in playtest.

**Discovery / News Reports.** The near-miss summary becomes genuinely informative instead
of generic, because there is now a concrete next tier to report against: *"Word is the
horses could become a herd here, if there were a stable."* This is a real content upgrade
and is worth a follow-up pass on the News Report pools.

**D-46 exclusivity.** Unchanged. Note that `built`-emitting structures are now numerous,
but limits *count* tiles rather than *claiming* them, so exclusivity scoping is untouched.

**Performance.** Cost per player action becomes `max_radius² × roster × tiers` — still
independent of world size, which is the property that matters. Per-need radii mean the
per-home-site cache is keyed by `(tag, radius)` rather than by `tag` alone. The radius cap
(§6.3) is the real budget lever.

**Save format.** Group arrivals mean a pending arrival may carry a count. Bump
`save_version`.

---

## 12. Open questions — all ruled 2026-09-04

- **OQ-A — Deer vs. Stag. RULED: neither option; a third.** A stag appears only where
  deer already live — *"it can't be a herd if there is no stag with the deer."* Expressed
  as `Deer.emits_tags = ["deer"]` and a `deer/4` need on Stag, so four deer support one
  stag. **No schema change**: it is an ordinary need against a resident-emitted tag, the
  same mechanic `people` already uses. Adds one edge to the acyclicity check (§6.1).
- **OQ-B — per-need radius band. RULED: 2–16**, replacing the current 8–12 hard-fail.
- **OQ-C — divisors, caps, limits, group sizes. RULED: §9 stands as a starting point**,
  expected to move in playtest.
- **OQ-D — villager family arrivals. RULED:** a family needs the larger house plus
  cultivated land at ≥2 tiles per person — the new `large_house*` gate and `cultivated/2`,
  max 4, arriving 3. *Interpretation flag: "≥2 sized cultivated" is read as the divisor
  (2 tiles per villager), not as a flat 2-tile minimum. Say so if the other reading was
  meant.*
- **OQ-E — Snowfield plausibility. RULED: allowed.** Snow may border grass; the game is
  not restricted to real-world climate adjacency. No art gate.
- **OQ-F — retire `quiet`. RULED: remove it.**

## 13. Out of scope

Player-facing tier names in the Field Guide (considered and set aside — tiers stay
mechanical for now); per-species amenity buildings; multi-resource economy; rebalancing
Wood costs for the three new terrains; News Report copy for the new tiers.
