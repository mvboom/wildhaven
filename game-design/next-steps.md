# Where We Actually Stand — and What to Do Next

> Written 2026-07-27 as a planning reality-check, for a reader coming from software
> development rather than game development. Not a design document: nothing here overrides
> [gdd.md](gdd.md). It is an assessment of state, a triage of what is genuinely undecided,
> and a recommended build order. Per-row state lives in [tier1-status.md](tier1-status.md);
> this doc is the argument for what to do with it.

## Your read, scored

You were right about the big thing and wrong about two smaller ones that both affect the
timeline.

| Your claim | Verdict | What's actually true |
|---|---|---|
| Game defined, light objective, major pieces defined | ✅ **Right** | Arguably *over*-defined — see "the real diagnosis" below |
| Assets: terrain, roster, buildings identified and sourced | 🟡 **Mostly** | Roster yes (12 species cleared). **Terrain: only 3 of 6 imported** — water, cultivated field and sand have no asset at all. Buildings: 1 house, facing unconfirmed |
| Gameplay core defined but light on nitty-gritty | ✅ **Right**, and precisely so | There is exactly **one** structural gap that blocks code. The rest is tuning |
| UI/UX, terrain gen, save, popups not started, not terribly large lifts | 🟡 **Half right** | The shell (save, menus, HUD, settings, audio) really is ~6–7h and highly delegable. **The simulation heart is not** — rows 2 and 6 alone are 7–11h of a 29–40h floor |
| We can programmatically generate a lot of it | ✅ **Right** | The world is *designed* to be procedural — reveal is a pure function of `(world_seed, x, y)` |
| Fact cards shouldn't hold up the game; dummy text goes a long way | ✅ **Right**, and already supported | `AnimalDefinition` ships a `PLACEHOLDER_MARKER` constant for exactly this. `validate()` flags placeholder copy without failing the build |
| Same for buildings, terrain, animals — grey-box them | ✅ **Right**, and cheaper than you think | See "grey-boxing is free here" below |
| Nothing is actually stopping us from building the game | ✅ **Right**, with one exception | One decision, ~1 hour. Section 3 |
| Most of our work has been CONTENT, not implementation | ✅ **Right — this is the diagnosis** | Numbers below |
| We probably need to start working on the game itself | ✅ **Right** | |
| Lots of things still need to be defined | ❌ **Wrong, and this is the trap** | Section 4 |

## 1. The diagnosis, in numbers

You're right that the work has gone into content rather than implementation. Here is how
lopsided it is:

| | Count |
|---|---|
| GDScript in the entire project | **418 lines**, across 4 files |
| Tier-1 systems rows past step 3 (implemented) | **0 of 15** |
| Test suites | 29 — of which **~24 validate asset imports and animation clip names** |
| Design/planning documents | 12 in `game-design/`, plus 10 plan/spec pairs |
| Species imported, cleared, attributed | 12 |
| Species with gameplay data | 2 |

The 418 lines are: a 16×16 grid spike, an 18-line camera that sets one angle, a 30-line
title screen, and one 229-line data schema. **There is no game yet — there is a very
well-specified game and a proof that the asset pipeline works.**

That is not a wasted week. The asset pipeline is genuinely the part that could have gone
badly and didn't: licences cleared, attribution automated and gated by a test, a
wrapper-scene convention that makes model swaps a one-line change. That work does not need
redoing. But it is finished, and continuing to do more of it is the current risk.

## 2. What's actually solid vs. thin

**Solid — don't touch, don't redo:**
- Asset sourcing, import, attribution and licence compliance. The strongest subsystem in
  the repo, with a fail-closed generator and a regression test.
- The content pipeline. Measured twice (first-of-kind and marginal), so per-species cost is
  a known quantity, not a guess.
- The design's *principles* — pillars, the causality rule, the inert-land invariant, the
  capacity formula. These have survived several rounds of review and are internally
  consistent.
- Data-driven architecture. Adding species #2 required **zero** code changes to
  `animal_definition.gd`. That promise held under its first real test.

