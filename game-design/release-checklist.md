# Release Checklist

> The ship gates for a v1 build. **Worked by [qa-engineer](../.claude/agents/qa-engineer.md);
> signed by the human.** Every line is checkable — a gate that needs a judgment call is
> named as such and routed to the human.
>
> This exists because one obligation here is a genuine blocker rather than polish, and it
> was previously recorded only in a `.tres` comment where nobody would look for it at ship
> time. See **Licensing** below.

## Gate 1 — The suite is green

- [ ] `bash scripts/run-tests.sh` exits 0. Every suite, not a filtered run.
- [ ] The suite count matches `ls project/tests/test_*.gd | wc -l` — a silently skipped
      suite is a failure, not a pass.
- [ ] No suite is passing only because it was pointed at a file that no longer exists.

## Gate 2 — Licensing and attribution

This gate is why the checklist exists. **Attribution is a license obligation, not polish**
(gdd.md, Tier-1 row 15).

- [ ] `godot --headless --path project --script res://attribution/generate_credits.gd`
      exits **0**. It fails closed on any entry claiming `attribution_required` without a
      `required_notice`; a non-zero exit is a real defect, never a script bug.
- [ ] `project/CREDITS.md` is freshly regenerated — not stale relative to
      `project/attribution/sources/*.tres`.
- [ ] `test_attribution.gd` passes.
- [ ] Every license text is present on disk under `project/assets/licenses/` — a link can
      rot, and a compliance review must be answerable offline.
- [ ] **The in-game Credits screen exists and renders the required notice.** ⚠️ **This is
      the release blocker.** The rabbit model ships under **CC BY 3.0**, whose attribution
      condition requires the credit be visible **to the player**. A complete `CREDITS.md`
      does **not** satisfy it. Tracked as Tier-1 row 15; owned by
      [ui-engineer](../.claude/agents/ui-engineer.md). The screen must read the same
      `AttributionEntry` `.tres` files the generator does, so the two cannot drift.
- [ ] **Open item, human decision:** the CC BY 3.0 §4(b) modification-note question,
      recorded as unsettled in `project/attribution/sources/sherkiz_rabbit.tres`. The
      rabbit's wrapper scene overrides materials while leaving the source `.glb`
      unmodified. Resolve before shipping; do not ship it still open.

## Gate 3 — Persistence

- [ ] Save/load round-trip passes: a world quit and reloaded comes back intact.
- [ ] `save_version` is written into every save, from day one.
- [ ] The two completion-test autosave triggers fire — a move-in and a mist reveal
      completing — not interval-only. A hard quit (window close, laptop lid) must not lose
      them, and no exit-to-menu save ever sees that case.
- [ ] Export/Import produces a file that reloads in a fresh install.

## Gate 4 — Trackers are honest

- [ ] No row in [content-pipeline-status.md](content-pipeline-status.md) or
      [tier1-status.md](tier1-status.md) shows ✅ without a recorded human sign-off.
- [ ] Each tracker's scan-table glyphs agree with its per-item `status` rows.
- [ ] A `design-integrity` run reports no BLOCKING findings.
- [ ] No `PROPOSED` or `PLACEHOLDER` marker has reached a shipped `.tres`.

## Gate 5 — Builds

- [ ] Export builds produced for **Linux, Windows, and Mac** (gdd.md → Target Release).
- [ ] Each build launches to the title screen on a clean machine.
- [ ] Performance smoke test holds **30 fps minimum at 1080p** on the reference target — a
      ~5-year-old mid-range laptop with integrated graphics — against a synthetic
      full-size world at the ~128×128 cap.
- [ ] ⚠️ **Human-run, not delegable:** the render validation over that full-size world.
      The headless harness cannot see a windowed run; QA's smoke test is the regression net
      *after* the human baseline exists, never a substitute for it.

## Gate 6 — The product actually works

- [ ] The complete-loop test passes on a shipped build, not just in the editor: new game →
      terraform → gather → build → a move-in → a fact card → mist growth → quit → load,
      world intact.
- [ ] At least one kid playtest has been run against a build at or near this state, per
      [docs/playtests/protocol.md](../docs/playtests/protocol.md).

---

**Sign-off:** the human records date and build identifier here. Gates 2 and 5's human-run
lines cannot be signed by an agent report alone.
