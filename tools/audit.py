#!/usr/bin/env python3
"""
audit.py - finds the things that look finished and do nothing.

    python tools/audit.py              from the project root
    python tools/audit.py --quiet      only findings, no clean sections

WHY THIS EXISTS
---------------
In one working day, a review of this project turned up eleven separate
instances of a single bug: a feature that is present, styled, wired and inert.

    the cloth armour line filed one equip slot too high
    a server slot vocabulary with a "robe" slot the enum never had
    a tooltip stats panel showing placeholder text for all 123 items
    a Settings button on the login screen connected to nothing
    an Options handler whose body was print("not yet implemented")
    two audio buses that every sound player was assigned to and did not exist
    get_attack_speed_multiplier(), defined, unit-tested, called by nothing
    FloatingLabel with no class_name, forcing every caller to pass a bare 0
    is_panel_open() covering four of nine panels
    a scene whose script path pointed at a file that is not there
    five of seven bosses placed in no world scene

None of those throw. None appear in a log. Every one of them looks correct
from the outside, and so does broken - which is the entire problem, and why
finding them needs a pass that reads the project rather than runs it.

THE MODEL IS exportgamedata.gd, which already refuses to write when its own
validation fails, and which reported the unplaced boss scenes unprompted. This
is that idea pointed at the whole project instead of one export.

A FINDING IS NOT AUTOMATICALLY A BUG. Scaffolding built ahead of its wiring is
a legitimate state and this project uses it deliberately - ItemData.damage sat
correctly authored for months before combat read it. What the audit gives you
is the list, so that state is a decision rather than a surprise. Silence a
known-and-intended one by adding its name to ALLOWED at the bottom.
"""

import os
import re
import sys
from collections import defaultdict

ROOT = os.path.abspath(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if not os.path.exists(os.path.join(ROOT, "project.godot")):
    ROOT = os.getcwd()

QUIET = "--quiet" in sys.argv

# Functions Godot calls itself. An engine callback nothing else references is
# the normal case, not a finding, and listing them here is cheaper than the
# false positives would be.
GODOT_VIRTUALS = {
    "_ready", "_process", "_physics_process", "_input", "_unhandled_input",
    "_unhandled_key_input", "_gui_input", "_draw", "_enter_tree",
    "_exit_tree", "_init", "_notification", "_get_configuration_warnings",
    "_to_string", "_get", "_set", "_get_property_list", "_can_drop_data",
    "_drop_data", "_get_drag_data", "_make_custom_tooltip", "_has_point",
    "_integrate_forces", "_shortcut_input", "_validate_property",
}


# =============================================================================
# READING THE PROJECT
# =============================================================================

def walk(*exts):
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", ".godot", ".import",
                                                "__pycache__", "addons")]
        for name in files:
            if name.endswith(exts):
                path = os.path.join(base, name)
                yield path, os.path.relpath(path, ROOT).replace("\\", "/")


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return ""


SCRIPTS = {rel: read(p) for p, rel in walk(".gd")}
SCENES = {rel: read(p) for p, rel in walk(".tscn")}
RESOURCES = {rel: read(p) for p, rel in walk(".tres")}
PROJECT = read(os.path.join(ROOT, "project.godot"))

ALL_SOURCE = "\n".join(SCRIPTS.values())
ALL_TEXT = ALL_SOURCE + "\n" + "\n".join(SCENES.values()) + "\n" + "\n".join(RESOURCES.values())


def strip_comments(text):
    # Comments are where this project keeps its reasoning, and they mention
    # nearly every symbol in the codebase. Counting a name in a comment as a
    # use would make "never called" find nothing at all.
    out = []
    for line in text.split("\n"):
        in_string = False
        quote = ""
        cut = len(line)
        for i, ch in enumerate(line):
            if in_string:
                if ch == quote and (i == 0 or line[i - 1] != "\\"):
                    in_string = False
            elif ch in "\"'":
                in_string, quote = True, ch
            elif ch == "#":
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)


CODE = {rel: strip_comments(src) for rel, src in SCRIPTS.items()}
ALL_CODE = "\n".join(CODE.values())


# =============================================================================
# REPORTING
# =============================================================================

# KNOWN AND INTENDED. A finding named here is suppressed, and the reason is
# printed at the end so the list stays a decision rather than a drawer.
#
# The first version of this file described this mechanism in its own docstring
# and did not implement it — which is, exactly, the bug this whole tool hunts.
ALLOWED = {
    "gamestate.gd signals":
        "gamestate.gd's own header says the signal set is declared ahead of "
        "multiplayer and deliberately unconnected. Reviewed and kept.",
}

FINDINGS = []
SUPPRESSED = []


def report(section, why, rows, severity="warn", allow_key=None):
    if allow_key and allow_key in ALLOWED and rows:
        SUPPRESSED.append((section, len(rows), ALLOWED[allow_key]))
        rows = []
    FINDINGS.append((section, why, rows, severity))


