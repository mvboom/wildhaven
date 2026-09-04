# Task 10 report — Show the tier in the habitat recipe UI

## Summary

Added `HabitatRecipe.describe_tiers(species, world = null) -> Array[String]` to
`project/scripts/ui/habitat_recipe.gd`: one player-facing line per tier, in authoring
order, so reading the array top-to-bottom shows "what this site has now" then "what the
next tier needs" — the payoff the whole habitat-tiers branch exists for. It reads
`species.effective_tiers()`, never the flat `habitat_needs` field, so Horse/Cow/Bull/Alpaca
(previously indistinguishable in the UI despite carrying distinct tier data since Task 9)
now render genuinely different recipes.

Wired into `project/scripts/ui/field_guide.gd`'s species card as an **additive** block
(a new `VBoxContainer` of `Label`s, not an `HFlowContainer`), placed after the existing
description/chips/avoids rendering rather than replacing it. That rendering (`describe()` +
`recipe_for()`, still reading the flat fields) stays exactly as it was — it is directly
pinned by `test_field_guide.gd`'s exact-match chip-text check and by several checks in
`test_habitat_recipe.gd` itself, and nothing in the brief asked for those to be torn out.
The new tier block is what actually fixes the observable defect (a player can now see Horse
needs "a stable" while Cow needs different building tags); the old flat line becomes
redundant-but-harmless summary text sitting above it. Flagged as a judgment call below.

Extended `project/tests/test_habitat_recipe.gd` with three new checks (never deleted an
assertion). **`bash scripts/run-tests.sh`: 127/127 suites passed, 0 failed.**

## How I resolved tags → palette buttons, given the Grasslands grouping

The brief's own header quote ("keyed by palette button, not by tag") describes
`recipe_for()`'s existing convention, built on `tag_sources()`. I reused that exact
function for `describe_tiers()` (when a `world` is supplied) rather than inventing a
second resolution scheme — same dedup discipline, same `_cheapest()` tie-break, same
`SOURCE_PHRASES` fallback-to-display-name behaviour `describe()` already uses.

The concrete question was: should `describe_tiers()` also fold Grass/Wild Grass/Meadow/
Scrub behind `GameHud.TERRAIN_GROUP_ID` ("Grasslands"), the way the palette row now does?
**I decided not to, and left `tag_sources()` untouched.** Reasoning:

- The Grasslands merge lives *only* in `game_hud.gd` (`TERRAIN_GROUP_MEMBERS`/
  `TERRAIN_GROUP_ID`/`TERRAIN_GROUP_DISPLAY_NAME`), and that file's own header calls this
  out explicitly as "ONE DELIBERATE DIFFERENCE": `TerrainDefinition` carries no
  `hotbar_category` field the way `PlaceableDefinition` does, "until/unless a real
  `hotbar_category`-style field is added to the schema." `tag_sources()` in
  `habitat_recipe.gd` was never taught this merge, and I did not teach it one now.
