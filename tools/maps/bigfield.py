"""The Big Field (0.94.0): the hub-and-wings map, built to be walled.

THE CROSSROADS, where you arrive, and a wing a tier off it - the courts
(light, wind), the chasm and its rift (water, ice), the caverns and their
arena (earth), the fortress (fire), the descent with the ladder at its heart
(dark) - and the crypt, the skeletons' own. Every shape is one the crypt
walls can edge exactly (walls.py): rooms are made of rectangles, every step
wide enough for a wall piece, rooms and corridors keep rock between them for
both their walls, and corridors leave a room straight out of one of its
sides. Writes the build file src/tools/buildbigfield.gd reads, and pictures.

    python3 tools/maps/bigfield.py [SEED] [OUT_DIR]       (seed 22 is the map)
    then copy OUT_DIR/bigfield_build.json over tools/maps/bigfield_build.json
    and run buildbigfield.gd's build() (zz/ has a scene for it).

Needs numpy, scipy and Pillow (pip install numpy scipy pillow).
PICS=0 skips the pictures.
"""
import heapq
import json
import math
import os
import random
import sys

import numpy as np
from scipy.ndimage import label, maximum_filter

import walls

SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 22
OUT = sys.argv[2] if len(sys.argv) > 2 else "out"
rng = random.Random(SEED)
TW, TH = 385, 322
TILE = 16
CLR = 5            # cells of rock kept inside a shape (tidy)
CLR_X, CLR_Y = 3, 4   # rock between two places that do not join: two columns
                      # side by side need 18 px, a front wall over a back 56
ROOM_GAP = 12      # between rooms, so a corridor can pass
MARGIN = 3         # cells of wall either side of a corridor's mouth
SAFE = 25          # no pack this many cells from where you arrive

floor = np.zeros((TH, TW), bool)
owner = np.full((TH, TW), -1, int)      # which room or corridor a cell is
reserved = np.zeros((TH, TW), bool)     # the chasm: no floor, no corridor
chasm_open = np.zeros((TH, TW), bool)   # rock cells whose edges are open
rooms, corridors, doors, gates, levers, pillars = [], [], [], [], [], []
REGION = [0]


def new_region():
    REGION[0] += 1
    return REGION[0] - 1


# =============================================================================
# SHAPES - a room is a mask of cells inside its box
# =============================================================================

def shape_rect(w, h):
    return np.ones((h, w), bool)


