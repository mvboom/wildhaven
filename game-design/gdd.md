# Wildhaven *(working title)* — Game Design Document

> This document specifies **v1 — exactly what we are initially building.** It states
> every principle, mechanic, and number that matters to play, and reads start to finish
> on its own. Field-level schemas, screen layouts, tuning tables, and open items live in
> [spec.md](spec.md); deferred and cut ideas live in [future.md](future.md). Numbered
> references like *#23* point to Open Questions in [spec.md](spec.md). The roster,
> terrain, and buildings — what each is, the attributes each requires, and which
> specific ones are already defined — are split out into [roster.md](roster.md),
> [terrain.md](terrain.md), and [buildings.md](buildings.md); this document keeps only
> a summary of each plus the cross-cutting mechanics (habitat tags, carrying capacity,
> qualification, Gentle Displacement) that all three read.

## Quick Facts

| | |
|---|---|
| **Genre** | Strategy/building sandbox — habitat-building |
| **Audience** | Kids 6–10; parents as a deliberate secondary audience. *v1's practical limit is device access (a family desktop); core texts are narrated from the floor — see Plan → Target Release* |
| **Platforms** | v1: Desktop (Linux/Windows/Mac) — a time-to-market choice, not the audience's home device · v2: Android/iOS for tablets/phones, where the audience actually is |
| **Mode** | Single-player only — no online or multiplayer features planned or supported |
| **Engine** | Godot |
| **Production** | Solo developer; 7-week class at 5–8 hrs/week (35–55 hours total) |
| **AI use** | Development-time only (Claude Code + Godot MCP server); the shipped game contains no runtime AI |
| **USP** | The builder's win condition, inverted: success isn't the biggest city — it's a landscape creatures *choose* to live in. Even the village works this way, because people are just another species |

## Executive Summary

**Wildhaven** is a 3D town-and-habitat-building strategy game for kids, in which the goal isn't building the biggest city — it's convincing wild animals to move in, because you've built somewhere they'd genuinely want to live.

The player terraforms one small, seamless world tile by tile and places buildings; terrain quietly accumulates "habitat" qualities, and when a spot suits an animal's needs it moves in — visibly, roaming free — and a fact card teaches something real. The world starts small, ringed by mist that unfurls as you build near it. A village grows the same way: people are just another species — a house with a farm nearby is their habitat. One loop, many species.

The **five** Pillars below govern everything: **no fail states or pressure, gentle to the bone, one interaction pattern, teach through play** — built for kids 6–10 and their parents. Teaching is through play and causality, loosely modeling real conservation science (the Habitat Suitability Index — habitat *needs*, not food webs). Genre precedents: Terra Nil, Alba, Animal Crossing, with SimCity/Civilization/Minecraft as broader inspiration. An explicit thin-form floor keeps the core loop always shippable (see Plan → Scope).

**The success criterion — v1 is done when:** a kid aged 6–10, playing on a family desktop beside a parent — its buyer is the 7-week course itself — completes the full core loop unaided in one sitting of about 20 minutes: terraform → build → an animal genuinely moves in → fact card → the world grows at the mist. A quit → reload restores their world faithfully. Validated at the step-5 kid playtest, re-validated in phase 8. Session-two retention and commercial/storefront posture are explicitly outside this bar; the asset pipeline records commercial-use clearance only because re-licensing later is expensive, not because v1 is a product.

## Design Pillars

The audience drives hard constraints throughout. Every later decision justifies itself against these pillars; when a feature conflicts with one, the pillar wins.

### Pillar 1 — No fail states, no pressure, ever
No win/loss condition, no timers, daily-login rewards, FOMO events, artificial scarcity, push notifications, or ads. Two invariants:

- **The indicator test (no number is a goal).** Every counter and Field Guide entry is a *status indicator*, never a target — it would become a goal if the game presented its value as something to reach, read it back to gate content/rewards/systems, or defined a completion/failure state over it, and nothing in the game does any of the three. 10 species hosted is exactly as good as 100.
- **The game never initiates loss.** Nothing bad befalls anything a player loves except as the warned, non-lethal, reversible result of the player's own choice. Absence is never noticed.

### Pillar 2 — Gentle to the bone (the no-harm line)
No combat, death, or predation. **The predation ban is operational, not atmospheric:** no content anywhere depicts, names, or alludes to hunting, animals eating animals, danger, or fear — enforced by the content checklist's predation check. The world is not falsely peaceful, though: animals that keep their distance in real life keep it here (the Avoids system). **The line is behavior vs. event** — the game models what a quiet wildlife-watcher can observe (wariness, distance) and simulates nothing beneath it.

### Pillar 3 — One interaction pattern
The entire game is playable with **"pick a mode (or none), then tap."** Camera control lives on separate inputs and never conflicts with gameplay taps.

### Pillar 4 — Teach through play, not lectures
Habitat suitability is loosely modeled on real conservation science; fact cards deliver real animal facts only at moments of success or curiosity — an animal moving in, a curious tap — never as a lecture.

### Pillar 5 — Built for 6–10, and their parents
The age range spans pre-fluent to fluent readers, motivating the Read-Aloud slice on fact cards and the displacement warning (full narration coverage is deferred — see future.md). Parent-friendliness is a real requirement — e.g. the ambient-only sound direction exists so nothing hooky loops in a parent's head across long sessions.

**Two design facts the document leans on:**
- **Villagers are just another species.** The village is not a second game — people are one more entry in the habitat system, a house-with-farm is their habitat, and a villager moving in is the same payoff as any move-in.
- **The mist is a curtain, not a gate.** The world's edge reveals as the player builds near it, at no cost and for no reward; nothing exists behind it.

**Non-Goals — permanent.** These are not scope cuts waiting for hours; they are the design, and no future revision adds them:

- **No win state, fail state, or score.** Ever (Pillar 1). Progress displays are indicators; nothing is a target.
- **No predation, combat, death, or danger — simulated or implied.** The predation ban is operational (Pillar 2): no mechanic, event, or copy anywhere models or alludes to hunting, eating, fear, or harm.
- **No timers, pressure, FOMO, login rewards, or notifications** (Pillar 1).
- **No interaction pattern beyond "pick a mode (or none), then tap"** (Pillar 3).
- **No real-world claims outside fact cards** (the two-register rule, Worldbuilding). Wildhaven's animals are named after real ones, not simulations of them.

**What a session feels like:** tending one living world. The player glides over a seamless landscape with one pan-and-zoom camera at a fixed diagonal angle (D-41) — the whole world in frame like a picture-book map, or close enough to watch a fox's ears twitch. They might terraform a pond, tap a fox for its fact card, or just watch. Holding Home pulls the camera out to that whole-world map view for as long as it's held, then returns exactly where the player was — the "see everything" glance without living in that view. Occasional News Reports hint that some animal is "looking for open grass and a cozy boulder out of the wind," seeding the Field Guide one species at a time. A session ends wherever the player stops; the world waits, unchanged, exactly as they left it.

## Game Features

**Visual style:** see [art.md](art.md) — the authoritative art direction, roster-asset scoping, and sourcing plan, including the Quaternius/Synty policy and current purchase decisions. The final roster is chosen from the assets, not vice versa — a roster audit of Quaternius's coverage happens before species are locked. The roster's design data (habitat needs, personality, avoids, tuning constants) lives in [roster.md](roster.md), not here.

**Audio style:** no melodic background music — a pure ambient soundscape (birds, wind, water, rustling). Chosen deliberately: parent-friendly (nothing hooky to loop across long sessions, Pillar 5) and lower-scope than a non-repetitive soundtrack. v1 audio is one ambient bed plus soft, warm confirmation sounds (chimes/pops) for placing, move-ins, and tending — never sharp or spammy; the tag-driven ambient layer system is designed and deferred (its originally-envisioned zoom-driven crossfade applies again under D-41's restored pan/zoom camera, after not applying during D-33's first-person interlude). Volume controls: separable Ambient/SFX sliders, floor of one master slider.

