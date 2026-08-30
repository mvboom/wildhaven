"""Terrain adapter -- covers terrain types AND tree/style variants.

VARIANT MODE is the common case and is pure data: TerrainDefinition.pick_variant(x, z)
chooses stably per tile with no save-state (D-42), and style_picker_popup derives its
label from the scene's directory name via String.capitalize(). So adding a tree is a
.tscn plus two lines in an existing .tres -- no GDScript edit, no new picker category.

NEW_TYPE MODE writes a fresh TerrainDefinition. The one thing it must never do is make
the BASE terrain emit tags: spec.md's inert-land invariant requires untouched revealed
land to be tag-inert, and TerrainDefinition.derive_bare_tags() keys off that id.
"""

from __future__ import annotations

import re
from pathlib import Path

from assetpipe.adapters.base import AdapterSpec, FieldSpec, render_tres
from assetpipe.review import Decision

# gdd.md -> World Structure; terrain.md -> Already-Defined Terrain.
BASE_TERRAIN_ID = "grass"

MODE_VARIANT = "variant"
MODE_NEW_TYPE = "new_type"

SPEC = AdapterSpec(
    name="terrain", category="terrain", data_dir="terrain",
    schema="TerrainDefinition",
    script_path="res://scripts/definitions/terrain_definition.gd",
    needs_rig=False, required_clips=[],
    fields=[
        FieldSpec("emitted_tags", "terrain.md tag-source mapping", "tags"),
        FieldSpec("cost", "terrain.md: nature is free; construction costs materials", "int"),
        FieldSpec("blocks_movement", "terrain.md; forest blocks, grass does not", "bool"),
        FieldSpec("model_scale", "sibling terrain wrappers", "float"),
    ],
)

_EXT = re.compile(r'^\[ext_resource type="PackedScene" path="([^"]+)" id="(\d+)_model"\]$',
                  re.MULTILINE)
_STEPS = re.compile(r"load_steps=(\d+)")
_SCENES = re.compile(r"^model_scenes = Array\[PackedScene\]\(\[(.*)\]\)$", re.MULTILINE)


def selftest_cases(c) -> None:
    import tempfile
    from assetpipe.formats import ModelProbe

    c.eq(SPEC.data_dir, "terrain", "terrain data dir")
    c.check(not SPEC.needs_rig, "terrain needs no rig")

    with tempfile.TemporaryDirectory() as td:
        tres = Path(td) / "forest.tres"
        tres.write_text(
            '[gd_resource type="Resource" script_class="TerrainDefinition" '
            'load_steps=4 format=3]\n\n'
            '[ext_resource type="Script" path="res://scripts/definitions/terrain_definition.gd" id="1_schema"]\n'
            '[ext_resource type="PackedScene" path="res://assets/terrain/common_tree_1/CommonTree1.tscn" id="2_model"]\n'
            '[ext_resource type="PackedScene" path="res://assets/terrain/bush/Bush.tscn" id="3_model"]\n\n'
            '[resource]\nscript = ExtResource("1_schema")\nid = "forest"\n'
            'model_scenes = Array[PackedScene]([ExtResource("2_model"), ExtResource("3_model")])\n')

        summary = append_variant(tres, "res://assets/terrain/maple_tree/MapleTree.tscn")
        text = tres.read_text()
        c.check('path="res://assets/terrain/maple_tree/MapleTree.tscn" id="4_model"' in text,
                "new ext_resource appended with the next free id")
        c.check('ExtResource("2_model"), ExtResource("3_model"), ExtResource("4_model")' in text,
                "model_scenes extended in order")
        c.check("load_steps=5" in text, "load_steps incremented")
        c.check("MapleTree" in summary, "summary names what was added")

        again = append_variant(tres, "res://assets/terrain/maple_tree/MapleTree.tscn")
        c.eq(tres.read_text().count("MapleTree.tscn"), 1, "appending twice is idempotent")
        c.check("already present" in again, "repeat append says so")

    c.eq(check_new_type("meadow", {"emitted_tags": ["flowers"]}), [],
         "a new terrain type emitting tags is fine")
    problems = check_new_type(BASE_TERRAIN_ID, {"emitted_tags": ["flowers"]})
    c.check(any("inert-land" in p for p in problems),
            "making the base terrain emit tags breaks the inert-land invariant")

    c.check([d.field for d in decisions(ModelProbe(fmt="obj"), "variant")] == ["model_scale"],
            "variant mode asks only for scale")
    names = [d.field for d in decisions(ModelProbe(fmt="obj"), "new_type")]
    for required in ("emitted_tags", "cost", "blocks_movement", "model_scale"):
        c.check(required in names, f"new_type mode asks for {required}")

    with tempfile.TemporaryDirectory() as td:
        proj = Path(td) / "project"
        path = write(proj, "meadow", "Meadow",
                     {"emitted_tags": ["flowers"], "cost": 0,
                      "blocks_movement": False, "model_scale": 1.0}, "; Meadow\n")
        c.eq(path, proj / "data" / "terrain" / "meadow.tres", "new type written")
        c.check("blocks_movement = false" in path.read_text(), "bool rendered")
        refused = False
        try:
            write(proj, BASE_TERRAIN_ID, "Grass", {"emitted_tags": ["flowers"]}, "; g\n")
        except RuntimeError as exc:
            refused = "inert-land" in str(exc)
        c.check(refused, "write refuses to break the inert-land invariant")


