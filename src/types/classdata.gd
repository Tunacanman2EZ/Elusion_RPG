# classdata.gd — one playable class's stat curve, as data.
#
# Third and last of the same pattern: ItemData, EnemyData, ClassData. Authored
# in the editor, saved under data/classes/, exported into gamedata.json, read by
# Godot and by Flask.
#
# WHY THIS ONE MATTERS MOST
# -------------------------
# The server owns level and xp now, and rolls every loot drop. It still takes the
# client's word for max_hp, because a character's maximum health is
#
#     hp_base + (level - 1) * hp_per_lvl
#
# and those two numbers lived inside each class's _set_stat_curve() as literals.
# The server knew your level and your class and STILL could not work out your
# health, so a modified client could declare max_hp = 999999 and the server had
# nothing to check it against.
#
# With the curve as data the server computes the answer itself, and max_hp joins
# level and xp on the list of things the client no longer gets to assert.
#
# WHAT IS DELIBERATELY NOT HERE
# -----------------------------
# Movement speed, attack cooldowns, ability costs, the spell scenes. Same line as
# EnemyData: if the server needs it to decide what is true about a character, it
# is data. Otherwise it stays in the script where it is read.
@tool
extends Resource
class_name ClassData


# =============================================================================
# IDENTITY
# =============================================================================

# Matches VALID_CLASSES in app.py and the string player.gd puts in
# character_name — "warrior", "mage", "tank", "healer". The server looks the
# curve up by this, so a mismatch means it falls back to trusting the client.
@export var class_id: String = ""

@export var display_name: String = ""


# =============================================================================
# STAT CURVE
# =============================================================================
# Each maximum is base + (level - 1) * per_level. Level 1 gets exactly the base,
# which is why the -1 is there and why it has to be in both implementations
# identically — see Player._recompute_max_stats().

@export var hp_base: int = 20
@export var hp_per_lvl: int = 0

@export var mana_base: int = 0
@export var mana_per_lvl: int = 0

@export var stam_base: int = 0
@export var stam_per_lvl: int = 0
