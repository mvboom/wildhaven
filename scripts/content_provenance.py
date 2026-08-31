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

from assetpipe import declared, fingerprint, formats, godot  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
SOURCE_ROOT = REPO / "source-content" / "assets"
DATA_DIRS = ("animals", "buildings", "terrain")
MODEL_SUFFIXES = (".gltf", ".glb", ".blend", ".fbx")

# Preference order for collapsing same-model sibling formats to one origin: a glTF/glb
# is the format Godot actually imported, so it wins ties; .blend and .fbx are re-exports
# a step further from what shipped.
FORMAT_RANK = {"gltf": 0, "glb": 0, "blend": 1, "fbx": 2}


def slug(name: str) -> str:
    """asset_pipeline.slug's rule (casefold, non-alphanumeric to underscore) -- PLUS a
    CamelCase split applied first.

    Source filenames carry no separator between words at all ("ChickenCoop.fbx",
    "WaterTower.blend"), so the bare asset_pipeline rule alone slugs "ChickenCoop" to
    "chickencoop", which never equals the .tres ident "chicken_coop" -- a real source
    file silently discarded as no-match. Splitting at each lowercase/digit-to-uppercase
    boundary first turns it into "Chicken_Coop" before casefolding, so the two now
    agree. Verified this also leaves single-word names ("Deer") unsplit.
    """
    name = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name)
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
    binary = godot.binary(repo)
    if not binary.is_file():
        # godot.binary()'s main-checkout fallback resolves from ITS OWN __file__, which
        # is correct for asset_pipeline.py (only ever invoked from the main checkout) but
        # not here: this script's own copy of scripts/assetpipe/godot.py lives inside
        # whatever worktree it is run from, so the fallback resolves to that worktree --
        # which has no godot/ directory -- rather than the real main checkout. Failing
        # here, at the cheapest point, with the fix named, beats a FileNotFoundError deep
        # inside subprocess.run.
        raise RuntimeError(
            f"no Godot binary at {binary}. Set GODOT_PATH to the main checkout's engine "
            f"binary before running this from a worktree -- godot.binary()'s fallback "
            f"cannot find it on its own from here.")
    env = dict(os.environ, WILDHAVEN_WRAPPER=wrapper_res)
    proc = subprocess.run(
        [str(binary), "--headless", "--path", str(repo / "project"),
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


def _collapse_to_origins(scored: list, assets_root: Path = SOURCE_ROOT) -> list:
    """Collapse same-model sibling formats into ONE origin, represented by its
    best-scoring member.

    candidates() returns every .gltf/.glb/.blend/.fbx file whose stem slugs to the
    asset's id, and most packs ship the SAME model in two or three of those formats side
    by side. Scoring them as competing candidates makes confidence() call a clean match
    AMBIGUOUS: Blender's BSDF default readback differs slightly from the glTF exporter's
    values, so a .blend/.fbx sibling of the truly-correct .gltf source lands 1-2 points
    lower -- within confidence()'s 1-point AMBIGUOUS band of the winner, even though
    there is no real doubt which pack the asset came from.

    Two candidates collapse only when they share BOTH the same normalised stem (already
    guaranteed -- candidates() only returns matches for one ident) AND the same pack
    root, via formats.pack_root(). Two DIFFERENT models -- same stem, different pack,
    e.g. "Cow.blend" shipped by two unrelated packs -- must NOT collapse: that is a real
    ambiguity confidence() still has to catch.

    Ties within a group break on score first, then a fixed format preference
    (.gltf/.glb, then .blend, then .fbx -- FORMAT_RANK), so repeated runs are
    deterministic.
    """
    groups: dict[tuple, list] = {}
    for path, s in scored:
        key = (slug(path.stem), formats.pack_root(path, assets_root))
        groups.setdefault(key, []).append((path, s))
    origins = []
    for members in groups.values():
        best = min(
            members,
            key=lambda t: (-t[1], FORMAT_RANK.get(t[0].suffix.lower().lstrip("."), 99)))
        origins.append(best)
    return origins


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
            origins = _collapse_to_origins(scored)
            conf = confidence([(str(p), s) for p, s in origins])
            if not scored:
                rows.append((ident, "UNKNOWN-SOURCE", "", "no candidate by name"))
                continue

            best = max(origins, key=lambda t: t[1])
            rel = str(best[0].relative_to(REPO))
            runners = ", ".join(f"{p.name}:{s}" for p, s in
                                sorted(origins, key=lambda t: -t[1])[1:3])
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

    # --- FINDING 1: slug() splits CamelCase before applying asset_pipeline's rule -----
    # Source filenames carry no separator at all between words ("ChickenCoop.fbx"), so
    # without the split, slug("ChickenCoop") == "chickencoop" never matches the .tres
    # ident "chicken_coop" -- 5 real source files were silently missed this way.
    c.eq(slug("ShibaInu"), "shiba_inu", "CamelCase split: shiba_inu")
    c.eq(slug("ChickenCoop"), "chicken_coop", "CamelCase split: chicken_coop")
    c.eq(slug("OpenBarn"), "open_barn", "CamelCase split: open_barn")
    c.eq(slug("SmallBarn"), "small_barn", "CamelCase split: small_barn")
    c.eq(slug("WaterTower"), "water_tower", "CamelCase split: water_tower")
    c.eq(slug("Deer"), "deer", "a single-word name is left unsplit -- no over-firing")

    # --- FINDING 2: sibling formats of ONE model collapse to a single origin ---------
    # Most packs ship the same model as .gltf + .blend + .fbx side by side, and scoring
    # them as competing candidates made confidence() call a clean match AMBIGUOUS.
    import tempfile as _tf2
    with _tf2.TemporaryDirectory() as td2:
        root2 = Path(td2)
        pack_a = root2 / "PackA"
        pack_b = root2 / "PackB"
        pack_a.mkdir(parents=True)
        pack_b.mkdir(parents=True)
        gltf = pack_a / "Model.gltf"; gltf.touch()
        blend = pack_a / "Model.blend"; blend.touch()
        fbx = pack_a / "Model.fbx"; fbx.touch()
        other_pack_model = pack_b / "Model.gltf"; other_pack_model.touch()

        siblings = [(gltf, 6), (blend, 5), (fbx, 4)]
        collapsed = _collapse_to_origins(siblings, root2)
        c.eq(len(collapsed), 1,
             "three sibling formats of one model, one pack, collapse to one origin")
        c.eq(collapsed[0], (gltf, 6),
             "the collapsed origin is the highest-scoring sibling")
        c.eq(confidence([(str(p), s) for p, s in collapsed]), "HIGH",
             "collapsing sibling formats turns a spurious AMBIGUOUS into HIGH")

        different_packs = [(gltf, 6), (other_pack_model, 5)]
        collapsed2 = _collapse_to_origins(different_packs, root2)
        c.eq(len(collapsed2), 2,
             "same stem, DIFFERENT pack roots -- two distinct origins, not collapsed")
        c.eq(confidence([(str(p), s) for p, s in collapsed2]), "AMBIGUOUS",
             "genuinely different candidate origins still report AMBIGUOUS")

        tie = [(fbx, 5), (blend, 5)]
        c.eq(_collapse_to_origins(tie, root2)[0][0], blend,
             "equal score: format preference picks .blend over .fbx")
        tie2 = [(blend, 5), (gltf, 5)]
        c.eq(_collapse_to_origins(tie2, root2)[0][0], gltf,
             "equal score: format preference picks .gltf over .blend")

    # --- FINDING 3: no silent continuation when the Godot binary cannot be resolved ---
    # godot.binary()'s main-checkout fallback resolves from ITS OWN __file__, which is
    # wrong when this script's own copy of godot.py lives inside a task worktree. An
    # explicit GODOT_PATH override always wins in godot.binary(), so pointing it at a
    # path that does not exist exercises the guard deterministically, regardless of
    # where this suite itself happens to run from.
    import tempfile as _tf3
    _saved_gp = os.environ.get("GODOT_PATH")
    try:
        with _tf3.TemporaryDirectory() as td3:
            os.environ["GODOT_PATH"] = str(Path(td3) / "no-such-godot-binary")
            try:
                runtime_manifest(Path(td3), "res://x.tscn")
                c.check(False, "runtime_manifest raises when the resolved binary "
                               "is not a file")
            except RuntimeError as exc:
                c.check("GODOT_PATH" in str(exc),
                        "the failure names GODOT_PATH as how to fix it")
    finally:
        if _saved_gp is None:
            os.environ.pop("GODOT_PATH", None)
        else:
            os.environ["GODOT_PATH"] = _saved_gp
