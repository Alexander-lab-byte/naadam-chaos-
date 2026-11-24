"""
Naadam Chaos - environment builder for Blender 4.2+ / 5.x

Makes (run this file, it writes into assets/env/):
  terrain.glb       - the steppe around the wrestling field: flat field, rolling hills,
                      big hills, a mountain range with a Bogd Khan-like massif in the north.
  naadam_props.glb  - Ger, Tug (white banner), Flag, StandSegment, Person_* (crowd),
                      Larch, Larch_Far, Rock_1..3, Eagle
  scatter.json      - where trees, rocks and far gers stand on the terrain (Godot coordinates)

Textures come from make_textures.py (run that first).
Coordinates: Blender Z-up, character/building front = -Y. Godot: x = x, y = z, z = -y.

Crowd people carry extra data for the Godot crowd shader:
  vertex color = base color,  UV2.x = 1 on the deel (tinted per person),  UV2.y = 1 on the arms (cheer animation)
"""
import bpy, bmesh, math, os, json, random
from mathutils import Vector, Matrix, Quaternion, noise

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.environ.get("NC_ENV_OUT", os.path.join(ROOT, "assets", "env"))
TEX = os.path.join(ROOT, "assets", "env", "textures")
random.seed(3)


# ------------------------------------------------------------------ basics

def clear():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for c in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for x in list(c):
            c.remove(x)


def srgb(c):
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


