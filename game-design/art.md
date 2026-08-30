# Wildhaven — Art Direction & Asset Plan

> Authoritative for all visual asset decisions. Supersedes the visual-style and licensing
> prose formerly in [gdd.md](gdd.md) (still the source of truth for gameplay mechanics —
> the roster's habitat/avoids/tuning data lives in [roster.md](roster.md), terrain tag
> vocabulary and per-terrain detail in [terrain.md](terrain.md), and building
> costs/footprints in [buildings.md](buildings.md)) and the root-level `art.md` (now a
> pointer here). Consolidates the
> decisions and live findings from
> [source-content/assets/ASSET_AUDIT.md](../source-content/assets/ASSET_AUDIT.md), which remains the detailed
> pack-by-pack inventory and audit trail.
>
> **This document exists to drive [.claude/agents/tech-art.md](../.claude/agents/tech-art.md):**
> every asset it needs to import, every gap it should report instead of trying to fill, and
> every pending purchase/decision, lives here.
>
> **Current per-item pipeline status** (source → audit → import → data entry → copy →
> attribution → validation → sign-off) lives in
> [content-pipeline-status.md](content-pipeline-status.md), not here — this document
> keeps only sourcing decisions, policy, and open tasks.

## Visual Style & Art Direction

Rounded, chunky "cute low-poly" 3D — soft edges, simplified geometric shapes, bright
toon-shaded colors, friendly exaggerated proportions; deliberately not blocky/voxel and not
realistic, aiming for a friendly picture-book world.

Picture-book rules bind **every** asset, new or sourced:

- **Silhouettes:** rounder everywhere — soften every hard corner; a creature or building
  should read as a friendly blob-shape before any detail arrives.
- **Proportions:** heads and eyes proportionally larger than realistic; short limbs; no
  sharp claws, teeth, or angular features on any animal.
- **Shading:** a soft two-step toon ramp, uniform across all assets (Godot toon shader) — no
  realistic gradients, no harsh shadow edges. This is the tool that unifies assets pulled
  from different creators/packs — it fixes color/lighting consistency but **not** mesh-level
  proportion or silhouette mismatches, which must be judged per-asset at pick time.
- **Palette:** saturated but gentle — bright hues pulled back from full saturation;
  warm-leaning; no pure black or pure white.
- **Readability test:** every animal must read as a recognizable, friendly shape at the
  default mid-zoom (~12–15 tiles on screen). If a species only reads at close zoom, simplify it.
- **Variation-ready:** animal textures separate base coat from a pattern-mask layer
  (patches, socks, chest blaze) so per-individual variation seeds can recolor them without new art.

**Technical constraints that shape the art pass** (full detail: gdd.md → Player Interface &
Controls, World Structure, Performance):

- Camera is fixed ~45° pitch, four fixed 90°-apart headings (D-44) — models/textures must
  read well from all four, never top-down or a free player-controlled orbit.
- Zoom-distance LOD: full detail near the camera, terrain simplifies and animals collapse
  into "paw badges" at far zoom — budget LOD/impostor work accordingly.
- 3D asset creation is the acknowledged weak spot (no in-house art), mitigated entirely by
  the asset-pack-first strategy below; mesh work (re-topo, re-proportion, cute-ification) is
  **not** available in the pipeline. Out-of-the-box silhouettes ship as-is — pick assets
  whose forms are already acceptable.

## Asset Sourcing Policy

Working guidance, not dogma — re-evaluate whenever following it would cost more time than it saves.

- **Base ecosystem: Quaternius, all the way.** CC0, Godot-native (glTF), one creator →
  cohesion for free, least pipeline friction. The default; don't mix creators for hero
  content without a reason.
- **"Make it my own" = looks unique, not owned.** Delivered by a **look-pass layer** — a
  uniform toon/cel + rim shader, a Wildhaven palette, lighting + post-processing, ambient FX
  — applied over the assets. Base-agnostic; this is what actually delivers "our style," not
  which creator modeled the mesh.
