"""Animal adapter -- covers animals AND people.

project/data/animals/human.tres IS an AnimalDefinition (display_name "Villager"), so
"people" is not a distinct content type and gets no adapter of its own.

Vocabulary and bands below are transcribed from
project/scripts/definitions/animal_definition.gd and game-design/roster.md. They are
NOT decided here -- this module only refuses values that are already known-invalid, and
every remaining choice goes to the human as a Decision.
"""

from __future__ import annotations

import re
from pathlib import Path

from assetpipe.adapters.base import AdapterSpec, FieldSpec, render_tres
from assetpipe.review import Decision

HABITAT_TAGS = ["water", "forest", "open_grass", "quiet", "cover", "flowers",
                "sand", "rocks", "cultivated", "house"]
# Tags untouched revealed land emits on its own. Kept as data because spec.md's
# inert-land invariant requires the derivation, never a hardcoded list.
BARE_TAGS = ["open_grass", "quiet"]
PERSONALITIES = ["Shy", "Bold"]
RADIUS_BAND = (8, 12)
# Transcribed from animal_definition.gd:64.
ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")

SPEC = AdapterSpec(
    name="animal", category="animals", data_dir="animals",
    schema="AnimalDefinition",
    script_path="res://scripts/definitions/animal_definition.gd",
    needs_rig=True, required_clips=["Idle", "Walk"],
    fields=[
        FieldSpec("habitat_needs", "roster.md habitat table; real-world ecology", "tags"),
        FieldSpec("personality", "roster.md; Shy or Bold", "enum"),
        FieldSpec("avoids", "roster.md Compatibility; closed predation graph", "tags"),
        FieldSpec("farm_tolerant", "roster.md farm-tolerance column", "bool"),
        FieldSpec("scout_radius", "roster.md band 8-12", "int"),
        FieldSpec("capacity_radius", "spec.md: 0 is the sentinel for 'follows scout'", "int"),
        FieldSpec("tiles_per_individual", "roster.md decided values; fox.tres uses 5", "int"),
        FieldSpec("max_individuals", "roster.md ~6 baseline (still open question #23)", "int"),
        FieldSpec("model_scale", "sibling wrappers: fox uses 0.2", "float"),
    ],
)


def validate_values(values: dict) -> list[str]:
    problems: list[str] = []
    needs = list(values.get("habitat_needs", []))

    for tag in needs:
        if tag not in HABITAT_TAGS:
            problems.append(f"unknown habitat tag {tag!r}")

    # `avoids` names other SPECIES ids, never habitat tags -- animal_definition.gd:125,
    # "Species ids to keep mutual distance from, in ID_PATTERN form". Real roster data:
    # fox avoids ["rabbit"], rabbit avoids ["fox"], husky avoids ["shiba_inu"]. We check the
    # id CONVENTION only, not existence: the roster is not available here, and a species may
    # legitimately avoid one being added later in the same batch.
    for other in values.get("avoids", []):
        if not isinstance(other, str) or ID_PATTERN.match(other) is None:
            problems.append(
                f"avoids entry {other!r} is not a valid species id "
                f"(lowercase snake, matching {ID_PATTERN.pattern})")

    if needs and all(tag in BARE_TAGS for tag in needs):
        problems.append(
            "habitat_needs %s are satisfiable by untouched land alone -- breaks the "
            "inert-land invariant (a species must never move in without the player "
            "shaping anything)" % needs)

    if values.get("personality") not in PERSONALITIES:
        problems.append(f"personality must be one of {PERSONALITIES}")

    radius = values.get("scout_radius")
    if isinstance(radius, int) and not (RADIUS_BAND[0] <= radius <= RADIUS_BAND[1]):
        problems.append(f"scout_radius {radius} outside roster.md's band {RADIUS_BAND}")

    return problems


def decisions(probe) -> list[Decision]:
    """Every field the human must rule, unruled, each carrying its sourcing.

    Proposals are deliberately absent here: stage 6 fills them from the LLM. A field
    with no proposal still reaches the checkpoint, so nothing can ship unruled.
    """
    return [Decision(field=f.name, proposal=None, source=f.source_hint,
                     confidence="unproposed", value=None) for f in SPEC.fields]


def write(project: Path, ident: str, display: str, values: dict, header: str) -> Path:
    body = {k: v for k, v in values.items() if k != "model_scale"}
    text = render_tres(
        SPEC, ident, display, body,
        [("PackedScene", f"res://assets/animals/{ident}/{display}.tscn", "2_model")],
        header,
    )
    text += 'model_scenes = Array[PackedScene]([ExtResource("2_model")])\n'
    path = project / "data" / SPEC.data_dir / f"{ident}.tres"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path


def selftest_cases(c) -> None:
    import tempfile
    from assetpipe.formats import ModelProbe

    c.eq(SPEC.category, "animals", "animals land in the animals asset category")
    c.eq(SPEC.data_dir, "animals", "people share the animals data dir -- human.tres is one")
    c.check(SPEC.needs_rig, "animals need a rig")
    c.eq(SPEC.required_clips, ["Idle", "Walk"], "idle and walk are required")

    good = {"habitat_needs": ["water", "cover"], "personality": "Shy",
            "avoids": ["rabbit"], "farm_tolerant": False, "scout_radius": 10,
            "capacity_radius": 0, "tiles_per_individual": 5, "max_individuals": 6}
    c.eq(validate_values(good), [], "a well-formed value set validates")

    inert = dict(good, habitat_needs=["open_grass", "quiet"])
    c.check(any("inert-land" in p for p in validate_values(inert)),
            "needs satisfiable by bare tags alone break the inert-land invariant")

    c.check(any("habitat tag" in p for p in
                validate_values(dict(good, habitat_needs=["lava"]))),
            "unknown habitat tag rejected")
    c.check(any("personality" in p for p in
                validate_values(dict(good, personality="Grumpy"))),
            "unknown personality rejected")
    c.check(any("scout_radius" in p for p in
                validate_values(dict(good, scout_radius=40))),
            "scout_radius outside the 8-12 band rejected")

    c.eq(validate_values(dict(good, avoids=["fox", "shiba_inu"])), [],
         "multiple valid species ids in avoids validates clean")
    c.check(any("species id" in p for p in
                validate_values(dict(good, avoids=["Fox"]))),
            "capitals in avoids violate id convention")
    c.check(any("species id" in p for p in
                validate_values(dict(good, avoids=[123]))),
            "non-string entry in avoids is rejected")
    c.eq(validate_values(dict(good, avoids=["water"])), [],
         "avoids with tag-shaped names passes shape check; existence is not verified here")

    ds = decisions(ModelProbe(fmt="fbx", clips=["Idle", "Walk"]))
    names = [d.field for d in ds]
    for required in ("habitat_needs", "personality", "avoids", "farm_tolerant",
                     "scout_radius", "capacity_radius", "tiles_per_individual",
                     "max_individuals", "model_scale"):
        c.check(required in names, f"{required} is put to the human")
    c.check(all(d.value is None for d in ds), "every decision starts unruled")
    c.check(all(d.source for d in ds), "every decision carries its sourcing")

    with tempfile.TemporaryDirectory() as td:
        proj = Path(td) / "project"
        path = write(proj, "pig", "Pig", good, "; Pig\n")
        c.eq(path, proj / "data" / "animals" / "pig.tres", "written to the data dir")
        text = path.read_text()
        c.check('habitat_needs = Array[String](["water", "cover"])' in text,
                "typed arrays survive into the file")
        c.check("model_scenes = Array[PackedScene]" in text, "model wired as a PackedScene")
