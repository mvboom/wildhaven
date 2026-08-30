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
from dataclasses import dataclass, field
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


@dataclass
class CopiedModel:
    """What copy_model actually put in the destination.

    `model` is the file the WRAPPER must reference, and it is NOT always named after the
    source. A .blend is CONVERTED: the source is Pig.blend, the committed artifact is
    Pig.gltf, and the .blend is deliberately never copied. Building the wrapper from the
    source's suffix therefore produced a .tscn pointing at a file that does not exist --
    Godot instanced nothing, anim_index came back -1, and the generated test asserted
    clips against an empty scene. Exposing the written filename is what stops the next
    converting format reintroducing that.

    `files` is everything written, for the operator-facing count only.
    """

    model: Path
    files: list[Path] = field(default_factory=list)


def copy_model(resolution, project: Path, category: str, name: str,
               display: str) -> CopiedModel:
    dest = dest_dir(project, category, name)
    dest.mkdir(parents=True, exist_ok=True)
    src = resolution.chosen_path

    if resolution.chosen == "blend":
        # CONVERTED, not copied. The .blend stays in source-content; what the project
        # commits is a plain glTF, so build-game.sh, a web export, CI and a fresh clone
        # never need Blender. export_gltf verifies the produced glTF still carries the
        # actions the .blend advertised -- these are BLENDER-v279 files and a modern
        # Blender can drop things opening them.
        from assetpipe import blender  # lazy: mirrors formats.probe's cycle break
        out = blender.export_gltf(src, dest, display)
        # What the exporter PRODUCED, read out of the glTF it wrote -- its own buffer and
        # image uris. A directory diff under-reported on a re-run (the .bin was already
        # there, so it vanished from the list) and counted directories as written files.
        # material_deps also hard-fails if the export referenced something it did not
        # write, which is a real check on the conversion rather than bookkeeping.
        return CopiedModel(model=out, files=[out, *material_deps(out, "gltf")])

    target = dest / f"{display}{src.suffix}"
    shutil.copy2(src, target)
    written = [target]
    for dep in material_deps(src, resolution.chosen):
        shutil.copy2(dep, dest / dep.name)
        written.append(dest / dep.name)
    if resolution.chosen == "fbx":
        write_import_file(target)
    return CopiedModel(model=target, files=written)


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


_TRANSFORM = re.compile(
    r"^transform = Transform3D\("
    r"[-\d.eE+]+, 0, 0, 0, [-\d.eE+]+, 0, 0, 0, [-\d.eE+]+, 0, 0, 0\)$", re.MULTILINE)


