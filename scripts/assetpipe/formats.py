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
    # obj/mtl/blend carry no skeleton this pipeline can use.
    return ModelProbe(fmt=ext.lstrip("."))


# Preference order. Higher index wins. `blend` is present so it can be REPORTED as
# rejected rather than silently ignored -- an operator who sees only .blend on disk
# should learn why, and that it is a one-setting fix.
RANK = ("blend", "obj", "fbx", "gltf", "glb")

ASSETS_ROOT = Path("source-content/assets")

_REJECTIONS = {
    "blend": "blender_path is not configured in project.godot",
    "obj": "no skeleton or animation",
}


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


def resolve(asset: Path, needs_rig: bool, assets_root: Path = ASSETS_ROOT) -> Resolution:
    found = siblings(asset, assets_root)
    rejected: dict[str, str] = {}
    usable: list[str] = []

    for ext in found:
        if ext == "blend":
            rejected[ext] = _REJECTIONS["blend"]
        elif ext == "obj" and needs_rig:
            rejected[ext] = _REJECTIONS["obj"]
        else:
            usable.append(ext)

    if not usable:
        return Resolution(
            chosen="", chosen_path=None, probe=None, rejected=rejected,
            reason="no importable format for this need: found %s" % (
                ", ".join(sorted(found)) or "nothing"),
        )

    best = max(usable, key=RANK.index)
    for ext in usable:
        if ext != best:
            rejected[ext] = f"{best} outranks it"

    preferred_present = any(e in found for e in ("gltf", "glb"))
    reason = (
        f"{best} is the preferred available format"
        if preferred_present else
        f"no gltf in pack; {best} is the highest-ranked option that meets the need"
    )
    return Resolution(chosen=best, chosen_path=found[best], probe=probe(found[best]),
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
        c.eq(r.rejected.get("blend"), "blender_path is not configured in project.godot",
             "blend always rejected")
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

        stat = d / "assets" / "Static Pack"
        stat.mkdir(parents=True)
        (stat / "Well.obj").write_text("o Well\n")
        (stat / "Well.mtl").write_text("newmtl m\nKd 1 1 1\n")
        r4 = resolve(stat / "Well.obj", needs_rig=False, assets_root=d / "assets")
        c.eq(r4.chosen, "obj", "obj is acceptable when no rig is needed")
        r5 = resolve(stat / "Well.obj", needs_rig=True, assets_root=d / "assets")
        c.eq(r5.chosen, "", "obj-only pack has nothing to offer a rigged need")
        c.check("no importable format" in r5.reason, "unresolvable run explains itself")
