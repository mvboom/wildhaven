# Style Guide Pipeline

> Operational companion to [gdd.md](gdd.md) → **Content Pipelines** (owns the full
> 8-step, multi-agent flow: audit → import → design proposal → data entry → copy →
> attribution → validation → human sign-off). This doc is step 5 (Copy)'s
> **Gentle-Displacement-scoped subset** — expanded into a runnable, self-correcting
> procedure the same role [fact-card-pipeline.md](fact-card-pipeline.md) plays for
> fact-card copy.

## What this replaces, and what it doesn't

Gentle Displacement copy (`project/scripts/ui/displacement_copy.gd`'s `WARN_`/`DEPART_`/
`MOVE_` constants) was hand-drafted for the floor species (Human, Fox, Rabbit) by
Content Writer — see `docs/content/displacement-copy.md`, which first worked this
content type's rules out in full. The other nine roster species (the cleared pool: Deer,
Stag, Horse, Donkey, Cow, Bull, Alpaca, Husky, Shiba Inu) had no copy of their own and
fell through to `WARN_GENERIC`/`DEPART_GENERIC`/`MOVE_GENERIC`. **For a cleared-pool
species' displacement copy specifically, run the pipeline instead of hand-drafting.**

**Scope, explicitly:** Gentle Displacement copy only (warning/departure/relocation
lines). Fact cards stay `fact_card_pipeline.py`'s remit (D-48). News Report pools and
first-time-nudge copy are **not** covered — those stay Content Writer's hand-drafted
remit, same posture D-48 already established for the fact-card pipeline.

## The tool

`scripts/style_guide_pipeline.py` — a Generator / Evaluator (scored) / Refiner loop.
Unlike the fact-card pipeline's binary accept/reject Evaluator, this one scores 1–10 and
gives a REASON; the Refiner rewrites using that REASON specifically. Full mechanism,
model selection, and backend setup are documented in the script's own module docstring;
this doc covers when and how to invoke it as part of the content pipeline.

```bash
python3 scripts/style_guide_pipeline.py "<species_id>" [--line-type warn|depart|move|all]
python3 scripts/style_guide_pipeline.py --selftest   # Evaluator only, no LLM calls, no API needed
```

## The procedure

### 1. Specify

Pick a species already past roster.md step 3 (design proposal) that is in the cleared
pool (`CLEARED_POOL_IDS` in the script — currently the nine species above). Floor
species (Human, Fox, Rabbit) already ship human-verified lines and the pipeline refuses
to target them. Decide `--line-type`: which of warn/depart/move to (re)generate, or
`all` (the default).

### 2. Run

```bash
python3 scripts/style_guide_pipeline.py "<species_id>"
```

Drafts against the style guide (tone/voice, vocabulary/framing — the villager doctrine,
formatting/structure — the Read-Aloud constraint), scores 1–10 with an LLM judge on a
*different* model than the Generator, refines on a REASON-specific rewrite, and
escalates (keeps the highest-scoring draft) instead of looping forever if 10/10 is never
reached.

### 3. Dual write (automatic, not a separate step)

A run writes to both places in one pass:
- `scripts/style_guide_pipeline_output/<species_id>.json` — the full attempt log (every
  draft, every score, every reason) — the evidence trail.
- `project/scripts/ui/displacement_copy.gd` — the species' `WARN_`/`DEPART_`/`MOVE_`
  const(s), inline-flagged pipeline-generated and **awaiting content-writer sign-off**,
  wired into the file's `_WARN_STRUCTURE`/`_WARN_HOME`/`_DEPART`/`_MOVE` lookup tables.
  Idempotent: re-running for the same species replaces its own prior entry rather than
  duplicating it.

### 4. Human sign-off (step 8 — not automated, never will be)

The pipeline's own Evaluator checks structure and framing; it does not carry the
judgment a content-writer sign-off does. A line landing in `displacement_copy.gd` is a
proposal, exactly like every other agent-authored content in this project.

### 5. Self-check

Before treating a run as done:

- [ ] `bash scripts/run-tests.sh` still green (the pipeline edits a real `.gd` file;
      confirm nothing it wrote broke a pinned test).
- [ ] `scripts/style_guide_pipeline_output/<species_id>.json` exists and its accepted/
      escalated line matches what's now in `displacement_copy.gd`.
- [ ] No stray `{`/`}` characters or other unresolved template syntax in a newly written
      line — the Evaluator checks this (added after a real catch, see Origin), but a
      human read is still worth it before sign-off.

## Known gaps, found and fixed mid-build

- The Evaluator's deterministic sweep did not originally check for unresolved
  `{display_name}`-style template syntax — a real production run's Refiner echoed that
  exact placeholder back as literal text in an accepted, 9/10-scored line. Fixed by
  adding a stray-`{`/`}` check plus a `selftest()` regression case reproducing the exact
  string.
- `write_output_json()` originally overwrote a species' entire attempt log on every run
  — re-running one `--line-type` alone (to fix the gap above) clobbered that species'
  already-logged evidence for its other line types. Fixed to merge `line_results` with
  any prior log for that species instead of replacing it.

Full account of both: `archive/mark-vanderboom-assignment-7/README.md`.

## Origin

Built for `archive/mark-vanderboom-assignment-7/` (see that folder's README and
style-guide.md for the assignment write-up, including the real defect the first
production run caught), then adopted as the project's production mechanism for this
content type rather than shelved — → [decisions.md](../decisions.md) D-49.
