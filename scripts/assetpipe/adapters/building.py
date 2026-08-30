"""Building adapter.

Placeables auto-register: project/scripts/economy/building_placement.gd directory-scans
res://data/buildings, so a new .tres needs no UI work -- UNLESS it introduces a
hotbar_category the UI has never heard of. That case halts rather than patching
GDScript, because the same category is hardcoded in three places and getting it wrong
breaks the build rather than merely adding bad data.
"""

from __future__ import annotations

from pathlib import Path

from assetpipe.adapters.base import AdapterSpec, FieldSpec, render_tres
from assetpipe.review import Decision

# Transcribed from project/scripts/ui/game_hud.gd:185 (_PICKER_CATEGORIES).
KNOWN_CATEGORIES = ("forest", "wild_grass", "house", "farm_building")

_CATEGORY_CALL_SITES = (
    "project/scripts/ui/game_hud.gd:185 (_PICKER_CATEGORIES)",
    "project/scripts/ui/style_picker_popup.gd:194",
    "project/scripts/world/world_root.gd (category persistence)",
)

SPEC = AdapterSpec(
    name="building", category="buildings", data_dir="buildings",
    schema="PlaceableDefinition",
    script_path="res://scripts/definitions/placeable_definition.gd",
    needs_rig=False, required_clips=[],
    fields=[
        FieldSpec("cost", "buildings.md baselines: ~15 Wood at 1x1, ~30 at 2x2", "int"),
        FieldSpec("footprint", "buildings.md footprints (open question #18)", "vec2i"),
        FieldSpec("allowed_terrain", "buildings.md placement rules", "tags"),
        FieldSpec("emitted_tags", "buildings.md: the footprint emits these instead of terrain tags", "tags"),
        FieldSpec("hotbar_category", f"one of {KNOWN_CATEGORIES}", "enum"),
        FieldSpec("model_scale", "sibling building wrappers", "float"),
    ],
)


def check_category(category: str) -> list[str]:
    if category in KNOWN_CATEGORIES:
        return []
    return [
        f"hotbar_category {category!r} is unknown to the UI. Adding it means editing "
        f"{len(_CATEGORY_CALL_SITES)} call sites -- " + "; ".join(_CATEGORY_CALL_SITES) +
        " -- which is a ui-engineer dispatch, not this pipeline's write. Halting."
    ]


def validate_values(values: dict) -> list[str]:
    """The pass resume() runs before anything is written.

    check_category existed and was tested, but nothing outside its own selftest called
    it: resume() dispatches on hasattr(module, "validate_values") and only animal.py had
    one, so an unknown hotbar_category went straight into the .tres. The spec's building
    row says "Halts when: introduces an unknown hotbar_category" -- this is what makes
    that true. A missing category is treated as unknown, deliberately: every SPEC field
    reaches the checkpoint, so an absent one means the payload is malformed.
    """
    return check_category(values.get("hotbar_category", ""))


def decisions(probe) -> list[Decision]:
    return [Decision(field=f.name, proposal=None, source=f.source_hint,
                     confidence="unproposed", value=None) for f in SPEC.fields]


def write(project: Path, ident: str, display: str, values: dict, header: str) -> Path:
    body = {k: v for k, v in values.items() if k != "model_scale"}
    text = render_tres(
        SPEC, ident, display, body,
        [("PackedScene", f"res://assets/buildings/{ident}/{display}.tscn", "2_model")],
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

    c.eq(SPEC.category, "buildings", "buildings land in the buildings asset category")
    c.check(not SPEC.needs_rig, "buildings need no rig")
    c.eq(SPEC.required_clips, [], "buildings require no clips")

    c.eq(check_category("farm_building"), [], "a known category passes")
    problems = check_category("workshop")
    c.check(problems, "an unknown category halts")
    c.check(any("game_hud.gd" in p for p in problems),
            "halt names the file that must be edited")
    c.check(any("ui-engineer" in p for p in problems),
            "halt names who owns that edit")

    # REGRESSION, whole-branch review IMPORTANT 4/14: check_category was referenced only
    # by this selftest, so resume() wrote an unknown category into the .tres unchecked.
    c.eq(validate_values({"hotbar_category": "farm_building"}), [],
         "a known category passes the pass resume() actually runs")
    c.check(validate_values({"hotbar_category": "workshop"}),
            "an unknown category is caught by validate_values, not just check_category")
    c.check(validate_values({}), "an absent hotbar_category is treated as unknown")

    ds = decisions(ModelProbe(fmt="obj"))
    names = [d.field for d in ds]
    for required in ("cost", "footprint", "allowed_terrain", "emitted_tags",
                     "hotbar_category", "model_scale"):
        c.check(required in names, f"{required} is put to the human")

    with tempfile.TemporaryDirectory() as td:
        proj = Path(td) / "project"
        path = write(proj, "well", "Well",
                     {"cost": 15, "footprint": [1, 1], "allowed_terrain": ["grass"],
                      "emitted_tags": ["house"], "hotbar_category": "farm_building",
                      "fact_text": "Wells reach water deep underground."},
                     "; Well\n")
        c.eq(path, proj / "data" / "buildings" / "well.tres", "written to the data dir")
        text = path.read_text()
        c.check("footprint = Vector2i(1, 1)" in text, "footprint renders as Vector2i")
        c.check('hotbar_category = "farm_building"' in text, "category written")
        c.check("model_scenes = Array[PackedScene]" in text, "model wired")
