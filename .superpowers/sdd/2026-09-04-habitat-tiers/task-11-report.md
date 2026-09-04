# Task 11 report — Full-suite verification and the documentation fold-back list

No code, `.tres`, or `game-design/*.md` file was touched by this task. No git command was
run.

## Step 1 — full suite

`bash scripts/run-tests.sh`: **127 suites total, 127 passed, 0 failed. Exit code 0.**
Total assertions passed across all suites: **5,049**. The two `FAIL` string hits in the
raw log are test-description text (`"a synthetic wild_grass emitting ... FAILS
validate()"`), both actually reported `PASS` — confirmed by grep, no real failure exists.

Trailing engine noise (`WARNING: 10 ObjectDB instances were leaked at exit`, `ERROR: 3
resources still in use at exit`) is process-teardown chatter after the suite already
printed its 127/127 summary and does not affect the exit code — consistent with every
prior task's runs in this branch.

## Step 2 — the two invariants no single task owns

`bash scripts/run-tests.sh new_terrains` — 26/26 passed, including the exact line:

```
PASS  wild grass still emits nothing — the inert-land invariant holds
```

`bash scripts/run-tests.sh roster_signatures` — 50/50 passed, including:

```
PASS  the roster has at least fifteen species (found 15)
...
PASS  the shipped dependency graph is acyclic
```

15 "has a distinct signature" PASS lines (husky, alpaca, donkey, horse, deer, cow, pug,
pig, fox, human, rabbit, sheep, stag, bull, shiba_inu) — **fifteen species, not sixteen**;
Chicken has no `AnimalDefinition` (asset unpurchased). This corrects the brief's own
"sixteen" language — see Step 5's note on the spec's matching error.

## Step 3 — Gentle Displacement regression gate

`bash scripts/run-tests.sh gentle_displacement` — **161/161 passed, 0 failed.** The
displacement trigger (`capacity(h,S) < population(h,S)`) exercises the rewritten
`capacity()` throughout — including boundary cases (`capacity == population` displaces
nobody), the real `Main.tscn` fixture, structure-home departure/relocation, and the
permanent Species-Hosted ledger surviving a departure. Five `PEND` lines close the suite,
all explicitly non-machine-checkable (copy content, Read-Aloud voice, kid-tonality read,
and the fact that shipped content has no second placeable to drive a *build*-triggered
displacement yet) — none of these are failures.

**Two items for human playtest** (neither is headless-checkable):
- **A tier fall must read as a thinning, not a vanishing.** Dropping from a herd tier to a
  pair tier should warn once and remove only the surplus — copy should land like "the herd
  will thin to a pair — the rest will find a wider field," never as the site emptying.
- **Two-level cascades must coalesce into ONE warning.** `deer → stag` and
  `human → people → dogs` each mean a single settled gesture can ripple through two
  species; the settlement rule must summarise both in one popup, not chain two.

## Step 4 — the numbers

