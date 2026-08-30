"""Have we already got this?

Deliberately conservative: a hit HALTS and reports, it never decides. Matching is by
normalised basename, which scripts/asset-manifest.py's own docstring calls "a pointer,
not a record" -- a model renamed on import reads as absent, and a generic name (House,
Well) can collide with something unrelated. Both failure directions are the operator's
to resolve, not this module's.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

_STRIP = re.compile(r"[^a-z0-9]+")


@dataclass
class DupeResult:
    is_dupe: bool
    matches: list[str] = field(default_factory=list)


def normalize(name: str) -> str:
    return _STRIP.sub("", name.casefold())


def check(asset: Path, project_assets: Path, status_doc: Path) -> DupeResult:
    target = normalize(asset.stem)
    matches: list[str] = []

    if project_assets.is_dir():
        for existing in project_assets.rglob("*"):
            if existing.is_file() and normalize(existing.stem) == target:
                matches.append(str(existing))

    if status_doc.is_file():
        for section_id in re.findall(r"^### `([a-z0-9_]+)`", status_doc.read_text(),
                                     re.MULTILINE):
            if normalize(section_id) == target:
                matches.append(f"{status_doc.name}: section `{section_id}`")

    return DupeResult(is_dupe=bool(matches), matches=matches)


def selftest_cases(c) -> None:
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        d = Path(td)
        c.eq(normalize("ShibaInu"), "shibainu", "camel case normalised")
        c.eq(normalize("Shiba_Inu"), "shibainu", "underscores stripped")
        c.eq(normalize("shiba-inu"), "shibainu", "hyphens stripped")
        c.eq(normalize("Common Tree 1"), "commontree1", "spaces stripped")

        pa = d / "assets" / "animals" / "shiba_inu"
        pa.mkdir(parents=True)
        (pa / "ShibaInu.gltf").write_text("{}")
        status = d / "status.md"
        status.write_text("### `wolf`\n| `source` | somewhere |\n")

        r = check(d / "src" / "ShibaInu.fbx", d / "assets", status)
        c.check(r.is_dupe, "existing project asset is detected")
        c.check(any("ShibaInu.gltf" in m for m in r.matches), "match names the file")

        r2 = check(d / "src" / "Wolf.fbx", d / "assets", status)
        c.check(r2.is_dupe, "an id recorded in the status doc counts as a dupe")

        r3 = check(d / "src" / "Otter.fbx", d / "assets", status)
        c.check(not r3.is_dupe, "genuinely new asset is not a dupe")
