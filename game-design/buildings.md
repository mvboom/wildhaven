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
Habitat Suitability). v1 ships **ten** buildables (2026-09-04, → D-52): House, Farmhouse, and eight farm
buildings. Each declares its own `emitted_tags`, and every one of them emits `built`. (Farms are not buildings — a
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

**Ten buildables ship** (2026-09-04, → D-52). Until that ruling the House was the only
one carrying `emitted_tags`; the eight farm buildings were imported, licence-cleared,
costed and hotbar-categorised but emitted **nothing**, making them placeable decoration
with no simulation meaning. They now have a job.

| Buildable | Footprint | Emits | Cost |
|---|---|---|---|
| House | 1×1 | `built` · `house` | ~15 Wood |
| **Farmhouse** *(new)* | 2×2 | `built` · `house` · `large_house` | ~30 Wood |
| Small Barn | 1×1 | `built` · `barn` | ~15 Wood |
| Large Barn | 2×2 | `built` · `barn` · `large_barn` | ~30 Wood |
| Open Barn | 1×1 | `built` · `barn` · `stable` | ~15 Wood |
| Chicken Coop | 1×1 | `built` · `coop` | ~15 Wood |
| Silo | 1×1 | `built` · `silo` | ~15 Wood |
| Windmill | 1×1 | `built` · `mill` | ~15 Wood |
| Well | 1×1 | `built` · `water` | ~15 Wood |
| Water Tower | 1×1 | `built` · `water` | ~15 Wood |

*Costs and footprints beyond House's are **proposals awaiting sign-off**, stated in each
`.tres` header — see the note at the end of this section.*

**Every placeable emits `built`, and that is load-bearing.** It lets a wild species carry
one exclusion limit (`built ≤ N`) instead of enumerating nine building tags, and it means
any building added later automatically participates in every wild species' exclusion
without touching a single species file.

**Three subsumptions are deliberate.** A large barn *is* a barn, so Large Barn satisfies both
`barn` and `large_barn`. An open-sided barn *is* a stable, so Open Barn serves cows or
horses from one building. A farmhouse *is* a house, so it still shelters dogs and single
villagers while also unlocking villager families.

**Well and Water Tower emit `water`** — the same tag a lake emits. That is what delivers
"a pond and/or a water tower" with no new tag: a lake and a tower satisfy the same need,
trading tiles against Wood.

**Farmhouse replaces the House's old 2×2 "form".** The 2×2 role is now its own buildable,
not a House variant — which is what lets `large_house` exist as a requirement at all, and
is what a villager *family* gates on (see [roster.md](roster.md)). A House is still a home
site with a fixed footprint, supporting villagers via carrying capacity exactly like any
other species' home site. **A villager moves in when its habitat is met** ships whole at
the floor — the USP requires the proof, not the building (see gdd.md → Scope, row 4).

**Floor building (Tier 1):** House at 1×1, grass only. The 1×1 asset is retained
post-deepening as a **Shed** placeable rather than thrown away (deferred —
[future.md](future.md)).

**Deferred buildings** (designed, not yet built — full detail: [future.md](future.md)):
Fence and Birdhouse (small placeables, allowed-terrain list open), the Shed (the
retained 1×1 House asset), Townscaper-style building joining (adjacent same-type
buildings merge and re-style), and species amenities (a special placeable that
delights or attracts a particular species, for every species — Well/School/Market for
villagers exactly as a birdhouse is for birds).

**Values awaiting sign-off.** Every cost, footprint and model choice for the nine
buildables beyond House is a **proposal, not a decision** — each `.tres` says so in its
own header, per the project rule that all tuning values are the human's. Farmhouse's
`cost = 30` and `footprint = 2×2` were copied from Large Barn's own unresolved proposal, and its
model (`HouseSecondage1Level3`, now `HouseMedium` — see the look-pool note below) was picked
as the largest already-wired House variant so it reads as bigger than the 1×1 House.

**House look pool cut 18 → 3 (2026-09-07, human ruling).** The House buildable offered
eighteen interchangeable looks in its `model_scenes`; it now offers three, all from the
`Houses_SecondAge_1_Level{1,2,3}` sub-family, renamed for the player:

| `model_scenes` idx | style id | picker label | source glTF |
|---|---|---|---|
| 0 | `house_large` | House - Large | `Houses_SecondAge_1_Level1` |
| 1 | `house_medium` | House - Medium | `Houses_SecondAge_1_Level3` |
| 2 | `house_small` | House - Small | `Houses_SecondAge_1_Level2` |

This closes the unresolved height-rule question the 2026-08-26 and 2026-08-29 growth passes
left open (how to reconcile eighteen variants spanning 2.66× in height) by not shipping
eighteen: the three survivors span 1.29×. The other fifteen wrappers **stay on disk, unwired** —
same posture as the `house_secondage_2_level{2,3}` hold-out — so their import tests, attribution
entries and CREDITS lines remain true statements about what the repo contains.

Note the labels are the human's names for how each building *reads*, not a height ranking:
`house_medium` is in fact the tallest of the three. Note also that Farmhouse (2×2) and the
House's `house_medium` look (1×1) now render the **same mesh at two footprints** — already true
before the cull, merely easier to notice at three variants than at eighteen. Raised, not decided.

Three model-centring corrections landed with the cull: all three of these meshes were off-centre
on their own origin in the source glTF (`house_medium`/`house_small` by 0.1622 units in Z), so a
placed House overhung its neighbouring tile. Each wrapper now carries a translation that is
exactly the negation of its measured AABB centre — a measurement, not a tuning value. It went
unnoticed for the same reason a lot of variant defects do: `test_building_footprint_alignment.gd`
only spill-checks `model_scenes[0]`, and index 0 used to be a different model.

## Open Questions Touching Buildings

Full list and resolution paths: [spec.md](spec.md) → Open Questions.

- **#8** Cost-table values — House cost, starting stockpile sizing
- **#16** Refund/grace tuning — exact grace-window seconds and recycle percentage
- **#18** Footprints & world dimensions — final House footprint sizes
- **#26** Starting Wood stockpile — exact value (sized to cover the House plus a small field)