def rescale_wrapper(path: Path, scale: float) -> str:
    """Put the human's ruled model_scale into a wrapper that already exists.

    run() writes the wrapper BEFORE the checkpoint, with a hardcoded 0.2, because Godot
    must import something before its AnimationPlayer can be probed. The ruled scale
    arrives at the checkpoint, after that -- and every adapter strips model_scale before
    rendering its .tres, so the wrapper is the ONLY place scale lives. Without this a
    building ruled 1.0 shipped at 0.2, and in terrain variant mode, where scale is the
    only field the human is asked for, the whole checkpoint was decorative.

    Rewriting the one transform line rather than re-rendering the wrapper preserves the
    model filename, the licence line and the AnimationPlayer index run() determined --
    none of which resume() can re-derive without another Godot probe.
    """
    text = path.read_text()
    replacement = (f"transform = Transform3D({scale}, 0, 0, 0, {scale}, 0, 0, 0, "
                   f"{scale}, 0, 0, 0)")
    text, count = _TRANSFORM.subn(lambda _m: replacement, text, count=1)
    if count != 1:
        raise RuntimeError(
            f"no uniform Transform3D line in {path} -- refusing to guess where the "
            f"ruled model_scale belongs")
    path.write_text(text)
    return f"model_scale {scale} written into {path.name}"


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
        c.eq(len(copied.files), 1, "copy reports what it wrote")
        c.eq(copied.model.name, "Pig.fbx",
             "copy reports the model filename the wrapper must reference")
        c.check((proj / "assets" / "animals" / "pig" / "Pig.fbx.import").is_file(),
                "fbx gets an authored .import")
        imp = (proj / "assets" / "animals" / "pig" / "Pig.fbx.import").read_text()
        c.check("fbx/importer=0" in imp, ".import pins the built-in ufbx importer")
        c.check("animation/import=true" in imp, ".import keeps animation import on")

        # A .blend is CONVERTED into the destination, not copied -- the artifact the
        # project commits is a plain glTF, so nothing downstream needs Blender. Stubbed
        # here: running a real Blender would make the suite slow and machine-dependent.
        from assetpipe import blender as _bl
        _real = _bl.export_gltf
        def _fake(blend, dest_dir, name):
            # Shaped like a real GLTF_SEPARATE export: the .gltf REFERENCES its .bin, the
            # way Blender writes it. The stub used to write an unreferenced .bin, which no
            # assertion could have distinguished from a lost buffer.
            dest_dir.mkdir(parents=True, exist_ok=True)
            out = dest_dir / f"{name}.gltf"
            out.write_text(json.dumps(
                {"animations": [], "meshes": [], "nodes": [], "skins": [],
                 "buffers": [{"byteLength": 3, "uri": f"{name}.bin"}]}))
            (dest_dir / f"{name}.bin").write_bytes(b"BIN")
            return out
        _bl.export_gltf = _fake
        try:
            blend_src = src / "Sheep.blend"
            blend_src.write_bytes(b"BLENDER-v279\x00ACWalk\x00ACIdle\x00")
            res_b = Resolution("blend", blend_src,
                               ModelProbe(fmt="blend", clips=["Idle", "Walk"]), "r", {})
            proj_b = d / "project_blend"
            got = copy_model(res_b, proj_b, "animals", "sheep", "Sheep")
            names = sorted(p.name for p in got.files)
            c.eq(names, ["Sheep.bin", "Sheep.gltf"],
                 "a .blend is converted into the destination, with its .bin")
            c.check(not (dest_dir(proj_b, "animals", "sheep") / "Sheep.blend").exists(),
                    "the .blend itself is NOT copied into the project")

            # REGRESSION, review MINOR: the written list was a directory DIFF, so a
            # re-run into a populated destination reported only the files that happened
            # not to be there already -- second run dropped the .bin. What the exporter
            # produced is read from the glTF it wrote, not inferred from the directory.
            again = copy_model(res_b, proj_b, "animals", "sheep", "Sheep")
            c.eq(sorted(p.name for p in again.files), ["Sheep.bin", "Sheep.gltf"],
                 "a re-run into a populated destination still reports every file written")

            # REGRESSION, review CRITICAL 1: the wrapper's model filename was built from
            # the SOURCE suffix, so a converted .blend yielded a .tscn pointing at
            # Sheep.blend -- a file copy_model deliberately never writes. Conversion and
            # wrapper were each verified in isolation and never joined. This joins them:
            # it runs the copy + wrapper sequence exactly as asset_pipeline.run() does and
            # asserts the reference resolves to a file that is actually on disk.
            proj_e = d / "project_e2e"
            copied_e = copy_model(res_b, proj_e, "animals", "sheep", "Sheep")
            write_wrapper(proj_e, "animals", "sheep", "Sheep", copied_e.model.name,
                          0.2, "CC0-1.0", None)
            dest_e = dest_dir(proj_e, "animals", "sheep")
            ref = re.search(r'path="res://assets/animals/sheep/([^"]+)"',
                            (dest_e / "Sheep.tscn").read_text())
            c.check(ref is not None, "the converted .blend's wrapper carries an ext_resource")
            named = ref.group(1) if ref else ""
            c.eq(named, "Sheep.gltf",
                 "a converted .blend's wrapper names the glTF, not the .blend")
            c.check((dest_e / named).is_file(),
                    f"the wrapper's ext_resource names a file that EXISTS (got {named!r})")
        finally:
            _bl.export_gltf = _real

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

        # REGRESSION, whole-branch review IMPORTANT 5: the human's ruled model_scale was
        # discarded. run() hardcodes 0.2 before the checkpoint, every adapter strips
        # model_scale before rendering, and resume() never rewrote the wrapper.
        dest_dir(proj, "buildings", "well").mkdir(parents=True, exist_ok=True)
        wp = write_wrapper(proj, "buildings", "well", "Well", "Well.obj", 0.2, "CC0-1.0", 2,
                           "PlaceableDefinition")
        summary = rescale_wrapper(wp, 1.0)
        after = wp.read_text()
        c.check("transform = Transform3D(1.0, 0, 0, 0, 1.0, 0, 0, 0, 1.0, 0, 0, 0)" in after,
                "the ruled scale replaces the pre-checkpoint 0.2")
        c.check("Transform3D(0.2" not in after, "no 0.2 transform survives the rewrite")
        c.check("1.0" in summary, "rescale summary names the scale it wrote")
        c.check('[node name="AnimationPlayer" parent="Model" index="2"]' in after,
                "rescale preserves the AnimationPlayer index run() determined")
        c.check('path="res://assets/buildings/well/Well.obj"' in after,
                "rescale preserves the model file reference")
        c.check("CC0-1.0" in after, "rescale preserves the licence line")

        refused = False
        try:
            noscale = proj / "noscale.tscn"
            noscale.write_text("[gd_scene format=3]\n")
            rescale_wrapper(noscale, 1.0)
        except RuntimeError as exc:
            refused = "refusing to guess" in str(exc)
        c.check(refused, "a wrapper with no transform line refuses rather than guessing")

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
