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

# The id of the terrain untouched revealed land is made of. NOT "grass": the schema's own
# load-bearing constant is project/scripts/definitions/terrain_definition.gd:31,
# `const WILD_GRASS_ID: String = "wild_grass"`. derive_bare_tags() (:104) finds by that id
# and validate() (:200) refuses `normalize_id(id) == WILD_GRASS_ID and not
# emitted_tags.is_empty()`. A guard keyed on "grass" protected a terrain the invariant
# does not cover, and left the one it does cover unguarded.
# gdd.md -> World Structure; terrain.md -> Already-Defined Terrain.
BASE_TERRAIN_ID = "wild_grass"

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

# Godot writes `uid="uid://..."` between `type` and `path` when it re-saves a resource
# (see project/assets/props/den/Den.tscn). No terrain .tres carries one today, but if a
# human ever opens one in the editor and saves, an entry without the optional group here
# would silently drop out of the match set -- under-counting ids and letting a later
# append duplicate an existing one. The optional group costs nothing and removes that.
_EXT = re.compile(
    r'^\[ext_resource type="PackedScene"(?: uid="[^"]*")? path="([^"]+)" id="(\d+)_model"\]$',
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

    # REGRESSION, whole-branch review IMPORTANT 6: the guard was keyed on "grass", but
    # terrain_definition.gd:31 defines WILD_GRASS_ID = "wild_grass" and both
    # derive_bare_tags() and validate() key off that. The guard protected the wrong id.
    c.eq(BASE_TERRAIN_ID, "wild_grass", "base terrain id matches WILD_GRASS_ID")
    c.check(any("inert-land" in p for p in
                check_new_type("wild_grass", {"emitted_tags": ["forest"]})),
            "wild_grass emitting tags is refused -- it is the id the invariant covers")
    c.eq(check_new_type("grass", {"emitted_tags": ["forest"]}), [],
         "plain grass emitting tags is allowed -- the invariant does not cover it")

    schema = Path("project/scripts/definitions/terrain_definition.gd")
    if schema.is_file():
        c.check(f'const WILD_GRASS_ID: String = "{BASE_TERRAIN_ID}"' in schema.read_text(),
                "BASE_TERRAIN_ID still matches the schema's own constant")
    else:
        c.check(True, "schema cross-check skipped, project/ not on this path")

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

    # FINDING 3(a): Mixed model + non-model .tres with non-discriminating id placement.
    # Fixture has 2_model, 4_model (both PackedScene with _model suffix), and 12_harvest
    # (Resource with different suffix). A correct filter sees max model id 4 → next_id=5.
    # A broken filter that wrongly counts all entries sees max id 12 → next_id=13.
    # This assertion diverges the two behaviors and proves the filter works.
    with tempfile.TemporaryDirectory() as td:
        mixed = Path(td) / "mixed.tres"
        mixed.write_text(
            '[gd_resource type="Resource" script_class="TerrainDefinition" '
            'load_steps=5 format=3]\n\n'
            '[ext_resource type="Script" path="res://scripts/definitions/terrain_definition.gd" id="1_schema"]\n'
            '[ext_resource type="PackedScene" path="res://assets/terrain/common_tree_1/CommonTree1.tscn" id="2_model"]\n'
            '[ext_resource type="PackedScene" path="res://assets/terrain/common_tree_2/CommonTree2.tscn" id="4_model"]\n'
            '[ext_resource type="Resource" path="res://data/terrain/forest_harvest.tres" id="12_harvest"]\n\n'
            '[resource]\nscript = ExtResource("1_schema")\nid = "forest"\n'
            'model_scenes = Array[PackedScene]([ExtResource("2_model"), ExtResource("4_model")])\n')

        summary = append_variant(mixed, "res://assets/terrain/birch_tree/BirchTree.tscn")
        text = mixed.read_text()
        # Correct filter sees max model id=4, so next=5. Broken filter sees max id=12, so next=13.
        c.check('path="res://assets/terrain/birch_tree/BirchTree.tscn" id="5_model"' in text,
                "discriminating fixture: next id is 5_model (only models counted)")
        c.check('id="13_model"' not in text,
                "discriminating fixture: does NOT use 13_model (would prove filter is broken)")
        c.check("load_steps=6" in text, "mixed: load_steps incremented to 6")
        c.check('ExtResource("2_model"), ExtResource("4_model"), ExtResource("5_model")' in text,
                "mixed: model_scenes now has three entries in order")

    # FINDING 3(b): A uid-bearing entry is still matched and counted correctly
    with tempfile.TemporaryDirectory() as td:
        uid_file = Path(td) / "uid.tres"
        uid_file.write_text(
            '[gd_resource type="Resource" script_class="TerrainDefinition" '
            'load_steps=4 format=3]\n\n'
            '[ext_resource type="Script" path="res://scripts/definitions/terrain_definition.gd" id="1_schema"]\n'
            '[ext_resource type="PackedScene" uid="uid://abc123def456" path="res://assets/terrain/common_tree_1/CommonTree1.tscn" id="2_model"]\n'
            '[ext_resource type="PackedScene" path="res://assets/terrain/bush/Bush.tscn" id="3_model"]\n\n'
            '[resource]\nscript = ExtResource("1_schema")\nid = "forest"\n'
            'model_scenes = Array[PackedScene]([ExtResource("2_model"), ExtResource("3_model")])\n')

        summary = append_variant(uid_file, "res://assets/terrain/maple_tree/MapleTree.tscn")
        text = uid_file.read_text()
        # The regex must match the uid-bearing entry; max id is 3, so next is 4
        c.check('id="4_model"' in text,
                "uid-bearing entry is still matched; next id is 4_model (not 3_model)")
        c.check('ExtResource("2_model"), ExtResource("3_model"), ExtResource("4_model")' in text,
                "uid test: model_scenes extended with 4_model")

    # FINDING 3(c): The refuse path -- .tres with ext_resources but NO model_scenes array
    with tempfile.TemporaryDirectory() as td:
        no_array = Path(td) / "no_array.tres"
        original = (
            '[gd_resource type="Resource" script_class="TerrainDefinition" '
            'load_steps=3 format=3]\n\n'
            '[ext_resource type="Script" path="res://scripts/definitions/terrain_definition.gd" id="1_schema"]\n'
            '[ext_resource type="PackedScene" path="res://assets/terrain/common_tree_1/CommonTree1.tscn" id="2_model"]\n\n'
            '[resource]\nscript = ExtResource("1_schema")\nid = "broken"\n')
        no_array.write_text(original)

        refused = False
        error_msg = ""
        try:
            append_variant(no_array, "res://assets/terrain/maple_tree/MapleTree.tscn")
        except RuntimeError as e:
            refused = True
            error_msg = str(e)
        c.check(refused, "no model_scenes array: append_variant raises RuntimeError")
        c.check("no model_scenes array" in error_msg, "error message names the problem")
        c.eq(no_array.read_text(), original, "refusal is atomic; file unchanged")

    # Header-prose idempotency regression test: a res:// path quoted in a comment but
    # NOT bound by any ext_resource line. The old raw-substring check would report
    # "already present" for this scenario and silently no-op. The structural check
    # should recognize it's not actually bound and append successfully.
    with tempfile.TemporaryDirectory() as td:
        header_prose = Path(td) / "header_prose.tres"
        header_prose.write_text(
            '; superseded — see res://assets/terrain/maple_tree/MapleTree.tscn for details\n'
            '[gd_resource type="Resource" script_class="TerrainDefinition" '
            'load_steps=3 format=3]\n\n'
            '[ext_resource type="Script" path="res://scripts/definitions/terrain_definition.gd" id="1_schema"]\n'
            '[ext_resource type="PackedScene" path="res://assets/terrain/common_tree_1/CommonTree1.tscn" id="2_model"]\n\n'
            '[resource]\nscript = ExtResource("1_schema")\nid = "forest"\n'
            'model_scenes = Array[PackedScene]([ExtResource("2_model")])\n')

        summary = append_variant(header_prose, "res://assets/terrain/maple_tree/MapleTree.tscn")
        text = header_prose.read_text()
        # The path IS in the file (in the header), but NOT bound by ext_resource.
        # Structural idempotency should append, not silently no-op.
        c.check("appended" in summary and "already present" not in summary,
                "header prose: path in comment does not block append")
        c.check('id="3_model"' in text,
                "header prose: new model added despite path appearing in header comment")


def append_variant(tres: Path, scene_res_path: str) -> str:
    text = tres.read_text()

    # Structural idempotency: compare against the paths actually bound by ext_resource
    # lines, not a raw substring of the whole file. A header comment quoting a res:// path
    # in prose would otherwise make a legitimate append silently no-op.
    existing = _EXT.findall(text)
    if scene_res_path in [path for path, _id in existing]:
        return f"{Path(scene_res_path).name} already present -- nothing appended"

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
