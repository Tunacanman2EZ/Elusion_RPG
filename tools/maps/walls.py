"""Crypt walls that fit exactly: every edge of a floor mask walled with the
crypt pieces (scene/crypt/), end to end, nothing over anything.

The floor is a mask of 16 px cells. Every edge between floor and rock gets a
wall, laid the way buildendless.gd lays the Endless's:
  N edge (floor below)  the back wall, its foot on the floor's top line
  S edge (floor above)  the front wall, its face just below the floor
  W edge (floor right)  a side column, 9 px, its right side on the floor
  E edge (floor left)   a side column, its left side on the floor
Pieces only come in a few sizes (runs 101/51/26 and the 17 px pillar; columns
58/36/35), so each wall line may sit a few px off its cell line - where the
floor tile under it is hidden by the wall itself:
  W: x in [T, T+9]    E: x in [T-9, T]    N: y in [T, T+28]    S: y in [T-28, T]
(P, the walkable edge; T, the cell line.) solve() picks each line's P so that
every run and every column comes out as a sum of whole pieces.

Edges against the chasm are "open": no wall, the tiles' rims and cliffs edge
the floor there, and a column meeting one stops on its cell line.

A column a crypt door's wall crosses carries e["door"] = (top, bottom), the
band in px the door's wall takes: solve() then fits the column's two parts
round it, each whole pieces (the Field's doors, field.py). Without it nothing
changes - the Big Field places its doors after solving.
"""
from functools import lru_cache

TILE = 16
RUN = {101: "wallrun4", 51: "wallrun2", 26: "wallrun1", 17: "pillar"}
SIDE = {58: "wallsidetall", 36: "wallsidea", 35: "wallsideb"}
MAXLEN = 8000


def _sums(parts):
    ok = [False] * (MAXLEN + 1)
    ok[0] = True
    for n in range(1, MAXLEN + 1):
        ok[n] = any(n >= p and ok[n - p] for p in parts)
    return ok


def _costs(parts, cost):
    best = [None] * (MAXLEN + 1)
    best[0] = 0.0
    for n in range(1, MAXLEN + 1):
        for p in parts:
            if n >= p and best[n - p] is not None:
                c = best[n - p] + cost[p]
                if best[n] is None or c < best[n]:
                    best[n] = c
    return best


BACK_COST = {101: 1.0, 51: 1.25, 26: 1.5, 17: 2.6}
# A pillar's body is 12 px at its foot, a run's 28: in a front wall a player
# can step into its top 16 px - but not past it. The Endless's front wall has
# them too.
FRONT_COST = {101: 1.0, 51: 1.25, 26: 1.5, 17: 2.6}
SIDE_COST = {58: 1.0, 36: 1.2, 35: 1.2}
BACK_C = _costs(tuple(BACK_COST), BACK_COST)
FRONT_C = _costs(tuple(FRONT_COST), FRONT_COST)
SIDE_C = _costs(tuple(SIDE_COST), SIDE_COST)
BACK_OK = [c is not None for c in BACK_C]


def _locked_costs(parts, cost, locks):
    """Like _costs, but a pillar is only allowed with at least `locks` other
    pieces to stand at the locked ends: a pillar is 30 tall to a run's 28, so
    at the end of a back wall under a column it would poke 2 px into it."""
    INF = None
    # state: (length) -> {(bigs capped at 2, has_pillar): cost}
    best = [dict() for _ in range(MAXLEN + 1)]
    best[0][(0, False)] = 0.0
    for n in range(1, MAXLEN + 1):
        cur = {}
        for p in parts:
            if n < p:
                continue
            for (bigs, pil), c in best[n - p].items():
                key = (min(2, bigs + (0 if p == 17 else 1)), pil or p == 17)
                cc = c + cost[p]
                if key not in cur or cc < cur[key]:
                    cur[key] = cc
        best[n] = cur
    out = [INF] * (MAXLEN + 1)
    for n in range(MAXLEN + 1):
        ok = [c for (bigs, pil), c in best[n].items() if not pil or bigs >= locks]
        anyway = [c for c in best[n].values()]
        # a pillar at a locked end is allowed, but dear: the solver takes any
        # other line it can first
        out[n] = min(ok) if ok else ((min(anyway) + 20.0) if anyway else INF)
    return out


