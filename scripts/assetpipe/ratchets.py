"""The roster ratchets: guards that fire because content was ADDED, not because it broke.

Two tests in this project pin a number that only changes when a human decides to ship new
content -- `test_attribution.gd`'s source count ("it is supposed to fail when an entry
lands, so that adding a source is a decision and not a side effect") and
`test_resident_wander.gd`'s EXPECTED_CLIPS table, which pins every roster species' exact
clip names. Both are deliberate. Neither should be discovered as an unexplained red suite
at stage 10 after the token spend.

So the pipeline ASKS them at the checkpoint instead, with the values already measured --
the clip names come from AnimalClips running against the real imported model, not from a
guess -- and applies the human's ruling to the test files before the suite runs. The gate
is unchanged; what changes is that it is a question with an answer rather than a failure
with a diagnosis. Ruling no leaves the guard to fail, on purpose.

Only the two ratchets that fire when a SPECIES or a SOURCE is added live here. The rest of
the suite's EXPECTED_* constants are per-asset (each animation test's own clip count) and
are already written by godot.write_import_test; test_fact_card.gd sizes itself off the
live roster and pins nothing.
"""

from __future__ import annotations

import re
from pathlib import Path

ATTRIBUTION_TEST = "test_attribution.gd"
WANDER_TEST = "test_resident_wander.gd"

# The checkpoint fields these become, and how the prompt parses an answer to each.
NEW_SOURCE_FIELD = "ratchet_new_source"
CLIP_ROW_FIELD = "ratchet_clip_row"
FIELD_KINDS = {NEW_SOURCE_FIELD: "bool", CLIP_ROW_FIELD: "str"}

_COUNT = re.compile(r'check_eq\(entries\.size\(\), (\d+), "(\d+) attribution sources on disk"\)')
_TABLE = re.compile(r"(const EXPECTED_CLIPS: Dictionary = \{\n)(.*?)(^\}$)",
                    re.MULTILINE | re.DOTALL)


def row_literal(row: dict) -> str:
    """One EXPECTED_CLIPS value, in the shape the table already uses."""
    flavors = ", ".join(f'"{f}"' for f in row.get("idle_flavors", []))
    return (f'{{"idle": "{row.get("idle", "")}", "walk": "{row.get("walk", "")}", '
            f'"run": "{row.get("run", "")}", "idle_flavors": [{flavors}]}}')


def attribution_count(text: str) -> int | None:
    match = _COUNT.search(text)
    return int(match.group(1)) if match else None


def set_attribution_count(text: str, count: int) -> str:
    """Both the asserted number AND the message that states it -- updating only the first
    leaves a passing test whose label is a lie."""
    return _COUNT.sub(
        f'check_eq(entries.size(), {count}, "{count} attribution sources on disk")',
        text, count=1)


def clips_pinned(text: str, ident: str) -> bool:
    return re.search(rf'^\t"{re.escape(ident)}":', text, re.MULTILINE) is not None


def add_clips_row(text: str, ident: str, literal: str) -> str:
    """Append the species to EXPECTED_CLIPS, at the end of the table as it already grew."""
    match = _TABLE.search(text)
    if match is None:
        raise RuntimeError(f"no EXPECTED_CLIPS table in the text -- refusing to guess")
    body = match.group(2).rstrip("\n")
    return (text[:match.start()] + match.group(1) + body + "\n"
            + f'\t"{ident}": {literal},\n' + match.group(3) + text[match.end():])


def apply(tests_dir: Path, sources_dir: Path, ident: str,
          rulings: dict) -> list[str]:
    """Carry out what the human ruled at the checkpoint. Returns one summary line each.

    The attribution count is set to the number of entries actually on disk rather than
    incremented, so a re-run, a hand-added entry, or a run that created none all land on
    the truth instead of drifting one at a time.
    """
    out: list[str] = []

    if rulings.get(NEW_SOURCE_FIELD):
        path = tests_dir / ATTRIBUTION_TEST
        if not path.is_file():
            out.append(f"WARNING: {ATTRIBUTION_TEST} not found -- source count not updated")
        else:
            text = path.read_text()
            actual = len(list(sources_dir.glob("*.tres")))
            current = attribution_count(text)
            if current is None:
                out.append(f"WARNING: no source-count assertion in {ATTRIBUTION_TEST}")
            elif current == actual:
                out.append(f"{ATTRIBUTION_TEST} already counts {actual} sources")
            else:
                path.write_text(set_attribution_count(text, actual))
                out.append(f"{ATTRIBUTION_TEST}: source count {current} -> {actual}")
    elif NEW_SOURCE_FIELD in rulings:
        out.append(f"{ATTRIBUTION_TEST} NOT updated -- you ruled no, so its source-count "
                   f"guard will fail at stage 10")

    literal = rulings.get(CLIP_ROW_FIELD)
    if literal:
        path = tests_dir / WANDER_TEST
        if not path.is_file():
            out.append(f"WARNING: {WANDER_TEST} not found -- clip row not pinned")
        else:
            text = path.read_text()
            if clips_pinned(text, ident):
                out.append(f"{WANDER_TEST} already pins `{ident}`")
            else:
                path.write_text(add_clips_row(text, ident, literal))
                out.append(f"{WANDER_TEST}: pinned `{ident}` as {literal}")
    elif CLIP_ROW_FIELD in rulings:
        out.append(f"{WANDER_TEST} NOT updated -- you ruled no clip row, so its roster "
                   f"guard will fail at stage 10")
    return out