def emit():
    total = 0
    for section, why, rows, severity in FINDINGS:
        if not rows and QUIET:
            continue
        mark = "!!" if (rows and severity == "fail") else ("--" if rows else "ok")
        print("\n%s  %s  (%d)" % (mark, section, len(rows)))
        print("    " + why.replace("\n", "\n    "))
        for row in rows:
            print("      %s" % row)
        total += len(rows)
    if SUPPRESSED:
        print("\nsilenced by ALLOWED:")
        for section, count, reason in SUPPRESSED:
            print("    %s (%d) — %s" % (section, count, reason))
    print("\n" + "=" * 72)
    print("  %d finding(s) across %d checks" % (total, len(FINDINGS)))
    print("=" * 72)
    return total


# =============================================================================
# 1. HANDLERS THAT DO NOTHING
# =============================================================================
# The Options button was wired to a handler whose entire body was a print. It
# had been on the HUD's nav row for months, styled, next to nine buttons that
# work.

FUNC = re.compile(r"^func\s+([A-Za-z_]\w*)\s*\(([^)]*)\)[^\n]*:\n((?:[ \t]+.*\n|\n)*)", re.M)


def function_bodies(code):
    for m in FUNC.finditer(code):
        yield m.group(1), m.group(3)


def body_is_inert(body):
    lines = [l.strip() for l in body.split("\n") if l.strip()]
    if not lines:
        return True
    for line in lines:
        if line == "pass":
            continue
        if re.match(r"^print\(", line) or re.match(r"^print_rich\(", line):
            continue
        if line.startswith("return") and line.strip() in ("return", "return null"):
            continue
        return False
    return True


rows = []
for rel, code in CODE.items():
    for name, body in function_bodies(code):
        if not body_is_inert(body):
            continue
        # Only handlers: something is connected to these, so the player has a
        # control that appears to do something. An empty helper is just an
        # empty helper.
        if not (name.startswith("_on_") or name.endswith("_pressed")
                or name.endswith("_toggled") or name.endswith("_changed")):
            continue
        rows.append("%s: %s() runs nothing" % (rel, name))
report("HANDLERS WIRED TO NOTHING",
       "A control the player can press, connected to a function whose whole body\n"
       "is pass or a print. This is what the Options button was for months.",
       sorted(rows), "fail")


# =============================================================================
# 2. res:// PATHS THAT DO NOT RESOLVE
# =============================================================================
# itemtooltip.tscn pointed at res://src/ui/itemtooltip.gd, which does not
# exist - the script is in src/ui/inventory/. It only worked because Godot
# resolves by UID before it tries the path, and would have broken the day the
# UID cache was rebuilt.

RES_PATH = re.compile(r'(?:preload|load)\(\s*"(res://[^"]+)"|path="(res://[^"]+)"')

rows = []
seen = set()
for source in (SCRIPTS, SCENES, RESOURCES):
    for rel, text in source.items():
        for m in RES_PATH.finditer(text):
            target = m.group(1) or m.group(2)
            local = os.path.join(ROOT, target[len("res://"):].replace("/", os.sep))
            if os.path.exists(local):
                continue
            key = (rel, target)
            if key in seen:
                continue
            seen.add(key)
            rows.append("%s -> %s" % (rel, target))
# GROUPED BY DESTINATION FOLDER, and quiet when the whole folder is absent.
#
# Run against a partial copy of the project — a sparse checkout, a clone with
# art excluded, a staging directory — every art reference misses and this
# prints two hundred lines that are all the same fact. A missing FOLDER is a
# missing folder; a missing FILE inside a folder that exists is the finding.
total_refs = len(seen)
by_folder = defaultdict(list)
for row in rows:
    target = row.split(" -> ")[1]
    by_folder[target.rsplit("/", 1)[0]].append(row)

grouped, absent_folders = [], []
for folder in sorted(by_folder):
    local = os.path.join(ROOT, folder[len("res://"):].replace("/", os.sep))
    if not os.path.isdir(local):
        absent_folders.append("%s — %d reference(s), and the folder itself is not here"
                              % (folder, len(by_folder[folder])))
        continue
    grouped.extend(sorted(by_folder[folder]))

if absent_folders and total_refs and len(rows) > total_refs * 0.25:
    grouped = ["(%d of %d references miss, and whole folders are absent — this looks"
               % (len(rows), total_refs),
               " like an incomplete copy of the project rather than broken links.",
               " Re-run from a full checkout before believing this section.)"] \
        + absent_folders
else:
    grouped = absent_folders + grouped

report("res:// PATHS THAT DO NOT EXIST",
       "A script or scene referencing a file that is not on disk. Godot resolves\n"
       "by UID first, so a wrong path can sit here for months without failing.",
       grouped, "fail")


# =============================================================================
# 3. AUDIO BUSES
# =============================================================================
# Every sound player in the game was assigned to "SFX" and "Music". There was
# no bus layout, so both resolved to nothing and everything played on Master -
# and the volume sliders written for them did nothing at all.

layout = ""
for rel, text in RESOURCES.items():
    if "AudioBusLayout" in text:
        layout = text
