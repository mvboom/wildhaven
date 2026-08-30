# Systems Pipeline

> Operational companion to [gdd.md](gdd.md) → **Scope: the floor and the depth** (owns
> *what* the fifteen Tier-1 rows are and what each one's thin form is) and to
> [tier1-status.md](tier1-status.md) (owns the per-row record of how far each has gotten —
> this doc is the *procedure*, not the *record*, so running it means updating a row there,
> not here). The content counterpart is gdd.md → **Content Pipelines** plus
> [asset-import-pipeline.md](asset-import-pipeline.md).
>
> Content gets eight steps because it has an asset gate, a license gate, a research gate,
> and a factual-verification gate. **Systems have none of those.** A system has a spec, a
> set of numbers, an implementation, a test, and a taste call — so this pipeline is five
> steps, deliberately. Any step that does not remove a human interrupt is ceremony, and
> ceremony is paid in human-attention hours, which is the binding constraint.

## The five steps

### 1. Scope the thin form

*Owner: the human, in the dispatch brief.*

Assemble, in 3–8 lines: the row's **thin form** verbatim from gdd.md's fifteen-row table,
every **pillar invariant** attached to it, and the **acceptance condition** — what
observable thing proves the row is done.

The invariants are the reason this step exists. They are scattered across gdd.md's Design
Pillars, its "Pillar invariants don't tier" rule, Systems in Play, and spec.md's *not a
depth axis* list. Assembling them once, up front, prevents the rebuild that happens when
an invariant surfaces at step 5 — after the code is written.

Output lands in `tier1-status.md` as the row's `thin_form` and `invariants` fields.
`invariants` is never blank: it says "none" explicitly or it lists them.

### 2. Declare constants → human decision

*Owner: the building agent proposes. **The human decides.***

Enumerate **every tuning number the row touches** before implementing any of them. For
each: its name, the value proposed, and where that value comes from — a
[spec.md](spec.md) Pacing Constants row, an Open Question `#NN`, or a stated GDD band.

Each becomes a named constant in code, seeded at the GDD baseline and marked as a
placeholder. In the tracker they are written `PROPOSED (YYYY-MM-DD) —`; **the human records
the decision by deleting the marker.**

This is the systems analogue of Content Pipeline step 3, and it is the load-bearing step.
It converts N mid-implementation "what number should this be?" interrupts into **one
batched gate**. That is a net *saving* of human hours, which is the only argument this
budget accepts for adding process.

**A row blocked here stops here.** Do not proceed on a guessed number.

### 3. Implement thin

*Owner: the row's `owner_agent` — gameplay-engineer or ui-engineer.*

One owner per row. Build the thin form and nothing past it: deepening is a later purchase,
not a thing to slip in while you're in the file.

**Declare `implementation_location` before you start building.** That declaration is what
makes gdd.md → Technical Strategy #6 checkable — parallel dispatch into one Godot project
is unsafe unless directories are disjoint, and a directory claimed up front can be checked
against every other row's claim. Declared after the fact, it proves nothing.

### 4. Verify headless

*Owner: qa-engineer.*

```
bash scripts/run-tests.sh
```

**The whole suite, not just this row's test.** gdd.md's build-depth rule requires the
complete-loop test to pass continuously, so a row that passes its own test while breaking
another has not passed step 4.

Add the row's own suite under `project/tests/`, asserting the thin form and every pillar
invariant that can be expressed mechanically. Some can't — "the camera feels good" is step
5's problem, not a test — but several can: capacity returning 0 for an unsuitable site, a
displacement warning firing before any resident leaves, the Hints toggle actually
suppressing hints. Record the result in `validation_status`.

### 5. Human gate

*Owner: the human.*

The taste, eyeball, and playability call — run it and decide whether the row passes its
slice of the complete-loop test. Also the moment the step-2 constants get their real
values if they were left provisional.

For rows 13–15 this is two minutes in the editor. For rows 2 and 6 **this is the work** —
which is what gdd.md already says under *where the hours actually go*: phases 3–6 are the
human-judgment spine, bottlenecked on playtesting and taste, where AI helps least.

Recorded as `human_gate`. Only after it is recorded may a row show ✅.

## Deepening is not a sixth step

Deepening a row from thin to full **re-runs steps 2–5** against the fuller form, and is
tracked by the `depth` field, not by a new stage. Do not invent a deepening ceremony.

Order comes from the week 2–3 velocity review, and Tier-1 deepening outranks every Tier-2
item. Nothing deepens until all fifteen rows are thin.

## Rows that skip steps

Not every row needs every step, and pretending otherwise is the cheapest way to make this
document ignored:

- **Row 15 (Settings & Credits)** has no meaningful step 2 — there are no tuning constants,
  only a volume slider and a toggle. It does carry a license obligation, so its step 4 is
  the attribution checks and its step 5 is a compliance confirmation, not a taste call.
- **Row 14 (audio slice)** likewise: one bed, one SFX, no constants worth gating.
- **Rows 13–15** have step 5s measured in minutes. Say so in the brief so nobody schedules
  a playtest for a chime.

## Report format

Same shape as the other pipelines:

- **Changed files**
- **Test results** — `run-tests.sh` summary; output excerpts for any failure
- **Tracker rows updated** — which row in [tier1-status.md](tier1-status.md), which fields
- **Proposals for the human** — every constant awaiting a ruling, one line each