def selftest_cases(c) -> None:
    import tempfile

    c.eq(row_literal({"idle": "Idle", "walk": "Walk", "run": "Run", "idle_flavors": []}),
         '{"idle": "Idle", "walk": "Walk", "run": "Run", "idle_flavors": []}',
         "a measured row renders in the table's own shape")
    c.eq(row_literal({"idle": "Idle", "walk": "Walk", "run": "Gallop",
                      "idle_flavors": ["Eating", "Idle_2"]}),
         '{"idle": "Idle", "walk": "Walk", "run": "Gallop", '
         '"idle_flavors": ["Eating", "Idle_2"]}',
         "flavours are quoted individually")

    attr = ('\tcheck_eq(entries.size(), 12, "12 attribution sources on disk")\n'
            '\tcheck_eq(binding.size(), 1, "exactly 1 source carries a binding obligation")\n')
    c.eq(attribution_count(attr), 12, "the current count is read from the assertion")
    bumped = set_attribution_count(attr, 13)
    c.check('check_eq(entries.size(), 13, "13 attribution sources on disk")' in bumped,
            "both the number and the message it states are updated")
    c.check("binding.size(), 1" in bumped, "the neighbouring count is untouched")
    c.eq(attribution_count("nothing here"), None, "a file with no such assertion reads None")

    table = ('const EXPECTED_CLIPS: Dictionary = {\n'
             '\t"fox": {"idle": "Idle"},\n'
             '\t"shiba_inu": {"idle": "Idle"},\n'
             '}\n\nconst WIDE: int = 8\n')
    c.check(not clips_pinned(table, "pig"), "a new species is not yet pinned")
    c.check(clips_pinned(table, "fox"), "an existing one is")
    c.check(not clips_pinned(table, "ox"),
            "the match is anchored -- `ox` must not claim `fox`'s row")

    grown = add_clips_row(table, "pig", '{"idle": "Idle", "walk": "Walk"}')
    c.check('\t"pig": {"idle": "Idle", "walk": "Walk"},\n}' in grown,
            "the row lands at the end of the table, inside the braces")
    c.check(clips_pinned(grown, "pig"), "and reads back as pinned")
    c.check("const WIDE: int = 8" in grown, "what follows the table is untouched")
    c.eq(grown.count('"shiba_inu"'), 1, "no existing row is disturbed")

    raised = False
    try:
        add_clips_row("no table here", "pig", "{}")
    except RuntimeError:
        raised = True
    c.check(raised, "a file with no EXPECTED_CLIPS table raises rather than guessing")

    with tempfile.TemporaryDirectory() as td:
        tests = Path(td) / "tests"; tests.mkdir()
        sources = Path(td) / "sources"; sources.mkdir()
        for i in range(13):
            (sources / f"entry_{i}.tres").write_text("x")
        (tests / ATTRIBUTION_TEST).write_text(attr)
        (tests / WANDER_TEST).write_text(table)

        lines = apply(tests, sources, "pig",
                      {NEW_SOURCE_FIELD: True,
                       CLIP_ROW_FIELD: '{"idle": "Idle", "walk": "Walk"}'})
        c.check(any("12 -> 13" in l for l in lines), "the count is set to what is on disk")
        c.check(any("pinned `pig`" in l for l in lines), "and the clip row is pinned")
        c.check(clips_pinned((tests / WANDER_TEST).read_text(), "pig"), "written to the file")

        # Idempotent: a second pass over the same tree changes nothing and says so.
        again = apply(tests, sources, "pig",
                      {NEW_SOURCE_FIELD: True,
                       CLIP_ROW_FIELD: '{"idle": "Idle", "walk": "Walk"}'})
        c.check(any("already counts 13" in l for l in again), "the count is already right")
        c.check(any("already pins" in l for l in again), "the row is already there")
        c.eq((tests / WANDER_TEST).read_text().count('"pig"'), 1, "no duplicate row")

        # Ruling NO leaves the guard to fail, and says so rather than going quiet.
        declined = apply(tests, sources, "goose",
                         {NEW_SOURCE_FIELD: False, CLIP_ROW_FIELD: ""})
        c.check(any("NOT updated" in l and "ruled no" in l for l in declined),
                "declining the source ratchet is reported, not silent")
        c.check(any("NOT updated" in l for l in declined if WANDER_TEST in l),
                "and so is declining the clip row")
        c.check(not clips_pinned((tests / WANDER_TEST).read_text(), "goose"),
                "nothing was written for the declined species")

        # A ratchet that does not apply to this run contributes nothing at all.
        c.eq(apply(tests, sources, "pig", {}), [],
             "a run with no ratchet decisions applies none")

    # The real files must still match the patterns, or this is text-matching a fiction.
    real = Path("project/tests")
    if (real / ATTRIBUTION_TEST).is_file():
        c.check(attribution_count((real / ATTRIBUTION_TEST).read_text()) is not None,
                f"the real {ATTRIBUTION_TEST} carries a readable source count")
        wander = (real / WANDER_TEST).read_text()
        c.check(_TABLE.search(wander) is not None,
                f"the real {WANDER_TEST} carries a matchable EXPECTED_CLIPS table")
        c.check(clips_pinned(wander, "fox"), "and fox reads as pinned in it")
    else:
        c.check(True, "real-test checks skipped, project/ not on this path")
