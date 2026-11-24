"""
Naadam Chaos - procedural textures for the environment (no internet / no stock images).
Run with plain Python 3 (numpy + Pillow):  python3 art/blender/make_textures.py
Writes PNGs to assets/env/textures/.
"""
import os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "env", "textures")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def tile_noise(n, cells, seed=0):
    """periodic (tileable) smooth value noise, n x n, values 0..1"""
    r = np.random.default_rng(seed)
    g = r.random((cells, cells))
    x = np.arange(n) * cells / n
    i0 = np.floor(x).astype(int)
    f = x - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % cells
    a = g[i0][:, i0] * (1 - f)[None, :] + g[i0][:, i1] * f[None, :]
    b = g[i1][:, i0] * (1 - f)[None, :] + g[i1][:, i1] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]


def fbm(n, base=4, octaves=5, seed=0):
    out = np.zeros((n, n))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += tile_noise(n, base * 2 ** o, seed + o * 17) * amp
        tot += amp
        amp *= 0.5
    return out / tot


def save(arr, name):
    arr = np.clip(arr, 0, 255).astype(np.uint8)
    Image.fromarray(arr).save(os.path.join(OUT, name))


def lerp(a, b, t):
    return a + (b - a) * t[..., None]


# ------------------------------------------------------------ ground: steppe grass (tileable, 1024)
def ground_grass():
    n = 1024
    base = fbm(n, 4, 6, 1)
    fine = fbm(n, 64, 3, 2)
    c1 = np.array([62, 104, 40], float)
    c2 = np.array([104, 140, 56], float)
    c3 = np.array([150, 150, 82], float)   # dry
    col = lerp(c1, c2, base)
    col = lerp(col, c3, np.clip((fbm(n, 3, 4, 3) - 0.55) * 4, 0, 1) * 0.5)
    col *= (0.82 + fine * 0.35)[..., None]
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8))
    # little blade strokes, wrapped so it stays tileable
    d = ImageDraw.Draw(img)
    for _ in range(26000):
        x, y = rng.integers(0, n, 2)
        l = rng.integers(4, 11)
        a = rng.uniform(-0.6, 0.6) - math.pi / 2
        shade = rng.uniform(0.7, 1.35)
        c = tuple(int(min(255, v * shade)) for v in (88, 128, 50))
        for ox in (0, -n, n):
            for oy in (0, -n, n):
                d.line([(x + ox, y + oy), (x + ox + math.cos(a) * l, y + oy + math.sin(a) * l)], fill=c, width=1)
    img.save(os.path.join(OUT, "ground_grass.png"))


def ground_dirt():
    n = 512
    b = fbm(n, 6, 6, 11)
    f = fbm(n, 48, 3, 12)
    c1 = np.array([118, 98, 68], float)
    c2 = np.array([160, 138, 98], float)
    col = lerp(c1, c2, b) * (0.85 + 0.3 * f)[..., None]
    # pebbles
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    for _ in range(900):
        x, y = rng.integers(0, n, 2)
        r = rng.uniform(1, 3)
        g = int(rng.uniform(90, 170))
        d.ellipse([x - r, y - r, x + r, y + r], fill=(g, g - 8, g - 20))
    img.save(os.path.join(OUT, "ground_dirt.png"))


def rock():
    n = 512
    b = fbm(n, 5, 7, 21)
    ridge = 1 - np.abs(fbm(n, 8, 5, 22) * 2 - 1)
    c1 = np.array([92, 90, 86], float)
    c2 = np.array([150, 146, 138], float)
    col = lerp(c1, c2, b * 0.7 + ridge * 0.3)
    lichen = np.clip((fbm(n, 12, 4, 23) - 0.62) * 5, 0, 1)
    col = lerp(col, np.array([120, 130, 70], float), lichen * 0.6)
    save(col, "rock.png")


# ------------------------------------------------------------ ger felt (white canvas cover)
def felt():
    n = 512
    f = fbm(n, 16, 5, 31)
    col = np.ones((n, n, 3)) * np.array([236, 232, 220], float)
    col *= (0.93 + 0.09 * f)[..., None]
    # fibres
    fib = fbm(n, 128, 2, 32)
    col *= (0.97 + 0.05 * fib)[..., None]
    # vertical seams every 128 px
    xs = np.arange(n)
    seam = (np.abs((xs % 128) - 64) > 61)
    col[:, seam] *= 0.86
    # dusty bottom (v = 1 at the bottom of the wall)
    v = np.linspace(0, 1, n)
    col *= (1 - 0.22 * np.clip((v - 0.8) / 0.2, 0, 1) ** 1.5)[:, None, None]
    save(col, "felt.png")


