# Design Integrity Audit

**Date:** 2026-07-27 · **Auditor:** design-integrity (read-only) · **Scope:** `game-design/`,
`.claude/agents/`, `decisions.md`, `project/`

Method: the fourteen-assertion list, worked in order. Every finding below traces to a file and
line. `bash scripts/run-tests.sh` was run in full: **29 suites, 29 passed, 0 failed.** No
project file was modified; this report is the only file written.

Context read but deliberately not assumed correct: the agent-roster rework (D-23), the new
`systems-pipeline.md` / `tier1-status.md` / `release-checklist.md`, and the D-24 roster
change. Everything below is against what is on disk.

---

## 1 · Schema and data (assertions 1–5)

### S-1 — `capacity_radius` and `max_individuals` are contract fields with no code, and the code states the opposite design
**What.** Two fields the schema docs declare as `AnimalDefinition` fields have no `@export` in
`animal_definition.gd`, and the code does not merely lack them — it documents a contradictory
design decision.

**Where.**
- Documented: `game-design/spec.md:27` (`capacity_radius`), `spec.md:29` (`max_individuals`);
  `game-design/roster.md:37` and `roster.md:39`; `game-design/gdd.md:157` — *"The three
  per-species tuning constants (`capacity_radius`, `tiles_per_individual`, `max_individuals`)
  are `AnimalDefinition` fields"*; and `gdd.md:151`, where the v1 capacity formula is written
  in terms of `S.capacity_radius` and `S.max_individuals`.
- Code: `project/scripts/definitions/animal_definition.gd:85–127` exports ten fields —
  `id`, `display_name`, `habitat_needs`, `personality`, `avoids`, `farm_tolerant`,
  `scout_radius`, `tiles_per_individual`, `model_scene`, `fact_text`. Neither field is present.
- The contradiction, not just the absence — `animal_definition.gd:117–118`:
  > `## Capacity reuses `scout_radius` as its neighborhood radius — there is deliberately`
  > `## no second radius field.`

This is why it is drift rather than doc-ahead-of-code: the code asserts a design ("deliberately
no second radius field") that `spec.md:27` and `gdd.md:157` both decide the other way, and
`gdd.md:151`'s formula cannot be implemented against the shipped schema as written.
`tier1-status.md:192` already records this as a row-6 prerequisite, so the tracker agrees.

**Severity.** MAJOR — a gameplay-engineer dispatched on row 6 reads two opposite instructions.

**Owner.** The human decides which is right (it is a schema/tuning call); gameplay-engineer
owns the resulting edit to `animal_definition.gd`.

**Reverse direction of assertion 1 is clean:** every `@export` in `animal_definition.gd` has a
matching row in `spec.md`'s AnimalDefinition table. No orphan code fields.

**Not a finding:** `PlaceableDefinition` (`spec.md:35–44`) and `HarvestableTileDefinition`
(`spec.md:48–56`) have no `project/scripts/definitions/*.gd` at all. That is expected Phase-0
doc-ahead-of-code and is recorded honestly at `tier1-status.md:162` and `tier1-status.md:147`.

---

### S-2 — `tiles_per_individual`: three sources, two different values — an open gate, stated as settled in two of them
**What.** `roster.md` says Human 1 / Fox 5 / Rabbit 4; the shipped `.tres` files and
`content-pipeline-status.md` say 12 for both Fox and Rabbit.

**Where.**
- `game-design/roster.md:47–48` — *"Floor placeholders for the three tuning constants … Human 1,
  Fox 5, Rabbit 4"*; repeated unmarked and in bold in the Already-Defined table at
  `roster.md:115` (Rabbit **4**) and `roster.md:116` (Fox **5**).
- `project/data/animals/fox.tres` — `tiles_per_individual = 12`;
  `project/data/animals/rabbit.tres` — `tiles_per_individual = 12`.
- `game-design/content-pipeline-status.md:155` and `:170` — *"`tiles_per_individual` 12"*, with
  no marker.

**This is an open gate, not a defect.** The gate is **Open Question #6** (`spec.md:163`,
"per-tag thresholds and the `tiles_per_individual` values"), tracked at
`game-design/tier1-status.md:190` under row 6 `constants`, which names the split explicitly:
*"roster.md proposes Human 1 / Fox 5 / Rabbit 4, shipped `.tres` hold the uniform placeholder
12 — both are unclosed and they close together here."*

**The reportable part** is that neither of the two places a reader lands first carries a marker.
`gameplay-engineer.md:45–49` requires a step-3 proposal written into `roster.md` to be prefixed
`PROPOSED (YYYY-MM-DD) —` and says *"Never write an unmarked design value into a design doc"*;
`roster.md:115–116` presents 4 and 5 in the bold "floor roster" style used for decided values,
and `content-pipeline-status.md:155/:170` state 12 as bare fact. Only `tier1-status.md:190`
tells the reader either number is provisional.