def shape_plus(w, h):
    m = np.zeros((h, w), bool)
    a, b = max(5, w // 4), max(5, h // 4)
    m[:, a:w - a] = True
    m[b:h - b, :] = True
    return m


def shape_octa(w, h):
    """A rectangle with its corners stepped off: reads as round in walls."""
    m = np.ones((h, w), bool)
    cw, ch = max(3, w // 5), max(5, h // 5)
    for (xs, ys) in ((slice(0, cw), slice(0, ch)), (slice(w - cw, w), slice(0, ch)),
                     (slice(0, cw), slice(h - ch, h)), (slice(w - cw, w), slice(h - ch, h))):
        m[ys, xs] = False
    if w >= 30 and h >= 30:   # a second step, rounder
        cw2, ch2 = cw + max(3, w // 8), 5
        for (xs, ys) in ((slice(0, cw2), slice(0, ch2)), (slice(w - cw2, w), slice(0, ch2)),
                         (slice(0, cw2), slice(h - ch2, h)), (slice(w - cw2, w), slice(h - ch2, h))):
            m[ys, xs] = False
    return m


def shape_L(w, h):
    m = np.ones((h, w), bool)
    a, b = rng.randint(w // 3, w // 2), rng.randint(h // 3, h // 2)
    corner = rng.randint(0, 3)
    xs = slice(0, a) if corner in (0, 2) else slice(w - a, w)
    ys = slice(0, b) if corner in (0, 1) else slice(h - b, h)
    m[ys, xs] = False
    return m


def shape_ring(w, h):
    m = np.ones((h, w), bool)
    hw, hh = rng.choice([7, 8, 9, 10]), rng.choice([5, 6, 7, 8])
    x0, y0 = (w - hw) // 2, (h - hh) // 2
    if x0 < CLR + 1 or y0 < CLR + 1:
        return None
    m[y0:y0 + hh, x0:x0 + hw] = False
    return m


def shape_cavern(w, h):
    """Blocks heaped round a middle one, on a four-cell grid: every step of
    its edge is wide enough for a wall piece."""
    gw, gh = w // 4, h // 4
    g = np.zeros((gh, gw), bool)
    g[gh // 4:gh - gh // 4, gw // 4:gw - gw // 4] = True
    for _ in range(rng.randint(3, 5)):
        rw, rh = rng.randint(2, max(2, gw - 2)), rng.randint(2, max(2, gh - 2))
        x, y = rng.randint(0, gw - rw), rng.randint(0, gh - rh)
        g[y:y + rh, x:x + rw] = True
    # no diagonal-only touches, no one-block notches
    for _ in range(3):
        for y in range(gh - 1):
            for x in range(gw - 1):
                q = g[y:y + 2, x:x + 2]
                if q.sum() == 2 and q[0, 0] == q[1, 1]:
                    q[:] = True
        for y in range(1, gh - 1):
            for x in range(1, gw - 1):
                if not g[y, x] and g[y - 1, x] + g[y + 1, x] + g[y, x - 1] + g[y, x + 1] >= 3:
                    g[y, x] = True
    lab, n = label(g)
    if n > 1:
        sizes = [(lab == i).sum() for i in range(1, n + 1)]
        g = lab == (1 + int(np.argmax(sizes)))
    m = np.kron(g, np.ones((4, 4), bool))
    out = np.zeros((h, w), bool)
    out[:m.shape[0], :m.shape[1]] = m
    return out


def tidy(m):
    """No sliver of rock or floor too thin for a wall: rock gaps under CLR
    cells inside the box are filled, floor fingers under 4 cells cut off."""
    h, w = m.shape
    for _ in range(4):
        changed = False
        for y in range(h):
            row = m[y]
            xs = np.nonzero(row)[0]
            if len(xs) == 0:
                continue
            x = xs[0]
            while x < xs[-1]:
                if not row[x]:
                    e = x
                    while not row[e]:
                        e += 1
                    if e - x < CLR:
                        m[y, x:e] = True
                        changed = True
                    x = e
                else:
                    x += 1
        for x in range(w):
            col = m[:, x]
            ys = np.nonzero(col)[0]
            if len(ys) == 0:
                continue
            y = ys[0]
            while y < ys[-1]:
                if not col[y]:
                    e = y
                    while not col[e]:
                        e += 1
                    if e - y < CLR:
                        m[y:e, x] = True
                        changed = True
                    y = e
                else:
                    y += 1
        # floor runs thinner than 4 cells go
        for y in range(h):
            run = 0
            for x in range(w + 1):
                if x < w and m[y, x]:
                    run += 1
                else:
                    if 0 < run < 4:
                        m[y, x - run:x] = False
                        changed = True
                    run = 0
        for x in range(w):
            run = 0
            for y in range(h + 1):
                if y < h and m[y, x]:
                    run += 1
                else:
                    if 0 < run < 5:
                        m[y - run:y, x] = False
                        changed = True
                    run = 0
        if not changed:
            break
    lab, n = label(m)
    if n > 1:
        sizes = [(lab == i).sum() for i in range(1, n + 1)]
        m = lab == (1 + int(np.argmax(sizes)))
    return m


SHAPES = {"rect": shape_rect, "plus": shape_plus, "octa": shape_octa, "L": shape_L, "ring": shape_ring,
          "cavern": shape_cavern, "hall": shape_rect}


def wallable(mask):
    """Can the crypt walls edge this shape on their own?"""
    pad = np.zeros((mask.shape[0] + 4, mask.shape[1] + 4), bool)
    pad[2:-2, 2:-2] = mask
    try:
        for lp in walls.loops(pad.tolist()):
            walls.solve(lp)
    except ValueError:
        return False
    return True


# =============================================================================
# ROOMS
# =============================================================================

def free_box(x, y, w, h, gap=ROOM_GAP):
    if x - gap < 1 or y - gap < 1 or x + w + gap > TW - 1 or y + h + gap > TH - 1:
        return False
    return not (floor[y - gap:y + h + gap, x - gap:x + w + gap].any()
                or reserved[y - gap:y + h + gap, x - gap:x + w + gap].any())


def place(mask, x, y, wing, kind, shape):
    h, w = mask.shape
    rid = new_region()
    floor[y:y + h, x:x + w] |= mask
    owner[y:y + h, x:x + w][mask] = rid
    ys, xs = np.nonzero(mask)
    room = {"id": rid, "wing": wing, "kind": kind, "shape": shape, "x": x, "y": y, "w": w, "h": h,
            "cx": int(x + xs.mean()), "cy": int(y + ys.mean()), "cells": int(mask.sum())}
    if not floor[room["cy"], room["cx"]] or owner[room["cy"], room["cx"]] != rid:
        k = len(xs) // 2
        room["cx"], room["cy"] = int(x + xs[k]), int(y + ys[k])
    rooms.append(room)
    if shape == "hall":
        for py in range(y + 5, y + h - 4, 7):
            for px in range(x + 5, x + w - 4, 8):
                if abs(py - (y + h // 2)) >= 3:
                    pillars.append((px * TILE + 8, py * TILE + 12))
    return room


WHY = {}


def fill(wing, box, target, shapes, weights, **kw):
    """Rooms into a wing until it holds `target` or no more will go."""
    got = []
    misses = 0
    while len(got) < target and misses < 6:
        r = add_room(wing, box, shapes, weights, **kw)
        if r:
            got.append(r)
            misses = 0
        else:
            misses += 1
    wings[wing] += got
    return got


def add_room(wing, box, shapes, weights, kind="room", wr=(18, 30), hr=(16, 26), tries=800, square=False,
             gap=ROOM_GAP):
    x0, y0, x1, y1 = box
    for _ in range(tries):
        sh = rng.choices(shapes, weights)[0]
        w, h = rng.randint(*wr), rng.randint(*hr)
        if square or sh in ("octa", "plus", "ring"):
            w = h = max(w, h) if square else min(w, h) + rng.randint(0, 4)
        if sh == "hall":
            w, h = max(w, 26), max(h, 20)
        if w > x1 - x0 or h > y1 - y0:
            continue
        x, y = rng.randint(x0, x1 - w), rng.randint(y0, y1 - h)
        if not free_box(x, y, w, h, gap=gap):
            WHY["space"] = WHY.get("space", 0) + 1
            continue
        mask = SHAPES[sh](w, h)
        if mask is None or not wallable(mask):
            WHY[sh] = WHY.get(sh, 0) + 1
            continue
        return place(mask, x, y, wing, kind, sh)
    return None


def room_at(rid):
    return next(r for r in rooms if r["id"] == rid)


# =============================================================================
# CORRIDORS - routed round everything, CLR cells clear, straight out of a side
# =============================================================================

def _sat(a):
    s = np.zeros((a.shape[0] + 1, a.shape[1] + 1), np.int32)
    s[1:, 1:] = np.cumsum(np.cumsum(a.astype(np.int32), 0), 1)
    return s


def _box_sum(s, x, y, w, h):
    if x < 0 or y < 0 or x + w > TW or y + h > TH:
        return 1
    return int(s[y + h, x + w] - s[y, x + w] - s[y + h, x] + s[y, x])


DIRS = {"N": (0, -1), "S": (0, 1), "W": (-1, 0), "E": (1, 0)}


def mouths(room, side, w):
    """Where a corridor w cells wide can leave this room's side: the brush's
    top-left just outside, and the way out."""
    m = owner == room["id"]
    out = []
    if side in ("N", "S"):
        ys = np.nonzero(m.any(1))[0]
        y = ys[0] if side == "N" else ys[-1]
        row = m[y]
        for x in range(room["x"], room["x"] + room["w"] - w + 1):
            if row[x - MARGIN:x + w + MARGIN].all() and x - MARGIN >= room["x"]:
                out.append((x, y - w if side == "N" else y + 1))
    else:
        xs = np.nonzero(m.any(0))[0]
        x = xs[0] if side == "W" else xs[-1]
        col = m[:, x]
        for y in range(room["y"], room["y"] + room["h"] - w + 1):
            if col[y - MARGIN:y + w + MARGIN].all() and y - MARGIN >= room["y"]:
                out.append((x - w if side == "W" else x + 1, y))
    return out


def route(a, b, w, sides_a=None, sides_b=None, stub=6, turn=10, tag="way", box=None, stub_b=None):
    """A corridor w cells wide from room a to room b. Returns its record, or
    None when no way round everything is clear. With a box, it stays in it."""
    ids = (a["id"], b["id"])
    mine = np.isin(owner, ids)
    foreign = (floor & ~mine) | reserved
    if box is not None:
        outside = np.ones_like(foreign)
        outside[max(0, box[1] - 2):box[3] + 2, max(0, box[0] - 2):box[2] + 2] = False
        foreign |= outside
    foreign[:2, :] = foreign[-2:, :] = True
    foreign[:, :2] = foreign[:, -2:] = True
    size = (2 * CLR_Y + 1, 2 * CLR_X + 1)
    near_foreign = maximum_filter(foreign.astype(np.uint8), size=size) > 0
    near_all = maximum_filter((foreign | mine).astype(np.uint8), size=size) > 0
    s_foreign, s_all = _sat(near_foreign), _sat(near_all)
    s_floor = _sat(floor)

    def stubs(room, sides, length):
        res = []
        for side in sides or "NSWE":
            dx, dy = DIRS[side]
            for (bx, by) in mouths(room, side, w):
                ok = True
                cells = []
                for k in range(length):
                    x, y = bx + dx * k, by + dy * k
                    if _box_sum(s_foreign, x, y, w, w) or _box_sum(s_floor, x, y, w, w):
                        ok = False
                        break
                    cells.append((x, y))
                if ok:
                    res.append((cells, side))
        return res

    starts = stubs(a, sides_a, stub)
    ends = stubs(b, sides_b, stub_b or 6)
    if not starts or not ends:
        return None
    goal = {}
    for cells, side in ends:
        goal.setdefault(cells[-1], (cells, side))
    # two rooms facing each other close by: the stubs meet head on
    along = {}
    for cells, side in ends:
        for i, c in enumerate(cells):
            along.setdefault(c, (cells[:i + 1], side))
    direct = None
    for cells, side in starts:
        for i, c in enumerate(cells):
            if c in along and (DIRS[side][0] + DIRS[along[c][1]][0], DIRS[side][1] + DIRS[along[c][1]][1]) == (0, 0):
                cand = cells[:i + 1] + list(reversed(along[c][0]))
                if direct is None or len(cand) < len(direct):
                    direct = cand
                break
    if direct is not None:
        return _carve_way(a, b, w, direct, tag)
    tx, ty = b["cx"], b["cy"]
    openq = []
    best = {}
    came = {}
    for cells, side in starts:
        x, y = cells[-1]
        st = (x, y, side, min(len(cells), w))
        best[st] = 0
        came[st] = ("start", cells)
        heapq.heappush(openq, (abs(x - tx) + abs(y - ty), 0, st))
    found = None
    expanded = 0
    while openq:
        f, g, st = heapq.heappop(openq)
        if g > best.get(st, 1e18):
            continue
        x, y, d, k = st
        if (x, y) in goal and (k >= w or goal[(x, y)][1] == {"N": "S", "S": "N", "W": "E", "E": "W"}[d]):
            found = st
            break
        expanded += 1
        if expanded > 600000:
            break
        for nd, (dx, dy) in DIRS.items():
            if (DIRS[d][0] + dx, DIRS[d][1] + dy) == (0, 0):
                continue
            if nd != d and k < w:      # every straight piece at least as long as it is wide
                continue
            nx, ny = x + dx, y + dy
            if (nx, ny) not in goal and _box_sum(s_all, nx, ny, w, w):
                continue
            if (nx, ny) in goal and _box_sum(s_foreign, nx, ny, w, w):
                continue
            ng = g + 1 + (turn if nd != d else 0)
            nst = (nx, ny, nd, 1 if nd != d else min(k + 1, w))
            if ng < best.get(nst, 1e18):
                best[nst] = ng
                came[nst] = st
                heapq.heappush(openq, (ng + abs(nx - tx) + abs(ny - ty), ng, nst))
    if found is None:
        return None
    far_ = {"way": 2.0}.get(tag, 3.0)
    if best[found] > far_ * (abs(a["cx"] - b["cx"]) + abs(a["cy"] - b["cy"])) + 40:
        return None
    path = []
    st = found
    while True:
        c = came[st]
        if c[0] == "start":
            path = c[1] + path
            break
        path.insert(0, (st[0], st[1]))
        st = c
    path.append((found[0], found[1]))
    end_cells, end_side = goal[(found[0], found[1])]
    path += list(reversed(end_cells))
    return _carve_way(a, b, w, path, tag)


def _carve_way(a, b, w, path, tag):
    rid = new_region()
    for (x, y) in path:
        sl = (slice(y, y + w), slice(x, x + w))
        fresh = ~floor[sl]
        owner[sl][fresh] = rid
        floor[sl] = True
    rec = {"id": rid, "a": a["id"], "b": b["id"], "w": w, "path": [list(p) for p in path], "tag": tag}
    corridors.append(rec)
    return rec


def straight_runs(rec):
    """The straight pieces of a corridor's centre path: (axis, fixed, lo, hi)."""
    w = rec["w"]
    pts = rec["path"]
    out = []
    i = 0
    while i < len(pts) - 1:
        j = i
        dx, dy = pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]
        while j < len(pts) - 1 and (pts[j + 1][0] - pts[j][0], pts[j + 1][1] - pts[j][1]) == (dx, dy):
            j += 1
        if dx == 0:
            out.append(("v", pts[i][0], min(pts[i][1], pts[j][1]), max(pts[i][1], pts[j][1]) + w))
        else:
            out.append(("h", pts[i][1], min(pts[i][0], pts[j][0]), max(pts[i][0], pts[j][0]) + w))
        i = j
    return out


def dist(a, b):
    return math.hypot(a["cx"] - b["cx"], a["cy"] - b["cy"])


def join(nodes, widths=(4, 6, 6), loops=0.25, box=None):
    """Every room of a wing joined - nearest first - and a few loops."""
    if len(nodes) < 2:
        return
    inside = [nodes[0]]
    rest = list(nodes[1:])
    while rest:
        pairs = sorted(((dist(a, b), a, b) for a in inside for b in rest), key=lambda t: t[0])
        for _, a, b in pairs:
            wd = rng.choice(widths)
            if route(a, b, wd, box=box) or (wd > 4 and route(a, b, 4, box=box)):
                inside.append(b)
                rest.remove(b)
                break
        else:
            print("  could not join", [r["id"] for r in rest])
            break
    for a in nodes:
        if rng.random() < loops:
            for b in sorted((b for b in nodes if b is not a), key=lambda b: dist(a, b))[1:3]:
                if not any({c["a"], c["b"]} == {a["id"], b["id"]} for c in corridors):
                    if route(a, b, rng.choice(widths), box=box):
                        break


def carve(x, y, w, h, wing, kind, shape="rect"):
    """A room exactly here (the hub, the halls, the rings): no searching."""
    m = np.ones((h, w), bool)
    return place(m, x, y, wing, kind, shape)




# =============================================================================
# THE PLAN
# =============================================================================
WING = {  # wing: (tier, box)
    "courts": (1, (3, 24, 84, 244)),
    "chasm": (2, (96, 3, 238, 120)),
    "caverns": (3, (256, 3, 382, 126)),
    "fortress": (4, (148, 182, 292, 319)),
    "descent": (5, (296, 132, 383, 319)),
    "crypt": (0, (3, 250, 142, 319)),
}
wings = {k: [] for k in WING}
DOOR_W = 6      # a crypt door's corridor: pillar, door, pillar


# THE CROSSROADS: a big hall, you arrive in its middle
hub = place(np.ones((34, 50), bool), 90, 132, "hub", "hub", "rect")

# ---- the places that do not move: each wing's way in, the rift, the rings
cx0, cy0, cx1, cy1 = WING["chasm"][1]
HALL_X, HALL_W = cx0 + 8, (cx1 - cx0) - 16
north_hall = carve(HALL_X, 46, HALL_W, 12, "chasm", "bank")
RIFT_TOP = north_hall["y"] + north_hall["h"]          # first cliff row
RIFT_ROWS = 9                                         # 2 of cliff, 7 of dark
south_hall = carve(HALL_X, RIFT_TOP + RIFT_ROWS, HALL_W, 12, "chasm", "bank")
reserved[RIFT_TOP:RIFT_TOP + RIFT_ROWS, HALL_X:HALL_X + HALL_W] = True
chasm_open[RIFT_TOP:RIFT_TOP + RIFT_ROWS, HALL_X:HALL_X + HALL_W] = True
bridges = []
for k in range(3):
    bx = HALL_X + int(HALL_W * (k + 1) / 4) - 2 + rng.randint(-8, 8)
    bridges.append(bx)
    floor[RIFT_TOP:RIFT_TOP + RIFT_ROWS, bx:bx + 4] = True
    owner[RIFT_TOP:RIFT_TOP + RIFT_ROWS, bx:bx + 4] = north_hall["id"]
    reserved[RIFT_TOP:RIFT_TOP + RIFT_ROWS, bx:bx + 4] = False
wings["chasm"] += [north_hall, south_hall]

courts_hall = carve(48, 134, 24, 20, "courts", "room", "hall")
wings["courts"].append(courts_hall)
caverns_gate = carve(262, 104, 24, 18, "caverns", "room")
wings["caverns"].append(caverns_gate)

fx0, fy0, fx1, fy1 = WING["fortress"][1]
gatehouse = carve(fx0 + 2, fy0 + 26, 18, 22, "fortress", "gatehouse")
wings["fortress"].append(gatehouse)

dx0, dy0, dx1, dy1 = WING["descent"][1]


def ring(x, y, w, h, t, kind):
    m = np.ones((h, w), bool)
    m[t:h - t, t:w - t] = False
    return place(m, x, y, "descent", kind, "ring")


outer = ring(dx0 + 3, dy0 + 4, 82, 180, 9, "outer ring")
inner = ring(dx0 + 22, dy0 + 25, 44, 138, 8, "inner ring")
heart = carve(dx0 + 37, dy0 + 82, 14, 24, "descent", "heart")
wings["descent"] += [outer, inner, heart]

kx0, ky0, kx1, ky1 = WING["crypt"][1]
crypt_grid = {}
kcw, kch = (kx1 - kx0 - 4) // 4, (ky1 - ky0 - 2) // 2


def crypt_room(i, j):
    for _ in range(80):
        w, h = rng.randint(kcw - 14, kcw - 9), rng.randint(kch - 14, kch - 10)
        x = kx0 + 2 + i * kcw + (kcw - w) // 2
        y = ky0 + 1 + j * kch + (kch - h) // 2
        sh = rng.choice(["rect", "L", "plus", "ring", "rect"])
        m = SHAPES[sh](w, h)
        if m is not None and free_box(x, y, w, h, gap=8) and wallable(m):
            crypt_grid[(i, j)] = place(m, x, y, "crypt", "crypt", sh)
            return


crypt_room(2, 0)       # the crypt's door room, under the hub
wings["crypt"] += list(crypt_grid.values())
rest = place(shape_rect(20, 16), 58, 196, "rest", "rest", "rect")

# =============================================================================
# THE HUB'S WAYS OUT, FIRST - the doors on the ones that leave up or down
# =============================================================================


def entry(name, target, sides_a, sides_b=None, w=DOOR_W, door=True, door_end="a"):
    rec = None
    for stub in ((16, 12, 10) if door else (6,)):
        if door_end == "a":
            rec = route(hub, target, w, sides_a=sides_a, sides_b=sides_b, stub=stub, turn=20)
        else:
            rec = route(hub, target, w, sides_a=sides_a, sides_b=sides_b, stub=6, stub_b=stub, turn=20)
        if rec:
            break
    if not rec:
        print("  no way into", name)
        return None
    rec["tag"] = "entry:" + name
    rec["door"] = door
    rec["door_end"] = door_end
    return rec


entry("chasm", south_hall, "N", "S")
entry("caverns", caverns_gate, "E", "S", door_end="b")
entry("fortress", gatehouse, "S", "N")
entry("crypt", crypt_grid.get((2, 0)), "S", "N")
entry("courts", courts_hall, "W", "E", w=8, door=False)
entry("descent", outer, "E", "W", w=8, door=False)
if not route(hub, rest, 6, sides_a="SW", sides_b="NE", turn=30):
    print("  no way to the rest room")

# =============================================================================
# THE ROOMS ROUND THEM
# =============================================================================
fill("chasm", (cx0, cy0, cx1, north_hall["y"] - 1), 6, ["rect", "L", "octa", "plus"], [3, 2, 2, 1],
     wr=(16, 26), hr=(14, 22))
fill("chasm", (cx0, south_hall["y"] + 12, cx1, cy1), 5, ["rect", "L", "octa"], [3, 2, 1],
     wr=(16, 26), hr=(12, 18))
arena = add_room("caverns", WING["caverns"][1], ["octa"], [1], "arena", wr=(38, 40), hr=(38, 40), square=True)
if arena:
    wings["caverns"].append(arena)
fill("caverns", WING["caverns"][1], 9, ["cavern", "ring", "octa", "cavern"], [3, 1, 1, 2],
     wr=(18, 28), hr=(16, 24))
grid = {}
cols, rows_ = 4, 3
cw, ch = (fx1 - fx0 - 34) // cols, (fy1 - fy0 - 4) // rows_
for i in range(cols):
    for j in range(rows_):
        for _ in range(80):
            w, h = rng.randint(cw - 14, cw - 10), rng.randint(ch - 15, ch - 11)
            x = fx0 + 32 + i * cw + (cw - w) // 2
            y = fy0 + 2 + j * ch + (ch - h) // 2
            sh = rng.choice(["rect", "rect", "hall", "octa"])
            if sh == "hall" and (w < 26 or h < 20):
                sh = "rect"
            m = SHAPES[sh](w, h)
            if m is not None and free_box(x, y, w, h, gap=8) and wallable(m):
                grid[(i, j)] = place(m, x, y, "fortress", "room", sh)
                break
wings["fortress"] += list(grid.values())
for i in range(4):
    for j in range(2):
        if (i, j) not in crypt_grid:
            crypt_room(i, j)
            if (i, j) in crypt_grid:
                wings["crypt"].append(crypt_grid[(i, j)])
fill("courts", WING["courts"][1], 11, ["rect", "hall", "octa", "plus", "L"], [3, 3, 2, 1, 1],
     wr=(20, 30), hr=(18, 26))
print("rooms:", {k: len(v) for k, v in wings.items()})

# =============================================================================
# EACH WING JOINED INSIDE ITSELF
# =============================================================================
join(list(wings["courts"]), widths=(6, 8, 8), box=WING["courts"][1])
join([north_hall] + [r for r in wings["chasm"] if r["y"] < north_hall["y"]], widths=(4, 6, 6),
     box=WING["chasm"][1])
join([south_hall] + [r for r in wings["chasm"] if r["y"] > south_hall["y"]], widths=(4, 6, 6),
     box=WING["chasm"][1])
join(list(wings["caverns"]), widths=(4, 6, 6, 8), box=WING["caverns"][1])
for (i, j), r in crypt_grid.items():
    for (di, dj) in ((1, 0), (0, 1)):
        o = crypt_grid.get((i + di, j + dj))
        if o and not route(r, o, 4, sides_a="E" if di else "S", sides_b="W" if di else "N", turn=40,
                           box=WING["crypt"][1]):
            route(r, o, 4, box=WING["crypt"][1])
for (i, j), r in grid.items():
    for (di, dj) in ((1, 0), (0, 1)):
        o = grid.get((i + di, j + dj))
        if o:
            route(r, o, 4, sides_a="E" if di else "S", sides_b="W" if di else "N", turn=40)
west = [grid[k] for k in sorted(grid) if k[0] == 0]
if west:
    route(gatehouse, min(west, key=lambda r: abs(r["cy"] - gatehouse["cy"])), 6, sides_a="E", sides_b="W")


def passage(a, b, x, y0, y1, kind):
    rid = new_region()
    floor[y0:y1, x:x + DOOR_W] = True
    owner[y0:y1, x:x + DOOR_W] = rid
    corridors.append({"id": rid, "a": a["id"], "b": b["id"], "w": DOOR_W, "tag": kind, "door": True,
                      "door_end": "a", "path": [[x, yy] for yy in range(y0, y1 - DOOR_W + 1)]})


passage(outer, inner, outer["x"] + 41 - 3, inner["y"] + inner["h"], outer["y"] + outer["h"] - 9, "descent:down")
passage(inner, heart, heart["x"] + 7 - 3, inner["y"] + 8, heart["y"], "descent:heart")
east = [grid[k] for k in sorted(grid) if k[0] == cols - 1]
if east:
    if not route(max(east, key=lambda r: r["cy"]), outer, 6, sides_a="E", sides_b="W"):
        print("  the fortress does not reach the descent")

# shortcuts: a lever in each wing's furthest room opens a gate back to the hub
for name in ("courts", "chasm", "caverns"):
    far = sorted(wings[name], key=lambda r: -dist(r, hub))
    for f in far[:6]:
        bb = (min(f["x"], hub["x"]) - 16, min(f["y"], hub["y"]) - 16, max(f["x"] + f["w"], hub["x"] + hub["w"]) + 16,
              max(f["y"] + f["h"], hub["y"] + hub["h"]) + 16)
        rec = route(f, hub, 4, turn=6, tag="shortcut:" + name, box=bb) or route(f, hub, 4, turn=6,
                                                                                tag="shortcut:" + name)
        if rec:
            rec["lever_room"] = f["id"]
            break
    else:
        print("  no shortcut for", name)

# anything left on its own joins its nearest neighbour that is joined
for _ in range(10):
    lab, n = label(floor)
    home = lab[hub["cy"], hub["cx"]]
    lost = [r for r in rooms if lab[r["cy"], r["cx"]] != home]
    if not lost:
        break
    a = lost[0]
    found = sorted((r for r in rooms if lab[r["cy"], r["cx"]] == home), key=lambda r: dist(r, a))
    for b in found[:8]:
        if route(a, b, 4):
            break
    else:
        print("  stranded:", a["id"], a["wing"])
        break
lab, n = label(floor)
print("corridors:", len(corridors), "floor pieces:", n)

# =============================================================================
# THE WALLS - every loop of the floor solved, the doors' columns held apart
# =============================================================================
import time
t0 = time.time()
fl = floor.tolist()
all_loops = walls.loops(fl)


def edge_open(e):
    if e["o"] == "N":
        rock = chasm_open[e["t"] - 1, e["a"]:e["b"]]
    elif e["o"] == "S":
        rock = chasm_open[e["t"], e["a"]:e["b"]]
    elif e["o"] == "W":
        rock = chasm_open[e["a"]:e["b"], e["t"] - 1]
    else:
        rock = chasm_open[e["a"]:e["b"], e["t"]]
    if rock.any() and not rock.all():
        raise SystemExit("an edge half on the rift: %s" % e)
    return bool(rock.all())


for lp in all_loops:
    for e in lp:
        if edge_open(e):
            e["open"] = True


def find_edge(o, t, ylo, yhi):
    for li, lp in enumerate(all_loops):
        for ei, e in enumerate(lp):
            if e["o"] == o and e["t"] == t and e["a"] <= ylo and e["b"] >= yhi:
                return li, ei
    return None


# a door's corridor: its two columns 86 px apart - pillar, door, pillar
door_plans = []
for c in corridors:
    if not c.get("door"):
        continue
    w = c["w"]
    if c["tag"].startswith("descent"):
        run = c["path"]
    elif c.get("door_end") == "b":
        run = c["path"][-10:][::-1]   # the far room's stub, from the room out
    else:
        run = c["path"][:10]       # the hub's stub
    x0 = run[0][0]
    ys = [p[1] for p in run]
    # the rows both its sides run straight: not the far brush, where it turns
    ylo, yhi = min(ys) + w, max(ys) + w
    if not c["tag"].startswith("descent") and run[1][1] > run[0][1]:
        ylo, yhi = min(ys), max(ys)
    left = find_edge("W", x0, ylo, yhi)
    right = find_edge("E", x0 + w, ylo, yhi)
    if not left or not right:
        print("  no columns for the door of", c["tag"])
        continue
    door_plans.append({"corridor": c, "left": left, "right": right, "ylo": ylo, "yhi": yhi,
                       "near_hub": yhi if run[1][1] < run[0][1] else ylo})

solved = []
failed = []
for li, lp in enumerate(all_loops):
    try:
        solved.append(walls.solve(lp))
    except ValueError as err:
        solved.append(None)
        failed.append(str(err))
        for e, lo, hi, lens in walls.diagnose(lp):
            print("   cannot wall", e, "between", lo["o"], lo["t"], "and", hi["o"], hi["t"], "lengths", lens[0], "..", lens[-1])

def solve_loop(li):
    try:
        solved[li] = walls.solve(all_loops[li])
    except ValueError as err:
        solved[li] = None
        print("  ", err)


def near_end(d, li, ei):
    """The neighbour of column ei at the door's end of the corridor."""
    lp = all_loops[li]
    n = len(lp)
    a_, b_ = lp[(ei - 1) % n], lp[(ei + 1) % n]
    row = d["near_hub"] if not d["corridor"]["tag"].startswith("descent") else d["ylo"]
    return (ei - 1) % n if abs(a_["t"] - row) <= abs(b_["t"] - row) else (ei + 1) % n


def place_doors():
    cuts = {}
    doors_out = []
    missed = []
    for d in door_plans:
        door = plan_door(d)
        if door is None:
            missed.append(d)
            continue
        (ll, le), (rl, re_) = d["left"], d["right"]
        G = door["y"]
        cuts.setdefault(ll, {})[le] = (G - 30, G)
        cuts.setdefault(rl, {})[re_] = (G - 30, G)
        doors_out.append(door)
    return cuts, doors_out, missed


def plan_door(d):
    (ll, le), (rl, re_) = d["left"], d["right"]
    if solved[ll] is None or solved[rl] is None:
        return None
    s1, t1 = walls.spans(all_loops[ll], solved[ll])[le]
    s2, t2 = walls.spans(all_loops[rl], solved[rl])[re_]
    # anywhere both columns run, nearest the hub (or the middle of a passage)
    mid = d["near_hub"] * TILE if not d["corridor"]["tag"].startswith("descent") else (s1 + t1) / 2.0
    best = None
    for G in range(int(max(s1, s2)) + 30, int(min(t1, t2)) + 1):
        # a column above and below it on both sides: never at the corridor's
        # mouth, where its pillars would meet the room's own wall
        ok = all(int(round(G - 30 - a)) >= 35 and int(round(b - G)) >= 35
                 and walls.SIDE_OK[int(round(G - 30 - a))] and walls.SIDE_OK[int(round(b - G))]
                 for (a, b) in ((s1, t1), (s2, t2)))
        if ok and (best is None or abs(G - mid) < abs(best - mid)):
            best = G
    if best is None:
        return None
    G = best
    Pw, Pe = solved[ll][le], solved[rl][re_]
    # pillar, run, door (78), run, pillar: each pillar may sit up to 4 px off
    # its column (17 wide over 9, it still covers it), so the gap between
    # them is 78 plus whole runs exactly
    Wc = Pe - Pw
    fit = None
    for r in range(0, 200):
        if walls.BACK_OK[r] and abs(86 + r - Wc) <= 8:
            fit = r
            break
    if fit is None:
        return None
    slide = 86 + fit - Wc            # how much further apart the pillars stand
    dl = -math.floor(slide / 2.0)
    dr = slide + dl
    lx, rx = Pw - 4.5 + dl, Pe + 4.5 + dr
    seq = walls.back_run(fit) if fit else []
    r1 = sum(seq[:len(seq) // 2])
    x = lx + 8.5
    pieces_ = [["pillar", lx, G], ["pillar", rx, G]]
    for wd in seq[:len(seq) // 2]:
        pieces_.append([walls.RUN[wd], x + wd / 2.0, G])
        x += wd
    door_x = x + 39
    x += 78
    for wd in seq[len(seq) // 2:]:
        pieces_.append([walls.RUN[wd], x + wd / 2.0, G])
        x += wd
    if abs(x - (rx - 8.5)) > 0.01:
        return None
    return {"name": "door_" + d["corridor"]["tag"].replace(":", "_"), "x": door_x, "y": G,
            "pieces": pieces_, "span": [Pw, Pe]}


cuts, doors_out, missed = place_doors()
if missed:
    # the columns' ends at the door's end held level, and those loops again
    again = set()
    for d in missed:
        for (li, ei) in (d["left"], d["right"]):
            ni = near_end(d, li, ei)
            e = all_loops[li][ni]
            e["fix"] = e["t"] * TILE
            again.add(li)
    for li in again:
        solve_loop(li)
    cuts, doors_out, missed = place_doors()
for d in missed:
    print("  no room for the door of", d["corridor"]["tag"])

wall_pieces = []
for li, lp in enumerate(all_loops):
    if solved[li] is not None:
        wall_pieces += walls.pieces(lp, solved[li], cuts.get(li))
for d in doors_out:
    wall_pieces += d["pieces"]
print("loops:", len(all_loops), "pieces:", len(wall_pieces), "doors:", len(doors_out), "failed:", len(failed),
      "in %.1fs" % (time.time() - t0))

# =============================================================================
# THE WALKABLE FLOOR, FOR NAVIGATION: each loop at its walls' faces
# =============================================================================
outlines = []
for li, lp in enumerate(all_loops):
    P = solved[li]
    if P is None:
        continue
    n = len(lp)
    pts = []
    for i in range(n):
        e, f = lp[i], lp[(i + 1) % n]
        if e["o"] in ("N", "S"):
            pts.append([P[(i + 1) % n], P[i]])
        else:
            pts.append([P[i], P[(i + 1) % n]])
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n)) / 2.0
    outlines.append({"points": pts, "hole": area < 0})
obstructions = []
for d in doors_out:
    obstructions.append([[d["span"][0], d["y"] - 22], [d["span"][1], d["y"] - 22], [d["span"][1], d["y"]],
                         [d["span"][0], d["y"]]])
for (x, y) in pillars:
    obstructions.append([[x - 9, y - 13], [x + 9, y - 13], [x + 9, y + 1], [x - 9, y + 1]])
print("outlines:", len(outlines), "holes:", sum(o["hole"] for o in outlines))

# Where a monster or a prop may stand: the walkable floor at 4 px, the
# pillars out, 20 px in from every wall's face.
from PIL import Image as _Im, ImageDraw as _Dr
from scipy.ndimage import binary_erosion as _erode
SCALE = 4
_mask = _Im.new("L", (TW * TILE // SCALE, TH * TILE // SCALE), 0)
_md = _Dr.Draw(_mask)
for o in outlines:
    if not o["hole"]:
        _md.polygon([(p_[0] / SCALE, p_[1] / SCALE) for p_ in o["points"]], fill=1)
for o in outlines:
    if o["hole"]:
        _md.polygon([(p_[0] / SCALE, p_[1] / SCALE) for p_ in o["points"]], fill=0)
for ob in obstructions:
    _md.polygon([(p_[0] / SCALE, p_[1] / SCALE) for p_ in ob], fill=0)
walkable_px = np.array(_mask) > 0
safe_px = _erode(walkable_px, iterations=5)


def safe_at(x, y):
    """Is (x, y) px at least 20 px inside the walkable floor?"""
    gx, gy = int(x // SCALE), int(y // SCALE)
    return 0 <= gx < safe_px.shape[1] and 0 <= gy < safe_px.shape[0] and bool(safe_px[gy, gx])


# =============================================================================
# THE SHORTCUTS' GATES AND LEVERS
# =============================================================================
gates_out = []
for c in corridors:
    if not c["tag"].startswith("shortcut"):
        continue
    w, path = c["w"], c["path"]
    gx, gy = path[-4]
    vertical = path[-1][0] == path[-2][0]
    if vertical:
        spikes = [[gx * TILE + 16 + 32 * k, gy * TILE + w * TILE / 2] for k in range(w // 2)]
    else:
        spikes = [[gx * TILE + w * TILE / 2, gy * TILE + 16 + 32 * k] for k in range(w // 2)]
    # the lever: in the far room, beside the way out, a cell inside
    f = room_at(c["lever_room"])
    (bx, by), (nx, ny) = path[0], path[1]
    if nx == bx:     # left the room up or down
        row = by + w if ny < by else by - 1
        spots = [(bx - 2, row), (bx + w + 1, row)]
    else:
        col = bx + w if nx < bx else bx - 1
        spots = [(col, by - 2), (col, by + w + 1)]
    lever = None
    for (lx, ly) in spots:
        if 0 <= lx < TW and 0 <= ly < TH and owner[ly, lx] == f["id"]:
            lever = [lx * TILE + 8, ly * TILE + 14]
            break
    if lever is None:
        print("  no wall for the lever of", c["tag"])
        continue
    gates_out.append({"name": c["tag"].replace(":", "_"), "spikes": spikes, "lever": lever, "room": f["id"]})
print("gates:", len(gates_out))

# =============================================================================
# THE MONSTERS - one land a room, packs well apart
# =============================================================================
from scipy.ndimage import binary_erosion
LANDS = {1: ["light", "wind"], 2: ["water", "ice"], 3: ["earth"], 4: ["fire"], 5: ["dark"]}
RECIPES = {
    "light": ["Splitters", "Nest", "Coven", "Hunters", "Swarm"], "wind": ["Splitters", "Nest", "Coven", "Hunters", "Swarm"],
    "water": ["Splitters", "Nest", "Coven", "Hunters", "Swarm"], "ice": ["Splitters", "Nest", "Coven", "Hunters", "Swarm"],
    "earth": ["Patrol", "Splitters", "Nest", "Coven", "Hunters"],
    "fire": ["Coven", "Swarm", "Elite", "Coven"], "dark": ["Splitters", "Nest", "Coven", "Hunters", "Swarm"],
}
MAGE = {"earth": "bushmage"}
SNIPER = {"fire": None}


def scenes(land, kind):
    """The monsters a pack is made of, as scene names."""
    if land == "plain":
        return {"Patrol": ["skeletonsoldier"] * 4, "Warband": ["skeletonsoldier"] * 5,
                "Elite": ["skeletonelite", "skeletonsoldier", "skeletonsoldier"]}[kind]
    if kind == "Sparks":
        return ["electricsprite", "electricsprite", "bushsniper"]
    if kind == "Ooze":
        return ["poisonslime"]
    sprite = "firesprite" if land == "fire" else land + "sprite"
    fsprite = "firesprite" if land == "fire" else land + "firesprite"
    mage = MAGE.get(land, land + "bushmage")
    sniper = SNIPER.get(land, land + "bushsniper")
    large, small = land + "slimelarge", land + "slime"
    return {
        "Splitters": [large, small, small],
        "Nest": [sniper, sniper, sprite],
        "Coven": [mage, fsprite, fsprite],
        "Hunters": [sprite, sprite, fsprite],
        "Swarm": [sprite, sprite, sprite] if land != "fire" else ["firesprite"] * 3,
        "Brood": [large, large, small, small, small],
        "Champion": [mage, mage, large, large, sniper] if land not in ("fire",) else [mage, mage, "skeletonelite", fsprite, fsprite],
        "Patrol": ["skeletonsoldier", "skeletonsoldier", "skeletonsoldier", sniper],
        "Elite": ["skeletonelite", fsprite, fsprite],
    }[kind]


TIER_OF = {name: t for name, (t, _) in WING.items()}
hubx, huby = hub["cx"], hub["cy"]
hx, hy = heart["cx"], heart["cy"]
packs = []
monsters = []
taken = []
turn, rturn = {}, {}
odd_turn = 0
crypt_far = max(wings["crypt"], key=lambda r: dist(r, hub)) if wings["crypt"] else None


def spots_in(rid, n, spacing=10):
    m = owner == rid
    m = binary_erosion(m, iterations=3)
    ys, xs = np.nonzero(m)
    order = list(range(len(xs)))
    rng.shuffle(order)
    out = []
    for k in order:
        x, y = int(xs[k]), int(ys[k])
        if math.hypot(x - hubx, y - huby) < SAFE or math.hypot(x - hx, y - hy) < 22:
            continue
        if any(math.hypot(x - a, y - b) < spacing for (a, b) in taken + out):
            continue
        out.append((x, y))
        if len(out) >= n:
            break
    return out


def add_pack(room, land, kind, at):
    names = scenes(land, kind)
    x, y = at
    pack = {"room": room["id"], "wing": room["wing"], "land": land, "kind": kind, "x": x, "y": y, "n": len(names)}
    packs.append(pack)
    taken.append((x, y))
    ring = [(0, 0), (-28, -18), (28, -18), (-28, 20), (28, 20), (0, 36), (0, -36), (-40, 0), (40, 0),
            (-24, 40), (24, 40), (-24, -40), (24, -40)]
    used = []
    for nm in names:
        for ox, oy in ring:
            mx, my = x * TILE + 8 + ox, y * TILE + 8 + oy
            if (ox, oy) not in used and safe_at(mx, my - 3):
                used.append((ox, oy))
                monsters.append({"scene": nm, "x": mx, "y": my, "leash": 250, "pack": len(packs) - 1, "land": land})
                break


for r in rooms:
    if r["kind"] in ("hub", "rest", "heart", "gatehouse"):
        continue
    if r["wing"] == "crypt":
        rec = "Elite" if r is crypt_far else ("Warband" if r["cells"] > 420 else "Patrol")
        for at in spots_in(r["id"], 2 if r["cells"] > 520 else 1):
            add_pack(r, "plain", rec, at)
            rec = "Patrol"
        continue
    tier = TIER_OF[r["wing"]]
    if r["kind"] in ("outer ring", "inner ring"):
        for i, at in enumerate(spots_in(r["id"], 14 if r["kind"] == "outer ring" else 8, spacing=22)):
            add_pack(r, "dark", ["Hunters", "Nest", "Swarm", "Coven", "Splitters"][i % 5], at)
        continue
    if tier == 2 and odd_turn < 4 and r["cells"] < 380 and r["kind"] == "room":
        kind = ["Sparks", "Ooze"][odd_turn % 2]
        for at in spots_in(r["id"], 1):
            add_pack(r, "electric" if kind == "Sparks" else "poison", kind, at)
        odd_turn += 1
        continue
    lands = LANDS[tier]
    land = lands[turn.get(tier, 0) % len(lands)]
    turn[tier] = turn.get(tier, 0) + 1
    area = r["cells"]
    count = 3 if r["kind"] == "arena" else (1 if area < 420 else (2 if area < 800 else (3 if area < 1200 else 4)))
    if r["kind"] == "bank":
        count = 4
    for i, at in enumerate(spots_in(r["id"], count)):
        if r["kind"] == "arena" and i == 0:
            rec = "Champion"
        elif area >= 800 and i == 0 and land != "fire":
            rec = "Brood"
        else:
            j = rturn.get(land, 0)
            rturn[land] = j + 1
            rec = RECIPES[land][j % len(RECIPES[land])]
        add_pack(r, land, rec, at)
print("packs:", len(packs), "monsters:", len(monsters),
      {w_: sum(1 for m_ in monsters if packs[m_["pack"]]["wing"] == w_) for w_ in WING})

# =============================================================================
# WHERE YOU ARRIVE AND LEAVE, AND WHAT STANDS IN THE ROOMS
# =============================================================================
arrival = [hub["cx"] * TILE + 8, hub["cy"] * TILE + 8]
ladder = [heart["cx"] * TILE + 8, heart["cy"] * TILE + 8]
LIGHTS = 38
props = []
mouth_cells = np.zeros_like(floor)
for c in corridors:
    for (x, y) in c["path"][:1] + c["path"][-1:]:
        mouth_cells[max(0, y - 4):y + c["w"] + 4, max(0, x - 4):x + c["w"] + 4] = True
busy = [(m_["x"] / TILE, m_["y"] / TILE) for m_ in monsters] + [(arrival[0] / TILE, arrival[1] / TILE)]
for g_ in gates_out:
    busy.append((g_["lever"][0] / TILE, g_["lever"][1] / TILE))
DECOR = {
    "crypt": ["gravestone", "skullpile", "bones", "ribcage", "skullbones", "cage", "skullpole", "urn", "rubble2"],
    "default": ["skullpile", "bones", "ribcage", "skullbones", "skullsmall", "rockcluster1", "rockcluster3",
                "rubble1", "rubble3", "crate", "cratestack", "pot", "potpair", "urn", "bonefragment"],
}


def near_back_wall(rid):
    """Cells in a room's top row, under its back wall: where a candelabra stands."""
    m = owner == rid
    out = []
    ys, xs = np.nonzero(m)
    for x, y in zip(xs, ys):
        if y > 0 and not floor[y - 1, x] and not mouth_cells[y, x] and 2 < x < TW - 3:
            if m[y, x - 2:x + 3].all():
                out.append((int(x), int(y)))
    return out


light_rooms = [hub, rest] + [r for r in rooms if r["kind"] in ("arena", "heart", "gatehouse")]
light_rooms += sorted((r for r in rooms if r not in light_rooms and r["kind"] not in ("outer ring", "inner ring")),
                      key=lambda r: -r["cells"])
lights = 0
for r in light_rooms:
    want = 4 if r is hub else (2 if r["kind"] in ("arena", "rest", "heart") else 1)
    cand = near_back_wall(r["id"])
    rng.shuffle(cand)
    placed = []
    for (x, y) in cand:
        if lights >= LIGHTS or len(placed) >= want:
            break
        if all(abs(x - a) > 8 for a, _ in placed):
            # just under the back wall's foot, wherever its line was laid
            px_ = x * TILE + 8
            col = walkable_px[:, px_ // SCALE]
            foot = None
            for yy in range(y * TILE, y * TILE + 44, SCALE):
                if col[yy // SCALE]:
                    foot = yy
                    break
            if foot is None or not safe_at(px_, foot + 22):
                continue
            props.append(["candelabra", px_, foot + 10])
            placed.append((x, y))
            lights += 1
for r in rooms:
    if r["kind"] in ("hub", "rest"):
        continue
    m = owner == r["id"]
    inner_ = binary_erosion(m, iterations=1)
    edge = inner_ & ~binary_erosion(m, iterations=3) & ~mouth_cells
    ys, xs = np.nonzero(edge)
    order = list(range(len(xs)))
    rng.shuffle(order)
    want = max(2, min(7, r["cells"] // 180))
    kinds = DECOR["crypt"] if r["wing"] == "crypt" else DECOR["default"]
    got = []
    for k in order:
        x, y = int(xs[k]), int(ys[k])
        if any(math.hypot(x - a, y - b) < 5 for a, b in got) or any(math.hypot(x - a, y - b) < 4 for a, b in busy):
            continue
        if not safe_at(x * TILE + 8, y * TILE + 12):
            continue
        props.append([rng.choice(kinds), x * TILE + 8, y * TILE + 12])
        got.append((x, y))
        if len(got) >= want:
            break
for (x, y) in pillars:
    props.append(["pillar", x, y])
print("props:", len(props), "lights:", lights)

# =============================================================================
# THE RIFT'S TILES - the north bank's cliff, the south bank's rim, the bridges
# =============================================================================
tiles = {}
r1, r2 = RIFT_TOP, RIFT_TOP + 1
rS = RIFT_TOP + RIFT_ROWS
bridge_cols = set()
for bx in bridges:
    bridge_cols |= set(range(bx, bx + 4))
for c in range(HALL_X, HALL_X + HALL_W):
    v = 1 + (c * 7) % 4
    if c in bridge_cols:
        if c - 1 not in bridge_cols:
            tiles[(c, r1)], tiles[(c, r2)] = (12, 0), (12, 1)
            for y in range(r2 + 1, rS):
                tiles[(c, y)] = (0, 1 + (y % 3))
            tiles[(c, rS)] = (12, 6)
        elif c + 1 not in bridge_cols:
            tiles[(c, r1)], tiles[(c, r2)] = (9, 0), (9, 1)
            for y in range(r2 + 1, rS):
                tiles[(c, y)] = (5, 1 + (y % 3))
            tiles[(c, rS)] = (9, 6)
        continue
    end_l, end_r = c == HALL_X, c == HALL_X + HALL_W - 1
    tiles[(c, r1)] = (0, 4) if end_l else ((5, 4) if end_r else (v, 4))
    tiles[(c, r2)] = (0, 5) if end_l else ((5, 5) if end_r else (v, 5))
    for y in range(r2 + 1, rS):
        tiles[(c, y)] = "void"
    tiles[(c, rS)] = (0, 0) if end_l else ((5, 0) if end_r else (v, 0))

# =============================================================================
# THE BUILD FILE
# =============================================================================
os.makedirs(OUT, exist_ok=True)
build = {
    "about": "The Big Field, built by tools/maps/bigfield.py (seed %d). buildbigfield.gd reads this." % SEED,
    "seed": SEED, "tile": TILE, "size": [TW, TH],
    "floor": ["".join("1" if v else "0" for v in row) for row in floor],
    "tiles": [[cx, cy] + ([-1, -1] if at == "void" else list(at)) for (cx, cy), at in sorted(tiles.items())],
    "walls": [[p_[0], round(p_[1], 2), round(p_[2], 2)] for p_ in wall_pieces],
    "doors": doors_out,
    "gates": gates_out,
    "props": [[p_[0], round(p_[1], 2), round(p_[2], 2)] for p_ in props],
    "monsters": monsters,
    "packs": packs,
    "arrival": arrival, "ladder": ladder,
    "nav": {"outlines": outlines, "obstructions": obstructions},
    "rooms": [{k: r[k] for k in ("id", "wing", "kind", "shape", "x", "y", "w", "h", "cx", "cy", "cells")} for r in rooms],
    "corridors": [{k: c[k] for k in ("id", "a", "b", "w", "tag")} for c in corridors],
    "wings": {k: {"tier": t, "box": list(b)} for k, (t, b) in WING.items()},
}


def _clean(o):
    if isinstance(o, dict):
        return {k: _clean(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)):
        return [_clean(v) for v in o]
    if isinstance(o, (np.integer,)):
        return int(o)
    if isinstance(o, (np.floating,)):
        return float(o)
    if isinstance(o, np.bool_):
        return bool(o)
    return o


with open(os.path.join(OUT, "bigfield_build.json"), "w") as fh:
    json.dump(_clean(build), fh, separators=(",", ":"))
print("build file: %.0f KB" % (os.path.getsize(os.path.join(OUT, "bigfield_build.json")) / 1024))
lab, n = label(floor)
print("floor pieces:", n)

no_cut = floor.copy()
for c in corridors:
    if c["tag"].startswith("shortcut"):
        for (x, y) in c["path"][-6:]:
            no_cut[y:y + c["w"], x:x + c["w"]] &= ~(owner[y:y + c["w"], x:x + c["w"]] == c["id"])
summary = {"seed": SEED, "pieces": int(label(floor)[1]), "gated_pieces": int(label(no_cut)[1]), "doors": len(doors_out), "gates": len(gates_out),
           "failed": len(failed), "monsters": len(monsters), "rooms": len(rooms),
           "entries": sum(1 for c in corridors if c["tag"].startswith("entry"))}
print("SUMMARY", json.dumps(summary))
if os.environ.get("PICS", "1") == "0":
    sys.exit(0)

# =============================================================================
# PICTURES
# =============================================================================
from PIL import Image, ImageDraw, ImageFont
import render
COL = {"hub": (120, 200, 120), "rest": (160, 220, 160), "courts": (235, 215, 120), "chasm": (110, 160, 230),
       "caverns": (190, 140, 90), "fortress": (230, 110, 80), "descent": (160, 110, 210), "crypt": (150, 150, 150)}
img = Image.new("RGB", (TW * 3, TH * 3), (20, 20, 24))
px = img.load()
wing_of = {r["id"]: r["wing"] for r in rooms}
for y in range(TH):
    for x in range(TW):
        c = None
        if floor[y, x]:
            o = owner[y, x]
            c = COL.get(wing_of.get(o, ""), (200, 200, 200)) if o in wing_of else (205, 205, 205)
        elif reserved[y, x]:
            c = (60, 30, 30)
        if c:
            for dy in range(3):
                for dx in range(3):
                    px[x * 3 + dx, y * 3 + dy] = c
d = ImageDraw.Draw(img)
for r in rooms:
    d.text((r["cx"] * 3 - 6, r["cy"] * 3 - 5), str(r["id"]), fill=(0, 0, 0))
img.save(os.path.join(OUT, "plan_quick.png"))

MCOL = {"light": (255, 240, 150), "wind": (140, 240, 190), "water": (90, 150, 255), "ice": (170, 230, 255),
        "earth": (200, 140, 70), "fire": (255, 90, 40), "dark": (190, 110, 255), "plain": (230, 230, 230),
        "electric": (255, 255, 0), "poison": (120, 255, 60)}
extra = []
for dd in doors_out:
    extra.append(render.door(dd["x"], dd["y"]))
def dot(x, y, col, r=5):
    def paint(im, ox, oy):
        dr = ImageDraw.Draw(im)
        dr.ellipse((x - ox - r, y - oy - r, x - ox + r, y - oy + r), fill=col + (255,), outline=(0, 0, 0, 255))
    return (y, paint)
for m_ in monsters:
    extra.append(dot(m_["x"], m_["y"], MCOL[m_["land"]]))
for g_ in gates_out:
    for (x, y) in g_["spikes"]:
        def sp(im, ox, oy, x=x, y=y):
            dr = ImageDraw.Draw(im)
            dr.rectangle((x - ox - 16, y - oy - 16, x - ox + 16, y - oy + 16), outline=(255, 60, 60, 255), width=3)
        extra.append((y, sp))
    extra.append(dot(g_["lever"][0], g_["lever"][1], (255, 220, 0), 7))
extra.append(dot(arrival[0], arrival[1], (60, 255, 60), 9))
extra.append(dot(ladder[0], ladder[1], (255, 40, 40), 9))
PROPS = {"candelabra": (255, 200, 80), "pillar": None}
allp = wall_pieces + [p_ for p_ in props if p_[0] == "pillar"]
for p_ in props:
    if p_[0] != "pillar":
        extra.append(dot(p_[1], p_[2], (255, 200, 80) if p_[0] == "candelabra" else (120, 110, 100), 3))
full = render.draw(floor.tolist(), tiles, allp, extra=extra)
full.convert("RGB").resize((TW * 4, TH * 4), Image.LANCZOS).save(os.path.join(OUT, "art_overview.png"))


def crop(name, cx, cy, w=1280, h=720):
    full.crop((int(cx - w // 2), int(cy - h // 2), int(cx + w // 2), int(cy + h // 2))).convert("RGB").save(
        os.path.join(OUT, name))


crop("art_hub.png", arrival[0], arrival[1])
crop("art_chasm.png", (bridges[1] + 2) * 16, RIFT_TOP * 16 + 40)
crop("art_fortress.png", gatehouse["cx"] * 16 + 400, gatehouse["cy"] * 16)
if doors_out:
    crop("art_door.png", doors_out[0]["x"], doors_out[0]["y"])
crop("art_heart.png", ladder[0], ladder[1])
if gates_out:
    crop("art_gate.png", gates_out[0]["spikes"][0][0], gates_out[0]["spikes"][0][1])
print("pictures done")