- **Sanctioned paid fallback: Synty SIMPLE (animals only).** If a gap species has no animated
  Quaternius model, a Synty **SIMPLE** animal is an acceptable buy — closest paid line to
  Quaternius, blends under the shared shader. **Animals only; humans stay Quaternius**
  (character style is where cross-creator mismatch shows most).
- **Never Synty POLYGON.** Off-brief detail level — Synty's own marketing distinguishes
  POLYGON as "higher detail and realism" vs. SIMPLE's "more stylized and casual," and POLYGON
  fights the picture-book proportions rule — and its animal selection is negligible anyway.
- **Willing to spend money to save time**, not to add polish for its own sake — every paid
  purchase should close a real, confirmed gap (see Synty Pack Purchase Decisions below), not
  duplicate something already free and working.

**Licensing:** all third-party art comes from free or cleared, appropriately-licensed
sources — Quaternius (CC0 1.0 Universal, no attribution required) primary, Synty (Store
EULA — one-time purchase, royalty-free, 5 seats; commercial use/modify/ship-derivatives ✓, no
reselling as stock art or training generative AI) as sanctioned fallback. Attribution is
satisfied on an in-game Credits screen per source's license terms, generated from
`project/attribution/sources/*.tres` (see `project/CREDITS.md`). Compiling each asset's
license identifier and commercial-use terms is part of the asset audit — nothing ships
without its license conditions met.

## Roster Assets Scoped

The floor plus the two designed-but-unsourced species — gameplay data (habitat needs, avoids,
`tiles_per_individual`) lives in [roster.md](roster.md); this table is the asset-availability
view only. **Floor = Human, Fox, Rabbit.** The nine-species cleared pool is under *Newly
Available Animals* below. Current per-item pipeline status (imported? data-entered? signed
off?) lives in [content-pipeline-status.md](content-pipeline-status.md) → Roster.

| Species | Asset |
|---|---|
| **Rabbit** ⭐floor | Quaternius, animated — imported (`project/assets/animals/rabbit`) |
| **Fox** ⭐floor | Quaternius, animated — imported (`project/assets/animals/fox`) |
| **Human** ⭐floor | 5 standalone Quaternius character glbs (Adventurer, Punk, Man, HoodieCharacter, AnimatedWoman) — imported (`project/assets/animals/human_*`); all 5 variants are wired in `AnimalDefinition.model_scenes`, equal-weight, randomly picked per villager (Adventurer is index [0]) |
| **Chicken** | none viable in Quaternius (both live candidates checked and rejected — armature-only, no real walk/idle cycle, and off-style) — resolves to a Synty SIMPLE Farm Animals Cartoon purchase, **not yet made; whether to make it is a velocity-review call** |
| **Duck** | none in Quaternius (no waterfowl at all) — same purchase, same open call. Duck is the only water-habitat species in any list |

## Sourcing Watch-List

**These are not roster members.** They were named in early design, no cleared asset was ever
found, and as of 2026-07-27 (→ D-24) they are **not tracked as gaps, targets, or debt** —
they carry no row in [roster.md](roster.md) or
[content-pipeline-status.md](content-pipeline-status.md). The roster has no target count; it
is a floor of three plus depth bought from the cleared pool. What survives here is the
research, so nobody repeats the search.

Re-check as the Quaternius / poly.pizza catalog grows. If a genuinely good asset turns up,
the species re-enters through a normal Add-an-Animal run like any other candidate — no
special claim on the roster, and **no substitutes**: Deer and Stag are roster candidates in
their own right, never stand-ins.

| Species | Original design intent | What the search found |
|---|---|---|
| **Cat** | `cultivated + cover`; Bold, farm-tolerant | Only candidate found (poly.pizza, Quaternius CC0) **rejected on style-fit** — silhouette and proportions miss the picture-book direction. No other CC0 candidate evaluated. |
| **Monkey** | `forest + water`; Bold, arboreal | No true primate anywhere evaluated — Quaternius has only a static Panda and a stylized "Monkroose"; nothing in any evaluated Synty pack. |
| **Leopard** | Shy, 3-tag "trophy," avoided by Rabbit | No big cat anywhere checked. A live poly.pizza search (109 results for "leopard") returned only the same rejected generic Cat. Nothing in any evaluated Synty pack. |