declared = set(re.findall(r'bus/\d+/name = &?"([^"]+)"', layout))
if layout and not declared:
    declared = {"Master"}
if not layout:
    declared = {"Master"}

used = set(re.findall(r'\.bus\s*=\s*"([^"]+)"', ALL_CODE))
used |= set(re.findall(r'set_bus_volume\(\s*"([^"]+)"', ALL_CODE))
used |= set(re.findall(r'get_bus_volume\(\s*"([^"]+)"', ALL_CODE))
used |= set(re.findall(r'get_bus_index\(\s*"([^"]+)"', ALL_CODE))

rows = ["%s  (declared: %s)" % (b, ", ".join(sorted(declared)) or "none")
        for b in sorted(used - declared)]
if not layout:
    rows.insert(0, "no AudioBusLayout resource anywhere in the project")
elif 'buses/default_bus_layout' not in PROJECT:
    rows.insert(0, "a bus layout exists but project.godot does not name it — "
                   "an unreferenced layout is a file, not a layout")
report("AUDIO BUSES THAT DO NOT EXIST",
       "A bus name assigned in code with no matching entry in the layout. Audio\n"
       "on a missing bus still plays, on Master, so nothing sounds wrong.",
       rows, "fail")


# =============================================================================
# 4. FUNCTIONS NOTHING CALLS
# =============================================================================
# get_attack_speed_multiplier() is defined on the player, has four unit tests,
# and is called by no class. Agility has bought no attack speed since it was
# written.

defined = defaultdict(list)
for rel, code in CODE.items():
    for m in re.finditer(r"^(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(", code, re.M):
        defined[m.group(1)].append(rel)

scene_text = "\n".join(SCENES.values())
rows = []
for name, where in sorted(defined.items()):
    if name in GODOT_VIRTUALS or name.startswith("_"):
        continue
    # One definition only: an override in four class scripts is called through
    # the base, and counting those as uncalled would bury the real ones.
    if len(where) > 1:
        continue
    # BOTH SPELLINGS. The first version of this counted only bare calls, which
    # excluded every `CharacterData.load_character_state(...)` in the project
    # and reported 83 findings, nearly all of them autoload methods called
    # dozens of times. An audit that cries wolf is the same failure as the
    # bugs it hunts: present, plausible, ignored.
    calls = len(re.findall(r"\b%s\s*\(" % re.escape(name), ALL_CODE))
    definitions = len(re.findall(r"func\s+%s\s*\(" % re.escape(name), ALL_CODE))
    referenced = (re.search(r'"%s"' % re.escape(name), ALL_CODE + scene_text)
                  or re.search(r"\b%s\b" % re.escape(name), scene_text))
    if calls <= definitions and not referenced:
        rows.append("%s: %s()" % (where[0], name))
report("FUNCTIONS NOTHING CALLS",
       "Defined once, called nowhere, not referenced by name in any scene. Some\n"
       "are deliberate API kept for later; each should be a decision.",
       rows)


# =============================================================================
# 5. ENUMS NOTHING CAN NAME
# =============================================================================
# floatinglabel.gd declares Type { DAMAGE, HEAL, MANA, LEVELUP, SKILLUP,
# NOTICE } and had no class_name, so every caller in the project passed a bare
# 0 or 3 and the enum's "append, never insert" rule was enforced by a comment
# in a file none of them had open.

rows = []
for rel, code in CODE.items():
    if not re.search(r"^enum\s+[A-Za-z_]\w*\s*\{", code, re.M):
        continue
    if re.search(r"^class_name\s", code, re.M):
        continue
    names = re.findall(r"^enum\s+([A-Za-z_]\w*)", code, re.M)
    rows.append("%s: enum %s unreachable — no class_name"
                % (rel, ", ".join(names)))
report("ENUMS NOTHING CAN NAME",
       "A script with an enum and no class_name. Callers have to pass bare\n"
       "integers, and reordering the enum silently repoints every one of them.",
       sorted(rows))


# =============================================================================
# 6. UNIQUE NAMES NOTHING LOOKS UP
# =============================================================================
# The login screen's Settings button was unique_name_in_owner, styled, 110x38,
# and %Settingsbutton appears in no script in the project.

NODE_LINE = re.compile(r'^\[node name="([^"]+)"', re.M)
rows = []
for rel, text in SCENES.items():
    blocks = text.split("[node ")
    for block in blocks[1:]:
        if "unique_name_in_owner = true" not in block.split("[node ")[0]:
            continue
        m = re.match(r'name="([^"]+)"', block)
        if not m:
            continue
        name = m.group(1)
        # THE NAME ANYWHERE IN ANY SCRIPT, not just as %name.
        #
        # The first version matched only the % spelling and reported four of
        # six findings wrongly: the bank's %goldinput, %withdrawbutton and
        # %depositbuttons and the HUD's %healthvalue are all reached by node
        # path instead. A section that is two-thirds wrong is a section nobody
        # reads, which is the same end state as the bugs this file hunts.
        #
        # Deliberately conservative. Matching the bare word will occasionally
        # let a dead node through because something unrelated shares its name —
        # under-reporting is recoverable, crying wolf is not.
        if re.search(r"\b%s\b" % re.escape(name), ALL_CODE):
            continue
        rows.append("%s: %%%s" % (rel, name))
