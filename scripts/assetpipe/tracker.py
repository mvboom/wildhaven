"""content-pipeline-status.md: give a newly imported item a section to be recorded in.

WHY THIS EXISTS. That file is the per-item RECORD, and every downstream writer patches a
section it expects to already exist -- fact_card_pipeline.py:596 looks for
`^### \\`<id>\\`` and, not finding one, reports "tracker not updated" and moves on. Nothing
in the chain ever created that section, so a genuinely new species could not be recorded
by the pipeline that imported it. Stage 7 creates the stub; the field owners fill it.

WHAT IT DOES NOT DO. It writes only the rows stage 7 can state as fact, marks the rest
pending, and NEVER touches a section that already exists -- content-pipeline-status.md's
own rule is that every field has exactly one write-owner, and overwriting a human's row
to "pending" would destroy the record this file exists to keep.
"""

from __future__ import annotations

import re
from pathlib import Path

# The group heading each adapter category's per-item sections live under.
GROUP_HEADINGS = {"animals": "## Roster", "buildings": "## Buildings",
                  "terrain": "## Terrain"}


def section_text(ident: str, display: str, rows: list[tuple[str, str]]) -> str:
    """One `### \`id\` — Display` block, in the table shape every existing section uses."""
    lines = [f"### `{ident}` \u2014 {display}", "", "| Field | Value |", "|---|---|"]
    lines += [f"| `{name}` | {value} |" for name, value in rows]
    return "\n".join(lines) + "\n"


def ensure_section(path: Path, category: str, ident: str, display: str,
                   rows: list[tuple[str, str]]) -> str:
    """Add the item's section if it has none. Returns a summary; never raises.

    Reported rather than raised because this is a RECORD-keeping step: a tracker that
    cannot be updated is worth surfacing, but it is not a reason to abandon an import
    whose asset, data and copy are already on disk.
    """
    if not path.is_file():
        return f"WARNING: {path} not found -- no tracker section created for {ident!r}"

    text = path.read_text()
    if re.search(rf"^### `{re.escape(ident)}`", text, re.MULTILINE):
        return f"`{ident}` already has a section -- left untouched"

    heading = GROUP_HEADINGS.get(category)
    if heading is None:
        return f"WARNING: no group heading known for category {category!r}"
    start = text.find(f"\n{heading}\n")
    if start < 0:
        return (f"WARNING: no {heading!r} heading in {path.name} -- no tracker section "
                f"created for {ident!r}")

    # The group ends at the next `## ` heading, or at end of file for the last group.
    # Sections inside a group are separated by a blank line and the group is closed by a
    # `---` rule, so the insertion point is BEFORE that rule -- inserting after it would
    # put the item under the following heading.
    after = text.find("\n## ", start + len(heading) + 1)
    end = len(text) if after < 0 else after
    body = text[:end]
    rule = re.search(r"\n+---\n+\Z", body)
    if rule is not None:
        end = rule.start()  # an index into `text`: `body` is a prefix of it

    # Exactly one blank line on each side of the new block, matching the spacing every
    # existing section uses -- a record people read should not drift in whitespace.
    block = section_text(ident, display, rows)
    tail = text[end:].lstrip("\n")
    text = (text[:end].rstrip("\n") + "\n\n" + block
            + ("\n" + tail if tail else ""))
    path.write_text(text)
    return f"added a `{ident}` section under {heading}"


