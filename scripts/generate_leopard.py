#!/usr/bin/env blender --background --factory-startup --python
"""Generate a Leopard / Snow Leopard model from the CC0 Quaternius Wolf.

The Quaternius "Ultimate Animated Animals" pack has no big cat. Rather than fork
the binary .blend by hand, this script *derives* the leopard from the pristine
Wolf.blend by a list of named, tunable proportion edits. The .blend it writes is
a build output; this file is the source of truth.

Why it works: every animal in the pack shares one 51-bone armature and the same
12 actions, and the mesh's vertex groups are named exactly after the bones. So a
region can be addressed by vertex group, and if bone rest positions and mesh
vertices move by the *same* transform, skin weights stay valid and all 12
animations survive untouched.

Vertex edits are weighted by vertex-group membership, so every transform feathers
out at the region boundary instead of leaving a seam.

Usage:
    blender --background --factory-startup <Wolf.blend> \
        --python scripts/generate_leopard.py -- \
        --variant leopard --out /path/to/Leopard.blend --render /path/to/prefix
"""

import argparse
import sys

import bpy
from mathutils import Matrix, Vector

# --------------------------------------------------------------------------
# Tunables. Every proportion decision lives here, named, so it is reviewable in
# git and dialable between render passes.
# --------------------------------------------------------------------------

PARAMS = {
    # 1. Longer cat body. Scales the whole rig in Y, which also spreads the
    #    fore/hind leg attachment points apart -- leopards are long-backed.
    "body_stretch_y": 1.10,

    # 2. Deeper, barrel chest through the shoulders.
    "chest_deepen_z": 1.06,
    "chest_widen_x": 1.12,

    # 3. Shorter, thicker legs. Scaled about the foot plane so the paws stay
    #    planted; the body is then dropped by the delta so nothing floats.
    "leg_shorten_z": 0.88,
    "leg_thicken_x": 1.20,
    "leg_thicken_y": 1.14,

    # 4. Big cat paws.
    "paw_widen": 1.15,
    "paw_height": 0.35,  # verts below this Z count as paw

    # 5. Small rounded ears. Wolf ears are tall triangles; scaling them down
    #    uniformly just makes small triangles, so squash height far harder than
    #    width to get a cat's low rounded ear.
    "ear_width": 0.78,
    "ear_depth": 0.60,
    "ear_height": 0.42,

    # 6. Big cat head -- leopards are notably large-headed for their body.
    "head_scale": 1.16,

    # 7. Short blunt muzzle. The single biggest "cat not dog" read. Only the
    #    geometry forward of the eye line is compressed, so the cranium keeps
    #    its volume instead of the whole head shrinking.
    "muzzle_line_t": 0.30,   # fraction along the Head bone where the face starts
    "muzzle_shorten": 0.52,
    "muzzle_widen": 1.06,
    # Height is scaled separately and slightly DOWN: widening the muzzle in Z as
    # well as X drives the lower jaw away from the pivot and hangs it off the
    # chin like a beard. Cats also have flatter faces than wolves.
    "muzzle_height": 0.74,
    "muzzle_band": 0.22,   # feather distance behind the eye line, avoids a seam

    # 8. Broad rounded cranium.
    "skull_widen_x": 1.16,
    "skull_height_z": 1.08,

    # 8. Thicker neck.
    "neck_thicken": 1.14,

    # 9. Heavy tail, with the wolf's flared brush tip taken back down so it
    #    reads as an even big-cat tail.
    "tail_thicken": 1.15,
    "tail_tip_shrink": 0.78,
}

