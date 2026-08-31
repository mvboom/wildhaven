"""One manifest shape for any model, whichever side produced it.

Phase 1 (content_provenance.py) uses this to SEARCH -- which source best matches this
imported asset? Phase 2 (content_fidelity.py) uses it to VERIFY -- does the declared
source still match? Same extraction, two callers.

Floats round to 4dp at construction so comparison is exact rather than epsilon-based;
base_colors sorts because neither Blender's exporter nor Godot's importer guarantees a
stable material order, and an order-sensitive diff reports failures that are not defects.
"""

import json
import struct
import subprocess
from pathlib import Path

MANIFEST_FIELDS = (
    "materials", "base_colors", "metallic", "roughness", "vertex_colors",
    "textures", "surfaces", "vertices", "clips", "joints", "aabb",
)


def round4(x: float) -> float:
    return round(float(x), 4)


def empty_manifest() -> dict:
    return {"materials": 0, "base_colors": [], "metallic": [], "roughness": [],
            "vertex_colors": False, "textures": [], "surfaces": 0, "vertices": 0,
            "clips": [], "joints": 0, "aabb": [0.0, 0.0, 0.0]}


def _gltf_doc(path: Path) -> dict:
    """The JSON of a .gltf, or of a .glb's first chunk."""
    raw = path.read_bytes()
    if raw[:4] != b"glTF":
        return json.loads(raw)
    # glb: 12-byte header, then length-prefixed chunks; chunk 0 is the JSON.
    length, kind = struct.unpack_from("<II", raw, 12)
    if kind != 0x4E4F534A:
        raise ValueError(f"{path}: first glb chunk is not JSON")
    return json.loads(raw[20:20 + length])


def manifest_from_gltf(path: Path) -> dict:
    doc = _gltf_doc(Path(path))
    m = empty_manifest()

    mats = doc.get("materials", [])
    m["materials"] = len(mats)
    # Sort the three per-material lists TOGETHER, keyed on colour, so a row stays coherent.
    rows = []
    for mat in mats:
        pbr = mat.get("pbrMetallicRoughness", {})
        rows.append((
            [round4(v) for v in pbr.get("baseColorFactor", [1.0, 1.0, 1.0, 1.0])],
            round4(pbr.get("metallicFactor", 1.0)),
            round4(pbr.get("roughnessFactor", 1.0)),
        ))
    rows.sort(key=lambda r: r[0])
    m["base_colors"] = [r[0] for r in rows]
    m["metallic"] = [r[1] for r in rows]
    m["roughness"] = [r[2] for r in rows]

    prims = [p for mesh in doc.get("meshes", []) for p in mesh.get("primitives", [])]
    m["surfaces"] = len(prims)
    m["vertex_colors"] = any("COLOR_0" in p.get("attributes", {}) for p in prims)

    accessors = doc.get("accessors", [])
    total = 0
    mins, maxs = [], []
    for p in prims:
        idx = p.get("attributes", {}).get("POSITION")
        if idx is not None and idx < len(accessors):
            acc = accessors[idx]
            total += acc.get("count", 0)
            if "min" in acc and "max" in acc:
                mins.append(acc["min"])
                maxs.append(acc["max"])
    m["vertices"] = total
    # Overall bounding box across ALL primitives, as an EXTENT (max - min per axis) rather
    # than a corner pair, so it is comparable to the Blender side's object `dimensions`.
    if mins:
        lo = [min(v[i] for v in mins) for i in range(3)]
        hi = [max(v[i] for v in maxs) for i in range(3)]
        m["aabb"] = [round4(hi[i] - lo[i]) for i in range(3)]

    m["clips"] = sorted(a.get("name", "") for a in doc.get("animations", []))
    m["joints"] = max((len(s.get("joints", [])) for s in doc.get("skins", [])), default=0)
    m["textures"] = sorted(
        Path(i["uri"]).name for i in doc.get("images", []) if i.get("uri"))
    return m