- **Suites: 127 total, 127 passed, 0 failed.**
- **Assertions passed: 5,049** (summed from each suite's own `--- name: N passed, 0
  failed ---` line).
- **Widest per-need radius actually used: 14** (`deer` and `stag`'s group-tier needs, and
  one of `horse`'s group-tier needs). Full distribution across all 59 need entries in
  `project/data/animals/*.tres`: 47 at `radius = 0` (the `CAPACITY_RADIUS_FOLLOWS_SCOUT`
  sentinel, meaning "= scout_radius"), 2 at 5, 1 at 8, 1 at 12, 9 at 14. Nothing hits the
  human's 16 ceiling; 14 is the actual high-water mark the perf budget (`radius² × roster
  × tiers`) has to cover.
- **Tiers vs. legacy flat fields:** all **15/15** shipped species carry an authored
  `tiers` array (`grep -l "^tiers = " project/data/animals/*.tres` → 15 files). All 15
  *also* still carry the legacy flat fields (`habitat_needs`, `tiles_per_individual`,
  `max_individuals`) verbatim in place — `effective_tiers()` prefers `tiers` when
  non-empty, so the legacy fields are present-but-inert everywhere, kept only so a
  rollback is a one-line edit rather than a re-authoring (per each file's own header
  comment, e.g. `alpaca.tres` lines 46-48).

## Step 5 — documentation fold-back list (human edits only; nothing below was touched)

**`game-design/gdd.md`** — Habitat Suitability section:
- Capacity is now `max` over a species' `tiers`, not a single flat recipe.
- `quiet` has left the tag vocabulary (confirmed absent from every emitted tag in
  `project/data/terrain/*.tres` and `project/data/buildings/*.tres`).
- Residents now emit tags themselves (`deer` emits `deer`, `human`/villager emits
  `people` — confirmed by `roster_signatures`'s "exactly two species emit anything"
  assertion), which is how `stag` gates on live deer population and the
  `human → people → dogs` cascade exists at all.
- Per-need radii (0–14 shipped; sentinel 0 = "follows scout_radius") and per-need
  divisors (`tiles_per_individual`, now called `tag`/`radius`/`tiles_per_individual` per
  `HabitatNeed`) replace the single flat recipe language.
- Exclusion limits (`HabitatLimit`, e.g. `built ≤ N`) and group arrivals
  (`arrival_group_size`) are new concepts with no current GDD section.

**`game-design/roster.md`** — the "Already-Defined Roster" table is superseded. It lists
14 species with flat needs; the shipped roster is **15** species with authored tiers.
`pig`, `sheep`, and `pug` were already shipped (`.tres` files exist, pass
`roster_signatures`) but were never added to the table.

**`game-design/terrain.md`** — three new terrains not in the doc: `meadow` (emits
`open_grass`, `flowers`), `scrub` (emits `browse`, `rocks`), `snowfield` (emits `snow`) —
all confirmed via `new_terrains` (26/26 pass). The tag-source mapping table needs these
three rows plus the building-tag sources below.

**`game-design/buildings.md`** — nine buildings now emit tags via `emitted_tags`
(barn, chicken_coop, farmhouse, open_barn, silo, small_barn, water_tower, well, windmill;
House already emitted `["house"]` pre-branch and now also emits `built`, shared by every
placeable — see `house.tres` lines 9-12). **Farmhouse is a new placeable**
(`farmhouse.tres`, emits `["built", "house", "large_house"]`), not a form of House. The
"House at 2×2 form" line in buildings.md is superseded — the 2×2 role is Farmhouse's own
buildable, not a House variant.

**`game-design/spec.md`**:
- Open Questions #5, #7, #20, #23 are affected by this branch (confirm exact resolutions
  against `docs/superpowers/specs/2026-09-04-habitat-tiers-design.md` § 12, "Open
  questions — all ruled 2026-09-04").
- The radius band spec.md states today (`scout_radius` "~8–12", line 26 and line 191) is
  stale — actual per-need radii now shipped run 0–14, and the human's ruled ceiling is 16,
  not 12.
- `save_version` is now **6** (`project/scripts/save/world_snapshot.gd:101`,
  `const SAVE_VERSION: int = 6`); spec.md's Save-file section (line 79) references
  `save_version` generically and doesn't currently need a number, but if one gets added it
  should read 6.

**`decisions.md`** — next available number is **D-52** (latest on file is D-51). Needs one
new entry recording the habitat-tiers ruling and the six Open-Question rulings of
2026-09-04 (spec § 12).

**Two errors in the spec itself**
(`docs/superpowers/specs/2026-09-04-habitat-tiers-design.md`), for the human to correct:
- **§ 9, line 338**: "Sixteen species, sixteen distinct habitat signatures" — should read
  **fifteen**; Chicken (`coop*` `cultivated/4`, line 331) has no `AnimalDefinition` asset
  and does not ship. Line 164 also says "sixteen" in the same sense and needs the same fix.
- **§ 9, Sheep row (line 333)**: `| Sheep | ... | flock: + \`mill\`, arrive 4 |` — the
  `mill` entry has no `*` gate marker, unlike every comparable building-gate entry in the
  same table (Cow's `barn*`/`silo*`, Bull's `large_barn*`, Alpaca's `barn*`, Villager's
  `house*`/`large_house*`, Pug's `house*`, Shiba Inu's `house*`). This makes it ambiguous
  whether `mill` gates the flock tier or is scored like an ordinary need — worth
  cross-checking against `sheep.tres`'s actual shipped group tier before deciding which
  way to fix the table.

**Also worth stating in the docs**: `coop` (emitted only by `chicken_coop.tres`) currently
has **zero consuming species** — same situation as `sand`, which also has no consumer.
Both are acceptable (Chicken is unshipped; nothing currently needs `sand`), but the docs
should say so rather than leave a silent dangling tag for a future reader to puzzle over.

## Reminder for the human

Every habitat value in the 15 shipped species `.tres` files and in `farmhouse.tres` is a
**proposal awaiting sign-off**, per each file's own header comment ("PROPOSAL, NOT A
DECISION... awaiting human sign-off, per the project rule that all tuning values are the
human's"). No ✅ should be recorded in `content-pipeline-status.md` or `tier1-status.md`
on the strength of this task's suite-green result alone — that result confirms mechanics
work as specified, not that the specified values are the human's final call.

## Concerns

None block the suite or this branch's mechanics. Everything above is either a stale-doc
fold-back item or a spec-text typo; no test failed, no invariant broke.
