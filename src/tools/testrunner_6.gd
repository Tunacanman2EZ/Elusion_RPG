# testrunner_6.gd - part 6 of the suite (testrunner.gd says how it is
# split): 34 tests, _test_notices_fade_and_login_is_quiet to _test_the_mage_kit.
extends "res://src/tools/testrunner_5.gd"


func _test_notices_fade_and_login_is_quiet() -> void:
	section("NOTICES — the box fades, a login's backlog is not news, and nothing is lost")

	var hud_script: Script = load("res://src/ui/characterhud.gd") as Script
	check("characterhud.gd loads", hud_script != null and hud_script.can_instantiate())
	if hud_script == null or not hud_script.can_instantiate():
		return
	var hud: Object = hud_script.new()
	hud._build_message_box()
	var box: Control = hud.message_box
	var rows: Control = hud.message_rows
	check("the box starts hidden", box != null and not box.visible)
	if box == null or rows == null:
		hud.free()
		return

	var show_ms: int = int(hud_script.MESSAGE_SHOW_SECONDS * 1000.0)
	var fade_ms: int = int(hud_script.MESSAGE_FADE_SECONDS * 1000.0)
	check("a notice stays up long enough to read and not much longer",
		show_ms >= 5000 and show_ms <= 15000 and fade_ms > 0, [show_ms, fade_ms])

	# ---- it fades ----
	hud._push_message("The server is open again.", Color.WHITE)
	check("a live notice pops the box", rows.get_child_count() == 1 and box.visible)
	# A PLACEHOLDER when nothing was pushed, so a broken push fails the checks
	# below by name instead of unwinding the section on a null.
	var line: Control = rows.get_child(0) as Control if rows.get_child_count() > 0 else Control.new()
	var shown: int = int(line.get_meta("shown_msec", -1))
	check("and is stamped with when it went up", shown >= 0, shown)

	hud._age_messages(shown + show_ms - 1)
	check("it is fully there until its time is up",
		rows.get_child_count() == 1 and is_equal_approx(line.modulate.a, 1.0) and box.visible)
	hud._age_messages(shown + show_ms + floori(fade_ms / 2.0))
	check("then it fades", line.modulate.a > 0.2 and line.modulate.a < 0.8, line.modulate.a)
	hud._age_messages(shown + show_ms + fade_ms + 1)
	check("THEN IT IS GONE", rows.get_child_count() == 0, rows.get_child_count())
	check("and an empty box hides itself", not box.visible)

	# EACH LINE ON ITS OWN CLOCK, not the box's. A notice that arrived five
	# seconds after another must not vanish with it.
	for leftover in rows.get_children():
		rows.remove_child(leftover)
		leftover.queue_free()
	hud._push_message("first", Color.WHITE)
	hud._push_message("second", Color.WHITE)
	if rows.get_child_count() == 2:
		var first: Control = rows.get_child(0) as Control
		var second: Control = rows.get_child(1) as Control
		second.set_meta("shown_msec", int(first.get_meta("shown_msec")) + 5000)
		hud._age_messages(int(first.get_meta("shown_msec")) + show_ms + fade_ms + 1)
		check("each line fades on its own clock",
			rows.get_child_count() == 1 and rows.get_child(0) == second and box.visible,
			rows.get_child_count())
		hud._age_messages(int(second.get_meta("shown_msec")) + show_ms + fade_ms + 1)
	else:
		check("each line fades on its own clock", false,
			"two pushes left %d lines" % rows.get_child_count())
	for leftover in rows.get_children():
		rows.remove_child(leftover)
		leftover.queue_free()

	var hud_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/characterhud.gd"))
	var proc: int = _first_code_index(hud_src, "func _process(", 0)
	var guard: int = _first_code_index(hud_src, "if active_character == null:", proc)
	var ages: int = _first_code_index(hud_src, "_age_messages(", proc)
	check("the HUD ages the box every frame, before the no-character guard",
		ages != -1 and guard != -1 and ages < guard,
		"age %d, guard %d - below the guard, a notice in a menu never fades" % [ages, guard])

	# ---- a login's backlog is history ----
	var before: int = hud._unlogged_lines.size()
	hud._read_broadcast_messages([
		{"body": "Update in progress - please come back later.", "kind": "system", "at": 1700000000},
		{"body": "Everyone has been moved to elusion.", "kind": "system", "at": 1700000100},
		{"body": "The server is open again.", "kind": "system", "at": 1700000200},
	], false)
	check("the catch-up does not pop the box", rows.get_child_count() == 0 and not box.visible,
		rows.get_child_count())
	check("BUT IT IS STILL RECORDED, every line of it",
		hud._unlogged_lines.size() == before + 3, hud._unlogged_lines.size() - before)
	# NULL-SAFE, and the sabotage that drops the buffer is why: indexing an
	# empty list raised, unwound the rest of this section, and the run lost
	# fifteen checks while reporting one red. Each read below is guarded.
	var said: Variant = hud._unlogged_lines[before] if hud._unlogged_lines.size() > before else null
	check("with the time it was said, not the time it was read",
		said is Dictionary and int(said["at"]) == 1700000000, said)
	hud._read_broadcast_messages([{"body": "Tunacan has gone hostile.", "kind": "system",
		"at": 1700000300}], true)
	check("while a notice arriving after that is announced", rows.get_child_count() == 1)

	# THE POLL'S ANSWER, DRIVEN. These two were read off the source while the
	# handling sat inside the request; _apply_broadcast() is the handling on its
	# own now, so they are what happens rather than what is written.
	for leftover in rows.get_children():
		rows.remove_child(leftover)
		leftover.queue_free()
	hud._broadcast_cursor = 0
	hud._apply_broadcast({"latest_id": 40, "messages": [
		{"body": "A week-old restart notice.", "kind": "system", "at": 1700000400}]})
	check("the poll announces only once it has caught up - cursor past 0",
		rows.get_child_count() == 0, "a poll from cursor 0 is answered with a week of notices")
	check("and asks BEFORE it moves the cursor, or the first answer counts as caught up",
		hud._broadcast_cursor == 40, hud._broadcast_cursor)
	hud._apply_broadcast({"latest_id": 41, "messages": [
		{"body": "Tunacan has gone hostile.", "kind": "system", "at": 1700000500}]})
	check("and the next answer, arriving after, is news", rows.get_child_count() == 1
		and hud._broadcast_cursor == 41, rows.get_child_count())
	var poll: int = _first_code_index(hud_src, "func _on_broadcast_poll_timeout(", 0)
	var poll_end: int = _first_code_index(hud_src, "\nfunc ", poll + 1)
	check("and the poll hands its answer to _apply_broadcast()",
		_within(_first_code_index(hud_src, "_apply_broadcast(data)", poll), poll_end) != -1)

	# ---- nothing is lost before chat exists ----
	var client_line_at: int = int(Time.get_unix_time_from_system())
	hud._push_message("Lost connection.", Color.RED)
	var last: Variant = hud._unlogged_lines.back() if not hud._unlogged_lines.is_empty() else null
	check("a notice this client made itself is stamped now, not at the flush",
		last is Dictionary and int(last["at"]) >= client_line_at, last)

	var stub_script := GDScript.new()
	stub_script.source_code = "extends Control\nvar got: Array = []\n" \
		+ "func push_system_line(text: String, _c: Color, at: int = 0) -> void:\n" \
		+ "\tgot.append([text, at])\n"
	stub_script.reload()
	var chat: Control = Control.new()
	chat.set_script(stub_script)
	chat.visible = false
	var waiting: int = hud._unlogged_lines.size()
	hud.chat_panel = chat
	hud._flush_unlogged_lines()
	check("when chat is built, everything that waited is written into it",
		chat.got.size() == waiting, [chat.got.size(), waiting])
	check("in order, with the server's own time",
		chat.got.size() > before and chat.got[before] == ["Update in progress - please come back later.", 1700000000],
		chat.got.slice(before, before + 1))
	check("and none of it is written twice", hud._unlogged_lines.is_empty(),
		hud._unlogged_lines.size())
	var toggle: int = _first_code_index(hud_src, "func toggle_chat(", 0)
	var built: int = _first_code_index(hud_src, "add_child(chat_panel)", toggle)
	var flushed: int = _first_code_index(hud_src, "_flush_unlogged_lines()", toggle)
	check("and toggle_chat() flushes as it builds chat",
		built != -1 and flushed != -1 and flushed > built
			and _within(flushed, _first_code_index(hud_src, "\nfunc ", toggle + 1)) != -1,
		[built, flushed])

	# ---- with chat there ----
	var got_before: int = chat.got.size()
	var rows_before: int = rows.get_child_count()
	hud._push_message("hidden chat", Color.WHITE)
	check("with chat built but closed, a notice is logged AND announced",
		chat.got.size() == got_before + 1 and rows.get_child_count() == rows_before + 1,
		[chat.got.size() - got_before, rows.get_child_count() - rows_before])
	chat.visible = true
	rows_before = rows.get_child_count()
	hud._push_message("open chat", Color.WHITE)
	check("with chat open, it is logged and not announced twice",
		chat.got.size() == got_before + 2 and rows.get_child_count() == rows_before)
	hud._age_messages(Time.get_ticks_msec())
	check("and the box stands down while chat is up, even with lines in it",
		rows.get_child_count() > 0 and not box.visible)
	chat.visible = false
	hud._age_messages(Time.get_ticks_msec())
	check("and comes back when chat closes, if anything is still fresh", box.visible)

	# ---- the waiting list is bounded ----
	hud.chat_panel = null
	for i in 60:
		hud._push_message("notice %d" % i, Color.WHITE, 0, false)
	check("notices waiting for chat are capped",
		hud._unlogged_lines.size() == hud_script.UNLOGGED_KEPT, hud._unlogged_lines.size())
	var oldest: Variant = hud._unlogged_lines[0] if not hud._unlogged_lines.is_empty() else null
	check("oldest dropped first",
		oldest is Dictionary and str(oldest["text"]) == "notice %d" % (60 - hud_script.UNLOGGED_KEPT),
		oldest)

	chat.free()
	hud.free()
	print("  %.0fs up, %.1fs to fade; a login's backlog goes to the log, not the screen"
		% [hud_script.MESSAGE_SHOW_SECONDS, hud_script.MESSAGE_FADE_SECONDS])


# =============================================================================
# THE HOTBAR HOLDS ITEMS
# =============================================================================
# Asked for as "make items travel instead of staying on one screen - we built
# an equipment screen to solve this problem". The keys used to hold an item_id
# pointing into the bag, so a potion showed in its bag cell AND on its key.
# Now each key holds the stack itself, as the backpack's cells 20-29, and
# dragging one onto a key moves it the way equipping moves a piece.
#
# The keys are ten (1-9 then 0), and that part is unchanged from the section
# this replaces: the counts, the key mapping, a real key press, and the frame
# hugging the slots are all still checked below.
#
# BEHAVIOURAL, WITH A REAL CONTAINER AND A REAL BAR. The items are two
# synthetic ItemData registered for the duration and removed after, so none of
# this needs the private art pack - it ran as a skip-shaped hole before.

