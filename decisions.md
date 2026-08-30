# Design Decisions

The rationale companion to [gdd.md](gdd.md). The GDD states **what** the game is; this log records **why**, and — more importantly — **which alternatives were considered and rejected**, so those debates don't have to be re-litigated inside the spec.

**How this relates to the other docs:**
- **gdd.md** — the spec. States each rule and invariant *once*, and points here (`see decisions.md → D-NN`) instead of re-arguing it.
- **future.md** — deferred and cut *features*, with return conditions. Where a decision cut a feature (Harmony Mode, Village Happiness/Amenities, multi-resource economy), the feature lives in future.md and the *reasoning* is summarized here with a pointer.
- **decisions.md** (this file) — the reasoning behind decisions that shape v1 as it stands.

Entries are stable-keyed (D-01…). When the GDD references a decision, it uses the key.

---

## Philosophy & progression

### D-01 · No win/loss; counters are information, not score
**Decision:** There is no win or loss condition and no game-assigned objective. Every number on screen (Resources, Species Hosted, Village Population, bond level, badge count) is a *status indicator*, never a target.

**The testable form — "the indicator test"** (this is the one piece kept in the GDD, under Objectives & Progression): a status display becomes a *goal* only if the game (a) presents its value as a target to reach, (b) reads its value back to gate content/rewards/systems, or (c) defines a completion or failure state over it. A display that only *shows or celebrates what already happened* is an indicator. Every progression surface in the game passes all three clauses.

**Why:** The design intent is a sandbox a kid falls in love with and keeps returning to, not a game to "beat." Ten badges and a hundred are equally good outcomes; one bonded animal and twenty are equally valid ways to have played. "Done" is not a state this game has.

**Rejected:** any completion percentage on the Field Guide, any previewed badge threshold, any content gated on a counter. All would convert an indicator into a goal.

### D-02 · The game never initiates loss
**Decision:** Nothing bad ever befalls anything a player loves except as the warned, non-lethal, reversible result of the player's own choice. Bonds never decay; no animal sickens, sulks, or leaves on its own; absence is never noticed, guilted, or rewarded against.

**Why:** The pillars ban *manufactured* stakes (pressure, decay, threatened loss), not warmth. A companionship system that produced no attachment would be the actual failure — so attachment is the point, and the guarantee is that the game never uses it as leverage. See D-10 for how the single legitimate door (the player's own disclosed build choice) is handled.

---

## Tone & the no-harm line

### D-03 · Predation ban is operational, not atmospheric
**Decision:** No content anywhere depicts, names, or alludes to hunting, animals eating animals, danger, or fear. The enforcement point is the content checklist's predation check, not a vibe.

**The line is behavior vs. event:** the game models what a quiet wildlife-watcher can observe (wariness, distance) and simulates nothing beneath it. Because no harm exists anywhere in the world, "some animals prefer their own space" is the whole truth of the world, not a euphemism over a hidden one.

**Why:** Harshness is *removed*, not hidden behind fantasy. A child's further "why?" about real foxes and rabbits is deliberately left with the real world and the family — the same place every fact card stops (a fox's card highlights hearing and family life, never diet).

### D-04 · Avoids is symmetric, and the copy must be too
**Decision:** The Avoids system is mutual by rule — declared on either species' entry, treated as symmetric at runtime. The data model literally cannot express "hunts." Every avoids-related string names both parties as equal subjects, or names only the relocating animal's own comfort: *"Foxes and rabbits each like plenty of space of their own."*

**Why symmetric:** A predation relation is asymmetric (predator seeks, prey flees). Making Avoids symmetric is what structurally excludes a food-web reading — the fox gives the rabbit space exactly as the rabbit gives the fox space.

**Rejected copy — and why it matters:** an earlier draft read *"Rabbits prefer to keep their distance from foxes."* One-directional phrasing is exactly how a predator-prey reading re-enters a system built to exclude it — it makes one animal the actor and the other the reactor. This was flagged independently by three agents during the pilot-3 content pipeline run. The rule now governs every avoids string, including relocation notices.

### D-05 · Harmony Mode toggle — cut
Cut; full reasoning and return condition in [future.md](future.md) ("Harmony Mode"). Summary: the base game is already nearly harmony (avoids never gates a move-in; worst case is a gentle announced relocation), so the toggle bought little while creating a structural eviction hazard (switching it off mid-game turns previously-legal arrangements into violations) and doubling the rule-set to balance and test. The avoids puzzle also teaches something true and complete on its own — some animals need their own space.

---

## Economy

### D-06 · One resource (Wood); a pacer, not an economy
**Decision:** Wood is the only resource in v1. It is a *material*, not money and not a score: harvesting adds to a stock, building spends it, removal refunds part.

**Pacer, not economy:** Wildhaven has a **pacer** (Wood) and a separate **strategy layer** (land allocation under carrying capacity). The pacer's whole job is to make building deliberate rather than summoned. The distinguishing test: an economy asks *what should I spend on?*; a pacer asks only *have I waited?* The design does not claim depth or material diversity for the v1 economy.

**Rejected:** a consuming-resource model (villagers or animals eating down a stock, scarcity as the reason they leave) — it would make a departure something the game initiates from a drained counter rather than something the player chose (violates D-02). The full multi-resource economy is deferred, not abandoned — see [future.md](future.md) ("Multi-resource economy").

### D-07 · No dead ends, by construction
**Decision:** Because Forest is free to paint and passively produces Wood, a player at zero resources can always paint free Forest, wait, and build again. There is no reachable state without a recovery path.

**Why it's structural:** the "no fail states" pillar holds *by construction*, not by tuning. This closes a previously-undocumented soft-lock: terraforming away one's last harvestable tiles while at zero stock.

---

## Villagers & the town

### D-08 · Villagers are just another species
**Decision:** Villagers ("person animals") are one more entry in the animal system — no separate people/economy simulation. Their habitat need is `house` plus carrying capacity (cultivated tiles within radius determine how many families a house supports). A villager moving in is the same payoff as any move-in, because it's the same system firing.

**Rejected:** a hunger/starvation/consumption mechanic for villagers — static requirement instead, never draining. Same reasoning as D-06: a family's departure must come from the player's build choice, not a drained counter. This is the load-bearing proof of the data-driven design and the game's USP ("people are just another species").

### D-09 · Village Happiness + Amenity Buildings — cut
Cut after review (not deferred by schedule); full reasoning and species-shaped return condition in [future.md](future.md) ("Species amenities"). Summary: Village Happiness (a meter nothing read) and flat-bonus Amenity Buildings (Well, School, Market) were the only two mechanics not derivable from the villagers-are-a-species model — the residue of a town-builder this game isn't. When amenities return, they return as species-targeted placeables (a Well for villagers exactly as a birdhouse is for birds), never as a happiness meter.

---

## Companionship & displacement

### D-10 · The habitat-loss warning is disclosure, not deterrence
**Decision:** Before a terraform that would displace a resident, the game warns with specifics that name the affected home — and, for a named individual, the name itself (*"If you build a farm here, Layla's family den will move"*). If the player proceeds, so be it.

**Informed consent for a player who is six:** a young child cannot be assumed to infer spatial consequences (that building *here* displaces a den over *there*), so the game states the consequence before it happens. Naming the individual is *precision, not pathos* — "a fox family's den" doesn't tell the kid *which* home; "Layla's family den" does.

**Rejected — both crueler:**
- **Silent displacement** (kid discovers Layla gone) — the one design that genuinely *would* manufacture attachment-and-loss (violates D-02).
- **Blocking the build** — turns a beloved animal into an obstacle and invents the game's only fail state.

**The capacity-loss extension is not optional:** under universal carrying capacity, a terraform can drop a neighborhood below its population with no footprint overlap at all (a field paved outside the fence line was the acreage feeding someone). The warning must fire on that loss exactly as on overlap — without it, silent displacement re-enters by a different mechanical path.

**Copy & staging rules:** factual and upbeat, no plea, no judgment, no sad animation/expression/music sting; once the player proceeds, the event leaves no emotional residue — nothing "misses" its old home, nothing references the event again. The world carries no grudge.

### D-11 · Right of first return
**Decision:** A named individual that moved away is remembered in the save (name, bond level, appearance seed); when its species next finds suitable habitat, the animal that moves in *is* that individual. Multiple departed individuals of one species return in the order they left.

**Why:** makes "moving away" genuinely non-lethal and reversible (supports D-02) — the door stays open, and Species Hosted / the Field Guide entry are already permanent.

### D-12 · Any individual can be named (no per-species cap)
**Decision:** Any individual can be named, villagers included, with no per-species limit.

**Rejected:** an earlier one-named-individual-per-species rule — it contradicted the village (many villagers get named, and people are just another species per D-08). Scope stays bounded without a separate cap: nameable individuals are exactly the mechanical residents, whose numbers carrying capacity and the roamer backstop already cap, and a name is two save fields (`name`, `bond_level`).

---

## World, camera & simulation

### D-13 · One seamless world, one camera, no modes
**Decision:** A single continuous terrain grid under one fixed-pitch (~45°), fixed-heading (north-up), pan-and-zoom camera. No view modes; no camera rotation.

**Why this camera:** no rotation → no disorientation and every asset needs only one authored facing; fixed pitch avoids collision/clipping problems; the pan/zoom continuum delivers 3D depth and "watch the animals roam" appeal without free-fly navigation complexity.

**Known tradeoff (accepted):** Minecraft's appeal partly comes from being *inside* what you build; this design deliberately trades that for safety, performance, and orientation.

**"Never lost" replaces the old contained-view guarantee** with three rails: pan clamped to revealed world, full zoom-out always frames everything, Home key/button snaps to full zoom-out.

### D-14 · The mist is a curtain, not a gate — and nothing is behind it
**Decision:** Beyond the revealed edge sits soft mist. Building/terraforming within ~2 tiles of it unfurls a few tiles deeper. Revealing land has no cost, benefit, reward, or consequence beyond more land to terraform. **Nothing exists behind the mist** — no terrain data, no animals, no simulation; revealed land always comes up grass that carries no habitat value of its own. *(Correction, 2026-07-21: this originally read "habitat-neutral grass," which was false — plain grass emits `open_grass`, which was Rabbit's entire requirement, so revealing would have handed the player finished rabbit habitat. What makes revealed land genuinely inert is the inert-land invariant; → D-22.)*

**Why "nothing behind it" is load-bearing:** it's the mechanism that makes the no-reward promise *true* rather than merely asserted — there is nothing out there to find, farm, or attract. Every forest, pond, and rock beyond the starting world is something the player terraformed.

**Why carrying capacity must be local, not global:** the mist is free to push, so a global tile budget would dissolve the first time a player walks the world open. Radii can't move with the player, so competition is always local; pushing the mist back only hands the player a fresh neighborhood with the same internal problem.

### D-15 · Person-scale tiles, not parcel-scale
**Decision:** A tile is person-/furniture-scale (a villager stands ~1 tile tall, a house spans 2×2), the Overcrowd reference.

**Rejected:** the earlier parcel-scale draft (one tile = a whole house). Person-scale is what makes the world read as dense and alive up close — buildings tower over animals, fences enclose real space, a pond is a place rather than a puddle. Accepted cost: more tiles (a full ~128×128 world ≈ 16k tiles), handled by LOD (see gdd.md → Performance Targets).

### D-16 · Roamer budget is a backstop; two old rules deleted
**Decision:** The global roamer budget exists purely as a performance backstop and must never be the constraint that limits population in normal play — that job belongs entirely to carrying capacity, which makes the cap diegetic instead of imposed.

**Deleted outright:** (1) a minimum same-species home-site spacing, and (2) a soft ceiling of ~15–20 roaming individuals per screen-sized area. Both were performance/legibility constraints dressed up as design. If the roamer budget binds regularly in playtest, that's a signal capacity is tuned too rich — not a lever to balance the game with.

### D-17 · Static local climate, not rotating seasons
**Decision:** "Seasons" are static local climate — each area's cosmetic weather is driven by its dominant terrain tags. Purely cosmetic; a wintery corner beside a desert is fine because nothing is compared between places.

**Rejected (after research):** Stardew's global season cutover and Animal Crossing's real-calendar sync — both impose a consistency this design doesn't want. Minecraft's per-biome weather is the reference. True rotating seasons remain a post-class stretch (see gdd.md → Future).

---

## Process & architecture

### D-18 · The Orchestrator agent — cut
**Decision:** The dev-agent roster is five agents, no Orchestrator.

**Why:** Orchestration produces no reviewable artifact (failing the roster's boundary rule), and on a solo project the orchestrator already exists — the human plus the main Claude Code session. Budgeting it as a sixth teammate would add token cost and diffuse accountability without adding capability.

### D-19 · Content-pipeline learnings (pilots 1–3b)
Operational findings from the content pilots. These informed the fact-card checklist and register rules in gdd.md → Data Schemas; the anecdotes are recorded here so the GDD can carry only the resulting rules.

- **Verification is the expensive, non-optional step.** Verifying one fact card against sources cost ~2.7× the entire drafting pass (~10× per unit of copy). Pilot 3's fox card asserted a fox family "shares one cozy den" (false — the male doesn't enter the maternity den) and placed kit play in daylight (sources place fox activity at night/twilight). That copy passed length, tone, and predation checks, cleared human sign-off, and was locked by 68 passing test assertions — **wrong and fully approved.** Only fetching the sources caught it.
- **Check terminology against the whole roster, not just the source.** Both standard terms for baby rabbits were unusable: "kits" collides with the shipped Fox card, "kittens" with Cat. Neither collision is visible from the rabbit's own sources. Rabbit uses plain "baby rabbits." Register is US English roster-wide ("kits" not "cubs"; reject UK "brush" for a fox's tail).
- **Species precision is load-bearing.** "Rabbit" resolved to European rabbit (*Oryctolagus cuniculus*) over eastern cottontail deliberately: cottontails are solitary, mutually intolerant, and shelter in a scrape, which would have deleted the safe copy territory (leaving only locomotion and vigilance — both predation tropes in costume). Pick and record the species before writing; claims don't transfer between close relatives.
- **Watch for predation facts with the predation surgically removed** — the dominant, subtle risk on prey species. A rabbit sitting up with ears turning is charming and entirely an early-warning behavior with the threat left offscreen; the fox's snow-dive and "hears a mouse under the snow" are the same. These get cut, not softened.
- **Proposed fifth checklist step, deferred:** *"does any clause assert something no source addresses?"* — both pilot-3 defects were claims that outran their sourcing, a gap the four steps don't structurally catch. Revisit if a second species hits the same failure mode.

