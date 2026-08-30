# Wildhaven build ledger

One row per working session, appended at session end. Protocol for filling a row:
`docs/phase0/measurement.md`. Unit of account is tokens (gdd.md, Technical Strategy →
Token Budget); dollars are always derived later via the rate table, never recorded here.

Conventions:
- **`[setup]` flag** in the work-unit column marks one-time scaffolding cost
  (project structure, schema creation, toolchain fixes). `[setup]` rows are EXCLUDED
  from per-unit multiplier math during synthesis.
- **billable** = input + output + cache-write. Cache-read is tracked separately because
  it prices at a fraction of input and would otherwise swamp every total.
- *human hours*: human **attention**, in decimal hours — NOT elapsed wall-clock. Waiting on a
  dispatch is not attention; that time went to other tasks. Attribute to human touchpoints
  (decision gates, hands-on tasks, review tasks), not per agent row — see `measurement.md`.
  The `.1` values below are the human's own estimate of per-step interaction time and are
  **real measurements, not placeholders**; the per-row *shape* is a known modelling error,
  corrected in the finding below.
- Numbers come from `docs/phase0/token-report.py`, which reads the session transcripts.
  They are exact, per-agent, and recoverable retroactively — see the methodology note.

| date | session | agent/pipeline | work unit | input | output | cache-read | cache-write | billable | human hours | note |
|---|---|---|---|---|---|---|---|---|---|---|
| 2026-07-20 | 4e8403c7 | main loop | `[setup]` phase-0 scaffolding + pilot-1 orchestration | 311 | 171,826 | 13,495,502 | 624,885 | **797,022** | .1 | Not separable: this one main loop covers both phase-0 doc scaffolding and pilot-1 dispatch. See orchestration-overhead note. |
| 2026-07-20 | 4e8403c7 | 11× general-purpose | `[setup]` phase-0 docs (5 write + 5 review + 1 final review) | 275 | 27,924 | 2,873,030 | 627,063 | **655,262** | .1 | Final whole-branch review alone was 247,864 — 38% of the eleven. |
| 2026-07-20 | 4e8403c7 | gameplay-engineer | pilot-1 grid spike (build) | 106 | 12,414 | 1,101,727 | 94,203 | **106,723** | .1 | Includes project scaffolding (folders, Main.tscn, camera_rig) — not separately dispatched, so not separable. |
| 2026-07-20 | 4e8403c7 | qa-engineer | pilot-1 grid spike (QA validation) | 52 | 8,118 | 257,032 | 86,327 | **94,497** | .1 | |
| 2026-07-20 | af1bcc0a | ui-engineer | pilot-2 title screen (build) | 90 | 17,317 | 1,116,701 | 87,400 | **104,807** | .1 | Single-agent unit, exactly as the brief specifies. |
| 2026-07-20 | af1bcc0a | main loop | pilot-2 orchestration + `[setup]` measurement tooling | 81 | 28,090 | 1,762,107 | 97,838 | **126,009** | .1 | Mixed: pilot-2 dispatch AND the token-report.py detour below. Figure is as-of mid-session and still rising. |
| 2026-07-20 | fbb483c4 | tech-art | pilot-3 add-a-fox (audit + import + attribution) | 260 | 43,074 | 7,300,767 | 700,116 | **743,450** | .1 | 56% of all agent cost this session. Absorbs the FAILED rabbit audit (all 82 Quaternius packs enumerated to prove a negative) plus `[setup]` attribution schema + CREDITS generator. Three pipeline steps in one agent — not separable. |
| 2026-07-20 | fbb483c4 | gameplay-engineer | pilot-3 add-a-fox (`[setup]` AnimalDefinition + data entry + sign-off edits) | 134 | 15,325 | 1,955,545 | 300,102 | **315,561** | .1 | Agent's own split estimate: ~2/3 `[setup]` schema, ~1/6 per-species `.tres`. Two dispatches (data entry, then step-8 enum + copy changes). |
| 2026-07-20 | fbb483c4 | qa-engineer | pilot-3 add-a-fox (validation) | 13,226 | 13,058 | 1,770,494 | 109,033 | **135,317** | .1 | Built a real reusable suite (`project/tests/`), not a throwaway harness. Note the anomalous input figure — 13,226 vs ~100 for every other agent. |
| 2026-07-20 | fbb483c4 | gameplay-engineer | pilot-3 add-a-fox (design proposal, step 3) | 28 | 9,096 | 190,897 | 85,834 | **94,958** | .1 | Cheapest system-agent step. Cheaper than a true new species would be: Fox's row was already decided in the GDD, so this was a stress-test rather than a proposal from scratch. |
| 2026-07-20 | fbb483c4 | content-writer | pilot-3 add-a-fox (copy + source verification, step 5) | 58 | 15,740 | 535,980 | 183,623 | **199,421** | .1 | Two dispatches: drafting (54,260) then source verification (145,161) after the firewall opened. **Verification cost 2.7× the drafting.** See the verification-cost finding below. |
| 2026-07-20 | fbb483c4 | main loop | pilot-3 add-a-fox orchestration | 260 | 127,411 | 12,602,779 | 773,668 | **901,339** | .1 | Orchestration ratio 0.60:1 against agents — see the revised orchestration finding below. Includes three mid-session human gates, the rabbit→fox pivot, and the post-verification copy correction landed directly rather than by dispatch. |
| 2026-07-20 | fbb483c4 | tech-art | **pilot-3b** add-a-rabbit (re-audit + import + first CC-BY attribution) | 182 | 40,612 | 12,774,308 | 588,093 | **628,887** | .1 | Delta vs pilot 3. Largest 3b line. Absorbs a full second-source audit (37 models across poly.pizza + kenney.nl, proving animation is the scarce resource) and the first real license obligation. Not a steady-state import. |
| 2026-07-20 | fbb483c4 | content-writer | **pilot-3b** add-a-rabbit (copy, drafted AND verified in one pass) | 2,485 | 9,647 | 702,987 | 259,564 | **271,696** | .1 | **The clean copy-step number.** One pass, sources reachable throughout, checklist step 1 satisfied at first writing. Compare the fox's 54,260 draft + 145,161 verify = 199,421 split across two passes. |
| 2026-07-20 | fbb483c4 | qa-engineer | **pilot-3b** add-a-rabbit (validation + fox rebaseline) | 104 | 25,158 | 3,369,274 | 216,086 | **241,348** | .1 | Delta. Wrote 4 new suites (rabbit ×3 + attribution) and rebaselined the fox suite. Found the assertion-count root cause: a `check()` inside a loop over `validate()` output made the count data-dependent. |
| 2026-07-20 | fbb483c4 | gameplay-engineer | **pilot-3b** add-a-rabbit (data entry) | 38 | 7,756 | 930,560 | 180,206 | **188,000** | .1 | **The clean marginal-cost number.** Delta. `animal_definition.gd` needed ZERO changes to absorb a second species — the "data entry, not code" principle held under its first real test. |
| 2026-07-20 | fbb483c4 | main loop | **pilot-3b** add-a-rabbit orchestration | 148 | 83,870 | 14,092,203 | 163,330 | **247,348** | .1 | Delta. Orchestration ratio **0.19:1** — the lowest measured, on fewer and larger dispatches. Step 3 (design proposal) was deliberately skipped: Rabbit's row was already decided. |
| 2026-07-27 | cf1dad28 | gameplay-engineer | **Step 1** content data layer (3 schemas + 8 `.tres` + 7 grey-box scenes) | 196 | 51,753 | 9,154,525 | 702,992 | **754,941** | .2 | **THE FIRST MEASURED SYSTEMS-AGENT UNIT.** Schema authoring + data entry + hand-authored scenes in one dispatch. Absorbs discovering that `TerrainDefinition` was needed at all (→ D-26). Against the budget's ~900K/unit gameplay-systems assumption this is 0.84× — but see the caveat below before treating that as validation. |
| 2026-07-27 | cf1dad28 | qa-engineer | **Step 1** validation (5 suites, 161 assertions, negative controls) | 128 | 32,673 | 4,884,117 | 310,859 | **343,660** | .1 | 0.46× the build agent. Includes negative controls — deliberately breaking each expectation to prove the suites can go red. New practice, not overhead. |
| 2026-07-27 | cf1dad28 | gameplay-engineer | **Step 2** simulation spine (rows 3/4/5/6: grid, economy, capacity, qualification, arrivals, `human.tres`) | 210 | 84,217 | 15,180,774 | 1,015,002 | **1,099,429** | .3 | The causal spine: paint -> tags -> capacity -> qualification -> arrival -> move-in. Replaced the pilot-1 grid spike. |
| 2026-07-27 | cf1dad28 | ui-engineer | **Step 2** UI shell (rows 2/7: camera + 3 safety rails, three-mode tap model, HUD, fact card, Read-Aloud) | 228 | 85,557 | 12,644,910 | 404,790 | **490,575** | .2 | 9 scripts + 2 scenes. Cheapest of the three build agents despite comparable output — its brief could name an exact API instead of describing a system. |
| 2026-07-27 | cf1dad28 | qa-engineer | **Step 2** validation (9 suites, 367 assertions, negative controls) | 300 | 107,046 | 25,846,302 | 1,115,544 | **1,222,890** | .3 | **The most expensive single unit measured so far** — more than either build agent. Found the Rail 2 pillar-invariant defect. See the verification-cost finding below. |
| 2026-07-27 | cf1dad28 | ui-engineer | **Step 2** Rail 2 repair | 152 | 42,798 | 4,269,099 | 447,903 | **490,853** | .1 | Rejected its own first fix after a QA control assertion caught panning going dead at full zoom-out. |
| 2026-07-27 | cf1dad28 | qa-engineer | **Step 2** Rail 2 independent confirmation (281-point convexity probe, 3 negative controls) | 160 | 41,683 | 3,829,688 | 495,080 | **536,923** | .1 | Confirmed the fix; found the guarantee holds with ~0.000044 world units of float margin. |
| 2026-07-28 | cf1dad28 | gameplay-engineer | **Row 10** displacement mechanism + settlement window + removal/refund (rows 3, 10) | 18,768 | 79,130 | 17,221,783 | 873,895 | **971,793** | .3 | Ran **in parallel** with content-writer; directory-disjoint. Built row 10 plus its two unbuilt prerequisites. |
| 2026-07-28 | cf1dad28 | content-writer | **Row 10** displacement copy + **#31 villager fact card** + preview strings | 388 | 40,021 | 3,858,021 | 376,150 | **416,559** | .2 | **First content-pipeline unit since pilot 3b, and the cheapest build unit of Step 2/row 10.** Closed the release blocker. Verification was single-sourced — Nat Geo Kids' whole domain unreachable. |
| 2026-07-28 | cf1dad28 | ui-engineer | **Row 10** warning dialogue, Read-Aloud, departure/relocation moments, removal tool | 226 | 66,402 | 12,518,798 | 345,806 | **412,434** | .2 | Ran in parallel with qa. Resolved removal as a palette entry, not a fourth mode — the mode switch stays at 3. |
| 2026-07-28 | cf1dad28 | qa-engineer | **Row 10** validation (3 new suites + 8 edited, 288 new assertions) + re-point #31 tests | 332 | 116,046 | 27,041,067 | 694,699 | **811,077** | .3 | Again the most expensive unit of its wave. Mutation-verified every control and restored byte-identical (`diff -q`). |

