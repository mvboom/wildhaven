# SDD ledger — plan: docs/superpowers/plans/2026-09-04-habitat-tiers.md

Branch: feature/habitat-tiers
Base: 23b9eb385fbe03ef0cc4a3100890d3a67d719cf1

Task 1: implemented (commits 23b9eb3..55a6554) — HabitatNeed/HabitatLimit/HabitatTier + test_habitat_tier_schema.gd, 13/13 pass. Review dispatched.
Task 1: complete (commits 23b9eb3..55a6554, review clean — spec ✅, quality approved, 0 findings)
Task 2: BASE=55a6554
Task 2: implemented (commits 55a6554..0d30a28) — animal_tiers 16/16, capacity_formula 53/53 regression gate holds.
Task 2: minor (deferred): _legacy_tier_cache sits in the functions section, conflicting with the file's stated fields-then-functions convention. Brief-mandated placement.
Task 2: minor (deferred): _legacy_tier_cache has no invalidation — would go stale if flat fields are ever mutated at runtime (hot-reload/runtime tuning). Inert today, no such path exists.
Task 2: ⚠️ resolved by controller — "cache used in dirty-queue drain" unverifiable from diff because the call site is Task 4's capacity() rewrite. Not a gap.
Task 2: complete (commits 55a6554..0d30a28, review clean — spec ✅, quality approved, 2 deferred minors)
Task 3: BASE=0d30a28
Task 3: implemented (commits 0d30a28..9ff6a4d) — habitat_validation 19/19 PASS; full suite 115/120, 5 expected failures: test_fox_schema, test_human_schema, test_inert_land_invariant, test_news_report, test_rabbit_schema. Task 9 closes these.
Task 3: CARRIED FINDING (from Tasks 1-2, confirmed by controller) — 5 orphaned .gd.uid files untracked: habitat_limit/habitat_need/habitat_tier.gd.uid, test_animal_tiers/test_habitat_tier_schema.gd.uid. Repo tracks 202 .gd.uid, not gitignored, Task 3 committed its own. Assigned to Task 4 implementer.
Task 3: minor (deferred): AnimalDefinition.BARE_TAGS is still hardcoded ["open_grass","quiet"] — and this branch just RETIRED `quiet` from HABITAT_TAGS, so BARE_TAGS now names a tag outside the vocabulary. Pre-existing hardcode (docstring already says "MUST BECOME DERIVED", tracked by test_bare_tags_derivation.gd), but the staleness is NEW as of Task 3. FINAL REVIEW MUST TRIAGE.
Task 3: minor (deferred): brief prose says Domesticated requires "no `built` limit" but the brief's own code never checks limits in that branch. Harmless (has_building_need already excludes it from Wild) but prose/code diverge. Brief defect, not implementer's.
Task 3: complete (commits 0d30a28..9ff6a4d, review clean — spec ✅, quality approved, 2 deferred minors; DFS hand-traced across 2-cycle/3-cycle/self-edge/diamond/disconnected, no failure modes)
Task 4: BASE=9ff6a4d
Task 4: implemented (commits 9ff6a4d..2685548, 2 commits: 7e19b41 uid cleanup + 2685548 formula) — tier_capacity 12/12, capacity_formula 53/53 unedited, full suite 116/121 with red list unchanged (same 5).
Task 4: DEVIATION 1 — tag_counts() tier param defaults null (brief required positional); null-tier calls emit BOTH radius-keyed and bare-tag-alias entries. Done to avoid editing the forbidden-to-edit test_capacity_formula.gd.
Task 4: DEVIATION 2 — added _uncached_legacy_tier(); implementer found Task 2's cache bakes a concrete radius so a live scout_radius retune stops tracking. This is Task 2's "inert today" staleness minor, now proven LIVE.
Task 4: review — spec ✅, quality Approved. One-walk rule, GATE_ONLY, limits-gate, no-lower-clamp all verified; _tile_counts_for() byte-identical; 7e19b41 is uid-only.
Task 4: Deviation 1 (null tier default + dual keys) ACCEPTED by reviewer — test_capacity_formula.gd really does make 6 direct 4-arg calls; keys are disjoint, no double-count.
Task 4: Deviation 2 escalated to human (plan-mandated conflict). HUMAN RULED: take the sentinel fix; it overrides task-2-brief.md:183. Brief amended. Fix round 1 dispatched to original implementer.
Task 4: minor (deferred): tag_counts() legacy mode emits both radius-keyed and bare-tag-alias entries; bare-tag-only would be cleaner. FINAL REVIEW TRIAGE.
Task 4: minor (deferred): two needs in one tier sharing a tag AND a resolved radius share one bucket key, double-counting that tile. Inherited from brief snippet; harmless for current data. FINAL REVIEW TRIAGE.
Task 4: fix round 1/5 (1 addressed, 0 open — sentinel fix landed, _uncached_legacy_tier deleted, key alignment verified, test_animal_tiers edit judged STRONGER not weakened, test_capacity_formula unedited; commits 2685548..5479f96)
Task 4: complete (commits 9ff6a4d..5479f96, review clean after 1 fix round, 2 deferred minors)
Task 5: BASE=5479f96
Task 5: implemented (commits 5479f96..f1bf3e2) — resident_tags 8/8, capacity_formula 53/53 unedited, tier_capacity 12/12, tile_exclusivity 45/45, full 117/122, red list unchanged.
Task 5: review — spec ✅, quality Approved with 1 Important. Per-individual counting, both key shapes, restore_site() re-derivation, never-persisted, self-site skip, tile-exact sites_at() all verified in code. Brief's vacant-site test inconsistency was real; amended test judged non-vacuous.
Task 5: IMPORTANT — new suite's 3 assertions are algebraic mirrors, never call the real tag_counts(); bucket-write loop untested. Originates in brief snippet. Fix round 1 dispatched (add integration coverage, no production changes).
Task 5: minor (deferred): sites_at() is an O(sites) linear scan called per-tile inside tag_counts(), making cost radius^2 x roster x tiers x sites. Fine at dozens of home sites; revisit if hundreds. FINAL REVIEW TRIAGE.
Task 5: minor (deferred): no per-site de-dup if a species' emits_tags ever held a duplicate tag. Roster-validation concern. FINAL REVIEW TRIAGE.
Task 5: NOTE — reviewer traced the self_site==null "hole" (prospective candidate on an occupied same-species tile) and found it unreachable on all production paths; wants a code comment, not a fix.
Task 5: fix round 1/5 (1 addressed, 0 open — 4 real integration checks added calling tag_counts() directly; per-tile regression WOULD fail them; test-only diff; commits f1bf3e2..50001ab)
Task 5: complete (commits 5479f96..50001ab, review clean after 1 fix round, 2 deferred minors + 1 comment-only note)
Task 6: BASE=50001ab
Task 6: implemented (commits 50001ab..754f19a) — group_arrivals 17/17, arrival/save/capacity_formula PASS, full 118/123, red list unchanged.
Task 6: double-walk FIXED — added CapacityEvaluator.evaluate() returning {capacity, tier} from one tier loop; capacity()/best_tier() became thin adapters; _evaluate() walks no more than before.
Task 6: FOR HUMAN — save_version bumped to 6, which forced renumbering two header comments that had RESERVED v6 for Tier-1 row 13's mist-extent work; those now say v7. Cross-feature coordination item.
Task 6: complete (commits 50001ab..754f19a, review clean — spec ✅, quality approved, ZERO findings. Both deviations judged sound; hoisted-recheck test confirmed would fail; save_version 5->6 migrate() step verified; best_tier() had zero prior callers.)
Task 7: BASE=754f19a
Task 7: BLOCKED then UNBLOCKED by controller. Implementer correctly stopped: 5 pre-existing suites pin facts this design deliberately changes — test_placeable_schema + test_causality_end_to_end (house.tres emitted_tags==["house"]), test_farm_buildings_schema (8 farm buildings emitted_tags==[] AND placeable_options()==9), test_hud_hotbar (farm hotbar==8), test_mode_tap_model ("emits no tags").
Task 7: RULING — authorized expectation updates under the plan's existing Task-9 policy (change expected values, never delete assertions, never weaken a rule, record old->new, stop if a failure isn't traceable to a deliberate change). NOT escalated: plan policy already covers it and the human already approved the Farmhouse.
Task 7: FOR HUMAN — adding Farmhouse makes the build hotbar 9 farm buildings instead of 8. Player-visible consequence of the OQ-D "larger house" ruling.
Task 7: Farmhouse model = assets/buildings/house_secondage_1_level3/HouseSecondage1Level3.tscn (largest wired variant, 2nd-tallest after the two towers). Proposals needing sign-off: cost=30, footprint=2x2, model/scale/facing.
Task 7: complete (commits 754f19a..539c221, review clean — spec ✅, quality approved, 0 Critical/Important). All 6 expectation edits audited as value swaps; none deleted, none loosened. built on all 10 placeables verified; 3 subsumptions verified; no trough tag invented; HABITAT_TAGS untouched; no new art imported.
Task 7: PROCESS GAP — task-7-report.md was never written despite being requested; test evidence exists only in the agent's return message (building_tags 76/76, full 119/124, red list = the expected 5). Diff was self-consistent so approval stands.
Task 8: BASE=539c221
Task 8: implemented (commit 51bd554 — COMMITTED BY CONTROLLER, the tech-art agent declined git citing the repo CLAUDE.md rule, unaware the human lifted it in-session). new_terrains 26/26, terrain_schema 127/127, attribution 50/50.
Task 8: REAL DEFECT FOUND (not a stale pin) — 3 new terrains take the Terraform palette to 11 buttons, overflowing the fixed HUD band into the Rotate/Erase cluster. Agent correctly left test_hud_hotbar's overlap guard FAILING rather than weakening it.
Task 8: HUMAN RULED — group grass + wild_grass + meadow + scrub behind one button; snowfield stays standalone. Yields 6 terrain + House + Farm Building = 8 buttons, the band's original count. Dispatched as Task 8b to ui-engineer.
Task 8b: BASE=51bd554 (unplanned follow-up, not in the original 11)
Task 8b: implemented (commit 46af257) — hud_hotbar 466/0 with overlap guard passing on real geometry, mode_tap 116/0, terrain green, full 120/125, red list = the expected 5. Group name proposed: "Grasslands" [COPY], awaiting sign-off.
Tasks 8+8b: complete (commits 539c221..46af257, combined review clean — spec ✅, quality approved, 0 Critical/Important). INERT-LAND INVARIANT HOLDS: wild_grass.tres absent from the 55-file diff, derive_bare_tags() still empty. Overlap guard confirmed BYTE-IDENTICAL — 8b fixed geometry, not the assertion. All 4 grouped terrains proven paintable via real paint_tile() coverage.
Tasks 8+8b: minor (deferred): wild_grass lost its long-press style-picker door (had 1 variant, inert today). FINAL REVIEW TRIAGE.
Tasks 8+8b: minor (deferred): TERRAIN_GROUP_MEMBERS duplicated across game_hud.gd and world_root.gd, following the codebase's existing bare-literal "farm_building" convention. FINAL REVIEW TRIAGE.
Tasks 8+8b: FOR HUMAN — group display name "Grasslands" is [COPY]-tagged and awaits content-writer/human sign-off.
Task 9: BASE=46af257
Task 9: PLAN DEFECT (controller-corrected before dispatch) — spec and plan both say "sixteen species"; there are FIFTEEN. Chicken has no AnimalDefinition (asset never purchased). Test corrected to >=15. Consequence: `coop` (ChickenCoop) will have no consuming species, like `sand`.
Task 9: implemented (commits 46af257..095933c) — FULL SUITE GREEN 126/126. 15 species, 15 distinct signatures, acyclic, 2 emitters. All 5 long-standing reds closed. BARE_TAGS fixed [open_grass,quiet]->[open_grass] (closes Task 3's deferred minor). 8 collateral suites repointed rock->cultivated_field for Rabbit's new tier.
Task 9: review — spec ✅ (all 15 parsed against spec §9), quality Approved. All 8 repoints preserved test subject; no assertion count fell (11 suites diffed). Alpaca's late barn* gate survived. Stag's deer/4 is pure data, no code special-case. BARE_TAGS fix verified correct, invariant not weakened.
Task 9: IMPORTANT — HomeSite.serves() (home_site.gd:103) and HabitatSimulation._home_site_radius_for() (habitat_simulation.gd:167) still read the FLAT habitat_needs. Cow/Bull/Horse/Alpaca's building gates live only in tiers, so a Barn/Silo/Stable returns radius 0 and _sync_structure_site() bails — a barn never becomes a home site the way a House does for a villager. Dispatching as Task 9b.
Task 9: RULED (reviewer, no human needed) — Sheep's `mill` as GATE_ONLY is correct: every other building tag in §9 carries `*`, mill is in BUILDING_TAGS, and a divisor would cap the flock at 1 (the exact failure GATE_ONLY exists to prevent). Treat as a one-char spec typo for the fold-back.
Task 9: minor (deferred): causality/preview fixtures now consume Wood where rock was free (no Wood assertion touched). FINAL REVIEW TRIAGE.
Task 9: minor (deferred): test_inert_land_invariant's two `quiet` assertions are now near-tautologies against a retired tag; better repointed at a live bare tag. FINAL REVIEW TRIAGE.
Task 9: minor (deferred): stale fixture names (RABBIT_ROCK_ORIGIN etc.) now name cultivated blocks. FINAL REVIEW TRIAGE.
Task 9: minor (deferred): signature fn reads `radius` raw, so follow-scout(0) vs explicit-equal would sign differently. Errs safe; no shipped pair at risk. FINAL REVIEW TRIAGE.
Task 9: complete (commits 46af257..095933c, review clean, 1 Important routed to Task 9b, 4 deferred minors)
Task 9b: BASE=095933c (unplanned, closes Task 9's Important finding)
Task 9b: complete (commit 095933c..0977e0b, review clean — spec ✅, quality approved, 0 Critical/Important). Test CONFIRMED would have failed pre-fix. Radius takes max() across MATCHING tiers, no under-reach. No special-casing. wild_grass edit comment-only (0 data changes). No pre-existing test edited or deleted. Full suite 127/127.
Task 10: BASE=0977e0b
Task 10: implemented (commit 0977e0b..51a7d98) — habitat_recipe 53/53, field_guide 55/55 + reachability 81/81, hud 466/466, FULL SUITE 127/127 GREEN.
Task 10: LIVE PLAYER-FACING BUG FOUND, NOT FIXED (needs human ruling) — Horse's `stable` gate (emitted ONLY by open_barn.tres) renders as "a barn", because tag_sources() resolves grouped-placeable display names from the Farm Building group's CURRENT DEFAULT rather than the member that actually carries the tag. The game would tell a child to build a Barn when a horse needs an Open Barn. Pre-existing accepted simplification (finding #7), latent until emitted_tags went live this branch. Agent correctly declined to reverse a pinned prior ruling.
Task 10: 6 copy proposals awaiting sign-off (see task-10-report.md).
Task 10: review — spec ❌ / Changes needed. TWO findings.
Task 10: CRITICAL — group-resolution bug affects 4/15 species, not 1. farm_building default resolves alphabetically to barn.tres, so tags Barn doesn't carry mislabel as "a barn": Horse(stable/open_barn), Sheep(mill/windmill), Human(large_house/farmhouse). Bull(large_barn) safe, coop unconsumed, water safe via _cheapest(). WORSE: Cow needs barn AND silo, both resolve to button_id "farm_building", so _need_phrase()'s `seen` dedup ERASES the silo requirement entirely — not mislabeled, gone.
Task 10: IMPORTANT — field_guide.gd still renders the old describe()/recipe_for() line above the tier block, still reading flat habitat_needs. Horse/Cow/Bull/Alpaca STILL display identically, directly above the fix.
Task 10: HUMAN RULED — "fix it properly": resolve grouped display name from the member carrying the tag, and key dedup on resolved building not group button. Reverses the pinned simplification. Fix round 1 dispatched with both findings + required per-species tests.
Task 10: Grasslands judgement call UPHELD by reviewer — recipe text names what to place, not the palette label; misleading beats merely imprecise for ages 6-10.
Task 10: fix round 1/5 (2 addressed, 1 NEW Critical opened; commits 51a7d98..10414a4). Finding 1 ADDRESSED — tag_sources() now returns resolved_id separately from button id; dedup keys on resolved_id; Cow names open barn AND silo, verified by execution. Finding 2 ADDRESSED — flat describe()/recipe_for()/chips block deleted from field_guide.gd, no raw habitat_needs on the display path.
Task 10: NEW CRITICAL — SOURCE_PHRASES carries baked-in articles ("a house","a farm field") written for the now-deleted describe(); new templates treat them as bare nouns. Yields "more a farm field means room for more" (Human/Bull/Pig/Rabbit) and "needs an a house" (Human/Pug/Shiba Inu). 6 of 15 species. Structural, not copy.
Task 10: PROCESS — implementer's report printed "needs a house" as captured runtime output; actual runtime is "needs an a house". Sample was not from a real run. Fix round 2 requires executed, verbatim output.
Task 10: reviewer ruled the dropped icon chips a fast follow-up, not a merge blocker. Cow's "an open barn" via _cheapest() left as a non-urgent human ruling item.
Task 10: fix round 2/5 (1 addressed, 0 open; commits 10414a4..37b3f9e). Root-cause fix: SOURCE_PHRASES holds bare nouns, _bare_noun() normalises, templates supply their own articles. Structural, not 6 special cases. New _check_no_article_defects_across_the_roster() scans all 15 species x every line for 4 doubling + 2 missing-article patterns — WOULD catch a 7th species or a reworded phrase. All 14 claimed lines independently derived from data and matched character-for-character. Bull "a barn" and Pug "a house" both verified correct, not resolution artefacts.
Task 10: complete (commits 0977e0b..37b3f9e, review clean after 2 fix rounds)
Task 11: BASE=37b3f9e
Task 11: complete — FULL SUITE 127/127, 5049 assertions, exit 0. Inert-land invariant HOLDS. Graph acyclic, 15 distinct signatures. gentle_displacement 161/161 (the regression gate on the whole formula rewrite). Widest per-need radius actually used = 14, under the human's 16 ceiling (59 need entries: 47x0-sentinel, 2x5, 1x8, 1x12, 9x14). All 15/15 species on authored tiers, legacy flat fields retained but inert. Fold-back list written: gdd.md(5), roster.md(1), terrain.md(1), buildings.md(2), spec.md(3), decisions.md(1 -> D-52), plus 2 spec-text errors and the coop-has-no-consumer note.
ALL 11 TASKS COMPLETE. Dispatching final whole-branch review.
FINAL WHOLE-BRANCH REVIEW: verdict FIX FIRST. Two branch-introduced regressions, both passing 127/127.
  C1 (Critical) — onboarding_coach.gd:132-147 still calls easiest_species()/recipe_for()/describe(), which still read flat habitat_needs. First-run coach says "Rabbits are easiest. Likes open grass and rocky cover" but Rabbit's real tier is open_grass/4 + cultivated/4 + !built<=2. A child paints grass and rock and NO RABBIT CAN EVER ARRIVE. Both tests over this path are self-referential (HabitatRecipe output vs HabitatRecipe output) — why the suite missed it.
  I2 (Important) — species sites register/claim at scout_radius, and claim() OVERWRITES site.radius. Deer's herd tier counts to 14 but its site is 10, so edits 11-14 tiles out never re-evaluate. Horse's Open Barn is registered at 14 by Task 9b then shrunk to 8 by the first move-in, breaking the spec's own flagship "dig more pond, get more horses" example from the first arrival onward.
FINAL REVIEW: invariants ALL PASS (inert-land, one-formula, no-lower-clamp, acyclic graph, human-gated vocabulary). Test-quality policy held: net assertion delta -27/+206, only 2 files lost any and both gained more.
FINAL REVIEW: deferred-minor triage — 2 closed (BARE_TAGS, self_site comment), 4 won't-fix, 11 follow-up. T5a (sites_at O(sites) scan) WORSENED by the branch (~2.7x calls: radius 12->14, tiers 1->2); not a blocker at dozens of sites, wants a position->sites index.
FINAL REVIEW: note for human — _describe_limit() renders Rabbit's !built<=2 as "away from buildings", which reads absolute though two buildings are tolerated.
FIX WAVE dispatched: C1, I2, plus 2 one-line validate guards (duplicate tier bucket key, duplicate emits_tags entry).
FIX WAVE: complete (commit 37b3f9e..720d97c, committed by controller — agent again declined git on the repo rule). C1 ADDRESSED (coach reads tiers; grep clean; regression test independently derived from rabbit.tres, self-referential shape NOT reproduced). I2 ADDRESSED (claim() uses maxi so never narrows; _move_in() registers at _species_widest_radius(); reuses Task 9b's tier.max_radius() rather than a second copy; new suite discriminates BOTH faults pre/post fix). Both validate guards landed and pinned.
FIX WAVE: re-review regression checks all clear — stale-wide site.radius is possible after a retune but harmless (walk radius computed independently from tier.max_radius(), never from site.radius); no over-dirtying beyond intent; all branch invariants still hold.
FIX WAVE: Rabbit->Deer starter change is CORRECT CODE, not a scoring bug — cultivated_field costs 2 Wood by decided rule, Deer's base tier is all free terrain, WOOD_COST_WEIGHT makes free terrain win. The old flat fields (open_grass+cover, both free) were masking Rabbit's real wood cost. Design/balance call for the human.
BRANCH COMPLETE: 19 commits, full suite 128/128, 0 failures. Awaiting human ruling on the onboarding starter species.