def selftest_cases(c) -> None:
    import tempfile

    def doc():
        return (
            "# Content Pipeline Status\n\n"
            "## Roster\n\n"
            "| id | Status |\n|---|---|\n| `fox` | \U0001f6a7 |\n\n"
            "### `fox` — Fox\n\n"
            "| Field | Value |\n|---|---|\n"
            "| `source` | Quaternius |\n"
            "| `copy_content_location` | done |\n\n"
            "---\n\n"
            "## Terrain\n\n"
            "### `grass` — Grass\n\n"
            "| Field | Value |\n|---|---|\n| `source` | Quaternius |\n\n"
            "---\n\n"
            "## Buildings\n\n"
            "### `well` — Well\n\n"
            "| Field | Value |\n|---|---|\n| `source` | Quaternius |\n")

    rows = [("source", "Quaternius, \"Farm Animals\" — CC0-1.0"),
            ("copy_content_location", "pending — stage 8 writes here"),
            ("status", "\U0001f6a7")]

    with tempfile.TemporaryDirectory() as td:
        path = Path(td) / "content-pipeline-status.md"

        path.write_text(doc())
        summary = ensure_section(path, "animals", "pig", "Pig", rows)
        text = path.read_text()
        c.check("### `pig` — Pig" in text, "the new section is created")
        c.check("added" in summary and "pig" in summary, "the summary says what happened")

        # fact_card_pipeline's own patterns must match what we wrote, or the stub is
        # decorative. These are its regexes, transcribed (fact_card_pipeline.py:595, :604).
        section = re.search(r"(^### `pig` .*?\n)(.*?)(?=^### |\Z)", text,
                            re.MULTILINE | re.DOTALL)
        c.check(section is not None, "fact_card_pipeline's section pattern matches it")
        c.check(re.search(r"^\| `copy_content_location` \|.*\|$", section.group(2),
                          re.MULTILINE) is not None,
                "and its copy_content_location row pattern matches too")

        # Placement: inside the right group, and not before an unrelated one.
        c.check(text.index("### `pig`") > text.index("## Roster"),
                "the section lands under its category's heading")
        c.check(text.index("### `pig`") < text.index("## Terrain"),
                "and before the next group begins")
        c.check(text.index("### `fox`") < text.index("### `pig`"),
                "appended after the group's existing items, not ahead of them")
        c.check("\n\n\n" not in text,
                "spacing matches the surrounding sections -- no double blank lines")
        c.check(text.endswith("\n") and not text.endswith("\n\n"),
                "the file still ends with exactly one newline")

        # Idempotency, and the write-owner rule: a second run must not touch the rows.
        before = path.read_text()
        again = ensure_section(path, "animals", "pig", "Pig",
                               [("source", "SOMETHING ELSE")])
        c.eq(path.read_text(), before,
             "an existing section is left exactly as it is -- rows have one write-owner")
        c.check("already" in again, "and the summary says the section was already there")

        # The last group has no following heading to insert before.
        path.write_text(doc())
        ensure_section(path, "buildings", "silo", "Silo", rows)
        text = path.read_text()
        c.check(text.index("### `silo`") > text.index("## Buildings"),
                "the final group appends at end of file")
        c.check(text.index("### `well`") < text.index("### `silo`"),
                "still after the group's existing items")

        # Terrain sits between two groups -- the boundary is the NEXT heading, not the last.
        path.write_text(doc())
        ensure_section(path, "terrain", "clover", "Clover", rows)
        text = path.read_text()
        c.check(text.index("## Terrain") < text.index("### `clover`") < text.index("## Buildings"),
                "a middle group inserts before the group that follows it")

        # A file with no such group is reported, never guessed at.
        path.write_text("# Nothing here\n")
        c.check("WARNING" in ensure_section(path, "animals", "pig", "Pig", rows),
                "a missing group heading is reported, not invented")
        c.eq(path.read_text(), "# Nothing here\n", "and nothing is written")

        # A missing file is reported rather than created: this is the project's record,
        # and conjuring one would hide that the real file moved or was deleted.
        missing = Path(td) / "gone.md"
        c.check("WARNING" in ensure_section(missing, "animals", "pig", "Pig", rows),
                "a missing tracker file is reported")
        c.check(not missing.exists(), "and not created")

    c.eq(sorted(GROUP_HEADINGS), ["animals", "buildings", "terrain"],
         "every adapter category maps to a group heading")