### D-20 · API/environment constraints — the binding limits are environmental
Full detail in gdd.md → Technical Strategy → API Constraints (kept there as operational reference for the build). The generalizable finding recorded here: **none of the three anticipated model-capability limits (usage, context window, latency) turned out to be binding.** The real constraints were environmental — default-deny network egress (assets and sources blocked until allowlisted), headless-only runs (windowed runs die silently and produce false-green verification), and tools that fail by returning plausible wrong answers rather than errors. Cross-check any load-bearing tool output against a second method.

### D-21 · Tier-1 flexes by depth, not by cutting content
**Decision:** Every Tier-1 requirement has a documented **thin form** — the minimum version that still passes the complete-loop test and still carries its pillar invariants — alongside the **full form** the GDD states. Thin is the default build target; leftover hours buy depth, and Tier-1 deepening outranks every Tier-2 item. Full detail in gdd.md → Plan → Scope Tiers → Tier 1 depth rule.

**Why:** A design review found that Tier 1 was fifteen mandatory interdependent systems against a solo 35–55-hour budget, with a relief valve — the old content-volume flex rule — that could only trim News Report blurbs and roster size. Neither dial had enough travel to absorb a system-sized overrun, so the schedule could not be shown to close. The finding was upheld: `costs.md` corroborates it rather than refuting it. Its 28–32h projection applies one blended ~1.0h-per-unit rate flat across all ~30 work units, including phases 3–6. That rate is generous against the ~0.5h its two content pilots averaged — but it was derived only from delegable-category runs, and applying it flat is precisely what `costs.md` warns against ("extrapolate review time separately, not at the gate rate"). All four pilots measured the delegable categories; none measured the human-judgment spine.

**The key reframing:** the defect was never estimate precision. A sharper number against a stuck valve is a better-documented failure. Under the depth rule nothing needs cutting — every system ships at whatever depth the hours bought — so closure stops being a prediction the phase-0 pilot must prove and becomes a property of the build order.

**Rejected — split Tier 1 into 1a / 1b:** re-derive Tier 1 strictly from the complete-loop test, demoting the roughly five items the test does not literally require (roster size, Avoids, Field Guide, News Reports, the audio slice) to Tier 2. This gives a genuine system-level valve, but at the cost of shipping a game with no Avoids data and no audio — quality floors rather than optional depth. Notably it would also strand the Avoids system with zero data in it, the same failure the roster risk note warns about.

**Rejected — replace the tiers with an ordered walking-skeleton build:** a strict build order shipping whatever state the clock reaches. It delivers the same closure property, but as a larger rewrite of the Plan section, and it discards the tier vocabulary the rest of the document already uses.

**Rejected — more phase-0 measurement first:** run a pilot against a phase 3–6 unit before changing anything. Rejected on a structural ground, not a budget one: a phase 3–6 unit *is* habitat tuning, camera feel, and roam quality, none of which can be measured before a grid, terrain, animals, and a camera exist. You cannot pilot camera feel before there is a camera. That measurement is only available during phases 3–6, which is where the velocity review already sits.

**The accepted residual, stated so it is a decision rather than a surprise:** if no depth is ever bought, v1 ships three species, four terrains, a 1×1 house, and untuned camera feel. That passes the complete-loop test and every pillar invariant, and it is a thinner game than the Tier-1 list reads. Thin-first accepts that floor as the guaranteed outcome in exchange for the schedule closing by construction.

### D-22 · Habitat qualification is event-driven; hints are a separate system
**Decision:** Split the single thing the GDD called "scouting" into two systems. **Habitat qualification** — the simulation deciding who moves in — runs only on discrete events: the player terraforms or builds, or a resident arrives or departs. Each event marks the affected neighbourhood dirty and re-evaluates it; qualified spots enqueue an arrival on a randomised delay, re-checked when it comes due. **Discovery** — News Reports, the player-facing hint layer — stays a pool on an ambient cadence, reading a one-way near-miss summary to weight *which* species it hints, never changing its copy.

**Why:** habitat state cannot change on its own — harvesting never removes tags (gdd.md → Economy), climate is static (→ D-17), and Pillar 1 bans timers. A continuous whole-world scan was therefore recomputing an answer that could not have changed: wasted work by construction, and the source of the review finding that ~16k tiles of habitat propagation and scouting "cannot be LOD'd away." Event-driven makes idle cost zero and per-action cost independent of world size, which turns the ~128×128 cap into a rendering and save-size question rather than a simulation one. The dirty-neighbourhood queue is the CPU budget the review found missing; its fallback is a slower drain, invisible because arrivals are already delayed.

**The inert-land invariant came out of this:** revealed land must satisfy nobody on its own, so no species' `habitat_needs` may be a subset of the tags bare land emits — enforced by automated `.tres` validation, with the bare set derived at validation time rather than hardcoded. Rabbit was the sole violation (`open_grass` alone) and gains `cover`. `cover` was chosen over `flowers` because four species already require it, so its tag-source mapping is mandatory regardless, whereas `flowers` is required by none and would have added a fifth emitter inside a 7-week build. Two consequences recorded: the roster's need-range becomes 2–3 (Rabbit was the only single-tag species), and rabbit copy must frame `cover` as comfort rather than safety, the predation-removed trap from D-19.

**Rejected:** a distinct zero-tag bare-ground terrain (correct, but costs a new terrain plus an art look), and exempting untouched land from candidate home sites (an invisible, arbitrary-feeling rule that would bar a rabbit from a meadow identical to one it would otherwise settle).

### D-23 · The Systems Pipeline; the roster stays at five build agents
**Decision:** The fifteen Tier-1 systems rows get their own pipeline — **scope the thin form → declare constants (the human decides) → implement thin → verify headless → human gate** — with a per-row record in `game-design/tier1-status.md`, mirroring the procedure/record split that already works for content (`asset-import-pipeline.md` / `content-pipeline-status.md`). Deepening re-runs steps 2–5 against the full form rather than adding a sixth step. `lead-game-designer` is retired and replaced by a read-only `design-integrity` auditor; the build roster stays at five. Full detail in gdd.md → AI Architecture → Systems Pipeline.

**Why a pipeline at all:** the two existing pipelines are both *content* pipelines, and content is roughly 15 of the ~28 work units. The other ~29–40h of the floor is systems work with no defined flow and no shared view of state — which meant the week 2–3 velocity review had no artifact to read and #30's "measured actuals" had nowhere to be recorded (`costs.md` tracks tokens per work unit, not human hours per row).

**Why five steps and not eight:** the content flow has eight because it has an asset gate, a license gate, a research gate and a factual-verification gate. A system has none of those. Mirroring the shape for symmetry would have added three empty stages, and ceremony is paid in human-attention hours — the binding constraint. **Step 2 is the one that earns its place:** batching every tuning number into one gate converts N mid-implementation "what number?" interrupts into a single decision, which is a net *saving* of the currency that actually binds. Step 3's requirement to declare `implementation_location` *before* building is what makes Technical Strategy #6's directory-disjointness precondition checkable rather than hoped-for.

**Why the roster does not grow:** D-18 cut the Orchestrator because review capacity, not agent capacity, is binding. That reasoning applies unchanged to every proposed addition. **Playtest facilitator — rejected:** gdd.md and qa-engineer both explicitly reserve playtesting judgment for the human and kid testers; making it an agent's job would contradict a stated boundary. It became a protocol document (`docs/playtests/protocol.md`) instead. **Release/compliance agent — rejected:** qa-engineer already owns export builds and tech-art already owns attribution, so the gap was a *checklist*, not a role (`game-design/release-checklist.md`); the one genuine hole — the in-game Credits screen that satisfies CC BY's "visible to the player" condition — is Tier-1 row 15 UI work, now named in ui-engineer's lanes. **Design integrity — accepted as an agent** after considering a pure grep script: the script is cheaper per run and deterministic, but the drift that actually matters is semantic (two docs stating the same fact differently, a reference that stops resolving after a restructure), and a fixed assertion list only protects what someone thought to list — the lesson `.superpowers/sdd/progress.md` already records from the trim. The mitigation for the script's advantage is that the agent ships *with* the assertion list, so its floor is mechanical and its ceiling is not.

**Why lead-game-designer is retired rather than repaired:** its job was validating gdd.md's structure against a GDD template. That work is finished, the doc set has since split into eight cross-linked files, and the agent could not complete a run in any case (it wrote to a `reviews/` directory that does not exist). Nothing live should reference the template again.

**Deferred, recorded so it is a decision:** the nine imported bonus species (deer, stag, horse, donkey, cow, bull, alpaca, husky, shiba_inu) are outside the decided eight and are **not** floor debt, despite reading as nine 🚧 rows. Their audit, import and attribution are done; what remains is the expensive half (ecology proposals and source-verified fact cards, measured at ~2.7× drafting cost). They are the cheapest available depth purchase and are sequenced at the velocity review. The tracker gained a `class` column so the distinction is visible, and a generic **resume rule** — batch by step, not by item — replaced what would otherwise have been a duplicate short-form pipeline document.

### D-24 · The roster has no target count
**Decision:** Cat, Monkey and Leopard are **not roster members** and are no longer tracked as gaps, targets, or debt. They carry no row in `roster.md` or `content-pipeline-status.md`; the sourcing research survives in `art.md` as a **Sourcing Watch-List** so nobody repeats the search. In their place, the nine imported-and-cleared species (Deer, Stag, Horse, Donkey, Cow, Bull, Alpaca, Husky, Shiba Inu) become the **cleared pool** — roster candidates in their own right, past the expensive gates, each awaiting a step-3 proposal. **The roster is a floor of three plus whatever depth the hours buy.** The "8 species" target is retired.

**Why:** the eight were a design-phase target, and three of them turned out to have no cleared asset anywhere evaluated. Carrying them as ⛔ rows made a *sourcing outcome* read as a *failure against a plan* — three permanent red marks for species that were never going to ship, sitting next to nine perfectly good species filed as "bonus." That framing had it exactly backwards: the nine are past audit, import and attribution, which is the expensive half, while the three never cleared step 1. Counting what exists rather than what was once named makes the available roster **larger** than the original target (3 floor + 9 cleared vs. 8), not smaller.

**The consequence in data:** Rabbit's `avoids` carried `leopard`, a deliberate dangling reference that `test_rabbit_schema.gd` enshrined as expected-pending ("inert until a leopard.tres exists") and that made `validate()` return exactly one permanent problem. With Leopard not coming, that was dead data pointing at nothing. `leopard` was removed from `rabbit.tres`, the test now asserts `unresolved_avoids()` is empty and `validate()` returns zero problems, and row 9's depth becomes a second pair drawn from the cleared pool — the village dogs (Husky / Shiba Inu) are the natural candidate. Late-binding `Array[String]` avoids ids remain non-fatal by design; there is simply nothing unresolved left to exercise it.

**Chicken and Duck are unaffected and stay open.** They differ from the three: a cleared source *does* exist (Synty SIMPLE Farm Animals Cartoon), it is merely unpurchased. **Whether to buy it at all is now a velocity-review call** — nine free cleared species already exist, so the purchase must justify itself on Duck's water habitat, the one axis nothing in the pool covers, rather than on roster volume.

**Rejected — move the three to `future.md`:** the project's standing rule is that nothing is cut without landing there, and this looks like a cut. It isn't. `future.md` holds *designed, prioritized and priced* work waiting on time; these three are waiting on an asset that may never exist, and filing them there would have re-created the same false debt in a different document. The watch-list is the honest home: research, not roadmap.

**Rejected — delete every trace:** the sourcing findings are real work (a live 109-result poly.pizza search among them) and deleting them invites repeating it.

### D-25 · Step-0 build unblocks: the tag model, packs, and the terraform brush
**Decision:** Three items closed so implementation can start, all resolved toward the simplest form that still carries the design intent.

**1. The tag model — tags are a property of the tile (Model A).** A tile's tag set is a pure function of what occupies it: its terrain type, or its building's `emitted_tags` where a footprint suppresses the ground. Tags do **not** spread to neighbouring tiles, carry no per-source emission radius, and have no distance weighting or per-tag "counts as met" threshold. `count_t` in the capacity formula is a plain count of tiles in the species' radius whose own terrain emits `t`. **Closes #5**, and removes the threshold half of #6.

*Why:* two documents described two incompatible data models — `terrain.md` said tiles accumulate tags "from their own terrain **and their neighbors**... at what radius, and with what weight," while the capacity formula said plainly "**count qualifying tiles** within radius." An implementer would have had to guess, which made this the single item genuinely blocking rows 3, 6 and 10. The alternative (Model B — tags diffusing with distance falloff and per-tag thresholds) needs three more undefined parameters and puts a second nested radius loop inside an evaluation that is already O(radius²), against a 35–55 hour budget.

*What survives:* the design intent Model A appears to threaten. Fox needs `forest` **and** `cover`, and with a species radius of 8–12 tiles, "both present within the radius" already **is** "forest near rock" — the deliberate two-brushstroke composition holds with no diffusion at all. **"Nearby" is expressed entirely by the species' radius, never by a radius belonging to the terrain.** Model B is not rejected, only deferred: it is already listed as row-6 depth ("tag radius richness"), so the design had implicitly chosen the thin form and simply never said so where an implementer would look.

