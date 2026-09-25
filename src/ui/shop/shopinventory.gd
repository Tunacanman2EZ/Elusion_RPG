# shopinventory.gd — the vendor panel.
#
# ASKS THE SERVER WHAT THINGS COST, rather than multiplying ItemData.value by
# the shop's markup itself. It could do that and would usually get the same
# number — and the day the rounding rule changes it would quietly get a
# different one and display a price /api/shop/buy then refuses. A panel that
# shows a price the till disagrees with is worse than a panel that waits.
#
# NOTHING HERE GRANTS AN ITEM OR SPENDS GOLD. Both happen inside one server
# transaction; this sends the request and renders what comes back. See
# ShopData.gd's header for why: _reconcile_inventory() trims a client holding
# more than the server granted, but a client-side shop asserts BOTH halves of
# the trade — the item gained and the gold spent — and the trim only checks the
# first.
extends Control


# How long to wait on the network before giving up. Longer than a UI action
# normally deserves because the alternative — a purchase that timed out on the
# client but landed on the server — is the one outcome a shop must not produce.
const REQUEST_TIMEOUT := 6.0

# Icon size in a stock row. Matches the inventory slot art so the same item
# looks the same in both places.
const ICON_SIZE := Vector2(32, 32)


@onready var header_label: Label = %headerlabel
@onready var close_button: Button = %closebutton
@onready var gold_label: Label = %goldlabel
@onready var stock_list: VBoxContainer = %stocklist
@onready var notice_label: Label = %noticelabel


# Which vendor this panel is currently showing. Empty when closed.
var shop_id: String = ""

# The character slot buying. Captured when the panel opens rather than read at
# click time: a panel left open across a character switch would otherwise spend
# the wrong character's gold.
var character_slot: int = 0

# The player node that opened this, for show_notice(). Captured for the same
# reason, and collapsed to null rather than held as a freed reference — see
# _notify().
var _player: Node = null

# ONE REQUEST AT A TIME. Two Buy clicks in flight would each read the gold
# balance before either had spent it, and the second would be priced against a
# purse that no longer exists. The server would refuse the second one anyway;
# this stops the player watching it fail.
var _busy: bool = false


func _ready() -> void:
	close_button.pressed.connect(close_shop)
	visible = false


# =============================================================================
# OPEN / CLOSE
# =============================================================================

func open_for_shop(id: String, player: Node) -> void:
	shop_id = id
	_player = player if is_instance_valid(player) else null
	character_slot = CharacterData.active_character_index

	notice_label.text = ""
	visible = true
	_refresh_gold()
	await _load_catalogue()


func close_shop() -> void:
	visible = false
	shop_id = ""
	_player = null
	_clear_rows()

	# Tell the vendor so it can go back to idle and accept another interact.
	# Same handshake bankchest.gd uses — without it the world node still thinks
	# its panel is open and swallows every further press.
	var vendor: Node = get_tree().get_first_node_in_group("openvendor")
	if vendor != null and vendor.has_method("notify_panel_closed"):
		vendor.notify_panel_closed()


# =============================================================================
# CATALOGUE
# =============================================================================

func _load_catalogue() -> void:
	_clear_rows()
	_set_notice("Loading…", false)

	var res: Dictionary = await Api.get_json("/api/shop/%s" % shop_id, REQUEST_TIMEOUT)

	# PAST AN AWAIT. Logout frees every panel and a ladder changes the scene,
	# either of which can happen while this request is in flight. Same guard and
	# same reason as bankinventory.gd's transfer.
	if not is_instance_valid(self) or not is_inside_tree():
		return

	if not res.get("ok", false):
		_set_notice(_refusal_text(res, "Could not reach the shop."), true)
		return

	var data: Dictionary = res.get("data", {})
	header_label.text = str(data.get("display_name", "Shop"))

	var stock: Array = data.get("stock", []) if data.get("stock", []) is Array else []
	if stock.is_empty():
		_set_notice("This vendor has nothing for sale.", false)
		return

	_set_notice("", false)
	for entry in stock:
		if entry is Dictionary:
			stock_list.add_child(_build_row(entry))


