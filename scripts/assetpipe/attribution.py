"""Attribution: extend an existing source entry, or author a new one.

Schema is project/attribution/attribution_entry.gd. Field names and the
PackedStringArray form are transcribed from the real entries in
project/attribution/sources/ -- notably quaternius_animated_men_characters.tres.

EXTENDING IS THE COMMON PATH: 11 of the 12 entries on disk are quaternius_*, so a new
Quaternius model almost always belongs in one that already exists
(asset-import-pipeline.md step 5). Creating a second entry for a recorded pack is a
defect.

generate_credits.gd FAILS CLOSED when attribution_required is set without a
required_notice, so new_entry_text always writes both or neither.
"""

from __future__ import annotations

import re
import shutil
from pathlib import Path

_SNAKE = re.compile(r"[^a-z0-9]+")
_ASSETS = re.compile(r"^assets_used = PackedStringArray\((.*)\)$", re.MULTILINE)

ENTRY_TEMPLATE = """[gd_resource type="Resource" script_class="AttributionEntry" load_steps=2 format=3]

[ext_resource type="Script" path="res://attribution/attribution_entry.gd" id="1_entry"]

[resource]
script = ExtResource("1_entry")
id = "{entry_id}"
creator = "{creator}"
source_name = "{source_name}"
source_version = "{source_version}"
creator_url = "{creator_url}"
source_url = "{source_url}"
support_url = ""
license_name = "{license_name}"
license_url = "{license_url}"
license_file = "{license_file}"
attribution_required = {attribution_required}
required_notice = "{required_notice}"
conditions = ""
assets_used = PackedStringArray({assets})
per_file_licensing = false
notes = "Added by scripts/asset_pipeline.py."
"""


def entry_id(creator: str, source_name: str) -> str:
    return _SNAKE.sub("_", f"{creator} {source_name}".casefold()).strip("_")


def find_entry(project: Path, creator: str, source_name: str) -> Path | None:
    path = project / "attribution" / "sources" / f"{entry_id(creator, source_name)}.tres"
    return path if path.is_file() else None


def extend_assets_used(path: Path, new_assets: list[str]) -> str:
    text = path.read_text()
    match = _ASSETS.search(text)
    if match is None:
        raise RuntimeError(f"no assets_used array in {path} -- refusing to guess")

    current = re.findall(r'"([^"]*)"', match.group(1))
    additions = [a for a in new_assets if a not in current]
    if not additions:
        return f"{new_assets} already listed in {path.name} -- nothing added"

    joined = ", ".join(f'"{a}"' for a in current + additions)
    text = text[:match.start()] + f"assets_used = PackedStringArray({joined})" \
        + text[match.end():]
    path.write_text(text)
    return f"added {additions} to {path.name}"


def new_entry_text(**fields) -> str:
    required = bool(fields.get("attribution_required"))
    notice = fields.get("required_notice", "")
    if required and not notice:
        raise ValueError(
            "attribution_required without a required_notice -- generate_credits.gd "
            "fails closed on exactly this, so it is refused here instead")
    assets = ", ".join(f'"{a}"' for a in fields.get("assets_used", []))
    return ENTRY_TEMPLATE.format(
        entry_id=fields["entry_id"], creator=fields["creator"],
        source_name=fields["source_name"], source_version=fields.get("source_version", ""),
        creator_url=fields.get("creator_url", ""), source_url=fields.get("source_url", ""),
        license_name=fields.get("license_name", ""),
        license_url=fields.get("license_url", ""),
        license_file=fields.get("license_file", ""),
        attribution_required="true" if required else "false",
        required_notice=notice, assets=assets)


def copy_license_text(pack: Path, project: Path, filename: str) -> Path | None:
    """A link can rot; a compliance review must be answerable offline."""
    for name in ("License.txt", "LICENSE", "LICENSE.txt", "license.txt"):
        src = pack / name
        if src.is_file():
            dest = project / "assets" / "licenses" / filename
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)
            return dest
    return None


def selftest_cases(c) -> None:
    import tempfile
    c.eq(entry_id("Quaternius", "Ultimate Animated Animals"),
         "quaternius_ultimate_animated_animals", "entry id is creator_source, snake case")
    c.eq(entry_id("Quaternius", "Farm Buildings"), "quaternius_farm_buildings",
         "matches the existing on-disk naming")

    with tempfile.TemporaryDirectory() as td:
        proj = Path(td) / "project"
        sources = proj / "attribution" / "sources"
        sources.mkdir(parents=True)
        existing = sources / "quaternius_farm_buildings.tres"
        existing.write_text(
            '[gd_resource type="Resource" script_class="AttributionEntry" '
            'load_steps=2 format=3]\n\n'
            '[ext_resource type="Script" path="res://attribution/attribution_entry.gd" id="1_entry"]\n\n'
            '[resource]\nscript = ExtResource("1_entry")\n'
            'id = "quaternius_farm_buildings"\ncreator = "Quaternius"\n'
            'source_name = "Farm Buildings"\n'
            'assets_used = PackedStringArray("Barn", "Silo")\n'
            'per_file_licensing = false\n')

        c.eq(find_entry(proj, "Quaternius", "Farm Buildings"), existing,
             "an existing pack entry is found")
        c.eq(find_entry(proj, "Quaternius", "Nothing Like This"), None,
             "an unknown pack has no entry")

        summary = extend_assets_used(existing, ["Windmill"])
        text = existing.read_text()
        c.check('PackedStringArray("Barn", "Silo", "Windmill")' in text,
                "assets_used extended in order")
        c.check("Windmill" in summary, "summary names what was added")

        again = extend_assets_used(existing, ["Windmill"])
        c.eq(existing.read_text().count("Windmill"), 1, "extending twice is idempotent")
        c.check("already listed" in again, "repeat extend says so")

        entry = new_entry_text(
            entry_id="sherkiz_otter", creator="Sherkiz", source_name="Otter",
            source_version="2026", creator_url="https://example.invalid",
            source_url="https://example.invalid", license_name="CC BY 4.0",
            license_url="https://creativecommons.org/licenses/by/4.0/",
            license_file="res://assets/licenses/Sherkiz_Otter_License.txt",
            attribution_required=True, required_notice="Otter by Sherkiz (CC BY 4.0)",
            assets_used=["Otter"])
        c.check('script_class="AttributionEntry"' in entry, "entry names its script class")
        c.check("attribution_required = true" in entry, "CC BY sets the obligation flag")
        c.check('required_notice = "Otter by Sherkiz (CC BY 4.0)"' in entry,
                "notice present -- generate_credits.gd fails closed without it")
        c.check('assets_used = PackedStringArray("Otter")' in entry, "assets listed")

        pack = Path(td) / "pack"; pack.mkdir()
        (pack / "License.txt").write_text("CC0 text here")
        dest = copy_license_text(pack, proj, "Quaternius_Test_License.txt")
        c.check(dest is not None and dest.is_file(), "licence text copied into the project")
        c.eq(dest.read_text(), "CC0 text here", "copied verbatim")
        c.eq(copy_license_text(Path(td) / "nopack", proj, "x.txt"), None,
             "a pack with no licence file yields None, not a crash")
