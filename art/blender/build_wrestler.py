"""
Naadam Chaos - bokh wrestler builder (v2: chunky stylized human) for Blender 4.2+ / 5.x

What it makes:
  - "Wrestler": a chunky, cartoony Mongolian wrestler (big belly, broad
    shoulders, short strong legs) with a real face: eyes, thick brows, round
    nose, wrestler's ears, red wind-burned cheeks, buzz-cut hair.
  - Costume: zodog (short-sleeved jacket, open chest, tied with a cord around
    the belly), shuudag (tight briefs), gutal (boots with curled-up toes and
    appliqué stripes). Material "Team" = zodog + shuudag (Godot recolors it).
  - "Rig": the same 14-bone skeleton names as v1, so the game code still works.
  - Animation clips (Actions): the 9 old ones + grip / throw clips for the
    real bokh techniques (mekh). See ANIMATIONS.md.
  - Shape key "full_stomach" for the Bayan Khodood rematch.

How to use inside Blender:
  Scripting tab -> Open this file -> Run Script. Space = play.
  Pick a clip in Dope Sheet -> Action Editor.

Optional: env var NC_OUT=/some/folder also saves bokh_wrestler.blend + .glb there.
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


def make_mat(name, rgb, rough=0.6, double=False, sheen=0.0):
    m = bpy.data.materials.new(name)
    rgb = tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb)  # sRGB -> linear
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = rough
    if sheen and "Sheen Weight" in bsdf.inputs:
        bsdf.inputs["Sheen Weight"].default_value = sheen
    m.diffuse_color = (*rgb, 1)
    m.use_backface_culling = not double
    return m


def link(name, bm, mat=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if mat:
        me.materials.append(mat)
    for poly in me.polygons:
        poly.use_smooth = True
    return ob


def ellipsoid(center, size, segs=24, rings=14, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    m = Matrix.Diagonal((*size, 1.0))
    if rot:
        m = rot.to_matrix().to_4x4() @ m
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(center)) @ m, verts=bm.verts)
    return bm


def capsule(a, b, r, segs=18, rings=10, r2=None):
    """capsule from a to b. r2 = radius at b (tapered)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    L = d.length
    r2 = r if r2 is None else r2
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    for v in bm.verts:
        top = v.co.z > 0
        rr = r2 if top else r
        v.co = Vector((v.co.x * rr, v.co.y * rr, v.co.z * rr + (L if top else 0)))
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(a) @ rot, verts=bm.verts)
    return bm


def smooth(x, a, b):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def mirror(v):
    return Vector((-v.x, v.y, v.z))


def apply_mod(ob, mod):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=mod.name)


