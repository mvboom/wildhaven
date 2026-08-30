# Wildhaven — Build Contract

> The field-level contract behind [gdd.md](gdd.md). `gdd.md` states every principle and
> every number that matters to play; this document holds the schemas, layouts, tuning
> tables, and open items that development builds against. Nothing here overrides
> `gdd.md` — where they appear to disagree, `gdd.md` is the design and this is a defect.
> Design-level detail for the roster, terrain, and buildings — what each is, and which
> specific species/terrains/buildings are already defined — lives in
> [roster.md](roster.md), [terrain.md](terrain.md), and [buildings.md](buildings.md);
> the schemas below are the field-level contract shared by all three.

## Data Schemas

The game's content is data-driven end to end: **adding content means filling out a data entry, not writing code.** These schemas are the contract that development — human and AI — builds against, and this document is ground truth for them. Each definition is a Godot custom Resource (`.tres`), editable in-editor.

**AnimalDefinition** — one per species (villagers included):

| Field | Meaning |
|---|---|
| `id` | unique species id |
| `display_name` | player-facing name |
| `habitat_needs` | list of required habitat tags |
| `personality` | `Shy` \| `Bold` (visibility trait) — stored as a **String** so the `.tres` self-documents; `validate()` is therefore load-bearing (the type system can't reject a bad value) |
| `avoids` | animal ids to keep mutual distance from (optional; symmetric). **Stored as ids (`Array[String]`), never resource references** — a `res://` reference to a not-yet-authored species is a hard load failure, whereas a bad id is inert text that degrades to nothing (behaviorally correct, since avoids never gates a move-in) |
| `farm_tolerant` | bool — can live on cultivated land |
| `scout_radius` | tiles; the radius over which habitat needs are scored (~8–12; Open Question #20). Lives in data, not code |
| `capacity_radius` | tiles; the radius over which carrying capacity counts tags (v1 default: equal to `scout_radius`; may diverge per species — Open Question #23) |
| `tiles_per_individual` | the capacity formula's divisor — with no lower clamp, `capacity = 0` is expressible; see Habitat Suitability in [gdd.md](gdd.md) |
| `max_individuals` | hard per-home-site cap — a readability bound, never the normal-play limit |
| `model_scenes` | `Array[PackedScene]` — one or more interchangeable look variants for this species (added 2026-08-26; was the single-scene `model_scene`, the same shape change D-42 made for `TerrainDefinition`). A resident picks one entry **stably**: `AnimalDefinition.pick_variant(index)` hashes the resident's index within its home site's `residents` array, which is append-only for a resident's whole lifetime and rebuilt in the same order by `HabitatSimulation.restore_site()` — so a villager keeps the same look across a save/load round trip **with no per-resident choice stored in save data**. `human.tres` ships 5 entries (Adventurer/Man/Woman/Hoodie/Punk, equal weight); every other species ships one |
| `fact_text_pool` | fact-card copy pool (→ D-47). The game currently reads only index 0 — no rotation UI exists yet |

*(No field holds the model's world scale or footprint: scale lives in the model's own wrapper scene, and animals occupy no tiles.)*

**PlaceableDefinition** — one per buildable (House in v1's floor; more arrive as post-class content):

| Field | Meaning |
|---|---|
| `id`, `display_name` | identity |
| `cost` | placement cost (resource amounts — see Economy in [gdd.md](gdd.md)) |
| `footprint` | tile footprint (House: 2×2 full form, 1×1 thin form) |
| `allowed_terrain` | terrain types the footprint may occupy (House: grass only) |
| `emitted_tags` | habitat tags emitted (e.g. House → `house`) |
| `model_scenes`, `fact_text` | model look variant(s) + flavor copy — an `Array[PackedScene]` (2026-08-26, building-variety B1). **No `pick_variant()`**, unlike `TerrainDefinition`/`AnimalDefinition`: every placed instance of a buildable shows the same look, so placement reads index 0; choosing which look sits there is sub-project B2's. |

*(The former AmenityDefinition — with `happiness_bonus` — was cut with the amenity system. When species amenities return, they return as PlaceableDefinitions whose `emitted_tags` target a species, not a new schema.)*

**TerrainDefinition** — one per terrain type, including wild grass (added 2026-07-27, → D-26):

| Field | Meaning |
|---|---|
| `id`, `display_name` | identity |
| `emitted_tags` | habitat tags this terrain emits — **may legitimately be empty**; wild grass emits nothing, and that emptiness is what makes the inert-land invariant structural rather than asserted |
| `cost` | Wood to paint one tile (0 for natural terrain — *"nature is free"*) |
| `model_scenes` | `Array[PackedScene]` — one or more interchangeable visuals for this terrain (added 2026-08-16, → D-42; was the single-scene `model_scene`). A given tile picks one entry **stably**: `TerrainDefinition.pick_variant(x, z)` hashes the tile coordinates together with the terrain's own `id`, so the same tile always shows the same variant across reloads while different tiles of the same terrain can land on different variants — with no per-tile choice stored in save data. As of the 2026-08-26 content-variety pass, `forest` ships 8 entries, `cultivated_field` 26, `rock` 6, `wild_grass` 4, `water` 3, and `grass` 2 (grass's 2 predate that pass). **Weighting is uniform across whatever the array holds** — there is no weight field and none is planned here, so a terrain's original single look is now shown on only `1/N` of its tiles; whether that ratio is right per terrain is an open human call, flagged in `water.tres`'s and `wild_grass.tres`'s own headers |
| `harvestable` | optional `HarvestableTileDefinition`, or null. Non-null only for Forest in v1 |

*This resource is what makes the tag-source mapping **data**, which the inert-land invariant below requires: `BARE_TAGS` must be derived "at validation time, never hardcoded," and a derivation needs something to derive from. `TerrainDefinition.derive_bare_tags()` returns the `wild_grass` entry's tags. **The derivation is vacuously satisfied if no `wild_grass` entry exists**, so its existence is asserted separately in `test_bare_tags_derivation.gd` — an empty result must mean "wild grass emits nothing," never "wild grass is missing."*

**HarvestableTileDefinition** — one per resource-producing tile:

| Field | Meaning |
|---|---|
| `id`, `display_name` | identity |
| `resource_type` | what it produces — **Wood** in v1 (field stays multi-valued for the deferred multi-resource system) |
| `land_use` | `cultivated` \| `wild` |
| `removes_habitat_when_harvested` | bool (Forest: false — zero-downside by design) |

*No `model_scene` (→ D-26).* This resource is a **yield rule**, not a thing on the ground — the model belongs to the host `TerrainDefinition`. That is also why it stays a separate resource rather than fields folded into terrain: two terrains can share one yield rule (a future Old-Growth Forest producing Wood on identical terms), and a shared rule cannot own a model.

**Shared patterns:**

- **Habitat tag vocabulary (v1):** `water`, `forest`, `open_grass`, `quiet`, `cover`, `flowers`, `sand`, `rocks`, `cultivated`, `house` — the single vocabulary shared by terrain emission and animal needs in v1, and by the deferred tag-driven audio and climate layers when they land (future.md).
- **The tag model (v1) — tags are a property of the tile, not a field radiating from it (→ D-25).** A tile's tag set is a pure function of what occupies it: its terrain type, or its building's `emitted_tags` where a footprint suppresses the ground. **Tags do not spread to neighbouring tiles**, carry no per-source emission radius, and have no distance weighting. `count_t` in the capacity formula is therefore a plain count: *the number of tiles within the species' radius whose own terrain (or building) emits `t`*. There is no "counts as met" threshold per tile — a tile either emits a tag or it does not.
  **This is the whole model, and it is sufficient.** The design intent it appears to threaten survives: Fox needs `forest` **and** `cover`, and with a species radius of 8–12 tiles, "both present within the radius" already *is* "forest near rock" — the two-brushstroke composition holds without any diffusion. Emission radii, per-source weights, and threshold curves are **depth** (Tier 1 row 6, "tag radius richness"), not v1.
  *Implementation note:* this makes a neighbourhood evaluation one pass over the tiles in radius, tallying a small fixed set of tag counters — no second nested loop, which is what keeps the `radius × roster` cost bound in gdd.md → Performance honest.
- **The inert-land invariant.** Untouched revealed land must never satisfy any species on its own — nor raise any existing neighborhood's carrying capacity — or pushing the mist becomes a reward and animals arrive (or multiply) on land the player never made, breaking both the mist pillar and the rule that every resident is something the player attracted. **v1 enforces this structurally:** untouched revealed land is *wild grass*, which emits no tags at all (see World Structure in [gdd.md](gdd.md)), so `BARE_TAGS` — the set of tags untouched land emits — is empty by construction, and the invariant covers qualification *and* capacity in one stroke, because both are functions of tag counts and wild grass contributes zero to either. The automated check in the `.tres` validation suite remains, guarding the construction itself: it derives `BARE_TAGS` **from the tag-source mapping at validation time, never hardcoded** — otherwise the check silently rots the first time tag emission changes — and fails the build if any source ever gives untouched land a tag; the qualitative subset check (**no species' `habitat_needs` ⊆ `BARE_TAGS`**) stays as the backstop for that future. The Add-an-Animal pipeline inherits the gate for free.
- **News Report content** is a per-animal (or general) text pool reusing the fact-card pipeline.
- **Save file** is JSON with a `save_version` field (full contents under Technical Overview → Saves in [gdd.md](gdd.md)).
- **Runtime instance state** (not in definition files): individual animals carry position, AI state, and home-site position.

## Fact-Card Content Checklist

**The checklist** (process defined; research/writing deferred): source only from reputable wildlife/education sources — the verified working set is **Animal Diversity Web**, **National Geographic Kids**, **The Wildlife Trusts**, and **National Geographic Society Education** (`education.nationalgeographic.org`, added 2026-07-28: a distinct publication from Nat Geo Kids, graded by reading level, and the source that carries material Nat Geo Kids does not — human origins and agriculture among it); no blog scraping; write original words, never copied text; 1–2 sentences, plain vocabulary, upbeat; a hard predation-framing check (a fox's card highlights hearing or family life, never diet; and because Rabbit now needs `cover`, rabbit copy frames cover as comfort — "a cozy spot out of the wind" — never as safety, hiding, or escape, which is precisely the predation-with-the-predation-removed trap); and a **graph check** — the structural predation check under Compatibility in [gdd.md](gdd.md), run for any species that carries an `avoids` entry. Register is **US English roster-wide** ("kits", never "cubs"). The same five-step checklist repeats for every animal added post-class, and News Report copy reuses it.

**Verification is the expensive, non-optional step** — it caught confidently-wrong-but-fully-approved copy in the pilots. The pilot-3 findings that shaped these rules — the fox-den error, the kits/kittens roster collision, European-rabbit-vs-cottontail precision, predation-facts-with-predation-removed, and the proposed fifth checklist step — are why the checklist reads as it does above. **Note:** Smithsonian's National Zoo has no red fox page (404) despite being an obvious candidate — do not assume a species has a page on a given site.

## Screen Layouts

Builder-facing layout intent for the UI Engineer. Exact pixel values and safe-area margins are implementation detail; the *arrangement* and *anchoring* below are the spec. All overlays are theme-consistent with the picture-book style (soft rounded panels, generous padding, large touch-friendly hit areas even on desktop, per Pillar 3).

**Persistent HUD (world view)** — corner-anchored so the center stays clear for the world:

```
┌─────────────────────────────────────────────┐
│ [🪵 Wood: 240]                    [Field Guide]│   top-left: resource + population counters (D-34); top-right: Field Guide
│ [Species Hosted: 4]                            │
│ [Currently Resident: 3]                        │
│ [Village Population: 6]                        │
│                 (world view)                   │
│                                                │
│ [Inspect][Terraform][Build]        [⚙][🏠 Home]│   bottom-left: mode switch
└─────────────────────────────────────────────┘    bottom-right: Settings, zoom-home
```

- **Mode switch** (bottom-left) is the primary control: three large buttons, current mode clearly highlighted. Selecting Terraform or Build opens its palette directly above the switch (a horizontal or grid strip of terrain/building icons). Inspect has no palette.
- **Top-left counters** (Wood, Species Hosted, Currently Resident, Village Population) are read-only indicators (Pillar 1), stacked at all times, at every zoom level and during the Home-key map peek alike. Never flash, never demand attention when low. Species Hosted is a bare running count with no denominator — it names a tally, not a ratio, per Pillar 1's indicator test (D-34).
- **Field Guide** (top-right).
- **Home + Settings** (bottom-right): Home snaps to full zoom-out; the gear opens the Settings overlay without pausing.

**Fact card** (fires on move-in; replays on Inspect-tap) — a centered card that never fills the screen (the world stays visible and simulating behind it):

```
┌────────────────────────────┐
│  [animal portrait]         │   the resident that moved in
│                             │
│                             │
│  Fox                    [🔊]│   species name + Read-Aloud button
│  ────────────────────────   │
│  1–2 sentence real fact,    │   large plain type, pre-fluent-friendly
│  upbeat, no predation.      │
│                        [✕]  │   dismiss (tap anywhere outside also dismisses)
└────────────────────────────┘
```

- The **Read-Aloud button** (🔊) is present on the scrim'd first-arrival fact card — floor and full alike. It is **not** on the right-side rolling feed (repeat fact cards, displacement warnings): those entries auto-expire in ~9 s, never auto-speak, and are not a consent surface, so each carries only a corner × dismiss. Wider coverage (News Reports, Field Guide) is deferred (future.md).
- On move-in the card fires where the animal actually settled, visible behind the card; on Inspect-tap it is paired with a small cute reaction.

**News Report** — a smaller, dismissable banner/toast (not a modal): slides in, never blocks input, auto-dismisses or is tapped away. The world keeps simulating.

**Resident inspect readout** — when Inspect-tapping a resident, the fact card/flavor panel appends one line: what the home neighborhood supports and how many live there (*"This meadow supports 6 · 4 live here."* — numeric-vs-qualitative form is Open Question #27).

## Pacing Constants

The invisible rhythm of the simulation, gathered in one place so every value is stated, owned, and tracked (values are placeholders; #28). None of these is a player-facing timer — they are all mechanics Pillar 1 already permits (randomised settling, not pressure).

| Constant | Placeholder | Resolution |
|---|---|---|
| Arrival delay (qualification → move-in) | 20–60 s randomised (thin build may stretch to ~90 s) | balancing/playtesting |
| **Time-to-first-move-in** (first paint → first resident) | **target ≤ 2 min, hard ceiling 5 min** | a *validation criterion*, not a timer — checked at the step-5 kid playtest; the arrival delay and starter-species needs are tuned until it holds. **Tap-rate-independent by construction:** arrivals enqueue on the edit, not at settlement, so excited tapping cannot defer a move-in (the settlement rule in [gdd.md](gdd.md)) |
| Grace window / settlement (see Controls in [gdd.md](gdd.md)) | ~10–15 s | balancing/playtesting (#16) |
| Autosave interval | ~1–2 min | implementation detail |
| Dirty-queue drain budget | N evaluations/frame | the CPU budget; first-playable validation |
| Passive Wood rate | ~1 Wood / forest tile / 60 s | balancing (#8) |
| House cost | 2×2 ~30 Wood — floor: 1×1 ~15 | balancing (#8, #26) |

Time-to-first-move-in is the number the First 60 Seconds hangs on: a 30-second wait and a 6-minute wait are different games for a seven-year-old, so the wait is bounded in the spec, not discovered in playtest. Measured from the player's first paint to the first resident.

## Tier 1 — What Deepening Buys

| # | System | What deepening buys |
|---|---|---|
| 1 | Start & persist | Preset variety, thumbnail select |
| 2 | Camera & modes | Camera *feel* — easing, framing polish, zoom-dependent detail (D-41 restores this depth axis after D-33's first-person interlude used mouse-look sensitivity/view-distance detail instead) |
| 3 | Terraform | Sand — more landscape variety; **drag-to-paint** (#17 closed to single-tap for v1) |
| 4 | Build | The 2×2 footprint and its placement-validation family; the 1×1 asset is retained as a Shed placeable (deferred — future.md) |
| 5 | Economy | Tap-to-tend (which also thickens Inspect Mode) |
| 6 | Habitat & move-in | Roam quality, scouting responsiveness, **tag radius richness** (emission radii, per-source weights, thresholds — the Model B the v1 tag model defers, #5), **pack/family group sizes** (#7), capacity scoring (geometric blend, diminishing curve — #24) |
| 7 | Fact cards | Card variants, richer card layout, Read-Aloud full coverage (News Reports, Field Guide) |
| 8 | The floor roster | Each species finished out of the nine-species cleared pool — one pipeline run apiece, and the expensive gates (audit, import, attribution) are already behind them |
| 9 | Minimal Avoids | A second pair from the cleared pool (village dogs are the natural candidate), plus tuning breadth |
| 10 | Gentle displacement | Rich affected-area preview, relocation animation |
| 11 | Species status | Per-species detail pages, Field Guide polish |
| 12 | Pointers | Per-species pools, outward-pointing mist invitations, volume |
| 13 | Mist | Organic chunk shapes, sprouting animation |
| 14 | A thin audio slice | *(already the floor — no travel)* |
| 15 | Settings & Credits | Separate Settings screen, per-channel sliders |

**Not depth axes.** These carry pillar or legal obligations and ship whole at thin depth: the three-mode tap model and the camera's "never lost" guarantee (the three safety rails — pan clamped, full zoom-out frames everything, Home one press away — restored 2026-08-14 by D-41 as the actual mechanism again, after D-33's 2026-08-03 first-person interlude used mouse-look + a Home-key map peek instead; the invariant that a 6–10 year old is never lost has shipped whole throughout, only the mechanism has changed twice); fact-card **tap-to-replay** (Pillar 4 delivers facts on success *and* curiosity); move-in causality ("only because a real spot met their needs"); the free-Forest recovery guarantee; gentle displacement's guarantee and no-unexplained-vanish rule; the Avoids symmetry rule and its copy framing; the Gameplay Hints toggle; fact-card **source verification** (pilot 3 shipped copy that was wrong and fully approved — only fetching sources caught it); and Credits/attribution.

## Open Questions

Explicitly undecided items, each with where its resolution is deferred. This section distinguishes *undecided* from *omitted* — if it's not here and not in the document, it isn't part of the design. Closed items #1–3 are omitted; this document starts at the build.

| # | Open item | Deferred to |
|---|---|---|
| 4 | **Final starter roster** — *narrowed:* the roster has **no target count** (→ D-24); it is a floor of three plus depth drawn from a nine-species cleared pool. **Fox and Rabbit shipped** (pilots 3, 3b); Human's fact card closed 2026-07-28 (→ #31, D-28). **Stale as of this note:** [content-pipeline-status.md](content-pipeline-status.md) records `human`'s `pre_import_audit: done`, but this row still lists the audit as open below — worth a pass to reconcile, not yet done. Open: a step-3 proposal per cleared-pool species as each is worked. Audit finding governing the rest: **animation, not species availability, is the scarce resource** (of 37 rabbit models across two CC0 libraries, exactly one was rigged and animated) | reconcile Human's audit status; then one step-3 proposal per pool species |
| 5 | **Tag-source mapping** — **CLOSED for v1 (→ D-25).** The source table is decided (full table: [terrain.md](terrain.md)), including rock as the `cover` source, **and the tag model is decided: tags are a per-tile property with no emission radius, no weights, and no thresholds** (Shared Patterns above). Emission radii, per-source weights, and whether forest emits *weak* `cover` all move to **depth** (row 6, "tag radius richness") — they are no longer open items blocking the build | closed — depth only |
| 6 | **Suitability thresholds** — *narrowed:* the qualification predicate `qualifies(h, S) ≡ capacity(h, S) ≥ 1` is decided (Habitat Suitability in [gdd.md](gdd.md)). Open: per-tag "counts as met" thresholds and the `tiles_per_individual` values (per-species table: [roster.md](roster.md)) | GDD refinement pass |
| 7 | **Instance counts** — *narrowed (→ D-25).* **Packs/families are accepted as the design direction**: species arrive as a social unit whose size varies by species. **v1 ships a uniform group size of 1** — the arrival predicate `capacity ≥ population + 1` already encodes this, so v1 needs no new field. Note the *ceiling* is not open: carrying capacity already answers "more forest and rock → more animals, more houses → more families." What remains open is the **per-species group size and its sizing rule**, and the question that must be answered before a `group_size` field is worth adding: **does a group of N arrive only where `capacity ≥ population + N`, or does it arrive partially?** | depth (row 6); field lands with the sizing rule, not before |
| 8 | **Cost-table values & starting stockpile** — v1 has one resource, so the open part is Wood cost values and starting stockpile size | balancing/playtesting |
| 9 | **Avoids tuning** — "personal space" distance between home sites; avoidance-failure relocation threshold | GDD tag-threshold pass |
| 10 | **World preset list** — exact New Game presets and their starting layouts. **Not closed, but narrower to close:** New Game's one v1 preset is now a `WorldPreset` resource (`project/scripts/definitions/world_preset.gd`, data at `project/data/presets/meadow_start.tres`), so resolving this item is authoring a `.tres` file per preset, not writing code | GDD refinement pass |
| 11 | **Fact-card content** — research and writing (process/checklist defined) | dedicated content pass |
| 12 | **First-time nudge copy** — exact wording | same content pass as fact cards |
| 13 | **Read-Aloud default state** — on or off by default | playtesting |
| 16 | **Refund/grace tuning** — exact grace-window seconds and recycle percentage | balancing/playtesting |
| 17 | **Terraform brush** — **CLOSED for v1 (→ D-25): single-tap only.** One tap converts one tile. Drag-to-paint moves to **depth** (row 3) — it is a comfort improvement, not a capability, and single-tap is the form that most obviously satisfies Pillar 3's "pick a mode, then tap" | closed — depth only |
| 18 | **Footprints & world dimensions** — final footprint sizes (House 2×2 baseline); start size (~36×36) and cap (~128×128) | GDD refinement pass |
| 19 | **Mist-reveal tuning** — trigger distance (~2 tiles baseline), reveal band depth, chunk size and shape | balancing/playtesting |
| 20 | **Home-site tuning** — per-species suitability radius (within ~8–12). *Human's value is decided: `scout_radius = 8` (approved 2026-07-28, → D-28).* Still open for the nine cleared-pool species, which have no value at all yet | GDD tag-threshold pass; per-species value lands with each species' step-3 proposal |
| 23 | **Capacity radius per species** — *narrowed:* the formula and the `capacity_radius` field are **decided** (Habitat Suitability in [gdd.md](gdd.md); v1 default = `scout_radius`). Open: per-species values (floor placeholders: [roster.md](roster.md)), and whether any species diverges from its scout radius. Start tight: the radius *is* the mechanism that makes the land-allocation tradeoff bite | GDD tag-threshold pass |
| 24 | **Habitat-to-individuals curve** — *narrowed:* v1 is **decided** as min-over-needs with a linear divisor (`tiles_per_individual`) — the min already discourages monoculture. Open: whether purchased depth adds a diminishing curve or geometric blend | balancing/playtesting |
| 25 | **Capacity hysteresis** — *narrowed:* the settlement rule (Controls in [gdd.md](gdd.md)) is **decided** and absorbs edit-time flicker. Open: whether a *settled* neighborhood slightly below capacity tolerates a standing margin before displacing. A margin is likely kinder | balancing/playtesting |
| 26 | **Starting Wood stockpile** — *narrowed:* the sizing principle is **decided** (covers the nudge's first build only, ~50 placeholder; pacing begins at the second build). Open: the exact value | balancing/playtesting |
| 27 | **Numeric vs. qualitative capacity display** — both pass the indicator test, but `X / Y` is a fraction a child reads as *a container to fill* — a goal-shaped display the indicator test cannot catch, which is why the **thin build ships qualitative** ("this meadow is lively") and numeric display must argue its way in | balancing/playtesting |
| 28 | **Pacing constant values** — the table under Game Mechanics (arrival delay, time-to-first-move-in target/ceiling, drain budget). TTFMI is validated at the step-5 kid playtest | balancing/playtesting |
| 29 | **Wild-grass visual treatment** — how visibly untouched revealed land reads as "wild" vs. true grass (it must read as *something to claim*, without reading as broken) | art pass / playtesting |
| 30 | **Hours-ledger re-verification** — the floor ledger omits priced rows: review gates across ~30 work units, playtest logistics breadth, three-platform export validation, and content-verification time. Re-price at the velocity review with measured actuals — per-row `actual_hours` are recorded in [tier1-status.md](tier1-status.md) as the work happens | velocity review (week 2–3) |
| 31 | **Villager fact-card content — CLOSED (approved 2026-07-28, → D-28).** `human.tres`'s `fact_text` is a real, source-verified fact about humans, double-sourced per clause (Animal Diversity Web + National Geographic Society Education) after a same-day correction against the second source. **Distinct from #4:** this closes only the fact-card gate. Human's asset audit is #4's own separate gate — [content-pipeline-status.md](content-pipeline-status.md) records it `pre_import_audit: done`, but #4's row below has not been updated to say so; that staleness is unrelated to this closure and is flagged there | closed — see `human.tres`'s header for the full per-clause provenance |

New open items discovered during formalization or build get added here as they come up.
