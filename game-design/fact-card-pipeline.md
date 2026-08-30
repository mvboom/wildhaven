# Fact-Card Pipeline

> Operational companion to [gdd.md](gdd.md) → **Content Pipelines** (owns the full
> 8-step, multi-agent flow: audit → import → design proposal → data entry → copy →
> attribution → validation → human sign-off) and to
> [content-pipeline-status.md](content-pipeline-status.md) (owns the per-item record of
> which step each species has reached — this doc is the *procedure*, not the *record*,
> so running it means updating a row there, not here). This doc is step 5 (Copy)'s
> **fact-card-scoped subset** — expanded into a runnable, self-correcting procedure so a
> human or a fresh agent session can generate a species' fact-card copy consistently,
> the same role [asset-import-pipeline.md](asset-import-pipeline.md) plays for steps
> 1/2/6/7 on the tech-art side.
>
> Design proposal, data entry, attribution, and human sign-off are **not** covered here
> — those belong to Gameplay Engineer, Content Writer's own judgment on non-fact-card
> copy, and the human respectively.

## What this replaces, and what it doesn't

Fact-card copy (`AnimalDefinition.fact_text_pool`) was previously hand-drafted by
Content Writer against the five-step checklist in [spec.md](spec.md) → Fact-Card
Content Checklist, one species at a time, with review happening after a draft shipped
(see `archive/mark-vanderboom-assignment-4/critic-catch.md` for what that one-shot-plus-
critic pattern looks like). **For fact-card copy specifically, run the pipeline instead
of hand-drafting.**

**Scope, explicitly:** fact cards only. News Report pools and first-time-nudge copy are
**not** covered — those stay Content Writer's hand-drafted remit (→ D-48). The pipeline
hasn't been validated against News Report's four-sub-pool structure or nudge copy's own
constraints, and generalizing it without that validation was deliberately out of scope
when it was adopted.

## The tool

`scripts/fact_card_pipeline.py` — a Generator / Evaluator / Refiner / Circuit Breaker
loop. Full mechanism, model selection, and backend setup are documented in the script's
own module docstring; this doc covers when and how to invoke it as part of the content
pipeline, not the mechanism itself.

```bash
python3 scripts/fact_card_pipeline.py "<Species Display Name>" --count N
python3 scripts/fact_card_pipeline.py --selftest   # Evaluator only, no LLM calls, no API needed
```

## The procedure

### 1. Specify

Pick a species already past step 3 (design proposal) — the pipeline needs a
`roster.md`-decided species with a known `id`/`display_name`/`avoids` (it reads these
from its own `ROSTER` table; a species not yet in that table needs an entry added
there first, mirroring how a new species enters `content-pipeline-status.md`'s scan
table). Decide `--count`: how many independent cards this run should try to land.

### 2. Run

```bash
python3 scripts/fact_card_pipeline.py "<Species>" --count N
```

Reads live from the approved source set (ADW, Nat Geo Kids, Wildlife Trusts, Nat Geo
Society Education, Wikipedia), drafts, evaluates against the GDD's two-register rule +
operational predation ban + closed predation-graph check (deterministic sweep, then an
LLM judge on a *different* model), refines on failure, and escalates instead of shipping
a card that never clears the loop.

### 3. Dual write (automatic, not a separate step)

A passing run writes to all three places in one pass:
- `scripts/fact_card_pipeline_output/<id>.json` — the full attempt log (every draft,
  every Evaluator verdict) — the evidence trail.
- `project/data/animals/<id>.tres` — accepted card(s) replace `fact_text_pool`,
  header-noted as pipeline-generated and awaiting step-8 sign-off.
- [content-pipeline-status.md](content-pipeline-status.md) — that species' own
  `copy_content_location` row, pointing at the attempt log.

If the Circuit Breaker fires (no candidate clears the loop), the `.tres` is left
untouched and the tracker row records the escalation instead of a card count — nothing
ships silently half-good.

### 4. Human sign-off (step 8 — not automated, never will be)

The pipeline's own Evaluator checks structure (banned vocabulary, the closed predation
graph, register, length, oblique framing, semantic duplication) — it does **not**
independently re-fetch and confirm each claim against its cited source the way a human
step-8 review does. A card landing in `fact_text_pool` is a proposal, exactly like every
other agent-authored content in this project; `content-pipeline-status.md`'s
`human_signoff` field is not touched by the pipeline and stays the human's call.

### 5. Self-check

Before treating a run as done:

- [ ] `bash scripts/run-tests.sh` still green (the pipeline edits real `.tres` files;
      confirm nothing it wrote broke a pinned schema test).
- [ ] `scripts/fact_card_pipeline_output/<id>.json` exists and its accepted count
      matches what's now in the `.tres`.
- [ ] `content-pipeline-status.md`'s row for the species points at that log and reads
      "awaiting step-8 human sign-off" (or the escalation form, if the breaker fired).
- [ ] If the breaker fired: the escalation reason in the log is a real content gap (no
      usable source, an un-resolvable framing issue), not a bug in the pipeline itself —
      report the distinction rather than assuming either.

## Origin

Built for `archive/mark-vanderboom-assignment-6/` (see that folder's README and
`pre-build-declaration.md` for the assignment write-up, including three concrete
catches from its first real runs), then adopted as the project's production mechanism
for this content type rather than shelved — → [decisions.md](../decisions.md) D-48.