# Per-variant overrides + palette.
VARIANTS = {
    "leopard": {
        "params": {},
        "colors": {
            "Main": (0.72, 0.50, 0.20, 1.0),        # golden tan
            "Main_Light": (0.90, 0.84, 0.68, 1.0),  # cream belly
            "Nose": (0.14, 0.09, 0.09, 1.0),
            "Eyes_Black": (0.05, 0.04, 0.03, 1.0),
        },
    },
    "snow_leopard": {
        # Snow leopards are stockier and much heavier-furred than leopards.
        "params": {
            "leg_thicken_x": 1.30,
            "leg_thicken_y": 1.22,
            "chest_widen_x": 1.20,
            "tail_thicken": 1.42,
            "neck_thicken": 1.22,
        },
        "colors": {
            "Main": (0.70, 0.71, 0.73, 1.0),        # pale smoke grey
            "Main_Light": (0.93, 0.93, 0.92, 1.0),  # near-white belly
            "Nose": (0.20, 0.16, 0.17, 1.0),
            "Eyes_Black": (0.06, 0.06, 0.06, 1.0),
        },
    },
}

# --------------------------------------------------------------------------
# Vertex-group / bone region sets
# --------------------------------------------------------------------------

SIDES = (".L", ".R")


def sided(*stems):
    return [stem + s for stem in stems for s in SIDES]


EAR_GROUPS = sided("Ear1", "Ear2", "Ear3", "Ear4")
LEG_GROUPS = sided(
    "FrontShoulder", "FrontUpperLeg", "FrontLowerLeg",
    "BackShoulder", "BackLeg", "BackUpperLeg", "BackLowerLeg",
)
LEG_BONES = LEG_GROUPS + sided("IKFrontLeg", "IKBackLeg", "FF", "FFB",
                               "PoleTarget", "PoleTargetBack")
TORSO_GROUPS = ["Back", "Torso", "Torso2", "Torso3"]
NECK_GROUPS = ["Neck1", "Neck2", "Neck3"]
TAIL_GROUPS = [f"Tail{i}" for i in range(1, 9)]
HEAD_GROUPS = ["Head"]

# Everything that is not a leg -- used to drop the body after leg shortening.
BODY_GROUPS = TORSO_GROUPS + NECK_GROUPS + TAIL_GROUPS + HEAD_GROUPS + EAR_GROUPS + ["Body"]


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

def scale_matrix(sx, sy, sz):
    return Matrix.Diagonal(Vector((sx, sy, sz))).to_3x3()


def deform_verts(mesh_ob, group_names, pivot, mat):
    """Apply `mat` about `pivot`, blended by each vertex's weight in the groups.

    Weighting the blend is what keeps region edges seamless: a vertex half-owned
    by Head and half by Neck3 moves half as far as a pure Head vertex.
    """
    idxs = {mesh_ob.vertex_groups[n].index
            for n in group_names if n in mesh_ob.vertex_groups}
    if not idxs:
        return
    for v in mesh_ob.data.vertices:
        w = sum(g.weight for g in v.groups if g.group in idxs)
        w = min(1.0, max(0.0, w))
        if w <= 0.0:
            continue
        target = mat @ (v.co - pivot) + pivot
        v.co = v.co.lerp(target, w)


def deform_verts_masked(mesh_ob, group_names, pivot, mat, mask):
    """As `deform_verts`, but only vertices for which `mask(co)` is true.

    Used where a region needs sub-group precision -- the muzzle is the front part
    of the Head group, not a group of its own.
    """
    idxs = {mesh_ob.vertex_groups[n].index
            for n in group_names if n in mesh_ob.vertex_groups}
    if not idxs:
        return
    for v in mesh_ob.data.vertices:
        if not mask(v.co):
            continue
        w = sum(g.weight for g in v.groups if g.group in idxs)
        w = min(1.0, max(0.0, w))
        if w <= 0.0:
            continue
        target = mat @ (v.co - pivot) + pivot
        v.co = v.co.lerp(target, w)


def deform_forward_of(mesh_ob, line_y, band, pivot, mat):
    """Apply `mat` to everything forward of `line_y`, feathered over `band`.

    Group-filtered deformation is wrong for the face: the jaw and throat carry
    Neck weights, not Head, so a Head-only muzzle compression leaves them jutting
    forward as a 'beard'. Selecting positionally takes the whole snout together.
    """
    for v in mesh_ob.data.vertices:
        w = (line_y - v.co.y) / band
        w = min(1.0, max(0.0, w))
        if w <= 0.0:
            continue
        target = mat @ (v.co - pivot) + pivot
        v.co = v.co.lerp(target, w)