**Licensing:** all third-party art and audio come from free or cleared, appropriately-licensed sources — see [art.md](art.md) for the art asset sourcing policy and decisions; audio uses freesound.org or equivalent. Attribution is satisfied on an in-game Credits screen per each source's license terms, compiled as part of the asset audit; nothing ships without its license conditions met.

## Game Mechanics

### Core Loop

1. The player places terrain and buildings on a grid — grass, water, forest, rock, and more.
2. Each tile silently carries the habitat tags its own terrain emits (`water`, `forest`, `open_grass`, `cover`, …); a neighbourhood's character is the *mix* of tags in an area, not tags bleeding between tiles.
3. Animals periodically "scout" the map, evaluating real spots as candidate home sites; when one meets an animal's needs, it moves in — a small den, burrow, or nest appears, and the animal roams free around it (never caged).
4. Moving in triggers a fact card teaching a real fact about that animal.
5. Progress accrues through informational counters — never a win/lose state or a score.

### Objectives & Progression

There is no win/loss condition and no game-assigned objective (Pillar 1). The player's objective is to play: tend a world, watch it live, follow their own curiosity — and author their own goals (*attract the fox, grow the village*). The game's job is to **acknowledge** progress, never to **assign** it. Every system below is a **status indicator, not a goal**, and passes the indicator test (Pillar 1).

- **Top-level counters** — Resources, Species Hosted, Currently Resident, Village Population (defined under Economy). Each is information, never a target.
- **The Field Guide** — a discovery tracker that fills one species at a time as News Reports arrive. No completion percentage, total-species count, or finish-the-guide reward — a nature journal that grows for as long as play continues. **One narrow, named exception (D-40):** the Field Guide's row list shows every roster species as a row, silhouetted until discovered — existence only, never a preference, hint, or completion measure — specifically so a player is never encouraged to build a habitat for a species that can never appear.
- **Skill expression without stakes** — difficulty lives in the puzzle, not in penalties: spatial-separation puzzles (two animals that avoid each other, needing room for both — Rabbit ↔ Fox at the floor) and the harder multi-tag species (Fox, two tags composed from two terrains) reward mastery without punishing its absence.

### Player Interface & Controls

One unified tap-based system underlies every interaction — a 6–10 year old only ever learns **"pick a mode (or none), then tap"** (Pillar 3). Camera pan/zoom lives on entirely separate inputs from the tap itself, so no camera gesture can ever act on the world and no tap can ever move the camera — the same disjoint-input guarantee D-13 shipped, restored by D-41 after D-33's first-person interlude. **Desktop scheme (v1 target):** "tap" means **left-click**, wherever the cursor actually is.

| Input | Action |
|---|---|
| Left-click | Every tap action (Inspect / Terraform / Build / Harvest) on whatever the cursor is over |
| Right-click drag (or WASD/arrow keys) | Pan the camera |
| Mouse wheel | Zoom |
| Two HUD buttons, or Q/E keys | Rotate the camera 90° (→ D-44; four fixed isometric headings) |
| Home key, held (and a HUD button) | Map peek: cuts to the whole-world overhead framing for as long as it's held, returns to exactly the same pan/zoom on release — the "see everything" panic button |
| Tab | Open/close the browse shell (Field Guide) |

**D-41 replaces D-33's first-person walk camera with a fixed orthographic camera at a diagonal heading** (yaw 45°, pitch ≈26.6° below horizontal — the isometric convention the project's own early mockups used), restoring D-13's pan/zoom model outright: nothing walks, the mouse is never captured, and cursor-position targeting replaces look-and-press. This reverses D-33's reversal because first-person read, in the human's own words, as "wrong, boring, hard to maneuver" — and because measurement showed camera angle alone does not fix the tree-occlusion problem D-33 was built to solve; a bounded, per-resident transparency fade (Technical Overview) solves it directly instead, independent of which camera angle is chosen. D-13's original three safety rails return, re-derived (not ported) for the diagonal heading: pan clamped to the revealed world, full zoom-out always framing everything, Home one press away. **D-44 later reopened this decision's "never rotates" clause narrowly**, adding discrete 90°-step rotation (two HUD buttons plus Q/E) among four fixed isometric headings — not free rotation — everything else in this paragraph is unchanged. Touchscreen laptops may work via Godot's touch-emulates-mouse fallback but are not a designed-for input in v1; true tablet/mobile is a v2 concern.

**The three modes:**

1. **Inspect Mode** (default, no tool) — "just enjoy the world." Taps react contextually: an **animal — and a villager is an animal, per the pillar** — replays its fact card plus a cute reaction (pure delight, no mechanical effect); a **Harvestable Tile** (Forest, …) is tended for a resource boost (see Economy); a **House** gives building flavor info the same way; a **resident** (animal or villager with a home neighborhood) also shows the carrying-capacity readout; **empty land** does nothing, optionally showing its terrain/tags. **Priority rule:** an animal standing on a tappable tile always wins the tap — generous animal hitboxes beat ambiguous taps for young kids. Tap-to-tend is row-5 depth; Inspect ships without it at the floor.
2. **Terraform Mode** — pick a terrain, tap tiles to convert. Natural terrains are **free**; cultivated fields cost a little Wood (see Economy). Tapping raw tiles at the world's growing edge is the same action extended into new territory — no separate expansion mechanic. The full terrain list, tag emission, and per-type costs: [terrain.md](terrain.md); floor: five of the six v1 terrains (sand is depth).
3. **Build Mode** — pick a building, tap an eligible tile to place its whole footprint at its Wood cost. (Farms are not buildings — a farm is cultivated terrain painted in Terraform Mode; see [terrain.md](terrain.md).) v1's only buildable is the House; its footprint, cost, and placement rules: [buildings.md](buildings.md); floor: 1×1, "a simple house," grass only.

**Live neighborhood preview:** while a tile is targeted in Terraform or Build, the affected carrying-capacity ring previews live — the same read the resident tap shows, surfaced at the moment of choice. It rides that same targeting tap, so no sixth pattern (Pillar 3); numeric (`4 / 6`) vs. qualitative ("this meadow is lively") display is Open Question #27, and either passes the indicator test.

**Removal / undo & refund policy** (uniform across Terraform reverts and Build removals). **Grace window** (~10–15 s after placement): removal refunds **100%** — accidental taps cost nothing. After the grace window, removal refunds a flat recycle percentage (placeholder ~50%, tunable) — "recycling," not a free take-back. Refunds are always in the resource originally spent; free natural terrain refunds nothing.

