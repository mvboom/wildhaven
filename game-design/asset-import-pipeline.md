# Asset Import Pipeline

> Operational companion to [art.md](art.md) (owns **what** to source and **why** — roster
> scoping, sourcing policy, licensing decisions), to
> [content-pipeline-status.md](content-pipeline-status.md) (owns the per-item record of
> which step each asset has reached — this doc is the *procedure*, not the *record*, so
> running it means updating a row there, not here), and to [gdd.md](gdd.md) → **Content
> Pipelines** (owns the full 8-step, multi-agent flow: audit → import → design proposal →
> data entry → copy → attribution → validation → human sign-off). This doc is the
> **tech-art-scoped subset** of that flow — steps 1 (audit), 2 (import & look pass), 6
> (attribution), and the import-level slice of 7 (validation) — expanded into a runnable
> procedure so a human or a fresh agent session can specify an asset, import it, validate it,
> attribute it, and audit past work consistently every time.
>
> Data entry (the `AnimalDefinition`/`PlaceableDefinition` `.tres`), fact-card copy, and human
> sign-off are **not** covered here — those belong to Gameplay Engineer, Content Writer, and
> the human respectively.

> **Automation:** `scripts/asset_pipeline.py` executes this procedure end to end
> (design: `docs/superpowers/specs/2026-08-30-asset-pipeline-design.md`; front-end:
> `/add-asset`). This document remains authoritative for the conventions it states —
> paths, naming, wrapper authoring, attribution shapes — and the pipeline implements
> them. Where the two disagree, this document is right and the pipeline has a bug.

## Directory & naming conventions

Codified from the working Fox/Rabbit imports already in the repo:

```
project/assets/<category>/<name>/<Name>.<gltf|glb>   ← raw imported asset, untouched
project/assets/<category>/<name>/<Name>.tscn          ← hand-authored wrapper scene
```

- **Categories:** `animals`, `buildings`, `terrain`, `props`, `audio`.
- **`<name>`** is lowercase (`fox`, `rabbit`); **`<Name>`** matches the in-game display name
  used for the file (`Fox.gltf`, `Fox.tscn`).
- **The wrapper scene is always hand-authored as text, never built via the Godot MCP
  `create_scene`/`add_node` tools.** gdd.md's Technical Strategy #3 documents why: those tools
  write non-standard properties that silently corrupt the scene. Write the `.tscn` directly.
- **Animated models:** the wrapper's `AnimationPlayer` sets `autoplay = "Idle"` — the spawn
  smoke test and the look-pass both depend on an idle clip playing without code triggering it.

## The six-step procedure

### 1. Specify

State, in one line: the source file(s) under `source-content/assets/`, the target category, and the
destination `<name>`. No formal schema — this is a task description, not a data record.

### 2. Audit (hard gate)

Before any import work:

- **License.** Must already be cleared per art.md's locked policy: Quaternius CC0 primary,
  Synty **SIMPLE** as the animals-only paid fallback, **never Synty POLYGON**. Record the
  license id (`CC0-1.0`, `Synty Store EULA`, etc.).
- **Animations.** For any character/animal, confirm idle/walk/reaction clips exist on the
  *source* model page or file — before importing, not after. A model that's animated in name
  only (armature with no real cycle) fails here.
