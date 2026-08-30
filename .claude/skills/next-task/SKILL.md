---
name: next-task
description: Cheap "what's next" check for Wildhaven's Tier 1 build. Diffs the latest tier1-planner dispatch report against tier1-status.md's scan table; promotes the next candidate if the top pick closed, re-surfaces the same brief if nothing changed, or bails to /task-planner if anything else moved. Use for the common case of "I just finished the last item, what's next" — use /task-planner for a full re-rank instead.
---

Run this entirely inline — do not dispatch any agent for this skill. The whole point is to
be cheaper than a full `tier1-planner` pass; spawning an agent for a fifteen-row diff
reintroduces the cost this skill exists to avoid.

## Procedure

1. Find the most recent `docs/dispatch/tier1-next-*.md` file by filename date (`ls
   docs/dispatch/tier1-next-*.md` and sort). If none exists, stop and tell the operator to
   run `/task-planner` first — there is no baseline to diff against.
2. Read that report's **classification table** (its required first section — the `| # |
   System | Phase | Scan glyph | Next incomplete step | Dispatchable? |` table) and its
   ranked/runner-up list. This is the cached baseline — trust its ranking, do not re-derive
   it from scratch.
3. Read two things fresh, and nothing else:
   - `game-design/tier1-status.md`'s scan table (under its `## Scan table` heading — the
     compact `| # | System | Phase | Owner | Depth | Est h | Status |` table, not the
     per-row detail blocks that follow it, and not the changelog prose above it).
   - The **top-ranked row's own detail block** in `tier1-status.md` (one row only, by its
     `## Row N — ...` heading).

   Do not read any other row's detail block yet, and do not read `gdd.md`,
   `systems-pipeline.md`, or `next-steps.md` in this skill — those are only read during a
   full `tier1-planner` pass. To classify the top-ranked row's own next incomplete step
   from its detail block, apply the exact same five rules `tier1-planner.md`'s own
   "Classify every row" section defines (read that section of `tier1-planner.md` — it's
   short, and using the identical rules keeps the two tools from ever disagreeing on what
   counts as "step 2" versus "step 3").
4. Diff in two stages:

   **Stage A — check every OTHER row for unexpected drift.** Compare the fresh scan
   table's phase and glyph, row by row, against the cached classification table — for every
   row except the top pick. If any of those rows' phase or glyph changed, or a new `⛔`
   appeared, stop immediately: name exactly which row(s) diverged and what changed (old →
   new), and tell the operator to run `/task-planner` for a full re-rank. Never proceed to
   Stage B if Stage A finds unexplained drift elsewhere.

   **Stage B — check the top-ranked row's own progress.** Using the top-ranked row's fresh
   detail-block classification (step 3's read), compare its next-incomplete-step to what
   the cached classification table recorded for it:
   - **Unchanged, AND the top-ranked row's fresh scan-table glyph is not `⛔`** → "Nothing changed." Re-surface the cached report's existing top brief unchanged. Do not re-spot-check it. (If the step is unchanged but the fresh scan-table glyph for the top-ranked row IS now `⛔`, treat this the same as Stage A's drift case: stop, name the row and the new `⛔`, and recommend `/task-planner` — a newly-blocked top pick must never be silently re-dispatched.)
   - **Advanced to `human_gate` recorded (now ✅)** → it closed since the cached report.
     Promote: take the cached report's own next-ranked runner-up row, read **that row's**
     detail block, apply the same five classification rules to confirm it is still
     dispatchable (next-incomplete-step is 1, 3, or 4, no `⛔`) — if it is no longer
     dispatchable, stop and recommend `/task-planner` rather than searching further down
     the list; `/next-task` promotes exactly one level, never chains further. If it is
     still dispatchable, spot-check it exactly as `tier1-planner` does for its top
     candidate (confirm `implementation_location` paths exist; confirm any named
     `validation_status` suites exist under `project/tests/`), and build its dispatch brief
     directly from its own detail block's `thin_form`, `invariants`, and acceptance
     condition — the same shape `tier1-planner`'s own brief uses.
   - **Advanced to something else (its next-incomplete-step moved, but isn't ✅ yet — e.g.
     3→4 or 4→5)** → by definition this row is no longer a dispatchable gap: reaching step
     4 or step 5 means it now needs verification or a human decision, not more building. Do
     **not** re-offer the old "build this" brief — the work described in it is already
     done. Instead, report plainly: name the row, what changed (old step → new step), and
     recommend `/next-task-human` if its new next-incomplete-step is 5, or note it's mid-
     verification (step 4) otherwise.

   Never read any row's detail block beyond the top-ranked row and, if promotion happens,
   its one successor.
5. If Stage B resolved to a brief (the "nothing changed" or "promoted" cases), make the
   dispatch offer:

   > Name the winning row (# and name) and its `owner_agent`. Ask the operator directly:
   > dispatch this now, or hold it?
   >
   > - If the operator confirms and `owner_agent` names a real agent (`ui-engineer`,
   >   `gameplay-engineer`, `tech-art`, or any other agent in `.claude/agents/`), issue the
   >   `Agent` tool call to that agent with the ready-to-dispatch brief as its `prompt`,
   >   verbatim, no edits.
   > - If `owner_agent` is `"content pipeline"` (row 8's current shape), do not offer a
   >   code-dispatch call at all. Say plainly that this row routes through the Content
   >   Pipeline's step-3 human decision (`gdd.md`) instead of a direct agent dispatch, and
   >   stop there.
   > - If the operator says hold, stop — do not dispatch anything, and do not ask again
   >   later in the same turn. A future `/next-task` or `/task-planner` invocation will offer again.

   Never dispatch without the operator's explicit go-ahead in that same exchange. A prior
   confirmation for a different row on a different day is not standing approval for this
   one.

This skill writes no report file of its own — it is a read-diff-offer, not a new record.

## Boundary
- Run no git commands.
- Never edit `tier1-status.md`, `gdd.md`, `decisions.md`, or any tracker field.
- Never decide a constant or sign a human gate — both stay named human blocks.
- Never dispatch an agent except at the points explicitly named above (this skill's own
  full-pass or triage dispatch, or the dispatch offer's follow-up call) — and the dispatch
  offer's follow-up call never fires without the operator's explicit go-ahead in that same
  exchange.