## Methodology note — supersedes the earlier "split is unrecoverable" finding

The pilot-1 entry originally recorded that the input/output/cache-read split was **not
recoverable**, and posed a choice for pilots 2–3: (a) run each in a fresh session so
`/cost` yields the split, or (b) accept per-subagent totals and lose the detail.

**Both premises were wrong, and the question is moot.** `/cost` reports
subscription-level usage, not per-session token splits — so option (a) never worked
either. But Claude Code writes complete per-message `usage` objects to its session
transcripts, which means the full split is recoverable **exactly, per-agent, and
retroactively**:

```
~/.claude/projects/<slug>/<session-id>.jsonl          # main loop
~/.claude/projects/<slug>/<session-id>/subagents/
    agent-<id>.jsonl / agent-<id>.meta.json           # per subagent, typed + described
```

`docs/phase0/token-report.py` reads these. Consequences:

- Every number in the table above is measured, not estimated. The earlier pilot-1
  figures (35,761 build / 22,644 QA, then split 40/60 by guess) were **wrong by ~3×** —
  the real billable totals are 106,723 and 94,497.
- The harness's own end-of-run `subagent_tokens` figure understates badly: it reported
  41,697 for the pilot-2 ui-engineer whose actual billable was 104,807. Do not use it.
- **The one-work-unit-per-session rule in measurement.md is no longer necessary** for
  attribution. It is still useful for keeping human-hours attribution clean, but the
  token data no longer depends on it.