**Severity.** MINOR as drift (the gate is correctly named once); MAJOR risk if the marker
convention is not applied, because an agent reading only `roster.md` will treat 4/5 as decided.

**Owner.** The human (the value); gameplay-engineer and tech-art own the marker on their
respective tracker/roster fields.

---

### S-3 — `capacity_radius` and `max_individuals` have no value in any data file
**What.** Both constants have floor placeholders in `roster.md` and no representation anywhere
in shipped data, because the fields do not exist (S-1).

**Where.** `game-design/roster.md:47–48` — *"`capacity_radius` = `scout_radius` (~8–12 tiles)
… `max_individuals` ~6"*; absent from `project/data/animals/fox.tres` and `rabbit.tres`.

**Open gate**, correctly named: **Open Question #23** (`spec.md:176`) for `capacity_radius`,
and `max_individuals` is carried in the same row-6 constants block at `tier1-status.md:190`.
Reported here for completeness of assertion 2, not as a defect independent of S-1.

**Severity.** MINOR (open gate). **Owner.** The human.

---

### S-4 — `scout_radius` agrees everywhere
No conflict. `fox.tres` = 12, `rabbit.tres` = 8; both inside the ~8–12 band stated at
`spec.md:26` and Open Question #20 (`spec.md:175`). Neither `roster.md` nor
`content-pipeline-status.md` states a per-species value that could disagree, and
`animal_definition.gd:211–212` enforces the band. **Clean.**

---

### S-5 — `BARE_TAGS` is a non-empty hardcoded literal, and the test suite now enforces that
**What.** `spec.md` states the inert-land invariant is structural — `BARE_TAGS` is *empty by
construction* and must be *derived at validation time, never hardcoded*. The shipped code
hardcodes a two-element literal, and the regression test asserts that the literal is non-empty.

**Where — the two passages that disagree.**
- `game-design/spec.md:61`:
  > *"…so `BARE_TAGS` — the set of tags untouched land emits — is **empty by construction** …
  > it derives `BARE_TAGS` **from the tag-source mapping at validation time, never hardcoded**
  > — otherwise the check silently rots the first time tag emission changes"*
- `project/scripts/definitions/animal_definition.gd:60`:
  > `const BARE_TAGS: PackedStringArray = ["open_grass", "quiet"]`

**Aggravating factor — the harness locks in the wrong state.**
`project/tests/test_inert_land_invariant.gd:41`:
> `check(AnimalDefinition.BARE_TAGS.size() > 0, "BARE_TAGS is non-empty")`

The suite now *requires* the condition `spec.md:61` says must not hold. This is precisely the
"silently rots" failure the spec passage was written to prevent, and it is green today
(29/29 pass), so nothing else will surface it.

**Two corroborating passages on the docs' side.** `game-design/terrain.md:78` — wild grass
emits *"nothing — tag-inert"*, with no source anywhere in that table emitting `quiet`;
`game-design/gdd.md:186` — revealed land *"comes up wild grass: visually grass-family,
tag-inert."* And the code's own stated gate has closed: `animal_definition.gd:45` marks
`BARE_TAGS` as *"PLACEHOLDER pending Open Question #5"*, but `spec.md:162` records #5 as
*narrowed* — the v1 source table is **decided** — leaving only radii, weights, and weak `cover`
open. Nothing in the still-open part of #5 justifies a non-empty bare set.

The code comment at `animal_definition.gd:51–55` already says "MUST BECOME DERIVED", so the
intent is on record; what is drift is that the shipped constant, the shipped validator, and the
shipped test all now encode the opposite of the spec's stated invariant.

**Severity.** BLOCKING — it breaks a stated invariant (`spec.md:61`, D-22 at
`decisions.md:182`, which says the bare set is *"derived at validation time rather than
hardcoded"*), and the guard that was supposed to catch the breakage asserts it instead.

**Owner.** gameplay-engineer (`animal_definition.gd`) and qa-engineer
(`test_inert_land_invariant.gd:41`); the human confirms the derivation source once terrain
definitions exist.

---

### S-6 — Habitat tag vocabulary: identical in all four places
Ten tags — `water`, `forest`, `open_grass`, `quiet`, `cover`, `flowers`, `sand`, `rocks`,
`cultivated`, `house` — same set, same count, same order in `game-design/gdd.md:158` and
`gdd.md:236`, `game-design/spec.md:60`, `game-design/terrain.md:63–64`, and
`HABITAT_TAGS` at `project/scripts/definitions/animal_definition.gd:32–43`. **Assertion 4
passes clean.**

---

### S-7 — No `PROPOSED` / `PLACEHOLDER` marker has reached a shipped `.tres`
All eight `.tres` on disk (`project/data/animals/{fox,rabbit}.tres` and the six
`project/attribution/sources/*.tres`) are free of both markers. `animal_definition.gd:222`
additionally rejects a `fact_text` beginning with `PLACEHOLDER`. **Assertion 5 passes clean.**

---

### S-8 — The fact-card checklist is four steps in code and data, five steps in the design docs — and there are two different "fifth steps" in circulation
**What.** The checklist length disagrees across docs, code, and shipped data, and the
disagreement lands on the one step that governs the project's only `avoids` pair.

**Where.**
- Five, in the design layer: `game-design/spec.md:68` — *"The same **five-step** checklist
  repeats for every animal added post-class"*; `game-design/gdd.md:182` — *"source-verified
  through the **five-step** checklist"*; `.claude/agents/content-writer.md:34` — a numbered
  five-step list whose step 5 is the **graph check**.
- Four, in the code and data layer: `project/scripts/definitions/animal_definition.gd:125–126`
  — *"Must clear the **four-step** checklist … (approved source -> 1-2 sentences -> tone check
  -> predation check)"*; `project/data/animals/fox.tres:11` — *"All **four** checklist steps
  now SATISFIED"*; `project/data/animals/rabbit.tres:21` — *"cleared **ALL FOUR** checklist
  steps"*; `game-design/content-pipeline-status.md:160` and `:175` — *"cleared all four
  checklist steps"* / *"all four checklist steps now satisfied"*.
