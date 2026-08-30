# Wildhaven — Terrain

> Authoritative for what terrain is, what data every terrain type carries, and which
> terrains are already decided. Split out of [gdd.md](gdd.md), which keeps only a
> summary and defers here for detail. The shared habitat-tag vocabulary and the
> carrying-capacity formula that terrain tags feed are cross-cutting mechanics that
> [roster.md](roster.md) also reads, so they stay in gdd.md under **Habitat
> Suitability**; this document covers what varies **per terrain type**. Field-level
> schema ground truth is [spec.md](spec.md); nothing here overrides it.

## What Terrain Is

Terrain is the tile-level surface type covering the world grid — grass, water,
forest, rock, sand, cultivated fields, and (behind the mist) wild grass. The player
paints it directly in **Terraform Mode**: pick a terrain, **one tap converts one tile**
(#17 closed — drag-to-paint is depth). **Each tile carries the habitat tags its own
terrain emits — tags do not spread to neighbouring tiles** (the v1 tag model, → D-25;
full statement in [spec.md](spec.md) → Shared Patterns). "Nearby" is expressed entirely
by the *species'* radius, not by any radius belonging to the terrain. The player never
manages tags directly (see gdd.md → Habitat Suitability). Terrain is
the substrate everything else builds on: buildings occupy terrain footprints (see
[buildings.md](buildings.md)), and the roster's habitat needs are satisfied by terrain
tags (see [roster.md](roster.md)).

**The one pricing rule:** *"Nature is free; construction costs materials."* Natural
terrains (grass, water, forest, sand, rock) are free to paint; cultivated fields cost
Wood — see Economy in gdd.md for the full resource narrative.

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
| `model_scene` | model reference |
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
| Paint natural terrain (grass, water, sand, rock, forest) | Free | the recovery guarantee |
| Paint cultivated field | ~2 Wood / tile | fencing & tools |

Removal/refund follows the uniform grace-window policy shared with buildings — see
Controls in gdd.md.

## Already-Defined Terrain

**v1 habitat tag vocabulary:** `water` · `forest` · `open_grass` · `quiet` · `cover` ·
`flowers` · `sand` · `rocks` · `cultivated` · `house` (full vocabulary and the
qualification/capacity mechanics that read it: gdd.md → Habitat Suitability).

**v1 tag-source mapping** (decided — and with #5 closed, this table *is* the complete
emission model; per-tag "counts as met" thresholds under #6 are likewise not part of v1):

| Source | Emits |
|---|---|
| Grass | `open_grass` |
| Water | `water` |
| Forest | `forest` |
| Rock | `cover` · `rocks` |
| Sand | `sand` |
| Cultivated field | `cultivated` |
| House *(a building, not terrain — see [buildings.md](buildings.md))* | `house` |
| Wild grass *(untouched revealed land)* | *nothing — tag-inert* |

**Rock, not forest, is the `cover` source**, so Fox habitat is always a two-brushstroke
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

**Floor terrain (Tier 1):** five of the six v1 terrains — grass, water, forest, rock,
cultivated (sand is depth). Cultivated ships at the floor because capacity reads
cultivated tiles in radius, which the villager move-in needs; rock is the v1 `cover`
source for Fox and Rabbit (Open Question #5 resolved) — see gdd.md → Scope, row 3.

**Tag-vocabulary note:** `quiet`, `flowers`, and `sand` have no consuming species in
v1 but stay in the vocabulary — free to keep, and a natural first post-class addition.

## Open Questions Touching Terrain

Full list and resolution paths: [spec.md](spec.md) → Open Questions.

- ~~**#5** Tag-source mapping~~ — **closed** (→ D-25): tags are per-tile, no radii or weights. Emission radii and weights are depth (row 6)
- **#8** Cost-table values — passive Wood rate, cultivated-field cost
- ~~**#17** Terraform brush~~ — **closed** (→ D-25): single-tap. Drag-to-paint is depth (row 3)
- **#29** Wild-grass visual treatment — reads as "wild" without reading as broken