report("UNIQUE NAMES NOTHING LOOKS UP",
       "A node marked unique_name_in_owner that no script ever asks for. Either\n"
       "the control is dead, or the script forgot it.",
       sorted(rows))


# =============================================================================
# 7. GROUPS THAT ONLY GO ONE WAY
# =============================================================================

added = set(re.findall(r'add_to_group\(\s*"([^"]+)"', ALL_CODE))
added |= set(re.findall(r'groups\s*=\s*\[([^\]]*)\]', scene_text)
             and re.findall(r'"([^"]+)"', " ".join(
                 re.findall(r'groups\s*=\s*\[([^\]]*)\]', scene_text))) or [])
queried = set(re.findall(r'in_group\(\s*"([^"]+)"', ALL_CODE))
queried |= set(re.findall(r'get_nodes_in_group\(\s*"([^"]+)"', ALL_CODE))

rows = ["queried but never joined: %s" % g for g in sorted(queried - added)]
rows += ["joined but never queried: %s" % g for g in sorted(added - queried)]
report("GROUPS THAT ONLY GO ONE WAY",
       "A group looked up by nobody who joins it, or joined by nobody who looks.\n"
       "A lookup that finds nothing returns null and the caller quietly does less.",
       rows)


# =============================================================================
# 8. SIGNALS NOTHING CONNECTS
# =============================================================================

rows = []
for rel, code in CODE.items():
    for m in re.finditer(r"^signal\s+([A-Za-z_]\w*)", code, re.M):
        name = m.group(1)
        if re.search(r"\.%s\.(connect|emit)\b" % re.escape(name), ALL_CODE):
            continue
        if re.search(r"(?<![\w.])%s\.(connect|emit)\b" % re.escape(name), ALL_CODE):
            continue
        if re.search(r'"%s"' % re.escape(name), ALL_CODE + scene_text):
            continue
        rows.append("%s: signal %s" % (rel, name))
gamestate_only = rows and all("gamestate.gd" in r for r in rows)
report("SIGNALS NOTHING CONNECTS OR EMITS",
       "Declared and never used in either direction. gamestate.gd keeps a set of\n"
       "these on purpose for multiplayer; the rest are worth a look.",
       sorted(rows), "warn",
       "gamestate.gd signals" if gamestate_only else None)


# =============================================================================
# 9. INPUT ACTIONS NOTHING READS
# =============================================================================

actions = re.findall(r"^(\w+)=\{", PROJECT.split("[input]")[-1].split("[layer_names]")[0], re.M) \
    if "[input]" in PROJECT else []
rows = []
for action in actions:
    if action.startswith("ui_"):
        continue
    if re.search(r'"%s"' % re.escape(action), ALL_CODE):
        continue
    rows.append(action)
report("INPUT ACTIONS NOTHING READS",
       "Bound in project.godot, never named in a script. The key does nothing and\n"
       "the binding screen would offer the player a control that is not wired.",
       sorted(rows))


# =============================================================================
# 10. ITEMS WITH NO PICTURE
# =============================================================================
# An item with no icon exists, drops, stacks and is worth gold, and renders as
# an empty cell in a grid of empty cells.

rows = []
for rel, text in RESOURCES.items():
    if "/items/" not in rel:
        continue
    m = re.search(r'^item_id = "([^"]*)"', text, re.M)
    if not m:
        continue
    # SubResource COUNTS. Every pet icon in this project is an AtlasTexture
    # cut out of a shared sheet — see the art pipeline notes — so looking only
    # for ExtResource reported all seven pets as art that does not exist.
    if re.search(r"^icon = (ExtResource|SubResource)", text, re.M):
        continue
    rows.append("%s (%s)" % (m.group(1), rel))
report("ITEMS WITH NO ICON",
       "Owned, sold, dropped and invisible — an empty cell among empty cells.\n"
       "This is the list to hand an artist.",
       sorted(rows))


# =============================================================================
# 11. SCENES NOTHING PLACES
# =============================================================================
# The export tool already reports this for enemies. Widened here to pets and
# projectiles, which fail the same way: authored, loadable, never instanced.

WATCH = ("scene/enemy/", "scene/enemies/", "scene/pets/", "scene/projectiles/")
instanced = set(re.findall(r'path="(res://[^"]+\.tscn)"', scene_text))
preloaded = set(re.findall(r'"(res://[^"]+\.tscn)"', ALL_CODE))
# AND FROM RESOURCES. A pet scene is named by its ItemData .tres
# (pet_scene = ExtResource(...)), loaded through PetController.pet_scene_for()
# — so reading only scenes and scripts reported every pet in the game as
# unreachable, when pets are one of the things that demonstrably work.
resource_text = "\n".join(RESOURCES.values())
preloaded |= set(re.findall(r'path="(res://[^"]+\.tscn)"', resource_text))
rows = []
for rel in sorted(SCENES):
    if not rel.startswith(WATCH):
        continue
    target = "res://" + rel
    if target in instanced or target in preloaded:
        continue
    rows.append(rel)
