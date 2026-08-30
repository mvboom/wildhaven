"""Blender: probe a .blend's actions, and convert one to glTF.

WHY THIS EXISTS. `source-content/assets/Farm Animals by @Quaternius` ships both FBX and
.blend for seven species. Four of the FBX exports (Llama, Pig, Pug, Sheep) carry only 2 of
the 6 actions the .blend holds -- and the four they dropped include `Walk`, which is
exactly the clip the animal audit gate requires. Those species were rejected as unusable
while being fully animated in source. Converting from .blend recovers them.

Cow, Horse and Zebra need no conversion: their FBX carries all 6. That is why selection is
by clip count rather than by file extension -- see formats.resolve.

Blender is needed ONLY when importing such an asset. The artifact committed to the project
is a plain glTF, so nothing downstream -- build-game.sh, a web export, CI, a fresh clone --
needs Blender installed.

NOTE ON FILE AGE: these .blend files are BLENDER-v279 (2017). A modern Blender opens them,
but material and rig handling changed substantially since. `export_gltf` therefore verifies
the produced glTF carries the clips the .blend advertised, rather than trusting the export.
"""

from __future__ import annotations

import gzip
import os
import re
import shutil
import subprocess
from pathlib import Path

from assetpipe.formats import UNKNOWN, ModelProbe, probe_gltf

BLENDER_ENV = "BLENDER_PATH"

# Blender stores each Action as an ID block whose name is prefixed "AC". Reading them is a
# pure file read -- no Blender needed -- so the audit gate can judge a .blend before any
# conversion is attempted, and the whole selftest stays offline.
_ACTION = re.compile(rb"AC([A-Za-z][A-Za-z0-9_.\- ]{2,30})\x00")


def binary() -> str | None:
    """The Blender executable, or None. `BLENDER_PATH` wins over PATH discovery."""
    override = os.environ.get(BLENDER_ENV)
    if override is not None:
        return override or None
    return shutil.which("blender")


def available() -> bool:
    """True when a Blender we could actually run is present.

    Checked at format-resolution time so a .blend only becomes a candidate when it can be
    converted -- rather than being chosen and then failing at import.
    """
    path = binary()
    if not path:
        return False
    return Path(path).is_file() or shutil.which(path) is not None


def probe_blend(path: Path) -> ModelProbe:
    """Action names read straight out of the .blend. No Blender required.

    Geometry counts stay UNKNOWN: only Blender can answer those, and guessing them from
    the container would be inventing evidence -- the same rule probe_fbx follows.
    """
    raw = path.read_bytes()
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    return ModelProbe(
        fmt="blend",
        clips=sorted({m.decode("ascii", "ignore") for m in _ACTION.findall(raw)}),
    )


# GLTF_SEPARATE writes <Name>.gltf plus its .bin beside it, matching the shape the rest of
# the project already uses (Wolf.gltf, Plant_7.gltf + .bin). Exporting straight into the
# destination means there is nothing to copy afterwards.
_EXPORT_EXPR = (
    "import bpy; "
    "bpy.ops.export_scene.gltf(filepath=r'{out}', export_format='GLTF_SEPARATE')"
)


def export_gltf(blend: Path, dest_dir: Path, name: str) -> Path:
    """Convert one .blend to glTF in `dest_dir`, and verify nothing was lost.

    The verification is not ceremony. These files are BLENDER-v279 (2017); a modern
    Blender opens them but handles materials and rigs differently, and a silently dropped
    action would otherwise surface as a missing animation at look-pass time instead of
    here, where it names the file and the clips.
    """
    exe = binary()
    if not exe:
        raise RuntimeError(
            f"cannot convert {blend.name}: Blender not found. Put it on PATH, or set "
            f"{BLENDER_ENV} to the executable."
        )
    dest_dir.mkdir(parents=True, exist_ok=True)
    out = dest_dir / f"{name}.gltf"
    proc = subprocess.run(
        [exe, "--background", str(blend), "--python-expr",
         _EXPORT_EXPR.format(out=out)],
        capture_output=True, text=True, timeout=600,
    )
    if proc.returncode != 0 or not out.is_file():
        tail = (proc.stdout + proc.stderr)[-400:]
        raise RuntimeError(
            f"Blender failed to export {blend.name} (exit {proc.returncode}). "
            f"Output tail: {tail}"
        )
    expected = set(probe_blend(blend).clips)
    got = set(probe_gltf(out).clips)
    missing = sorted(expected - got)
    if missing:
        raise RuntimeError(
            f"{blend.name} advertises actions {sorted(expected)} but the exported glTF "
            f"carries {sorted(got)} -- missing {missing}. These are BLENDER-v279 files; a "
            f"modern Blender may need different export options for them."
        )
    return out


def selftest_cases(c) -> None:
    import tempfile

    with tempfile.TemporaryDirectory() as td:
        d = Path(td)

        plain = d / "Pig.blend"
        plain.write_bytes(
            b"BLENDER-v279\x00junk"
            b"ACIdle\x00pad\x00ACWalk\x00ACRun\x00ACJump\x00ACIdle\x00"
        )
        p = probe_blend(plain)
        c.eq(p.clips, ["Idle", "Jump", "Run", "Walk"],
             "blend actions parsed, deduped and sorted")
        c.eq(p.fmt, "blend", "blend format tag")
        c.eq(p.skins, UNKNOWN, "blend geometry counts are unknown, not zero")

        packed = d / "Cow.blend"
        packed.write_bytes(gzip.compress(b"BLENDER-v279\x00ACWalk\x00ACDeath\x00"))
        c.eq(probe_blend(packed).clips, ["Death", "Walk"],
             "a gzip-compressed .blend is read too")

        empty = d / "Rock.blend"
        empty.write_bytes(b"BLENDER-v279\x00no actions here\x00")
        c.eq(probe_blend(empty).clips, [], "a .blend with no actions yields no clips")

        # binary() honours the env override without requiring Blender to exist.
        saved = os.environ.get(BLENDER_ENV)
        try:
            os.environ[BLENDER_ENV] = "/nonexistent/blender"
            c.eq(binary(), "/nonexistent/blender", "BLENDER_PATH overrides discovery")
            os.environ.pop(BLENDER_ENV)
            c.check(isinstance(available(), bool), "available() answers without raising")
        finally:
            if saved is None:
                os.environ.pop(BLENDER_ENV, None)
            else:
                os.environ[BLENDER_ENV] = saved

        # export_gltf must refuse clearly rather than shelling out to nothing.
        saved = os.environ.get(BLENDER_ENV)
        try:
            os.environ[BLENDER_ENV] = ""
            raised = False
            try:
                export_gltf(plain, d, "Pig")
            except RuntimeError as exc:
                raised = "Blender" in str(exc)
            c.check(raised, "export_gltf raises a named error when Blender is unavailable")
        finally:
            if saved is None:
                os.environ.pop(BLENDER_ENV, None)
            else:
                os.environ[BLENDER_ENV] = saved