# Runs INSIDE Blender. Emits the same dict shape manifest_from_gltf produces, fenced by
# markers because Blender writes its own banner and addon chatter to stdout.
BLENDER_DUMP = r'''
import bpy, json, sys
path = sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
low = path.lower()
if low.endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=path)
elif low.endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=path)
else:
    raise SystemExit("unsupported: " + path)

rows, textures = [], set()
for mat in bpy.data.materials:
    if not mat.use_nodes:
        continue
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        continue
    col = list(bsdf.inputs["Base Color"].default_value)
    rows.append([[round(float(v), 4) for v in col],
                 round(float(bsdf.inputs["Metallic"].default_value), 4),
                 round(float(bsdf.inputs["Roughness"].default_value), 4)])
    for img in (n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image):
        textures.add(img.name)
rows.sort(key=lambda r: r[0])

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
verts = sum(len(o.data.vertices) for o in meshes)
surfaces = sum(max(1, len(o.material_slots)) for o in meshes)
vcol = any(len(o.data.color_attributes) > 0 for o in meshes)
joints = max([len(a.data.bones) for a in bpy.data.objects if a.type == "ARMATURE"] or [0])

dims = [0.0, 0.0, 0.0]
for o in meshes:
    for i in range(3):
        dims[i] = max(dims[i], round(float(o.dimensions[i]), 4))

print("<<<MANIFEST>>>" + json.dumps({
    "materials": len(rows),
    "base_colors": [r[0] for r in rows],
    "metallic": [r[1] for r in rows],
    "roughness": [r[2] for r in rows],
    "vertex_colors": vcol,
    "textures": sorted(textures),
    "surfaces": surfaces,
    "vertices": verts,
    "clips": sorted(a.name for a in bpy.data.actions),
    "joints": joints,
    "aabb": dims,
}) + "<<<END>>>")
'''


def manifest_from_blender(path: Path) -> dict:
    """Materials, colours, clips and counts read by Blender itself.

    No heuristic fallback when Blender is missing: a manifest built from a parser known
    to over-report would bake wrong literals into a generated suite, which is worse than
    having no suite at all.
    """
    from assetpipe import blender
    if not blender.available():
        raise RuntimeError(
            f"cannot fingerprint {path.name}: {blender.unavailable_reason()}")
    proc = subprocess.run(
        [blender.binary(), "--background", "--factory-startup",
         "--python-expr", BLENDER_DUMP, "--", str(path)],
        capture_output=True, text=True, timeout=300)
    out = proc.stdout
    if "<<<MANIFEST>>>" not in out:
        raise RuntimeError(
            f"blender produced no manifest for {path}\n"
            f"--- stdout ---\n{out[-2000:]}\n--- stderr ---\n{proc.stderr[-2000:]}")
    body = out.split("<<<MANIFEST>>>", 1)[1].split("<<<END>>>", 1)[0]
    return json.loads(body)