report("SCENES NOTHING PLACES OR PRELOADS",
       "An enemy, pet or projectile scene that no other scene instances and no\n"
       "script loads. Anything it alone drops cannot be obtained.",
       rows)


# =============================================================================
# 12. AUTOLOADS NOTHING USES
# =============================================================================

autoloads = re.findall(r"^(\w+)=\"\*?res://", PROJECT.split("[autoload]")[-1]
                       .split("[audio]")[0].split("[display]")[0], re.M) \
    if "[autoload]" in PROJECT else []
rows = []
for name in autoloads:
    hits = len(re.findall(r"(?<![\w.])%s\." % re.escape(name), ALL_CODE))
    if hits:
        continue
    # A SINGLETON THAT DRIVES ITSELF IS NOT UNUSED. PerfOverlay listens for its
    # own hotkey and draws its own overlay; nothing calls it because nothing
    # needs to. Only a singleton with no engine callbacks at all is inert.
    path = re.search(r'^%s="\*?(res://[^"]+)"' % re.escape(name), PROJECT, re.M)
    body = CODE.get(path.group(1)[len("res://"):], "") if path else ""
    if re.search(r"^func (_ready|_process|_input|_unhandled_input|"
                 r"_unhandled_key_input|_physics_process|_notification)\b",
                 body, re.M):
        continue
    rows.append(name)
report("AUTOLOADS NOTHING USES",
       "Registered as a singleton, never referenced. It is loaded at boot and\n"
       "costs whatever its _ready() costs.",
       sorted(rows))


# =============================================================================
# 13. ANIMATION SETS MISSING A DIRECTION
# =============================================================================
# Every creature in this game is drawn four ways. A set with three is a
# character that turns a corner and vanishes, or holds the wrong pose — and
# there is no error, because playing an animation that does not exist is a
# push_error in the log and a sprite that keeps its last frame.
#
# ANIMATION NAMES END IN up / down / left / right. Marker2D names end in
# top / bottom / left / right. Two vocabularies, four directions, and the
# project's own art notes single this out as the most confusable thing in it.

DIRECTIONS = ("up", "down", "left", "right")
ANIM = re.compile(r'"name": &"([a-z]+)"[^}]*?"speed": ([0-9.]+)', re.S)
ANIM_NAME = re.compile(r'"name": &"([a-z]+)"')
ANIM_SPEED = re.compile(r'"speed": ([0-9.]+)')


def animation_sets(text):
    # Parsed per animation dict rather than with one regex over the file: the
    # speed of an animation sits before its name in some blocks and after it
    # in others, depending on how Godot last wrote the scene.
    out = {}
    for block in re.split(r"\{", text):
        name = ANIM_NAME.search(block)
        if not name:
            continue
        speed = ANIM_SPEED.search(block)
        out[name.group(1)] = float(speed.group(1)) if speed else None
    return out


missing_rows, speed_rows = [], []
for rel, text in SCENES.items():
    if '"name": &"' not in text:
        continue
    anims = animation_sets(text)
    if not anims:
        continue

    groups = defaultdict(dict)
    for name, speed in anims.items():
        for d in DIRECTIONS:
            if name.endswith(d):
                groups[name[: -len(d)]][d] = speed
                break

    for base, found in sorted(groups.items()):
        if base == "":
            continue
        absent = [d for d in DIRECTIONS if d not in found]
        if absent and len(found) > 1:
            missing_rows.append("%s: %s* has no %s"
                                % (rel, base, ", ".join(absent)))

        speeds = {v for v in found.values() if v is not None}
        if len(speeds) > 1:
            speed_rows.append("%s: %s* runs at %s"
                              % (rel, base,
                                 ", ".join("%s %g" % (d, found[d])
                                           for d in DIRECTIONS if d in found
                                           and found[d] is not None)))

report("ANIMATION SETS MISSING A DIRECTION",
       "Three of four directions drawn. The fourth plays nothing and the sprite\n"
       "holds its last frame. This is the list to hand an artist.",
       sorted(missing_rows))

report("ANIMATIONS THAT CHANGE SPEED WHEN THEY TURN",
       "One direction of a set running at a different rate from its siblings —\n"
       "usually a new animation left at Godot's default 5.0 beside three that\n"
       "were tuned. The character visibly changes pace as it turns.",
       sorted(speed_rows))