def mat(name, rgb=(0.8, 0.8, 0.8), rough=0.7, image=None, alpha=False, metal=0.0, double=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(rgb), 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if image:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(os.path.join(TEX, image), check_existing=True)
        nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
        if alpha:
            nt.links.new(tex.outputs["Alpha"], b.inputs["Alpha"])
            m.blend_method = 'CLIP' if hasattr(m, "blend_method") else None
    m.use_backface_culling = not double
    return m


class Mesh:
    """Builds one mesh from many parts straight into a bmesh, with per-part
    material, vertex color and UV2 (robe mask, arm weight)."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.col = self.bm.verts.layers.float_color.new("Col")
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.uv2 = self.bm.loops.layers.uv.new("UV2")
        self.mats = []

    def _mi(self, m):
        if m is None:
            return 0
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _finish(self, verts, m, color, robe, arm, uvfn=None):
        vs = set(verts)
        faces = {f for v in verts for f in v.link_faces}
        mi = self._mi(m)
        for v in verts:
            v[self.col] = (*srgb(color), 1.0)
        for f in faces:
            f.material_index = mi
            f.smooth = True
            for l in f.loops:
                if uvfn:
                    l[self.uv].uv = uvfn(l.vert.co, l)
                l[self.uv2].uv = (robe, arm(l.vert.co) if callable(arm) else arm)
        return verts

    def sphere(self, c, size, segs=12, rings=8, rot=None, m=None, color=(1, 1, 1), robe=0, arm=0, uvfn=None):
        r = bmesh.ops.create_uvsphere(self.bm, u_segments=segs, v_segments=rings, radius=1.0, calc_uvs=True)
        mtx = Matrix.Diagonal((*size, 1.0))
        if rot:
            mtx = rot.to_matrix().to_4x4() @ mtx
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(Vector(c)) @ mtx, verts=r["verts"])
        return self._finish(r["verts"], m, color, robe, arm, uvfn)

    def capsule(self, a, b, r1, r2=None, segs=10, rings=6, m=None, color=(1, 1, 1), robe=0, arm=0, uvfn=None):
        a, b = Vector(a), Vector(b)
        d = b - a
        L = d.length
        r2 = r1 if r2 is None else r2
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=segs, v_segments=rings, radius=1.0, calc_uvs=True)
        for v in res["verts"]:
            top = v.co.z > 0
            rr = r2 if top else r1
            v.co = Vector((v.co.x * rr, v.co.y * rr, v.co.z * rr + (L if top else 0)))
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(a) @ rot, verts=res["verts"])
        return self._finish(res["verts"], m, color, robe, arm, uvfn)

    def lathe(self, prof, segs=24, m=None, color=(1, 1, 1), robe=0, arm=0, center=(0, 0), u_rep=1.0, cap=False, sx=1.0, sy=1.0):
        """prof: list of (radius, z) from bottom to top. UV u = around, v = along the profile."""
        rings = []
        total = sum((Vector(p) - Vector(q)).length for p, q in zip(prof, prof[1:])) or 1
        acc = [0.0]
        for p, q in zip(prof, prof[1:]):
            acc.append(acc[-1] + (Vector(p) - Vector(q)).length)
        for (r, z) in prof:
            ring = []
            for k in range(segs):
                a = 2 * math.pi * k / segs
                ring.append(self.bm.verts.new((center[0] + math.cos(a) * r * sx, center[1] + math.sin(a) * r * sy, z)))
            rings.append(ring)
        verts = [v for r in rings for v in r]
        faces = []
        for i, (lo, hi) in enumerate(zip(rings, rings[1:])):
            for k in range(segs):
                k2 = (k + 1) % segs
                f = self.bm.faces.new((lo[k], lo[k2], hi[k2], hi[k]))
                faces.append((f, i, k))
        if cap:
            f = self.bm.faces.new(list(reversed(rings[-1])))
        self.bm.normal_update()
        mi = self._mi(m)
        for v in verts:
            v[self.col] = (*srgb(color), 1.0)
        for f, i, k in faces:
            f.material_index = mi
            f.smooth = True
            for l in f.loops:
                vi = None
                # find ring + seg of this vertex
                for ri, ring in enumerate(rings[i:i + 2]):
                    if l.vert in ring:
                        vi = (i + ri, ring.index(l.vert))
                        break
                kk = vi[1]
                if kk == 0 and k == segs - 1:
                    kk = segs
                l[self.uv].uv = (kk / segs * u_rep, 1.0 - acc[vi[0]] / total)
                l[self.uv2].uv = (robe, arm(l.vert.co) if callable(arm) else arm)
        if cap:
            f.material_index = mi
            for l in f.loops:
                l[self.uv].uv = (0.5, 0.5)
                l[self.uv2].uv = (robe, 0)
        return verts

    def quad_strip(self, pts_l, pts_r, m=None, color=(1, 1, 1), u=(0, 1)):
        """a strip of quads between two point lists (used for hair cards, flags)"""
        L = [self.bm.verts.new(p) for p in pts_l]
        R = [self.bm.verts.new(p) for p in pts_r]
        n = len(L) - 1
        mi = self._mi(m)
        for i in range(n):
            f = self.bm.faces.new((L[i], R[i], R[i + 1], L[i + 1]))
            f.material_index = mi
            f.smooth = True
            for l, uvv in zip(f.loops, ((u[0], i / n), (u[1], i / n), (u[1], (i + 1) / n), (u[0], (i + 1) / n))):
                l[self.uv].uv = (uvv[0], 1.0 - uvv[1])
                l[self.uv2].uv = (0, uvv[1])
        for v in L + R:
            v[self.col] = (*srgb(color), 1.0)
        return L + R

    def box(self, c, size, m=None, color=(1, 1, 1), rot_z=0.0, uv_scale=1.0):
        r = bmesh.ops.create_cube(self.bm, size=1.0)
        mtx = Matrix.Translation(Vector(c)) @ Matrix.Rotation(rot_z, 4, 'Z') @ Matrix.Diagonal((*size, 1.0))
        bmesh.ops.transform(self.bm, matrix=mtx, verts=r["verts"])

        def uvf(co, l):
            n = l.face.normal
            if abs(n.z) > 0.7:
                return (co.x * uv_scale, co.y * uv_scale)
            if abs(n.x) > 0.7:
                return (co.y * uv_scale, co.z * uv_scale)
            return (co.x * uv_scale, co.z * uv_scale)
        self.bm.normal_update()
        for f in {f for v in r["verts"] for f in v.link_faces}:
            f.smooth = False
        return self._finish(r["verts"], m, color, 0, 0, uvf)

    def done(self, smooth=True):
        # glTF flips V on every UV set; pre-flip UV2 so Godot reads the values we wrote
        for f in self.bm.faces:
            for l in f.loops:
                u = l[self.uv2].uv
                l[self.uv2].uv = (u.x, 1.0 - u.y)
        me = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        if not me.materials:
            me.materials.append(mat(self.name + "_mat"))
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        me.color_attributes.active_color = me.color_attributes["Col"]
        me.color_attributes.render_color_index = me.color_attributes.find("Col")
        return ob


# ------------------------------------------------------------------ terrain

def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


FIELD_R = 38.0   # flat area around the wrestling field


def height(x, y):
    r = math.hypot(x, y)
    p = Vector((x, y, 0))
    h = 0.0
    # rolling steppe
    h += (noise.fractal(p / 140.0, 1.0, 2.0, 4) + 0.3) * 9.0 * smoothstep(FIELD_R, 160, r)
    # big hills
    h += max(0.0, noise.fractal(p / 380.0 + Vector((7, 3, 0)), 1.0, 2.0, 5) + 0.35) * 70.0 * smoothstep(200, 520, r)
    # mountain range (ridged)
    rid = noise.ridged_multi_fractal(p / 520.0 + Vector((31, 17, 0)), 1.0, 2.1, 6, 1.0, 2.0)
    h += rid * 150.0 * smoothstep(520, 1000, r)
    # a big Bogd Khan-like massif in the north (+Y in Blender = -Z in Godot)
    d = (Vector((x, y)) - Vector((-120, 1050))).length
    h += 260.0 * math.exp(-(d / 420.0) ** 2) * smoothstep(400, 800, r)
    if r < FIELD_R:
        h = 0.0
    return h - 0.03


def forest(x, y):
    """0..1 how much larch forest grows here (patches on the bigger hills, below the tree line)"""
    r = math.hypot(x, y)
    h = height(x, y)
    n = noise.fractal(Vector((x, y, 0)) / 160.0 + Vector((50, 50, 0)), 1.0, 2.0, 3)
    m = smoothstep(0.05, 0.35, n) * smoothstep(170, 300, r) * (1 - smoothstep(170, 240, h))
    return m


def build_terrain():
    rings = [i * 4.0 for i in range(11)]          # 0..40
    r = 40.0
    for step, until in ((6.0, 220), (12.0, 600), (30.0, 1500), (80.0, 3200)):
        while r < until:
            r += step
            rings.append(r)
    segs = 256
    bm = bmesh.new()
    col = bm.verts.layers.float_color.new("Col")
    uvl = bm.loops.layers.uv.new("UVMap")
    center = bm.verts.new((0, 0, height(0, 0)))
    grid = []
    for ri, rr in enumerate(rings[1:]):
        row = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            x, y = math.cos(a) * rr, math.sin(a) * rr
            v = bm.verts.new((x, y, height(x, y)))
            v[col] = (forest(x, y), 0, 0, 1)
            row.append(v)
        grid.append(row)
    center[col] = (0, 0, 0, 1)
    for k in range(segs):
        bm.faces.new((center, grid[0][k], grid[0][(k + 1) % segs]))
    for lo, hi in zip(grid, grid[1:]):
        for k in range(segs):
            k2 = (k + 1) % segs
            bm.faces.new((lo[k], hi[k], hi[k2], lo[k2]))     # counter-clockwise from above = faces up
    for f in bm.faces:
        f.smooth = True
        for l in f.loops:
            l[uvl].uv = (l.vert.co.x / 8.0, l.vert.co.y / 8.0)
    me = bpy.data.meshes.new("Terrain")
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat("Terrain", (0.35, 0.5, 0.25)))
    ob = bpy.data.objects.new("Terrain", me)
    bpy.context.scene.collection.objects.link(ob)
    me.color_attributes.active_color = me.color_attributes["Col"]
    me.color_attributes.render_color_index = me.color_attributes.find("Col")
    return ob


def godot(x, y, z):
    return [round(x, 2), round(z, 2), round(-y, 2)]


def scatter():
    trees, rocks, gers, horses = [], [], [], []
    tries = 0
    while len(trees) < 1400 and tries < 60000:
        tries += 1
        a = random.uniform(0, 2 * math.pi)
        r = random.uniform(160, 1100)
        x, y = math.cos(a) * r, math.sin(a) * r
        if random.random() < forest(x, y):
            trees.append(godot(x, y, height(x, y)) + [round(random.uniform(0.75, 1.35), 2), round(random.uniform(0, 6.28), 2)])
    for _ in range(420):
        a = random.uniform(0, 2 * math.pi)
        r = random.uniform(FIELD_R + 6, 700) if random.random() < 0.8 else random.uniform(FIELD_R + 2, 70)
        x, y = math.cos(a) * r, math.sin(a) * r
        rocks.append(godot(x, y, height(x, y)) + [round(random.uniform(0.4, 2.2) * (1 + r / 400), 2), round(random.uniform(0, 6.28), 2), random.randint(1, 3)])
    # a ger camp on the hills (families who came for Naadam)
    for cx, cy, n in ((-150, 110, 6), (160, 140, 5), (-60, -150, 4), (230, -60, 4), (40, 230, 5)):
        for i in range(n):
            x = cx + random.uniform(-25, 25)
            y = cy + random.uniform(-25, 25)
            gers.append(godot(x, y, height(x, y)) + [round(random.uniform(0.9, 1.1), 2), round(random.uniform(0, 6.28), 2)])
    return {"trees": trees, "rocks": rocks, "gers": gers}


# ------------------------------------------------------------------ props

def build_ger(M):
    g = Mesh("Ger")
    R, H = 3.0, 1.55
    # wall (felt) with a dark skirt at the bottom
    g.lathe([(R + 0.03, 0.0), (R + 0.03, 0.14)], 40, M["skirt"], u_rep=8)
    g.lathe([(R, 0.12), (R, H)], 40, M["felt"], u_rep=6)
    g.lathe([(R + 0.025, H - 0.24), (R + 0.025, H - 0.02)], 40, M["band"], u_rep=10)
    # roof: slightly concave, with an eave
    prof = [(R + 0.22, H - 0.06), (R + 0.05, H + 0.05)]
    for i in range(1, 7):
        t = i / 6
        prof.append((R + 0.05 - (R - 0.6) * t, H + 0.05 + 1.05 * (t ** 0.85)))
    g.lathe(list(reversed(prof))[::-1], 40, M["felt"], u_rep=6)
    g.lathe([(0.92, H + 0.96), (0.62, H + 1.12)], 40, M["band"], u_rep=4)
    # toono (crown) + chimney
    g.lathe([(0.62, H + 1.1), (0.6, H + 1.2), (0.5, H + 1.22), (0.48, H + 1.12)], 24, M["orange"])
    g.capsule((0.0, 0.0, H + 1.18), (0.0, 0.0, H + 1.28), 0.36, 0.36, 16, 4, M["orange"])
    g.lathe([(0.07, H + 0.9), (0.07, H + 2.25)], 10, M["metal"], center=(0.3, 0.18))
    g.lathe([(0.12, H + 2.25), (0.14, H + 2.32), (0.02, H + 2.36)], 10, M["metal"], center=(0.3, 0.18), cap=True)
    # 3 ropes around the wall + 2 ropes over the roof
    for z in (0.4, 0.82, 1.22):
        g.lathe([(R + 0.035, z - 0.018), (R + 0.045, z), (R + 0.035, z + 0.018)], 40, M["rope"])
    for ang in (0.6, -0.6):
        pts = [Vector((math.sin(ang) * r, -math.cos(ang) * r, 0)) for r, _ in prof]
        for (r, z), p in zip(prof, pts):
            p.z = z + 0.03
        for p, q in zip(pts, pts[1:]):
            g.capsule(p, q, 0.022, None, 6, 3, M["rope"])
    # door (faces -Y): painted double door + frame + step
    g.box((0, -R - 0.06, 0.66), (1.04, 0.12, 1.32), M["orange"])
    door_verts = []
    bm = g.bm
    v = [bm.verts.new(p) for p in ((-0.46, -R - 0.125, 0.06), (0.46, -R - 0.125, 0.06), (0.46, -R - 0.125, 1.26), (-0.46, -R - 0.125, 1.26))]
    f = bm.faces.new(v)
    f.material_index = g._mi(M["door"])
    for l, uv in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        l[g.uv].uv = uv
        l[g.uv2].uv = (0, 0)
    for vv in v:
        vv[g.col] = (1, 1, 1, 1)
    g.box((0, -R - 0.32, 0.06), (1.2, 0.42, 0.12), M["wood"])
    return g.done()


def build_tug(M):
    t = Mesh("Tug")
    # stone base
    t.lathe([(0.55, 0.0), (0.55, 0.18), (0.42, 0.2), (0.42, 0.36), (0.28, 0.38), (0.2, 0.5)], 20, M["stone"], cap=True)
    # lacquered pole
    t.lathe([(0.055, 0.45), (0.045, 4.55)], 12, M["lacquer"])
    top = 4.55
    # white horsehair (сүлд): cards hanging from a ring and flaring out
    n = 40
    for i in range(n):
        a = 2 * math.pi * i / n + random.uniform(-0.05, 0.05)
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0)) * 0.09
        L = random.uniform(1.25, 1.55)
        flare = random.uniform(0.42, 0.56)
        pts = []
        for k in range(7):
            s = k / 6
            p = d * (0.07 + flare * math.sin(s * 1.35)) + Vector((0, 0, top - 0.08 - s * L))
            pts.append(p)
        t.quad_strip([p - side * (0.6 + k * 0.12) for k, p in enumerate(pts)],
                     [p + side * (0.6 + k * 0.12) for k, p in enumerate(pts)], M["hair"], (0.97, 0.96, 0.93), u=(i % 4 / 4, i % 4 / 4 + 0.25))
    # golden fittings + trident (сэрээ)
    t.lathe([(0.1, top - 0.12), (0.12, top), (0.08, top + 0.1)], 16, M["gold"], cap=True)
    t.sphere((0, 0, top + 0.17), (0.08, 0.08, 0.08), 12, 8, None, M["gold"])
    t.lathe([(0.03, top + 0.22), (0.03, top + 0.32)], 8, M["gold"])
    # flat blade: central flame-leaf spear
    t.sphere((0, 0, top + 0.55), (0.065, 0.018, 0.24), 12, 8, None, M["silver"])
    # side prongs curving up
    for s in (-1, 1):
        pts = [Vector((s * 0.03, 0, top + 0.33)), Vector((s * 0.14, 0, top + 0.36)), Vector((s * 0.19, 0, top + 0.45)), Vector((s * 0.18, 0, top + 0.6))]
        for p, q in zip(pts, pts[1:]):
            t.capsule(p, q, 0.022, 0.017, 8, 3, M["silver"])
        t.sphere(pts[-1] + Vector((0, 0, 0.04)), (0.03, 0.012, 0.07), 8, 6, None, M["silver"])
    t.capsule((-0.16, 0, top + 0.34), (0.16, 0, top + 0.34), 0.02, None, 8, 3, M["gold"])
    return t.done()


def build_flag(M):
    f = Mesh("Flag")
    f.lathe([(0.06, 0.0), (0.045, 8.0)], 10, M["pole"])
    f.sphere((0, 0, 8.08), (0.08, 0.08, 0.08), 10, 6, None, M["gold"])
    # cloth: 2.4 x 1.2, many segments for the wave shader. UV2.y = distance from the pole (0..1)
    W, H, nx, ny = 2.4, 1.2, 24, 10
    bm = f.bm
    verts = [[bm.verts.new((0.06 + W * i / nx, 0, 7.9 - H * j / ny)) for i in range(nx + 1)] for j in range(ny + 1)]
    mi = f._mi(M["flag"])
    for j in range(ny):
        for i in range(nx):
            q = bm.faces.new((verts[j][i], verts[j + 1][i], verts[j + 1][i + 1], verts[j][i + 1]))
            q.material_index = mi
            q.smooth = True
            for l in q.loops:
                co = l.vert.co
                u = (co.x - 0.06) / W
                vv = (7.9 - co.z) / H
                l[f.uv].uv = (u, 1 - vv)
                l[f.uv2].uv = (0, u)
    for row in verts:
        for v in row:
            v[f.col] = (1, 1, 1, 1)
    return f.done()


def build_stand(M):
    """6 m long grandstand section, seats face -Y (toward the field)"""
    s = Mesh("StandSegment")
    Lx = 6.0
    for t in range(4):
        y = t * 0.9
        z = 0.45 * (t + 1)
        s.box((0, y + 0.45, z / 2), (Lx, 0.9, z), M["concrete"], uv_scale=0.5)
        s.box((0, y + 0.55, z + 0.05), (Lx - 0.1, 0.36, 0.06), M["wood"], uv_scale=0.6)   # bench plank
    # front railing
    for x in (-2.9, -1.45, 0, 1.45, 2.9):
        s.capsule((x, -0.05, 0), (x, -0.05, 0.95), 0.025, None, 6, 2, M["metal"])
    s.capsule((-3, -0.05, 0.95), (3, -0.05, 0.95), 0.03, None, 6, 2, M["metal"])
    s.capsule((-3, -0.05, 0.55), (3, -0.05, 0.55), 0.02, None, 6, 2, M["metal"])
    # canopy on posts
    for x in (-2.8, 2.8):
        s.capsule((x, 3.5, 1.8), (x, 3.5, 4.2), 0.06, None, 8, 2, M["metal"])
        s.capsule((x, 0.4, 1.0), (x, 0.4, 3.4), 0.05, None, 8, 2, M["metal"])
    bm = s.bm
    pts = [(-3.05, 0.1, 3.35), (3.05, 0.1, 3.35), (3.05, 3.8, 4.25), (-3.05, 3.8, 4.25)]
    v = [bm.verts.new(p) for p in pts]
    fc = bm.faces.new(v)
    fc.material_index = s._mi(M["canopy"])
    for l, uv in zip(fc.loops, ((0, 0), (3, 0), (3, 1), (0, 1))):
        l[s.uv].uv = uv
        l[s.uv2].uv = (0, 0)
    # scalloped valance at the front
    for i in range(12):
        x0 = -3.05 + i * 0.508
        a = bm.verts.new((x0, 0.1, 3.35))
        b = bm.verts.new((x0 + 0.508, 0.1, 3.35))
        c = bm.verts.new((x0 + 0.254, 0.08, 3.05))
        tri = bm.faces.new((a, b, c))
        tri.material_index = s._mi(M["blue"])
        for l in tri.loops:
            l[s.uv].uv = (0.5, 0.5)
            l[s.uv2].uv = (0, 0)
        for vv in (a, b, c):
            vv[s.col] = (1, 1, 1, 1)
    for vv in v:
        vv[s.col] = (1, 1, 1, 1)
    return s.done()


# ---- crowd people: same proportions, so one shader can raise every arm

SKIN = [(0.78, 0.55, 0.38), (0.7, 0.47, 0.32), (0.84, 0.62, 0.45)]
SHOULDER_Z = {"stand": 1.36, "sit": 1.0}


def person(name, pose, hat, rng):
    p = Mesh(name)
    skin = rng.choice(SKIN)
    sz = SHOULDER_Z[pose]
    base = 0.0
    robe = (0.8, 0.8, 0.8)            # tinted per person in Godot
    sash = rng.choice([(0.95, 0.75, 0.2), (0.85, 0.2, 0.15), (0.2, 0.6, 0.35), (0.95, 0.95, 0.9)])
    boot = (0.25, 0.12, 0.06)
    if pose == "stand":
        for s in (-1, 1):
            p.capsule((s * 0.09, -0.02, 0.05), (s * 0.09, 0.0, 0.42), 0.07, 0.065, 8, 4, color=boot)
            p.sphere((s * 0.09, -0.08, 0.05), (0.07, 0.12, 0.06), 8, 6, color=boot)
        # deel: long robe, flared, closed with a diagonal flap
        p.lathe([(0.27, 0.28), (0.25, 0.6), (0.22, 0.95), (0.21, 1.15), (0.2, 1.3), (0.13, 1.4)], 14, color=robe, robe=1, sy=0.78, cap=True)
    else:
        for s in (-1, 1):
            p.capsule((s * 0.1, -0.05, 0.08), (s * 0.1, -0.38, 0.08), 0.075, 0.07, 8, 4, color=robe, robe=1)   # thighs
            p.capsule((s * 0.1, -0.4, 0.06), (s * 0.1, -0.42, -0.34), 0.065, 0.06, 8, 4, color=boot)
        p.lathe([(0.24, 0.0), (0.23, 0.3), (0.21, 0.6), (0.2, 0.8), (0.13, 0.98)], 14, color=robe, robe=1, sy=0.8, cap=True)
    zs = 0.95 if pose == "stand" else 0.48
    p.lathe([(0.225, zs - 0.05), (0.232, zs), (0.225, zs + 0.06)], 14, color=sash, sy=0.8)
    # arms (sleeves) hanging at the sides; UV2.y = 1 on the arm
    for s in (-1, 1):
        sh = Vector((s * 0.2, 0, sz))
        el = Vector((s * 0.25, -0.03, sz - 0.3))
        wr = Vector((s * 0.24, -0.08, sz - 0.56))
        p.capsule(sh, el, 0.075, 0.065, 8, 4, color=robe, robe=1, arm=1)
        p.capsule(el, wr, 0.065, 0.06, 8, 4, color=robe, robe=1, arm=1)
        p.sphere(wr + Vector((0, -0.01, -0.05)), (0.045, 0.035, 0.055), 6, 4, color=skin, arm=1)
    # neck + head
    hz = sz + 0.22
    p.capsule((0, 0, sz - 0.02), (0, 0, sz + 0.1), 0.06, None, 8, 3, color=skin)
    p.sphere((0, -0.005, hz), (0.105, 0.11, 0.125), 12, 8, color=skin)
    p.sphere((0.04, -0.1, hz + 0.02), (0.014, 0.008, 0.014), 4, 3, color=(0.05, 0.04, 0.03))
    p.sphere((-0.04, -0.1, hz + 0.02), (0.014, 0.008, 0.014), 4, 3, color=(0.05, 0.04, 0.03))
    if hat == "mongol":          # traditional pointed hat with upturned brim + red knot
        p.lathe([(0.15, hz + 0.05), (0.16, hz + 0.09), (0.12, hz + 0.1), (0.11, hz + 0.2), (0.03, hz + 0.27)], 14,
                color=rng.choice([(0.15, 0.12, 0.35), (0.12, 0.1, 0.08), (0.55, 0.1, 0.1)]), cap=True)
        p.sphere((0, 0, hz + 0.29), (0.03, 0.03, 0.03), 6, 4, color=(0.85, 0.1, 0.1))
    elif hat == "cap":
        p.sphere((0, 0.0, hz + 0.06), (0.112, 0.118, 0.08), 12, 6, color=rng.choice([(0.1, 0.1, 0.12), (0.85, 0.85, 0.85), (0.1, 0.3, 0.6)]))
        p.sphere((0, -0.12, hz + 0.04), (0.08, 0.06, 0.012), 8, 4, color=(0.1, 0.1, 0.12))
    elif hat == "scarf":         # woman's headscarf
        p.sphere((0, 0.01, hz + 0.02), (0.12, 0.125, 0.135), 12, 8, color=rng.choice([(0.85, 0.3, 0.45), (0.9, 0.75, 0.3), (0.3, 0.55, 0.75)]))
        p.capsule((0, 0.08, hz - 0.08), (0, 0.12, hz - 0.2), 0.05, 0.03, 6, 3, color=(0.85, 0.3, 0.45))
    else:                        # bare head, black hair
        p.sphere((0, 0.015, hz + 0.035), (0.112, 0.116, 0.11), 12, 6, color=(0.06, 0.05, 0.04))
    ob = p.done()
    for v in ob.data.vertices:
        v.co.z += base if pose == "sit" else 0.0
    return ob


def build_larch(name, detail):
    t = Mesh(name)
    bark = (0.3, 0.2, 0.13)
    t.capsule((0, 0, 0), (0, 0, 9.0), 0.22, 0.04, 8, 3, color=bark)
    tiers = 11 if detail else 8
    for i in range(tiers):
        f = i / (tiers - 1)
        z = 1.6 + f * 7.0
        R = 2.4 * (1 - f) ** 0.85 + 0.3
        n = max(4, int(8 * (1 - f) + 3)) if detail else max(3, int(6 * (1 - f) + 2))
        for k in range(n):
            a = 2 * math.pi * k / n + random.uniform(-0.4, 0.4) + i * 1.3
            d = Vector((math.cos(a), math.sin(a), 0))
            c = d * R * random.uniform(0.4, 0.8) + Vector((0, 0, z - R * 0.15 + random.uniform(-0.25, 0.25)))
            g = random.uniform(0.7, 1.2)
            col = (0.17 * g, 0.31 * g, 0.13 * g) if random.random() > 0.15 else (0.28 * g, 0.36 * g, 0.14 * g)
            rot = Quaternion(Vector((-d.y, d.x, 0)), random.uniform(0.25, 0.6))
            sz = random.uniform(0.85, 1.15)
            t.sphere(c, (R * 0.5 * sz, R * 0.42 * sz, R * 0.36 * sz), 6 if detail else 5, 4, rot, color=col)
    t.sphere((0, 0, 8.9), (0.35, 0.35, 0.8), 6, 4, color=(0.15, 0.3, 0.13))
    return t.done()


def build_rock(i):
    r = Mesh(f"Rock_{i}")
    res = bmesh.ops.create_icosphere(r.bm, subdivisions=3, radius=1.0)
    seed = Vector((i * 3.1, i * 1.7, i * 0.3))
    for v in res["verts"]:
        d = noise.fractal(v.co * 1.3 + seed, 1.0, 2.0, 4) * 0.35
        v.co = v.co * (1 + d)
        v.co.z *= 0.6
        v.co.x *= 1.0 + 0.3 * (i % 2)
    r.bm.normal_update()
    for v in res["verts"]:
        lich = max(0.0, noise.noise(v.co * 3 + seed)) * (1 if v.normal.z > 0.3 else 0.2)
        g = 0.45 + noise.noise(v.co * 6) * 0.06
        c = Vector((g, g * 0.98, g * 0.95)).lerp(Vector((0.45, 0.5, 0.25)), min(1, lich * 2))
        v[r.col] = (*srgb(tuple(c)), 1)
    for f in {f for v in res["verts"] for f in v.link_faces}:
        f.smooth = True
        for l in f.loops:
            l[r.uv].uv = (l.vert.co.x, l.vert.co.y)
            l[r.uv2].uv = (0, 0)
    return r.done()


def build_eagle():
    e = Mesh("Eagle")
    brown = (0.33, 0.22, 0.12)
    dark = (0.18, 0.12, 0.07)
    e.sphere((0, 0, 0), (0.18, 0.5, 0.17), 10, 6, color=brown)
    e.sphere((0, -0.48, 0.06), (0.11, 0.13, 0.11), 8, 6, color=(0.45, 0.33, 0.18))
    e.capsule((0, -0.6, 0.05), (0, -0.68, 0.0), 0.035, 0.01, 6, 3, color=(0.95, 0.75, 0.2))
    # tail fan
    bm = e.bm
    tl = [bm.verts.new(p) for p in ((-0.06, 0.4, 0), (0.06, 0.4, 0), (0.22, 0.85, 0.02), (-0.22, 0.85, 0.02))]
    ft = bm.faces.new(tl)
    for l in ft.loops:
        l[e.uv2].uv = (0, 0)
    for v in tl:
        v[e.col] = (*srgb(dark), 1)
    # wings: UV2.y = distance from the body (0 = body, 1 = tip) for the flap shader
    for s in (-1, 1):
        prof = [(0.12, -0.18, 0.18), (0.6, -0.15, 0.3), (1.15, -0.05, 0.26), (1.6, 0.05, 0.16), (1.8, 0.15, 0.08)]
        front = [Vector((s * x, y, 0.02)) for x, y, w in prof]
        back = [Vector((s * x, y + w * 2.0, 0.02)) for x, y, w in prof]
        vs_f = [bm.verts.new(p) for p in front]
        vs_b = [bm.verts.new(p) for p in back]
        for i in range(len(prof) - 1):
            q = bm.faces.new((vs_f[i], vs_f[i + 1], vs_b[i + 1], vs_b[i]) if s > 0 else (vs_f[i], vs_b[i], vs_b[i + 1], vs_f[i + 1]))
            for l in q.loops:
                l[e.uv2].uv = (0, abs(l.vert.co.x) / 1.8)
        for v in vs_f + vs_b:
            t = abs(v.co.x) / 1.8
            c = Vector(brown).lerp(Vector(dark), t)
            v[e.col] = (*srgb(tuple(c)), 1)
    return e.done()


def build_props():
    M = {
        "felt": mat("Felt", image="felt.png", rough=0.95, double=True),
        "band": mat("OrnamentBand", image="ornament_band.png", rough=0.8, double=True),
        "skirt": mat("GerSkirt", (0.35, 0.33, 0.3), 0.95),
        "orange": mat("PaintedWood", (0.88, 0.45, 0.13), 0.55),
        "door": mat("Door", image="door.png", rough=0.5),
        "wood": mat("Wood", image="wood.png", rough=0.8),
        "metal": mat("Metal", (0.25, 0.25, 0.27), 0.4, metal=0.8),
        "rope": mat("Rope", (0.55, 0.42, 0.28), 0.9),
        "stone": mat("Stone", image="rock.png", rough=0.9),
        "lacquer": mat("Lacquer", (0.45, 0.08, 0.06), 0.35),
        "hair": mat("Horsehair", image="horsehair.png", alpha=True, rough=0.6, double=True),
        "gold": mat("Gold", (0.95, 0.72, 0.25), 0.3, metal=0.9),
        "silver": mat("Silver", (0.86, 0.86, 0.9), 0.25, metal=0.9),
        "pole": mat("FlagPole", (0.85, 0.85, 0.85), 0.35, metal=0.6),
        "flag": mat("FlagCloth", image="flag_mongolia.png", rough=0.7, double=True),
        "concrete": mat("Concrete", (0.72, 0.7, 0.66), 0.9),
        "canopy": mat("Canopy", image="canopy.png", rough=0.8, double=True),
        "blue": mat("CanopyBlue", (0.12, 0.28, 0.62), 0.8, double=True),
    }
    objs = [build_ger(M), build_tug(M), build_flag(M), build_stand(M)]
    rng = random.Random(5)
    for pose in ("stand", "sit"):
        for hat in ("mongol", "cap", "scarf", "bare"):
            objs.append(person(f"Person_{pose}_{hat}", pose, hat, rng))
    objs += [build_larch("Larch", True), build_larch("Larch_Far", False)]
    objs += [build_rock(i) for i in (1, 2, 3)]
    objs.append(build_eagle())
    # line them up so the .blend is easy to look at (Godot uses them by name)
    for i, o in enumerate(objs):
        o.location.x = i * 8.0
    return objs


def export(objs, path):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
              export_animations=False, export_vertex_color='NAME', export_vertex_color_name='Col', export_all_vertex_colors=True)
    while True:
        try:
            bpy.ops.export_scene.gltf(**kw)
            return
        except TypeError as e:
            bad = [k for k in kw if k in str(e)]
            if not bad:
                raise
            kw.pop(bad[0])


def main():
    clear()
    os.makedirs(OUT, exist_ok=True)
    terrain = build_terrain()
    export([terrain], os.path.join(OUT, "terrain.glb"))
    with open(os.path.join(OUT, "scatter.json"), "w") as f:
        json.dump(scatter(), f)
    bpy.data.objects.remove(terrain, do_unlink=True)
    props = build_props()
    export(props, os.path.join(OUT, "naadam_props.glb"))
    if os.environ.get("NC_SAVE_BLEND"):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "naadam_props.blend"))
    print("props:", ", ".join(o.name for o in props))


if __name__ == "__main__":
    main()