**The world settles per neighborhood, after the grace window (the settlement rule).** Capacity itself is re-evaluated **immediately, on every edit** — it is the dirty-queue arithmetic described under Performance, and a burst of taps coalesces into one evaluation because a neighbourhood is either dirty or it isn't. What the grace window gates is not the arithmetic but the **irreversible half of the consequences**: the displacement warning's final trigger, and any relocation or departure. **Every further edit inside an affected neighborhood restarts that neighborhood's window**, so a burst of taps — the natural input style of a six-year-old — warns once and reverts as one gesture. Restarts are deliberately uncapped, because the only thing a restart defers is a loss: while the player is still editing, nothing irreversible has happened. Reverting within the window means the displacement never happened: the world had not yet reacted. This is what makes Pillar 1's word *reversible* literally true rather than resource-deep only, and it covers free terrain, where there is no refund transaction to carry the undo. Warnings and losses attach to the *settled neighborhood gesture*, never per-tile (#17). **Arrivals sit deliberately outside the window.** A move-in is a gift, never needs undoing, and gating it behind a restartable window would let ordinary excited tapping defer the payoff past the time-to-first-move-in ceiling — the acceptance test's own bound. Arrivals ride the arrival delay instead (Habitat Suitability), which absorbs bursts by re-checking at due time rather than by making the player stop.

**GUI & screens** (layouts in [spec.md](spec.md)). The Title/Splash screen offers **New Game** and **Load Game** primarily, with Settings, Help, Credits and Exit secondary. New Game picks a starting world preset ("Jungle Start," "Desert Start," "Farm Start," … or Random), names the world once, and enters — it is never manually saved again (see Technical Overview → Saves). Load Game is a save-select screen of named saves with thumbnails. Settings and Credits are reachable only from the Title screen (→ D-50) — volume, Read-Aloud, Gameplay Hints for Settings; the attribution each asset and audio source's license requires for Credits — not from the in-game Tab browse shell, which now hosts only the Field Guide. Changing Settings mid-run means leaving to the Title screen first: "Exit to Main Menu" autosaves then confirms — a courtesy against a misclick, not a data-loss guard — and the change takes effect on the next session. Exit closes the app from the title.

In game, the world view is one seamless camera from whole-world far zoom to street-level close-up (D-41), no view modes. A persistent HUD shows Resources by type plus a quick-access Field Guide icon, present even at far zoom. Build and Terraform palettes appear only while their mode is active. The Field Guide screen shows hinted-at species, Currently Resident species, and the all-time Species Hosted count in one place, opened via Tab — the only thing that shell hosts now that Settings and Credits moved to the Title screen.

**First-time engagement nudge:** every brand-new save shows one dismissable popup within the first few seconds, gently pointing toward Terraform Mode (*"This meadow is just waiting for a garden — or a few mossy boulders…"*). It is the first News Report a player ever sees, fired on a new-save trigger rather than the ambient cadence, and its copy must name terrain the shipped roster actually reads (exact wording #12). The Gameplay Hints toggle disables it permanently.

**The First 60 Seconds — the acceptance script.** The blank-canvas onboarding bet de-risked into a concrete flow, and **the experiential acceptance test for the build we actually ship:** every beat is achievable at the floor — 3 species, five terrains, the 1×1 House, qualitative preview, single ambient bed. Deepening only makes it richer. (Constants in [spec.md](spec.md).)

1. **0:00 — New Game → name → in.** A small, calm, mostly-grass world at mid-zoom, ambient bed playing, camera on buildable land — an open meadow, not an empty lot.
2. **~0:03 — The first News Report fires** (the first-time nudge), Read-Aloud available. Its copy names terrain the floor roster reads — cultivated (villager) and rock, the `cover` source (rabbit, fox) — never terrain no shipped species responds to (#12). Dismissable; the Hints toggle disables it forever.
3. **~0:10 — First tap teaches the whole model.** Open Terraform, pick a terrain, tap a tile — it converts instantly, free, with a warm chime. "Pick a mode, then tap" (Pillar 3) is learned from one tap, no tutorial gate.
4. **~0:20 — Cause becomes visible.** The live preview gives a qualitative read ("this spot is getting cozy for someone") — never an `X / Y` fraction, which a child reads as a container to fill (#27). The referent is real at zero residents: it reads the qualification system's near-miss summary.
5. **~0:40 — The starting stockpile invites a build.** Wood in hand covers exactly the nudge's suggestion (Economy): a small cultivated field, or the 1×1 House with its confirmation chime.
6. **The payoff — within ~2:00 of the first paint (hard ceiling 5:00).** A low-requirement floor species — a rabbit onto grass-near-boulders, or a villager family into the house-with-field — qualifies the fresh habitat (`capacity ≥ 1`) and **moves in**, firing the fact card. The bound is **time-to-first-move-in** (Pacing constants), measured from the first paint, and holds even at the floor's stretched ~90 s arrival delay. A spec commitment validated at the step-5 kid playtest, not a hope.

**Design guarantees for this window:** no modal blocks the world; no step is mandatory (ignore the nudge and just pan, and nothing punishes or re-prompts with urgency, per Pillar 1); the first move-in is reachable with the cheapest possible habitat, so no new player is stranded before the payoff. If the step-5 playtest shows kids stall before it, the pressure valve is *content* (a more directive nudge, a lower-requirement starter species) or the arrival-delay constant — never a forced tutorial.

### Systems in Play

*Player-facing behavior only; the data structures behind these systems are specified in [spec.md](spec.md).*

**Habitat Suitability (core mechanic)** — loosely modeled on real conservation science (Habitat Suitability Index): habitat **needs**, not food webs. Each animal has a small checklist of habitat tags it needs nearby; **each tile carries the tags its own terrain emits — tags do not spread between tiles** (the v1 tag model, → D-25), so "nearby" is expressed entirely by the species' own radius; the player never manages tags directly. **No predator/prey simulation** — animals care about the environment, not each other, the Avoids system excepted.

- **Qualification is event-driven, not a continuous scan.** Habitat changes only on terraform, build, arrival, or departure (harvesting never removes tags, climate is static, Pillar 1 bans timers); each event marks the affected neighbourhood dirty and re-evaluates it against the roster. A qualifying spot enqueues an arrival — **one individual in v1** (packs are depth, #7) — on a short randomised delay, **re-checked when it comes due** since the land may have changed, so arrivals happen while the player is elsewhere in the world. **The enqueue happens on the edit itself, never at settlement** — the delay plus that re-check is what absorbs a tap burst, so a qualification the player undoes mid-burst simply never lands, and no amount of tapping can defer a move-in. **A pending arrival that de-qualifies before it comes due is silently dropped, never warned:** nothing had moved in, so there is nothing to explain — Pillar 1's no-unexplained-vanish rule governs residents, not un-arrived animals. A neighbourhood with room for several fills gradually rather than all at once. Qualification queries *revealed* land only; the walk in from the mist edge is presentation. **Vocabulary note:** what the game calls *scouting* is the player-facing hint layer (News Reports — see Discovery); the matching described here is a separate system sharing no machinery with it.
- **Carrying capacity is a property of the habitat itself, universal across every species, villagers included, and evaluated per home-site neighbourhood — never globally:** what sits within a species' radius sets how many individuals settle there.
- **The capacity formula (v1).** For species `S` at home site `h`, count qualifying tiles within `S.capacity_radius` for each tag `t` in `S.habitat_needs`; then

  `capacity(h, S) = min( min over t ( floor(count_t / S.tiles_per_individual) ), S.max_individuals )`

  The scarcest need caps the population — **Liebig's law of the minimum**. **There is no lower clamp: capacity can be 0, and 0 means unsuitable** — a site short of `tiles_per_individual` on any needed tag supports nobody.
- **A tile counts toward at most one home site of the same kind (the exclusivity rule, scoped — D-46).** Exclusivity is not global across every species: it only applies between home sites that are genuinely rivals for the same land. Where capacity radii overlap **within that scope**, each qualifying tile goes to the **nearest home site only, ties to the older site** — two fox dens in one wood split its `forest` tiles, and two Houses each keep their own `house` tile **regardless of which species lives in each one** (Human, Husky, and Shiba Inu all need `house`, and a House is the only source of it, so every one of their home sites is a structure site under this rule). **Different species never compete for the same land.** A fox den and a rabbit warren, or a cow pasture and a horse pasture, freely coexist on identical ground — real cross-species spacing, where it matters, is the Avoids system's job (see roster.md), not a side effect of tile scarcity. The radius is a real land-allocation tradeoff among same-scope rivals (#23); crowding home sites of the same kind buys nothing.
- **The predicate is the same function:** `qualifies(h, S) ≡ capacity(h, S) ≥ 1`, and an arrival is enqueued only where `capacity(h, S) ≥ population(h, S) + 1` — one read, not two systems.
- **De-qualification is live, not a one-time move-in check.** Every edit re-evaluates `capacity(h, S)` for home sites whose radius intersects it — immediately, on the same dirty event that drives arrivals. If that re-evaluation puts capacity below population, the Gentle Displacement flow is **armed but does not fire**: it runs when the neighbourhood settles, warning first and acting after, so a burst that ends where it started displaces nobody.
- **The three per-species tuning constants** (`capacity_radius`, `tiles_per_individual`, `max_individuals`) are `AnimalDefinition` fields, proposed from ecology, decided by the human (tunable — #6, #20, #23). Floor placeholder values and the full per-species table: [roster.md](roster.md).
- **v1 habitat tag vocabulary:** `water` · `forest` · `open_grass` · `quiet` · `cover` · `flowers` · `sand` · `rocks` · `cultivated` · `house`
- **v1 tag-source mapping** — which terrain (and the House) emits which tag, decided and complete (#5 closed — emission radii and weights are depth, not v1); the full table and per-terrain detail: [terrain.md](terrain.md). **Rock, not forest, is the `cover` source**, so Fox habitat is always a two-brushstroke composition (forest *near* rock), never a side effect of painting forest for Wood — see [roster.md](roster.md).
- **A tile under a building footprint stops emitting its terrain tags** while occupied; the building's `emitted_tags` are what that ground now says.

**Personality: Shy vs. Bold** — a per-species visibility trait only; it never gates whether an animal moves in. Full definition, design rationale, and deferred visibility rules: [roster.md](roster.md).

**Compatibility: the Avoids system** — some animals keep their distance from specific others: real, observable wariness with none of nature's machinery beneath it (Pillar 2), never a move-in gate, always mutual and symmetric by rule, and never the cause of a departure on its own. Full definition, the structural predation check, and the written position for player-facing copy: [roster.md](roster.md).

**Economy** — Wood is the only v1 resource: a **material, not a score, and a pacer, not an economy** (harvesting adds, building spends, removal refunds part). The reason to keep a mixed landscape is habitat diversity, not material diversity; hoarding carries no benefit. The one pricing rule is ***"Nature is free; construction costs materials."*** **No dead ends, by construction:** Forest is free to paint and passively produces Wood, so a player at zero can always paint, wait, and build again. **The passive Wood rate is v1's most load-bearing constant:** ~1 Wood per Forest tile per 60 s (#8), plus a ~5 Wood tap-to-tend burst on a per-tile cooldown (row-5 depth; floor: passive accrual only). The starting stockpile is ~50 Wood (floor ~35, sized to the 1×1 House plus a small field — #26) and **deliberately not a buffer:** covering several builds would make Wood decorative, so pacing begins at the *second* build. **A cultivated field's job** is the `cultivated` tag and the villager capacity it contributes, **not a yield**. Harvestables run **Passive + Active Boost** — no penalty for a kid who'd rather watch — and **Forest → Wood is the sole harvestable in v1**, never removing tags or disturbing residents. **Top-level counters:** Resources, Species Hosted (all-time, never decreases), Currently Resident, Village Population — information, never a score (Pillar 1); a counter going down is normal.

| Action | Cost | Notes |
|---|---|---|
| Paint natural terrain (grass, water, sand, rock, forest) | Free | the recovery guarantee |
| Paint cultivated field | ~2 Wood / tile | fencing & tools |
| House (2×2) | ~30 Wood | floor: 1×1 ~15 Wood |

**Villagers: the people species** — another entry in the animal system, no separate people/economy simulation. A villager needs `house` plus carrying capacity, with no hunger, starvation, or consumption mechanic (Pillar 1 intact); **House** is a placeable satisfying the `house` tag. **Towns are emergent, not a system.** **Village Population** sits beside the wildlife counters — a fact, not a separate scoreboard. **The villager's move-in card is a real fact card, not flavor:** the two-register rule does not bend for the one species the player happens to be. Full definition, the House/capacity relationship, and the villager fact-card gate: [roster.md](roster.md).

**Gentle Displacement** — the pillar stated precisely: **animals are never killed, and nothing blinks out unexplained.** Any loss is the warned, reversible result of the player's own settled choice, never the game's initiative (Pillar 1). **The warning is informed consent for a player who is six:** before any action whose settled effect would displace a resident — terraform, build, or removal alike, the warning being **mode-agnostic** — the game names the affected home by family (*"If you build a farm here, the fox family's den will move."*). It is **disclosure, not deterrence**: factual, upbeat, no plea, no judgment, no residue afterward. **The computable trigger:** an action warns iff, once its neighbourhood settles, `capacity(h, S)` would fall below `population(h, S)` for any home site in range — including to 0. **Frequency is bounded by settlement, not rate-limiting:** one warning per settled gesture summarizing every affected home, and a warning is never suppressed while its consequence proceeds. **Two gentle outcomes, in order: relocation** if a suitable spot exists (`capacity ≥ population` there), the animal visibly moving its home; otherwise **moving away**, a visible departure framed as finding a home elsewhere — Species Hosted and the Field Guide entry stay permanent. Departure copy speaks in the **plain game voice, not the bulletin voice** (*"The fox family moved away to find a new home."*). The warning carries the Read-Aloud 🔊 slice — consent must not require fluent reading. Choices stay discrete and tile-by-tile, **deliberately no continuous sliders** — easier for the target age to reason about. Rejected: **silent displacement** (breaks "nothing unexplained"), **blocking the build** (a fail state), and **capacity floors** making settled land un-losable (habitat goes decorative after move-in — the USP requires live land). **The written position for villager displacement — decided here, not deferred to the content pass,** because it is a pillar invariant that ships at the floor and it is the sharpest tonal hazard in the document: a displaced villager family is never described as losing a home, only as finding one. The warning names the habitat, never the loss (*"If you clear this field, the farm family won't have enough to grow here — they'll look for better soil."*), and departure keeps the plain game voice with the destination, not the cause, in the sentence (*"The farm family went off to farm somewhere sunnier."*). **The copy may never** put the player's action and the family's hardship in one sentence, nor leave a family with nowhere named to go. This is not an edge case: Human's divisor is 1 against a 1×1 floor House, which makes villager displacement the **likeliest** displacement in the floor, so these lines run early and often.

**Discovery: News Reports & the Field Guide** — the habitat-tag system is invisible and open sandboxes are often *harder* for young kids than expected, so this passive layer makes the sandbox legible (an active accelerator is deferred — future.md). **News Reports** are occasional unprompted blurbs — *"Word has it a fox is looking for a den somewhere in the woods, near a bit of rocky cover…"* — hinting at needs. **A hint is an invitation, not an assignment** (Pillar 1): the game never tracks whether one was followed, hints never expire or repeat with urgency, nothing extra is awarded for acting on one, and a report reveals that animal's **Field Guide** entry. **One narrator:** News Reports and the first-time nudge share a single cheerful local-nature-bulletin voice that reports on the world and never hands the player a task — which is what lets hints and nudges share one pool. The displacement warning is deliberately **not** that voice; consent copy must never sound like flavor. **Discovery reads the simulation; it never drives it.** Qualification produces a **near-miss summary** as a byproduct of checks it already runs (per species, how close the world comes and which tag is missing), which Discovery reads to weight *which* species gets hinted. **The copy itself never changes:** hints stay pool-generic, since naming the player's own spot would read as an assignment. An empty or stale summary degrades to plain terrain bias, so the hint layer ships independently.

### World & Cast

**Worldbuilding** — a gentle, real-ish natural world: real species, real habitat logic, real facts, all harshness **removed rather than hidden** behind fantasy. Tone rules are absolute across every content type (fact cards, news reports, warnings): factual, upbeat, never violent, the predation ban is operational (Pillar 2, enforced at the content checklist's predation check); education arrives at moments of success or curiosity, never as a lecture (Pillar 4). **The two-register rule** governs what the game may claim: **fact cards assert real-world facts** and are the entire teaching channel, source-verified through the five-step checklist; **everything else describes the game world and asserts nothing about the real one.** Creatures are *named after* real animals and shaped like them, but their behavior is the game's own gentle rulebook — predation is **absent by construction**, the convention of every classic picture-book world where the fox is a neighbor. The boundary is structural: real-world claims exist only where the checklist runs.

**The roster** — animals are pure data, so the roster is unlimited by architecture and **has no target number**: v1 ships a **floor of 3 (Human, Fox, Rabbit)** plus whatever depth the 7-week deadline buys, drawn from a **cleared pool of nine more** already imported, licence-cleared and attributed, each awaiting a step-3 design proposal. Roster size is therefore a purchase, not a promise — and species that were named early but for which no cleared asset was ever found are not roster members, not gaps, and not tracked as debt (the sourcing findings live in [art.md](art.md)). The mix varies Bold/Shy, farm-tolerant/wild-only, and 2–3 habitat needs. Full species table, per-species habitat needs and tuning, personality, avoids, the cleared pool, and the villager entry: [roster.md](roster.md).

**World structure** — **one continuous world:** a single terrain grid with natural edges and no internal boundaries in data or presentation, starting ~36×36 tiles and growing to a hard cap of ~128×128 (a performance ceiling; both tunable). **One camera, no modes (D-41, reverses D-33 back to D-13's model):** fixed pitch, pan + zoom, a continuum from a close zoom through a street-level default out to the whole revealed world, where terrain simplifies and animals collapse into paw badges — plus 90°-step rotation among four fixed isometric headings (D-44). **Never lost:** pan clamped to revealed land, full zoom-out always shows everything, Home snaps to it. **The mist is a curtain, not a gate**, never metering progress: **build or terraform within ~2 tiles of the mist and the nearby stretch unfurls a few tiles deeper** (#19) — organic chunks, a gentle chime, no cost or menu. **Revealed land never re-covers, and nothing exists behind the mist** — no terrain, animals, or simulation — and it comes up **wild grass: visually grass-family, tag-inert**, which one free Terraform tap converts to true grass. That makes the inert-land invariant *structural*: untouched revealed land contributes nothing to qualification **or to carrying capacity**, so pushing the mist can never raise a neighbourhood's population, mist-hugging is never the optimal play, and a reveal is not a dirty event. **Simulation runs everywhere all the time**; only rendering detail is gated, by camera distance. **World presets** ("Jungle Start," …) set starting terrain only, **never content gates**: every animal is eligible everywhere, gated purely by habitat tags — a Jungle-start player can dig a lake and get ducks.

**Level & world design** — tiles are **person-scale** (a villager stands ~1 tile tall, a house spans 2×2; the Overcrowd reference). The start holds a fenced ~30–40-tile farm field, two ~100–150-tile habitat pockets (the avoids-puzzle minimum), an `open_grass` buffer between, and room to grow toward the cap (tunable — #18). **Home sites** are tile positions evaluated over the species radius; the move-in prop (den, burrow, nest) is decoration — no tiles, no collision, gone if the home relocates — and a house is a home site with a fixed footprint. **The global roamer budget** scales with revealed world size as a pure performance backstop, not a design tool: capacity limits population in play; a budget that binds regularly in playtest means capacity is tuned too rich. **Animals occupy no tiles** — they roam the walkable surface freely within their home neighbourhood's capacity. Building placement rules (`allowed_terrain`, no rotation, the footprint/home-prop interaction) are in [buildings.md](buildings.md); terrain-painting mechanics (paint-bucket-simple, drag-to-paint) are in [terrain.md](terrain.md).

## Technical Overview

**Engine:** Godot — open-source, strong glTF/low-poly asset fit, solid desktop and Android export (iOS needs Mac+Xcode), and a maturing MCP ecosystem for AI-assisted development. Unity and Unreal were considered and dropped: Unity for a past lukewarm fit, Unreal for a Blueprint-centric workflow that pairs poorly with AI code assistance.

**Platforms:** v1 ships as Desktop executables (Linux/Windows/Mac) — a time-to-market choice for the 7-week schedule, not an audience-fit claim. HTML5 was evaluated and dropped on Godot's tablet export risk; Android/iOS export is planned for v2. Acknowledged disconnect: tablets, not desktops, are where kids 6–10 actually play.

**Performance:** v1 targets 30fps+ **minimum** on a ~5-year-old mid-range laptop with integrated graphics, at 1080p, held by a zoom-distance LOD strategy — full detail near the camera, progressively simplified terrain and markers further out — against a person-scale grid that runs ~16k tiles at the ~128×128 cap (~1.3k at a ~36×36 start). **Ordinary play reaches the whole-world framing directly, by zooming out (D-41)** — not only via the Home-key map peek — so the frustum-verified overview framing and full-size-world validation below need to hold under normal zoom, not just a panic-button peek. The CPU side is no longer a scaling risk: habitat qualification is event-driven, so an idle world does no simulation work, and a single player action costs `scout_radius × roster size` — independent of world size. The dirty-neighbourhood queue drains a bounded number of evaluations per frame; that queue *is* the CPU budget, and the fallback if it's ever exceeded is simply a slower drain, invisible because arrivals are already delayed. What still scales with revealed tile count is rendering and save size, not simulation. The render strategy carries a named owner and a **human-run desktop validation over a synthetic full-size world at the step-5 checkpoint**, because the headless harness cannot see a windowed run; QA's smoke test is the regression net *after* that human baseline exists, never the substitute for it. The live neighborhood preview rides the same bound: at cursor rate it computes a one-tile tag delta against cached per-home-site counts, touching only home sites whose capacity radius contains the cursor — the same `radius × roster` cost shape, never a re-scan.

**Saves:** one self-contained JSON file per world, fully human-readable because the game must not hide or encrypt its content. Contents cover **revealed land only** — reveal is a deterministic function of `(world_seed, x, y)`, so save size scales with revealed extent, never the cap: tile/terrain state; revealed-mist extent; placed buildings (type, position, tend-timestamps); animal and villager instances (position, AI state, home-site position); all top-level counters; save name; and a thumbnail — a full zoom-out screenshot, embedded as base64 in the same file. Since a player is not guaranteed to be zoomed all the way out at the exact instant of an autosave, the thumbnail is captured by cutting a hidden camera to the same overview framing the Home-key map peek uses, grabbing one frame, and returning it — invisible to the player, at save time rather than "whenever the player visits far zoom." A `save_version` field ships from day one, so post-class growth handles old saves gracefully. Autosave is invisible (~1–2 min, plus the two events the completion test hangs on — a move-in and a mist reveal completing — each written under the modal or animation that opens at that instant, so the write is unseen — plus exiting to menu; no save button, no prompts). Those two triggers are Tier 1, not polish: the success criterion is a quit → reload wrapped around exactly those moments, and interval-only cadence can lose them to a hard quit — a window close, a closed laptop lid — which no exit-to-menu save ever sees. World time pauses while the game is closed rather than simulating catch-up growth; and Export/Import lets a family copy or back up a world as a normal file.

## AI Architecture

**The shipped game contains no runtime AI.** No LLM is called by the game at any point — all AI involvement is at development time. (Animal "AI" in the gameplay sense — roaming, distance-keeping — is conventional game logic, not machine learning.)

AI's development role: the design phase was AI-assisted discussion (Claude chat); the build phase runs on **Claude Code driving a Godot MCP server** for direct scene and script editing.

**Agent roster:** five build agents, deliberately lean — review capacity, not agent capacity, is the binding constraint; agent boundaries fall along the seams the data-driven architecture already provides; dispatch is serial by default; and the Orchestrator was cut deliberately. Two more are read-only and do not widen the build roster: **Design Integrity** audits cross-doc and doc-vs-code consistency and produces findings, never edits; **Tier 1 Planner** reads gdd.md and tier1-status.md, ranks the fifteen rows' unbuilt gaps, and writes a dispatch brief for the top one, never deciding or building.

1. **Gameplay Engineer** — builds the simulation systems (terrain, habitat tagging, scouting/matching, roaming and avoids, economy, save/load, audio playback and volume control): decides whether terraforming actually changes what moves in. Largest budget line; a candidate to split. **Artifact:** GDScript/scenes.
2. **UI Engineer** — builds every screen and overlay the player touches (menu flow, HUD, palettes, Field Guide, fact-card/News Report popups, Settings): the player's entire hands-on interface. **Artifact:** UI scenes/scripts.
3. **Tech Art & Asset Pipeline** — imports and configures third-party models and audio and applies the toon shader, and **owns audio integration**: decides what the world looks and sounds like on screen, with no original asset creation. **Artifact:** configured assets, materials.
4. **Content Writer** — writes all player-facing copy (fact cards, News Reports, first-time nudge): decides the exact words a fact card says, and rewrites them the moment a source contradicts one — the shipped Fox card itself was rewritten this way after its first draft claimed a den-behavior detail Animal Diversity Web's account contradicts. **Artifact:** source-verified, checklist-passing copy.
5. **QA Engineer** — runs automated verification (schema validation, save/load round-trips, performance smoke tests against the 128×128 cap, export builds for all three desktop platforms), invisible to the player; playtesting judgment stays with the human and kid testers. **Artifact:** test suites and reports.

*(Read-only, outside the build roster:* **Design Integrity** *— audits the design docs against each other and against shipped code, reporting drift as findings it never patches. Its ground is the seam nothing else covers: a fact stated correctly in two places that later stop agreeing.* **Artifact:** *an audit report.* **Tier 1 Planner** *— reads this section and* [tier1-status.md](tier1-status.md) *to rank which of the fifteen Tier-1 rows to build next and why, stopping at a dispatch brief for* the row's own owner_agent. **Artifact:** *a dispatch brief.)*

**Content Pipelines** — adding one piece of content follows a repeatable, named pipeline through the same skeleton:

1. Asset audit (source + license, including commercial-use rights)
2. Import & look pass
3. Design proposal → human decision — the pipeline proposes gameplay-facing values from research; **the human decides.** These are game balance, never agent judgment.
4. Data entry
5. Copy
6. Attribution
7. Validation
8. Human sign-off

Each step has exactly one owner, so "the agents work together" means a strict hand-off, never shared editing: **tech-art** runs 1, 2, and 6; **the human** decides 3 and signs off at 8; **gameplay-engineer** enters 4; **content-writer** verifies 5 against source; **qa-engineer** runs 7. (Full per-item ownership and state: [content-pipeline-status.md](content-pipeline-status.md).)

**Hard gate:** nothing proceeds without a commercial-use-cleared source; there is no AI asset generation. **Floor rule:** a floor species that fails audit substitutes from the base asset set with no re-look pass.

- **Add-an-Animal** (the flagship) additionally proposes habitat needs, personality, avoids, and farm-tolerance from real ecology for the human to decide, and requires idle/walk/reaction animations plus the structural predation check before a species is accepted. Full roster definition: [roster.md](roster.md).
- **Add-a-Building**: the look pass adds **one fixed variant, one fixed facing**; the proposal covers footprint, cost, and emitted tags; data entry is the PlaceableDefinition, copy is inspect-tap flavor, validation covers footprint/placement and render. Full building definition: [buildings.md](buildings.md).
- **Add-a-Terrain**: the proposal covers emitted tags **and radius (#5)**, and harvestable resource type if any; **extending the shared habitat-tag vocabulary is always a system-wide design decision, never a pipeline default.** Full terrain definition: [terrain.md](terrain.md).

**Automation status:** [orchestration/roster-add](../orchestration/roster-add/README.md) is a companion prototype, not a build agent — it drafts steps 3, 4, and 5 for cleared-pool species and runs a deterministic step-7-style pre-check, producing proposals the human still decides on. It changes who drafts, never who decides or signs off. Its checklist currently automates 4 of the 5 fact-card steps; the graph/avoids check (Compatibility, above) is not yet automated — a named gap, not a silent one.

**Systems Pipeline** — content has a pipeline; the fifteen Tier-1 systems have one too, deliberately shorter because a system carries no asset, license, or source-verification gate: **scope the thin form → declare constants (the human decides) → implement thin → verify headless → human gate.** Deepening re-runs steps 2–5 against the full form; it is not a sixth step. Procedure: [systems-pipeline.md](systems-pipeline.md); per-row state, owners, constants awaiting a ruling and hours actuals: [tier1-status.md](tier1-status.md). The runnable procedures for content are [asset-import-pipeline.md](asset-import-pipeline.md) (the tech-art slice) with per-item state in [content-pipeline-status.md](content-pipeline-status.md).

**Content is data, not code.** Every species, placeable, and harvestable is one entry in a small set of content record types — an Animal entry holds habitat needs, personality, avoid-list, and fact text; a Placeable entry holds cost, footprint, and emitted habitat tags — with field-level schemas in [spec.md](spec.md), and design-level detail in [roster.md](roster.md), [terrain.md](terrain.md), and [buildings.md](buildings.md).
The shared vocabulary every terrain, animal, and ambient system reads from is ten tags: `water` · `forest` · `open_grass` · `quiet` · `cover` · `flowers` · `sand` · `rocks` · `cultivated` · `house`. One lesson the pilots surfaced: a fact card can pass every automated check and human read-through and still be factually wrong — only fetching and checking the source catches it — which is why verification is a hard, non-skippable gate (checklist in [spec.md](spec.md)).

## Technical Strategy

**Agent roles & workflow:** the toolchain is decided — Claude Code plus a Godot MCP server for direct scene/script editing, with design iterated through AI-assisted discussion before build. Each of the five build agents produces exactly one kind of reviewable artifact, which is its own review gate; the human orchestrates, reviews, and owns all tuning. 3D asset creation is where AI helps least, so the mitigation there is strategic rather than tooling: build on ready-made asset packs, with a human 3D-artist fallback for tricky gaps.

**Constraints, measured rather than assumed:** a series of small calibration pilots confirmed the binding constraints on an AI-assisted solo build are environmental, not model-capability limits.

1. **Network egress is default-deny.** Assets are hand-carried into the repo by a human; any pipeline step depending on the open web needs its sources allowlisted in advance, or it silently degrades to unsourced model knowledge.
2. **Editor-independence holds but run-and-observe does not.** Windowed runs die on display-server init and report false-green success; all validation runs headless, with `--import` *first* — it registers `class_name`s — then `--quit` or `--script`.
3. **Agent tooling fails silently**, returning plausible wrong answers rather than errors — `create_scene` writes non-standard properties, so scenes are authored as text instead; any load-bearing tool output gets cross-checked a second way.
4. **Context-window pressure is real but was never binding** — agents worked from the GDD accurately across nine dispatches without exhausting context.
5. **Orchestration cost scales with dispatch count, not agent work** — measured across three pilots at 0.93 : 1, 1.20 : 1, 0.60 : 1 (main loop : agents); many small dispatches carry proportionally more overhead than a few large ones.
6. **Parallel dispatch into one engine project is unsafe by default** — two agents stayed clean only because their directories were disjoint, and the global `class_name` registry, `.godot/` import cache and `project.godot` are shared surfaces; treat directory-disjointness as a precondition for fanning out.
7. **Human decision gates, not agent parallelism, are the real serialization point** — no amount of running agents side by side removes the need for the human to make and sign off on design calls, and that review time is what actually consumes the hours budget.

**Token budget:** the methodology is to measure a small calibration pilot and extrapolate, never derive from first principles — the budget's job is plausibility-checking against a ceiling, not precision. Unit of account is tokens, not dollars, priced through a swappable rate table, with input, output and cache-read tracked separately (**cache reads bill at ~0.1× input and dominate long sessions**). Development runs on a **subscription**, so marginal dollar cost is effectively zero; two numbers matter — API-equivalent cost and usage-limit share, the fraction of the weekly limit a work unit consumes, which is the one that can halt work mid-week. The build breaks into ~28 discrete work units: ~15 content-pipeline runs (the 3 floor species plus a first tranche of the cleared pool, a building, ~6 terrains), the phase 1–5 gameplay systems, and ~8 UI screens/overlays — each priced from a calibration pilot's three representative units (an Add-an-Animal run, a Gameplay Engineer slice, a UI screen) times an iteration factor for revision and QA.

| Line item | Units | Measured tokens/unit (pilot) | × 2.5 iteration | Total tokens |
|---|---|---|---|---|
| Content pipeline runs | ~15 | ~360K | ~900K | ~13.5M |
| Gameplay systems (phases 1–5) | ~5 | ~900K | ~2.25M | ~11.2M |
| UI screens + Discovery layer | ~8 | ~180K | ~450K | ~3.6M |
| QA + polish | — | ~20% of subtotal | | ~5.7M |
| **Contingency** | | | +50% | ~17.0M |
| **Projected total** | | | | **~51M billable tokens** |

At the current rate table that projects to roughly **$760 in API-equivalent cost for the v1 build** (~$850 across the whole project, phase-0 pilots included) — comfortably under the comfort ceiling, with the +50% contingency still intact. Every session appends one line to the cost ledger; the week 2–3 velocity review compares actuals against the pilot multipliers and corrects them. This is a **ceiling, not a target**: the projection is checked against a **comfort ceiling** — an API-equivalent spend and a weekly usage share the build can sustain — and fitting under it with contingency intact means the budget's job is done. If ledger actuals run well over projection, what shrinks is *purchased depth* — the fifteen thin forms are the floor and do not flex, which is why **v1 ships regardless of what the ledger says**.

## Plan

### Target Release

- **v1 — end of the 7-week class:** desktop (Linux/Windows/Mac) executables, Tier 1 scope.
- **v2 (post-class):** Android/iOS for tablets/phones, with its own reduced performance targets and a touch-input pass.

**v1 audience & platform reality.** Kids 6–10 live on tablets, so desktop v1 is a **time-to-market choice** — the cheapest platform to ship in 7 weeks once HTML5-on-tablets risk ruled web out — **not an audience-fit claim**. Read-Aloud ships thin in the floor (rows 7/10), so the payoff and the consent moment are hearable by pre-fluent readers; News Reports, the Field Guide, and menus stay text-first until full coverage lands. **v1's practical narrowing is therefore device access — a family desktop — more than reading fluency**; tablets and full Read-Aloud lead post-Tier-1.

### Milestones

Budget: **35–55 total hours** (7 weeks × 5–8 hrs/week). Three checkpoints:

- **Agent Roster pass — week 0–1, before build:** resolved the agent-roster and cost-projection unknowns via the **calibration pilot** and re-priced the phase plan in hours — what makes the math closeable.
- **Early playtest checkpoint — end of step 5:** first point the loop is playable end to end — terrain, a move-in, a surviving save. Real kid testers here, not only at the end: camera feel and tap learnability are worth catching early.
- **Velocity review — week 2–3:** allocates the remaining depth budget once real velocity and the AI-assist multiplier are measured — not *whether* to flex (every system is already thin) but **which deepens first**; it also resolves the phase 3–6 pricing residual and ledger re-verification (#30).

### Phases of Work

1. Core grid + tile placement + minimal menu shell (New Game → straight in)
2. Buildings/resources + costs
3. Habitat tagging (tiles compute tags from neighbors)
4. Animal data + scouting/matching logic
5. Spawning + roam + fact card, save/load + autosave — **early playtest checkpoint**
6. Passive Discovery — News Reports, Field Guide + reveal
7. Polish loop — menus, audio, counters, Credits/attribution, art pass
8. Playtesting with kids, bug fixing, final polish

**Build depth:** every phase targets **thin forms**. Phases 1–7 close the complete loop *thin* before anything is deepened; deepening runs alongside phase 8 in the velocity review's order, so the complete-loop test passes continuously.

**Where the hours actually go:** phases 3–6 are the human-judgment spine — habitat feel, camera feel, tuning — bottlenecked on playtesting and taste, where AI helps least; save/load, menu flow and sound are the delegable shell.

### Scope: the floor and the depth

Not all of this fits 35–55 hours. Scope decisions are "which tier is this," not ad-hoc triage. Three rules govern:

- **The complete-loop test (defines Tier 1):** at the end of 7 weeks, a stranger must be able to experience the entire core loop in one sitting, stop, and come back — start a new game → terraform → gather resources → build → an animal genuinely moves in → learn something real → the world grows at the mist → quit → load, world intact. There is no "finish"; *complete* means the whole loop, not an ending. Tier 1 is exactly the set of requirements without which this test fails.
- **Pillar invariants don't tier:** a feature enters a tier with its pillar obligations attached. If terraforming and animals ship, gentle displacement ships; if resources ship, the free-Forest no-dead-end guarantee ships; if hints ship, the Hints toggle ships — load-bearing parts of features already in the tier, not weighable features.
- **Change control:** a new row enters Tier 1 only by naming, in hours, which depth purchases it forfeits — the ledger below prices the exchange. The floor can grow; it cannot grow for free. (Applied once: the Read-Aloud slice entered rows 7 and 10 at ~1–2h against row 2's camera depth.)

**Tier 1 depth rule.** The fifteen rows below are stated in their **thin form** — the minimum that still passes the complete-loop test and carries every pillar invariant attached to it; each has a fuller form. **Thin is the default build target:** all fifteen are built thin in Phases of Work order; remaining hours deepen thin → full, the only thing build hours buy. The floor does not flex, which closes the schedule *by construction*.

| # | System | Thin form (the floor) |
|---|---|---|
| 1 | Start & persist | Fixed preset → name → in; Load a plain named list; autosave on interval + move-in + mist reveal + exit-to-menu. "Save a game" means *autosave works and Load restores faithfully* — no save button. |
| 2 | Camera & modes | The three-mode tap model ships whole (Pillar 3) — modes, cursor-position tap semantics, priority rule. Fixed orthographic pan/zoom camera at four fixed 90°-apart headings (D-41, D-44) with the three safety rails as its "never lost" guarantee, no easing; Inspect's taps thin except tap-to-tend. |
| 3 | Terraform | Five of six v1 terrains: grass, water, forest, rock, cultivated. Pricing and removal/refund policy ship whole. Cultivated because capacity reads cultivated tiles in radius — row 4's move-in needs it; **rock as the v1 `cover` source** for Fox and Rabbit (#5 resolved). |
| 4 | Build | House at 1×1, grass only (**full form 2×2**). **A villager moves in when its habitat is met** ships whole — the USP requires the proof, not the building. |
| 5 | Economy | Passive Wood from Forest only; tap-to-tend is depth. **The free-Forest recovery guarantee ships whole** (pillar invariant). |
| 6 | Habitat & move-in | Animals move in *only because a real spot met their needs* — never scripted, never timed. Causality ships whole; coarser cadence, slower scout tick (within the time-to-first-move-in ceiling — Pacing constants), waypoint wander, home prop. **Carrying capacity ships whole in its decided thin form — min-over-needs, no lower clamp, `capacity = 0` is the unsuitable state**; rows 3, 4 and 10 read it; only scoring richness and readout thin (#27). **The live neighborhood preview ships too**, its cursor-rate cost bounded (Performance). |
| 7 | Fact cards | The signature move-in card fires, **plus tap-to-replay in Inspect**: the curious tap is a pillar invariant (Pillar 4 delivers on curiosity too), not depth. One card per species; **the Read-Aloud thin slice ships here** (🔊 via OS-level TTS). Source verification is **not** a depth axis. |
| 8 | The floor roster | **Human, Fox, Rabbit.** Fox and Rabbit are cleared and shipped; **Human still faces both gates — asset audit (#4) and fact-card content (#31)**. Everything beyond the three is depth, drawn from the nine-species cleared pool. |
| 9 | Minimal Avoids | One real pair, **Rabbit ↔ Fox**, already in the thin roster, so mutual distance-keeping ships with it; symmetry rule and copy framing ship whole. |
| 10 | Gentle displacement | Guarantee and no-unexplained-vanish rule ship whole (pillar invariant), **including the warning's specifics** — from the capacity formula, mode-agnostic, evaluated at settlement — and **it carries the Read-Aloud slice**. Only presentation thins. |
| 11 | Species status | HUD counters + a flat Field Guide list. **Resident state only**; the "hinted at" column needs row 12's per-species News Reports. |
| 12 | Pointers | First-time nudge + one small shared News Report pool. **The Gameplay Hints toggle ships whole** — pillar invariant. |
| 13 | Mist | Build-proximity reveal per World Structure: band unfurls, chime plays. Instant, no sprouting — Tier-1-cheap. |
| 14 | A thin audio slice | One ambient bed + one soft confirmation SFX. Silence reads as broken; the tag-driven layer system is deferred. |
| 15 | Settings & Credits | **Credits ships whole — attribution is a license obligation, not polish.** Master volume + Hints toggle on the existing overlay. |

(What deepening buys: [spec.md](spec.md). Per-row build state, owners and constants: [tier1-status.md](tier1-status.md).)

**The travel is not evenly distributed.** Rows 13–15 barely move — already floors — while nearly all hours live in rows **2, 3, 4, 6 and 8**: camera feel, terrain count, footprints, habitat tuning, roster size. Row 8 is the strongest lever: Fox and Rabbit are already cleared and shipped (pilots 3, 3b) and *are* the Rabbit ↔ Fox pair, so row 9's floor is free. **The thin roster costs one Add-an-Animal run, not six** — Human alone remains, and the five deepening species are each a purchase rather than an obligation.

**Known thinnesses for the velocity review.** *Economy:* House and cultivated fields are the only Wood sinks; tap-to-tend buys back first. *First-time nudge:* the copy (#12) must point at cultivated or rock, the shipped roster's terrains; a water variant waits for Duck. *Human's two gates:* row 4's move-in is the USP proof and Human clears neither gate yet — **the single point of failure in the floor, and it has two independent paths.** The asset audit (#4) can substitute a model under the floor rule; the fact-card content (#31) has no substitute, because the register is fixed and no other species can carry row 4's proof. Both run inside row 8's one Add-an-Animal run; the human-fact research is the half with no fallback. *Audio and Settings:* row 13's chime and row 14's SFX are one sound, and master volume replaces the separable Ambient/SFX sliders (Pillar 5).

**The accepted residual, a decision not a surprise:** if no depth is bought, v1 ships three species, five terrains, a 1×1 house and untuned camera feel — thinner than these rows read, but passing the complete-loop test and every pillar invariant, accepted as the guaranteed outcome for a schedule that closes by construction.

**First-cut hours ledger** — the floor priced, so "closes by construction" is checkable against "closes by estimate." Estimates are human-attention hours, the currency that binds: agents multiply output, taste does not. A subset: review gates, playtest logistics, export and content verification are unpriced; re-verified, not trusted, at the velocity review (#30).

| Rows | Thin-form work | Est. hours |
|---|---|---|
| 1 | Start & persist | 2–3 |
| 2 | Camera & modes | 3–5 |
| 3 | Terraform, five terrains | 2–3 |
| 4 | Build + villager move-in | 1.5–2 |
| 5 | Economy (passive) | 0.5–1 |
| 6 | Habitat, capacity formula & preview | 4–6 |
| 7 | Fact cards + replay + Read-Aloud slice | 1.5–2 |
| 8 | Roster (one Add-an-Animal run: Human) | 1.5–2 |
| 9 | Avoids machinery | 1 |
| 10 | Displacement, warning & settlement | 2–3 |
| 11–12 | Species status + pointers | 2 |
| 13 | Mist | 1.5–2 |
| 14–15 | Audio slice + Settings/Credits | 1.5–2 |
| — | Render validation (human-run, step-5) | 1 |
| — | Integration, debugging, playtest logistics | 3–5 |
| | **Floor total** | **≈ 29–40 h** |

Per-row actuals are recorded in [tier1-status.md](tier1-status.md) as the work happens — `costs.md` tracks tokens per work unit, not human hours per row, and #30 is re-verified against measured hours, not tokens.

Read honestly against 35–55h: **the floor closes with margin only in the upper half of the range.** At 5 hrs/week (35h) the floor consumes nearly everything and depth purchases are few; at 8 hrs/week (55h), ~15–25h of depth is buyable in the velocity review's priority order. Construction guarantees *shape* — nothing cut, everything thin; this table is the claim about *quantity*, corrected at the velocity review with measured actuals.

**Everything beyond these fifteen rows is deferred to [future.md](future.md)** — designed, prioritized and priced; nothing was cut without landing there.

## Team

- **Designer/developer:** solo — minimal 3D art/modeling experience, mitigated by the asset-pack strategy; has access to people with 3D art skills for tricky assets or animations.
- **AI development agents:** Claude Code + Godot MCP — the five build agents named under AI Architecture, plus two read-only agents: the Design Integrity auditor and the Tier 1 Planner.
- **Playtesters:** actual kids in the target age range (the designer's own kids and peers), engaged from the step-5 checkpoint onward; the session protocol is [docs/playtests/protocol.md](../docs/playtests/protocol.md).
- **Class context:** built within a 7-week course.

## Revision Summary

This v1 spec is a substantial revision of the original vision document. The changes that mattered most:

- **Complexity cuts to the floor.** The hardest fight was reducing scope: the roster floor dropped to three (Human, Fox, Rabbit), and the full Companionship layer — naming, bonding, badges, Scouts, ambient life — was deferred to future work, leaving v1 a leaner, always-shippable core.   This probably remains the largest area that will need further refinement.  Agent review, peer review, and personal review all fixated here.  What can we truly get done.
- **Simulation model optimized.** Continuous world-scanning gave way to event-driven qualification on a dirty-neighbourhood queue, so CPU cost now scales with a single player action (`scout_radius × roster`), not with world size.   Agent review pointed out the non-LODable cost, which really was a defect in the original intent.
- **Carrying capacity made precise.** The qualitative "a small wood holds two foxes" became an explicit min-over-needs formula (Liebig's law of the minimum) with a tile-exclusivity rule and three tunable per-species constants.
Agent review pushed back hard on how we scoped how animals would move in, many refinements were made to simplify and fine-tune just what we actually needed and intended to implement.
- **"Done" made testable.** A concrete success criterion and the beat-by-beat *First 60 Seconds* acceptance script replaced the earlier UX aspiration, giving the step-5 kid playtest a real pass/fail bar.   With a game that has no real win/lose scenario, it became important to define an objective to meet in-game.  This is what agent review pushed back on hardest — but it makes sense: defining what the player is actually supposed to do, in a game with no win/lose state, took real work, and needs more still.
- **Worldbuilding, displacement, and return tightened.** The two-register rule and structural predation check hardened the safety doctrine, and Gentle Displacement gained settlement/grace-window semantics plus a decided villager-displacement voice — so every departure and return is warned, gentle, and never unexplained.    Personally I had trouble, and Agent Review pointed it out, defining what happens when animals have to leave, while still maintaining the Pillars of the game.   Turns out it is hard to NOT model predation in a game!
- **My Largest Concern still stands in some respect.** I still personally have a hard time accepting the time/functionality limitations I am facing.  As an example, the plan stripps the species count to three, but I believe this is actually unacceptable, and too limited.  I need further work on Asset pipeline flow, as I believe this will be a key time-cost.
