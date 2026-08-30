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
