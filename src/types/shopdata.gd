# shopdata.gd — what one vendor sells.
#
# WHY THIS IS A RESOURCE AND NOT AN ARRAY ON THE VENDOR NODE. A shop's stock is
# content, not scene layout: it wants to be diffable, reviewable and editable
# without opening the scene the vendor happens to stand in, and eventually
# readable by the SERVER, which has no scenes at all. ItemData and EnemyData
# are already authored this way for the same reason.
#
# PRICES ARE NOT STORED HERE. They come from ItemData.value, multiplied by
# price_multiplier. Storing a second copy of the price next to the item is how
# two numbers for one thing drift apart — and the whole point of the tier curve
# on ItemData.value is that there is ONE price ladder for the whole game. A
# vendor that hardcoded its own numbers would be outside it within a week.
#
# =============================================================================
# THE BUY HAS TO HAPPEN ON THE SERVER
# =============================================================================
# This resource is the catalogue, not the till. Nothing here may grant an item
# or deduct gold on the client.
#
# _reconcile_inventory() in app.py says this in its own docstring: "Shops,
# crafting and cooking do not exist server-side yet; the day they do, each must
# grant through the server the same way." Every legitimate gain today writes
# carry_items server-side BEFORE the client syncs — loot, bank withdrawals,
# staff grants. A client-side shop would be the first exception, and it would
# be an item printer: hold more than the server granted and the trim catches
# it, but a client that also asserts the gold it spent is asserting both halves
# of the trade.
#
# So a purchase is POST /api/shop/buy: the server checks the shop stocks the
# item, computes the price from its own ItemData copy, checks the player's
# gold, then deducts and grants in one transaction. The gold it removes is a
# SINK — it leaves the economy rather than moving to anyone.
class_name ShopData
extends Resource


# Stable id, used by the server to look this shop up and to key the buy
# request. Must be unique across every shop.
@export var shop_id: String = ""

# Shown as the panel's header.
@export var display_name: String = "Shop"

# item_ids this vendor sells, in display order. Every entry must resolve in
# ItemRegistry — an id with no ItemData is a row the player can click and not
# receive, which is worse than the item simply not being listed.
@export var stock: Array[String] = []

# Vendor markup over ItemData.value. 1.0 sells at the reference price.
#
# ABOVE 1.0 IS THE SAFE DIRECTION. The vendor is a gold SINK — every purchase
# destroys currency — so a markup drains faster. Going BELOW 1.0 would let a
# player buy here and sell to another player at the reference price, which
# turns a sink into a faucet and is the RuneScape high-alchemy trap in reverse.
@export var price_multiplier: float = 1.0

# WHAT THIS VENDOR PAYS when a player sells to it, as a fraction of
# ItemData.value (5 Oct, the owner: "we should be able to sell items to the
# shop"). The server rounds it down, pays only for gear, potions and food,
# fish and the fishing kit, and never pays what it charges.
#
# SMALL ON PURPOSE. Selling MINTS gold, the one shop action that does, and
# gear drops are worth seven or eight times an hour's coin at catalogue value.
# At 0.1 a player who sold everything earned a set in about four hours, which
# undid the same day's price pass (sets at six to eight hours of coin); at
# 0.05 it is about five, and a spare jade sword is still thirteen kills' coin
# in the band that drops it. The API's test_pacing.py measures both with the
# real kill roll.
#
# MUST STAY BELOW price_multiplier. A vendor that pays what it asks is a
# printing press: buy, sell, repeat.
@export var sell_multiplier: float = 0.05

# Reserved for limited stock. 0 means this vendor never runs out, which is what
# a starter shop wants: a queue for potions is not interesting, and scarcity
# here would push players to hoard rather than spend — the opposite of what a
# sink is for.
@export var restock_seconds: float = 0.0
