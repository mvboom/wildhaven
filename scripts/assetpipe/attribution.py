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

from assetpipe import audit

_SNAKE = re.compile(r"[^a-z0-9]+")
_ASSETS = re.compile(r"^assets_used = PackedStringArray\((.*)\)$", re.MULTILINE)

# Pack FOLDER names on disk carry tails that entry ids never do:
#   "Ultimate Animated Animals - July 2021"                    -> a release-date tail
#   "Farm Buildings - Sept 2018-20260723T015504Z-1-001"        -> both, the second being
#                                                                 a Google Drive export stamp
# The real entries are quaternius_ultimate_animated_animals.tres and
# quaternius_farm_buildings.tres, so the raw folder name never matched anything.
_DRIVE_SUFFIX = re.compile(r"-\d{8}T\d{6}Z-\d+-\d+$")
_MONTHS = ("jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|"
           "aug|august|sep|sept|september|oct|october|nov|november|dec|december")
_DATE_SUFFIX = re.compile(rf"\s*-\s*(?:{_MONTHS})\.?\s+\d{{4}}$", re.IGNORECASE)


class AmbiguousEntry(RuntimeError):
    """Several attribution entries could be the pack's. Never guessed.

    Picking one would silently credit the wrong source, which is the one failure mode
    attribution exists to prevent, so the candidates are named and the run halts.
    """


def normalize_pack_name(name: str) -> str:
    """A pack folder name reduced to the form its attribution entry id is built from."""
    previous = None
    while previous != name:
        previous = name
        name = _DRIVE_SUFFIX.sub("", name).rstrip()
        name = _DATE_SUFFIX.sub("", name).rstrip()
    return name


def license_filename(creator: str, source_name: str) -> str:
    """Bare filename for the pack's preserved licence text.

    Mirrors the naming already on disk -- project/assets/licenses/ holds
    Quaternius_UltimateAnimatedAnimals_License.txt and its two siblings -- so a pipeline
    run extends the existing convention rather than starting a second one.
    """
    words = re.findall(r"[A-Za-z0-9]+", normalize_pack_name(source_name))
    pack = "".join(w[:1].upper() + w[1:] for w in words)
    creator_part = "".join(re.findall(r"[A-Za-z0-9]+", creator))
    return f"{creator_part}_{pack}_License.txt"

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
support_url = "{support_url}"
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
    """Locate the pack's entry, tolerating the tails real folder names carry.

    Three passes, narrowest first:
      1. the id built from the name as given -- what a caller passing a clean pack name gets;
      2. the id built from the normalised name -- strips the release-date and Drive-export
         tails, which is what turns "Ultimate Animated Animals - July 2021" into the real
         quaternius_ultimate_animated_animals.tres;
      3. a segment-anchored PREFIX match against the ids actually on disk -- catches the
         decorated tails normalisation cannot enumerate, e.g. the folder
         "Stylized Nature MegaKit[Standard](1)" against quaternius_stylized_nature_megakit.

    Two or more prefix matches is a halt, not a coin flip.
    """
    sources = project / "attribution" / "sources"
    for candidate in (source_name, normalize_pack_name(source_name)):
        path = sources / f"{entry_id(creator, candidate)}.tres"
        if path.is_file():
            return path

    if not sources.is_dir():
        return None
    derived = entry_id(creator, normalize_pack_name(source_name))
    # The trailing "_" makes this a SEGMENT prefix: an id must end where a word ends in
    # the derived id, so quaternius_farm cannot claim quaternius_farm_buildings' pack.
    matches = sorted(p for p in sources.glob("*.tres")
                     if derived.startswith(p.stem + "_"))
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        raise AmbiguousEntry(
            f"pack folder {source_name!r} (id {derived!r}) prefix-matches "
            f"{len(matches)} attribution entries: {[p.name for p in matches]}. "
            f"Crediting the wrong source is worse than halting -- pick one by hand.")
    return None


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
        support_url=fields.get("support_url", ""),
        attribution_required="true" if required else "false",
        required_notice=notice, assets=assets)