BACK_C_LOCK = {0: BACK_C, 1: _locked_costs(tuple(BACK_COST), BACK_COST, 1),
               2: _locked_costs(tuple(BACK_COST), BACK_COST, 2)}
FRONT_OK = [c is not None for c in FRONT_C]
SIDE_OK = [c is not None for c in SIDE_C]


def _compose(n, parts, cost):
    """The cheapest list of parts adding up to n (None when none does)."""
    best = [None] * (n + 1)
    best[0] = (0.0, [])
    for k in range(1, n + 1):
        for p in parts:
            if k >= p and best[k - p] is not None:
                c = best[k - p][0] + cost[p]
                if best[k] is None or c < best[k][0]:
                    best[k] = (c, best[k - p][1] + [p])
    return None if best[n] is None else best[n][1]


@lru_cache(maxsize=None)
def back_run(n, lock_lo=False, lock_hi=False):
    """A back wall of n px: long runs, a pillar about every fourth piece,
    mirrored as far as the pieces allow - and no pillar at an end that is
    locked (a column comes down onto it)."""
    locks = int(lock_lo) + int(lock_hi)
    if locks == 0:
        return _arrange(_compose(n, tuple(BACK_COST), BACK_COST))
    # cheapest composition that leaves a big piece for every locked end
    best = None
    for parts in _compositions(n, tuple(BACK_COST)):
        bigs = [p for p in parts if p != 17]
        if 17 in parts and len(bigs) < locks:
            continue
        c = sum(BACK_COST[p] for p in parts)
        if best is None or c < best[0]:
            best = (c, parts)
    if best is None:
        return _arrange(_compose(n, tuple(BACK_COST), BACK_COST))
    seq = _arrange(best[1])
    # walk a pillar off a locked end, swapping it with the nearest big piece
    if lock_lo and seq and seq[0] == 17:
        k = next(i for i, p in enumerate(seq) if p != 17)
        seq[0], seq[k] = seq[k], seq[0]
    if lock_hi and seq and seq[-1] == 17:
        k = next(i for i in range(len(seq) - 1, -1, -1) if seq[i] != 17)
        seq[-1], seq[k] = seq[k], seq[-1]
    return seq