def deform_all_verts(mesh_ob, pivot, mat):
    for v in mesh_ob.data.vertices:
        v.co = mat @ (v.co - pivot) + pivot


def translate_verts(mesh_ob, group_names, offset):
    idxs = {mesh_ob.vertex_groups[n].index
            for n in group_names if n in mesh_ob.vertex_groups}
    for v in mesh_ob.data.vertices:
        w = sum(g.weight for g in v.groups if g.group in idxs)
        w = min(1.0, max(0.0, w))
        if w > 0.0:
            v.co = v.co + offset * w


def edit_bones(arm_ob):
    bpy.context.view_layer.objects.active = arm_ob
    bpy.ops.object.mode_set(mode='EDIT')
    return arm_ob.data.edit_bones


def leave_edit():
    bpy.ops.object.mode_set(mode='OBJECT')


def move_bones(ebones, names, pivot, mat):
    wanted = set(names)
    for b in ebones:
        if b.name in wanted:
            b.head = mat @ (Vector(b.head) - pivot) + pivot
            b.tail = mat @ (Vector(b.tail) - pivot) + pivot


def move_all_bones(ebones, pivot, mat):
    for b in ebones:
        b.head = mat @ (Vector(b.head) - pivot) + pivot
        b.tail = mat @ (Vector(b.tail) - pivot) + pivot


def offset_bones(ebones, names, offset):
    wanted = set(names)
    for b in ebones:
        if b.name in wanted:
            b.head = Vector(b.head) + offset
            b.tail = Vector(b.tail) + offset


def bone_head(arm_ob, name):
    return Vector(arm_ob.data.bones[name].head_local)


def action_fcurves(action):
    """Blender 5.x moved fcurves into slotted action layers."""
    if hasattr(action, "fcurves") and len(getattr(action, "fcurves", [])) > 0:
        return list(action.fcurves)
    out = []
    for layer in getattr(action, "layers", []):
        for strip in getattr(layer, "strips", []):
            for bag in getattr(strip, "channelbags", []):
                out.extend(bag.fcurves)
    return out


# --------------------------------------------------------------------------
# The reshape
# --------------------------------------------------------------------------

