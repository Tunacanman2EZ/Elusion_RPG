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

# The area the game starts in, BY NAME - not a preload any more.
#
# THE PRELOAD WAS WHAT MADE THE LOGIN SCREEN SLOW. loginmenu.tscn exports this
# scene, so preloading the town here put the town, the field, the HUD, every
# panel and about sixty scripts in front of the login screen's first frame -
# 1.8 of the 2.6 seconds from launch to a login box, measured cold. The reason
# it was a preload - "a broken elusion.tscn shows up early" - is the suite's
# job now: _test_the_world_loads_in_the_background() walks the login screen's
# whole load and loads the town itself.
#
# The login screen starts the town loading in the background (see
# AreaRegistry.prefetch), so by the time a character is picked it is
# normally already there.
const WORLD_AREA := "elusion"

# Set once a character has been picked, so a second click while the town
# finishes loading cannot start a second trip.
var _entering: bool = false

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
	# revoking permissions even without real tampering.
	#
	# Normally already under way from the login screen, and then a no-op. This
	# covers arriving here any other way - back from the world, say.
	AreaRegistry.prefetch(WORLD_AREA)
	_build_logout_row()
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
			labels[i].text = slot_text(slot, SLOT_CLASSES[i])
			create_btns[i].disabled = true
			select_btns[i].disabled = false
		else:
			# slot is empty — show placeholder, enable create only
			labels[i].text = "empty slot"
			create_btns[i].disabled = false
			select_btns[i].disabled = true


static func slot_text(slot: Dictionary, slot_class: String) -> String:
	"""What an occupied slot says. A character is named after its class, and
	the class is already the heading over the slot - "warrior  |  level: 1"
	under WARRIOR said it twice. A character with a name of its own still
	shows it."""
	var level: int = int(slot.get("level", 1))
	var name_of: String = str(slot.get("character", ""))
	if name_of == "" or name_of.to_lower() == slot_class.to_lower():
		return "Level %d" % level
	return "%s  |  Level %d" % [name_of, level]


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
	#
	# ONE TRIP. Checked here, not only in _enter_world(): by then a second
	# click would already have changed which character is active.
	if _entering:
		return
	var slot = CharacterData.character_slots[idx]
	if not _is_slot_valid(slot):
		if OS.is_debug_build():
			# THE INDEX, NOT THE INDEX PLUS ONE. See the note in the print below.
			print("[CHAR] slot %d is empty — nothing to select" % [idx])
		return

	if OS.is_debug_build():
		# summarises what was actually loaded, not just which slot was clicked.
		# "selected warrior in slot 1" told you the click landed; it could not
		# tell you the save came back with the right level, gold or inventory,
		# which is the thing that actually goes wrong after a save-format
		# change. Reading it here means a bad load is visible at the character
		# screen instead of surfacing later as a confused "where did my stuff
		# go" in the world.
		# COUNTING, CAREFULLY. The saved inventory is one entry per CELL, not
		# per item — InventoryContainer.to_save_array() appends null for every
		# empty cell to keep positions stable across a save/load. Reporting
		# .size() as "items" said "20 items" with one potion in the bag.
		#
		# Occupied cells are the non-null entries. Item count is the sum of
		# their quantities, because one entry can be a stack of 16.
		#
		# BUT .size() IS NOT THE BAG'S CAPACITY, which is what this used to
		# claim. An empty ARRAY and a bag of twenty empty CELLS are different
		# saves, and both are normal: gameover.gd assigns [] outright when you
		# decline a revive, and a fresh character starts the same way. So a
		# perfectly healthy load printed "0 items in 0/0 slots", which reads
		# like the bag evaporated — on the death-and-reselect path, which is
		# the one you walk through most while testing.
		#
		# The real capacity is grid_width * grid_height on the container, and
		# the container does not exist yet at this screen. So this reports what
		# it can actually see, and names the empty case rather than dressing it
		# up as a ratio.
		#
		# quantity goes through int() rather than being read raw: a quantity
		# that once became a float stays a float for the life of that save
		# (see _capture_inventory in characterdata.gd).
		var inventory: Variant = slot.get("inventory", [])
		var cells_saved: int = 0
		var cells_used: int = 0
		var item_count: int = 0
		if inventory is Array:
			var entries: Array = inventory
			cells_saved = entries.size()
			for entry in entries:
				if entry is Dictionary:
					cells_used += 1
					item_count += int(entry.get("quantity", 1))

		var bag: String = "empty bag"
		if cells_saved > 0:
			bag = "%d items in %d/%d cells" % [item_count, cells_used, cells_saved]

		# THE SAME NUMBER EVERY OTHER LOG USES, and it was not.
		#
		# This printed idx + 1, so the character that `saves.slot`, every
		# server log line, deathwatch.py and every API payload call slot 0
		# appeared here as "slot 1". Reading the two side by side while
		# chasing a save bug, that is a number you have to keep converting -
		# and the first time you forget, you are looking at the wrong
		# character's row.
		#
		# A ONE-BASED SLOT NUMBER IS A UI DECISION, and this is not the UI.
		# The buttons on this screen can say "Slot 1" if they ever say
		# anything; a debug line exists to be matched against the server's,
		# so it uses the server's numbering.
		print("[CHAR] %s slot %d — lv %d, %d gold, %s" % [
			slot["character"],
			idx,
			int(slot.get("level", 1)),
			int(slot.get("gold", 0)),
			bag,
		])

	# mark this slot as the active character and persist before scene change.
	# without saving here, a crash between scene transitions could lose the
	# selection.
	CharacterData.active_character_index = idx
	CharacterData.save_data()

	_enter_world(idx)