## Finding — orchestration overhead is roughly 1:1 with the work

Pilot 2 is the clean measurement (one agent, one unit, minimal noise):

| | billable |
|---|---|
| ui-engineer (the actual build) | 104,807 |
| main loop (brief-reading, dispatch, verification, ledger) | 126,009 |

**The main loop cost more than the agent it dispatched.** Pilot 1's session shows the
same shape at larger scale — 797,022 main loop against 856,482 across thirteen subagents.

This is the single most important input to the Token Budget extrapolation, and the
current template does not account for it. A per-unit estimate built from agent-only
figures **understates true cost by roughly 2×**. Recommended change to the extrapolation:
take the measured agent cost, then apply a ~1.0× orchestration multiplier *before* the
2.5× iteration factor and the 50% contingency.

Caveat on the pilot-2 main-loop figure: it absorbs the `[setup]` cost of building
`token-report.py` and the investigation behind this note. A clean pilot-2 orchestration
number would be lower — but pilot 1's independent ~1:1 ratio suggests the effect is real
and not an artifact of this detour.

## Toolchain note — pilot 2 (feeds API Constraints)

1. **`run_project` reports false success.** It returns "started in debug mode" on spawn,
   but the process dies immediately on display-server init (container lacks `libX11`,
   `libwayland-client`, `libfontconfig`); `get_debug_output` then reports "No active
   Godot process." The tool does not surface startup crashes. **Consequence: the
   run-and-observe lane in `mcp-setup.md`'s capability table is NOT available in this
   container** — the §D text-mode fallback is the real lane.
   Pilot 1's and pilot 3's done-criteria both say "verified via `run_project`" and need
   rewording. Worth revisiting how pilot 1's QA pass reported a clean `get_debug_output`
   run under the same constraint. **[Both questions answered in pilot 3 — see the
   validation-lane correction below. The `--headless --quit` half of this item was WRONG.]**
2. **`create_scene` is unusable for named roots.** It hardcodes the root node name to
   `root` and writes a non-standard `unique_id=` property into the node header. Scenes
   are authored as `.tscn` text instead — which mcp-setup already calls the normal
   complement, not a fallback.
3. Fontconfig warning on every headless invocation — cosmetic, no action.
4. **`/cost` does not answer the measurement question** — see methodology note above.

## Correction — the validation lane was wrong (pilot 3)

The pilot-2 toolchain note above named `--headless --quit` as "the real lane." Measured in
pilot 3, independently by two agents: **`--quit` is a parse check only. It does not import
assets and does not register global `class_name`s.**