- A third position: `decisions.md:157` (D-19) records the fifth step as *"**Proposed** fifth
  checklist step, **deferred**"* — and defines it as *"does any clause assert something no
  source addresses?"*, which is **not** the graph check that `content-writer.md:42–45` and
  `spec.md:68` install as step 5. Two different fifth steps are live under one name.

**Why it matters concretely.** `content-writer.md:42–45` requires the graph check *"for any
species carrying an `avoids` entry"*. Fox and Rabbit are the only species with `avoids` entries
in the project, and their provenance records — the two `.tres` headers and both
`copy_content_location` rows — assert four steps, so the graph check is not recorded as having
run on either.

**Severity.** MAJOR — a content-writer reading the shipped provenance concludes the copy
cleared the checklist as currently defined, and it does not say so.

**Owner.** content-writer (`copy_content_location` rows and the `.tres` headers); the human for
D-19's status and for which fifth step is the real one; gameplay-engineer for
`animal_definition.gd:125`.

---

### S-9 — Numbers stated in more than one place that disagree
Three, all citable, none tuning-critical:

1. **Roster size.** `game-design/roster.md:19–20` — *"It ships **8 species** — floor: 3
   (Human, Fox, Rabbit)"* — contradicts `roster.md:142` twenty-three lines later (*"the roster
   has **no fixed target number**"*), `game-design/gdd.md:184` (*"has no target number"*),
   `game-design/spec.md:161` (*"the roster has **no target count** (→ D-24)"*), and D-24 itself
   at `decisions.md:200` (*"The '8 species' target is **retired**"*). A doc contradicting itself
   and three others. **Severity: MAJOR.** **Owner: the human** (roster.md is a design doc).
2. **Terrain count in the accepted residual.** `decisions.md:175` (D-21) — *"three species,
   **four terrains**, a 1×1 house"* — vs `game-design/gdd.md:331` and `gdd.md:130` and the
   ledger at `gdd.md:339`, all *five terrains*, matching `terrain.md:97` (grass, water, forest,
   rock, cultivated). **Severity: MINOR.** **Owner: the human.**
3. **Work-unit count.** `game-design/gdd.md:252` and `decisions.md:189` say *"~28 discrete work
   units"*; `game-design/spec.md:183` (#30) and `decisions.md:165` say *"~30 work units"*.
   **Severity: MINOR.** **Owner: the human.**

---

## 2 · References and structure (assertions 6–10)

### R-1 — Every `gdd.md:NNN` line-number citation in shipped code and data is now stale
**What.** The GDD restructure left ~18 hard line-number citations pointing at blank lines,
unrelated paragraphs, or past the end of the file. `gdd.md` is 378 lines.

**Where.**

| Citation | Cited from | What `gdd.md` actually holds there |
|---|---|---|
| `gdd.md:203` | `animal_definition.gd:150` | blank line |
| `gdd.md:207` | `animal_definition.gd:63`, `:104`; `test_fox_schema.gd:131`; `test_rabbit_schema.gd:129`, `:135` | blank line |
| `gdd.md:324` | `rabbit.tres:2`; `test_rabbit_schema.gd:4` | blank line |
| `gdd.md:326` | `rabbit.tres:13` | blank line |
| `gdd.md:329` | `fox.tres:2`; `test_fox_schema.gd:4` | "**Known thinnesses for the velocity review.**" |
| `gdd.md:354` | `animal_definition.gd:70`, `:112`, **`:212`**; `test_fox_schema.gd:81`; `test_rabbit_schema.gd:73` | the hours-ledger sentence about `actual_hours` |
| `gdd.md:518` | `test_fox_schema.gd:3`; `test_rabbit_schema.gd:3` | past end of file |
| `gdd.md:670` | `test_rabbit_schema.gd:76` | past end of file |
| `gdd.md:33` | `test_fox_schema.gd:106` | Executive Summary paragraph, not the predation ban |

