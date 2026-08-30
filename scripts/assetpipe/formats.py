"""Format probing and resolution.

Answers two questions without importing anything into Godot:
  1. What animation clips does this model actually have?
  2. Which of a model's several on-disk representations should we import?

WHY THIS MATTERS: source-content/assets ships 674 fbx, 604 obj, 536 blend, 208 gltf and
9 glb -- mostly the same models in several formats. `Farm Animals by @Quaternius` ships
NO gltf at all, so a gltf-only gate rejects Pig outright. Meanwhile the animation gate is
the one that costs a wasted import when it is wrong (game-design's asset-audit skill:
"that is exactly how the Quaternius chickens failed"), so it runs here, for free.
"""

from __future__ import annotations

import json
import os
import re
import struct
from dataclasses import dataclass, field
from pathlib import Path

# FBX stores animation stack names as plain strings of the form "Armature|<ClipName>".
# This is a HEURISTIC on a binary format with no public text schema -- it is a cheap
# pre-gate, never the authority. project/tests/test_<name>_import.gd enumerates the real
# AnimationPlayer after import and wins any disagreement (see Task 9).
_FBX_CLIP = re.compile(rb"Armature\|([A-Za-z0-9_]{2,40})")

UNKNOWN = -1


@dataclass
class ModelProbe:
    fmt: str
    clips: list[str] = field(default_factory=list)
    meshes: int = UNKNOWN
    nodes: int = UNKNOWN
    skins: int = UNKNOWN
    # Set when the file is PRESENT but this pipeline could not parse it -- a container
    # compressed with a codec we do not have, say. Distinct from "parsed fine, zero clips",
    # which is a real answer. Conflating the two lost every clip comparison silently and,
    # worse, made blender.export_gltf's "verify nothing was lost" check vacuous: with no
    # expected clips, nothing can go missing.
    unreadable: str | None = None


def probe_gltf(path: Path) -> ModelProbe:
    """Exact counts: .gltf is JSON, and .glb wraps that JSON in its first chunk."""
    if path.suffix.lower() == ".glb":
        raw = path.read_bytes()
        _magic, _ver, _len = struct.unpack("<4sII", raw[:12])
        chunk_len, _chunk_type = struct.unpack("<II", raw[12:20])
        doc = json.loads(raw[20:20 + chunk_len])
    else:
        doc = json.loads(path.read_text())
    return ModelProbe(
        fmt="glb" if path.suffix.lower() == ".glb" else "gltf",
        clips=sorted({a.get("name", "") for a in doc.get("animations", [])} - {""}),
        meshes=len(doc.get("meshes", [])),
        nodes=len(doc.get("nodes", [])),
        skins=len(doc.get("skins", [])),
    )


def probe_fbx(path: Path) -> ModelProbe:
    """Clip names only. Counts stay UNKNOWN -- ufbx is the only real parser, and Godot
    owns it, so guessing geometry counts from the binary would be inventing evidence."""
    found = _FBX_CLIP.findall(path.read_bytes())
    return ModelProbe(
        fmt="fbx",
        clips=sorted({m.decode("ascii", "ignore") for m in found}),
    )


def probe(path: Path) -> ModelProbe:
    ext = path.suffix.lower()
    if ext in (".gltf", ".glb"):
        return probe_gltf(path)
    if ext == ".fbx":
        return probe_fbx(path)
    if ext == ".blend":
        # Lazy: assetpipe.blender imports ModelProbe from here, so a module-level import
        # would be circular. Reading a .blend's actions needs no Blender installed.
        from assetpipe import blender
        return blender.probe_blend(path)
    # obj/mtl carry no skeleton this pipeline can use.
    return ModelProbe(fmt=ext.lstrip("."))


# Preference order, used as the LAST tiebreak only. Higher index wins, which ranks the
# formats needing no conversion above `blend` -- converting is work, and work we only do
# when it buys something. It is not a veto: for a rigged need, required-clip coverage and
# then raw clip count are compared first (see resolve), so a .blend that carries Walk
# outranks an fbx that does not. `blend` is a real candidate whenever Blender can run;
# when it cannot, it is still listed as REJECTED with the reason, so an operator who sees
# only .blend on disk learns why and that it is a one-setting fix.
RANK = ("blend", "obj", "fbx", "gltf", "glb")