func _build_row(entry: Dictionary) -> Control:
	var item_id: String = str(entry.get("item_id", ""))
	var price: int = int(entry.get("price", 0))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var icon := TextureRect.new()
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# FROM ItemRegistry, NOT FROM THE RESPONSE. The server has no icons — it
	# deals in ids — so the art comes from the same place the inventory gets it
	# and an item looks identical in both panels.
	var data: ItemData = ItemRegistry.get_item(item_id)
	if data != null:
		icon.texture = data.icon
		if data.icon_tint != Color.WHITE:
			icon.modulate = data.icon_tint
	row.add_child(icon)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 0)

	var name_label := Label.new()
	name_label.text = str(entry.get("display_name", item_id))
	name_label.add_theme_font_size_override("font_size", 13)
	text_column.add_child(name_label)

	var sub_label := Label.new()
	sub_label.text = "Tier %d  ·  %s%s" % [
		int(entry.get("tier", 1)),
		str(entry.get("type_name", "")).capitalize(),
		_requirement_suffix(entry),
	]
	sub_label.add_theme_font_size_override("font_size", 10)
	sub_label.add_theme_color_override("font_color", Color(0.7, 0.66, 0.6))
	text_column.add_child(sub_label)
	row.add_child(text_column)

	var price_label := Label.new()
	price_label.text = "%s g" % GameConstants.commas(price)
	price_label.add_theme_font_size_override("font_size", 13)
	price_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	price_label.custom_minimum_size = Vector2(56, 0)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price_label)

	var buy := Button.new()
	buy.text = "Buy"
	buy.custom_minimum_size = Vector2(52, 26)
	buy.add_theme_font_size_override("font_size", 12)
	# bind() rather than a lambda capturing the loop variable: a lambda would
	# close over whatever `entry` held when the signal fired, which on the last
	# iteration is every row's handler buying the same item.
	buy.pressed.connect(_on_buy_pressed.bind(item_id, price))
	row.add_child(buy)

	# HOVER SHOWS THE TOOLTIP, the same one the backpack and the equipment doll
	# use. The shop was the one place items were listed and could not be
	# inspected - which is the panel where you most need it, because you are
	# deciding whether to spend on something you do not own yet.
	#
	# MOUSE_FILTER_PASS, not STOP. The row holds a Buy button, and STOP on the
	# container eats the press before the button sees it. PASS lets the row see
	# the motion and the button keep the click.
	#
	# THE ROW IS ITS OWN source_slot. The tooltip tracks whoever asked so a hide
	# from somewhere else cannot close it; it does not care what kind of node
	# that is, only that the same one asks twice.
	if data != null:
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.mouse_entered.connect(_on_row_hovered.bind(row, data))
		row.mouse_exited.connect(_on_row_unhovered.bind(row))

	return row


func _on_row_hovered(row: Control, data: ItemData) -> void:
	var tooltip: Node = get_tree().get_first_node_in_group("itemtooltip")
	if tooltip == null or not tooltip.has_method("show_for_stack"):
		return
	# QUANTITY 1: the shop sells one at a time, and the tooltip only prints a
	# count above one, so this reads as an item rather than as a stack.
	tooltip.show_for_stack(ItemStack.new(data, 1), row)


func _on_row_unhovered(row: Control) -> void:
	var tooltip: Node = get_tree().get_first_node_in_group("itemtooltip")
	if tooltip == null or not tooltip.has_method("hide_tooltip"):
		return
	# ONLY IF THIS ROW IS THE ONE SHOWING. Moving between two rows fires exited
	# on the old and entered on the new in that order, so an unconditional hide
	# would close the tooltip the new row had just opened.
	if "_current_slot" in tooltip and tooltip._current_slot != row:
		return
	tooltip.hide_tooltip()


