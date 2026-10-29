"""Draws a built map with the game's own art, the way Godot will: the floor
tiles, then everything standing sorted by its feet."""
import os
import random

from PIL import Image

# The game's folder: this file is in tools/maps/.
PIC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..") + os.sep
TILE = 16
PIECES = {  # scene: (texture, region x, y, w, h, offset y, scale, offset x)
    "wallrun1": ("floorwalls", 71, 11, 26, 28, -14),
    "wallrun2": ("floorwalls", 100, 11, 51, 28, -14),
    "wallrun4": ("floorwalls", 154, 11, 101, 28, -14),
    "pillar": ("floorwalls", 260, 9, 17, 30, -15),
    "wallsidea": ("floorwalls", 326, 36, 9, 36, -18),
    "wallsideb": ("floorwalls", 326, 77, 9, 35, -17.5),
    "wallsidetall": ("floorwalls", 326, 118, 9, 58, -29),
    "wallcornerbackleft": ("floorwalls", 344, 36, 26, 36, -18),
    "wallcornerbackright": ("floorwalls", 342, 77, 25, 36, -18),
    "wallcornerfrontleft": ("floorwalls", 344, 118, 26, 58, -29),
    "wallcornerfrontright": ("floorwalls", 344, 182, 26, 57, -28.5),
}
_tex = {}


def tex(name):
    if name not in _tex:
        path = {"floorwalls": "art/floordecoration/floorwalls.png", "underground": "art/tiles/underground.png",
                "cryptdoor": "art/floordecoration/cryptdoor.png"}[name]
        _tex[name] = Image.open(PIC + path).convert("RGBA")
    return _tex[name]


def region(name, x, y, w, h, scale=1):
    im = tex(name).crop((x, y, x + w, y + h))
    if scale != 1:
        im = im.resize((w * scale, h * scale), Image.NEAREST)
    return im


def draw(floor, tiles, pieces, box=None, extra=None, seed=7):
    """floor: rows of bools; tiles: {(cx, cy): (ax, ay)} overriding the plain
    floor; pieces: [scene, x, y]; box: (x0, y0, x1, y1) px to draw; extra:
    [(foot y, callable(img, ox, oy))] drawn sorted with the pieces."""
    h, w = len(floor), len(floor[0])
    if box is None:
        box = (0, 0, w * TILE, h * TILE)
    x0, y0, x1, y1 = [int(v) for v in box]
    img = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 255))
    ug = tex("underground")
    rng = random.Random(seed)
    for cy in range(max(0, y0 // TILE), min(h, y1 // TILE + 1)):
        for cx in range(max(0, x0 // TILE), min(w, x1 // TILE + 1)):
            at = tiles.get((cx, cy))
            if at is None:
                if not floor[cy][cx]:
                    continue
                r = random.Random(cx * 7919 + cy * 104729 + seed)
                at = (r.randint(1, 4), r.randint(1, 3))
            if at == "void":
                continue
            t = ug.crop((at[0] * 16, at[1] * 16, at[0] * 16 + 16, at[1] * 16 + 16))
            img.alpha_composite(t, (cx * TILE - x0, cy * TILE - y0))
    items = []
    for scene, x, y in pieces:
        items.append((y, scene, x))
    for e in (extra or []):
        items.append((e[0], e[1], None))
    items.sort(key=lambda t: t[0])
    for y, what, x in items:
        if callable(what):
            what(img, x0, y0)
            continue
        texname, rx, ry, rw, rh, off = PIECES[what]
        im = region(texname, rx, ry, rw, rh)
        left = int(round(x - rw / 2.0)) - x0
        top = int(round(y + off - rh / 2.0)) - y0
        if left + rw < 0 or top + rh < 0 or left > x1 - x0 or top > y1 - y0:
            continue
        _paste(img, im, left, top)
    return img


def _paste(img, im, left, top):
    cx0, cy0 = max(0, -left), max(0, -top)
    cx1 = min(im.size[0], img.size[0] - left)
    cy1 = min(im.size[1], img.size[1] - top)
    if cx1 <= cx0 or cy1 <= cy0:
        return
    im = im.crop((cx0, cy0, cx1, cy1))
    img.alpha_composite(im, (left + cx0, top + cy0))


def door(x, y):
    """The crypt door at (x, y), its foot: stone sides and planks at 2x."""
    def paint(img, ox, oy):
        for rx, w, cx in ((14, 9, -30), (23, 21, 0), (44, 9, 30)):
            im = region("cryptdoor", rx, 19, w, 28, 2)
            left = int(round(x + cx - w)) - ox
            top = int(round(y - 28 - 28)) - oy
            _paste(img, im, left, top)
    return (y, paint)
