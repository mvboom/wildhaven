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
# yet reviewed. CONVENTION: sign-off must REMOVE this marker. `verified_line_types` treats a
# line still carrying it as regenerable, so a marker left in place after review would let
# the pipeline overwrite copy you had actually approved.
AWAITING_MARKER = "AWAITING CONTENT-WRITER SIGN-OFF"

# The constant prefix displacement_copy.gd uses for each Gentle Displacement line type.
# style_guide_pipeline imports this rather than restating it, so the sign-off GATE and the
# WRITER can never disagree about which constant a line type lives in -- the exact class
# of drift that let a per-species gate stand in front of a per-line-type writer.
LINE_TYPE_PREFIX = {"warn": "WARN", "depart": "DEPART", "move": "MOVE"}


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
        raise RuntimeError(
            f"{path} does not exist -- refusing to treat 'no floor list' as 'nothing to "
            f"check'. The floor species are what prove the derived roster is complete; "
            f"without them load_roster cannot tell a full roster from an empty one.")
    # DOTALL as well as MULTILINE: displacement_copy.gd's own header calls itself an
    # interim home for these lines, so the declaration can plausibly be reformatted across
    # lines -- and with a line-bounded `.` that yielded no match and, before the raises
    # below, no floor list and therefore no check at all.
    match = re.search(
        r"^const FLOOR_SPECIES_IDS: Array\[String\] = \[(.*?)\]",
        path.read_text(),
        re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise RuntimeError(
            f"no FLOOR_SPECIES_IDS declaration found in {path} -- refusing to run with "
            f"no floor list, because an unparsed one is indistinguishable from an empty "
            f"one and silently disables the completeness check.")
    ids = re.findall(r'"([^"]+)"', match.group(1))
    if not ids:
        raise RuntimeError(
            f"FLOOR_SPECIES_IDS in {path} parsed EMPTY -- refusing to run, because an "
            f"empty floor list means load_roster would accept ANY roster, including one "
            f"with no species in it at all.")
    return ids


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

    Raises when the roster comes back empty, and when a floor species is missing. That is
    the loud failure the old hardcode could not give us: a wrong path or an unreadable
    directory would otherwise shrink the closed-predation-graph check to whatever happened
    to parse, and the fact-card evaluator would go on reporting PASS with a smaller graph
    than it thinks it has. An EMPTY roster is the worst case of that, not the harmless
    one -- the graph loop iterates nothing, so every card passes -- and the floor-species
    check cannot catch it on its own, because floor_species_ids failing is exactly the
    condition under which the roster is likely to be empty too.
    """
    roster = _load_dir(repo_root, ANIMALS_DIR)
    if not roster:
        raise RuntimeError(
            f"derived roster is EMPTY -- refusing to run with no predation graph at all. "
            f"Looked in {repo_root / ANIMALS_DIR}"
            f"{'' if (repo_root / ANIMALS_DIR).is_dir() else ' (which does not exist)'}. "
            f"Every closed-graph check would pass vacuously against an empty roster.")
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


def verified_line_types(species_id: str, displacement_copy_path: Path,
                        line_types) -> list:
    """Which of `line_types` this species has displacement copy a human has signed off.

    Three states exist PER LINE TYPE, and only the first is protected:
      - a constant with no AWAITING marker -> verified, refuse to overwrite
      - a constant still marked AWAITING   -> generated, not yet reviewed, regenerable
      - no constant at all                 -> nothing to lose

    PER LINE TYPE is the whole point. The predecessor answered one bool per SPECIES from
    `WARN_<ID>` alone, while `style_guide_pipeline.write_displacement_copy` writes
    WARN_/DEPART_/MOVE_ according to `--line-type` (default `all`). Both directions were
    destructive: a species whose DEPART_ and MOVE_ were signed off but whose WARN_ was
    still marked read as "not verified", so a default run OVERWROTE two human-approved
    lines -- exactly the hazard the marker convention exists to prevent; and a species
    whose WARN_ alone was signed off read as "verified", so DEPART_/MOVE_ could never be
    generated at all.

    Returns the verified subset, in `line_types` order, so the caller can regenerate the
    rest and name which ones it left alone.
    """
    if not displacement_copy_path.is_file():
        return []
    text = displacement_copy_path.read_text()
    out: list = []
    for line_type in line_types:
        prefix = LINE_TYPE_PREFIX.get(line_type)
        if prefix is None:
            raise ValueError(
                f"unknown displacement line type {line_type!r} -- expected one of "
                f"{sorted(LINE_TYPE_PREFIX)}")
        match = re.search(
            rf"^const {prefix}_{re.escape(species_id.upper())}: String = .*$",
            text, re.MULTILINE,
        )
        if match is not None and AWAITING_MARKER not in match.group(0):
            out.append(line_type)
    return out


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

    # REGRESSION, review CRITICAL 3: the loud-failure guard silently disabled itself.
    # floor_species_ids returned [] when the file was absent AND when the regex missed,
    # which made load_roster's `missing` list empty -- so it returned whatever it had
    # loaded, INCLUDING {}. An empty ROSTER makes the fact-card evaluator's
    # closed-predation-graph loop iterate nothing, so every card passes the check: the
    # same "silently weakened a content-safety gate" failure the hardcode was removed to
    # fix, reintroduced one level down. All three modes must raise, each naming itself.
    def _raises(fn, needle: str) -> bool:
        try:
            fn()
        except RuntimeError as exc:
            return needle in str(exc)
        return False

    with tempfile.TemporaryDirectory() as td:
        fake = Path(td)
        (fake / DISPLACEMENT_COPY.parent).mkdir(parents=True)
        gd = fake / DISPLACEMENT_COPY

        check(_raises(lambda: floor_species_ids(fake), "does not exist"),
              "an absent displacement_copy.gd raises, naming the missing file")

        gd.write_text("extends Node\n# no floor list here\n")
        check(_raises(lambda: floor_species_ids(fake), "no FLOOR_SPECIES_IDS"),
              "a FLOOR_SPECIES_IDS the regex cannot find raises, naming the declaration")

        gd.write_text("const FLOOR_SPECIES_IDS: Array[String] = []\n")
        check(_raises(lambda: floor_species_ids(fake), "parsed EMPTY"),
              "a floor list that parses empty raises rather than checking nothing")

        # The pattern was MULTILINE but not DOTALL, so reformatting the declaration
        # across lines -- which displacement_copy.gd's own header invites, calling itself
        # an interim home for these lines -- silently yielded no match.
        gd.write_text(
            'const FLOOR_SPECIES_IDS: Array[String] = [\n'
            '\t"human",\n\t"fox",\n\t"rabbit",\n]\n'
        )
        check(sorted(floor_species_ids(fake)) == ["fox", "human", "rabbit"],
              "a multi-line FLOOR_SPECIES_IDS declaration is read, not missed")

        (fake / ANIMALS_DIR).mkdir(parents=True)
        check(_raises(lambda: load_roster(fake), "EMPTY"),
              "an empty animals dir raises rather than returning an empty predation graph")

    copy_path = repo / DISPLACEMENT_COPY
    all_types = list(LINE_TYPE_PREFIX)
    check(verified_line_types("fox", copy_path, all_types) == all_types,
          "fox's human-verified copy is protected, all three line types")
    check(verified_line_types("horse", copy_path, all_types) == [],
          "horse's copy is still AWAITING sign-off, so every line type is regenerable")
    check(verified_line_types("stag", copy_path, all_types) == [],
          "stag has no copy at all, so nothing to protect")
    check(verified_line_types("otter", copy_path, all_types) == [],
          "an unknown species has nothing to protect")
    check(verified_line_types("fox", copy_path, ["move"]) == ["move"],
          "the gate answers only for the line types asked about")

    # REGRESSION, review CRITICAL 2: the gate was per-SPECIES (it inspected WARN_ alone)
    # while the writer is per-LINE-TYPE. Both directions were reproduced against real
    # displacement_copy.gd states, and both are destructive:
    #   - DEPART_/MOVE_ signed off but WARN_ still marked -> the gate said "not verified"
    #     and a default `--line-type all` run OVERWROTE two human-approved lines.
    #   - WARN_ signed off but the others still marked -> the gate said "verified" and the
    #     species was refused entirely, so DEPART_/MOVE_ could never be generated.
    with tempfile.TemporaryDirectory() as td:
        gd = Path(td) / "displacement_copy.gd"
        signed = 'const {name}: String = "human copy."\n'
        marked = ('const {name}: String = "pipeline copy."  '
                  f"# pipeline-generated -- {AWAITING_MARKER}\n")

        gd.write_text(signed.format(name="DEPART_HORSE") +
                      signed.format(name="MOVE_HORSE") +
                      marked.format(name="WARN_HORSE"))
        check(verified_line_types("horse", gd, all_types) == ["depart", "move"],
              "signed-off DEPART_/MOVE_ are protected even while WARN_ is still marked")

        gd.write_text(signed.format(name="WARN_HORSE") +
                      marked.format(name="DEPART_HORSE") +
                      marked.format(name="MOVE_HORSE"))
        check(verified_line_types("horse", gd, all_types) == ["warn"],
              "a signed-off WARN_ does not lock DEPART_/MOVE_ out of regeneration")

        gd.write_text("".join(signed.format(name=f"{p}_HORSE")
                              for p in LINE_TYPE_PREFIX.values()))
        check(verified_line_types("horse", gd, all_types) == all_types,
              "an all-verified species protects every line type")

        gd.write_text("".join(marked.format(name=f"{p}_HORSE")
                              for p in LINE_TYPE_PREFIX.values()))
        check(verified_line_types("horse", gd, all_types) == [],
              "a none-verified species protects nothing")

        check(verified_line_types("horse", Path(td) / "absent.gd", all_types) == [],
              "no displacement_copy.gd at all means nothing to protect")

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
