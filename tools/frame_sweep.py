#!/usr/bin/env python3
"""
frame_sweep.py - what the project does on every single frame.

A game holds 30fps or it does not, and the whole question is decided inside
_process() and _physics_process(). Everything else in the codebase runs when
somebody clicks something; these run sixty times a second, per node, forever.

So this walks every one of them and flags the calls that are cheap once and
ruinous sixty times a second:

  LOOKUPS      get_node / find_child / get_tree().get_nodes_in_group with a
               string. A node path is resolved by walking and comparing names;
               doing it per frame is paying a search for an answer that has not
               changed since _ready().
  ALLOCATION   .new() / .instantiate() / .duplicate(). Every one is a heap
               allocation the collector has to deal with, on a treadmill.
  SCANS        get_children() in a loop, sort_custom, filter, map - work that
               grows with how much content the game has, done every frame.
  TEXT         "%s" formatting and str() concatenation. A string built per
               frame is garbage created per frame, and the label almost always
               has not changed.
  PHYSICS      intersect_ray / intersect_shape - a space query per frame per
               node is the single most expensive thing on this list.

WHAT IT IS NOT. It cannot tell you a flagged line is slow, only that it is on
the hot path - some of these are correct and necessary. It is a list of places
to look, ordered so the worst offenders are at the top, not a list of bugs.

Usage: frame_sweep.py <project-src-dir>
"""
import os
import re
import sys
import collections

# _draw BELONGS HERE AND WAS MISSING. A _draw() runs whenever the node is
# redrawn, and a node that calls queue_redraw() from _process() is redrawn
# every single frame - so its _draw() is as hot as _process() is, and the
# first version of this sweep could not see any of it.
HOT = ("_process", "_physics_process", "_draw")

PATTERNS = [
    # Not expensive in itself - it is what it COMMITS the node to. A
    # queue_redraw() on every frame means a _draw() on every frame, for this
    # node, forever, whether or not anything about it changed.
    ("REDRAW", 4, re.compile(r"\bqueue_redraw\s*\(")),
    ("PHYSICS", 5, re.compile(r"\b(intersect_ray|intersect_shape|intersect_point|"
                              r"cast_motion|collide_shape)\s*\(")),
    ("LOOKUP", 4, re.compile(r"\b(get_nodes_in_group|find_child|find_children)\s*\(")),
    ("LOOKUP", 3, re.compile(r"\bget_node(_or_null)?\s*\(\s*[\"']")),
    ("ALLOC", 3, re.compile(r"\b(instantiate|duplicate)\s*\(")),
    ("ALLOC", 2, re.compile(r"\b[A-Z]\w*\.new\s*\(")),
    ("SCAN", 2, re.compile(r"\b(sort_custom|get_children|filter|map|reduce)\s*\(")),
    ("TEXT", 1, re.compile(r"%\s*\[|%\s*\w+\s*$|\bstr\s*\(")),
]

# A line that only reads these is fine: they are cached members, not lookups.
IGNORE_LINE = re.compile(r"^\s*(#|\"\"\")")


def hot_blocks(path):
    """Yield (func_name, start_line, [lines]) for each hot function in a file.

    Godot indents with tabs. A function body is everything indented past the
    `func` line until something at or below its own indentation appears.
    """
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        m = re.match(r"^(\s*)func\s+(\w+)\s*\(", lines[i])
        if not m or m.group(2) not in HOT:
            i += 1
            continue
        indent = len(m.group(1))
        body = []
        j = i + 1
        while j < len(lines):
            line = lines[j]
            if line.strip() and (len(line) - len(line.lstrip())) <= indent:
                break
            body.append((j + 1, line))
            j += 1
        yield m.group(2), i + 1, body
        i = j


def _all_funcs(path):
    """{name: [(lineno, line)]} for every function in a file."""
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    except OSError:
        return {}
    out = {}
    i = 0
    while i < len(lines):
        m = re.match(r"^(\s*)func\s+(\w+)\s*\(", lines[i])
        if not m:
            i += 1
            continue
        indent = len(m.group(1))
        body = []
        j = i + 1
        while j < len(lines):
            line = lines[j]
            if line.strip() and (len(line) - len(line.lstrip())) <= indent:
                break
            body.append((j + 1, line))
            j += 1
        out[m.group(2)] = body
        i = j
    return out


