"""Import: copy the resolved model and its materials into the project, author its
.import file, and author the wrapper scene as TEXT.

The wrapper is never built with the Godot MCP create_scene/add_node tools -- gdd.md
Technical Strategy #3: they write non-standard properties that silently corrupt the
scene. Conventions (paths, naming, wrapper role) are asset-import-pipeline.md's.
"""

from __future__ import annotations

import json
import re
import shutil
from pathlib import Path


class MissingTexture(RuntimeError):
    """A model references a file that is not on disk. Hard fail: shipping it would mean
    a pink mesh -- or, for a missing buffer, an EMPTY mesh -- discovered at look-pass
    time instead of here."""


# Copied verbatim from the proven params at project/assets/props/den/Bush_1.fbx.import
# rather than inheriting Godot's per-version defaults, so an engine upgrade cannot
# silently change how this project's assets import.
FBX_IMPORT_PARAMS = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[deps]

source_file="res://{res_path}"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
mesh_library/use_node_names_as_mesh_names=false
array_mesh/deduplicate_surfaces=true
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=true
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path=""
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={{}}
fbx/importer=0
fbx/allow_geometry_helper_nodes=false
fbx/embedded_image_handling=1
fbx/naming_version=2
"""

WRAPPER = '''; {display} — model scene for {schema}.model_scenes
; Source: {source}
; Wrapper exists so the world-scale factor and any future look-pass overrides live in
; readable text and survive a re-import of {model_file}.
; SCALE IS A PROPOSAL, not a measurement — the human rules it at the checkpoint.
[gd_scene load_steps=2 format=3]

[ext_resource type="PackedScene" path="res://assets/{category}/{name}/{model_file}" id="1_model"]

[node name="{display}" type="Node3D"]

[node name="Model" parent="." instance=ExtResource("1_model")]
transform = Transform3D({s}, 0, 0, 0, {s}, 0, 0, 0, {s}, 0, 0, 0)
'''

ANIM_BLOCK = '''
[node name="AnimationPlayer" parent="Model" index="{index}"]
autoplay = "Idle"

[editable path="Model"]
'''


def material_deps(model: Path, fmt: str) -> list[Path]:
    """Every EXTERNAL file the model references. Empty for fbx (all embedded).

    For .gltf that is both `images[].uri` and `buffers[].uri`. The buffers matter as much
    as the textures and were the silent gap: `Stylized Nature MegaKit[Standard](1)/glTF/
    Plant_7.gltf` carries buffers[0].uri == "Plant_7.bin", 68 such .bin files exist on
    disk, and dropping one imports an EMPTY mesh rather than a pink one -- with no error
    anywhere. asset-import-pipeline.md's promise is that every referenced file is copied
    alongside the model, and that one which cannot be located is a hard fail.

    `data:` URIs are skipped: those are embedded payloads, not files.
    """
    out: list[Path] = []
    if fmt == "obj":
        mtl = model.with_suffix(".mtl")
        if mtl.is_file():
            out.append(mtl)
            for ref in re.findall(r"^\s*map_\w+\s+(\S+)", mtl.read_text(), re.MULTILINE):
                candidate = mtl.parent / ref
                if not candidate.is_file():
                    raise MissingTexture(f"{mtl.name} references {ref}, not found on disk")
                out.append(candidate)
    elif fmt in ("gltf", "glb"):
        # .glb packs its buffer and images into the file's own chunks, so it has nothing
        # external to collect; every .glb in source-content/assets was verified to carry
        # no external buffer uri.
        doc = json.loads(model.read_text()) if fmt == "gltf" else {}
        for referrer in ("images", "buffers"):
            for item in doc.get(referrer, []):
                uri = item.get("uri", "")
                if not uri or uri.startswith("data:"):
                    continue
                candidate = model.parent / uri
                if not candidate.is_file():
                    raise MissingTexture(
                        f"{model.name} references {uri}, not found on disk")
                if candidate not in out:
                    out.append(candidate)
    return out


def dest_dir(project: Path, category: str, name: str) -> Path:
    return project / "assets" / category / name


def copy_model(resolution, project: Path, category: str, name: str,
               display: str) -> list[Path]:
    dest = dest_dir(project, category, name)
    dest.mkdir(parents=True, exist_ok=True)
    src = resolution.chosen_path
    target = dest / f"{display}{src.suffix}"
    shutil.copy2(src, target)
    written = [target]
    for dep in material_deps(src, resolution.chosen):
        shutil.copy2(dep, dest / dep.name)
        written.append(dest / dep.name)
    if resolution.chosen == "fbx":
        write_import_file(target)
    return written


def write_import_file(model: Path) -> Path:
    res_path = "/".join(model.parts[model.parts.index("assets"):])
    path = model.with_suffix(model.suffix + ".import")
    path.write_text(FBX_IMPORT_PARAMS.format(res_path=res_path))
    return path


def wrapper_text(display: str, category: str, name: str, model_file: str, scale: float,
                 source: str, anim_index: int | None,
                 schema: str = "AnimalDefinition") -> str:
    text = WRAPPER.format(display=display, category=category, name=name,
                          model_file=model_file, s=scale, source=source, schema=schema)
    if anim_index is not None and anim_index >= 0:
        text += ANIM_BLOCK.format(index=anim_index)
    return text


def write_wrapper(project: Path, category: str, name: str, display: str,
                  model_file: str, scale: float, source: str,
                  anim_index: int | None, schema: str = "AnimalDefinition") -> Path:
    path = dest_dir(project, category, name) / f"{display}.tscn"
    path.write_text(wrapper_text(display, category, name, model_file, scale, source,
                                 anim_index, schema))
    return path


def selftest_cases(c) -> None:
    import tempfile
    from assetpipe.formats import ModelProbe, Resolution

    with tempfile.TemporaryDirectory() as td:
        d = Path(td)
        src = d / "src"; src.mkdir()

        (src / "Well.obj").write_text("mtllib Well.mtl\no Well\n")
        (src / "Well.mtl").write_text("newmtl m\nKd 1 1 1\nmap_Kd wood.png\n")
        (src / "wood.png").write_bytes(b"PNG")
        deps = material_deps(src / "Well.obj", "obj")
        names = sorted(p.name for p in deps)
        c.eq(names, ["Well.mtl", "wood.png"], "obj pulls its mtl and referenced texture")

        (src / "Deer.gltf").write_text(json.dumps(
            {"images": [{"uri": "deer_tex.png"}], "animations": [], "meshes": [],
             "nodes": [], "skins": []}))
        (src / "deer_tex.png").write_bytes(b"PNG")
        c.eq([p.name for p in material_deps(src / "Deer.gltf", "gltf")], ["deer_tex.png"],
             "gltf pulls its referenced images")

        # REGRESSION, whole-branch review CRITICAL 3: an EXTERNAL .bin buffer was never
        # collected, so the mesh imported empty with no error. Shaped after the real
        # Stylized Nature MegaKit/glTF/Plant_7.gltf, which has exactly this pair.
        (src / "Plant_7.gltf").write_text(json.dumps(
            {"images": [{"uri": "Leaves.png"}], "buffers": [{"byteLength": 2016,
                                                             "uri": "Plant_7.bin"}]}))
        (src / "Leaves.png").write_bytes(b"PNG")
        (src / "Plant_7.bin").write_bytes(b"\x00" * 16)
        c.eq(sorted(p.name for p in material_deps(src / "Plant_7.gltf", "gltf")),
             ["Leaves.png", "Plant_7.bin"],
             "gltf pulls its external .bin buffer as well as its textures")

        (src / "Embedded.gltf").write_text(json.dumps(
            {"buffers": [{"byteLength": 4, "uri": "data:application/octet-stream;base64,AAAA"}]}))
        c.eq(material_deps(src / "Embedded.gltf", "gltf"), [],
             "a data: buffer is embedded, not a file to copy")

        (src / "NoBuffer.gltf").write_text(json.dumps(
            {"images": [], "buffers": [{"byteLength": 12, "uri": "NoBuffer.bin"}]}))
        missing_buffer = False
        try:
            material_deps(src / "NoBuffer.gltf", "gltf")
        except MissingTexture as exc:
            missing_buffer = "NoBuffer.bin" in str(exc)
        c.check(missing_buffer,
                "an unlocatable .bin buffer is a hard fail, not a silently empty mesh")

        real = Path("source-content/assets/Stylized Nature MegaKit[Standard](1)/glTF/"
                    "Plant_7.gltf")
        if real.is_file():
            c.eq(sorted(p.name for p in material_deps(real, "gltf")),
                 ["Leaves.png", "Plant_7.bin"],
                 "the real Plant_7.gltf yields its real external buffer")
        else:
            c.check(True, "real Plant_7.gltf check skipped, source-content not on this path")

        (src / "Pig.fbx").write_bytes(b"\x00Armature|Idle\x00")
        c.eq(material_deps(src / "Pig.fbx", "fbx"), [],
             "fbx materials are embedded -- nothing external to copy")

        (src / "Broken.obj").write_text("mtllib Broken.mtl\n")
        (src / "Broken.mtl").write_text("map_Kd missing.png\n")
        missing = False
        try:
            material_deps(src / "Broken.obj", "obj")
        except MissingTexture as exc:
            missing = "missing.png" in str(exc)
        c.check(missing, "an unlocatable texture is a hard fail, not a pink mesh")

        proj = d / "project"
        c.eq(dest_dir(proj, "animals", "pig"), proj / "assets" / "animals" / "pig",
             "destination follows the conventional path")

        res = Resolution("fbx", src / "Pig.fbx",
                         ModelProbe(fmt="fbx", clips=["Idle"]), "r", {})
        copied = copy_model(res, proj, "animals", "pig", "Pig")
        c.check((proj / "assets" / "animals" / "pig" / "Pig.fbx").is_file(),
                "model copied under its display name")
        c.eq(len(copied), 1, "copy reports what it wrote")
        c.check((proj / "assets" / "animals" / "pig" / "Pig.fbx.import").is_file(),
                "fbx gets an authored .import")
        imp = (proj / "assets" / "animals" / "pig" / "Pig.fbx.import").read_text()
        c.check("fbx/importer=0" in imp, ".import pins the built-in ufbx importer")
        c.check("animation/import=true" in imp, ".import keeps animation import on")

        plain = wrapper_text("Pig", "animals", "pig", "Pig.fbx", 0.2, "CC0-1.0", None)
        c.check("[gd_scene load_steps=2 format=3]" in plain, "wrapper header is valid")
        c.check("AnimationPlayer" not in plain, "phase-one wrapper omits the anim override")
        c.check('transform = Transform3D(0.2, 0, 0, 0, 0.2, 0, 0, 0, 0.2, 0, 0, 0)' in plain,
                "scale written into the transform")

        withanim = wrapper_text("Pig", "animals", "pig", "Pig.fbx", 0.2, "CC0-1.0", 1)
        c.check('[node name="AnimationPlayer" parent="Model" index="1"]' in withanim,
                "phase-two wrapper carries the real index")
        c.check('autoplay = "Idle"' in withanim, "autoplay set")
        c.check('[editable path="Model"]' in withanim,
                "editable marker present -- without it the override is ignored")

        # Verify FBX_IMPORT_PARAMS fidelity against the real Bush_1.fbx.import file.
        # Skip gracefully if the reference file is missing.
        ref_path = Path("project/assets/props/den/Bush_1.fbx.import")
        if ref_path.is_file():
            ref_text = ref_path.read_text()
            ref_params = set()
            in_params = False
            for line in ref_text.splitlines():
                if line == "[params]":
                    in_params = True
                    continue
                if in_params and line.startswith("["):
                    break
                if in_params and "=" in line:
                    key = line.split("=")[0].strip()
                    if key:
                        ref_params.add(key)

            const_params = set()
            in_params = False
            for line in FBX_IMPORT_PARAMS.splitlines():
                if line == "[params]":
                    in_params = True
                    continue
                if in_params and line.startswith("["):
                    break
                if in_params and "=" in line:
                    key = line.split("=")[0].strip()
                    if key:
                        const_params.add(key)

            c.eq(const_params, ref_params, "FBX_IMPORT_PARAMS [params] keys match Bush_1.fbx.import")
        else:
            c.check(True, "FBX_IMPORT_PARAMS fidelity check skipped, reference file absent")
