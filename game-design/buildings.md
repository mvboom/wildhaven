# Wildhaven — Buildings

> Authoritative for what a building is, what data every buildable carries, and which
> buildings are already decided. Split out of [gdd.md](gdd.md), which keeps only a
> summary and defers here for detail. The habitat-tag vocabulary and carrying-capacity
> formula a building's `emitted_tags` feed into are cross-cutting mechanics that
> [roster.md](roster.md) and [terrain.md](terrain.md) also read, so they stay in
> gdd.md under **Habitat Suitability**; this document covers what varies **per
> building**. Field-level schema ground truth is [spec.md](spec.md); nothing here
> overrides it.

## What a Building Is

A building is a placeable structure with a fixed tile footprint, placed onto eligible
terrain via **Build Mode**: pick a building, tap an eligible tile to place its whole
footprint at its Wood cost. Unlike terrain, a building occupies its footprint
exclusively — a tile under a building stops emitting its terrain tags while occupied,
and the building's own `emitted_tags` are what that ground now says (see gdd.md →
Habitat Suitability). v1 ships one buildable, the House. (Farms are not buildings — a
farm is cultivated terrain painted in Terraform Mode; see [terrain.md](terrain.md).)

## Attributes Required (PlaceableDefinition)

One `PlaceableDefinition` per buildable (ground truth: [spec.md](spec.md) → Data Schemas):

| Field | Meaning |
|---|---|
| `id`, `display_name` | identity |
| `cost` | placement cost (resource amounts — see Economy in gdd.md) |
| `footprint` | tile footprint |
| `allowed_terrain` | terrain types the footprint may occupy — every placeable declares this, and goes only where *every* footprint tile is allowed; ineligible tiles don't accept the tap (a soft cue, never an error) |
| `emitted_tags` | habitat tags emitted (e.g. House → `house`) |
| `model_scenes`, `fact_text` | model look variant(s) + flavor copy — an `Array[PackedScene]` (2026-08-26, building-variety B1). Unlike `TerrainDefinition`/`AnimalDefinition` there is **no `pick_variant()`**: every placed instance of a buildable shows the same look, so placement reads index 0. Letting the player choose which look sits at index 0 is sub-project B2's job, not this schema's. |

*(The former AmenityDefinition — with `happiness_bonus` — was cut with the amenity
system. When species amenities return, they return as PlaceableDefinitions whose
`emitted_tags` target a species, not a new schema — see [future.md](future.md).)*

### Placement rules

- **No rotation logic** — every building has one fixed facing; buildings themselves never
  rotate, independent of the camera. D-13/D-41's original reasoning was that a fixed,
  no-rotation camera meant a building was only ever seen from one side; **D-44 reopened
  that narrowly** — the camera now rotates in four fixed 90°-apart headings, so a building
  IS now seen from more than one angle. Playtest of D-44's spike did not surface a
  structural problem (missing geometry, wrong-facing texture) from the rotated angles, but
  a full human art pass over the building/placeable roster at all four headings is still
  open — see D-44's own "not exhaustively art-reviewed" note.
- **Placing a building over a home prop is the same event as any capacity-loss edit:**
  warned, then a gentle relocation — props block nothing, but are never silently
  deleted (see Gentle Displacement in gdd.md).
- **Houses build on grass only** closes the *footprint-overlap* eviction family at the
  source, but **not** capacity-loss displacement: footprint tiles stop emitting
  terrain tags, so a build can drop capacity with no overlap at all — which is why the
  displacement warning is mode-agnostic, firing from Build Mode exactly as from
  Terraform Mode.
- **Removal/refund** follows the uniform grace-window policy shared with terrain — see
  Controls in gdd.md: within the grace window (~10–15 s), removal refunds 100%; after
  it, a flat recycle percentage (placeholder ~50%, tunable).

Adding a new building type is the **Add-a-Building** pipeline (gdd.md → AI
Architecture → Content Pipelines): the look pass adds one fixed variant, one fixed
facing; the proposal covers footprint, cost, and emitted tags; data entry is the
PlaceableDefinition; copy is inspect-tap flavor; validation covers footprint/placement
and render.

## Already-Defined Buildings

**House** — the only v1 buildable, satisfying the `house` tag:

| Form | Footprint | Allowed terrain | Cost |
|---|---|---|---|
| Floor (Tier 1) | 1×1 | grass only | ~15 Wood |
| Full | 2×2 | grass only | ~30 Wood |

A House is a home site with a fixed footprint. It supports villager families via
carrying capacity exactly like any other species' home site: cultivated tiles within
radius set how many families it supports (floor: the 1×1 House supports one family,
since Human's `tiles_per_individual` divisor is 1 against a single-tile footprint; the
2×2 form lets a broad farm support up to four — see [roster.md](roster.md)). **A
villager moves in when its habitat is met** ships whole at the floor — the USP requires
the proof, not the building (see gdd.md → Scope, row 4).

**Floor building (Tier 1):** House at 1×1, grass only. Depth buys the 2×2 footprint and
its placement-validation family; the 1×1 asset is retained post-deepening as a **Shed**
placeable rather than thrown away (deferred — [future.md](future.md)).

**Deferred buildings** (designed, not yet built — full detail: [future.md](future.md)):
Fence and Birdhouse (small placeables, allowed-terrain list open), the Shed (the
retained 1×1 House asset), Townscaper-style building joining (adjacent same-type
buildings merge and re-style), and species amenities (a special placeable that
delights or attracts a particular species, for every species — Well/School/Market for
villagers exactly as a birdhouse is for birds).

## Open Questions Touching Buildings

Full list and resolution paths: [spec.md](spec.md) → Open Questions.

- **#8** Cost-table values — House cost, starting stockpile sizing
- **#16** Refund/grace tuning — exact grace-window seconds and recycle percentage
- **#18** Footprints & world dimensions — final House footprint sizes
- **#26** Starting Wood stockpile — exact value (sized to cover the House plus a small field)
