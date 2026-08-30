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
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from assetpipe.harness import Checks
from assetpipe import audit, dedupe, formats, importer, llm, review, runlog, worktree
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


def selftest() -> int:
    from assetpipe.adapters import base
    c = Checks()
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

        print("[5/10] verify...... (godot --import + generated test; see Task 17)")

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
        print(f"--resume {args.resume}: not yet implemented (lands in Task 19)")
        return 1
    if args.abandon:
        print(f"--abandon {args.abandon}: not yet implemented (lands in Task 19)")
        return 1
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