The dangerous part is that it fails *green*. Against a project with a cleared `.godot/`,
`--quit` returned **exit 0**, and the immediately following `--script` run failed with
`Parse Error: Could not find base class "QATestCase"`. A CI gate built on `--quit` would
report clean on a project Godot had never successfully imported.

**The correct lane is `--import` first, then `--quit` or `--script`:**

```
godot --headless --path project --import    # actually imports; registers class_name
godot --headless --path project --quit      # parse check
godot --headless --path project --script res://tests/<test>.gd
```

**And this resolves the open pilot-1 question.** Pilot 1's done-criteria required "no script
errors in `get_debug_output`". With the process dying on display-server init,
`get_debug_output` returns "No active Godot process" — so **absence of output was read as
absence of errors.** Pilot 1's grid logic is probably sound (pilot 3's spawn test loaded
`Main.tscn` and it built its 256 tiles correctly, which is independent evidence), but its
stated verification method verified nothing. Both pilot briefs need their done-criteria
reworded off `run_project`.

## Finding — orchestration overhead is NOT a fixed multiplier (revises the finding above)

The ~1.0× orchestration multiplier recommended above was derived from pilots 1 and 2.
Pilot 3 contradicts it:

| pilot | agents | main loop | ratio |
|---|---|---|---|
| 1 | 856,482 (13 agents) | 797,022 | 0.93 : 1 |
| 2 | 104,807 (1 agent) | 126,009 | 1.20 : 1 |
| 3 | 1,488,707 (5 agents, 9 dispatches) | 901,339 | **0.60 : 1** |
| 3b | 1,329,931 (4 agents, 5 dispatches) | 247,348 | **0.19 : 1** |

**Orchestration is closer to a fixed cost per dispatch than a multiplier on agent work.**
Pilot 2 was one agent building one screen; pilot 3 was eight dispatches each doing
substantial independent work, so briefing-and-verifying amortized across far more agent
output. Applying a flat 1.0× to a full content-pipeline run would **overstate** it by
roughly 2× — the opposite of the error the original note was written to correct.

Revised guidance for the extrapolation: scale the orchestration term by *number of
dispatches*, not by agent tokens. Work units with many small dispatches carry proportionally
more; single-agent units like pilot 2 carry the most of all.

## Finding — human attention is ~0.1h per touchpoint, and latency is free (pilots 3/3b)

**The single most consequential finding for the 35–55-hour ceiling**, and it points the
opposite way to everything else in this ledger.

Agent dispatches ran tens of minutes of wall-clock each; several ran far longer. But the
human's actual involvement was **~0.1h (≈6 minutes) per touchpoint** — read the summary,
make the call, move on. The intervening time was spent on other work entirely.

**Waiting is not attention, and the hours budget is denominated in attention.** This is the
mechanism by which AI assistance actually helps here: it does not primarily reduce the human
hours per feature, it **converts human hours into wall-clock latency**, which the budget does
not charge for. A 40-minute dispatch the human ignores costs the project 0 hours.

**Phase-0 human attention, counted by touchpoint rather than by agent row:**

| touchpoint | count | ~hours |
|---|---|---|
| decision gates (a question answered, a value ruled) | ~6 | 0.6 |
| hands-on tasks (hand-carrying the 40 MB archive; editing the firewall allowlist twice) | ~3 | 0.3+ |
| review tasks (eyeball test) | 1 | 0.1 |
| **total, pilots 3 + 3b** | | **~1.0–1.2** |

Two full content-pipeline runs — including one failed audit, a species pivot, and a
first-of-kind license path — for roughly **one hour of human attention.**

**Caveats, so this is not read as more good news than it is:**

- **The compressibility is uneven.** Decision gates compress well because agents pre-digest
  them into a ruling. **Review tasks do not** — the picture-book eyeball test and source
  verification are irreducibly human, and the rabbit's eyeball test is still outstanding.
  Extrapolate review time separately, not at the gate rate.
- **Hands-on tasks are the expensive category** and they exist only because of environmental
  blockers. Every firewall gap converts directly into human minutes. This is why the
  firewall findings belong in the hours model, not just the token model.
- **Gate count is not constant per unit.** Pilot 3 needed four gates partly because the
  rabbit audit failed and forced a species decision mid-run. A clean run needs fewer.
- The `.1` figures are the human's own estimate, not stopwatch data. Precise enough for
  plausibility-checking, which is this budget's stated job.

**Consequence for the extrapolation:** at ~28–32 work units and even a generous 1.0h of
attention per unit (gates + eyeball + verification, well above the ~0.5h these two runs
averaged), phase 1–8 lands near **28–32 hours against a 35–55-hour ceiling** — with the
whole of phase 0 already spent. That closes, but not comfortably, and the margin lives
almost entirely in review time and in how many environmental blockers remain. It is a
plausibility check, not a forecast.

## Finding — the marginal cost of species #2 (pilot 3b) — THE number for the budget

Pilot 3b ran the same Add-an-Animal pipeline a second time, with all scaffolding in place.
This is the measurement Open Question #2 actually needs.