**Worst instance.** `animal_definition.gd:212` emits the stale pointer in a runtime validation
*failure message*:
```gdscript
problems.append("`scout_radius` %d sits outside the GDD's ~8-12 tile band (gdd.md:354)." % scout_radius)
```
The ~8–12 band no longer appears in `gdd.md` at all — it lives at `game-design/spec.md:26` and
Open Question #20 (`spec.md:175`). A developer following that message lands on the hours ledger.

**Severity.** MAJOR — a reader or agent following any of these lands somewhere wrong, and one
of them is baked into a shipped diagnostic string.

**Owner.** gameplay-engineer (`animal_definition.gd`, the two schema tests); content-writer or
gameplay-engineer for the two `.tres` headers.

---

### R-2 — `gdd.md -> Data Schemas` is cited eight times; `gdd.md` has no Data Schemas section
**What.** The section moved to `spec.md` in the restructure. `grep -n "Data Schemas"
game-design/gdd.md` returns nothing.

**Where.** `project/scripts/definitions/animal_definition.gd:4` (*"see gdd.md -> Data Schemas /
Content Architecture"*), `:28`, `:48`; `project/tests/test_inert_land_invariant.gd:2`;
`project/tests/test_fox_schema.gd:3`; `project/tests/test_rabbit_schema.gd:3`;
`project/data/animals/fox.tres:1`; `project/data/animals/rabbit.tres:1`; and `decisions.md:151`
(D-19, *"the fact-card checklist and register rules in gdd.md → Data Schemas"*). The correct
target in every case is `game-design/spec.md` → **Data Schemas**.

**Severity.** MAJOR — this is the single most-cited pointer in the codebase and it resolves to
nothing.

**Owner.** gameplay-engineer (code and tests), content-writer (`.tres` headers), the human
(`decisions.md`).

---

### R-3 — `decisions.md`'s own relative links do not resolve
**What.** `decisions.md` sits at the repo root but links as if it sat in `game-design/`.

**Where.** `decisions.md:3` — `[gdd.md](gdd.md)`; `decisions.md:49`, `:60`, `:77`, `:208` —
`[future.md](future.md)`. The real paths are `game-design/gdd.md` and `game-design/future.md`.
Five broken links; no other `.md` under `game-design/` or `.claude/agents/` has a broken link.

**Severity.** MAJOR — `decisions.md` is named as ground truth in `.claude/CLAUDE.md:24` and in
this auditor's own brief.

**Owner.** The human.

---

### R-4 — Three `decisions.md` section-path citations name `gdd.md` headings that no longer exist
**Where.**
- `decisions.md:160` (D-20) — *"gdd.md → Technical Strategy → **API Constraints**"*; the
  subsection is **"Constraints, measured rather than assumed"** (`gdd.md:242`).
- `decisions.md:171` (D-21) — *"gdd.md → Plan → **Scope Tiers** → Tier 1 depth rule"*; the
  section is **"Scope: the floor and the depth"** (`gdd.md:297`).
- `decisions.md:151` (D-19) — *"gdd.md → Data Schemas"* (covered by R-2).

**Severity.** MINOR — stale wording, resolvable by a reader who searches.
**Owner.** The human.

---

### R-5 — `rabbit.tres` justifies a live terminology rule with a retired roster member
**What.** The rule ("never *kittens*") may still be correct, but its stated reason is dead data.

**Where.** `project/data/animals/rabbit.tres:12–13`:
> `; the shipped Fox card, which uses "kits" for fox young. Never "kittens" — that collides`
> `; with Cat on the roster (gdd.md:326).`

Cat is **not a roster member** (D-24, `decisions.md:200`: *"Cat, Monkey and Leopard are not
roster members … They carry no row in `roster.md` or `content-pipeline-status.md`"*) and now
appears only on the Sourcing Watch-List at `game-design/art.md:120`. The line-number citation is
also stale (R-1). The same reasoning survives correctly in `decisions.md:154`.

**Severity.** MINOR. **Owner.** content-writer.

---

### R-6 — Assertion 7 passes clean
Every `gdd.md` section name cited by an agent definition exists:
`content-writer.md:11–14` → **Game Mechanics → World & Cast** (`gdd.md:180`), **Game Mechanics →
Systems in Play** (`gdd.md:141`), **AI Architecture → Content Pipelines** (`gdd.md:216`), and
**Systems in Play → Compatibility** (`gdd.md:164`); `gameplay-engineer.md:11–13` → **Game
Mechanics**, **Systems in Play**, **Player Interface & Controls** (`gdd.md:99`);
`qa-engineer.md:12` → **Technical Overview** (`gdd.md:190`); `tech-art.md:12–14` → **Game
Features** (`gdd.md:73`), **AI Architecture → Content Pipelines**; `ui-engineer.md:12–14` →
**Player Interface & Controls**, **Game Features**. The `spec.md` sections they cite (**Data
Schemas**, **Pacing Constants**, **Screen Layouts**, **Fact-Card Content Checklist**) all exist
too. **Clean.**

---

### R-7 — Assertion 6 is otherwise clean; no live doc links into `archive/`
All relative markdown links in `.claude/agents/*.md` and `game-design/*.md` resolve — including
`gdd.md:364` → `../docs/playtests/protocol.md`, `content-pipeline-status.md:18` →
`../godot/assets/ASSET_AUDIT.md`, and all twenty-two agent-to-doc cross-links. **No live doc
contains a link into `archive/`**; the only mentions of `archive/` are the exclusion rules at
`.claude/CLAUDE.md:4` and `design-integrity.md:21,46,53`. The only broken links found anywhere
in scope are R-3's, in `decisions.md`.

---

### R-8 — Assertion 8 passes clean
Every `#NN` open-question citation across `game-design/*.md`, `.claude/agents/*.md`,
`decisions.md`, `animal_definition.gd`, and both animal `.tres` resolves to a row in
`spec.md`'s Open Questions table (rows 4–13, 16–20, 23–31). The only two apparent misses are
not OQ citations: `asset-import-pipeline.md:32` cites *"gdd.md's Technical Strategy #3"* (the
numbered constraints list at `gdd.md:244–250`) and `spec.md:157` refers to *"Closed items #1–3"*
as omitted by design. `D-01` … `D-24` are all present in `decisions.md`, each exactly once as a
`### D-NN` heading — no duplicates — and every `D-NN` cited from code or docs (`D-17`, `D-18`,
`D-19`, `D-22`, `D-24`, cited from `animal_definition.gd:48`, `tier1-status.md:189,294`,
`test_rabbit_schema.gd:118,138`, `art.md:106`, `content-writer.md:48`) exists.

---

### R-9 — Assertion 9 passes clean
`gdd.md:206` claims *"five build agents … A sixth, **Design Integrity**, is read-only"* — six
total. `ls .claude/agents/*.md | wc -l` = **6**. The five build agents named at `gdd.md:208–212`
each have a file (`gameplay-engineer.md`, `ui-engineer.md`, `tech-art.md`, `content-writer.md`,
`qa-engineer.md`), plus `design-integrity.md`. `gdd.md:240` and `gdd.md:363` restate "five build
agents" consistently, and every agent file's own self-description says "one of five development
agents". The retired `lead-game-designer` (D-23, `decisions.md:195`) has no file and is
referenced from no live doc.

---

### R-10 — Assertion 10 passes clean
`game-design/` contains exactly one GDD file: `gdd.md`. The stale full copies are all under
`archive/` (`archive/gdd.md`, `archive/gdd.v2.md`, `archive/gdd.raw.md`,
`archive/gdd.notes.md`, `archive/gdd.template.md`, `archive/gdd.template.revised.md`,
`archive/gdd-one/gdd.trimmed.md`, `archive/gdd-one/gdd.raw.md`), where they belong and where
nothing live cites them.

---

## 3 · Trackers (assertions 11–13)

### T-1 — `fox` shows ✅ with no recorded human sign-off
**What.** The item's own `human_signoff` field states that no sign-off is recorded, while the
item shows ✅ in both places.

**Where — the two passages that disagree, in one file.**
- `game-design/content-pipeline-status.md:178` (`human_signoff`):
  > *"register decision logged ("kits," never "cubs") but **no explicit sign-off date/name** —
  > flagged for human backfill"*
- `content-pipeline-status.md:179` (`status`) = **✅**, and the scan table at
  `content-pipeline-status.md:115` = **✅**.
- The rule it breaks, stated by the same file at `content-pipeline-status.md:33–34`:
  > *"the one hard rule is that it can only show ✅ once `human_signoff` is actually recorded"*
- And restated as a ship gate at `game-design/release-checklist.md:53–54`.

**Severity.** MAJOR — `release-checklist.md` Gate 4 fails on this today, and ✅ is the glyph the
velocity review will read as "done, gated".

**Owner.** The human (`human_signoff` is human-exclusive by that file's own write-owner table).

---

### T-2 — `rabbit` shows ✅ on a sign-off that is asserted but not recorded
**What.** Same rule, weaker case: a sign-off event is claimed, but only by reference to a
comment inside a data file, with no date or name in the tracker.

**Where.** `content-pipeline-status.md:163` (`human_signoff`):
> *"`fact_text` recorded as "picked by the human at step-8 sign-off" in `rabbit.tres`'s own
> comments — **exact date/name not logged pre-tracker, flagged for human backfill**"*

against `content-pipeline-status.md:164` (`status` ✅) and the scan table at `:114` (✅), under
the same hard rule at `:33–34`. `release-checklist.md:8` names this exact failure mode — an
obligation *"recorded only in a `.tres` comment where nobody would look for it."*

**Severity.** MAJOR (same gate as T-1, marginally better evidence).
**Owner.** The human.

---

### T-3 — `rabbit`'s ✅ means "all 8 steps complete" while its own attribution row says a license condition is unmet
**What.** The glyph legend and the item's own text pull in different directions.

**Where.** `content-pipeline-status.md:67` defines ✅ as *"all 8 pipeline steps complete, human
sign-off recorded, live in project"*. `content-pipeline-status.md:161`
(`attribution_status`, marked *done*) says:
> *"the in-game Credits *screen* (row 15, UI Engineer scope) doesn't exist yet — the license's
> "visible to the player" condition **isn't satisfied until that ships**"*

**This is disclosed, not concealed** — it is tracked at `release-checklist.md:31–36` as *the*
release blocker, at `tier1-status.md:332`, and in `ui-engineer.md:34–40`. The finding is only
that the ✅ overstates it at scan-table glance.

**Severity.** MINOR. **Owner.** The human.

---

### T-4 — Scan-table/status agreement: clean in both trackers
- **`content-pipeline-status.md`:** all fourteen roster scan rows (`:114–127`) match their
  per-item `status` rows; all six terrain rows (`:367–372`) match (`grass` `:394`, `water`
  `:409`, `forest` `:424`, `rock` `:439`, `cultivated_field` `:454`, `sand` `:469`); the single
  building row (`:477`) matches `:492`.
- **`tier1-status.md`:** all fifteen scan glyphs (`:75–89`) match their row `status` fields
  (rows 1–15 at `:122, :137, :152, :167, :182, :197, :212, :227, :242, :257, :272, :287, :302,
  :317, :332`). No row shows ✅, so the sign-off rule at `tier1-status.md:22` is not exercised.
  The file's own tally at `:340` — *"0 rows ✅, 8 rows 🚧, 7 rows ⬜"* — is arithmetically
  correct.

**The glyph half of assertion 11 passes clean in both files.** The ✅-without-sign-off half
fails in `content-pipeline-status.md` only (T-1, T-2).

---

### T-5 — `tier1-status.md` renames row 8 against a table it says it only quotes
**What.** Row 8 is called *"The decided roster"*; `gdd.md` and `spec.md` both call it *"The
floor roster"*, and *"decided roster"* is the framing D-24 retired.

**Where.** `game-design/tier1-status.md:82` (scan table) and `tier1-status.md:214` (row
heading) — *"The decided roster"* — vs `game-design/gdd.md:316` and `game-design/spec.md:144`,
both *"The floor roster"*. The file's own constraint, `tier1-status.md:13`: *"`thin_form` quotes
gdd.md's table; **it never extends it**."* The row's `thin_form` text itself (`:218`) is a
faithful quote; only the name diverges.

**Severity.** MINOR. **Owner.** The human.

---

### T-6 — `content-pipeline-status.md`'s "seeded as of" date predates content it already contains
**Where.** `content-pipeline-status.md:36` — *"Every entry below was seeded against actual
current repo state … as of **2026-07-26**"* — but the file already carries the 2026-07-27 D-24
changes: the `class` column (`:112–127`), the cleared-pool framing (`:106–110`), and the absence
of Cat/Monkey/Leopard rows, all dated 2026-07-27 at `decisions.md:200` and `art.md:106`.

**Severity.** MINOR. **Owner.** tech-art or the human.

---

### T-7 — Assertion 12 passes clean
Every tracker path that claims to exist, exists. Verified on disk:

- **`project_location`** — all 22: `rabbit/Rabbit.tscn`, `fox/Fox.tscn`,
  `human_adventurer/Adventurer.tscn` + the four sibling variant directories,
  `deer/Deer.tscn`, `stag/Stag.tscn`, `horse/Horse.tscn`, `donkey/Donkey.tscn`,
  `cow/Cow.tscn`, `bull/Bull.tscn`, `alpaca/Alpaca.tscn`, `husky/Husky.tscn`,
  `shiba_inu/ShibaInu.tscn`, `grass_common_short/GrassCommonShort.tscn`,
  `grass_common_tall/GrassCommonTall.tscn`, `common_tree_1/CommonTree1.tscn`,
  `common_tree_2/CommonTree2.tscn`, `rock_1/Rock1.tscn`, `buildings/house/House.tscn`.
- **`data_entry_location`** — `project/data/animals/fox.tres`, `rabbit.tres`
  (`content-pipeline-status.md:159`, `:174`; `tier1-status.md:221`).
- **`validation_status` test files** — every named suite exists **and passes**. Full run:
  `bash scripts/run-tests.sh` → *"Suites: 29 total, 29 passed, 0 failed."* This covers
  `test_rabbit_schema`, `test_rabbit_animations`, `test_rabbit_spawn`, `test_fox_schema`,
  `test_fox_animations`, `test_fox_spawn`, `test_inert_land_invariant`, `test_attribution`,
  `test_human_adventurer_import` + 4 siblings, the nine cleared-pool animation suites, the four
  terrain import suites, `test_rock_1_import`, `test_house_import`, `test_den_import`.
- **`tier1-status.md` "Existing:" claims** — `project/scenes/TitleScreen.tscn`,
  `project/scripts/title_screen.gd` (`:116`), `project/scripts/camera_rig.gd` (`:131`),
  `project/scripts/grid_manager.gd` (`:146`),
  `project/scripts/definitions/animal_definition.gd` (`:191`),
  `project/attribution/generate_credits.gd` (`:326`),
  `project/assets/buildings/house/House.tscn` (`:167`). The line counts the tracker quotes are
  accurate too: `camera_rig.gd` is 18 lines (`:137`), `grid_manager.gd` is 141 (`:152`).
- **`docs/content/` copy** — `fox-news-report-pool.md` and `rabbit-news-report-pool.md` exist
  as claimed at `tier1-status.md:287` and `content-writer.md:22`.

**Not findings.** `project/scripts/{world,simulation,economy,save,ui,audio}/`,
`project/scenes/ui/`, `project/data/{terrain,buildings}/`, `project/data/animals/human.tres`,
and `project/assets/audio/` do not exist — but each is labelled *"reserved, not yet created"*
(`tier1-status.md:96`) or *"not started"*, and the field's own definition at
`tier1-status.md:61` requires `implementation_location` be **declared before building**. A
non-existent reserved directory is the specified state, not drift. Likewise the tracker's
negative claims are all accurate: `project/data/terrain/` (`:152`), `project/data/buildings/`
(`:162`), and `project/assets/audio/` (`:317`) genuinely do not exist.

---

### T-8 — Assertion 13 passes clean: directory-disjointness holds
No two rows with different `owner_agent` claim the same `implementation_location` directory
(`tier1-status.md:98–105`, owners from the scan table `:75–89`):

| Directory | Rows | Owner(s) |
|---|---|---|
| `project/scripts/world/` | 3, 13 | gameplay-engineer only |
| `project/scripts/simulation/` | 6, 9, 10 | gameplay-engineer only |
| `project/scripts/economy/` | 4, 5 | gameplay-engineer only |
| `project/scripts/save/` | 1 | gameplay-engineer |
| `project/scripts/ui/` + `project/scenes/ui/` | 2, 7, 11, 12, 15 | ui-engineer only |
| `project/scripts/audio/` | 14 | tech-art |
| `project/data/animals/` | 8 | content pipeline |

The precondition `gdd.md:249` (Technical Strategy #6) and `systems-pipeline.md:60–63` depend on
is satisfied.

---

## 4 · Licensing (assertion 14)

### L-1 — Assertion 14 passes clean
All six `project/attribution/sources/*.tres` appear in `project/CREDITS.md`:
`quaternius_poly_pizza_characters` (→ "Standalone Character Models"),
`quaternius_stylized_nature_megakit`, `quaternius_ultimate_animated_animals`,
`quaternius_ultimate_fantasy_rts`, `quaternius_ultimate_nature_pack`, `sherkiz_rabbit`. The
obligation summary table lists exactly six rows.

Exactly one entry sets `attribution_required = true` —
`project/attribution/sources/sherkiz_rabbit.tres:17` — and it carries a non-empty
`required_notice` (`:18`), rendered verbatim into `CREDITS.md` under **Required attributions**.
The other five set `attribution_required = false` with `required_notice = ""`, which is correct
for CC0. `test_attribution.gd` passes and asserts the same shape (6 sources, 1 binding
obligation, the CC BY fragment surviving into `CREDITS.md`).

---

### L-2 — The generated Credits file, and the generator, still call the game "Habitat Town"
**What.** The project's own license record ships under the retired project name, and
regenerating it will not fix that because the string is hardcoded in the generator.

**Where.**
- `project/CREDITS.md:8` — *"**Habitat Town** is built on third-party asset packs. This file is
  the auditable record of what we use and under what terms."*
- `project/attribution/generate_credits.gd:109`:
  ```gdscript
  s += "Habitat Town is built on third-party asset packs. This file is the auditable\n"
  ```
- Contradicted by `.claude/CLAUDE.md:1` (*"This is a game called Wildhaven."*),
  `game-design/gdd.md:1`, and every agent definition.
- Why it reaches the player: `.claude/agents/ui-engineer.md:39–40` and
  `game-design/release-checklist.md:35–36` both require the in-game Credits screen to read *"the
  same `AttributionEntry` `.tres` files the generator does, so the two cannot drift"* — the
  wrong title is in the generator's header, not in the `.tres` data, so it will drift into the
  shipped screen unless fixed at source.
- Also `README.md:1` — `# Habitat Town`.

**Severity.** MAJOR — a compliance artifact naming the wrong product, on the path to a
player-visible screen that a CC BY 3.0 obligation depends on.

**Owner.** tech-art (owns attribution and `generate_credits.gd`); the human for `README.md`.

---

## Assertions that passed clean

| # | Assertion | Result |
|---|---|---|
| 1 | spec.md schema fields ↔ `@export` | **Fails one direction** (S-1: `capacity_radius`, `max_individuals`). Reverse direction clean — no orphan code fields. |
| 2 | Tuning constants agree across roster / tracker / `.tres` | **Open gates** (S-2, S-3) + three cross-doc number disagreements (S-9). `scout_radius` clean (S-4). |
| 3 | `BARE_TAGS` not a non-empty hardcoded literal | **FAILS — BLOCKING** (S-5). |
| 4 | Habitat tag vocabulary identical in 4 places | **CLEAN** (S-6). |
| 5 | No `PROPOSED` / `PLACEHOLDER` in a shipped `.tres` | **CLEAN** (S-7). |
| 6 | Paths and links in agents + `game-design/` resolve; no `archive/` links | **CLEAN for the literal scope** (R-7). Fails just outside it in `decisions.md` (R-3), and for `gdd.md:NNN` / `gdd.md → Data Schemas` citations from code and data (R-1, R-2, R-4, R-5). |
| 7 | Agent-cited `gdd.md` section names exist | **CLEAN** (R-6). |
| 8 | `#NN` resolve; `D-NN` unique and existent | **CLEAN** (R-8). |
| 9 | Agent-count claim matches the filesystem | **CLEAN** (R-9). |
| 10 | No stray `gdd*.md` in `game-design/` | **CLEAN** (R-10). |
| 11 | Scan glyph ↔ `status`; no ✅ without sign-off | **Glyph half CLEAN in both trackers** (T-4); sign-off half **fails** for `fox` and `rabbit` (T-1, T-2, T-3). |
| 12 | Tracker-claimed paths exist | **CLEAN** (T-7). |
| 13 | Directory-disjointness across owners | **CLEAN** (T-8). |
| 14 | Sources in `CREDITS.md`; required notices present | **CLEAN** (L-1). Separate naming defect in the same file (L-2). |

**Categories with nothing to report:** none entirely — but assertions **4, 5, 7, 8, 9, 10, 12,
13, 14** each returned clean, and the glyph-consistency half of 11 returned clean in both
trackers.

---

## Finding index by severity

| ID | Severity | One line | Owner |
|---|---|---|---|
| S-5 | **BLOCKING** | `BARE_TAGS` hardcoded non-empty against `spec.md:61`'s "empty by construction"; `test_inert_land_invariant.gd:41` asserts the wrong state | gameplay-engineer + qa-engineer |
| S-1 | MAJOR | `capacity_radius` / `max_individuals` documented as schema fields; code says "deliberately no second radius field" | human → gameplay-engineer |
| S-8 | MAJOR | Four-step vs five-step fact-card checklist; two different "fifth steps" live | content-writer / human |
| S-9.1 | MAJOR | `roster.md:19` "ships 8 species" vs D-24 and three other docs | human |
| R-1 | MAJOR | All `gdd.md:NNN` citations in code/data stale; one is in a runtime failure message | gameplay-engineer |
| R-2 | MAJOR | `gdd.md -> Data Schemas` cited 8× ; no such section in `gdd.md` | gameplay-engineer / content-writer / human |
| R-3 | MAJOR | `decisions.md`'s five own relative links do not resolve | human |
| T-1 | MAJOR | `fox` ✅ with `human_signoff` = "no explicit sign-off date/name" | human |
| T-2 | MAJOR | `rabbit` ✅ on a sign-off recorded only in a `.tres` comment | human |
| L-2 | MAJOR | `CREDITS.md` + generator say "Habitat Town"; on the path to a player-visible screen | tech-art / human |
| S-2 | MINOR¹ | `tiles_per_individual` 4/5/1 vs 12 — open gate #6, unmarked in two of three places | human |
| S-3 | MINOR | `capacity_radius` / `max_individuals` values unrepresented in data — open gate #23 | human |
| S-9.2 | MINOR | D-21 "four terrains" vs gdd.md "five terrains" | human |
| S-9.3 | MINOR | "~28" vs "~30" work units | human |
| R-4 | MINOR | Three stale `gdd.md` section-path citations in `decisions.md` | human |
| R-5 | MINOR | `rabbit.tres:13` cites "Cat on the roster" — retired by D-24 | content-writer |
| T-3 | MINOR | `rabbit` ✅ while its own row says a license condition is unmet | human |
| T-5 | MINOR | `tier1-status.md` row 8 named "The decided roster" vs "The floor roster" | human |
| T-6 | MINOR | `content-pipeline-status.md:36` "as of 2026-07-26" predates D-24 content it holds | tech-art / human |

¹ MINOR as drift because the gate is correctly named at `tier1-status.md:190`; the risk is the
missing marker, not the value.

---

*No project file was modified. All git operations were left to the human.*