def _compositions(n, parts, limit=4000):
    """Multisets of parts adding up to n, cheapest-looking first (few pieces)."""
    out = []
    parts = sorted(parts, reverse=True)

    def rec(rem, i, acc):
        if len(out) >= limit:
            return
        if rem == 0:
            out.append(list(acc))
            return
        if i >= len(parts):
            return
        p = parts[i]
        for k in range(rem // p, -1, -1):
            acc.extend([p] * k)
            rec(rem - k * p, i + 1, acc)
            del acc[len(acc) - k:]
            if len(out) >= limit:
                return
    rec(n, 0, [])
    return out


@lru_cache(maxsize=None)
def front_run(n):
    parts = _compose(n, tuple(FRONT_COST), FRONT_COST)
    return _arrange(parts)


@lru_cache(maxsize=None)
def side_run(n):
    parts = _compose(n, tuple(SIDE_COST), SIDE_COST)
    if parts is None:
        return None
    return sorted(parts, reverse=True)


def _arrange(parts):
    if parts is None:
        return None
    big = sorted([p for p in parts if p != 17], reverse=True)
    pillars = [p for p in parts if p == 17]
    # mirrored: the biggest at both ends, smaller toward the middle
    left, right = [], []
    for i, p in enumerate(big):
        (left if i % 2 == 0 else right).append(p)
    seq = left + right[::-1]
    # pillars spread evenly between pieces
    if pillars:
        out = []
        gaps = len(seq) + 1
        at = sorted({round((i + 1) * gaps / (len(pillars) + 1)) for i in range(len(pillars))})
        while len(at) < len(pillars):
            at.append(at[-1] + 1)
        k = 0
        for i in range(len(seq) + 1):
            while k < len(at) and at[k] == i:
                out.append(17)
                k += 1
            if i < len(seq):
                out.append(seq[i])
        while k < len(pillars):
            out.append(17)
            k += 1
        seq = out
    return seq


# =============================================================================
# THE EDGES OF A FLOOR MASK
# =============================================================================

def loops(floor):
    """Every boundary of the floor as a loop of straight edges, each
    {"o": "N"|"S"|"W"|"E", "t": cell line, "a": start, "b": end} (cells; a<b
    along the edge), in order round the loop. Floor is kept on the right."""
    h, w = len(floor), len(floor[0])

    def f(x, y):
        return 0 <= x < w and 0 <= y < h and floor[y][x]

    # unit edges, directed with the floor on the right (clockwise round floor)
    nxt = {}
    for y in range(h):
        for x in range(w):
            if not floor[y][x]:
                continue
            if not f(x, y - 1):
                nxt.setdefault((x, y), []).append((x + 1, y))       # N side, going east
            if not f(x + 1, y):
                nxt.setdefault((x + 1, y), []).append((x + 1, y + 1))  # E side, going south
            if not f(x, y + 1):
                nxt.setdefault((x + 1, y + 1), []).append((x, y + 1))  # S side, going west
            if not f(x - 1, y):
                nxt.setdefault((x, y + 1), []).append((x, y))       # W side, going north
    for k, v in nxt.items():
        if len(v) > 1:
            raise ValueError("floor touches itself corner to corner at %s" % (k,))
    seen = set()
    out = []
    for start in list(nxt.keys()):
        if start in seen:
            continue
        pts = [start]
        p = start
        while True:
            seen.add(p)
            q = nxt[p][0]
            if q == start:
                break
            pts.append(q)
            p = q
        # merge into straight edges
        n = len(pts)
        corners = []
        for i in range(n):
            a, b, c = pts[i - 1], pts[i], pts[(i + 1) % n]
            if (b[0] - a[0], b[1] - a[1]) != (c[0] - b[0], c[1] - b[1]):
                corners.append(b)
        edges = []
        m = len(corners)
        for i in range(m):
            p0, p1 = corners[i], corners[(i + 1) % m]
            if p0[1] == p1[1]:
                if p1[0] > p0[0]:
                    edges.append({"o": "N", "t": p0[1], "a": p0[0], "b": p1[0]})
                else:
                    edges.append({"o": "S", "t": p0[1], "a": p1[0], "b": p0[0]})
            else:
                if p1[1] > p0[1]:
                    edges.append({"o": "E", "t": p0[0], "a": p0[1], "b": p1[1]})
                else:
                    edges.append({"o": "W", "t": p0[0], "a": p1[1], "b": p0[1]})
        out.append(edges)
    return out


# =============================================================================
# SOLVING THE LINES
# =============================================================================

def window(e):
    T = e["t"] * TILE
    if "fix" in e:
        return [e["fix"]]
    if e.get("open"):
        return [T]
    o = e["o"]
    if o == "W":
        return list(range(T, T + 10))
    if o == "E":
        return list(range(T, T - 10, -1))
    if o == "N":
        return list(range(T, T + 29))
    return list(range(T, T - 29, -1))


def _ends(e, prev, nxt):
    """For edge e between prev and nxt (in loop order, floor on the right),
    which neighbour is at its low end (left/top) and which at its high end."""
    # loop order: N goes east (low end first), E south, S west, W north
    if e["o"] in ("N", "E"):
        return prev, nxt
    return nxt, prev


def _concave_lo(e, lo):
    return e["o"] == "N" and lo is not None and lo["o"] == "E" and not lo.get("open")


def _concave_hi(e, hi):
    return e["o"] == "N" and hi is not None and hi["o"] == "W" and not hi.get("open")


def run_span(e, lo, hi, plo, phi):
    """The [start, end] in px of the pieces along edge e, given its low and
    high neighbours and their lines (None: the neighbour is open)."""
    o = e["o"]
    if o == "N":
        s = (plo + 17) if lo["o"] == "W" else plo          # convex corner | concave
        t = (phi - 16) if hi["o"] == "E" else phi
        if lo.get("open"):
            s = plo
        if hi.get("open"):
            t = phi
        return s, t
    if o == "S":
        s = (plo + 17) if lo["o"] == "W" else (plo + 9)
        t = (phi - 17) if hi["o"] == "E" else (phi - 9)
        if lo.get("open"):
            s = plo
        if hi.get("open"):
            t = phi
        return s, t
    # a column: lo is the edge above, hi the edge below
    s = (plo + 8) if lo["o"] == "N" else plo
    t = (phi - 30) if hi["o"] == "S" else (phi - 28)
    if lo.get("open"):
        s = plo
    if hi.get("open"):
        t = phi
    return s, t


def _cost(e, length, lo=None, hi=None):
    """What a wall of this length costs in pieces; None when none fits."""
    if e.get("open"):
        return 0.0
    if length < 0 or length > MAXLEN:
        return None
    if e["o"] == "N":
        locks = int(_concave_lo(e, lo)) + int(_concave_hi(e, hi))
        return BACK_C_LOCK[locks][length]
    if e["o"] == "S":
        return FRONT_C[length]
    return SIDE_C[length]


def _door_cost(e, s, t):
    """A column a door's wall crosses (e["door"], the band (top, bottom) in
    px it leaves out): both parts whole pieces, each at least a short one."""
    g0, g1 = e["door"]
    a, b = int(round(g0 - s)), int(round(t - g1))
    if a < 35 or b < 35 or a > MAXLEN or b > MAXLEN:
        return None
    if SIDE_C[a] is None or SIDE_C[b] is None:
        return None
    return SIDE_C[a] + SIDE_C[b]


def solve(loop):
    """Each edge's line P, so that every run and column is whole pieces.
    Returns {index: P} or raises ValueError naming the edge that cannot fit."""
    n = len(loop)
    result = {}
    # two cycles: the H edges' lines are fixed by the V runs between them
    # and the other way round. Edge i's run depends on i-1 and i+1.
    for parity in (0, 1):
        idx = [i for i in range(n) if i % 2 == parity]        # the variables
        # constraint between idx[k] and idx[k+1]: the edge between them
        dom = [window(loop[i]) for i in idx]
        m = len(idx)
        if m == 0:
            continue

        def cost(i, p):
            # a line off its cell takes floor from the room: a little cost
            return 0.01 * abs(p - loop[i]["t"] * TILE)

        def allowed(k, a, b):
            i, j = idx[k], idx[(k + 1) % m]
            mid = (i + 1) % n
            e = loop[mid]
            lo, hi = _ends(e, loop[i], loop[j])
            plo, phi = (a, b) if lo is loop[i] else (b, a)
            s, t = run_span(e, lo, hi, plo, phi)
            if "door" in e:
                return _door_cost(e, s, t)
            return _cost(e, int(round(t - s)), lo, hi)

        best = None
        for v0 in dom[0]:
            # Viterbi round the cycle from v0 back to v0
            layer = {v0: (cost(idx[0], v0), [v0])}
            for k in range(m - 1):
                new = {}
                for b in dom[k + 1]:
                    cand = None
                    for a, (c, path) in layer.items():
                        ec = allowed(k, a, b)
                        if ec is not None:
                            cc = c + ec + cost(idx[k + 1], b)
                            if cand is None or cc < cand[0]:
                                cand = (cc, path)
                    if cand is not None:
                        new[b] = (cand[0], cand[1] + [b])
                layer = new
                if not layer:
                    break
            for a, (c, path) in layer.items():
                ec = allowed(m - 1, a, v0)
                if ec is not None and (best is None or c + ec < best[0]):
                    best = (c + ec, path)
        if best is None:
            raise ValueError("no fit for the %s lines of loop at %s" % ("odd" if parity else "even", loop[0]))
        for k, i in enumerate(idx):
            result[i] = best[1][k]
    return result


# =============================================================================
# THE PIECES
# =============================================================================

def spans(loop, P):
    """Each edge's pieces' [start, end] in px, by index."""
    out = {}
    n = len(loop)
    for i, e in enumerate(loop):
        pi, ni = (i - 1) % n, (i + 1) % n
        lo_i, hi_i = (pi, ni) if e["o"] in ("N", "E") else (ni, pi)
        out[i] = run_span(e, loop[lo_i], loop[hi_i], P[lo_i], P[hi_i])
    return out


def pieces(loop, P, cuts=None):
    """The wall pieces for a solved loop: [scene, x, y] (y the piece's foot).
    cuts: {edge index: (top, bottom)} - a band left out of a column, where a
    door's wall crosses the corridor."""
    out = []
    n = len(loop)
    cuts = cuts or {}
    for i, e in enumerate(loop):
        if e.get("open"):
            continue
        pi, ni = (i - 1) % n, (i + 1) % n
        lo_i, hi_i = (pi, ni) if e["o"] in ("N", "E") else (ni, pi)
        lo, hi = loop[lo_i], loop[hi_i]
        s, t = run_span(e, lo, hi, P[lo_i], P[hi_i])
        length = int(round(t - s))
        p = P[i]
        if e["o"] in ("N", "S"):
            seq = back_run(length, _concave_lo(e, lo), _concave_hi(e, hi)) if e["o"] == "N" else front_run(length)
            foot = p if e["o"] == "N" else p + 28
            x = s
            last = len(seq) - 1
            for k, wdt in enumerate(seq):
                # A pillar is 30 tall to a run's 28: one at the end of a back
                # wall a column comes down onto stands 2 px lower, its cap
                # meeting the column's foot instead of tucking under it.
                drop = 0
                if wdt == 17 and ((k == 0 and _concave_lo(e, lo)) or (k == last and _concave_hi(e, hi))):
                    drop = 2
                out.append([RUN[wdt], x + wdt / 2.0, foot + drop])
                x += wdt
            # the corners at its ends, where they are convex and walled
            if lo["o"] == "W" and not lo.get("open"):
                kind = "wallcornerbackleft" if e["o"] == "N" else "wallcornerfrontleft"
                out.append([kind, P[lo_i] + 4, foot + (8 if e["o"] == "N" else 0)])
            if hi["o"] == "E" and not hi.get("open"):
                if e["o"] == "N":
                    out.append(["wallcornerbackright", P[hi_i] - 3.5, foot + 8])
                else:
                    out.append(["wallcornerfrontright", P[hi_i] - 4, foot])
        else:
            cx = p - 4.5 if e["o"] == "W" else p + 4.5
            parts = [(s, t)]
            if i in cuts:
                g0, g1 = cuts[i]
                parts = [(s, g0), (g1, t)]
            elif "door" in e:
                g0, g1 = e["door"]
                parts = [(s, g0), (g1, t)]
            for (a, b) in parts:
                seq = side_run(int(round(b - a)))
                if seq is None:
                    raise ValueError("a cut column does not fit: %s %s-%s" % (e, a, b))
                y = a
                for hgt in seq:
                    y += hgt
                    out.append([SIDE[hgt], cx, y])
    return out


def diagnose(loop):
    """The edges that cannot be walled whatever their neighbours' lines -
    each with its neighbours and the lengths it could have had."""
    n = len(loop)
    bad = []
    for mid, e in enumerate(loop):
        if e.get("open"):
            continue
        i, j = (mid - 1) % n, (mid + 1) % n
        lo, hi = _ends(e, loop[i], loop[j])
        li, hj = (i, j) if lo is loop[i] else (j, i)
        lens = set()
        for a in window(loop[li]):
            for b in window(loop[hj]):
                s, t = run_span(e, loop[li], loop[hj], a, b)
                lens.add(int(round(t - s)))
        if not any(_cost(e, L, loop[li], loop[hj]) is not None for L in lens):
            bad.append((e, loop[li], loop[hj], sorted(lens)))
    return bad