| | pilot 3 (Fox, first-of-kind) | pilot 3b (Rabbit, marginal) | ratio |
|---|---|---|---|
| agents | 1,488,707 | 1,329,931 | 0.89 |
| main loop | 901,339 | 247,348 | 0.27 |
| **total** | **2,390,046** | **1,577,279** | **0.66** |

**Species #2 cost 66% of species #1, not the ~25% the scaffolding argument predicted.** The
savings were real but smaller than expected, and they were partly offset. Do not extrapolate
the remaining roster at a quarter-cost.

**Where the savings actually landed:**

- **Data entry: 188,000 vs 315,561 (~⅓ of the fox's, and the fox's was itself the cheap
  per-species half of a mostly-`[setup]` dispatch).** `animal_definition.gd` needed **zero
  changes** to absorb a second species. This is the GDD's "adding content means filling out a
  data entry, not writing code" principle passing its first real test — the strongest single
  result in either pilot.
- **Orchestration: 0.19 : 1**, the lowest of any pilot, on fewer and larger dispatches.
- **Step 3 collapsed to zero** — Rabbit's row was already decided, so the design-proposal
  dispatch was skipped entirely. This is a genuine per-species variable: Monkey's row is a
  fresh proposal and will cost like the Fox's 94,958; the rest carry over and will not.

**Where the savings were eaten — all first-of-kind costs that recur only per-source, not
per-species:**

- **tech-art 628,887** — a full second-source audit (37 models across two new sites, to
  establish that animation, not rabbits, is the scarce resource) plus the project's first
  CC-BY attribution entry. A steady-state import from an already-audited pack is a fraction
  of this.
- **qa-engineer 241,348** — four brand-new suites. Species #3 rebaselines rather than authors.

**Honest read for the extrapolation:** two data points cannot pin a convergence curve. What
they support is a **floor and a ceiling**: a species from an already-audited, already-licensed
pack with a pre-decided roster row approaches the data-entry + copy + QA-rebaseline floor
(order 500k); a species needing a new source audit, a new license path, and a fresh design
proposal costs like pilot 3 (order 2.4M). Most of the remaining roster sits between, and
**five of the six remaining species can be sourced from the Quaternius archive already on
disk**, which pushes them toward the floor.

## Finding — verifying copy costs ~2.7× writing it (pilot 3), and ~0 if done in one pass (3b)

**Updated by pilot 3b.** The fox's 2.7× verification premium was an artifact of doing it
twice. With sources reachable from the start, the rabbit's copy step drafted *and* verified in
a single pass for **271,696** — against the fox's 199,421 split across a blocked draft
(54,260) and a later verification round (145,161).

So verification is not inherently 2.7× — **re-entering a finished task to verify it is.** The
correct guidance is: never run a content step with its sources blocked. A blocked step does not
save the verification cost, it defers it at a premium and ships a wrong artifact in the
meantime. Budget copy as one pass at roughly 270k per species.

The original finding's substance stands and is preserved below, because the *reason* it was
worth 145,161 tokens has not changed.

## Finding — the original verification premium (pilot 3)

The single most surprising number in this pilot. content-writer ran twice on the same fox
fact card — once to draft (sources blocked), once to verify (sources opened mid-session):

| | billable |
|---|---|
| drafting 4 fact-card options + a full News Report pool | 54,260 |
| verifying the ONE shipped option against sources | 145,161 |

**Verification cost 2.7× the drafting, for one-quarter of the output.** Per unit of copy the
ratio is closer to 10×. Drafting is cheap because a model already holds the material;
verification means fetching pages, reading them, and reasoning per-clause about whether a
specific sentence is actually supported.

**And it was worth every token.** The shipped card asserted "the whole family shares one cozy
den"; ADW states the male does not enter the maternity den. A second clause put kit play in
daylight when every source places fox activity at night and twilight. Both survived the
original four-step checklist, tone review, human sign-off, and 68 passing assertions — the
copy was *wrong and fully approved*. Only fetching the sources caught it.

Consequences for the budget:

- The fact-card line item in the extrapolation should be sized on **draft + verify**, not
  draft. Sizing on drafting alone understates copy by ~3.7×.
- This is per-species and does not amortize — each animal needs its own sources read.
- **Corollary for the GDD's content pipeline:** checklist step 1 ("approved source") is not a
  cheap box-tick performed while writing. It is the most expensive step in the copy pipeline
  and belongs in the cost model as its own line.

## Finding — the firewall is a per-unit HUMAN cost, not a token cost (pilot 3)

Two hard blocks, both discovered by running the pipeline rather than by reasoning about it:

1. **No asset can be downloaded.** Every Quaternius pack routes through `drive.google.com`,
   which the default-deny allowlist in `.devcontainer/habitown-firewall.sh` drops
   (`quaternius.com` itself is reachable only because it is GitHub Pages). `syntystore.com`
   and `quaternius.itch.io` are also blocked. Resolved this session by the human
   hand-carrying the archive. **Mitigable:** one archive covers 12 species, so carrying the
   remaining 11 now would amortize it to near zero.