def selftest_cases(c) -> None:
    import json as _json
    import tempfile
    from pathlib import Path as _P

    with tempfile.TemporaryDirectory() as td:
        d = _P(td)
        doc = {
            "materials": [
                {"name": "Black", "pbrMetallicRoughness": {
                    "baseColorFactor": [0.0374080, 0.0374080, 0.0374080, 1],
                    "metallicFactor": 0, "roughnessFactor": 0.5}},
                {"name": "White", "pbrMetallicRoughness": {
                    "baseColorFactor": [0.8, 0.8, 0.8, 1],
                    "metallicFactor": 1, "roughnessFactor": 0.2}},
            ],
            "meshes": [{"primitives": [
                {"material": 0, "attributes": {"POSITION": 0, "COLOR_0": 1}},
                {"material": 1, "attributes": {"POSITION": 0, "COLOR_0": 1}},
            ]}],
            "accessors": [
                {"count": 1108, "min": [-1.0, -2.0, -3.0], "max": [4.0, 5.0, 6.0]},
                {"count": 1108},
            ],
            "animations": [{"name": "Walk"}, {"name": "Idle"}],
            "skins": [{"joints": list(range(31))}],
            "images": [],
        }
        (d / "m.gltf").write_text(_json.dumps(doc))
        m = manifest_from_gltf(d / "m.gltf")

        c.eq(m["materials"], 2, "gltf: material count")
        c.eq(m["base_colors"][0], [0.0374, 0.0374, 0.0374, 1.0],
             "gltf: base colours sorted ascending, rounded to 4dp")
        c.eq(m["base_colors"][1], [0.8, 0.8, 0.8, 1.0], "gltf: second base colour")
        c.eq(m["metallic"], [0.0, 1.0], "gltf: metallic paired with its material row")
        c.eq(m["roughness"], [0.5, 0.2], "gltf: roughness paired with its material row")
        c.eq(m["vertex_colors"], True, "gltf: COLOR_0 detected")
        c.eq(m["clips"], ["Idle", "Walk"], "gltf: clips sorted")
        c.eq(m["joints"], 31, "gltf: skin joint count")
        c.eq(m["textures"], [], "gltf: no images means no textures")
        c.eq(m["surfaces"], 2, "gltf: primitive count")
        c.eq(m["aabb"], [5.0, 7.0, 9.0],
             "gltf: aabb is the per-axis extent (max - min) from accessor min/max, "
             "across all primitives")

        # Material ORDER must not change the manifest -- exporters do not guarantee it.
        # Black/White carry DIFFERENT metallic/roughness values (see fixture above)
        # specifically so a desync between base_colors and metallic/roughness after
        # the reversal would be visible here rather than silently passing.
        doc["materials"].reverse()
        for i, prim in enumerate(doc["meshes"][0]["primitives"]):
            prim["material"] = 1 - i
        (d / "rev.gltf").write_text(_json.dumps(doc))
        rev = manifest_from_gltf(d / "rev.gltf")
        c.eq(rev["base_colors"], m["base_colors"],
             "gltf: reordered materials produce an identical manifest")
        c.eq(rev["metallic"], m["metallic"],
             "gltf: reordered materials -- metallic stays paired with its colour")
        c.eq(rev["roughness"], m["roughness"],
             "gltf: reordered materials -- roughness stays paired with its colour")
        c.eq(rev["aabb"], m["aabb"],
             "gltf: reordered materials -- aabb unaffected (geometry unchanged)")

        c.eq(sorted(empty_manifest().keys()), sorted(MANIFEST_FIELDS),
             "empty_manifest covers exactly MANIFEST_FIELDS")

        # .glb: same JSON, wrapped in the binary container -- the two paths must agree.
        # This now also exercises a LIVE aabb (accessor min/max carried the whole doc
        # over), not the [0,0,0] default the field used to be stuck at.
        json_bytes = _json.dumps(doc).encode("utf-8")
        pad = (-len(json_bytes)) % 4
        json_bytes += b" " * pad
        header = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(json_bytes))
        chunk_header = struct.pack("<II", len(json_bytes), 0x4E4F534A)
        (d / "m.glb").write_bytes(header + chunk_header + json_bytes)
        c.eq(manifest_from_gltf(d / "m.glb"), rev,
             "glb: binary container parses to the same manifest as the equivalent .gltf")

    # Blender path. Skipped with a VISIBLE note when Blender is absent, never silently:
    # a skipped extraction that looks like a pass is how wrong literals reach a suite.
    from assetpipe import blender as _b
    if not _b.available():
        c.check(True, f"blender extraction SKIPPED -- {_b.unavailable_reason()}")
    else:
        _sheep = _P("source-content/assets/Farm Animals by @Quaternius/Blends/Sheep.blend")
        if _sheep.is_file():
            bm = manifest_from_blender(_sheep)
            c.eq(bm["materials"], 2, "blend: Sheep has two materials")
            c.eq(bm["vertex_colors"], True, "blend: Sheep carries a colour attribute")
            c.check(len(bm["clips"]) == 6, f"blend: Sheep has 6 clips, got {bm['clips']}")
            c.check(bm["joints"] > 0, "blend: Sheep is rigged")
        else:
            c.check(True, "blend: Sheep.blend absent, extraction case skipped")

        # .fbx path -- manifest_from_blender exists partly to AVOID formats.probe_fbx's
        # over-reporting heuristic, so the fbx branch needs its own live exercise, not
        # just the .blend one above. Most of this project's imported models are
        # FBX-derived, so a broken branch here would otherwise surface as a failure in
        # unrelated, later code.
        _pig_fbx = _P("source-content/assets/Farm Animals by @Quaternius/FBX/Pig.fbx")
        if _pig_fbx.is_file():
            fm = manifest_from_blender(_pig_fbx)
            c.eq(sorted(fm.keys()), sorted(MANIFEST_FIELDS),
                 "fbx: manifest carries exactly MANIFEST_FIELDS")
            c.check(fm["materials"] > 0, "fbx: Pig has at least one material")
            c.check(fm["vertices"] > 0, "fbx: Pig has vertices")
            c.check(len(fm["clips"]) > 0, "fbx: Pig has at least one clip")
            # Measured this run: Pig.fbx carries only 2 of the 6 actions Pig.blend
            # holds (see assetpipe/blender.py's module docstring) -- pin that specific,
            # verified fact rather than just echoing whatever the call returned.
            c.eq(len(fm["clips"]), 2,
                 f"fbx: Pig.fbx carries 2 of its .blend's 6 actions, got {fm['clips']}")
        else:
            c.check(True, "fbx: Pig.fbx absent, extraction case skipped")

    base = empty_manifest() | {
        "materials": 2, "base_colors": [[0.1, 0.1, 0.1, 1.0], [0.8, 0.8, 0.8, 1.0]],
        "metallic": [0.0, 0.0], "roughness": [0.5, 0.5], "vertex_colors": True,
        "textures": ["Bark.png"], "surfaces": 2, "vertices": 1000,
        "clips": ["Idle", "Walk"], "joints": 31, "aabb": [1.0, 1.0, 1.0]}

    c.eq(compare(base, dict(base), set()), [], "identical manifests produce no findings")
    c.eq(verdict([]), "OK", "no findings is OK")

    lost = dict(base, materials=1, base_colors=[[0.8, 0.8, 0.8, 1.0]])
    fields = {f.field for f in compare(base, lost, set())}
    c.check("materials" in fields and "base_colors" in fields,
            f"a dropped material fails on both counts, got {fields}")
    c.eq(verdict(compare(base, lost, set())), "FAIL", "a dropped material is a FAIL")

    flat = dict(base, vertex_colors=False)
    c.eq([f.level for f in compare(base, flat, set())], ["FAIL"],
         "vertex colours turned off is a FAIL -- this is the flat-grey-model bug")

    c.eq(compare(base, flat, {"vertex_colors"}), [],
         "a sanctioned field is exempt")

    # Seam splitting is normal; a near-empty mesh is not.
    c.eq(compare(base, dict(base, vertices=2412), set()), [],
         "2.4x vertices is inside the seam-splitting band")
    c.eq([f.level for f in compare(base, dict(base, vertices=50), set())], ["WARN"],
         "a near-empty mesh warns")
    c.eq(verdict(compare(base, dict(base, vertices=50), set())), "WARN",
         "warnings alone are WARN, not FAIL")

    c.eq([f.field for f in compare(base, dict(base, textures=[]), set())], ["textures"],
         "a texture that did not arrive is reported")
    c.eq([f.level for f in compare(base, dict(base, textures=[]), set())], ["FAIL"],
         "a missing texture is a FAIL")
    c.eq([f.level for f in compare(base, dict(base, textures=["Bark.png", "X.png"]),
                                   set())], ["WARN"],
         "an EXTRA texture only warns")

    c.check(_suffix_kind(_P("a.gltf")) == "gltf" and _suffix_kind(_P("a.glb")) == "gltf",
            "gltf and glb dispatch to the JSON reader")
    c.check(_suffix_kind(_P("a.blend")) == "blender"
            and _suffix_kind(_P("a.fbx")) == "blender",
            "blend and fbx dispatch to Blender")
    c.eq(_suffix_kind(_P("a.obj")), "", "obj has no manifest path")

    # aabb is compared as a sorted multiset of extents, not axis-for-axis -- measured
    # evidence: sheep's Blender dimensions matched Godot's runtime AABB with no swap,
    # while pig's and pug's needed Y and Z exchanged to match, so no fixed axis swap
    # is correct either.
    aabb_src = dict(base, aabb=[3.0, 9.0, 4.5])
    aabb_perm = dict(base, aabb=[3.0, 4.5, 9.0])  # same three extents, Y/Z exchanged
    c.eq([f.field for f in compare(aabb_src, aabb_perm, set())], [],
         "a permutation of the same extents is not an aabb mismatch")

    aabb_off = dict(base, aabb=[3.0, 9.0, 6.0])  # sorted magnitudes genuinely differ
    c.eq([f.field for f in compare(aabb_src, aabb_off, set())], ["aabb"],
         "a genuine magnitude mismatch still warns even sorted")