def reshape(mesh_ob, arm_ob, P):
    log = []

    # --- 1. Longer body: uniform Y stretch of everything, about the origin. ---
    m = scale_matrix(1.0, P["body_stretch_y"], 1.0)
    deform_all_verts(mesh_ob, Vector((0, 0, 0)), m)
    eb = edit_bones(arm_ob)
    move_all_bones(eb, Vector((0, 0, 0)), m)
    leave_edit()
    log.append(f"body stretched Y x{P['body_stretch_y']}")

    # --- 2. Deeper / broader chest through the shoulders. ---
    torso_z = bone_head(arm_ob, "Torso2").z
    pivot = Vector((0, 0, torso_z))
    m = scale_matrix(P["chest_widen_x"], 1.0, P["chest_deepen_z"])
    deform_verts(mesh_ob, TORSO_GROUPS, pivot, m)
    log.append(f"chest x{P['chest_widen_x']} wide, x{P['chest_deepen_z']} deep")

    # --- 3. Shorter, thicker legs about the foot plane, then drop the body. ---
    foot_z = min(v.co.z for v in mesh_ob.data.vertices)
    shoulder_z_before = bone_head(arm_ob, "FrontUpperLeg.L").z
    pivot = Vector((0, 0, foot_z))
    m = scale_matrix(P["leg_thicken_x"], P["leg_thicken_y"], P["leg_shorten_z"])
    deform_verts(mesh_ob, LEG_GROUPS, pivot, m)
    eb = edit_bones(arm_ob)
    move_bones(eb, LEG_BONES, pivot, m)
    leave_edit()

    shoulder_z_after = bone_head(arm_ob, "FrontUpperLeg.L").z
    drop = Vector((0, 0, shoulder_z_after - shoulder_z_before))
    translate_verts(mesh_ob, BODY_GROUPS, drop)
    eb = edit_bones(arm_ob)
    offset_bones(eb, BODY_GROUPS + ["Body"], drop)
    leave_edit()
    log.append(f"legs x{P['leg_shorten_z']} tall / x{P['leg_thicken_x']} thick, "
               f"body dropped {drop.z:+.3f}")

    # --- 4. Big paws (purely positional: the lowest band of leg verts). ---
    paw_cut = foot_z + P["paw_height"]
    s = P["paw_widen"]
    for v in mesh_ob.data.vertices:
        if v.co.z < paw_cut:
            t = 1.0 - (v.co.z - foot_z) / P["paw_height"]  # 1 at sole, 0 at cut
            f = 1.0 + (s - 1.0) * max(0.0, min(1.0, t))
            cx = 0.0 if abs(v.co.x) < 1e-6 else v.co.x
            v.co.x = cx * f
            v.co.y = v.co.y * f
    log.append(f"paws x{s} below z={paw_cut:.2f}")

    # --- 5. Enlarge the whole head about the neck junction.
    #        MUST run before the ear pass: scaling the head about the neck also
    #        translates the ears outward, which would undo an earlier shrink. ---
    neck_join = bone_head(arm_ob, "Head")
    hs = P["head_scale"]
    m = scale_matrix(hs, hs, hs)
    deform_verts(mesh_ob, HEAD_GROUPS + EAR_GROUPS, neck_join, m)
    eb = edit_bones(arm_ob)
    move_bones(eb, ["Head"] + EAR_GROUPS, neck_join, m)
    leave_edit()
    log.append(f"head x{hs}")

    # --- 6. Small rounded ears: squash height much harder than width. ---
    for side in SIDES:
        root = bone_head(arm_ob, "Ear1" + side)
        m = scale_matrix(P["ear_width"], P["ear_depth"], P["ear_height"])
        deform_verts(mesh_ob, [g for g in EAR_GROUPS if g.endswith(side)], root, m)
        eb = edit_bones(arm_ob)
        move_bones(eb, [b for b in EAR_GROUPS if b.endswith(side)], root, m)
        leave_edit()
    log.append(f"ears x{P['ear_width']} wide / x{P['ear_height']} tall")

    # --- 7. Blunt the muzzle: compress only what is forward of the eye line,
    #        so the cranium keeps its volume. ---
    h_head = bone_head(arm_ob, "Head")
    h_tail = Vector(arm_ob.data.bones["Head"].tail_local)
    muzzle_line = h_head.y + (h_tail.y - h_head.y) * P["muzzle_line_t"]
    pivot = Vector((0.0, muzzle_line, h_head.z))
    m = scale_matrix(P["muzzle_widen"], P["muzzle_shorten"], P["muzzle_height"])
    deform_forward_of(mesh_ob, muzzle_line, P["muzzle_band"], pivot, m)
    log.append(f"muzzle x{P['muzzle_shorten']} long forward of y={muzzle_line:.2f}, "
               f"x{P['muzzle_widen']} broad")

    # --- 8. Broad rounded cranium. ---
    m = scale_matrix(P["skull_widen_x"], 1.0, P["skull_height_z"])
    deform_verts_masked(mesh_ob, HEAD_GROUPS, h_head, m,
                        mask=lambda co: co.y >= muzzle_line)
    log.append(f"cranium x{P['skull_widen_x']} wide")

    # --- 8. Thicker neck. ---
    neck = bone_head(arm_ob, "Neck2")
    m = scale_matrix(P["neck_thicken"], 1.0, P["neck_thicken"])
    deform_verts(mesh_ob, NECK_GROUPS, neck, m)
    log.append(f"neck x{P['neck_thicken']}")

    # --- 9. Heavy tail, flared wolf brush tip taken back down. ---
    tail = bone_head(arm_ob, "Tail1")
    m = scale_matrix(P["tail_thicken"], 1.0, P["tail_thicken"])
    deform_verts(mesh_ob, TAIL_GROUPS, tail, m)
    tip = P["tail_tip_shrink"]
    tip_axis = bone_head(arm_ob, "Tail6")
    deform_verts(mesh_ob, ["Tail6", "Tail7", "Tail8"], tip_axis,
                 scale_matrix(tip, 1.0, tip))
    log.append(f"tail x{P['tail_thicken']}, tip x{tip}")

    mesh_ob.data.update()
    return log


