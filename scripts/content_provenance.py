#!/usr/bin/env python3
"""Phase 1: find and record where each imported asset came from.

Only 3 of 31 .tres files record a `; Source:` line -- the ones the pipeline made. The rest
predate it. This fingerprints each unrecorded asset, ranks candidate originals in
source-content/, and writes the Source line for unambiguous matches.

It NEVER guesses silently. An asset whose origin cannot be established keeps no Source
line and reports UNKNOWN-SOURCE forever, which is an honest state and visible every run.

Usage:
    python3 scripts/content_provenance.py            # report only, writes nothing
    python3 scripts/content_provenance.py --write    # write HIGH-confidence matches
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from assetpipe import declared, fingerprint, godot  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
SOURCE_ROOT = REPO / "source-content" / "assets"
DATA_DIRS = ("animals", "buildings", "terrain")
MODEL_SUFFIXES = (".gltf", ".glb", ".blend", ".fbx")


def slug(name: str) -> str:
    """Same rule as asset_pipeline.slug -- casefold, non-alphanumeric to underscore."""
    return re.sub(r"[^a-z0-9]+", "_", name.casefold()).strip("_")


def score(src: dict, run: dict) -> int:
    total = 0
    if src["materials"] == run["materials"]:
        total += 2
    if src["base_colors"] == run["base_colors"]:
        total += 2
    if set(src["clips"]) == set(run["clips"]):
        total += 1
    if src["joints"] == run["joints"]:
        total += 1
    return total


def confidence(scored: list) -> str:
    """scored is [(label, score), ...] in any order. Derived, never judged."""
    if not scored:
        return "LOW"
    ranked = sorted(scored, key=lambda t: -t[1])
    best = ranked[0][1]
    rest = [s for _, s in ranked[1:]]
    if len(rest) and best - max(rest) <= 1:
        return "AMBIGUOUS"
    if best == 6 and all(s <= 3 for s in rest):
        return "HIGH"
    return "LOW"


def runtime_manifest(repo: Path, wrapper_res: str) -> dict:
    """The live manifest, via dump_fidelity.gd."""
    env = dict(os.environ, WILDHAVEN_WRAPPER=wrapper_res)
    proc = subprocess.run(
        [str(godot.binary(repo)), "--headless", "--path", str(repo / "project"),
         "--script", "res://tests/dump_fidelity.gd"],
        capture_output=True, text=True, env=env, timeout=300)
    if "<<<MANIFEST>>>" not in proc.stdout:
        raise RuntimeError(
            f"no manifest for {wrapper_res}\n{proc.stdout[-1500:]}{proc.stderr[-1500:]}")
    body = proc.stdout.split("<<<MANIFEST>>>", 1)[1].split("<<<END>>>", 1)[0]
    return json.loads(body)


def candidates(repo: Path, ident: str) -> list:
    """Every source model whose basename slugs to this asset's id."""
    root = repo / "source-content" / "assets"
    return sorted(p for p in root.rglob("*")
                  if p.suffix.lower() in MODEL_SUFFIXES and slug(p.stem) == ident)


def wrapper_res_for(tres_text: str) -> str:
    """The model wrapper a .tres points at, read from its ext_resource line."""
    m = re.search(r'\[ext_resource type="PackedScene" path="([^"]+)"', tres_text)
    return m.group(1) if m else ""


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true",
                    help="write '; Source:' for HIGH-confidence matches")
    args = ap.parse_args(argv)

    rows, written = [], 0
    for sub in DATA_DIRS:
        for tres in sorted((REPO / "project" / "data" / sub).glob("*.tres")):
            text = tres.read_text()
            decl = declared.parse(text)
            ident = tres.stem
            if decl["placeholder"]:
                rows.append((ident, "KNOWN-PLACEHOLDER", "", ""))
                continue
            if decl["source"]:
                rows.append((ident, "ALREADY-RECORDED", decl["source"], ""))
                continue
            wrapper = wrapper_res_for(text)
            if not wrapper:
                rows.append((ident, "NO-WRAPPER", "", "no PackedScene ext_resource"))
                continue

            print(f"  ...probing {ident} ({wrapper})", file=sys.stderr)
            run = runtime_manifest(REPO, wrapper)
            scored = []
            for cand in candidates(REPO, ident):
                print(f"      candidate {cand.name}", file=sys.stderr)
                try:
                    scored.append((cand, score(fingerprint.manifest_for_source(cand), run)))
                except Exception as exc:                      # noqa: BLE001
                    rows.append((ident, "CANDIDATE-ERROR", str(cand), str(exc)[:80]))
            conf = confidence([(str(p), s) for p, s in scored])
            if not scored:
                rows.append((ident, "UNKNOWN-SOURCE", "", "no candidate by name"))
                continue

            best = max(scored, key=lambda t: t[1])
            rel = str(best[0].relative_to(REPO))
            runners = ", ".join(f"{p.name}:{s}" for p, s in
                                sorted(scored, key=lambda t: -t[1])[1:3])
            if conf == "HIGH" and args.write and declared.write_source(tres, rel):
                written += 1
                rows.append((ident, "WRITTEN", rel, f"score {best[1]}"))
            else:
                rows.append((ident, conf, rel, f"score {best[1]}; {runners}"))

    width = max(len(r[0]) for r in rows) if rows else 10
    for ident, state, path, note in rows:
        print(f"  {ident:<{width}}  {state:<17} {path}  {note}".rstrip())
    print(f"\n{len(rows)} item(s); {written} Source line(s) written.")
    if not args.write:
        print("Report only. Re-run with --write to record HIGH-confidence matches.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


def selftest_cases(c) -> None:
    from assetpipe.fingerprint import empty_manifest

    a = empty_manifest() | {"materials": 2, "base_colors": [[0.8, 0.8, 0.8, 1.0]],
                            "clips": ["Idle", "Walk"], "joints": 31}
    c.eq(score(a, dict(a)), 6, "an exact match scores the full 6")
    c.eq(score(a, dict(a, joints=0)), 5, "a wrong joint count costs 1")
    c.eq(score(a, dict(a, materials=9)), 4, "a wrong material count costs 2")
    c.eq(score(empty_manifest(), dict(a)), 0, "nothing in common scores 0")

    c.eq(confidence([("x", 6), ("y", 2)]), "HIGH", "a clear winner is HIGH")
    c.eq(confidence([("x", 6), ("y", 5)]), "AMBIGUOUS",
         "two candidates within 1 point are AMBIGUOUS")
    c.eq(confidence([("x", 4), ("y", 1)]), "LOW", "a weak best match is LOW")
    c.eq(confidence([]), "LOW", "no candidates is LOW")
    c.eq(confidence([("x", 6)]), "HIGH", "a single perfect candidate is HIGH")
