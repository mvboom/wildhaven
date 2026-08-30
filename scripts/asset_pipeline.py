"""Wildhaven Asset Pipeline -- raw asset in, built game out.

Takes a path under source-content/assets/ and carries it through assess, import,
content generation, wiring, attribution, validation and build, halting exactly once at
a review checkpoint where a human rules every tuning value.

Design: docs/superpowers/specs/2026-08-30-asset-pipeline-design.md

Run:
  python3 scripts/asset_pipeline.py "<path>" --as animal
  python3 scripts/asset_pipeline.py --selftest      # no LLM calls, no git, no writes
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from assetpipe.harness import Checks
from assetpipe import blender, attribution, audit, dedupe, formats, importer, llm, review, runlog, worktree, godot
from assetpipe.adapters import animal, building, terrain

ADAPTERS = ("animal", "building", "terrain")
ADAPTER_MODULES = {"animal": animal, "building": building, "terrain": terrain}


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.casefold()).strip("_")


def _selftest_cli(c) -> None:
    c.eq(slug("Shiba Inu"), "shiba_inu", "display name to id")
    c.eq(slug("Common Tree 1"), "common_tree_1", "digits preserved")
    c.eq(slug("Pig"), "pig", "single word")
    c.eq(sorted(ADAPTER_MODULES), ["animal", "building", "terrain"],
         "three adapters registered")
    for name, module in ADAPTER_MODULES.items():
        c.eq(module.SPEC.name, name, f"{name} module's SPEC matches its key")
        c.check(hasattr(module, "decisions"), f"{name} exposes decisions()")

    import inspect
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        log_path = Path(td) / "build.log"
        log_path.write_text("exporting...\ndone\n")
        c.check(build_log_clean(log_path), "a clean build log passes")
        log_path.write_text("exporting...\nERROR: Cannot open file\ndone\n")
        c.check(not build_log_clean(log_path),
                "an ERROR: line fails the build even though the script exits 0")

        # Spec's required selftest: the GER pipelines must run from the WORKTREE's
        # own copy. They resolve their repo root from __file__, so invoking the main
        # checkout's copy would patch the main checkout while we believe we are
        # sandboxed. Assert the invocation is cwd-anchored to the worktree.
        src = Path("scripts/asset_pipeline.py").read_text()
        c.check('"scripts/fact_card_pipeline.py"' in src and "cwd=tree" in src,
                "fact_card_pipeline is invoked with cwd=tree, not the main checkout")
        c.check("REPO_ROOT / \"scripts\"" not in src,
                "no absolute main-checkout path is built for the GER pipelines")

        # Both GER copy pipelines are wired per the design's adapter table (line 181):
        # fact_card_pipeline -> fact_text_pool, style_guide_pipeline -> WARN_/DEPART_/
        # MOVE_. Missing the second one ships a new animal with no Gentle Displacement
        # lines, falling through to WARN_GENERIC.
        c.check('"scripts/style_guide_pipeline.py"' in src,
                "style_guide_pipeline is invoked for the Gentle Displacement copy")
        c.check('payload["adapter"] == "animal"' in src,
                "style_guide_pipeline is guarded to animals only -- buildings and "
                "terrain have no WARN_/DEPART_/MOVE_ lines")

        payload = {"decisions": [{"field": "cost", "proposal": 40, "value": None,
                                  "source": "s", "confidence": "med"}]}
        c.check(not review.ready(payload), "resume refuses an unruled review")
        payload["decisions"][0]["value"] = 25
        c.check(review.ready(payload), "resume proceeds once every field is ruled")

        # REGRESSION, whole-branch review IMPORTANT 8: buildings' copy row targets the
        # buildings directory, and terrain has no copy row at all.
        c.check('cmd += ["--target", "building_text"]' in src,
                "the fact-card pipeline is given --target building_text for buildings")
        c.check('if adapter_name == "terrain":' in src,
                "terrain skips the fact-card pipeline -- its spec copy row is 'none'")

        # REGRESSION, whole-branch review IMPORTANT 7: both copy pipelines ran with
        # check=False and printed a success line regardless of outcome.
        copy_src = inspect.getsource(_copy_stage)
        c.eq(copy_src.count("check=False).returncode"), 2,
             "both copy pipelines' return codes are captured, not discarded")
        c.eq(copy_src.count("FAILED rc={rc}"), 2,
             "a non-zero copy stage reports the code instead of printing success")
        c.check("if rc == 0:" in copy_src,
                "the success line is printed only on a zero return code")
        c.check("ROSTER" in copy_src,
                "the failure message names the hardcoded ROSTER the operator must edit")

        # REGRESSION, whole-branch review IMPORTANT 5: the ruled model_scale never reached
        # the wrapper, which is the only place scale lives.
        stages_src = inspect.getsource(_resume_stages)
        c.check("importer.rescale_wrapper(wrapper, scale)" in stages_src,
                "resume rewrites the wrapper with the ruled scale, not the 0.2 run() wrote")
        c.check('values.get("model_scale")' in stages_src,
                "the scale rewritten is the one from the review, not a constant")
        code_only = [line for line in stages_src.splitlines()
                     if not line.lstrip().startswith("#")]
        c.check(not any("0.2" in line for line in code_only),
                "resume hardcodes no scale of its own")

        # REGRESSION, whole-branch review IMPORTANT 17: copy_license_text was implemented,
        # hardened, tested and never called.
        c.check("attribution.copy_license_text" in inspect.getsource(_preserve_license),
                "stage 9 preserves the pack's licence text offline")
        c.check("_preserve_license(pack, project, tree)" in stages_src,
                "stage 9 actually invokes it")

    # REGRESSION, whole-branch review IMPORTANT 4/14: resume()'s validation dispatch
    # reached only animal.py, so an unknown hotbar_category was written straight through.
    c.check(_validate(building, "building", "well", None, {"hotbar_category": "workshop"}),
            "an unknown hotbar_category is caught by the path resume() uses")
    c.eq(_validate(building, "building", "well", None,
                   {"hotbar_category": "farm_building"}), [],
         "a known hotbar_category passes that path")
    c.check(_validate(terrain, "terrain", "wild_grass", terrain.MODE_NEW_TYPE,
                      {"emitted_tags": ["forest"]}),
            "terrain new_type gets the inert-land check through resume()'s path")
    c.eq(_validate(terrain, "terrain", "wild_grass", terrain.MODE_VARIANT,
                   {"model_scale": 1.0}), [],
         "variant mode writes no terrain id, so the inert-land check does not apply")
    c.eq(_validate(animal, "animal", "pig", None,
                   {"habitat_needs": ["forest"], "avoids": [], "scout_radius": 10,
                    "capacity_radius": 0, "tiles_per_individual": 5,
                    "max_individuals": 6, "personality": "Shy"}), [],
         "animal's existing validation still runs through the shared path")

    # PROMOTED MINOR: formats.pack_root's unguarded relative_to raised a bare ValueError
    # from inside run()'s try -- after the worktree existed, stranding it.
    with tempfile.TemporaryDirectory() as td:
        outside = Path(td) / "Loose.fbx"
        outside.write_bytes(b"\x00")
        problems = validate_asset_path(outside)
        c.check(any("not under" in p for p in problems),
                "an asset outside the assets root is refused before the worktree exists")
        c.check(any("is not a file" in p
                    for p in validate_asset_path(Path(td) / "nope.fbx")),
                "a nonexistent asset is refused too")
        inside_root = Path(td) / "assets"
        (inside_root / "Pack" / "FBX").mkdir(parents=True)
        good = inside_root / "Pack" / "FBX" / "Pig.fbx"
        good.write_bytes(b"\x00")
        c.eq(validate_asset_path(good, assets_root=inside_root), [],
             "a real asset under the assets root passes")

    c.check("traceback.print_exc()" in inspect.getsource(run),
            "run()'s handler prints the traceback, not just str(exc)")
    c.check("traceback.print_exc()" in inspect.getsource(resume),
            "resume() has a broad handler that prints the traceback")
    c.check("worktree KEPT at" in inspect.getsource(resume),
            "resume()'s handler names the worktree it kept")

    # REGRESSION, whole-branch review IMPORTANT 9: --abandon could not clean up a crashed
    # run, and the stranded worktree then blocked every future run at preflight.
    c.eq(worktree_of("20260830-shiba_inu-ab12", Path("/r")),
         (Path("/r/.worktrees/asset-shiba_inu"), "asset/shiba_inu"),
         "worktree path and branch are recoverable from the run id alone")

    with tempfile.TemporaryDirectory() as td:
        import subprocess as _sp
        repo = Path(td) / "repo"
        (repo / "project").mkdir(parents=True)
        (repo / "project" / "a.tres").write_text("one\n")
        for args in (["init", "-b", "main"], ["add", "."],
                     ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", "init"]):
            _sp.run(["git", *args], cwd=repo, check=True, capture_output=True)
        worktree.create(repo, "asset/pig", repo / ".worktrees" / "asset-pig")

        run_id = "20260830-pig-ab12"
        c.check(not (repo / "runs" / run_id / "review.json").is_file(),
                "the crashed-run fixture has no review.json, as a crash before stage 1 does")
        c.eq(abandon_run(run_id, repo), 0,
             "abandon_run succeeds when review.json is absent")
        c.check(not (repo / ".worktrees" / "asset-pig").exists(),
                "the stranded worktree is actually removed")
        c.eq(preflight_names(repo), [],
             "and preflight is unblocked afterwards")

    c.check('"incomplete": True' in src,
            "run() writes an abandon-able stub before any stage runs")
    c.check('payload.get("incomplete")' in inspect.getsource(resume),
            "resume refuses that stub -- its empty decisions list is not 'nothing to rule'")


def preflight_names(repo: Path) -> list[str]:
    return [p for p in worktree.preflight(repo) if "stale worktree" in p]


def selftest() -> int:
    from assetpipe.adapters import base
    c = Checks()
    attribution.selftest_cases(c)
    formats.selftest_cases(c)
    audit.selftest_cases(c)
    dedupe.selftest_cases(c)
    review.selftest_cases(c)
    runlog.selftest_cases(c)
    worktree.selftest_cases(c)
    importer.selftest_cases(c)
    blender.selftest_cases(c)
    base.selftest_cases(c)
    animal.selftest_cases(c)
    building.selftest_cases(c)
    terrain.selftest_cases(c)
    llm.selftest_cases(c)
    godot.selftest_cases(c)
    _selftest_cli(c)
    return c.report("SELFTEST")


def _format_cost_line(cost: dict) -> str:
    """cost carries in/out/usd/usd_known. The SDK backend reports no dollar figure
    (llm.py: "the Messages API returns no dollar figure and this repo has no pricing
    table") -- printing $0.00 in that case would present a real spend as free. Only
    print a dollar figure when every stage that contributed cost knew its own price."""
    tokens = f"{cost.get('in', 0):,} in / {cost.get('out', 0):,} out tokens"
    if cost.get("usd_known", True):
        return f"${cost.get('usd', 0.0):.4f} ({tokens})"
    return f"{tokens} (dollar cost not reported by this backend)"


def validate_asset_path(asset: Path, assets_root: Path = formats.ASSETS_ROOT) -> list[str]:
    """Checked BEFORE the worktree is created, and that ordering is the point.

    formats.pack_root() calls Path.relative_to() unguarded, so an asset outside
    source-content/assets/ raised a bare ValueError from inside run()'s try -- by which
    time the worktree existed. It was then stranded (--abandon had no review.json to read)
    and blocked every later run at preflight. Failing here costs nothing.
    """
    problems: list[str] = []
    if not asset.is_file():
        problems.append(f"{asset} is not a file")
        return problems
    try:
        formats.pack_root(asset, assets_root)
    except ValueError:
        problems.append(
            f"{asset} is not under {assets_root}/ -- this pipeline only imports assets "
            f"that live in the source-content drop, because the pack folder is where the "
            f"licence and the attribution entry are found")
    return problems


def _validate(module, adapter_name: str, ident: str, mode: str | None,
              values: dict) -> list[str]:
    """Every adapter's pre-write validation, in one place.

    resume() used to call module.validate_values(values) behind a hasattr guard, and only
    animal.py had one -- so buildings wrote an unvalidated hotbar_category and terrain got
    no pass at all. building.py now has validate_values; terrain's check needs the IDENT,
    which a validate_values(values) signature cannot carry, so it is called directly, and
    only in new_type mode -- variant mode writes no .tres and defines no terrain id.
    """
    problems: list[str] = []
    if hasattr(module, "validate_values"):
        problems += module.validate_values(values)
    if adapter_name == "terrain" and mode == terrain.MODE_NEW_TYPE:
        problems += module.check_new_type(ident, values)
    return problems


def run(asset: Path, adapter_name: str, repo: Path, notes: str = "",
        dry_run: bool = False, variant_of: str | None = None) -> int:
    module = ADAPTER_MODULES[adapter_name]
    spec = module.SPEC
    display = asset.stem
    ident = slug(display)
    mode = "variant" if variant_of else ("new_type" if adapter_name == "terrain" else None)

    problems = validate_asset_path(asset) + worktree.preflight(repo)
    if problems:
        for p in problems:
            print(f"PREFLIGHT: {p}")
        return 1

    run_id = runlog.new_run_id(ident)
    log = runlog.RunLog(repo / "runs", run_id)
    base_branch = worktree.current_branch(repo)
    branch = f"asset/{ident}"
    tree = worktree.create(repo, branch, repo / ".worktrees" / f"asset-{ident}")
    print(f"[0/10] worktree..... {tree}  ({worktree.seed_import_cache(repo, tree)})")

    # Written BEFORE any stage runs, so --abandon always has something to read. review.json
    # used to appear only at the checkpoint; a crash in stages 1-6 therefore left
    # abandon_run raising FileNotFoundError, and the stranded worktree then blocked every
    # future run at preflight. `incomplete` is what stops resume() acting on a stub.
    review.write(log.dir / "review.json", {
        "run_id": run_id, "asset": str(asset), "adapter": adapter_name,
        "worktree": str(tree), "branch": branch, "base_branch": base_branch,
        "mode": mode, "variant_of": variant_of, "decisions": [], "incomplete": True,
    })

    project = tree / "project"
    try:
        resolution = formats.resolve(asset, spec.needs_rig)
        print(f"[1/10] format...... {resolution.chosen or 'NONE'} -- {resolution.reason}")

        gate = audit.gate(resolution, spec.required_clips, formats.pack_root(asset),
                          adapter_name=spec.name)
        if not gate.passed:
            for p in gate.problems:
                print(f"[2/10] audit....... FAIL {p}")
            worktree.abandon(repo, tree, branch)
            return 1
        print(f"[2/10] audit....... PASS (licence {gate.evidence['license']}, "
              f"{len(gate.evidence['clips'])} clips)")

        dupe = dedupe.check(asset, project / "assets",
                            tree / "game-design" / "content-pipeline-status.md")
        if dupe.is_dupe:
            print(f"[3/10] dedupe...... HALT already present: {dupe.matches[:3]}")
            worktree.abandon(repo, tree, branch)
            return 1
        print("[3/10] dedupe...... no match")

        written = importer.copy_model(resolution, project, spec.category, ident, display)
        importer.write_wrapper(project, spec.category, ident, display,
                               f"{display}{resolution.chosen_path.suffix}",
                               0.2, gate.evidence["license"], None, spec.schema)
        print(f"[4/10] import...... {len(written)} file(s) -> "
              f"{importer.dest_dir(project, spec.category, ident)}")

        godot.import_project(tree, repo)
        scene_res = f"assets/{spec.category}/{ident}/{display}.tscn"
        idx = godot.anim_index(tree, scene_res, repo) if spec.required_clips else -1
        if idx >= 0:
            importer.write_wrapper(project, spec.category, ident, display,
                                   f"{display}{resolution.chosen_path.suffix}", 0.2,
                                   gate.evidence["license"], idx, spec.schema)
            godot.import_project(tree, repo)
        godot.write_import_test(tree, ident, display, spec.category,
                                resolution.probe.clips, spec.required_clips)
        heuristic = set(resolution.probe.clips)
        print(f"[5/10] verify...... AnimationPlayer index {idx}; "
              f"{len(heuristic)} clips from the pre-gate")

        # cost's usd_known starts True: a dry run or a run whose only stage was free
        # made no unpriced spend, so there is nothing to warn about.
        usd_known = True
        if dry_run:
            decisions = module.decisions(resolution.probe, mode) \
                if spec.name == "terrain" else module.decisions(resolution.probe)
            print("[6/10] values...... --dry-run: proposals skipped, fields unruled")
        else:
            decisions, usage = llm.propose(spec, display, resolution.probe, notes)
            if spec.name == "terrain" and mode == "variant":
                keep = {d.field for d in module.decisions(resolution.probe, mode)}
                decisions = [d for d in decisions if d.field in keep]
            usd_known = usage.get("usd_known", True)
            log.record(6, "values", runlog.stage_key(ident, resolution.chosen),
                       {"fields": [d.field for d in decisions]}, usage)
            print(f"[6/10] values...... {len(decisions)} proposed")

        cost = log.total_cost()
        cost["usd_known"] = usd_known

        payload = {
            "run_id": run_id, "asset": str(asset), "adapter": adapter_name,
            "worktree": str(tree), "branch": branch, "base_branch": base_branch,
            "mode": mode, "variant_of": variant_of, "incomplete": False,
            "resolved_format": {"chosen": resolution.chosen, "reason": resolution.reason,
                                "rejected": resolution.rejected},
            "decisions": [d.to_dict() for d in decisions],
            "deferred": [{"check": "silhouette", "evidence": gate.evidence}],
            "cost": cost,
        }
        review.write(log.dir / "review.json", payload)

        if dry_run:
            # --dry-run makes no LLM calls and decides nothing a human must rule on --
            # leaving the worktree behind would strand a branch with no checkpoint to
            # resolve it. review.json is still written, for inspection only.
            worktree.abandon(repo, tree, branch)
            print(f"\n=== DRY RUN COMPLETE === worktree abandoned; nothing awaits your ruling")
            print(f"  {log.dir / 'review.json'}  (informational only)")
            return 0

        print(f"\n=== CHECKPOINT === {len(review.unruled(payload))} field(s) await your ruling")
        print(f"  cost: {_format_cost_line(cost)}")
        print(f"  {log.dir / 'review.json'}")
        print(f"  resume:  python3 scripts/asset_pipeline.py --resume {run_id}")
        print(f"  abandon: python3 scripts/asset_pipeline.py --abandon {run_id}")
        return 0

    except Exception as exc:
        # The traceback, not just str(exc). This handler spans every stage, and several
        # of them raise messages that name no location at all (a bare ValueError, a
        # subprocess timeout); an unattributable one-liner on the first real run of a
        # 10-stage pipeline is not a diagnosis.
        print(f"FAILED: {type(exc).__name__}: {exc}")
        traceback.print_exc()
        print(f"worktree left intact for inspection: {tree}")
        print(f"clean it up with: python3 scripts/asset_pipeline.py --abandon {run_id}")
        return 1


def build_log_clean(log_path: Path) -> bool:
    """build-game.sh exits 0 even when the export is broken -- Godot writes
    project.binary and reports success while omitting files the game needs to boot.
    /deploy-game greps for ^ERROR: for exactly this reason; so do we."""
    return not any(line.startswith("ERROR:")
                   for line in log_path.read_text().splitlines())


def build(repo: Path) -> tuple[bool, str]:
    log_path = repo / "runs" / "last-build.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(["bash", "scripts/build-game.sh", "web-singlethread", "release"],
                          cwd=repo, capture_output=True, text=True, timeout=3600)
    log_path.write_text(proc.stdout + proc.stderr)
    ok = proc.returncode == 0 and build_log_clean(log_path)
    return ok, str(log_path)


def worktree_of(run_id: str, repo: Path) -> tuple[Path, str]:
    """Where run() would have put this run's worktree and branch.

    run_id is "<yyyymmdd>-<ident>-<hex4>" and slug() never emits a hyphen, so the ident is
    recoverable from it -- which is what lets --abandon clean up a run that died before
    it wrote anything at all.
    """
    ident = "-".join(run_id.split("-")[1:-1])
    return repo / ".worktrees" / f"asset-{ident}", f"asset/{ident}"


def abandon_run(run_id: str, repo: Path) -> int:
    """Destroy a run's worktree and branch. Must work on a CRASHED run.

    A run that died before its checkpoint used to leave abandon_run raising
    FileNotFoundError on the missing review.json -- and the stranded worktree then blocked
    every future run at preflight, with no supported way out. run() now writes a stub
    immediately, and this falls back to deriving the paths from the run id when even that
    is absent.
    """
    path = repo / "runs" / run_id / "review.json"
    if path.is_file():
        payload = review.read(path)
        tree, branch = Path(payload["worktree"]), payload["branch"]
    else:
        tree, branch = worktree_of(run_id, repo)
        print(f"no review.json for {run_id}; derived worktree {tree} and branch {branch} "
              f"from the run id")
    worktree.abandon(repo, tree, branch)
    print(f"abandoned {run_id}: worktree and branch removed")
    print(f"evidence kept: {repo / 'runs' / run_id}")
    return 0


def resume(run_id: str, repo: Path) -> int:
    log_dir = repo / "runs" / run_id
    payload = review.read(log_dir / "review.json")

    if payload.get("incomplete"):
        # The stub run() writes before stage 1, so --abandon always has something to read.
        # It carries no decisions, which would otherwise read as "nothing left to rule".
        print(f"cannot resume {run_id}: it never reached its checkpoint. This review.json "
              f"is the stub --abandon needs, not a ruling sheet.")
        print(f"  abandon: python3 scripts/asset_pipeline.py --abandon {run_id}")
        return 1

    unruled = review.unruled(payload)
    if unruled:
        print(f"cannot resume: {len(unruled)} field(s) still unruled: {unruled}")
        print("Every tuning value is the human's. Rule them in "
              f"{log_dir / 'review.json'}, or via /add-asset.")
        return 1

    module = ADAPTER_MODULES[payload["adapter"]]
    adapter_name = payload["adapter"]
    tree = Path(payload["worktree"])
    mode = payload.get("mode")
    project = tree / "project"
    ident = slug(Path(payload["asset"]).stem)
    display = Path(payload["asset"]).stem
    values = {d["field"]: d["value"] for d in payload["decisions"]}

    problems = _validate(module, adapter_name, ident, mode, values)
    if problems:
        for p in problems:
            print(f"VALIDATION: {p}")
        return 1

    try:
        return _resume_stages(run_id, repo, payload, module, adapter_name, tree, project,
                              mode, ident, display, values)
    except Exception as exc:
        # resume() is the function that touches the OPERATOR'S REAL REPOSITORY, and the
        # stages below raise messages that name no location: terrain.write()'s inert-land
        # RuntimeError, regenerate_credits' RuntimeError, attribution.AmbiguousEntry. A
        # raw traceback here would leave the operator holding a worktree with no statement
        # of what it contains or how to get rid of it.
        print(f"FAILED at resume: {type(exc).__name__}: {exc}")
        traceback.print_exc()
        print(f"worktree KEPT at {tree} -- nothing was merged and the main checkout is "
              f"untouched.")
        print(f"clean it up with: python3 scripts/asset_pipeline.py --abandon {run_id}")
        return 1


def _resume_stages(run_id: str, repo: Path, payload: dict, module, adapter_name: str,
                   tree: Path, project: Path, mode: str | None, ident: str, display: str,
                   values: dict) -> int:
    header = (f"; {display} — generated by scripts/asset_pipeline.py run {run_id}\n"
              f"; Source: {payload['asset']}\n"
              f"; Format: {payload['resolved_format']['chosen']} "
              f"({payload['resolved_format']['reason']})\n"
              f"; Every value below was ruled by the human at this run's checkpoint.\n")

    # The ruled model_scale has to reach the artifact. run() wrote the wrapper BEFORE the
    # checkpoint with a hardcoded 0.2 (it must, so Godot can probe the AnimationPlayer),
    # and every adapter strips model_scale before rendering its .tres -- so the wrapper is
    # the only place scale lives, and nothing was putting the ruling into it. A building
    # ruled 1.0 shipped at 0.2; in terrain variant mode, where scale is the ONLY field the
    # human is asked for, the checkpoint was entirely decorative.
    scale = values.get("model_scale")
    if scale is None:
        print("[7/10] scale....... no model_scale in this review -- wrapper left as run() "
              "wrote it")
    else:
        wrapper = importer.dest_dir(project, module.SPEC.category, ident) / f"{display}.tscn"
        print(f"[7/10] scale....... {importer.rescale_wrapper(wrapper, scale)}")

    if mode == "variant":
        # A tree has no .tres of its own: it is appended to an existing terrain type's
        # model_scenes, and style_picker_popup derives its label from the directory name.
        host = project / "data" / "terrain" / f"{payload['variant_of']}.tres"
        summary = module.append_variant(
            host, f"res://assets/terrain/{ident}/{display}.tscn")
        print(f"[7/10] data entry.. {host.name}: {summary}")
    else:
        path = module.write(project, ident, display, values, header)
        print(f"[7/10] data entry.. {path.relative_to(tree)}")

    _copy_stage(adapter_name, tree, display, ident, payload)

    # Extending an existing pack's AttributionEntry is a generated-file operation; creating
    # a NEW entry is a licensing decision that belongs to game-design/art.md, not this
    # pipeline -- so a missing entry halts here rather than fabricating one. 11 of the 12
    # entries on disk are Quaternius; that is the creator this pipeline knows how to extend.
    pack = formats.pack_root(Path(payload["asset"]))
    try:
        entry = attribution.find_entry(project, "Quaternius", pack.name)
    except attribution.AmbiguousEntry as exc:
        print(f"[9/10] credits..... HALT {exc}")
        return 1
    if entry is None:
        print(f"[9/10] credits..... NO ENTRY for pack {pack.name!r} -- a new "
              f"AttributionEntry is a licensing decision, not a generated file. Halting.")
        return 1
    print(f"[9/10] credits..... {attribution.extend_assets_used(entry, [display])}")
    _preserve_license(pack, project, tree)
    godot.regenerate_credits(tree, repo)

    passed, output = godot.run_tests(tree, repo=repo)
    print(f"[10/10] tests...... {'PASS' if passed else 'FAIL'}")
    if not passed:
        print(output[-2000:])
        return 1

    worktree.commit_all(tree, f"feat(content): add {display} via asset pipeline ({run_id})")
    try:
        worktree.merge(repo, payload["branch"], payload["base_branch"])
    except worktree.MainBranchRefused as exc:
        print(f"\n{exc}")
        print(f"worktree kept at {tree}")
        return 2

    worktree.abandon(repo, tree, payload["branch"])
    ok, log_path = build(repo)
    print(f"build....... {'OK' if ok else 'FAILED'} ({log_path})")
    return 0 if ok else 1


def _copy_stage(adapter_name: str, tree: Path, display: str, ident: str,
                payload: dict) -> None:
    """The GER copy pipelines, per the design's adapter table.

    fact_card takes a DISPLAY name; style_guide takes a species ID. Both run from the
    WORKTREE's copy (cwd=tree) because they resolve their repo root from __file__ --
    invoking the main checkout's copy would patch the main checkout while this run
    believes it is sandboxed.

    Both were invoked with check=False and a success line printed regardless of outcome.
    Both carry a hardcoded ROSTER (fact_card_pipeline.py:146-160,
    style_guide_pipeline.py:154), and a newly imported species is by definition absent from
    it, so both exit non-zero with "unknown species" -- and the animal run then died at
    stage 10 on AnimalDefinition.validate() rejecting an empty fact_text_pool, with nothing
    connecting that failure back to here. The ROSTER limitation is pre-existing and out of
    this branch's scope, so this reports honestly rather than halting.
    """
    if adapter_name == "terrain":
        # The spec's terrain copy row is "none": terrain has no fact cards and no
        # WARN_/DEPART_/MOVE_ lines. Running fact_card_pipeline here would look for
        # project/data/animals/<id>.tres, which for a terrain type does not exist.
        print("[8/10] copy........ skipped -- the spec's terrain copy row is 'none'")
        return

    cmd = ["python3", "scripts/fact_card_pipeline.py", display, "--count", "2"]
    if adapter_name == "building":
        # Task 13 added --target building_text for exactly the spec's building row.
        # Without it the run patches project/data/animals/<id>.tres instead of
        # project/data/buildings/<id>.tres -- the wrong file, or none at all.
        cmd += ["--target", "building_text"]
    rc = subprocess.run(cmd, cwd=tree, check=False).returncode
    if rc == 0:
        print("[8/10] copy........ fact_card_pipeline (worktree copy)")
    else:
        print(f"[8/10] copy........ FAILED rc={rc} -- fact_card_pipeline wrote NOTHING. "
              f"Its ROSTER is hardcoded, so {display!r} has to be added there before it "
              f"can generate copy. Stage 10 will fail for an animal until you do: "
              f"AnimalDefinition.validate() rejects an empty fact_text_pool.")

    # Gentle Displacement copy is ANIMALS ONLY -- displacement_copy.gd has WARN_/DEPART_/
    # MOVE_ lines per species; buildings and terrain have none. Without this a new animal
    # ships with fact cards but falls through to WARN_GENERIC, which is exactly the gap
    # style_guide_pipeline.py exists to close.
    if payload["adapter"] == "animal":
        rc = subprocess.run(["python3", "scripts/style_guide_pipeline.py", ident,
                             "--line-type", "all"], cwd=tree, check=False).returncode
        if rc == 0:
            print("[8/10] copy........ style_guide_pipeline (WARN/DEPART/MOVE)")
        else:
            print(f"[8/10] copy........ FAILED rc={rc} -- style_guide_pipeline wrote "
                  f"NOTHING. Its ROSTER is hardcoded too, so {ident!r} needs adding "
                  f"there. Until then this animal falls through to WARN_GENERIC.")


def _preserve_license(pack: Path, project: Path, tree: Path) -> None:
    """Keep the pack's licence text in the repo alongside the credit.

    art.md's rule is that a link can rot and a compliance review must be answerable
    offline. attribution.copy_license_text() was implemented and traversal-hardened but
    never called by any stage. An already-present file is left alone: the three licences
    on disk today were curated by hand, and overwriting one would be a silent edit to a
    compliance record.
    """
    filename = attribution.license_filename("Quaternius", pack.name)
    dest = project / "assets" / "licenses" / filename
    if dest.is_file():
        print(f"[9/10] licence..... {filename} already preserved")
        return
    copied = attribution.copy_license_text(pack, project, filename)
    if copied is None:
        print(f"[9/10] licence..... no License.txt in {pack.name!r} -- nothing to preserve "
              f"offline; the entry's license_url stays the only record")
    else:
        print(f"[9/10] licence..... {copied.relative_to(tree)} -- point the entry's "
              f"license_file field at it yourself; editing an AttributionEntry is a "
              f"licensing decision, not a generated write")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("asset", nargs="?", help="Path to a file under source-content/assets/")
    parser.add_argument(
        "--as", dest="adapter", choices=ADAPTERS,
        help="Content type. REQUIRED for a real run -- never inferred from the path, "
             "because the same model can legitimately be an animal or a static prop.",
    )
    parser.add_argument("--selftest", action="store_true",
                        help="Run every deterministic check. No LLM calls, no git, no writes.")
    parser.add_argument("--notes", default="", help="Optional design hint passed to stage 6")
    parser.add_argument("--variant-of", metavar="TERRAIN_ID", default=None,
                        help="Terrain adapter only: append this model as a style variant "
                             "of an existing terrain type (e.g. --variant-of forest) "
                             "instead of writing a new terrain type.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Run every deterministic stage, skip the paid ones, then abandon")
    parser.add_argument("--resume", metavar="RUN_ID", help="Continue a run past its checkpoint")
    parser.add_argument("--abandon", metavar="RUN_ID", help="Destroy a run's worktree and branch")
    args = parser.parse_args()

    if args.selftest:
        return selftest()
    if args.resume:
        return resume(args.resume, Path.cwd())
    if args.abandon:
        return abandon_run(args.abandon, Path.cwd())
    if not args.asset:
        parser.error("an asset path is required (or --selftest)")
    if not args.adapter:
        parser.error("--as {animal|building|terrain} is required")
    if args.variant_of and args.adapter != "terrain":
        parser.error("--variant-of applies only to --as terrain")
    return run(Path(args.asset), args.adapter, Path.cwd(), args.notes or "",
               args.dry_run, args.variant_of)


if __name__ == "__main__":
    raise SystemExit(main())