def append_variant(tres: Path, scene_res_path: str) -> str:
    text = tres.read_text()
    if scene_res_path in text:
        return f"{Path(scene_res_path).name} already present -- nothing appended"

    existing = _EXT.findall(text)
    next_id = max((int(n) for _p, n in existing), default=1) + 1
    new_line = (f'[ext_resource type="PackedScene" path="{scene_res_path}" '
                f'id="{next_id}_model"]')

    last = list(_EXT.finditer(text))[-1]
    text = text[:last.end()] + "\n" + new_line + text[last.end():]

    text = _STEPS.sub(lambda m: f"load_steps={int(m.group(1)) + 1}", text, count=1)

    def _extend(match: re.Match) -> str:
        inner = match.group(1).strip()
        joined = f'{inner}, ExtResource("{next_id}_model")' if inner \
            else f'ExtResource("{next_id}_model")'
        return f"model_scenes = Array[PackedScene]([{joined}])"

    text, count = _SCENES.subn(_extend, text, count=1)
    if count != 1:
        raise RuntimeError(f"no model_scenes array found in {tres} -- refusing to guess")

    tres.write_text(text)
    return f"appended {Path(scene_res_path).name} as id {next_id}_model"


def check_new_type(ident: str, values: dict) -> list[str]:
    if ident == BASE_TERRAIN_ID and values.get("emitted_tags"):
        return [
            f"{ident!r} is the base terrain; giving it emitted_tags {values['emitted_tags']} "
            f"breaks the inert-land invariant (untouched revealed land must be tag-inert, "
            f"spec.md -> Shared invariants)"
        ]
    return []


def decisions(probe, mode: str) -> list[Decision]:
    fields = SPEC.fields if mode == MODE_NEW_TYPE else [
        f for f in SPEC.fields if f.name == "model_scale"]
    return [Decision(field=f.name, proposal=None, source=f.source_hint,
                     confidence="unproposed", value=None) for f in fields]


def write(project: Path, ident: str, display: str, values: dict, header: str) -> Path:
    """NEW_TYPE mode only. Variant mode goes through append_variant instead -- it has no
    .tres of its own to write, which is exactly why a tree is data and not code."""
    problems = check_new_type(ident, values)
    if problems:
        raise RuntimeError("; ".join(problems))
    body = {k: v for k, v in values.items() if k != "model_scale"}
    text = render_tres(
        SPEC, ident, display, body,
        [("PackedScene", f"res://assets/terrain/{ident}/{display}.tscn", "2_model")],
        header,
    )
    text += 'model_scenes = Array[PackedScene]([ExtResource("2_model")])\n'
    path = project / "data" / SPEC.data_dir / f"{ident}.tres"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path