2. **No fact-card source could be reached.** WWF, Nat Geo Kids, Smithsonian National Zoo,
   Wildlife Trusts, Wikipedia — all blocked. The GDD's fact-card checklist step 1 (approved
   source) could not be satisfied in-container at all, and pilot 3's copy shipped UNVERIFIED.
   **RESOLVED mid-session:** the human added `animaldiversity.org`, `nationalzoo.si.edu`,
   `wildlifetrusts.org` and `kids.nationalgeographic.com` to the allowlist (persisted to
   `habitown-firewall.sh`, so it survives a rebuild), plus `poly.pizza`, `kenney.nl`,
   `freesound.org` and the Godot domains. Verification then ran in-container and caught two
   factual errors — see the verification-cost finding above. **This converts a recurring
   human cost into a recurring token cost**, which is the better trade given the hours
   ceiling. Blocker 1 above is unchanged: `drive.google.com` is still blocked.

Consequence for the budget: these move the **human-hours** axis, not the token axis — and
human-hours is what the 35–55-hour ceiling is actually denominated in. The token figures in
this ledger therefore *understate* the true per-unit cost of a content pipeline run, in a
way no multiplier on tokens can capture.

## Process findings — agent coordination (pilots 3 and 3b)

Three failures of coordination, all caused by the orchestrator (the main session), all cheap
to prevent:

1. **Agents were directed to edit other agents' artifacts, and it destroyed test history.**
   The main loop told `gameplay-engineer` to update `test_fox_schema.gd` — QA's file — when the
   personality enum changed. Consequence: QA's recorded baseline was **31 assertions**, but by
   the time it was asked to rebaseline, the file reported 44/45 with ~14 assertions QA had not
   authored. QA could account for the 44↔45 oscillation completely but could not attest to the
   31→44 jump, because it did not make those edits. **Rule adopted: agents request changes to
   another agent's artifact rather than making them.** Costs one round-trip; buys a traceable
   test history.
2. **A brief asserted something globally true only locally.** The pilot-3b data-entry brief
   said `animal_definition.gd` was "unchanged, deliberately" — true of the rabbit pipeline, but
   the schema *had* changed earlier in the session (the personality enum→String ruling). QA
   caught and corrected it. Briefs that state project-wide facts must be scoped, or an agent
   will reason from a false premise it has no way to check.
3. **A green test suite stopped proving what it claimed.** After Rabbit landed,
   `test_fox_schema.gd` still passed — while asserting a comment that said Fox was the only
   species with a `.tres`. It tested real behavior against an explicitly-passed roster, so the
   assertions stayed true; the *claim* went stale. **A passing suite is not evidence its
   premises still hold.** Rebaseline tests when the world they describe changes.

A fourth, found by QA and worth generalizing beyond tests: **`check()` inside a loop over
variable-length data makes assertion counts data-dependent.** The fox suite's count moved
44↔45 with no file edit, because a loop over `validate()`'s output contributed one assertion
per problem found. An assertion count that moves on its own hides the one that moved for a
real reason.

## Finding — parallel dispatch into one Godot project is not free (pilot 3)

Two agents wrote to the same Godot project simultaneously (tech-art on `project/attribution/`,
gameplay-engineer on `project/data/` + `project/scripts/definitions/`). No conflict occurred,
but only because their directories happened to be disjoint. The shared surfaces — the global
`class_name` registry, the `.godot/` import cache, and `project.godot` — are exactly where a
real collision would land, and `--import` rewrites the class registry on every run. Wall-clock
savings from fanning out are real; treat directory-disjointness as a precondition, not luck.

## GDD gap — pilot 2

The Accessibility section specifies read-aloud and hints but **no tap-target or
font-size minimums**, so "big tap targets" had no number behind it. The ui-engineer
chose 480×104 px buttons at 48px text on its own authority. Proposed GDD addition:
minimum interactive target 96×96 px, minimum body text 32px at 1080p — otherwise every
subsequent UI screen re-invents the number.

## GDD gaps — pilot 3

Running one full content pipeline surfaced six schema/spec gaps. The pattern is worth
noting on its own: **every one was found by executing the pipeline, none by reading the
GDD.** This is the strongest argument for the pilot's existence.

1. **`AnimalDefinition` had no `scout_radius` field** — gdd.md:354 specifies a per-species
   home-site scoring radius (~8–12 tiles, "a fox ranges wider than a rabbit") but the
   schema table (gdd.md:518–529) has no row for it, which would have forced a code edit
   per species and broken the "content is a data entry, not code" promise. **Resolved:**
   human approved adding it; Fox set to 12. The GDD's schema table still needs the row.
2. **News Report copy has nowhere to land.** gdd.md:567 describes a per-animal text pool
   "reusing the fact-card pipeline," but no schema field exists. Step 5 produced hint,
   move-in, ambient, and relocation copy the schema cannot hold — and those fire at
   different moments, so a single flat pool would be wrong. **Open.**
3. **The behavior library's reaction vocabulary is unspecified.** The Add-an-Animal spec
   requires an audit to check "reaction-animation candidates," but nothing lists which
   reactions are needed, so the criterion cannot objectively pass or fail. Will recur on
   all 8 species. **Open.**