# ------------------------------------------------------------ ornaments (alkhan khee meander + ulziy)
BLUE = (28, 66, 150)
RED = (190, 36, 32)
ORANGE = (228, 120, 32)
GOLD = (240, 190, 60)
WHITE = (245, 240, 228)
GREEN = (40, 120, 80)


def meander(d, x0, y0, w, h, cell, col, width):
    """repeating Mongolian 'alkhan' key pattern (simplified Greek-key) along a band"""
    x = x0
    while x < x0 + w:
        s = cell
        pts = [(x, y0 + h - 2), (x, y0 + 2), (x + s * 0.8, y0 + 2), (x + s * 0.8, y0 + h * 0.65),
               (x + s * 0.35, y0 + h * 0.65), (x + s * 0.35, y0 + h * 0.35), (x + s * 0.55, y0 + h * 0.35)]
        d.line(pts, fill=col, width=width, joint="curve")
        d.line([(x, y0 + h - 2), (x + s, y0 + h - 2)], fill=col, width=width)
        x += s


def ulziy(d, cx, cy, r, col, width):
    """endless knot (өлзий), simplified: interlaced squares rotated 45 degrees with loops"""
    k = r * 0.45
    for ang in (0, 90):
        a = math.radians(ang + 45)
        pts = []
        for i in range(5):
            t = a + i * math.pi / 2
            pts.append((cx + math.cos(t) * r, cy + math.sin(t) * r))
        d.line(pts, fill=col, width=width)
    for i in range(4):
        t = math.radians(45 + i * 90)
        lx, ly = cx + math.cos(t) * r, cy + math.sin(t) * r
        d.ellipse([lx - k, ly - k, lx + k, ly + k], outline=col, width=width)
    d.ellipse([cx - r * 0.25, cy - r * 0.25, cx + r * 0.25, cy + r * 0.25], outline=col, width=width)


def ornament_band():
    w, h = 1024, 128
    img = Image.new("RGB", (w, h), BLUE)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w, 10], fill=RED)
    d.rectangle([0, h - 10, w, h], fill=RED)
    meander(d, 6, 20, w, h - 40, 64, WHITE, 6)
    img.save(os.path.join(OUT, "ornament_band.png"))


def door():
    w, h = 512, 768
    img = Image.new("RGB", (w, h), ORANGE)
    d = ImageDraw.Draw(img)
    # frame + 2 leaves
    d.rectangle([0, 0, w - 1, h - 1], outline=RED, width=26)
    d.line([(w / 2, 0), (w / 2, h)], fill=RED, width=14)
    for x0 in (30, w / 2 + 12):
        x1 = x0 + w / 2 - 42
        d.rectangle([x0, 40, x1, h - 40], outline=BLUE, width=8)
        d.rectangle([x0 + 16, 56, x1 - 16, h - 56], outline=GOLD, width=4)
        cx = (x0 + x1) / 2
        ulziy(d, cx, h * 0.33, 60, BLUE, 7)
        ulziy(d, cx, h * 0.33, 60, GOLD, 2)
        # clouds (үүлэн хээ): two spirals
        for cy in (h * 0.62, h * 0.78):
            for s in (-1, 1):
                for k in range(3):
                    r = 26 - k * 8
                    d.arc([cx + s * 32 - r, cy - r, cx + s * 32 + r, cy + r], 0 if s > 0 else 180, 360 if s > 0 else 540, fill=GREEN if k % 2 else BLUE, width=5)
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    img.save(os.path.join(OUT, "door.png"))


def wood():
    n = 512
    y = np.linspace(0, 1, n)[:, None]
    grain = fbm(n, 4, 4, 41)
    rings = np.sin((y * 40 + grain * 6) * math.pi) * 0.5 + 0.5
    c1 = np.array([92, 58, 32], float)
    c2 = np.array([140, 94, 56], float)
    col = lerp(c1, c2, rings * 0.6 + fbm(n, 32, 3, 42) * 0.4)
    save(np.transpose(col, (1, 0, 2)), "wood.png")