# =============================================================================
# 15. SPAWNS THAT STREAK IN FROM THE WORLD ORIGIN
# =============================================================================
# add_child() resets physics interpolation — to whatever transform the node has
# AT THAT MOMENT, which for a freshly instantiated scene is its authored origin,
# usually (0, 0). So the ORDER is the entire bug:
#
#     add_child(n); n.global_position = p            streaks from (0,0)
#     n.global_position = p; add_child(n)            fine
#     add_child(n); n.global_position = p
#                   n.reset_physics_interpolation()  fine
#
# Only the first form is reported. Deferred variants count the same, because
# deferred calls flush in the order they were queued.
#
# This check exists because the respawner had it for months and nobody could
# name it: a respawning enemy drew two or three ghost copies strung between the
# map origin and its spawn point, and the only report it ever got was "the
# after images are back".
#
# WHAT IT DELIBERATELY DOES NOT CATCH: moving a node that is ALREADY in the
# tree — a teleport, or field.gd/boss.gd dropping the player onto an arrival
# portal. Those streak for the same reason, but the pattern is indistinguishable
# from ordinary movement code, which sets position on every enemy every frame.
# Reporting it would bury the tractable case in noise, and an audit that cries
# wolf fails the same way the bugs do. Only fresh spawns are tracked, because
# there the instantiate() gives an unambiguous handle on the node.

SPAWN_SKIP = ("panel", "row", "slot", "label", "button", "popup", "screen",
              "tooltip", "entry", "line", "icon", "box", "dialog", "menu",
              "card", "tab", "ui", "hud", "bar", "list", "sep", "spacer",
              "container", "grid", "vbox", "hbox", "margin", "scroll",
              "texture", "style", "tween", "timer", "shape", "material",
              "image", "rect", "fade")

SPAWN_INSTANTIATE = re.compile(
    r"^\s*var\s+(\w+)(?:\s*:\s*[\w\.]+)?\s*:?=\s*.*\binstantiate\(\)")

streak_rows = []
for rel, text in SCRIPTS.items():
    # UI lives in a CanvasLayer and is not physics-interpolated at all.
    if "/ui/" in rel:
        continue
    lines = text.splitlines()
    for i, line in enumerate(lines):
        match = SPAWN_INSTANTIATE.match(line)
        if not match:
            continue
        var = match.group(1)
        if any(s in var.lower() for s in SPAWN_SKIP):
            continue

        added = re.compile(r"\badd_child(?:\.call_deferred)?\(\s*%s\b"
                           r"|\bcall_deferred\(\s*[\"']add_child[\"']\s*,\s*%s\b"
                           % (var, var))
        moved = re.compile(
            r"^\s*%s\.(?:global_position|position|global_transform|transform)\s*="
            r"|^\s*%s\.set_deferred\(\s*[\"'](?:global_)?position"
            r"|^\s*%s\.call_deferred\(\s*[\"']set[\"']\s*,\s*[\"'](?:global_)?position"
            % (var, var, var))
        was_reset = re.compile(
            r"\b%s\.reset_physics_interpolation\(\)"
            r"|\b%s\.call_deferred\(\s*[\"']reset_physics_interpolation[\"']"
            % (var, var))

        add_at = move_at = reset_at = None
        for j in range(i + 1, len(lines)):
            nxt = lines[j]
            if re.match(r"^func\s", nxt):
                break
            if add_at is None and added.search(nxt):
                add_at = j
            if move_at is None and moved.match(nxt):
                move_at = j
            if reset_at is None and was_reset.search(nxt):
                reset_at = j

        if add_at is None or move_at is None:
            continue
        if move_at < add_at:
            continue
        if reset_at is not None and reset_at > move_at:
            continue
        streak_rows.append("%s:%d  '%s' is moved on line %d, after add_child()"
                           % (rel, i + 1, var, move_at + 1))

report("SPAWNS THAT STREAK IN FROM THE WORLD ORIGIN",
       "A node added to the tree and THEN moved. Physics interpolation draws it\n"
       "blended from its authored origin to where it belongs, so it arrives as a\n"
       "trail of ghost copies. Set the position before add_child(), or call\n"
       "reset_physics_interpolation() after moving it.",
       sorted(streak_rows), severity="fail")


# =============================================================================
# 16. TUNING VALUES A REVERT CAN DROP WITHOUT ANYONE NOTICING
# =============================================================================
# THIS CHECK HAS BEEN WRITTEN THREE TIMES AND WAS WRONG TWICE, both times for
# the same reason: it tried to decide from project.godot alone whether the
# frame pacing was correct, and project.godot does not contain that answer.
#
#   v1 REQUIRED run/max_fps, on the theory that a low render cap hid spawns
#      that missed their interpolation reset.
#   v2 FORBADE run/max_fps alongside vsync, on the theory that two limiters
#      beat against each other and walk a tear seam up the screen.
#
# Both were plausible. Neither was checkable here. What settled it was a
# runtime measurement: with max_fps removed, the game ran at 2625 fps on a
# 60 Hz screen — so vsync had never been pacing anything, whatever the mode
# said, and max_fps had been the only real limiter the whole time. v2 would
# have told you to delete the one thing holding the frame rate down.
#
# THE RULE THIS LEAVES: whether vsync works is a property of the machine, the
# driver, and whether the game is running embedded in the editor. It cannot be
# read out of a config file, so this check no longer pretends to. PerfOverlay
# measures it instead — it compares the frame rate against the screen's actual
# refresh rate and says "VSYNC REQUESTED BUT NOT WORKING" when they disagree,
# which is the only honest place for that question to live.
#
# What IS checkable here is a tuning value going missing, which has happened
# once already: a revert dropped physics_ticks_per_second and nothing said so.

