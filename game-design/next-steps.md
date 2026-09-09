# Where We Actually Stand — and What to Do Next

> **Rewritten 2026-09-08**, replacing the 2026-07-27 assessment wholesale. That version was
> written when the repo held 418 lines of GDScript and no Tier-1 row had been implemented;
> keeping it patched would have meant maintaining a document whose every number was six
> weeks stale. Its arguments that still matter are carried forward below and marked as such.
> Not a design document: nothing here overrides [gdd.md](gdd.md). It is an assessment of
> state, a triage of what is genuinely undecided, and a recommended order. Per-row state
> lives in [tier1-status.md](tier1-status.md); this doc is the argument for what to do
> with it.

## 1. The headline

**The game exists and plays.** The complete-loop test — new game → terraform → gather →
build → an animal genuinely moves in → a fact card → the world grows at the mist → quit →
load, world intact — is buildable end to end today, in a browser, from a URL.

That is a different project from the one the July assessment described, and the two
diagnoses invert:

| July 2026 | September 2026 |
|---|---|
| "There is no game yet — there is a very well-specified game" | There is a game, and it has overshot most of its own floors |
| Most of the work has been content, not implementation | Implementation caught up and passed; **the remaining gaps are taste and one asset class** |
| The risk is continuing to design instead of build | The risk is **shipping untuned** — nearly every number in the game is still a proposal |

## 2. The diagnosis, in numbers

| | July 27 | Today |
|---|---|---|
| GDScript in `project/scripts/` | 418 lines, 4 files | **19,507 lines, 76 files** |
| Test suites | 29, ~24 of them asset-import checks | **152 suites, 32,910 lines — 152/152 green, 0 failed** (`bash scripts/run-tests.sh`, 2026-09-08) |
| Tier-1 rows past step 3 (implemented) | 0 of 15 | **14 of 15** |
| Species with gameplay data | 2 | **15** |
| Buildable placeables | 0 | **10** |
| Paintable terrains | 0 | **8**, plus wild grass |
| World presets | 0 | **3**, each building a different world |
| Attribution sources cleared | — | **14** |
| Shipping platform | planned desktop ×3 | **one web build**, deployed |

**The one row still at zero is row 14, audio.** There is no `.ogg`, `.wav` or `.mp3` in the
repo, no bus layout beyond Godot's default Master, and no `AudioStreamPlayer` in any
gameplay scene. Settings' Master Volume slider controls nothing audible. Every chime the GDD
narrates — terraform confirmation, build confirmation, mist reveal — is design intent.

## 3. What's solid

**Don't touch, don't redo:**

- **The simulation spine.** Habitat tiers (D-52), per-need radii and divisors, gate-only
  needs, exclusion limits, group arrivals with partial landing, resident-emitted tags, the
  acyclic emission graph. It is the most-specified part of the design and the code matches
  the specification field for field.
- **Asset sourcing, import, attribution and licence compliance.** Still the strongest
  subsystem in the repo, and it now carries 14 sources with a fail-closed generator and a
  regression test. It scaled from 2 species to 15 without changing shape.
- **Data-driven content, proven repeatedly.** Going from 1 building to 10, from 5 terrains
  to 8, and from 2 species to 15 required no schema rewrite. The promise held under real
  load, not just its first test.
- **The test suite.** 152 suites, all green, is not ceremonial — it caught the villager-variety
  save/load bug, the building centre-tile emission defect, and the camera Rail 2
  regression. It is also honest about its own limits: several suites carry explicit
  `PEND` notes saying a thing *cannot* be tested headlessly and belongs to the human.
- **Persistence.** `save_version` 7 with a complete migration chain from v1, idempotent,
  every step documented in place.

## 4. What's thin — and it is not what it used to be

**Audio (row 14) — the only true zero.** ~0.75–1 h of tech-art work, one ambient bed and
one confirmation SFX. It is cheap, it is unstarted, and "silence reads as broken" is the
row's own justification. This is the single most disproportionate gap in the build.

**Tree occlusion is an open problem again.** D-41 built a per-resident transparency fade to
solve it; D-59 removed the fade because it flickered in play. The measured finding that
camera angle alone does not fix occlusion still stands, so the problem is open with no
candidate solution in the repo.

**Tuning — the real exposure.** **All fifteen** animal `.tres` files carry proposal language
in their headers, and **nine of ten** building costs are proposals (only House's 15 Wood was
ratified, at D-29). Habitat radii, divisors, tier caps, arrival group sizes, building costs:
every one shipped as a proposal awaiting sign-off. The suite being green confirms the
mechanics work as specified; it says nothing about whether the numbers are right. **This is
now the largest single block of un-run human judgment in the project**, and no amount of
agent work reduces it — the project rule is that all tuning values are the human's.

There is a hard consequence attached: the release checklist's Gate 4 requires that **no
`PROPOSED` or `PLACEHOLDER` marker has reached a shipped `.tres`**. On today's data that gate
fails outright.

**Content copy.** Shiba Inu has no `fact_text` (no approved source cleared step 1), Bull's
is flagged provisional, and nine `[COPY]` markers sit in UI scripts — the terrain group's
player-facing name among them.