# ------------------------------------------------------------ horsehair (white tassels of the Nine Banners)
def horsehair():
    w, h = 256, 512
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for _ in range(520):
        x = rng.uniform(0, w)
        l = rng.uniform(0.72, 1.0) * h
        sway = rng.uniform(-10, 10)
        g = int(rng.uniform(215, 255))
        a = int(rng.uniform(150, 255))
        pts = [(x + sway * (t / 8) ** 2, t / 8 * l) for t in range(9)]
        d.line(pts, fill=(g, g, int(g * 0.96), a), width=int(rng.integers(1, 3)))
    img.save(os.path.join(OUT, "horsehair.png"))


# ------------------------------------------------------------ Mongolian flag with the Soyombo
def flag():
    w, h = 1200, 600
    img = Image.new("RGB", (w, h), (196, 39, 45))
    d = ImageDraw.Draw(img)
    d.rectangle([w / 3, 0, 2 * w / 3, h], fill=(1, 95, 165))
    y = (255, 210, 0)
    cx = w / 6
    s = h / 600  # scale
    # Soyombo (simplified but faithful order): fire, sun, moon, triangle, bar, yin-yang, bar, triangle, side pillars
    # fire: three tongues
    for dx, top in ((-26, 92), (0, 70), (26, 92)):
        d.polygon([(cx + dx - 14 * s, 140 * s), (cx + dx, top * s), (cx + dx + 14 * s, 140 * s)], fill=y)
    d.ellipse([cx - 34 * s, 128 * s, cx + 34 * s, 160 * s], fill=y)
    # sun
    d.ellipse([cx - 32 * s, 168 * s, cx + 32 * s, 232 * s], fill=y)
    # moon (crescent)
    d.ellipse([cx - 44 * s, 220 * s, cx + 44 * s, 300 * s], fill=y)
    d.ellipse([cx - 44 * s, 206 * s, cx + 44 * s, 278 * s], fill=(196, 39, 45))
    # triangle (points down) + bar
    d.polygon([(cx - 44 * s, 306 * s), (cx + 44 * s, 306 * s), (cx, 340 * s)], fill=y)
    d.rectangle([cx - 44 * s, 348 * s, cx + 44 * s, 362 * s], fill=y)
    # yin-yang (two fish)
    R = 40 * s
    cy = 410 * s
    d.ellipse([cx - R, cy - R, cx + R, cy + R], fill=y)
    d.pieslice([cx - R, cy - R, cx + R, cy + R], 90, 270, fill=(196, 39, 45))
    d.ellipse([cx - R / 2, cy - R, cx + R / 2, cy], fill=(196, 39, 45))
    d.ellipse([cx - R / 2, cy, cx + R / 2, cy + R], fill=y)
    d.ellipse([cx - 6 * s, cy - R / 2 - 6 * s, cx + 6 * s, cy - R / 2 + 6 * s], fill=y)
    d.ellipse([cx - 6 * s, cy + R / 2 - 6 * s, cx + 6 * s, cy + R / 2 + 6 * s], fill=(196, 39, 45))
    # bar + triangle
    d.rectangle([cx - 44 * s, 458 * s, cx + 44 * s, 472 * s], fill=y)
    d.polygon([(cx - 44 * s, 480 * s), (cx + 44 * s, 480 * s), (cx, 514 * s)], fill=y)
    # pillars
    for sx in (-1, 1):
        d.rectangle([cx + sx * 56 * s - 8 * s, 306 * s, cx + sx * 56 * s + 8 * s, 514 * s], fill=y)
    img.save(os.path.join(OUT, "flag_mongolia.png"))


# ------------------------------------------------------------ canopy fabric for the grandstand
def canopy():
    w, h = 512, 256
    img = Image.new("RGB", (w, h), WHITE)
    d = ImageDraw.Draw(img)
    for i in range(0, w, 64):
        d.rectangle([i, 0, i + 31, h], fill=BLUE)
    meander(d, 0, h - 44, w, 40, 40, GOLD, 4)
    img.save(os.path.join(OUT, "canopy.png"))


if __name__ == "__main__":
    ground_grass(); ground_dirt(); rock(); felt(); ornament_band(); door(); wood(); horsehair(); flag(); canopy()
    print("textures:", sorted(os.listdir(OUT)))