def rescale_action_locations(sy, drop_z):
    """Keep root translation in step with the rig edits.

    Actions keyframe bone-local location on the root bones; the Y stretch and the
    body drop change the rest pose those offsets are measured from.
    """
    touched = 0
    for action in bpy.data.actions:
        for fc in action_fcurves(action):
            if not fc.data_path.endswith(".location"):
                continue
            if '"Body"' not in fc.data_path:
                continue
            if fc.array_index == 1:  # Y
                for kp in fc.keyframe_points:
                    kp.co.y *= sy
                    kp.handle_left.y *= sy
                    kp.handle_right.y *= sy
                touched += 1
    return touched


def diagnose(mesh_ob, arm_ob):
    """Print where each material and each head-region vertex group actually sits.

    Renders answer "does it look right"; they do not answer "which vertices are
    that lump". This does.
    """
    print("--- material regions (bbox of the polys using each slot) ---")
    per_mat = {}
    for poly in mesh_ob.data.polygons:
        per_mat.setdefault(poly.material_index, []).extend(poly.vertices)
    for mi, vids in sorted(per_mat.items()):
        mat = mesh_ob.data.materials[mi]
        cos = [mesh_ob.data.vertices[i].co for i in set(vids)]
        lo = [round(min(c[k] for c in cos), 2) for k in range(3)]
        hi = [round(max(c[k] for c in cos), 2) for k in range(3)]
        name = mat.name if mat else "<none>"
        print(f"  [{mi}] {name:14s} n={len(set(vids)):4d} x={lo[0]}..{hi[0]} "
              f"y={lo[1]}..{hi[1]} z={lo[2]}..{hi[2]}")

    print("--- head-region vertex groups ---")
    for gname in HEAD_GROUPS + NECK_GROUPS + EAR_GROUPS:
        if gname not in mesh_ob.vertex_groups:
            continue
        gi = mesh_ob.vertex_groups[gname].index
        cos = [v.co for v in mesh_ob.data.vertices
               if any(g.group == gi and g.weight > 0.01 for g in v.groups)]
        if not cos:
            continue
        lo = [round(min(c[k] for c in cos), 2) for k in range(3)]
        hi = [round(max(c[k] for c in cos), 2) for k in range(3)]
        print(f"  {gname:10s} n={len(cos):4d} x={lo[0]}..{hi[0]} "
              f"y={lo[1]}..{hi[1]} z={lo[2]}..{hi[2]}")

    hb = arm_ob.data.bones["Head"]
    print(f"  Head bone head={tuple(round(v,2) for v in hb.head_local)} "
          f"tail={tuple(round(v,2) for v in hb.tail_local)}")


def recolor(mesh_ob, colors):
    for mat in mesh_ob.data.materials:
        if mat is None or mat.name not in colors:
            continue
        rgba = colors[mat.name]
        mat.diffuse_color = rgba  # viewport / workbench
        if mat.use_nodes:
            for node in mat.node_tree.nodes:
                if node.type == 'BSDF_PRINCIPLED':
                    node.inputs['Base Color'].default_value = rgba


# --------------------------------------------------------------------------
# Render (workbench, flat material colors -- we are judging silhouette)
# --------------------------------------------------------------------------

