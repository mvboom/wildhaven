# Pilot 3 — Content pipeline: Add-a-Rabbit (four agents — the full content pipeline)

> ## ⚠️ COMPLETED 2026-07-20 — but as **Add-a-Fox**, not Add-a-Rabbit.
>
> **The rabbit failed step 1.** No naturalistic rabbit exists anywhere in the Quaternius
> catalogue — all 82 packs were enumerated; the only `rabbit`/`bunny` hits were a bipedal
> monster, a platformer mascot, and an anthropomorphic restaurant waiter. The Ultimate
> Animated Animal Pack, where one should have been, is 12 medium/large quadrupeds with no
> small mammals at all. Per the brief's own escape hatch, the human substituted **Fox** —
> already a decided v1 roster species, so no roster axis was lost.
>
> **Read the brief below as species-agnostic.** Everything about the eight steps, the
> measurement protocol, and the human gates held up; only the animal changed.
>
> **Outcomes, findings, and per-agent costs: see `costs.md`.** Headlines: the pipeline
> produced a complete, validated species bundle (69 passing assertions); the two most
> valuable findings were environmental rather than about the fox (asset downloads and
> fact-card sources were both firewalled); source verification cost 2.7× the drafting and
> caught two factual errors in copy that had already passed every other gate.
>
> **Rabbit's roster slot is still open**, not resolved. The audit failed *Quaternius*, not
> the world — the GDD permits Synty and 3D-artist escalation, neither tried, and
> `poly.pizza`/`kenney.nl` have since been unblocked. Rabbit is the target of both avoids
> pairs and the roster's only 1-tag species. See "Roster risk" in `costs.md`.

**Session rule:** fresh Claude Code session, this brief as the opening context.
**Agents, in pipeline order:** `tech-art` (audit + look pass) → `gameplay-engineer`
(proposal) → **human decision** → `gameplay-engineer` (data entry) → `content-writer` →
`tech-art` (attribution) → `qa-engineer` → **human sign-off**.
**Prerequisites:** pilots 1–2 complete. Runs LAST deliberately: this measures true
per-unit content cost after one-time setup exists.
**Pipeline spec:** gdd.md → AI Architecture → Content Pipelines → Add-an-Animal.
**Human availability:** this session has TWO synchronous human gates (steps 3 and 8);
run it when you can respond mid-session.

## The eight steps, mapped

1. **Asset audit** (`tech-art`): find a rabbit in Quaternius packs; verify license,
   rig, idle/walk animations, reaction-animation candidates. Hard gate — no cleared
   source, no pipeline. **If the rabbit fails audit:** report and stop; the human
   picks a substitute species (spec rule: same axes covered), and this brief re-runs
   with the substitute. The measurement is species-agnostic.
2. **Import & look pass** (`tech-art`): glTF import, MINIMAL VIABLE look — the toon/rim
   shader and LOD tiers likely don't exist yet; do not build them for this pilot.
   Import clean, apply the simplest acceptable material, note every gap in the report.
   Variation hooks (tint/pattern/size) are OUT for the pilot — note as gap.
3. **Design proposal → HUMAN DECISION** (`gameplay-engineer` proposes): habitat needs,
   personality (Shy|Bold), avoids, farm-tolerance — proposed from real ecology with the
   GDD's Characters/Creatures rabbit row as the starting point. THE HUMAN DECIDES the
   final values before step 4 proceeds.
4. **Data entry** (`gameplay-engineer`): create the `AnimalDefinition` custom Resource
   script if it doesn't exist yet — that creation is `[setup]`, flag it — then the
   rabbit's schema-conformant `.tres` per gdd.md → Data Schemas (fields: id,
   display_name, habitat_needs, personality, avoids, farm_tolerant, model_scene,
   fact_text).
5. **Copy** (`content-writer`): rabbit fact card + News Report blurbs through the
   four-step checklist; strings land in the `.tres` text fields.
6. **Attribution** (`tech-art`): Credits entry per the asset's license terms.
7. **Validation** (`qa-engineer`): schema check of the `.tres`, required-animations
   check, spawn smoke test (spawn the rabbit in the pilot-1 world; it loads and idles —
   roaming behavior is NOT built yet and NOT required).
8. **HUMAN SIGN-OFF:** the picture-book eyeball test in the local editor.

## Done criteria
A complete species bundle: cleared asset imported, decided stats in a schema-valid
`.tres`, checklist-passing copy, attribution entry, QA validation report, human
sign-off. Gaps (shader, variation hooks, roaming) explicitly listed in reports.

## Session close
Run the measurement checklist (`docs/phase0/measurement.md`). Work unit column:
`pilot-3 add-a-rabbit`; the AnimalDefinition script row flagged `[setup]`.
