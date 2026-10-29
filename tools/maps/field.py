"""The Field (0.94.2): the last map before the boss, built to be walled.

You arrive top left, from the Big Field's ladder; the ladder down to the boss
is bottom right, behind a spike gate with a lever either side. Two routes go
round a solid middle: FIRE over the top and down the right (tier 4), DARK
down the left and along the bottom (tier 5, harder), and both end in the
exit hall, where a skeleton guard stands at the levers. Rooms, corridors,
walls, doors and pictures are made the Big Field's way (bigfield.py, whose
room, corridor and wall code this shares; walls.py; render.py).

    python3 tools/maps/field.py [SEED] [OUT_DIR]       (seed 38 is the map)
    then copy OUT_DIR/field_build.json over tools/maps/field_build.json
    and run buildfield.gd's build_field() (zz/ has a scene for it).

Needs numpy, scipy and Pillow. PICS=0 skips the pictures.
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

SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 38
OUT = sys.argv[2] if len(sys.argv) > 2 else "out"
rng = random.Random(SEED)
TW, TH = 150, 108      # 2400 x 1728 px: about twice the old Field's area
TILE = 16
CLR = 5            # cells of rock kept inside a shape (tidy)
CLR_X, CLR_Y = 3, 4   # rock between two places that do not join
ROOM_GAP = 10      # between rooms, so a corridor can pass
MARGIN = 3         # cells of wall either side of a corridor's mouth
SAFE = 25          # no pack this many cells from where you arrive
NEAR_LADDER = 8    # nor this near the ladder
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
DOOR_W = 6      # a crypt door's corridor: pillar, door, pillar

# where you arrive, the exit hall and the ladder's room, fixed
landing = carve(6, 6, 24, 16, "landing", "landing")
exit_hall = carve(116, 74, 28, 14, "exit", "exit hall")
ladder_room = carve(122, 96, 16, 9, "exit", "ladder")
# THE SOLID MIDDLE: nothing is built or dug through it
MID = (48, 44, 100, 64)
reserved[MID[1]:MID[3], MID[0]:MID[2]] = True

# EACH ROUTE'S ROOMS, a slot each, so both have four and a door has room:
# the fire's three along the top and one round the corner, the dark's two
# down the left and two along the bottom. Shape and size vary in the slot.
SH = ["rect", "L", "octa", "hall", "cavern", "ring", "plus"]
SW = [1, 2, 2, 2, 3, 2, 1]
# (box, the sides its corridors leave by)
SLOTS = {
    "fire": [((44, 4, 70, 30), "WE"), ((84, 4, 110, 30), "WE"), ((124, 4, 146, 30), "WS"),
             ((114, 46, 146, 58), "NS")],
    "dark": [((4, 44, 34, 62), "NS"), ((4, 76, 34, 104), "NE"), ((48, 78, 72, 104), "WE"),
             ((86, 76, 102, 104), "WE")],
}


def has_mouth(mask, side, w=DOOR_W):
    """Room on this side of the shape for a corridor w wide and its margins."""
    edge = {"N": mask[np.nonzero(mask.any(1))[0][0]], "S": mask[np.nonzero(mask.any(1))[0][-1]],
            "W": mask[:, np.nonzero(mask.any(0))[0][0]], "E": mask[:, np.nonzero(mask.any(0))[0][-1]]}[side]
    run = best = 0
    for v in edge:
        run = run + 1 if v else 0
        best = max(best, run)
    return best >= w + 2 * MARGIN + 1


def slot_room(slot, wing):
    (x0, y0, x1, y1), sides = slot
    for _ in range(600):
        sh = rng.choices(SH, SW)[0]
        w = rng.randint(max(14, (x1 - x0) - 10), x1 - x0)
        h = rng.randint(max(12, (y1 - y0) - 8), y1 - y0)
        if sh in ("octa", "plus", "ring"):
            w = h = min(w, h)
        if sh == "hall" and (w < 26 or h < 20):
            sh = "rect"
        x = rng.randint(x0, x1 - w)
        y = rng.randint(y0, y1 - h)
        m = SHAPES[sh](w, h)
        if m is None or not all(has_mouth(m, sd) for sd in sides):
            continue
        if free_box(x, y, w, h, gap=8) and wallable(m):
            room = place(m, x, y, wing, "room", sh)
            room["sides"] = sides
            return room
    print("  no room in", slot)
    return None


fire = [r for r in (slot_room(bx, "fire") for bx in SLOTS["fire"]) if r]
dark = [r for r in (slot_room(bx, "dark") for bx in SLOTS["dark"]) if r]
print("rooms: fire", len(fire), "dark", len(dark))


def way(a, b, w=None, door_end=None, **kw):
    """A corridor from a to b; with door_end, a crypt door at that end."""
    rec = None
    widths = [DOOR_W] if door_end else [w or rng.choice((4, 6, 6)), 4]
    for wd in widths:
        for stub in ((16, 12, 10) if door_end else (6,)):
            if door_end == "b":
                rec = route(a, b, wd, stub=6, stub_b=stub, turn=14, **kw)
            else:
                rec = route(a, b, wd, stub=stub, turn=14, **kw)
            if rec:
                break
        if rec:
            break
    if not rec and door_end:
        return way(a, b, **{k: v for k, v in kw.items() if k != "sides_a" or door_end != "a"})
    if not rec:
        for wd in (4, 6):
            rec = route(a, b, wd, turn=6, tag="long", **kw)
            if rec:
                break
    if not rec:
        print("  no way from", a["kind"], a["id"], "to", b["kind"], b["id"])
        return None
    if door_end:
        rec["door"] = True
        rec["door_end"] = door_end
        rec["tag"] = "door:%d_%d" % (a["id"], b["id"])
    return rec


# THE DARK ROUTE: through a door below the landing, down the left and along
# the bottom into the exit hall
if dark:
    way(landing, dark[0], door_end="a", sides_a="S", sides_b="N")
    for a, b in zip(dark, dark[1:]):
        way(a, b, sides_a=a["sides"][1], sides_b=b["sides"][0])
    way(dark[-1], exit_hall, sides_a="E", sides_b="W")
# THE FIRE ROUTE: east along the top, a door round the corner, a door into
# the exit hall
if fire:
    way(landing, fire[0], sides_a="E", sides_b="W")
    for a, b in zip(fire[:-2], fire[1:-1]):
        way(a, b, sides_a=a["sides"][1], sides_b=b["sides"][0])
    if len(fire) > 1:
        way(fire[-2], fire[-1], door_end="b", sides_a="S", sides_b="N")
    way(fire[-1], exit_hall, door_end="b", sides_a="S", sides_b="N")

# DEAD ENDS: a few small rooms off the routes, where there is room - nothing
# in them but what stands in every room
NOOKS = 3
nooks = []
for _ in range(60):
    if len(nooks) >= NOOKS:
        break
    keep = (floor.copy(), owner.copy(), REGION[0], len(rooms))
    r = add_room("nook", (3, 3, TW - 3, TH - 3), ["rect", "octa", "L", "cavern", "plus"], [2, 2, 2, 2, 1],
                 kind="nook", wr=(12, 18), hr=(10, 14), tries=60, gap=8)
    if r is None:
        continue
    near = sorted(fire + dark, key=lambda q: dist(q, r))[:2]
    if any(route(r, q, 4, turn=10) for q in near if dist(q, r) < 40):
        nooks.append(r)
        r["wing"] = near[0]["wing"]
    else:
        floor[:], owner[:] = keep[0], keep[1]
        REGION[0] = keep[2]
        del rooms[keep[3]:]
print("dead ends:", len(nooks))

# THE GATE: a passage down from the exit hall to the ladder's room
GATE_X = exit_hall["x"] + exit_hall["w"] // 2 - DOOR_W // 2
g_rid = new_region()
gy0, gy1 = exit_hall["y"] + exit_hall["h"], ladder_room["y"]
floor[gy0:gy1, GATE_X:GATE_X + DOOR_W] = True
owner[gy0:gy1, GATE_X:GATE_X + DOOR_W] = g_rid
corridors.append({"id": g_rid, "a": exit_hall["id"], "b": ladder_room["id"], "w": DOOR_W, "tag": "gate",
                  "path": [[GATE_X, yy] for yy in range(gy0, gy1 - DOOR_W + 1)]})

for _ in range(10):
    lab, n = label(floor)
    home = lab[landing["cy"], landing["cx"]]
    lost = [r for r in rooms if lab[r["cy"], r["cx"]] != home]
    if not lost:
        break
    a = lost[0]
    found = sorted((r for r in rooms if lab[r["cy"], r["cx"]] == home and r is not ladder_room), key=lambda r: dist(r, a))
    for b in found[:8]:
        if route(a, b, 4) or route(a, b, 4, turn=6, tag="long"):
            break
    else:
        print("  stranded:", a["id"], a["wing"])
        break
lab, n = label(floor)
home = lab[landing["cy"], landing["cx"]]
lost = [r for r in rooms if lab[r["cy"], r["cx"]] != home]
print("corridors:", len(corridors), "floor pieces:", n, "rooms cut off:", [r["id"] for r in lost])
if os.environ.get("QUICK"):
    from PIL import Image as _QI, ImageDraw as _QD
    os.makedirs(OUT, exist_ok=True)
    q = _QI.new("RGB", (TW * 4, TH * 4), (20, 20, 24))
    qd = _QD.Draw(q)
    for y in range(TH):
        for x in range(TW):
            c = None
            if floor[y, x]:
                o = owner[y, x]
                rr = next((r for r in rooms if r["id"] == o), None)
                c = {"fire": (230, 110, 80), "dark": (160, 110, 210), "landing": (120, 200, 120),
                     "exit": (220, 220, 120)}.get(rr["wing"], (200, 200, 200)) if rr else (205, 205, 205)
            elif reserved[y, x]:
                c = (60, 30, 30)
            if c:
                qd.rectangle((x * 4, y * 4, x * 4 + 3, y * 4 + 3), fill=c)
    for r in rooms:
        qd.text((r["cx"] * 4 - 4, r["cy"] * 4 - 5), str(r["id"]), fill=(0, 0, 0))
    q.save(os.path.join(OUT, "quick.png"))
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

# THE DOORS FIRST (walls.py, e["door"]): each door's row is chosen before the
# walls are solved, and both its columns fit their pieces round it. A row
# that leaves the walls no fit is moved and tried again.
def _solves(lis):
    for li in lis:
        try:
            walls.solve(all_loops[li])
        except ValueError:
            return False
    return True


def door_pieces(d, G):
    """Pillar, run, door (78), run, pillar across the corridor at G."""
    (ll, le), (rl, re_) = d["left"], d["right"]
    Pw, Pe = solved[ll][le], solved[rl][re_]
    # each pillar may sit up to 4 px off its column (17 wide over 9, it
    # still covers it), so the gap between them is 78 plus whole runs exactly
    Wc = Pe - Pw
    fit = None
    for r in range(0, 200):
        if walls.BACK_OK[r] and abs(86 + r - Wc) <= 8:
            fit = r
            break
    if fit is None:
        return None
    slide = 86 + fit - Wc
    dl = -math.floor(slide / 2.0)
    dr = slide + dl
    lx, rx = Pw - 4.5 + dl, Pe + 4.5 + dr
    seq = walls.back_run(fit) if fit else []
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


chosen = []
for d in door_plans:
    (ll, le), (rl, re_) = d["left"], d["right"]
    e1, e2 = all_loops[ll][le], all_loops[rl][re_]
    lo, hi = min(d["ylo"], d["yhi"]) * TILE, max(d["ylo"], d["yhi"]) * TILE
    mid = (lo + hi) / 2.0 + 15
    at = None
    for G in sorted(range(int(lo) - 32, int(hi) + 64, 4), key=lambda g: abs(g - mid)):
        e1["door"] = e2["door"] = (G - 30, G)
        if _solves({ll, rl}):
            at = G
            break
    if at is None:
        e1.pop("door", None)
        e2.pop("door", None)
        print("  no room for the door of", d["corridor"]["tag"])
    else:
        chosen.append((d, at))

solved = []
failed = []
for li, lp in enumerate(all_loops):
    try:
        solved.append(walls.solve(lp))
    except ValueError as err:
        solved.append(None)
        failed.append(str(err))
        for e, lo_, hi_, lens in walls.diagnose(lp):
            print("   cannot wall", e, "lengths", lens[0], "..", lens[-1])
doors_out = []
for d, G in chosen:
    door = door_pieces(d, G)
    if door is None:
        # no door after all: its columns whole again
        (ll, le), (rl, re_) = d["left"], d["right"]
        all_loops[ll][le].pop("door", None)
        all_loops[rl][re_].pop("door", None)
        for li in {ll, rl}:
            solved[li] = walls.solve(all_loops[li])
        print("  the door of", d["corridor"]["tag"], "does not fit across")
    else:
        doors_out.append(door)
cuts = {}
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
# THE BOSS GATE: three spikes across the passage, a lever either side
# =============================================================================
spike_y = (gy0 + gy1) / 2.0 * TILE
gates_out = [{"name": "bossgate",
              "spikes": [[GATE_X * TILE + 16 + 32 * k, spike_y] for k in range(DOOR_W // 2)],
              "lever_out": [(GATE_X - 3) * TILE + 8, (gy0 - 3) * TILE + 8],
              "lever_in": [(GATE_X + DOOR_W + 2) * TILE + 8, gy1 * TILE + 14]}]


# =============================================================================
# THE MONSTERS - one land a room, a pack a room, the guard at the levers
# =============================================================================
from scipy.ndimage import binary_erosion
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

hubx, huby = landing["cx"], landing["cy"]
hx, hy = ladder_room["cx"], ladder_room["cy"]
packs = []
monsters = []
taken = []
def spots_in(rid, n, spacing=10):
    m = owner == rid
    m = binary_erosion(m, iterations=3)
    ys, xs = np.nonzero(m)
    order = list(range(len(xs)))
    rng.shuffle(order)
    out = []
    for k in order:
        x, y = int(xs[k]), int(ys[k])
        if math.hypot(x - hubx, y - huby) < SAFE or math.hypot(x - hx, y - hy) < NEAR_LADDER:
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
                # No leash given: each keeps its own, as the old Field's did
                # (a bush mage's 1,500 - exportgamedata.gd, authored_leash()).
                monsters.append({"scene": nm, "x": mx, "y": my, "pack": len(packs) - 1, "land": land})
                break


FIRE_PACKS = ["Coven", "Elite", "Swarm", "Coven"]
DARK_PACKS = ["Splitters", "Hunters", "Nest", "Coven"]
for route_rooms, land, recipes in ((fire, "fire", FIRE_PACKS), (dark, "dark", DARK_PACKS)):
    for i, r in enumerate(route_rooms):
        for at in spots_in(r["id"], 1):
            add_pack(r, land, recipes[i % len(recipes)], at)
# THE EXIT GUARD, by the outer lever
gx_, gy_ = GATE_X + DOOR_W // 2, gy0 - 5
guard_at = min(spots_in(exit_hall["id"], 20, spacing=1) or [(gx_, gy_)],
               key=lambda p: math.hypot(p[0] - gx_, p[1] - gy_))
add_pack(exit_hall, "plain", "Elite", guard_at)
print("packs:", len(packs), "monsters:", len(monsters))


# =============================================================================
# WHERE YOU ARRIVE AND LEAVE, AND WHAT STANDS IN THE ROOMS
# =============================================================================
arrival = [landing["cx"] * TILE + 8, landing["cy"] * TILE + 8]
ladder = [ladder_room["cx"] * TILE + 8, ladder_room["cy"] * TILE + 8]
LIGHTS = 16
props = []
mouth_cells = np.zeros_like(floor)
for c in corridors:
    for (x, y) in c["path"][:1] + c["path"][-1:]:
        mouth_cells[max(0, y - 4):y + c["w"] + 4, max(0, x - 4):x + c["w"] + 4] = True
busy = [(m_["x"] / TILE, m_["y"] / TILE) for m_ in monsters] + [(arrival[0] / TILE, arrival[1] / TILE),
        (ladder[0] / TILE, ladder[1] / TILE)]
for g_ in gates_out:
    busy += [(g_["lever_out"][0] / TILE, g_["lever_out"][1] / TILE), (g_["lever_in"][0] / TILE, g_["lever_in"][1] / TILE)]
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


light_rooms = [landing, exit_hall, ladder_room] + sorted((r for r in rooms if r["kind"] == "room"),
                                                         key=lambda r: -r["cells"])
lights = 0
for r in light_rooms:
    want = 2 if r in (landing, exit_hall) else 1
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
    if r["kind"] in ("landing", "ladder"):
        continue
    m = owner == r["id"]
    inner_ = binary_erosion(m, iterations=1)
    edge = inner_ & ~binary_erosion(m, iterations=3) & ~mouth_cells
    ys, xs = np.nonzero(edge)
    order = list(range(len(xs)))
    rng.shuffle(order)
    want = max(2, min(7, r["cells"] // 180))
    kinds = DECOR["crypt"] if r is exit_hall else DECOR["default"]
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

tiles = {}


# =============================================================================
# THE BUILD FILE
# =============================================================================
os.makedirs(OUT, exist_ok=True)
build = {
    "about": "The Field, built by tools/maps/field.py (seed %d). buildfield.gd reads this." % SEED,
    "seed": SEED, "tile": TILE, "size": [TW, TH],
    "floor": ["".join("1" if v else "0" for v in row) for row in floor],
    "tiles": [],
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


with open(os.path.join(OUT, "field_build.json"), "w") as fh:
    json.dump(_clean(build), fh, separators=(",", ":"))
lab, n = label(floor)
summary = {"seed": SEED, "pieces": int(n), "doors": len(doors_out), "failed": len(failed),
           "monsters": len(monsters), "packs": len(packs), "rooms": len(rooms), "lost": len(lost)}
print("SUMMARY", json.dumps(summary))
if os.environ.get("PICS", "1") == "0":
    sys.exit(0)

# =============================================================================
# PICTURES
# =============================================================================
from PIL import ImageDraw
import render
MCOL = {"fire": (255, 90, 40), "dark": (190, 110, 255), "plain": (230, 230, 230)}
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
    extra.append(dot(g_["lever_out"][0], g_["lever_out"][1], (255, 220, 0), 7))
    extra.append(dot(g_["lever_in"][0], g_["lever_in"][1], (255, 220, 0), 7))
extra.append(dot(arrival[0], arrival[1], (60, 255, 60), 9))
extra.append(dot(ladder[0], ladder[1], (255, 40, 40), 9))
allp = wall_pieces + [p_ for p_ in props if p_[0] == "pillar"]
for p_ in props:
    if p_[0] != "pillar":
        extra.append(dot(p_[1], p_[2], (255, 200, 80) if p_[0] == "candelabra" else (120, 110, 100), 3))
full = render.draw(floor.tolist(), tiles, allp, extra=extra)
full.convert("RGB").save(os.path.join(OUT, "field_overview.png"))


def crop(name, cx, cy, w=1280, h=720):
    full.crop((int(cx - w // 2), int(cy - h // 2), int(cx + w // 2), int(cy + h // 2))).convert("RGB").save(
        os.path.join(OUT, name))


crop("field_landing.png", arrival[0] + 300, arrival[1] + 150)
crop("field_exit.png", ladder[0], ladder[1] - 250)
print("pictures done")