**The near-miss summary does not exist.** Discovery is supposed to weight *which* species
gets hinted from qualification's own byproduct; it degrades to plain terrain bias instead,
exactly as designed to. `NewsReportContent.pick_species()` already accepts the summary as an
optional input for the day it lands.

**Sand was never built.** It is named across the docs as the sixth v1 terrain and as a depth
purchase; it has no `TerrainDefinition` and no wired asset, so the `sand` tag has neither a
source nor a consumer. Either build it or stop counting it.

## 5. The trap has moved

July's trap was "lots of things still need defining" when the real answer was *stop
designing and build*. That argument was right and it worked. **The trap now is its mirror
image:** the build has run so far ahead that it is easy to keep buying features instead of
running the gates that turn proposals into decisions.

Read the open-question ledger by what it would take to close each:

| Category | Examples | What closes it |
|---|---|---|
| **Tuning — needs a running game** | #8 costs, #9 avoids distance, #16 grace/recycle, #19 mist, #20 radii, #28 pacing | **Playing it.** The game runs; this is now unblocked and unstarted |
| **Playtest-resolved** | #27 numeric vs. qualitative, #29 wild-grass look | Kids, at the step-5 checkpoint |
| **Content** | #11 fact cards, #12 nudge copy | A content pass; two species short |
| **Structural, still open** | #18's world size half, tree occlusion | A ruling and, for occlusion, a design |
| **Process** | #30 hours re-verification | The velocity review, which has not run |

Every one of these is now answerable, and most were not in July. **The blocker is no longer
information; it is your attention.** `actual_hours` is filled in on exactly one of fifteen
rows, which means the week 2–3 velocity review still has nothing to correct against — the
same warning July's version ended on, still unheeded.

## 6. Two things the July assessment got right and are still true

Carried forward because they aged well, not out of sentiment:

1. **"You cannot pilot camera feel before there is a camera" (D-21).** The corollary now
   binds in the other direction: there *is* a camera, and a habitat system, and an economy.
   The things that could only be answered by playing can now be answered by playing, and
   nothing else will answer them.
2. **Mechanism → agent, feel → human.** Row 6 split exactly this way and the split held
   through habitat tiers, the capacity evaluator and roam regions. It is the reason the
   simulation spine is as solid as it is, and it is the right shape for whatever comes next.

## 7. Recommended order

### Now — close the zero
**Row 14, audio.** One ambient bed, one confirmation SFX, wired to the existing Master
Volume. Cheapest remaining row, largest perceived gap, and it makes the Settings slider
mean something. tech-art, directory-disjoint from everything.

### Now — run the tuning gates
This is the work, and it is yours. Batch it: sit with the running game and rule on the
`PROPOSED` constants row by row — building costs, habitat radii and divisors, the grace
window, the arrival delay. Each ruling is minutes; the value is that a decided number stops
being a liability at the release checklist's "no `PROPOSED` marker has reached a shipped
`.tres`" gate. **Record `actual_hours` as you go**, or the velocity review stays impossible.

### Next — the kid playtest
Everything the step-5 checkpoint was defined to validate is now buildable: time-to-first-
move-in against its 2 min target and 5 min ceiling, camera feel, tap learnability, whether
the qualitative preview reads. The web build makes the logistics trivial — a URL, not an
install. This is the highest-information hour available in the project.

### Then — the two named gaps
Tree occlusion (open with no candidate), and the near-miss summary (specified, unbuilt,
with its call site already waiting). Neither blocks the loop; both are visible in play.

### Then — content backfill
Shiba Inu's fact card and Bull's replacement, the nine `[COPY]` markers, and the terrain
group's player-facing name. Batched by step, not by species, per the resume rule.

### Deliberately not recommended
**More species, more buildings, more terrains.** The roster is at fifteen against a floor of
three, and each addition is a fresh set of unruled numbers. Depth is already bought well past
what the schedule assumed; buying more of it now trades against the tuning and playtest work
that actually stands between this and a shippable v1.

## 8. Timeline honesty

- The floor was estimated at **29–40 h** against a **35–55 h** budget. Fourteen of fifteen
  rows are built, most past thin — so the *construction* half of the schedule closed, and it
  closed with more depth than the estimate assumed.
- **`actual_hours` is recorded on one row of fifteen.** The single measured figure (~3–4 h
  for row 3, against a 2–3 h estimate) is the only evidence there is, and one data point
  cannot correct a ledger. Open Question #30 is not answerable in this state.
- **The accepted worst case is long since beaten.** The residual the GDD wrote down — three
  species, five terrains, one buildable, untuned camera feel — was overshot on every axis
  except the last. **Untuned is the one that survived**, and it is the one now worth
  worrying about.
- What remains between here and v1 is not construction. It is one cheap row, a batch of
  rulings, a playtest, and two named gaps.

**The single highest-value thing you can do this week is play the game with a six-year-old
and write down what the numbers should be.** Everything you don't currently know — whether
the arrival delay is right, whether the preview reads, whether a house costs too much — is
on the other side of that, and none of it is on the other side of more building.