timing_rows = []
if "physics_interpolation=true" in PROJECT and "physics_ticks_per_second" not in PROJECT:
    timing_rows.append(
        "project.godot [physics] has no common/physics_ticks_per_second — "
        "falls back to Godot's 60; this project is tuned for 80 and has lost "
        "the line to a revert before")

report("TUNING VALUES A REVERT CAN DROP SILENTLY",
       "A physics tick rate that is gone rather than chosen. It does not error and\n"
       "the game still runs, so the only symptom is that motion feels different and\n"
       "nobody can say when it changed. Frame pacing itself is NOT checked here —\n"
       "see the note above, and read PerfOverlay's fps line for that.",
       timing_rows, severity="fail")


# =============================================================================
# 17. LOCALS THAT SHADOW A BASE-CLASS PROPERTY
# =============================================================================
# `var size` in a Control, `var name` in a Node. Godot reports these itself —
# but only when it reloads the script, so they arrive two at a time over
# several launches in whatever order the boot happens to touch files. This
# lists the whole set at once, which is the only reason it is worth having a
# second copy of a check the engine already does.
#
# They are warnings rather than errors because the code usually still works:
# the local wins inside its own block and the property is simply unreachable
# there. It stops being harmless the moment something in that block meant to
# read the node's real `size` or `name` — at which point it is a bug that
# looks exactly like correct code.

SHADOW_OBJECT = {"name", "owner", "script"}
SHADOW_NODE = SHADOW_OBJECT | {"process_mode", "process_priority", "multiplayer"}
SHADOW_CANVAS = SHADOW_NODE | {"visible", "modulate", "self_modulate",
                               "material", "z_index", "light_mask"}
SHADOW_2D = SHADOW_CANVAS | {"position", "rotation", "scale", "skew",
                             "transform", "global_position", "global_rotation",
                             "global_scale", "global_transform"}
SHADOW_CONTROL = SHADOW_CANVAS | {"size", "position", "rotation", "scale",
                                  "pivot_offset", "custom_minimum_size",
                                  "theme", "tooltip_text", "focus_mode",
                                  "mouse_filter", "global_position"}

# Only the bases this project actually extends. An unknown base contributes
# nothing rather than guessing, so a new one shows up as a gap in coverage
# instead of a wrong finding.
SHADOW_BASES = {
    "Object": SHADOW_OBJECT, "RefCounted": SHADOW_OBJECT,
    "Resource": SHADOW_OBJECT | {"resource_path", "resource_name"},
    "Node": SHADOW_NODE, "CanvasLayer": SHADOW_NODE,
    "CanvasItem": SHADOW_CANVAS,
    "Node2D": SHADOW_2D, "Sprite2D": SHADOW_2D, "AnimatedSprite2D": SHADOW_2D,
    "Area2D": SHADOW_2D, "CharacterBody2D": SHADOW_2D, "RigidBody2D": SHADOW_2D,
    "StaticBody2D": SHADOW_2D, "Marker2D": SHADOW_2D, "Camera2D": SHADOW_2D,
    "TileMapLayer": SHADOW_2D, "CollisionShape2D": SHADOW_2D,
    "Control": SHADOW_CONTROL, "Panel": SHADOW_CONTROL,
    "PanelContainer": SHADOW_CONTROL, "Button": SHADOW_CONTROL,
    "TextureButton": SHADOW_CONTROL, "Label": SHADOW_CONTROL,
    "RichTextLabel": SHADOW_CONTROL, "TextureRect": SHADOW_CONTROL,
    "ColorRect": SHADOW_CONTROL, "NinePatchRect": SHADOW_CONTROL,
    "VBoxContainer": SHADOW_CONTROL, "HBoxContainer": SHADOW_CONTROL,
    "GridContainer": SHADOW_CONTROL, "MarginContainer": SHADOW_CONTROL,
    "ScrollContainer": SHADOW_CONTROL, "CenterContainer": SHADOW_CONTROL,
    "ItemList": SHADOW_CONTROL, "LineEdit": SHADOW_CONTROL,
    "OptionButton": SHADOW_CONTROL, "CheckButton": SHADOW_CONTROL,
    "CheckBox": SHADOW_CONTROL, "HSlider": SHADOW_CONTROL,
    "TabContainer": SHADOW_CONTROL,
}

SHADOW_DECL = re.compile(r"^\s*(?:var|const)\s+(\w+)\b"
                         r"|^\s*for\s+(\w+)\s+in\b"
                         r"|^\s*func\s+\w+\s*\((.*)\)")
SHADOW_PARAM = re.compile(r"(?:^|,)\s*(\w+)\s*(?::|=|$)")

