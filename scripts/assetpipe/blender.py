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


# Answered once per binary per process: resolve() asks for every .blend candidate, and
# launching Blender repeatedly to learn the same fact would be wasteful.
_RUNNABLE: dict = {}


def available() -> bool:
    """True when a Blender we can actually RUN is present.

    Deliberately LAUNCHES it rather than checking the file exists. A snap Blender is on
    PATH and passes an exists-check, then dies under a confined sandbox with a DBus
    "cannot create transient scope" error. Catching that here means format resolution
    simply does not offer .blend as a candidate -- and records why -- instead of choosing
    it and failing mid-import, after the worktree is built. Every other gate in this
    pipeline fails at the cheapest point; this one now does too.
    """
    path = binary()
    if not path:
        return False
    if path not in _RUNNABLE:
        try:
            proc = subprocess.run([path, "--version"], capture_output=True, timeout=60)
            _RUNNABLE[path] = proc.returncode == 0
        except (OSError, subprocess.SubprocessError):
            _RUNNABLE[path] = False
    return _RUNNABLE[path]


def unavailable_reason() -> str:
    """Why .blend is not a candidate, accurately.

    "Not found" and "found but will not run" are different problems with different fixes,
    and the operator sees this text at the checkpoint. The snap case is the second one.
    """
    path = binary()
    if not path:
        return ("Blender not found -- put it on PATH or set BLENDER_PATH; a .blend is "
                "only a candidate when it can be converted to glTF")
    return (f"Blender at {path} could not be launched -- it exists but did not run "
            f"(a snap build fails this way under a confined sandbox). Set BLENDER_PATH "
            f"to a working build.")


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

        # available() must answer "can we RUN it", not "does the file exist". A snap
        # Blender exists on PATH and dies under a confined sandbox with a DBus error;
        # catching that here means resolution never offers .blend and then fails at import.
        import stat as _stat
        runnable = d / "runs-fine"
        runnable.write_text("#!/bin/sh\nexit 0\n")
        runnable.chmod(runnable.stat().st_mode | _stat.S_IXUSR)
        broken = d / "exits-nonzero"
        broken.write_text("#!/bin/sh\nexit 3\n")
        broken.chmod(broken.stat().st_mode | _stat.S_IXUSR)
        not_exec = d / "not-executable"
        not_exec.write_text("#!/bin/sh\nexit 0\n")

        _s2 = os.environ.get(BLENDER_ENV)
        try:
            os.environ[BLENDER_ENV] = str(runnable)
            c.check(available(), "a Blender that launches is available")
            os.environ[BLENDER_ENV] = str(broken)
            c.check(not available(), "a Blender that exits non-zero is NOT available")
            os.environ[BLENDER_ENV] = str(not_exec)
            c.check(not available(),
                    "a file that exists but cannot be executed is NOT available")
            os.environ[BLENDER_ENV] = "/nonexistent/blender"
            c.check(not available(), "a missing Blender is NOT available")
        finally:
            if _s2 is None:
                os.environ.pop(BLENDER_ENV, None)
            else:
                os.environ[BLENDER_ENV] = _s2

        _s3 = os.environ.get(BLENDER_ENV)
        try:
            os.environ[BLENDER_ENV] = ""
            c.check("not found" in unavailable_reason(),
                    "with no Blender at all, the reason says not found")
            os.environ[BLENDER_ENV] = str(broken)
            reason = unavailable_reason()
            c.check("could not be launched" in reason,
                    "a Blender that exists but will not run says so, not 'not found'")
            c.check(str(broken) in reason,
                    "and names the path it actually tried")
        finally:
            if _s3 is None:
                os.environ.pop(BLENDER_ENV, None)
            else:
                os.environ[BLENDER_ENV] = _s3

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
