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
    for p in prims:
        idx = p.get("attributes", {}).get("POSITION")
        if idx is not None and idx < len(accessors):
            total += accessors[idx].get("count", 0)
    m["vertices"] = total

    m["clips"] = sorted(a.get("name", "") for a in doc.get("animations", []))
    m["joints"] = max((len(s.get("joints", [])) for s in doc.get("skins", [])), default=0)
    m["textures"] = sorted(
        Path(i["uri"]).name for i in doc.get("images", []) if i.get("uri"))
    return m


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
            "accessors": [{"count": 1108}, {"count": 1108}],
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

        c.eq(sorted(empty_manifest().keys()), sorted(MANIFEST_FIELDS),
             "empty_manifest covers exactly MANIFEST_FIELDS")

        # .glb: same JSON, wrapped in the binary container -- the two paths must agree.
        json_bytes = _json.dumps(doc).encode("utf-8")
        pad = (-len(json_bytes)) % 4
        json_bytes += b" " * pad
        header = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(json_bytes))
        chunk_header = struct.pack("<II", len(json_bytes), 0x4E4F534A)
        (d / "m.glb").write_bytes(header + chunk_header + json_bytes)
        c.eq(manifest_from_gltf(d / "m.glb"), rev,
             "glb: binary container parses to the same manifest as the equivalent .gltf")
