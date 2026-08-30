"""Derive the species roster from the game's own data instead of restating it.

Both GER pipelines (`fact_card_pipeline.py`, `style_guide_pipeline.py`) used to carry a
hand-maintained `ROSTER` literal duplicating `project/data/animals/*.tres`. That duplicate
had to be edited by hand for every species added -- and the fact-card evaluator's
closed-predation-graph check ("a card must never name another roster species") is only as
complete as that list, so a stale ROSTER silently WEAKENED a content-safety gate rather
than failing loudly. Deriving it removes the edit and closes the gate.

Derivation was verified to reproduce both literals exactly before they were removed: 12
species, with identical `display_name`, `habitat_needs` and `avoids` in every case.

Run `python3 scripts/roster_data.py --selftest` to check this module on its own.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ANIMALS_DIR = Path("project") / "data" / "animals"
BUILDINGS_DIR = Path("project") / "data" / "buildings"
DISPLACEMENT_COPY = Path("project") / "scripts" / "ui" / "displacement_copy.gd"

# The marker the style-guide pipeline writes beside copy it generated but a human has not
# yet reviewed. CONVENTION: sign-off must REMOVE this marker. `has_verified_copy` treats a
# line still carrying it as regenerable, so a marker left in place after review would let
# the pipeline overwrite copy you had actually approved.
AWAITING_MARKER = "AWAITING CONTENT-WRITER SIGN-OFF"


@dataclass
class RosterSpecies:
    """One roster entry. `tags` is `habitat_needs`; the fact-card pipeline ignores it."""

    id: str
    display_name: str
    tags: list = field(default_factory=list)
    avoids: list = field(default_factory=list)


def _scalar(text: str, field_name: str) -> str | None:
    match = re.search(rf'^{field_name} = "([^"]*)"', text, re.MULTILINE)
    return match.group(1) if match else None


def _string_array(text: str, field_name: str) -> list:
    match = re.search(
        rf"^{field_name} = Array\[String\]\(\[(.*?)\]\)", text, re.MULTILINE
    )
    return re.findall(r'"([^"]+)"', match.group(1)) if match else []


def _parse_tres(path: Path) -> RosterSpecies | None:
    text = path.read_text()
    ident = _scalar(text, "id")
    display = _scalar(text, "display_name")
    if not ident or not display:
        return None
    return RosterSpecies(
        id=ident,
        display_name=display,
        tags=_string_array(text, "habitat_needs"),
        avoids=_string_array(text, "avoids"),
    )


def floor_species_ids(repo_root: Path) -> list:
    """The floor species, read from the game rather than restated here.

    `displacement_copy.gd` owns this list because a floor species falling through to
    WARN_GENERIC is, in its own words, "a defect worth failing a test over". Cross-reading
    it means this module and the game cannot drift apart.
    """
    path = repo_root / DISPLACEMENT_COPY
    if not path.is_file():
        return []
    match = re.search(
        r"^const FLOOR_SPECIES_IDS: Array\[String\] = \[(.*?)\]",
        path.read_text(),
        re.MULTILINE,
    )
    return re.findall(r'"([^"]+)"', match.group(1)) if match else []


def _load_dir(repo_root: Path, rel_dir: Path) -> dict:
    directory = repo_root / rel_dir
    out: dict = {}
    if not directory.is_dir():
        return out
    for path in sorted(directory.glob("*.tres")):
        entry = _parse_tres(path)
        if entry is not None:
            out[entry.id] = entry
    return out


def load_roster(repo_root: Path) -> dict:
    """Every animal in `project/data/animals/`, keyed by id.

    Raises when a floor species is missing. That is the loud failure the old hardcode
    could not give us: a wrong path or an unreadable directory would otherwise shrink the
    closed-predation-graph check to whatever happened to parse, and the fact-card
    evaluator would go on reporting PASS with a smaller graph than it thinks it has.
    """
    roster = _load_dir(repo_root, ANIMALS_DIR)
    missing = [s for s in floor_species_ids(repo_root) if s not in roster]
    if missing:
        raise RuntimeError(
            f"derived roster is missing floor species {missing} -- refusing to run with "
            f"an incomplete predation graph. Looked in {repo_root / ANIMALS_DIR}, found "
            f"{sorted(roster) or 'nothing'}."
        )
    return roster


def load_buildings(repo_root: Path) -> dict:
    """Every placeable in `project/data/buildings/`, keyed by id.

    Used only to resolve a name for `--target building_text`. Buildings carry no `avoids`
    and take no part in the predation graph -- that stays the animal roster, because a
    building's fact card must not name a species either.
    """
    return _load_dir(repo_root, BUILDINGS_DIR)


def has_verified_copy(species_id: str, displacement_copy_path: Path) -> bool:
    """True when this species has displacement copy a human has signed off.

    Three states exist, and only the first is protected:
      - a WARN_ constant with no AWAITING marker -> verified, refuse to overwrite
      - a WARN_ constant still marked AWAITING    -> generated, not yet reviewed, regenerable
      - no WARN_ constant at all                  -> nothing to lose
    """
    if not displacement_copy_path.is_file():
        return False
    match = re.search(
        rf"^const WARN_{re.escape(species_id.upper())}: String = .*$",
        displacement_copy_path.read_text(),
        re.MULTILINE,
    )
    return match is not None and AWAITING_MARKER not in match.group(0)


# ---------------------------------------------------------------------------
# Self-test: no LLM calls, no network. Run directly or from either pipeline.
# ---------------------------------------------------------------------------

def selftest() -> int:
    import tempfile

    ok = True
    lines: list = []

    def check(cond: bool, label: str) -> None:
        nonlocal ok
        if not cond:
            ok = False
        lines.append(f"[{'PASS' if cond else 'FAIL'}] {label}")

    repo = _find_repo_root(Path(__file__).resolve().parent)

    floor = floor_species_ids(repo)
    check(sorted(floor) == ["fox", "human", "rabbit"],
          f"floor species cross-read from displacement_copy.gd (got {floor})")

    roster = load_roster(repo)
    check(len(roster) >= 12, f"roster derived from the data dir ({len(roster)} species)")
    check("fox" in roster and roster["fox"].display_name == "Fox",
          "derived entry carries display_name")
    check(roster.get("fox") is not None and roster["fox"].avoids == ["rabbit"],
          "derived entry carries avoids")
    check(roster.get("human") is not None and roster["human"].display_name == "Villager",
          "human's display_name is Villager, as the .tres says")
    check("house" in roster.get("shiba_inu", RosterSpecies("", "")).tags,
          "derived entry carries habitat_needs as tags")

    with tempfile.TemporaryDirectory() as td:
        fake = Path(td)
        (fake / ANIMALS_DIR).mkdir(parents=True)
        (fake / ANIMALS_DIR / "otter.tres").write_text(
            'id = "otter"\ndisplay_name = "Otter"\n'
            'habitat_needs = Array[String](["water"])\navoids = Array[String]([])\n'
        )
        (fake / DISPLACEMENT_COPY.parent).mkdir(parents=True)
        (fake / DISPLACEMENT_COPY).write_text(
            'const FLOOR_SPECIES_IDS: Array[String] = ["human", "fox", "rabbit"]\n'
        )
        raised = False
        try:
            load_roster(fake)
        except RuntimeError as exc:
            raised = "floor species" in str(exc)
        check(raised, "a roster missing floor species raises rather than running short")

    copy_path = repo / DISPLACEMENT_COPY
    check(has_verified_copy("fox", copy_path),
          "fox's human-verified copy is protected")
    check(not has_verified_copy("horse", copy_path),
          "horse's copy is still AWAITING sign-off, so regenerable")
    check(not has_verified_copy("stag", copy_path),
          "stag has no copy at all, so nothing to protect")
    check(not has_verified_copy("otter", copy_path),
          "an unknown species has nothing to protect")

    buildings = load_buildings(repo)
    check(len(buildings) >= 9, f"buildings derived from the data dir ({len(buildings)})")
    check(buildings.get("well") is not None and buildings["well"].display_name == "Well",
          "building entry carries display_name")

    for line in lines:
        print(line)
    return 0 if ok else 1


def _find_repo_root(start: Path) -> Path:
    marker = Path("project") / "scripts" / "definitions" / "animal_definition.gd"
    for candidate in [start, *start.parents]:
        if (candidate / marker).is_file():
            return candidate
    return start


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        rc = selftest()
        print("ROSTER_DATA SELFTEST " + ("PASSED" if rc == 0 else "FAILED"))
        raise SystemExit(rc)
    print(__doc__)