**Thin — needs work, but is ordinary work:**
- Two of three schemas don't exist (`PlaceableDefinition`, `HarvestableTileDefinition`).
- No terrain, building, or world data exists at all — `project/data/` holds two animals.
- Half the terrain assets are missing (water, cultivated, sand).

**Untested — the real unknown:**
- **We have never dispatched an agent to build a game system.** Section 6.

## 3. The one thing genuinely blocking code

Everything else can start today. This cannot, because two documents describe two different
data models and an implementer would have to guess:

> [terrain.md:16](terrain.md) — "Each tile silently accumulates habitat tags from its own
> terrain **and its neighbors**"
> [terrain.md:30](terrain.md) — every terrain declares which tags it emits "**at what
> radius, and with what weight**"
> [gdd.md](gdd.md) capacity formula — "**count qualifying tiles** within `capacity_radius`"
> [spec.md](spec.md) #6 — open: "per-tag **'counts as met' thresholds**"

Those imply two incompatible implementations:

**Model A — tags are a property of the tile.** A forest tile *is* a `forest` tag.
`count_t` = how many tiles in the species' radius emit tag `t`. No emission radius, no
weights, no thresholds. Implementable this afternoon.

**Model B — tags diffuse.** Each painted tile radiates its tags into a neighbourhood with
distance falloff; every tile accumulates a weighted score per tag; a tile "has" tag `t`
once its score crosses a threshold. This needs three more undefined parameters and puts a
second nested radius loop inside an evaluation that is already O(radius²).

**Recommendation: Model A, and the design already agrees — it just never said so where an
implementer would look.** [spec.md](spec.md)'s deepening table lists "**tag radius
richness**" as *depth* for row 6, which means the thin form is the version without it.
Model A also satisfies the design intent it appears to threaten: Fox needs `forest` **and**
`cover`, and with a species radius of 8–12 tiles, "both within the radius" already *is*
"forest near rock." The two-brushstroke composition survives.

**Action:** one paragraph added to `spec.md` under Shared Patterns stating the thin tag
model, and #5 narrowed to say emission radii and weights are depth. ~1 hour, mostly your
judgment, and it unblocks rows 3, 6 and 10.

## 4. "Lots still to define" — the trap

There are **24 open questions**. Here is what they actually are:

