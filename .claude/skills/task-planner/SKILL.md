---
name: task-planner
description: Full re-rank of Wildhaven's fifteen Tier 1 rows. Dispatches the tier1-planner agent fresh, presents its report, then offers to dispatch the winning brief. Use when starting a new work session, after several rows have changed since the last pass, or when /next-task bails because it found drift its cheap diff couldn't explain.
---

Dispatch the `tier1-planner` agent (`.claude/agents/tier1-planner.md`) via the `Agent` tool,
asking it to run its full classify-rank-spot-check pass and write its dated report. Run it
in the foreground (`run_in_background: false`) — there is nothing useful to do before
seeing its report.

Once it completes, present the full report to the operator: the classification table, the
identified next step and its ranking reasons, the ready-to-dispatch brief, the runner-up
list, and the blocked-rows table. Do not trim any section. The report's own closing question
(its final item) is superseded by the dispatch offer below — read the report's other
sections in full, but treat the offer below as the one the operator actually answers.

Then make the dispatch offer:

> Name the winning row (# and name) and its `owner_agent`. Ask the operator directly: dispatch
> this now, or hold it?
>
> - If the operator confirms and `owner_agent` names a real agent (`ui-engineer`,
>   `gameplay-engineer`, `tech-art`, or any other agent in `.claude/agents/`), issue the
>   `Agent` tool call to that agent with the ready-to-dispatch brief as its `prompt`,
>   verbatim, no edits.
> - If `owner_agent` is `"content pipeline"` (row 8's current shape), do not offer a
>   code-dispatch call at all. Say plainly that this row routes through the Content
>   Pipeline's step-3 human decision (`gdd.md`) instead of a direct agent dispatch, and stop
>   there.
> - If the operator says hold, stop — do not dispatch anything, and do not ask again later
>   in the same turn. A future `/next-task` or `/task-planner` invocation will offer again.

Never dispatch without the operator's explicit go-ahead in that same exchange. A prior
confirmation for a different row on a different day is not standing approval for this one.

## Boundary
- Run no git commands.
- Never edit `tier1-status.md`, `gdd.md`, `decisions.md`, or any tracker field.
- Never decide a constant or sign a human gate — both stay named human blocks.
- Never dispatch an agent except at the points explicitly named above (this skill's own
  full-pass or triage dispatch, or the dispatch offer's follow-up call) — and the dispatch
  offer's follow-up call never fires without the operator's explicit go-ahead in that same
  exchange.
