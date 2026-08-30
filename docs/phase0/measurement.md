# Pilot measurement protocol

Purpose (gdd.md, Technical Strategy → Token Budget): measure three pilot work units so
the extrapolation template can be filled from data. Plausibility, not precision.

## Session rules

1. **One work unit per Claude Code session** — still recommended, but for *human-hours*
   attribution only. Token attribution no longer depends on it: `token-report.py` breaks
   out every subagent individually, so mixed sessions stay measurable.
2. **Per-agent tokens come from the session transcripts, not `/cost`.** `/cost` reports
   subscription-level usage and cannot answer this. Do not use the harness's
   end-of-run `subagent_tokens` figure either — it understated pilot 2 by ~2.5×.
3. **Record the main loop as its own row.** Orchestration (reading briefs, dispatching,
   verifying, writing the ledger) measured ~1:1 against the agent work it dispatched.
   Omitting it understates a work unit by roughly half.
3. **`[setup]` work inside a pilot session** (creating project structure, schemas,
   toolchain fixes): where the session can attribute it (e.g. a distinct dispatch),
   log it as its own `[setup]` row. Where it can't be separated, flag the whole row's
   note with what setup it absorbed.
4. Record **human interaction hours** — actual human *attention*, not elapsed time.

   **These are different by an order of magnitude, and conflating them would wreck the
   budget.** Measured in pilots 3/3b: agent dispatches ran for tens of minutes of wall-clock
   each, but the human's involvement was a few minutes per decision gate — the rest of that
   elapsed time was spent on other tasks entirely. **Waiting is not attention.** The 35–55
   hour ceiling is denominated in attention; latency does not consume it.

   **Attribute attention to human touchpoints, NOT to agent rows.** Attention does not
   decompose per agent — the human spends the same few minutes at a decision gate whether one
   agent or five sat behind it. Recording 0.1h against each of twelve agent rows inflates the
   figure as agent count grows, with no extra human work. Count instead:

   - **decision gates** (a question answered, a value ruled on) — measured ~0.1h each
   - **hands-on tasks** (hand-carrying an asset past the firewall, editing the allowlist) —
     the expensive ones, and the reason firewall blockers matter to the hours budget
   - **review tasks** (the picture-book eyeball test, verifying sourced claims) — the
     longest-running human work in the pipeline, and the least compressible

   Record these in the session's main-loop row and leave agent rows blank, or note the gate
   count. A per-agent hours column is a category error.

## Measurement checklist (run at END of every pilot session)

1. Run `python3 docs/phase0/token-report.py` to list sessions and find this session's
   ID, then `python3 docs/phase0/token-report.py <session-id>` for the per-agent table.
2. Note human wall-clock hours for the session (decimal).
3. Append ONE row to `costs.md` PER AGENT plus one for the main loop, in its column
   order: date | session | agent/pipeline | work unit | input | output | cache-read |
   cache-write | billable | human hours | note.
4. If anything blocked, degraded, or surprised (MCP hiccup, context pressure, rate
   limit, editor-review friction): one clause in the note column. These notes are the
   raw material for the GDD's API Constraints section.

## What feeds synthesis

- Per-unit *billable* totals (non-`[setup]` rows) → the extrapolation template's
  "Measured tokens/unit" column. Apply an orchestration term, THEN × 2.5 iteration,
  + 50% contingency.
- **The orchestration term is NOT a fixed multiplier.** Measured main-loop : agent ratios
  across the three pilots were 0.93 : 1, 1.20 : 1, and 0.60 : 1. Orchestration behaves like
  a fixed cost *per dispatch*, so single-agent units carry the most overhead and many-agent
  units the least. Scale it by dispatch count, not by agent tokens. The earlier "~1.0×
  always" guidance came from pilots 1–2 and would overstate a full content-pipeline run by
  roughly 2× — see the revised finding in `costs.md`.
- **Copy costs must be recorded as draft + verify, not draft.** Verifying one fact card
  against sources measured 2.7× the whole drafting pass. Sizing on drafting alone
  understates copy by ~3.7×, and verification does not amortize across species.
- **Note which steps were blocked or degraded when the number was taken.** A step that ran
  without its sources, its assets, or its verification produces a real token figure for
  unreal work. Pilot 3's first content-writer figure measured the cost of *unverified*
  copy, which is not the thing the budget needs to know.
- Cache-read is tracked but priced separately; never fold it into the billable figure.
- `[setup]` rows → reported once as fixed cost, excluded from multipliers.
- Note-column incidents → API Constraints section.
- Human hours → the phases 1–8 re-estimate in hours.