def render_views(prefix, res=(640, 480)):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'MATERIAL'
    sc.display.shading.show_shadows = True
    sc.display.shading.show_cavity = True
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.image_settings.file_format = 'PNG'

    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            ob.hide_render = True

    mesh = [o for o in bpy.data.objects if o.type == 'MESH'][0]
    bb = [mesh.matrix_world @ Vector(c) for c in mesh.bound_box]
    lo = Vector([min(v[i] for v in bb) for i in range(3)])
    hi = Vector([max(v[i] for v in bb) for i in range(3)])
    ctr = (lo + hi) / 2
    size = max((hi - lo)[i] for i in range(3))

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = size * 1.25
    cam = bpy.data.objects.new("Cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam

    views = {
        "side": (Vector((1.0, 0.0, 0.10)), ctr, size * 1.25),
        "threeq": (Vector((0.75, -0.75, 0.35)), ctr, size * 1.25),
        "front": (Vector((0.0, -1.0, 0.12)), ctr, size * 1.25),
    }

    # The face needs the most iteration, so frame a close-up on the Head bone.
    arm = bpy.data.objects.get("AnimalArmature")
    if arm is not None and "Head" in arm.data.bones:
        hb = arm.data.bones["Head"]
        head_ctr = (Vector(hb.head_local) + Vector(hb.tail_local)) / 2
        views["head"] = (Vector((0.90, -0.35, 0.18)), head_ctr, size * 0.26)

    for name, (d, target, scale) in views.items():
        cam_data.ortho_scale = scale
        cam.location = target + d.normalized() * size * 3
        cam.rotation_euler = (target - cam.location).normalized().to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = f"{prefix}_{name}.png"
        bpy.ops.render.render(write_still=True)
        print("WROTE", sc.render.filepath)


# --------------------------------------------------------------------------

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", default="leopard", choices=sorted(VARIANTS))
    ap.add_argument("--out", default="")
    ap.add_argument("--render", default="")
    ap.add_argument("--pose", default="",
                    help="ACTION:FRAME -- pose the rig before rendering, to prove "
                         "the source animations still drive the reshaped mesh")
    ap.add_argument("--diag", action="store_true",
                    help="print material/vertex-group regions instead of guessing from renders")
    ap.add_argument("--no-reshape", action="store_true",
                    help="render the source model untouched, for before/after comparison")
    ap.add_argument("--set", action="append", default=[],
                    help="override a tunable, e.g. --set muzzle_shorten=0.6")
    args = ap.parse_args(argv)

    variant = VARIANTS[args.variant]
    P = dict(PARAMS)
    P.update(variant["params"])
    for override in args.set:
        k, v = override.split("=", 1)
        P[k] = float(v)

    arm_ob = bpy.data.objects["AnimalArmature"]
    mesh_ob = [o for o in bpy.data.objects if o.type == 'MESH'][0]

    bpy.ops.object.mode_set(mode='OBJECT')
    for ob in bpy.data.objects:
        ob.select_set(False)

    name = "SnowLeopard" if args.variant == "snow_leopard" else "Leopard"
    if args.no_reshape:
        log, n = ["(reshape skipped)"], 0
    else:
        log = reshape(mesh_ob, arm_ob, P)
        n = rescale_action_locations(P["body_stretch_y"], 0.0)
        recolor(mesh_ob, variant["colors"])

    mesh_ob.name = name
    mesh_ob.data.name = name

    print(f"--- {name} ---")
    for line in log:
        print("   ", line)
    print(f"    rescaled {n} root-location fcurves")
    print(f"    dims {tuple(round(v, 3) for v in mesh_ob.dimensions)}")

    if args.pose:
        act_name, _, frame = args.pose.partition(":")
        act = bpy.data.actions.get(act_name)
        if act is None:
            print("POSE FAIL: no action", act_name)
        else:
            if arm_ob.animation_data is None:
                arm_ob.animation_data_create()
            arm_ob.animation_data.action = act
            # Blender 5.x slotted actions need an explicit slot binding.
            slots = getattr(act, "slots", None)
            if slots:
                try:
                    arm_ob.animation_data.action_slot = slots[0]
                except Exception as exc:
                    print("slot bind skipped:", exc)
            bpy.context.scene.frame_set(int(frame or 1))
            bpy.context.view_layer.update()
            print(f"POSED {act_name} @ {frame or 1}")

    if args.diag:
        diagnose(mesh_ob, arm_ob)

    if args.out:
        bpy.ops.wm.save_as_mainfile(filepath=args.out)
        print("SAVED", args.out)
    if args.render:
        render_views(args.render)


main()
