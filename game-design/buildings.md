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
exclusively — every tile under a building stops emitting its terrain tags while occupied.

**A building emits its tags ONCE, at its centre tile (→ D-60), however many tiles it covers.**
The rest of its footprint is occupied and terrain-suppressed but emits nothing at all. This is
not an optimisation, it is what keeps a building's *habitat* meaning independent of its *size*:
a tag count is a count of tiles, so before this rule a 3×3 barn counted as nine barns and a 2×2
water tower as four ponds. Every `built` ceiling in [roster.md](roster.md) — rabbit's "a distant
cottage is fine, a village is not" — therefore still means what it was ruled to mean, and will
keep meaning it the next time a footprint changes. **Centre and not origin** because the emitting
tile is what radius checks measure to; an origin corner sits up to 1.41 tiles off a 3×3 building's
visual centre, enough to fall outside the horse's radius-5 `stable` need when the barn plainly
looks inside it (see gdd.md → Habitat Suitability). v1 ships **ten** buildables (2026-09-04, → D-52): House, Farmhouse, and eight farm
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
| House | 2×2 | `built` · `house` | ~15 Wood |
| **Farmhouse** | 3×3 | `built` · `house` · `large_house` | ~30 Wood |
| Small Barn | 2×2 | `built` · `barn` | ~15 Wood |
| Large Barn | 3×3 | `built` · `barn` · `large_barn` | ~30 Wood |
| Open Barn | 2×2 | `built` · `barn` · `stable` | ~15 Wood |
| Chicken Coop | 1×1 | `built` · `coop` | ~15 Wood |
| Silo | 2×2 | `built` · `silo` | ~15 Wood |
| Windmill | 2×2 | `built` · `mill` | ~15 Wood |
| Well | 1×1 | `built` · `water` | ~15 Wood |
| Water Tower | 2×2 | `built` · `water` | ~15 Wood |

**Footprints were re-cut 2026-09-08 (→ D-60), and costs deliberately were not.** Buildings had
been sized by a normalisation convention inherited from the first House batch, never against a
person: a villager is exactly 1.0 tile tall and every 1×1 building's mesh stood *shorter* than
that — a house nobody could walk into, a stable shorter than the horse. The ladder above is the
result, with the model scaled to fill its plot in each case. Holding cost fixed means
wood-per-tile-claimed fell; that is a known consequence, noted against #8/#26, not an oversight.

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

**Farmhouse is the large-house role as its own buildable,** not a House variant — which is what
lets `large_house` exist as a requirement at all, and is what a villager *family* gates on (see
[roster.md](roster.md)). It is now 3×3 against the House's 2×2 (→ D-60): once every former 1×1
went to 2×2, Farmhouse and House were the same size and `large_house` had no size of its own left.
A House is still a home site with a fixed footprint, supporting villagers via carrying capacity
exactly like any other species' home site. **A villager moves in when its habitat is met** ships whole at
the floor — the USP requires the proof, not the building (see gdd.md → Scope, row 4).

**Floor building (Tier 1):** House at 2×2, grass only (→ D-60; it was 1×1 from D-29 until
2026-09-08). The footprint is the only thing that moved — the floor is still "a simple house,
grass only", and every placement rule, cost and tag is unchanged. A 1×1 **Shed** placeable is
still designed and still deferred ([future.md](future.md)), but it is no longer a way of reusing
the House's old asset: the House kept its meshes and merely got bigger.

**Deferred buildings** (designed, not yet built — full detail: [future.md](future.md)):
Fence and Birdhouse (small placeables, allowed-terrain list open), the Shed (a 1×1
placeable in its own right since D-60, no longer the retained House asset),
Townscaper-style building joining (adjacent same-type
buildings merge and re-style), and species amenities (a special placeable that
delights or attracts a particular species, for every species — Well/School/Market for
villagers exactly as a birdhouse is for birds).

**Values awaiting sign-off.** Every **cost** for the nine buildables beyond House is still a
**proposal, not a decision** — each `.tres` says so in its own header, per the project rule that
all tuning values are the human's. **Footprints are no longer in that set:** the ladder above was
ruled by the human on 2026-09-08 (→ D-60), building by building, against a rendered scale
comparison. What remains open on footprints is #18's other half — world start size and cap — plus
a human eye pass on facing, which no footprint ruling touched.

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
`house_medium` is in fact the tallest of the three.

**The shared-mesh problem this section used to raise is CLOSED (2026-09-08, → D-60).** Farmhouse
and the House's `house_medium` look used to render the same mesh at two footprints. The Farmhouse
now has its own model — `assets/buildings/house1/House1.tscn`, from Quaternius's "Buildings Pack -
Jan 2019" (CC0 1.0, its own attribution entry) — standing ~2.14 units against the House's
1.41–1.82 and the villager's 1.00. That was not cosmetic: while the two rendered the same mesh, a
bigger footprint just meant the same house in more space, and `large_house` has to out-read `house`
on sight, not only on tile count.

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
