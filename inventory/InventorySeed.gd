extends Object
class_name InventorySeed

## Lightweight seed helpers to validate inventory UI/stacking/persistence.
## Safe: only seeds when the inventory appears empty.

static func is_empty(inv: Inventory) -> bool:
	if inv == null:
		return true
	for s in inv.slots:
		if s != null:
			return false
	return true

static func seed_bag_if_empty(inv: Inventory) -> void:
	if inv == null:
		return
	if not is_empty(inv):
		return

	var potion: ItemType = load("res://items/test_potion.tres")
	var coin: ItemType = load("res://items/test_coin.tres")
	var treasure: ItemType = load("res://items/test_treasure.tres")
	if potion:
		inv.try_add(potion, 5)
	if coin:
		inv.try_add(coin, 35)
	if treasure:
		inv.try_add(treasure, 1)