ASSETS_ROOT = Path("source-content/assets")

OBJ_REJECTION = "no skeleton or animation"

# A .blend is usable only if we can convert it. Checked at resolution time so it is never
# chosen and then found unconvertible at import.


def _blender_available() -> bool:
    from assetpipe import blender  # lazy: see probe()
    return blender.available()


@dataclass
class Resolution:
    chosen: str
    chosen_path: Path | None
    probe: ModelProbe | None
    reason: str
    rejected: dict[str, str]


def pack_root(asset: Path, assets_root: Path = ASSETS_ROOT) -> Path:
    """The topmost directory under `assets_root` on this path -- the pack folder.

    Packs nest inconsistently (a plain `Farm Animals by @Quaternius/FBX/Pig.fbx`, but
    also Drive-export folders wrapping a second copy of their own name), so anchoring on
    the assets root rather than counting levels is the only rule that holds for both.
    """
    asset = asset.resolve()
    root = assets_root.resolve()
    rel = asset.relative_to(root)
    return root / rel.parts[0]


def siblings(asset: Path, assets_root: Path = ASSETS_ROOT) -> dict[str, Path]:
    """Every representation of this model in its pack, keyed by format."""
    stem = asset.stem
    out: dict[str, Path] = {}
    for candidate in pack_root(asset, assets_root).rglob("*"):
        if not candidate.is_file() or candidate.stem != stem:
            continue
        ext = candidate.suffix.lower().lstrip(".")
        if ext in RANK and ext not in out:
            out[ext] = candidate
    return out


def resolve(asset: Path, needs_rig: bool, assets_root: Path = ASSETS_ROOT,
            required_clips=()) -> Resolution:
    found = siblings(asset, assets_root)
    rejected: dict[str, str] = {}
    usable: list[str] = []
    probed: dict[str, ModelProbe] = {}

    for ext in found:
        if ext == "blend":
            if not _blender_available():
                from assetpipe import blender  # lazy: see probe()
                rejected[ext] = blender.unavailable_reason()
                continue
            # A container we cannot parse is excluded WITH ITS REASON rather than
            # compared as zero clips -- scanned raw it silently lost every comparison,
            # and if it had won one, the conversion's own verification would have been
            # vacuous. Unreadable-but-present is a distinct, stated outcome.
            probed[ext] = probe(found[ext])
            if probed[ext].unreadable:
                rejected[ext] = probed[ext].unreadable
                continue
            usable.append(ext)
        elif ext == "obj" and needs_rig:
            rejected[ext] = OBJ_REJECTION
        else:
            usable.append(ext)

    if not usable:
        return Resolution(
            chosen="", chosen_path=None, probe=None, rejected=rejected,
            reason="no importable format for this need: found %s" % (
                ", ".join(sorted(found)) or "nothing"),
        )

    # For a RIGGED need the animations are the whole point. What matters FIRST is whether
    # a source carries the clips the audit gate will demand -- raw count is only a
    # tiebreak after that. Count alone was the wrong question: animal.SPEC.required_clips
    # is ["Idle", "Walk"], so an fbx with 7 clips none of which is Walk beat a 6-clip
    # .blend that had it, and the asset was then rejected at the gate as unusable while a
    # usable source sat beside it. Real case: Pig's fbx has 2 of the 6 actions its .blend
    # holds, and the four it dropped include Walk. Static content ignores clips entirely
    # and keeps the plain ranking.
    # CAVEAT on the comparison: a .blend's action names are read exactly (ID blocks), but
    # the FBX side is the binary "Armature|<name>" heuristic, which can OVER-report -- the
    # real Cow.fbx scans as 8 when it holds 6, and on this pack Cow, Horse and Zebra all
    # win 8-vs-6 on phantom names alone. Ranking by required-clip coverage first blunts
    # that, since a phantom name is not one of the two clips being looked for, but an
    # over-read can still swing the raw-count tiebreak. The post-import Godot test
    # enumerates the real AnimationPlayer and remains the authority, as for the audit gate.
    probes = ({ext: probed[ext] if ext in probed else probe(found[ext])
               for ext in usable} if needs_rig else {})
    counts = {ext: len(p.clips) for ext, p in probes.items()}
    covered = {ext: sum(1 for clip in required_clips if clip in p.clips)
               for ext, p in probes.items()}

    def _rank_rigged(ext: str) -> tuple:
        return (covered[ext], counts[ext], RANK.index(ext))

    best = max(usable, key=_rank_rigged) if needs_rig else max(usable, key=RANK.index)
    for ext in usable:
        if ext != best:
            rejected[ext] = f"{best} outranks it"

    # Reuse the probe already taken above rather than re-reading a multi-megabyte binary.
    chosen_probe = probes[best] if best in probes else probe(found[best])

    if needs_rig and len(usable) > 1:
        runner = max((e for e in usable if e != best), key=_rank_rigged)
        prefix = "" if any(e in found for e in ("gltf", "glb")) else "no gltf in pack; "
        if covered[best] > covered[runner]:
            return Resolution(
                chosen=best, chosen_path=found[best], probe=chosen_probe,
                rejected=rejected,
                reason=(f"{prefix}{best} carries {covered[best]} of the "
                        f"{len(required_clips)} required clips vs {runner}'s "
                        f"{covered[runner]}"))
        if counts[best] > counts[runner]:
            return Resolution(
                chosen=best, chosen_path=found[best], probe=chosen_probe,
                rejected=rejected,
                reason=(f"{prefix}{best} carries {counts[best]} clips vs "
                        f"{runner}'s {counts[runner]}"))

    preferred_present = any(e in found for e in ("gltf", "glb"))
    reason = (
        f"{best} is the preferred available format"
        if preferred_present else
        f"no gltf in pack; {best} is the highest-ranked option that meets the need"
    )
    return Resolution(chosen=best, chosen_path=found[best], probe=chosen_probe,
                      reason=reason, rejected=rejected)