from collections import namedtuple

Finding = namedtuple("Finding", "field level detail")

# PROPOSALS, not rulings. Real ratios across all 31 assets come out of Phase 1; the human
# rules these once that data exists (project rule: all tuning values are the human's).
VERTEX_BAND = (0.5, 3.0)
AABB_TOLERANCE = 0.05


def _suffix_kind(path: Path) -> str:
    s = path.suffix.lower()
    if s in (".gltf", ".glb"):
        return "gltf"
    if s in (".blend", ".fbx"):
        return "blender"
    return ""


def manifest_for_source(path: Path) -> dict:
    path = Path(path)
    kind = _suffix_kind(path)
    if kind == "gltf":
        return manifest_from_gltf(path)
    if kind == "blender":
        return manifest_from_blender(path)
    raise ValueError(f"no manifest path for {path.suffix!r} ({path})")


def _ratio_ok(src: float, run: float, lo: float, hi: float) -> bool:
    if src == 0:
        return run == 0
    return lo <= (run / src) <= hi


def compare(src: dict, run: dict, sanctioned: set) -> list:
    """Findings where runtime diverges from source, minus fields the artifact sanctions."""
    out = []

    def add(field, level, detail):
        if field not in sanctioned:
            out.append(Finding(field, level, detail))

    for field in ("materials", "vertex_colors"):
        if src[field] != run[field]:
            add(field, "FAIL", f"source {src[field]} vs runtime {run[field]}")

    if src["base_colors"] != run["base_colors"]:
        add("base_colors", "FAIL",
            f"source {src['base_colors']} vs runtime {run['base_colors']}")

    for field in ("textures", "clips"):
        missing = sorted(set(src[field]) - set(run[field]))
        extra = sorted(set(run[field]) - set(src[field]))
        if missing:
            add(field, "FAIL", f"missing {missing}")
        if extra:
            add(field, "WARN", f"extra {extra}")

    if src["joints"] > 0 and src["joints"] != run["joints"]:
        add("joints", "FAIL", f"source {src['joints']} vs runtime {run['joints']}")

    if src["surfaces"] != run["surfaces"]:
        add("surfaces", "WARN", f"source {src['surfaces']} vs runtime {run['surfaces']}")

    if not _ratio_ok(src["vertices"], run["vertices"], *VERTEX_BAND):
        add("vertices", "WARN",
            f"source {src['vertices']} vs runtime {run['vertices']} "
            f"(outside {VERTEX_BAND[0]}x-{VERTEX_BAND[1]}x)")

    for field in ("metallic", "roughness"):
        if src[field] != run[field]:
            add(field, "WARN", f"source {src[field]} vs runtime {run[field]}")

    # Compared as a SORTED multiset of extents, not axis-for-axis. Measured directly:
    # sheep's Blender (Z-up) dimensions matched Godot's (Y-up) runtime AABB with no
    # swap, while pig's and pug's needed Y and Z exchanged to match -- these .blend
    # files are not authored on a consistent up-axis, so there is no fixed swap to
    # apply. Sorting keeps the field's real job (catch a mis-scaled import) while
    # giving up detecting an import that came in rotated -- a capability that was
    # never real here, since this extraction can't tell authored orientation apart
    # from an actual rotation.
    lo, hi = 1.0 - AABB_TOLERANCE, 1.0 + AABB_TOLERANCE
    if not all(_ratio_ok(s, r, lo, hi)
               for s, r in zip(sorted(src["aabb"]), sorted(run["aabb"]))):
        add("aabb", "WARN", f"source {src['aabb']} vs runtime {run['aabb']}")

    return out


def verdict(findings: list) -> str:
    if any(f.level == "FAIL" for f in findings):
        return "FAIL"
    return "WARN" if findings else "OK"
