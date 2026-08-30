"""Shared adapter machinery: the per-type contract, and .tres rendering.

WHY RENDERING IS DETERMINISTIC AND NOT AN LLM'S JOB: orchestration/roster-add/README.md
records the earlier crew's Schema Writer emitting plain `[...]` arrays and a bare
model_scene string instead of Godot's `Array[String]([...])` and `ExtResource(...)`
forms -- output that validated structurally but was not drop-in. That README names the
fix as "a small deterministic formatter between Schema Writer and merge". This is it.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class FieldSpec:
    name: str
    source_hint: str
    kind: str


@dataclass
class AdapterSpec:
    name: str
    category: str
    data_dir: str
    schema: str
    script_path: str
    needs_rig: bool
    required_clips: list[str]
    fields: list[FieldSpec] = field(default_factory=list)


def tres_value(v: object) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return f'"{v}"'
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, (list, tuple)):
        items = list(v)
        if items and all(isinstance(i, int) and not isinstance(i, bool) for i in items) \
                and len(items) == 2:
            return f"Vector2i({items[0]}, {items[1]})"
        inner = ", ".join(f'"{i}"' for i in items)
        return f"Array[String]([{inner}])"
    raise TypeError(f"no .tres rendering for {type(v).__name__}: {v!r}")


def render_tres(spec: AdapterSpec, ident: str, display: str, values: dict,
                ext_resources: list[tuple[str, str, str]], header: str) -> str:
    load_steps = 2 + len(ext_resources)
    lines = [header.rstrip("\n"),
             f'[gd_resource type="Resource" script_class="{spec.schema}" '
             f'load_steps={load_steps} format=3]', ""]
    lines.append(f'[ext_resource type="Script" path="{spec.script_path}" id="1_schema"]')
    for res_type, path, res_id in ext_resources:
        lines.append(f'[ext_resource type="{res_type}" path="{path}" id="{res_id}"]')
    lines += ["", "[resource]", 'script = ExtResource("1_schema")',
              f'id = {tres_value(ident)}', f'display_name = {tres_value(display)}']
    for key, val in values.items():
        lines.append(f"{key} = {tres_value(val)}")
    return "\n".join(lines) + "\n"


def selftest_cases(c) -> None:
    c.eq(tres_value("shiba_inu"), '"shiba_inu"', "strings quoted")
    c.eq(tres_value(True), "true", "bools lowercase")
    c.eq(tres_value(False), "false", "false lowercase")
    c.eq(tres_value(12), "12", "ints bare")
    c.eq(tres_value(["water", "cover"]), 'Array[String](["water", "cover"])',
         "string arrays use Godot's typed-array form, not a bare list")
    c.eq(tres_value([]), "Array[String]([])", "empty array still typed")
    c.eq(tres_value([2, 2]), "Vector2i(2, 2)", "int pairs render as Vector2i")

    spec = AdapterSpec(
        name="animal", category="animals", data_dir="animals",
        schema="AnimalDefinition",
        script_path="res://scripts/definitions/animal_definition.gd",
        needs_rig=True, required_clips=["Idle", "Walk"],
        fields=[FieldSpec("scout_radius", "roster.md band 8-12", "int")],
    )
    text = render_tres(spec, "pig", "Pig",
                       {"habitat_needs": ["cultivated"], "scout_radius": 10,
                        "farm_tolerant": True},
                       [("PackedScene", "res://assets/animals/pig/Pig.tscn", "2_model")],
                       header="; Pig — pipeline generated\n")
    c.check(text.startswith("; Pig — pipeline generated"), "header comment leads the file")
    c.check('[gd_resource type="Resource" script_class="AnimalDefinition"' in text,
            "resource header names the script class")
    c.check("load_steps=3" in text, "load_steps counts script + ext resources")
    c.check('script = ExtResource("1_schema")' in text, "script bound by ext resource")
    c.check('habitat_needs = Array[String](["cultivated"])' in text, "typed array emitted")
    c.check("farm_tolerant = true" in text, "bool emitted")
    c.check('id = "pig"' in text and 'display_name = "Pig"' in text, "identity fields")
