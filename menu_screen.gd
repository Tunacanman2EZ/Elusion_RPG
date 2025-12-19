extends Control

"""Main menu screen: handles menu toggle, content switching, and inventory display."""

var popup_recently_closed := false

func _ready():
	$Popup.hide()
	show_panel("InventoryPanel")
	update_inventory_panel()

# --- Menu toggle ---

func _on_MenuButton_pressed():
	if popup_recently_closed:
		return
	if $Popup.visible:
		$Popup.hide()
	else:
		$Popup.popup_centered()

func _on_Popup_popup_hide():
	popup_recently_closed = true
	await get_tree().create_timer(0.1).timeout
	popup_recently_closed = false

# --- Navigation buttons ---

func _on_InventoryButton_pressed():
	update_inventory_panel()
	show_panel("InventoryPanel")

func _on_StatsButton_pressed():
	show_panel("StatsPanel")

func _on_OptionsButton_pressed():
	show_panel("OptionsPanel")

func _on_MapButton_pressed():
	show_panel("MapPanel")

func _on_ShopButton_pressed():
	show_panel("ShopPanel")

func _on_DiscordButton_pressed():
	OS.shell_open("https://discord.gg/4PEhh4Uu")

func _on_LogoutButton_pressed():
	get_tree().quit()

# --- Show only the active content panel ---

func show_panel(panel_name: String):
	var panels = $Popup/MainMargin/MainHBox/ContentPanels.get_children()
	for panel in panels:
		panel.visible = (panel.name == panel_name)

# --- Inventory display logic ---

func update_inventory_panel():
	var parent = get_parent()
	if not parent or not parent.has_node("Player"):
		print("Player node not found for MenuPanel!")
		return

	var player = parent.get_node("Player")
	var inv_panel = $Popup/MainMargin/MainHBox/ContentPanels/InventoryPanel
	inv_panel.get_node("GoldLabel").text = "Gold: %d" % player.gold
	inv_panel.get_node("LusionsLabel").text = "Lusions: %d" % player.lusions

	var items_container = inv_panel.get_node("ItemsContainer")
	for i in range(20):
		var slot = items_container.get_node_or_null("InventorySlot%d" % (i + 1))
		if slot:
			if i < player.inventory.size():
				slot.text = str(player.inventory[i])
				slot.disabled = false
			else:
				slot.text = ""
				slot.disabled = true
		else:
			print("Missing inventory slot node: ", "InventorySlot%d" % (i + 1))
