---
name: add-asset
description: Drives scripts/asset_pipeline.py end to end for one asset — runs it, presents the review checkpoint's decisions as a table, takes your rulings in plain language, and resumes or abandons. Use when adding a specific asset from source-content/assets/ to the game.
---

This skill is a front-end to a program. It runs `scripts/asset_pipeline.py` and presents
its checkpoint; it never decides a tuning value, never edits a `.tres` by hand, and never
runs git itself — the pipeline owns all three.

## Procedure

### 1. Run

```
python3 scripts/asset_pipeline.py "<path>" --as {animal|building|terrain}
```

`--as` is required. Do not infer it from the path: the same model can legitimately be an
animal or a static prop, and guessing wrong wastes an import. Two optional flags exist and
are rarely needed: `--notes "<hint>"` passes a design hint into the value proposals, and
`--variant-of <terrain_id>` (terrain only) appends the model as a style variant of an
existing terrain type instead of writing a new one. Never pass `--dry-run` unless the
operator explicitly asked for a dry run — a real run is what ships content.

If preflight fails, report its lines verbatim and stop. It prints one `PREFLIGHT: ...`
line per problem; the two common causes are uncommitted tracked changes under `project/`
or `scripts/`, and a stale worktree left over from a prior run — both the operator's to
clear. Do not clear them yourself: do not commit, stash, or discard anything on their
behalf.

A run that gets past preflight but fails an earlier stage (bad format, missing required
animation clip, already-imported duplicate) prints its own reason and abandons the
worktree automatically — there is nothing to resume. Report that reason and stop; it is
not a bug to work around.

### 2. Present the checkpoint

A successful run prints a `=== CHECKPOINT ===` block naming the run id and
`runs/<run_id>/review.json`. Read that file. Show ONE table: field, proposal, source,
confidence — one row per entry in `decisions`. Then, separately, the deferred silhouette
check (`deferred[0]`) with its evidence — chosen format and why, clip list, and mesh/node/
skin counts — that one is a judgment call, so show the evidence and ask, never a
recommendation dressed as a finding.

Say plainly how many fields are unruled (`decisions` entries with `"value": null`) and
that none of them can ship unruled.

Report the cost line as the pipeline printed it. If it reads "(dollar cost not reported by
this backend)", say exactly that — never substitute `$0.00`, which would present a real,
unknown spend as free.

### 3. Take rulings

Accept plain language ("cost should be 25, rest is fine"). Write the values into
`review.json` through the pipeline's own contract (`assetpipe.review.apply_rulings`), not
by hand-editing JSON — that function is what enforces "every decision needs a non-null
`value`" and preserves the rest of the payload untouched:

```
python3 - <<'PY'
import sys
sys.path.insert(0, "scripts")
from pathlib import Path
from assetpipe import review

path = Path("runs/<run_id>/review.json")
payload = review.read(path)
payload = review.apply_rulings(payload, {"cost": 25, "blocks_movement": False})
review.write(path, payload)
PY
```

A ruling of `0` or `false` is a real ruling — write it as given, never treat it as "no
answer" and re-ask. **Never rule a field yourself, and never carry a proposal through as a
value because it looked reasonable.** If the operator rules only some fields, say which
remain and stop; do not call `--resume`.

### 4. Resume or abandon

```
python3 scripts/asset_pipeline.py --resume <run_id>
python3 scripts/asset_pipeline.py --abandon <run_id>
```

`--resume` refuses (exit 1, unchanged review.json) if any field is still unruled — go back
to step 3. Once every field is ruled, resume runs data entry, copy, credits and tests,
then merges and builds.

**Exit code 2 means the merge was refused because the base branch is `main`** — that is
not a failure. The pipeline prints the ready branch name and leaves the worktree intact;
report that branch and tell the operator to merge it themselves. Do not merge it for them.

Any other non-zero exit (validation failure, missing attribution entry, failing tests, a
failed build) is a real failure: report the printed reason and stop. Do not retry blindly
or carry the run forward some other way.

## Boundary

- Run no git commands. The pipeline runs its own, locally.
- Never decide a tuning value; never sign a human gate.
- Never hand-edit a file the pipeline owns (`.tres`, wrapper `.tscn`, `CREDITS.md`,
  `review.json` outside of `apply_rulings`).
- If a stage fails, report it and stop. Do not carry a broken import forward.