*Consequence already applied:* Rabbit's `avoids` entry for `leopard` was dead data pointing
at a species that was never coming, and was removed from `rabbit.tres` on 2026-07-27.

## Newly Available Animals

Confirmed **animated**, free Quaternius models — all nine below are now imported, attributed and
import-tested (the "cleared pool"). They widen the design axes
(Bold/Shy, farm-tolerant/wild, tag mixes) if the human wants more roster volume. Habitat
needs below are proposals, not decided.

| Candidate | Source | Suggested needs · traits | Adds |
|---|---|---|---|
| **Deer** | Ultimate Animated Animals | open_grass, forest · Shy | gentle wild grazer |
| **Stag** | Ultimate Animated Animals | forest, cover, rocks · Shy | rare "trophy" |
| **Cow** | Ultimate Animated Animals | cultivated, open_grass · Bold, farm-tol | barnyard life by the village |
| **Bull** | Ultimate Animated Animals | cultivated, open_grass · Bold, farm-tol | barnyard life by the village — kept as its own roster spot (2026-07-26 human call) despite sharing Cow's base mesh (recolor only) |
| **Horse / Donkey** | Ultimate Animated Animals | open_grass, cultivated · Bold, farm-tol | pasture animals |
| **Alpaca** | Ultimate Animated Animals | open_grass · Bold | exotic-cute grazer |
| **Husky / Shiba Inu** | Ultimate Animated Animals | house, open_grass · Bold, farm-tol | "village dogs"; the natural candidate for row 9's second avoids pair |
| **Pig / Sheep / Rooster / Goat** | Synty SIMPLE Farm Animals Cartoon (bonus species riding along with the Duck/Chicken purchase) | cultivated, open_grass · Bold, farm-tol | extra farmyard variety, already paid for |

**Verify on import:** Ultimate Animated Animals = confirmed animated. Quaternius's separate
**Farm Animals** pack (Pig, Pug, Sheep, Llama, Zebra + Cow/Horse) is presumed rigged but its
title lacks "Animated" — confirm animations exist before relying on those five.

## Terrain — Assets & Availability

v1 terrain vocabulary and tag mapping is decided gameplay design ([terrain.md](terrain.md),
`v1 tag-source mapping`); this is the asset side only. **Abundant — no purchase needed.**
Current per-item pipeline status lives in
[content-pipeline-status.md](content-pipeline-status.md) → Terrain.

**2026-08-16 look-pass sourcing note:** no local vendor/asset-pack directory exists in
this repo (nothing beyond what was already imported was on disk), so the additional Rock/
Grass/Cultivated field picks used for this pass were sourced fresh via individual CC0
Quaternius downloads through poly.pizza rather than hand-carried from the packs named
below — see [`quaternius_poly_pizza_nature.tres`](../project/attribution/sources/quaternius_poly_pizza_nature.tres)
for exactly which pieces and their source pages. The table below still names the
originally-evaluated packs as the general availability picture; it was not re-verified
pack-by-pack in this pass.

**2026-08-16 same-day follow-up (3 human eyeball fixes):** (1) every composed terrain
scene's ground slab widened X/Z from 0.94 to 1.0 to close a real cross-tile seam gap
against `WorldGrid.TILE_SIZE`; (2) `grass`/`wild_grass` rebuilt around a single
`MultiMeshInstance3D` each (36 / 32 baked instances) at a shorter height baseline, replacing
individually hand-placed nodes, per an explicit "shorter, more instances (30+)" complaint;
(3) Forest gained a 3rd tree, "Pine Tree" (Quaternius, CC0, sourced fresh via poly.pizza —
same no-local-pack situation as the note above), because the 2 existing "common tree"
picks read as visually indistinguishable at the fixed camera pitch despite alternating
correctly in code. Full detail in
[content-pipeline-status.md](content-pipeline-status.md) → Terrain's per-item rows.

