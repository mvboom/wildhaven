# Wildhaven — Content Pipeline Status

> Authoritative, per-item **pipeline state** for every concrete species, terrain type,
> and building already defined in [roster.md](roster.md), [terrain.md](terrain.md), and
> [buildings.md](buildings.md) — where each item's asset came from, how far through
> [gdd.md](gdd.md) → AI Architecture → **Content Pipelines**' 8-step flow (Asset audit →
> Import & look pass → Design proposal → Data entry → Copy → Attribution → Validation →
> Human sign-off) it has gotten, and where to look to confirm each step. **This file
> replaces [art.md](art.md)'s three former per-item status tables** as the state of
> record.
>
> **What this file is not:** it does not duplicate gameplay data (habitat needs,
> footprints, costs — that's roster.md/terrain.md/buildings.md, with
> [spec.md](spec.md) as field-level ground truth), sourcing *narrative* (which pack was
> picked and why, gap substitutes, open sourcing tasks — that's art.md), the runnable
> import *procedure* (that's [asset-import-pipeline.md](asset-import-pipeline.md)),
> pack-level historical detail (that's
> [source-content/assets/ASSET_AUDIT.md](../source-content/assets/ASSET_AUDIT.md)), or license text
> (that's `project/attribution/sources/*.tres`, rendered to `project/CREDITS.md` — this
> file links to entries, never copies their text).
>
> **Who writes here:** [tech-art](../.claude/agents/tech-art.md) updates `source`,
> `pre_import_audit`, `project_location`, and `attribution_status` as it works;
> [gameplay-engineer](../.claude/agents/gameplay-engineer.md) updates
> `data_entry_location` when it lands the `.tres`;
> [content-writer](../.claude/agents/content-writer.md) updates
> `copy_content_location` when the copy lands (even when it lands in that same `.tres`);
> [qa-engineer](../.claude/agents/qa-engineer.md) updates `validation_status` after it
> runs schema/headless checks; the human fills `human_signoff`. **Every field has exactly
> one write-owner** — if you find yourself editing a field you don't own, report it
> instead. **`status` is not
> human-exclusive** — whoever last changes a field recomputes it from the legend below,
> the same way any of them would fix a stale value they noticed; the one hard rule is
> that it can only show ✅ once `human_signoff` is actually recorded. Every entry below
> was seeded against **actual current repo state** (not just re-glyphed from art.md's
> prose) as of 2026-07-26 — several items are less far along than earlier narrative
> implied, and that's called out explicitly rather than smoothed over.
>
> **Mechanics, read before editing:**
> - Every field name below is exact and used consistently in every per-item block —
>   `source`, not "Source"; `attribution_status`, not "Attribution." Other documents
>   (asset-import-pipeline.md, tech-art.md, qa-engineer.md) reference these same exact
>   names; if you rename a field here, update those references too.
> - **One field per row, always** — even a not-started field gets its own row saying
>   "not started." Never collapse several fields into one combined row: the next update
>   only touches one field, and a combined row has to be split apart to do that safely.
> - **Two places track status per item — the category's scan table row and the item's
>   own `status` row below it — and they must always agree.** Updating one without the
>   other is an incomplete edit, not a finished one.
> - **Adding an item that isn't here yet** (a new species/terrain/building's first
>   pipeline run): add its `id` to the category's scan table, then copy the field list
>   from any existing item in that category as the template, in the same order, before
>   filling in real values. Creating the entry is part of finishing the work.
> - **Resuming a partial item.** An item entering the pipeline mid-flow runs only the
>   steps its row shows open, in canonical order — **the tracker row *is* the resume
>   plan**, so there is no separate short-form pipeline to look up. When N items share the
>   same open steps, **batch by step, not by item**: one dispatch per step covering all N,
>   one human gate per step. Never one pipeline run per item — orchestration cost scales
>   with dispatch count, not with agent work (gdd.md → Technical Strategy #5), so nine
>   items with five open steps is five dispatches and two gates, not forty-five and
>   eighteen.

## Status Glyphs

| Glyph | Meaning |
|---|---|
| ✅ | **Done** — all 8 pipeline steps complete, human sign-off recorded, live in project |
| 🚧 | **In progress** — somewhere between "not started" and "validated, sign-off pending" |
| 🛒 | **Sourcing resolved, acquisition pending** — a cleared source is identified (step 1 passed) but nothing has been imported yet (purchase not made, or file not yet hand-carried in) |
| ⛔ | **Blocked** — the item is genuinely required and cannot proceed; name the blocker. Currently unused. **Not for "we wanted this and no asset exists"** — an item with no cleared source is simply not a roster/terrain/building item and gets no row here; the sourcing finding lives in [art.md](art.md). |

## Fields

Every field maps to one of gdd.md's 8 canonical pipeline steps, or is identity/
navigation, not a step. **Step 3 (Design proposal → human decision) has no dedicated
field here** — its artifact *is* the "Already-Defined" row in roster.md/terrain.md/
buildings.md that `category_attributes` links to; tracking it twice would duplicate,
not clarify.

| Field | Pipeline step | Meaning |
|---|---|---|
| `id` | — | matches the id used in roster.md/terrain.md/buildings.md and in the `.tres` data definition, where one exists |
| `category` | — | `roster` \| `terrain` \| `building` |
| `category_attributes` | — | one-line summary (not the full schema) + link to the item's row |
| `source` | 1. Asset audit | pack/creator + license id; link to the specific `project/attribution/sources/*.tres` entry (never the license text itself) |
| `pre_import_audit` | 1. Asset audit | commercial-use clearance, animation-exists check (roster), style-fit check |
| `project_location` | 2. Import & look pass | path under `project/assets/...` for the imported/configured asset |
| `data_entry_location` | 4. Data entry | path under `project/data/...` for the `.tres` data definition instance — **owned by gameplay-engineer** |
| `copy_content_location` | 5. Copy | where the written fact-card/flavor copy lives — in practice the same `.tres`'s `fact_text` field; tracked as its own step because Content Writer's deliverable and sign-off gate are distinct from Data Entry even when they land in the same file — **owned by content-writer** |
| `attribution_status` | 6. Attribution | done/not-required/pending + link to the attribution `.tres` entry |
| `validation_status` | 7. Validation | pass/fail + which test files — **owned by qa-engineer** |
| `human_signoff` | 8. Human sign-off | who/when, or what's still blocking it |
| `status` | computed | single glyph, see legend above |

**Scoping note:** art.md's asset tables also mention **Flowers** (in-vocabulary tag, no
v1 consumer, no terrain.md row of its own), **Move-in props** (the Den — a decorative
prop, not a terrain/building category item; see `project/assets/props/den/`), and
**Ambient life** (deferred `future.md` "Charm layer" scope). None gets a row below —
deliberate scoping, not an oversight, since none is a roster/terrain/building item as
`category` defines it.

---

## Roster

**Read the `class` column before reading the glyphs.** Only the three **floor** species are
Tier 1 (gdd.md row 8). The **cleared pool** is nine species already past the expensive
gates — licence-cleared, imported, attributed, import-tested — waiting on design values.
Everything past the floor is a depth purchase, so a 🚧 in the pool is *available work*, not
debt against the floor.

| id | Class | Status |
|---|---|---|
| `rabbit` | floor | ✅ |
| `fox` | floor | ✅ |
| `human` | floor | ✅ |
| `deer` | cleared pool | 🚧 |
| `stag` | cleared pool | 🚧 |
| `horse` | cleared pool | 🚧 |
| `donkey` | cleared pool | 🚧 |
| `cow` | cleared pool | 🚧 |
| `bull` | cleared pool | 🚧 |
| `alpaca` | cleared pool | 🚧 |
| `husky` | cleared pool | 🚧 |
| `shiba_inu` | cleared pool | 🚧 |
| `chicken` | designed, unsourced | 🛒 |
| `duck` | designed, unsourced | 🛒 |

**The roster has no target number.** It is a floor of three plus whatever depth the hours
buy. Species that were named in early design and for which **no cleared asset was ever
found are not tracked here at all** — they were never roster members in any shippable sense,
and carrying them as ⛔ rows made a sourcing outcome read as a failure against a target.
The sourcing findings survive in [art.md](art.md) as a watch-list so the search is not
repeated.

**The nine cleared-pool species share the same open steps** — 3 (design proposal), 4 (data
entry), 5 (copy), 8 (sign-off). That makes them the textbook case for the resume rule above:
**batch by step, not by item.** They are the cheapest available depth in the project because
the expensive gates are already behind them, and they are sequenced at the week 2–3 velocity
review. See [tier1-status.md](tier1-status.md) row 8.

**`chicken` and `duck` are designed but unsourced** — their assets resolve to a Synty SIMPLE
purchase that has not been made. **Whether to make it at all is a velocity-review call**
now that nine free cleared species exist; Duck is the only water-habitat species in any list,
which is the argument for it.

**`human` is the only floor row still open**, and gdd.md names it the single point of
failure in the floor. **Step 4 (data entry) closed 2026-07-27** — `project/data/animals/human.tres`
landed alongside the Tier-1 rows 3–6 simulation dispatch, since row 4's villager move-in is
the USP proof and cannot run without it. **Step 5 (copy) closed 2026-07-28** — Open Question
#31's fact card is written and source-verified against ADW's *Homo sapiens* account, so the
half with no fallback is done. Its remaining open steps are **7 (re-validation, because the
copy edit invalidates the assertions that pinned the placeholder) and 8 (sign-off)**.

### `rabbit` — Rabbit

| Field | Value |
|---|---|
| `category_attributes` | open_grass + cover · Bold · avoids Fox · `tiles_per_individual` 12 · floor species — [roster.md](roster.md#already-defined-roster) |
| `source` | "Rabbit" by Sherkiz, via Poly Pizza — CC BY 3.0, **attribution required** — [`sherkiz_rabbit.tres`](../project/attribution/sources/sherkiz_rabbit.tres) |
| `pre_import_audit` | done — animated, license terms confirmed and tracked (first binding attribution obligation in the project), style fit accepted |
| `project_location` | `project/assets/animals/rabbit/Rabbit.tscn` |
| `data_entry_location` | `project/data/animals/rabbit.tres` |
| `copy_content_location` | same file, `fact_text` — cleared all four checklist steps including source verification (Animal Diversity Web, Wildlife Trusts) |
| `attribution_status` | done — required notice recorded in `sherkiz_rabbit.tres`, rendered in `project/CREDITS.md`. Note: the in-game Credits *screen* (row 15, UI Engineer scope) doesn't exist yet — the license's "visible to the player" condition isn't satisfied until that ships, even though the data-layer attribution record is complete |
| `validation_status` | pass — `test_rabbit_schema.gd`, `test_rabbit_animations.gd`, `test_rabbit_spawn.gd` exist and pass; exact pass date predates this tracker (qa-engineer to date on next run) |
| `human_signoff` | **BACKFILLED 2026-07-28 by the human (→ D-27).** Signed off during pilot 3b; the tracker that records sign-off did not exist yet, and `rabbit.tres`'s own comments already note the `fact_text` was "picked by the human at step-8 sign-off." Recorded as a backfill, **not** a fresh review — the original decision stands, only its record was missing. Clears a standing Gate-4 failure in [release-checklist.md](release-checklist.md). |
| `status` | ✅ |

### `fox` — Fox

| Field | Value |
|---|---|
| `category_attributes` | forest + cover · Shy · avoids Rabbit · `tiles_per_individual` 12 · floor species — [roster.md](roster.md#already-defined-roster) |
| `source` | Quaternius, "Ultimate Animated Animal Pack" — CC0 1.0 Universal — [`quaternius_ultimate_animated_animals.tres`](../project/attribution/sources/quaternius_ultimate_animated_animals.tres) |
| `pre_import_audit` | done — animated, CC0, style fit accepted |
| `project_location` | `project/assets/animals/fox/Fox.tscn` |
| `data_entry_location` | `project/data/animals/fox.tres` |
| `copy_content_location` | same file, `fact_text` — option B2, a post-verification rewrite after the original shipped copy failed source verification (ADW male-den contradiction); all four checklist steps now satisfied |
| `attribution_status` | not required (CC0) — courtesy entry recorded, rendered in `project/CREDITS.md` |
| `validation_status` | pass — `test_fox_schema.gd`, `test_fox_animations.gd`, `test_fox_spawn.gd` exist and pass; exact pass date predates this tracker |
| `human_signoff` | **BACKFILLED 2026-07-28 by the human (→ D-27).** Signed off during pilot 3, including the register decision ("kits," never "cubs") and the post-verification copy correction that pilot surfaced. Recorded as a backfill, **not** a fresh review. Clears a standing Gate-4 failure in [release-checklist.md](release-checklist.md). |
| `status` | ✅ |

### `human` — Human (Villager)

| Field | Value |
|---|---|
| `category_attributes` | house + cultivated · Bold · no avoids · `tiles_per_individual` 1 · floor species, the roster's single remaining open gate — [roster.md](roster.md#already-defined-roster) |
| `source` | **18 Quaternius character models across 3 CC0 1.0 Universal source entries, one of which is a CORRECTION of a previously-wrong record.** (a) 4 standalone poly.pizza-style glbs — Adventurer, Punk, HoodieCharacter, AnimatedWoman — [`quaternius_poly_pizza_characters.tres`](../project/attribution/sources/quaternius_poly_pizza_characters.tres). (b) 6 from **"Animated Men Characters" (Feb 2019)** — [`quaternius_animated_men_characters.tres`](../project/attribution/sources/quaternius_animated_men_characters.tres), NEW entry with the pack's own `License.txt` copied to `project/assets/licenses/Quaternius_AnimatedMenCharacters_License.txt`. (c) 8 from **"Animated Women Characters" (Feb 2019)** — [`quaternius_animated_women_characters.tres`](../project/attribution/sources/quaternius_animated_women_characters.tres), NEW entry, its own `License.txt` copied to `project/assets/licenses/Quaternius_AnimatedWomenCharacters_License.txt`. **`Man` MOVED FROM (a) TO (b):** the shipped `human_man/Man.glb` is `Male_Casual` from the men's pack — the pack was on disk in `source-content/assets/` and the model had been re-downloaded standalone, so (a) recorded it as an unidentified single-model download and explained its rig as "a modeling-generation difference." Measured evidence for the correction (six materials matching the pack's `Smooth_Male_Casual` to 4dp, same `HumanArmature` rig, same 11 clip names, AABB matching to 1e-6) is in the men's entry. **No compliance consequence** — same creator, same CC0 dedication, nothing about what may be shipped changes; the file itself is untouched. |
| `pre_import_audit` | done — all 5 original variants confirmed animated/imported; all 5 wired into `model_scenes`, equal-weight (Adventurer at index 0). **13 MORE VARIANTS AUDITED AND IMPORTED (character-pack batch):** `Male_LongSleeve`, `Male_Shirt`, `Smooth_Male_Casual`, `Smooth_Male_LongSleeve`, `Smooth_Male_Shirt` from the men's pack; `Female_Alternative/Casual/Dress/TankTop` and their four `Smooth_` twins from the women's pack. CC0 confirmed from each pack's own `License.txt` before import. **Animations verified per model, not assumed:** one `AnimationPlayer`, 11 clips, `HumanArmature` rig (42 bones). **A brief-supplied clip name was WRONG and was corrected by measurement:** the men's models name their clips `HumanArmature|Man_*`, not `Male_*` (same convention the shipped `Man.glb` uses); the women's are `HumanArmature|Female_*`. **Texture/material audit run on every raw file:** `albedo_texture` null everywhere and NO surface carries an `ARRAY_COLOR` channel, so the FBX importer's `vertex_color_use_as_albedo = true` is inert and colour comes entirely from per-surface `albedo_color`, which is distinct and meaningful on every surface — not the uniform ~0.9063 grey that flagged the DeadTree/PineTree2 bug. No fix needed. **`Male_Suit` and `Smooth_Male_Suit` were HELD OUT** of the batch: shirt and pants at `Kd 0.0185` are effectively pure black, which art.md's palette rule excludes. That is a rule applied, not a taste call — reversible if the human overrules it. Every model that did ship was checked against the same rule; the darkest garment anywhere is linear 0.1652 (~44% sRGB grey). **Rig footnote:** the shipped `Man.glb` has 31 bones where the pack FBX files have 42, despite identical armature and clip names — consistent with the `.glb` export dropping unskinned/unanimated bones. Recorded, not corrected; no retarget involved. **Both the base and `Smooth_` sets were imported on purpose** so the base-vs-smooth comparison can be made in-engine; the losing set gets pulled later. |
| `project_location` | `project/assets/animals/human_adventurer/Adventurer.tscn` (+ 4 sibling variants: `human_punk`, `human_man`, `human_hoodie`, `human_woman`) — the 5 wired variants, unchanged. **13 more locations added, NOT wired:** `human_male_longsleeve/MaleLongSleeve.tscn`, `human_male_shirt/MaleShirt.tscn`, `human_smooth_male_casual/SmoothMaleCasual.tscn`, `human_smooth_male_longsleeve/SmoothMaleLongSleeve.tscn`, `human_smooth_male_shirt/SmoothMaleShirt.tscn`, `human_female_alternative/FemaleAlternative.tscn`, `human_female_casual/FemaleCasual.tscn`, `human_female_dress/FemaleDress.tscn`, `human_female_tanktop/FemaleTankTop.tscn`, `human_smooth_female_alternative/SmoothFemaleAlternative.tscn`, `human_smooth_female_casual/SmoothFemaleCasual.tscn`, `human_smooth_female_dress/SmoothFemaleDress.tscn`, `human_smooth_female_tanktop/SmoothFemaleTankTop.tscn` — each wraps its own raw `.fbx` in the same directory (source name with underscores stripped, matching this asset's existing naming convention), each with `autoplay` set to its own idle clip and a per-model measured scale (`1 / measured AABB height`, 0.206558–0.214896) in its header. **Adding these to `human.tres`'s `model_scenes` is gameplay-engineer's step and was deliberately not done here.** |
| `data_entry_location` | `project/data/animals/human.tres` — `AnimalDefinition`, landed 2026-07-27 with the Tier-1 rows 3–6 simulation dispatch, because row 4's USP proof cannot run without it. Values transcribed from roster.md's **already-decided** row, not proposed here: `habitat_needs = ["house", "cultivated"]`, `personality = "Bold"`, `avoids = []`, `farm_tolerant = true`, `tiles_per_individual = 1`. `model_scenes` → 5 entries (`human_adventurer/Adventurer.tscn` at index 0, plus `human_man`/`human_woman`/`human_hoodie`/`human_punk`). **`scout_radius = 8` is a PLACEHOLDER** at the tight end of spec.md's ~8–12 band (#20) — no Human value is stated anywhere; the proposal and its reasoning are in the `.tres` header and in the build report. **`fact_text` is a `PLACEHOLDER`-prefixed string (#31)** — deliberately not written by the gameplay engineer; the register is decided, the copy is not. `AnimalDefinition.validate()` therefore reports this entry as awaiting step-8 sign-off, which is the schema working, not a defect. **2026-08-29 (character-pack wiring, Content Pipeline step 4): `model_scenes` grown 5 → 18** — 13 already-imported/attributed/import-tested character wrappers appended; index 0 (Adventurer) unchanged. **Base and `Smooth_` sets are BOTH wired on purpose**, on the human's "import both, decide in-engine" ruling — a temporary comparison state; the losing set gets pulled. **`Male_Suit` / `Smooth_Male_Suit` are held out** on art.md's palette rule (`Kd 0.0185`, effectively pure black) — their absence is intentional. No other `AnimalDefinition` field changed; `fact_text_pool` is untouched and a variant does not get its own fact card |
| `copy_content_location` | **done (2026-07-28), and REVISED THE SAME DAY BY A SECOND-SOURCE PASS — the shipped string changed.** Same file, `fact_text`. Open Question #31's copy is now **double-sourced per clause**, matching the fox's standard: [ADW *Homo sapiens*](https://animaldiversity.org/accounts/Homo_sapiens/) plus four Nat Geo Society Education pages ([The Development of Agriculture](https://education.nationalgeographic.org/resource/development-agriculture/), [Hunter-Gatherer Culture](https://education.nationalgeographic.org/resource/hunter-gatherer-culture/), [Agricultural Communities](https://education.nationalgeographic.org/resource/resource-library-agricultural-communities/), [Early Agricultural Communities](https://education.nationalgeographic.org/resource/early-agricultural-communities/)). It was single-sourced at first landing only because Nat Geo Kids' whole domain was unreachable; the domain is back and `education.nationalgeographic.org` has since been added to spec.md's approved set. **Outcome: partially corroborated — two of three clauses were rewritten**, and the pass earns its cost. (1) *nomadic before settled* corroborated unchanged. (2) **"About 10,000 years ago" was over-precise and is now "About 10,000 to 12,000 years ago"** — the approved sources disagree (ADW and *Agricultural Communities* say ~10,000; *The Development of Agriculture* and *Hunter-Gatherer Culture*, the two most on-point pages, say ~12,000; *Early Agricultural Communities* says 10,000–15,000), so the old flat number sat at the extreme low edge of the range and was contradicted by the best sources. (3) **"that is when people began to settle down" pinned a gradual process to a moment** and is now "little by little they settled down in one place" — *The Development of Agriculture* states outright that "the transition from wild harvesting was gradual", and describes settling as *marked by*, not caused at, a date. **Nat Geo Kids is reachable but has no human-origins or agriculture page** — recorded in the `.tres` so the search is not re-run. Per-clause quotes, the banned-vocabulary note (ADW's sentence reads "nomadic hunter gatherers"; the copy rests on the conclusion and never shows that work), and the roster-wide terminology findings — "town"/"village" cut, and the new **"settled in" near-miss** against fox/rabbit News Report copy, cleared and recorded — are all in the `.tres` header. **Awaiting step-8 human sign-off** and re-validation |
| `attribution_status` | not required (CC0) — courtesy entries recorded. **Two NEW entries authored** (`quaternius_animated_men_characters.tres`, `quaternius_animated_women_characters.tres`), each with the pack's own `License.txt` copied into `project/assets/licenses/` rather than reusing the shared generic Quaternius CC0 boilerplate. **One entry CORRECTED:** `Man` removed from `quaternius_poly_pizza_characters.tres`'s `assets_used` and recorded under its real pack as `Male_Casual`; both entries' `notes` say what changed and why, and `Man.tscn`'s own header pointer was updated to match. `CREDITS.md` regenerated (12 sources, 1 with binding obligations). `test_attribution.gd`'s source-count ratchet bumped 10 → 12 **and extended** with assertions that pin the correction (Man absent from the poly.pizza entry, `Male_Casual` present in the men's entry, both new license files on disk) so it cannot silently revert. |
| `validation_status` | **pass (2026-07-28, updated) — OPEN QUESTION #31'S COPY IS NOW VALIDATED, AND THE PLACEHOLDER PINS ARE RE-POINTED.** `bash scripts/run-tests.sh` **50/50 green, 1550 assertions** (47/47 and 1187 before this pass, of which 2 suites were correctly RED against this file: content-writer's copy edit deliberately invalidated the assertions that pinned the placeholder, which is the ratchet working). **`test_human_schema.gd` 41 → 68 assertions.** `fact_text` is now pinned as an **exact string**, the way `test_fox_schema.gd` and `test_rabbit_schema.gd` pin shipped copy — the wording is what cleared all five checklist steps, so any drift, even a typo fix, invalidates that clearance and fails loudly rather than passing a fuzzy “non-empty” check. Asserted alongside it: it is **not** `PLACEHOLDER`-prefixed, does not contain the marker anywhere, and no longer renders an open-question number to the player. **BANNED-VOCABULARY SWEEP, word-boundary matched** (not substring, so “osprey”/“great” cannot false-fail): `hunt`/`hunter`/`hunters`/`hunting`/`hunts`, `gather`/`gatherer`/`gatherers`/`gathering`/`gathers`, `prey`, `kill`/`kills`/`killing`. **`gather*` is in the set for a reason specific to this card and recorded in the `.tres`:** ADW's source sentence reads “nomadic hunter gatherers” and the copy rests on the conclusion instead of showing that work, so a future editor “restoring” the source wording is exactly what the sweep exists to catch. **The sweep has its own negative control:** the identical matcher run over ADW's own wording fires on exactly the two words it should (`gatherers`, `hunter`), so the clean result is a measurement and not a broken regex or an empty list. **The roster-wide terminology finding is mechanized too** — `town`/`towns`/`village`/`villages`/`villager`/`villagers` are asserted absent, because `display_name` is “Villager” and the HUD counter is “Village Population”, so a real-world claim carrying those words would read as a claim about the game world (the two-register rule); and the copy is asserted to name no other roster species, keeping the predation graph closed by copy as well as by data. **`validate()` is CLEAN for the first time** — zero problems with and without a roster, where the pinned state was “exactly one problem, the `fact_text` placeholder” — **with a negative control that a clone carrying the placeholder again still reports exactly one `fact_text` problem**, so “clean” is a real check and not a validator that never speaks. **`test_fact_card.gd` 40 → 53 assertions:** the villager's card is asserted at the **render surface**, on the real `Main.tscn` — `%Body` equals the data's `fact_text` verbatim **and** equals the shipped literal (two independent pins, so a card and a `.tres` cannot drift together), the word PLACEHOLDER is gone from what a playtester would see, the banned-word sweep is re-run on the rendered text with its own matcher control, and **no roster species renders placeholder copy at all** — so a fourth species added with a placeholder fails on the day it lands. Everything the 2026-07-27 pass validated is unchanged and still green: typed binding asserted before any field is read, `id`/`display_name`, `habitat_needs == ["house", "cultivated"]`, `personality == "Bold"`, `farm_tolerant`, `tiles_per_individual == 1`, `scout_radius == 8`, `avoids` empty in all three forms, every field's type including the typed `Array[String]`s, both needs in the shared ten-tag vocabulary, the inert-land invariant, `model_scene` pinned to the Adventurer variant and instantiable as a `Node3D`, and `SpeciesRoster.by_id("human")` returning *this* resource. End to end, the villager still lands through the ordinary qualification path in `test_causality_end_to_end.gd`, and it is now also **displaced** through it in the new `test_gentle_displacement.gd`, which removes the occupied House and asserts the warning names this entry's own `display_name`. Import suites unchanged: `test_human_adventurer_import.gd` + 4 siblings. **STILL NOT VALIDATED AND NOT VALIDATABLE HERE: the sourcing itself.** Machine checks cover the schema, the exact string, the banned sets and the register; whether ADW's *Homo sapiens* account actually supports each clause is the step-8 human read, and `human.tres`'s own header says “AWAITING STEP-8 SIGN-OFF”. Also still a proposal, not a ruling: `scout_radius = 8` (#20). **RE-VALIDATED 2026-08-29 (pin re-point after the sanctioned `model_scenes` growth):** the 2026-08-29 asset-audit sweep grew `human.tres`'s `model_scenes` 5 -> 18 (13 Animated Men/Women character variants appended; no schema change, no other field touched), which correctly turned two pins in `test_human_schema.gd` RED -- the ratchet working, exactly as `human.tres`'s own header predicted. Both are now **re-pointed, not relaxed**: `check_eq(human.model_scenes.size(), 18)` and the exact ORDERED 18-path list, read out of the `.tres` rather than reconstructed. The list stays an exact-order `check_eq` on purpose -- a `>=` or a prefix match would let an unreviewed content edit land silently, which is the one thing this pin exists to prevent. `model_scenes[0]` keeps its own separate assertion that it is STILL `Adventurer.tscn` (the shipped default staying first is load-bearing for saves and for `world_root.gd`'s style defaults), and every entry is still asserted `PackedScene` + `can_instantiate()`, so all 13 new wrappers are load-tested here as well. `test_human_schema.gd` 112 -> 114 assertions, 0 failed. **Full suite `bash scripts/run-tests.sh`: 91/91 suites pass, 0 failed, zero SCRIPT ERROR.** Nothing else in this row's validation changed -- fact_text exact-string pin, banned-vocabulary sweep and its negative control, the two-register terminology checks, the inert-land invariant and the `SpeciesRoster.by_id` identity check are all untouched and still green. **STILL NOT VALIDATED HERE, unchanged: the sourcing itself (step 8), and `scout_radius = 8` remains a proposal (#20).** |
| `human_signoff` | **2026-07-28 — approved.** Closes Open Question #31 (the fact card, double-sourced and corrected against a second source the same day) and #20's Human-specific value (`scout_radius = 8`, the `PROPOSED` marker in [tier1-status.md](tier1-status.md) row 6 removed accordingly). Recorded as **D-28** in [decisions.md](../decisions.md). |
| `status` | ✅ — the floor species itself is unchanged and still fully signed off (D-28); the 5 wired look variants, the data, and the copy are all live. **KEPT AT ✅ DELIBERATELY, flagged rather than decided:** 13 more look variants were imported, attributed and import-tested in the character-pack batch; **they were wired into `model_scenes` on 2026-08-29 (5 → 18)** on the human's "import both, decide in-engine" ruling, and they remain **not design-proposed and not eyeball-signed-off**. Nothing shippable regressed — they are available depth, the same posture the doc uses for the cleared pool, not open debt against the floor — so downgrading a floor species to 🚧 would misreport the build. If the reading should instead be "the item has open steps, therefore 🚧", that is a one-glyph change here plus the Roster scan table; raised for the human/qa-engineer rather than taken unilaterally. Open for the 13: **base-vs-`Smooth_` comparison** (both sets were imported precisely so this can be judged in-engine — the loser gets pulled), **facing** (all identity, unconfirmed), and one **scale consequence worth a look**: per-model `1 / measured height` normalises every villager to exactly 1.0 tile, which erases the ~3.8% height difference between the men's and women's raw meshes. A single shared factor (e.g. 0.207 for all 18) is the alternative if men and women should read as different heights. Import-tested by `test_human_pack_variants_import.gd` (105 assertions, green). |

### `chicken` — Chicken

| Field | Value |
|---|---|
| `category_attributes` | cultivated + open_grass · Bold · farm-tolerant · `tiles_per_individual` proposed — [roster.md](roster.md#already-defined-roster) |
| `source` | none viable in Quaternius (both live candidates rejected — armature-only, no real walk/idle cycle, off-style); resolved to buy Synty SIMPLE Farm Animals Cartoon — **not yet purchased** |
| `pre_import_audit` | sourcing resolved; purchase still open |
| `project_location` | not started |
| `data_entry_location` | not started |
| `copy_content_location` | not started |
| `attribution_status` | not started |
| `validation_status` | not started |
| `human_signoff` | not started |
| `status` | 🛒 |

### `duck` — Duck

| Field | Value |
|---|---|
| `category_attributes` | water + cover · Bold · not farm-tolerant · `tiles_per_individual` proposed — [roster.md](roster.md#already-defined-roster) |
| `source` | none in Quaternius (no waterfowl at all); resolved to buy Synty SIMPLE Farm Animals Cartoon (same purchase as Chicken) — **not yet purchased** |
| `pre_import_audit` | sourcing resolved; purchase still open |
| `project_location` | not started |
| `data_entry_location` | not started |
| `copy_content_location` | not started |
| `attribution_status` | not started |
| `validation_status` | not started |
| `human_signoff` | not started |
| `status` | 🛒 |

### `deer` — Deer

| Field | Value |
|---|---|
| `category_attributes` | proposed open_grass, forest · Shy (art.md → Newly Available Animals) — no roster.md row yet; not yet a design-locked species |
| `source` | Quaternius, "Ultimate Animated Animal Pack" — CC0 1.0 Universal — [`quaternius_ultimate_animated_animals.tres`](../project/attribution/sources/quaternius_ultimate_animated_animals.tres) |
| `pre_import_audit` | done (2026-07-26) — 13 animation clips confirmed including required Idle/Walk (non-degenerate, 48 tracks each); style fit not rejected but not eyeball-confirmed — see header comment in `Deer.tscn` |
| `project_location` | `project/assets/animals/deer/Deer.tscn` |
| `data_entry_location` | not started |
| `copy_content_location` | **4 card(s) generated** (2026-08-17) by `scripts/fact_card_pipeline.py` (Generator/Evaluator/Refiner/Circuit-Breaker loop, cross-model validated) -- landed directly in `project/data/animals/deer.tres`'s `fact_text_pool`, **awaiting step-8 human sign-off** (at least one OTHER requested candidate was also circuit-breaker-escalated this run -- see the log). Full attempt log: `scripts/fact_card_pipeline_output/deer.json` |
| `attribution_status` | not required (CC0) — courtesy entry recorded, `assets_used` extended, rendered in `project/CREDITS.md` |
| `validation_status` | import-level only — `test_deer_animations.gd` exists and passes (9/9 checks) |
| `human_signoff` | not started — scale (0.2, matching Fox's factor for this pack) not yet eyeball-confirmed |
| `status` | 🚧 — asset imported, audited, attributed, validated; data entry, copy, sign-off all still open. Cleared-pool species awaiting a step-3 proposal |

### `stag` — Stag

| Field | Value |
|---|---|
| `category_attributes` | proposed forest, cover, rocks · Shy, "trophy" (art.md → Newly Available Animals) — no roster.md row yet; not yet a design-locked species |
| `source` | Quaternius, "Ultimate Animated Animal Pack" — CC0 1.0 Universal — [`quaternius_ultimate_animated_animals.tres`](../project/attribution/sources/quaternius_ultimate_animated_animals.tres) |
| `pre_import_audit` | done (2026-07-26) — 13 animation clips confirmed including required Idle/Walk (non-degenerate, 42 tracks each); style fit not rejected but not eyeball-confirmed — see header comment in `Stag.tscn` |
| `project_location` | `project/assets/animals/stag/Stag.tscn` |
| `data_entry_location` | not started |
| `copy_content_location` | **PROPOSED, homeless** — [`docs/content/cleared-pool-fact-cards.md`](../docs/content/cleared-pool-fact-cards.md) § Stag. Source-verified (ADW *Cervus elaphus* + The Wildlife Trusts' Red Deer page); no `.tres` field exists to receive it yet |
| `attribution_status` | not required (CC0) — courtesy entry recorded, `assets_used` extended, rendered in `project/CREDITS.md` |
| `validation_status` | import-level only — `test_stag_animations.gd` exists and passes (9/9 checks) |
| `human_signoff` | not started — scale (0.2, matching Fox's factor for this pack) not yet eyeball-confirmed; tallest of the 9 new imports, flagged for a look at proportion against the rest of the roster |
| `status` | 🚧 — asset imported, audited, attributed, validated; data entry, copy, sign-off all still open. Cleared-pool species awaiting a step-3 proposal |

### `horse` — Horse

| Field | Value |
|---|---|
| `category_attributes` | proposed open_grass, cultivated · Bold, farm-tolerant (art.md → Newly Available Animals) — no roster.md row yet; not yet a design-locked species |
| `source` | Quaternius, "Ultimate Animated Animal Pack" — CC0 1.0 Universal — [`quaternius_ultimate_animated_animals.tres`](../project/attribution/sources/quaternius_ultimate_animated_animals.tres) |
| `pre_import_audit` | done (2026-07-26) — 13 animation clips confirmed including required Idle/Walk (non-degenerate, 52 tracks each); style fit not rejected but not eyeball-confirmed — see header comment in `Horse.tscn`. Note: `Horse_White` colour variant exists in the same pack, deliberately not imported (out of this task's scope) |
| `project_location` | `project/assets/animals/horse/Horse.tscn` |
| `data_entry_location` | not started |
| `copy_content_location` | **PROPOSED, homeless** — [`docs/content/cleared-pool-fact-cards.md`](../docs/content/cleared-pool-fact-cards.md) § Horse. Source-verified (ADW *Equus caballus*); Nat Geo Kids has no domestic-horse page (only Przewalski's horse, a different species, checked and not used); no `.tres` field exists to receive it yet |
| `attribution_status` | not required (CC0) — courtesy entry recorded, `assets_used` extended, rendered in `project/CREDITS.md` |
| `validation_status` | import-level only — `test_horse_animations.gd` exists and passes (9/9 checks) |
| `human_signoff` | not started — scale (0.2, matching Fox's factor for this pack) not yet eyeball-confirmed |
| `status` | 🚧 — asset imported, audited, attributed, validated; data entry, copy, sign-off all still open |

### `donkey` — Donkey

| Field | Value |
|---|---|
| `category_attributes` | proposed open_grass, cultivated · Bold, farm-tolerant (art.md → Newly Available Animals) — no roster.md row yet; not yet a design-locked species |
| `source` | Quaternius, "Ultimate Animated Animal Pack" — CC0 1.0 Universal — [`quaternius_ultimate_animated_animals.tres`](../project/attribution/sources/quaternius_ultimate_animated_animals.tres) |
| `pre_import_audit` | done (2026-07-26) — 13 animation clips confirmed including required Idle/Walk (non-degenerate, 53 tracks each); style fit not rejected but not eyeball-confirmed — see header comment in `Donkey.tscn` |
| `project_location` | `project/assets/animals/donkey/Donkey.tscn` |
| `data_entry_location` | not started |
| `copy_content_location` | **PROPOSED, homeless** — [`docs/content/cleared-pool-fact-cards.md`](../docs/content/cleared-pool-fact-cards.md) § Donkey. Source-verified (ADW *Equus asinus*); no `.tres` field exists to receive it yet |
| `attribution_status` | not required (CC0) — courtesy entry recorded, `assets_used` extended, rendered in `project/CREDITS.md` |
| `validation_status` | import-level only — `test_donkey_animations.gd` exists and passes (9/9 checks) |
| `human_signoff` | not started — scale (0.2, matching Fox's factor for this pack) not yet eyeball-confirmed |
| `status` | 🚧 — asset imported, audited, attributed, validated; data entry, copy, sign-off all still open |

### `cow` — Cow

| Field | Value |
|---|---|
| `category_attributes` | proposed cultivated, open_grass · Bold, farm-tolerant (art.md → Newly Available Animals) — no roster.md row yet; not yet a design-locked species |
| `source` | Quaternius, "Ultimate Animated Animal Pack" — CC0 1.0 Universal — [`quaternius_ultimate_animated_animals.tres`](../project/attribution/sources/quaternius_ultimate_animated_animals.tres) |
| `pre_import_audit` | done (2026-07-26) — 13 animation clips confirmed including required Idle/Walk (non-degenerate, 47 tracks each); style fit not rejected but not eyeball-confirmed — see header comment in `Cow.tscn`. **2026-07-26 human decision: keep Cow and Bull as separate roster spots for now** despite Bull sharing Cow's base mesh (see `bull` above). |
| `project_location` | `project/assets/animals/cow/Cow.tscn` |
| `data_entry_location` | not started |
| `copy_content_location` | **PROPOSED, homeless** — [`docs/content/cleared-pool-fact-cards.md`](../docs/content/cleared-pool-fact-cards.md) § Cow. Source-verified (ADW *Bos taurus*, general coat-color clause). **Corrected 2026-08-06 by a consistency-check pass**: the original draft's Holstein black-and-white-pattern claim didn't match the imported `Cow.gltf`'s materials (solid brown/tan, no black or white body material) and was replaced with ADW's general coat-color sentence, which the actual model does support; deliberately distinct from Bull's line below so the shared-mesh risk doesn't become a shared-copy risk too; no `.tres` field exists to receive it yet |
| `attribution_status` | not required (CC0) — courtesy entry recorded, `assets_used` extended, rendered in `project/CREDITS.md` |
| `validation_status` | import-level only — `test_cow_animations.gd` exists and passes (9/9 checks) |
| `human_signoff` | not started — scale (0.2, matching Fox's factor for this pack) not yet eyeball-confirmed |
| `status` | 🚧 — asset imported, audited, attributed, validated; data entry, copy, sign-off all still open |

### `bull` — Bull

| Field | Value |
|---|---|
| `category_attributes` | proposed cultivated, open_grass · Bold, farm-tolerant (art.md → Newly Available Animals) — no roster.md row yet; not yet a design-locked species |
| `source` | Quaternius, "Ultimate Animated Animal Pack" — CC0 1.0 Universal — [`quaternius_ultimate_animated_animals.tres`](../project/attribution/sources/quaternius_ultimate_animated_animals.tres) |
| `pre_import_audit` | done (2026-07-26) — 13 animation clips confirmed including required Idle/Walk (non-degenerate, 47 tracks each); style fit not rejected but **flagged**: Bull's mesh is the same base mesh as Cow (identical AABB, mesh literally named "Cow" in the raw glTF), so it may read as a recolor rather than a distinct silhouette — see header comment in `Bull.tscn`. **2026-07-26 human decision: keep Bull and Cow as separate roster spots for now** despite the shared mesh. |
| `project_location` | `project/assets/animals/bull/Bull.tscn` |
| `data_entry_location` | not started |
| `copy_content_location` | **2 card(s) generated** (2026-08-17) by `scripts/fact_card_pipeline.py` (Generator/Evaluator/Refiner/Circuit-Breaker loop, cross-model validated) -- landed directly in `project/data/animals/bull.tres`'s `fact_text_pool`, **awaiting step-8 human sign-off**. Full attempt log: `scripts/fact_card_pipeline_output/bull.json` |
| `attribution_status` | not required (CC0) — courtesy entry recorded, `assets_used` extended, rendered in `project/CREDITS.md` |
| `validation_status` | import-level only — `test_bull_animations.gd` exists and passes (9/9 checks) |
| `human_signoff` | not started — scale (0.2, matching Fox's factor for this pack) not yet eyeball-confirmed |
| `status` | 🚧 — asset imported, audited, attributed, validated; data entry, copy, sign-off all still open |

### `alpaca` — Alpaca

| Field | Value |
|---|---|
| `category_attributes` | proposed open_grass · Bold (art.md → Newly Available Animals) — no roster.md row yet; not yet a design-locked species |
| `source` | Quaternius, "Ultimate Animated Animal Pack" — CC0 1.0 Universal — [`quaternius_ultimate_animated_animals.tres`](../project/attribution/sources/quaternius_ultimate_animated_animals.tres) |
| `pre_import_audit` | done (2026-07-26) — 13 animation clips confirmed including required Idle/Walk (non-degenerate, 48 tracks each); style fit **flagged, not rejected**: raw AABB height (5.398) is taller than Horse (4.824) and close to Stag (5.378), likely an artifact of an alert/neck-up rest pose rather than the model's relaxed standing height — see header comment in `Alpaca.tscn` |
| `project_location` | `project/assets/animals/alpaca/Alpaca.tscn` |
| `data_entry_location` | not started |
| `copy_content_location` | **PROPOSED, homeless** — [`docs/content/cleared-pool-fact-cards.md`](../docs/content/cleared-pool-fact-cards.md) § Alpaca. Source-verified (ADW *Lama pacos*, cria terminology + humming); no `.tres` field exists to receive it yet |
| `attribution_status` | not required (CC0) — courtesy entry recorded, `assets_used` extended, rendered in `project/CREDITS.md` |
| `validation_status` | import-level only — `test_alpaca_animations.gd` exists and passes (9/9 checks) |
| `human_signoff` | not started — scale (0.2, matching Fox's factor for this pack) not yet eyeball-confirmed; the height/proportion flag above makes this one of the higher-priority items for a human look-pass |
| `status` | 🚧 — asset imported, audited, attributed, validated; data entry, copy, sign-off all still open |

### `husky` — Husky

| Field | Value |
|---|---|
| `category_attributes` | proposed house, open_grass · Bold, farm-tolerant, "village dog" (art.md → Newly Available Animals) — no roster.md row yet; not yet a design-locked species |
| `source` | Quaternius, "Ultimate Animated Animal Pack" — CC0 1.0 Universal — [`quaternius_ultimate_animated_animals.tres`](../project/attribution/sources/quaternius_ultimate_animated_animals.tres) |
| `pre_import_audit` | done (2026-07-26) — 12 animation clips confirmed including required Idle/Walk (non-degenerate, 54 tracks each — canids in this pack ship one fewer clip than the hooved animals, a single "Attack" instead of Attack_Headbutt + Attack_Kick); style fit not rejected but not eyeball-confirmed — see header comment in `Husky.tscn` |
| `project_location` | `project/assets/animals/husky/Husky.tscn` |
| `data_entry_location` | not started |
| `copy_content_location` | **PROPOSED, homeless** — [`docs/content/cleared-pool-fact-cards.md`](../docs/content/cleared-pool-fact-cards.md) § Husky. Source-verified (ADW's general *Canis lupus familiaris* account, the one clause naming huskies by breed); no `.tres` field exists to receive it yet |
| `attribution_status` | not required (CC0) — courtesy entry recorded, `assets_used` extended, rendered in `project/CREDITS.md` |
| `validation_status` | import-level only — `test_husky_animations.gd` exists and passes (9/9 checks) |
| `human_signoff` | not started — scale (0.2, matching Fox's factor for this pack) not yet eyeball-confirmed |
| `status` | 🚧 — asset imported, audited, attributed, validated; data entry, copy, sign-off all still open |

### `shiba_inu` — Shiba Inu

| Field | Value |
|---|---|
| `category_attributes` | proposed house, open_grass · Bold, farm-tolerant, "village dog" (art.md → Newly Available Animals) — no roster.md row yet; not yet a design-locked species |
| `source` | Quaternius, "Ultimate Animated Animal Pack" — CC0 1.0 Universal — [`quaternius_ultimate_animated_animals.tres`](../project/attribution/sources/quaternius_ultimate_animated_animals.tres) |
| `pre_import_audit` | done (2026-07-26) — 12 animation clips confirmed including required Idle/Walk (non-degenerate, 51 tracks each — same canid clip set as Husky); style fit not rejected but not eyeball-confirmed — see header comment in `ShibaInu.tscn`. Display name "Shiba Inu"; `id`/directory use `shiba_inu` |
| `project_location` | `project/assets/animals/shiba_inu/ShibaInu.tscn` |
| `data_entry_location` | not started |
| `copy_content_location` | **2 card(s) generated** (2026-08-17) by `scripts/fact_card_pipeline.py` (Generator/Evaluator/Refiner/Circuit-Breaker loop, cross-model validated) -- landed directly in `project/data/animals/shiba_inu.tres`'s `fact_text_pool`, **awaiting step-8 human sign-off**. Full attempt log: `scripts/fact_card_pipeline_output/shiba_inu.json` |
| `attribution_status` | not required (CC0) — courtesy entry recorded, `assets_used` extended, rendered in `project/CREDITS.md` |
| `validation_status` | import-level only — `test_shiba_inu_animations.gd` exists and passes (9/9 checks) |
| `human_signoff` | not started — scale (0.2, matching Fox's factor for this pack) not yet eyeball-confirmed |
| `status` | 🚧 — asset imported, audited, attributed, validated; data entry, copy, sign-off all still open |

---

## Terrain

| id | Status |
|---|---|
| `grass` | 🚧 |
| `water` | 🚧 |
| `forest` | 🚧 |
| `rock` | 🚧 |
| `cultivated_field` | 🚧 |
| `wild_grass` | 🚧 |
| `sand` | 🚧 |

**2026-08-16 look-pass (→ D-42):** all six v1 floor terrains now have REAL art wired as
their live `model_scenes` (pluralized from the old singular `model_scene` — D-42 gave
`TerrainDefinition` a stable per-tile variant picker), replacing every remaining grey-box.
`rock`, `forest`, `grass`, and `cultivated_field` now carry 2-4 `model_scenes` variants
each for genuine per-tile variety; `water` and `wild_grass` carry 1 (a variant pass wasn't
called for on either — water's variety comes from its animated shader, not multiple
meshes). Every item is still 🚧 because no human sign-off is recorded — this pass is a
tech-art proposal, not a final look, and every scale/density/color/treatment choice is
explicitly flagged in each item's row and in the underlying `.tscn`/`.tres` header
comments for the human's eyeball call. `sand` is depth, not floor, and remains untouched.

Before this pass: `grass`, `forest`, and `rock` had a single-variant imported asset each
(the 2026-08-03 "common set" pick); `water`, `cultivated_field`, and `wild_grass` were
still grey-box. New sourcing this pass came from individually-downloaded CC0 Quaternius
models via poly.pizza (recorded in the new
[`quaternius_poly_pizza_nature.tres`](../project/attribution/sources/quaternius_poly_pizza_nature.tres)
attribution entry) — no local vendor/pack directory exists in this repo, so `art.md`'s
"assets plentiful and free" note above was sourced fresh rather than hand-carried in.

**2026-08-16 SAME-DAY FOLLOW-UP (3 human eyeball fixes on the look-pass above):**

1. **Tile seams (all six terrains, and `cultivated_field`'s 2 variants too — every
   composed terrain scene):** every ground slab/surface widened X/Z from `0.94` to exactly
   `1.0`, matching `WorldGrid.TILE_SIZE` so adjacent tile edges meet with no sky-blue gap
   ("tiles did not have separation... you can't tell where the first tile ends" — the human
   meant the opposite of what shipped). Y (height) untouched everywhere; `water`'s
   deliberate -0.04 recess offset also untouched (X/Z-only fix). Applied identically across
   all 12 affected `.tscn` files — see each one's own header.
2. **`grass` / `wild_grass` density + height:** both rebuilt around a single
   `MultiMeshInstance3D` each (36 / 32 baked instances respectively) instead of hand-placed
   individual nodes, at a shorter scale baseline (0.075 / 0.065) — see their own rows below
   and each `.tscn`'s header for the full reasoning, including why a plain node-count
   increase was rejected (`terrain_view.gd`'s own per-tile node-count cost warning).
   `grass_common_tall` was left alone (only its slab widened per fix 1).
3. **`forest` variety:** a 3rd tree, `PineTree.tscn` (Quaternius "Pine Tree", CC0, sourced
   fresh via poly.pizza), added to `model_scenes` — a genuinely different conifer
   silhouette, not a third round-canopy "common tree" — see the `forest` row below.

Full suite (`bash scripts/run-tests.sh`) is green at 70/71 after this follow-up (1 new
test, `test_pine_tree_import.gd`, added; the 1 failure is the same pre-existing
`test_placeable_schema` gap, unrelated). Every item below remains 🚧 — this follow-up is
still tech-art proposal, not human-confirmed.

**`wild_grass` is new to this table** (added 2026-07-27 per the "adding an item"
procedure above). It was always a decided terrain in [terrain.md](terrain.md)'s
tag-source mapping — *"untouched revealed land … nothing, tag-inert"* — but had no row
here because it had no asset and no data entry. It has a data entry now, and it is the
one this project's inert-land invariant is derived from
(`TerrainDefinition.derive_bare_tags()`), so it needs to be trackable.

### `grass` — Grass (emits `open_grass`)

| Field | Value |
|---|---|
| `category_attributes` | emits `open_grass`; free to paint — [terrain.md](terrain.md#already-defined-terrain) |
| `source` | MegaKit `Grass_Common_Short` + `Grass_Common_Tall` (2 of several available variants — Nature Pack Grass/Crops Grass/Clover/Fern not evaluated) — CC0 — [`quaternius_stylized_nature_megakit.tres`](../project/attribution/sources/quaternius_stylized_nature_megakit.tres) |
| `pre_import_audit` | done — CC0 confirmed; style fit not yet eyeball-confirmed |
| `project_location` | `project/assets/terrain/grass_common_short/GrassCommonShort.tscn`, `project/assets/terrain/grass_common_tall/GrassCommonTall.tscn` |
| `data_entry_location` | `project/data/terrain/grass.tres` — `TerrainDefinition`, emits `open_grass`, `cost` 0. **COVERAGE PASS (2026-08-16, → D-42):** `model_scenes` (pluralized from `model_scene`) now carries BOTH `GrassCommonShort.tscn` and `GrassCommonTall.tscn` as stably-picked per-tile variants — Tall was previously imported but unused; both scenes were reworked first so either reads as full-tile coverage: `GrassCommonShort.tscn` grew from 6 to 10 scattered instances (denser, reaching closer to the tile edges) plus 2 subtle darker/lighter `PlaneMesh` floor patches; `GrassCommonTall.tscn` gained its first-ever slab + 8 scattered instances + 2 floor patches (it previously shipped as a single bare, ground-less prop, never wired). No tileable grass ground texture was found in the audited packs (`Grass.png` is a thin UV-strip palette texture for mesh vertex coloring, not a tiling texture — confirmed by inspection) — the blotchy multi-tone patch treatment is the documented fallback for that gap. See both `.tscn` header comments for the full transform list and reasoning. **SAME-DAY FOLLOW-UP (2026-08-16, human-reported): "still spotty… shorter height, and more instances (30+)."** `GrassCommonShort.tscn` was REBUILT around a single `MultiMeshInstance3D` (36 baked `Transform3D` instances — position/Y-rotation/scale jitter, deterministic fixed-seed scatter — instead of 30+ individual `MeshInstance3D` nodes, which `terrain_view.gd`'s own header flags as a real per-tile node-count cost at scale) at a shorter scale baseline (0.075, down from 0.112 — FLAG FOR HUMAN SIGN-OFF, no GDD number exists). `GrassCommonTall.tscn` was left untouched by this follow-up (only its slab widened, see below) — the human's density/height complaint was addressed via `GrassCommonShort`, the terrain's other live variant. Also in this same pass: every terrain slab (including both grass scenes) widened X/Z from 0.94 to 1.0 to close a real cross-tile seam gap against `WorldGrid.TILE_SIZE` — see each `.tscn`'s own header |
| `copy_content_location` | not applicable (terrain, no fact-card copy) |
| `attribution_status` | not required (CC0) — courtesy entry recorded |
| `validation_status` | **pass (2026-08-16)** — schema unchanged (`test_terrain_schema.gd`, does not pin which scene(s) `model_scenes` carries or instance counts). Import-level, unchanged: `test_grass_common_short_import.gd`, `test_grass_common_tall_import.gd` (scene load + "contains a MeshInstance3D" only — the rebuilt `GrassCommonShort.tscn` still satisfies this via its `Ground` box even though the grass instances themselves are now `MultiMeshInstance3D`, not `MeshInstance3D`). Full suite (`bash scripts/run-tests.sh`) reconfirmed green (70/71, the 1 pre-existing `test_placeable_schema` gap unrelated) after both the seam-gap fix and the MultiMesh rework |
| `human_signoff` | not started — scale is still an unmeasured first-pass judgment call (no GDD number exists for grass height); NEW judgment calls from the 2026-08-16 pass also await a look: whether 10 (Short, superseded by 36 in the same-day follow-up) / 8 (Tall) instances reads as coverage without crossing into clutter at the fixed ~45° camera pitch, whether the 2 floor-tint patches per scene read as texture variation or as stray shapes, and — new — the 0.075 height baseline and 36-instance MultiMesh density on the rebuilt `GrassCommonShort.tscn`, plus whether the tile-edge seam fix (0.94 → 1.0 slabs) reads as intended (no visible gap) once seen in-engine |
| `status` | 🚧 — 2 real-art variants wired into `model_scenes` (Short + Tall); `GrassCommonShort.tscn` REBUILT (2026-08-16 same-day follow-up) around a single `MultiMeshInstance3D` at 36 instances and a shorter height baseline per explicit human density/height feedback; all slabs widened to close the cross-tile seam gap; human eyeball sign-off on the combined look still open |

### `water` — Water (emits `water`)

| Field | Value |
|---|---|
| `category_attributes` | emits `water`; free to paint — [terrain.md](terrain.md#already-defined-terrain) |
| `source` | surface is a shader/plane, no model needed (per art.md's own plan) — `project/assets/shaders/water_surface.gdshader`, authored in-repo from primitive shader math, no third-party asset. **LILYPAD EDGE DRESSING ADDED (2026-08-26, content-variety pass Task 8):** `Lilypad.fbx`, Quaternius Ultimate Nature Pack, CC0 1.0 Universal — found on disk in the already-owned pack (`source-content/assets/Ultimate Nature Pack - Jun 2019.../FBX/Lilypad.fbx`), not a poly.pizza standalone download as the task brief assumed at spec time. Recorded in [`quaternius_ultimate_nature_pack.tres`](../project/attribution/sources/quaternius_ultimate_nature_pack.tres) (not `quaternius_poly_pizza_nature.tres`, the file the brief named before the on-disk search corrected the source) |
| `pre_import_audit` | not applicable for the shader surface itself — no third-party asset used there; nothing to audit for license. **Lilypad prop (2026-08-26):** done — CC0 1.0 Universal confirmed via the pack's own `License.txt`, re-checked before import per `asset-import-pipeline.md`'s audit gate |
| `project_location` | `project/assets/terrain/water/Water.tscn` (subdivided `BoxMesh` + `ShaderMaterial`, unchanged by this pass), `project/assets/shaders/water_surface.gdshader`. **NEW (2026-08-26):** `project/assets/terrain/lilypad/Lilypad.fbx` (raw source, one shared copy), `project/assets/terrain/water_lilypad_1/WaterLilypad1.tscn` (2 lilypads), `project/assets/terrain/water_lilypad_2/WaterLilypad2.tscn` (4 lilypads) — both instance `Water.tscn` verbatim as a child plus scattered lilypad props, per each scene's own header |
| `data_entry_location` | `project/data/terrain/water.tres` — `TerrainDefinition`, emits `water`, `cost` 0. **REAL SURFACE LANDED (2026-08-16):** `model_scenes` (pluralized from `model_scene`, → D-42) now points at `Water.tscn` instead of the grey-box — a subdivided `BoxMesh` (8x8 top-face subdivisions for the ripple shader to displace) with `water_surface.gdshader` applied: depth-tint gradient (deep/shallow via fresnel), fresnel rim brighten, gentle animated double-sine vertex ripple. Kept the grey-box's recessed offset (slab dropped 0.04 below other terrains) for legibility. See `Water.tscn` and the shader file's own headers for full per-uniform reasoning. **SAME-DAY FOLLOW-UP (2026-08-16, human-reported cross-tile seam gap, affects all six terrains):** `BoxMesh_surface` widened X/Z from 0.94 to 1.0 to match `WorldGrid.TILE_SIZE` exactly, closing the sky-blue gap between adjacent tiles. The deliberate -0.04 recess offset is UNCHANGED (X/Z-only fix). **SECOND SAME-DAY FOLLOW-UP (2026-08-16, human-reported: water tiles still show a visible edge against each other after the width fix):** root cause was the mesh itself, not the width — a `BoxMesh` has 4 vertical side faces, and two adjacent water tiles' abutting side walls caught the shader's fresnel/specular response as a rim at every tile boundary, water-water included. Replaced `BoxMesh_surface` with a flat `PlaneMesh_surface` (same 1.0x1.0 footprint, same Y position, same subdivision counts, same material) — a plane has no side faces, so adjacent water tiles now share a coincident edge with nothing to catch a highlight. Water-against-land still shows the intended recess (the land tile's own box wall is solid well past the water plane's Y). Also wrapped `Surface` under a new `Slab`-named node — `Water.tscn` had never gotten the `OcclusionFader`-exemption wrapper every other terrain's ground piece has (`scripts/world/occlusion_fader.gd`'s `_collect_fadeable_meshes()` skips a node by that exact name); found while in the file, not a separate human report. **THIRD SAME-DAY FOLLOW-UP (2026-08-16, human-reported with screenshot: thin lines on the water surface that "come and go"):** root cause was in `water_surface.gdshader`, not `Water.tscn` — `vertex()` displaces `VERTEX.y` for the ripple but never updated `NORMAL` to match, so `specular_schlick_ggx` lit a geometrically wavy surface with a normal that stayed flat; that mismatch reads as faceted highlight lines that shift every frame as the animated displacement moves under the still-flat normal. Fixed by recomputing `NORMAL` analytically from the same two sine/cosine terms' partial derivatives (`normalize(-dh/dx, 1, -dh/dz)`), so the lit surface now matches its own geometry. Re-imported clean (no shader compile errors) and `bash scripts/run-tests.sh terrain` / `placeholder_scenes` both pass; could not visually confirm the fix myself (headless environment). **FOURTH SAME-DAY FOLLOW-UP (2026-08-16, human-reported, second and more precise description: "lines... fade in in one direction, fade out, and then fade in another direction and then fade out"):** the third follow-up's normal fix was correct but insufficient — that exact description is what two independent directional sine/cosine wavefronts (X-oriented at speed `t`, Z-oriented at speed `1.2t`) actually look like as they beat against each other; it was never a shading mismatch, it was the wave shape itself. Removed the geometric vertex displacement from `water_surface.gdshader` entirely (any additive spatial sine/cosine term structurally produces traveling line patterns, so patching the same approach further wasn't going to close this) and replaced the motion cue with a uniform, position-independent brightness pulse (`1.0 + sin(TIME * shimmer_speed) * shimmer_strength`, no `VERTEX.x`/`VERTEX.z` term anywhere) — every fragment brightens/dims together, which is structurally incapable of producing a line or band. The static fresnel depth-tint gradient (deep vs. shallow color) is unchanged and was already carrying most of the "reads as water" work. Also dropped `Water.tscn`'s `PlaneMesh` subdivisions from 8x8 back to a single quad, since they existed solely to give the now-removed ripple geometry to bend — 81 vertices per tile for a flat, unmoving surface was pure waste. Re-imported clean, `terrain`/`placeholder_scenes` suites still pass; still not visually confirmed by a human — this is the fourth attempt, so flagged strongly for an eyeball check before considering water settled. **FIFTH SAME-DAY FOLLOW-UP (2026-08-16, human-reported: seams/lines are gone, but "it does look rather flat"):** expected consequence of the fourth follow-up — with no displacement, `NORMAL` is a constant `(0,1,0)` everywhere and `VIEW` barely changes across one small tile at this camera distance, so `fresnel` (and therefore the whole depth-tint gradient) is nearly uniform across the surface, reading as one near-solid color. Rather than reintroduce any geometric or directional-color motion (the exact artifact class of follow-ups three and four), added a sparse twinkling sparkle/glint effect: a `vertex()` varying (`world_pos`, from `MODEL_MATRIX * VERTEX`) feeds a world-space cell hash in `fragment()`, hashed together with a `floor()`'d `TIME` step so which cells glint re-randomizes at discrete intervals — individual sparkles appear/disappear in place, never slide in a direction, so this is structurally unable to reproduce the earlier line artifact. Uses world position (not per-tile UV) so the pattern is seamless across tile boundaries, same as the depth-tint gradient already was. Kept sparse (`sparkle_probability` default 0.06) per this pass's "variety without noise" brief — 4 new uniforms (`sparkle_density`, `sparkle_probability`, `sparkle_speed`, `sparkle_brightness`) all first-pass values, flagged for human sign-off same as every other uniform in this shader. Re-imported clean, `terrain`/`placeholder_scenes` suites still pass; not visually confirmed — fifth attempt, still open. **LILYPAD VARIANTS ADDED (2026-08-26, content-variety pass Task 8):** `model_scenes` grown from 1 entry (`Water.tscn`) to 3 (`Water.tscn`, `WaterLilypad1.tscn`, `WaterLilypad2.tscn`) — see `water.tres`'s own header for the full addition and, critically, an explicit OPEN QUESTION flagged there and restated in `human_signoff` below: `pick_variant()` is equal-weight across the array, so plain open water now shows on only 1/3 of water tiles instead of all of them |
| `copy_content_location` | not applicable (terrain, no fact-card copy) |
| `attribution_status` | shader surface: not required — no third-party asset; nothing to attribute. **Lilypad prop (2026-08-26):** not required (CC0) — courtesy entry recorded, `quaternius_ultimate_nature_pack.tres`'s `assets_used` extended with `"Lilypad"` |
| `validation_status` | **pass (2026-08-16)** — schema unchanged (`test_terrain_schema.gd`, does not pin which scene `model_scenes` carries). No dedicated `test_water_import.gd` was authored — this is hand-authored shader/primitive content, not an imported asset, so the existing import-test convention doesn't apply; `Water.tscn` loading/instantiating cleanly is exercised indirectly by any world-building test that paints water (none currently do). Full suite (`bash scripts/run-tests.sh`) reconfirmed green (69/70, the 1 pre-existing `test_placeable_schema` gap unrelated) after the change. **RE-VALIDATED (2026-08-26):** `--headless --import` clean (no errors for `Lilypad.fbx` or either new `.tscn`), `bash scripts/run-tests.sh terrain_schema` PASS (85/85), `bash scripts/run-tests.sh attribution` PASS (36/36, source count unchanged at 9 since this extends an existing entry rather than adding a new one) |
| `human_signoff` | not started — every uniform in `water_surface.gdshader` (deep/shallow color, wave speed/scale/height, fresnel power, roughness/specular) is a first-pass judgment call with no GDD number; whether the shader reads as "water" at the fixed ~45° camera pitch is the human's eyeball call. Lilypad edge dressing is no longer an unevaluated nice-to-have — it now ships, and needs its own eyeball pass: lilypad scale/count/placement (both `.tscn` headers), AND — the one that needs a decision, not just a look — **whether 1/3-plain-water is the right ratio**, or whether plain water should dominate (which would need either duplicate plain-water entries in the array or a real weighting mechanism, neither built in this pass). NEW: whether the widened 1.0 slab reads as intended (no visible cross-tile gap) |
| `status` | 🚧 — real shader-based surface wired as a `model_scenes` entry (2026-08-16), replacing the flat-color grey-box; slab widened same-day to close the cross-tile seam gap; **2 lilypad-dressed variants added (2026-08-26)**, growing `model_scenes` to 3 equal-weight entries (open ratio question, see `human_signoff`); human eyeball sign-off on the combined look still open |

### `forest` — Forest (emits `forest`; v1's sole harvestable)

| Field | Value |
|---|---|
| `category_attributes` | emits `forest`; free to paint; passive Wood harvestable — [terrain.md](terrain.md#already-defined-terrain) |
| `source` | MegaKit `CommonTree_1` + `CommonTree_2` (2 of a huge surplus — MegaKit Pine/Twisted, Nature Pack Birch/Common/Pine/Palm/Willow, Trees pack (45 models) not evaluated) — CC0 — [`quaternius_stylized_nature_megakit.tres`](../project/attribution/sources/quaternius_stylized_nature_megakit.tres). **2026-08-16 same-day follow-up addition:** "Pine Tree" by Quaternius, CC0, sourced fresh via poly.pizza (poly.pizza/m/gX8WmgkeEm) — [`quaternius_poly_pizza_nature.tres`](../project/attribution/sources/quaternius_poly_pizza_nature.tres). **2026-08-26 content-variety pass (Task 5), 5 more:** `BirchTree_1.fbx`, `Bush_1.fbx`, `BushBerries_1.fbx` from Ultimate Nature Pack (CC0, extends [`quaternius_ultimate_nature_pack.tres`](../project/attribution/sources/quaternius_ultimate_nature_pack.tres)); `DeadTree_3.fbx`, `Pine_2.fbx` from Textured Stylized Trees (CC0, first use of this pack — new [`quaternius_textured_stylized_trees.tres`](../project/attribution/sources/quaternius_textured_stylized_trees.tres)). Both packs' `License.txt` re-checked (CC0 1.0 Universal) before import, per asset-import-pipeline.md's audit gate |
| `pre_import_audit` | done — CC0 confirmed for all 8 trees/bushes now in `model_scenes` (License.txt re-checked per pack before each import); style fit not yet eyeball-confirmed for any of them |
| `project_location` | `project/assets/terrain/common_tree_1/CommonTree1.tscn`, `project/assets/terrain/common_tree_2/CommonTree2.tscn`, `project/assets/terrain/pine_tree/PineTree.tscn`, `project/assets/terrain/pine_tree/PineTree.glb`. **New (2026-08-26, Task 5):** `project/assets/terrain/birch_tree/BirchTree.tscn` + `.fbx`, `project/assets/terrain/dead_tree/DeadTree.tscn` + `.fbx`, `project/assets/terrain/pine_tree_2/PineTree2.tscn` + `.fbx`, `project/assets/terrain/bush/Bush.tscn` + `.fbx`, `project/assets/terrain/bush_berries/BushBerries.tscn` + `.fbx` |
| `data_entry_location` | `project/data/terrain/forest.tres` — `TerrainDefinition`, emits `forest` (**not** `cover`; rock is the `cover` source), `cost` 0, plus `project/data/terrain/forest_harvest.tres`, the project's only `HarvestableTileDefinition` (wood / wild / `removes_habitat_when_harvested = false`). **BOTH TREES LIVE (2026-08-16, → D-42):** `model_scenes` (pluralized from `model_scene`) carries both `CommonTree1.tscn` and `CommonTree2.tscn` as stably-picked per-tile variants — Tree2 was previously imported but unused. Tree2 was brought to parity with Tree1's ground treatment first (see below) so a tile's floor doesn't change depending on which tree it lands. Also: FLOOR FIX — both scenes gained 3 blotchy multi-tone `PlaneMesh` floor patches (moss-dark-green / leaf-litter-brown) addressing the human complaint "floor should not just be a solid color"; no tileable ground texture exists in the audited packs (confirmed by inspection), so this is the documented fallback treatment. All ground meshes (slab + patches) on both scenes were regrouped under one wrapper node named `Slab` — required for `OcclusionFader`'s exemption mechanism (scripts/world/occlusion_fader.gd only skips a node by that exact name), not cosmetic; see each `.tscn` header. **3RD VARIANT ADDED (2026-08-16, same-day follow-up, human-reported):** "It does not seem like forest cycles between multiple assets." `pick_variant()`'s hash was confirmed still distributing evenly and both trees confirmed correctly wired — the real problem was CommonTree1/CommonTree2 both being "common tree" picks from the same MegaKit set at the same ~2.5-tile canopy height, reading as indistinguishable at the fixed ~45° camera pitch. Added `PineTree.tscn` — a genuinely different silhouette (narrow tapered conifer, not another round-canopy common tree), same `Slab`-wrapper ground treatment and canopy-height target (2.5 tiles, scale 0.701) as the other two — as `model_scenes`' 3rd entry, equal weight, both existing trees unchanged. Also in this same pass: `CommonTree1.tscn`/`CommonTree2.tscn` slabs widened X/Z from 0.94 to 1.0 (cross-tile seam-gap fix, unrelated to the variety complaint — see each `.tscn` header). **5 MORE VARIANTS ADDED (2026-08-26, content-variety pass Task 5), `model_scenes` now 8 entries:** `BirchTree.tscn` (~2.5-tile height, uniform scale 0.700), `DeadTree.tscn` (~2.2-tile, deliberately shorter — bare branches read taller/busier than a filled canopy at the same height, uniform scale 0.392), `PineTree2.tscn` (~2.5-tile height but a NON-UNIFORM scale — Y=0.300 for height, X/Z=0.096 for a footprint deliberately narrower than PineTree.tscn's, since the raw Pine_2 mesh is naturally bushy/wide rather than tapered like Pine_1 — see the scene's own header for the full reasoning), `Bush.tscn` and `BushBerries.tscn` (~0.6-tile, the first 2 non-tree ground-level undergrowth picks, uniform scales 0.483/0.470). All 5 use the same `Slab`-wrapper + 3-floor-patch treatment as the existing 3 trees. All 8 variants are equal weight in `pick_variant()` |
| `copy_content_location` | not applicable (terrain, no fact-card copy) |
| `attribution_status` | not required (CC0) — courtesy entries recorded; new Pine Tree entry added to the existing [`quaternius_poly_pizza_nature.tres`](../project/attribution/sources/quaternius_poly_pizza_nature.tres) `assets_used` list (source-file count unchanged, still 7 — this extends an existing entry rather than adding a new source file); `CREDITS.md` regenerated. **2026-08-26 (Task 5):** [`quaternius_ultimate_nature_pack.tres`](../project/attribution/sources/quaternius_ultimate_nature_pack.tres) `assets_used` extended with `BirchTree_1`/`BushBerries_1` (`Bush_1` was already listed from the Den prop use, now reused); new [`quaternius_textured_stylized_trees.tres`](../project/attribution/sources/quaternius_textured_stylized_trees.tres) authored for `DeadTree_3`/`Pine_2` (first use of that pack — attribution source count now 8, `test_attribution.gd`'s hardcoded count bumped 7→8); `CREDITS.md` regenerated |
| `validation_status` | **pass (2026-08-16)** — schema unchanged (`test_terrain_schema.gd`/`test_harvestable_schema.gd`, neither pins which scene(s) or how many `model_scenes` carries). Import-level, unchanged: `test_common_tree_1_import.gd`, `test_common_tree_2_import.gd`; new `test_pine_tree_import.gd` added (scene load + instantiate + contains-a-MeshInstance3D, same shape as its 2 siblings). `test_occlusion_fader.gd` (unrelated suite, exercises Forest tiles specifically) caught a real regression from the floor-patch addition — the new patches were initially plain siblings of `Slab` rather than nested under it, so `OcclusionFader._collect_fadeable_meshes()` picked them up as fadeable tree material; fixed by nesting all ground meshes under one `Slab`-named wrapper node on both scenes (and built into `PineTree.tscn` from the start). Full suite (`bash scripts/run-tests.sh`) reconfirmed green (70/71, the 1 pre-existing `test_placeable_schema` gap unrelated) after the 3rd-variant addition. **2026-08-26 (Task 5): `$GODOT --headless --path project --import` clean, `bash scripts/run-tests.sh terrain_schema` PASS (85/85, forest's own assertions included), `bash scripts/run-tests.sh attribution` PASS (34/34, 8-source count).** Full suite re-run surfaced ONE pre-existing-but-newly-exposed gap, NOT introduced fresh by this task: `test_occlusion_fader.gd`'s `_check_unfade_restores_original_material()` hardcodes a 3x3 tile block at `Vector2i(20,4)` and asserts whichever tile happens to fade has a material with real `TRANSPARENCY_ALPHA_SCISSOR` — true for `CommonTree1`/`CommonTree2` (glTF, alpha-cutout leaf-card textures) but ALREADY FALSE for `PineTree.glb` (transparency=0, confirmed by direct measurement) even before this task; it simply never landed on that specific hardcoded tile with only 3 `model_scenes`. All 5 new picks are genuinely solid vertex-colored low-poly geometry with no texture/alpha channel at all (confirmed by inspection — `has_tex=false`, `vertex_color_use_as_albedo=true` on every surface), so `TRANSPARENCY_DISABLED` is the CORRECT state for them, not a defect to fix in the `.tscn` — the test's assumption that every Forest pick uses alpha-cutout leaf cards is what's now demonstrably false, and will recur for Tasks 6-9 as those add more variants elsewhere. Not fixed in this task (test-design decision spanning all 5 terrain-variety tasks, out of this task's file list) — deferred to the pass's final whole-branch review. **RESOLVED (2026-08-26, final whole-branch review):** `test_occlusion_fader.gd`'s `_check_unfade_restores_original_material()` rewritten to stop betting on the tile-coordinate hash — it now discovers at runtime which `forest.tres` variants actually ship `TRANSPARENCY_ALPHA_SCISSOR` materials (only `CommonTree1`/`CommonTree2` of the 8 do), picks a 3x3 block whose CENTRE tile draws one of them, and asserts the restored transparency against the CAPTURED original rather than a hardcoded constant. A second, separate assumption in the same check was also false and fixed: "a tile this check paints has exactly one fadeable mesh" — painting a tile forest IS a repaint (every tile starts as wild grass) and `TerrainChunkLod`'s `queue_free()` of the retired visual is deferred, which used to collect zero fadeable meshes but now collects the desert prop Task 9's `WildGrassCactus`/`WildGrassPalm`/`WildGrassCoconut` variants hang OUTSIDE their `Slab` wrapper. The check now collects the tile's fadeable meshes once and asserts across every mesh and every surface of that captured list. Verified by mutation (re-introducing the original `TRANSPARENCY_DISABLED`-on-the-duplicate bug fails 4 assertions). Full suite `bash scripts/run-tests.sh`: **85/85 suites pass, 0 failed**, first unfiltered run across the whole content-variety pass |
| `human_signoff` | not started — canopy-height scale (~2.5 tiles, all 3 original trees) is still an unmeasured first-pass judgment call; from 2026-08-16: whether the 3 floor patches per tree read as "mottled forest floor" rather than stray shapes, whether alternating between now-3 trees reads as natural variety, and whether Pine Tree at the SAME height as the 2 common trees sells the "different tree" read strongly enough. **NEW from 2026-08-26 (Task 5), FLAG FOR HUMAN SIGN-OFF on all 5:** DeadTree's ~2.2 vs ~2.5-tile height judgment call and whether a bare-branch tree reads as "dead"/intentional rather than broken; PineTree2's non-uniform-scale footprint squash (whether it reads as a narrow conifer or a visibly distorted mesh); Bush/BushBerries' fundamentally different scale-class (first non-tree Forest picks — whether squat ground-level undergrowth reads correctly at the fixed ~45° camera pitch); BushBerries' berry-detail legibility at that scale specifically |
| `status` | 🚧 — 8 real-art tree/bush variants now wired into `model_scenes` (3 from 2026-08-16, 5 more from 2026-08-26's content-variety pass Task 5 — BirchTree, DeadTree, PineTree2, Bush, BushBerries), all floor-fixed and ground-mesh-grouped for correct occlusion-fader behavior; harvestable already landed; human eyeball sign-off on the combined look (now across all 8 variants) still open; the one test-infrastructure gap this pass surfaced (`test_occlusion_fader.gd`'s hardcoded-tile/ALPHA_SCISSOR assumption) is FIXED as of the final whole-branch review — see `validation_status` |

### `rock` — Rock (emits `cover`, `rocks`; the v1 `cover` source)

| Field | Value |
|---|---|
| `category_attributes` | emits `cover` + `rocks`, load-bearing for Fox/Rabbit habitat; free to paint — [terrain.md](terrain.md#already-defined-terrain) |
| `source` | Nature Pack `Rock_1` (plain, non-moss) — CC0 — [`quaternius_ultimate_nature_pack.tres`](../project/attribution/sources/quaternius_ultimate_nature_pack.tres). **2026-08-16 addition:** 3 more small/medium rock pieces individually sourced via poly.pizza — `Rock` (`Rock_2.glb`), `Rock Medium` (`RockMediumMoss.glb`, mossy), `Rocks` (`RocksCluster.glb`, a pre-modeled 3-rock group) — CC0, [`quaternius_poly_pizza_nature.tres`](../project/attribution/sources/quaternius_poly_pizza_nature.tres). **2026-08-26 addition (content-variety pass Task 6):** 2 more mossy pieces from the same Ultimate Nature Pack extraction directory (audited directly on disk, exact filenames confirmed) — `Rock_Moss_2.fbx` and `Rock_Moss_5.fbx` (the pack ships `Rock_Moss_1..7.fbx`; only `_3` was previously used, by `RockCluster1`/the Den prop) — CC0, extends [`quaternius_ultimate_nature_pack.tres`](../project/attribution/sources/quaternius_ultimate_nature_pack.tres)'s `assets_used`, NOT `quaternius_poly_pizza_nature.tres` (that file covers standalone poly.pizza downloads, a different sourcing path from these on-disk pack files) |
| `pre_import_audit` | done — CC0 confirmed for all 4 pieces (Quaternius creator + CC0 license verified on each poly.pizza model page before download); style fit not yet eyeball-confirmed. **2026-08-26:** CC0 re-confirmed directly from the Ultimate Nature Pack's own `License.txt` on disk for `Rock_Moss_2.fbx`/`Rock_Moss_5.fbx` before import |
| `project_location` | `project/assets/terrain/rock_1/Rock1.tscn` (superseded, no longer wired — see below), `project/assets/terrain/rock_2/Rock_2.glb`, `project/assets/terrain/rock_medium_moss/RockMediumMoss.glb`, `project/assets/terrain/rocks_cluster/RocksCluster.glb`, and 6 composed cluster scenes: `project/assets/terrain/rock_cluster_1/RockCluster1.tscn` .. `rock_cluster_6/RockCluster6.tscn` (`_5`/`_6` added 2026-08-26), plus the 2 new raw pieces `project/assets/terrain/rock_moss_2/Rock_Moss_2.fbx` and `project/assets/terrain/rock_moss_5/Rock_Moss_5.fbx` |
| `data_entry_location` | `project/data/terrain/rock.tres` — `TerrainDefinition`, emits `cover` + `rocks`, `cost` 0. **REWORKED (2026-08-16, → D-42):** explicit human complaint — "much much shorter, look like a bunch of rocks, not a giant rock, varied preferred." The single-variant `Rock1.tscn` (one `Rock_1` mesh at NATURAL scale, height 0.877 — near tile-height) read as one giant rock. `model_scenes` (pluralized) now carries 4 new scattered-cluster variants instead, each composing 3-4 small rocks (max height ~0.25) on their own slab: `RockCluster1` reuses already-imported `Rock_1`+`Rock_Moss_3` (no new download); `RockCluster2` uses 4x the new small `Rock_2`; `RockCluster3` anchors the new mossy `RockMediumMoss` with 2x `Rock_2`; `RockCluster4` uses the new pre-clustered `RocksCluster` scaled up plus 1x `Rock_2`. `Rock1.tscn` itself is untouched, still imported/attributed, just no longer referenced — see each `RockClusterN.tscn` header for full measured-AABB/scale reasoning. **SAME-DAY FOLLOW-UP (2026-08-16, human-reported cross-tile seam gap):** all 4 `RockClusterN.tscn` slabs widened X/Z from 0.94 to 1.0 to match `WorldGrid.TILE_SIZE` exactly — unrelated to the rock-size complaint above, fixed in the same pass. **2 MORE MOSSY VARIANTS ADDED (2026-08-26, content-variety pass Task 6):** `model_scenes` now 6 entries. `RockCluster5.tscn` (3 pieces: 2x `Rock_Moss_2.fbx` + 1x `Rock_Moss_5.fbx`, measured max piece height 0.220) and `RockCluster6.tscn` (4 pieces: 2x `Rock_Moss_5.fbx` + 2x `Rock_Moss_2.fbx`, different arrangement from Cluster5, measured max piece height 0.240) — same cluster-composition convention, same ~0.25 height cap (D-42) as the existing 4, not a new number; heights confirmed via a one-off `SceneTree` AABB-measurement script (same procedure Task 5 used), not guessed |
| `copy_content_location` | not applicable (terrain, no fact-card copy) |
| `attribution_status` | not required (CC0) — existing Nature Pack entry extended (Rock_1, Rock_Moss_3 already listed); new [`quaternius_poly_pizza_nature.tres`](../project/attribution/sources/quaternius_poly_pizza_nature.tres) entry authored for the 3 new poly.pizza pieces used here (plus 3 more used by Cultivated field/Grass-adjacent work, and now also Pine Tree for Forest — see that entry's own notes). **2026-08-26:** [`quaternius_ultimate_nature_pack.tres`](../project/attribution/sources/quaternius_ultimate_nature_pack.tres)'s `assets_used` extended with `Rock_Moss_2`, `Rock_Moss_5`; `notes` extended with the 4th-use paragraph; `CREDITS.md` regenerated (still 8 sources on disk — no new attribution file needed, same-pack reuse) |
| `validation_status` | **pass (2026-08-16)** — schema unchanged (`test_terrain_schema.gd`, does not pin which scene(s) `model_scenes` carries). No new `test_<name>_import.gd` was authored for the 3 new raw pieces (they are only ever used composed inside the 4 cluster wrapper scenes, never referenced directly by any `.tres` — same posture as `Rock_Moss_3.fbx`, which also has no standalone import test since it's only ever used inside a composed wrapper). `test_attribution.gd`'s hardcoded source count was bumped 6→7 for the new entry; `CREDITS.md` regenerated. Full suite (`bash scripts/run-tests.sh`) reconfirmed green (70/71 after the same-day follow-up's `test_pine_tree_import.gd` addition; the 1 pre-existing `test_placeable_schema` gap unrelated). **pass (2026-08-26, Task 6):** `--headless --import` clean for both new `.fbx` files; `bash scripts/run-tests.sh terrain_schema` 85/85 PASS; `bash scripts/run-tests.sh attribution` 34/34 PASS (source count unchanged at 8, no test edit needed) |
| `human_signoff` | not started — every cluster's per-piece scale/density/spacing is a first-pass judgment call (no GDD number for rock height); NEW from 2026-08-16: whether 4 clusters is enough variety without reading as noisy, which cluster (if any) reads best, and whether the widened 1.0 slab reads as intended (no visible cross-tile gap). **NEW from 2026-08-26 (Task 6):** now 6 clusters — whether 6 is too many/noisy, and which of the 6 (including the 2 new mossy ones) reads best |
| `status` | 🚧 — 6 real-art cluster variants now wired into `model_scenes` (4 from 2026-08-16, 2 more mossy ones from 2026-08-26), replacing the single giant-rock variant; slabs widened 2026-08-16 to close the cross-tile seam gap; human eyeball sign-off on the combined look still open |

### `cultivated_field` — Cultivated field (emits `cultivated`; costs Wood)

| Field | Value |
|---|---|
| `category_attributes` | emits `cultivated`; ~2 Wood/tile; villager-need terrain — [terrain.md](terrain.md#already-defined-terrain) |
| `source` | Nature/Crops assets individually sourced via poly.pizza (2026-08-16) — `Crops` (`CropsPlot.glb`, a pre-composed 5-row furrow plot: tomato, pumpkin, 2 cabbage-style rows) and `Wheat` (`Wheat.glb`, wheat-stalk clumps) — CC0, [`quaternius_poly_pizza_nature.tres`](../project/attribution/sources/quaternius_poly_pizza_nature.tres). ~~Growth-stage variants (Wheat/Corn/Carrot/etc. `_Crop`/`_Harvested`) from the full Nature Crops Pack were NOT pursued — v1 has no growth-stage mechanic, so one fixed visual stage per crop type is the correct scope, not a gap~~ **REVERSED (2026-08-26, content-variety pass Task 7, human-confirmed cap):** the human explicitly asked for capped growth-stage variety (2 growth stages + 1 harvested per species, purely visual — no growth-stage *mechanic* was added, so the earlier "no such mechanic exists" reasoning above no longer blocks the variety, it just no longer implies a 1:1 mechanic tie). 8 species (Wheat, Corn, Carrot, Lettuce, Tomato, Pumpkin, Apple, Cactus) x 3 chosen frames each = 24 new files, from the on-disk `Nature Crops Pack` (Jan 2020) extraction — a DIFFERENT, separately-named/dated Quaternius pack from the poly.pizza-downloaded Wheat/Crops above, CC0, [`quaternius_nature_crops_pack.tres`](../project/attribution/sources/quaternius_nature_crops_pack.tres) (new file, this pass) |
| `pre_import_audit` | done — CC0 confirmed for both original pieces (Quaternius creator + CC0 license verified on each poly.pizza model page before download); style fit not yet eyeball-confirmed. **2026-08-26:** CC0 re-confirmed via the Nature Crops Pack's own `License.txt` on disk (covers all 8 species, one check). Audited the brief's stage table against the pack's actual file listing: confirmed Carrot has no `_Harvested` file (brief's own flagged question) AND found, beyond the brief, that **Wheat also has no `_Harvested` file** — both substituted with `_Crop` instead (same fallback rule the brief specified for Carrot, applied identically to Wheat once found) |
| `project_location` | `project/assets/terrain/wheat/Wheat.glb`, `project/assets/terrain/crops_plot/CropsPlot.glb`, plus 2 composed wrapper scenes: `project/assets/terrain/cultivated_wheat_row/CultivatedWheatRow.tscn`, `project/assets/terrain/cultivated_crops_plot/CultivatedCropsPlot.tscn`. **2026-08-26:** 24 new raw FBX + wrapper `.tscn` pairs under `project/assets/terrain/crop_<species>_<stage>/Crop<Species><Stage>.tscn` (e.g. `crop_wheat_2/CropWheat2.tscn` … `crop_cactus_harvested/CropCactusHarvested.tscn`) — full 8-species x 3-variant matrix |
| `data_entry_location` | `project/data/terrain/cultivated_field.tres` — `TerrainDefinition`, emits `cultivated`, **`cost` 2 (the only non-zero terrain cost in v1; PLACEHOLDER at terrain.md's baseline, Open Question #8 — unchanged by this pass)**. **REAL ART LANDED (2026-08-16, → D-42):** human complaint — "needs to look like actual farm fields." `model_scenes` (pluralized from `model_scene`) now carries 2 variants instead of the grey-box: `CultivatedWheatRow.tscn` (6 wheat clumps in 2 loose furrow rows) and `CultivatedCropsPlot.tscn` (the pre-composed 5-row crop mesh, scaled to fit the tile with a soil-slab margin) — both compose a small plot with visible rows, not a single plant in a box. See each `.tscn` header for measured-AABB/scale reasoning. **SAME-DAY FOLLOW-UP (2026-08-16, human-reported cross-tile seam gap):** both scenes' slabs widened X/Z from 0.94 to 1.0 to match `WorldGrid.TILE_SIZE` exactly — unrelated to the "farm fields" complaint above, fixed in the same pass; the crop meshes themselves are untouched. **2026-08-26 (content-variety pass Task 7):** `model_scenes` extended 2 → 26 entries (`load_steps` 4 → 28), 24 new `ext_resource` ids `4_model`..`27_model`, one per new per-species/stage wrapper scene. Each new scene: 1 dirt-brown `Slab` + 3 small clustered instances of the same crop mesh (per-instance rotation+scale jitter, same convention as `CultivatedWheatRow`'s 6 clumps), scaled per-role target (mid ~0.10 tall / grown ~0.16 tall / harvested-reading ~0.07 tall, each footprint-capped so wide/short models don't overrun the tile). See `cultivated_field.tres`'s own header for full rationale, including a measurement-tooling gotcha found and fixed during this task (`Node3D.global_transform` silently returning identity for a not-yet-tree-attached node in a `--script` run, hiding this pack's baked ~100x scale + axis-swap transform) |
| `copy_content_location` | not applicable (terrain, no fact-card copy) |
| `attribution_status` | not required (CC0) — new [`quaternius_poly_pizza_nature.tres`](../project/attribution/sources/quaternius_poly_pizza_nature.tres) entry covers both original pieces (shared with Rock's 2026-08-16 additions, and now also Forest's Pine Tree). **2026-08-26:** the 24 new Nature Crops Pack files are NOT covered by that entry (different pack) — new [`quaternius_nature_crops_pack.tres`](../project/attribution/sources/quaternius_nature_crops_pack.tres) authored, one `assets_used` entry per of the 24 files, uniform CC0 license (`attribution_required = false`). `CREDITS.md` regenerated — now 9 sources (was 8), `test_attribution.gd`'s hardcoded source count updated 8 → 9 |
| `validation_status` | **pass (2026-08-16)** — schema unchanged (`test_terrain_schema.gd`, `cost` 2 still pinned, does not pin which scene(s) `model_scenes` carries). No dedicated `test_<name>_import.gd` was authored for `Wheat.glb`/`CropsPlot.glb` — same posture as Rock's new pieces, only ever used composed inside wrapper scenes. Full suite (`bash scripts/run-tests.sh`) reconfirmed green (70/71 after the same-day follow-up's `test_pine_tree_import.gd` addition; the 1 pre-existing `test_placeable_schema` gap unrelated). **2026-08-26: pass** — `$GODOT_PATH --headless --path project --import` clean (all 24 new FBX imported without error/warning); `bash scripts/run-tests.sh terrain_schema` 85/85 (including `cultivated_field: model_scenes is non-empty`/`every model_scenes entry is a PackedScene`/`validate() is CLEAN`); `bash scripts/run-tests.sh attribution` 36/36 (9 sources, CREDITS.md fresh). Only these filtered suites run, per this task's instructions, to avoid the known pre-existing `test_occlusion_fader` full-suite gap |
| `human_signoff` | not started — wheat-clump height/count and the crops-plot scale-down are first-pass judgment calls (no GDD number for crop height/density); the Wood cost (#8) remains a separate open human decision, untouched by this pass. NEW: whether the widened 1.0 slab reads as intended (no visible cross-tile gap). **2026-08-26: NEW, whole 24-scene batch flagged** — the `_2`/`_4` stage choice (vs `_1`/`_3`), the per-role target heights/footprint caps, the 3-instance cluster arrangement (all first-pass judgment calls, no GDD number), and specifically the Wheat/Carrot `_Crop`-for-missing-`_Harvested` substitution (Wheat's gap found during this task's own audit, beyond what the brief flagged) |
| `status` | 🚧 — 2 real-art variants now wired into `model_scenes` (2026-08-16), replacing the grey-box; slabs widened same-day to close the cross-tile seam gap; human eyeball sign-off on the combined look still open, and the Wood cost is still an open human decision (#8). **2026-08-26:** extended to 26 `model_scenes` variants (24 new per-species/growth-stage/harvested crop scenes, content-variety pass Task 7) — validated and attributed, human eyeball sign-off on the full 26-variant rotation still open |

### `wild_grass` — Wild grass (emits *nothing* — tag-inert)

| Field | Value |
|---|---|
| `category_attributes` | emits nothing at all; free to convert to true grass with one Terraform tap; **the structural source of the inert-land invariant** — [terrain.md](terrain.md#already-defined-terrain) |
| `source` | Reuses already-imported `Grass_Common_Short.gltf` (MegaKit, CC0 — [`quaternius_stylized_nature_megakit.tres`](../project/attribution/sources/quaternius_stylized_nature_megakit.tres)); no new asset sourced, per this pass's chosen treatment (wild grass is visually grass-family, just duller/sparser — see below). **2026-08-26 (content-variety pass Task 9):** 3 sand/desert-flavor siblings added, each instancing `WildGrass.tscn` verbatim plus one new-sourced prop — `Cactus_1.fbx` and `PalmTree_1.fbx` (Quaternius Ultimate Nature Pack, CC0 — [`quaternius_ultimate_nature_pack.tres`](../project/attribution/sources/quaternius_ultimate_nature_pack.tres)) and `Coconut_Half.fbx` (Quaternius Nature Crops Pack, CC0 — [`quaternius_nature_crops_pack.tres`](../project/attribution/sources/quaternius_nature_crops_pack.tres)) |
| `pre_import_audit` | not applicable for the original entry — no new third-party asset, reuses an already-audited one. **2026-08-26 (Task 9):** audited before import — Cactus_1.fbx was directly confirmed in Ultimate Nature Pack at plan time; PalmTree_1.fbx was flagged unconfirmed at plan time and confirmed by this task's own on-disk `find` in that same pack; Coconut_Half.fbx (Nature Crops Pack) was confirmed as the only coconut-themed asset in any owned pack after a full on-disk audit (no standalone "Coconut" tree exists anywhere, so no poly.pizza fallback was needed — see WildGrassCoconut.tscn's own header for the full audit note). All 3 packs' `License.txt` re-checked, CC0 1.0 Universal / Public Domain Dedication |
| `project_location` | `project/assets/terrain/wild_grass/WildGrass.tscn` — first real (non-grey-box) asset for this terrain. **2026-08-26 (Task 9):** 3 new siblings — `project/assets/terrain/wild_grass_cactus/WildGrassCactus.tscn`, `project/assets/terrain/wild_grass_palm/WildGrassPalm.tscn`, `project/assets/terrain/wild_grass_coconut/WildGrassCoconut.tscn` — each instances `WildGrass.tscn` as a base plus one desert prop; raw sources copied alongside each (`Cactus_1.fbx`, `PalmTree_1.fbx`, `Coconut_Half.fbx`) |
| `data_entry_location` | `project/data/terrain/wild_grass.tres` — `TerrainDefinition`, `emitted_tags` **deliberately empty**, `cost` 0 (unchanged). This entry is the derivation source `spec.md` requires: `TerrainDefinition.derive_bare_tags()` reads its `emitted_tags` to produce `BARE_TAGS` instead of hardcoding them, and `TerrainDefinition.validate()` rejects any `wild_grass` entry that emits a tag. **REAL ART LANDED (2026-08-16):** `model_scenes` now points at `WildGrass.tscn` instead of the grey-box — a PROPOSED treatment for Open Question #29 (not a closure of it): the same grass mesh as true Grass, but a duller olive-khaki slab tint, only 4 sparse scattered instances (vs. true Grass's 10), and 2 bare-dirt patches for a "patchy, untended" read. See `WildGrass.tscn`'s own header for the full reasoning and the #29 framing. **SAME-DAY FOLLOW-UP (2026-08-16, human-reported): "still spotty… shorter height, and more instances (30+)"** (same complaint that also drove `grass`'s rework). `WildGrass.tscn` was REBUILT around a single `MultiMeshInstance3D` with 32 baked, CLUSTERED instances (4 uneven cluster centers — 10/6/10/6 — rather than an even scatter, so real bare-ground gaps remain between clumps, keeping the "patchy/untended" read distinct from Grass's now-even 36-instance coverage) at a shorter scale baseline (0.065, down from ~0.08 average, and shorter than Grass's own new 0.075 baseline — continuing this terrain's existing "smaller than true Grass" convention). 3rd bare-dirt patch added (up from 2). Also: slab widened X/Z from 0.94 to 1.0 (cross-tile seam-gap fix, applied to every terrain this pass touches, unrelated to the density complaint). **2026-08-27 (post-B2 human ruling):** sub-project B2 had re-added Cactus/Palm to `model_scenes` (Task 2, picker-only intent) and shipped its long-press style picker; the human then reviewed Cactus/Palm as picker options for Wild grass specifically and ruled them out there too. `model_scenes` is back to its single original entry (`ExtResource("2_model")`, `WildGrass.tscn`); the now-unreferenced `3_model`/`4_model` `ext_resource` declarations were removed from the file and `load_steps` updated (5 -> 3). `WildGrassCactus.tscn`/`WildGrassPalm.tscn` remain on disk, imported and attributed, unused — unwired, not deleted, same disposition as the pre-B2 2026-08-26 state |
| `copy_content_location` | not applicable (terrain, no fact-card copy) |
| `attribution_status` | not required (CC0) — no new source, reuses the already-recorded MegaKit entry. **2026-08-26 (Task 9):** Cactus_1/PalmTree_1 appended to `quaternius_ultimate_nature_pack.tres`'s `assets_used`; Coconut_Half appended to `quaternius_nature_crops_pack.tres`'s `assets_used`; both entries' notes extended with this task's use. Still not required (CC0) — courtesy-only, `test_attribution.gd` reconfirmed green. **2026-08-26, SAME-DAY human eyeball pass:** Coconut_Half removed from `assets_used` (asset deleted, see below); Cactus_1/PalmTree_1 stay in `assets_used` (files kept on disk for sub-project B, only unwired from `model_scenes`) |
| `validation_status` | **pass (2026-08-16)** — schema unchanged (`test_terrain_schema.gd`/`test_bare_tags_derivation.gd`, both still clean — `emitted_tags` stays empty, the derivation-source assertion is untouched by this pass). `test_occlusion_fader.gd` (unrelated suite) caught a real transient-visual bug from this scene's initial structure: wild grass is the world's default untouched-land terrain, so it is the "old" visual sitting under nearly every tile a player ever repaints to Forest, and `TerrainView`'s `queue_free()` on that old visual is deferred, not immediate — for one frame both visuals coexist, and this scene's ground box + 6 decorative pieces were initially plain top-level siblings rather than exempted, so `OcclusionFader` picked them up as fadeable. Fixed by nesting everything under one wrapper node named `Slab` (the fader's exemption mechanism) — preserved through the same-day MultiMesh rebuild (still one `Slab`-named wrapper holding the ground box, all 3 bare-dirt patches, and the multimesh). Full suite (`bash scripts/run-tests.sh`) reconfirmed green (70/71, the 1 pre-existing `test_placeable_schema` gap unrelated) after both fixes. **2026-08-26 (Task 9):** `--headless --path project --import` clean (no errors); `test_terrain_schema.gd` PASS (85/85, including `wild_grass: emitted_tags matches terrain.md's tag-source mapping` still empty); `test_bare_tags_derivation.gd` PASS (11/11 + 1 pre-existing PEND unrelated) — the inert-land invariant survived this task untouched; `test_attribution.gd` PASS (36/36); all 3 new scenes independently instantiate cleanly (one-off SceneTree verification script, deleted after use) |
| `human_signoff` | not started — and this item's look pass is **Open Question #29** (must read as "something to claim" without reading as broken); the treatment above is tech-art's PROPOSAL, not a closure of #29 — that reading is the human's eyeball call. NEW from the same-day follow-up: the 0.065 height baseline, 32-instance/uneven-clustering density choice, and whether the widened 1.0 slab reads as intended (no visible cross-tile gap) all await the same eyeball pass. **2026-08-26, SAME-DAY human eyeball pass on Task 9's 4-variant rotation — RULED, not just flagged**: (1) Coconut_Half rejected outright ("does not look good at all") — asset deleted entirely, not deferred; (2) the equal-weight-across-N-variants question is now CLOSED for this terrain specifically: plain Wild grass must stay the default, and Cactus/Palm must NOT be part of the automatic random pick at all — they're reserved exclusively for sub-project B's player-facing style picker. `model_scenes` reverted to its original single entry (`WildGrass.tscn`) accordingly; `WildGrassCactus.tscn`/`WildGrassPalm.tscn` stay imported on disk for that future picker. Open Question #29's core question (does plain Wild grass itself read as "something to claim, not broken") is unaffected by this and remains open |
| `status` | 🚧 — first real asset landed and wired (2026-08-16), proposing a treatment for #29; REBUILT same-day (MultiMesh, shorter/denser-but-still-patchy) per explicit human density/height feedback; human eyeball sign-off (and #29's actual closure) still open. **2026-08-26:** briefly extended to 4 `model_scenes` variants (content-variety pass Task 9), then REVERTED THE SAME DAY to 1 entry per human eyeball ruling (Coconut deleted; Cactus/Palm deferred to sub-project B, not randomized). **2026-08-27:** sub-project B2 re-added Cactus/Palm to `model_scenes` for its style picker, then the human ruled them out of the picker too — back to 1 entry (`WildGrass.tscn`) again, `WildGrassCactus.tscn`/`WildGrassPalm.tscn` still on disk unused — plain Wild grass's own #29 look-pass sign-off is still the only open item on this row |

### `sand` — Sand (emits `sand`; depth, not v1 floor)

| Field | Value |
|---|---|
| `category_attributes` | emits `sand`; no v1 consumer yet; depth row, not blocking v1 — [terrain.md](terrain.md#already-defined-terrain) |
| `source` | Cactus, PalmTree, Coconut — available, not needed at the floor |
| `pre_import_audit` | not started — deferred by design (depth), not blocked |
| `project_location` | not started |
| `data_entry_location` | not started |
| `copy_content_location` | not started |
| `attribution_status` | not started |
| `validation_status` | not started |
| `human_signoff` | not started |
| `status` | 🚧 |

---

## Buildings

| id | Status |
|---|---|
| `house` | 🚧 |
| `barn` | 🚧 |
| `small_barn` | 🚧 |
| `open_barn` | 🚧 |
| `chicken_coop` | 🚧 |
| `silo` | 🚧 |
| `windmill` | 🚧 |
| `water_tower` | 🚧 |
| `well` | 🚧 |

### `house` — House

| Field | Value |
|---|---|
| `category_attributes` | floor 1×1 / full 2×2, grass only, ~15/~30 Wood — [buildings.md](buildings.md#already-defined-buildings) |
| `source` | Quaternius, "Ultimate Fantasy RTS" — CC0 1.0 Universal — [`quaternius_ultimate_fantasy_rts.tres`](../project/attribution/sources/quaternius_ultimate_fantasy_rts.tres). Same single entry now covers **20** house models: the 10 FirstAge already shipped plus the pack's whole **SecondAge** house catalogue, imported in the SecondAge house batch. |
| `pre_import_audit` | done — `Houses_FirstAge_1_Level1` picked from 9 live candidates by measured footprint fit (0.869×0.761 units inside a 1×1 tile, no rescale needed); documented in `House.tscn`'s own header comment. **9 MORE VARIANTS AUDITED AND IMPORTED (2026-08-26, content-variety pass Task 2):** the remaining 8 `Houses_FirstAge_{1,2,3}_Level{1,2,3}` candidates plus `TowerHouse_FirstAge`, same pack, CC0 re-confirmed unchanged. Each variant's raw AABB footprint was measured (manual local-transform composition, not `global_transform` — see `cultivated_field.tres`'s header for the gotcha) and, where it exceeded a 1×1 tile, uniformly scaled so its max footprint axis matches `HousesFirstAge1Level1`'s own natural 0.8693 max-axis fit; two variants needed no rescale. Per-variant numbers are in each new `.tscn`'s own header and in `house.tres`'s consolidated header note. **10 MORE VARIANTS AUDITED AND IMPORTED (SecondAge house batch):** `Houses_SecondAge_{1,2,3}_Level{1,2,3}` plus `TowerHouse_SecondAge` — the half of the pack's house catalogue that had never been touched (`grep -rli secondage project/` returned nothing before this run). Same pack, CC0 re-confirmed. **Why this tier:** the shipped `Houses_FirstAge_1_Level1` is a 404-triangle, 2-material lean-to with no modelled door or windows; the SecondAge tier is the same artist and palette at 964–5,948 triangles across 5–6 materials, with both. **Material audit run on every raw glTF:** `albedo_texture` null and NO `ARRAY_COLOR` channel on any surface — colour comes entirely from per-surface `albedo_color`, and the `Wood`/`Stone` values are byte-identical to the shipped FirstAge variants', so this is the same palette, not a second one. **Footprints re-measured on this run rather than trusted:** `SecondAge_1_Level1` 0.889953×0.864464, `_2_Level1` 0.887446×0.811244, `_3_Level1` 0.676501×0.676506 — all three already inside a 1×1 tile and shipped **unscaled**; the other seven exceed it and are uniformly scaled so their long footprint axis lands on 0.869309, the FirstAge target. **Those seven factors are PROPOSALS, not forced measurements** (the measurement is forced; the 0.869309 target is an inherited convention) — see each `.tscn` header and the batch report. |
| `project_location` | `project/assets/buildings/house/House.tscn` (wraps `HousesFirstAge1Level1.gltf`) — index 0 of `model_scenes`, unchanged. **9 more locations added:** `project/assets/buildings/house_firstage_1_level2/HouseFirstage1Level2.tscn`, `house_firstage_1_level3/HouseFirstage1Level3.tscn`, `house_firstage_2_level1/HouseFirstage2Level1.tscn`, `house_firstage_2_level2/HouseFirstage2Level2.tscn`, `house_firstage_2_level3/HouseFirstage2Level3.tscn`, `house_firstage_3_level1/HouseFirstage3Level1.tscn`, `house_firstage_3_level2/HouseFirstage3Level2.tscn`, `house_firstage_3_level3/HouseFirstage3Level3.tscn`, `house_tower_firstage/HouseTowerFirstage.tscn` — each wraps its own source glTF (same directory, renamed to strip underscores per this asset's existing naming convention), each `model_scenes` indices 1–9 in `house.tres`, in that order. **10 more locations added, NOT wired:** `project/assets/buildings/house_secondage_1_level1/HouseSecondage1Level1.tscn` and its 8 siblings (`house_secondage_{1,2,3}_level{1,2,3}/HouseSecondage<n>Level<l>.tscn`), plus `house_tower_secondage/HouseTowerSecondage.tscn` — each wraps its own source glTF in the same directory (renamed to strip underscores, per this asset's existing naming convention). **Adding them to `house.tres`'s `model_scenes` is gameplay-engineer's step and was deliberately not done here.** |
| `data_entry_location` | `project/data/buildings/house.tres` — `PlaceableDefinition`, emits `house`, `allowed_terrain = ["grass"]`, **`cost` 15 and `footprint` 1×1 are PLACEHOLDERS** at buildings.md's floor baselines (Open Questions #8/#26 and #18). `model_scenes[0]` points at the **real** imported `assets/buildings/house/House.tscn`, not a grey-box (the field became an `Array[PackedScene]` on 2026-08-26, building-variety B1; index 0 is what placement reads, unchanged); a grey-box fallback exists at `assets/placeholder/house/House.tscn` should the facing fail its look pass. **2026-08-29 (SecondAge wiring, Content Pipeline step 4): `model_scenes` grown 10 → 18** — 8 of the 10 already-imported/attributed/import-tested SecondAge wrappers appended (`house_secondage_1_level{1,2,3}`, `house_secondage_2_level1`, `house_secondage_3_level{1,2,3}`, `house_tower_secondage`). Index 0 unchanged. **`house_secondage_2_level2` and `house_secondage_2_level3` are deliberately NOT wired** on the human's 2026-08-29 ruling: both are multi-building compounds whose fit-to-1×1 rescale drives them to 0.5315 / 0.4316 tile-heights (under half a villager), and `footprint` belongs to the buildable, not to a variant — a 2×2 rescale would overflow tiles this buildable does not own. Their files, wrappers, tests and attribution stay on disk for a possible future 2×2 buildable. `footprint`, `cost`, `allowed_terrain`, `emitted_tags` and `fact_text` are untouched by this pass — wiring only |
| `copy_content_location` | **done (2026-08-06).** `project/data/buildings/house.tres`, `fact_text`: "This simple house is ready to be someone's new home. Plant a field close by, and a family will settle in before long." Inspect-Mode **building flavor** (gdd.md line 115), not a fact card — no external wildlife source exists for a building, per the brief. Source is internal: gdd.md lines 60, 87, 115, 117 and buildings.md lines 75-81 (the House-as-home-site, farm-triggers-move-in mechanics), plus human.tres's header (lines 119-131) for the already-cleared GAME-register use of "settled in" (fox/rabbit News Report pools). Two-register sweep clean: no literal "town"/"village". Distinct from the Villager's own fact card (human.tres), which asserts a real prehistory claim this string never touches. Full per-clause sourcing and checklist log are in `house.tres`'s own header comment. `PlaceableDefinition.pending_signoff()` should no longer report this field once re-validated — that re-validation is gameplay-engineer's/qa-engineer's to run, not done here |
| `attribution_status` | not required (CC0) — courtesy entry recorded. `assets_used` in `quaternius_ultimate_fantasy_rts.tres` extended (2026-08-26) with the 9 new source filenames (`Houses_FirstAge_1_Level2/3`, `Houses_FirstAge_2_Level1/2/3`, `Houses_FirstAge_3_Level1/2/3`, `TowerHouse_FirstAge`); same single entry, not a new one.. `assets_used` extended again (SecondAge house batch) with the 10 SecondAge source filenames (`Houses_SecondAge_{1,2,3}_Level{1,2,3}`, `TowerHouse_SecondAge`) and the entry's `notes` record why the tier was imported; still the same single entry, still no new license file — the pack's CC0 terms are unchanged. `CREDITS.md` regenerated; `test_attribution.gd` green. |
| `validation_status` | **pass (2026-08-16, re-validated)** — schema: `test_placeable_schema.gd` (binds to `PlaceableDefinition`, `validate()` clean both with and without a terrain roster, `footprint == Vector2i(1,1)`, `allowed_terrain == ["grass"]` resolving against the six real terrain ids, `emitted_tags == ["house"]`, `cost` 15, `model_scene` pinned to the **real** imported asset and instantiable). **RE-POINTED off the pre-copy PLACEHOLDER pin (was stale — see prior `status` note):** `fact_text` is now asserted as the exact shipped string (verbatim, same pattern `test_human_schema.gd` uses for human.tres), not-PLACEHOLDER-prefixed, and `pending_signoff()` now reports EMPTY (the only thing it ever flagged is gone) — with a negative control that a clone carrying the placeholder again is still flagged, so "empty" is a real check. The deliberate `PlaceableDefinition`/`AnimalDefinition` validate-vs-pending_signoff divergence is still asserted, now against a directly-constructed placeholder literal rather than against `house.fact_text` (which is real copy now, not a placeholder). Import-level, unchanged: `test_house_import.gd`; grey-box fallback covered by `test_placeholder_scenes.gd`. **Cost 15 and footprint 1×1 are still pinned as placeholders, not ruled on** (#8/#26, #18). **STILL NOT VALIDATED HERE: the sourcing itself** — schema/exact-string/not-a-placeholder are machine checks; step 8 (human sign-off on the copy) is a human read, per this row's `status` field **RE-VALIDATED 2026-08-29 (pin re-point after the sanctioned `model_scenes` growth):** the 2026-08-29 asset-audit sweep grew `house.tres`'s `model_scenes` 10 -> 18 (8 RTS SecondAge house variants appended; no schema change, no other field touched), correctly turning the hard-pinned count in `test_placeable_schema.gd` RED. **Re-pointed, not relaxed:** `check_eq(house.model_scenes.size(), 18)`, with `model_scenes[0]` keeping its own separate assertion that it is STILL `House.tscn` / `HousesFirstAge1Level1` -- the shipped default staying first is load-bearing for saves and for `world_root.gd`'s style defaults. Every entry is still asserted `PackedScene` + `can_instantiate()`, so all 8 new wrappers are load-tested here. **Deliberately NOT asserted, and the test comment now says why: "every wrapper on disk is wired".** `house_secondage_2_level2` and `house_secondage_2_level3` exist under `project/assets/buildings/` and are held out by human ruling (multi-building compounds that flatten below villager height in a 1x1 footprint), so a disk-count-equals-`model_scenes`-count check would encode a false invariant and go red on a correct repo. `test_placeable_schema.gd` 62 -> 63 assertions, 0 failed. **Full suite `bash scripts/run-tests.sh`: 91/91 suites pass, 0 failed, zero SCRIPT ERROR** -- note this supersedes the "1 pre-existing `test_placeable_schema` gap" caveat repeated in older rows above; there is no such gap now. **STILL NOT VALIDATED HERE, unchanged: the sourcing/copy sign-off (step 8), the 8 new variants' facing and rescale factors (human eyeball), and `cost` 15 / `footprint` 1x1 remain pinned placeholders pending #8/#26/#18.** |
| `human_signoff` | **confirmed 2026-08-03 — both counts (index-0 variant only).** The variant pick (`Houses_FirstAge_1_Level1`) and the facing (identity transform, no rotation) were visually approved under the first-person walk camera (D-33 replaced the fixed ~45° pitch this item was originally scoped against); `House.tscn`'s own header comment is updated to match. **NOT YET COVERED: the 9 new variants added 2026-08-26 (Task 2).** Per-variant scale fit (each new `.tscn`'s header) and facing (all left identity, unconfirmed) are FLAGGED FOR HUMAN SIGN-OFF — none of the 9 has had an eye pass under the walk camera yet. |
| `status` | 🚧 — asset imported and attributed, data entry landed and schema-validated, both sign-off items now confirmed for the original variant, and copy content (`fact_text`) now written (2026-08-06, content-writer) — **step 6 (re-validation) and step 8 (copy sign-off) are still open**, since `validation_status` above still pins the pre-copy PLACEHOLDER state and `human_signoff` above only covers the asset/variant, not the new string. **Note, not fixed here:** `data_entry_location` above still calls `cost 15` / `footprint 1×1` PLACEHOLDERS, but tier1-status.md's row 4 records both as DECIDED 2026-08-01 (→ D-29) — this row's own fields are stale on that point and worth a follow-up sync. **2026-08-26 (content-variety pass Task 2): `model_scenes` grown 1 → 10** with 8 more `Houses_FirstAge` variants plus `TowerHouse_FirstAge`, all imported, wrapped, scaled, schema/import-tested (`test_placeable_schema.gd`, `test_house_variants_import.gd`), and attributed (same `quaternius_ultimate_fantasy_rts.tres` entry, `assets_used` extended) — full suite green (86/86, zero SCRIPT ERROR). The 9 new variants' scale fit and facing are pending human sign-off (see `human_signoff` above); which variant a placed House shows is gameplay-engineer's/Content Pipeline step 3 call, not decided here. **SecondAge house batch: 10 more variants imported, wrapped, scaled, attributed and import-tested** (`test_house_secondage_variants_import.gd`, 41 assertions) — full suite green **91/91, zero SCRIPT ERROR**. `model_scenes` was still 10 at that point (wiring is gameplay-engineer's step); **it is now 18 as of 2026-08-29** — 8 of the 10 SecondAge variants wired, `HouseSecondage2Level2`/`HouseSecondage2Level3` held out by human ruling (see `data_entry_location` above). Pending on the 10: facing (all identity, unconfirmed), and the seven rescale factors, which are **proposals** — the 0.869309 fit target is inherited convention, not a measurement of these assets. **Two of the seven needed a real look before wiring, and got one:** `HouseSecondage2Level3` (scaled height 0.4316) and `HouseSecondage2Level2` (0.5315) are multi-building compounds squeezed into a 1×1 footprint, so at those factors they end up **shorter than a villager** (villagers normalise to 1.0 tall). A 2×2 footprint target (1.738618, the Barn precedent) would keep them building-shaped. **DECIDED 2026-08-29: held out of `model_scenes`, kept on disk for a possible future 2×2 buildable.** **Still raised, not decided:** `HouseSecondage3Level2` (wired, idx 15) carries the *same* compound/shorter-than-a-villager flag in its wrapper header at height 0.3515 — shorter than either held-out variant — and the already-shipped FirstAge idx 7/8 sit at 0.3469, so height alone is evidently not the disqualifier; worth a look alongside the unresolved FirstAge height-rule question, which now spans 18 entries. |

### `barn` — Barn

| Field | Value |
|---|---|
| `category_attributes` | proposed 2x2 footprint (the one outlier in this batch — every other new farm building proposes 1x1), grass only, ~30 Wood — FIRST-PASS PROPOSAL, no design doc row exists yet (buildings.md's only decided buildable is House); see barn.tres's own header |
| `source` | Quaternius, "Farm Buildings" — CC0 1.0 Universal — [`quaternius_farm_buildings.tres`](../project/attribution/sources/quaternius_farm_buildings.tres) |
| `pre_import_audit` | done (2026-08-26, content-variety pass Task 3) — CC0 re-confirmed via the pack's own License.txt. Texture situation confirmed EMPIRICALLY, not assumed from the pack-level "no texture files found" observation: a throwaway probe script (same method used to diagnose the DeadTree/PineTree2 missing-texture bug) checked every surface's `albedo_texture`/`albedo_color`/`vertex_color_use_as_albedo` on the raw FBX. Result: this pack ships NO textures in any export format (confirmed via the sibling OBJ/MTL export's `.mtl` files — no `map_Kd` line anywhere), but bakes its named flat-color Blender materials into real, MEANINGFUL, DISTINCT per-vertex color — NOT the uniform near-(0.9063, 0.9063, 0.9063, 1.0) missing-texture tell. No texture fix needed. Full per-surface readings in Barn.tscn's own header. |
| `project_location` | `project/assets/buildings/barn/Barn.tscn` (wraps `Barn.fbx`), scaled 0.211448 (raw AABB 7.7269 x 8.2224 x 6.0086 -> scaled 1.6338 x 1.2705 x 1.7386, x/y/z) to target a 2x2-tile max-axis margin |
| `data_entry_location` | `project/data/buildings/barn.tres` — `PlaceableDefinition`, `allowed_terrain = ["grass"]`, `emitted_tags = []`. **`cost` 30 and `footprint` 2x2 are FIRST-PASS PROPOSALS**, not decided anywhere — FLAG FOR HUMAN SIGN-OFF, this row especially (the only 2x2 proposal in the batch). `fact_text` is a `PLACEHOLDER`-prefixed string — Content Pipeline step 5 not yet dispatched |
| `copy_content_location` | not started — `fact_text` is `PLACEHOLDER — flavor copy for the Barn pending Content Pipeline step 5.` (content-writer's job, not tech-art's) |
| `attribution_status` | not required (CC0) — courtesy entry recorded. NEW `quaternius_farm_buildings.tres` entry created (2026-08-26), `assets_used` lists all 8 farm buildings including `Barn` |
| `validation_status` | **pass (2026-08-26)** — `test_farm_buildings_schema.gd`: binds to `PlaceableDefinition`, `validate()` clean with and without a terrain roster, `id`/`display_name`/`cost`/`footprint`/`allowed_terrain`/`emitted_tags` match the proposal table, `model_scenes` has exactly 1 entry and instantiates, measured world-composed footprint fits the proposed 2x2 budget, `pending_signoff()` reports exactly the `fact_text` placeholder. `WorldRoot.placeable_options()` confirmed to include `barn`. Full suite green (87/87, zero SCRIPT ERROR) |
| `human_signoff` | **not yet started.** Cost/footprint proposal (especially the 2x2 outlier), scale fit, and facing (identity, unconfirmed) all await a human eye pass — see Barn.tscn's header |
| `status` | 🚧 — asset imported and attributed, data entry landed and schema-validated. Copy (step 5), re-validation after copy (step 6), and human sign-off (step 8) are all still open |

### `small_barn` — Small Barn

| Field | Value |
|---|---|
| `category_attributes` | proposed 1x1 footprint, grass only, ~15 Wood — FIRST-PASS PROPOSAL, no design doc row exists yet; see small_barn.tres's own header |
| `source` | Quaternius, "Farm Buildings" — CC0 1.0 Universal — [`quaternius_farm_buildings.tres`](../project/attribution/sources/quaternius_farm_buildings.tres) |
| `pre_import_audit` | done (2026-08-26, content-variety pass Task 3) — CC0 re-confirmed. Texture situation confirmed EMPIRICALLY (same probe method as `barn`, run separately against this asset's own FBX, not assumed from the pack level): albedo_texture null on every surface, vertex_color_use_as_albedo true with meaningful, distinct per-surface colors matching Barn.fbx's shared material set — NOT the missing-texture tell. No texture fix needed. Full readings in SmallBarn.tscn's own header. |
| `project_location` | `project/assets/buildings/small_barn/SmallBarn.tscn` (wraps `SmallBarn.fbx`), scaled 0.138560 (raw AABB 6.0787 x 4.9611 x 6.2739 -> scaled 0.8423 x 0.6874 x 0.8693) to House's own established 1x1 max-axis margin (0.869309) |
| `data_entry_location` | `project/data/buildings/small_barn.tres` — `PlaceableDefinition`, `allowed_terrain = ["grass"]`, `emitted_tags = []`. **`cost` 15 and `footprint` 1x1 are FIRST-PASS PROPOSALS** — FLAG FOR HUMAN SIGN-OFF. `fact_text` is a `PLACEHOLDER`-prefixed string |
| `copy_content_location` | not started — `fact_text` is `PLACEHOLDER — flavor copy for the Small Barn pending Content Pipeline step 5.` |
| `attribution_status` | not required (CC0) — courtesy entry recorded in `quaternius_farm_buildings.tres`, `assets_used` includes `SmallBarn` |
| `validation_status` | **pass (2026-08-26)** — `test_farm_buildings_schema.gd`, same checks as `barn`'s row above, adapted to this entry's own proposed values. `WorldRoot.placeable_options()` confirmed to include `small_barn`. Full suite green (87/87, zero SCRIPT ERROR) |
| `human_signoff` | **not yet started.** Cost/footprint proposal, scale fit, and facing (identity, unconfirmed) all await a human eye pass |
| `status` | 🚧 — asset imported and attributed, data entry landed and schema-validated. Copy (step 5), re-validation after copy (step 6), and human sign-off (step 8) are all still open |

### `open_barn` — Open Barn

| Field | Value |
|---|---|
| `category_attributes` | proposed 1x1 footprint, grass only, ~15 Wood — FIRST-PASS PROPOSAL, no design doc row exists yet; see open_barn.tres's own header |
| `source` | Quaternius, "Farm Buildings" — CC0 1.0 Universal — [`quaternius_farm_buildings.tres`](../project/attribution/sources/quaternius_farm_buildings.tres) |
| `pre_import_audit` | done (2026-08-26, content-variety pass Task 3) — CC0 re-confirmed. Texture situation confirmed EMPIRICALLY: albedo_texture null on every surface, vertex_color_use_as_albedo true with meaningful, distinct per-surface colors (including a `Brown` wood tone not present on Barn/SmallBarn) — NOT the missing-texture tell. No texture fix needed. Full readings in OpenBarn.tscn's own header. |
| `project_location` | `project/assets/buildings/open_barn/OpenBarn.tscn` (wraps `OpenBarn.fbx`), scaled 0.140618 (raw AABB 5.7438 x 4.7435 x 6.1820 -> scaled 0.8077 x 0.6670 x 0.8693) to House's own established 1x1 max-axis margin |
| `data_entry_location` | `project/data/buildings/open_barn.tres` — `PlaceableDefinition`, `allowed_terrain = ["grass"]`, `emitted_tags = []`. **`cost` 15 and `footprint` 1x1 are FIRST-PASS PROPOSALS** — FLAG FOR HUMAN SIGN-OFF. `fact_text` is a `PLACEHOLDER`-prefixed string |
| `copy_content_location` | not started — `fact_text` is `PLACEHOLDER — flavor copy for the Open Barn pending Content Pipeline step 5.` |
| `attribution_status` | not required (CC0) — courtesy entry recorded in `quaternius_farm_buildings.tres`, `assets_used` includes `OpenBarn` |
| `validation_status` | **pass (2026-08-26)** — `test_farm_buildings_schema.gd`, same checks as `barn`'s row above, adapted to this entry's own proposed values. `WorldRoot.placeable_options()` confirmed to include `open_barn`. Full suite green (87/87, zero SCRIPT ERROR) |
| `human_signoff` | **not yet started.** Cost/footprint proposal, scale fit, and facing (identity, unconfirmed) all await a human eye pass |
| `status` | 🚧 — asset imported and attributed, data entry landed and schema-validated. Copy (step 5), re-validation after copy (step 6), and human sign-off (step 8) are all still open |

### `chicken_coop` — Chicken Coop

| Field | Value |
|---|---|
| `category_attributes` | proposed 1x1 footprint, grass only, ~15 Wood — FIRST-PASS PROPOSAL, no design doc row exists yet; see chicken_coop.tres's own header |
| `source` | Quaternius, "Farm Buildings" — CC0 1.0 Universal — [`quaternius_farm_buildings.tres`](../project/attribution/sources/quaternius_farm_buildings.tres) |
| `pre_import_audit` | done (2026-08-26, content-variety pass Task 3) — CC0 re-confirmed. Texture situation confirmed EMPIRICALLY: albedo_texture null on every surface, vertex_color_use_as_albedo true with meaningful, distinct per-surface colors — NOT the missing-texture tell. No texture fix needed. Full readings in ChickenCoop.tscn's own header. |
| `project_location` | `project/assets/buildings/chicken_coop/ChickenCoop.tscn` (wraps `ChickenCoop.fbx`), scaled 0.361127 (raw AABB 2.4072 x 1.8509 x 2.1540 -> scaled 0.8693 x 0.6684 x 0.7779) to House's own established 1x1 max-axis margin |
| `data_entry_location` | `project/data/buildings/chicken_coop.tres` — `PlaceableDefinition`, `allowed_terrain = ["grass"]`, `emitted_tags = []`. **`cost` 15 and `footprint` 1x1 are FIRST-PASS PROPOSALS** — FLAG FOR HUMAN SIGN-OFF. `fact_text` is a `PLACEHOLDER`-prefixed string |
| `copy_content_location` | not started — `fact_text` is `PLACEHOLDER — flavor copy for the Chicken Coop pending Content Pipeline step 5.` |
| `attribution_status` | not required (CC0) — courtesy entry recorded in `quaternius_farm_buildings.tres`, `assets_used` includes `ChickenCoop` |
| `validation_status` | **pass (2026-08-26)** — `test_farm_buildings_schema.gd`, same checks as `barn`'s row above, adapted to this entry's own proposed values. `WorldRoot.placeable_options()` confirmed to include `chicken_coop`. Full suite green (87/87, zero SCRIPT ERROR) |
| `human_signoff` | **not yet started.** Cost/footprint proposal, scale fit, and facing (identity, unconfirmed) all await a human eye pass |
| `status` | 🚧 — asset imported and attributed, data entry landed and schema-validated. Copy (step 5), re-validation after copy (step 6), and human sign-off (step 8) are all still open |

### `silo` — Silo

| Field | Value |
|---|---|
| `category_attributes` | proposed 1x1 footprint, grass only, ~15 Wood — FIRST-PASS PROPOSAL, no design doc row exists yet; see silo.tres's own header |
| `source` | Quaternius, "Farm Buildings" — CC0 1.0 Universal — [`quaternius_farm_buildings.tres`](../project/attribution/sources/quaternius_farm_buildings.tres) |
| `pre_import_audit` | done (2026-08-26, content-variety pass Task 3) — CC0 re-confirmed. Texture situation confirmed EMPIRICALLY: albedo_texture null on every surface, vertex_color_use_as_albedo true with meaningful, distinct per-surface colors (including a mid-grey metal tone) — NOT the missing-texture tell. No texture fix needed. Full readings in Silo.tscn's own header. |
| `project_location` | `project/assets/buildings/silo/Silo.tscn` (wraps `Silo.fbx`), scaled 0.237029 (raw AABB 3.6675 x 9.0686 x 3.5100 -> scaled 0.8693 x 2.1495 x 0.8320) to House's own established 1x1 max-axis margin — height deliberately NOT capped to match other buildings (a silo reading tall is the point of the shape) |
| `data_entry_location` | `project/data/buildings/silo.tres` — `PlaceableDefinition`, `allowed_terrain = ["grass"]`, `emitted_tags = []`. **`cost` 15 and `footprint` 1x1 are FIRST-PASS PROPOSALS** — FLAG FOR HUMAN SIGN-OFF. `fact_text` is a `PLACEHOLDER`-prefixed string |
| `copy_content_location` | not started — `fact_text` is `PLACEHOLDER — flavor copy for the Silo pending Content Pipeline step 5.` |
| `attribution_status` | not required (CC0) — courtesy entry recorded in `quaternius_farm_buildings.tres`, `assets_used` includes `Silo` |
| `validation_status` | **pass (2026-08-26)** — `test_farm_buildings_schema.gd`, same checks as `barn`'s row above, adapted to this entry's own proposed values. `WorldRoot.placeable_options()` confirmed to include `silo`. Full suite green (87/87, zero SCRIPT ERROR) |
| `human_signoff` | **not yet started.** Cost/footprint proposal, scale fit (including the un-capped ~2.15-unit height), and facing (identity, unconfirmed) all await a human eye pass |
| `status` | 🚧 — asset imported and attributed, data entry landed and schema-validated. Copy (step 5), re-validation after copy (step 6), and human sign-off (step 8) are all still open |

### `windmill` — Windmill

| Field | Value |
|---|---|
| `category_attributes` | proposed 1x1 footprint, grass only, ~15 Wood — FIRST-PASS PROPOSAL, no design doc row exists yet; see windmill.tres's own header |
| `source` | Quaternius, "Farm Buildings" — CC0 1.0 Universal — [`quaternius_farm_buildings.tres`](../project/attribution/sources/quaternius_farm_buildings.tres). Uses `Windmill.fbx` specifically (the pack also ships a taller `TowerWindmill.fbx`, not evaluated here) |
| `pre_import_audit` | done (2026-08-26, content-variety pass Task 3) — CC0 re-confirmed. Texture situation confirmed EMPIRICALLY on both the "Windmill" base and "Windmill_Blades" rotor nodes: albedo_texture null on every surface, vertex_color_use_as_albedo true with meaningful, distinct per-surface colors — NOT the missing-texture tell. No texture fix needed. Full readings in Windmill.tscn's own header. |
| `project_location` | `project/assets/buildings/windmill/Windmill.tscn` (wraps `Windmill.fbx`), scaled 0.133582 (raw combined base+blades AABB 6.5077 x 11.1962 x 1.8979 -> scaled 0.8693 x 1.4956 x 0.2535) to House's own established 1x1 max-axis margin, capped to the BLADE SPAN (a judgment call — see Windmill.tscn's header for the overhang-vs-cap alternative) |
| `data_entry_location` | `project/data/buildings/windmill.tres` — `PlaceableDefinition`, `allowed_terrain = ["grass"]`, `emitted_tags = []`. **`cost` 15 and `footprint` 1x1 are FIRST-PASS PROPOSALS** — FLAG FOR HUMAN SIGN-OFF. `fact_text` is a `PLACEHOLDER`-prefixed string |
| `copy_content_location` | not started — `fact_text` is `PLACEHOLDER — flavor copy for the Windmill pending Content Pipeline step 5.` |
| `attribution_status` | not required (CC0) — courtesy entry recorded in `quaternius_farm_buildings.tres`, `assets_used` includes `Windmill` |
| `validation_status` | **pass (2026-08-26)** — `test_farm_buildings_schema.gd`, same checks as `barn`'s row above, adapted to this entry's own proposed values. `WorldRoot.placeable_options()` confirmed to include `windmill`. Full suite green (87/87, zero SCRIPT ERROR) |
| `human_signoff` | **not yet started.** Cost/footprint proposal, scale fit (including the blade-span-vs-tower-footprint judgment call), and facing (identity, unconfirmed) all await a human eye pass |
| `status` | 🚧 — asset imported and attributed, data entry landed and schema-validated. Copy (step 5), re-validation after copy (step 6), and human sign-off (step 8) are all still open |

### `water_tower` — Water Tower

| Field | Value |
|---|---|
| `category_attributes` | proposed 1x1 footprint, grass only, ~15 Wood — FIRST-PASS PROPOSAL, no design doc row exists yet; see water_tower.tres's own header |
| `source` | Quaternius, "Farm Buildings" — CC0 1.0 Universal — [`quaternius_farm_buildings.tres`](../project/attribution/sources/quaternius_farm_buildings.tres) |
| `pre_import_audit` | done (2026-08-26, content-variety pass Task 3) — CC0 re-confirmed. Texture situation confirmed EMPIRICALLY: albedo_texture null on every surface, vertex_color_use_as_albedo true with meaningful, distinct per-surface colors — NOT the missing-texture tell. No texture fix needed. Full readings in WaterTower.tscn's own header. |
| `project_location` | `project/assets/buildings/water_tower/WaterTower.tscn` (wraps `WaterTower.fbx`), scaled 0.343295 (raw AABB 2.5323 x 8.4286 x 2.4895 -> scaled 0.8693 x 2.8935 x 0.8546) to House's own established 1x1 max-axis margin — height deliberately NOT capped, same reasoning as `silo` |
| `data_entry_location` | `project/data/buildings/water_tower.tres` — `PlaceableDefinition`, `allowed_terrain = ["grass"]`, `emitted_tags = []`. **`cost` 15 and `footprint` 1x1 are FIRST-PASS PROPOSALS** — FLAG FOR HUMAN SIGN-OFF. `fact_text` is a `PLACEHOLDER`-prefixed string |
| `copy_content_location` | not started — `fact_text` is `PLACEHOLDER — flavor copy for the Water Tower pending Content Pipeline step 5.` |
| `attribution_status` | not required (CC0) — courtesy entry recorded in `quaternius_farm_buildings.tres`, `assets_used` includes `WaterTower` |
| `validation_status` | **pass (2026-08-26)** — `test_farm_buildings_schema.gd`, same checks as `barn`'s row above, adapted to this entry's own proposed values. `WorldRoot.placeable_options()` confirmed to include `water_tower`. Full suite green (87/87, zero SCRIPT ERROR) |
| `human_signoff` | **not yet started.** Cost/footprint proposal, scale fit (including the un-capped ~2.89-unit height, the tallest of the 8), and facing (identity, unconfirmed) all await a human eye pass |
| `status` | 🚧 — asset imported and attributed, data entry landed and schema-validated. Copy (step 5), re-validation after copy (step 6), and human sign-off (step 8) are all still open |

### `well` — Well

| Field | Value |
|---|---|
| `category_attributes` | proposed 1x1 footprint, grass only, ~15 Wood — FIRST-PASS PROPOSAL, no design doc row exists yet; see well.tres's own header |
| `source` | Quaternius, "Farm Buildings" — CC0 1.0 Universal — [`quaternius_farm_buildings.tres`](../project/attribution/sources/quaternius_farm_buildings.tres) |
| `pre_import_audit` | done (2026-08-26, content-variety pass Task 3) — CC0 re-confirmed. Texture situation confirmed EMPIRICALLY: albedo_texture null on every surface, vertex_color_use_as_albedo true with meaningful, distinct per-surface colors (including a near-white bucket/rope tone, ~(0.8521, 0.821, 0.821) — distinct on all three channels from the 0.9063 missing-texture tell, and one of five clearly-distinct colors on this mesh, so read as intentional) — NOT the missing-texture tell. No texture fix needed. Full readings in Well.tscn's own header. |
| `project_location` | `project/assets/buildings/well/Well.tscn` (wraps `Well.fbx`), scaled 0.584652 (raw AABB 1.2767 x 2.1456 x 1.4869, the smallest raw mesh of the 8 -> scaled 0.7465 x 1.2544 x 0.8693) to House's own established 1x1 max-axis margin |
| `data_entry_location` | `project/data/buildings/well.tres` — `PlaceableDefinition`, `allowed_terrain = ["grass"]`, `emitted_tags = []`. **`cost` 15 and `footprint` 1x1 are FIRST-PASS PROPOSALS** — FLAG FOR HUMAN SIGN-OFF. `fact_text` is a `PLACEHOLDER`-prefixed string |
| `copy_content_location` | not started — `fact_text` is `PLACEHOLDER — flavor copy for the Well pending Content Pipeline step 5.` |
| `attribution_status` | not required (CC0) — courtesy entry recorded in `quaternius_farm_buildings.tres`, `assets_used` includes `Well` |
| `validation_status` | **pass (2026-08-26)** — `test_farm_buildings_schema.gd`, same checks as `barn`'s row above, adapted to this entry's own proposed values. `WorldRoot.placeable_options()` confirmed to include `well`. Full suite green (87/87, zero SCRIPT ERROR) |
| `human_signoff` | **not yet started.** Cost/footprint proposal, scale fit, and facing (identity, unconfirmed) all await a human eye pass |
| `status` | 🚧 — asset imported and attributed, data entry landed and schema-validated. Copy (step 5), re-validation after copy (step 6), and human sign-off (step 8) are all still open |