- **Style.** Silhouette and proportions read as picture-book (art.md's Visual Style rules) —
  no mesh work is available to fix a bad silhouette after the fact, so a marginal asset gets
  rejected here, not patched later.

**No cleared source → stop and report.** Do not import. Floor species substitute per gdd.md's
floor rule; non-floor content just doesn't ship yet.

### 3. Import

Place the raw file and the wrapper scene at the conventional path (above). The wrapper is the
only thing game code ever references (`AnimalDefinition.model_scenes`, a building's placeable
scene, etc.) — never point gameplay code at the raw glTF/FBX directly.

### 4. Validate

```
$GODOT_PATH --headless --path project --import
```

`--import` must run first — it registers `class_name`s and rebuilds the import cache; a bare
`--headless ... --quit` is a parse check only and will not catch a broken asset import.

Then author (or re-run, if one already exists) `project/tests/test_<name>_import.gd`,
following the existing `test_fox_animations.gd` / `test_rabbit_animations.gd` template:

```gdscript
extends QATestCase
## Required-animations check on the <Name> model.

const MODEL_PATH: String = "res://assets/<category>/<name>/<Name>.tscn"
const REQUIRED_CLIPS: PackedStringArray = ["Idle", "Walk"]
const EXPECTED_CLIP_COUNT: int = 0  # fill in from the audit step

func _init() -> void:
    begin("<Name> animations")

    var packed: PackedScene = load(MODEL_PATH) as PackedScene
    if not check(packed != null, "%s loads as PackedScene" % MODEL_PATH):
        finish(); return

    var inst: Node = packed.instantiate()
    if not check(inst != null, "%s.tscn instantiates" % "<Name>"):
        finish(); return

    var player: AnimationPlayer = _find_animation_player(inst)
    if not check(player != null, "model contains an AnimationPlayer"):
        inst.free(); finish(); return

    var clips: PackedStringArray = player.get_animation_list()
    for required: String in REQUIRED_CLIPS:
        check(player.has_animation(required), "required clip \"%s\" is present" % required)
    check_eq(clips.size(), EXPECTED_CLIP_COUNT, "clip count")
    check_eq(player.autoplay, "Idle", "AnimationPlayer autoplay is \"Idle\"")

    inst.free()
    finish()

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child: Node in node.get_children():
        var found: AnimationPlayer = _find_animation_player(child)
        if found != null:
            return found
    return null
```

Run it:

```
$GODOT_PATH --headless --path project --script res://tests/test_<name>_import.gd
```

Non-animated content (static props, terrain, buildings) skips the `AnimationPlayer` checks —
assert the scene loads and instantiates, at minimum.

### 5. Attribute

- **Same source pack as an existing entry** (e.g. another Quaternius CC0 pack already
  recorded): extend that `AttributionEntry`'s `assets_used` in
  `project/attribution/sources/*.tres`.
- **New source:** author a new `AttributionEntry` `.tres`. Pick the shape per
  `attribution_entry.gd`'s doc comment — **uniform license** (whole pack, one license: fill
  `license_name`/`license_url`/`attribution_required`, list files in `assets_used`) vs.
  **per-file license** (site licenses each file separately, e.g. freesound.org: set
  `per_file_licensing = true`, add one `AttributionAsset` per file to `assets`).
- Copy the license text into `project/assets/licenses/` — a link can rot; a compliance review
  must be answerable offline.
- Regenerate `CREDITS.md`:

  ```
  godot --headless --path project --script res://attribution/generate_credits.gd
  ```

  This fails closed (exit 1) if any entry claims `attribution_required` without a
  `required_notice`, or has any other malformed field — treat that failure as a real defect,
  not a script bug.
- Re-run `test_attribution.gd` to confirm the obligation (if any) survived into the rendered
  file and the artifact isn't stale.

### 6. Self-check

Before filing the report, confirm:

- [ ] Raw asset + wrapper scene at the conventional path.
- [ ] `test_<name>_import.gd` passes headless.
- [ ] Attribution entry exists (new or extended) and `CREDITS.md` was regenerated.
- [ ] `test_attribution.gd` still passes.
- [ ] The item's row in [content-pipeline-status.md](content-pipeline-status.md)
      updated (`source`, `pre_import_audit`, `project_location`, `attribution_status`,
      `status`) — art.md is sourcing narrative only and does not get a status edit.
- [ ] Report filed per the format below.

## Standalone Audit Mode

A separate checklist for re-auditing **already-imported** assets on demand — not tied to a
new import, and not a rerun of the whole procedure above. Use this when asked to audit the
pipeline's past work, or periodically to catch drift.

For each previously-imported asset:

1. Re-run its `test_<name>_import.gd`. A failure here means something changed underneath it
   (re-import, moved file, edited scene) without the pipeline being re-run.
2. Confirm its attribution entry and license file still exist on disk and the entry's
   `assets_used`/`assets` still names it.
3. Cross-check the item's row in [content-pipeline-status.md](content-pipeline-status.md)
   against reality: a row marked ✅ with no matching test file or no attribution entry is
   a defect, not a documentation nit.

**Report drift as findings — do not silently patch it.** An audit's job is to surface gaps for
human decision, same as the audit step in a fresh import.

## Report format

Extends tech-art.md's standard report with a test-results line:

- **Changed files**
- **Test results** — pass/fail per validation step, with output excerpts for failures
- **Attribution entries added**
- **Pipeline-status rows updated** — which item(s) in
  [content-pipeline-status.md](content-pipeline-status.md), which fields
- **Proposals for the human**
