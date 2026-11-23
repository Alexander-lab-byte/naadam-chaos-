"""
Naadam Chaos - bean wrestler (bokh) builder for Blender 4.2+ / 5.x

What it makes:
  - "Wrestler": a goofy bean-shaped body (party-game style) wearing a
    zodog (open-front vest with sleeves), shuudag (shorts) and gutal boots
  - "Rig": one simple skeleton (14 bones)
  - 9 animation clips (Actions) named exactly like ANIMATIONS.md
  - Shape key "full_stomach" for the Bayan Khodood rematch

How to use inside Blender:
  Scripting tab -> Open this file -> Run Script.
  Press Space in the viewport to play. Pick a clip in the Action Editor
  (Dope Sheet -> Action Editor) to see other clips.

Optional: set env var NC_OUT=/some/folder to also save .blend and .glb there.
"""
import bpy, bmesh, math, os
from mathutils import Vector, Matrix, Quaternion, Euler
from mathutils.bvhtree import BVHTree

FPS = 30

# ------------------------------------------------------------------ helpers

def clear_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.actions):
        for item in list(coll):
            coll.remove(item)


def make_mat(name, rgb, rough=0.6, double=False):
    m = bpy.data.materials.new(name)
    rgb = tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb)  # sRGB -> linear
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = rough
    m.diffuse_color = (*rgb, 1)
    m.use_backface_culling = not double
    return m


def new_mesh_obj(name, bm, mat, groups):
    """groups: {vertex_group_name: weight} for every vertex, or a callable(co)->dict"""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(mat)
    for poly in me.polygons:
        poly.use_smooth = True
    for v in me.vertices:
        w = groups(v.co) if callable(groups) else groups
        for g, val in w.items():
            if val <= 0:
                continue
            vg = ob.vertex_groups.get(g) or ob.vertex_groups.new(name=g)
            vg.add([v.index], val, 'REPLACE')
    return ob


def ellipsoid(center, size, segs=24, rings=12, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    m = Matrix.Diagonal((*size, 1.0))
    if rot:
        m = rot.to_matrix().to_4x4() @ m
    bmesh.ops.transform(bm, matrix=Matrix.Translation(center) @ m, verts=bm.verts)
    return bm


def capsule(a, b, r, segs=16, rings=10):
    a, b = Vector(a), Vector(b)
    d = b - a
    L = d.length
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    for v in bm.verts:
        if v.co.z > 0:
            v.co.z += L
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(a) @ rot, verts=bm.verts)
    return bm


def smooth(x, a, b):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ sizes
BODY_BOTTOM, BODY_TOP, BODY_R = 0.22, 1.62, 0.40
SH = Vector((0.31, 0.0, 1.00))   # left shoulder
EL = Vector((0.53, 0.0, 0.83))   # left elbow
WR = Vector((0.71, 0.0, 0.68))   # left wrist
HIP = Vector((0.16, 0.0, 0.42))
KNEE = Vector((0.17, 0.0, 0.22))
ANK = Vector((0.17, 0.0, 0.07))


def pear(z):
    """bean shape: wide bottom, a bit narrower head"""
    t = (z - BODY_BOTTOM) / (BODY_TOP - BODY_BOTTOM)
    return 1.0 - 0.10 * max(0.0, min(1.0, t))


def body_weights(co):
    z = co.z
    hips = 1 - smooth(z, 0.62, 0.86)
    head = smooth(z, 1.08, 1.28)
    chest = 1 - hips - head
    return {"hips": hips, "chest": max(0.0, chest), "head": head}


def mirror(v):
    return Vector((-v.x, v.y, v.z))


# ------------------------------------------------------------------ build model