CALL = re.compile(r"\b(?:self\.)?([a-z_]\w*)\s*\(")


def _reachable_from_hot(path):
    """Every function a frame can actually reach, not just the two entry points.

    THE REASON THIS EXISTS. The first version of this sweep read only
    _process() and _physics_process() and came back almost empty, which was a
    comforting answer to the wrong question: nobody writes the expensive thing
    inline in _physics_process, they write `_update_ai()` there and the
    expensive thing lives in _update_ai. A tool that cannot see one call deeper
    reports a clean bill of health on a game that drops frames.

    Follows calls to functions defined in the SAME FILE, transitively. It stops
    at file boundaries because GDScript resolves cross-file calls through types
    this sweep does not track - so it under-reports rather than guessing, which
    is the right direction for a tool whose output is a list of places to look.
    """
    funcs = _all_funcs(path)
    seen = set()
    queue = [(name, False) for name in funcs if name in HOT]
    order = []
    while queue:
        name, gated = queue.pop(0)
        if name in seen or name not in funcs:
            continue
        seen.add(name)
        order.append((name, funcs[name], gated))
        # PAST AN EARLY RETURN IS NOT EVERY FRAME. Half of what the first
        # version reported sat behind `if not visible: return` or
        # `if not Input.is_action_just_pressed(...): return` - a panel that is
        # closed and a keypress that has not happened. Reporting those beside a
        # raycast that genuinely runs sixty times a second is how a tool
        # teaches you to stop reading it.
        past_guard = gated
        for _lineno, line in funcs[name]:
            stripped = line.strip()
            if stripped == "return" or stripped.startswith("return "):
                past_guard = True
            bare = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
            for called in CALL.findall(bare):
                if called in funcs and called not in seen:
                    queue.append((called, past_guard))
    return order


def main(root):
    findings = []
    hot_funcs = 0
    scanned = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in sorted(filenames):
            if not name.endswith(".gd"):
                continue
            path = os.path.join(dirpath, name)
            scanned += 1
            reached = _reachable_from_hot(path)
            for func, body, gated in reached:
                hot_funcs += 1
                for lineno, line in body:
                    if IGNORE_LINE.match(line):
                        continue
                    # strings can contain anything; strip them before matching
                    bare = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
                    for kind, weight, pattern in PATTERNS:
                        if pattern.search(bare if kind != "TEXT" else line):
                            findings.append((0 if gated else weight, kind,
                                             path, lineno, func,
                                             line.strip()[:96], gated))
                            break

    print("scanned %d scripts, %d functions reachable from a frame, "
          "%d lines worth a look\n" % (scanned, hot_funcs, len(findings)))

    by_file = collections.Counter(f[2] for f in findings if not f[6])
    print("=== FILES WITH THE MOST UNGATED PER-FRAME WORK ===")
    for path, count in by_file.most_common(12):
        worst = max(f[0] for f in findings if f[2] == path and not f[6])
        print("  %-52s %3d lines   (worst weight %d)"
              % (path.replace(root, "").lstrip("/"), count, worst))

    ungated = [f for f in findings if not f[6]]
    print("\n  of those, %d are on an UNGATED path - reached every frame with no"
          % len(ungated))
    print("  early return in the way. The rest sit behind a guard (a closed")
    print("  panel, a keypress that has not happened) and are listed after.\n")

    print("=== EVERY-FRAME, WORST FIRST ===")
    if not ungated:
        print("  none")
    for weight, kind, path, lineno, func, src, _g in sorted(ungated, reverse=True):
        print("  [%s] %s:%d  in %s()" % (kind, path.replace(root, "").lstrip("/"),
                                         lineno, func))
        print("         %s" % src)

    print("\n=== BEHIND A GUARD (look only if the guard is often true) ===")
    for weight, kind, path, lineno, func, src, _g in sorted(
            [f for f in findings if f[6]], reverse=True)[:12]:
        print("  [%s] %s:%d  in %s()   %s"
              % (kind, path.replace(root, "").lstrip("/"), lineno, func, src[:60]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "src"))