func _requirement_suffix(entry: Dictionary) -> String:
	# SHOWN, NOT ENFORCED. Buying ahead of your level is legitimate — a stack of
	# Greater Potions bought at 18 and drunk at 22 is planning, not an exploit,
	# and the store's own stock (potion tiers 1-3, needing levels 1, 5 and 10)
	# would be half-unbuyable if the shop refused. The line exists so the player
	# is told BEFORE they spend, rather than finding out when the potion refuses
	# to go down.
	#
	# FROM THE SERVER'S ROW, like the price: /api/shop/<id> sends the
	# requirements out of its own ItemData copy, so the label and the gate read
	# the same numbers even if the client's .tres files are stale.
	var parts := PackedStringArray()

	var level: int = int(entry.get("required_level", 1))
	if level > 1:
		parts.append("Lv %d" % level)

	var skill: String = str(entry.get("required_skill", "")).strip_edges()
	var skill_level: int = int(entry.get("required_skill_level", 1))
	if skill != "" and skill_level > 1:
		parts.append("%s %d" % [skill.capitalize(), skill_level])

	# THE CLASS, which is the one this rack needed most. The general store
	# sells an ironsword, an ironmaul, an ironstaff and an ironscepter side by
	# side - same level, same shelf, one per class - and nothing on the row
	# said which of them you could hold. The first time you found out was the
	# equip refusing, after you had paid.
	#
	# EMPTY MEANS ANYONE, which is most of the catalogue. A potion printing
	# "Needs: anyone" would be noise on every row to help on a few.
	#
	# Capitalised and joined with "or" rather than a comma: ironchest is
	# ["warrior", "tank"] and "Warrior, Tank" reads like it needs both.
	var classes: Array = entry.get("required_classes", []) if entry.get("required_classes", []) is Array else []
	if not classes.is_empty():
		var names := PackedStringArray()
		for c in classes:
			names.append(str(c).capitalize())
		parts.append(" or ".join(names))

	if parts.is_empty():
		return ""
	return "  ·  Needs %s" % ", ".join(parts)


func _clear_rows() -> void:
	for child in stock_list.get_children():
		child.queue_free()


# =============================================================================
# BUYING
# =============================================================================

func _on_buy_pressed(item_id: String, price: int) -> void:
	if _busy or shop_id == "":
		return

	# Checked here only to save a round trip and give an instant answer. The
	# server checks it too, against its own row, and its answer is the one that
	# counts — this number came from a save the client does not own.
	if _current_gold() < price:
		_set_notice("You cannot afford that.", true)
		return

	_busy = true
	_set_notice("", false)

	var acting_player: Node = _player if is_instance_valid(_player) else null

	var res: Dictionary = await Api.post("/api/shop/buy", {
		"slot": character_slot,
		"shop_id": shop_id,
		"item_id": item_id,
		"quantity": 1,
	}, REQUEST_TIMEOUT)

	if not is_instance_valid(self) or not is_inside_tree():
		return

	_busy = false

	if not res.get("ok", false):
		_set_notice(_refusal_text(res, "The vendor refused the sale."), true)
		return

	var data: Dictionary = res.get("data", {})

	# THE SERVER'S NUMBERS, NOT A LOCAL SUBTRACTION. It already decided the
	# price and the new balance; recomputing here would be a second opinion that
	# can disagree, and the disagreement would show up as a purse that drifts.
	_apply_purchase(data, acting_player)