4. **gdd.md:208's own sample copy violates gdd.md:207's symmetry rule.** *"Rabbits prefer
   to keep their distance from foxes"* is one-directional, which is precisely how a
   predator-prey reading enters. Three independent agents flagged this. content-writer
   supplied symmetric replacements. **Open — one-line fix.**
5. **Tone-incompatible animations ship inside the assets.** The Fox glTF contains `Attack`
   and `Death` clips. Nothing currently prevents a random reaction-pool selector from
   reaching them. Whatever builds animation selection needs an explicit allow-list, not an
   index or a play-any-clip API. **Open.**
6. **The pattern-mask variation hook may not be buildable as specified.** gdd.md:319 treats
   coat tint, pattern mask, and ±10% size as equally cheap. The Fox model has **no UVs and
   no textures** (flat `baseColorFactor` materials), so tint and size are straightforward
   but a pattern mask would need UV authoring — asset creation, which is explicitly where
   the project has decided AI helps least. **Open.**

## Decisions taken during pilot 3 (need landing in gdd.md)

1. **`scout_radius` added to `AnimalDefinition`**; Fox set to 12 (top of gdd.md:354's ~8–12
   band). The GDD's schema table still needs the row.
2. **`personality` is a String, not an int enum** — `@export_enum("Shy", "Bold")`, so the
   `.tres` reads `personality = "Shy"` and self-documents. Trade-off recorded by the
   implementing agent: the type system no longer makes an invalid value impossible, so
   `validate()` is now load-bearing rather than a review convenience. Whatever loads the
   roster must call it.
3. **US English is the roster-wide register** — "kits", never "cubs". The US/UK split is real
   (US sources: kits/pups; UK: cubs) and would otherwise be re-litigated per species. Note
   this same call would have gone the *other* way on the rejected option C's "brush", a UK
   term — a silent inconsistency had C shipped.
4. **Rejected:** a proposed 5th checklist step ("does any clause assert something no source
   addresses?"). Worth revisiting if a second species hits the same failure mode — both of
   pilot 3's copy defects were assertions that outran their sourcing, which the existing four
   steps structurally cannot catch.

## Roster risk — carried forward from pilot 3

Rabbit failed the asset audit and has no source. It is the target of **both** avoids pairs
in the v1 roster (Rabbit↔Fox, Rabbit↔Leopard) and is the only 1-tag species — the easiest
first move-in and the bottom rung of the difficulty curve. If it is dropped with no
substitute, the avoids system ships with zero data in it.

**The audit failed Quaternius, not the world.** The GDD's hard gate (gdd.md:475) permits
escalation to Synty or the human/3D-artist fallback; neither was tried before the pivot.
A rabbit is among the cheapest possible low-poly models. Recommend re-auditing before
treating Rabbit's roster slot as lost.

**New since the pivot:** the firewall change opened `poly.pizza` and `kenney.nl`, both large
CC0 low-poly libraries that were unreachable when the audit ran. A rabbit in either would
restore the roster's only 1-tag species and give the avoids system its data back. Two caveats
before adopting one: they are outside the GDD's approved-source list (Quaternius primary,
Synty fallback), so using one is an Art Direction amendment; and a model aggregator is weaker
than a coherent pack on rig/animation consistency, which is exactly what the single-source
rule exists to protect. A re-audit would either recover Rabbit or yield a definitive "no CC0
rabbit exists in any reachable source" — a far stronger basis for a roster change than the
current "not in Quaternius".

## Finding — the first systems measurement, and why it does NOT validate the budget

**Step 1 (2026-07-27) is the first work unit outside the content pipeline that was measured
rather than extrapolated.** Two dispatches, ~1.10M billable tokens combined (754,941 build +
343,660 validation), ~0.3 human hours, delivering three schemas, eight data entries, seven
hand-authored scenes and five test suites. The suite went 29 → 34 green.

The tempting reading is that it lands at **0.84×** the budget's `~900K tokens/unit`
assumption for "Gameplay systems (phases 1–5)", and therefore the ~11.2M projection holds.
**Do not read it that way.** Three reasons:

1. **This unit is content-pipeline-shaped, not systems-shaped.** Schema authoring and data
   entry against a written spec is close to what pilot 3b measured for a species. The
   remaining systems rows are *algorithms* — a capacity evaluator, a dirty-neighbourhood
   queue, camera feel, a save format — with integration against existing code and, for rows
   2 and 6, a human taste gate that this unit did not have.
2. **It began with an unbudgeted discovery.** A significant share of the build agent's cost
   went into establishing that `TerrainDefinition` had to exist at all (→ D-26) — a
   contradiction between two decided rules that was invisible until someone implemented it.
   Later rows will surface their own; that class of cost is real and is not in any estimate.
3. **`.3` human hours is not the steady-state number.** Both dispatches were briefed from
   design docs that were freshly audited and unusually precise. The brief itself took longer
   to write than the review took to do — which is the orchestration-cost finding again, and
   argues for fewer, larger dispatches on the rows that follow.

**What it does establish:** the two-agent build→validate shape works, the agents respect
field-level tracker ownership without supervision (gameplay-engineer declined to write
`validation_status` and reported the staleness instead), and per-unit cost is in the right
order of magnitude rather than off by 5×.