shadow_rows = []
for rel, text in SCRIPTS.items():
    base_match = re.search(r"^extends\s+([\w\.]+)", text, re.M)
    if not base_match:
        continue
    base = base_match.group(1).split(".")[-1]
    props = SHADOW_BASES.get(base)
    if not props:
        continue
    for number, line in enumerate(text.splitlines(), 1):
        code = line.split("#")[0]
        if not code.strip():
            continue
        found_decl = SHADOW_DECL.match(code)
        if not found_decl:
            continue
        if found_decl.group(1):
            names = [found_decl.group(1)]
        elif found_decl.group(2):
            names = [found_decl.group(2)]
        else:
            names = [p for p in SHADOW_PARAM.findall(found_decl.group(3)) if p]
        for local in names:
            if local in props:
                shadow_rows.append("%s:%d  '%s' shadows %s.%s"
                                   % (rel, number, local, base, local))

report("LOCALS THAT SHADOW A BASE-CLASS PROPERTY",
       "A local, loop variable or parameter with the same name as a property the\n"
       "script inherits. Inside that block the property is unreachable, so code\n"
       "meaning to read the node's own size or name silently reads the local.",
       sorted(shadow_rows))


# =============================================================================
# 18. INTEGER DIVISION NOBODY HAS SIGNED FOR
# =============================================================================
# Dividing an int by an int throws the remainder away. Usually that is exactly
# what was wanted — a count of cells, a byte length, a pixel origin — and the
# project already marks those with @warning_ignore("integer_division") plus a
# line saying why. This finds the ones with no such mark, which are either a
# decision nobody wrote down or a genuine mistake.
#
# THE WHOLE VALUE IS IN NOT CRYING WOLF, so three things are excluded:
#   - `/` inside a string literal ("0/100", a URL, "layer_names/2d_physics")
#   - a numerator whose declared type is floating point, where the division
#     is float division and Godot says nothing
#   - anything already carrying @warning_ignore on the line above
#
# Without the first two this check reported eight findings of which one was
# real, and a check like that gets skimmed past for the rest of its life.

# `/ 2` but not `/ 2.0`, and not the `2` of a later decimal.
INT_DIV = re.compile(r"/\s*(\d+)(?![\d.])")
STRING_LITERAL = re.compile(r'"[^"]*"|\'[^\']*\'')
FLOAT_CALL = re.compile(r"float\(|\d+\.\d|delta|_seconds|speed|randf|TAU|PI")
FLOAT_TYPES = {"float", "Vector2", "Vector3", "Vector4", "Rect2",
               "Transform2D", "Color"}
# The identifiers feeding the left side of the `/`.
LEADING_NAME = re.compile(r"(\w+)(?:\.\w+)*\s*$")

int_div_rows = []
for rel, text in SCRIPTS.items():
    lines = text.splitlines()

    # name -> declared type, for the float check below. File-wide rather than
    # per-scope, which can only make this check quieter, never louder.
    declared = {}
    for line in lines:
        typed = re.match(r"^\s*(?:var|const)\s+(\w+)\s*:\s*([\w]+)", line)
        if typed:
            declared[typed.group(1)] = typed.group(2)
            continue
        inferred = re.match(r"^\s*(?:var|const)\s+(\w+)\s*:?=\s*([A-Z]\w*)\(", line)
        if inferred:
            declared[inferred.group(1)] = inferred.group(2)

    for number, line in enumerate(lines, 1):
        code = STRING_LITERAL.sub('""', line.split("#")[0])
        if not INT_DIV.search(code) or FLOAT_CALL.search(code):
            continue

        # Already a recorded decision. Looked for over the preceding few
        # lines rather than just the one above, because @warning_ignore
        # attaches to the STATEMENT and a statement can be wrapped — in
        # settings.gd the annotation sits above the window_set_position(
        # call and the division is on the continuation line under it.
        window = lines[max(0, number - 4):number]
        if any("integer_division" in w for w in window):
            continue

        # A float on the left means float division and no warning.
        floaty = False
        for match in INT_DIV.finditer(code):
            before = code[:match.start()].rstrip().rstrip(")]")
            name = LEADING_NAME.search(before)
            if name and declared.get(name.group(1), "") in FLOAT_TYPES:
                floaty = True
        if floaty:
            continue

        int_div_rows.append("%s:%d  %s" % (rel, number, code.strip()[:56]))

report("INTEGER DIVISION NOBODY HAS SIGNED FOR",
       "int / int discards the remainder. Where that is intended the project says\n"
       "so with @warning_ignore(\"integer_division\") and a reason; these carry no\n"
       "such note, so they are an undocumented decision or a real rounding bug.",
       sorted(int_div_rows))


# =============================================================================
print("=" * 72)
print("  ELUSION PROJECT AUDIT — %s" % ROOT)
print("  %d scripts, %d scenes, %d resources"
      % (len(SCRIPTS), len(SCENES), len(RESOURCES)))
print("=" * 72)
found = emit()
sys.exit(0)