func _apply_purchase(data: Dictionary, acting_player: Node) -> void:
	var gold: int = int(data.get("gold", _current_gold()))
	_write_gold(gold)
	_refresh_gold()

	# The backpack the server laid out, applied the same way a loot take
	# applies it — so the client and the server never disagree about which cell
	# the purchase landed in. See _add_to_backpack()'s header for why placement
	# is the server's decision, and lootbaginventory.gd for the same three
	# lines: the coercion and the load live on the container because two copies
	# of "parse the server's array" is how they stop agreeing.
	var cells: Array = data.get("inventory", []) if data.get("inventory", []) is Array else []
	if not cells.is_empty():
		var container: Node = _player_inventory_container()
		if container != null:
			container.load_server_array(cells)
		else:
			push_warning("ShopInventory: player inventory not found — the server has the item, this screen does not")

	Audio.play("coin")

	var bought: String = str(data.get("item_id", ""))
	var paid: int = int(data.get("total_paid", 0))
	var label: String = bought
	var item: ItemData = ItemRegistry.get_item(bought)
	if item != null:
		label = item.display_name
	_notify(acting_player, "Bought %s for %s." % [label, GameConstants.gold_text(paid)])


func _player_inventory_container() -> Node:
	# Reached through the HUD rather than held as a reference: the inventory
	# screen is lazily created and freed on logout, so a cached node here would
	# be a dangling pointer the first time someone logs out and back in.
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return null
	var inventory_screen: Node = hud.get("inventory_screen") if "inventory_screen" in hud else null
	if inventory_screen == null:
		return null
	return inventory_screen.get_node_or_null("%inventorycontainer")


# =============================================================================
# GOLD
# =============================================================================

func _current_gold() -> int:
	var player: Node = _player if is_instance_valid(_player) else null
	if player != null and "gold" in player:
		return int(player.gold)
	return 0


func _write_gold(amount: int) -> void:
	var player: Node = _player if is_instance_valid(_player) else null
	if player == null:
		return
	if player.has_method("set_gold"):
		player.set_gold(amount)
	elif "gold" in player:
		player.gold = amount


func _refresh_gold() -> void:
	var carried: int = _current_gold()
	gold_label.text = "Gold: %s" % GameConstants.commas(carried)
	# Carried gold, because that is the pile this till can take.
	GameConstants.apply_gold_icon(get_node_or_null("%goldicon"), carried)


# =============================================================================
# MESSAGES
# =============================================================================

func _set_notice(message: String, is_error: bool) -> void:
	notice_label.text = message
	notice_label.add_theme_color_override(
		"font_color",
		Color(1, 0.6, 0.5) if is_error else Color(0.75, 0.72, 0.66),
	)


func _refusal_text(res: Dictionary, fallback: String) -> String:
	# READS res.error, WHICH api.gd HAS ALREADY BUILT. The first version of this
	# reached into res.data.message itself and re-derived what
	# _describe_api_error() had just finished deriving — worse, because it only
	# handled message-as-String and quietly dropped the ARRAY form a validation
	# failure returns.
	#
	# AND IT LIED ABOUT THE FIRST REAL FAILURE. The panel came up saying "Could
	# not reach the shop." while the server was running and answering every
	# other call; the endpoint was simply missing from it, and a 404 with a
	# Flask HTML body parses to nothing, so the old code fell through to a
	# sentence about the network. That sentence cost the time it takes to prove
	# a server is up. A message that names the wrong subsystem is worse than no
	# message, because it is believed.
	var status: int = int(res.get("status", 0))
	if status == 0:
		# Nothing answered. res.error already says which kind of nothing.
		var transport: String = str(res.get("error", ""))
		return transport if transport != "" else "No connection to the server."

	# SAID OUT LOUD, because it is not a player problem. The server is up and
	# refusing to admit this route exists, which in practice means it is running
	# an app.py older than the shop.
	if status == 404:
		push_warning("ShopInventory: the server has no /api/shop route — is app.py current and restarted?")
		return "The server doesn't know this shop yet."

	var message: String = str(res.get("error", ""))
	if message != "":
		return message
	return "%s (HTTP %d)" % [fallback, status]


func _notify(player: Node, message: String) -> void:
	# Callers collapse a freed reference to null before calling. GDScript checks
	# a typed Node parameter AT THE CALL BOUNDARY, so a freed object never
	# reaches this body to be guarded against — the same trap combat.gd
	# documents at length.
	if is_instance_valid(player) and player.has_method("show_notice"):
		player.show_notice(message)
