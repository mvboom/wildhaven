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
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from assetpipe.harness import Checks
from assetpipe import attribution, audit, dedupe, formats, importer, llm, review, runlog, worktree, godot
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


def run(asset: Path, adapter_name: str, repo: Path, notes: str = "",
        dry_run: bool = False, variant_of: str | None = None) -> int:
    module = ADAPTER_MODULES[adapter_name]
    spec = module.SPEC
    display = asset.stem
    ident = slug(display)
    mode = "variant" if variant_of else ("new_type" if adapter_name == "terrain" else None)

    problems = worktree.preflight(repo)
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

        godot.import_project(tree)
        scene_res = f"assets/{spec.category}/{ident}/{display}.tscn"
        idx = godot.anim_index(tree, scene_res) if spec.required_clips else -1
        if idx >= 0:
            importer.write_wrapper(project, spec.category, ident, display,
                                   f"{display}{resolution.chosen_path.suffix}", 0.2,
                                   gate.evidence["license"], idx, spec.schema)
            godot.import_project(tree)
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
            "mode": mode, "variant_of": variant_of,
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
        print(f"FAILED: {exc}")
        print(f"worktree left intact for inspection: {tree}")
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


def abandon_run(run_id: str, repo: Path) -> int:
    payload = review.read(repo / "runs" / run_id / "review.json")
    worktree.abandon(repo, Path(payload["worktree"]), payload["branch"])
    print(f"abandoned {run_id}: worktree and branch removed")
    print(f"evidence kept: {repo / 'runs' / run_id}")
    return 0


def resume(run_id: str, repo: Path) -> int:
    log_dir = repo / "runs" / run_id
    payload = review.read(log_dir / "review.json")
    unruled = review.unruled(payload)
    if unruled:
        print(f"cannot resume: {len(unruled)} field(s) still unruled: {unruled}")
        print("Every tuning value is the human's. Rule them in "
              f"{log_dir / 'review.json'}, or via /add-asset.")
        return 1

    module = ADAPTER_MODULES[payload["adapter"]]
    tree = Path(payload["worktree"])
    mode = payload.get("mode")
    project = tree / "project"
    ident = slug(Path(payload["asset"]).stem)
    display = Path(payload["asset"]).stem
    values = {d["field"]: d["value"] for d in payload["decisions"]}

    problems = module.validate_values(values) if hasattr(module, "validate_values") else []
    if problems:
        for p in problems:
            print(f"VALIDATION: {p}")
        return 1

    header = (f"; {display} — generated by scripts/asset_pipeline.py run {run_id}\n"
              f"; Source: {payload['asset']}\n"
              f"; Format: {payload['resolved_format']['chosen']} "
              f"({payload['resolved_format']['reason']})\n"
              f"; Every value below was ruled by the human at this run's checkpoint.\n")

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

    # BOTH copy pipelines, per the design's adapter table. fact_card takes a DISPLAY name;
    # style_guide takes a species ID. Both run from the WORKTREE's copy (cwd=tree) because
    # they resolve their repo root from __file__ -- invoking the main checkout's copy would
    # patch the main checkout while this run believes it is sandboxed.
    subprocess.run(["python3", "scripts/fact_card_pipeline.py", display, "--count", "2"],
                   cwd=tree, check=False)
    print("[8/10] copy........ fact_card_pipeline (worktree copy)")

    # Gentle Displacement copy is ANIMALS ONLY -- displacement_copy.gd has WARN_/DEPART_/
    # MOVE_ lines per species; buildings and terrain have none. Without this a new animal
    # ships with fact cards but falls through to WARN_GENERIC, which is exactly the gap
    # style_guide_pipeline.py exists to close.
    if payload["adapter"] == "animal":
        subprocess.run(["python3", "scripts/style_guide_pipeline.py", ident,
                        "--line-type", "all"], cwd=tree, check=False)
        print("[8/10] copy........ style_guide_pipeline (WARN/DEPART/MOVE)")

    # Extending an existing pack's AttributionEntry is a generated-file operation; creating
    # a NEW entry is a licensing decision that belongs to game-design/art.md, not this
    # pipeline -- so a missing entry halts here rather than fabricating one. 11 of the 12
    # entries on disk are Quaternius; that is the creator this pipeline knows how to extend.
    pack = formats.pack_root(Path(payload["asset"]))
    entry = attribution.find_entry(project, "Quaternius", pack.name)
    if entry is not None:
        print(f"[9/10] credits..... {attribution.extend_assets_used(entry, [display])}")
    else:
        print(f"[9/10] credits..... NO ENTRY for pack {pack.name!r} -- a new "
              f"AttributionEntry is a licensing decision, not a generated file. Halting.")
        return 1
    godot.regenerate_credits(tree)

    passed, output = godot.run_tests(tree)
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
