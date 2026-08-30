---
name: next-task-goal
description: Autonomous "just build the next thing" runner for Wildhaven's Tier 1 build. Runs the full tier1-planner pass, then immediately dispatches the winning row's owner_agent to write the code — no operator confirmation step in between. Use only for a deliberate hands-off run (e.g. a demo); for normal operation use /task-planner or /next-task, which always stop and ask before dispatching.
---

This skill exists to demonstrate the full read-GDD → scan-state → detect-gaps → prioritize →
generate-code loop in one unattended invocation. It reuses `tier1-planner` and whichever
`owner_agent` the winning row names exactly as `/task-planner` does — the only thing this
skill changes is removing the "dispatch this now, or hold it?" pause between planning and
code generation.

Read [.claude/CLAUDE.md](../../CLAUDE.md) first for the doc map; `archive/` is never in
scope for the planning/build steps themselves.

## Why this is safe to skip the gate, and where it still isn't

[.claude/CLAUDE.md](../../CLAUDE.md)'s ground rule is "all tuning values are the human's;
agents propose with sources, the human decides." That rule is enforced *inside* every
`owner_agent` (`gameplay-engineer`, `ui-engineer`, `tech-art` all propose tuning values and
never decide them) — this skill doesn't touch that. What it skips is the *convenience* gate
`task-planner`/`next-task` add on top: asking the operator to confirm before firing the
dispatch call at all. Skipping that convenience gate is the entire point of a goal-oriented
agent — an operator who has to approve every dispatch by hand isn't demonstrating an
autonomous agent, just a slower manual one. Treat this skill as the deliberate exception, not
a template for loosening `/task-planner` or `/next-task` — those keep their gate.

## Procedure

1. Dispatch the `tier1-planner` agent (`.claude/agents/tier1-planner.md`) via the `Agent`
   tool, exactly as `/task-planner` does, run in the foreground (`run_in_background:
   false`). This performs the read-GDD, scan-state, and detect-gaps steps and writes its
   dated report to `docs/dispatch/tier1-next-<date>.md`.
2. Read that report's **Identified next step** and **Ready-to-dispatch brief** sections —
   this is the prioritize step, already done, with its reasons already written down.
3. Check the winning row before dispatching anything:
   - If the report's own classification marks the top row **not dispatchable** (next step 2
     or 5, or carrying `⛔`), stop. There is nothing to auto-build — report the blocker
     plainly and recommend `/next-task-human`. Never fall through to a lower-ranked row; that
     silently substitutes a different goal than the one the planner actually picked.
   - If the winning row's `owner_agent` is `"content pipeline"`, stop. Say plainly that this
     row routes through the Content Pipeline's step-3 human decision (`gdd.md`), not a code
     dispatch, and do not invoke any agent.
4. Otherwise, dispatch the named `owner_agent` via the `Agent` tool with the brief as its
   `prompt`, verbatim, no edits — run in the foreground. **Do not ask the operator first.**
   This is the one point where this skill's behavior differs from every other skill in this
   family, and it's deliberate (see above).
5. Once the owner_agent completes, report back in this shape:
   - **Row picked, and why** — the row #, name, and the planner's own ranking reasons,
     quoted from step 2 above.
   - **What got built** — the owner_agent's own summary of the files it wrote or changed.
   - **Did it run** — whatever verification the owner_agent itself performed (tests it ran,
     `mcp__godot__run_project` output, etc.) — do not independently claim success beyond what
     the owner_agent reported.
   - **Gate note** — one line stating this run skipped the operator-confirmation step by
     design (see above), so the record is honest about what happened.

This skill writes no report file of its own beyond what `tier1-planner` already wrote — its
job is the orchestration between planning and dispatch, not a new tracked artifact.

## What this skill does not do

It does not read game source files to independently verify what's built — like
`tier1-planner`, it trusts `tier1-status.md`'s maintained `implementation_location` and
`validation_status` fields (spot-checked for existence, not content) rather than re-deriving
build state from the codebase itself. That tracker is kept current specifically because
steps 3 and 4 of `systems-pipeline.md` require it, so treating it as ground truth here is the
same call `tier1-planner` already makes, not a new shortcut introduced by this skill.

## Boundary
- Run no git commands.
- Never edit `tier1-status.md`, `gdd.md`, `decisions.md`, or any tracker field — the
  dispatched `owner_agent` may propose edits in its own output; applying them is still the
  operator's step.
- Never decide a constant or sign a human gate — both stay named human blocks, exactly as in
  `tier1-planner`'s own boundary.
- Never substitute a lower-ranked row for a blocked top pick — stop and say so instead.
- Dispatch exactly one `owner_agent` call per run, for the single winning row only.
