# Wildhaven — Terrain

> Authoritative for what terrain is, what data every terrain type carries, and which
> terrains are already decided. Split out of [gdd.md](gdd.md), which keeps only a
> summary and defers here for detail. The shared habitat-tag vocabulary and the
> carrying-capacity formula that terrain tags feed are cross-cutting mechanics that
> [roster.md](roster.md) also reads, so they stay in gdd.md under **Habitat
> Suitability**; this document covers what varies **per terrain type**. Field-level
> schema ground truth is [spec.md](spec.md); nothing here overrides it.

## What Terrain Is

Terrain is the tile-level surface type covering the world grid. **Eight paintable types ship** —
grass, water, forest, rock, cultivated field, meadow, scrub and snowfield — plus wild grass,
which is what sits behind the mist and is never painted deliberately. **Sand was designed but
never built:** it has no `TerrainDefinition` and no asset wired, so the `sand` tag has no
source. It is a depth item with nothing behind it, not a ninth shipped terrain. The player
paints it directly in **Terraform Mode**: pick a terrain, **one tap converts one tile**
(#17 closed — drag-to-paint is depth). **Each tile carries the habitat tags its own
terrain emits — tags do not spread to neighbouring tiles** (the v1 tag model, → D-25;
full statement in [spec.md](spec.md) → Shared Patterns). "Nearby" is expressed entirely
by the *species'* radius, not by any radius belonging to the terrain. The player never
manages tags directly (see gdd.md → Habitat Suitability). Terrain is
the substrate everything else builds on: buildings occupy terrain footprints (see
[buildings.md](buildings.md)), and the roster's habitat needs are satisfied by terrain
tags (see [roster.md](roster.md)).

**The one pricing rule:** *"Nature is free; construction costs materials."* Every natural
terrain (grass, water, forest, rock, meadow, scrub, snowfield) is free to paint; the
cultivated field is the only terrain that costs Wood — 2 per tile. See Economy in gdd.md for
the full resource narrative.

## Attributes Required

### Tag emission (every terrain type)

Every terrain type declares which habitat tags it emits when painted. **That is the
whole declaration** — no radius, no weight (→ D-25). A tile emits its terrain's tags
and nothing else; a tile under a building footprint emits the building's `emitted_tags`
instead.

Each terrain type is one **`TerrainDefinition`** resource (field-level ground truth:
[spec.md](spec.md) → Data Schemas; added 2026-07-27, → D-26). Those resources collectively
**are** the tag-source mapping below — the table is the human-readable statement of what the
data says, not a separate source of truth. This is required, not merely convenient: the
inert-land invariant demands `BARE_TAGS` be derived from the mapping at validation time and
never hardcoded, which is impossible while the mapping exists only as prose.

| Field | Meaning |
|---|---|
| `id`, `display_name` | identity |
| `emitted_tags` | tags emitted — empty for wild grass, and legitimately so |
| `cost` | Wood per tile (0 for natural terrain) |
| `model_scenes` | `Array[PackedScene]` — one or more interchangeable visuals (→ D-42; was the single-scene `model_scene`). A tile picks one **stably** via `pick_variant(x, z)`, hashing the tile coordinates with the terrain's `id`, so no per-tile choice is stored in save data. Shipped counts: `cultivated_field` 26, `rock` 6, `forest` 5, `grass` 4, `water`/`meadow`/`scrub`/`snowfield` 3 each, **`wild_grass` exactly 1 (→ D-56)** |
| `blocks_movement` | bool — whether a resident may walk this tile. Read by `WorldNavigation`; affects roaming only, never tags, capacity, or placement |
| `harvestable` | optional `HarvestableTileDefinition`, or null |

Adding a new terrain type is the **Add-a-Terrain** pipeline (gdd.md → AI Architecture →
Content Pipelines): the proposal covers emitted tags, plus harvestable resource type if
any; data entry is the `TerrainDefinition`; extending the shared tag vocabulary itself is
always a system-wide design decision, never a pipeline default.

### Harvestable terrain (`HarvestableTileDefinition`)

One per resource-producing tile (ground truth: [spec.md](spec.md) → Data Schemas):

| Field | Meaning |
|---|---|
| `id`, `display_name` | identity |
| `resource_type` | what it produces — **Wood** in v1 (field stays multi-valued for the deferred multi-resource system, [future.md](future.md)) |
| `land_use` | `cultivated` \| `wild` |
| `removes_habitat_when_harvested` | bool (Forest: false — zero-downside by design) |

*No `model_scene`* (→ D-26) — the model lives on the host `TerrainDefinition`. The split exists so two terrains can share one yield rule; a shared rule cannot own a model.

### Cost

| Action | Cost | Notes |
|---|---|---|
| Paint natural terrain (grass, water, rock, forest, meadow, scrub, snowfield) | Free | the recovery guarantee |
| Paint cultivated field | 2 Wood / tile | fencing & tools |

Removal/refund follows the uniform grace-window policy shared with buildings — see
Controls in gdd.md.

## Already-Defined Terrain

**Habitat tag vocabulary** (extended 2026-09-04 by the habitat-tiers ruling, → D-52;
full vocabulary and the qualification/capacity mechanics that read it: gdd.md → Habitat
Suitability):

- **Terrain-emitted:** `water` · `forest` · `open_grass` · `browse` · `flowers` ·
  `sand` · `rocks` · `cultivated` · `snow`
- **Building-emitted:** `built` · `house` · `large_house` · `barn` · `large_barn` ·
  `stable` · `coop` · `silo` · `mill`
- **Resident-emitted:** `people` · `deer` — contributed by a *resident animal*, not by a
  tile (see gdd.md → Habitat Suitability)

**`quiet` was retired.** It had no source and no consumer, and a `built` exclusion limit
does its job strictly better: it is actually enforced, and it needs no terrain to emit it.

**`cover` was retired too (2026-09-07, → D-52).** The tier re-spec left it with a source
but no consumer — Fox moved to `forest`/`open_grass`/`water`, Rabbit to
`open_grass`/`cultivated` — so it went the way of `quiet`. Rock now emits `rocks` alone,
which Donkey, Alpaca, Shiba Inu and Stag all need, so Rock's place is unchanged and there
is no gameplay effect.

**Two tags still have no consuming species:** `sand` — which is worse off than that, since no
shipped terrain *emits* it either, there being no sand terrain — and `coop` (emitted by the
Chicken Coop, but Chicken has no `AnimalDefinition` — its asset was never purchased). Both are
deliberate, not oversights.

**Tag-source mapping** (decided — and with #5 closed, this table *is* the complete
emission model; per-tag "counts as met" thresholds under #6 are likewise not part of v1):

| Source | Emits |
|---|---|
| Grass | `open_grass` |
| **Meadow** *(new, 2026-09-04)* | `open_grass` · `flowers` |
| **Scrub** *(new, 2026-09-04)* | `browse` · `rocks` |
| **Snowfield** *(new, 2026-09-04)* | `snow` |
| Water | `water` |
| Forest | `forest` |
| Rock | `rocks` |
| ~~Sand~~ *(never built — no `TerrainDefinition`)* | *would be* `sand` |
| Cultivated field | `cultivated` |
| Wild grass *(untouched revealed land)* | *nothing — tag-inert* |
| *Buildings* — every placeable emits `built` plus its own tags | see [buildings.md](buildings.md) |

**The three new terrains.** **Meadow** is rich grazing, and it finally gives the dormant
`flowers` tag a source. **Scrub** is rough grazing: `browse` versus `open_grass` is the
real ecological browser/grazer split, and it is what separates Donkey and the Deer herd
tier from every grass-eater. Note that Scrub is the *"wild grass with tags"* idea made
real — actual wild grass stays deliberately inert and is unchanged. **Snowfield** is Husky
habitat, and **may border grass**: the game is not restricted to real-world climate
adjacency (human ruling, 2026-09-04), so no placement or neighbour gating exists.

All three are natural terrain and therefore **free to paint**, per the one pricing rule.
Art for all three came from packs already imported, licence-cleared and attributed — the
Ultimate Nature Pack's snow variants, and the Stylized Nature MegaKit's flowers, ferns,
bushes and tall grass. No new sourcing gate was opened.

**Rock, not forest, was the `cover` source** — a tag retired at D-52 once nothing consumed
it. Kept here as history because it explains a design idea worth remembering: it made Fox
habitat a two-brushstroke
composition (forest *near* rock), never a side effect of painting forest for Wood (see
[roster.md](roster.md)).

**Forest** is v1's sole harvestable: it passively produces Wood (~1 Wood per Forest
tile per 60 s — Open Question #8) and never removes tags or disturbs residents when
tended. It is free to paint, which is v1's no-dead-ends guarantee: a player at zero Wood
can always paint Forest, wait, and build again.

**Terraform mechanics stay paint-bucket-simple:** one Forest tile grows one tree, and a farm is an *area* painted a few taps at a time — **single-tap in v1** (#17 closed; drag-to-paint is depth, row 3).

**Wild grass** is what untouched revealed land looks like: visually grass-family but
**tag-inert** — it emits nothing, so it never satisfies any species or raises any
neighborhood's carrying capacity on its own (the inert-land invariant, gdd.md → World
Structure). One free Terraform tap converts it to true grass. Visual treatment for how
it reads as "wild" without reading as broken is Open Question #29.

**Floor terrain (Tier 1):** five terrains — grass, water, forest, rock, cultivated.
**The shipped build is three past that floor** (meadow, scrub, snowfield, added 2026-09-04),
and sand — the sixth the floor was once counted against — was never built. Cultivated ships at the floor because capacity reads
cultivated tiles in radius, which the villager move-in needs; rock is the `rocks` source
(Open Question #5 resolved), consumed by Donkey, Alpaca, Shiba Inu and Stag — see gdd.md →
Scope, row 3.

**Tag-vocabulary note:** `flowers` gained a source on 2026-09-04 (Meadow) and a consumer
(Rabbit's warren tier). `coop` is emitted with no consuming species, and `sand` has neither
a source nor a consumer — both free to keep in the vocabulary, and each a natural first
post-class addition. `quiet` was retired
entirely; see the vocabulary block above for why.

## Open Questions Touching Terrain

Full list and resolution paths: [spec.md](spec.md) → Open Questions.

- ~~**#5** Tag-source mapping~~ — **closed** (→ D-25): tags are per-tile, no radii or weights. Emission radii and weights are depth (row 6)
- **#8** Cost-table values — passive Wood rate, cultivated-field cost
- ~~**#17** Terraform brush~~ — **closed** (→ D-25): single-tap. Drag-to-paint is depth (row 3)
- **#29** Wild-grass visual treatment — reads as "wild" without reading as broken
