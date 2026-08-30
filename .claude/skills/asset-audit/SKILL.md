---
name: asset-audit
description: Sweeps source-content/assets/ for content nobody has assessed yet, judges it against Wildhaven's open needs, and — on the operator's pick — drives the full content pipeline that gets it into the game (import, data entry, copy, menu wiring, validation). Takes an optional pack-folder name to scope the sweep to one drop. Use after downloading new assets, or periodically to ask "is there anything here we should be using?"
---

The cheap parts of this skill run inline. Only steps 2 and 4 dispatch agents, and each
dispatch covers **every** item in the batch — one dispatch per pipeline step, never one
per asset. Orchestration cost scales with dispatch count, not agent work (gdd.md →
Technical Strategy #5).

**Argument:** an optional pack folder name, matched case-insensitively as a substring
(`/asset-audit medieval` → `Medieval Village Pack - Dec 2020-...`). No argument sweeps
everything unassessed. An ambiguous match is an error listing the candidates — resolve it
with the operator, never guess.

## What owns what

| Doc | Role in this skill |
|---|---|
| [source-content/assets/ASSET_AUDIT.md](../../../source-content/assets/ASSET_AUDIT.md) | The summary this skill maintains: generated pack inventory + the decision prose for every pack and model considered, **including rejects and why** |
| [game-design/asset-import-pipeline.md](../../../game-design/asset-import-pipeline.md) | The runnable import procedure step 4 hands to tech-art — do not restate it here |
| [game-design/content-pipeline-status.md](../../../game-design/content-pipeline-status.md) | Per-item live state; each agent writes only its own fields |
| [game-design/art.md](../../../game-design/art.md) | Sourcing policy and the licensing gate — Quaternius CC0 primary, Synty SIMPLE animals-only, never Synty POLYGON |
| [roster.md](../../../game-design/roster.md) · [terrain.md](../../../game-design/terrain.md) · [buildings.md](../../../game-design/buildings.md) | The decided content values a candidate is measured against |

## Procedure

### 1. Diff (inline, no agent)

```
python3 scripts/asset-manifest.py --diff
```

Read the verdict line. Four outcomes:

- **`nothing new`, and no argument was given** → **do not stop yet.** `assessed` means
  "we know what is in this pack", *not* "we decided against it", and reading it the second
  way is how nine `Houses_SecondAge_*` and fifteen animated villagers sat unused inside
  already-cleared packs while the game shipped a 404-triangle lean-to. Run:

  ```
  python3 scripts/asset-manifest.py --unused
  ```

  Report the packs already drawn from with their imported/unused split, and offer a
  `--unused "<pack>"` look at any the operator is curious about. Then stop. Still cheap —
  no dispatch, no audit prose. **If the operator says the game is weak somewhere (houses
  look poor, not enough villagers), start here, not with a new download**: the answer is
  usually inside a pack that was cleared and never fully drawn from.
- **`nothing new`, but an argument was given** → the named pack is already assessed. Say
  so, quote its decision lines from ASSET_AUDIT.md, and ask whether the operator wants a
  deliberate re-assessment before going further. Only continue on a yes.
- **New / changed / unassessed packs exist** → continue to step 2 with exactly those
  packs (narrowed to the argument's pack, if one was given).
- **`RECORDED BUT MISSING FROM DISK` is non-empty** → surface it plainly. A pack that
  vanished may be referenced by an already-imported asset's attribution entry; that is a
  finding for the operator, not something to clean up here.

**Duplicates are not work.** A pack listed under `DUPLICATE CONTENT` with `[a copy is
already assessed]` is the same download twice — record it as a duplicate in step 5 and
drop it from the candidate set. Two unassessed copies of each other count as **one** item.

**Widen the candidate set past the new packs.** Before dispatching, check whether an
already-cleared pack answers the same need more cheaply — a model in an assessed pack is
native-format, already licensed, already attributed, and needs no new entry:

```
python3 scripts/asset-manifest.py --unused                  # per-pack split
python3 scripts/asset-manifest.py --unused "<pack>"         # the actual names
```

The counts are a *pointer*, not a record — matching is by normalized basename, so a model
renamed on import reads as unused and a generic name (`House`, `Well`) can read as used.
content-pipeline-status.md is the record. Where a cleared pack plausibly covers the need,
name it in the step-2 brief and ask the agent to compare, rather than assuming the new
download wins.

For each pack that survives, get its model list before dispatching, so the brief names
real models rather than sending an agent to go find them:

```
python3 scripts/asset-manifest.py --models "<pack>"
python3 scripts/asset-manifest.py --models "<pack>" --animated-only
```

### 2. Assess (one **tech-art** dispatch, covering all surviving packs)

The brief tells tech-art to run [asset-import-pipeline.md](../../../game-design/asset-import-pipeline.md)
§ **2. Audit (hard gate)** against the listed models — and **only** that step. It reports;
it imports nothing. Require in the brief:

- **License** per art.md's locked policy. Anything not Quaternius CC0 and not a sanctioned
  Synty SIMPLE animal pack is a hard stop for that model, named as such. (The
  `(loose files)` pseudo-pack of poly.pizza downloads is mixed-authorship — every loose
  file needs its own creator and license confirmed, not the pack's.)
- **Animations are real.** The manifest's `Animated` column is a byte-signature hint only.
  An armature with no idle/walk cycle fails this gate — that is exactly how the Quaternius
  chickens failed in the existing audit, and re-learning it costs an import.
- **Silhouette** reads picture-book per art.md. No mesh work exists to fix it later, so a
  marginal model is rejected here, with the reason recorded.
- **Mapping to a need**, in this priority order:
  1. an open gap — a species art.md's roster table still shows unresolved (Duck and
     Chicken, as of D-24), or a roster/terrain/buildings row whose content-pipeline-status
     is not ✅. **art.md is the authority here, not ASSET_AUDIT.md's historical search
     record**, and its Sourcing Watch-List species (Cat, Monkey, Leopard) are explicitly
     *not* gaps — a Watch-List candidate re-enters through a normal Add-an-Animal run,
     with no special claim on the roster;
  2. an item that would *replace* something shipped as a compromise — flag these loudly.
     Note that a cleared-pool species is **not** a stand-in for anything (D-24: Deer and
     Stag are roster candidates in their own right), so this is about assets, not species;
  3. content that widens an existing category (another buildable, another tree, village
     dressing) with no gap behind it;
  4. **no current use** — say so and stop. "Available" is not a reason to import.
- **Cost estimate** per candidate: which pipeline steps it needs, and whether it lands in
  an existing attribution entry or needs a new one.

Tech-art returns a table. It does not edit ASSET_AUDIT.md, content-pipeline-status.md, or
any tracker in this step — assessment is not a pipeline run.

### 3. Present options (inline)

Show the operator one ranked table: model → proposed role (animal / building / terrain /
prop) → what it fills or widens → license → animation verdict → estimated pipeline steps.
Group rejects underneath with one-line reasons.

Then ask which to add — plainly, as a list to pick from. **Nothing is imported without an
explicit pick in this exchange.** If the operator picks nothing, go to step 5 anyway: the
assessment itself is worth recording, so the next sweep does not repeat it.

### 4. Run the pipeline — batched by step, two gates

Everything picked moves together, one dispatch per step:

1. **tech-art** — import raw file + hand-authored wrapper `.tscn` at the conventional path,
   look pass, `test_<name>_import.gd`, attribution entry (new or extended) + license text
   + regenerate `CREDITS.md`, and its own fields in content-pipeline-status.md. The
   procedure is asset-import-pipeline.md's steps 3–6; the brief points there rather than
   restating it.

2. **GATE 1 — the operator rules the values.** Present, per item, the proposed design
   values with their sourcing: for an animal `habitat_needs`, `personality`, `avoids`,
   `farm_tolerant`, `scout_radius`, `capacity_radius`, `tiles_per_individual`,
   `max_individuals`; for a building `hotbar_category`, `cost`, `footprint`,
   `allowed_terrain`, `emitted_tags`. Say where each number comes from (an existing
   decided row, a sibling item's baseline, or nothing at all) and mark anything unsourced
   as a proposal. **All tuning values are the human's** — never pick one and proceed. If
   the ruling is a genuinely new design decision, draft the `D-NN` entry for
   [decisions.md](../../../decisions.md) and hand it to the operator to log; do not write
   it yourself.

3. **gameplay-engineer** — write the `.tres` under `project/data/<category>/`, using the
   ruled values verbatim, following the header-comment convention of the existing files
   (source, license, per-field sourcing, anything still a proposal called out). Update
   `data_entry_location`.

4. **content-writer** — `fact_text` / `fact_text_pool` per the GDD's five-step checklist
   and [fact-card-pipeline.md](../../../game-design/fact-card-pipeline.md). Update
   `copy_content_location`.

5. **Wiring check (inline, before qa).** Most content needs no UI work — `SpeciesRoster`
   (`project/scripts/simulation/species_roster.gd`) loads every `.tres` in
   `res://data/animals` by directory scan, and `game_hud.gd` groups placeables by
   `hotbar_category` on its own. Confirm rather than assume:
   - a new **animal** appears in the roster and in the Field Guide;
   - a new **building** appears in the hotbar under its category;
   - the item does **not** introduce a `hotbar_category` unknown to the hard-coded
     `"farm_building"` filter in `project/scripts/world/world_root.gd` (~line 730) or to
     `style_picker_popup` / `game_hud.gd`'s grouping.

   Auto-registered and visible → say so explicitly and move on. Needs wiring → dispatch
   **ui-engineer** for that wiring only, in one dispatch covering every affected item.

6. **qa-engineer** — `bash scripts/run-tests.sh` (never a bare `--quit`; `--import` runs
   before `--script`). Report failures with output, do not paper over them. Update
   `validation_status`.

7. **GATE 2 — human sign-off.** Content Pipeline step 8. Present what landed and what each
   test said. `status` cannot show ✅ until `human_signoff` is actually recorded, and the
   operator records it.

If any step fails, stop the chain there and report — do not carry a broken import forward
into data entry.

### 5. Record (inline)

1. Add the decision prose to ASSET_AUDIT.md — a short block per assessed pack, listing
   models **used** (with their destination) and models **rejected** (with the reason, in
   enough detail that the next sweep does not re-litigate: "armature only, no walk cycle",
   not "not suitable"). Duplicate packs get one line naming the copy they duplicate.
2. If a candidate resolves or changes an entry in the **Missing animals — historical
   search record** or the pack-evaluation log, update that row too — a stale "still
   looking" row for something just imported is a defect. Sourcing *narrative* still
   belongs to art.md; if this run changes what art.md's roster table or Sourcing
   Watch-List should say, report that to the operator rather than editing art.md here.
3. Flip each assessed pack's row:
   ```
   python3 scripts/asset-manifest.py --set-status "<pack>" assessed
   ```
   Only for packs whose decision prose is now actually in the doc. A pack the operator
   deferred stays `new` unless the deferral itself is written down as the decision.
4. Re-run `python3 scripts/asset-manifest.py --write` if any pack folder changed on disk
   during the run, then `--diff` once to confirm the record and the disk agree.

Per-item live state stays in content-pipeline-status.md, written by its field owners.
ASSET_AUDIT.md never duplicates it.

## Boundary

- **Run no git commands.** Report changed file paths instead.
- Never import anything without the operator's step-3 pick in that same exchange.
- Never decide a tuning value, and never sign a human gate — both stay named blocks at
  GATE 1 and GATE 2.
- Never edit a content-pipeline-status.md field this skill does not own; each agent writes
  its own, and a field you don't own is a finding, not an edit.
- Never hand-edit rows inside ASSET_AUDIT.md's generated manifest block — `--write` and
  `--set-status` own it. Prose outside the markers is yours to write.
- Never dispatch more than one agent per pipeline step per run.