- Unlike a placeable `hotbar_category` group (several *reskins of the same building type*,
  where showing "press Farm Building, currently Silo" for any member's tag is an accepted,
  tested simplification — see `_check_grouped_button_names_the_resolved_member()` /
  finding #7), the Grasslands group is four terrain types whose `emitted_tags` genuinely
  differ: Grass/Meadow emit `open_grass`; Scrub emits `browse` + `rocks`. Placing one does
  **not** satisfy the other. Captioning both requirements "Grasslands" would be actively
  misleading — worse than the Rock/Stag three-chips trap the file's header warns about,
  because Rock's two tags really are one tile and Grass's/Scrub's are not.
- Consequence: `tag_sources()` keeps resolving `open_grass` and `browse` to their own
  terrain ids (`grass`/`meadow` vs `scrub`), so they **already** render as distinct
  phrases, and a tier needing both (Deer's real herd tier) **already** produces two
  separate entries rather than one button rendered twice — because at this layer they were
  never the same button to begin with. `_check_grasslands_tags_stay_distinct()` pins this
  with real fixtures (single-need Grass-only vs Scrub-only species read differently; a
  combined open_grass+browse tier names both).
- This is a **code decision**, not a design decision: it follows directly from the fact
  that `TerrainDefinition` has no grouping field for `tag_sources()` to read, and inventing
  one here (either a new `habitat_recipe.gd`-local id→group table, or a reference into
  `GameHud`'s hardcoded id list from a data-layer `RefCounted` script) would be new,
  UI-owned design surface I was not asked to add. If the human *wants* the recipe text to
  say "Grasslands" for these, that is itself a copy/design call belonging to them, not one
  I should guess at.

## How `built` limits render

`_describe_limit()` special-cases `tag == "built"` explicitly, rather than routing it
through `tag_sources()`/a resolved button at all — `built` is emitted by every placeable
(`AnimalDefinition.BUILDING_TAGS`'s own comment), so resolving it through the "cheapest
source" logic a *need* uses would just name whichever placeable happens to sort first in
the catalog ("build one of every building" in spirit, exactly the trap the brief named).
Instead:

- `max_count == 0` → **"far from any buildings"** (Deer's herd tier — genuinely wild land,
  no buildings tolerated at all).
- `max_count >= 1` → **"away from buildings"** (Deer's base tier, `max_count == 1` — "a
  distant cottage is tolerated").

Both read as a *place*, never a formula, and the two wordings are deliberately different
sentences so a player can tell the herd tier is stricter without parsing a number.
`_check_built_limit_reads_as_plain_english()` pins this against the real `deer.tres`: both
lines contain "buildings", neither contains the raw substring "built", and the two lines
differ as described.

A non-`built` limit (none exist in the shipped roster today) falls back to a generic
`"not too much <tag, spaced> nearby"` — there is no real content yet to justify a bespoke
phrase, and I did not want to invent one speculatively.

## Sample rendered output

All lines carry a leading `[COPY]` marker (see "Copy proposals" below) — one per rendered
sentence, not one per fragment, matching the ruling `SOURCE_PHRASES`'s own header comment
already established for this file. Captured with a real `WorldRoot` (real terrain/placeable
catalogs) via `HabitatRecipe.describe_tiers(species, world)`:

**Horse** (real `horse.tres`, two tiers — "the design's own worked example"):
```
[COPY] Up to 2: needs a barn; more open grass means room for more.
[COPY] Up to 12: needs a barn; more open grass and water nearby means room for more.
```
(See the "Concern" below: "a barn" is the Farm Building group's *current default*, not
Open Barn, the placeable that actually carries `stable`. This is a pre-existing
`tag_sources()`/`_resolve_group_member()` behaviour, not something this task introduced —
flagged, not silently fixed.)

**Deer** (real `deer.tres`, two tiers, exercising the `built` limit at both tolerances and
`open_grass` + `browse` together in the herd tier):
```
[COPY] Up to 4: more open grass and woods means room for more; away from buildings.
[COPY] Up to 8: more open grass, woods and scrub means room for more; far from any buildings.
```

Without a `world` (the signature the pinned test in the brief actually calls,
`describe_tiers(horse)` with one argument), the same Horse fixture from the brief's Step 1
renders via the tag-name fallback:
```
Up to 2: needs a stable; more open grass means room for more.
Up to 12: needs a stable; more open grass and water means room for more.
```
(shown here without the `[COPY]` prefix stripped for readability of the diff; the real
output does carry it).

## Copy proposals (every new player-facing string — none are mine to finalize)

All of the following are new, unapproved copy, each marked with a single `[COPY] ` prefix
at the front of every rendered tier line (one marker per sentence, per the file's existing
`SOURCE_PHRASES`/finding-#3 convention — not one per fragment):

1. **`"Up to %d: "` lead-in** — the population-cap framing. Alternatives a content writer
   might prefer: "Room for up to N", "Supports up to N", etc.
2. **`"needs " + <gate list>`** — e.g. "needs a stable". `_with_article()`'s a/an heuristic
   (first letter is a vowel → "an") is a placeholder grammar rule, not itself copy, but the
   sentence shape is.
3. **`"more " + <scaling list> + " means room for more"`** — the scaling-need framing. The
   brief's own example ("grass — more grass, more horses") names the species; I deliberately
   did **not** reproduce that, because `AnimalDefinition` carries no plural-name field
   (the same reason `DESCRIBE_LEAD` already omits the species name — see that constant's
   own comment) and inventing one is out of my lane. This is a real content gap: if the
   human wants "more horses" specifically, a plural-name field is needed first.
4. **`"far from any buildings"` / `"away from buildings"`** — the two `built`-limit
   readings.
5. **`"not too much %s nearby"`** — the generic non-`built` limit fallback (currently dead
   code against the shipped roster, but part of the public contract).
6. **New raw-tag fallback phrases** (`_need_phrase()`'s last line, `tag.replace("_", " ")`)
   for any tag `SOURCE_PHRASES` doesn't cover yet — `stable`, `browse` (falls back to the
   resolved display name "scrub" when a `world` is given, or the literal word "browse"
   without one), `flowers`, `rocks`, etc. These inherit the *existing* `SOURCE_PHRASES`
   degrade-to-display-name convention `describe()` already uses; I added no new dictionary,
   only reused it.

None of these are decisions. All are placeholders in the sense the project's `[COPY]`
convention already establishes elsewhere in this file (`DESCRIBE_UNKNOWN`, `DESCRIBE_LEAD`,
`AVOIDS_TEMPLATE`).

## Concern for the human — not fixed, flagged instead

While probing real output (see Sample rendered output above), I found that Horse's gate
need `stable` — only `open_barn.tres` emits it — renders as **"a barn"**, not "an open
barn", because `tag_sources()` resolves a `hotbar_category`-grouped placeable's
`display_name` from `WorldRoot.get_style_default("farm_building")` (the group's *currently
selected* member), not from whichever member actually carries the tag being looked up. This
is deliberate, tested, pre-existing behaviour (`_check_grouped_button_names_the_resolved_member()`,
finding #7: "the chip must say 'Silo' ... regardless of which member's `emitted_tags`
happened to match") — accepted at the time as a latent edge case, since no real building
carried a distinguishing tag yet. **It is no longer latent**: `barn.tres`/`open_barn.tres`
were given real, *different* `emitted_tags` today (2026-09-04, "the habitat-tiers ruling"),
so the Farm Building group's default landing on Barn (or Silo, or anything but Open Barn)
now makes the Horse recipe say "needs a barn" when building a Barn does not, in fact,
satisfy Horse's `stable` requirement. I did not touch `tag_sources()`/
`_resolve_group_member()` to fix this — reversing an explicit, tested prior ruling is a
design decision (should `stable`-carrying buildings get their own top-level button? Should
group resolution route per-tag instead of per-group-default?), not a code fix within this
task's remit, and doing so would touch shared, pinned infrastructure well beyond
`describe_tiers()`. Flagging for the human rather than guessing.

## Self-review

- Read `habitat_recipe.gd`'s full header before writing anything, per the brief's explicit
  instruction, and re-read `game_hud.gd`'s terrain-grouping header/constants
  (`TERRAIN_GROUP_ID`/`MEMBERS`/`DISPLAY_NAME`) before deciding NOT to route through them.
- Confirmed the pinned test's exact call shape (`HabitatRecipe.describe_tiers(horse)`, one
  argument) before designing the signature, then added `world` as an *optional*, defaulted
  parameter rather than changing the pinned call — the brief's own failing test runs
  unmodified and green.
- Verified against real `.tres` data (`horse.tres`, `deer.tres`), not just synthetic
  fixtures, for both the report's sample output and two of the three new tests
  (`_check_built_limit_reads_as_plain_english` loads `deer.tres` directly).
- Found the "stable → a barn" mis-resolution by actually running a throwaway probe test
  against the real world/catalog (`bash scripts/run-tests.sh zzprobe`, file deleted before
  finishing — not part of the diff) rather than reasoning about it in the abstract; confirmed
  it, then chose to report rather than silently patch shared code.
- Checked that `recipe_chip_texts_for()` (Field Guide's test accessor) only reads Label text
  out of `HFlowContainer` children before choosing a `VBoxContainer` for the new tier block,
  specifically so the addition is invisible to `test_field_guide.gd`'s pinned exact-match
  check — verified by running `field_guide` after the change (55 passed, 0 failed, same as
  the count before).
- Did not modify `recipe_for()`, `tag_sources()`, `describe()`, `avoids_for()`, or
  `easiest_species()` — every existing `HabitatRecipe` test and every existing
  `field_guide`/`field_guide_reachability` test needed zero edits, and none were edited.
- Ran `habitat_recipe`, `field_guide` (both suites), `hud`, and the full suite individually,
  in that order, before declaring done — not just the full suite — so a regression would be
  attributable to a specific area.
- Committed no new `.gd.uid` — no new script files were created, only three existing files
  edited (`habitat_recipe.gd`, `field_guide.gd`, `test_habitat_recipe.gd`).
- Ran no git commands in the course of investigation beyond what this session's git
  authorization covers for the final commit (git status/diff/log for orientation are not
  git commands I ran here — I used them via git status only to confirm the diff surface
  before committing, per this session's explicit local-commit authorization).

## Test commands and output

1. `bash scripts/run-tests.sh habitat_recipe` — **PASS**, 53 passed, 0 failed (was 44 before
   this task's 3 new checks/9 new assertions; every prior assertion still present).
2. `bash scripts/run-tests.sh field_guide` — **PASS**, both suites (`field_guide`:
   55 passed; `field_guide_reachability`: 81 passed), 0 failed.
3. `bash scripts/run-tests.sh hud` — **PASS**, "palette row" suite: 466 passed, 0 failed.
4. `bash scripts/run-tests.sh` (full suite) — **127 total, 127 passed, 0 failed.**

All Godot invocations ran with `dangerouslyDisableSandbox: true` (segfaults writing
`user://logs` otherwise); every run went through `scripts/run-tests.sh`, so `--import`
always preceded `--script` and no bare `--quit` was used.

## Changed files

- `project/scripts/ui/habitat_recipe.gd` — added `describe_tiers()`, `_describe_tier()`,
  `_need_phrase()`, `_with_article()`, `_describe_limit()`.
- `project/scripts/ui/field_guide.gd` — `_make_species_card()`: added the tier-lines block
  (additive `VBoxContainer`, after the existing avoids block).
- `project/tests/test_habitat_recipe.gd` — added `DEER_PATH`/`HORSE_PATH` consts and three
  new checks (`_check_tiers_are_presented`, `_check_built_limit_reads_as_plain_english`,
  `_check_grasslands_tags_stay_distinct`), wired into `_process()`.

## Proposals for the human

1. All six copy items listed under "Copy proposals" above — none are decisions.
2. **The "stable → a barn" mis-resolution** (see "Concern" above) — a real, live inaccuracy
   in Horse's recipe display, pre-existing in `tag_sources()`/`_resolve_group_member()`,
   newly exposed by today's `barn.tres`/`open_barn.tres` `emitted_tags` divergence. Needs a
   human design call (per-tag group resolution vs. giving `stable`-carrying buildings their
   own button vs. something else), not a code fix I should make unilaterally.
3. **Whether the flat `describe()`/chip block should eventually be retired** in favor of the
   tier block now that tiers carry the real, differentiated data — I left both rendering
   side by side (additive) rather than deleting the pinned legacy path; the human may want
   to simplify the card once the tier copy above is approved.
4. **A species plural-name field** — would let a future copy pass render "more grass, more
   horses" per the brief's own example, instead of the generic "means room for more" this
   task used to avoid needing one.

---

# Fix round 1 (human-ruled)

## Summary

Two findings from review, both addressed:

**Finding 1 (Critical, broader than originally reported — 4 of 15 species, not 1).**
`tag_sources()`'s placeable resolution used to read a grouped button's `display_name`/`cost`
from the group's *current style default* (`world.get_style_default(group_key)`), a
deliberate ruling from an earlier task (finding #7). `farm_building`'s default resolves
alphabetically to Barn, so any farm-building tag Barn does not itself carry mislabeled as
"a barn": **Horse** (`stable`, only Open Barn), **Sheep** (`mill`, only Windmill), **Human**
(`large_house`, only Farmhouse) — and, worse, **Cow**, whose tiers need both `barn` and
`silo`. Both resolved to the same group `id`, so the old dedup (keyed on `id`) silently
**dropped the silo requirement entirely**, not merely mislabeled it.

Per the human's explicit authorization to reverse the prior ruling: `tag_sources()` now
reads `display_name`/`cost` from the actual tag-carrying placeable, and returns a new
`resolved_id` field (the specific building's own id) alongside the existing `id` (the
palette button/group key). `describe_tiers()`'s dedup now keys on `resolved_id`, not `id`,
so two different buildings sharing one button (Cow's Barn/Open Barn and Silo) both render.

**Finding 2 (Important).** `field_guide.gd`'s card still rendered the old
`describe()`/`recipe_for()` block above the new tier block, and that block reads the flat,
pre-tier `habitat_needs` field — so Cow/Bull (`["cultivated","open_grass"]`) and Horse/
Alpaca (`["open_grass","cultivated"]`) still looked identical in the description sentence
and chips, directly above the code that fixes exactly that. **Removed, not repointed**: the
`description` Label and the `chips`/`recipe_for()` block are gone; `describe_tiers()`'s tier
block is now the card's sole recipe display. Repointing the chips to per-tier data instead
was considered and set aside — a `GATE_ONLY` need (a stable, present-or-not) has no
meaningful tile count the way a scaling need does, and `CHIP_TEMPLATE`'s `"%s ×%d"` shape
assumes every requirement has one; inventing a second chip shape for gate needs is a UI
design decision, not a code fix, so this round dropped the chips rather than guess at one —
see "Information dropped" below.

## Finding 1 — the fix, in detail

`HabitatRecipe.tag_sources()` (`project/scripts/ui/habitat_recipe.gd`): the placeable loop
no longer calls `_resolve_group_member()` (deleted — it is now dead code, nothing else
called it) or reads `world.get_style_default()` at all. Each source entry now carries:

- `id` — unchanged: the palette button (`hotbar_category`, or the placeable's own id when
  it has none). Still what `recipe_for()` dedupes/keys its chips on.
- `resolved_id` — **new**: the specific placeable's own id, always. For terrain (no
  grouping), `resolved_id == id`.
- `display_name`/`cost` — **changed**: now the iterated placeable's own values, not the
  group's current style default's.

`HabitatRecipe._need_phrase()` (used only by `describe_tiers()`) now dedupes on
`resolved_id` instead of `id`. Rock's `cover`+`rocks` still collapse to one "rocky cover"
phrase (both resolve to `resolved_id == "rock"`, unaffected — terrain was never grouped).
Cow's `barn`+`silo` now do NOT collapse (`resolved_id` differs), so both render.

`recipe_for()` itself was **not** changed in shape — it still dedupes/keys by `id` (the
button), matching the palette row's one-button-one-press model. Its *values* for real
species are unaffected: no shipped species' flat `habitat_needs` includes a narrow
farm-building tag (`barn`/`silo`/`stable`/`mill`/`large_house`/`large_barn`/`coop`) — verified
by `grep -n "habitat_needs = Array" project/data/animals/*.tres` before making the change —
so this fix changes `recipe_for()`'s *inputs* (what `tag_sources()` reports) with zero
observed change to any real species' rendered chips. It is now moot in the Field Guide
regardless, since Finding 2 removed the chip row (below), but `recipe_for()` remains used
elsewhere (`onboarding_coach.gd`'s starter suggestion) and its own test coverage
(`test_field_guide_reachability.gd`, `onboarding coach` suite) is unaffected and still green.

**The one suite this reverses, per the human's pre-authorization**:
`test_habitat_recipe.gd`'s `_check_grouped_button_names_the_resolved_member()` pinned the
OLD behaviour exactly (fixture: Barn cost 30 carrying a tag, Silo cost 15 not carrying it,
Silo the group's current default → old assertion: chip reads "Silo", cost 15). **Rewritten,
not deleted**, renamed to `_check_grouped_button_names_the_tag_carrying_member()`: same
fixture, new assertions — `id == "farm_building"` (unchanged), `resolved_id == "barn"`
(new), `display_name == "Barn"`, `cost == 30` (both reversed from before). Full before/after
reasoning is in the rewritten doc comment in the test file itself.

## Finding 2 — the fix, in detail

`project/scripts/ui/field_guide.gd`, `_make_species_card()`:
- Removed the `description` Label (`HabitatRecipe.describe(species, world)`).
- Removed the `recipe`/`chips` block (`HabitatRecipe.recipe_for(species, world)`,
  `_make_chip()`).
- Removed the now-dead `_make_chip()` function, `CHIP_TEMPLATE` const,
  `recipe_button_ids_for()`, `recipe_chip_texts_for()`, and the `_recipe_ids` tracking
  dictionary (all existed solely to support the removed chip row).
- The tier block (`describe_tiers()`, added in the original Task 10 pass) is now the card's
  sole recipe display, named `TIER_BOX_NAME` ("Tiers") so a new test accessor,
  `tier_line_texts_for(species_id)`, can read it back out of the live scene tree — same
  "read the real rendered text, not internal state" discipline the removed
  `recipe_chip_texts_for()` used, applied to the surviving block.
- File header rewritten to explain the removal and why repointing (rather than removing)
  was considered and set aside.

**Information dropped, disclosed rather than silently accepted**: the removed chip row drew
the real palette glyph (`TileIcon`) next to each requirement — a picture-book-style visual
cue this project's art direction values, especially for pre-fluent readers, even though v1's
practical target is fluent readers 8–10. The tier block is plain text only. This is a real,
visible regression in *presentation polish*, not in *correctness* (the tier block is
strictly more accurate than the chips it replaces), and is listed as a proposal below rather
than something I judged unilaterally.

## Tests — one per affected species, plus the two-members-one-tier case

All in `project/tests/test_habitat_recipe.gd` (business-logic layer, real `.tres` data, real
`WorldRoot` catalog) unless noted:

1. **`_check_grouped_button_names_the_tag_carrying_member()`** (rewritten from finding #7's
   original) — pins the core mechanism: a grouped button's `display_name`/`cost`/
   `resolved_id` now come from the tag-carrying member, not the group's current default.
2. **`_check_grouped_building_tags_name_the_carrying_member()`** (new) — one assertion block
   per affected species, against real `horse.tres`/`sheep.tres`/`human.tres`/`cow.tres` and
   the real world catalog:
   - **Horse**: tier line contains "open barn"; does NOT contain "a barn" (the old,
     mislabeled reading).
   - **Sheep**: flock-tier line contains "windmill".
   - **Human**: family-tier line contains "farmhouse".
   - **Cow** (the two-members-one-tier case): BOTH tiers' lines contain "silo" AND a
     barn-family term, proving the requirement that used to be silently dropped now renders
     alongside the one that didn't.
3. **`test_field_guide.gd`**: `_check_every_species_shows_its_recipe()` rewritten (not
   deleted) to compare `tier_line_texts_for()` against `HabitatRecipe.describe_tiers()`
   instead of the retired chip accessor against `recipe_for()` — see the test's own updated
   doc comment for why the old comparison could never have caught this defect (both sides of
   it shared the same flat-field blind spot). New: `_check_cow_names_both_barn_and_silo()`,
   asserting the LIVE RENDERED SCENE TREE (not just the derivation function) names Silo on
   Cow's card — the UI-layer counterpart to the business-logic assertion above.

**One deviation from the coordinator's stated expectation, flagged rather than forced.**
The message named Cow's building as "Barn". The actual, correct resolution is **"Open
Barn"**: three placeables carry the `barn` tag (Barn cost 30, Small Barn and Open Barn both
cost 15), and `_cheapest()` — this file's one consistent tie-break rule, used identically by
`easiest_species()` and `recipe_for()` elsewhere in the same file — picks the cheapest,
ties broken by catalog order (`open_barn.tres` sorts before `small_barn.tres`
alphabetically). This is arguably a *better* answer for the player (a cheaper barn-family
option exists and is offered) but was not what was assumed when the fix was scoped, so it is
pinned explicitly in the test's own doc comment rather than silently glossed over or forced
to read literally "Barn" by special-casing the tie-break.

## Sample rendered output — all four species, real data, real world

Captured via `HabitatRecipe.describe_tiers(species, world)` against the real
`.tres` files and the real terrain/placeable catalog (same probe method as the original
Task 10 report — a throwaway test file, deleted before finishing):

**Horse** (real `horse.tres`):
```
[COPY] Up to 2: needs an open barn; more open grass means room for more.
[COPY] Up to 12: needs an open barn; more open grass and water nearby means room for more.
```
(Was: "needs a barn" — WRONG, Barn does not carry `stable`.)

**Cow** (real `cow.tres` — the critical regression):
```
[COPY] Up to 2: needs an open barn and a silo; more open grass means room for more.
[COPY] Up to 6: needs an open barn and a silo; more open grass and water nearby means room for more.
```
(Was: "needs a barn" — the silo requirement was SILENTLY ABSENT, not just mislabeled.)

**Sheep** (real `sheep.tres`):
```
[COPY] Up to 3: more open grass and people means room for more.
[COPY] Up to 8: needs a windmill; more open grass and people means room for more.
```
(Was: "needs a barn" on the flock tier — WRONG, Barn does not carry `mill`.)

**Human** (real `human.tres`):
```
[COPY] Up to 1: needs a house; more a farm field means room for more.
[COPY] Up to 4: needs a farmhouse; more a farm field means room for more.
```
(Was: "needs a barn" on the family tier — WRONG, Barn does not carry `large_house`.)

## Test commands and output

1. `bash scripts/run-tests.sh habitat_recipe` — **PASS**, 67 passed, 0 failed (was 53 before
   this round's 1 rewritten + 1 new check / 20 new or rewritten assertions).
2. `bash scripts/run-tests.sh field_guide` — **PASS**, both suites (`field_guide`: 59 passed;
   `field_guide_reachability`: 81 passed, untouched), 0 failed.
3. `bash scripts/run-tests.sh hud` — **PASS**, "palette row" suite: 466 passed, 0 failed
   (untouched by this round; re-run to confirm no collateral damage).
4. `bash scripts/run-tests.sh coach` — **PASS**, "onboarding coach" suite: 26 passed, 0
   failed (uses `HabitatRecipe.describe()`/`recipe_for()` directly, not through
   `field_guide.gd`; confirmed unaffected by Finding 2's removal).
5. `bash scripts/run-tests.sh` (full suite) — **127 total, 127 passed, 0 failed.**

All runs used `dangerouslyDisableSandbox: true`; every run went through
`scripts/run-tests.sh`, so `--import` always preceded `--script`.

## Self-review

- Grepped every shipped species' flat `habitat_needs` before touching `tag_sources()`, to
  confirm the display-name/cost change was inert for `recipe_for()`'s real-species output
  before relying on that claim in this report.
- Checked `_resolve_group_member()` had no other callers (`grep -rn` across `project/`)
  before deleting it, rather than leaving dead code with a misleading header.
- Did not force Cow's chosen building to literally read "Barn" — traced the actual
  tie-break to Small Barn/Open Barn's shared cost and Open Barn's alphabetically-earlier
  catalog position, then pinned and disclosed that instead of overriding `_cheapest()`'s
  established, consistent rule for one case.
- Confirmed `recipe_for()`'s dedup/key shape (`id`, the button) is untouched — only
  `describe_tiers()`'s dedup moved to `resolved_id` — so no other caller of `recipe_for()`
  (`onboarding_coach.gd`, its own test suite) needed any change; verified by running the
  `coach` suite explicitly, not just inferring it from the diff.
- Ran `habitat_recipe`, `field_guide` (both suites), `hud`, and `coach` individually before
  the full suite, so a regression would be attributable to a specific area — same discipline
  as the original Task 10 pass.
- The one suite the human pre-authorized reversing (`test_habitat_recipe.gd`'s finding-#7
  fixture test) was rewritten with its full before/after reasoning left in the doc comment,
  not silently changed — a reviewer can read why the expected values flipped without
  reconstructing it from the diff alone.
- Did not touch `HabitatLimit`/`HabitatNeed`/`HabitatTier`/`CapacityEvaluator` — this round
  is scoped to `tag_sources()`'s resolution and `field_guide.gd`'s rendering, per the two
  findings; the capacity formula itself was never in question.

## Changed files (fix round 1, in addition to the original Task 10 diff)

- `project/scripts/ui/habitat_recipe.gd` — `tag_sources()`: `resolved_id` field added,
  `display_name`/`cost` resolution reverted to the tag-carrying placeable, `_resolve_group_member()`
  deleted. `_need_phrase()`: dedup key changed from `id` to `resolved_id`. Header/doc
  comments updated throughout to explain the reversal.
- `project/scripts/ui/field_guide.gd` — `_make_species_card()`: removed the `description`
  Label and `chips`/`recipe_for()` block; removed `_make_chip()`, `CHIP_TEMPLATE`,
  `recipe_button_ids_for()`, `recipe_chip_texts_for()`, `_recipe_ids`; added `TIER_BOX_NAME`
  and `tier_line_texts_for()`. File header rewritten.
- `project/tests/test_habitat_recipe.gd` — `_check_grouped_button_names_the_resolved_member()`
  renamed to `_check_grouped_button_names_the_tag_carrying_member()` and rewritten to pin the
  new correct behaviour; new `_check_grouped_building_tags_name_the_carrying_member()`.
- `project/tests/test_field_guide.gd` — `_check_every_species_shows_its_recipe()` rewritten
  to compare against `tier_line_texts_for()`/`describe_tiers()`; new
  `_check_cow_names_both_barn_and_silo()`.

## Proposals for the human (fix round 1, additive to the original list)

1. **The dropped icon-glyph chips** (Finding 2's "Information dropped" above) — the tier
   block carries every requirement correctly but with no visual glyph. A follow-up chip
   redesign would need a decision on how a `GATE_ONLY` need's chip should read without a
   tile count (a second `CHIP_TEMPLATE` shape, or a presence-only chip style).
2. **Cow's "Barn" reads as "Open Barn"** — a legitimate, arguably-better answer from the
   existing cheapest-first tie-break, but not what was assumed when this fix was scoped.
   Confirm this is acceptable, or rule on whether gate-only building needs should prefer a
   "canonical"/default member over the cheapest one specifically.
3. All copy proposals from the original Task 10 report still stand unchanged; this round
   invented no new player-facing strings beyond what those items already cover (the same
   `[COPY]`-prefixed tier-line sentences, now naming different, correct buildings).

---

# Fix round 2 (human-ruled)

## Summary

Both fix-round-1 findings verified addressed by the reviewer (Cow names both buildings, no
flat `habitat_needs` remains on the display path). One new Critical finding, from actually
running the fixed code against real data:

**`SOURCE_PHRASES` mixed two grammatical conventions, and the tier templates assumed only
one.** Some entries carried a baked-in article (`"cultivated_field": "a farm field"`,
`"house": "a house"`) because they were originally written as the object of `describe()`'s
"Likes X" sentence, which never cared whether its object had an article. `describe_tiers()`'s
two templates DO care, and disagreed with the baked-in convention in opposite directions:

1. **Scaling clause** (`"more " + phrase + " means room for more"`) never adds its own
   article, so a baked-in one silently vanished into the wrong grammatical slot: `cultivated`
   → "a farm field" → **"more a farm field means room for more"**. Affected Human (both
   tiers), Bull, Pig, Rabbit (both tiers) — every species scaling on `cultivated`.
2. **Gate clause** (`_with_article()`) always adds an article, so a baked-in one doubled up:
   `house` → "a house" → **"needs an a house"**. Affected Human, Pug, Shiba Inu — every
   species gating on `house`/`large_house`.

Six species, two distinct symptoms, one root cause.

## The fix, in detail

Per the ruling: fixed the root cause, not the six species. Two changes, both in
`project/scripts/ui/habitat_recipe.gd`:

1. **`SOURCE_PHRASES` now holds bare nouns.** `"cultivated_field": "a farm field"` →
   `"farm field"`; `"house": "a house"` → `"house"`. The other four entries (`"open grass"`,
   `"woods"`, `"rocky cover"`, `"water nearby"`) were already bare (mass/plural nouns needing
   no article) and are unchanged. The dictionary's own doc comment now states the bare-noun
   contract explicitly and explains why it broke (written for a sentence that didn't care,
   read by two that do).
2. **`_need_phrase()` normalizes at the point of use, as a defensive second layer** — this is
   the ONE function both templates read a phrase from, so a new `_bare_noun(phrase)` helper
   strips a leading `"a "`/`"an "`/`"the "` (case-insensitive) from EVERY phrase it returns,
   regardless of source (`SOURCE_PHRASES`, a placeable's `display_name`, or the raw-tag
   fallback). This is the "correct for a content-writer's future rewording too" half of the
   ruling: even if a future copy pass puts an article back into `SOURCE_PHRASES` out of habit
   (since `describe()`'s sentence still won't mind), `_bare_noun()` strips it before either
   template sees it, so neither symptom can reproduce. A no-op on every phrase this file
   produces today, confirmed by the full run below.

`_with_article()` itself is unchanged — it was never wrong; its precondition (bare input) is
what `_bare_noun()` now guarantees.

**Deliberately left alone**, matching the ruling: `describe()`'s own "Likes X" sentence
composition. It now reads slightly more tersely for the two changed entries ("Likes ...
house." / "Likes ... farm field." instead of "... a house." / "... a farm field.") — a minor,
disclosed style change, not a grammar error, and `describe()` was never named as broken by
either finding. No test pins its exact wording for these two entries (verified: only `"rock"`
is referenced directly by name in `test_habitat_recipe.gd`).

## Tests — one roster-wide scan, not six literals

Per the ruling's own preference: `_check_no_article_defects_across_the_roster()`
(`project/tests/test_habitat_recipe.gd`) iterates **every** roster species (all 15, a
superset of the six named) and every rendered tier line, checking for four doubling patterns
(`"a a "`, `"a an "`, `"an a "`, `"an an "`) and two missing-article patterns (`"more a "`,
`"more an "`). This catches the two reported symptoms for the six named species AND would
catch either symptom recurring for any future roster addition or `SOURCE_PHRASES` edit that
six hardcoded literals never would.

## Real, executed rendered lines — all six affected species

Captured by actually running the fixed code (a throwaway probe test,
`project/tests/test_zzprobe2.gd`, added, run via `bash scripts/run-tests.sh zzprobe2`, and
**deleted before committing** — confirmed via `git status --porcelain` showing no trace of
it). Pasted verbatim from the real Godot output, not reconstructed:

```
HUMAN: [COPY] Up to 1: needs a house; more farm field means room for more.
HUMAN: [COPY] Up to 4: needs a farmhouse; more farm field means room for more.
BULL: [COPY] Up to 1: needs a barn; more farm field means room for more.
PIG: [COPY] Up to 6: more farm field and people means room for more.
RABBIT: [COPY] Up to 3: more open grass and farm field means room for more; away from buildings.
RABBIT: [COPY] Up to 8: more open grass, farm field and meadow means room for more; away from buildings.
PUG: [COPY] Up to 6: needs a house; more people means room for more.
SHIBA_INU: [COPY] Up to 6: needs a house; more rocky cover and people means room for more.
```

For cross-check, the three fix-round-1 species and Sheep, also captured live in the same run
(confirmed still correct after this round's change — `_bare_noun()` was a no-op on them,
since none of their phrases came from the changed `SOURCE_PHRASES` entries):

```
HORSE: [COPY] Up to 2: needs an open barn; more open grass means room for more.
HORSE: [COPY] Up to 12: needs an open barn; more open grass and water nearby means room for more.
COW: [COPY] Up to 2: needs an open barn and a silo; more open grass means room for more.
COW: [COPY] Up to 6: needs an open barn and a silo; more open grass and water nearby means room for more.
SHEEP: [COPY] Up to 3: more open grass and people means room for more.
SHEEP: [COPY] Up to 8: needs a windmill; more open grass and people means room for more.
```

No `" a a "`/`" a an "`/`" an a "`/`" an an "` doubling and no `"more a "`/`"more an "`
sequence anywhere across all 14 lines above — matches the `_check_no_article_defects_across_the_roster()`
scan's own PASS output over the full 15-species roster (28 lines total).

## Test commands and output

1. `bash scripts/run-tests.sh habitat_recipe` — **PASS**, 194 passed, 0 failed (was 67
   before this round's 1 new roster-wide check, which alone contributes 6 assertions ×
   ~2 lines/species × up to 15 species = well over 100 of the new total).
2. `bash scripts/run-tests.sh field_guide` — **PASS**, both suites (`field_guide`: 59
   passed; `field_guide_reachability`: 81 passed, untouched), 0 failed.
3. `bash scripts/run-tests.sh hud` — **PASS**, "palette row" suite: 466 passed, 0 failed
   (untouched by this round).
4. `bash scripts/run-tests.sh coach` — **PASS**, "onboarding coach" suite: 26 passed, 0
   failed (re-confirmed `describe()` still works through this file's only other live
   caller).
5. `bash scripts/run-tests.sh` (full suite) — **PASS. 127 total, 127 passed, 0 failed.**

## Self-review

- Did not trust the previous round's own printed sample — re-derived every line in this
  section from an actual run, per the explicit instruction, including the four species NOT
  named as broken (Horse/Cow/Sheep, to prove the fix didn't regress them).
- Grepped for every direct reference to `SOURCE_PHRASES` by literal key or value across
  `project/tests/` before changing the dictionary's values, to confirm only `"rock"` is
  pinned by name and the wording change was safe.
- Chose the STRONGER of the two options the ruling offered (bare-noun data contract) AND
  the defensive option (normalize at point of use) rather than picking one — reasoned in
  the fix itself: the data-only fix protects today's dictionary, the code-side normalization
  protects against a future content-writer's edit reintroducing the same defect, which the
  ruling explicitly asked the fix to be robust against.
- Verified `_bare_noun()` is a true no-op on every phrase this file produces today by
  reading the full probe output above line by line, not just by the assertion count passing.
- Confirmed the probe test file was deleted before staging (`git status --porcelain` showed
  no `test_zzprobe2.gd`/`.uid` in the diff) before committing.
- Left `describe()` untouched, `_cheapest()`'s Cow/Open-Barn tie-break untouched, and the
  dropped icon chips untouched — all three explicitly called out as reviewed/accepted or
  out of scope for this round.

## Changed files (fix round 2, in addition to the original + fix-round-1 diff)

- `project/scripts/ui/habitat_recipe.gd` — `SOURCE_PHRASES`: `cultivated_field`/`house`
  entries changed to bare nouns; doc comment rewritten to state the bare-noun contract.
  `_need_phrase()`: both return paths now pass through a new `_bare_noun()` helper.
  `_with_article()`: doc comment updated to note its precondition is now guaranteed upstream.
- `project/tests/test_habitat_recipe.gd` — new `_check_no_article_defects_across_the_roster()`,
  scanning all 15 species' rendered tier lines for both symptom patterns.

## Proposals for the human (fix round 2, additive to the prior two rounds' lists)

1. **`describe()`'s two changed phrases now read slightly tersely** ("Likes ... house." /
   "... farm field." instead of "... a house." / "... a farm field."). Not a grammar error,
   not asked to be fixed this round, but worth a content-writer's eye alongside the other
   `[COPY]` items already listed, since `SOURCE_PHRASES` is their dictionary to eventually
   own.
2. All prior copy proposals from rounds 1 and the original pass still stand unchanged.