**The number that will actually test the budget** is the first true Tier-1 row through all
five systems-pipeline steps — row 3 (Terraform) or row 6 (Habitat). Until one of those is
measured, the ~11.2M gameplay-systems line remains an extrapolation, and `actual_hours` in
[game-design/tier1-status.md](game-design/tier1-status.md) is where the correction gets
recorded for #30.

## Finding — the first real Tier-1 measurement, and verification is now the biggest line

**Step 2 (2026-07-27) delivered the walking skeleton** — Tier-1 rows 2, 3, 4, 5, 6 and 7 at thin form, the full causal path from a player edit to an animal moving in. Five dispatches across three agents, **~3.84M billable tokens**, ~1.0 human hour. Suite 34 → 43 green.

**Against the budget:** the projection allots `~900K/unit × 5 units ≈ 4.5M` for "Gameplay systems (phases 1–5)" before the ×2.5 iteration factor. Six rows landed for 3.84M. That is **broadly on-plan** — the first genuinely comparable data point the project has, and it does not blow the estimate up. Two caveats keep it honest: these are *thin* forms, and rows 1, 9, 10 and 13 are still unbuilt.

**The finding that actually matters: verification cost more than construction.**

| Unit | Billable |
|---|---|
| gameplay-engineer (simulation spine) | 1,099,429 |
| ui-engineer (UI shell) | 490,575 |
| **qa-engineer (validation)** | **1,222,890** |

QA was the single most expensive unit of the whole project to date — more than either agent whose work it validated, and 1.11× the larger of them. This echoes pilot 3's *"verifying copy costs ~2.7× writing it"*, now confirmed on code: **checking is not a cheap tail on building, and any estimate that prices QA as a percentage of build cost will be wrong.** The ~20% "QA + polish" line in the token budget is the specific thing this contradicts.

It also earned its cost. QA found the **Rail 2 pillar-invariant defect** (max zoom-out from a panned corner did not frame the world — the exact disorientation the rail exists to prevent), which no amount of building would have surfaced. The repair cycle then cost a further 1.03M across two dispatches — *more than the entire UI shell it was fixing* — which is the real price of a defect caught late rather than an argument against catching it.

**Two second-order observations worth carrying forward:**

1. **A brief that can name an API is dramatically cheaper than one that must describe a system.** ui-engineer's shell (490K) cost 45% of gameplay-engineer's spine (1.10M) for comparable output, and the difference was that its brief could hand it an exact method and signal list. Sequencing dispatches so each one inherits a concrete contract is worth real tokens.
2. **Negative controls paid for themselves twice.** ui-engineer rejected its own first Rail 2 fix because a QA control assertion caught panning going dead at full zoom-out — a regression that would otherwise have shipped as "fixed."

**Human hours: ~1.0 for six thin rows**, against a ledger estimate of 12.5–19h for rows 2–7. That gap is almost certainly optimistic rather than real — it excludes the taste gates (camera feel, habitat tuning) that gdd.md says *are* the work in rows 2 and 6, and which have not been run. `actual_hours` in tier1-status.md stays the number to watch at the velocity review.

## Finding — the first parallel dispatch, and the content pipeline is cheap

**Row 10 (Gentle Displacement) shipped as two parallel pairs**, the first time this project ran agents concurrently. **~2.61M billable, ~1.0 human hour**, against a 2–3 h ledger estimate. Suite 47 → 50 green, 1550 assertions.

**Parallelism worked, and the precondition is what made it safe.** gameplay-engineer (`scripts/{simulation,world,economy}/`) ran beside content-writer (`docs/content/`, `data/animals/`); ui-engineer (`scripts/ui/`) ran beside qa-engineer (`tests/`). Zero collisions. The directory claims in `tier1-status.md` were written for exactly this and paid off on first use — Technical Strategy #6's "treat directory-disjointness as a precondition" is now demonstrated rather than assumed.

**What it bought is wall-clock, not tokens** — as predicted. The two waves cost what four sequential dispatches would have. What it did *not* buy is human hours, which is the currency that binds (Technical Strategy #7). Useful when latency matters; irrelevant to the 35–55h budget.

**The content pipeline is far cheaper than the systems pipeline.** content-writer closed Open Question #31 — the release blocker — for **416K**, the cheapest build unit in either step, and 43% of gameplay-engineer's mechanism dispatch. This matters for planning: nine cleared-pool species are waiting on exactly this kind of unit, and the marginal cost looks closer to pilot 3b's rabbit than to a systems row. **The content half of the roster is cheap; the systems half is not.**

**QA remains the most expensive line, for the third wave running** (811K, vs 972K/416K/412K for the three build agents combined at 1.80M). Two waves ago it was *more* than any single builder; here it is second only to the mechanism. The pattern holds: **verification is a first-class cost, not a tail.** The token budget's "QA + polish ≈ 20% of subtotal" is now contradicted by three independent measurements.

**One process result worth keeping:** qa mutated the implementation to prove its negative controls, then restored it and confirmed byte-identity with `diff -q`. That is the discipline that makes a green suite mean something, and it costs almost nothing once it is habit.