| Terrain (emits) | Assets available | Notes |
|---|---|---|
| **Forest** (`forest`) | Huge surplus — MegaKit CommonTree/Pine/Twisted; Nature Pack Birch/Common/Pine/Palm/Willow (+ seasonal); Trees pack (45 models) | Pick a small "common" set |
| **Rock** (`cover`, `rocks`) | Nature Pack `Rock_1..7`, `Rock_Moss_*`; MegaKit `Rock_Medium`, Pebbles; RTS `Rock`/`Mountain` | Load-bearing — the Fox/Rabbit `cover` source. `Rock_Moss` = the nudge's "mossy boulders" |
| **Cultivated field** (`cultivated`) | Nature Crops Pack — Wheat, Corn, Carrot, Beet, Lettuce, Tomato, Pumpkin, Watermelon, Rice, with growth stages (`_Crop`/`_Harvested`); RTS `Farm_*` modeled plots | Villager need |
| **Grass** (`open_grass`) | MegaKit Grass_Common/Wispy, Nature Pack Grass, Crops Grass, Clover, Fern | |
| **Water** (`water`) | Surface is a shader/plane, no model | Dress edges with Nature Pack `Lilypad`, reeds |
| **Sand** (depth) | Cactus, PalmTree, Coconut | Not in v1 floor |
| **Flowers** (`flowers`, no v1 consumer) | Crops Flower_1..4, MegaKit Flower/Petals, `Bush_Common_Flowers` | Free to keep in vocabulary; no species reads it yet |
| **Move-in props** (den/burrow/nest) | No dedicated CC0 model found | Compose from existing Quaternius pieces (mossy log + rock + bush = a den). Decoration only, low risk |
| **Ambient life** (deferred — future.md "Charm layer": songbird flocks, butterflies, fish ripples, dragonflies, fireflies) | Gap in Quaternius; **Synty POLYGON Nature Pack's particle effects (butterflies, fireflies, sunrays, falling leaves) are a good stylistic match** if/when the Charm layer is built | Deferred with the layer itself — not a v1 need |

## Buildings — Assets & Availability

v1 building data (footprint, cost, `allowed_terrain`) is decided gameplay design
([buildings.md](buildings.md), spec.md); this is the asset side only. Current per-item
pipeline status lives in [content-pipeline-status.md](content-pipeline-status.md) →
Buildings.

| Building | Assets available |
|---|---|
| **House** (v1 2×2 / floor 1×1, grass only) | RTS `Houses_FirstAge_*` (FirstAge cottages read most picture-book — imported as `Houses_FirstAge_1_Level1`, facing not yet eyeball-confirmed), Farm Buildings `Silo_House` |
| **Farm/village flavor** (not v1 buildings — dressing) | Quaternius Farm Buildings — Barn, Coop, Silo, Windmill, Well, WaterTower, Fence (for the fenced field) — available now, free |

**Deferred placeables** (future.md — priced but not v1 scope):

- **Fence & Birdhouse** — "leaning toward any land terrain except water — final list still
  open." Fence asset already available free (Farm Buildings, above); Birdhouse not yet sourced.
- **Shed** — reuses the House's 1×1 thin-form asset once the House deepens to 2×2, so this is
  asset-free (already in hand).
