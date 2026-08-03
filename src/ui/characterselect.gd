# character select screen — allows players to create and select characters
# across 4 slots. each slot is hardcoded to a class (warrior/mage/tank/healer)
# so the class roster is predictable regardless of slot pick order.
#
# button signals are wired through the .tscn editor signal panel — function
# names below must match the connections in characterselect.tscn or the
# buttons will silently fail to respond.
extends Control


# =============================================================================
# CONSTANTS
# =============================================================================

# preloaded reference to the main game scene. preloading here means any
# parse error in elusion.tscn surfaces at characterselect.tscn load time,
# not on first click — easier to catch broken references early.
const ELUSION_SCENE := preload("res://scene/elusion.tscn")

# class assigned to each slot — slot index maps to class name.
# the order here defines which class each slot creates.
const SLOT_CLASSES := ["warrior", "mage", "tank", "healer"]


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# CHANGED: removed the redundant CharacterData.load_data() call that
	# used to run here. its original justification ("CharacterData also
	# loads on autoload init") no longer applies — CharacterData._ready()
	# doesn't load anything at boot anymore (see its class comment); it
	# only loads via load_for_user(), which loginmenu.gd already calls
	# right after a successful login, BEFORE this scene ever runs. by the
	# time we get here, character_slots/account_data are already correct
	# for the logged-in user. reloading again here was not just redundant
	# but appeared to be actively re-triggering signature verification
	# against a freshly round-tripped copy of the same data, which was
	# resetting is_admin even without real tampering.
	update_slot_labels()


# =============================================================================
# SLOT UI REFRESH
# =============================================================================

func update_slot_labels() -> void:
	# loop all 4 slots, populating the label and toggling buttons based on
	# whether the slot contains valid character data. called on _ready and
	# after any create-button press to refresh the new slot's state.
	var labels      = [%label1,        %label2,        %label3,        %label4]
	var create_btns = [%createbutton1, %createbutton2, %createbutton3, %createbutton4]
	var select_btns = [%selectbutton1, %selectbutton2, %selectbutton3, %selectbutton4]

	for i in range(4):
		var slot = CharacterData.character_slots[i]
		var is_valid: bool = _is_slot_valid(slot)

		if is_valid:
			# slot has a character — show name and level, enable select only
			labels[i].text = "%s  |  level: %d" % [slot["character"], slot["level"]]
			create_btns[i].disabled = true
			select_btns[i].disabled = false
		else:
			# slot is empty — show placeholder, enable create only
			labels[i].text = "empty slot"
			create_btns[i].disabled = false
			select_btns[i].disabled = true


func _is_slot_valid(slot) -> bool:
	# returns true if the slot has the minimum data needed to be selectable.
	# guards against null, wrong types, and partial/corrupted save data.
	return slot != null \
		and typeof(slot) == TYPE_DICTIONARY \
		and slot.has("character") \
		and slot.has("level")


# =============================================================================
# CREATE BUTTON HANDLERS
# =============================================================================
# one handler per slot — connected via the editor's signals panel.
# function names below MUST match the connections in characterselect.tscn.

func _on_createbutton1_pressed() -> void:
	_create_in_slot(0)


func _on_createbutton2_pressed() -> void:
	_create_in_slot(1)


func _on_createbutton3_pressed() -> void:
	_create_in_slot(2)


func _on_createbutton4_pressed() -> void:
	_create_in_slot(3)


func _create_in_slot(idx: int) -> void:
	# shared logic for all 4 create buttons. delegates to CharacterData
	# which handles the actual character creation and disk save.
	CharacterData.create_character(idx, SLOT_CLASSES[idx])
	update_slot_labels()


# =============================================================================
# SELECT BUTTON HANDLERS
# =============================================================================
# one handler per slot — connected via the editor's signals panel.

func _on_selectbutton1_pressed() -> void:
	_select_character(0)


func _on_selectbutton2_pressed() -> void:
	_select_character(1)


func _on_selectbutton3_pressed() -> void:
	_select_character(2)


func _on_selectbutton4_pressed() -> void:
	_select_character(3)


func _select_character(idx: int) -> void:
	# validates the slot, sets it as active, saves to disk, and transitions
	# to the main game scene. the player's _ready() will then call
	# CharacterData.load_character_state(self) to pull saved stats into
	# the freshly instanced player.
	var slot = CharacterData.character_slots[idx]
	if not _is_slot_valid(slot):
		print("no character in slot %d to select!" % [idx + 1])
		return

	print("selected %s in slot %d" % [slot["character"], idx + 1])

	# mark this slot as the active character and persist before scene change.
	# without saving here, a crash between scene transitions could lose the
	# selection.
	CharacterData.active_character_index = idx
	CharacterData.save_data()

	get_tree().change_scene_to_packed(ELUSION_SCENE)