func _test_the_hotbar_holds_items() -> void:
	section("HOTBAR — ten keys that hold their items, 1-9 then 0")

	# ---- ten keys ----
	check("the hotbar is ten keys", Hotbar.SLOT_COUNT == 10, Hotbar.SLOT_COUNT)
	check("there is one key per slot",
		Hotbar.SLOT_KEYS.size() == Hotbar.SLOT_COUNT, Hotbar.SLOT_KEYS.size())
	var distinct: Dictionary = {}
	for k in Hotbar.SLOT_KEYS:
		distinct[k] = true
	check("and no key fires two slots",
		distinct.size() == Hotbar.SLOT_KEYS.size(), Hotbar.SLOT_KEYS)
	var misrouted: Array = []
	for i in Hotbar.SLOT_KEYS.size():
		if Hotbar.slot_for_key(Hotbar.SLOT_KEYS[i]) != i:
			misrouted.append("%s -> %d" % [OS.get_keycode_string(Hotbar.SLOT_KEYS[i]),
				Hotbar.slot_for_key(Hotbar.SLOT_KEYS[i])])
	check("every key fires its own slot", misrouted.is_empty(), misrouted)
	# BY NAME, because 0 is the one that arithmetic gets wrong: KEY_0 sits one
	# BELOW KEY_1, so `keycode - KEY_1` sends it to slot -1.
	check("0 fires the tenth slot", Hotbar.slot_for_key(KEY_0) == 9,
		Hotbar.slot_for_key(KEY_0))
	check("a letter fires nothing", Hotbar.slot_for_key(KEY_Q) == -1,
		Hotbar.slot_for_key(KEY_Q))

	# ---- fixtures ----
	var potion := ItemData.new()
	potion.item_id = _HB_POTION
	potion.display_name = "Test Potion"
	potion.stackable = true
	potion.max_stack = 20
	var sword := ItemData.new()
	sword.item_id = _HB_SWORD
	sword.display_name = "Test Sword"
	ItemRegistry._items[_HB_POTION] = potion
	ItemRegistry._items[_HB_SWORD] = sword

	var packed: PackedScene = load("res://scene/ui/hotbar.tscn") as PackedScene
	check("hotbar.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		ItemRegistry._items.erase(_HB_POTION)
		ItemRegistry._items.erase(_HB_SWORD)
		return
	var bar: Hotbar = packed.instantiate() as Hotbar
	var bag := InventoryContainer.new()
	add_child(bag)
	add_child(bar)
	await get_tree().process_frame

	var grid: int = bag.capacity
	var carry: int = grid + Hotbar.SLOT_COUNT
	check("the bag's grid is the server's twenty", grid == 20, grid)

	# COUNTED, NOT LOOKED UP BY NAME. A lookup of slot1..slot<SLOT_COUNT> passes
	# on a scene with an eleventh slot nobody can fire.
	var row: Node = bar.get_node_or_null("margin/slots")
	var drawn: int = 0
	if row != null:
		for child in row.get_children():
			if child is HotbarSlot:
				drawn += 1
	check("the bar draws exactly SLOT_COUNT keys", drawn == Hotbar.SLOT_COUNT,
		"%d drawn, %d keys" % [drawn, Hotbar.SLOT_COUNT])
	check("and resolves every one of them",
		bar.slots.size() == Hotbar.SLOT_COUNT and not bar.slots.has(null), bar.slots)

	# ---- the keys arrive with the bag, even before the bar is attached ----
	# The HUD loads the bag and THEN wires the hotbar. Cells 20-29 in that first
	# load must be kept, not dropped for want of a slot to put them in.
	bag.load_save_array(_hb_cells({3: [_HB_SWORD, 1], grid + 1: [_HB_POTION, 5]}, carry))
	var kept: Array = bag.to_save_array()
	check("a carry loaded before the hotbar attaches keeps all thirty cells",
		kept.size() == carry, kept.size())
	check("including what is on key 2",
		kept.size() > grid + 1 and kept[grid + 1] is Dictionary
			and str(kept[grid + 1].get("item_id", "")) == _HB_POTION, kept.slice(grid))

	bar.set_inventory_container(bag)
	var key: Array = bar.slots
	check("attached, the backpack owns thirty cells", bag.slots.size() == carry,
		bag.slots.size())
	check("and key 2 IS cell 21, holding the five potions",
		bag.get_slot_at(grid + 1) == key[1] and _hb_holds(key[1], _HB_POTION, 5),
		key[1].stack.quantity if not key[1].is_empty() else "empty")
	var misnumbered: Array = []
	for i in bag.slots.size():
		if bag.slots[i].slot_index != i:
			misnumbered.append("%d says %d" % [i, bag.slots[i].slot_index])
	check("every cell's slot_index is its position, keys included",
		misnumbered.is_empty(), misnumbered)
	check("every key knows the backpack is its container, not the bar's row",
		key.all(func(s: HotbarSlot) -> bool: return s.home_container == bag))

	# ---- a server answer lands on the keys ----
	bag.load_server_array(_hb_cells({grid + 5: [_HB_POTION, 4]}, carry))
	check("a server layout moves the potions to key 6",
		_hb_holds(key[5], _HB_POTION, 4) and key[1].is_empty(),
		[key[1].is_empty(), key[5].is_empty()])

	# ---- dragging moves, it does not copy ----
	var changes: Array = [0]
	var on_change := func() -> void: changes[0] += 1
	bag.inventory_changed.connect(on_change)

	var cell0: InventorySlot = bag.get_slot_at(0)
	cell0._drop_data(Vector2.ZERO, _hb_drag(key[5]))
	check("dragging key 6 onto bag cell 0 moves the potions into the bag",
		_hb_holds(cell0, _HB_POTION, 4))
	check("AND OFF THE KEY - one place, not two", key[5].is_empty())

	key[0]._drop_data(Vector2.ZERO, _hb_drag(cell0))
	check("dragging them back onto key 1 empties the bag cell",
		_hb_holds(key[0], _HB_POTION, 4) and cell0.is_empty())

	bag.get_slot_at(1).set_stack(ItemStack.new(potion, 3))
	key[0]._drop_data(Vector2.ZERO, _hb_drag(bag.get_slot_at(1)))
	check("more of the same merges onto the key's stack",
		_hb_holds(key[0], _HB_POTION, 7) and bag.get_slot_at(1).is_empty())

	var cell3: InventorySlot = bag.get_slot_at(3)
	cell3.set_stack(ItemStack.new(sword, 1))
	key[0]._drop_data(Vector2.ZERO, _hb_drag(cell3))
	check("something different swaps with it",
		_hb_holds(key[0], _HB_SWORD, 1) and _hb_holds(cell3, _HB_POTION, 7))

	# KEY TO KEY, and counted on its own: neither end is a bag cell, so the only
	# way the backpack hears about it is through the keys' own wiring.
	changes[0] = 0
	key[4]._drop_data(Vector2.ZERO, _hb_drag(key[0]))
	check("key to key moves too", _hb_holds(key[4], _HB_SWORD, 1) and key[0].is_empty())
	check("and a change made entirely on the keys reaches the save",
		changes[0] > 0, changes[0])

	bag._drop_data(Vector2.ZERO, _hb_drag(key[4]))
	check("dropped in a gap in the bag, a key's stack lands in a BAG cell",
		key[4].is_empty() and _hb_holds(bag.get_slot_at(0), _HB_SWORD, 1),
		bag.get_slot_at(0).stack.data.item_id if not bag.get_slot_at(0).is_empty() else "empty")

	# AND A FULL BAG IS FULL. The keys are cells too, and after the grid in
	# `slots`, so "the first empty cell" would happily be key 1.
	for i in range(grid):
		if bag.get_slot_at(i).is_empty():
			bag.get_slot_at(i).set_stack(ItemStack.new(sword, 1))
	key[8].set_stack(ItemStack.new(potion, 2))
	bag._drop_data(Vector2.ZERO, _hb_drag(key[8]))
	check("into a full bag's gap, a key's stack stays on its key",
		_hb_holds(key[8], _HB_POTION, 2) and key[0].is_empty(),
		[key[0].is_empty(), key[8].is_empty()])
	for i in range(grid):
		bag.get_slot_at(i).clear_stack()
	key[8].clear_stack()
	bag.inventory_changed.disconnect(on_change)

	# ---- the keys are not the bag's for everything ----
	bag.set_slot_type("bank")
	check("retyping the grid leaves the keys as keys",
		key.all(func(s: HotbarSlot) -> bool: return s.slot_type == HotbarSlot.HOTBAR_SLOT_TYPE)
			and cell0.slot_type == "bank")
	bag.set_slot_type("inventory")

	# ---- using a key spends the key ----
	key[2].set_stack(ItemStack.new(potion, 2))
	bag.get_slot_at(2).set_stack(ItemStack.new(potion, 6))
	var used: Array = []
	var on_used := func(s: HotbarSlot) -> void: used.append(s)
	bar.slot_used.connect(on_used)
	var relayed: Array = [0]
	var on_relay := func(_s: InventorySlot) -> void: relayed[0] += 1
	bag.slot_right_clicked.connect(on_relay)
	var press := InputEventKey.new()
	press.keycode = KEY_3
	press.pressed = true
	bar._unhandled_input(press)
	check("pressing 3 hands over key 3 itself, not the bag cell with the same potion",
		used.size() == 1 and used[0] == key[2], used)
	used.clear()
	var held := InputEventKey.new()
	held.keycode = KEY_3
	held.pressed = true
	held.echo = true
	bar._unhandled_input(held)
	check("holding it does not drink the stack", used.is_empty(), used)
	key[2].slot_right_clicked.emit(key[2])
	check("a right-click on a key uses it once",
		used.size() == 1 and used[0] == key[2], used.size())
	check("and is not ALSO relayed as a bag right-click, which would use it twice",
		relayed[0] == 0, relayed[0])
	used.clear()
	var finger_down := InputEventScreenTouch.new()
	finger_down.index = 3
	finger_down.pressed = true
	finger_down.position = Vector2(20, 20)
	key[2].gui_input.emit(finger_down)
	var finger_up := InputEventScreenTouch.new()
	finger_up.index = 3
	finger_up.position = Vector2(22, 21)
	key[2].gui_input.emit(finger_up)
	var tapped_once: bool = used.size() == 1 and used[0] == key[2]
	used.clear()
	key[2].gui_input.emit(finger_down)
	finger_up.position = Vector2(80, 20)
	key[2].gui_input.emit(finger_up)
	check("on a touch screen a tap on a key uses it, as a right-click does - and a finger slid off it is the drag, not a use (0.53.0)",
		tapped_once and used.is_empty() and relayed[0] == 0, [tapped_once, used.size()])
	used.clear()
	bar.slot_used.disconnect(on_used)
	bag.slot_right_clicked.disconnect(on_relay)

	bag.remove_quantity_at(key[2].slot_index, 1)
	check("the backpack's own removal reaches a key by its cell",
		_hb_holds(key[2], _HB_POTION, 1) and _hb_holds(bag.get_slot_at(2), _HB_POTION, 6))

	# ---- the trash takes a key's stack ----
	var trash_script: Script = load("res://src/ui/inventory/trashslot.gd")
	var trash := PanelContainer.new()
	trash.set_script(trash_script)
	add_child(trash)
	check("the trash accepts a key's stack now that a key holds one",
		trash._can_drop_data(Vector2.ZERO, _hb_drag(key[2])))
	var trashed: Array = [0]
	var on_trashed := func() -> void: trashed[0] += 1
	bag.inventory_changed.connect(on_trashed)
	trash._pending_source_slot = key[2]
	trash._pending_stack = key[2].stack.duplicate_stack()
	trash._on_delete_confirmed()
	check("and deleting it empties the key",
		key[2].is_empty() and not (bag.to_save_array()[grid + 2] is Dictionary))
	# THROUGH THE BACKPACK. A key's parent is the bar's row, which has no
	# request_discard(), and clearing the slot there would tell nobody - the key
	# would look empty and the item would come back on the next load.
	check("THROUGH THE BACKPACK THAT ASKS THE SERVER, not by clearing the slot quietly",
		trashed[0] > 0, trashed[0])
	bag.inventory_changed.disconnect(on_trashed)
	trash.queue_free()

	# ---- the save carries the keys ----
	key[7].set_stack(ItemStack.new(potion, 9))
	var saved: Array = bag.to_save_array()
	check("a save sends every carried cell", saved.size() == carry, saved.size())
	check("with the keys in their own places",
		saved[grid + 7] is Dictionary and int(saved[grid + 7].get("quantity", 0)) == 9,
		saved.slice(grid))

	# ---- a partial set of keys is refused, not shifted ----
	var other := InventoryContainer.new()
	add_child(other)
	await get_tree().process_frame
	other.load_save_array(_hb_cells({grid + 3: [_HB_SWORD, 1]}, carry))
	var gappy: Array = key.duplicate()
	gappy[1] = null
	# The ERROR this prints is the refusal, and is expected in a green run.
	other.attach_remote_slots(gappy)
	check("a hotbar with a key missing is not attached at all",
		other.slots.size() == grid, other.slots.size())
	check("and what was on the keys is still kept for the save",
		other.to_save_array().size() == carry
			and other.to_save_array()[grid + 3] is Dictionary)
	other.queue_free()

	# ---- the wire: no hotbar list either way ----
	var storage := ServerStorage.new()
	var body: Dictionary = storage._save_body(0, {"character": "warrior",
		"hotbar_assignments": ["x", "", ""]})
	check("a save never sends the retired hotbar list", not body.has("hotbar"), body)
	var loaded_slot: Dictionary = storage._slot_from_server({"class_id": "warrior",
		"hotbar": ["x"], "inventory": _hb_cells({grid + 1: [_HB_POTION, 2]}, carry)})
	check("a load makes no hotbar list either",
		not loaded_slot.has("hotbar_assignments"), loaded_slot.keys())
	check("and hands the keys over inside the inventory",
		(loaded_slot.get("inventory", []) as Array).size() == carry)

	# ---- the requests name the cell ----
	# Text, because these reach the network: the server half of each is tested
	# in test_api.py's "THE HOTBAR IS CARRIED".
	var screen: String = _code_only(FileAccess.get_file_as_string(
		"res://src/ui/inventory/inventoryscreen.gd"))
	var at: int = _first_code_index(screen, "func _use_consumable(", 0)
	var end: int = _first_code_index(screen, "\nfunc ", at + 1)
	var post: int = _first_code_index(screen, "/api/character/consume", at)
	check("drinking names the cell drunk from",
		_within(post, end) != -1 and _within(_first_code_index(screen, "\"position\": slot.slot_index", post), end) != -1)
	var bank_src: String = _code_only(FileAccess.get_file_as_string(
		"res://src/ui/bank/bankinventory.gd"))
	at = _first_code_index(bank_src, "func _on_transfer_requested(", 0)
	end = _first_code_index(bank_src, "\nfunc ", at + 1)
	check("a drag into or out of the bank names the cell dragged",
		_within(_first_code_index(bank_src, "source_slot.slot_index", at), end) != -1)
	var cd_src: String = _code_only(FileAccess.get_file_as_string(
		"res://src/systems/characterdata.gd"))
	at = _first_code_index(cd_src, "func equip_item(", 0)
	end = _first_code_index(cd_src, "\nfunc ", at + 1)
	check("equipping sends the cell it came from",
		_within(_first_code_index(cd_src, "body[\"position\"] = position", at), end) != -1)

	# ---- nothing still speaks the old model ----
	var retired := RegEx.new()
	retired.compile("\\b(hotbar_assignments|set_linked_item_ids|is_item_linked|refresh_from_inventory|assigned_item_id|item_used)\\b")
	var speakers: Array[String] = []
	var files: Array[String] = []
	_gd_files_under("res://src", files)
	for path in files:
		if _is_suite_script(path):
			continue
		if retired.search(_code_only(FileAccess.get_file_as_string(path))) != null:
			speakers.append(path)
	check("no code still points a key at a bag item", speakers.is_empty(), speakers)
	check("and the scan read the project", files.size() > 50, files.size())

	# ---- the frame hugs the keys ----
	var need: Vector2 = bar.get_combined_minimum_size()
	var hud_path := "res://scene/ui/characterhud.tscn"
	var left: Variant = _node_prop_in_scene(hud_path, "hotbar", "offset_left")
	var right: Variant = _node_prop_in_scene(hud_path, "hotbar", "offset_right")
	var top: Variant = _node_prop_in_scene(hud_path, "hotbar", "offset_top")
	var bottom: Variant = _node_prop_in_scene(hud_path, "hotbar", "offset_bottom")
	var given: Vector2 = Vector2(float(right) - float(left), float(bottom) - float(top)) \
		if left != null and right != null and top != null and bottom != null else Vector2.ZERO
	check("the HUD gives the bar exactly the width its keys need",
		is_equal_approx(given.x, need.x),
		"given %s, keys need %s - the difference is empty frame" % [given, need])
	check("and exactly the height", is_equal_approx(given.y, need.y),
		"given %s, need %s" % [given, need])

	bar.queue_free()
	bag.queue_free()
	ItemRegistry._items.erase(_HB_POTION)
	ItemRegistry._items.erase(_HB_SWORD)
	await get_tree().process_frame
	print("  %d keys that hold items: moved, merged, swapped, used, trashed and saved in place"
		% Hotbar.SLOT_COUNT)


func _test_the_staff_desk() -> void:
	section("STAFF DESK — a paged list, a record, staff-only notes, and the log")

	var packed: PackedScene = load("res://scene/ui/staff/staffpanel.tscn") as PackedScene
	check("staffpanel.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return
	# The panel offers by rank, and the rank it reads is Api's. A mod, for
	# the length of this section, and put back after.
	var was_role: String = Api.role
	var was_owner: bool = Api.is_owner
	Api.role = "mod"
	Api.is_owner = false
	var panel: Control = packed.instantiate() as Control
	add_child(panel)
	panel.visible = true
	# The log loads the first time its tab is shown. Marked loaded here so the
	# tab switches below measure the panel instead of asking a server.
	panel._log_loaded = true
	await get_tree().process_frame

	# ---- the shape ----
	check("it is attached as a window", panel.get("_window") != null)
	var tabs: TabContainer = panel.tabs
	var detail_tabs: TabContainer = panel.detail_tabs
	check("Players, Log and Reports are tabs",
		tabs.get_tab_count() == 3 and tabs.get_tab_title(0) == "Players" and tabs.get_tab_title(1) == "Log"
			and tabs.get_tab_title(2).begins_with("Reports"),
		[tabs.get_tab_title(0), tabs.get_tab_title(1), tabs.get_tab_title(2) if tabs.get_tab_count() > 2 else ""])
	check("a player's Actions, Record and Trades are tabs",
		detail_tabs.get_tab_count() == 3 and detail_tabs.get_tab_title(0) == "Actions"
		and detail_tabs.get_tab_title(1) == "Record" and detail_tabs.get_tab_title(2) == "Trades",
		[detail_tabs.get_tab_count()])
	check("both sized to their tallest tab, so switching never resizes the window",
		tabs.use_hidden_tabs_for_min_size and detail_tabs.use_hidden_tabs_for_min_size)
	check("the list opens on who is online - who a kick is for",
		panel._show_value() == "online" and panel.show_filter.item_count == panel.SHOW_FILTERS.size(),
		panel._show_value())

	# Picked, so the detail is on screen for the measurements below.
	panel._selected = "rowdy"
	panel._selected_entry = {"username": "rowdy", "role": "player", "actionable": true}
	panel._show_detail(panel._selected_entry)
	var heights: Array[float] = []
	var cut: Array[String] = []
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		for j in (detail_tabs.get_tab_count() if i == 0 else 1):
			if i == 0:
				detail_tabs.current_tab = j
			await get_tree().process_frame
			heights.append(PanelWindow.content_minimum(panel).y)
			for edit in panel.find_children("*", "LineEdit", true, true):
				var line: LineEdit = edit as LineEdit
				if line.placeholder_text == "" or not line.is_visible_in_tree():
					continue
				var box: StyleBox = line.get_theme_stylebox("normal")
				var room: float = line.size.x - (box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT) if box != null else 0.0)
				var need: float = line.get_theme_font("font").get_string_size(line.placeholder_text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, line.get_theme_font_size("font_size")).x
				if need > room:
					cut.append("%s needs %d, has %d" % [line.name, need, room])
	check("the window is the same height on every tab", heights.max() == heights.min(), heights)
	check("no input's hint is cut off", cut.is_empty(), cut)
	tabs.current_tab = 0
	detail_tabs.current_tab = 0
	# READ FROM THE SCENE, not the live node: PanelWindow may have restored a
	# rectangle saved by an earlier run, and that is not what a new mod gets.
	var top: float = 0.0
	var bottom: float = 0.0
	var root_state: SceneState = packed.get_state()
	for p in root_state.get_node_property_count(0):
		match root_state.get_node_property_name(0, p):
			"offset_top":
				top = float(root_state.get_node_property_value(0, p))
			"offset_bottom":
				bottom = float(root_state.get_node_property_value(0, p))
	check("its default size holds its tallest tab",
		bottom - top + 0.5 >= heights.max(), "authored %d, needs %d" % [bottom - top, heights.max()])
	check("and it opens clear of the menu bar", 360.0 + bottom <= 720.0 - 76.0, 360.0 + bottom)

	# ---- the list is a page, and asks for the next one ----
	panel._selected = ""
	panel._selected_entry = {}
	panel.search_input.text = "  Row  "
	var params: Dictionary = panel._list_params("fresh")
	check("a search asks the server for the first page of what was typed, trimmed",
		params == {"show": "online", "q": "Row", "limit": panel.PAGE_SIZE}, params)
	var before_gen: int = panel._list_generation
	panel.search_input.text_changed.emit("Ro")
	check("typing waits for a pause rather than asking per keystroke",
		panel._search_countdown > 0.0 and panel._list_generation == before_gen, panel._search_countdown)
	panel._search_countdown = -1.0
	panel.search_input.text = ""

	var amy: Dictionary = {"username": "amy", "role": "player", "online": true, "actionable": true, "record": {}}
	var bob: Dictionary = {"username": "bob", "role": "player", "online": false, "actionable": true,
		"record": {"ban": 1.0, "warn": 2.0, "note": 5.0}}
	var cat: Dictionary = {"username": "cat", "role": "mod", "online": true, "actionable": false, "record": {}}
	panel._apply_list_page({"ok": true, "data": {"accounts": [amy, bob], "more": true,
		"next_after": "bob", "matched": 1204.0, "online": 12.0, "now": 1000.0}}, "fresh")
	await get_tree().process_frame
	check("a page is drawn", _staff_rows(panel.account_list).size() == 2, _staff_rows(panel.account_list).size())
	check("the count is the server's match, not the rows held",
		panel.count_label.text == "2 of 1,204 · 12 online", panel.count_label.text)
	check("and there is a way to the next page", panel.more_button.visible)
	params = panel._list_params("more")
	check("which asks for what comes after the last name, not for page two",
		params.get("after", "") == "bob" and params.get("limit", 0) == panel.PAGE_SIZE, params)

	panel._apply_list_page({"ok": true, "data": {"accounts": [cat], "more": true,
		"next_after": null, "matched": 3.0, "online": 2.0, "now": 1000.0}}, "more")
	await get_tree().process_frame
	var names: Array = _staff_rows(panel.account_list).map(func(r): return str(r.get_meta("username", "")))
	check("the next page is added below, in order", names == ["amy", "bob", "cat"], names)
	check("the last page has no way on", not panel.more_button.visible)
	check("and asks for nothing more", panel._list_params("more").is_empty())
	check("a refresh re-reads a first page's worth", panel._list_params("refresh").get("limit", 0) == panel.PAGE_SIZE)

	var held: Array = []
	for i in 120:
		held.append({"username": "p%03d" % i})
	panel._accounts = held
	check("a refresh re-reads everything loaded, in one request",
		panel._list_params("refresh").get("limit", 0) == 120, panel._list_params("refresh"))
	for i in range(120, 250):
		held.append({"username": "p%03d" % i})
	check("and past the server's largest page, waits for the Refresh button",
		panel._list_params("refresh").is_empty())

	# ---- the row carries the record ----
	panel._apply_list_page({"ok": true, "data": {"accounts": [amy, bob], "more": false,
		"next_after": null, "matched": 2.0, "online": 1.0, "now": 1000.0}}, "fresh")
	await get_tree().process_frame
	var bob_row: Button = null
	for row in _staff_rows(panel.account_list):
		if str(row.get_meta("username", "")) == "bob":
			bob_row = row
	check("a repeat offender's row says so", bob_row != null and bob_row.text.contains("1 ban · 2 warnings"),
		bob_row.text if bob_row != null else "no row")
	check("but not the notes - a note is not a sanction", bob_row != null and not bob_row.text.contains("note"))
	check("clipped to the column, with the whole line on hover",
		bob_row != null and bob_row.clip_text and bob_row.tooltip_text.ends_with(bob_row.text))
	var amy_row: Button = null
	for row in _staff_rows(panel.account_list):
		if str(row.get_meta("username", "")) == "amy":
			amy_row = row
	check("the presence dot is drawn, not a letter the font lacks: filled online, hollow offline",
		bob_row != null and amy_row != null and bob_row.icon != null and amy_row.icon != null
		and not bob_row.text.contains("●") and not bob_row.text.contains("○")
		and [str(amy_row.get_meta("mark", "")), str(bob_row.get_meta("mark", ""))]
			== ["online" if bool(amy.get("online", false)) else "offline",
				"online" if bool(bob.get("online", false)) else "offline"]
		and amy_row.tooltip_text.begins_with("online - " if bool(amy.get("online", false)) else "offline - ")
		and amy_row.icon == Marks.texture("online", panel.COLOUR_ONLINE)
		and bob_row.icon == Marks.texture("offline", panel.COLOUR_OFFLINE),
		[amy_row.get_meta("mark", "") if amy_row else null, bob_row.get_meta("mark", "") if bob_row else null])

	# ---- the picked player survives a page that does not carry them ----
	panel._selected = "amy"
	panel._selected_entry = amy
	panel._apply_list_page({"ok": true, "data": {"accounts": [bob], "more": false,
		"next_after": null, "matched": 1.0, "online": 0.0, "now": 1000.0}}, "fresh")
	check("a new search does not quietly unpick the player the buttons are aimed at",
		panel.detail_box.visible and panel.name_label.text == "amy", panel.name_label.text)
	var amy_banned: Dictionary = amy.duplicate()
	amy_banned["banned"] = true
	amy_banned["ban"] = {"permanent": true, "banned_by": "thedev", "reason": "x"}
	panel._apply_list_page({"ok": true, "data": {"accounts": [amy_banned, bob], "more": false,
		"next_after": null, "matched": 2.0, "online": 1.0, "now": 1000.0}}, "fresh")
	check("and a page that does carry them updates what the detail says",
		panel.ban_label.text.begins_with("Banned permanently"), panel.ban_label.text)

	# ---- the empty list that is a trap ----
	panel.search_input.text = "rowdy"
	panel._apply_list_page({"ok": true, "data": {"accounts": [], "more": false,
		"next_after": null, "matched": 0.0, "online": 3.0, "now": 1000.0}}, "fresh")
	check("no match under Online says to look at Everyone - the player may just be offline",
		panel.empty_label.visible and panel.empty_label.text.contains("Everyone"), panel.empty_label.text)
	panel.search_input.text = ""

	panel._apply_list_page({"ok": false, "status": 404, "error": "Not found."}, "fresh")
	check("a 404 means this account is no longer staff, and the list goes",
		panel._accounts.is_empty() and panel.notice_label.text.contains("no longer lists you"),
		panel.notice_label.text)

	# ---- notes are offered by reach ----
	panel._show_detail({"username": "rowdy", "role": "player", "actionable": true})
	check("a mod may write a note on a player",
		not panel.note_button.disabled and not panel.warn_button.disabled and panel.note_input.editable)
	panel._show_detail({"username": "cat", "role": "mod", "actionable": false})
	check("but not on another mod - they could not read it back either",
		panel.note_button.disabled and panel.warn_button.disabled and not panel.note_input.editable)

	# ---- the record ----
	panel._selected = "rowdy"
	panel._selected_entry = {"username": "rowdy", "role": "player", "actionable": true}
	panel._record = []
	panel._record_more = false
	panel._record_before = 0
	check("the record asks about the picked player, sanctions and notes first",
		panel._record_params("fresh") == {"player": "rowdy", "limit": panel.RECORD_PAGE_SIZE,
			"action": "moderation"},
		panel._record_params("fresh"))
	panel._record_everything = true
	check("  and everything when asked to show everything",
		not panel._record_params("fresh").has("action"), panel._record_params("fresh"))
	panel._record_everything = false
	check("  from a toggle on the record tab", panel.record_all_button != null
		and panel.record_all_button.toggle_mode and panel.record_all_button.get_parent() == panel.record_list.get_parent().get_parent())
	check("and asks for no older entries before it knows there are some",
		panel._record_params("more").is_empty())
	panel._apply_record_page({"ok": true, "data": {"actions": [
		{"id": 9.0, "at": 1000.0, "by": "themod", "action": "warn", "target": "rowdy", "detail": "spam"},
		{"id": 7.0, "at": 900.0, "by": "themod", "action": "ban", "target": "rowdy", "detail": "1 days: x"},
		{"id": 5.0, "at": 800.0, "by": "themod", "action": "note", "target": "rowdy", "detail": "[color=red]x[/color]"},
	], "more": true, "next_before": 5.0,
		"summary": {"ban": 1.0, "kick": 1.0, "warn": 1.0, "note": 2.0}}}, "fresh")
	await get_tree().process_frame
	var lines: Array = _staff_rows(panel.record_list)
	check("the record is drawn, a line an entry", lines.size() == 3, lines.size())
	check("with the tally of the whole record above it",
		panel.record_summary.text == "Record: 1 ban · 1 kick · 1 warning · 2 notes", panel.record_summary.text)
	check("and the count on the tab, where somebody about to ban is looking",
		detail_tabs.get_tab_title(1) == "Record (3)", detail_tabs.get_tab_title(1))
	check("a note's text is drawn as typed, never as markup",
		lines.size() == 3 and lines[2] is Label and (lines[2] as Label).text.contains("[color=red]x[/color]"))
	var older: Dictionary = panel._record_params("more")
	check("older entries are asked for before the last id shown",
		older.get("before", 0) == 5 and older.get("player", "") == "rowdy", older)
	panel._apply_record_page({"ok": true, "data": {"actions": [
		{"id": 3.0, "at": 700.0, "by": "thedev", "action": "kick", "target": "rowdy", "detail": "1 session(s)"},
	], "more": false, "next_before": null, "summary": {"ban": 1.0, "kick": 1.0, "warn": 1.0, "note": 2.0}}}, "more")
	await get_tree().process_frame
	check("and added below", _staff_rows(panel.record_list).size() == 4 and not panel.record_more.visible)
	panel._apply_record_page({"ok": true, "data": {"actions": [], "more": false, "summary": {}}}, "fresh")
	check("a clean record says so, and the tab loses its count",
		panel.record_summary.text == "Record: clean" and detail_tabs.get_tab_title(1) == "Record"
		and panel.record_empty.visible, [panel.record_summary.text, detail_tabs.get_tab_title(1)])

	# ---- the log ----
	check("the kind filter opens on Moderation, with Everything next to it",
		panel.log_kind.item_count == 2 and panel.log_kind.selected == 0
		and panel._log_kind_value() == "moderation" and str(panel.log_kind.get_item_metadata(1)) == "",
		[panel.log_kind.item_count, panel.log_kind.selected])
	var log_page: Dictionary = {"ok": true, "data": {"actions": [
		{"id": 41.0, "at": 1000.0, "by": "themod", "action": "kick", "target": "rowdy", "detail": ""},
		{"id": 40.0, "at": 990.0, "by": "thedev", "action": "guild_rename", "target": "Shared", "detail": "-> Other"},
	], "more": true, "next_before": 40.0, "kinds": ["ban", "kick", "warn", "smite"]}}
	panel._apply_log_page(log_page, "fresh")
	await get_tree().process_frame
	var kinds_shown: Array = []
	for i in panel.log_kind.item_count:
		kinds_shown.append(panel.log_kind.get_item_text(i))
	check("and fills from the server's own list of kinds",
		kinds_shown == ["Moderation", "Everything", "Bans", "Kicks", "Warnings", "smite"], kinds_shown)
	var entries: Array = _staff_rows(panel.log_entries)
	check("the log is drawn", entries.size() == 2, entries.size())
	check("a line about a player takes you to them",
		entries.size() == 2 and (entries[0] as Control).mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND)
	check("a line about a guild does not pretend to",
		entries.size() == 2 and (entries[1] as Control).mouse_default_cursor_shape != Control.CURSOR_POINTING_HAND)
	var second: Dictionary = log_page.duplicate(true)
	second["data"]["kinds"] = ["ban"]
	second["data"]["more"] = false
	second["data"]["next_before"] = null
	panel._apply_log_page(second, "more")
	await get_tree().process_frame
	check("the kinds are filled once, not reset under somebody's cursor", panel.log_kind.item_count == 6)
	check("older entries go below", _staff_rows(panel.log_entries).size() == 4 and not panel.log_more.visible)

	for i in panel.log_kind.item_count:
		if str(panel.log_kind.get_item_metadata(i)) == "warn":
			panel.log_kind.select(i)
	panel.log_player.text = " Rowdy "
	params = panel._log_params("fresh")
	check("the log's filters go to the server, trimmed",
		params == {"player": "Rowdy", "staff": "", "action": "warn", "limit": panel.PAGE_SIZE}, params)
	check("and the one left empty is not sent",
		panel.build_query(params) == "?player=Rowdy&action=warn&limit=%d" % panel.PAGE_SIZE,
		panel.build_query(params))

	# ---- the wiring no bare panel can prove ----
	var src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/staff/staffpanel.gd"))
	var wired := func(fn: String, needle: String) -> bool:
		var at: int = _first_code_index(src, "func %s(" % fn, 0)
		var end: int = _first_code_index(src, "\nfunc ", at + 1)
		return at != -1 and _within(_first_code_index(src, needle, at), end) != -1
	check("the list asks the server with the list's own question",
		wired.call("_load", "Api.get_json(\"/api/staff/users\" + build_query(params))")
		and wired.call("_load", "_list_params(mode)") and wired.call("_load", "_apply_list_page(res, mode)"))
	check("a stale answer is dropped rather than drawn",
		wired.call("_load", "generation != _list_generation"))
	check("the record asks the log about the picked player",
		wired.call("_load_record", "Api.get_json(\"/api/staff/actions\" + build_query(params))")
		and wired.call("_load_record", "_apply_record_page(res, mode)"))
	check("and drops an answer about somebody no longer picked",
		wired.call("_load_record", "username != _selected"))
	check("picking a player reads their record", wired.call("_pick", "_load_record(\"fresh\")"))
	check("acting on a player re-reads their record", wired.call("_perform", "_load_record(\"fresh\")"))
	check("the log tab asks the log",
		wired.call("_load_log", "Api.get_json(\"/api/staff/actions\" + build_query(params))")
		and wired.call("_load_log", "_apply_log_page(res, mode)"))
	check("the log is read when its tab is first opened", wired.call("_on_tab_changed", "_load_log(\"fresh\")"))
	check("a note is sent with its kind",
		wired.call("_on_note_pressed", "Api.post(\"/api/staff/note\"")
		and wired.call("_on_note_pressed", "\"kind\": kind"))
	check("the warning button logs a warning and the note button a note",
		wired.call("_ready", "warn_button.pressed.connect(_on_note_pressed.bind(\"warn\"))")
		and wired.call("_ready", "note_button.pressed.connect(_on_note_pressed.bind(\"note\"))"))
	check("a log line opens its player", wired.call("_on_entry_input", "_open_player(username)"))
	check("across everyone, not just who is online", wired.call("_open_player", "== \"all\""))

	# ---- THE DOOR ----
	# For as long as this panel existed, NOTHING OPENED IT. characterhud.tscn
	# carried a hidden Staff button, _add_owner_button() hid its whole row
	# from everybody but the owner, and no line anywhere instanced the panel -
	# while this file tested the panel itself, thoroughly, in isolation. So a
	# mod had no way in, and every check above was about a room with no door.
	# These build the real HUD (out of the tree: its _ready() starts polls)
	# and ask the row who it is for, and what the button is connected to.
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	var staff_row: Control = hud.get_node_or_null("%staffrow") as Control
	var staff_button: Button = hud.get_node_or_null("%staffbutton") as Button
	check("the HUD has the staff row and its button", staff_row != null and staff_button != null)
	if staff_row != null and staff_button != null:
		Api.role = "player"
		hud._add_owner_button()
		check("a player has no staff row", not staff_row.visible)
		Api.role = "mod"
		hud._add_owner_button()
		check("a mod has the row, with the Staff button showing", staff_row.visible and staff_button.visible)
		check("and the button opens the desk",
			staff_button.pressed.is_connected(Callable(hud, "_toggle_staff_panel")))
		check("but a mod gets none of the owner's buttons",
			not staff_row.has_node("ownerbutton") and not staff_row.has_node("powersbutton"))
		Api.role = "owner"
		Api.is_owner = true
		hud._add_owner_button()
		check("the owner gets Staff, Owner and Powers",
			staff_button.visible and staff_row.has_node("ownerbutton") and staff_row.has_node("powersbutton"))
		Api.is_owner = false
		Api.role = "mod"
	var hud_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/characterhud.gd"))
	var toggle_at: int = _first_code_index(hud_src, "func _toggle_staff_panel(", 0)
	var toggle_end: int = _first_code_index(hud_src, "\nfunc ", toggle_at + 1)
	check("the toggle builds the desk from its scene and opens it",
		_within(_first_code_index(hud_src, "STAFF_PANEL_SCENE.instantiate()", toggle_at), toggle_end) != -1
		and _within(_first_code_index(hud_src, "staff_panel.toggle_panel()", toggle_at), toggle_end) != -1)
	# ESCAPE, with the real panel standing in as the HUD's.
	hud.staff_panel = panel
	panel.visible = true
	check("Escape counts the desk as open", hud.is_panel_open())
	hud.hide_panel()
	check("and closes it", not panel.visible)
	hud.staff_panel = null
	hud.free()

	panel.queue_free()
	Api.role = was_role
	Api.is_owner = was_owner
	await get_tree().process_frame
	print("  a desk a mod can run while the owner is away: pages, a record, notes and a log")


# =============================================================================
# THE GUILD PANEL - a name that is never cut, a roster by rank, and room to act
# =============================================================================
# Reported with a screenshot: a guild called "the first" whose own panel called
# it "the". The name shared one row with the line about it, and a Label sharing
# a row gives way - so the guild's name was the thing trimmed to make room for
# a sentence about the guild. Beside that: an "R" nobody could read as refresh,
# a heading that was the VIEWER's rank printed over everybody, "+" and "-" for
# online, three tiny buttons on every row, and Leave and Disband doing the same
# thing for a leader alone. All of it is checked by building the real panel and
# handing it answers in the server's shape through _repaint(), the function a
# real answer lands in.

func _test_the_guild_panel_reads_well() -> void:
	section("GUILD PANEL — the name fits, the roster is by rank, actions open on click")

	var packed: PackedScene = load("res://scene/ui/guild/guildpanel.tscn") as PackedScene
	check("guildpanel.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return
	var was_name: String = Api.username
	Api.username = "Tunacan"
	var panel: Control = packed.instantiate() as Control
	add_child(panel)
	panel.visible = true
	await get_tree().process_frame

	var now: int = int(Time.get_unix_time_from_system())
	var solo: Dictionary = {"in_guild": true, "rank": "leader", "invites": [], "now": now,
		"cost": 5000, "guild": {"name": "the first", "tag": "THE FIRST", "created_at": now - 86400,
		"members": [{"username": "Tunacan", "role": "owner", "rank": "leader",
			"online": true, "last_seen_at": now}], "size": 1, "capacity": 50}}

	# ---- the header ----
	var fits := func(label: Label) -> bool:
		var need: float = label.get_theme_font("font").get_string_size(label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		return label.size.x + 0.5 >= need
	panel._repaint(solo)
	await get_tree().process_frame
	await get_tree().process_frame
	var title: Label = panel.title
	check("the guild's name is drawn whole, not cut to make room for a sentence about it",
		title.text == "the first" and fits.call(title), [title.text, title.size.x])
	var legacy: Dictionary = solo.duplicate(true)
	legacy["guild"]["name"] = "Twenty Four Characters!!"
	panel._repaint(legacy)
	await get_tree().process_frame
	await get_tree().process_frame
	check("so is the longest name a guild from before the twelve-character cap can have",
		fits.call(title), title.size.x)
	panel._repaint(solo)
	await get_tree().process_frame
	check("the tag is drawn in the tag's own colour, as it is beside a name in chat",
		panel.tag_label.visible and panel.tag_label.text == "[THE FIRST]"
		and panel.tag_label.get_theme_color("font_color") == Api.GUILD_TAG_COLOUR, panel.tag_label.text)
	check("a guild of one says so in words, not arithmetic",
		panel.count_label.text.begins_with("just you") and not panel.count_label.text.contains("of 1"),
		panel.count_label.text)
	var header: Node = panel.get_node("frame/margin/rows/headerpanel")
	var letters: Array = []
	for b in header.find_children("*", "Button", true, false):
		letters.append((b as Button).text)
	check("the header has one button, the same × as every other panel", letters == ["×"], letters)
	check("and no R: the roster re-reads itself", panel.get_node_or_null("%guildrefreshbutton") == null)

	# ---- the guide, where the empty space was ----
	var solo_text: String = " ".join(_guild_texts(panel.rows))
	check("a new guild is told what its tag is for",
		solo_text.contains("[THE FIRST] is your guild's tag"), solo_text)
	check("how to invite", solo_text.contains("Invite somebody by typing their name above"))
	check("and where to talk", solo_text.contains("Guild tab in chat"))

	# ---- the footer ----
	check("a leader alone has one way out, called what it does",
		not panel.leave_button.visible and panel.disband_button.visible
		and panel.disband_button.text == "Close the guild",
		[panel.leave_button.visible, panel.disband_button.text])

	# ---- the roster, by rank ----
	# Deliberately NOT in the server's order: the headings must not depend on it.
	var full: Dictionary = solo.duplicate(true)
	full["guild"]["members"] = [
		{"username": "p001", "role": "player", "rank": "member", "online": false, "last_seen_at": now - 5 * 86400},
		{"username": "rowdy", "role": "player", "rank": "officer", "online": true, "last_seen_at": now},
		{"username": "Tunacan", "role": "owner", "rank": "leader", "online": true, "last_seen_at": now},
		{"username": "quietone", "role": "mod", "rank": "officer", "online": false, "last_seen_at": now - 7200},
		{"username": "newbie", "role": "player", "rank": "member", "online": true, "last_seen_at": now},
	]
	full["guild"]["size"] = 5
	panel._repaint(full)
	await get_tree().process_frame
	var headings: Array = []
	for row in _guild_rows_of(panel):
		if row is Label and not (row as Label).autowrap_mode:
			headings.append((row as Label).text)
	check("each rank under its own heading, leader first, with counts",
		headings == ["Leader", "Officers · 2", "Members · 2"], headings)
	check("the header counts the guild", panel.count_label.text.begins_with("5 members, 3 online"),
		panel.count_label.text)
	check("and a guild with people in it gets no beginner's guide",
		not " ".join(_guild_texts(panel.rows)).contains("Getting started"))

	var me_frame: PanelContainer = _guild_member_frame(panel, "Tunacan")
	var rowdy: PanelContainer = _guild_member_frame(panel, "rowdy")
	var quiet: PanelContainer = _guild_member_frame(panel, "quietone")
	check("every member has a row", me_frame != null and rowdy != null and quiet != null)
	if me_frame == null or rowdy == null or quiet == null:
		panel.queue_free()
		Api.username = was_name
		return
	var me_texts: Array = _guild_texts(me_frame)
	check("online is a filled dot and offline a hollow one - shapes, not + and -",
		_marks_of(me_frame).has("online") and _marks_of(quiet).has("offline")
		and not me_texts.has("+") and not _guild_texts(quiet).has("-"), [_marks_of(me_frame), _marks_of(quiet)])
	check("your own row says it is you", me_texts.has("you"), me_texts)
	check("an online row does not say 'online' beside the dot that already does",
		not me_texts.has("online"), me_texts)
	check("an offline row says when", _guild_texts(quiet).has("2 h ago"), _guild_texts(quiet))

	# ---- actions on click ----
	check("rows carry no buttons until they are opened",
		rowdy.find_children("*", "Button", true, false).is_empty())
	check("your own row offers nothing and does not pretend to",
		me_frame.mouse_default_cursor_shape != Control.CURSOR_POINTING_HAND and not _marks_of(me_frame).has("closed"))
	check("a row with something to offer says so", _marks_of(quiet).has("closed"), _marks_of(quiet))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	quiet.gui_input.emit(click)
	await get_tree().process_frame
	quiet = _guild_member_frame(panel, "quietone")
	var offered: Array = []
	for b in quiet.find_children("*", "Button", true, false):
		offered.append((b as Button).text)
	check("clicking an officer's row opens what the leader may do to them",
		offered == ["Demote", "Make leader", "Remove"], offered)
	check("and only that row", _guild_member_frame(panel, "rowdy").find_children("*", "Button", true, false).is_empty())

	panel._repaint(panel._last_data)
	await get_tree().process_frame
	quiet = _guild_member_frame(panel, "quietone")
	check("the fifteen-second refresh redraws it still open",
		quiet.find_children("*", "Button", true, false).size() == 3)

	# REMOVE ASKS TWICE. Pressed once it arms and says what the second press
	# does; nothing is sent. (A second press would reach the server.)
	var remove: Button = null
	for b in quiet.find_children("*", "Button", true, false):
		if str(b.get_meta("action", "")) == "remove":
			remove = b
	# NULL-SAFE: with the row not open there is no Remove to press, and an error
	# here would end the section and hide every check below it.
	check("the open row has a Remove to press", remove != null)
	if remove != null:
		remove.pressed.emit()
	await get_tree().process_frame
	quiet = _guild_member_frame(panel, "quietone")
	var armed_texts: Array = _guild_texts(quiet)
	check("Remove asks before it removes", armed_texts.has("Sure?") and not panel._busy, armed_texts)
	check("and says what the second press will do", panel.notice.text.contains("remove quietone"),
		panel.notice.text)
	panel._armed["until"] = 0.0
	panel._repaint(panel._last_data)
	await get_tree().process_frame
	check("an arm that has run out reads Remove again",
		_guild_texts(_guild_member_frame(panel, "quietone")).has("Remove"))

	quiet = _guild_member_frame(panel, "quietone")
	quiet.gui_input.emit(click)
	await get_tree().process_frame
	check("clicking the open row closes it",
		_guild_member_frame(panel, "quietone").find_children("*", "Button", true, false).is_empty())

	check("a leader with people under them keeps Leave and Disband",
		panel.leave_button.visible and panel.disband_button.visible and panel.disband_button.text == "Disband")

	# ---- the same guild, seen by a member ----
	var as_member: Dictionary = full.duplicate(true)
	as_member["rank"] = "member"
	Api.username = "p001"
	panel._open_member = ""
	panel._repaint(as_member)
	await get_tree().process_frame
	headings = []
	for row in _guild_rows_of(panel):
		if row is Label and not (row as Label).autowrap_mode:
			headings.append((row as Label).text)
	check("a member sees the same headings - not 'Member' printed over the leader",
		headings == ["Leader", "Officers · 2", "Members · 2"], headings)
	var arrows: int = 0
	for row in _guild_rows_of(panel):
		if row is PanelContainer and _marks_of(row).has("closed"):
			arrows += 1
	check("and is offered nothing on anybody's row", arrows == 0, arrows)
	check("and only Leave in the footer", panel.leave_button.visible and not panel.disband_button.visible)

	# ---- names in their own colours, rank as marks, who they are playing ----
	var rich: Dictionary = full.duplicate(true)
	rich["rank"] = "leader"
	rich["guild"]["members"] = [
		{"username": "p001", "role": "player", "rank": "member", "online": false,
			"last_seen_at": now - 5 * 86400, "name_hue": null, "character": "", "class_id": "", "level": 0, "area": ""},
		{"username": "quietone", "role": "mod", "rank": "officer", "online": false,
			"last_seen_at": now - 7200, "name_hue": 140, "character": "Quill", "class_id": "healer", "level": 22, "area": "elusion"},
		{"username": "Tunacan", "role": "owner", "rank": "leader", "online": true,
			"last_seen_at": now, "name_hue": 200, "character": "Kaelen", "class_id": "warrior", "level": 12, "area": "elusion"},
		{"username": "rowdy", "role": "player", "rank": "officer", "online": true,
			"last_seen_at": now, "name_hue": 20, "character": "Rowan", "class_id": "mage", "level": 7, "area": "field"},
		{"username": "newbie", "role": "dev", "rank": "member", "online": true,
			"last_seen_at": now, "name_hue": 300, "character": "Vex", "class_id": "tank", "level": 3, "area": "bossarena"},
	]
	rich["guild"]["activity"] = [
		{"at": now - 30, "kind": "promoted", "actor": "Tunacan", "target": "rowdy", "detail": "officer"},
		{"at": now - 86400 - 5, "kind": "renamed", "actor": "", "target": "the first", "detail": "old name"},
		{"at": now - 3 * 86400, "kind": "shrugged", "actor": "rowdy", "target": ""},
	]
	Api.username = "Tunacan"
	panel._open_member = ""
	panel._repaint(rich)
	await get_tree().process_frame

	var order: Array = []
	for row in _guild_rows_of(panel):
		if row is PanelContainer and row.has_meta("username"):
			order.append(str(row.get_meta("username")))
	check("inside each rank, whoever is on right now comes first",
		order == ["Tunacan", "rowdy", "quietone", "newbie", "p001"], order)

	var name_of := func(who: String) -> Label:
		var f: PanelContainer = _guild_member_frame(panel, who)
		return f.find_child("name", true, false) as Label if f != null else null
	var rowdy_name: Label = name_of.call("rowdy")
	check("a name is drawn in the colour its player chose",
		rowdy_name != null and rowdy_name.get_theme_color("font_color") == NameTag.colour(20))
	var p001_name: Label = name_of.call("p001")
	check("and a member who never chose one in the default",
		p001_name != null and p001_name.get_theme_color("font_color") == NameTag.colour(null))
	var owner_row: PanelContainer = _guild_member_frame(panel, "Tunacan")
	check("the server's owner wears the crown in the guild too",
		owner_row != null and owner_row.find_child("crown", true, false) is TextureRect)
	check("a mod wears MOD, a dev DEV",
		_guild_texts(_guild_member_frame(panel, "quietone")).has("MOD")
		and _guild_texts(_guild_member_frame(panel, "newbie")).has("DEV"))
	var mark_of := func(who: String) -> TextureRect:
		var f: PanelContainer = _guild_member_frame(panel, who)
		return f.find_child("rankmark", true, false) as TextureRect if f != null else null
	var lead_mark: TextureRect = mark_of.call("Tunacan")
	var off_mark: TextureRect = mark_of.call("rowdy")
	check("the guild leader wears a gold crown mark",
		lead_mark != null and lead_mark.get_meta("mark", "") == "leader"
		and lead_mark.texture == Marks.texture("leader", panel.RANK_COLOURS["leader"]))
	check("an officer a blue diamond",
		off_mark != null and off_mark.get_meta("mark", "") == "officer"
		and off_mark.texture == Marks.texture("officer", panel.RANK_COLOURS["officer"]))
	check("and a member nothing", mark_of.call("p001") == null)
	var gold_heading: bool = false
	for r in _guild_rows_of(panel):
		if r is Label and (r as Label).text == "Leader":
			gold_heading = (r as Label).get_theme_color("font_color") == panel.RANK_COLOURS["leader"]
	check("the headings wear the same rank colours", gold_heading)

	var char_of := func(who: String) -> String:
		var f: PanelContainer = _guild_member_frame(panel, who)
		var l: Label = f.find_child("character", true, false) as Label if f != null else null
		return l.text if l != null else ""
	check("under each name, who they are playing",
		char_of.call("rowdy") == "Rowan · Mage · lvl 7", char_of.call("rowdy"))
	check("and nothing invented for a member with no character", char_of.call("p001") == "")
	var where_of := func(who: String) -> String:
		var f: PanelContainer = _guild_member_frame(panel, who)
		var l: Label = f.find_child("where", true, false) as Label if f != null else null
		return l.text if l != null else ""
	check("somebody on right now shows where they are", where_of.call("rowdy") == "in Field",
		where_of.call("rowdy"))
	check("somebody away shows when they were last on, never where",
		where_of.call("quietone") == "2 h ago", where_of.call("quietone"))

	check("the header bar shows how full the guild is",
		panel.fill_bar.visible and int(panel.fill_bar.value) == 5 and int(panel.fill_bar.max_value) == 50,
		[panel.fill_bar.visible, panel.fill_bar.value, panel.fill_bar.max_value])

	# ---- the history ----
	var history: Array = []
	var in_history: bool = false
	for row in _guild_rows_of(panel):
		if row is Label and (row as Label).text == "Recent activity":
			in_history = true
		elif in_history and row is HBoxContainer:
			history.append(" ".join(_guild_texts(row)))
	check("the guild's recent history is at the bottom, newest first",
		history.size() == 3 and history[0] == "just now Tunacan made rowdy an officer", history)
	check("a staff rename says what the guild was called and not who did it",
		history.size() == 3 and history[1] == "1 day ago Staff renamed the guild from old name", history)
	check("and a kind this build has never heard of still reads as a sentence",
		history.size() == 3 and history[2] == "3 days ago rowdy shrugged", history)

	# ---- the row lights up under the pointer ----
	var hover: PanelContainer = _guild_member_frame(panel, "rowdy")
	hover.mouse_entered.emit()
	check("a row you can act on lights up under the pointer", hover.has_theme_stylebox_override("panel"))
	hover.mouse_exited.emit()
	check("and goes back when the pointer leaves", not hover.has_theme_stylebox_override("panel"))
	var still: PanelContainer = _guild_member_frame(panel, "Tunacan")
	check("your own row, with nothing to offer, does not light up",
		still.get_signal_connection_list("mouse_entered").is_empty())

	# ---- invitations ----
	var invited: Dictionary = {"in_guild": false, "rank": "", "now": now, "cost": 5000,
		"invites": [{"guild": "Dave's Lads", "by": "dave", "at": now}]}
	panel._repaint(invited)
	await get_tree().process_frame
	var answers: Array = []
	for b in panel.rows.find_children("*", "Button", true, false):
		answers.append([(b as Button).text, (b as Button).size.x >= 60.0])
	check("an invitation is answered with Join or Decline, each wide enough to read",
		answers == [["Join", true], ["Decline", true]], answers)
	check("outside a guild the header says what founding one costs",
		panel.count_label.text.contains("to found one") and not panel.tag_label.visible
		and not panel.fill_bar.visible)

	# ---- the rules, pure ----
	var script: Script = panel.get_script()
	check("a leader may demote, hand on or remove an officer",
		Array(script.actions_for("leader", "boss", "o", "officer")) == ["demote", "handon", "remove"])
	check("an officer may only remove a member",
		Array(script.actions_for("officer", "o1", "m", "member")) == ["remove"])
	check("nobody is offered anything against an equal",
		script.actions_for("officer", "o1", "o2", "officer").is_empty())
	check("or against themselves, whatever the case of the name",
		script.actions_for("leader", "Boss", "boss", "member").is_empty())
	check("a rank this build has never heard of is offered nothing",
		script.actions_for("warlord", "x", "m", "member").is_empty())
	check("history says 'just now', '1 day ago' - not '0 min', not '1 days'",
		script.ago_text(now - 10, now) == "just now" and script.ago_text(now - 86400, now) == "1 day ago"
		and script.ago_text(now - 3 * 86400, now) == "3 days ago")
	check("a sighting seconds old is 'just now', never '0 min ago' (one rule, LocalTime.ago)",
		script.presence_text({"last_seen_at": now - 20}, now) == "just now"
		and script.presence_text({"last_seen_at": now - 86400}, now) == "1 day ago",
		script.presence_text({"last_seen_at": now - 20}, now))

	panel.queue_free()
	Api.username = was_name
	await get_tree().process_frame
	print("  a guild panel that names its guild, groups its people and keeps its buttons until asked")


# =============================================================================
# TRADES — the right person, the offer you saw, and the result reaches you
# =============================================================================
# Four defects, all found by driving a trade between two accounts:
#
#   the invitee was never told: nothing polled the trade unless the window was
#     already open, so a trade sat unseen until it expired
#   a typed name went to the other player's FIRST character, not the one they
#     were playing (the window sent to_slot 0)
#   Accept agreed to whatever was standing when it landed, so an offer swapped
#     a moment before the click was accepted as the swap
#   whoever accepted FIRST was told nothing, kept the old bag on screen, and
#     their next save - a whole-bag replace - deleted what they had received
#
# The server halves are held by test_trades.py. These are the client halves:
# the window, the HUD and the save path, each driven with made-up answers in
# the exact shape the server sends.

# 6 Oct, the owner, on the GM panel's Move Players: "pick who from a list", "go
# to lands next to them", "its own name box", and Bring everyone stays the
# whole game. The row read the name box at the top of the tab and "Go to area"
# left you at the room's entrance.
func _test_move_players_from_the_list() -> void:
	section("GM PANEL - move players: a list, a name box, and Go to beside them")
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var was_name: String = Api.username
	var was_role: String = Api.role
	var was_owner: bool = Api.is_owner
	Api.username = "boss"
	Api.role = "owner"
	Api.is_owner = true
	var online: Array = [{"ok": true, "data": {"players": [
		{"username": "boss", "name": "Me", "level": 99, "area": "field", "with_you": true},
		{"username": "caster", "name": "Aldra", "level": 9, "area": "field", "with_you": true},
		{"username": "fighter", "name": "Bram", "level": 7, "area": "town", "with_you": false},
	]}}]
	gm.online_request = func(_path: String) -> Dictionary:
		await get_tree().process_frame
		return online[0]
	var posted: Array = []
	gm.post_request = func(path: String, body: Dictionary) -> Dictionary:
		posted.append([path, body])
		await get_tree().process_frame
		return {"ok": true, "data": {"area": "field"}}

	var list: VBoxContainer = gm.get_node_or_null("%onlinelist") as VBoxContainer
	var name_box: LineEdit = gm.get_node_or_null("%movenameinput") as LineEdit
	check("Move Players has its own name box and a list of who is online",
		list != null and name_box != null and gm.get_node_or_null("%onlinerefresh") != null)
	check("  and Bring everyone stays, beside the list", gm.get_node_or_null("%tpeveryonebutton") != null)
	if list == null or name_box == null:
		gm.queue_free()
		Api.username = was_name
		Api.role = was_role
		Api.is_owner = was_owner
		return
	await gm.refresh_online()
	await get_tree().process_frame
	var rows: Array = list.get_children().filter(func(n: Node) -> bool: return n is HBoxContainer)
	check("everyone online but you is listed", rows.size() == 2, rows.size())
	check("  with a count", (gm.get_node("%onlinelabel") as Label).text == "MOVE PLAYERS - 2 ONLINE",
		(gm.get_node("%onlinelabel") as Label).text)
	var caster: Node = list.get_node_or_null("row_caster")
	var pick: Button = caster.get_node_or_null("pick") as Button if caster != null else null
	check("a row says who, which character, what level and where",
		pick != null and pick.text.contains("caster") and pick.text.contains("Aldra")
		and pick.text.contains("Lv 9") and pick.text.contains("(here)"), pick.text if pick != null else "no row")

	# A body to measure "beside me" from, as the panel's own buttons need.
	var me := CharacterBody2D.new()
	me.add_to_group("player")
	var me_shape := CollisionShape2D.new()
	var me_circle := CircleShape2D.new()
	me_circle.radius = 7.0
	me_shape.shape = me_circle
	me.add_child(me_shape)
	add_child(me)
	me.global_position = Vector2(-90000, -90000)
	await get_tree().physics_frame

	pick.pressed.emit()
	check("clicking a name puts it in the name boxes",
		name_box.text == "caster" and (gm.get_node("%usernameinput") as LineEdit).text == "caster")
	(caster.get_node("bring") as Button).pressed.emit()
	await get_tree().create_timer(0.1).timeout
	check("a row's Bring asks the server to move that player",
		posted.size() == 1 and posted[0][0] == "/api/staff/teleport"
		and str(posted[0][1].get("username", "")) == "caster", posted)
	name_box.text = ""
	(gm.get_node("%tpbringbutton") as Button).pressed.emit()
	await get_tree().create_timer(0.1).timeout
	check("Bring here with an empty box asks for a name and moves nobody", posted.size() == 1, posted)
	name_box.text = "fighter"
	name_box.text_submitted.emit("fighter")
	await get_tree().create_timer(0.1).timeout
	check("Enter in the name box brings them", posted.size() == 2
		and str(posted[1][1].get("username", "")) == "fighter", posted)
	(gm.get_node("%tpeveryonebutton") as Button).pressed.emit()
	await get_tree().create_timer(0.1).timeout
	check("Bring everyone still asks twice first", posted.size() == 2
		and (gm.get_node("%tpeveryonebutton") as Button).text == "Confirm?")
	gm._disarm()
	await gm.teleport("goto", "nobody")
	check("Go to somebody who is not online says so",
		gm.results.get_parsed_text().contains("'nobody' is not online"), gm.results.get_parsed_text())
	online[0] = {"ok": true, "data": {"players": [
		{"username": "ghost", "name": "G", "level": 1, "area": "nowhere", "with_you": false}]}}
	await gm.teleport("goto", "ghost")
	check("  and an area this build does not know is refused, not travelled to",
		gm.results.get_parsed_text().contains("which this build does not know"))

	# PRESENCE.MEET(): where Go to lands. A stand-in for their picture, with the
	# display_name a RemotePlayer carries.
	var picture_script := GDScript.new()
	picture_script.source_code = "extends Node2D\nvar display_name: String = \"\"\n"
	picture_script.reload()
	var them := Node2D.new()
	them.set_script(picture_script)
	them.set("display_name", "caster")
	add_child(them)
	them.global_position = me.global_position + Vector2(300, 0)
	Presence._remotes[990001] = them
	check("their picture is found by name, ignoring case", Presence.remote_named("CASTER") == them)
	check("meet() stands you beside them at once when they are drawn here",
		Presence.meet("caster") and Presence.meeting() == "", Presence.meeting())
	var gap: float = me.global_position.distance_to(them.global_position)
	check("  beside, not on top of them", gap > 1.0 and gap < 120.0, gap)
	Presence._remotes.erase(990001)
	me.global_position = Vector2(-90000, -90000)
	check("somebody not drawn yet is waited for", not Presence.meet("caster") and Presence.meeting() == "caster")
	Presence._remotes[990001] = them
	check("  and met as soon as they are", Presence._try_meet(me) and Presence.meeting() == ""
		and me.global_position.distance_to(them.global_position) < 120.0)
	Presence._remotes.erase(990001)
	Presence.meet("caster")
	Presence._meet_until_msec = Time.get_ticks_msec() - 1
	check("a meeting that never happens is given up, not kept for later",
		not Presence._try_meet(me) and Presence.meeting() == "")

	them.queue_free()
	me.queue_free()
	gm.queue_free()
	Api.username = was_name
	Api.role = was_role
	Api.is_owner = was_owner

	# THE AREA GOES TO THE SERVER ON ARRIVAL. Played with two games: the target
	# walked into town and stood still, the server's who-is-online list still
	# said the Field (the area rode along with the next step's save), and Go to
	# went to the Field and found nobody.
	var store_script := GDScript.new()
	store_script.source_code = "extends SaveStorage\nfunc save(_payload: Dictionary) -> bool:\n\treturn true\n"
	store_script.reload()
	var was_storage = CharacterData.storage
	var was_pending: bool = CharacterData._save_pending
	var was_failed: bool = CharacterData.load_failed
	var was_index: int = CharacterData.active_character_index
	var was_slots: Array = CharacterData.character_slots.duplicate()
	CharacterData.storage = store_script.new()
	CharacterData.load_failed = false
	CharacterData.active_character_index = 0
	# THE EXPLORED MAP AS THE SERVER SENT IT: JSON, so every number a float. The
	# save route refuses w/h/ox/oy that are not whole numbers.
	CharacterData.character_slots = [{"name": "Stand-in", "area": "field",
		"explored": JSON.parse_string("{\"field\": {\"w\": 126, \"h\": 108, \"ox\": -16, \"oy\": -14, \"bits\": \"\"}}")},
		null, null, null]
	CharacterData._save_pending = false
	CharacterData.note_area("elusion")
	var noted: bool = str(CharacterData.character_slots[0].get("area", "")) == "elusion" and CharacterData._save_pending
	var sent: String = JSON.stringify(CharacterData.character_slots[0].get("explored", {}))
	var whole: bool = not RegEx.create_from_string("\\d\\.0[,}]").search(sent)
	CharacterData._save_pending = false
	CharacterData.note_area("elusion")
	var again: bool = CharacterData._save_pending
	CharacterData.note_area("")
	var blank: String = str(CharacterData.character_slots[0].get("area", ""))
	CharacterData.storage = was_storage
	CharacterData._save_pending = was_pending
	CharacterData.load_failed = was_failed
	CharacterData.active_character_index = was_index
	CharacterData.character_slots = was_slots
	check("arriving in an area records it and saves, without waiting for a step", noted)
	check("  with the map as WorldMap holds it - whole numbers, not the floats JSON gave back",
		whole, sent.left(200))
	check("  the same area again saves nothing", not again)
	check("  and nowhere (a menu) never overwrites a real area", blank == "elusion", blank)
	check("AreaRegistry tells CharacterData on every arrival",
		_func_body(_code_src("res://src/systems/arearegistry.gd"), "func _on_scene_changed(").contains("CharacterData.note_area("))
	await get_tree().process_frame

# 6 Oct, the owner: "every window needs to close with escape also". Escape used
# to close fourteen of the nineteen, from hand-kept lists that had drifted: the
# doll and the GM panel each open alone were closed but not counted, so Escape
# did nothing; the players list was in no list at all; and the shop, the loot
# bag, the kingdom board and the trade window were left out on purpose. Now the
# HUD keeps one list (_escape_windows()) and this opens every window there is,
# one at a time, and presses Escape on it.
func _test_escape_closes_every_window() -> void:
	section("ESCAPE - every window closes, the way its own x closes it")
	const WINDOWS := {
		"inventory_screen": "res://scene/ui/inventory/inventory.tscn",
		"equipment_panel": "res://scene/ui/equipment/equipmentpanel.tscn",
		"stats_screen": "res://scene/ui/statsscreen.tscn",
		"bank_screen": "res://scene/ui/bank/bankinventory.tscn",
		"lootbag_panel": "res://scene/ui/lootbag/lootbaginventory.tscn",
		"cooking_panel": "res://scene/ui/cooking/cookingscreen.tscn",
		"smith_panel": "res://scene/ui/smith/smithscreen.tscn",
		"shop_panel": "res://scene/ui/shop/shopinventory.tscn",
		"kingdom_panel": "res://scene/ui/kingdom/kingdomboard.tscn",
		"trade_panel": "res://scene/ui/trade/tradepanel.tscn",
		"chat_panel": "res://scene/ui/chat/chatpanel.tscn",
		"friends_panel": "res://scene/ui/friends/friendspanel.tscn",
		"players_panel": "res://scene/ui/players/playerspanel.tscn",
		"guild_panel": "res://scene/ui/guild/guildpanel.tscn",
		"staff_panel": "res://scene/ui/staff/staffpanel.tscn",
		"owner_panel": "res://scene/ui/owner/ownerpanel.tscn",
		"item_spawner": "res://scene/ui/owner/itemspawner.tscn",
		"save_history": "res://scene/ui/owner/savehistory.tscn",
		"stats_window": "res://scene/ui/owner/statswindow.tscn",
		"event_report": "res://scene/ui/owner/eventreport.tscn",
		"land_report": "res://scene/ui/owner/landreport.tscn",
		"options_screen": "res://scene/ui/menus/optionsscreen.tscn",
		"map_screen": "res://scene/ui/menus/mapscreen.tscn",
		"controls_panel": "res://scene/ui/controls/controlspanel.tscn",
		"kills_panel": "res://scene/ui/kills/killrecord.tscn",
		"credits_panel": "res://scene/ui/menus/creditsscreen.tscn",
		"party_panel": "res://scene/ui/party/partypanel.tscn",
	}
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	check("with nothing open, Escape has nothing to close (and opens the options instead)",
		not hud.is_panel_open())
	var uncounted: Array = []
	var stuck: Array = []
	var scripts: Array = []
	for field in WINDOWS:
		var window: Control = (load(WINDOWS[field]) as PackedScene).instantiate() as Control
		add_child(window)
		await get_tree().process_frame
		if window.get_script() != null:
			scripts.append((window.get_script() as Script).resource_path)
		hud.set(field, window)
		window.visible = true
		if not hud.is_panel_open():
			uncounted.append(field)
		hud.hide_panel()
		if window.visible:
			stuck.append(field)
		hud.set(field, null)
		window.queue_free()
	await get_tree().process_frame
	check("every window counts as open", uncounted.is_empty(), uncounted)
	check("  and Escape closes every one", stuck.is_empty(), stuck)
	check("the HUD's list has all %d of them" % WINDOWS.size(),
		hud._escape_windows().size() == WINDOWS.size(), hud._escape_windows().size())

	# EVERY WINDOW THERE IS: a script under src/ui/ built on PanelWindow is a
	# window, and it has to be one of the above. A new one fails here until it
	# is added to the HUD's list and to this one.
	var missing: Array = []
	for path in _all_gd_under("res://src/ui"):
		if _code_src(path).contains("PanelWindow") and not scripts.has(path):
			missing.append(path.get_file())
	check("every window under src/ui/ is one of them", missing.is_empty(), missing)
	hud.free()

	# Escape does what the x does, and the trade window's x hides the window. It
	# has never withdrawn an offer - the trade lives on the server.
	check("closing the trade window does not cancel the trade",
		not _func_body(_code_src("res://src/ui/trade/tradepanel.gd"), "func close_panel(").contains("Api."))

# 0.7.5. The owner, 6 Oct: "roll back and give player item might be useful".
# The item catalogue gives to a named player; the GM panel's Account tab opens
# it, and the new Save history window, on the name in its box; and the HUD says
# what a player was given. The server's half - who may, what a snapshot holds,
# the ledger, the sessions - is test_rollback.py.
func _test_give_and_save_history() -> void:
	section("GIVE AND ROLL BACK - a player's bag, and their character as it was")
	const History := preload("res://src/ui/owner/savehistory.gd")
	var was_name: String = Api.username
	var was_role: String = Api.role
	var was_owner: bool = Api.is_owner
	Api.username = "boss"
	Api.role = "owner"
	Api.is_owner = true
	var potion: ItemData = _menu_item("givetest_potion", ItemData.Type.CONSUMABLE, ItemData.EquipSlot.NONE, 99)
	ItemRegistry._items[potion.item_id] = potion

	# --- THE CATALOGUE GIVES TO A NAME ----------------------------------------
	var menu: Control = (load("res://scene/ui/owner/itemspawner.tscn") as PackedScene).instantiate() as Control
	add_child(menu)
	await get_tree().process_frame
	var asked: Array = []
	var adopted: Array = []
	var equipped: Array = []
	var answer: Array = [{"ok": true, "data": {"username": "hank", "slot": 2, "character": "tank",
		"granted_item_id": "givetest_potion", "granted_quantity": 3, "carry_positions": [0], "online": true}}]
	menu.post_request = func(path: String, body: Dictionary) -> Dictionary:
		asked.append([path, body])
		await get_tree().process_frame
		return answer[0]
	menu.adopt_bag = func(slot_index: int, cells: Array) -> void:
		adopted.append([slot_index, cells])
	menu.equip_request = func(id: String, cell: int) -> bool:
		equipped.append([id, cell])
		return true

	check("Give to starts empty, and empty is your own bag", menu.give_to.text == "" and menu.recipient() == "")
	menu.set_recipient("  hank ")
	menu.quantity.value = 3
	await get_tree().process_frame
	menu.wear_toggle.button_pressed = true
	await menu.spawn("givetest_potion")
	check("a name in Give to is sent: the grant route, the name and no slot",
		asked.size() == 1 and asked[0][0] == "/api/staff/grant" and asked[0][1].get("username") == "hank"
		and not asked[0][1].has("slot") and asked[0][1].get("quantity") == 3, asked)
	check("  nothing lands in your own bag", adopted.is_empty(), adopted)
	check("  and it says who got what, and that their game is told",
		menu.status.text == "Gave 3 × givetest_potion to hank's tank. Their game is told on its next poll.",
		menu.status.text)
	answer[0] = {"ok": true, "data": {"username": "hank", "slot": 2, "character": "tank",
		"granted_item_id": "doubleaxe", "granted_quantity": 1, "carry_positions": [1], "online": false}}
	await menu.spawn("doubleaxe")
	check("gear given to somebody else is never put on - \"put gear on\" is about you",
		equipped.is_empty() and adopted.is_empty(), [equipped, adopted])
	check("  and an offline player is said to find it when they sign in",
		menu.status.text.contains("offline") and menu.status.text.contains("Double Axe"), menu.status.text)

	menu.set_recipient("BOSS")
	answer[0] = {"ok": true, "data": {"inventory": [{"item_id": "givetest_potion", "quantity": 1}],
		"carry_positions": [0], "granted_item_id": "givetest_potion"}}
	await menu.spawn("givetest_potion")
	check("your own name, in any case, is your own bag: a slot, no name, and the bag adopted",
		asked[-1][1].has("slot") and not asked[-1][1].has("username") and adopted.size() == 1, asked[-1])
	menu.set_recipient("hank")
	answer[0] = {"ok": false, "status": 409, "error": "hank's backpack is full (20 slots)."}
	await menu.spawn("givetest_potion")
	check("a refusal is said in the server's words", menu.status.text == "hank's backpack is full (20 slots).",
		menu.status.text)
	menu.visible = false
	menu.open_for("caster")
	check("open_for() opens it with the name in Give to", menu.visible and menu.give_to.text == "caster")
	menu.queue_free()

	# --- THE GM PANEL OPENS BOTH ON ITS NAME -----------------------------------
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var opened: Array = []
	gm.open_window = func(method: String, who: String) -> bool:
		opened.append([method, who])
		return true
	var view_b: Button = gm.get_node_or_null("%viewbutton") as Button
	var give_b: Button = gm.get_node_or_null("%givebutton") as Button
	var hist_b: Button = gm.get_node_or_null("%historybutton") as Button
	check("Give item and Save history sit in View account's row - the tab is no taller",
		view_b != null and give_b != null and hist_b != null and give_b.get_parent() == view_b.get_parent()
		and hist_b.get_parent() == view_b.get_parent() and view_b.get_parent() is HBoxContainer)
	if give_b != null and hist_b != null:
		gm.username_input.text = ""
		give_b.pressed.emit()
		hist_b.pressed.emit()
		check("with no name above, neither opens anything", opened.is_empty(), opened)
		gm.username_input.text = " hank "
		give_b.pressed.emit()
		hist_b.pressed.emit()
		check("Give item opens the item catalogue on the name", opened.size() == 2
			and opened[0] == ["open_item_spawner_for", "hank"], opened)
		check("Save history opens the save history on it", opened.size() == 2
			and opened[1] == ["open_save_history", "hank"], opened)
		Api.is_owner = false
		give_b.pressed.emit()
		hist_b.pressed.emit()
		check("anyone but the owner opens neither", opened.size() == 2, opened)
		Api.is_owner = true
	var hud_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/characterhud.gd"))
	check("the HUD opens both, the owner only",
		_func_body(hud_src, "func open_save_history(").contains("Api.is_owner")
		and _func_body(hud_src, "func open_item_spawner_for(").contains("Api.is_owner"))
	gm.queue_free()

	# --- SAVE HISTORY ----------------------------------------------------------
	var hist: Control = (load("res://scene/ui/owner/savehistory.tscn") as PackedScene).instantiate() as Control
	add_child(hist)
	await get_tree().process_frame
	check("the save history is a window of its own", hist.get("_window") != null)
	var now: int = int(Time.get_unix_time_from_system())
	var listing: Dictionary = {"ok": true, "data": {"username": "hank", "slot": 2, "playing": 2,
		"characters": [{"slot": 0, "name": "warrior", "class_id": "warrior", "level": 4},
			{"slot": 2, "name": "tank", "class_id": "tank", "level": 18}],
		"now": {"name": "tank", "class_id": "tank", "level": 18, "gold": 1240, "items": 11},
		"snapshots": [
			{"id": 9, "taken_at": now - 60, "reason": "before-give", "level": 18, "gold": 1240, "items": 10},
			{"id": 7, "taken_at": now - 3600, "reason": "save", "level": 13, "gold": 980, "items": 9}],
		"kept": 20, "every_seconds": 600}}
	var got: Array = []
	var posted: Array = []
	var reply: Array = [listing]
	var post_reply: Array = [{}]
	hist.get_request = func(path: String) -> Dictionary:
		got.append(path)
		await get_tree().process_frame
		return reply[0]
	hist.post_request = func(path: String, body: Dictionary) -> Dictionary:
		posted.append([path, body])
		await get_tree().process_frame
		return post_reply[0]

	hist.visible = false
	await hist.open_for("hank")
	check("open_for() shows it and reads the name's history, the character they are playing",
		hist.visible and got == ["/api/staff/snapshots?username=hank"], got)
	var row9: Node = hist.list.get_node_or_null("snap_9")
	var row7: Node = hist.list.get_node_or_null("snap_7")
	check("  a line per snapshot, newest first",
		hist.list.get_child_count() == 2 and hist.list.get_child(0) == row9, hist.list.get_child_count())
	var what9: String = (row9.get_node("what") as Label).text if row9 != null else ""
	var what7: String = (row7.get_node("what") as Label).text if row7 != null else ""
	check("  each says the level, gold and what was carried",
		what7 == "level 13 · 980 gold · 9 carried", what7)
	check("  and why, when it was not an ordinary save", what9.ends_with("· before a gift"), what9)
	check("  and when, the way the rest of the game says a time",
		row7 != null and (row7.get_node("when") as Label).text == LocalTime.stamp(now - 3600))
	check("the character as it is now, to compare against",
		hist.now_label.text == "hank's tank now: level 18, 1240 gold, 11 carried.", hist.now_label.text)
	check("every character on the account, on the one they are playing",
		hist.slot_pick.item_count == 2 and hist.slot_pick.selected == 1
		and hist.slot_pick.get_item_text(1).contains("(playing)"),
		[hist.slot_pick.item_count, hist.slot_pick.selected])
	hist.slot_pick.select(0)
	hist.slot_pick.item_selected.emit(0)
	await get_tree().process_frame
	await get_tree().process_frame
	check("picking another character reads that one", got.size() == 2
		and got[-1] == "/api/staff/snapshots?username=hank&slot=0", got)
	reply[0] = listing
	await hist.load_history("hank", 2)

	# RESTORE ASKS TWICE.
	var restore7: Button = hist.list.get_node_or_null("snap_7/restore") as Button
	var restore9: Button = hist.list.get_node_or_null("snap_9/restore") as Button
	await hist.press_restore(7)
	check("the first press only arms it", posted.is_empty() and restore7 != null
		and restore7.text == "Sure?" and hist.is_armed(7), restore7.text if restore7 != null else "")
	await hist.press_restore(9)
	check("  pressing another row moves the arm, and still asks nothing",
		posted.is_empty() and restore7.text == "Restore" and restore9.text == "Sure?"
		and hist.is_armed(9) and not hist.is_armed(7))
	hist._armed_until = 0.0
	await hist.press_restore(9)
	check("  an arm whose time has run out is a first press again", posted.is_empty() and hist.is_armed(9))
	post_reply[0] = {"ok": true, "data": {"username": "hank", "slot": 2, "character": "tank", "restored": 9,
		"taken_at": now - 60, "undo_snapshot": 12, "was": {"level": 18, "gold": 1240, "items": 11},
		"now": {"level": 18, "gold": 1240, "items": 10}, "pet_cleared": false, "sessions_ended": 1}}
	var reads: int = got.size()
	await hist.press_restore(9)
	check("the second press sends it: the rollback route, the name and that snapshot",
		posted.size() == 1 and posted[0][0] == "/api/staff/rollback"
		and posted[0][1] == {"username": "hank", "snapshot_id": 9}, posted)
	check("  the list is read again, for the line that undoes it", got.size() == reads + 1
		and got[-1] == "/api/staff/snapshots?username=hank&slot=2", got)
	check("  and it says what changed, and that their game was signed out to reload it",
		hist.status.text.contains("was level 18, 1240 gold, 11 carried; now level 18, 1240 gold, 10 carried")
		and hist.status.text.contains("signed out")
		and hist.status.text.contains("undoes"), hist.status.text)
	post_reply[0] = {"ok": false, "status": 409, "error": "hank is in a trade. Try again when it has finished or timed out."}
	await hist.press_restore(7)
	await hist.press_restore(7)
	check("a refusal is said in the server's words",
		hist.status.text.begins_with("hank is in a trade"), hist.status.text)
	check("rolling back your own character says you are being signed out",
		History.restored_line({"username": "Boss", "sessions_ended": 1}, "boss").contains("You are being signed out"))
	check("  and a player who was not signed in gets it next time",
		History.restored_line({"username": "ivy", "sessions_ended": 0}, "boss").contains("not signed in"))
	check("  and a pet nobody holds any more is said",
		History.restored_line({"username": "ivy", "pet_cleared": true}, "boss").contains("none is out"))

	# The list was read again after the rollback, so its buttons are new ones.
	restore7 = hist.list.get_node_or_null("snap_7/restore") as Button
	await hist.press_restore(7)
	hist.close_button.pressed.emit()
	check("its x closes it, and disarms a Restore left at Sure?", not hist.visible and not hist.is_armed(7)
		and restore7 != null and restore7.text == "Restore")
	reply[0] = {"ok": false, "status": 404, "error": "No such account."}
	await hist.load_history("nobody")
	check("an unknown name is said, and the list empties",
		hist.list.get_child_count() == 0 and hist.status.text == "No such account.", hist.status.text)
	Api.is_owner = false
	var before: int = got.size()
	await hist.load_history("hank")
	await hist.press_restore(7)
	check("anyone but the owner asks the server nothing", got.size() == before and posted.size() == 2
		and hist.status.text.contains("owner"), hist.status.text)
	Api.is_owner = true
	hist.queue_free()

	# --- THE PLAYER IS TOLD WHAT THEY WERE GIVEN -------------------------------
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	check("a gift reads as who gave what, by the item's name",
		hud.gift_line({"by": "boss", "item_id": "givetest_potion", "quantity": 3}) == "boss gave you 3 × givetest_potion.",
		hud.gift_line({"by": "boss", "item_id": "givetest_potion", "quantity": 3}))
	check("  one is not counted", hud.gift_line({"by": "boss", "item_id": "givetest_potion", "quantity": 1})
		== "boss gave you givetest_potion.")
	check("  and an id this game does not know is said as the id",
		hud.gift_line({"by": "boss", "item_id": "nosuchthing_x", "quantity": 2}) == "boss gave you 2 × nosuchthing_x.")
	hud._unlogged_lines.clear()
	hud._on_carry_adopted({"slot": 0, "inventory": [], "trade": null, "gifts": [
		{"by": "boss", "item_id": "givetest_potion", "quantity": 2},
		{"by": "boss", "item_id": "nosuchthing_x", "quantity": 1}]})
	var said: Array = hud._unlogged_lines.map(func(line: Dictionary) -> String: return str(line["text"]))
	check("the bag arriving with gifts says one line each",
		said == ["boss gave you 2 × givetest_potion.", "boss gave you nosuchthing_x."], said)
	hud._unlogged_lines.clear()
	hud._on_carry_adopted({"slot": 0, "inventory": [], "trade": null})
	said = hud._unlogged_lines.map(func(line: Dictionary) -> String: return str(line["text"]))
	check("  and without them it says what it always did", said == ["Your backpack was updated by the server."], said)
	hud.free()

	ItemRegistry._items.erase(potion.item_id)
	Api.username = was_name
	Api.role = was_role
	Api.is_owner = was_owner

# 0.7.1. The owner, 6 Oct: "remove debug keys i have a full menu to debug", and
# for the performance readout, "add to menu instead and remove backslash". F1-F7
# and Ctrl+letter granted items, pets, lusions and a fishing kit, Ctrl+G
# switched god mode and backslash showed the readout. The owner panel does all
# of it now, and the keyboard hands out nothing.
func _test_no_debug_keys_the_panel_does_it() -> void:
	section("NO DEBUG KEYS - the owner panel does their work")
	const GONE := ["KEY_F1", "KEY_F2", "KEY_F3", "KEY_F4", "KEY_F5", "KEY_F6", "KEY_F7",
		"KEY_F9", "KEY_BACKSLASH", "_staff_debug_allowed", "_debug_give_", "DEBUG_KEYS_MIN_ROLE",
		"_toggle_god_mode"]
	var found: Array = []
	for path in _all_gd_under("res://src"):
		if _is_suite_script(path):
			continue
		var code: String = _code_src(path)
		for word in GONE:
			if code.contains(word):
				found.append("%s: %s" % [path.get_file(), word])
	check("no script reads a function key or backslash, or keeps a debug-key helper",
		found.is_empty(), found)

	var shown_before: bool = PerfOverlay.is_shown()
	PerfOverlay.set_shown(false)
	var key := InputEventKey.new()
	key.keycode = KEY_BACKSLASH
	key.pressed = true
	get_viewport().push_input(key)
	check("backslash no longer shows the performance readout",
		not PerfOverlay.is_shown() and not PerfOverlay.has_method("_input"))

	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var perf: CheckButton = gm.get_node_or_null("%perfbutton") as CheckButton
	var testing_tab: Node = gm.get_node_or_null("frame/margin/rows/tabsscroll/ownertabs/testing")
	check("the panel's Testing tab has a Performance readout switch",
		perf != null and testing_tab != null and testing_tab.is_ancestor_of(perf))
	if perf == null:
		gm.queue_free()
		PerfOverlay.set_shown(shown_before)
		return
	PerfOverlay._worst_fps = 5.0
	perf.button_pressed = true
	check("switching it on shows the readout", PerfOverlay.is_shown())
	check("  measuring its worst frame from now, not from last time",
		is_equal_approx(PerfOverlay._worst_fps, 0.0), PerfOverlay._worst_fps)
	check("  and the panel says so", gm.results.get_parsed_text().contains("Performance readout ON"),
		gm.results.get_parsed_text())
	perf.button_pressed = false
	check("switching it off hides it", not PerfOverlay.is_shown())
	PerfOverlay.set_shown(true)
	gm._sync_perf_button()
	check("the switch shows what the readout is doing, without flipping it",
		perf.button_pressed and PerfOverlay.is_shown())
	var god: Node = gm.get_node_or_null("%godmodebutton")
	check("god mode is a switch on the same tab", god != null and testing_tab.is_ancestor_of(god))
	PerfOverlay.set_shown(shown_before)
	gm.queue_free()
	await get_tree().process_frame

# =============================================================================
# THE READOUT COUNTS A CROWD (0.63.0)
# =============================================================================
# The owner, stress testing the Big Field's 366 monsters: "i need to upgrade
# the performance read out". The rows a crowd needs: hitches, the physics tick
# and the rest of the frame - scripts and drawing, which is what Godot's
# TIME_PROCESS measures (0.63.1) - and the monsters awake and asleep.
func _test_the_readout_counts_a_crowd() -> void:
	section("THE READOUT COUNTS A CROWD - hitches, physics, scripts and drawing, monsters awake and asleep (0.63.0)")
	var shown_before: bool = PerfOverlay.is_shown()
	PerfOverlay.set_shown(false)
	var before: Vector2i = PerfOverlay.monster_counts()
	var crowd := Node2D.new()
	add_child(crowd)
	for i in 5:
		var monster := Node2D.new()
		monster.add_to_group(&"enemies")
		if i < 2:
			monster.set_meta(&"asleep", true)     # what enemysleeper.gd marks
		crowd.add_child(monster)
	PerfOverlay.set_shown(true)
	check("switched on, its counts start from now",
		PerfOverlay._frames == 0 and PerfOverlay._hitches == 0
		and is_zero_approx(PerfOverlay._worst_physics_ms) and is_zero_approx(PerfOverlay._worst_process_ms))
	await get_tree().process_frame
	await get_tree().process_frame
	var counts: Vector2i = PerfOverlay.monster_counts()
	check("it counts the monsters here and the ones asleep",
		counts == before + Vector2i(5, 2), [before, counts])
	var text: String = PerfOverlay.readout()
	var want: String = "%d here   %d awake   %d asleep" % [counts.x, counts.x - counts.y, counts.y]
	check("  and says so: \"%s\"" % want, text.contains("monsters") and text.contains(want), text)
	check("the physics tick against its own budget - 80 ticks a second is 12.50 ms",
		text.contains("physics") and text.contains("ms a tick") and text.contains("budget %.2f" % (1000.0 / float(Engine.physics_ticks_per_second)))
		and Engine.physics_ticks_per_second == 80, text)
	check("  the rest of the frame and its worst, named for what it is: scripts + drawing, not scripts alone",
		text.contains("process") and text.contains("(worst ") and text.contains("scripts + drawing"), text)
	var frames: int = PerfOverlay._frames
	var hitches: int = PerfOverlay._hitches
	PerfOverlay._note_frame(0.040)
	PerfOverlay._note_frame(0.017)
	check("a 40 ms frame is a hitch; a 17 ms one on a 60 Hz screen is not",
		PerfOverlay._frames == frames + 2 and PerfOverlay._hitches == hitches + 1,
		[PerfOverlay._frames - frames, PerfOverlay._hitches - hitches])
	PerfOverlay._accum = PerfOverlay.SAMPLE_INTERVAL
	await get_tree().process_frame
	await get_tree().process_frame
	text = PerfOverlay.readout()
	check("  and the hitches row counts them, over 25 ms", text.contains("hitches") and text.contains("frames over 25 ms"), text)

	# HELD (0.69.2). The owner's 8x screenshot: fps 15, frame 66.67 ms, 64% of
	# frames hitching, physics 0.75 ms a tick and process 9.5 ms - the game was
	# held at the background rate, and the readout did not say so.
	check("  it says how busy each frame is, and what the graphics card took",
		text.contains("busy") and text.contains("ms of each frame") and text.contains("gpu"), text)
	var was_resting: bool = Settings._resting
	var was_focused: bool = Settings._focused
	Settings._resting = true
	var note: String = PerfOverlay._cap_note()
	check("held by a resting screen, the frame rate says so and how to wake it",
		Settings.held_reason() == "resting" and note.contains("held at %d" % Settings.BACKGROUND_FPS)
		and note.contains("resting") and note.contains("press a key"), note)
	Settings._resting = false
	Settings._focused = false
	note = PerfOverlay._cap_note()
	check("  held with the game in the background, it says that instead",
		Settings.held_reason() == "background" and note.contains("held at %d" % Settings.BACKGROUND_FPS)
		and note.contains("background"), note)
	Settings._focused = was_focused
	Settings._resting = was_resting
	frames = PerfOverlay._frames
	hitches = PerfOverlay._hitches
	PerfOverlay._note_frame(1.0 / float(Settings.BACKGROUND_FPS), true)
	check("  and a held frame is counted neither as a hitch nor at all",
		PerfOverlay._frames == frames and PerfOverlay._hitches == hitches, [PerfOverlay._frames - frames, PerfOverlay._hitches - hitches])
	var now_ms: int = Time.get_ticks_msec()
	Settings._last_rest_check_msec = now_ms
	Settings._last_input_msec = now_ms - int(Settings.REST_AFTER * 1000.0) - 5000
	Settings.check_rest()
	check("the screen does not rest while the readout is up - it is for watching, hands off",
		not Settings.is_resting())
	if bool(Settings.get_value("screen_rest")):
		PerfOverlay.set_shown(false)
		Settings._last_rest_check_msec = Time.get_ticks_msec()
		Settings._last_input_msec = Time.get_ticks_msec() - int(Settings.REST_AFTER * 1000.0) - 5000
		Settings.check_rest()
		check("  and rests as ever once it is closed", Settings.is_resting())
		Settings.note_input()
		PerfOverlay.set_shown(true)
	crowd.free()
	PerfOverlay._accum = PerfOverlay.SAMPLE_INTERVAL
	await get_tree().process_frame
	await get_tree().process_frame
	if before.x == 0:
		check("  with nobody about, it says none here", PerfOverlay.readout().contains("none here"), PerfOverlay.readout())
	check("still drawn five times a second, not every frame - the readout must not cost what it measures",
		is_equal_approx(PerfOverlay.SAMPLE_INTERVAL, 0.2))
	PerfOverlay.set_shown(false)
	PerfOverlay.set_shown(shown_before)

# =============================================================================
# OPTIONS EXPLAIN THEMSELVES (0.64.0)
# =============================================================================
# The owner: "what if a player changes settings unknowingly maybe we need a
# hud explaining ... some people may not even know what vulkan is", "maybe a
# tool tip or something". A bubble beside whatever setting is pointed at or
# tapped says what it does in plain words; what is set oddly is marked in the
# title bar and in orange. A new setting with no words fails here.
func _test_options_explain_themselves() -> void:
	section("OPTIONS EXPLAIN THEMSELVES - a help bubble, for a mouse and a finger alike (0.64.0)")
	const SettingsScript := preload("res://src/systems/settings.gd")
	var opts_script: GDScript = load("res://src/ui/menus/optionsscreen.gd") as GDScript
	var consts: Dictionary = opts_script.get_script_constant_map()
	var help: Dictionary = consts["HELP"]
	var kept := {}
	for key in ["volume_master", "vsync", "frame_cap", "brightness"]:
		kept[key] = Settings.get_value(key)
	for key in kept:
		Settings.set_value(key, SettingsScript.DEFAULTS[key])
	var options: Control = (load("res://scene/ui/menus/optionsscreen.tscn") as PackedScene).instantiate() as Control
	add_child(options)
	await get_tree().process_frame
	options.open()
	await get_tree().process_frame

	# ---- every setting has its words --------------------------------------------------
	var unexplained: Array = []
	var tooltips_left: Array = []
	for node in options.find_children("*", "", true):
		if not (node is OptionButton or node is Slider or node is CheckButton):
			continue
		if not help.has(str(node.name)):
			unexplained.append(str(node.name))
		elif (node as Control).tooltip_text != "":
			tooltips_left.append(str(node.name))
	for button_name in ["optionscreditsbutton", "optionskeysbutton", "optionsresetbutton", "optionsclosebutton"]:
		if not help.has(button_name):
			unexplained.append(button_name)
	check("every picker, slider and switch in Options - and the buttons - has plain words in HELP (%d)" % help.size(),
		unexplained.is_empty() and help.size() >= 30, unexplained)
	var too_long: Array = []
	for key in help:
		var words: String = str(opts_script.call("help_for", str(key)))
		if words.is_empty() or words.length() > 240 or not words.ends_with("."):
			too_long.append("%s (%d)" % [key, words.length()])
	check("  each one short enough to read in a glance - two lines, a full stop at the end", too_long.is_empty(), too_long)
	check("  the numbers in them are Settings' own: %d pictures a second in the background, %d on Battery saver, %d minutes to rest"
		% [SettingsScript.BACKGROUND_FPS, SettingsScript.SAVER_FPS, roundi(SettingsScript.REST_AFTER / 60.0)],
		str(opts_script.call("help_for", "backgroundlimit")).contains("only %d pictures" % SettingsScript.BACKGROUND_FPS)
		and str(opts_script.call("help_for", "batterysaver")).contains("at most %d pictures" % SettingsScript.SAVER_FPS)
		and str(opts_script.call("help_for", "screenrest")).contains("after %d minutes" % roundi(SettingsScript.REST_AFTER / 60.0)))
	check("  and Vulkan is said in words a player knows: how the game talks to the graphics card",
		str(help.get("graphicsapi", "")).contains("talks to your graphics card") and str(help.get("renderer", "")).contains("restart"))
	check("no setting keeps a tooltip of its own as well - the bubble says it, on a phone too", tooltips_left.is_empty(), tooltips_left)

	# ---- pointing and tapping ---------------------------------------------------------------
	var bubble: Control = options.get("help_bubble") as Control
	var panel: Control = options.get_node("mainpanel") as Control
	check("resting, with nothing set oddly: no bubble, and nothing in the title bar",
		bubble != null and not bubble.visible and options.call("header_text") == "" and options.call("help_text") == "")
	var vsync: Control = options.get_node("%vsyncmode") as Control
	vsync.mouse_entered.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var row_rect: Rect2 = vsync.get_parent().get_global_rect()
	var bubble_rect: Rect2 = bubble.get_global_rect()
	check("pointing at V-Sync - or tapping it, which a touch screen sends as the same - opens a bubble saying what it does",
		bubble.visible and options.call("help_text") == opts_script.call("help_for", "vsyncmode")
		and str(options.call("help_text")).contains("Most players: On")
		and bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true)), options.call("help_text"))
	check("  beside the setting, not on it, and inside the panel",
		(bubble_rect.position.y >= row_rect.end.y - 0.5 or bubble_rect.end.y <= row_rect.position.y + 0.5)
		and panel.get_global_rect().grow(1.0).encloses(bubble_rect), [row_rect, bubble_rect, panel.get_global_rect()])
	check("  floating over the panel - Options is no taller for it", options.size.y <= 720.0
		and bubble.top_level and bubble.mouse_filter == Control.MOUSE_FILTER_IGNORE, options.size)
	var last: Control = options.get_node("%othersattacks") as Control
	last.mouse_entered.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check("  and over the bottom row, where under it would cover the footer's buttons, it opens above",
		bubble.get_global_rect().end.y <= last.get_parent().get_global_rect().position.y + 0.5
		and panel.get_global_rect().grow(1.0).encloses(bubble.get_global_rect()), [last.get_parent().get_global_rect(), bubble.get_global_rect()])
	(options.get_node("%textsize") as Control).get_parent().mouse_entered.emit()
	check("pointing at a setting's name, beside it, works too", options.call("help_text") == opts_script.call("help_for", "textsize"))
	(options.get_node("%lighting") as Control).focus_entered.emit()
	check("  and so does reaching it with the keyboard", options.call("help_text") == opts_script.call("help_for", "lighting"))
	check("  the footer row itself says nothing - only its three buttons do",
		(options.get_node("mainpanel/margincontainer/vboxcontainer/footerrow") as Control).mouse_entered.get_connections().is_empty())
	(options.get_node("%lighting") as Control).focus_exited.emit()
	await get_tree().create_timer(float(consts["HELP_HIDE_SECONDS"]) + 0.2).timeout
	check("  moving off it, the bubble goes - after a moment, so crossing from a name to its control does not blink",
		not bubble.visible and float(consts["HELP_HIDE_SECONDS"]) > 0.0 and float(consts["HELP_HIDE_SECONDS"]) <= 0.3)

	# ---- what is set oddly ------------------------------------------------------------------------
	var vsync_name: Label = vsync.get_parent().get_node("label") as Label
	# The colours the scene file draws the two names in - read off a copy
	# that never ran, so nothing of the panel's own has touched them.
	var as_drawn: Control = (load("res://scene/ui/menus/optionsscreen.tscn") as PackedScene).instantiate() as Control
	var vsync_colour: Color = (as_drawn.get_node("mainpanel/margincontainer/vboxcontainer/columnsscroll/columns/rightcol/vsyncrow/label") as Label).get_theme_color("font_color")
	var master_colour: Color = (as_drawn.get_node("mainpanel/margincontainer/vboxcontainer/columnsscroll/columns/leftcol/masterrow/label") as Label).get_theme_color("font_color")
	as_drawn.free()
	check("each setting's name is drawn in the panel's own colour while nothing is odd",
		vsync_name.get_theme_color("font_color") == vsync_colour, [vsync_name.get_theme_color("font_color"), vsync_colour])
	vsync.mouse_entered.emit()
	Settings.set_value("window_x", int(Settings.get_value("window_x")))
	Settings.changed.emit("window_x", Settings.get_value("window_x"))
	check("a setting no warning reads changing - the window moved - leaves an open bubble open", bubble.visible)
	options.call("hide_help")
	Settings.set_value("vsync", "off")
	await get_tree().process_frame
	check("turning V-Sync Off marks it at once: a line in the title bar, and its name in orange",
		str(options.call("header_text")).begins_with("Heads up: V-Sync is Off")
		and vsync_name.get_theme_color("font_color") == consts["HELP_WARNING_COLOUR"], options.call("header_text"))
	vsync.mouse_entered.emit()
	check("  pointing at it says why first, and the way back",
		str(options.call("help_text")).begins_with("V-Sync is Off, so the picture can tear")
		and str(options.call("help_text")).contains("Reset to defaults puts it back."), options.call("help_text"))
	options.close()
	options.open()
	check("  and the next time Options opens, the title bar says so before anything is pointed at",
		str(options.call("header_text")).begins_with("Heads up: V-Sync is Off") and options.call("help_text") == "",
		options.call("header_text"))
	Settings.set_value("volume_master", 0.0)
	await get_tree().process_frame
	var master_name: Label = (options.get_node("%mastervolume") as Control).get_parent().get_node("label") as Label
	check("  two things odd: the title bar counts them, and both names are orange",
		str(options.call("header_text")).contains("2 settings are set unusually")
		and master_name.get_theme_color("font_color") == consts["HELP_WARNING_COLOUR"], options.call("header_text"))
	check("  the title bar's line never widens the window", (options.get("help_header") as Label).clip_text and options.size.y <= 720.0)
	options.call("_on_reset_pressed")
	check("Reset to defaults clears them: the line goes, and the names are the colour the panel drew them in again",
		options.call("header_text") == "" and str(Settings.get_value("vsync")) == "on"
		and vsync_name.get_theme_color("font_color") == vsync_colour and master_name.get_theme_color("font_color") == master_colour
		and vsync_colour != consts["HELP_WARNING_COLOUR"],
		[options.call("header_text"), vsync_name.get_theme_color("font_color"), vsync_colour])
	var none: Array = opts_script.call("help_warnings", 1.0, "on", 0, 60.0, 1.0)
	var low_cap: Array = opts_script.call("help_warnings", 1.0, "on", 30, 60.0, 1.0)
	var high_cap: Array = opts_script.call("help_warnings", 1.0, "on", 144, 60.0, 1.0)
	var unknown_screen: Array = opts_script.call("help_warnings", 1.0, "on", 30, -1.0, 1.0)
	var dim: Array = opts_script.call("help_warnings", 1.0, "on", 0, 60.0, 0.5)
	check("a frame cap under the screen's rate is worth a word; over it, or a screen that cannot say, is not; a dim game is",
		none.is_empty() and low_cap.size() == 1 and str(low_cap[0][0]) == "frame_cap" and high_cap.is_empty()
		and unknown_screen.is_empty() and dim.size() == 1 and str(dim[0][1]).contains("50%"),
		[none, low_cap, high_cap, unknown_screen, dim])
	options.queue_free()
	for key in kept:
		Settings.set_value(key, kept[key])
	await get_tree().process_frame

# =============================================================================
# OLD VERSIONS MUST UPDATE - the minimum build, from the GM panel (0.11.8)
# =============================================================================
# The owner: "how to raise client build". The server's gate (POST
# /api/server/minbuild, test_clientbuild.py) had no control in the game. The
# Server tab's switch sets it to THIS game's build or to 0 - never a typed
# number, so it cannot lock its owner out.

func _test_old_versions_must_update() -> void:
	section("MINIMUM BUILD - old versions must update, from the Server tab")

	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var button: CheckButton = gm.get_node_or_null("%minbuildbutton") as CheckButton
	var status_line: Label = gm.get_node_or_null("%minbuildstatus") as Label
	var server_tab: Node = gm.get_node_or_null("frame/margin/rows/tabsscroll/ownertabs/server")
	check("the Server tab has the switch, under who may log in, with a line saying where it stands",
		button != null and status_line != null and server_tab != null
		and server_tab.is_ancestor_of(button) and server_tab.is_ancestor_of(status_line))
	if button == null or status_line == null:
		gm.queue_free()
		return
	var status: Array = [{"ok": true, "data": {"min_client_build": 0, "current_client_build": Api.BUILD}}]
	gm.status_request = func(_path: String) -> Dictionary:
		await get_tree().process_frame
		return status[0]
	var posted: Array = []
	var answer: Array = [{"ok": true, "data": {"min_client_build": Api.BUILD, "armed": true}}]
	gm.post_request = func(path: String, body: Dictionary) -> Dictionary:
		posted.append([path, body])
		await get_tree().process_frame
		return answer[0]
	var was_owner: bool = Api.is_owner
	Api.is_owner = true
	button.set_pressed_no_signal(true)
	await gm._refresh_minbuild()
	check("  it shows the server's minimum without posting it back: 0 is off",
		not button.button_pressed and posted.is_empty() and not button.disabled
		and status_line.text == "Every version of the game can play.", status_line.text)
	status[0] = {"ok": true, "data": {"min_client_build": Api.BUILD}}
	await gm._refresh_minbuild()
	check("  and this game's build is on", button.button_pressed
		and status_line.text.contains("build %d" % Api.BUILD), status_line.text)
	await gm._on_minbuild_toggled(true)
	check("switching it on asks for this game's own build, and nothing typed",
		posted.size() == 1 and posted[0][0] == "/api/server/minbuild"
		and posted[0][1] == {"build": Api.BUILD}, posted)
	check("  and says what that means",
		gm.results.get_parsed_text().contains("told to update"), gm.results.get_parsed_text())
	answer[0] = {"ok": true, "data": {"min_client_build": 0, "armed": false}}
	await gm._on_minbuild_toggled(false)
	check("switching it off asks for 0, and every version can play again",
		posted.size() == 2 and posted[1][1] == {"build": 0}
		and status_line.text == "Every version of the game can play.", posted)
	answer[0] = {"ok": false, "status": 400, "error": "build 9 is newer than any client that exists"}
	status[0] = {"ok": true, "data": {"min_client_build": 0}}
	button.set_pressed_no_signal(true)
	await gm._on_minbuild_toggled(true)
	check("a refusal puts the switch back to the server's state and says so",
		not button.button_pressed and gm.results.get_parsed_text().contains("refused"))
	Api.is_owner = false
	var asked_before: int = posted.size()
	await gm._on_minbuild_toggled(true)
	check("anyone but the owner asks nothing", posted.size() == asked_before)
	Api.is_owner = was_owner
	gm.queue_free()
	await get_tree().process_frame

func _test_a_kill_waits_for_the_servers_receipt() -> void:
	section("KILL RECEIPTS - a kill waits for the server's own count of the fight (0.57.0)")
	# SECURITY_NOTES E-3, step 2. With the owner's switch on the server pays a
	# kill only when its books agree the monster died, and answers 202 - "not
	# yet" - until they have written it down. The server's half is
	# test_receipts.py; this is the game asking again, and giving up in time.
	check("the game is build 7, the first that waits for a receipt",
		Api.BUILD == 7 and Combat.RECEIPT_BUILD == 7, [Api.BUILD, Combat.RECEIPT_BUILD])
	var pending := {"ok": true, "status": 202, "data": {"pending": true, "retry_after_ms": 100,
		"message": "The server has not finished counting that fight yet."}}
	check("a 202 that says pending is the server's \"not yet\" - nothing else is",
		_CombatCode._receipt_pending(pending)
		and not _CombatCode._receipt_pending({"ok": true, "status": 200, "data": {"pending": true}})
		and not _CombatCode._receipt_pending({"ok": true, "status": 202, "data": {}})
		and not _CombatCode._receipt_pending({"ok": false, "status": 409, "data": {"pending": true}}))
	var pause_of := func(retry_ms: Variant) -> int:
		return _CombatCode.receipt_pause_ms({"ok": true, "status": 202, "data": {"pending": true, "retry_after_ms": retry_ms}})
	check("  asked again after the pause the server names, held to 100..2000 ms",
		pause_of.call(400) == 400 and pause_of.call(5) == Combat.RECEIPT_RETRY_LEAST_MS
		and pause_of.call(99999) == Combat.RECEIPT_RETRY_MOST_MS and pause_of.call("soon") == 400
		and pause_of.call(650.0) == 650, [pause_of.call(5), pause_of.call(99999), pause_of.call("soon")])
	check("  and when it gives up, it says why it most likely was",
		_CombatCode.receipt_gave_up_text("off").contains("No live link")
		and _CombatCode.receipt_gave_up_text("waiting").contains("No live link")
		and _CombatCode.receipt_gave_up_text("open").contains("did not see that fight"))
	check("  every kill is posted through the seam, so these checks drive the real loop",
		not _func_body(_code_src("res://src/systems/combat.gd"), "func report_kill(").contains("Api.post("))

	# ---- the loop, driven ---------------------------------------------------------------
	var stand_script := GDScript.new()
	stand_script.source_code = "extends Node2D\nvar xp: int = 0\nvar notices: Array = []\n" \
		+ "func gain_xp(n: int) -> void:\n\txp += n\n" \
		+ "func show_notice(message: String) -> void:\n\tnotices.append(message)\n"
	stand_script.reload()
	var killer: Node2D = Node2D.new()
	killer.set_script(stand_script)
	killer.add_to_group("player")
	add_child(killer)
	var kept_post: Callable = Combat.kill_post
	var kept_wait: float = Combat.receipt_wait_seconds
	var kept_token: String = Api.token
	var kept_known: bool = Api.reachability_known
	var kept_online: bool = Api.server_online
	Api.token = "test-not-a-real-token"
	# AS IF THE SERVER HAD ANSWERED: a request the suite makes elsewhere, to no
	# server, can mark it known offline while these wait - so before each kill.
	var reachable := func() -> void:
		Api.reachability_known = true
		Api.server_online = true
	var posts: Array = []
	var answers: Array = []
	Combat.kill_post = func(path: String, body: Dictionary, _timeout: float) -> Dictionary:
		posts.append([path, body.duplicate()])
		await get_tree().process_frame
		return answers.pop_front() if answers.size() > 1 else answers[0]
	var paid := {"ok": true, "status": 200, "data": {"enemy_id": "bushmage", "xp_gained": 7, "contents": []}}

	# FILLED IN PLACE, never reassigned: the stand-in post holds this array.
	answers.append_array([pending, pending, paid])
	reachable.call()
	await Combat.report_kill("bushmage", Vector2.ZERO, killer)
	var bodies_alike: bool = posts.size() == 3
	for entry in posts:
		bodies_alike = bodies_alike and entry[0] == "/api/combat/kill" and entry[1] == posts[0][1] \
			and entry[1].get("enemy_id") == "bushmage"
	check("pending twice and then paid: three posts of the same kill, paid once",
		bodies_alike and int(killer.get("xp")) == 7 and (killer.get("notices") as Array).is_empty(),
		[posts, killer.get("xp"), killer.get("notices")])

	posts.clear()
	answers.clear()
	answers.append(pending)
	Combat.receipt_wait_seconds = 0.35
	var kept_xp: int = int(killer.get("xp"))
	reachable.call()
	await Combat.report_kill("bushmage", Vector2.ZERO, killer)
	var asked: int = posts.size()
	await get_tree().create_timer(0.3).timeout
	var said: Array = killer.get("notices") as Array
	check("pending past the wait: it gives up, says so, and pays nothing",
		asked >= 2 and asked <= 6 and int(killer.get("xp")) == kept_xp and said.size() == 1
		and str(said[0]) == _CombatCode.receipt_gave_up_text(Presence.phase()), [asked, killer.get("xp"), said])
	check("  and it stops asking", posts.size() == asked, [asked, posts.size()])

	posts.clear()
	answers.clear()
	answers.append(paid)
	Combat.receipt_wait_seconds = kept_wait
	reachable.call()
	await Combat.report_kill("bushmage", Vector2.ZERO, killer)
	check("with the switch off a kill is one post and one answer, as it always was",
		posts.size() == 1 and int(killer.get("xp")) == kept_xp + 7, [posts.size(), killer.get("xp")])

	Combat.kill_post = kept_post
	Combat.receipt_wait_seconds = kept_wait
	Api.token = kept_token
	Api.reachability_known = kept_known
	Api.server_online = kept_online
	killer.queue_free()

	# ---- the GM panel's switch ----------------------------------------------------------
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var button: CheckButton = gm.get_node_or_null("%receiptsbutton") as CheckButton
	var testing_tab: Node = gm.get_node_or_null("frame/margin/rows/tabsscroll/ownertabs/testing")
	check("the GM panel has the receipts switch, on the Testing tab with the other world switches",
		button != null and testing_tab != null and testing_tab.is_ancestor_of(button))
	if button == null:
		gm.queue_free()
		return
	var status: Array = [{"ok": true, "data": {"kill_receipts": true}}]
	gm.status_request = func(_path: String) -> Dictionary:
		await get_tree().process_frame
		return status[0]
	var gm_posted: Array = []
	var gm_answer: Array = [{"ok": true, "data": {"kill_receipts": true, "min_client_build": 0}}]
	gm.post_request = func(path: String, body: Dictionary) -> Dictionary:
		gm_posted.append([path, body])
		await get_tree().process_frame
		return gm_answer[0]
	var was_owner: bool = Api.is_owner
	Api.is_owner = true
	button.set_pressed_no_signal(false)
	await gm._refresh_receipts()
	check("  it shows what the server holds, without posting it back",
		button.button_pressed and gm_posted.is_empty() and not button.disabled)
	status[0] = {"ok": true, "data": {}}
	await gm._refresh_receipts()
	check("  a server that says nothing about receipts reads as off - kills paid on the game's word",
		not button.button_pressed)
	await gm._on_receipts_toggled(true)
	check("switching it on asks the owner's route", gm_posted.size() == 1
		and gm_posted[0][0] == "/api/server/receipts" and gm_posted[0][1] == {"on": true}, gm_posted)
	check("  and says the minimum build has to follow, while it is below 7",
		gm.results.get_parsed_text().contains("Set Old versions must update to 7"), gm.results.get_parsed_text())
	gm_answer[0] = {"ok": false, "status": 404, "error": "Not found."}
	status[0] = {"ok": true, "data": {"kill_receipts": false}}
	button.set_pressed_no_signal(true)
	await gm._on_receipts_toggled(true)
	check("a refusal puts the switch back to the server's state and says so",
		not button.button_pressed and gm.results.get_parsed_text().contains("refused"))
	Api.is_owner = false
	var asked_before: int = gm_posted.size()
	await gm._on_receipts_toggled(true)
	check("anyone but the owner asks nothing", gm_posted.size() == asked_before)
	Api.is_owner = was_owner
	gm.queue_free()
	await get_tree().process_frame


func _test_the_trade_switch_reaches_the_game() -> void:
	section("TRADE SWITCH - the owner can stop new trades, and the game says so")

	# 6 Oct: E-3 is open (the kill is the game's word), so a cheated drop is
	# real loot and trading is the only road between accounts. The owner's
	# switch is POST /api/server/trade; off stops NEW trades and lets an open
	# one finish. The server's rules are test_tradegates.py; this is the game.

	# ---- the GM panel's switch ----
	var gm: Control = (load("res://scene/ui/owner/ownerpanel.tscn") as PackedScene).instantiate() as Control
	add_child(gm)
	await get_tree().process_frame
	var button: CheckButton = gm.get_node_or_null("%tradebutton") as CheckButton
	var testing_tab: Node = gm.get_node_or_null("frame/margin/rows/tabsscroll/ownertabs/testing")
	var pvp: Node = gm.get_node_or_null("%pvpbutton")
	check("the GM panel has the trading switch, beside the other world switch, PvP",
		button != null and testing_tab != null and testing_tab.is_ancestor_of(button)
		and pvp != null and pvp.get_parent() == button.get_parent())
	if button == null:
		gm.queue_free()
		return
	var status: Array = [{"ok": true, "data": {"trade": false}}]
	gm.status_request = func(_path: String) -> Dictionary:
		await get_tree().process_frame
		return status[0]
	var posted: Array = []
	var answer: Array = [{"ok": true, "data": {"trade": false, "open_trades": 1}}]
	gm.post_request = func(path: String, body: Dictionary) -> Dictionary:
		posted.append([path, body])
		await get_tree().process_frame
		return answer[0]
	var was_owner: bool = Api.is_owner
	Api.is_owner = true
	button.set_pressed_no_signal(true)
	await gm._refresh_trade()
	check("  it shows what the server holds, without posting it back",
		not button.button_pressed and posted.is_empty() and not button.disabled)
	status[0] = {"ok": true, "data": {}}
	await gm._refresh_trade()
	check("  a server that says nothing about trade reads as on", button.button_pressed)
	await gm._on_trade_toggled(false)
	check("switching it off asks the owner's route", posted.size() == 1
		and posted[0][0] == "/api/server/trade" and posted[0][1] == {"on": false}, posted)
	check("  and says what that means, and how many trades may still finish",
		gm.results.get_parsed_text().contains("nobody can open a new trade")
		and gm.results.get_parsed_text().contains("1 open trade may still finish"),
		gm.results.get_parsed_text())
	answer[0] = {"ok": false, "status": 404, "error": "Not found."}
	status[0] = {"ok": true, "data": {"trade": true}}
	button.set_pressed_no_signal(false)
	await gm._on_trade_toggled(false)
	check("a refusal puts the switch back to the server's state and says so",
		button.button_pressed and gm.results.get_parsed_text().contains("refused"))
	Api.is_owner = false
	var asked_before: int = posted.size()
	await gm._on_trade_toggled(false)
	check("anyone but the owner asks nothing", posted.size() == asked_before)
	Api.is_owner = was_owner
	gm.queue_free()

	# ---- the trade window ----
	var trade: Control = (load("res://scene/ui/trade/tradepanel.tscn") as PackedScene).instantiate() as Control
	add_child(trade)
	await get_tree().process_frame
	var says: Array = [{"ok": true, "data": {"trade": false}}]
	trade.status_request = func(_path: String) -> Dictionary:
		await get_tree().process_frame
		return says[0]
	await trade._check_trading_open()
	check("the trade window says trading is off before anybody types a name",
		trade.notice_label.text == trade.TRADING_OFF_TEXT and trade.offer_button.disabled,
		trade.notice_label.text)
	check("  in the server's own words", trade.TRADING_OFF_TEXT
		== "Trading is switched off for now. A trade already open can still finish.")
	says[0] = {"ok": true, "data": {"trade": true}}
	trade._set_notice("", false)
	await trade._check_trading_open()
	check("  and on again, offers again", not trade.offer_button.disabled and trade.notice_label.text == "")
	says[0] = {"ok": false, "status": 0, "error": "No connection"}
	trade.offer_button.disabled = true
	await trade._check_trading_open()
	check("  no answer leaves it to the server - nothing is refused here on a guess",
		not trade.offer_button.disabled)
	check("it asks when the window opens on the start page",
		_func_body(_code_src("res://src/ui/trade/tradepanel.gd"), "func open_panel(").contains("_check_trading_open()"))
	trade.queue_free()

	# ---- the staff log ----
	var StaffPanel: Script = load("res://src/ui/staff/staffpanel.gd") as Script
	check("the staff log words the switch, and the owner's level and skill tools",
		StaffPanel.describe_entry({"by": "boss", "action": "trade", "target": "server", "detail": "off"})
			== "boss changed trade switch - off"
		and StaffPanel.KIND_LABELS.get("level") == "Level sets" and StaffPanel.KIND_LABELS.get("skill") == "Skill sets",
		StaffPanel.describe_entry({"by": "boss", "action": "trade", "target": "server", "detail": "off"}))
	await get_tree().process_frame


func _test_trades_reach_the_right_people() -> void:
	section("TRADES — the right person, the offer you saw, and the result reaches you")

	var TradePanel: Script = load("res://src/ui/trade/tradepanel.gd") as Script
	var packed: PackedScene = load("res://scene/ui/trade/tradepanel.tscn") as PackedScene
	check("tradepanel.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate() or TradePanel == null:
		return

	var was_name: String = Api.username
	Api.username = "tester"
	var panel: Control = packed.instantiate() as Control
	add_child(panel)
	panel.visible = true
	await get_tree().process_frame

	# ---- a typed name is a person, not a slot ----
	var typed: Dictionary = panel._offer_body("bob", -1)
	check("an offer to a typed name sends no slot for them - the server picks who they are playing",
		not typed.has("to_slot") and typed.get("username") == "bob", typed)
	var picked: Dictionary = panel._offer_body("bob", 1)
	check("one picked off the nearby list sends the slot the server listed",
		int(picked.get("to_slot", -1)) == 1, picked)
	var src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/trade/tradepanel.gd"))
	var pressed_at: int = src.find("func _on_offer_pressed")
	var pressed_end: int = src.find("\nfunc ", pressed_at + 10)
	check("and the Open trade button is the typed path",
		_within(src.find("_send_offer(who, -1)", pressed_at), pressed_end) != -1
		and _within(src.find("_send_offer(who, 0)", pressed_at), pressed_end) == -1)

	# ---- drawing a trade ----
	var sword: Array = [{"item_id": "ironsword", "quantity": 2}]
	panel._apply_poll({"trade": _trade_payload(3, sword), "resync": null})
	await get_tree().process_frame
	check("an open trade shows the trade, not the list", panel.trade_box.visible and not panel.start_box.visible)
	check("the window remembers which revision it drew", panel._revision == 3, panel._revision)
	check("and Accept sends exactly that", panel._confirm_body() == {"revision": 3}, panel._confirm_body())
	var name_label: Label = panel.with_row.get_node_or_null("name") as Label
	check("who it is with: their character, in the colour they chose",
		name_label != null and name_label.text == "Bram"
		and name_label.get_theme_color("font_color") == NameTag.colour(200),
		name_label.text if name_label else "no label")
	check("with their rank as a badge", panel.with_row.get_node_or_null("badge") != null)
	var detail: Label = panel.with_row.get_node_or_null("detail") as Label
	check("and their account and level", detail != null and detail.text == "(bob) · lv 7",
		detail.text if detail else "no detail")
	var dot: TextureRect = panel.with_row.get_node_or_null("presence") as TextureRect
	check("with a presence dot", dot != null and dot.get_meta("mark", "") == "online")
	var their_row: Node = panel.them_list.get_node_or_null("item_ironsword")
	check("their item is drawn as a row with an icon's space kept",
		their_row != null and their_row.get_node_or_null("icon") != null
		and (their_row.get_node("icon") as Control).custom_minimum_size == TradePanel.ICON_SIZE)
	var qty: Label = their_row.get_node_or_null("quantity") as Label if their_row else null
	check("and its quantity", qty != null and qty.text == "x2", qty.text if qty else "no quantity")
	check("and its tooltip says what it is", their_row != null
		and str((their_row as Control).tooltip_text).length() > 0)
	check("the Decline button is only for the asked; the opener gets Cancel trade",
		panel.cancel_button.text == "Cancel trade", panel.cancel_button.text)

	# ---- a change is pointed out, not slipped in ----
	panel._set_notice("", false)
	panel._apply_poll({"trade": _trade_payload(3, sword), "resync": null})
	check("the same offer read again says nothing", panel.notice_label.text == "", panel.notice_label.text)
	var stick: Array = [{"item_id": "tinyhealthpotion", "quantity": 1}]
	panel._apply_poll({"trade": _trade_payload(4, stick), "resync": null})
	check("a changed offer is pointed out by name",
		panel.notice_label.text.contains("Bram changed their offer"), panel.notice_label.text)
	check("the column that changed is lit", panel.them_panel.modulate != Color.WHITE, panel.them_panel.modulate)
	check("and Accept now names the new revision", panel._confirm_body() == {"revision": 4})
	panel._set_notice("", false)
	panel._apply_poll({"trade": _trade_payload(5, stick, 1), "resync": null})
	check("a change of one gold is a change too",
		panel.notice_label.text.contains("changed their offer"), panel.notice_label.text)

	# ---- the answer to Accept ----
	panel._set_notice("", false)
	panel._apply_confirm({"ok": false, "status": 409, "error": "The offer changed.",
		"data": {"error": "Conflict", "trade": _trade_payload(6, sword, 50)}}, null)
	check("an accept refused because the offer moved redraws the offer as it now stands",
		panel._revision == 6 and panel.them_gold.text == "Gold 50", [panel._revision, panel.them_gold.text])
	check("and says why, by name",
		panel.notice_label.text.contains("changed the offer before your accept arrived"), panel.notice_label.text)

	# ---- the four states of Accept ----
	var us: Dictionary = {"confirmed": false}
	var them: Dictionary = {"name": "Bram", "confirmed": false, "online": true}
	check("nobody has accepted: Accept", TradePanel.accept_state(us, them)["text"] == "Accept")
	check("they have: it says so, still live",
		TradePanel.accept_state(us, {"name": "Bram", "confirmed": true, "online": true})["text"] == "Accept (Bram has)"
		and not TradePanel.accept_state(us, {"name": "Bram", "confirmed": true, "online": true})["disabled"])
	check("you have: waiting, and the button is spent",
		TradePanel.accept_state({"confirmed": true}, them)["disabled"]
		and str(TradePanel.accept_state({"confirmed": true}, them)["text"]).begins_with("Waiting for Bram"))
	check("they have gone offline: nothing to accept against",
		TradePanel.accept_state(us, {"name": "Bram", "online": false})["disabled"]
		and str(TradePanel.accept_state(us, {"name": "Bram", "online": false})["text"]).contains("offline"))
	panel._apply_poll({"trade": _trade_payload(6, sword, 50, false), "resync": null})
	check("an offline partner disables Accept in the window, and says so",
		panel.confirm_button.disabled and panel.notice_label.text.contains("gone offline"),
		[panel.confirm_button.disabled, panel.notice_label.text])
	check("the dot goes hollow",
		str(panel.with_row.get_node("presence").get_meta("mark", "")) == "offline")
	check("the asked side can Decline", TradePanel.cancel_text("b", {"confirmed": false}) == "Decline")
	check("but not once they have agreed to something",
		TradePanel.cancel_text("b", {"confirmed": true}) == "Cancel trade")

	# ---- the line above the buttons ----
	check("the summary quotes the server's cut",
		TradePanel.summary_text({"tax": 5}, {"offering_value": 100})
			== "You receive 100 gold's worth. The kingdom takes 5 gold from you.")
	check("an item the server cannot value is said plainly, never 'worth 0'",
		TradePanel.summary_text({"tax": null}, {"offering_value": null}).contains("cannot go through")
		and not TradePanel.worth_text(null).contains("0"))
	check("nothing offered yet", TradePanel.summary_text({"tax": 0}, {"offering_value": 0}) == "You receive nothing yet.")

	# ---- how it ended ----
	panel._apply_poll({"trade": null, "resync": null, "last": {"trade_id": "t-one", "state": "cancelled"}})
	check("a trade the other side called off says so",
		panel.notice_label.text == "The trade was called off." and panel.start_box.visible,
		panel.notice_label.text)
	check("and the window stops watching it", panel._watched_trade_id == "")
	panel._apply_poll({"trade": _trade_payload(1, sword), "resync": null})
	panel._apply_poll({"trade": null, "resync": null, "last": {"trade_id": "t-one", "state": "done"}})
	check("one that finished - result already delivered by the HUD's poll - says complete",
		panel.notice_label.text == "Trade complete.", panel.notice_label.text)
	panel._apply_poll({"trade": _trade_payload(1, sword), "resync": null})
	panel._apply_poll({"trade": null, "resync": null, "last": {"trade_id": "some-other", "state": "done"}})
	check("one that simply vanished expired", panel.notice_label.text == "The trade expired.",
		panel.notice_label.text)
	check("the ending words are one function",
		TradePanel.ending_text("x", null, {"trade": {"trade_id": "x"}}) == "Trade complete.")

	# ---- the result reaches whoever accepted first ----
	var saved_slots: Array = CharacterData.character_slots.duplicate(true)
	var saved_index: int = CharacterData.active_character_index
	var announced: Array = []
	var listen := func(resync: Dictionary) -> void: announced.append(resync)
	CharacterData.carry_adopted.connect(listen)

	var cells: Array = []
	cells.resize(30)
	cells[4] = {"item_id": "ironsword", "quantity": 1.0}
	CharacterData.character_slots = [{"gold": 10, "inventory": []}, null, {"gold": 900, "inventory": []}, null]
	CharacterData.active_character_index = 0
	var record: Dictionary = {"trade_id": "t-one", "with": "bob", "with_name": "Bram",
		"got": [{"item_id": "ironsword", "quantity": 1}], "gave": [], "gold_got": 0,
		"gold_gave": 300, "tax": 10, "at": 1}

	panel._apply_poll({"trade": _trade_payload(1, sword), "resync": null})
	panel._apply_poll({"trade": null, "last": null,
		"resync": {"slot": 2, "gold": 610, "inventory": cells, "trade": record}})
	var slot2: Dictionary = CharacterData.character_slots[2]
	check("the trade poll's result lands in that character's saved copy",
		int(slot2.get("gold", -1)) == 610 and slot2.get("inventory", []).size() == 30, slot2.get("gold"))
	# NULL-SAFE: a sabotage that leaves the cache alone must fail THIS check,
	# not index an empty array and unwind the rest of the section.
	var cached: Array = slot2.get("inventory", []) if slot2.get("inventory", []) is Array else []
	var fourth: Variant = cached[4] if cached.size() > 4 else null
	check("with the quantities as integers, not JSON's floats",
		fourth is Dictionary and typeof((fourth as Dictionary).get("quantity")) == TYPE_INT, fourth)
	check("and the window says complete from it", panel.notice_label.text == "Trade complete.")
	check("it is announced once", announced.size() == 1, announced.size())

	# The live character: a stand-in player with a purse and a cached bag.
	var fake := GDScript.new()
	fake.source_code = "extends Node\nvar gold: int = 0\nvar inventory_data: Array = []\n" \
		+ "func set_gold(v: int) -> void:\n\tgold = v\n"
	fake.reload()
	var body: Node = Node.new()
	body.set_script(fake)
	check("apply_server_carry() adopts onto the character being played",
		CharacterData.apply_server_carry({"slot": 0, "gold": 42, "inventory": cells, "trade": record}, body))
	check("its purse is the server's number", int(body.gold) == 42, body.gold)
	var carried: Array = body.inventory_data
	check("and the bag its next save will send is the server's bag",
		carried.size() == 30 and carried[4] is Dictionary and (carried[4] as Dictionary).get("item_id") == "ironsword")
	check("so that save no longer deletes what the trade gave",
		int((CharacterData.character_slots[0] as Dictionary).get("gold", -1)) == 42)
	var before: int = announced.size()
	check("an empty array is not an empty bag - it is ignored",
		not CharacterData.apply_server_carry({"slot": 0, "gold": 1, "inventory": []}, body)
		and int(body.gold) == 42)
	check("nor is a slot that is not there", not CharacterData.apply_server_carry(
		{"slot": 9, "gold": 1, "inventory": cells}, body))
	check("nor anything that is not a result", not CharacterData.apply_server_carry("nope", body))
	check("and none of those announced anything", announced.size() == before, announced.size())

	# THE SAVE PATH HAS NOTHING TO ADOPT ANY MORE. A save used to carry the
	# whole bag, and a 409 from a trade that had run meanwhile came back with
	# the server's bag for _adopt_refusal() to take. The bag is the server's
	# now (ONE CELL AT A TIME): a save carries no bag, and a trade's result
	# reaches this client only through apply_server_carry() above, from the
	# trade poll or the broadcast poll. These checks named the old function
	# after it was gone, and the SCRIPT ERROR that made silently ended this
	# section there - every check below it went unrun and still read 0 failed.
	var storage := ServerStorage.new()
	check("the save path has no whole-bag refusal to adopt - a trade's bag comes on the poll",
		not storage.has_method("_adopt_refusal"))
	var ss_src: String = _code_only(FileAccess.get_file_as_string("res://src/systems/serverstorage.gd"))
	check("and a save never names the bag routes",
		not ss_src.contains("/api/character/inventory\"") and not ss_src.contains("/api/account/bank\""))
	body.free()

	# ---- history ----
	panel._apply_recent({"trades": [record], "now": 3601})
	var recent_texts: Array = _guild_texts(panel.recent_list)
	# THE ITEM'S NAME AS THE REGISTRY HAS IT - "Iron Sword" with the art pack
	# present, its id without (a .tres naming missing art does not load). The
	# sentence is what is under test, not the pack.
	var sword_name: String = TradePanel.item_name("ironsword")
	var potion_name: String = TradePanel.item_name("tinyhealthpotion")
	check("recent trades are listed from your side",
		recent_texts.size() >= 1 and str(recent_texts[0]) == "Bram: got %s for 300 gold" % sword_name, recent_texts)
	check("aged against the server's clock", recent_texts.has("1 h ago"), recent_texts)
	var first_row: Control = panel.recent_list.get_child(0) as Control if panel.recent_list.get_child_count() > 0 else Control.new()
	check("and the whole sentence is in the tooltip",
		first_row.tooltip_text == TradePanel.result_line(record), first_row.tooltip_text)
	check("the sentence says what came, what went and the cut",
		TradePanel.result_line(record)
			== "Trade with bob complete: you got %s for 300 gold. The kingdom took 10 gold." % sword_name,
		TradePanel.result_line(record))
	var gift: Dictionary = {"with": "bob", "got": [], "gave": [], "gold_got": 1500, "gold_gave": 0, "tax": 75}
	check("a gift reads as a gift, not a trade 'for nothing'",
		TradePanel.result_line(gift) == "Trade with bob complete: you got 1,500 gold. The kingdom took 75 gold."
		and TradePanel.history_line(gift) == "bob: got 1,500 gold", [TradePanel.result_line(gift), TradePanel.history_line(gift)])
	check("and one you gave away reads that way round",
		TradePanel.history_line({"with": "bob", "gave": [], "gold_gave": 20, "got": []}) == "bob: gave 20 gold")
	var stacked := ItemData.new()
	stacked.value = 50
	stacked.stackable = true
	var single := ItemData.new()
	single.value = 16000
	single.stackable = false
	check("'each' only where there can be more than one",
		TradePanel.value_hint(stacked) == "50 gold each" and TradePanel.value_hint(single) == "worth 16,000 gold",
		[TradePanel.value_hint(stacked), TradePanel.value_hint(single)])
	check("big numbers are grouped, as the backpack groups them",
		TradePanel.worth_text(40500) == "worth 40,500 gold"
		and TradePanel.summary_text({"tax": 2025}, {"offering_value": 40500})
			== "You receive 40,500 gold's worth. The kingdom takes 2,025 gold from you.")
	var listed: String = TradePanel.goods_text([{"item_id": "ironsword", "quantity": 1},
		{"item_id": "tinyhealthpotion", "quantity": 3}], 20)
	check("lists read as lists",
		listed == "%s, 3 x %s and 20 gold" % [sword_name, potion_name], listed)
	# A PET, because the pets are the items whose art is not in the private pack
	# - so this one is meaningful on a clone without it, where the sword is not.
	check("an item the registry knows is called by its name, not its id",
		TradePanel.item_name("petboss") == "Crowned Companion", TradePanel.item_name("petboss"))
	check("and one it does not know falls back to its id rather than to nothing",
		TradePanel.item_name("nosuchthing") == "nosuchthing")
	panel._apply_recent({"trades": [], "now": 1})
	check("no trades yet says so", " ".join(_guild_texts(panel.recent_list)).contains("None yet"))

	# ---- nearby, drawn like every other list ----
	panel._apply_nearby({"area": "town", "precision": "area", "players": [
		{"username": "bob", "slot": 1, "name": "Bram", "level": 7, "role": "mod", "name_hue": 200}]})
	var nearby_row: Node = panel.nearby_list.get_child(0) if panel.nearby_list.get_child_count() > 0 else Node.new()
	var nearby_name: Label = nearby_row.get_node_or_null("name") as Label
	check("a nearby player's character is drawn in their colour with their badge",
		nearby_name != null and nearby_name.text == "Bram"
		and nearby_name.get_theme_color("font_color") == NameTag.colour(200)
		and nearby_row.get_node_or_null("badge") != null)
	check("with a Trade button", nearby_row.get_node_or_null("tradewith") is Button)

	CharacterData.carry_adopted.disconnect(listen)
	CharacterData.character_slots = saved_slots
	CharacterData.active_character_index = saved_index
	panel.queue_free()
	Api.username = was_name

	# ---- the HUD: the person asked is told ----
	var hud: Node = (load("res://scene/ui/characterhud.tscn") as PackedScene).instantiate()
	hud._build_message_box()
	hud._build_status_strip()
	var trade_button: Button = hud.get_node_or_null("%tradebutton") as Button
	check("the HUD has its Trade button", trade_button != null)
	check("the poll tells the server which character this is",
		hud._broadcast_path().ends_with("&slot=%d" % CharacterData.active_character_index), hud._broadcast_path())
	var asked: Dictionary = {"trade_id": "t-9", "with": "bob", "from_them": true,
		"they_accepted": false, "you_accepted": false}
	hud._read_trade(asked)
	check("a trade opened with you lights the strip",
		hud.status_strip.visible and hud.status_label.text == "bob wants to trade with you", hud.status_label.text)
	check("and the Trade button", trade_button != null and trade_button.text == "Trade •")
	var said: int = hud.message_rows.get_child_count()
	check("and says so once", said == 1, said)
	hud._read_trade(asked)
	check("not again on the next poll", hud.message_rows.get_child_count() == said)
	hud._read_trade({"trade_id": "t-9", "with": "bob", "from_them": true,
		"they_accepted": true, "you_accepted": false})
	check("when they accept, the strip says they are waiting on you",
		hud.status_label.text == "bob accepted your trade - waiting on you", hud.status_label.text)
	hud._read_trade({"trade_id": "t-9", "with": "bob", "from_them": true,
		"they_accepted": true, "you_accepted": true})
	check("once you have too, nothing is waiting on you", not hud.status_strip.visible)
	hud.set_world_status("pvp", "PvP is ON")
	hud._read_trade(asked)
	check("a waiting trade outranks the pvp notice on the strip",
		hud.status_label.text == "bob wants to trade with you", hud.status_label.text)
	hud._read_trade(null)
	check("when it is answered the light goes out",
		hud.status_label.text == "PvP is ON" and trade_button != null and trade_button.text == "Trade")
	hud._read_trade({"trade_id": "t-10", "with": "bob", "from_them": false,
		"they_accepted": false, "you_accepted": false})
	check("a trade you opened is not announced to you", hud.message_rows.get_child_count() == said
		and hud.status_label.text == "PvP is ON")

	var saved_slots2: Array = CharacterData.character_slots.duplicate(true)
	CharacterData.character_slots = [null, null, {"gold": 0, "inventory": []}, null]
	hud._on_carry_adopted({"trade": record})
	var last_line: Node = hud.message_rows.get_child(hud.message_rows.get_child_count() - 1)
	check("a finished trade is announced in the sentence the history uses",
		" ".join(_guild_texts_any(last_line)).contains(TradePanel.result_line(record)))
	hud._read_trade_resync({"slot": 2, "gold": 77, "inventory": cells})
	check("the broadcast poll's result lands too",
		int((CharacterData.character_slots[2] as Dictionary).get("gold", -1)) == 77)

	# THE POLL ITSELF, with an answer in the shape the server sends - so a
	# reader that is never called from it fails here, not in a player's hands.
	hud._read_trade(null)
	hud._apply_broadcast({"messages": [], "latest_id": 0, "maintenance": null, "pvp": false,
		"teleport": null, "guild_tag": "", "trade": {"trade_id": "t-11", "with": "cara",
		"from_them": true, "they_accepted": false, "you_accepted": false},
		"trade_resync": {"slot": 2, "gold": 88, "inventory": cells}})
	check("the broadcast poll lights a waiting trade",
		hud.status_label.text == "cara wants to trade with you", hud.status_label.text)
	check("and hands on a finished one",
		int((CharacterData.character_slots[2] as Dictionary).get("gold", -1)) == 88)
	var toggle_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/characterhud.gd"))
	var toggle_at: int = toggle_src.find("func toggle_trade")
	check("opening the window puts the light out at once, not a poll later",
		_within(toggle_src.find('set_world_status("trade", "")', toggle_at),
			toggle_src.find("toggle_panel(", toggle_at)) != -1)

	# WIRED WHERE THE POLL STARTS, so a result delivered by ANY route is
	# announced - the window's poll and the save path do not know the HUD.
	# The HUD is out of the tree, so its timer never runs; the deferred first
	# poll finds nobody logged in and returns.
	hud._start_broadcast_poll()
	check("the HUD listens for a result however it arrived",
		CharacterData.carry_adopted.is_connected(hud._on_carry_adopted))
	var hud_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/characterhud.gd"))
	var start_at: int = hud_src.find("func _start_broadcast_poll")
	check("and polls once on arrival rather than ten seconds later - the poll is how the server learns the slot",
		_within(hud_src.find("_on_broadcast_poll_timeout.call_deferred()", start_at),
			hud_src.find("\nfunc ", start_at + 10)) != -1)
	await get_tree().process_frame
	if CharacterData.carry_adopted.is_connected(hud._on_carry_adopted):
		CharacterData.carry_adopted.disconnect(hud._on_carry_adopted)
	CharacterData.character_slots = saved_slots2
	hud.free()


func _test_guild_chat_is_open() -> void:
	section("GUILD CHAT — the tab asks the server, and shows what it says")

	var packed: PackedScene = load("res://scene/ui/chat/chatpanel.tscn") as PackedScene
	check("chatpanel.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return
	var chat: Control = packed.instantiate() as Control
	add_child(chat)
	chat.visible = true
	await get_tree().process_frame

	chat._show_channel("guild")
	check("opening the Guild tab no longer says guilds are not in the game",
		not chat.notice.text.contains("not in the game"), chat.notice.text)
	check("the poll asks the server for guild chat",
		chat._poll_path() == "/api/chat?channel=guild&since=0", chat._poll_path())
	check("nothing refuses guild on this side - the server knows if you are in one",
		chat._local_refusal("guild") == "")
	chat._whisper_with = ""
	check("a whisper to nobody is still the one local refusal",
		chat._local_refusal("private").begins_with("Type who you want to whisper to"))
	check("and the poll does not ask for it", (func() -> String:
		chat._channel = "private"
		var asked: String = chat._poll_path()
		chat._channel = "guild"
		return asked).call() == "")

	# ---- a guild line arrives ----
	var now: int = int(Time.get_unix_time_from_system())
	chat._apply_read("guild", {"channel": "guild", "available": true, "latest_id": 5, "removed": [],
		"messages": [{"id": 5, "by": "rowdy", "role": "player", "name_hue": 120,
			"guild_tag": "THE FIRST", "body": "oi bruv", "at": now}]})
	await get_tree().process_frame
	var lines: Array = chat._feeds["guild"]["lines"]
	check("a guild line from the server lands in the guild feed",
		lines.size() == 1 and str((lines[0] as Dictionary).get("body", "")) == "oi bruv", lines)
	check("and moves the guild cursor", int(chat._feeds["guild"]["cursor"]) == 5)
	var shown: Array = []
	for child in chat.lines_box.get_children():
		for text_node in [child] + child.find_children("*", "RichTextLabel", true, false):
			if text_node is RichTextLabel:
				shown.append((text_node as RichTextLabel).get_parsed_text())
	check("and is drawn on the Guild tab, tag and all",
		" ".join(shown).contains("rowdy: oi bruv") and " ".join(shown).contains("THE FIRST"), shown)

	# ---- not in a guild: the server's words, not a guess ----
	var told: String = "You are not in a guild yet. Open Guild to found one, or answer an invite."
	chat._apply_read("guild", {"channel": "guild", "available": false, "notice": told,
		"messages": [], "removed": [], "latest_id": 0})
	check("not in a guild shows what the server said", chat.notice.text == told, chat.notice.text)
	check("and a player removed from a guild stops seeing its last page",
		(chat._feeds["guild"]["lines"] as Array).is_empty())
	# WHILE THE ROOM IS SHUT a send is tried and refused - a different notice
	# now stands. The room opening must take down ITS notice and only that.
	chat._set_notice("That was refused for another reason.")
	chat._apply_read("guild", {"channel": "guild", "available": true, "latest_id": 6, "removed": [],
		"messages": []})
	check("a refusal from a send is not wiped when the room opens",
		chat.notice.text == "That was refused for another reason.", chat.notice.text)
	chat._apply_read("guild", {"channel": "guild", "available": false, "notice": told,
		"messages": [], "removed": [], "latest_id": 0})
	chat._apply_read("guild", {"channel": "guild", "available": true, "latest_id": 6, "removed": [],
		"messages": []})
	check("but the room's own notice comes down when you join", chat.notice.text == "", chat.notice.text)

	# ---- Say and the picture button go through the same gate ----
	var chat_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/chat/chatpanel.gd"))
	check("no code path says guilds are not in the game any more",
		not chat_src.contains('_set_notice("Guilds are not in the game yet.")'))
	var say_at: int = chat_src.find("func _on_send_pressed")
	var say_end: int = chat_src.find("\nfunc ", say_at + 10)
	check("Say asks _local_refusal() and then sends to the open channel, guild included",
		_within(chat_src.find("_local_refusal(_channel)", say_at), say_end) != -1
		and _within(chat_src.find("await _send(_channel, text, \"\")", say_at), say_end) != -1)
	var pic_at: int = chat_src.find("func _postable_channel")
	check("and so does the picture button",
		_within(chat_src.find("_local_refusal(_channel)", pic_at), chat_src.find("\nfunc ", pic_at + 10)) != -1)
	var poll_at: int = chat_src.find("func _poll()")
	check("and the poll hands every answer to _apply_read()",
		_within(chat_src.find("_apply_read(asked, data)", poll_at), chat_src.find("\nfunc ", poll_at + 10)) != -1)

	chat.queue_free()


# =============================================================================
# STAFF DESK — TRADES: "he scammed me", checked from the desk
# =============================================================================
# Every finished trade is kept so a report can be checked, and until now the
# only way to check one was sqlite3 on the server. The server half is
# test_trades.py (T-12): reach, paging by a pair cursor, the tally. These are
# the desk's half, driven with pages in the shape the server sends.

func _test_the_staff_desk_reads_trades() -> void:
	section("STAFF DESK — TRADES: what an account gave, got and paid, one page at a time")

	var packed: PackedScene = load("res://scene/ui/staff/staffpanel.tscn") as PackedScene
	check("staffpanel.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return
	var StaffPanel: Script = load("res://src/ui/staff/staffpanel.gd") as Script
	var was_role: String = Api.role
	Api.role = "mod"
	var panel: Control = packed.instantiate() as Control
	add_child(panel)
	panel.visible = true
	panel._log_loaded = true
	await get_tree().process_frame
	panel._selected = "alice"
	panel._selected_entry = {"username": "alice", "role": "player", "actionable": true}
	panel._show_detail(panel._selected_entry)

	check("the Trades tab is the third tab", panel.detail_tabs.get_tab_title(panel.TRADES_TAB) == "Trades")

	# ---- a page ----
	var now: int = 1_790_000_000
	panel._apply_trades_page({"ok": true, "status": 200, "data": {
		"username": "alice", "more": true, "next_before": {"at": 1789990000.0, "seq": 42.0},
		"summary": {"done": 17, "cancelled": 13, "open": 1}, "now": now,
		"trades": [_staff_trade("done", now - 100), _staff_trade("cancelled", now - 200),
			_staff_trade("open", now - 300)]}}, "fresh", "alice")
	await get_tree().process_frame
	var rows: Array = panel.trade_list.get_children()
	check("each trade is a row", rows.size() == 3, rows.size())
	var first: Label = rows[0] as Label if rows.size() > 0 else Label.new()
	var pet: String = _trade_panel_script().item_name("petboss")
	check("a finished trade reads from the account's side, with whom and on which character",
		first.text.ends_with("with Rowan (rowdy), as Aldra: got 1,500 gold for %s. The kingdom took 75 gold." % pet),
		first.text)
	check("in the same words the player's own history uses",
		first.text.contains(_trade_panel_script().exchange_text(_staff_trade("done", now))))
	var second: Label = rows[1] as Label if rows.size() > 1 else Label.new()
	check("a called-off one says so, and what it would have done",
		second.text.contains("called off (it would have got 1,500 gold for %s)" % pet), second.text)
	var third: Label = rows[2] as Label if rows.size() > 2 else Label.new()
	check("an open one says so - a scam is often reported mid-attempt",
		third.text.contains("still open (so far it would get 1,500 gold for %s)" % pet), third.text)
	check("finished, called off and open are told apart by colour too",
		first.get_theme_color("font_color") != second.get_theme_color("font_color")
		and third.get_theme_color("font_color") != first.get_theme_color("font_color"))
	check("the tally comes first", panel.trade_summary.text == "Trades: 17 finished · 13 called off · 1 open",
		panel.trade_summary.text)
	check("and on the tab", panel.detail_tabs.get_tab_title(panel.TRADES_TAB) == "Trades (17)",
		panel.detail_tabs.get_tab_title(panel.TRADES_TAB))
	check("the tooltip carries the trade id the ledger names, and the other person",
		first.tooltip_text.contains("Trade abcdef12") and first.tooltip_text.contains("Click to open rowdy"),
		first.tooltip_text)
	check("and the row opens them", first.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND
		and first.gui_input.get_connections().size() == 1)

	# ---- paging by the pair cursor ----
	check("Older trades is offered", panel.trade_more.visible)
	var asked: Dictionary = panel._trades_params("more")
	check("and asks for the page after (at, seq) - JSON's floats made whole",
		asked.get("before_at") == 1789990000 and asked.get("before_seq") == 42
		and asked.get("username") == "alice", asked)
	panel._apply_trades_page({"ok": true, "status": 200, "data": {"more": false, "next_before": null,
		"summary": {"done": 17}, "now": now, "trades": [_staff_trade("done", now - 400)]}}, "more", "alice")
	check("the next page is added below, not in place", panel.trade_list.get_child_count() == 4)
	check("and the last page takes the button away", not panel.trade_more.visible
		and panel._trades_params("more").is_empty())
	panel._apply_trades_page({"ok": true, "status": 200, "data": {"more": true, "next_before": null,
		"summary": {}, "now": now, "trades": []}}, "fresh", "alice")
	check("'more' with no cursor is not believed", not panel.trade_more.visible)
	check("an empty history says so", panel.trade_empty.visible
		and panel.trade_empty.text == "alice has not traded with anybody.", panel.trade_empty.text)
	check("the cursor reader refuses nothing-shaped cursors",
		StaffPanel.trade_cursor({"next_before": null}).is_empty()
		and StaffPanel.trade_cursor({"next_before": {"at": 0, "seq": 5}}).is_empty()
		and StaffPanel.trade_cursor({}).is_empty())

	# ---- out of reach reads like no account ----
	panel._apply_trades_page({"ok": false, "status": 404, "error": "No such account."}, "fresh", "alice")
	check("out of reach is said plainly", panel.trade_empty.text == "You cannot read this account's trades.",
		panel.trade_empty.text)

	# ---- the tab loads itself, and a new pick forgets the old ----
	panel._trades_for = ""
	panel.detail_tabs.current_tab = panel.TRADES_TAB
	# READ AT ONCE, not a frame later. _load_trades() writes this line before
	# its first await; a frame is long enough for a refused connection to come
	# back and write "Could not read trades" over it, which is how this check
	# failed on a machine with nothing listening on the port.
	check("opening the Trades tab asks for that account's trades",
		panel.trade_empty.text == "Reading alice's trades...", panel.trade_empty.text)
	await get_tree().process_frame
	panel._apply_trades_page({"ok": true, "status": 200, "data": {"more": false, "summary": {"done": 2},
		"now": now, "trades": [_staff_trade("done", now)]}}, "fresh", "alice")
	panel._pick("rowdy")
	check("picking somebody else forgets alice's trades at once",
		panel._trades.is_empty() and panel._trades_for == "", panel._trades.size())
	check("and asks for theirs, since the Trades tab is the one open",
		panel.trade_empty.text == "Reading rowdy's trades...", panel.trade_empty.text)
	check("the tab title does not carry alice's count onto rowdy",
		panel.detail_tabs.get_tab_title(panel.TRADES_TAB) == "Trades")

	panel.queue_free()
	Api.role = was_role


func _test_the_friends_header_reads_well() -> void:
	section("FRIENDS — a title, a line in words, and one ×")

	var packed: PackedScene = load("res://scene/ui/friends/friendspanel.tscn") as PackedScene
	check("friendspanel.tscn loads", packed != null and packed.can_instantiate())
	if packed == null or not packed.can_instantiate():
		return
	var Friends: Script = load("res://src/ui/friends/friendspanel.gd") as Script
	var panel: Control = packed.instantiate() as Control
	add_child(panel)
	panel.visible = true
	await get_tree().process_frame
	var now: int = 1_790_000_000
	panel._repaint({"now": now,
		"friends": [
			{"username": "rowdy", "role": "player", "online": true, "last_seen_at": now},
			{"username": "quietone", "role": "mod", "online": false, "last_seen_at": now - 7200},
			{"username": "Tunacan", "role": "owner", "online": true, "last_seen_at": now},
			{"username": "p001", "role": "player", "online": false, "last_seen_at": now - 86400 * 5}],
		"incoming": [{"username": "newbie", "role": "player", "online": true, "last_seen_at": now}],
		"outgoing": []})
	await get_tree().process_frame
	await get_tree().process_frame

	var header: Node = panel.get_node("frame/margin/rows/headerpanel")
	var letters: Array = []
	for b in header.find_children("*", "Button", true, false):
		letters.append((b as Button).text)
	check("the header has one button, the same × as every other panel", letters == ["×"], letters)
	check("and no R: the list re-reads itself", panel.get_node_or_null("%friendsrefreshbutton") == null)
	check("the × is flat, like the guild's and the trade window's",
		(panel.close_button as Button).flat)
	check("the line under the title is words", panel.count_label.text == "2 of 4 friends online",
		panel.count_label.text)
	check("a request waiting is said in the header too",
		panel.requests_label.visible and panel.requests_label.text == "· 1 request waiting",
		panel.requests_label.text)
	var fits := func(label: Label) -> bool:
		var need: float = label.get_theme_font("font").get_string_size(label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		return label.size.x + 0.5 >= need
	check("both fit, whole", fits.call(panel.count_label) and fits.call(panel.requests_label),
		[panel.count_label.size.x, panel.requests_label.size.x])

	panel._repaint({"now": now, "friends": [], "incoming": [], "outgoing": []})
	check("nobody yet is said in words, not '0 online of 0'",
		panel.count_label.text == "nobody on your list yet" and not panel.requests_label.visible,
		panel.count_label.text)
	var one_on: Array = [{"online": true}]
	var one_off: Array = [{"online": false}]
	check("one friend reads as one", Friends.header_line(one_on) == "1 friend, online"
		and Friends.header_line(one_off) == "1 friend, offline")
	check("everybody on, nobody on",
		Friends.header_line([{"online": true}, {"online": true}]) == "2 friends, all online"
		and Friends.header_line([{"online": false}, {"online": false}]) == "2 friends, none online")
	check("more than one request", Friends.requests_text(3) == "· 3 requests waiting"
		and Friends.requests_text(0) == "")

	panel.close_button.emit_signal("pressed")
	check("the × closes it", not panel.visible)
	panel.queue_free()



# =============================================================================
# THE LOGIN SCREEN DOES NOT WAIT FOR THE WORLD
# =============================================================================
# characterselect.gd used to preload elusion.tscn, and loginmenu.tscn exports
# characterselect.tscn, so the login screen's first frame waited on the town,
# the field it exports, the HUD, every panel and about sixty scripts. Measured
# cold in the sandbox: a login box at 2.6 s, 1.8 s of it the world. Now the
# town loads on a worker thread while the player types (AreaRegistry.prefetch)
# and the login box is up in under a second.
#
# THE WALK IS THE CHECK. A preload is invisible to get_dependencies(), which is
# exactly how this chain went unnoticed: nothing in the scene file named the
# town. So the walk reads the preloads out of every script it passes through.

func _test_one_thread_loads_in_the_background() -> void:
	# The owner, twice on 0.74.x: Play stuck on "Loading the world..." for good.
	# Two of Godot's workers loading at once deadlock on a script's preloads
	# (arearegistry.gd, "BACKGROUND LOADS ARE SAFE ON ONE THREAD ONLY"). This
	# sandbox has two cores, so it always had one loading thread and can never
	# show the deadlock - which is why the rule is held here as numbers.
	section("LOADING — the background loads on one thread, so it cannot deadlock (0.74.2)")
	check("Godot's own sum, as loader_threads() works it: 16 threads at its default 0.3 load on 4",
		_AreaRegistryCode.loader_threads(16, 0.3) == 4, _AreaRegistryCode.loader_threads(16, 0.3))
	var sums: Array = [_AreaRegistryCode.loader_threads(2, 0.3), _AreaRegistryCode.loader_threads(1, 0.3),
		_AreaRegistryCode.loader_threads(16, 0.9)]
	check("  2 threads on 1, 1 thread on 1, and 16 at 0.9 on 14", sums == [1, 1, 14], sums)
	var ratio: float = float(ProjectSettings.get_setting(_AreaRegistryCode.LOADER_RATIO_SETTING, 0.3))
	check("project.godot sets the loading ratio so that a 64-thread computer loads on one",
		_AreaRegistryCode.loader_threads(64, ratio) == 1, ratio)
	check("  and so does this one", _AreaRegistryCode.loader_threads(-1, ratio) == 1, [OS.get_processor_count(), ratio])
	var pool_setting: Variant = ProjectSettings.get_setting(_AreaRegistryCode.POOL_THREADS_SETTING, -1)
	var ratio_setting: Variant = ProjectSettings.get_setting(_AreaRegistryCode.LOADER_RATIO_SETTING, 0.3)
	ProjectSettings.set_setting(_AreaRegistryCode.POOL_THREADS_SETTING, 16)
	ProjectSettings.set_setting(_AreaRegistryCode.LOADER_RATIO_SETTING, 0.3)
	var would_with_four: bool = _AreaRegistryCode.loads_in_background()
	ProjectSettings.set_setting(_AreaRegistryCode.LOADER_RATIO_SETTING, ratio_setting)
	var would_with_one: bool = _AreaRegistryCode.loads_in_background()
	ProjectSettings.set_setting(_AreaRegistryCode.POOL_THREADS_SETTING, pool_setting)
	check("were the setting ever lost, nothing would load ahead - slower, never stuck",
		not would_with_four and would_with_one, [would_with_four, would_with_one])


func _test_the_world_loads_in_the_background() -> void:
	section("LOADING — the login screen does not wait for the world")

	var areas: Dictionary = AreaRegistry.AREAS
	var login := _load_closure("res://scene/ui/menus/loginmenu.tscn")
	check("the walk reaches character select's script (it is not blind)",
		login.has("res://src/ui/menus/characterselect.gd"), login.keys().size())
	var town_walk := _load_closure(areas["elusion"])
	check("and it follows an exported scene: the town pulls the Big Field, where its portal leads (0.15.0)",
		town_walk.has(areas["bigfield"]))
	var hud_walk := _load_closure("res://src/ui/characterhud.gd")
	check("and a script's preloads: the HUD pulls the trade window",
		hud_walk.has("res://scene/ui/trade/tradepanel.tscn"))
	var pulled: Array = []
	for area_id in areas:
		if login.has(areas[area_id]):
			pulled.append(_chain(login, areas[area_id]))
	check("the login screen's load pulls in no area", pulled.is_empty(), pulled)

	var world: PackedScene = load(areas["elusion"]) as PackedScene
	check("the town still loads - what the preload used to promise",
		world != null and world.can_instantiate())

	# ---- who asks for it -------------------------------------------------
	var Select: Script = load("res://src/ui/menus/characterselect.gd") as Script
	var world_area: String = str(Select.get_script_constant_map().get("WORLD_AREA", ""))
	check("character select names the area it starts in, and it is an area",
		areas.has(world_area), world_area)
	var login_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/menus/loginmenu.gd"))
	var ready_at: int = login_src.find("func _ready()")
	var ready_end: int = login_src.find("\nfunc ", ready_at + 1)
	check("the login screen starts that area loading as it opens",
		_within(login_src.find("AreaRegistry.prefetch(\"%s\")" % world_area, ready_at), ready_end) != -1)
	var select_src: String = _code_only(FileAccess.get_file_as_string("res://src/ui/menus/characterselect.gd"))
	var enter_at: int = select_src.find("func _enter_world(")
	var enter_end: int = select_src.find("\nfunc ", enter_at + 1)
	check("picking a character takes the town from the registry",
		_within(select_src.find("AreaRegistry.scene_for(WORLD_AREA)", enter_at), enter_end) != -1)
	check("and queues the other areas behind it",
		_within(select_src.find("AreaRegistry.prefetch_all()", enter_at), enter_end) != -1)
	var pick_at: int = select_src.find("func _select_character(")
	check("a second click cannot change the character mid-load",
		select_src.find("if _entering", pick_at) != -1
		and select_src.find("if _entering", pick_at) < select_src.find("active_character_index = idx", pick_at))

	# Forget the town first, or a town already held would pass this for free.
	var settle_first: int = Time.get_ticks_msec() + 20000
	while AreaRegistry.is_loading(world_area) and Time.get_ticks_msec() < settle_first:
		await get_tree().process_frame
	AreaRegistry._cache.erase(world_area)
	var screen_packed: PackedScene = load("res://scene/ui/menus/characterselect.tscn") as PackedScene
	var screen: Control = screen_packed.instantiate() as Control
	add_child(screen)
	await get_tree().process_frame
	check("character select asks for the town too (arriving from the world)",
		AreaRegistry.is_loading(world_area) or AreaRegistry._cache.has(world_area))
	screen._show_loading(2)
	var locked: bool = true
	for b in screen.find_children("*", "Button", true, false):
		if str(b.name).begins_with("selectbutton") or str(b.name).begins_with("createbutton"):
			locked = locked and (b as Button).disabled
	check("while it finishes the screen says so, and every slot button waits",
		screen.get_node("%label3").text == "Loading the world..." and locked,
		screen.get_node("%label3").text)
	screen.queue_free()

	# ---- the registry --------------------------------------------------------
	check("an area that does not exist is refused", not AreaRegistry.prefetch("nowhere"))
	# Settle whatever the screen above started, then forget two areas so the
	# loader has real work.
	var settle_until: int = Time.get_ticks_msec() + 20000
	while (not AreaRegistry._prefetching.is_empty() or not AreaRegistry._prefetch_queue.is_empty()) \
			and Time.get_ticks_msec() < settle_until:
		await get_tree().process_frame
	AreaRegistry._cache.erase("boss")
	AreaRegistry._cache.erase("bossarena")
	AreaRegistry._cache.erase("easteregg")
	var to_load: int = 0
	for area_id in areas:
		if not AreaRegistry._cache.has(area_id):
			to_load += 1
	AreaRegistry.prefetch_all()
	check("prefetch_all() starts one load and queues the rest",
		to_load >= 3 and AreaRegistry._prefetching.size() == 1
		and AreaRegistry._prefetch_queue.size() == to_load - 1,
		[to_load, AreaRegistry._prefetching.keys(), AreaRegistry._prefetch_queue])
	check("and the registry is watching for it", AreaRegistry.is_processing())
	var most_at_once: int = 0
	var until: int = Time.get_ticks_msec() + 20000
	while (not AreaRegistry._prefetching.is_empty() or not AreaRegistry._prefetch_queue.is_empty()) \
			and Time.get_ticks_msec() < until:
		most_at_once = maxi(most_at_once, AreaRegistry._prefetching.size())
		await get_tree().process_frame
	check("one at a time, all the way through", most_at_once == 1, most_at_once)
	var all_held: bool = true
	var same_object: bool = true
	for area_id in areas:
		all_held = all_held and AreaRegistry._cache.get(area_id) is PackedScene
		same_object = same_object and load(areas[area_id]) == AreaRegistry._cache.get(area_id)
	check("every area ends up held", all_held, AreaRegistry._cache.keys())
	check("and a door's load() gets the very scene the loader made", same_object)
	check("the registry stops watching once there is nothing to collect",
		not AreaRegistry.is_processing())

	# The door is reached before the loader is done: scene_for() waits for it
	# rather than loading it a second time.
	AreaRegistry._cache.erase("bossarena")
	AreaRegistry.prefetch("bossarena")
	var early: PackedScene = AreaRegistry.scene_for("bossarena")
	check("an area asked for mid-load comes back whole",
		early != null and early.can_instantiate() and AreaRegistry._cache.get("bossarena") == early
		and not AreaRegistry.is_loading("bossarena"))

	# An area still waiting its turn is loaded on the spot and leaves the queue.
	AreaRegistry._cache.erase("boss")
	AreaRegistry._cache.erase("easteregg")
	AreaRegistry.prefetch("boss")
	AreaRegistry.prefetch("easteregg")
	var queued_now: bool = AreaRegistry._prefetch_queue.has("easteregg")
	var jumped: PackedScene = AreaRegistry.scene_for("easteregg")
	check("an area still queued is loaded when asked for, and leaves the queue",
		queued_now and jumped != null and not AreaRegistry._prefetch_queue.has("easteregg"),
		[queued_now, AreaRegistry._prefetch_queue])

	# Landing a teleport used to switch the registry's _process() off. With a
	# load still running that would strand it: finished, never collected.
	var stand_in := Node2D.new()
	stand_in.add_to_group("player")
	add_child(stand_in)
	AreaRegistry._arm_spawn(Vector2(12, 34))
	AreaRegistry._apply_spawn_now()
	check("a teleport landing does not stop a load being collected",
		stand_in.global_position == Vector2(12, 34) and not AreaRegistry._has_pending_spawn
		and (AreaRegistry.is_processing() or not AreaRegistry.is_loading("boss")),
		[AreaRegistry.is_processing(), AreaRegistry.is_loading("boss")])
	stand_in.queue_free()
	until = Time.get_ticks_msec() + 20000
	while AreaRegistry.is_loading("boss") and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	check("and it is collected", AreaRegistry._cache.get("boss") is PackedScene)

	# ---- the doors -----------------------------------------------------------
	# In Godot 4.6.1 a plain load() of an area that is loading in the background
	# never returns - found when a sabotage of scene_for() hung this suite. The
	# doors that name their destination by path go through scene_at(), which
	# collects the background load instead. A hang cannot be a FAIL line, so the
	# rule is held by reading the code, and scene_at() is held by running it.
	AreaRegistry._cache.erase("bossarena")
	AreaRegistry.prefetch("bossarena")
	var in_flight: bool = AreaRegistry.is_loading("bossarena")
	var through_door: PackedScene = AreaRegistry.scene_at(areas["bossarena"])
	check("a door reached mid-load gets the area, from the registry",
		in_flight and through_door != null and through_door == AreaRegistry._cache.get("bossarena")
		and not AreaRegistry.is_loading("bossarena"))
	var not_an_area: PackedScene = AreaRegistry.scene_at("res://scene/ladderdown.tscn")
	check("and a scene that is not an area still loads the ordinary way",
		not_an_area != null and not AreaRegistry._cache.values().has(not_an_area))

	var area_literals: Array = []
	for area_id in areas:
		area_literals.append("\"%s\"" % areas[area_id])
	var offenders: Array = []
	var dir_stack: Array = ["res://src"]
	while not dir_stack.is_empty():
		var dir_path: String = dir_stack.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub in dir.get_directories():
			dir_stack.append(dir_path + "/" + sub)
		for file_name in dir.get_files():
			if not file_name.ends_with(".gd") or file_name.begins_with("testrunner") or file_name == "arearegistry.gd":
				continue
			var code: String = _code_only(FileAccess.get_file_as_string(dir_path + "/" + file_name))
			for call_text in ["load(", "preload(", "change_scene_to_file(", "load_threaded_request("]:
				var at: int = code.find(call_text)
				while at != -1:
					var arg: String = code.substr(at + call_text.length(), 48).split(")")[0].strip_edges()
					if arg in ["destination_scene_path", "world_scene_path"] or area_literals.has(arg):
						offenders.append("%s: %s%s)" % [file_name, call_text, arg])
					at = code.find(call_text, at + 1)
	check("no script loads an area by path behind the registry's back", offenders.is_empty(), offenders)
	for door in ["res://src/world/ladder.gd", "res://src/world/victoryteleporter.gd",
			"res://src/ui/menus/gameover.gd"]:
		check("%s goes through AreaRegistry.scene_at()" % door.get_file(),
			_code_only(FileAccess.get_file_as_string(door)).contains("AreaRegistry.scene_at("))

	# Leave nothing loading for the sections after this one.
	until = Time.get_ticks_msec() + 20000
	while (not AreaRegistry._prefetching.is_empty() or not AreaRegistry._prefetch_queue.is_empty()) \
			and Time.get_ticks_msec() < until:
		await get_tree().process_frame


# =============================================================================
# RARE LOOT LOOKS RARE
# =============================================================================
# Nothing marked an item as rare before: an Ember Cuirass sat in a loot bag
# looking exactly like an iron one, and the only "legendary" effect in the game
# was petbeam, a flat Line2D poking 149 pixels out of the sack. Now a tier has a
# name and a colour (GameConstants' RARITY), every slot frames uncommon and up
# in it, the tooltip names it, and a bag on the ground glows for epic or better.
#
# The loot bag panel was also fixed-size - a 200-pixel scroll area under a
# two-item bag - with stack counts at font size 7 and no way to empty it but a
# double-click per cell.

func _test_presence_carries_the_monsters() -> void:
	section("SHARED MONSTERS - the presence link carries who leads, the world and the hits")
	Presence.set_process(false)
	Presence.stop()
	var got: Dictionary = {"lead": [], "world": [], "hits": [], "need": []}
	var on_lead := func(a: String, id: int, n: int) -> void: got["lead"].append([a, id, n])
	var on_world := func(d: Dictionary) -> void: got["world"].append(d)
	var on_hits := func(from_id: int, hits: Array) -> void: got["hits"].append([from_id, hits])
	var on_need := func(id: int) -> void: got["need"].append(id)
	Presence.lead_changed.connect(on_lead)
	Presence.world_received.connect(on_world)
	Presence.hits_received.connect(on_hits)
	Presence.world_needed.connect(on_need)
	Presence._phase = "open"

	check("the game says it speaks shared monsters when it says hello",
		_code_src("res://src/systems/presence.gd").contains('"t": "hello", "ticket": _ticket, "v": SHARED_VERSION'))
	check("  and that others' attacks may ride the tick (0.76.0)",
		_code_src("res://src/systems/presence.gd").contains('"v": SHARED_VERSION, "xt": TICK_ATTACKS,')
		and Presence.TICK_ATTACKS == 1)
	check("  and that it draws the server's count of the monsters' health (0.87.0)",
		_code_src("res://src/systems/presence.gd").contains('"sh": SERVER_HEALTH, "en": RUN_VERSION})')
		and Presence.SERVER_HEALTH == 1)
	Presence.handle_message({"t": "welcome", "id": 7})
	check("a server from before shared monsters does not share them - every game fights its own",
		not Presence.shares())
	Presence.handle_message({"t": "welcome", "id": 7, "v": 2})
	check("  one that says so does", Presence.shares() and Presence.my_id() == 7)
	Presence.handle_message({"t": "lead", "a": "field", "id": 9, "n": 1})
	check("who leads an area is passed on", got["lead"] == [["field", 9, 1]], got["lead"])
	check("  and remembered for that area only",
		Presence.leader_for("field") == 9 and Presence.leader_for("bigfield") == -2 and Presence.sharers() == 1)
	Presence.handle_message({"t": "need", "id": 12})
	check("the server asking for everything for a game is passed on", got["need"] == [12], got["need"])
	Presence.handle_message({"t": "w", "d": {"snap": [[1, 2.0, 3.0, "idledown", 10]]}})
	Presence.handle_message({"t": "w", "d": "not a world"})
	check("the leader's world is passed on, and nothing that is not one",
		got["world"].size() == 1 and (got["world"][0] as Dictionary).has("snap"), got["world"])
	Presence.handle_message({"t": "h", "from": 3, "p": [[1, 20, 0]]})
	check("another game's hits are passed on with who sent them",
		got["hits"].size() == 1 and got["hits"][0][0] == 3, got["hits"])
	Presence.stop()
	check("when the link goes, nobody leads any more - a follower takes its monsters back",
		got["lead"].size() == 2 and got["lead"][1][1] == -1 and not Presence.shares(), got["lead"])

	Presence.lead_changed.disconnect(on_lead)
	Presence.world_received.disconnect(on_world)
	Presence.hits_received.disconnect(on_hits)
	Presence.world_needed.disconnect(on_need)
	Presence._server_shares = false
	Presence._failures = 0
	Presence.set_process(true)


func _test_shared_monsters_lead() -> void:
	section("SHARED MONSTERS - the leader runs them and says what they do")
	var world: Node2D = _sm_world()
	var fs: BaseEnemy = world.get_node("enemies/fs1")
	var sn: BaseEnemy = world.get_node("enemies/sn1")
	var link := FakeLink.new()
	link.area = SM_AREA
	link.leader = 1
	add_child(link)
	var sync: Node = _sm_sync(link)
	world.add_child(sync)
	await get_tree().process_frame

	check("the game the server names leads, and runs the monsters", sync.has_authority())
	check("  every monster gets a number, and the conductor",
		fs.net_id > 0 and sn.net_id > 0 and fs.net_id != sn.net_id and fs._net_sync == sync,
		[fs.net_id, sn.net_id])
	check("  and none of them is a mirror", not fs.net_mirror and not sn.net_mirror)
	var full: Dictionary = _sm_last_world(link)
	check("it tells the others everything at once, as a reset - these numbers are new",
		bool(full.get("full", false)) and bool(full.get("reset", false))
		and (full.get("spawn", []) as Array).size() == 2, full)
	var rec: Dictionary = {}
	for r in full.get("spawn", []):
		if int(r.get("id", -1)) == fs.net_id:
			rec = r
	check("  a record names the scene, the spot it was authored at, and its profile",
		rec.get("s", "") == "res://scene/enemy/firesprite.tscn"
		and str(rec.get("o", "")).ends_with("smworld/enemies/fs1")
		and str(rec.get("p", {}).get("ed", "")).begins_with("res://data/enemies/"), rec)

	link.sent_world.clear()
	fs.global_position += Vector2(12, 0)
	sync.tick_lead()
	var delta: Dictionary = _sm_last_world(link)
	var moved: Array = []
	for st in delta.get("snap", []):
		moved.append(int(st[0]))
	check("a tick sends only the monster that moved", moved == [fs.net_id], delta)
	link.sent_world.clear()
	sync.tick_lead()
	check("  and nothing at all when nothing did", link.sent_world.is_empty(), link.sent_world)

	var arrow: Node = (load("res://scene/projectiles/arrow.tscn") as PackedScene).instantiate()
	arrow.shoot_vector(Vector2(3, 4))
	sn.spawn_projectile_node(arrow, Vector2(-20100, -19990))
	sync.tick_lead()
	var shot: Dictionary = {}
	for ev in _sm_last_world(link).get("ev", []):
		if ev.get("k", "") == "p":
			shot = ev
	check("a monster's shot goes to every screen, from where it left, aimed the same way",
		int(shot.get("id", -1)) == sn.net_id and shot.get("s", "") == "res://scene/projectiles/arrow.tscn"
		and is_equal_approx(float(shot.get("ax", 0)), 0.6) and is_equal_approx(float(shot.get("ay", 0)), 0.8)
		and is_equal_approx(float(shot.get("y", 0)), -19990.0), shot)
	await get_tree().process_frame

	var hp_before: int = fs.hp
	link.deliver_hits(2, [[fs.net_id, 30, 0], [99999, 50, 0], ["x", 1, 0]])
	check("another player's hit lands on the leader's monster", fs.hp == hp_before - 30, [hp_before, fs.hp])
	check("  as theirs: this game's player has not helped", fs._net_remote_hit and not fs._net_local_hit)
	check("  so a kill from here would not be this game's to report", not fs._should_report_kill())
	sn.take_damage(5)
	check("this game's own hit counts as helping", sn._net_local_hit and sn._should_report_kill())
	var alone: BaseEnemy = (load("res://scene/enemy/firesprite.tscn") as PackedScene).instantiate()
	check("  and a monster nobody else touched is reported as always", alone._should_report_kill())
	alone.free()

	link.sent_world.clear()
	sync._on_hits(2, [[fs.net_id, 100000, 0]])
	sync.tick_lead()
	var died: Dictionary = {}
	for ev in _sm_last_world(link).get("ev", []):
		if ev.get("k", "") == "die":
			died = ev
	check("a monster killed by another player's hit dies on every screen", int(died.get("id", -1)) > 0, died)
	check("  and the leader stops talking about it", not sync.monsters().has(int(died.get("id", -1))))

	link.sent_world.clear()
	link.deliver_need(7)
	var to_seven: Array = link.sent_world.filter(func(m: Array) -> bool: return m[1] == 7)
	check("a game walking in is sent everything, to it alone",
		to_seven.size() == 1 and bool((to_seven[0][0] as Dictionary).get("full", false))
		and not bool((to_seven[0][0] as Dictionary).get("reset", true)), link.sent_world)

	link.n = 0
	link.sent_world.clear()
	sn.global_position += Vector2(0, 30)
	sync.tick_lead()
	check("with nobody else in the area, nothing is sent at all", link.sent_world.is_empty())

	world.free()
	link.free()


func _test_shared_monsters_follow() -> void:
	section("SHARED MONSTERS - a follower draws the leader's, and sends its hits")
	var world: Node2D = _sm_world()
	var fs: BaseEnemy = world.get_node("enemies/fs1")
	var sn: BaseEnemy = world.get_node("enemies/sn1")
	var link := FakeLink.new()
	link.me = 2
	add_child(link)
	var sync: Node = _sm_sync(link)
	var kills: Array = []
	sync.report_kill = func(enemy_id: String, at: Vector2, _who: Node) -> void: kills.append([enemy_id, at])
	world.add_child(sync)
	await get_tree().process_frame

	check("a game that has not heard who leads holds every monster still",
		not sync.has_authority() and fs.net_mirror and sn.net_mirror)
	link.lead_changed.emit(SM_AREA, 1, 1)
	check("told somebody else leads, it follows", sync.is_following())
	check("  and asks for nothing yet - the leader was asked when it walked in", link.asked == 0)

	var origin_fs: String = str(fs.get_meta(&"net_origin", ""))
	var full: Dictionary = {"full": true, "reset": false, "part": 0, "parts": 1, "wave": -1, "spawn": [
		{"id": 4, "o": origin_fs, "s": "res://scene/enemy/firesprite.tscn", "pp": "smworld/enemies",
			"x": -19950.0, "y": -20000.0, "a": "walkleft", "hp": 300, "mh": fs.max_hp,
			"p": fs.net_props()},
		{"id": 9, "o": "", "s": "res://scene/enemy/poisonslime.tscn", "pp": "smworld/enemies",
			"x": -19900.0, "y": -19950.0, "a": "smallidledown", "hp": 60, "mh": 80,
			"p": {"ed": "res://data/enemies/poisonslimesmall.tres", "eo": -1, "lr": 400.0, "g": false,
				"hx": -19900.0, "hy": -19950.0, "sm": true, "du": true, "sp": true}},
		{"id": 11, "o": "", "s": "res://scene/ui/characterhud.tscn", "x": 0, "y": 0, "hp": 1},
	]}
	link.world_received.emit(JSON.parse_string(JSON.stringify(full)))
	var sniper_gone: bool = sn._death_resolved and sn.is_queued_for_deletion()
	await get_tree().process_frame
	var mirrors: Dictionary = sync.monsters()
	check("the leader's monster is matched to the one authored at the same spot",
		mirrors.get(4) == fs and fs.net_id == 4, mirrors.keys())
	check("  moved to where the leader has it, with the leader's health",
		fs.global_position.distance_to(Vector2(-19950, -20000)) < 0.5 and fs.hp == 300,
		[fs.global_position, fs.hp])
	var slime: BaseEnemy = mirrors.get(9)
	check("a monster this game never had is built, as a mirror, in the leader's form",
		slime != null and slime.net_mirror and bool(slime.get("is_small"))
		and slime.global_position.distance_to(Vector2(-19900, -19950)) < 0.5, slime)
	check("one the leader does not have goes", sniper_gone)
	check("and nothing outside the enemy scenes is ever built from a world message",
		not mirrors.has(11))

	var start: Vector2 = fs.global_position
	sync.apply_world({"snap": [[4, -19930.0, -20000.0, "attackleft", 250]]})
	check("a tick from the leader sets what it is playing and its health",
		fs.current_anim == "attackleft" and fs.hp == 250, [fs.current_anim, fs.hp])
	for i in range(10):
		await get_tree().physics_frame
	check("  and it walks there rather than jumping",
		fs.global_position.x > start.x and fs.global_position.x <= -19930.0 + 0.5, fs.global_position)

	var hp_now: int = fs.hp
	fs.take_damage(12)
	check("your hit on a mirror changes nothing here", fs.hp == hp_now and not fs._death_resolved)
	sync._flush_hits()
	var sent: Array = []
	for batch in link.sent_hits:
		for hit in batch:
			sent.append([int(hit[0]), int(hit[1]), int(hit[2])])
	check("  it goes to the leader", sent == [[4, 12, 0]], link.sent_hits)

	sync.apply_world({"ev": [{"k": "p", "id": 4, "s": "res://scene/projectiles/fireprojectile.tscn",
		"x": -19930.0, "y": -20010.0, "ax": 1.0, "ay": 0.0}]})
	await get_tree().process_frame
	var shots: Node = get_tree().get_first_node_in_group("projectiles")
	# ON ITS LINE FROM THAT SPOT, not exactly on it: the shot is added at the
	# end of a frame, and a physics step can move it along its aim (+x) before
	# process_frame - the full run caught it 0 of 1 once, 7 Oct.
	var landed: Array = shots.get_children().filter(func(n: Node) -> bool:
		if not n is Node2D:
			return false
		var off: Vector2 = (n as Node2D).global_position - Vector2(-19930, -20010)
		return absf(off.y) < 1.0 and off.x > -1.0 and off.x < 40.0)
	check("the leader's shot is fired here too, from the same spot", landed.size() == 1, landed.size())
	var count: int = shots.get_child_count()
	sync.apply_world({"ev": [{"k": "p", "id": 4, "s": "user://evil.tscn", "x": 0, "y": 0, "ax": 1, "ay": 0}]})
	await get_tree().process_frame
	check("  and nothing from outside the projectile scenes", shots.get_child_count() == count)

	var fs_id: String = fs.get_enemy_id()
	sync.apply_world({"ev": [{"k": "die", "id": 4, "x": -19930.0, "y": -20000.0},
		{"k": "die", "id": 9, "x": -19900.0, "y": -19950.0}]})
	check("a monster you hit that dies is your kill, reported by this game",
		kills.size() == 1 and kills[0][0] == fs_id, kills)
	check("  one you never touched is not", kills.size() == 1)
	check("  and both die here", fs._death_resolved and slime._death_resolved)

	link.lead_changed.emit(SM_AREA, 2, 1)
	check("when the server names this game, it takes over", sync.has_authority())
	var takeover: Dictionary = _sm_last_world(link)
	check("  and tells the others everything, keeping the numbers they know",
		bool(takeover.get("full", false)) and not bool(takeover.get("reset", true)), takeover)

	link.lead_changed.emit(SM_AREA, 1, 1)
	link.lead_changed.emit("", -1, 0)
	check("a follower whose link drops runs its own monsters again", sync.has_authority())

	world.free()
	link.free()
	await get_tree().process_frame


func _test_shared_monsters_handover() -> void:
	section("SHARED MONSTERS - handing over keeps the fight where it stands")
	var world: Node2D = _sm_world()
	var fs: BaseEnemy = world.get_node("enemies/fs1")
	var link := FakeLink.new()
	link.me = 3
	add_child(link)
	var sync: Node = _sm_sync(link)
	world.add_child(sync)
	await get_tree().process_frame
	link.lead_changed.emit(SM_AREA, 1, 1)
	var full: Dictionary = {"full": true, "reset": false, "part": 0, "parts": 1, "wave": -1, "spawn": [
		{"id": 21, "o": str(fs.get_meta(&"net_origin", "")), "s": "res://scene/enemy/firesprite.tscn",
			"pp": "smworld/enemies", "x": -19800.0, "y": -20000.0, "a": "idledown", "hp": 123,
			"mh": fs.max_hp, "p": fs.net_props()}]}
	link.world_received.emit(full)
	fs.take_damage(7)
	link.lead_changed.emit(SM_AREA, 3, 1)
	check("the mirror becomes the monster, where it stood and as hurt as it was",
		not fs.net_mirror and fs.hp == 123
		and fs.global_position.distance_to(Vector2(-19800, -20000)) < 0.5, [fs.net_mirror, fs.hp])
	check("  keeping its number", fs.net_id == 21 and sync.monsters().get(21) == fs)
	check("  and a monster you hit as a follower is one you helped kill", fs._net_local_hit)
	check("  new monsters are numbered past every number already known", sync._next_id > 21, sync._next_id)
	world.free()
	link.free()
	await get_tree().process_frame


func _test_shared_monsters_targets() -> void:
	section("SHARED MONSTERS - who a monster may chase")
	var Targets := preload("res://src/shared/targets.gd")
	var RemoteScript := preload("res://src/characters/remoteplayer.gd")
	var holder := Node2D.new()
	add_child(holder)
	var sharing: Node2D = RemoteScript.new()
	sharing.user_id = 501
	holder.add_child(sharing)
	sharing.set_identity({"id": 501, "name": "Ally", "cls": "warrior", "lvl": 3, "v": 2})
	sharing.place(Vector2(-30000, -30000))
	var old_game: Node2D = RemoteScript.new()
	old_game.user_id = 502
	holder.add_child(old_game)
	old_game.set_identity({"id": 502, "name": "Old", "cls": "mage", "lvl": 3, "v": 0})
	old_game.place(Vector2(-30010, -30000))
	var all: Array = Targets.all(get_tree())
	check("a player whose game shares monsters can be chased", all.has(sharing))
	check("  one whose game does not, cannot - its monsters are its own", not all.has(old_game))
	check("  and another player's picture is still not \"the player\"",
		not sharing.is_in_group("player") and sharing.is_in_group("remoteplayers"))
	var marker: Node2D = sharing.get_node_or_null("bodyshape")
	check("it marks the floor its class's body stands on, for a boss to aim at",
		marker != null and marker.position.distance_to(Vector2(0, 13)) < 1.0,
		str(marker.position) if marker else "no marker")
	sharing.set_target(Vector2(-29990, -30000))
	await get_tree().create_timer(0.1).timeout
	sharing.set_target(Vector2(-29970, -30000))
	check("  and works out how fast it is moving, for a boss to lead",
		sharing.velocity.x > 0.0 and absf(sharing.velocity.y) < 0.01, sharing.velocity)
	var e: BaseEnemy = (load("res://scene/enemy/firesprite.tscn") as PackedScene).instantiate()
	e.position = Vector2(-30050, -30000)
	holder.add_child(e)
	e._resolve_player()
	var local_far: bool = true
	for p in get_tree().get_nodes_in_group("player"):
		if (p as Node2D).global_position.distance_to(e.global_position) < 50000.0:
			local_far = false
	check("a monster with another player beside it goes after them",
		e.player == sharing or not local_far, e.player)
	sharing.set_motion("deathdown", [], "")
	check("  but not once they are playing their death", not Targets.all(get_tree()).has(sharing))
	holder.free()


func _test_shared_monsters_pieces() -> void:
	section("SHARED MONSTERS - the respawner, the gauntlet and the acid agree")
	# THE RESPAWNER brings back only what this game runs.
	var Respawner := preload("res://src/world/enemyrespawner.gd")
	var area := Node2D.new()
	add_child(area)
	var light: Node2D = (load("res://scene/enemy/lightsprite.tscn") as PackedScene).instantiate()
	light.position = Vector2(-40000, -40000)
	area.add_child(light)
	var respawner: Node = Respawner.new()
	respawner.spawn_scatter = 0.0
	respawner.respawn_seconds = 0.05
	respawner.respawn_jitter = 0.0
	area.add_child(respawner)
	var link := FakeLink.new()
	link.me = 2
	add_child(link)
	var sync: Node = _sm_sync(link)
	area.add_child(sync)
	await get_tree().process_frame
	await get_tree().process_frame
	link.lead_changed.emit(SM_AREA, 1, 1)
	var entry: Dictionary = respawner._census[0] if not respawner._census.is_empty() else {}
	check("every placed monster is keyed by where it was authored",
		str(entry.get("key", "")) != "" and str(light.get_meta(&"net_origin", "")) == str(entry.get("key", "")),
		entry.get("key"))
	var before: int = area.get_child_count()
	(light as BaseEnemy).net_vanish()
	check("a follower's respawner does not even start a clock when its monster dies",
		not bool(entry.get("pending", false)))
	await get_tree().create_timer(0.3).timeout
	check("  and brings nothing back - the leader does",
		area.get_child_count() <= before and not bool(entry.get("pending", false)), area.get_child_count())
	link.lead_changed.emit(SM_AREA, 2, 1)
	check("  taking the area over starts a clock for the dead one", bool(entry.get("pending", false)))
	await get_tree().create_timer(0.3).timeout
	var back: Node = null
	for child in area.get_children():
		if child is BaseEnemy and not (child as BaseEnemy)._death_resolved:
			back = child
	check("  and brings it back, keyed to the same spot",
		back != null and str(back.get_meta(&"net_origin", "")) == str(entry.get("key", "")), back)

	# A SCENE ON ITS WAY OUT HEARS NOTHING. Changing area takes the old scene
	# out of the tree a moment before it is freed; Presence, finding no player,
	# stops and says nobody leads - and the old scene's sync took the area
	# over and started a clock with no tree: the owner's "Cannot call method
	# 'create_timer' on a null value" (enemyrespawner.gd, _respawn_after).
	link.lead_changed.emit(SM_AREA, 1, 1)
	if back != null:
		(back as BaseEnemy).net_vanish()
	var dead_again: bool = not bool(entry.get("pending", false)) and int(entry.get("live", -1)) == 0
	remove_child(area)
	link.lead_changed.emit("", -1, 0)
	check("a scene taken out of the tree is off the link: told nobody leads as it goes, its sync stays as it was",
		dead_again and sync.is_following() and not link.lead_changed.is_connected(sync._on_lead)
		and not link.world_received.is_connected(sync._on_world), [dead_again, sync.role])
	check("  and its respawner starts no clock", not bool(entry.get("pending", false)))
	respawner.resume_authority()
	respawner._respawn_after(entry, 0.01)
	check("  a respawner out of the tree starts none even when asked - no tree to time it",
		not bool(entry.get("pending", false)))
	add_child(area)
	link.lead_changed.emit(SM_AREA, 2, 1)
	check("back in the tree it is on the link again, once: it takes the area and starts the clock",
		sync.has_authority() and bool(entry.get("pending", false))
		and link.lead_changed.get_connections().filter(func(c: Dictionary) -> bool: return c["callable"] == Callable(sync, "_on_lead")).size() == 1)
	area.free()
	link.free()

	# THE GAUNTLET catches up to the wave the leader is on.
	var Gauntlet := preload("res://src/world/bossgauntlet.gd")
	var arena := Node2D.new()
	add_child(arena)
	var bosses: Array = []
	# Gates first, into a sequencer not yet in the tree, so each gate finds its
	# boss and the sequencer finds its gates when they all enter together.
	var gauntlet: Node2D = Gauntlet.new()
	for wave in [1, 2, 2]:
		var boss: BaseEnemy = (load("res://scene/enemy/firesprite.tscn") as PackedScene).instantiate()
		boss.name = "smboss%d" % bosses.size()
		boss.position = Vector2(-50000 - bosses.size() * 100, -50000)
		arena.add_child(boss)
		bosses.append(boss)
		var gate: Node2D = (load("res://src/world/bossgate.gd") as GDScript).new()
		gate.wave = wave
		gate.boss_path = NodePath("../../" + boss.name)
		gauntlet.add_child(gate)
	arena.add_child(gauntlet)
	check("a game walking into the arena starts at wave 1, like everybody", gauntlet.net_wave() == 1)
	bosses[0].net_remove()
	gauntlet.net_jump_to(2)
	check("told the leader is on wave 2, it opens every gate to it",
		gauntlet.net_wave() == 2 and not bosses[1].gated and not bosses[2].gated)
	check("  and waits on the bosses of that wave alone", gauntlet._live.size() == 2, gauntlet._live.size())
	gauntlet.net_jump_to(1)
	check("  and never goes backwards", gauntlet.net_wave() == 2)
	arena.free()

	# THE ACID: the same spike leaves the same pools on every screen.
	var a: Node = (load("res://scene/projectiles/waterbossprojectile.tscn") as PackedScene).instantiate()
	var b: Node = (load("res://scene/projectiles/waterbossprojectile.tscn") as PackedScene).instantiate()
	for spike in [a, b]:
		spike.leaves_puddle = true
		spike.puddle_chance = 1.0
		spike.puddle_seed = 424242
		spike._puddle_extra = 2
	check("two copies of a spike with one seed leave the same acid in the same places",
		a.puddle_plan() == b.puddle_plan() and a.puddle_plan().size() == 3, a.puddle_plan())
	b.puddle_seed = 777
	check("  and a different seed somewhere else", a.puddle_plan() != b.puddle_plan())
	a.free()
	b.free()


# THE LEADER RUNS THE MONSTERS; IT DOES NOT DECIDE HOW HARD THEY HIT YOU. Three
# numbers in a world message reach your health without passing through this
# game's own copy of a monster - a spike's telegraph and size, and a stalker
# pillar's damage, telegraph and size - so a follower holds them to what its own
# boss could do. And a world message cannot fill the screen with monsters.
# =============================================================================
# THE SERVER'S BOOKS (0.10.0) - E3_SCOPE.md option C, step 1
# =============================================================================
# presence.py keeps its own count of every monster's health from the leader's
# world and every hit any game sends (combatbook.py), holds each hit to what
# the character could do, and writes down what it sees - nothing in play
# changes. The game's part: a leader sends its world even alone when the
# server keeps books, with its own player's hits inside it; a fresh ticket
# after an equip; and the numbers the server bounds hits by, exported, are the
# game's own (test_combatbook.py does the server's half).

func _test_presence_carries_the_books() -> void:
	section("THE SERVER'S BOOKS - the link knows when the server keeps them")
	Presence.set_process(false)
	Presence.stop()
	Presence._phase = "open"
	check("the game says it sends its own hits (wire 3), and still shares with a server on 2",
		Presence.SHARED_VERSION == 3 and Presence.SHARED_MINIMUM == 2)
	Presence.handle_message({"t": "welcome", "id": 7, "v": 2})
	check("a server that shares monsters but keeps no books: no books", Presence.shares() and not Presence.books())
	Presence.handle_message({"t": "welcome", "id": 7, "v": 2, "books": true})
	check("  one whose welcome says so keeps them", Presence.books())
	Presence.handle_message({"t": "welcome", "id": 7, "v": 2, "books": "yes"})
	check("  and only a true says so", not Presence.books())

	var stub_script := GDScript.new()
	stub_script.source_code = "extends Node\nvar equipped: Dictionary = {}\n"
	stub_script.reload()
	var stub := Node.new()
	stub.set_script(stub_script)
	Presence._renew_clock = 0.0
	CharacterData._apply_equip_result(stub, {"equipment": {"weapon": "ironsword"}})
	check("an equip asks for a fresh ticket at once, not within the minute - the books hold hits to what is in hand",
		Presence._renew_clock >= Presence.RENEW_SECONDS, Presence._renew_clock)
	stub.free()
	Presence.stop()
	check("when the link goes, so do the books", not Presence.books())
	Presence._server_shares = false
	Presence._server_books = false
	Presence._renew_clock = 0.0
	Presence._failures = 0
	Presence.set_process(true)


func _test_shared_monsters_keep_the_books() -> void:
	section("THE SERVER'S BOOKS - a leader alone still tells the server, with its own hits")
	var world: Node2D = _sm_world()
	var fs: BaseEnemy = world.get_node("enemies/fs1")
	var sn: BaseEnemy = world.get_node("enemies/sn1")
	var link := BooksLink.new()
	link.area = SM_AREA
	link.leader = 1
	link.n = 0
	add_child(link)
	var sync: Node = _sm_sync(link)
	world.add_child(sync)
	await get_tree().process_frame

	var full: Dictionary = _sm_last_world(link)
	check("a leader with nobody else in the area still sends everything when it takes it, for the books",
		sync.has_authority() and bool(full.get("full", false)) and bool(full.get("reset", false))
		and (full.get("spawn", []) as Array).size() == 2, full)
	link.sent_world.clear()
	var sn_id: int = sn.net_id
	sn.take_damage(5)
	fs.global_position += Vector2(12, 0)
	sync.tick_lead()
	var delta: Dictionary = _sm_last_world(link)
	check("  and its own player's hits, in the next world", _sm_hits(delta) == [[sn_id, 5, 0]], delta)
	check("  beside what changed - the one it moved and the one it hurt",
		(delta.get("snap", []) as Array).size() == 2, delta)

	link.sent_world.clear()
	link.deliver_hits(2, [[fs.net_id, 7, 0]])
	sync.tick_lead()
	check("another player's hit is not sent as this game's - the server counted it on its way here",
		_sm_hits(_sm_last_world(link)).is_empty(), _sm_last_world(link))

	link.sent_world.clear()
	for i in range(70):
		fs.take_damage(1)
	sync.tick_lead()
	var first_batch: int = _sm_hits(_sm_last_world(link)).size()
	link.sent_world.clear()
	sync.tick_lead()
	check("seventy hits go as no more than presence.py takes in one world, the rest in the next",
		first_batch == 64 and _sm_hits(_sm_last_world(link)).size() == 6, [first_batch, _sm_last_world(link)])

	link.sent_world.clear()
	sn.take_damage(100000)
	sync.tick_lead()
	var last: Dictionary = _sm_last_world(link)
	var died: bool = false
	for ev in last.get("ev", []):
		if ev.get("k", "") == "die" and int(ev.get("id", -1)) == sn_id:
			died = true
	check("a killing hit travels in the same world as the death it caused, ahead of it",
		died and _sm_hits(last).has([sn_id, 100000, 0]), last)

	# BORN SINCE THE LAST TICK (0.21.2). The books' first week: 41 deaths of
	# 1,182 SHORT, every one a small slime - born from a split or a respawn
	# into a fire ring or a burning crater, hit before the next tick gave it a
	# number, and that hit sent nowhere. A new monster is numbered on its
	# first hit now, and its spawn rides in the same world as the hit.
	link.sent_world.clear()
	var newborn: BaseEnemy = (load("res://scene/enemy/firesprite.tscn") as PackedScene).instantiate()
	newborn.name = "fsnew"
	newborn.position = Vector2(-20050, -20050)
	world.get_node("enemies").add_child(newborn)
	var unnumbered: bool = newborn.net_id < 0
	newborn.take_damage(9)
	var born_id: int = newborn.net_id
	sync.tick_lead()
	var born: Dictionary = _sm_last_world(link)
	var spawned: int = 0
	for ev in born.get("ev", []):
		if ev.get("k", "") == "spawn" and int((ev.get("r", {}) as Dictionary).get("id", -1)) == born_id:
			spawned += 1
	check("a monster hit before the leader's tick reached it is numbered by the hit, and the hit is sent",
		unnumbered and born_id >= 0 and sync.monsters().get(born_id) == newborn
		and _sm_hits(born).has([born_id, 9, 0]), born)
	check("  with its spawn in the same world, for the server to read before the hit", spawned == 1, born)
	link.sent_world.clear()
	sync.tick_lead()
	var twice: bool = false
	for ev in _sm_last_world(link).get("ev", []):
		if ev.get("k", "") == "spawn":
			twice = true
	check("  and the next tick does not number it again", not twice and newborn.net_id == born_id,
		_sm_last_world(link))

	link.sent_world.clear()
	link.deliver_need(0)
	var to_books: Array = link.sent_world.filter(func(m: Array) -> bool: return m[1] == 0)
	check("the server's books asking for everything (for game 0) are sent it",
		to_books.size() == 1 and bool((to_books[0][0] as Dictionary).get("full", false))
		and not bool((to_books[0][0] as Dictionary).get("reset", true)), link.sent_world)

	link.keeps_books = false
	link.sent_world.clear()
	fs.take_damage(3)
	var held_back: bool = sync._own_hits.is_empty()
	fs.global_position += Vector2(5, 0)
	sync.tick_lead()
	check("with no books and nobody else here, nothing is sent - as before 0.10.0", link.sent_world.is_empty())
	check("  and no hit is kept for a server that is not counting", held_back, sync._own_hits)

	link.keeps_books = true
	link.sent_world.clear()
	var fs_id: int = fs.net_id
	fs.died.emit()
	sync.tick_lead()
	var again: bool = false
	for ev in _sm_last_world(link).get("ev", []):
		if ev.get("k", "") == "spawn":
			again = true
	check("a monster that has said it died is not numbered again while it still stands (a slime splitting)",
		not again and not sync.monsters().values().has(fs) and fs.net_id == fs_id, _sm_last_world(link))

	link.lead_changed.emit(SM_AREA, 9, 1)
	var sn2: BaseEnemy = null
	for e in sync._all_enemies():
		if e != fs:
			sn2 = e
	if sn2 != null:
		sn2.take_damage(4)
	check("a follower's hits go to the leader as before, never as its own",
		sync.is_following() and sync._own_hits.is_empty() and (sn2 == null or not sync._hits.is_empty()))

	world.free()
	link.free()

	# A SCENE LOADS BEFORE ITS SOCKET DOES: every change of area opens a new
	# link, so the game starts running its monsters with nobody told.
	world = _sm_world()
	link = BooksLink.new()
	link.area = SM_AREA
	link.open = false
	add_child(link)
	sync = _sm_sync(link)
	world.add_child(sync)
	await get_tree().process_frame
	check("a scene that loads with no link runs its own monsters, telling nobody",
		sync.has_authority() and link.sent_world.is_empty())
	link.open = true
	link.n = 0
	link.lead_changed.emit(SM_AREA, 1, 0)
	var told: Dictionary = _sm_last_world(link)
	check("  and when the link opens and names it leader, the books are sent everything, as a new scene's",
		link.sent_world.size() == 1 and bool(told.get("full", false)) and bool(told.get("reset", false))
		and (told.get("spawn", []) as Array).size() == 2, link.sent_world)
	link.lead_changed.emit(SM_AREA, 1, 0)
	check("  once", link.sent_world.size() == 1, link.sent_world.size())
	link.lead_changed.emit(SM_AREA, -1, 0)
	link.lead_changed.emit(SM_AREA, 1, 0)
	check("  and again after the link drops and comes back", link.sent_world.size() == 2, link.sent_world.size())
	world.free()
	link.free()


func _test_combat_bounds_match_the_game() -> void:
	section("THE SERVER'S BOOKS - the numbers it holds every hit to are the game's")
	var data := _load_gamedata()
	var combat: Dictionary = data.get("combat", {}) if data.get("combat", {}) is Dictionary else {}
	var areas: Dictionary = data.get("areas", {}) if data.get("areas", {}) is Dictionary else {}
	check("gamedata.json carries the combat numbers and every area's map (re-run the exporter if not)",
		not combat.is_empty() and not areas.is_empty())
	if combat.is_empty() or areas.is_empty():
		return
	var classes: Dictionary = combat.get("classes", {})
	var scripts := {"warrior": "res://src/characters/warrior.gd", "mage": "res://src/characters/mage.gd",
		"healer": "res://src/characters/healer.gd", "tank": "res://src/characters/tank.gd"}
	var speeds_ok: bool = true
	for cls in scripts:
		var consts: Dictionary = (load(scripts[cls]) as GDScript).get_script_constant_map()
		if int((classes.get(cls, {}) as Dictionary).get("speed", -1)) != int(consts.get("CLASS_SPEED", -2)):
			speeds_ok = false
	check("every class walks at its own CLASS_SPEED, as exported", speeds_ok, classes)
	check("  and _ready() walks it at that speed, not a number of its own",
		scripts.values().all(func(path: String) -> bool: return _code_src(path).contains("speed = CLASS_SPEED")))
	check("agility adds the same to a walk as exported, in both places a walk is worked out",
		int(combat.get("agility_speed", -1)) == PlayerStats.AGILITY_SPEED_PER_LEVEL
		and _code_src("res://src/characters/player.gd").contains("speed + (agility - 1) * PlayerStats.AGILITY_SPEED_PER_LEVEL")
		and _code_src("res://src/characters/tank.gd").contains("speed + (agility - 1) * PlayerStats.AGILITY_SPEED_PER_LEVEL"),
		combat.get("agility_speed"))
	# 0.25.1, the owner: "at level 99 max speed chars are way too fast
	# especially with the option to run" - 1,180 px/s walking, 2,360 running.
	var warrior_speed: int = int((load(scripts["warrior"]) as GDScript).get_script_constant_map().get("CLASS_SPEED", 0))
	var top_walk: float = warrior_speed + 98 * float(combat.get("agility_speed", 0))
	var top_run: float = top_walk * float(combat.get("sprint", 0.0))
	check("a level-99 warrior, the fastest, walks 298 px/s and runs 447 - not 1,180 and 2,360 (0.25.1)",
		is_equal_approx(top_walk, 298.0) and is_equal_approx(top_run, 447.0), [top_walk, top_run])
	check("the skill, agility, pet and double-cast numbers are the game's",
		is_equal_approx(float(combat.get("skill_step", -1)), PlayerStats.ATTACK_DAMAGE_PERCENT_PER_LEVEL)
		and is_equal_approx(float(combat.get("skill_step", -1)), PlayerStats.MAGIC_DAMAGE_PERCENT_PER_LEVEL)
		and is_equal_approx(float(combat.get("agility_step", -1)), PlayerStats.AGILITY_ATTACK_SPEED_PERCENT_PER_LEVEL)
		and is_equal_approx(float(combat.get("agility_cap", -1)), PlayerStats.MAX_ATTACK_SPEED_MULTIPLIER)
		and is_equal_approx(float(combat.get("pet_share", -1)), (load("res://src/pets/pet.gd") as GDScript).get_script_constant_map().get("PET_STAT_SHARE", -2.0))
		and is_equal_approx(float(combat.get("double_chance", -1)), (load("res://src/characters/player.gd") as GDScript).get_script_constant_map().get("WEAPON_DOUBLE_CHANCE", -2.0)),
		combat)
	check("  and so is the physics rate a healer's shots are counted against",
		int(combat.get("physics_ticks", -1)) == int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")))
	var attacks: Dictionary = {}
	for item in ItemRegistry.get_all_items():
		if int(item.weapon_attack) != ItemData.WeaponAttack.NONE:
			attacks[item.item_id] = String(ItemData.WeaponAttack.keys()[int(item.weapon_attack)])
	check("the Meteorite's burn and Dynamite's chain bonus and smoulder are the game's, so the books allow for them",
		is_equal_approx(float((classes.get("mage", {}) as Dictionary).get("meteor_burn_share", -1.0)), BurningCrater.BURN_SHARE)
		and is_equal_approx(float((classes.get("mage", {}) as Dictionary).get("meteor_burn_every", -1.0)), BurningCrater.BURN_EVERY)
		and is_equal_approx(float((classes.get("tank", {}) as Dictionary).get("dynamite_chain_bonus", -1.0)), Dynamite.CHAIN_BONUS)
		and is_equal_approx(float((classes.get("tank", {}) as Dictionary).get("dynamite_field_share", -1.0)), Dynamite.FIELD_SHARE)
		and is_equal_approx(float((classes.get("tank", {}) as Dictionary).get("dynamite_field_every", -1.0)), Dynamite.FIELD_EVERY),
		[classes.get("mage", {}), classes.get("tank", {})])
	var shard_consts: Dictionary = (load("res://src/projectiles/frostring.gd") as GDScript).get_script_constant_map()
	check("  and the mage's critical spike and its ice shards, so they allow for them every cast (0.71.0, 0.71.1)",
		is_equal_approx(float((classes.get("mage", {}) as Dictionary).get("crit_chance", -1.0)),
			float(_mage_const("CRIT_CHANCE")))
		and is_equal_approx(float((classes.get("mage", {}) as Dictionary).get("crit_mult", -1.0)),
			float(_mage_const("CRIT_MULT")))
		and int((classes.get("mage", {}) as Dictionary).get("shard_hits_each", -1)) == int(shard_consts.get("SHARD_HITS_EACH", -2))
		and is_equal_approx(float((classes.get("mage", {}) as Dictionary).get("shard_share", -1.0)),
			float(shard_consts.get("SHARD_SHARE", -2.0))), classes.get("mage", {}))
	check("the Double Axe's top spin rate is the game's, so the books allow for it",
		is_equal_approx(float((classes.get("warrior", {}) as Dictionary).get("axe_spin_max_rate", -1.0)),
			SpinningAxe.SPIN_MAX_RATE), classes.get("warrior", {}))
	check("  and so is its bleed (0.14.0)",
		is_equal_approx(float((classes.get("warrior", {}) as Dictionary).get("axe_bleed_share", -1.0)), Bleed.BLEED_SHARE)
		and is_equal_approx(float((classes.get("warrior", {}) as Dictionary).get("axe_bleed_every", -1.0)), Bleed.BLEED_EVERY),
		classes.get("warrior", {}))
	var tank_consts: Dictionary = (load("res://src/characters/tank.gd") as GDScript).get_script_constant_map()
	var tank_row: Dictionary = classes.get("tank", {})
	check("Dynamite's roll is the game's - the bundle and the barrage - so the books allow for it (0.18.0)",
		int(tank_row.get("dynamite_bundle_sticks", -1)) == int(tank_consts.get("DYNAMITE_BUNDLE_STICKS", -2))
		and is_equal_approx(float(tank_row.get("dynamite_bundle_chance", -1.0)), float(tank_consts.get("DYNAMITE_BUNDLE_CHANCE", -2.0)))
		and int(tank_row.get("dynamite_barrage_sticks", -1)) == int(tank_consts.get("DYNAMITE_BARRAGE_STICKS", -2))
		and is_equal_approx(float(tank_row.get("dynamite_barrage_chance", -1.0)), float(tank_consts.get("DYNAMITE_BARRAGE_CHANCE", -2.0)))
		and not tank_row.has("dynamite_bundle_every"),
		tank_row)
	check("every weapon that brings its own attack is named, by its attack",
		not attacks.is_empty() and attacks == combat.get("weapon_attacks", {}), [attacks, combat.get("weapon_attacks")])

	var known_areas: Dictionary = AreaRegistry.AREAS
	check("every area has a map, and no map is an area the game does not have",
		known_areas.keys().all(func(k) -> bool: return areas.has(k))
		and areas.keys().all(func(k) -> bool: return known_areas.has(k)), [known_areas.keys(), areas.keys()])
	if not _pack_present():
		check_needs_pack("each area's monsters stand where the map says, and are what it says", false)
		return
	var stale: Array = []
	for area_id in known_areas:
		var root: Node = (load(String(known_areas[area_id])) as PackedScene).instantiate()
		var here: Array = []
		var walk: Array = [root]
		while not walk.is_empty():
			var node: Node = walk.pop_back()
			for child in node.get_children():
				if child.scene_file_path.begins_with("res://scene/enemy/"):
					var data_res: Variant = child.get("enemy_data")
					var enemy_id: String = ""
					if data_res is EnemyData:
						enemy_id = (data_res as EnemyData).enemy_id
					else:
						# Its _ready() fills it from the script's own profile
						# (ENEMY_DATA; a large poison slime's LARGE_DATA).
						var consts: Dictionary = (child.get_script() as GDScript).get_script_constant_map()
						var own: Variant = consts.get("ENEMY_DATA", consts.get("LARGE_DATA"))
						enemy_id = (own as EnemyData).enemy_id if own is EnemyData else ""
					here.append("%s|%s" % [str(root.get_path_to(child)), enemy_id])
				else:
					walk.append(child)
		root.free()
		var mapped: Array = []
		for spot in (areas.get(area_id, {}) as Dictionary).get("spawns", []):
			mapped.append("%s|%s" % [str(spot.get("o", "")), str(spot.get("e", ""))])
		here.sort()
		mapped.sort()
		if here != mapped:
			stale.append([area_id, here.filter(func(s) -> bool: return not mapped.has(s)).slice(0, 3),
				mapped.filter(func(s) -> bool: return not here.has(s)).slice(0, 3)])
	check("each area's monsters stand at the spots the map names, and are what it says (re-run the exporter if not)",
		stale.is_empty(), stale)
	var puddle: Node = (load("res://scene/projectiles/petpoisonpuddle.tscn") as PackedScene).instantiate()
	check("a pet's puddle ticks for what the books allow it",
		int(puddle.get("tick_damage")) == int(combat.get("puddle_damage", -1)), puddle.get("tick_damage"))
	puddle.free()
	var reads := {
		"warrior": {"base": "base_melee_damage", "cooldown": "attack_lock_duration", "wave_ratio": "wave_damage_ratio"},
		"mage": {"base": "damage_per_magic", "cooldown": "spell_cooldown"},
		"healer": {"base": "damage_per_magic", "cooldown": "shot_cooldown"},
		"tank": {"base": "aura_damage", "cooldown": "aura_tick", "dynamite_cooldown": "dynamite_cooldown",
			"dynamite_stick_ticks": "dynamite_stick_ticks"},
	}
	var off: Array = []
	for cls in reads:
		var body: Node = (load("res://scene/characters/%s.tscn" % cls) as PackedScene).instantiate()
		for key in reads[cls]:
			if not is_equal_approx(float((classes.get(cls, {}) as Dictionary).get(key, -1)), float(body.get(reads[cls][key]))):
				off.append("%s.%s" % [cls, key])
		if not is_equal_approx(float(combat.get("sprint", -1)), float(body.get("sprint_speed_multiplier"))):
			off.append("%s.sprint" % cls)
		body.free()
	check("every class hits as hard and as often as exported (re-run the exporter if not)", off.is_empty(), off)


func _test_shared_monsters_hold_the_leaders_numbers() -> void:
	section("SHARED MONSTERS - a leader cannot make the floor hit you harder")
	const Sync := preload("res://src/world/monstersync.gd")
	const Stalker := preload("res://src/enemies/bossstalker.gd")
	check("an honest boss spike passes untouched",
		Sync.safe_spike(0.52, 14.0).is_equal_approx(Vector2(0.52, 14.0)), Sync.safe_spike(0.52, 14.0))
	var greedy: Vector2 = Sync.safe_spike(0.0, 500.0)
	check("  one that lands at once and fills the room is held to what a boss can cast",
		is_equal_approx(greedy.x, Sync.MIN_SPIKE_TELEGRAPH) and is_equal_approx(greedy.y, Sync.MAX_SPIKE_RADIUS),
		greedy)
	check("a stalker pillar keeps the damage an honest leader sends",
		Sync.safe_pillar_damage(15, null) == 15)
	check("  and is never more than the stalker's own once the boss has gone",
		Sync.safe_pillar_damage(99999, null) == Stalker.PILLAR_DAMAGE
		and Sync.safe_pillar_damage(0, null) == Stalker.PILLAR_DAMAGE)
	var boss: Node = (load("res://scene/enemy/fireboss.tscn") as PackedScene).instantiate()
	var own: int = int(boss.call("trail_damage"))
	if own <= 0:
		own = Stalker.PILLAR_DAMAGE
	check("  or than this game's own copy of the boss gives its trail",
		Sync.safe_pillar_damage(99999, boss) == own and Sync.safe_pillar_damage(own, boss) == own, own)
	boss.free()

	var world: Node2D = _sm_world()
	var link := FakeLink.new()
	link.me = 2
	add_child(link)
	var sync: Node = _sm_sync(link)
	world.add_child(sync)
	await get_tree().process_frame
	link.lead_changed.emit(SM_AREA, 1, 1)
	var at := Vector2(-19000, -19000)
	sync.apply_world({"ev": [{"k": "sp", "s": "res://scene/projectiles/bossprojectile.tscn",
		"x": at.x, "y": at.y, "d": 99999, "t": 0.0, "el": -1, "r": 500.0}]})
	var pillar: Node2D = null
	var places: Array = get_tree().get_nodes_in_group("groundeffects")
	places.append(get_tree().current_scene)
	for place in places:
		for child in (place as Node).get_children():
			if child is Node2D and (child as Node2D).global_position.distance_to(at) < 1.0:
				pillar = child
	check("a pillar from a leader that would one-shot you is built at the stalker's own damage",
		pillar != null and int(pillar.get("damage")) <= Stalker.PILLAR_DAMAGE,
		pillar.get("damage") if pillar != null else null)
	check("  with the stalker's own warning and no wider than its own",
		pillar != null and float(pillar.get("telegraph_seconds")) >= Stalker.PILLAR_TELEGRAPH - 0.001
		and pillar.scale.x <= Stalker.PILLAR_RADIUS / 20.0 + 0.001,
		str([pillar.get("telegraph_seconds"), pillar.scale]) if pillar != null else "no pillar")
	if pillar != null:
		pillar.free()

	for i in range(Sync.MAX_MONSTERS):
		sync._enemies[100000 + i] = null
	var record: Dictionary = {"id": 99, "o": "", "s": "res://scene/enemy/firesprite.tscn",
		"pp": "smworld/enemies", "x": -19800.0, "y": -19800.0, "a": "idledown", "hp": 10, "mh": 10, "p": {}}
	check("a follower draws no more than MAX_MONSTERS, whatever a world message asks",
		sync.build_mirror(record) == null)
	sync._enemies.clear()
	var one: Node = sync.build_mirror(record)
	check("  and draws them again once there is room", one != null)
	if one != null:
		one.free()

	world.free()
	link.free()
	await get_tree().process_frame

# 6 Oct, the owner: "i found a issue when walking up to the wall enemies dont
# attack". Every enemy asked "can I see you" with a ray to the player's NODE
# ORIGIN, and the origin is not where the body is: the warrior's body sits 13 px
# below it, the tank's 16 px above. Walk a warrior up into a north wall (or a
# tank down into a south one) and the origin is inside the masonry, every ray
# hits the wall first, and the whole pack stands around you holding fire. The
# shots aimed at the origin too. Both use BaseEnemy.target_point() now - the
# body, through Targets.body_point(), as the boss's _aim_point() always did.
# =============================================================================
# THE MAGE'S SPIKE FINDS ITS MARK, AND THE THIRD CAST DROPS THREE (0.70.0)
# =============================================================================
# The owner: "mage is the weakest of all my chars ... a single ice spike is
# kinda lame". A spike lands a third of a second after the cast on an 18 px
# circle, so a walking monster was out from under it. Now it takes the nearest
# monster near the aim and follows it down; and every third cast drops three,
# on three monsters - but one spike a monster a cast, so the server's bound on
# a mage holds.
func _test_the_mage_spike_finds_its_mark() -> void:
	section("MAGE - the spike finds its mark and follows it down; every third cast drops three (0.70.0)")
	const Targets := preload("res://src/shared/targets.gd")
	const Mage := preload("res://src/characters/mage.gd")
	var arena := Node2D.new()
	add_child(arena)
	var base := Vector2(-94000.0, 64000.0)
	_attack_wall(arena, base + Vector2(0, -60), Vector2(600, 4), 1)
	var mage: Node2D = _hero_against(arena, "mage", base.y + 200.0, base.x)
	mage.global_position = base + Vector2(0, 120)
	var aim := base
	var near: CharacterBody2D = _weapon_dummy(arena, aim + Vector2(30, 0))
	var _nearer_behind: CharacterBody2D = _weapon_dummy(arena, aim + Vector2(0, -70))   # past the wall, 70 off
	var far: CharacterBody2D = _weapon_dummy(arena, aim + Vector2(-150, 0))
	for i in 3:
		await get_tree().physics_frame
	var one: Array = mage.call("spike_marks", aim, 1)
	check("a spike aimed near a monster takes it as its mark",
		one.size() == 1 and one[0]["target"] == near and one[0]["at"] == Targets.body_point(near), one)
	near.global_position = aim + Vector2(Mage.SPIKE_SEEK_RADIUS + 10.0, 0)
	one = mage.call("spike_marks", aim, 1)
	check("  one further than SPIKE_SEEK_RADIUS is not taken - the spike lands where it was aimed",
		one.size() == 1 and one[0]["target"] == null and one[0]["at"] == aim, one)
	near.global_position = aim + Vector2(30, 0)
	var hidden_close: CharacterBody2D = _weapon_dummy(arena, aim + Vector2(0, -64))
	await get_tree().physics_frame
	one = mage.call("spike_marks", aim + Vector2(0, -40), 1)
	check("  nor one behind a wall from the mage, however near", one[0]["target"] != hidden_close, one)

	# THE THIRD CAST: three marks, three monsters, nearest first.
	var second: CharacterBody2D = _weapon_dummy(arena, aim + Vector2(70, 10))
	var third: CharacterBody2D = _weapon_dummy(arena, aim + Vector2(-60, 20))
	await get_tree().physics_frame
	var three: Array = mage.call("spike_marks", aim, Mage.TRIPLE_SPIKES)
	var on: Array = three.map(func(m: Dictionary) -> Variant: return m["target"])
	check("the third cast's three go on three monsters, the mark first and the next nearest after",
		three.size() == 3 and on == [near, second, third], on)
	second.global_position = aim + Vector2(400, 0)
	third.global_position = aim + Vector2(-400, 0)
	far.global_position = aim + Vector2(0, 400)
	await get_tree().physics_frame
	three = mage.call("spike_marks", aim, Mage.TRIPLE_SPIKES)
	var spread_ok: bool = three.size() == 3 and three[0]["target"] == near
	for k in range(1, three.size()):
		spread_ok = spread_ok and three[k]["target"] == null and is_equal_approx(
			(three[k]["at"] as Vector2).distance_to(three[0]["at"]), Mage.TRIPLE_SPREAD)
	check("  with no others near, the two more land round the mark, TRIPLE_SPREAD out", spread_ok, three)

	# The cast count: one, one, three - with no critical spike to drop three
	# early (0.71.0; _test_the_mage_kit() rolls those).
	mage.set("last_direction", Vector2.UP)
	mage.set("pointer_on_game", false)
	mage.set("crit_chance", 0.0)
	var counts: Array = []
	for i in 3:
		var made: Array = mage.call("_spawn_stalagmite")
		counts.append(made.size())
		for spell in made:
			(spell as Node).queue_free()
	check("every third cast drops three spikes, the others one", counts == [1, 1, 3], counts)

	# FOLLOWING THE MARK DOWN, and one spike a monster a cast.
	var scene: PackedScene = mage.get("target_circle_scene")
	var spike: Area2D = scene.instantiate()
	spike.set("target", near)
	arena.add_child(spike)
	spike.global_position = Targets.body_point(near)
	near.global_position += Vector2(24, 0)
	spike.call("follow")
	check("the spike keeps over its mark's feet as it walks", spike.global_position == Targets.body_point(near),
		[spike.global_position, Targets.body_point(near)])
	(spike.get("anim") as AnimatedSprite2D).frame = 4
	near.global_position += Vector2(24, 0)
	spike.call("follow")
	check("  and once it has struck it stays where it struck", spike.global_position != Targets.body_point(near)
		and spike.get("target") == null)
	spike.queue_free()
	var struck: Dictionary = {}
	var twins: Array = []
	for i in 2:
		var twin: Area2D = scene.instantiate()
		twin.set("struck", struck)
		twin.set("explosion_damage", 10)
		arena.add_child(twin)
		twin.global_position = Targets.body_point(near) + Vector2(4.0 * i, 0)
		twins.append(twin)
	for i in 3:
		await get_tree().physics_frame
	for twin in twins:
		twin.call("_apply_area_damage")
	check("two spikes of one cast on one monster hit it once", near.get("taken").size() == 1, near.get("taken"))
	for twin in twins:
		(twin as Node).queue_free()
	check("  which is what the server's bound on a mage counts: one hit a cast",
		_func_body(_code_src("res://src/projectiles/spelltargetcircle.gd"), "func _apply_area_damage(").contains("struck[id] = true"))
	mage.queue_free()

	# THE FINISHER'S BURST, FROM THIS SIDE OF A WALL. The owner: "warriors
	# bullet projectile is spilling outside the map and is scattering in the
	# black kind of like teleporting". The burst left from the middle of the
	# monster's hurtbox - over a 2 px Big Field wall, already in the black.
	var wall_y: float = base.y - 60.0
	var wave: SlashWave = (load("res://scene/projectiles/slashwave.tscn") as PackedScene).instantiate()
	wave.finisher = true
	wave.burst_damage = 5
	arena.add_child(wave)
	wave.global_position = Vector2(base.x + 100.0, wall_y + 12.0)
	wave.shoot_vector(Vector2.UP)
	var before: int = arena.get_children().filter(func(n: Node) -> bool: return n is BladeOrb).size()
	wave.burst(Vector2(base.x + 100.0, wall_y - 10.0), null)
	await get_tree().process_frame
	var orbs: Array = arena.get_children().filter(func(n: Node) -> bool: return n is BladeOrb)
	var past: Array = orbs.filter(func(o: Node) -> bool: return (o as Node2D).global_position.y < wall_y)
	check("a finisher's burst at a monster whose hurtbox stands over the wall starts this side of it",
		orbs.size() > before and past.is_empty(), [orbs.size() - before, past.size()])
	wave.queue_free()
	for orb in orbs:
		(orb as Node).queue_free()
	arena.queue_free()
	await get_tree().process_frame


# =============================================================================
# BULLETS VANISH OVER THE BLACK (0.72.1)
# =============================================================================
# The owner: "i still have the white bullet projectiles from warrior fling in
# the black of the map for some reason and spraying across the map instead of
# vanishing". The Big Field is walled all round; the town, the Field and the
# boss arena are not, and a warrior's orbs and waves flew on over the black
# until their range ran out. MapBackdrop.black_at(): past the painted map, a
# bullet is gone.
func _test_bullets_vanish_over_the_black() -> void:
	section("BULLETS - past the painted map they are gone, not flying on over the black (0.72.1)")
	const MapBackdrop := preload("res://src/world/mapbackdrop.gd")
	var area := Node2D.new()
	area.name = "blackarea"
	add_child(area)
	area.global_position = Vector2(-106000.0, 76000.0)
	var backdrop := Node2D.new()
	backdrop.set_script(MapBackdrop)
	backdrop.set("rects", [Rect2(0, 0, 160, 96), Rect2(0, 96, 40, 24)] as Array[Rect2])
	backdrop.call("build_grid")
	area.add_child(backdrop)
	var origin: Vector2 = area.global_position
	check("the backdrop knows where the map is painted and where the black begins",
		backdrop.call("painted", Vector2(80, 40)) == true and backdrop.call("painted", Vector2(20, 110)) == true
		and backdrop.call("painted", Vector2(80, 110)) == false and backdrop.call("painted", Vector2(170, 40)) == false
		and backdrop.call("painted", Vector2(-5, 40)) == false)
	check("  and black_at() asks it for anything in its area, in the world",
		not MapBackdrop.black_at(area, origin + Vector2(80, 40)) and MapBackdrop.black_at(area, origin + Vector2(200, 40)))
	var outsider := Node2D.new()
	add_child(outsider)
	check("  but nothing outside the area - a test's arena, anything not in it - is ever in the black",
		not MapBackdrop.black_at(outsider, origin + Vector2(200, 40)))
	outsider.queue_free()

	# The warrior's orbs, flying out over the edge.
	var orb: BladeOrb = BladeOrb.fire(area, origin + Vector2(130, 40), Vector2.RIGHT, 300.0, 300.0, 0, BladeOrb.STEEL)
	var stays: BladeOrb = BladeOrb.fire(area, origin + Vector2(20, 40), Vector2.RIGHT, 30.0, 300.0, 0, BladeOrb.STEEL)
	for i in 12:
		await get_tree().physics_frame
	check("a warrior's orb flying off the painted map is gone at its edge, not 300 px out",
		(not is_instance_valid(orb) or orb.is_queued_for_deletion()), str(orb.global_position) if is_instance_valid(orb) else "gone")
	check("  and one over the map flies on as ever",
		is_instance_valid(stays) and not stays.is_queued_for_deletion() and not stays._done)
	if is_instance_valid(stays):
		stays.queue_free()

	# A finisher's wave: gone quietly, no burst out in the black.
	var wave: SlashWave = (load("res://scene/projectiles/slashwave.tscn") as PackedScene).instantiate()
	wave.finisher = true
	wave.hitbox_scale = SlashWave.FINISHER_SCALE
	wave.burst_damage = 5
	area.add_child(wave)
	wave.global_position = origin + Vector2(120, 40)
	wave.reset_physics_interpolation()
	wave.shoot_vector(Vector2.RIGHT)
	for i in 12:
		await get_tree().physics_frame
	var burst_orbs: int = area.get_children().filter(func(n: Node) -> bool: return n is BladeOrb and not n.is_queued_for_deletion()).size()
	check("a wave flying off the map breaks at its edge, and a finisher bursts nothing out there",
		(not is_instance_valid(wave) or bool(wave.get("_is_dying"))) and burst_orbs == 0, burst_orbs)

	# The monsters' shots and the healer's orb, the same.
	var shots: Array = []
	for path in ["res://scene/projectiles/arrow.tscn", "res://scene/projectiles/magicprojectile.tscn",
			"res://scene/projectiles/fireprojectile.tscn", "res://scene/projectiles/poisonball.tscn"]:
		var shot: Node2D = (load(path) as PackedScene).instantiate()
		area.add_child(shot)
		shot.global_position = origin + Vector2(140, 20 + 12 * shots.size())
		shot.reset_physics_interpolation()
		shot.call("shoot_vector", Vector2.RIGHT)
		shots.append(shot)
	var heal: Node2D = (load("res://scene/projectiles/turretprojectile.tscn") as PackedScene).instantiate()
	heal.set("homing_turn_rate", 0.0)
	heal.set("weave_amplitude_deg", 0.0)
	heal.set("direction", Vector2.RIGHT)
	heal.set("damage", 0)
	area.add_child(heal)
	heal.global_position = origin + Vector2(140, 80)
	shots.append(heal)
	for i in 12:
		await get_tree().physics_frame
	var flying: Array = shots.filter(func(n: Variant) -> bool: return is_instance_valid(n) and not (n as Node).is_queued_for_deletion())
	check("  so do the monsters' arrows and orbs and the healer's orb", flying.is_empty(),
		flying.map(func(n: Node) -> String: return n.name))
	for path in ["res://src/projectiles/petarrow.gd", "res://src/projectiles/petfireprojectile.gd",
			"res://src/projectiles/petelectricprojectile.gd"]:
		check("  and the pets' shots ask too: " + path.get_file(),
			_func_body(_code_src(path), "func _physics_process(").contains("MapBackdrop.black_at(self, global_position)"))

	# The Double Axe: the map's edge is a wall to it - it stops there and spins.
	var hand: Node2D = _weapon_hand(area, origin + Vector2(100, 40))
	var axe: SpinningAxe = (load("res://scene/projectiles/spinningaxe.tscn") as PackedScene).instantiate()
	axe.caster = hand
	axe.wounds = false
	area.add_child(axe)
	axe.set_physics_process(false)
	axe.throw_to(hand.global_position, hand.global_position + Vector2(150, 0))
	var steps := 0
	while axe.state == SpinningAxe.State.OUT and steps < 200:
		await get_tree().physics_frame
		axe.advance(1.0 / 80.0)
		steps += 1
	var axe_x: float = axe.global_position.x - origin.x
	check("the Double Axe thrown off the map stops at its edge and spins there, as at a wall",
		axe.state == SpinningAxe.State.SPINNING and axe_x < 160.0 and axe_x > 150.0, [axe.state, axe_x])
	axe.queue_free()
	hand.queue_free()

	# The real town, where the owner saw it.
	var town: Node = (load("res://scene/elusion.tscn") as PackedScene).instantiate()
	var rects: Array[Rect2] = MapBackdrop.cover(town)
	var probe := Node2D.new()
	probe.set_script(MapBackdrop)
	probe.set("rects", rects)
	probe.call("build_grid")
	var left: float = INF
	var inside_ok: bool = true
	for r in rects:
		left = minf(left, r.position.x)
		inside_ok = inside_ok and bool(probe.call("painted", r.get_center()))
	check("the town's grid is its painted tiles: every run painted, and past its west edge the black",
		not rects.is_empty() and inside_ok and probe.call("painted", Vector2(left - 20.0, rects[0].get_center().y)) == false)
	probe.free()
	town.free()
	area.queue_free()
	await get_tree().process_frame


# =============================================================================
# PLACED, NOT MOVED (0.72.2)
# =============================================================================
# The owner's video of a Big Field fight, frame by frame: a white disc out in
# the black past the room's west wall, one frame at a time and somewhere new
# each time - what he had been calling "white bullet projectiles from warrior
# fling in the black of the map" and "still flying through walls". It was the
# sword's strike flash (strikefx.gd). It was put in the projectiles container
# and then placed at the blow, and nothing told the renderer it had been
# placed rather than moved, so its one bright frame was drawn part way along
# the line from the area's origin - up and left of every fight there. The
# healer orb's splash and the boss's stalker did the same.
#
# THE RULE IS CLAUDE.md's ("reset_physics_interpolation() goes after the
# position"), and this holds every script to it: a node added with
# add_child() and then given a global_position or global_transform in the
# same function is reset after the last of them.
func _test_placed_nodes_are_not_drawn_from_the_origin() -> void:
	section("PLACED, NOT MOVED - a node put in the world is drawn there on its first frame (0.72.2)")
	var add_re := RegEx.create_from_string("(?:^|[^\\w])add_child\\((\\w+)")
	var offenders: Array = []
	var checked: Array = []
	for path in _all_gd_under("res://src"):
		if _is_suite_script(path) or path.contains("/tools/") or path.contains("/prototype/"):
			continue
		var lines: PackedStringArray = _code_src(path).split("\n")
		for i in lines.size():
			var found := add_re.search(lines[i])
			if found == null:
				continue
			var node_name: String = found.get_string(1)
			var placed_re := RegEx.create_from_string("\\b" + node_name + "\\.global_(position|transform)\\s*=[^=]")
			var reset_re := RegEx.create_from_string("\\b" + node_name + "\\.reset_physics_interpolation\\(\\)")
			var placed := -1
			var reset := -1
			var j := i + 1
			while j < lines.size() and not (lines[j].begins_with("func ") or lines[j].begins_with("static func ")):
				if placed_re.search(lines[j]) != null:
					placed = j
				if reset_re.search(lines[j]) != null:
					reset = j
				j += 1
			if placed == -1:
				continue
			checked.append(path.get_file())
			if reset < placed:
				offenders.append("%s:%d %s" % [path.get_file(), i + 1, node_name])
	check("every node added and then placed in the world is reset after it - or its first frame is drawn on the way in from the origin",
		offenders.is_empty(), offenders)
	check("  the scan finds them: the strike flash, the healer's splash, the boss's stalker and the rest",
		checked.size() >= 10 and checked.has("strikefx.gd") and checked.has("turretprojectile.gd") and checked.has("bossenemy.gd"),
		[checked.size(), checked.slice(0, 12)])


# =============================================================================
# BULLETS THAT FLY TRUE (0.72.0)
# =============================================================================
# The owner: "we need to upgrade bullets to be way more refined darza managed
# this ability nicely", and of what was offered: shape and flight, hitboxes and
# rules, and the monsters' bullets too.
func _test_bullets_fly_true() -> void:
	section("BULLETS - they face where they fly, hit where they are drawn, and end by their rules (0.72.0)")
	const FrostRing := preload("res://src/projectiles/frostring.gd")
	var arena := Node2D.new()
	add_child(arena)
	var base := Vector2(-102000.0, 72000.0)

	# ---- SHAPE AND FLIGHT -------------------------------------------------------
	var orb: Node2D = (load("res://scene/projectiles/turretprojectile.tscn") as PackedScene).instantiate()
	orb.set("homing_turn_rate", 0.0)
	orb.set("weave_amplitude_deg", 0.0)
	orb.set("direction", Vector2.RIGHT)
	orb.set("damage", 0)
	arena.add_child(orb)
	orb.global_position = base
	for i in 2:
		await get_tree().physics_frame
	var flame: Node2D = orb.get_node(^"animatedsprite2d") as Node2D
	var tip: Vector2 = Vector2.UP.rotated(flame.rotation)
	orb.set("direction", Vector2.DOWN)
	for i in 2:
		await get_tree().physics_frame
	var turned_tip: Vector2 = Vector2.UP.rotated(flame.rotation)
	check("the healer's orb streams its flame behind it - the art's tip points back along its flight, as it turns",
		tip.is_equal_approx(Vector2.LEFT) and turned_tip.is_equal_approx(Vector2.UP), [tip, turned_tip])
	orb.queue_free()

	var flying: BladeOrb = BladeOrb.fire(arena, base + Vector2(0, 100), Vector2(1, 1).normalized(), 200.0, 300.0, 0)
	var still: BladeOrb = BladeOrb.fire(arena, base + Vector2(0, 160), Vector2(1, 1).normalized(), 0.0, 300.0, 0)
	var flying_picture: Sprite2D = flying.get_node(^"picture") as Sprite2D
	var still_picture: Sprite2D = still.get_node(^"picture") as Sprite2D
	check("a flying orb is drawn long along its flight, one standing still round and square",
		is_equal_approx(flying_picture.rotation, Vector2(1, 1).angle()) and flying_picture.scale.is_equal_approx(BladeOrb.STRETCH)
		and BladeOrb.STRETCH.x > 1.0 and BladeOrb.STRETCH.y < 1.0
		and is_zero_approx(still_picture.rotation) and still_picture.scale.is_equal_approx(Vector2.ONE),
		[flying_picture.rotation, flying_picture.scale, still_picture.scale])
	flying.queue_free()
	still.queue_free()
	var ring: Node2D = FrostRing.spin(arena, base + Vector2(200, 0), 18.0, 0, {})
	var shard: BladeOrb = ring.get_child(1) as BladeOrb
	var spoke: Vector2 = (shard.position).normalized()
	var carried: float = (shard.get_node(^"picture") as Node2D).rotation
	ring.call("advance", FrostRing.ORBIT_SECONDS + 0.01)
	var thrown: float = (shard.get_node(^"picture") as Node2D).rotation
	check("  an ice shard is drawn along its ring as it is carried round, then along its way out",
		absf(Vector2.from_angle(carried).dot(spoke)) < 0.01
		and Vector2.from_angle(thrown).is_equal_approx(shard.direction), [carried, thrown, spoke])
	ring.queue_free()

	var field := BulletField.new()
	arena.add_child(field)
	field.bounds = Rect2(base - Vector2(500, 500), Vector2(1000, 1000))
	field.spawn(base, 0.5, 100.0, Color.WHITE)
	var drawn: Transform2D = field.shape_of(0)
	check("the Field's bullets are drawn long along their flight - the monsters' too",
		absf(drawn.x.length() - BulletField.SMALL_SIZE * BulletField.STRETCH_LONG) < 0.01
		and absf(drawn.y.length() - BulletField.SMALL_SIZE * BulletField.STRETCH_SHORT) < 0.01
		and absf(drawn.x.angle() - 0.5) < 0.001, [drawn.x, drawn.y])
	field.clear()
	var curving := BulletField.new()
	arena.add_child(curving)
	curving.bounds = field.bounds
	curving.spawn(base, 0.0, 100.0, Color.WHITE, true, 2.0)
	for i in 10:
		curving.step(1.0 / 60.0, Vector2.INF, 1.0, 0.0, true)
	var turned: Transform2D = curving.shape_of(0)
	check("  a curving one turns with its path, and a big one is drawn twice the size",
		absf(turned.x.angle() - 2.0 * 10.0 / 60.0) < 0.01
		and absf(turned.x.length() - BulletField.BIG_SIZE * BulletField.STRETCH_LONG) < 0.01, turned)
	var mines := BulletField.new()
	arena.add_child(mines)
	mines.bounds = field.bounds
	mines.spawn_settling(base, 1.0, 90.0, Color.WHITE, 26.0, 4.0)
	for i in 60:
		mines.step(1.0 / 60.0, Vector2.INF, 1.0, 0.0, true)
	var lying: Transform2D = mines.shape_of(0)
	check("  and one that has settled lies round and square, not a stretched orb turned",
		lying.x.is_equal_approx(Vector2(BulletField.SMALL_SIZE, 0)) and lying.y.is_equal_approx(Vector2(0, BulletField.SMALL_SIZE)),
		lying)
	for f in [field, curving, mines]:
		(f as Node).queue_free()

	# ---- HITBOXES THAT MATCH THE ART -------------------------------------------
	var off: Array = []
	var electric: Array = ["res://scene/pets/petprojectiles/petmagicprojectile.tscn"]
	for element in ["", "dark", "earth", "ice", "light", "water", "wind"]:
		electric.append("res://scene/projectiles/%smagicprojectile.tscn" % element)
	for path in electric:
		var shot: Node = (load(path) as PackedScene).instantiate()
		var sprite: AnimatedSprite2D = shot.get_node_or_null(^"AnimatedSprite2D") as AnimatedSprite2D
		if sprite == null:
			sprite = shot.get_node_or_null(^"animatedsprite2d") as AnimatedSprite2D
		var shape: CollisionShape2D = shot.find_children("*", "CollisionShape2D", false, false)[0] as CollisionShape2D
		var art: Vector2 = Vector2.ZERO
		if sprite != null and sprite.sprite_frames != null:
			var anim: StringName = sprite.sprite_frames.get_animation_names()[0]
			art = _opaque_size(sprite.sprite_frames.get_frame_texture(anim, 0)) * sprite.scale.x
		var across: float = (shape.shape as CircleShape2D).radius * 2.0 * shape.scale.x
		if art == Vector2.ZERO or absf(across - minf(art.x, art.y)) > 1.5:
			off.append([path.get_file(), across, art])
		shot.free()
	check("every electric orb's hit circle is as big as its art (it was 60% of it)", off.is_empty(), off)
	off.clear()
	for element in ["", "dark", "earth", "ice", "light", "water", "wind"]:
		var path: String = "res://scene/projectiles/%sarrow.tscn" % element
		var shot: Node = (load(path) as PackedScene).instantiate()
		var sprite: Sprite2D = shot.get_node(^"sprite2d") as Sprite2D
		var shape: CollisionShape2D = shot.get_node(^"attackrange") as CollisionShape2D
		var art: Vector2 = _opaque_size(sprite.texture) * sprite.scale
		var capsule: CapsuleShape2D = shape.shape as CapsuleShape2D
		# The shaft is three pixels of the art's five (the head and fletching
		# stand a pixel either side).
		if absf(capsule.radius * 2.0 - 3.0 * sprite.scale.y) > 0.05 or absf(capsule.height - art.x) > 1.5 * sprite.scale.x:
			off.append([path.get_file(), capsule.radius, capsule.height, art])
		shot.free()
	check("  and every arrow's is its shaft, three pixels thick (it was two)", off.is_empty(), off)
	var probe: Node = (load("res://scene/projectiles/turretprojectile.tscn") as PackedScene).instantiate()
	var healer_art: Vector2 = _opaque_size((probe.get_node(^"animatedsprite2d") as AnimatedSprite2D)
		.sprite_frames.get_frame_texture(&"projectile", 0))
	var healer_scale: float = (probe as Node2D).scale.x
	check("  the healer's orb reaches as far as its own flame is wide - half of it, 6, where it reached 14",
		is_equal_approx(float(probe.get("hit_pad")), healer_art.x * healer_scale / 2.0), [probe.get("hit_pad"), healer_art, healer_scale])
	probe.free()

	# ---- RULES -------------------------------------------------------------------
	var zap: Node2D = (load("res://scene/projectiles/magicprojectile.tscn") as PackedScene).instantiate()
	arena.add_child(zap)
	zap.global_position = base + Vector2(0, 300)
	zap.call("_on_visible_on_screen_notifier_2d_screen_exited")
	check("an electric orb flies its RANGE on every screen - leaving one is not the end of it",
		not zap.is_queued_for_deletion() and is_equal_approx(float(zap.get("lifetime")),
			float(zap.get("RANGE")) / float(zap.get("speed"))), [zap.get("lifetime"), zap.get("speed")])
	zap.queue_free()
	var pet_src: String = _func_body(_code_src("res://src/projectiles/petarrow.gd"), "func _check_initial_overlaps(")
	check("  a pet's arrow born inside a bush and a monster at once still hits the monster",
		pet_src.contains("if _spent:") and not pet_src.contains("_on_body_entered(body)\n\t\treturn"))
	arena.queue_free()
	await get_tree().process_frame


# =============================================================================
# THE MAGE'S KIT (0.71.0)
# =============================================================================
# The owner: "mage needs to be strong enough to kill enemies at level 1", and
# "consumes more mana deals more damage i was thinking more projectiles maybe a
# critical projectile also maybe some ice bullets that spin in a circle around
# the ring". A level 1 mage's whole bar was 144 damage, short of one sprite.
func _test_the_mage_kit() -> void:
	section("THE MAGE'S KIT - a heavy spike, a critical one, and ice shards round the ring (0.71.0, 0.71.1)")
	const FrostRing := preload("res://src/projectiles/frostring.gd")
	const Targets := preload("res://src/shared/targets.gd")
	var arena := Node2D.new()
	add_child(arena)
	var base := Vector2(-98000.0, 68000.0)

	# ---- THE HEAVY SPIKE ------------------------------------------------------
	var mage: Node2D = (load("res://scene/characters/mage.tscn") as PackedScene).instantiate()
	arena.add_child(mage)
	mage.set_physics_process(false)
	mage.global_position = base + Vector2(0, 150)
	check("the spike costs 20 mana, hits for 30 and casts once a second",
		int(mage.get("spell_mana_cost")) == 20 and int(mage.get("damage_per_magic")) == 30
		and is_equal_approx(float(mage.get("spell_cooldown")), 1.0),
		[mage.get("spell_mana_cost"), mage.get("damage_per_magic"), mage.get("spell_cooldown")])
	var sprite_hp: int = 233
	var bar: int = 250
	var per_bar: int = floori(float(bar) / float(mage.get("spell_mana_cost"))) * int(mage.get("damage_per_magic"))
	check("  so a level 1 mage's bar is more than a Wind Sprite - it was 144 of 233",
		per_bar >= sprite_hp, per_bar)

	# ---- THE CRITICAL SPIKE ---------------------------------------------------
	var _under_aim: CharacterBody2D = _weapon_dummy(arena, base + Vector2(10, 0))
	for i in 2:
		await get_tree().physics_frame
	mage.set("last_direction", Vector2.UP)
	mage.set("pointer_on_game", false)
	mage.set("crit_chance", 0.0)
	mage.set("stalagmite_casts", 0)
	var plain: Array = mage.call("_spawn_stalagmite")
	var plain_hit: int = int(plain[0].get("explosion_damage")) if not plain.is_empty() else -1
	var plain_crit: bool = plain.size() == 1 and plain[0].get("critical") == false
	for spell in plain:
		(spell as Node).queue_free()
	mage.set("crit_chance", 1.0)
	mage.set("stalagmite_casts", 0)
	var crit: Array = mage.call("_spawn_stalagmite")
	var crit_hit: int = int(crit[0].get("explosion_damage")) if not crit.is_empty() else -1
	check("a critical spike hits twice as hard (CRIT_MULT), one cast in five (CRIT_CHANCE)",
		plain_crit and absi(crit_hit - plain_hit * 2) <= 1 and is_equal_approx(float(_mage_const("CRIT_MULT")), 2.0)
		and is_equal_approx(float(_mage_const("CRIT_CHANCE")), 0.2), [plain_hit, crit_hit])
	var all_crit: bool = crit.size() == 3
	for spell in crit:
		all_crit = all_crit and spell.get("critical") == true and int(spell.get("explosion_damage")) == crit_hit
	check("  and drops the third cast's three spikes on the first cast, every one critical",
		all_crit, crit.size())
	for spell in crit:
		(spell as Node).queue_free()
	check("  rolled from crit_chance, or every cast with the owner panel's switch on",
		_func_body(_code_src("res://src/characters/mage.gd"), "func rolls_critical(").contains("common_forced() or randf() < crit_chance"))
	check("  and told to the others in the area, whose picture shatters as wide",
		_func_body(_code_src("res://src/characters/mage.gd"), "func _drop_spike(").contains("RemoteAttacks.FLAG_CRITICAL if critical else 0")
		and _func_body(_code_src("res://src/characters/remoteattacks.gd"), "static func _stalagmite(").contains("flags & FLAG_CRITICAL != 0")
		and RemoteAttacks.FLAG_CRITICAL == 128)
	mage.queue_free()

	# Its number: big and gold.
	var labels := Node2D.new()
	labels.add_to_group("floatinglabels")
	arena.add_child(labels)
	var sprite: BaseEnemy = (load("res://scene/enemy/firesprite.tscn") as PackedScene).instantiate()
	sprite.position = base + Vector2(400, 0)
	arena.add_child(sprite)
	sprite.set_physics_process(false)
	var was_on: Variant = Settings.get_value("damage_numbers")
	Settings.set_value("damage_numbers", true)
	var hp_before: int = sprite.hp
	sprite.take_damage(10)
	sprite.take_critical_damage(20)
	Settings.set_value("damage_numbers", was_on)
	var shown: Array = labels.get_children()
	var small: Node2D = shown[0] if shown.size() == 2 else null
	var big: Node2D = shown[1] if shown.size() == 2 else null
	var gold: Color = big.get("critical_color") if big != null else Color.BLACK
	check("a critical hit's number is bigger than a plain one's, and gold - the owner: \"we need that critical to be gold\"",
		small != null and big != null and big.scale.x > small.scale.x * 1.5
		and gold.is_equal_approx(Color(1.0, 0.82, 0.3)) and FloatingLabel.Type.CRITICAL == FloatingLabel.Type.size() - 1
		and (big.get("label") as CanvasItem).modulate.is_equal_approx(gold)
		and not (small.get("label") as CanvasItem).modulate.is_equal_approx(gold),
		[shown.size(), str(big.scale) if big != null else "none"])
	check("  the healer's double's gold, appended to the label types so no old number changes colour",
		gold.is_equal_approx((load("res://src/projectiles/turretprojectile.gd") as GDScript).get_script_constant_map().get("GOLD", Color.BLACK))
		and FloatingLabel.Type.NOTICE == 5)
	check("  and the hit itself is a plain hit: the monster takes what it was given",
		sprite.hp == hp_before - 30 and sprite.get("_critical_next") == false, [hp_before, sprite.hp])
	sprite.queue_free()

	# A critical spike shatters wider.
	var spike: Node2D = (load("res://scene/projectiles/spelltargetcircle.tscn") as PackedScene).instantiate()
	spike.set("cosmetic", true)
	spike.set("critical", true)
	arena.add_child(spike)
	spike.global_position = base + Vector2(800, 0)
	await get_tree().process_frame
	var before: Array = arena.get_children()
	var fall: AnimatedSprite2D = spike.get_node(^"stalagmiteprojectile") as AnimatedSprite2D
	fall.pause()
	fall.frame = 4
	var made: Array = arena.get_children().filter(func(n: Node) -> bool: return not before.has(n))
	var shatter: Blast = null
	var ring: Node2D = null
	for n in made:
		if n is Blast:
			shatter = n
		elif n.name.begins_with("frostring"):
			ring = n
	check("a critical spike shatters CRIT_SHATTER wider",
		shatter != null and is_equal_approx(shatter.radius, float(spike.get("circle_radius")) * float(spike.get("CRIT_SHATTER"))),
		str(shatter.radius) if shatter != null else "none")

	# ---- GOLD, as every class's big roll is - the owner: "well the spike gold" ----
	var gold_mat := fall.material as ShaderMaterial
	check("a critical spike comes down gold: its ice art turned to the healer's gold, shades lifted",
		gold_mat != null and gold_mat.shader == preload("res://src/shared/element_recolour.gdshader")
		and is_equal_approx(float(gold_mat.get_shader_parameter("element_hue")), float(spike.get("CRIT_HUE")))
		and float(gold_mat.get_shader_parameter("value_lift")) > 0.0
		and absf(float(spike.get("CRIT_HUE")) - Color(1.0, 0.82, 0.3).h) < 0.01,
		gold_mat)
	check("  its ring and glints gold, and its shatter",
		(spike.call("ring_colour") as Color).is_equal_approx(spike.get("CRIT_RING"))
		and (spike.get("CRIT_RING") as Color).r > (spike.get("CRIT_RING") as Color).b
		and shatter != null and shatter.modulate.is_equal_approx(spike.get("CRIT_TINT")),
		str(shatter.modulate) if shatter != null else "none")
	var plain_spike: Node2D = (load("res://scene/projectiles/spelltargetcircle.tscn") as PackedScene).instantiate()
	plain_spike.set("cosmetic", true)
	arena.add_child(plain_spike)
	check("  and a plain spike stays ice: no gold on its art, an ice ring",
		(plain_spike.get_node(^"stalagmiteprojectile") as CanvasItem).material == null
		and (plain_spike.call("ring_colour") as Color).is_equal_approx(plain_spike.get("RING_COLOUR")))
	plain_spike.queue_free()
	var them := Node2D.new()
	arena.add_child(them)
	them.global_position = base + Vector2(1000, 40)
	var told: Array = RemoteAttacks.fire(them, ["stalag", 0, them.global_position.x, them.global_position.y,
		them.global_position.x + 4.0, them.global_position.y - 40.0, 0, RemoteAttacks.FLAG_CRITICAL])
	var their_spike: Node = told[0] if not told.is_empty() else null
	check("  and somebody else's critical spike comes down gold on this screen too",
		their_spike != null and their_spike.get("critical") == true and their_spike.get("cosmetic") == true
		and (their_spike.get_node(^"stalagmiteprojectile") as CanvasItem).material is ShaderMaterial, told)
	if their_spike != null:
		their_spike.queue_free()
	them.queue_free()
	var shader_src: String = FileAccess.get_file_as_string("res://src/shared/element_recolour.gdshader")
	check("  the monsters' recolour shader lifts nothing unless asked (value_lift 0)",
		shader_src.contains("uniform float value_lift : hint_range(0.0, 1.0) = 0.0;")
		and shader_src.contains("hsv.z + (1.0 - hsv.z) * value_lift"))

	# ---- THE ICE SHARDS ---------------------------------------------------------
	var shards: Array = ring.get_children() if ring != null else []
	var ringed: bool = shards.size() == FrostRing.SHARDS and FrostRing.SHARDS == 6
	for o in shards:
		ringed = ringed and o is BladeOrb and o.palette == BladeOrb.GOLD and o.cosmetic and o.damage == 0 \
			and absf((o as Node2D).position.length() - float(spike.get("circle_radius")) - FrostRing.ORBIT_PAD) < 0.1
	check("as it lands, six shards ring it, just outside its frost ring - gold round a critical one, a picture's cutting nothing",
		ringed, shards.size())
	spike.queue_free()
	if ring != null:
		ring.queue_free()

	var centre: Vector2 = base + Vector2(1200, 0)
	var cast_hits: Dictionary = {}
	var landed_on: CharacterBody2D = _weapon_dummy(arena, centre + Vector2(60, 60))
	var crowd: CharacterBody2D = _weapon_dummy(arena, centre + Vector2(-60, 60))
	var spun: Node2D = FrostRing.spin(arena, centre, 18.0, 50, cast_hits)
	var held: Array = spun.get_children()
	var each_hit: int = roundi(50 * FrostRing.SHARD_SHARE)
	var shared_ok: bool = held.size() == 6 and is_equal_approx(FrostRing.SHARD_SHARE, 0.2) and FrostRing.SHARD_HITS_EACH == 2
	for o in held:
		shared_ok = shared_ok and o.damage == each_hit and is_same(o.cast_hits, cast_hits) \
			and o.cast_hits_each == FrostRing.SHARD_HITS_EACH and o.palette == BladeOrb.ICE
	check("each shard cuts for SHARD_SHARE (a fifth) of the spike's hit, counting the cast's hits together - frost white on a plain spike",
		shared_ok, [held.size(), each_hit])
	var start: Vector2 = (held[0] as Node2D).global_position
	spun.call("advance", FrostRing.ORBIT_SECONDS * 0.5)
	check("  they spin round the ring, held there, for ORBIT_SECONDS",
		spun.get("released") == false and (held[0] as Node2D).global_position.distance_to(start) > 4.0
		and absf((held[0] as Node2D).global_position.distance_to(centre) - start.distance_to(centre)) < 0.1
		and held.all(func(o: Node) -> bool: return is_zero_approx(o.speed)))
	spun.call("advance", FrostRing.ORBIT_SECONDS)
	var outward: bool = spun.get("released") == true
	for o in held:
		var shard: BladeOrb = o
		var out_way: Vector2 = (shard.global_position - centre).normalized()
		outward = outward and shard.direction.is_equal_approx(shard.position.normalized()) \
			and is_equal_approx(shard.speed, FrostRing.SHARD_SPEED) \
			and out_way.dot(shard.global_transform.basis_xform(shard.direction).normalized()) > 0.99
	check("  then fly straight out, each along its spoke", outward)
	var first: BladeOrb = held[0]
	var was: float = first.global_position.distance_to(centre)
	first._physics_process(0.1)
	check("  and away from the middle as they fly",
		first.global_position.distance_to(centre) > was + 20.0, [was, first.global_position.distance_to(centre)])

	# THE OWNER: "the spinning balls are not hitting the enemies, really we need
	# to increase the amount of times a enemy can be damaged and make sure
	# bullets are absorbed by impacts" (0.71.1).
	var a: BladeOrb = held[1]
	var b: BladeOrb = held[2]
	var c: BladeOrb = held[3]
	a._try_hit(landed_on)
	check("a shard hits the monster it touches - the spike's own mark too - and is spent on it",
		landed_on.get("taken") == [each_hit] and a._done, landed_on.get("taken"))
	b._try_hit(landed_on)
	check("  a second shard hits it again: SHARD_HITS_EACH (2) a monster a cast, after the spike",
		landed_on.get("taken") == [each_hit, each_hit] and b._done, landed_on.get("taken"))
	c._try_hit(landed_on)
	check("  a third is absorbed by it for nothing - never through it",
		landed_on.get("taken") == [each_hit, each_hit] and c._done, landed_on.get("taken"))
	(held[4] as BladeOrb)._try_hit(crowd)
	check("  and the count is each monster's: another one still takes its two",
		crowd.get("taken") == [each_hit] and int(cast_hits.get(crowd.get_instance_id(), 0)) == 1, crowd.get("taken"))
	spun.call("advance", FrostRing.MAX_SECONDS)
	check("  and the ring is gone by MAX_SECONDS, whatever is left",
		spun.is_queued_for_deletion())

	# IN THE GAME'S OWN PHYSICS: a monster on the ring is cut as the shards
	# spin into it, and the shard that cut it is gone.
	var swept_at: Vector2 = base + Vector2(1400, 0)
	var on_ring: CharacterBody2D = _weapon_dummy(arena, swept_at + Vector2(0, 18.0 + FrostRing.ORBIT_PAD))
	for i in 2:
		await get_tree().physics_frame
	var sweeping: Node2D = FrostRing.spin(arena, swept_at, 18.0, 50, {})
	for i in 20:
		await get_tree().physics_frame
	var left_spinning: int = 0
	if is_instance_valid(sweeping):
		for o in sweeping.get_children():
			if not (o as BladeOrb)._done:
				left_spinning += 1
	check("a monster on the ring is cut by the spinning shards themselves, and each that cuts it is spent",
		on_ring.get("taken").size() >= 1 and on_ring.get("taken").size() <= FrostRing.SHARD_HITS_EACH
		and left_spinning <= FrostRing.SHARDS - on_ring.get("taken").size(), [on_ring.get("taken"), left_spinning])
	if is_instance_valid(sweeping):
		sweeping.queue_free()

	# FOUR PLAYERS ON ONE MONSTER: the owner, "i do not want only 1 persons
	# attack to register". One spike a monster is one CAST's rule - each
	# caster's cast has its own count.
	var shared_target: CharacterBody2D = _weapon_dummy(arena, base + Vector2(1500, 200))
	for i in 2:
		await get_tree().physics_frame
	var casters: Array = []
	for i in 4:
		var theirs: Area2D = (load("res://scene/projectiles/spelltargetcircle.tscn") as PackedScene).instantiate()
		theirs.set("explosion_damage", 30)
		arena.add_child(theirs)
		theirs.global_position = Targets.body_point(shared_target) + Vector2(2.0 * i, 0)
		casters.append(theirs)
	for i in 3:
		await get_tree().physics_frame
	for theirs in casters:
		theirs.call("_apply_area_damage")
	check("four players' spikes on one monster all land - each cast has its own count",
		shared_target.get("taken") == [30, 30, 30, 30], shared_target.get("taken"))
	for theirs in casters:
		(theirs as Node).queue_free()

	# Not past a wall.
	var walled: Vector2 = base + Vector2(1600, 0)
	_attack_wall(arena, walled + Vector2(21, 0), Vector2(2, 400), 1)
	for i in 2:
		await get_tree().physics_frame
	var by_wall: Node2D = FrostRing.spin(arena, walled, 18.0, 50, {})
	var past: Array = by_wall.get_children().filter(func(o: Node) -> bool: return (o as Node2D).global_position.x > walled.x + 21.0)
	check("no shard starts past a wall: against a 2 px wall the spoke beyond it is left out",
		by_wall.get_child_count() == 5 and past.is_empty(), [by_wall.get_child_count(), past.size()])
	by_wall.queue_free()
	check("  and a spike's shards are spun as it strikes, counting with the cast's other shards",
		_func_body(_code_src("res://src/projectiles/spelltargetcircle.gd"), "func _spin_shards(").contains(
			"FrostRing.spin(parent, global_position, circle_radius, explosion_damage, shard_hits, cosmetic,")
		and _func_body(_code_src("res://src/characters/mage.gd"), "func _spawn_stalagmite(").contains("var shard_hits: Dictionary = {}")
		and _func_body(_code_src("res://src/projectiles/spelltargetcircle.gd"), "func _on_frame_changed(").contains("_spin_shards()"))
	arena.queue_free()
	await get_tree().process_frame