| Category | Count | Can it be resolved before the game runs? |
|---|---|---|
| Structural — blocks code | **1** (#5's model half) | Yes — do it now, section 3 |
| Shape-of-code, thin form is obvious | 2 (#7 group size, #17 tap-vs-drag) | Yes — pick the thin form, 10 minutes |
| **Tuning — needs a running game to answer** | **13** | **No** |
| Content — placeholder unblocks building | 3 (#11, #12, #31) | Yes, for building. No, for shipping |
| Playtest-resolved | 3 (#13, #27, #29) | No |
| Process/measurement | 2 (#28, #30) | No |

**Thirteen of twenty-four cannot be answered by more design work.** They are questions like
"how long should the arrival delay be," "how much Wood should a house cost," "how big should
the grace window be." You cannot answer those in a document. You answer them by playing the
thing and noticing it feels wrong.

The project already made this argument formally and wrote it down. From `decisions.md` D-21,
rejecting a proposal to do more measurement before building:

> *You cannot pilot camera feel before there is a camera.*

So: your instinct that "lots of things still need defining" is true by count and false by
consequence. More design work now is the failure mode, not the fix. **The `systems-pipeline`
already encodes the correct handling** — step 2 says every tuning number becomes a named
constant seeded at the GDD baseline, batched into one human decision, and *closed at the
human gate after the row runs*. That is the mechanism for turning 13 unanswerable questions
into 13 constants you tune once you can feel them.

## 5. Grey-boxing is free here — a property worth knowing

You're right that grey-boxing is the move, and the existing architecture makes it cheaper
than usual. Two reasons:

1. **Game code never references a raw asset.** It references a hand-authored wrapper scene
   (`project/assets/<category>/<name>/<Name>.tscn`). Swapping a grey box for a real model
   later is editing one wrapper, not hunting references.
2. **Content is data.** A terrain type is a `.tres` row. Its `model_scene` field can point
   at a coloured cube today and a Quaternius mesh next week with no code change.

So: build all five floor terrains as coloured cubes now, and the three missing assets
(water, cultivated, sand) stop being blockers. Same for the house. Same for fact-card text —
`PLACEHOLDER` copy is already a supported, validated state.

**The one thing you cannot grey-box** is the Human villager's fact card at *ship* time —
row 4's villager move-in is the USP proof, and gdd.md argues no other species can carry it.
But that's a shipping gate, not a building gate. Placeholder text is fine right up until the
step-5 playtest.

## 6. The agent gap — you identified this correctly

You said content-wise the agents may be defined and implementation-wise we may be lacking.
That's exactly right, and here is the sharp version:

**Our estimate confidence is inverted relative to our risk.**

| Work type | How well measured | Share of the token budget |
|---|---|---|
| Content pipeline runs | **Twice** — first-of-kind (Fox) and marginal (Rabbit), so we have a real ratio | ~13.5M |
| **Gameplay systems** | **Once** — a 141-line grid spike that also absorbed project scaffolding | **~11.2M** |
| UI screens | Once — a 30-line title screen | ~3.6M |

The budget's second-largest line is extrapolated roughly 8× from a spike. That's not
necessarily wrong, but it is unmeasured, and it covers the work that is now 100% of what
remains.

**What's missing, concretely:**

1. **The systems pipeline has never been run.** It was written today. The first row through
   it is the measurement that matters more than any other number in `costs.md`.
2. **A useful reframe the GDD currently blurs.** gdd.md says phases 3–6 are "the
   human-judgment spine, where AI helps least." That's true of camera *feel* and habitat
   *tuning*. It is **not** true of the capacity evaluator, which is a written formula with a
   machine-checkable invariant — precisely what agents are good at. Row 6 splits cleanly:
   **mechanism → agent, with tests; feel → you, after the mechanism runs.** Treating the
   whole row as human-bound would waste the agents on the biggest row in the build.
3. **Parallel dispatch is now possible and has never been tried.**
   [tier1-status.md](tier1-status.md) reserves six disjoint directories precisely so
   Technical Strategy #6's safety precondition is checkable. Rows 1 (`save/`), 14
   (`audio/`) and 15 (`ui/`) don't touch `simulation/` or `world/`.
   **But be clear-eyed about what this buys:** wall-clock, not human hours. Technical
   Strategy #7 says human decision gates are the real serialisation point, and the budget
   is denominated in *your* hours. Parallelism ships sooner on the calendar; it does not
   shrink the 29–40h.

## 7. Recommended order

One deliberate deviation from gdd.md's Phases of Work is flagged below.

### Step 0 — Unblock ✅ **DONE 2026-07-27 (→ D-25)**
- **Tag model: Model A.** Tags are a per-tile property — no emission radius, no weights, no
  thresholds. #5 **closed**; the threshold half of #6 closed with it. Model B is row-6 depth.
- **#7 narrowed.** Packs/families accepted as direction; **v1 ships group size 1** for every
  species. No new field yet — the arrival predicate already reads `capacity ≥ population + 1`,
  and the open question that gates a `group_size` field is whether a group of N requires
  `capacity ≥ population + N` or arrives partially.
- **#17 closed: single-tap.** Drag-to-paint is row-3 depth.

**Nothing structural now blocks writing simulation code.**

### Step 1 — Schemas and grey-box data ✅ **DONE 2026-07-27 (→ D-26)**
Landed: **three** schemas, not two — `TerrainDefinition` was forced by the inert-land
invariant (a derivation needs data to derive from), which is a contradiction nobody saw
until implementation started. Six terrain entries, a harvestable, a house, seven grey-box
scenes, five validation suites. **Suite 29 → 34 green.**

Two dispatches, two agents (gameplay-engineer then qa-engineer). **This is the first
measured systems-agent cost in the project** — see `costs.md`. Note what it is *not*: no
Tier-1 row passed step 3, because this was the data layer beneath rows 3, 4 and 5, not
the rows themselves.

### Step 2 — The walking skeleton ✅ **DONE 2026-07-27**
Rows **2, 3, 4, 5, 6, 7** built thin and validated. Five dispatches, three agents,
**~3.84M tokens, ~1.0 human hour.** Suite 34 → 43 green.

**The premise now demonstrably works:** paint rock beside grass → `rabbit` capacity rises
above 0 → arrival enqueues → resident spawns → fact card fires. And row 4's USP proof is
real — a villager moves into a House only once a cultivated field beside it lifts capacity.

**What it deliberately is not:** the complete *First 60 Seconds*. The causal spine is built;
beats 2 (nudge), 4 (live preview) and the audio bed are not. Two **pillar invariants
attached to Tier-1 rows remain unbuilt** — Gentle Displacement (row 10) and removal/undo
with its grace window (#16) — and both must ship before the kid playtest.

QA found and confirmed the fix for one pillar-invariant defect (camera Rail 2). **Verifying
cost more than building** — see the finding in `costs.md`; it is the most important budget
correction the project has.

### Row 10 — Gentle Displacement ✅ **DONE 2026-07-28**
The two pillar invariants missing after Step 2 are closed: the displacement guarantee, and
removal/undo with its grace window. **#31 closed in the same wave** — no shipped fact card
reads `PLACEHOLDER`. Four agents, two parallel pairs, **~2.61M tokens, ~1.0 human hour**
against a 2–3 h estimate. Suite 47 → 50.

**First parallel dispatch, and it held** — directory-disjointness made it safe. It buys
wall-clock, not human hours, so it does not move the 35–55h budget.

**Two things still gate a playtest:** row 10's presentation half is unvalidated, and the
priority rule currently makes the floor's likeliest displacement unreachable by tap while
the villager is home. See `tier1-status.md`.

### Step 3 — Persistence, earlier than the GDD schedules it ⚠️
**This is the one place I'd deviate from gdd.md's phase order**, which puts save/load in
phase 5. Standard software reasoning: serialisation gets more expensive with every state
type you add. Doing it when the world has three kinds of state instead of twelve is
materially cheaper, and "quit → reload, world intact" is half the complete-loop test.

Not a design change — a sequencing preference. Worth your call.

### Step 4 — The shell (delegable, parallel-safe, ~6–7h)
Rows 11, 12, 14, 15 and camera polish. Directory-disjoint from the simulation, so this is
the natural first parallel-dispatch experiment.

### Step 5 — The rest of the simulation
Rows 10 (displacement — depends on row 6's capacity evaluator), 13 (mist), 9 (avoids
behaviour). Displacement is a pillar invariant and does not thin much; budget for it.

### Step 6 — Content backfill
Human's Add-an-Animal run first — it's the floor's single point of failure. Then real fact
cards replacing placeholders. Then pool species as depth, **batched by step, not by
species**, per the resume rule.

## 8. Timeline honesty

- The floor is estimated at **29–40h** against a **35–55h** budget. It closes with margin
  only in the upper half of that range.
- **Zero hours of it are spent.** The 418 lines are phase-0 pilots.
- That estimate's largest component is extrapolated from a spike. Step 1 and Step 2 are
  where you find out whether it holds — which is exactly what `actual_hours` in
  [tier1-status.md](tier1-status.md) exists to capture. **Fill it in, or the week 2–3
  velocity review has nothing to correct against.**
- The design deliberately closes the schedule *by construction*, not by estimate: all
  fifteen rows are built thin, and leftover hours buy depth. If the estimate is wrong, what
  shrinks is purchased depth — not the ship date, and not the pillar invariants.
- The accepted worst case is already written down and is genuinely shippable: three species,
  five terrains, a 1×1 house, untuned camera feel — passing the complete-loop test and every
  pillar obligation.

**The single highest-value thing you can do this week is get one systems row through the
pipeline end to end.** Not because that row matters most, but because everything you don't
currently know — agent cost on systems, whether the schemas hold, whether the capacity
formula survives contact with a grid — is on the other side of it.