def selftest_cases(c) -> None:
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        d = Path(td)

        gltf = d / "Deer.gltf"
        gltf.write_text(json.dumps({
            "animations": [{"name": "Idle"}, {"name": "Walk"}, {"name": "Gallop"}],
            "meshes": [{}], "nodes": [{}] * 48, "skins": [{}],
        }))
        p = probe_gltf(gltf)
        c.eq(p.clips, ["Gallop", "Idle", "Walk"], "gltf clips parsed and sorted")
        c.eq(p.meshes, 1, "gltf mesh count")
        c.eq(p.nodes, 48, "gltf node count")
        c.eq(p.skins, 1, "gltf skin count")
        c.eq(p.fmt, "gltf", "gltf format tag")

        fbx = d / "Pig.fbx"
        fbx.write_bytes(b"\x00junk\x00Armature|Idle\x00pad\x00Armature|Jump\x00Armature|Idle\x00")
        q = probe_fbx(fbx)
        c.eq(q.clips, ["Idle", "Jump"], "fbx clips scanned, deduped and sorted")
        c.eq(q.skins, -1, "fbx counts are unknown, not zero")
        c.eq(q.fmt, "fbx", "fbx format tag")

        empty = d / "Rock.fbx"
        empty.write_bytes(b"\x00no rig here\x00")
        c.eq(probe_fbx(empty).clips, [], "unrigged fbx yields no clips")

        c.eq(probe(gltf).fmt, "gltf", "probe dispatches on extension")
        c.eq(probe(fbx).fmt, "fbx", "probe dispatches on extension")
        c.eq(probe(d / "Pig.obj").clips, [], "obj probe yields no clips")

        pack = d / "assets" / "Some Pack by @Quaternius"
        (pack / "FBX").mkdir(parents=True)
        (pack / "OBJ").mkdir(parents=True)
        (pack / "Blends").mkdir(parents=True)
        (pack / "FBX" / "Pig.fbx").write_bytes(b"\x00Armature|Idle\x00Armature|Walk\x00")
        (pack / "OBJ" / "Pig.obj").write_text("o Pig\n")
        (pack / "Blends" / "Pig.blend").write_bytes(b"BLENDER")

        c.eq(pack_root(pack / "FBX" / "Pig.fbx", assets_root=d / "assets"), pack,
             "pack root is the topmost dir under the assets root")

        r = resolve(pack / "FBX" / "Pig.fbx", needs_rig=True, assets_root=d / "assets")
        c.eq(r.chosen, "fbx", "animal with no gltf resolves to fbx")
        c.eq(r.rejected.get("obj"), "no skeleton or animation", "obj rejected for a rigged need")
        # Force unavailability: Blender may or may not be installed on a given machine,
        # and this assertion must mean the same thing either way.
        _sv = os.environ.get("BLENDER_PATH")
        os.environ["BLENDER_PATH"] = ""
        try:
            r_nb = resolve(pack / "FBX" / "Pig.fbx", needs_rig=True,
                           assets_root=d / "assets")
            c.check("Blender" in (r_nb.rejected.get("blend") or ""),
                    "with no Blender, blend is rejected and the reason says why")
        finally:
            if _sv is None:
                os.environ.pop("BLENDER_PATH", None)
            else:
                os.environ["BLENDER_PATH"] = _sv
        c.check("no gltf" in r.reason, "reason names the missing preferred format")

        (pack / "GLTF").mkdir()
        (pack / "GLTF" / "Pig.gltf").write_text(json.dumps(
            {"animations": [{"name": "Idle"}, {"name": "Walk"}], "meshes": [{}],
             "nodes": [{}], "skins": [{}]}))
        r2 = resolve(pack / "FBX" / "Pig.fbx", needs_rig=True, assets_root=d / "assets")
        c.eq(r2.chosen, "gltf", "gltf outranks fbx even when fbx was the path given")
        c.eq(r2.probe.clips, ["Idle", "Walk"], "resolution carries the chosen format's probe")

        r3 = resolve(pack / "OBJ" / "Pig.obj", needs_rig=False, assets_root=d / "assets")
        c.eq(r3.chosen, "gltf", "static need still prefers gltf when present")

        # --- .blend selection, when Blender is available -----------------------
        # Farm Animals is the real case: Pig's FBX carries 2 of the 6 actions its .blend
        # holds, and the four it dropped include Walk -- the clip the animal gate requires.
        import stat as _stat
        fake_blender = d / "fake-blender"
        fake_blender.write_text("#!/bin/sh\nexit 0\n")
        fake_blender.chmod(fake_blender.stat().st_mode | _stat.S_IXUSR)
        _saved = os.environ.get("BLENDER_PATH")
        os.environ["BLENDER_PATH"] = str(fake_blender)
        try:
            farm = d / "assets" / "Farm Animals"
            (farm / "FBX").mkdir(parents=True)
            (farm / "Blends").mkdir(parents=True)
            (farm / "FBX" / "Pig.fbx").write_bytes(
                b"\x00Armature|Idle\x00Armature|Jump\x00")
            (farm / "Blends" / "Pig.blend").write_bytes(
                b"BLENDER-v279\x00ACDeath\x00ACIdle\x00ACJump\x00ACRun\x00"
                b"ACWalk\x00ACWalkSlow\x00")
            rp = resolve(farm / "FBX" / "Pig.fbx", needs_rig=True, assets_root=d / "assets")
            c.eq(rp.chosen, "blend", "a richer .blend beats a thin fbx for a rigged need")
            c.check("6" in rp.reason and "2" in rp.reason,
                    "the reason states the clip counts it compared")
            c.eq(sorted(rp.probe.clips)[:2], ["Death", "Idle"],
                 "resolution carries the .blend's own clips")

            # Cow is the counter-case: its FBX is complete, so nothing should convert.
            (farm / "FBX" / "Cow.fbx").write_bytes(
                b"\x00Armature|Death\x00Armature|Idle\x00Armature|Jump\x00"
                b"Armature|Run\x00Armature|Walk\x00Armature|WalkSlow\x00")
            (farm / "Blends" / "Cow.blend").write_bytes(
                b"BLENDER-v279\x00ACDeath\x00ACIdle\x00ACJump\x00ACRun\x00"
                b"ACWalk\x00ACWalkSlow\x00")
            rc_ = resolve(farm / "FBX" / "Cow.fbx", needs_rig=True, assets_root=d / "assets")
            c.eq(rc_.chosen, "fbx", "an equally rich fbx wins the tie -- no needless convert")

            # REGRESSION, review IMPORTANT 1: raw clip COUNT was the whole predicate, so
            # an fbx with MORE total clips beat a .blend carrying the clips the audit gate
            # actually requires. animal.SPEC.required_clips is ["Idle", "Walk"]; a 7-clip
            # fbx with no Walk beat a 6-clip .blend that had it, and the asset was then
            # rejected at the audit gate as unusable while a usable source sat beside it.
            # The old comment claiming "an inflated fbx only ever wins a tie it would
            # already win" is false for this very pack: Cow, Horse and Zebra all score
            # fbx=8 vs blend=6, outright wins produced entirely by phantom names from the
            # binary heuristic.
            (farm / "FBX" / "Goat.fbx").write_bytes(
                b"\x00Armature|Idle\x00Armature|Jump\x00Armature|Run\x00"
                b"Armature|Death\x00Armature|Sit\x00Armature|Eat\x00Armature|Sleep\x00")
            (farm / "Blends" / "Goat.blend").write_bytes(
                b"BLENDER-v279\x00ACIdle\x00ACWalk\x00ACRun\x00ACDeath\x00"
                b"ACJump\x00ACWalkSlow\x00")
            rg = resolve(farm / "FBX" / "Goat.fbx", needs_rig=True,
                         assets_root=d / "assets", required_clips=["Idle", "Walk"])
            c.eq(rg.chosen, "blend",
                 "the source satisfying more REQUIRED clips wins over the one with more "
                 "clips overall")
            c.check("required" in rg.reason,
                    "the reason names the required-clip comparison it made")

            rg2 = resolve(farm / "FBX" / "Goat.fbx", needs_rig=True,
                          assets_root=d / "assets")
            c.eq(rg2.chosen, "fbx",
                 "with no required clips stated, raw count is still the tiebreak")

            rc2 = resolve(farm / "FBX" / "Cow.fbx", needs_rig=True,
                          assets_root=d / "assets", required_clips=["Idle", "Walk"])
            c.eq(rc2.chosen, "fbx",
                 "an fbx that already covers the required clips still wins the tie")

            # REGRESSION, review IMPORTANT 2: a container we cannot parse used to scan as
            # zero clips, which silently lost every comparison instead of saying why.
            (farm / "FBX" / "Yak.fbx").write_bytes(b"\x00Armature|Idle\x00")
            (farm / "Blends" / "Yak.blend").write_bytes(b"\x00\x01not a blender file\x00")
            ry = resolve(farm / "FBX" / "Yak.fbx", needs_rig=True,
                         assets_root=d / "assets", required_clips=["Idle", "Walk"])
            c.eq(ry.chosen, "fbx", "an unreadable .blend is excluded from the comparison")
            c.check("unreadable" in (ry.rejected.get("blend") or "").lower(),
                    "and is REPORTED as unreadable-but-present, with a stated reason")

            # Static content ignores clip counts entirely.
            rs = resolve(farm / "FBX" / "Pig.fbx", needs_rig=False, assets_root=d / "assets")
            c.eq(rs.chosen, "fbx", "a static need keeps the static ranking")
        finally:
            if _saved is None:
                os.environ.pop("BLENDER_PATH", None)
            else:
                os.environ["BLENDER_PATH"] = _saved

        stat = d / "assets" / "Static Pack"
        stat.mkdir(parents=True)
        (stat / "Well.obj").write_text("o Well\n")
        (stat / "Well.mtl").write_text("newmtl m\nKd 1 1 1\n")
        r4 = resolve(stat / "Well.obj", needs_rig=False, assets_root=d / "assets")
        c.eq(r4.chosen, "obj", "obj is acceptable when no rig is needed")
        r5 = resolve(stat / "Well.obj", needs_rig=True, assets_root=d / "assets")
        c.eq(r5.chosen, "", "obj-only pack has nothing to offer a rigged need")
        c.check("no importable format" in r5.reason, "unresolvable run explains itself")