def copy_license_text(pack: Path, project: Path, filename: str) -> Path | None:
    """A link can rot; a compliance review must be answerable offline.

    `filename` must be a BARE name. This writes a compliance record, so a path separator
    or an absolute path is refused rather than silently placing a licence file outside
    project/assets/licenses/ -- verified escapable otherwise: "../../../x.txt" wrote
    three levels above the destination, and an absolute path ignored it entirely.
    """
    if not filename or Path(filename).name != filename:
        raise ValueError(
            f"licence filename must be a bare name with no path separator, "
            f"got {filename!r}")
    # audit.license_files(), not a second hardcoded name list: this preserves the very file
    # the audit gate cleared the pack on, and a private copy of the search would go stale the
    # moment that one changed -- which it did, when nested Drive-export packs started being
    # searched. (Its own list was already one name short of LICENSE_FILENAMES.)
    for src in audit.license_files(pack):
        dest = project / "assets" / "licenses" / filename
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
        return dest
    return None


class UnautomatableLicence(RuntimeError):
    """The pack's licence was cleared, but its OBLIGATIONS cannot be read off the file.

    Clearing a licence and stating what it requires are different questions. The audit
    gate answers the first from a text match; the second decides what must appear in
    CREDITS.md, and getting it wrong is a compliance failure rather than a bad guess.
    Only licences in AUTOMATABLE_LICENCES answer both from the file itself.
    """


# A licence belongs here only if the pack's own licence text states the obligation, so
# nothing is inferred. CC0 does: it requires no attribution, which is why every
# quaternius_*.tres on disk carries attribution_required = false. A Synty store EULA
# does not -- its terms live in a contract the pack does not ship, so it is refused.
AUTOMATABLE_LICENCES = {
    "CC0-1.0": {
        "license_name": "CC0 1.0 Universal (CC0 1.0) Public Domain Dedication",
        "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
        "attribution_required": False,
        "required_notice": "",
    },
}

_URL = re.compile(r"https?://[^\s\"'<>)]+")


def support_url_of(pack: Path) -> str:
    """The support link the pack's licence text asks for, if it names one.

    quaternius_ultimate_animated_animals.tres records its Patreon "because the pack's
    License.txt asks for it, not because anything requires it" -- so this reads the same
    file rather than hardcoding a creator's URL.
    """
    for name in ("License.txt", "LICENSE", "LICENSE.txt", "license.txt"):
        path = pack / name
        if path.is_file():
            for url in _URL.findall(path.read_text(errors="ignore")):
                if "patreon.com" in url:
                    return url.rstrip(".,")
            return ""
    return ""