func _enter_world(idx: int) -> void:
	"""Into the town - once it has loaded, which it almost always has.

	WAITS BY THE FRAME, NOT BY BLOCKING. If the player picked a character
	faster than the town loaded, scene_for() would freeze the window until it
	finished; waiting here keeps the screen drawing and says why."""
	if _entering:
		return
	_entering = true

	if not AreaRegistry.is_ready(WORLD_AREA):
		_show_loading(idx)
		while not AreaRegistry.is_ready(WORLD_AREA) and AreaRegistry.is_loading(WORLD_AREA):
			await get_tree().process_frame
			# PAST AN AWAIT. Logging out or closing the window frees this screen.
			if not is_instance_valid(self) or not is_inside_tree():
				return
		# NOT LOADING AT ALL - a build without threads loads nothing ahead
		# (AreaRegistry.loads_in_background()), so scene_for() below holds the
		# screen while it loads. It must hold on this label, not on a click that
		# seems to have done nothing - and that takes TWO frames: the first
		# resumes inside the frame the click arrived in, before that frame is
		# drawn. Watched in Chromium: with one, the label never reached the screen.
		if not AreaRegistry.is_ready(WORLD_AREA):
			for _frame in 2:
				await get_tree().process_frame
				if not is_instance_valid(self) or not is_inside_tree():
					return

	var world: PackedScene = AreaRegistry.scene_for(WORLD_AREA)
	if world == null:
		# The error naming the file already came from AreaRegistry. Say it
		# here too, where the player is looking, and let them try again.
		_entering = false
		update_slot_labels()
		_slot_labels()[idx].text = "The world failed to load - try again"
		return

	# Everything else loads behind the player now, so no door waits on the disk.
	AreaRegistry.prefetch_all()
	get_tree().change_scene_to_packed(world)


func _slot_labels() -> Array:
	return [%label1, %label2, %label3, %label4]


func _show_loading(idx: int) -> void:
	_slot_labels()[idx].text = "Loading the world..."
	for button in [%createbutton1, %createbutton2, %createbutton3, %createbutton4,
			%selectbutton1, %selectbutton2, %selectbutton3, %selectbutton4]:
		button.disabled = true


# =============================================================================
# LOG OUT
# =============================================================================
# THIS SCREEN HAD NO WAY OUT. With "Remember me" on, reopening the game comes
# straight here, and the only door back to the login screen was to walk into
# the world and press Logout on the HUD - so a player who wanted another
# account, or to sign out of a shared computer, had to enter the game first.

const LOGIN_MENU_PATH := "res://scene/ui/menus/loginmenu.tscn"

var logout_button: Button = null
var _leaving: bool = false


func _build_logout_row() -> void:
	if logout_button != null:
		return
	var grid: Node = get_node_or_null("centercontainer/mainpanel/margincontainer/vboxcontainer/gridcontainer")
	if grid == null:
		return
	var column: Node = grid.get_parent()
	var row := HBoxContainer.new()
	row.name = "logoutrow"
	row.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(row)
	column.move_child(row, grid.get_index() + 1)
	logout_button = Button.new()
	logout_button.name = "logoutbutton"
	logout_button.text = "Log out"
	logout_button.tooltip_text = "Back to the login screen. On a shared computer, this is how you leave."
	logout_button.custom_minimum_size = Vector2(110, 0)
	row.add_child(logout_button)
	logout_button.pressed.connect(_on_logout_pressed)


func _on_logout_pressed() -> void:
	if _leaving or _entering:
		return
	_leaving = true
	logout_button.disabled = true
	# The same order as the HUD's Logout: anything still waiting to be saved
	# goes first, then the server's session, then the screen.
	await CharacterData.finish_saving()
	CharacterData.clear_current_user()
	await Api.logout()
	if not is_instance_valid(self) or not is_inside_tree():
		return
	get_tree().change_scene_to_file(LOGIN_MENU_PATH)