**2. Packs and families — accepted as direction, uniform size 1 in v1. Narrows #7.** Species arrive as social units whose size varies by species. v1 ships a group size of 1 for every species, villagers included.

*The important clarification:* the *ceiling* was never open. Carrying capacity already answers "more forest and rock → more animals; more houses → more families" — that is exactly `min over t (floor(count_t / tiles_per_individual))`, and Human's `house`/`cultivated` needs at `tiles_per_individual = 1` mean house tiles already drive family count. What packs add is a different axis: how many individuals arrive **per move-in event**, versus how many the land supports in total.

*No new field in v1.* The arrival predicate is already `capacity ≥ population + 1`, which encodes group size 1 exactly. A `group_size` field is deliberately **not** added yet, for the same reason `capacity_radius` and `max_individuals` are currently a documented-but-unimplemented defect: a field with a uniform value and no formula is inert, and it invites a value nothing knows how to consume. **The question that must be answered before the field is worth adding:** does a group of N arrive only where `capacity ≥ population + N`, or does it arrive partially and fill over time? The generalization seam is one line — `+ 1` becomes `+ group_size`.

**3. The terraform brush — single-tap only. Closes #17.** One tap converts one tile. Drag-to-paint moves to row-3 depth. It is a comfort improvement rather than a capability, and single-tap is the form that most obviously satisfies Pillar 3's "pick a mode, then tap."