def join(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


# ------------------------------------------------------------------ proportions
# Character faces -Y (Blender front view). +X is the character's LEFT. Feet at z=0.
SH = Vector((0.36, 0.0, 1.21))    # left shoulder joint
EL = Vector((0.55, 0.02, 0.99))   # left elbow
WR = Vector((0.69, -0.02, 0.80))  # left wrist
HIP = Vector((0.15, 0.0, 0.62))
KNEE = Vector((0.17, -0.02, 0.35))
ANK = Vector((0.17, 0.0, 0.10))
HEAD_C = Vector((0.0, -0.02, 1.53))
HEAD_R = Vector((0.155, 0.16, 0.178))

BONES = [
    # name, head, tail, parent
    ("root", (0, 0, 0), (0, 0, 0.25), None),
    ("hips", (0, 0, 0.62), (0, 0, 0.95), "root"),
    ("chest", (0, 0, 0.95), (0, 0, 1.30), "hips"),
    ("head", (0, 0, 1.30), (0, 0, 1.72), "chest"),
]
for _side, _sx in (("L", 1), ("R", -1)):
    _s = lambda v, sx=_sx: tuple(Vector((v.x * sx, v.y, v.z)))
    _hand_tip = WR + (WR - EL).normalized() * 0.17
    BONES += [
        (f"upper_arm.{_side}", _s(SH), _s(EL), "chest"),
        (f"forearm.{_side}", _s(EL), _s(WR), f"upper_arm.{_side}"),
        (f"hand.{_side}", _s(WR), _s(_hand_tip), f"forearm.{_side}"),
        (f"thigh.{_side}", _s(HIP), _s(KNEE), "hips"),
        (f"shin.{_side}", _s(KNEE), _s(ANK), f"thigh.{_side}"),
    ]


def seg_dist(p, a, b):
    a, b = Vector(a), Vector(b)
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (a + ab * t - p).length, t


# Skin weights: each vertex follows the bones closest to it, blended softly.
# A few region rules stop e.g. the belly from following the arms.
def auto_weights(co, allow=None):
    d = {}
    for name, h, t, parent in BONES:
        if name == "root":
            continue
        if allow and name not in allow:
            continue
        dist, tt = seg_dist(co, h, t)
        # region rules
        if name.startswith(("thigh", "shin")) and co.z > 0.72:
            continue
        if name.startswith(("upper_arm", "forearm", "hand")):
            side = 1 if name.endswith(".L") else -1
            if co.x * side < 0.22:
                continue
        if name == "head" and co.z < 1.27:
            continue
        if name == "hips" and co.z > 1.12:
            continue
        d[name] = dist
    if not d:
        return {"hips": 1.0}
    dmin = min(d.values())
    w = {k: math.exp(-(v - dmin) / 0.035) for k, v in d.items() if v - dmin < 0.14}
    s = sum(w.values())
    w = {k: v / s for k, v in w.items() if v / s > 0.02}
    s = sum(w.values())
    return {k: v / s for k, v in w.items()}


def set_weights(ob, fn):
    for v in ob.data.vertices:
        for g, val in fn(v.co).items():
            vg = ob.vertex_groups.get(g) or ob.vertex_groups.new(name=g)
            vg.add([v.index], val, 'REPLACE')


def dominant(co):
    w = auto_weights(co)
    return max(w, key=w.get)


# ------------------------------------------------------------------ body

def build_body(skin):
    P = []
    E = lambda c, s, **k: P.append(ellipsoid(c, s, **k))
    C = lambda a, b, r, r2=None: P.append(capsule(a, b, r, r2=r2))
    # torso: big round belly, wide chest, strong back
    E((0, -0.035, 0.79), (0.285, 0.265, 0.25))        # belly
    E((0, -0.075, 0.74), (0.22, 0.22, 0.17))          # belly front bulge
    E((0, 0.0, 0.65), (0.25, 0.2, 0.13))              # pelvis
    E((0, 0.0, 1.06), (0.30, 0.2, 0.22))              # ribcage
    E((0, 0.045, 1.2), (0.3, 0.15, 0.11))             # upper back / traps
    for s in (1, -1):
        E((0.12 * s, -0.115, 1.12), (0.13, 0.08, 0.1))  # pecs
        E((0.1 * s, 0.1, 0.62), (0.13, 0.12, 0.12))     # glutes
        E((0.36 * s, 0.0, 1.19), (0.13, 0.12, 0.12))    # deltoids
        E((0.21 * s, 0.03, 1.27), (0.12, 0.09, 0.07))   # trapezius slope
    C((0, 0.0, 1.22), (0, -0.005, 1.4), 0.1)           # thick neck
    E(HEAD_C, HEAD_R, segs=32, rings=18)               # head
    E((0, -0.05, 1.44), (0.125, 0.11, 0.085))          # jaw / cheeks
    for side in (1, -1):
        f = (lambda v: v) if side == 1 else mirror
        C(f(SH), f(EL), 0.1, 0.082)                    # upper arm (beefy)
        E(f(SH.lerp(EL, 0.45)) + Vector((0, 0.0, 0.0)), (0.105, 0.1, 0.12))   # biceps
        C(f(EL), f(WR), 0.082, 0.062)                  # forearm
        C(f(HIP), f(KNEE), 0.135, 0.095)               # thigh (thick)
        C(f(KNEE), f(ANK), 0.09, 0.065)                # calf (inside boot)
    parts = [link("part", bm) for bm in P]
    body = join(parts, "Body")
    # union everything into one smooth skin
    rm = body.modifiers.new("Remesh", 'REMESH')
    rm.mode = 'VOXEL'
    rm.voxel_size = 0.011
    apply_mod(body, rm)
    sm = body.modifiers.new("Smooth", 'SMOOTH')
    sm.factor = 0.6
    sm.iterations = 10
    apply_mod(body, sm)
    body.data.materials.append(skin)
    for p in body.data.polygons:
        p.use_smooth = True
    return body


def build_hands(skin):
    out = []
    for side in (1, -1):
        f = (lambda v: v) if side == 1 else mirror
        d = (WR - EL).normalized()
        c = WR + d * 0.075
        # mitten-ish chunky hand: palm + 4 fingers + thumb
        rot = Vector((0, 0, -1)).rotation_difference(d)
        bms = [ellipsoid(Vector((0, 0, 0)), (0.058, 0.032, 0.062), 16, 10)]
        for i in range(4):
            x = -0.033 + i * 0.022
            bms.append(capsule((x, 0, -0.05), (x, -0.012, -0.105 + abs(i - 1.5) * 0.008), 0.014, 10, 6))
        bms.append(capsule((0.05, -0.01, -0.01), (0.072, -0.04, -0.05), 0.016, 10, 6))
        objs = []
        for bm in bms:
            m = rot.to_matrix().to_4x4()
            mtx = Matrix.Translation(c) @ m if side == 1 else Matrix.Translation(mirror(c)) @ Matrix.Scale(-1, 4, (1, 0, 0)) @ m
            bmesh.ops.transform(bm, matrix=mtx, verts=bm.verts)
            if side == -1:
                bmesh.ops.reverse_faces(bm, faces=bm.faces)
            objs.append(link("hand", bm, skin))
        out.append(join(objs, "Hand"))
    return out


# ------------------------------------------------------------------ costume

def decimate(ob, tris):
    n = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if n > tris:
        dc = ob.modifiers.new("Decimate", 'DECIMATE')
        dc.ratio = tris / n
        apply_mod(ob, dc)


def shell_cut(body, name, offset, planes, keep, mat, tris=2500, thick=0.008):
    """A copy of the skin pushed out by `offset`, sliced along `planes`
    (so the cloth edges are clean straight lines), keeping faces where keep(center)."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * offset
    for co, no in planes:
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=Vector(co), plane_no=Vector(no))
    kill = [f for f in bm.faces if not keep(f.calc_center_median())]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    ob = link(name, bm, mat)
    decimate(ob, tris)
    so = ob.modifiers.new("Solid", 'SOLIDIFY')
    so.thickness = thick
    so.offset = 1.0
    apply_mod(ob, so)
    return ob


def arm_t(co, side):
    sh, el = (SH, EL) if side > 0 else (mirror(SH), mirror(EL))
    return seg_dist(co, sh, el)[1]


def leg_t(co, side):
    hp, kn = (HIP, KNEE) if side > 0 else (mirror(HIP), mirror(KNEE))
    return seg_dist(co, hp, kn)[1]


def arm_plane(side, t):
    sh, el = (SH, EL) if side > 0 else (mirror(SH), mirror(EL))
    return (sh.lerp(el, t), (el - sh).normalized())


def leg_plane(side, t):
    hp, kn = (HIP, KNEE) if side > 0 else (mirror(HIP), mirror(KNEE))
    return (hp.lerp(kn, t), (kn - hp).normalized())


SLEEVE_T, Z_BOTTOM, Z_COLLAR, OPEN_X = 0.6, 0.71, 1.25, 0.2


def zodog_region(c, band=False):
    part = dominant(c)
    if part.startswith("upper_arm"):
        t = arm_t(c, 1 if part.endswith(".L") else -1)
        return (SLEEVE_T - 0.075 < t < SLEEVE_T) if band else t < SLEEVE_T
    if part not in ("hips", "chest") or c.z < Z_BOTTOM or c.z > 1.34:
        return False
    if abs(c.x) < OPEN_X and c.z > Z_COLLAR:            # neck opening
        return False
    if c.y < 0 and abs(c.x) < OPEN_X:                    # OPEN chest + belly (real zodog)
        return False
    if not band:
        return True
    return (c.z < Z_BOTTOM + 0.035 or (c.y < 0 and abs(c.x) < OPEN_X + 0.035)
            or (abs(c.x) < OPEN_X + 0.035 and c.z > Z_COLLAR - 0.035))


def shuudag_region(c, band=False):
    part = dominant(c)
    if part.startswith("thigh"):
        t = leg_t(c, 1 if part.endswith(".L") else -1)
        return (0.16 < t < 0.22) if band else t < 0.22
    if part != "hips" or c.z > 0.69:
        return False
    return c.z > 0.655 if band else True


def build_costume(body, team, trim, cord_mat):
    zp = [((0, 0, Z_BOTTOM), (0, 0, 1)), ((0, 0, Z_BOTTOM + 0.035), (0, 0, 1)), ((0, 0, Z_COLLAR), (0, 0, 1)),
          ((0, 0, Z_COLLAR - 0.035), (0, 0, 1)), ((0, 0, 0), (0, 1, 0))]
    for sx in (1, -1):
        zp += [((OPEN_X * sx, 0, 0), (1, 0, 0)), (((OPEN_X + 0.035) * sx, 0, 0), (1, 0, 0)),
               arm_plane(sx, SLEEVE_T), arm_plane(sx, SLEEVE_T - 0.075)]
    sp = [((0, 0, 0.69), (0, 0, 1)), ((0, 0, 0.655), (0, 0, 1))]
    for sx in (1, -1):
        sp += [leg_plane(sx, 0.22), leg_plane(sx, 0.16)]
    parts = [
        shell_cut(body, "Zodog", 0.012, zp, zodog_region, team, 3500),
        shell_cut(body, "ZodogTrim", 0.018, zp, lambda c: zodog_region(c, True), trim, 6000),
        shell_cut(body, "Shuudag", 0.01, sp, shuudag_region, team, 1500),
        shell_cut(body, "ShuudagTrim", 0.015, sp, lambda c: shuudag_region(c, True), trim, 3000),
    ]
    # the zodog cord: tied around the belly, knot in front (rays from INSIDE the belly)
    bvh = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    pts = []
    for i in range(40):
        a = 2 * math.pi * i / 40
        dirv = Vector((math.cos(a), math.sin(a), 0))
        hit = bvh.ray_cast(Vector((0, 0, 0.75)), dirv)
        pts.append(hit[0] + dirv * 0.014)
    cords = [link("cord", capsule(a, b, 0.011, 8, 4), cord_mat) for a, b in zip(pts, pts[1:] + pts[:1])]
    front = pts[30]  # -Y side (a=270deg)
    cords.append(link("knot", ellipsoid(front + Vector((0, -0.012, 0)), (0.026, 0.02, 0.022), 10, 6), cord_mat))
    for dx, dz in ((0.03, -0.09), (-0.025, -0.1)):
        cords.append(link("tail", capsule(front, front + Vector((dx, -0.02, dz)), 0.009, 8, 4), cord_mat))
    parts.append(join(cords, "Cord"))
    return parts


def build_gutal(boot, boot_trim, sole):
    out = []
    for side in (1, -1):
        f = (lambda v: v) if side == 1 else mirror
        objs = []
        # shaft (lathe around the calf)
        bm = bmesh.new()
        rings = []
        prof = [(0.0, 0.098), (0.06, 0.1), (0.14, 0.1), (0.19, 0.105), (0.23, 0.112), (0.25, 0.114)]
        for z, r in prof:
            rings.append([bm.verts.new(f(Vector((ANK.x + math.cos(2 * math.pi * k / 20) * r,
                                                ANK.y + math.sin(2 * math.pi * k / 20) * r * 1.05, 0.06 + z)))) for k in range(20)])
        for lo, hi in zip(rings, rings[1:]):
            for k in range(20):
                k2 = (k + 1) % 20
                bm.faces.new((lo[k], lo[k2], hi[k2], hi[k]) if side == 1 else (lo[k], hi[k], hi[k2], lo[k2]))
        objs.append(link("shaft", bm, boot))
        # foot: long, then the famous upturned toe
        objs.append(link("foot", ellipsoid(f(ANK + Vector((0, -0.06, -0.035))), (0.105, 0.17, 0.07)), boot))
        toe_a = ANK + Vector((0, -0.19, -0.03))
        toe_b = ANK + Vector((0, -0.27, 0.02))
        toe_c = ANK + Vector((0, -0.28, 0.1))
        objs.append(link("toe", capsule(f(toe_a), f(toe_b), 0.05, 12, 6, r2=0.03), boot))
        objs.append(link("toe2", capsule(f(toe_b), f(toe_c), 0.03, 12, 6, r2=0.016), boot))
        objs.append(link("sole", ellipsoid(f(ANK + Vector((0, -0.07, -0.085))), (0.11, 0.2, 0.022)), sole))
        # appliqué: top band, front stripe, side spirals (simple rings)
        objs.append(link("band", capsule(f(ANK + Vector((0, 0, 0.215))), f(ANK + Vector((0, 0, 0.235))), 0.12, 20, 4), boot_trim))
        objs.append(link("band2", capsule(f(ANK + Vector((0, 0, 0.05))), f(ANK + Vector((0, 0, 0.065))), 0.106, 20, 4), boot_trim))
        objs.append(link("stripe", capsule(f(ANK + Vector((0, -0.105, 0.08))), f(ANK + Vector((0, -0.112, 0.21))), 0.012, 8, 4), boot_trim))
        objs.append(link("stripe2", capsule(f(ANK + Vector((0, -0.09, 0.0))), f(toe_b + Vector((0, 0.02, 0.03))), 0.011, 8, 4), boot_trim))
        for zz in (0.12, 0.2):
            c = f(ANK + Vector((0.103, 0, zz)))
            if side == -1:
                c = mirror(ANK + Vector((0.103, 0, zz)))
            objs.append(link("dot", ellipsoid(c, (0.012, 0.03, 0.03), 10, 6), boot_trim))
        g = join(objs, "Gutal")
        out.append(g)
    return out


# ------------------------------------------------------------------ face + hair

def build_face(body, mats):
    bvh = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())

    def surf(x, z, push=0.0):
        hit = bvh.ray_cast(Vector((x, -1, z)), Vector((0, 1, 0)))
        return hit[0] + hit[1] * push, hit[1]

    objs = []
    for s in (1, -1):
        p, n = surf(0.062 * s, 1.55, -0.006)
        q = n.to_track_quat('Z', 'Y')
        objs.append(link("eyeW", ellipsoid(p, (0.036, 0.043, 0.02), 16, 10, rot=q), mats["eyew"]))
        pp = p + n * 0.014 + Vector((-0.004 * s, 0, -0.003))
        objs.append(link("pupil", ellipsoid(pp, (0.02, 0.024, 0.011), 12, 8, rot=q), mats["eye"]))
        objs.append(link("shine", ellipsoid(pp + n * 0.006 + Vector((0.006, 0, 0.007)), (0.005, 0.005, 0.003), 8, 4, rot=q), mats["eyew"]))
        # thick, determined eyebrows
        pb, nb = surf(0.066 * s, 1.61, 0.006)
        tilt = Quaternion(nb, math.radians(-12 * s))
        objs.append(link("brow", ellipsoid(pb, (0.048, 0.014, 0.018), 14, 6, rot=tilt @ nb.to_track_quat('Z', 'Y')), mats["hair"]))
        # red wind-burned cheeks
        pc, nc = surf(0.1 * s, 1.485, 0.0)
        objs.append(link("cheek", ellipsoid(pc, (0.036, 0.03, 0.006), 14, 6, rot=nc.to_track_quat('Z', 'Y')), mats["blush"]))
        # wrestler's ears (a bit thick)
        ec = HEAD_C + Vector((0.157 * s, 0.01, -0.01))
        objs.append(link("ear", ellipsoid(ec, (0.022, 0.035, 0.05), 12, 8, rot=Quaternion((0, 0, 1), math.radians(18 * s))), mats["skin"]))
    # round nose
    pn, nn = surf(0.0, 1.505, 0.012)
    objs.append(link("nose", ellipsoid(pn, (0.034, 0.032, 0.03), 14, 8), mats["skin"]))
    # mouth: confident grin
    pm, nm = surf(0.0, 1.44, -0.002)
    objs.append(link("mouth", ellipsoid(pm, (0.042, 0.012, 0.012), 14, 6, rot=nm.to_track_quat('Z', 'Y')), mats["mouth"]))
    # buzz-cut hair: a shell over the top/back of the head
    bm = ellipsoid(HEAD_C + Vector((0, 0.008, 0.012)), HEAD_R + Vector((0.006, 0.006, 0.006)), 32, 18)
    kill = [f for f in bm.faces if not (f.calc_center_median().z > 1.59 - 0.12 * smooth(f.calc_center_median().y, -0.06, 0.08)
                                        and not (f.calc_center_median().y < -0.1 and f.calc_center_median().z < 1.645))]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    objs.append(link("hair", bm, mats["hair"]))
    face = join(objs, "Face")
    return face


# ------------------------------------------------------------------ build model

def build_model():
    M = {
        "skin": make_mat("Skin", (0.76, 0.48, 0.31), 0.55),
        "team": make_mat("Team", (0.86, 0.06, 0.08), 0.35, double=True, sheen=0.4),  # silk; recolored in Godot
        "trim": make_mat("Trim", (0.98, 0.78, 0.18), 0.35),
        "cord": make_mat("Cord", (0.95, 0.92, 0.85), 0.6),
        "boot": make_mat("Boot", (0.30, 0.13, 0.06), 0.45),
        "boottrim": make_mat("BootTrim", (0.85, 0.15, 0.1), 0.45),
        "sole": make_mat("Sole", (0.12, 0.07, 0.04), 0.7),
        "eye": make_mat("Eye", (0.05, 0.04, 0.03), 0.15),
        "eyew": make_mat("EyeWhite", (0.97, 0.96, 0.93), 0.25),
        "mouth": make_mat("Mouth", (0.42, 0.1, 0.1), 0.5),
        "hair": make_mat("Hair", (0.08, 0.06, 0.05), 0.7),
        "blush": make_mat("Blush", (0.85, 0.36, 0.3), 0.6),
    }
    body = build_body(M["skin"])
    hands = build_hands(M["skin"])
    costume = build_costume(body, M["team"], M["trim"], M["cord"])
    gutal = build_gutal(M["boot"], M["boottrim"], M["sole"])
    face = build_face(body, M)
    decimate(body, 9000)
    # weights per part
    set_weights(body, auto_weights)
    for c in costume:
        set_weights(c, auto_weights)
    for side, h in zip(("L", "R"), hands):
        set_weights(h, lambda co, s=side: {f"hand.{s}": 1.0})
    for side, g in zip(("L", "R"), gutal):
        set_weights(g, lambda co, s=side: {f"shin.{s}": 1.0} if co.z < 0.3 else {f"shin.{s}": 0.7, f"thigh.{s}": 0.3})
    set_weights(face, lambda co: {"head": 1.0})
    wrestler = join([body] + costume + hands + gutal + [face], "Wrestler")
    # UV map (Godot wants one)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(island_margin=0.01)
    bpy.ops.object.mode_set(mode='OBJECT')
    # Bayan Khodood "full stomach": belly + zodog cord + shorts grow together
    wrestler.shape_key_add(name="Basis")
    sk = wrestler.shape_key_add(name="full_stomach")
    for i, v in enumerate(wrestler.data.vertices):
        c = v.co
        if 0.5 < c.z < 1.1 and abs(c.x) < 0.42:
            fz = math.sin(math.pi * (c.z - 0.5) / 0.6)
            front = max(0.0, -c.y) / 0.3
            radial = Vector((c.x, c.y * 1.4, 0)) * (0.11 * fz)
            sk.data[i].co = c + radial + Vector((0, -0.09 * fz * front, 0))
    return wrestler


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
    {"hips": {"r": (8, 0, 0)}, "head": {"r": (-8, 0, 0)}},
    arms((0.5, -0.55, -0.67), (0.25, -0.95, -0.1)),        # wrestler ready hands
    legs((0.18, -0.22, -1), (0.02, 0.22, -1)),               # knees bent, feet wide
)
# Holding the rival's zodog (both wrestlers bent forward, heads close)
GRIP = merge(
    {"hips": {"r": (26, 0, 0)}, "chest": {"r": (10, 0, 0)}, "head": {"r": (-30, 0, 0)}, "root": {"l": (0, 0, -0.04)}},
    arms((0.32, -0.9, 0.15), (0.1, -0.75, 0.6), hand=(0.05, -0.6, 0.8)),
    legs((0.3, 0.05, -0.95), (0.05, 0.3, -1)),
)


def clips():
    C = {}

    # IDLE - breathing, little sway (loop 1.6 s)
    breathe = merge(STANCE, {
        "root": {"l": (0, 0, -0.015)},
        "hips": {"r": (10, 2, 0), "s": (1.03, 0.97, 1.03)},
        "chest": {"r": (3, 0, 0)},
        "head": {"r": (-5, -3, 4)},
    }, arms((0.55, -0.45, -0.7), (0.3, -0.9, -0.25)))
    C["idle"] = ([(0, STANCE), (24, breathe), (48, STANCE)], True)

    # WALK - heavy wrestler waddle (loop 0.67 s, code speeds it up)
    contact = merge(
        {"root": {"l": (0, 0, -0.02)},
         "hips": {"r": (12, -6, 9), "s": (1.04, 0.95, 1.04)},
         "chest": {"r": (2, 0, 6)},
         "head": {"r": (-10, 5, -10)}},
        legs((0.1, -0.7, -0.7), (0.0, -0.2, -1), "L"),
        legs((0.1, 0.55, -0.83), (0.0, 0.85, -0.5), "R"),
        arms((0.65, 0.5, -0.4), (0.4, 0.45, 0.2), "L"),
        arms((0.5, -0.7, -0.3), (0.25, -0.75, 0.5), "R"),
    )
    passing = merge(
        {"root": {"l": (0, 0, 0.06)},
         "hips": {"r": (10, 0, 0), "s": (0.97, 1.05, 0.97)},
         "head": {"r": (-6, 0, 0)}},
        legs((0.1, -0.1, -1), (0.0, 0.55, -0.83), "L"),
        legs((0.1, 0.05, -1), (0.0, 0.1, -1), "R"),
        arms((0.75, 0.0, -0.55), (0.5, -0.4, -0.25)),
    )
    C["walk"] = ([(0, contact), (5, passing), (10, mir_pose(contact)), (15, mir_pose(passing)), (20, contact)], True)

    # PUSH - wind up, both arms SHOOT forward (0.33 s)
    windup = merge(STANCE, {"hips": {"r": (-6, 0, 0)}, "chest": {"r": (-6, 0, 0)}, "head": {"r": (4, 0, 0)},
                            "root": {"l": (0, 0.04, 0)}},
                   arms((0.7, 0.45, -0.35), (0.15, -0.5, 0.85)))
    thrust = merge(STANCE, {"hips": {"r": (22, 0, 0), "s": (0.95, 1.08, 0.95)}, "chest": {"r": (6, 0, 0)},
                            "head": {"r": (-24, 0, 0)}, "root": {"l": (0, -0.1, 0)}},
                   arms((0.22, -1, 0.08), (0.12, -1, 0.06)),
                   legs((0.15, 0.45, -0.9), (0.0, 0.5, -0.85), "R"))
    hold = merge(thrust, {"hips": {"r": (17, 0, 0), "s": 1.0}, "root": {"l": (0, -0.06, 0)}})
    C["push"] = ([(0, STANCE), (3, windup), (6, thrust), (10, hold)], False)

    # HIT - got shoved: lean back, arms flail (0.43 s)
    flail = merge({"root": {"l": (0, 0.08, 0.04)},
                   "hips": {"r": (-22, 4, 12), "s": (1.08, 0.9, 1.08)},
                   "chest": {"r": (-8, 0, 0)}, "head": {"r": (-25, 0, -12)}},
                  arms((0.6, 0.3, 0.75), (0.3, -0.3, 1.0), "L"),
                  arms((0.75, -0.2, 0.55), (0.5, 0.5, 0.8), "R"),
                  legs((0.15, -0.65, -0.75), (0, -0.2, -1), "L"),
                  legs((0.18, 0.1, -1), (0, 0.1, -1), "R"))
    flail2 = merge(mir_pose(flail), {"hips": {"r": (-10, -3, -6), "s": (0.97, 1.04, 0.97)},
                                     "head": {"r": (12, 0, 8)}, "root": {"l": (0, 0.05, 0)}})
    C["hit"] = ([(0, STANCE), (3, flail), (8, flail2), (13, STANCE)], False)

    # EAGLE DANCE (devekh) - slow wing flaps, high knee hops, turning (loop 1.6 s)
    def wings(up, lag):
        ua = (1, 0.15, 0.55) if up else (1, 0.15, -0.2)
        fa = (1, 0.25, 0.55 + lag) if up else (1, 0.25, -0.2 + lag)
        return arms(ua, fa, hand=fa)
    proud = {"hips": {"r": (14, 0, 0)}, "chest": {"r": (-6, 0, 0)}, "head": {"r": (-14, 0, 0)}}
    stepL = merge(proud, legs((0.25, -0.95, 0.1), (0.05, 0.0, -1), "L"), legs((0.15, 0.05, -1), (0, 0.05, -1), "R"))
    stepR = mir_pose(stepL)
    low = merge(proud, legs((0.15, -0.2, -1), (0.0, 0.2, -1)), {"root": {"l": (0, 0, -0.03)}, "hips": {"s": (1.04, 0.94, 1.04)}})
    ED = []
    for i, (base, turn, hop) in enumerate([(stepL, 18, 0.10), (low, 0, -0.03), (stepR, -18, 0.10), (low, 0, -0.03)]):
        f0 = i * 12
        pose_up = merge(base, wings(True, -0.35), {"root": {"r": (0, 0, turn), "l": (0, 0, hop)}})
        pose_dn = merge(low, wings(False, 0.35), {"root": {"r": (0, 0, turn * 0.5), "l": (0, 0, -0.03)}})
        ED += [(f0, pose_up), (f0 + 6, pose_dn)]
    ED.append((48, ED[0][1]))
    C["eagle_dance"] = (ED, True)

    # LOSE - deflated slump, slow sad sway (loop 2 s)
    slump = merge({"hips": {"r": (18, 0, 4), "s": (1.05, 0.93, 1.05)}, "chest": {"r": (14, 0, 0)},
                   "head": {"r": (28, 0, -6)}, "root": {"l": (0, 0, -0.03)}},
                  arms((0.3, -0.1, -1), (0.12, -0.2, -1)),
                  legs((0.16, -0.15, -1), (0.0, 0.25, -1)))
    slump2 = merge(slump, {"hips": {"r": (22, 0, -4), "s": (1.08, 0.9, 1.08)}, "head": {"r": (32, 0, 8)}})
    C["lose"] = ([(0, slump), (30, slump2), (60, slump)], True)

    # PALM BRACE - slam both palms down to save yourself (0.4 s, holds last pose)
    brace = merge({"root": {"l": (0, -0.05, -0.08)},
                   "hips": {"r": (38, 0, 0), "s": (1.05, 0.94, 1.05)}, "chest": {"r": (14, 0, 0)},
                   "head": {"r": (-38, 0, 0)}},
                  arms((0.4, -0.8, -0.45), (0.3, -0.55, -0.8), hand=(0.2, -0.3, -1)),
                  legs((0.16, -0.55, -0.8), (0.0, 0.5, -0.85)))
    impact = merge(brace, {"hips": {"s": (1.1, 0.88, 1.1)}, "root": {"l": (0, -0.05, -0.11)}})
    settle = merge(brace, {"hips": {"r": (34, 0, 0), "s": (1.02, 0.98, 1.02)}})
    C["palm_brace"] = ([(0, STANCE), (4, brace), (7, impact), (12, settle)], False)

    # BAYAN KHODOOD STRUT - chest out, nose up, hands on hips, slow arrogant steps (loop 1.33 s)
    akimbo = arms((0.85, 0.35, -0.4), (-0.55, 0.15, -0.55), hand=(-0.6, 0.0, -0.4))
    boss = {"hips": {"r": (-8, 0, 0)}, "chest": {"r": (-14, 0, 0), "s": (1.05, 1.0, 1.05)}, "head": {"r": (-22, 0, 0)}}
    s1 = merge(boss, akimbo, {"root": {"r": (0, 6, 12), "l": (0, 0, 0.05)}, "head": {"r": (-22, 8, -10)}},
               legs((0.12, -0.85, -0.35), (0.0, 0.15, -1), "L"), legs((0.12, 0.1, -1), (0, 0.1, -1), "R"))
    p1 = merge(boss, akimbo, {"root": {"l": (0, 0, -0.02)}, "hips": {"s": (1.04, 0.95, 1.04)}},
               legs((0.14, -0.15, -1), (0.0, 0.15, -1)))
    C["bayan_khodood_strut"] = ([(0, s1), (10, p1), (20, mir_pose(s1)), (30, mir_pose(p1)), (40, s1)], True)

    # STUMBLE - trip, windmill arms, catch balance (0.8 s)
    trip = merge({"hips": {"r": (32, 0, 6)}, "head": {"r": (-10, 0, 0)}, "root": {"l": (0, -0.05, 0)}},
                 arms((0.5, -0.6, 0.6), (0.2, -0.6, 0.8), "L"), arms((0.6, 0.6, 0.2), (0.3, 0.8, 0.4), "R"),
                 legs((0.12, 0.8, -0.5), (0, 0.95, -0.2), "R"), legs((0.12, -0.2, -1), (0, 0.3, -1), "L"))
    wind = merge({"hips": {"r": (44, -4, -8), "s": (0.96, 1.06, 0.96)}, "head": {"r": (-28, 0, 10)}, "root": {"l": (0, -0.08, -0.04)}},
                 arms((0.5, -0.6, 0.6), (0.2, -0.6, 0.8), "R"), arms((0.6, 0.6, 0.2), (0.3, 0.8, 0.4), "L"),
                 legs((0.12, -0.6, -0.8), (0, -0.1, -1), "R"), legs((0.12, 0.3, -1), (0, 0.7, -0.7), "L"))
    wind2 = merge(mir_pose(wind), {"hips": {"r": (36, 4, 8)}})
    catch = merge(STANCE, {"hips": {"r": (-12, 0, 0), "s": (1.06, 0.92, 1.06)}, "head": {"r": (10, 0, 0)},
                           "root": {"l": (0, -0.03, -0.03)}}, arms((0.95, 0.05, 0.35), (0.9, 0.0, 0.5)))
    C["stumble"] = ([(0, STANCE), (4, trip), (9, wind), (14, wind2), (19, catch), (24, STANCE)], False)

    # ======================= NEW: grappling (барьц) and techniques (мэх) =======================

    # THIGH SLAP - before the bout wrestlers slap their thighs: "ready!" (1 s)
    squat = merge(STANCE, {"hips": {"r": (20, 0, 0)}, "root": {"l": (0, 0, -0.06)}, "head": {"r": (-20, 0, 0)}},
                  legs((0.3, -0.25, -0.92), (0.0, 0.35, -0.95)))
    slap = merge(squat, arms((0.35, -0.3, -0.9), (0.1, -0.45, -0.9), hand=(0.15, -0.3, -1)), {"hips": {"s": (1.05, 0.95, 1.05)}})
    up = merge(squat, arms((0.6, -0.2, -0.2), (0.45, -0.4, 0.6)))
    C["thigh_slap"] = ([(0, STANCE), (6, up), (10, slap), (16, up), (20, slap), (30, STANCE)], False)

    # GRAB - lunge in and take the grip (0.27 s)
    reach = merge(GRIP, {"hips": {"r": (34, 0, 0)}, "root": {"l": (0, -0.12, -0.03)}},
                  arms((0.3, -1, 0.3), (0.15, -1, 0.35)))
    C["grab"] = ([(0, STANCE), (4, reach), (8, GRIP)], False)

    # GRIP IDLE - holding the rival's zodog, pulling and leaning (loop 1.2 s)
    grip2 = merge(GRIP, {"hips": {"r": (24, 4, 6)}, "root": {"l": (0.02, 0, -0.05)}, "head": {"r": (-28, 0, -6)}},
                  arms((0.3, -0.85, 0.05), (0.12, -0.7, 0.55), "L"))
    C["grip_idle"] = ([(0, GRIP), (18, grip2), (36, mir_pose(grip2)), (54, GRIP)], True)

    # ACHIKH (Ачих) - load the rival onto your back and throw him over (0.9 s)
    turn_in = merge({"root": {"r": (0, 0, 90), "l": (0, -0.1, -0.08)}, "hips": {"r": (20, 0, 0)}, "head": {"r": (-10, 0, 0)}},
                    arms((0.3, -0.8, 0.5), (0.1, -0.4, 0.9)), legs((0.3, 0.0, -0.95), (0, 0.4, -0.9)))
    loaded = merge({"root": {"r": (0, 0, 175), "l": (0, -0.15, -0.14)}, "hips": {"r": (30, 0, 0), "s": (1.08, 0.92, 1.08)},
                    "chest": {"r": (10, 0, 0)}, "head": {"r": (-25, 0, 0)}},
                   arms((0.15, 0.3, 0.95), (0.1, -0.6, 0.8), hand=(0, -0.9, 0.4)),
                   legs((0.32, -0.2, -0.92), (0.0, 0.45, -0.9)))
    over = merge({"root": {"r": (0, 0, 175), "l": (0, -0.2, 0.02)}, "hips": {"r": (75, 0, 0)}, "chest": {"r": (20, 0, 0)},
                  "head": {"r": (-10, 0, 0)}},
                 arms((0.2, -0.9, -0.3), (0.1, -0.6, -0.8)), legs((0.25, -0.1, -1), (0, 0.1, -1)))
    C["achikh"] = ([(0, GRIP), (6, turn_in), (11, loaded), (18, over), (23, over), (27, STANCE)], False)

    # GUYADAKH (Гуядах) - step in and lift him with your THIGH, twisting (0.8 s)
    step = merge(GRIP, {"root": {"r": (0, 0, 30), "l": (0, -0.12, 0)}, "hips": {"r": (20, 0, -10)}})
    lift = merge(GRIP, {"root": {"r": (0, -12, 55), "l": (0, -0.15, 0.05)}, "hips": {"r": (30, -14, -20)}, "chest": {"r": (18, 0, 25)},
                        "head": {"r": (-20, 0, 25)}},
                 legs((0.15, -1, 0.35), (0.1, -0.4, -0.9), "R"), legs((0.15, 0.1, -1), (0, 0.15, -1), "L"),
                 arms((0.5, -0.6, -0.5), (0.4, 0.2, -0.85), "L"), arms((0.2, -0.95, 0.3), (0.0, -0.5, 0.85), "R"))
    finish = merge(lift, {"root": {"r": (0, -6, 80)}, "chest": {"r": (35, 0, 40)}}, legs((0.2, -0.6, -0.75), (0, 0.2, -1), "R"))
    C["guyadakh"] = ([(0, GRIP), (6, step), (12, lift), (18, finish), (24, STANCE)], False)

    # DEGEEDEKH (Дэгээдэх) - HOOK his leg from the inside and drive forward (0.7 s)
    hook = merge(GRIP, {"root": {"l": (0, -0.12, 0)}, "hips": {"r": (18, 6, 0)}},
                 legs((-0.45, -0.75, -0.5), (-0.6, 0.2, -0.78), "L"), legs((0.2, 0.1, -1), (0, 0.15, -1), "R"))
    drive = merge(hook, {"hips": {"r": (40, 6, 0)}, "chest": {"r": (12, 0, 0)}, "root": {"l": (0, -0.25, -0.05)}},
                  arms((0.25, -1, 0.0), (0.1, -1, -0.1)))
    C["degeedekh"] = ([(0, GRIP), (6, hook), (13, drive), (17, drive), (22, STANCE)], False)

    # TAKHIMDAKH (Тахимдах) - drop low, catch behind his KNEE, push him over backwards (0.75 s)
    dip = merge({"root": {"l": (0, -0.12, -0.18)}, "hips": {"r": (50, 0, 0), "s": (1.06, 0.94, 1.06)}, "chest": {"r": (10, 0, 0)},
                 "head": {"r": (-40, 0, 0)}},
                legs((0.35, -0.6, -0.72), (0.0, 0.6, -0.8), "R"), legs((0.25, 0.4, -0.88), (0, 0.6, -0.8), "L"),
                arms((0.1, -0.75, -0.65), (0.05, -0.5, -0.86), "R"), arms((0.25, -0.95, 0.1), (0.1, -0.9, 0.4), "L"))
    shove = merge(dip, {"root": {"l": (0, -0.3, -0.06)}, "hips": {"r": (35, 0, 0)}},
                  arms((0.15, -0.8, -0.55), (0.0, -0.3, -0.95), "R"), arms((0.2, -1, 0.35), (0.1, -0.8, 0.6), "L"))
    C["takhimdakh"] = ([(0, GRIP), (6, dip), (13, shove), (18, shove), (24, STANCE)], False)

    # USGIIDUKH (Өсгийдөх) - sweep his HEEL out from behind and pull him down (0.7 s)
    reach_leg = merge(GRIP, {"root": {"r": (0, 0, -20)}, "hips": {"r": (10, -8, -10)}},
                      legs((0.0, 0.35, -0.94), (0.0, 0.6, -0.8), "R"))
    sweep = merge(GRIP, {"root": {"r": (0, 0, -30), "l": (0, 0.05, 0)}, "hips": {"r": (-5, -10, -15)}, "chest": {"r": (-10, 0, -10)},
                         "head": {"r": (-10, 0, 0)}},
                  legs((0.35, -0.7, -0.6), (0.4, -0.85, -0.3), "R"),
                  arms((0.55, -0.4, -0.3), (0.4, 0.3, -0.5)))
    C["usgiidukh"] = ([(0, GRIP), (6, reach_leg), (12, sweep), (17, sweep), (22, STANCE)], False)

    # KHUL AVAKH (Хөл авах) - DIVE for his leg and lift it (no grip needed) (0.8 s)
    dive = merge({"root": {"l": (0, -0.3, -0.3)}, "hips": {"r": (70, 0, 0)}, "chest": {"r": (10, 0, 0)}, "head": {"r": (-55, 0, 0)}},
                 arms((0.25, -0.9, -0.35), (0.15, -0.6, -0.8)),
                 legs((0.2, -0.7, -0.7), (0, 0.7, -0.7), "L"), legs((0.2, 0.6, -0.8), (0, 0.85, -0.5), "R"))
    lift_leg = merge({"root": {"l": (0, -0.2, 0.0)}, "hips": {"r": (5, 0, 0)}, "chest": {"r": (-10, 0, 0)}, "head": {"r": (-15, 0, 0)}},
                     arms((0.3, -0.7, 0.6), (0.1, 0.0, 1.0)), legs((0.2, -0.1, -1), (0, 0.1, -1)))
    C["khul_avakh"] = ([(0, STANCE), (6, dive), (12, dive), (19, lift_leg), (24, STANCE)], False)

    # SEEREN DUNGUI (Сээрэн дунгуй) - turn in and ROLL him over your hip (0.85 s)
    side_in = merge({"root": {"r": (0, 0, 100), "l": (0, -0.1, -0.1)}, "hips": {"r": (15, -15, 0)}, "head": {"r": (-10, 0, -20)}},
                    arms((0.5, -0.8, 0.3), (0.1, -0.2, 0.95), "L"), arms((0.2, -0.95, 0.0), (0.1, -0.9, 0.3), "R"),
                    legs((0.3, 0.0, -0.95), (0, 0.35, -0.94)))
    roll = merge({"root": {"r": (0, -25, 170), "l": (0, -0.1, -0.02)}, "hips": {"r": (55, -20, 0)}, "chest": {"r": (15, 0, 30)},
                  "head": {"r": (-10, 0, 0)}},
                 arms((0.4, -0.7, -0.6), (0.3, -0.1, -0.95)), legs((0.3, -0.1, -0.95), (0, 0.2, -1)))
    C["seeren_dungui"] = ([(0, GRIP), (7, side_in), (15, roll), (20, roll), (26, STANCE)], False)

    # MUSHGIKH (Мушгих) - TWIST his upper body down to the side (0.7 s)
    tw1 = merge(GRIP, {"chest": {"r": (10, 0, 40)}, "hips": {"r": (24, 0, 15)}, "head": {"r": (-25, 0, 30)}},
                arms((0.3, -0.7, 0.6), (0.2, -0.3, 0.9), "L"), arms((0.1, -0.9, -0.4), (0.0, -0.5, -0.85), "R"))
    tw2 = merge(GRIP, {"root": {"r": (0, 0, -40)}, "chest": {"r": (25, 0, -55)}, "hips": {"r": (35, 0, -25)}, "head": {"r": (-15, 0, -40)}},
                arms((0.3, -0.5, -0.8), (0.1, 0.2, -0.95), "L"), arms((0.6, -0.5, 0.3), (0.4, -0.4, 0.8), "R"))
    C["mushgikh"] = ([(0, GRIP), (6, tw1), (13, tw2), (17, tw2), (22, STANCE)], False)

    # TONGOROKH (Тонгорох) - LIFT him off the grass and flip him over backwards (1 s)
    load = merge(GRIP, {"root": {"l": (0, -0.1, -0.16)}, "hips": {"r": (20, 0, 0), "s": (1.06, 0.94, 1.06)}},
                 arms((0.25, -0.95, -0.1), (0.1, -0.4, 0.9)), legs((0.4, 0.0, -0.92), (0.0, 0.4, -0.92)))
    heave = merge({"root": {"l": (0, 0.0, 0.08)}, "hips": {"r": (-25, 0, 0)}, "chest": {"r": (-25, 0, 0)}, "head": {"r": (-35, 0, 0)}},
                  arms((0.2, 0.2, 0.96), (0.1, 0.4, 0.9)), legs((0.15, 0.1, -1), (0, 0.1, -1)))
    C["tongorokh"] = ([(0, GRIP), (8, load), (16, heave), (22, heave), (30, STANCE)], False)

    # KHARIULT (Хариулт) - COUNTER: slip out to the side and pull him past you (0.6 s)
    slip = merge({"root": {"r": (0, 0, -45), "l": (0.12, 0.05, -0.06)}, "hips": {"r": (15, 10, 0)}, "head": {"r": (-15, 0, -20)}},
                 arms((0.4, -0.7, 0.2), (0.3, 0.2, -0.3), "L"), arms((0.6, -0.2, -0.4), (0.5, 0.5, -0.2), "R"),
                 legs((0.35, 0.1, -0.93), (0, 0.3, -0.95)))
    yank = merge(slip, {"root": {"r": (0, 0, -80)}, "chest": {"r": (5, 0, -25)}}, arms((0.6, 0.6, -0.4), (0.4, 0.8, -0.3)))
    C["khariult"] = ([(0, GRIP), (5, slip), (11, yank), (18, STANCE)], False)

    # THROWN - in the air, everything flailing (loop 0.4 s). The physics body does the flying.
    air1 = merge({"hips": {"r": (-10, 0, 0)}, "head": {"r": (-20, 0, 0)}},
                 arms((1, 0.2, 0.6), (0.9, 0.0, 0.8), "L"), arms((1, -0.3, 0.3), (0.7, 0.5, 0.6), "R"),
                 legs((0.5, -0.6, -0.6), (0.4, 0.3, -0.9), "L"), legs((0.4, 0.2, -0.9), (0.2, 0.6, -0.8), "R"))
    C["thrown"] = ([(0, air1), (6, mir_pose(air1)), (12, air1)], True)
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
    rig.animation_data.action = actions["idle"]
    scn.frame_start, scn.frame_end = 0, 48
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
    print("Built clips:", ", ".join(actions), "| tris:", sum(len(p.vertices) - 2 for p in mesh.data.polygons))
