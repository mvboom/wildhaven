---
name: next-task-human
description: Surfaces Wildhaven's Tier 1 rows that are blocked on a human decision or check, triaged into paperwork/decision/verify with drafted replacement text, sourced candidate values, and minimal verification checklists. Dispatches the tier1-unblocker agent and presents its report. Use when you want to clear human blocks on the Tier 1 build, not just see the list of them.
---

Dispatch the `tier1-unblocker` agent (`.claude/agents/tier1-unblocker.md`) via the `Agent`
tool with a prompt asking it to read the latest `docs/dispatch/tier1-next-*.md` report and
triage its "Blocked, needs a human" list per its own instructions. Run it in the foreground
(`run_in_background: false`) — its report is what this skill exists to show, so there is
nothing useful to do while it's running.

If `tier1-unblocker` reports that no `docs/dispatch/tier1-next-*.md` file exists yet, relay
that directly: tell the operator to run `/task-planner` first, since there is no blocked-
rows list to triage without a prior full pass.

Otherwise, once it completes, present its report to the operator in full — the Paperwork,
Decision, and Verify sections in that order, as it wrote them. Do not summarize, trim, or
reorder its buckets; the ordering (cheapest first) is itself part of what makes the report
actionable.

This skill takes no further action on its own. It does not edit any tracker file, does not
apply any drafted text, and does not ask a follow-up dispatch question — `tier1-unblocker`'s
output is proposals for the operator to apply by hand, not a brief to fire at another agent.

## Boundary
- Run no git commands.
- Never edit `tier1-status.md`, `gdd.md`, `decisions.md`, or any tracker field.
- Never decide a constant or sign a human gate — both stay named human blocks.
- Never dispatch an agent except at the points explicitly named above (this skill's own
  full-pass or triage dispatch, or the dispatch offer's follow-up call) — and the dispatch
  offer's follow-up call never fires without the operator's explicit go-ahead in that same
  exchange.