def build_model():
    skin = make_mat("Skin", (0.88, 0.57, 0.38), 0.55)
    team = make_mat("Team", (0.90, 0.05, 0.08), 0.45, double=True)  # recolor in Godot for P2
    boot = make_mat("Boot", (0.36, 0.17, 0.08), 0.5)
    trim = make_mat("Trim", (0.98, 0.80, 0.15), 0.4)
    eye = make_mat("Eye", (0.03, 0.03, 0.04), 0.15)
    white = make_mat("EyeShine", (1, 1, 1), 0.2)
    mouth = make_mat("Mouth", (0.45, 0.06, 0.08), 0.5)

    parts = []

    # --- bean body: a lathe (rings all the way up, so it bends smoothly)
    zb = BODY_BOTTOM + BODY_R
    zt = BODY_TOP - BODY_R
    prof = []                                  # (radius, z) from bottom pole to top pole
    for i in range(9):                         # bottom half-sphere
        a = math.radians(-90 + 90 * i / 8)
        prof.append((BODY_R * math.cos(a), zb + BODY_R * math.sin(a)))
    for i in range(1, 12):                     # straight middle
        prof.append((BODY_R, zb + (zt - zb) * i / 12))
    for i in range(9):                         # top half-sphere
        a = math.radians(90 * i / 8)
        prof.append((BODY_R * math.cos(a), zt + BODY_R * math.sin(a)))
    SEG = 40
    bm = bmesh.new()
    rings = []
    for r, z in prof:
        p = pear(z)
        if r < 1e-4:
            rings.append([bm.verts.new((0, 0, z))])
            continue
        rings.append([bm.verts.new((math.cos(2 * math.pi * k / SEG) * r * p,
                                    math.sin(2 * math.pi * k / SEG) * r * p * 0.9, z)) for k in range(SEG)])
    for lo, hi in zip(rings, rings[1:]):
        for k in range(SEG):
            k2 = (k + 1) % SEG
            if len(lo) == 1:
                bm.faces.new((lo[0], hi[k], hi[k2]))
            elif len(hi) == 1:
                bm.faces.new((lo[k], lo[k2], hi[0]))
            else:
                bm.faces.new((lo[k], lo[k2], hi[k2], hi[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    body_bm = bm.copy()
    body = new_mesh_obj("Body", bm, skin, body_weights)
    parts.append(body)
    bvh = BVHTree.FromBMesh(body_bm)

    def surface(x, z, push=0.0):
        hit = bvh.ray_cast(Vector((x, -3, z)), Vector((0, 1, 0)))
        loc, nrm = hit[0], hit[1]
        return loc + nrm * push, nrm

    def shell(name, keep, mat, offset, trim_band=None):
        sb = body_bm.copy()
        sb.normal_update()
        for v in sb.verts:
            v.co += v.normal * offset
        bmesh.ops.delete(sb, geom=[v for v in sb.verts if not keep(v.co)], context='VERTS')
        return new_mesh_obj(name, sb, mat, body_weights)

    # zodog: covers back + shoulders, chest is open (real bokh vest)
    def zodog_keep(c):
        back = c.y > 0.05
        if not (0.70 < c.z < 1.20 if back else 0.80 < c.z < 1.20):
            return False
        open_front = c.y < -0.02 and abs(c.x) < 0.13 + (1.2 - c.z) * 0.12
        return not open_front
    parts.append(shell("Zodog", zodog_keep, team, 0.018))
    # shuudag: tight shorts
    parts.append(shell("Shuudag", lambda c: c.z < 0.57, team, 0.014))
    # yellow waist trim on shuudag
    parts.append(shell("ShuudagTrim", lambda c: 0.53 < c.z < 0.60, trim, 0.022))

    # --- face (sits on the bean surface, moves with head bone)
    for s in (1, -1):
        p, n = surface(0.12 * s, 1.33, 0.0)
        q = n.to_track_quat('Z', 'Y')
        parts.append(new_mesh_obj("Eye", ellipsoid(p, (0.062, 0.095, 0.03), rot=q), eye, {"head": 1}))
        ps, _ = surface(0.12 * s + 0.022 * s, 1.36, 0.02)
        parts.append(new_mesh_obj("Shine", ellipsoid(ps, (0.016, 0.016, 0.01), 12, 6, rot=q), white, {"head": 1}))
        # thick angry-but-silly eyebrow
        pb, nb = surface(0.12 * s, 1.465, 0.005)
        tilt = Quaternion(nb, math.radians(-14 * s))
        parts.append(new_mesh_obj("Brow", ellipsoid(pb, (0.075, 0.018, 0.022), 16, 8, rot=tilt @ q), eye, {"head": 1}))
    pm, nm = surface(0.0, 1.20, 0.0)
    qm = nm.to_track_quat('Z', 'Y')
    parts.append(new_mesh_obj("Mouth", ellipsoid(pm, (0.09, 0.035, 0.02), rot=qm), mouth, {"head": 1}))

    # --- arms + legs (rigid pieces, each glued to one bone)
    for side, sx in (("L", 1), ("R", -1)):
        f = (lambda v: v) if sx == 1 else mirror
        parts.append(new_mesh_obj("Sleeve", capsule(f(SH), f(EL), 0.112), team, {f"upper_arm.{side}": 1}))
        parts.append(new_mesh_obj("Cuff", capsule(f(EL.lerp(SH, 0.12)), f(EL), 0.118), trim, {f"upper_arm.{side}": 1}))
        parts.append(new_mesh_obj("Forearm", capsule(f(EL), f(WR), 0.092), skin, {f"forearm.{side}": 1}))
        hand_c = f(WR + (WR - EL).normalized() * 0.07)
        parts.append(new_mesh_obj("Hand", ellipsoid(hand_c, (0.118, 0.118, 0.118), 16, 10), skin, {f"hand.{side}": 1}))
        parts.append(new_mesh_obj("Thigh", capsule(f(HIP), f(KNEE), 0.105), skin, {f"thigh.{side}": 1}))
        parts.append(new_mesh_obj("Shin", capsule(f(KNEE), f(ANK), 0.095), boot, {f"shin.{side}": 1}))
        # gutal: boot with the famous curled-up toe
        parts.append(new_mesh_obj("Gutal", ellipsoid(f(ANK + Vector((0, -0.05, -0.01))), (0.115, 0.17, 0.075)), boot, {f"shin.{side}": 1}))
        toe = capsule(f(ANK + Vector((0, -0.17, 0.0))), f(ANK + Vector((0, -0.25, 0.09))), 0.035, 10, 6)
        parts.append(new_mesh_obj("GutalToe", toe, trim, {f"shin.{side}": 1}))
        parts.append(new_mesh_obj("GutalTop", capsule(f(ANK + Vector((0, 0, 0.1))), f(ANK + Vector((0, 0, 0.13))), 0.105, 16, 6), trim, {f"shin.{side}": 1}))

    # join everything into ONE mesh (one draw call in Godot)
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "Wrestler"
    body.data.name = "Wrestler"
    body_bm.free()
    # UV map (Godot needs it; also lets you paint textures later)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(island_margin=0.02)
    bpy.ops.object.mode_set(mode='OBJECT')

    # Bayan Khodood "full stomach" shape key (belly + shorts + vest grow together)
    body.shape_key_add(name="Basis")
    sk = body.shape_key_add(name="full_stomach")
    for i, v in enumerate(body.data.vertices):
        c = v.co
        if 0.3 < c.z < 1.05 and abs(c.x) < 0.5:
            fz = math.sin(math.pi * (c.z - 0.3) / 0.75)
            front = max(0.0, -c.y) / 0.36
            radial = Vector((c.x, c.y * 1.6, 0)) * (0.10 * fz)
            sk.data[i].co = c + radial + Vector((0, -0.12 * fz * front, 0))
    return body


# ------------------------------------------------------------------ rig

BONES = [
    # name, head, tail, parent
    ("root", (0, 0, 0), (0, 0, 0.25), None),
    ("hips", (0, 0, 0.42), (0, 0, 0.80), "root"),
    ("chest", (0, 0, 0.80), (0, 0, 1.12), "hips"),
    ("head", (0, 0, 1.12), (0, 0, 1.62), "chest"),
]
for side, sx in (("L", 1), ("R", -1)):
    s = lambda v: tuple(Vector((v.x * sx, v.y, v.z)))
    hand_tip = WR + (WR - EL).normalized() * 0.16
    BONES += [
        (f"upper_arm.{side}", s(SH), s(EL), "chest"),
        (f"forearm.{side}", s(EL), s(WR), f"upper_arm.{side}"),
        (f"hand.{side}", s(WR), s(hand_tip), f"forearm.{side}"),
        (f"thigh.{side}", s(HIP), s(KNEE), "hips"),
        (f"shin.{side}", s(KNEE), s(ANK), f"thigh.{side}"),
    ]


def build_rig(mesh):
    arm_data = bpy.data.armatures.new("Rig")
    rig = bpy.data.objects.new("Rig", arm_data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    for name, h, t, parent in BONES:
        eb = arm_data.edit_bones.new(name)
        eb.head, eb.tail, eb.roll = h, t, 0.0
        if parent:
            eb.parent = arm_data.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode='OBJECT')
    rig.show_in_front = True
    mesh.parent = rig
    mod = mesh.modifiers.new("Armature", 'ARMATURE')
    mod.object = rig
    return rig


# ------------------------------------------------------------------ animation system
#
# Poses are written in "body space" so they are easy to read:
#   r   = rotation in degrees (x, y, z) around the armature axes
#         +x leans forward, +y tilts to the character's left, +z turns left
#   aim = direction a limb bone points to (arms: relative to chest,
#         legs: relative to hips). Character faces -Y, +X is its LEFT side.
#   l   = location offset (meters), s = scale (x, along-bone, z)

LIMB_ROOTS = {"upper_arm.L", "upper_arm.R", "thigh.L", "thigh.R"}


def mir_pose(p):
    """swap left/right of a pose dict"""
    out = {}
    for b, spec in p.items():
        nb = b.replace(".L", ".X").replace(".R", ".L").replace(".X", ".R")
        ns = {}
        for k, v in spec.items():
            if k == "r":
                ns[k] = (v[0], -v[1], -v[2])
            elif k in ("aim", "l"):
                ns[k] = (-v[0], v[1], v[2])
            else:
                ns[k] = v
        out[nb] = ns
    return out


def merge(*poses):
    out = {}
    for p in poses:
        for b, s in p.items():
            out.setdefault(b, {}).update(s)
    return out


def arms(ua, fa, side="LR", hand=None):
    """same arm pose on both sides (mirrored)"""
    p = {"upper_arm.L": {"aim": ua}, "forearm.L": {"aim": fa}}
    if hand:
        p["hand.L"] = {"aim": hand}
    if side == "L":
        return p
    m = mir_pose(p)
    return m if side == "R" else merge(p, m)


def legs(th, sh, side="LR"):
    p = {"thigh.L": {"aim": th}, "shin.L": {"aim": sh}}
    if side == "L":
        return p
    m = mir_pose(p)
    return m if side == "R" else merge(p, m)


def make_action(rig, name, keys, loop):
    """keys: list of (frame, pose_dict). Every bone gets a key on every frame."""
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = act
    bones = rig.data.bones
    order = [b[0] for b in BONES]
    last_q = {}
    for frame, pose in keys:
        acc = {}
        for bname in order:
            pb = rig.pose.bones[bname]
            pb.rotation_mode = 'QUATERNION'
            spec = pose.get(bname, {})
            bone = bones[bname]
            qr = bone.matrix_local.to_quaternion()
            parent_acc = Quaternion() if (bname in LIMB_ROOTS or bone.parent is None) else acc.get(bone.parent.name, Quaternion())
            if "aim" in spec:
                rest_dir = (bone.tail_local - bone.head_local).normalized()
                target = parent_acc.inverted() @ Vector(spec["aim"]).normalized()
                qw = rest_dir.rotation_difference(target)
            else:
                r = spec.get("r", (0, 0, 0))
                qw = Euler([math.radians(a) for a in r], 'XYZ').to_quaternion()
            acc[bname] = parent_acc @ qw
            ql = qr.inverted() @ qw @ qr
            if bname in last_q and last_q[bname].dot(ql) < 0:
                ql = -ql
            last_q[bname] = ql
            pb.rotation_quaternion = ql
            pb.location = qr.inverted() @ Vector(spec.get("l", (0, 0, 0)))
            s = spec.get("s", 1.0)
            pb.scale = (s, s, s) if isinstance(s, (int, float)) else s
            pb.keyframe_insert("rotation_quaternion", frame=frame, group=bname)
            pb.keyframe_insert("location", frame=frame, group=bname)
            pb.keyframe_insert("scale", frame=frame, group=bname)
    act.frame_range = (keys[0][0], keys[-1][0])
    act.use_frame_range = True
    act.use_cyclic = loop
    return act


# ------------------------------------------------------------------ the clips

STANCE = merge(
    {"hips": {"r": (6, 0, 0)}, "head": {"r": (-6, 0, 0)}},
    arms((0.55, -0.55, -0.6), (0.25, -0.95, -0.05)),        # wrestler ready hands
    legs((0.12, -0.25, -1), (0.02, 0.2, -1)),                # knees a bit bent
)


def clips():
    C = {}

    # IDLE - breathing, little sway (loop 1.6 s)
    breathe = merge(STANCE, {
        "root": {"l": (0, 0, -0.015)},
        "hips": {"r": (8, 2, 0), "s": (1.04, 0.96, 1.04)},
        "chest": {"r": (3, 0, 0)},
        "head": {"r": (-3, -3, 4)},
    }, arms((0.6, -0.45, -0.68), (0.3, -0.9, -0.2)))
    C["idle"] = ([(0, STANCE), (24, breathe), (48, STANCE)], True)

    # WALK - waddly party-game run (loop 0.67 s, code speeds it up)
    contact = merge(
        {"root": {"l": (0, 0, -0.02)},
         "hips": {"r": (14, -7, 8), "s": (1.06, 0.93, 1.06)},
         "chest": {"r": (2, 0, 6)},
         "head": {"r": (-12, 5, -10)}},
        legs((0.05, -0.75, -0.65), (0.0, -0.25, -1), "L"),
        legs((0.05, 0.6, -0.8), (0.0, 0.9, -0.5), "R"),
        arms((0.6, 0.55, -0.35), (0.35, 0.5, 0.25), "L"),     # left arm back
        arms((0.45, -0.75, -0.25), (0.2, -0.75, 0.55), "R"),  # right arm forward
    )
    passing = merge(
        {"root": {"l": (0, 0, 0.07)},
         "hips": {"r": (12, 0, 0), "s": (0.95, 1.08, 0.95)},
         "head": {"r": (-6, 0, 0)}},
        legs((0.05, -0.1, -1), (0.0, 0.6, -0.8), "L"),
        legs((0.05, 0.05, -1), (0.0, 0.1, -1), "R"),
        arms((0.75, 0.0, -0.55), (0.5, -0.4, -0.2)),
    )
    C["walk"] = ([(0, contact), (5, passing), (10, mir_pose(contact)), (15, mir_pose(passing)), (20, contact)], True)

    # PUSH - wind up, both arms SHOOT forward (0.33 s)
    windup = merge(STANCE, {"hips": {"r": (-8, 0, 0)}, "chest": {"r": (-6, 0, 0)}, "head": {"r": (4, 0, 0)},
                            "root": {"l": (0, 0.04, 0)}},
                   arms((0.7, 0.45, -0.35), (0.15, -0.5, 0.85)))
    thrust = merge(STANCE, {"hips": {"r": (20, 0, 0), "s": (0.94, 1.1, 0.94)}, "chest": {"r": (6, 0, 0)},
                            "head": {"r": (-22, 0, 0)}, "root": {"l": (0, -0.1, 0)}},
                   arms((0.22, -1, 0.08), (0.12, -1, 0.06)),
                   legs((0.1, 0.45, -0.9), (0.0, 0.5, -0.85), "R"))
    hold = merge(thrust, {"hips": {"r": (15, 0, 0), "s": 1.0}, "root": {"l": (0, -0.06, 0)}})
    C["push"] = ([(0, STANCE), (3, windup), (6, thrust), (10, hold)], False)

    # HIT - got shoved: lean back, arms flail (0.43 s)
    flail = merge({"root": {"l": (0, 0.08, 0.04)},
                   "hips": {"r": (-24, 4, 12), "s": (1.1, 0.88, 1.1)},
                   "chest": {"r": (-8, 0, 0)}, "head": {"r": (-25, 0, -12)}},
                  arms((0.6, 0.3, 0.75), (0.3, -0.3, 1.0), "L"),
                  arms((0.75, -0.2, 0.55), (0.5, 0.5, 0.8), "R"),
                  legs((0.12, -0.7, -0.75), (0, -0.2, -1), "L"),
                  legs((0.15, 0.1, -1), (0, 0.1, -1), "R"))
    flail2 = merge(mir_pose(flail), {"hips": {"r": (-10, -3, -6), "s": (0.96, 1.05, 0.96)},
                                     "head": {"r": (12, 0, 8)}, "root": {"l": (0, 0.05, 0)}})
    C["hit"] = ([(0, STANCE), (3, flail), (8, flail2), (13, STANCE)], False)

    # EAGLE DANCE (devekh) - slow wing flaps, high knee hops, turning (loop 1.6 s)
    def wings(up, lag):
        ua = (1, 0.15, 0.55) if up else (1, 0.15, -0.2)
        fa = (1, 0.25, 0.55 + lag) if up else (1, 0.25, -0.2 + lag)
        return arms(ua, fa, hand=fa)
    proud = {"hips": {"r": (14, 0, 0)}, "chest": {"r": (-6, 0, 0)}, "head": {"r": (-14, 0, 0)}}
    stepL = merge(proud, legs((0.25, -0.95, 0.1), (0.05, 0.0, -1), "L"), legs((0.12, 0.05, -1), (0, 0.05, -1), "R"))
    stepR = mir_pose(stepL)
    low = merge(proud, legs((0.12, -0.2, -1), (0.0, 0.2, -1)), {"root": {"l": (0, 0, -0.03)}, "hips": {"s": (1.06, 0.92, 1.06)}})
    ED = []
    for i, (base, turn, hop) in enumerate([(stepL, 18, 0.10), (low, 0, -0.03), (stepR, -18, 0.10), (low, 0, -0.03)]):
        f0 = i * 12
        pose_up = merge(base, wings(True, -0.35), {"root": {"r": (0, 0, turn), "l": (0, 0, hop)}})
        pose_dn = merge(low, wings(False, 0.35), {"root": {"r": (0, 0, turn * 0.5), "l": (0, 0, -0.03)}})
        ED += [(f0, pose_up), (f0 + 6, pose_dn)]
    ED.append((48, ED[0][1]))
    C["eagle_dance"] = (ED, True)

    # LOSE - deflated slump, slow sad sway (loop 2 s)
    slump = merge({"hips": {"r": (18, 0, 4), "s": (1.07, 0.9, 1.07)}, "chest": {"r": (14, 0, 0)},
                   "head": {"r": (28, 0, -6)}, "root": {"l": (0, 0, -0.03)}},
                  arms((0.3, -0.1, -1), (0.12, -0.2, -1)),
                  legs((0.14, -0.15, -1), (0.0, 0.25, -1)))
    slump2 = merge(slump, {"hips": {"r": (22, 0, -4), "s": (1.1, 0.87, 1.1)}, "head": {"r": (32, 0, 8)}})
    C["lose"] = ([(0, slump), (30, slump2), (60, slump)], True)

    # PALM BRACE - slam both palms down to save yourself (0.4 s, holds last pose)
    brace = merge({"root": {"l": (0, -0.05, -0.08)},
                   "hips": {"r": (38, 0, 0), "s": (1.06, 0.92, 1.06)}, "chest": {"r": (14, 0, 0)},
                   "head": {"r": (-38, 0, 0)}},
                  arms((0.4, -0.8, -0.45), (0.3, -0.55, -0.8), hand=(0.2, -0.3, -1)),
                  legs((0.14, -0.55, -0.8), (0.0, 0.5, -0.85)))
    impact = merge(brace, {"hips": {"s": (1.14, 0.84, 1.14)}, "root": {"l": (0, -0.05, -0.11)}})
    settle = merge(brace, {"hips": {"r": (34, 0, 0), "s": (1.03, 0.97, 1.03)}})
    C["palm_brace"] = ([(0, STANCE), (4, brace), (7, impact), (12, settle)], False)

    # BAYAN KHODOOD STRUT - chest out, nose up, hands on hips, slow arrogant steps (loop 1.33 s)
    akimbo = arms((0.85, 0.35, -0.4), (-0.55, 0.15, -0.55), hand=(-0.6, 0.0, -0.4))
    boss = {"hips": {"r": (-8, 0, 0)}, "chest": {"r": (-14, 0, 0), "s": (1.06, 1.0, 1.06)}, "head": {"r": (-22, 0, 0)}}
    s1 = merge(boss, akimbo, {"root": {"r": (0, 6, 12), "l": (0, 0, 0.05)}, "head": {"r": (-22, 8, -10)}},
               legs((0.1, -0.85, -0.35), (0.0, 0.15, -1), "L"), legs((0.1, 0.1, -1), (0, 0.1, -1), "R"))
    p1 = merge(boss, akimbo, {"root": {"l": (0, 0, -0.02)}, "hips": {"s": (1.05, 0.94, 1.05)}},
               legs((0.12, -0.15, -1), (0.0, 0.15, -1)))
    C["bayan_khodood_strut"] = ([(0, s1), (10, p1), (20, mir_pose(s1)), (30, mir_pose(p1)), (40, s1)], True)

    # STUMBLE - trip, windmill arms, catch balance (0.8 s) - party-game classic
    trip = merge({"hips": {"r": (32, 0, 6)}, "head": {"r": (-10, 0, 0)}, "root": {"l": (0, -0.05, 0)}},
                 arms((0.5, -0.6, 0.6), (0.2, -0.6, 0.8), "L"), arms((0.6, 0.6, 0.2), (0.3, 0.8, 0.4), "R"),
                 legs((0.1, 0.8, -0.5), (0, 0.95, -0.2), "R"), legs((0.1, -0.2, -1), (0, 0.3, -1), "L"))
    wind = merge({"hips": {"r": (44, -4, -8), "s": (0.95, 1.08, 0.95)}, "head": {"r": (-28, 0, 10)}, "root": {"l": (0, -0.08, -0.04)}},
                 arms((0.5, -0.6, 0.6), (0.2, -0.6, 0.8), "R"), arms((0.6, 0.6, 0.2), (0.3, 0.8, 0.4), "L"),
                 legs((0.1, -0.6, -0.8), (0, -0.1, -1), "R"), legs((0.1, 0.3, -1), (0, 0.7, -0.7), "L"))
    wind2 = merge(mir_pose(wind), {"hips": {"r": (36, 4, 8)}})
    catch = merge(STANCE, {"hips": {"r": (-12, 0, 0), "s": (1.08, 0.9, 1.08)}, "head": {"r": (10, 0, 0)},
                           "root": {"l": (0, -0.03, -0.03)}}, arms((0.95, 0.05, 0.35), (0.9, 0.0, 0.5)))
    C["stumble"] = ([(0, STANCE), (4, trip), (9, wind), (14, wind2), (19, catch), (24, STANCE)], False)
    return C


# ------------------------------------------------------------------ main

def build():
    clear_scene()
    scn = bpy.context.scene
    scn.render.fps = FPS
    mesh = build_model()
    rig = build_rig(mesh)
    actions = {}
    for name, (keys, loop) in clips().items():
        actions[name] = make_action(rig, name, keys, loop)
    rig.animation_data.action = actions["walk"]
    scn.frame_start, scn.frame_end = 0, 20
    return rig, mesh, actions


def export(rig, mesh, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = rig
    kw = dict(filepath=os.path.join(out_dir, "bokh_wrestler.glb"), export_format='GLB',
              use_selection=True, export_animations=True, export_animation_mode='ACTIONS',
              export_morph=True, export_force_sampling=True, export_frame_range=False)
    try:
        bpy.ops.export_scene.gltf(**kw)
    except TypeError:
        kw.pop("export_animation_mode")
        bpy.ops.export_scene.gltf(**kw)


if __name__ == "__main__":
    rig, mesh, actions = build()
    out = os.environ.get("NC_OUT")
    if out:
        export(rig, mesh, out)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "bokh_wrestler.blend"))
    print("Built clips:", ", ".join(actions))