def new_entry_for_pack(project: Path, pack: Path, creator: str, license_id: str,
                       license_evidence: str, assets: list[str]) -> Path:
    """Author the pack's AttributionEntry from the licence the audit gate already cleared.

    Stage 2 refuses to import anything whose licence it cannot clear from the pack's own
    License.txt. Once that gate passes, using the asset and recording where it came from
    are the same decision -- so leaving the entry to a later hand-edit shipped art with
    no credit. Refuses to touch an entry that exists (extend_assets_used is that path)
    and refuses any licence whose obligations are not stated by the file.
    """
    terms = AUTOMATABLE_LICENCES.get(license_id)
    if terms is None:
        raise UnautomatableLicence(
            f"licence {license_id or '(none cleared)'!r} for pack {pack.name!r}: this "
            f"pipeline generates an entry only when the pack's own licence text states "
            f"the attribution obligation, and this one does not. Author "
            f"project/attribution/sources/{entry_id(creator, normalize_pack_name(pack.name))}"
            f".tres by hand -- attribution_entry.gd's doc comment gives the shape.")

    ident = entry_id(creator, normalize_pack_name(pack.name))
    path = project / "attribution" / "sources" / f"{ident}.tres"
    if path.exists():
        raise FileExistsError(
            f"{path} already exists -- extend its assets_used instead of regenerating it")

    text = new_entry_text(
        entry_id=ident, creator=creator, source_name=normalize_pack_name(pack.name),
        source_version="", creator_url="", source_url="",
        license_name=terms["license_name"], license_url=terms["license_url"],
        license_file=f"res://assets/licenses/{license_filename(creator, pack.name)}",
        support_url=support_url_of(pack),
        attribution_required=terms["attribution_required"],
        required_notice=terms["required_notice"], assets_used=assets)
    # The audit evidence, so a compliance review can retrace the clearance without
    # re-running the pipeline, and the standing instruction every hand-written entry
    # carries: extend this one, never open a second for the same pack.
    text = text.replace(
        'notes = "Added by scripts/asset_pipeline.py."',
        f'notes = "Generated by scripts/asset_pipeline.py from the pack\'s own licence '
        f'text: {license_evidence}. creator_url/source_url are blank -- the licence file '
        f'does not state them, and inventing a URL in a compliance record is worse than '
        f'leaving it empty. As each further model from this pack is imported, append its '
        f'name to assets_used -- do NOT create a second entry for this pack."')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path


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

        # Two entries that both prefix-match must halt rather than pick one.
        (sources / "quaternius_farm.tres").write_text("id = \"quaternius_farm\"\n")
        ambiguous = False
        try:
            find_entry(proj, "Quaternius", "Farm Buildings Extra")
        except AmbiguousEntry as exc:
            ambiguous = ("quaternius_farm.tres" in str(exc)
                         and "quaternius_farm_buildings.tres" in str(exc))
        c.check(ambiguous, "two prefix matches halt with both candidates named")
        (sources / "quaternius_farm.tres").unlink()

    # Suffix normalisation, against the tails the real folders actually carry.
    c.eq(normalize_pack_name("Ultimate Animated Animals - July 2021"),
         "Ultimate Animated Animals", "a release-date tail is stripped")
    c.eq(normalize_pack_name("Farm Buildings - Sept 2018-20260723T015504Z-1-001"),
         "Farm Buildings", "a Drive-export stamp and a date tail are both stripped")
    c.eq(normalize_pack_name("Farm Animals by @Quaternius"),
         "Farm Animals by @Quaternius", "a name with no tail is left alone")
    c.eq(normalize_pack_name("Ultimate Nature Pack - Jun 2019-20260723T015350Z-1-001"),
         "Ultimate Nature Pack", "abbreviated month tail stripped")

    c.eq(license_filename("Quaternius", "Ultimate Animated Animals - July 2021"),
         "Quaternius_UltimateAnimatedAnimals_License.txt",
         "licence filename reproduces the name already in project/assets/licenses/")
    c.eq(license_filename("Quaternius", "Animated Men Characters - Feb 2019-20260723T015429Z-1-001"),
         "Quaternius_AnimatedMenCharacters_License.txt",
         "licence filename matches the second real file on disk")
    c.check(Path(license_filename("Quaternius", "../../../etc")).name
            == license_filename("Quaternius", "../../../etc"),
            "licence filename is always bare -- copy_license_text refuses anything else")

    # REGRESSION, whole-branch review CRITICAL 2: resume() looked the entry up from the
    # raw pack FOLDER name, which matched nothing on disk, so every real run halted at
    # stage 9 after the token spend. These are the actual folders and the actual entries.
    real_project = Path("project")
    if (real_project / "attribution" / "sources").is_dir():
        for folder, expected in (
            ("Ultimate Animated Animals - July 2021",
             "quaternius_ultimate_animated_animals.tres"),
            ("Farm Buildings - Sept 2018-20260723T015504Z-1-001",
             "quaternius_farm_buildings.tres"),
            ("Stylized Nature MegaKit[Standard](1)",
             "quaternius_stylized_nature_megakit.tres"),
            ("Nature Crops Pack - Jan 2020-20260723T015311Z-1-001",
             "quaternius_nature_crops_pack.tres"),
            ("Textured Stylized Trees - May 2020-20260723T015323Z-1-001",
             "quaternius_textured_stylized_trees.tres"),
            ("Ultimate Fantasy RTS - Aug 2022-20260723T014914Z-1-001",
             "quaternius_ultimate_fantasy_rts.tres"),
            ("Ultimate Nature Pack - Jun 2019-20260723T015350Z-1-001",
             "quaternius_ultimate_nature_pack.tres"),
            ("Animated Men Characters - Feb 2019-20260723T015429Z-1-001",
             "quaternius_animated_men_characters.tres"),
            ("Animated Women Characters - Feb 2019-20260723T015412Z-1-001",
             "quaternius_animated_women_characters.tres"),
        ):
            found = find_entry(real_project, "Quaternius", folder)
            c.eq(found.name if found else None, expected,
                 f"real pack folder {folder!r} resolves to its real entry")
        c.eq(find_entry(real_project, "Quaternius", "Medieval Village Pack - Dec 2020"), None,
             "a real pack with no entry on disk still yields None, not a wrong guess")
    else:
        c.check(True, "real-entry resolution check skipped, project/ not on this path")

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

        # Filename validation: bare names are accepted
        dest2 = copy_license_text(pack, proj, "Another_Test_License.txt")
        c.check(dest2 is not None and dest2.is_file(),
                "bare filename still copies successfully")

        # Path traversal is rejected
        try:
            copy_license_text(pack, proj, "../escape.txt")
            c.check(False, "path traversal ../escape.txt should raise ValueError")
        except ValueError as e:
            c.check("bare name" in str(e), "path traversal raises ValueError")
            escape_parent = proj / "attribution"
            c.check(not (escape_parent / "escape.txt").is_file(),
                    "no file created outside licenses directory on path traversal")

        # Absolute path is rejected
        try:
            copy_license_text(pack, proj, "/tmp/absolute.txt")
            c.check(False, "absolute path /tmp/absolute.txt should raise ValueError")
        except ValueError as e:
            c.check("bare name" in str(e), "absolute path raises ValueError")

        # Empty filename is rejected
        try:
            copy_license_text(pack, proj, "")
            c.check(False, "empty filename should raise ValueError")
        except ValueError as e:
            c.check("bare name" in str(e), "empty filename raises ValueError")

    # --- authoring a NEW entry from the audited licence ----------------------
    # Stage 2 already CLEARS the licence from the pack's own License.txt before a single
    # byte is imported; refusing to record what that gate accepted left a pack in the
    # game with no credit at all. So the entry is generated from that same evidence --
    # but only for a licence whose obligations the file itself states.
    with tempfile.TemporaryDirectory() as td:
        proj = Path(td) / "project"
        (proj / "attribution" / "sources").mkdir(parents=True)
        pack = Path(td) / "Farm Animals by @Quaternius"
        pack.mkdir()
        (pack / "License.txt").write_text(
            "Farm Animals Pack by Quaternius\n"
            "Consider supporting me on Patreon, even $1 helps me a lot!\n"
            "https://www.patreon.com/quaternius\n"
            "License:\nCC0 1.0 Universal (CC0 1.0) \nPublic Domain Dedication\n"
            "https://creativecommons.org/publicdomain/zero/1.0/\n")

        written = new_entry_for_pack(proj, pack, "Quaternius", "CC0-1.0",
                                     "License.txt: matched 'cc0'", ["Pig"])
        c.eq(written.name, "quaternius_farm_animals_by_quaternius.tres",
             "the entry lands at the id find_entry looks for")
        c.eq(find_entry(proj, "Quaternius", pack.name), written,
             "and find_entry now resolves the pack it just refused")

        text = written.read_text()
        c.check('script_class="AttributionEntry"' in text, "a real AttributionEntry")
        c.check('license_name = "CC0 1.0 Universal' in text, "the cleared licence, named")
        c.check("creativecommons.org/publicdomain/zero/1.0" in text, "with its url")
        c.check("attribution_required = false" in text,
                "CC0 carries no obligation -- generate_credits.gd fails closed otherwise")
        c.check('required_notice = ""' in text, "and so no notice")
        c.check('assets_used = PackedStringArray("Pig")' in text, "the asset is listed")
        c.check("patreon.com/quaternius" in text,
                "the support url the pack's own licence file asks for")
        c.check("Quaternius_FarmAnimalsByQuaternius_License.txt" in text,
                "license_file points at the preserved text, not just a url")
        c.check("License.txt: matched 'cc0'" in text,
                "the audit evidence travels with the entry, so a review can retrace it")

        # Extending is still the common path: an entry that exists is never rewritten.
        overwritten = False
        try:
            new_entry_for_pack(proj, pack, "Quaternius", "CC0-1.0", "e", ["Cow"])
        except FileExistsError:
            overwritten = True
        c.check(overwritten, "an existing entry is never regenerated over")
        c.check("Cow" not in written.read_text(), "and its assets_used is untouched")

        # A licence whose obligations are not stated by the file is NOT automated.
        synty = Path(td) / "Synty SIMPLE Pack"; synty.mkdir()
        refused = ""
        try:
            new_entry_for_pack(proj, synty, "Synty", "Synty Store EULA (SIMPLE)", "e", ["X"])
        except UnautomatableLicence as exc:
            refused = str(exc)
        c.check("Synty Store EULA (SIMPLE)" in refused,
                "a store EULA is named as the reason it cannot be generated")
        c.check("obligation" in refused.lower(),
                "because the obligation is the thing that cannot be derived")

        blank = ""
        try:
            new_entry_for_pack(proj, pack, "Quaternius", "", "e", ["X"])
        except UnautomatableLicence as exc:
            blank = str(exc)
        c.check(blank != "", "an uncleared licence never reaches entry generation")

    c.eq(sorted(AUTOMATABLE_LICENCES), ["CC0-1.0"],
         "exactly one licence family is safe to record without a human reading it")