**Net effect:** the open-question count drops by two closed (#5, #17) and two narrowed (#6, #7), and — more to the point — **nothing structural now blocks writing simulation code.** Every remaining open item is either tuning that cannot be answered before the game runs, content that placeholder text unblocks, or process. See [game-design/next-steps.md](game-design/next-steps.md).

### D-26 · TerrainDefinition — the tag-source mapping becomes data
**Decision:** Terrain types are `TerrainDefinition` resources (`id`, `display_name`, `emitted_tags`, `cost`, `model_scene`, optional `harvestable`), one per type including **wild grass**. Those resources collectively *are* the tag-source mapping; terrain.md's table is the human-readable statement of what the data says, not a parallel source of truth. Added to spec.md → Data Schemas alongside the other three.

**Why it was forced rather than chosen:** `terrain.md` previously stated outright that "there is no dedicated schema resource for terrain as such — emission is expressed directly in the tag-source mapping." That sentence and spec.md's inert-land invariant could not both be true. The invariant requires `BARE_TAGS` be **derived from the tag-source mapping at validation time, never hardcoded** — and a markdown table cannot be derived from at runtime. Two further decided rules point the same way: "content is data, not code," and Add-a-Terrain's data-entry step needs an artifact to produce. The contradiction was invisible until someone tried to implement it, which is the argument for building earlier in general.

**The derivation's failure mode, made explicit.** `TerrainDefinition.derive_bare_tags()` returns the `wild_grass` entry's `emitted_tags` — empty today, which is the correct answer. But it *also* returns empty when no `wild_grass` entry exists at all, which would make the inert-land invariant **vacuously true** while looking green. `test_bare_tags_derivation.gd` therefore asserts the entry exists *before* asserting the result is empty, and separately proves the function is a real derivation (a synthetic `wild_grass` emitting `["quiet","flowers"]` must return exactly that) rather than a constant. A `validate()` rule also rejects any `wild_grass` entry with non-empty tags, so the invariant cannot be broken by a data edit.

**Not yet reconciled, deliberately:** `AnimalDefinition.BARE_TAGS` remains the hardcoded `["open_grass","quiet"]` while the derivation returns `[]`. They disagree, but the hardcoded set is a strict *superset*, so the species-side subset check is **over**-enforced, not under-enforced — a species needing only `open_grass` is rejected today and would be accepted under the derivation. Safe direction. Reconciling belongs to row 6 and will require rewriting `test_inert_land_invariant.gd`, not just flipping a constant, because three of its assertions become inapplicable.

**Amended 2026-07-27, same day, by human ruling on the three flagged calls:**
- **`house.tres` keeps the real imported asset**, not the grey-box. The grey-box House stays as a labelled fallback if the unconfirmed facing fails its look pass.
- **`HarvestableTileDefinition` loses `model_scene`.** The question asked was whether *future* harvestable types justify the duplication. They justify the opposite. The split earns its place through a case the duplication would break: two terrains sharing one yield rule — a future Old-Growth Forest producing Wood on identical terms references the same resource — and **a rule shared by two terrains cannot own one model**. So the resource stays separate (it is a *yield rule*, not a thing on the ground) and the model lives only on the host `TerrainDefinition`. `spec.md` and `terrain.md` updated; `test_harvestable_schema.gd` now pins the absence in both directions so the field cannot creep back.
- **`PlaceableDefinition.pending_signoff()` stands** — a building's inspect-tap flavor is not an animal fact card, and release gating reads `pending_signoff()`.
- **Placeholder values pinned, not ruled:** cultivated_field 2 Wood, House 15 Wood, footprint 1×1. The human reviewed and accepted these as the working values; **#8, #18 and #26 stay open** and the `PROPOSED` markers stay in place. Pinning means the tests will report when a value moves; it does not mean the value is decided.

**Also recorded:** `project/scripts/definitions/` is now shared by rows 3, 4, 5, 6 and 8 — the first directory that breaks the disjointness precondition parallel dispatch depends on (Technical Strategy #6). The four schemas are separate files so ordinary edits do not collide, but they share the ten-tag vocabulary, which lives once in `AnimalDefinition.HABITAT_TAGS` and is *referenced* by the other three precisely so it cannot drift. Consequence: those rows must not be dispatched in parallel while any schema is in flux.

### D-27 · Four human gate rulings — schema, divisor, hitbox, sign-off backfill
Taken 2026-07-28, working the human-gate list one item at a time.

**1. `capacity_radius` and `max_individuals` become real `AnimalDefinition` fields. The documents win.**
`spec.md` and `roster.md` both list them; `animal_definition.gd:117` stated the opposite as a decision ("Capacity reuses `scout_radius` … there is deliberately no second radius field"), and `CapacityEvaluator` carried `max_individuals` as a module constant instead.

*Why the documents win, against the recommendation on offer:* the case for the code was that v1's default makes `capacity_radius` numerically identical to `scout_radius`, so the field buys nothing today. True — but **`spec.md` is the field-level build contract, and a contract that code may silently overrule is not a contract.** The cost of honouring it is two fields that hold predictable values in v1; the cost of not honouring it is that every future reader has to check whether spec.md still describes the thing that shipped. The design-integrity auditor was already reporting this as a defect in exactly those terms.

**2. `tiles_per_individual` — roster.md's decided values win: Human 1, Fox 5, Rabbit 4.** The uniform `12` in `fox.tres`/`rabbit.tres` was never a decision, only the schema's `DEFAULT_TILES_PER_INDIVIDUAL` stub showing through. This is live rather than cosmetic: at 12, Rabbit needs twelve `cover` tiles to reach capacity 1 where the decided value is four, so time-to-first-move-in was being measured against roughly a 3× harder world than the design intends — against a **≤2 min target, 5 min hard ceiling** the acceptance test hangs on.

**3. The resident tap radius is capped nearer one tile, rather than exempting the remove tool from the priority rule.** The radius is `max(44 px, 0.8 × tile-on-screen)`; at street zoom the fraction dominates and makes an animal's hitbox **wider than the tile it stands on** (measured 162.8 px against a 44 px floor). That is the actual defect — the priority rule is fine, its input was wrong. Consequence today: a villager on its House wins the tap on the adjacent field, so the floor's *likeliest* displacement is unreachable while the family is home, intermittently, because residents roam. **Rejected: exempting the remove tool** — narrower and predictable, but it carves a mode-shaped hole in a Pillar 3 invariant to compensate for a sizing bug, and the bug would still mis-target Inspect taps.

**4. Fox and Rabbit's `human_signoff` is backfilled, dated 2026-07-28 and marked as a backfill.** Both shipped through the full pilot-3/3b pipeline with source-verified copy and passing suites; the sign-off happened, the tracker that records it did not exist yet. Recording it as a backfill rather than a fresh review keeps the distinction honest. This clears a standing **Gate-4 failure** in `release-checklist.md` that would have failed an export build.

### D-28 · #31 and #20 (Human) approved
**Decision:** The villager fact card (Open Question #31) and Human's `scout_radius = 8` (the Human-specific half of #20) are approved as written, 2026-07-28. Recorded by the human directly in `content-pipeline-status.md`'s `human_signoff` field.

**#31 — closed outright.** `human.tres`'s `fact_text` is the two-source-corroborated card written earlier the same day (ADW + National Geographic Society Education, after a same-day correction of an over-precise date the second source caught). No further work is expected against this item.

**#20 — closed for Human only.** The general question — per-species suitability radius — stays open: the nine cleared-pool species have no `scout_radius` at all yet, and each will need one at its own step-3 proposal. Only Human's value (8, the tight end of the ~8–12 band) is decided.

**Mechanical consequences applied in the same pass:**
- `content-pipeline-status.md`: `human`'s scan-table glyph and per-item `status` both moved 🚧 → ✅.
- `tier1-status.md` row 6: the `PROPOSED (2026-07-27) — Human scout_radius = 8` marker removed.
- `spec.md`: #31 marked closed; #20 annotated with Human's decided value while remaining open generally.

**Found and flagged, not decided, in the same pass:** `spec.md` #4 still lists Human's asset audit as open, while `content-pipeline-status.md` has recorded `pre_import_audit: done` for `human` since the row 3–6 dispatch. That is a stale cross-reference, not a new ruling — noted on #4's own row for a future reconciliation pass rather than closed here.

### D-29 · Working the remaining human-gate list, rows 2–10

Taken 2026-08-01, ratifying or reversing every proposed constant still open across rows 2–10, plus three real conflicts surfaced along the way. Full per-row detail lives in `tier1-status.md`; this is the summary of what was decided and why.

**Ratified as proposed, no change:** Row 3 (cultivated_field cost 2 Wood, free natural-terrain pricing, world start size 36×36, grace window 12.0s, recycle fraction 0.5); Row 4 (House cost 15 Wood, footprint 1×1); Row 5 (passive Wood rate 1/forest-tile/60s, starting stockpile 50); Row 6 (arrival delay 20–60s, dirty-queue drain budget 4/frame, walk speed 0.6 tiles/s, waypoint pause 2–6s, waypoint-pick radius 3 tiles, global roamer budget 64, preview poll 0.1s); Row 7 (TTS rate 0.9, TTS volume 80, card minimum width 620px); Row 10 (relocation search radius 8 tiles, banner dwell 4.5s, marker fade 1.6s, queued-moments cap 8).

**Reversed:**
1. **Row 3 — world start terrain: `wild_grass`, not `grass`.** The implementer's pick (`grass`, for gdd.md's "open meadow, not empty lot" read) is overridden — the player's starting world should read exactly like freshly-revealed mist land, tag-inert until the player acts on it. **Consequence surfaced, not resolved here:** this puts `wild_grass`'s unresolved look-pass (Open Question #29 — "must read as something to claim without reading as broken") on the very first frame the player sees, not just at the mist's edge. Implementation pending (`WorldGrid.START_TERRAIN_ID`).
2. **Row 7 — Open Question #13 closed: `AUTO_SPEAK = true`.** Fact cards speak the moment they appear; the prior pick (silent, tap to hear) is reversed. A settings-level mute must exist — whether Row 15's single Master Volume slider covers Read-Aloud or it needs its own toggle is not decided and carries forward as that row's open item.
3. **Row 2 — close zoom retuned to 4.0 tiles across (was 7.0).** Human playtest verdict: default zoom, FOV, zoom step, keyboard pan, overview margin, recentre begin, and auto-select-first-palette-entry all read correctly; only the close end felt too far from the animals. 4.0 falls below gdd.md's own stated "~6–8 tiles close" baseline, so that sentence is corrected in the same pass (`gdd.md` → World Structure). Implementation pending (`CameraRig.ZOOM_MIN_TILES`).

**New builds ruled on (nothing existed to ratify):**
4. **Row 9 — Avoids: 5-tile avoid distance, re-pathing piggybacked on Row 6's wander-pause cadence (2–6s).** No baseline existed anywhere; sized relative to the floor pair's already-decided scout/capacity radii (Rabbit 8, Fox 12) and Row 6's wander radius (3), so distance-keeping reads as deliberate without competing with habitat placement itself. Nothing built yet — this closes step 2 only.

**Conflicts resolved:**
5. **Row 6 — the capacity-overshoot edge case: extend the arrival check, don't ship the limitation.** A home site can end up over capacity the instant a neighbouring site's arrival claims tiles the first site was counting on, because the arrival predicate only checks the arriving site's own capacity. **Ruled:** the arrival check must also re-evaluate neighbouring sites, and trigger Gentle Displacement on any neighbour it drops below population. Rejected: shipping it as a known v1 limit — real at the now-realistic divisors (D-27 #2), not a rare edge case. Implementation pending.
6. **Row 6 — the live-preview "getting closer" gap: ship it.** The two-band preview (`wild`/`welcoming`, no band between) was flagged as a decision the dispatch made rather than a ruling. **Ruled:** ship with the gap. gdd.md's own exemplar line ("this spot is getting cozy for someone") won't fire the way the GDD imagines until Row 12's near-miss summary lands, and that's accepted for the floor.
7. **Rows 2 & 10 — the animal-wins-the-tap priority rule becomes mode-aware.** The rule (generous animal hitboxes always win a tap) made the floor's likeliest displacement — clearing the field beside an occupied House — unreachable while the villager stands near it, even after D-27 #3's hitbox-cap fix. **Ruled:** in Terraform/Build mode, the tile action always wins regardless of resident-hitbox overlap; animal-wins-the-tap stays the rule only in Inspect mode. This changes Row 2's own thin form (previously stated to ship uniformly across all three modes) as well as resolving Row 10's reachability conflict. Implementation pending (`tap_router.gd`).

**Mechanical consequences applied in the same pass:**
- `tier1-status.md`: every `PROPOSED` marker above removed and re-marked `DECIDED`/`REVERSED` 2026-08-01, rows 2, 3, 4, 5, 6, 7, 9, 10's `human_gate` fields updated to reflect what's ratified vs. still pending implementation or a human look.
- Row 5's `status` flipped 🚧 → ✅ — nothing else was outstanding for that row.
- Row 8's `human_gate`/`status` **corrected, not re-ruled**: it still read as an open Gate-4 failure for Rabbit/Fox sign-off that D-27 #4 and D-28 had already closed on 2026-07-28. Flipped 🚧 → ✅ to match `content-pipeline-status.md`, the actual record of owner.
- `gdd.md` → World Structure: "~6–8 tiles close" corrected to "~4 tiles close," dated and cross-referenced to this decision.

**Explicitly NOT closed by this pass, and why:**
- **Row 4** cannot flip to ✅ despite its two constants ratifying clean: `content-pipeline-status.md`'s `house` entry flags the variant pick and camera facing as never visually confirmed by a human, and today's camera playtest didn't cover a placed House. Needs a dedicated look.
- **Row 10's presentation half** (`DisplacementNotice`, the actual warning UI) has never been seen by a human — approving its timing constants is not the same as approving how it reads on screen.
- **Row 7** still carries two items this pass didn't touch: nothing has verified a voice actually speaks on a real desktop (undecidable headless), and every species' fact card still shows an empty portrait rectangle.
- **Rows 1, 11, 12, 13, 14** remain unbuilt; nothing to gate.

### D-30 · Row 1 (Start & persist) — five rulings on the save/load build

Taken 2026-08-01, before and during the row 1 implementation, so the build had a decision to
follow rather than a guess.

**1. One data-driven preset; #10 stays deferred to `.tres` authoring.** New Game shows a
single preset card (`WorldPreset` resource, `project/data/presets/meadow_start.tres`), not a
choice among several. Because the preset is data rather than a branch in code, resolving Open
Question **#10** later — the real preset list — is authoring more `.tres` files, not writing
code. "Preset variety" stays exactly what row 1's `tier1-status.md` entry already named it: a
clean depth purchase, bought later without touching the save/load system itself.

**2. The mist trigger ships as a contract, not a stub.** `Autosave` exposes one entry point,
`request(reason)`, over a fixed four-reason vocabulary that already contains `mist_reveal`
alongside `interval`, `move_in`, and `exit_to_menu`. Row 1 proves the contract — every reason
in the vocabulary is asserted to write a file — but does not call `mist_reveal` from anywhere,
because nothing in the shipped game produces that event yet. Row 13 (Mist, unbuilt) adds
exactly one call site when it lands. **Rejected:** waiting to declare the vocabulary until row
13 exists — that would leave row 1 unable to state its own floor today, and would risk a
differently-named reason arriving later that the autosave suite never covered.

**3. The save holds committed state only; in-flight timers are re-derived on load.** Pending
arrivals, open settlement gestures, removal receipts, and the dirty-neighbourhood queue are
deliberately absent from the save format. On load, `WorldRoot` restores terrain, buildings,
Wood, home sites and residents, then attaches `HabitatSimulation` — its own post-edit path
marks every neighbourhood dirty and re-derives whatever arrivals or settlement gestures the
restored state actually calls for, rather than the save file trying to serialize a snapshot of
timers mid-flight. **Why:** a saved timer is either wrong the instant real-world clock time has
passed (an autosave interval or a settlement grace window that already looks stale on load) or
requires reconciling elapsed wall-clock time against game time, which no other row does. Reusing
the event-driven model's own restore path is also what keeps `SettlementWindow`'s "reverting
within the window means it never happened" property true across a reload — no pre-edit state is
recorded anywhere, on disk or in memory.

**4. Naming is never destructive.** A New Game world name that collides with an existing save
auto-suffixes (`wildhaven` → `wildhaven-2`); there is no delete control anywhere in the save UI.
**Why:** the New Game and Load Game screens are kid-facing, and a delete control on a
kid-facing screen is a way to lose a beloved world by mis-tap — the exact failure mode D-02 and
D-10 already rule out for the world's animals. Auto-suffix gets the player into a fresh world
with zero typing required (the same "press *Let's go!* without typing" design goal that gives
`DEFAULT_WORLD_NAME` its value) without ever asking the game to destroy something on the
player's behalf.

**5. The exit control is row 1's own `CanvasLayer`, not an edit to `GameUI.tscn`.** *Leave*
lives in `LeaveOverlay.tscn`, instanced into `Main.tscn` beside `GameUI`, rather than as a new
button inside the UI row's own scene. **Why:** it keeps the directory claims disjoint —
`project/scripts/ui/` stays row 2/7/11/12/15's alone, and row 1's menu-flow work stays inside
`project/scripts/menu/` + `project/scenes/menu/`. The cost is one extra `CanvasLayer` and one
extra instance line in `Main.tscn`; row 15 can later fold *Leave* into the shared Settings
overlay by deleting that one line, which is cheaper than un-sharing a scene two rows had grown
to depend on.

### D-31 · Row 1 review rulings — the arrival queue is saved; every world gets a real seed

Taken 2026-08-02, on two defects the whole-branch review of the row 1 build found and left for
a human because both are design calls rather than patches. They ship together as one
`save_version` bump, 1 → 2.

**1. Pending arrivals are persisted. This PARTIALLY REVERSES D-30 ruling 3.** The save file now
carries the arrival queue. Everything else ruling 3 named — open settlement gestures, removal
receipts, the dirty-neighbourhood queue, Wood's fractional accumulator — is still deliberately
absent and still re-derived on load. **Why the reversal:** ruling 3 reasoned that an arrival is
enqueued when a neighbourhood is marked dirty, so `WorldSnapshot.apply()`'s closing
`mark_all_dirty()` would re-derive the queue through the simulation's own event-driven path.
It provably does not. `mark_all_dirty()` reaches `_mark_all_sites_dirty()`, which enqueues only
home sites that ALREADY EXIST — and a habitat that qualifies but has nobody living in it yet
has no home site to enqueue. Reproduced under the real load path: capacity 1, sites 0, capture,
apply → 0 residents after 600 simulated seconds, and 1 only after some further player edit. In
the child's terms: paint a rabbit meadow, quit inside the 20–60 s arrival delay, and the rabbit
never comes. What stops the restore from double-enqueueing is `ArrivalQueue.enqueue()`'s
`has_pending()` no-op, and that guarantee is **order-independent** — corrected 2026-08-02 after a
review measured it. `apply()` restores the queue before `mark_all_dirty()`, but the ordering is
not load-bearing: `mark_all_dirty()` enqueues **zero** arrivals synchronously, since it only marks
neighbourhoods dirty and the enqueue happens in a later `tick()` drain, by which point `restore()`
has run under either ordering. Swapping the two steps left both suites green (158/158, 70/70). The
order stands for readability. **Rejected:** saving the dirty queue too — it drains at 4 evaluations/frame
(~240/s) against a child's tap rate of a few per second, so no real backlog accumulates, and
anything that was dirty has already been evaluated into either an arrival (now saved) or
nothing. That would be schema for no behaviour.

**2. `world_seed` is drawn at New Game time, and a v1 file's seed is derived from its name.**
The v1 build wrote a constant `0` into every save, justified as "a seed absent from the first
shipped files could not be recovered" — but a constant 0 in every file is exactly as
unrecoverable as absent. The seed is now drawn once, in `new_game_screen.gd`, at the instant a
player creates a world, and carried through `GameSession`. **Explicitly not in
`WorldRoot._ready()`**: that path also runs for every headless suite and for the `"none"`
intent, so a random draw there would make world construction non-deterministic across the whole
test suite. `_migrate()`'s v1 → v2 step gives an old world a seed derived deterministically
from its **name** — stable (the same file always migrates to the same value, so its mist does
not reshuffle every time it is opened) and distinct (two differently-named worlds do not
collide). A generated or migrated seed is never `0`, because `0` is already a sentinel
elsewhere: `ArrivalQueue._init()` reads it as "randomize", and the `"none"`/editor path keeps
it as "no seed chosen". Row 13's mist reveal is specified as a deterministic function of
`(world_seed, x, y)`, which is what makes this worth fixing before any world ships.

### D-32 · A settlement gesture is RE-ARMED on load, not persisted

Taken 2026-08-02, on the third defect the whole-branch review of the row 1 build left for a
human (C-3). Like D-31 it is a design call rather than a patch, and unlike D-31 it adds no
schema and no `save_version` bump.

**The defect.** `GentleDisplacement`'s 12 s grace window gates the *irreversible* half of a
displacement — the warning's final trigger, and any relocation or departure. Only two paths ever
open a gesture, `on_edit()` and `on_arrival()`, and **a restore reaches neither**.
`WorldSnapshot.apply()` closed at `mark_all_dirty()`, which re-derives capacity arithmetic and
enqueues arrivals but opens no window. So a gesture that was open when the file was written was
silently *cancelled* by the reload, and the home sat **permanently over capacity** — until some
unrelated later edit near it happened to re-arm a window, at which point the displacement finally
fired with no context for the child. Reproduced by the reviewer through the ordinary
`exit_to_menu` path: villager in a House, clear the field beside it → capacity 0, population 1,
one pending gesture; capture, apply into a fresh world → zero gestures, and population still 1
against capacity 0 after 200 simulated seconds. That is row 10's pillar invariant — "nothing
blinks out unexplained; any loss is the warned, reversible result of the player's own settled
choice" — broken across a reload.

**The ruling: re-arm at load from world state (Option A).** `WorldSnapshot.apply()` now ends with
`GentleDisplacement.reconcile_after_load()`, which walks the existing home sites and opens a fresh
gesture for any whose population exceeds its capacity, through `SettlementWindow.touch()` — the
same mechanism `on_edit()` and `on_arrival()` use, not a parallel path. Three reasons it beats
persisting the gesture:

1. **No schema.** Nothing about the pre-edit world is recorded anywhere, which is exactly what
   makes `SettlementWindow`'s revert rule ("reverting within the window means the displacement
   never happened") a property of the arithmetic rather than a claim — and it stays true across a
   reload instead of becoming a thing the file has to get right.
2. **It self-heals a home that is over capacity at the moment of the load, from any cause** — not
   only from the gesture that happened to be open at capture. *Corrected 2026-08-02:* this was
   first written as also covering "a restored arrival that lands after the reload". It cannot, and
   does not need to: `reconcile_after_load()` runs once, at load, before any arrival lands. That
   case is handled by `WorldRoot`'s `resident_arrived` → `GentleDisplacement.on_arrival()` wiring,
   which pre-dates D-32 and is untouched by it. The behaviour was always right; the attribution
   was not.
3. **It restores what the design document already described.** The restore-order diagram in
   `2026-08-01-start-and-persist-design.md` has read "any home over capacity opens a fresh
   settlement gesture" all along. The code simply never implemented it; this makes the code match
   the document.

**Rejected: persisting `gestures`.** It would put the 12 s countdown, its merged tile set and its
neighbourhood keys into the file — in-flight state of exactly the kind D-30 ruling 3 keeps out —
and it would still heal only the one gesture that was open, leaving every other route to an
over-capacity home unhandled.

**The child gets a fresh 12 seconds**, which the design document already calls "strictly more
forgiving than never having quit".

**The zero this must not cost, and does not.** gdd.md → Performance and `SettlementWindow`'s own
header rest on "a world with no residents never opens a settlement window in its life", and a
settlement timer must not create idle work. A healthy world therefore arms **nothing** on load —
asserted in `test_save_round_trip.gd` for a restored world that genuinely holds a settled
resident, not only for an empty one. Measured: `reconcile_after_load()` moves
`HabitatSimulation.evaluations_run` by **0**, because it reads `CapacityEvaluator` directly and
enqueues no habitat evaluation. The walk is one capacity read per **existing home site** — single
digits in a real world — deliberately not the full-world candidate sweep (tiles × roster) that
was measured at ~1.6 s.

### D-33 · First-person walk camera replaces the fixed-pitch pan/zoom camera (reverses D-13)
**Decision (2026-08-03):** The shipped v1 camera becomes a true first-person walk camera —
free mouse-look (yaw + pitch), WASD ground-level walking at eye height, no top-down view as
the default state. This reverses D-13's "one seamless world, one camera, no modes" outright:
D-13 named the Minecraft-style inside-the-world camera as the option being *traded away* for
safety, performance, and orientation; this decision takes that trade back.

**Why now:** real tree models (taller than the grey-box placeholders they replaced) block
sightlines to tiles behind them at the old fixed 45° pitch — the problem a same-day
occlusion-fade spike (rejected on sight) and a low-angle-pitch spike (Spike A, built as a
comparison point) were both built to investigate. A first-person spike (Spike B) was built
alongside them; the human's own children, experienced Minecraft players, read as capable of
handling first-person's added complexity, and playing Spike B settled it in first-person's
favor over both alternatives.

**What this costs, named rather than hidden — D-13's own three safety rails no longer apply:**
1. **No rotation → free rotation.** "North always north" is gone; a first-person player can
   face any direction and lose their bearing the way D-13 was written to prevent.
2. **Pan clamped to revealed world → free walking.** There is no clamp preventing the player
   from walking toward the mist edge (see D-14 — nothing exists past it; a first-person
   controller needs its own stop condition at the revealed boundary, which did not need to
   exist under the old pan clamp).
3. **Full zoom-out always frames everything, Home one press away → no equivalent yet.** This
   is the rail with no first-person analog by default, and shipping first-person without
   replacing it would reintroduce the exact "got lost in my own world" failure D-13's rails
   were built to prevent.

**Proposed replacement for rail 3, first pass — human to confirm, not yet built:** repurpose
the OLD camera's rail-2 machinery (`CameraRig._overview_distance()`'s frustum-verified
"frames the whole world from the centre" search — real, tested code, not thrown away) as a
**Home-key map peek**: hold Home to cut to that exact overhead framing for as long as it's
held, release to return to first-person exactly where the player was standing and facing.
This gives back a "see everything, one key away" panic button without living in the top-down
view full time. The same repurposed camera doubles as the **save-thumbnail capture** (gdd.md
→ Saves already specs "a full zoom-out screenshot," which a first-person session never
visits naturally) — at save time, a hidden camera snaps to the overview framing, captures one
frame, and snaps back, invisible to the player. Both uses are the same already-verified
frustum search; nothing about rail 2's guarantee needs re-deriving; it changes from something
the play camera does continuously to something a second camera does on demand.

**Targeting changes too, not just the camera.** The old model's single left-click read the
real mouse-cursor position; first-person hides and captures the cursor for mouse-look, so
tapping a tile or a resident becomes **look-and-press**: aim a screen-centre crosshair at the
target and press the tap action, no cursor position involved. The mouse pointer is freed only
for literal HUD/palette clicks (choosing which terrain or building to place), via a dedicated
toggle — not for the gameplay tap itself. `TerrainView.screen_to_grid()` and
`ResidentPicker.pick()` already read `get_viewport().get_camera_3d()` generically rather than
hardcoding the old camera, so a screen-centre point raycasts correctly through whichever
camera is active with no change to either function.

**New gap this opens, not present under the old camera:** first-person walking needs real
collision against trees, rocks, buildings, and water. None exists today — confirmed nothing
beyond one whole-tile raycast-picking `StaticBody3D` per tile, with zero collision on any
prop mesh. Walking through a tree was an accepted, disclosed gap in the throwaway spike; it
is not acceptable in the shipped camera. First pass: block movement using the existing
per-tile colliders (whole tile impassable, not per-mesh precision) rather than authoring new
per-model collision shapes — a coarser but much cheaper starting point, flagged for the human
to refine.

**Superseded by this decision:** D-29's row-2 camera constants (`ZOOM_MIN_TILES`,
`ZOOM_DEFAULT_TILES`, `ZOOM_STEP`, `KEY_PAN_TILES_PER_SECOND`, `OVERVIEW_MARGIN`,
`RECENTRE_BEGIN`, camera FOV) — all describe the pan/zoom camera's feel, and none apply to a
first-person controller. `tier1-status.md` row 2's 2026-08-02 full human gate closed the OLD
camera; the row reopens against this decision rather than staying closed.

### D-34 · Row 11 (Species status) — six rulings on the HUD/Field Guide build

Taken 2026-08-08, closing the human-gate items ui-engineer's thin build surfaced.

**1. All four counters stay persistent on the HUD.** Wood, Species Hosted, Currently
Resident, and Village Population all render in the top-left corner at all times, in both
first-person and map-peek view, as built. **spec.md's Screen Layouts sketch is corrected to
match** — it previously drew only Wood in that corner, predating this row.

**2. "Currently Resident" counts distinct species, not individual headcount.** Ratifies the
build's own read (`resident_species_ids().size()`), taken from a doc comment `HomeSiteRegistry`
already carried. The counter answers "how many kinds of animal are home right now," not "how
many individuals."

**3. Village Population's hardcoded `"human"` species id is accepted, not schematized.**
Matches existing precedent (`displacement_copy.gd`'s `FLOOR_SPECIES_IDS`); a dedicated
`AnimalDefinition.is_villager` flag is not worth adding against a value that essentially never
changes. Revisit only if the villager species id is ever actually renamed.

**4. `UiPalette.FONT_HUD_SECONDARY = 22` ratified as proposed.**

**5. The empty Field Guide state's copy is approved as written:** *"Nothing here yet — keep
exploring the world."* Low-stakes enough not to need a content-writer pass; the `[COPY]`
marker is cleared.

**6. Species Hosted stays a bare running count, no denominator.** Confirms the build's own
reading of Pillar 1's ban as forbidding the ratio ("N of the total that exist"), not the tally
itself — the Economy section already names Species Hosted as one of the four legitimate
counters.

**Mechanical consequences applied in the same pass:** `tier1-status.md` row 11's `human_gate`
recorded as full sign-off; `status` flipped 🚧 → ✅. `spec.md`'s Screen Layouts sketch updated
to show all four stacked counters.

### D-35 · Row 1 (Start & persist) — five constants ruled, all as proposed

Taken 2026-08-09, closing every `PROPOSED (2026-08-01)` constant this row was carrying.

**1. `Autosave.INTERVAL_SECONDS = 90.0`** — approved as proposed. Midpoint of spec.md → Pacing
Constants' "~1–2 min" band, consistent with the same midpoint-of-a-stated-band move already
ruled for row 2's `ZOOM_DEFAULT_TILES` and row 10's `GRACE_WINDOW_SECONDS` (both D-29).

**2. `WorldSnapshot.SAVE_VERSION = 1`** — approved as proposed. The only sensible value for a
first save format.

**3. Preset `display_name = "Meadow Start"`** — approved as proposed. Matches gdd.md's
`"[Terrain] Start"` preset-naming convention.

**4. `DEFAULT_WORLD_NAME = "Wildhaven"`** — approved as proposed. Matches the game's own
title; pre-filled so a kid can press *Let's go!* without typing.

**5. `MIN_SAVED_WORLD_TILES / MAX_SAVED_WORLD_TILES = 1 / 128`** — approved as proposed. 128 is
gdd.md → World Structure's own "hard cap of ~128×128," also spec.md Open Question #18; 1 is the
obvious floor. **Rules the identical number for row 13's world cap in the same pass (D-38)** so
the two never drift apart.

**Mechanical consequence applied in the same pass:** `tier1-status.md` row 1's `constants`
field markers changed `PROPOSED (2026-08-01)` → `DECIDED 2026-08-09 (→ D-35)` for all five.
This closes step 2 (constants) only — row 1's `human_gate` still carries its own open items
(`LeaveOverlay` unwalked, the displacement-pending-across-reload check, the `_ever_hosted`
pollution defect) and is untouched by this decision.

### D-36 · Row 2 (Camera & modes) — first-person rebuild constants ruled, impassable-terrain mechanism decided

Taken 2026-08-09, closing every `PROPOSED (2026-08-03)` constant D-33's first-person rebuild
was carrying.

**1. `CameraRig.EYE_HEIGHT = 0.9`** — approved as proposed.

**2. `CameraRig.MOVE_UNITS_PER_SECOND = 4.0`** — approved as proposed. No GDD precedent; a
judgment call, ratified as-is.

**3. `CameraRig.MOUSE_SENSITIVITY_DEG = 0.15`** — approved as proposed. A feel number, ratified
as-is.

**4. `CameraRig.PITCH_LIMIT_DEGREES = 80.0`** — approved as proposed. Matches D-33's own spike
brief ("something sane, e.g. ±80").

**5. `CameraRig.BODY_CAPSULE_RADIUS = 0.3` / `BODY_CAPSULE_HEIGHT = 0.8`** — approved as
proposed.

**6. `TerrainView.IMPASSABLE_TERRAIN_IDS` mechanism — stays a hardcoded id list in view code.**
The alternative (a `TerrainDefinition.blocks_movement` field, the shape D-27 #1 used for
`max_individuals`/`capacity_radius`) is rejected for now — the hardcoded list ships fastest and
the values themselves (`forest`, `rock`, `water`) are already D-33's stated scope. Revisit only
if more impassable terrain types are added and the list starts feeling like it should move with
the data.

**7. `TerrainView.MOVEMENT_BLOCK_HEIGHT = 2.5`** — approved as proposed.

**8. `ThumbnailViewport` size `(480, 270)`** — approved as proposed.

**Mechanical consequence applied in the same pass:** `tier1-status.md` row 2's `constants`
block markers changed `PROPOSED (2026-08-03)` → `DECIDED 2026-08-09 (→ D-36)`, and the
`IMPASSABLE_TERRAIN_IDS` mechanism note ("flagged for the human") replaced with this ruling.
Row 2's `human_gate` is untouched — it still needs a build and a human playtest against the new
camera before it can re-close.

### D-37 · Row 12 (Pointers) — nudge delay and News Report cadence ruled

Taken 2026-08-09, closing both constants this row was carrying as "not started."

**1. Nudge trigger delay = ~3 s.** Transcribes gdd.md's First 60 Seconds beat 2 verbatim
("~0:03 — the first News Report fires").

**2. News Report cadence = 90–150 s, randomised.** No GDD or spec.md precedent exists for this
number — flagged as a pure judgment call by the triage, and picked here rather than left open.
Chosen deliberately at a different scale than the two nearest cadence-shaped constants in the
project (row 6's 2–6 s wander pause, a presentation tick, and row 1's 90 s autosave, an invisible
background write) — neither fits a narrative-hint rhythm. The band sits above the nudge's own
~3 s opener so the pool reads as occasional across a typical play session (a handful of reports
in 10–15 minutes) without the fixed-interval feel a single number would give; randomised for the
same reason row 6's arrival delay and wander pause are randomised — so reports don't fall into a
noticeable lockstep.

**Mechanical consequence applied in the same pass:** `tier1-status.md` row 12's `constants`
field changed from "not started" to `DECIDED 2026-08-09 (→ D-37)` naming both values. This
closes step 2 (constants) only — implementation (`project/scripts/ui/`) has not started.

### D-38 · Row 13 (Mist) — reveal proximity, band depth, and world cap ruled

Taken 2026-08-09, closing all three constants this row was carrying as "not started."

**1. Reveal proximity = 2 tiles.** Stated directly in gdd.md → World Structure ("build or
terraform within ~2 tiles of the mist") and independently in spec.md Open Question #19.

**2. Reveal band depth = 2 tiles.** gdd.md only said "a few tiles deeper" with no baseline;
spec.md #19 left it fully open. Set equal to the reveal proximity value rather than a separate
number — one band-width constant to reason about instead of two.

**3. World cap = 128×128.** Stated repeatedly in gdd.md and spec.md Open Question #18. **The
identical number row 1's `MAX_SAVED_WORLD_TILES` rules in the same pass (D-35)** — decided
together so the two constants cannot drift apart.

**Mechanical consequence applied in the same pass:** `tier1-status.md` row 13's `constants`
field changed from "not started" to `DECIDED 2026-08-09 (→ D-38)` naming all three values. This
closes step 2 (constants) only — implementation (`project/scripts/world/`) has not started.

### D-39 · Row 1 (Start & persist) — two full-gate rulings, closing the row

Taken 2026-08-09, at the same real-build playtest that closed row 1's `LeaveOverlay` and
across-reload-displacement checklist items.

**1. The rabbit's `tiles_per_individual = 4` (D-27 #2) stands unchanged — no revisit.** The
2026-08-02 playtest surfaced that this makes the rabbit ~4× harder to attract than the
villager (8 tiles of cover needed vs. the villager's 2), a real risk to gdd.md's ≤2-minute
time-to-first-move-in target. Having now played a real build against it, the human's ruling is
to leave the number as D-27 #2 set it — the qualitative hover preview (row 6) is judged
sufficient to carry a player through the wait.

**2. The `_ever_hosted` save-corruption defect is triaged and ruled non-blocking, deferred
past Tier 1.** `HomeSiteRegistry.restore_site()` writes a loaded save's species into
`_ever_hosted` before `HabitatSimulation.restore_site()` validates that species exists, so a
corrupt or hand-edited save naming a nonexistent species permanently pollutes the Species
Hosted counter. Real, but reachable only via a corrupt or hand-edited file, never normal play —
judged too low-severity to hold up Tier 1's close. Fixed whenever row 1 gets its next pass,
not before.

**Mechanical consequence applied in the same pass:** `tier1-status.md` row 1's `human_gate`
recorded as a full gate, superseding the 2026-08-02 partial gate; `status` flipped 🚧 → ✅.

### D-40 · The Field Guide shows the whole roster — a narrow, existence-only exception to D-34 #6 and gdd.md's "no total-species count" (amends D-34 #5, #6)

Taken 2026-08-10, during a playability pass raised directly by the human (not surfaced by a
dispatch brief): the Field Guide showed nothing for a species the player had never attracted,
so a player could spend real effort building what they believed was the perfect habitat for an
animal that could never appear, with no way to tell those two situations apart. The fix chosen
is Approach 3 of three considered in that conversation: show that a species *exists* (an icon
row, silhouetted until discovered) without ever revealing what it *needs* — discovery stays
real, but nothing is solvable off a spec sheet.

**This amends, rather than merely narrows, two prior rulings:**

- **D-34 #6** ("Species Hosted stays a bare running count, no denominator") is unchanged for
  the *counter* itself, but the Field Guide's row list — which D-34 #6's own reasoning treated
  as the thing the ban protected — now renders one row per roster species, discovered or not.
  Counting the rows supplies exactly the denominator D-34 #6 declined to put in the counter.
  The human's ruling, this session, is that the tradeoff is worth it: **existence-only** is
  judged a materially different disclosure than a completion percentage or a "finish the guide"
  reward (gdd.md's actual three bans), specifically because no *preference* data ever leaks —
  a player still cannot solve a habitat by reading the guide, only avoid wasting effort on an
  animal that was never in the roster to begin with.
- **D-34 #5** ("the empty Field Guide state's copy is approved as written... the `[COPY]`
  marker is cleared") is retired, not merely superseded. That approved string ("Nothing here
  yet — keep exploring the world.") described a *player-has-done-nothing-yet* state, which no
  longer exists now that every roster species always renders a row (silhouetted at minimum).
  The empty state is now reachable only if the roster itself fails to load — a data/config
  failure, not a normal moment of play — and needs its own content-writer pass; the `[COPY]`
  marker is deliberately re-opened (`FieldGuide.EMPTY_STATE_TEXT`) rather than carrying the
  old, now-inapplicable approved copy forward.

**The exception is scoped narrowly and structurally, not by convention alone.** A row renders
either a species' `display_name` (once hosted, permanently — `WorldRoot.species_hosted_ids()`)
or a fixed glyph, `"???"` (before that); no habitat tag, terrain preference, or hint of any
kind is rendered anywhere by this change, and a headless check (`test_field_guide.gd`) asserts
no row's text can ever contain a value from `AnimalDefinition.HABITAT_TAGS`. The list stays
flat and in roster order — never ranked, never sorted by discovered-status — so the "indicator
test" invariant D-34 and every prior Field Guide ruling already held keeps holding for
everything this decision does not touch.

**`gdd.md` -> Objectives & Progression's "No completion percentage, total-species count, or
finish-the-guide reward" sentence is corrected in the same pass** to point here, rather than
reading as still-absolute — the ban itself is unchanged; this is the one named, deliberate
exception to it, not a quiet erosion of it. Any future change that reveals more than existence
(a count of *how close* a habitat is, a hint stronger than News Reports already plan to give)
is a new decision, not an extension of this one.

### D-41 · Iso camera + selective occlusion fade replaces the first-person walk camera (reverses D-33)

**Decision (2026-08-14):** The camera becomes a fixed orthographic camera at
`yaw = 45°`, `pitch ≈ -26.565°` (`IsoCameraFraming.YAW_DEGREES`/`PITCH_DEGREES`) —
matching the original 2D mockups' isometric convention — replacing D-33's
first-person walker outright. Movement reverts to D-13's model: right-drag,
WASD/arrows, and wheel pan/zoom the camera; nothing walks. The occlusion problem
D-33 was built to solve (real tree models blocking sightlines at D-13's old 45°
pitch) is addressed directly by a bounded, per-resident selective transparency
fade (`OcclusionFader`), not by camera angle.

**Why now, and why this is not another blind guess.** The human's own build
history had tried three real designs — D-13's fixed-pitch diorama, D-33's
first-person walker, and the project's original 2D cartoon mockups
(`archive/images/mockups/`) — and found the first two each wanting on a
different axis (diorama: trees hid things; first-person: "just feels wrong,
boring, hard to maneuver," the human's own words). This attempt is grounded in
measurement, not preference alone:

- The mockup generator's own tile-diamond ratio (`TILE_W=96`/`TILE_H=48`, an
  exact 2:1 — the standard pixel-art isometric convention) derives the exact
  yaw/pitch above; it is not a guessed "steeper angle" — an early spike at
  steep pitch (-60°/-70°, no yaw) was tried first, read as too top-down and
  too zoomed out, and was corrected once the 2:1 ratio's actual implication
  (shallow pitch **plus** 45° yaw, not steep pitch alone) was derived from the
  generator's own math.
- **Camera angle alone does not fix occlusion — measured, not assumed.** A
  headless AABB-ray probe against real instantiated tree geometry, restricted
  to the ring of tiles actually adjacent to a forest block (where residents
  qualify from, per their `scout_radius` — not the canopy interior), found:
  original unsquashed canopy under the old D-13 pitch ≈ 11% of the ring
  occluded; a squashed canopy under that same old pitch ≈ 6%; the same
  squashed canopy under the new iso angle ≈ 12% — back up near the original
  problem. The canopy squash was doing the real work; the shallower pitch
  gave most of it back. This is why occlusion is solved separately, not by
  the angle chosen here.
- **Selective per-object transparency fade is proven prior art, not a house
  invention.** Stardew Valley ships almost exactly this by default (the
  specific occluding sprite fades to alpha 0.4, restored the instant it stops
  blocking) — validated by web research before building `OcclusionFader`, and
  a flicker-hysteresis guard was added specifically because a Don't Starve
  Together developer's own account of this exact failure mode (a wobbling
  detection boundary causing visible flutter) was found in the same research
  pass.

**Supersedes:** D-33's and D-36's first-person-specific decisions in full —
mouse-look, WASD ground movement, look-and-press crosshair targeting (screen
centre, not the real cursor), the bounded `MAX_INTERACTION_RANGE` "walk
closer" gate on every tap, the merged Tab pointer-capture/menu-open gesture,
per-tile movement collision (`MOVEMENT_BLOCKING_COLLISION_LAYER`,
`IMPASSABLE_TERRAIN_IDS`, the boundary walls), and the `OverviewCameraRig`
map-peek swap-camera. `TapRouter`/`ResidentPicker`/`WorldRoot`'s public API
needed **no changes at all** to support the reverted camera — both were
already written against `get_viewport().get_camera_3d()` generically, from
D-33's own original work.

**Reaffirmed, not reversed:** D-13's original safety-rail *invariants* — pan
clamped to the revealed world, full zoom-out always frames everything, Home
one press away — all still hold, re-derived (not ported) for the yawed
orthographic geometry, since a diagonal heading's screen-space silhouette is a
diamond, not an axis-aligned rectangle. Orthographic framing turned out to
*simplify* rail 2: `IsoCameraFraming.size_to_frame()` is a closed-form
projection, not the old perspective camera's 24-step frustum binary search.

**What changed in the zoom continuum:** `ZOOM_MIN_TILES = 4.0`,
`ZOOM_DEFAULT_TILES = 14.0`, `ZOOM_STEP = 1.15`,
`KEY_PAN_TILES_PER_SECOND = 16.0`, `OVERVIEW_MARGIN = 1.06`,
`RECENTRE_BEGIN = 0.60` are all carried over unchanged as the *starting point*
from D-29's already-playtested values, not re-derived from nothing — but they
are explicitly **not re-validated** under orthographic projection (a different
zoom mechanic — frustum `size`, not distance+FOV) and are flagged for a real
playtest, the same way D-29's own values were once playtest-tuned rather than
assumed.

**What is genuinely new, not carried over:** `OcclusionFader`
(`project/scripts/world/occlusion_fader.gd`) — bounded by a fixed radius
around each real resident (`RESIDENT_CHECK_RADIUS_TILES = 3`), never a
whole-world scan, matching this project's event-driven/bounded-cost
philosophy elsewhere (the dirty-neighbourhood queue). `fade_alpha = 0.9`
(90% opaque) is the human's own stated starting point, explicitly flagged as
needing further tuning, not a settled number.

**Still open, not decided here — the human's calls, not this decision's:**

- Final zoom-range constants under orthographic (re-tuned from a real
  playtest, not assumed transfer from the old perspective values).
- Occlusion-fade scope: forest-only vs. also rocks/buildings; residents-only
  vs. also the player's current tap target. `fade_alpha`/hysteresis-frame
  final tuning.
- The tree-canopy render bug: two independent scale-based fixes (a
  non-uniform Y-only squash, then a uniform full-axis scale-down) both
  rendered as a broken, muddy reddish-brown mess instead of clean green,
  for a reason not yet root-caused (pixel inspection of the leaf texture
  ruled out the obvious "alpha-cutout mipmap bleed toward a hidden fill
  colour" theory — the hidden colour is dark olive-green, not brown).
  Recommended path: tech-art sources a genuinely shorter tree asset instead
  of continuing to scale-hack one that wasn't built for it, per art.md's own
  standing sourcing philosophy.

Full design: `docs/superpowers/specs/2026-08-14-iso-camera-occlusion-fade-design.md`.
Full implementation plan: `docs/superpowers/plans/2026-08-14-iso-camera-occlusion-fade.md`.

**Mechanical consequence applied in the same pass:** `tier1-status.md` row 2
reopened against this decision, the same pattern D-33 itself used against row
2 when it landed — see that row's own note for the full account.

**Mechanical consequences applied in the same pass:** `gdd.md`'s Field Guide bullet gains an
inline pointer to D-40. `tier1-status.md` row 11's `human_gate` and `status` cells gain a note
that this decision amends the 2026-08-08 D-34 gate on the two points above; row 11 is not
reopened to 🚧 over it — the counters and the resident-state mechanics D-34 gated remain fully
built and unchanged, only the Field Guide's row-list behavior and one piece of its copy moved.

### D-42 · `TerrainDefinition.model_scene` becomes `model_scenes` — per-tile visual variants, no new save-state

**Decision:** `TerrainDefinition`'s single `model_scene: PackedScene` field is replaced by
`model_scenes: Array[PackedScene]`, and a new method, `pick_variant(x: int, z: int) ->
PackedScene`, picks which entry a given tile shows. With zero entries it returns `null`
(same failure shape the old unset field had); with exactly one entry it returns that entry
directly, no hashing; with more than one it hashes `"%d_%d_%s" % [x, z, id]` through
Godot's `hash()` builtin and takes it modulo `model_scenes.size()`. `TerrainView`'s
`_refresh_tile_visual()` calls this instead of reading the old field directly.

**Why:** this is prerequisite plumbing for an upcoming tech-art look pass that intends to
source real multi-variant assets per terrain (several rock meshes, several tree species,
…). The requirement stated going in was that the SAME tile always show the SAME variant
across reloads, while different tiles of the same terrain are free to land on different
variants — and that this hold with **no new save-data field**. Hashing tile coordinates
plus the terrain's own `id` satisfies both: it is a pure function of data the save file
already has (grid position + which terrain occupies it), so it is reproducible on every
load without persisting a per-tile choice anywhere. A terrain repainted to something else
and back is explicitly allowed to land on a different variant than before — that is a
side effect of the tile no longer being the same "terrain instance," not a bug.

**Scope, explicitly:** `AnimalDefinition.model_scene` and `PlaceableDefinition.model_scene`
are unrelated fields on unrelated schemas that happen to share a name — neither was
touched. `HarvestableTileDefinition` still has no `model_scene` field of its own (→ D-26)
and this decision does not reopen that.

**Migration:** all six v1 `.tres` terrain entries (`grass`, `water`, `forest`, `rock`,
`cultivated_field`, `wild_grass`) moved from `model_scene = ExtResource(...)` to
`model_scenes = Array[PackedScene]([ExtResource(...)])` — a single-element array each,
since no multi-variant asset exists yet. `validate()` now requires `model_scenes` be
non-empty and rejects any null entry, in place of the old null check. `spec.md`'s
`TerrainDefinition` schema row and the relevant tests (`test_terrain_schema.gd`,
`test_harvestable_schema.gd`) were updated in the same pass.

**Flagged for human sign-off**, consistent with how D-25/D-26 were handled: this is a
schema shape change, not a tuning value, so it was implemented directly rather than
proposed-and-parked, but the human should still review the hashing scheme and the
array-of-one migration before a tech-art pass builds on top of it.

### D-43 · Cleared-pool step 3 ruled — habitat needs, personality, avoids, farm-tolerance for all nine

**Decision:** the nine cleared-pool species (Deer, Stag, Horse, Donkey, Cow, Bull, Alpaca,
Husky, Shiba Inu) each get a ruled `habitat_needs` / `personality` / `avoids` /
`farm_tolerant` / `scout_radius` / `tiles_per_individual` / `max_individuals` set, closing
step 3 (design proposal → human decision) for the whole pool at once. Values recorded in
[roster.md](game-design/roster.md) → Already-Defined Roster table; `capacity_radius` is the
`CAPACITY_RADIUS_FOLLOWS_SCOUT` sentinel throughout, matching Fox/Rabbit/Human.

| Animal | Habitat needs | Personality | Avoids | Farm-tolerant | `scout_radius` | `tiles_per_individual` | `max_individuals` |
|---|---|---|---|---|---|---|---|
| Deer | open_grass, forest | Shy | — | No | 10 | 6 | 6 |
| Stag | forest, cover, rocks | Shy | — | No | 12 | 8 | 3 |
| Horse | open_grass, cultivated | Bold | — | Yes | 8 | 5 | 6 |
| Donkey | cultivated, rocks | Bold | — | Yes | 8 | 4 | 6 |
| Cow | cultivated, open_grass | Bold | — | Yes | 8 | 5 | 6 |
| Bull | cultivated, open_grass | Bold | — | Yes | 8 | 6 | 6 |
| Alpaca | open_grass, cultivated | Bold | — | Yes | 8 | 3 | 6 |
| Husky | house, open_grass | Bold | Shiba Inu | Yes | 8 | 2 | 6 |
| Shiba Inu | house, open_grass | Shy | Husky | Yes | 8 | 2 | 6 |

**Why, per species:**
- **Deer** — white-tailed deer (ADW *Odocoileus virginianus*, the same species pin
  `cleared-pool-fact-cards.md` already committed to for its fact card): a forest-edge
  grazer of open ground, matching art.md's suggested axes. Wild, not farm-tolerant.
- **Stag** — red deer (ADW *Cervus elaphus*, same pin as its fact card). Three tags
  (forest + cover + rocks) deliberately mirror Fox's "hardest habitat" framing one tag
  harder. `max_individuals = 3` (half the roster's ~6 baseline) plus the pool's highest
  `tiles_per_individual` makes art.md's "rare trophy" framing literal through capacity —
  the same rarity job Fox's `Shy` personality does through visibility, applied here through
  scarcity instead.
- **Horse / Donkey** — art.md proposed identical axes for both; ruled apart on real
  ecology instead: donkeys are the more arid/rough-terrain-tolerant of the two (ADW
  *Equus asinus* — desert/mountain origin, sure-footed), so Donkey trades `open_grass` for
  `rocks` and gets a smaller `tiles_per_individual` (4 vs. Horse's 5) as the lower-upkeep
  animal.
- **Cow / Bull** — same real species (*Bos taurus*), so identical habitat axes by design;
  no ecological basis to split them, and they already share a base mesh
  (content-pipeline-status.md's flagged shared-mesh risk). The only distinction ruled in is
  `tiles_per_individual` (5 vs. 6 — a bull kept singly needs more room than a cow in a
  herd). **Explicitly acknowledged as thin** rather than treated as settled: Cow and Bull
  now differ by one number only. Ruled to keep both as separate roster spots anyway,
  consistent with the 2026-07-26 call already on record in content-pipeline-status.md to
  keep them separate despite the shared mesh.
- **Alpaca** — art.md's single-tag axis (`open_grass`) would have violated roster.md's own
  "≥ 2 tags" mix rule, so `cultivated` was added — alpacas are commonly kept alongside
  crops/pasture. Lowest `tiles_per_individual` in the pool (3): ADW notes alpacas are
  efficient grazers with padded feet, gentler on pasture per animal than cattle or horses.
- **Husky / Shiba Inu** — ruled in as row 9's second Avoids pair, the candidate art.md and
  roster.md already named. Mutual, symmetric `avoids`; both domestic dogs, so the
  structural predation-graph check stays clean the same way it does for Rabbit ↔ Fox.
  Personality split — Husky `Bold`, Shiba Inu `Shy` — matches each breed's documented real
  temperament (huskies outgoing/pack-social, Shiba Inu independent/reserved) and gives this
  second pair its own visibility hook, the same job Fox's `Shy` does for the first pair.

**Not ruled on here:** a third avoids relationship (the copy-level graph check in
`cleared-pool-fact-cards.md` already found no other real predator/prey dyad in this pool,
and this decision adds none at the design level either); the written two-register position
for Husky ↔ Shiba Inu (still needed before that pair ships, the same way Rabbit ↔ Fox has
one); and Shiba Inu's `fact_text` (still unsourced — `cleared-pool-fact-cards.md` found no
approved-source, predation-free Shiba Inu fact; Bull's `fact_text` is similarly flagged
provisional there, not blocking this decision either).

**What this unblocks:** step 4 (data entry — gameplay-engineer builds the nine `.tres`
files) for all nine species. Step 5 (copy) is already drafted for eight of nine in
`docs/content/cleared-pool-fact-cards.md`, homeless until step 4 lands; Bull's is flagged
provisional and Shiba Inu's is not yet written.

---

### D-44 · Camera rotation (90° steps) partially reopens D-41's "never rotates" clause

**Decision:** The fixed-heading camera D-41 shipped (`yaw=45°`, pan/zoom only) gains discrete
90° rotation — two HUD buttons (with directional arrow glyphs, `↺`/`↻`) plus Q/E keys —
cycling through the four cardinal-family headings (45°/135°/225°/315°), each still the same
isometric pitch. Instant snap, no easing, matching every other camera transform in this
codebase. `DirectionalLight3D` rotates in lockstep with the camera so lighting reads the same
at every heading, rather than the sun's fixed-world-space direction making the three
non-default headings look inconsistently lit.

**Why:** Requested to let the player see behind tall assets/around obstructions by turning
the view, rather than relying solely on `OcclusionFader`'s automatic per-resident tree fade
(which only helps sightlines to *residents*, not the player's own view). Validated with a
throwaway spike before committing to the full change — the human's verdict: it materially
helps read what's on screen, no structural (missing-geometry/wrong-texture) problems surfaced
from the rotated angles, only a lighting-consistency issue this decision's sun-lock fixes.

**What D-41's reasoning got right, still:** buildings still have no independent rotation
logic of their own — one fixed footprint/facing per placed building, unchanged. What's
reopened is narrower than "the camera can show any side of anything": D-41's ban was on
*free* rotation (walking around, arbitrary angle); this ships four fixed, still-isometric
headings, and playtest didn't surface the building-facing problem D-41 was written to
prevent. Flagged as **not exhaustively art-reviewed** — a human pass over the full
building/placeable roster at all four headings is still open, not gated on this decision.

**Supersedes:** `camera_rig.gd`'s "never rotates" header claim and
`test_camera_rails.gd`'s old `_check_cannot_be_rotated()` (replaced with `_check_rotation()`,
its inverse).

**Mechanical consequence applied in the same pass:** `tier1-status.md` row 2's `status` cell
gains a note at the top of its current (2026-08-14, → D-41) entry. Row 2 is **not** reopened
a further notch over this decision — it is already 🚧 from D-41 and stays there — but its
still-pending human gate now has to additionally cover three things this decision introduces:
the rotation control itself (does it feel right, do `↺`/`↻` actually match the direction each
one turns), whether the sun-lock fix genuinely keeps lighting consistent across all four
headings in real play and not just in the headless check, and the **not exhaustively
art-reviewed** open item this decision flags two paragraphs up.

Full design: `docs/superpowers/specs/2026-08-16-camera-rotation-design.md`.
Full implementation plan: `docs/superpowers/plans/2026-08-16-camera-rotation.md`.

### D-45 · Alpaca's `tiles_per_individual` raised 3 → 5 — a live-playtest correction to D-43

**Decision:** Alpaca's `tiles_per_individual` changes from D-43's originally-ruled **3** to
**5**, matching Horse and Cow. Every other D-43 value for Alpaca (`habitat_needs`,
`personality`, `farm_tolerant`, `scout_radius`, `max_individuals`) is unchanged.

**Why:** reported directly from play — "way too many alpacas… every other animal tends to
leave." Traced through the shipped simulation code, not guessed:

- `HomeSiteRegistry.rebuild_ownership()` gives every home site **exclusive ownership of its
  entire radius disc** (~200 tiles at radius 8) the moment it registers — not just the tiles
  it needs to satisfy its own `habitat_needs`. Any tile inside that disc stops counting for
  every *other* species' capacity, regardless of whether the owning species even reads that
  tile's tags. A newer or nearer site can also take tiles from an existing owner on the next
  rebuild (nearest-wins, ties to the older site — gdd.md's stated rule, `home_site_registry.gd`
  lines ~204-221).
- `CapacityEvaluator` only counts tiles a site currently owns (`capacity_evaluator.gd`), so
  losing tiles this way directly shrinks a site's `capacity(h, S)`.
- **Gentle Displacement (Tier 1 row 10) is fully shipped**, not a stub: when a site's capacity
  drops below its population, the game correctly warns and then relocates or evicts the
  residents (`gentle_displacement.gd`). The reported symptom — other animals leaving — is this
  system firing exactly as designed, in response to a real capacity loss, not a bug in it.
- The trigger was Alpaca's specific D-43 tuning: `tiles_per_individual = 3` was the lowest of
  any farm-tag species (Horse/Cow 5, Donkey 4, Bull 6) on `[open_grass, cultivated]` — the two
  most generic, most common tags in the game, shared by every other farm-tag species plus
  Rabbit (`open_grass`) and Human (`cultivated`). Alpaca could reach `capacity >= 1` on far
  less land than any competitor sharing those tags, so Alpaca sites proliferated cheaply
  almost anywhere near a farm, and **each one locked up its full ~200-tile disc** — most of it
  unused by the Alpaca itself — starving Horse/Donkey/Cow/Bull (and to a lesser extent
  Rabbit/Human) of land they needed, dropping their capacity below population, and triggering
  the displacement the player observed.

**Why this fix and not the others considered:** raising `tiles_per_individual` to 5 removes
Alpaca's outlier cost advantage over its own farm-tag cluster without touching the shared
exclusivity/ownership mechanism (which is intentional, load-bearing architecture already
working correctly for Fox/Rabbit, and not itself defective — it just had no prior outlier to
expose the whole-disc-claim cost). Two alternatives were raised and set aside: diversifying
Alpaca's habitat tags away from the open_grass/cultivated commons (would also help, but needs
a fresh ecological justification and wasn't judged necessary once the cost outlier was
closed), and reducing Alpaca's `scout_radius`/`capacity_radius` (not viable — 8 is already the
GDD's stated band floor, `validate()` rejects anything below it).

**Not addressed by this decision, flagged for awareness:** the underlying whole-radius-disc
exclusivity mechanism means any future species with a low `tiles_per_individual` on common
tags could reproduce this same failure mode. This decision fixes Alpaca's specific outlier
value; it does not change the mechanism itself, which was judged correct and shared
infrastructure other species already depend on.

**Files changed:** `project/data/animals/alpaca.tres` (`tiles_per_individual` 3 → 5, header
comment updated), `game-design/roster.md` (Already-Defined Roster table, Alpaca row).

### D-46 · Home-site tile exclusivity scoped per-species — different species no longer compete for the same land

**Decision:** the home-site tile-ownership rule (gdd.md's exclusivity rule) is no longer
global across every species. It now applies only between home sites that are genuinely
rivals for the same land:

- **Structure sites** (any home site backed by a placed building — a House, currently the
  only one) pool into one shared scope **regardless of occupant species**, vacant or claimed.
  "Two Houses each keep their own `house` tile" (gdd.md's own example) still holds
  independent of who lives in each one.
- **Every other ("wild den") site** is scoped to its own `species_id`. Two Fox dens still
  split forest tiles between themselves (gdd.md's other example) — but a Fox den and a
  Rabbit warren, or a Cow pasture and a Horse pasture, no longer compete at all. Different
  species now freely and independently draw capacity from the same land.

**Why:** raised directly by the human, following D-45's Alpaca fix, with a sharper example
than Alpaca alone — Human, Cow, and Horse were fighting each other for the same cultivated/
open_grass tiles under the old global rule, despite sharing that kind of land perfectly well
in real life. D-45 fixed Alpaca's specific tuning outlier but left the underlying mechanism
untouched; this decision fixes the mechanism itself. gdd.md's own two worked examples were
already, on inspection, two different rules bundled into one sentence — "two fox dens" is
same-species competition, "two Houses" is same-structure-type competition — and neither
example ever asked for cross-species competition. The old code enforced it anyway, purely as
a side effect of the ownership map being keyed by tile alone with no species dimension. That
stayed invisible while the floor roster's tag needs barely overlapped (Fox: forest+cover,
Rabbit: open_grass+cover, Human: house+cultivated); D-43 made the overlap real by adding five
species that all read open_grass/cultivated.

**The structure carve-out, and why it's necessary, not just tidy:** Human, Husky, and Shiba
Inu all need `house` in their `habitat_needs`, and the *only* tag source for `house` is a
placed House (terrain.md's tag-source table). That means every one of their home sites is,
in practice, always a structure site — there is no non-structure path to a `house` tag. If
structure sites were scoped by species instead of pooled together, two Houses occupied by
different species (say a human family and a husky) would stop competing for the same yard,
silently breaking "two Houses each keep their own tile" the moment more than one house-tag
species exists. Pooling every structure into one scope, independent of occupant species, is
what keeps that invariant true in general rather than true only by accident of the floor
roster having exactly one house-tag species.

**A second gap found and fixed during implementation, not part of the original ask:**
scoping ownership by species reopened a hole the old global map had closed for free. A
genuinely prospective candidate (a tile the player just edited, nobody home yet) resolves
its query scope from its own species id, never the structure scope — so, unguarded, it could
read a *structure's own footprint tile* (e.g. a House's `house` tag) as unclaimed, because it
was never checking the structure scope at all. Verified empirically, not theoretically: a
single House next to a cultivated field spawned a second, phantom villager family standing
on the field tile itself, and two adjacent cultivated tiles produced three families from one
House. This fired in the game's single most common building configuration, not an edge case.
Fixed with a narrow, tile-exact guard (`HomeSiteRegistry.structure_site_at()`): a prospective
candidate never counts a structure's own footprint tile, full stop — but this does not
withhold the *rest* of a structure's scoped territory (a field or grass patch a House merely
happens to be the nearest structure-scope owner of stays freely shareable with a wild species
that has no use for `house`), so it doesn't reopen the cross-species competition this
decision removes elsewhere.

**Consequence for the shipped floor roster, called out explicitly:** Fox and Rabbit stop
competing for `cover` (rock) tiles, which the old global rule made them do as an unintended
side effect (they share the `cover` tag despite otherwise-disjoint needs). Their spacing was
already meant to be the Avoids system's job — roster.md: *"foxes and rabbits each like plenty
of space of their own"* — so removing the redundant tile-level competition makes the
simulation match that stated intent more closely, not less. No shipped test asserted the old
cross-species behavior for Fox/Rabbit specifically (checked before implementing), so this is
a correction, not a break.

**gdd.md updated** (Habitat Suitability, the exclusivity-rule bullet) to state the scoping
explicitly, so the doc no longer implies global competition the code never actually intended
per its own two worked examples.

**Files changed:**
- `project/scripts/simulation/home_site_registry.gd` — scoped ownership map, `STRUCTURE_SCOPE`,
  `_scope_key()`, `structure_site_at()`
- `project/scripts/simulation/capacity_evaluator.gd` — `_tile_counts_for()` resolves query
  scope from `self_site`/`species`, plus the prospective-candidate structure-footprint guard
- `project/tests/test_tile_exclusivity.gd` — same-species fixtures corrected to match the
  file's own "two fox dens" framing; new test proving different species no longer split
  tiles; new test proving two Houses split land regardless of occupant species
- `project/tests/test_gentle_displacement.gd` — three-home fixture's synthetic species given
  distinct `capacity_radius` values (test geometry only, not gameplay tuning) since it
  depended on the old global nearest-wins across two different species
- `project/tests/test_avoids_distance_keeping.gd` — a perf-smoke transition-count bound tied
  to a population size that only existed because Rabbit/Fox previously competed for land;
  changed to scale per-roamer now that they legitimately coexist and more residents land
- `game-design/gdd.md` — exclusivity-rule bullet rewritten to state the scoping

**Test status:** 70/71 suites pass (`bash scripts/run-tests.sh`), verified independently.
The one failure, `test_fact_card`, is the pre-existing, already-tracked Shiba Inu placeholder
`fact_text` gap — unrelated, untouched by this decision.

**Flagged for the human:** the `structure_site_at()` guard was a design call made during
implementation to close a concretely-verified duplication bug, not a values/tuning decision
— worth a second look given it wasn't part of the original scoping request, even though it
was necessary to keep that request from regressing ordinary House placement.

### D-47 · `AnimalDefinition.fact_text` becomes `fact_text_pool` — multi-card content, no UI change yet

**Decision:** `AnimalDefinition`'s single `fact_text: String` field is replaced by
`fact_text_pool: Array[String]`, plus a new method, `effective_fact_text() -> String`, that
returns `fact_text_pool[0]` (or `""` if the pool is empty). `FactCard.show_species()` and
every other caller now read through `effective_fact_text()` instead of the raw field, the
same "resolve through a helper, never read the raw field" contract `effective_capacity_radius()`
already establishes on this class. **No player-facing behavior changes**: the game still
shows exactly one card per species, since only index 0 is ever read — gdd.md row 7's "One
card per species" line stands unmodified.

**Why:** this assignment's content-generation pipeline (`archive/mark-vanderboom-assignment-6/`)
needed to be able to generate more than one validated fact card per species, both to demo
that capability and because a rotating pool is the real fix for tap-to-replay showing the
same sentence every time — raised directly by the human. Building the pipeline against a
field that can only ever hold one card would mean re-migrating the schema the moment
rotation UI actually gets built, the same "prerequisite plumbing before the real feature"
shape D-42 used for `TerrainDefinition.model_scenes`.

**Migration:** all twelve roster `.tres` files (`rabbit`, `fox`, `human`, `deer`, `stag`,
`horse`, `donkey`, `cow`, `bull`, `alpaca`, `husky`, `shiba_inu`) moved from
`fact_text = "..."` to `fact_text_pool = Array[String](["..."])` — a single-element array
each, wording unchanged (including Shiba Inu's still-open `PLACEHOLDER` entry, which
`validate()` still catches, now against `fact_text_pool[0]`). `validate()`'s empty/placeholder
checks were re-pointed to iterate the pool rather than read one field. `spec.md`'s
`AnimalDefinition` schema row and every test that read `.fact_text` directly
(`test_fox_schema.gd`, `test_rabbit_schema.gd`, `test_human_schema.gd`, `test_fact_card.gd`,
`test_inert_land_invariant.gd`, `test_news_report.gd`) now go through `effective_fact_text()`
or set `fact_text_pool` instead.

**Scope, explicitly:** `PlaceableDefinition.fact_text` (buildings' flavor copy) is an
unrelated field on an unrelated schema that happens to share a name — not touched, not
migrated. Fact-card **rotation** (picking something other than index 0, on a timer or on
replay) is explicitly deferred — no design exists yet for how a repeat tap should choose
among a pool, and building that blind was out of scope for tonight. `content-pipeline-status.md`'s
per-species `copy_content_location` notes ("same file, `fact_text` field") were not batch-edited
for the new field name — still accurate in substance (same file), just not re-worded.

**Flagged for human sign-off**, consistent with how D-25/D-26/D-42 were handled: a schema
shape change, implemented directly rather than proposed-and-parked, but the human should
review the pool contract (and, separately, decide whether/how rotation ships) before more
content lands in it.

### D-48 · `scripts/fact_card_pipeline.py` adopted as the production fact-card mechanism

**Decision:** the Generator/Evaluator/Refiner/Circuit-Breaker pipeline built for
`archive/mark-vanderboom-assignment-6/` (→ D-47 is its schema prerequisite) is adopted
as Wildhaven's actual mechanism for fact-card content going forward, not shelved as a
one-off assignment artifact. Concretely: (1) moved out of `archive/` to
`scripts/fact_card_pipeline.py` — CLAUDE.md's rule that `archive/` is never used
unless explicitly referenced makes that folder the wrong home for a tool meant to keep
running; (2) it now writes `content-pipeline-status.md`'s `copy_content_location` row
for whichever species it runs against, the same field Content Writer's hand-drafted
process already owned, via a new `update_content_pipeline_status()` that touches only
that one row (never `status`, which needs data/attribution/validation state the script
has no visibility into); (3) it has doc standing —
[game-design/fact-card-pipeline.md](../game-design/fact-card-pipeline.md), the
fact-card-scoped analog of `asset-import-pipeline.md`, referenced from
`.claude/agents/content-writer.md`: *"for fact-card copy specifically, run it instead
of hand-drafting."*

**Why:** raised directly by the human, mid-conversation, as a direct challenge to my
own framing — I had described `content-writer.md`'s hand-drafted process as "the agent
that does this for real going forward" purely out of inertia with the existing pattern,
without weighing that the new pipeline already does more than the hand-drafted process
(an automated refine loop, cross-model judging, a circuit breaker, dedup checking) and
had already been proven against two real gaps. There was no good argument for archiving
the stronger tool and continuing to run the weaker one.

**Scope, explicitly (task 4 of the adoption):** fact cards ONLY. News Report pools and
first-time-nudge copy are NOT covered — `fact-card-pipeline.md` states this and
`content-writer.md` is updated to say so. The pipeline hasn't been validated against
News Report's four-sub-pool structure or nudge copy's own constraints; generalizing it
without that validation would have been an assumption, not a decision, so it stays
Content Writer's hand-drafted remit until a future pass deliberately extends it.

**Evidence the move didn't just relocate a file:** re-run for real from the new
location against both of D-47's original targets. Shiba Inu (`--count 2`): 2 cards
accepted, `shiba_inu.tres`'s `fact_text_pool` replaced, tracker row updated. Bull
(`--count 2`): candidate 1 took all 3 refine attempts before the judge accepted
*"Bulls can see almost all the way around themselves without moving their heads!"*;
candidate 2 passed first try with a distinct fact (working-animal strength/history);
tracker row updated. `bash scripts/run-tests.sh`: 71/71 green after both runs. Full
attempt-by-attempt logs: `scripts/fact_card_pipeline_output/{shiba_inu,bull}.json`.

**Flagged for human sign-off**, same posture as D-47: `content-pipeline-status.md`'s two
rows and both `.tres` files hold pipeline-proposed content, not human-approved content —
`human_signoff` was not touched and is not this decision's to grant.

### D-49 · `scripts/style_guide_pipeline.py` adopted as the production Gentle Displacement copy mechanism

**Decision:** the Generator/Evaluator(scored)/Refiner pipeline built for
`archive/mark-vanderboom-assignment-7/` is adopted as Wildhaven's actual mechanism for
Gentle Displacement copy going forward, not shelved as a one-off assignment artifact —
the same call D-48 made for fact cards, mirrored deliberately: (1) moved out of
`archive/` to `scripts/style_guide_pipeline.py`, same CLAUDE.md rationale as D-48; (2) it
writes directly into `project/scripts/ui/displacement_copy.gd`'s `WARN_`/`DEPART_`/
`MOVE_` constants and lookup tables — the content's own established interim home
(`docs/content/displacement-copy.md`'s "Where this should live" section already flagged
this file as homeless pending a schema decision; this pipeline targets the existing
home, not a new one); (3) it has doc standing —
[game-design/style-guide-pipeline.md](../game-design/style-guide-pipeline.md), the
Gentle-Displacement-scoped analog of `fact-card-pipeline.md`, referenced from
`.claude/agents/content-writer.md`.

**Why:** raised directly by the human, mid-conversation, asking to adopt this pipeline
"the same way" as D-48 — a deliberate mirror of that decision rather than a new
argument, since the underlying case is the same one D-48 already made (an automated
refine loop beats hand-drafting for a content type with a mechanically-checkable rule
set) applied to a second content type with its own distinct rule set.

**Scope, explicitly:** Gentle Displacement copy ONLY (warning/departure/relocation
lines for the nine cleared-pool species). Not fact cards (D-48's remit), not News
Reports, not the first-time nudge — those stay Content Writer's hand-drafted remit.

**Deliberately NOT done by this decision:** wiring a `copy_content_location`-style
pointer into `content-pipeline-status.md`. That tracker's field is already
fact-card-pipeline-owned per species (D-48) under its "every field has exactly one
write-owner" rule, and `docs/content/displacement-copy.md` had already flagged, before
this pipeline existed, that displacement copy's eventual schema home (a `SpeciesCopy`
sub-resource vs. new `AnimalDefinition` fields) is an open, undecided question. Adding a
second content-writer pointer into a field D-48 already owns, or inventing a new field
ahead of that schema decision, would be an assumption, not a decision — left to the
human as a follow-up, exactly the posture D-48 itself set for extending the fact-card
pipeline to other content types.

**Evidence the tool works for real, including a real catch:** `--demo` ran the
assignment's required 3 before/after violation-class cases (tone, vocabulary/framing,
formatting) against Bull, Shiba Inu, and Husky — full transcript in
`archive/mark-vanderboom-assignment-7/README.md`. Real production runs for Bull and
Shiba Inu (all three line types each) landed 5 of 6 lines clean and caught a genuine
defect on the 6th: a Refiner rewrite for Shiba Inu's relocation line echoed the file's
own `{display_name}` template syntax back as literal, unsubstituted text, scored 9/10 by
the LLM judge, with nothing in the original style guide or deterministic sweep written
to catch it. Fixed by adding a stray-`{`/`}` check to `deterministic_evaluate()` plus a
`selftest()` regression case reproducing the exact string; the affected line was
re-generated clean. `bash scripts/run-tests.sh`: 71/71 green after the fix and both real
species runs. Full attempt-by-attempt logs:
`scripts/style_guide_pipeline_output/{demo,bull,shiba_inu}.json`.

**Flagged for human sign-off**, same posture as D-47/D-48: the six new
`WARN_`/`DEPART_`/`MOVE_` constants in `displacement_copy.gd` hold pipeline-proposed
content, not human-approved content — each is inline-flagged "AWAITING CONTENT-WRITER
SIGN-OFF" and this decision does not grant it.

### D-50 · Settings and Credits move off the in-game Tab popup onto their own Title-screen pages

**Decision:** `MenuWindow` (the Tab popup) drops its Settings and Credits tabs; Field
Guide is its only remaining tab. The real Settings content (Master Volume slider +
Gameplay Hints toggle, `scripts/ui/settings_overlay.gd`) and real Credits content (the
license-attribution list, `scripts/ui/credits_screen.gd`) move onto
`scenes/menu/SettingsScreen.tscn`/`CreditsScreen.tscn` — the Title screen's own Settings/
Credits buttons, which previously routed to `coming_soon_screen.gd` placeholders. Both
screens keep their existing scripts; only their host scene changed.

**Why:** raised directly by the human. Settings/Credits are no longer reachable
mid-session — reaching them means leaving to the Title screen first (`LeaveOverlay`
autosaves, then confirms), same as any other "Exit to Main Menu" trip. A value changed
there (Hints, Master Volume) still round-trips through the one `GameplaySettings` source
of truth and takes effect on the next session; there is no longer a live in-session
toggle path.

**Supersedes gdd.md's prior line** ("Settings is one shared screen reachable from title
and in-game … opening it in-game does not pause the world, per Pillar 1") — gdd.md's
GUI & screens section and its Tab control-scheme row were rewritten to match this
decision, not left to drift.

**Tests:** `test_menu_window.gd` now asserts the Settings/Credits tabs are gone rather
than hosted; `test_news_report.gd`'s live-wiring check was replaced with a check that a
freshly-bound `NewsReportPresenter` reads `GameplaySettings.hints_enabled()` at bind
time (the cross-session path this decision now relies on, in place of the retired
mid-session signal). Two new suites, `test_settings_screen.gd`/`test_credits_screen.gd`,
cover the real content now living on the Title-screen pages.

### D-51 · The in-game Credits screen now lists every attribution source, not only the binding one

**Decision:** `credits_screen.gd`'s `refresh()` reads `AttributionCatalog.load_entries()`
(all 7 sources) instead of `AttributionCatalog.binding_entries()` (the 1 under a binding
CC BY 3.0 obligation — Sherkiz's Rabbit). The in-game screen and `CREDITS.md` now show
the same set; `CREDITS.md` still sections them ("Required attributions" vs.
"Acknowledgements") and the in-game screen does not, but every source's `creator —
source_name (license_name)` line renders either way, and the Sherkiz entry's
`required_notice` line still appears verbatim, unweakened by sitting alongside six
courtesy entries.

**Why:** raised directly by the human — "our credits do not include attribution for all
of the assets we use... not just the rabbit." The prior scope (binding-only) was a
deliberate reading of the license condition ("credit what a license actually requires,"
D-15/row-15 history in tier1-status.md), not an oversight — every CC0 Quaternius pack was
already fully documented in `CREDITS.md`, just not surfaced in-game. This decision is the
human choosing generosity over the legal floor: a CC0 creator gets thanked on-screen too,
not only in the repo's audit trail.

**Not a data change.** No `.tres` entry, license file, or `CREDITS.md` content changed —
the underlying attribution record was already complete for every asset actually imported
(verified against `project/assets/` during this pass: every folder there traces to an
`assets_used` entry in one of the 7 `attribution/sources/*.tres` files, several of them
composite scenes — e.g. `RockCluster*.tscn`, `CultivatedCropsPlot.tscn` — built entirely
from pieces already-credited elsewhere, needing no new entry). Only which entries the
in-game screen renders changed.

**Tests:** `test_credits_screen.gd` rewritten to assert against `load_entries()` (all 7)
rather than `binding_entries()` (1), plus an explicit check that the Sherkiz
`required_notice` still appears verbatim in the rendered list.