- **Species amenities** (Well/School/Market for villagers, "exactly as a birdhouse is for
  birds") — Well asset available free (Farm Buildings); School/Market not sourced, post-class only.

## Synty Pack Purchase Decisions (2026-07-25)

Five Synty Store packs were evaluated as a possible base, not just a gap-filler, on a
content-volume-and-time basis (see
[source-content/assets/ASSET_AUDIT.md](../source-content/assets/ASSET_AUDIT.md) for the full evaluation).
Verdict: buy one, skip four.

| Pack | Verdict | Why |
|---|---|---|
| SIMPLE Farm Animals Cartoon | **Buy** | Closes the only two real gaps (Duck, Chicken) plus 8 bonus pre-animated farm species |
| POLYGON Nature Pack | Skip | Duplicates abundant free Quaternius terrain coverage; no Godot project; off-brief detail level |
| POLYGON Farm Pack | Skip | Duplicates free Quaternius farm buildings; characters ship unanimated; off-brief |
| SIMPLE Farm Cartoon Assets | Skip | Same redundancy as POLYGON Farm; characters also unanimated |
| SIMPLE Forest Animals Cartoon | Skip | Species mostly already covered free by the cleared pool |

## Pending Tasks for Tech Art

Per-item pipeline status (what's done vs. blocked) is tracked in
[content-pipeline-status.md](content-pipeline-status.md); this list is the narrative
task queue behind those blockers.

- ~~Import Human~~ — ✅ **done** (5 look variants imported; see roster table above).
- ~~Import Deer, Stag, Horse, Donkey, Cow, Bull, Alpaca, Husky, Shiba Inu~~ — ✅ **done**
  (2026-07-26; all 9 from Quaternius Ultimate Animated Animal Pack, same source as Fox —
  `project/assets/animals/<name>/`). **These nine are the cleared pool** — roster candidates
  in their own right, never stand-ins; Bull and Cow are kept as separate spots despite Bull
  sharing Cow's base mesh (2026-07-26 human call). Data entry, copy, and sign-off still open
  for all 9 — see [content-pipeline-status.md](content-pipeline-status.md) → Roster.
- **Purchase + import Synty SIMPLE Farm Animals Cartoon** — **not purchased**, and whether to
  buy it at all is now a **velocity-review call** (→ D-24): nine free cleared species already
  exist, so the purchase must justify itself on Duck's water habitat rather than on roster
  volume. No file on disk (confirmed on the 2026-07-26 audit). If purchased: Unity/FBX only,
  no file on disk (confirmed on the same 2026-07-26 audit). Once purchased: Unity/FBX only,
  no Godot project; import FBX same as other non-native Quaternius packs. Extract Duck and
  Chicken as roster residents; hold Pig/Sheep/Rooster/Goat/Cow/Bull/Horse as optional
  bonus-species candidates. Record the Synty EULA attribution entry on import (per-asset,
  per Licensing above).
- ~~Compose the move-in prop~~ — ✅ **done** (`project/assets/props/den/Den.tscn`; WoodLog_Moss +
  Rock_Moss_3 + Bush_1 from Ultimate Nature Pack). Arrangement/scale is a first-pass
  composition — flagged for human eyeball sign-off, not yet visually confirmed in-engine.
- ~~Pick one fixed House variant + facing~~ — ✅ **done**: `Houses_FirstAge_1_Level1`
  (`project/assets/buildings/house/House.tscn`). Measured footprint (0.869×0.761 units)
  already fits a 1×1 tile with no rescale — confirms art.md's own "reads most picture-book"
  note. Facing left as authored; not yet visually confirmed against the fixed camera —
  flagged for human sign-off.
- ~~Pick a "common" tree/rock/grass set~~ — ✅ **done**: 2 MegaKit trees (`CommonTree_1`,
  `CommonTree_2`), 2 MegaKit grass variants (`Grass_Common_Short`, `Grass_Common_Tall`), and
  1 plain Nature Pack rock (`Rock_1`, distinct from the Den's mossy `Rock_Moss_3`) —
  5 pieces total under `project/assets/terrain/`, deliberately small per "avoid importing
  everything." Scale for all 5 is an unmeasured look-pass judgment call (no GDD number
  exists for tree/grass height) — flagged for human sign-off in each wrapper's header
  comment. See [content-pipeline-status.md](content-pipeline-status.md) → Terrain for the
  per-item pipeline state.
- **Low-priority: keep half an eye on poly.pizza** for the Sourcing Watch-List species as the
  Quaternius catalog grows. This is opportunistic, not an open task — nothing is waiting on
  it. If searching, re-run the live search (`poly.pizza/search/<name>`) rather than trusting
  the profile page's default view, which under-reports the `#Animated` tag.
- Every import above requires: **idle/walk/reaction animations** confirmed *before* import
  work starts (gdd.md's Add-an-Animal gate), a Credits/attribution entry in the same task, and
  the structural predation check for any animal gaining an `avoids` entry.
