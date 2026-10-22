# economyrules.gd - THE ECONOMY'S NUMBERS (0.74.0), the EconomyRules autoload.
#
# The owner, of the fifth economy idea: "Economy numbers you can change without
# shipping ... Today, changing the trade tax or a price means a new version. If
# those numbers lived on the server, you could adjust them in a minute." They
# live on the server now (the API's economyrules/), and this holds the four the
# game draws, read once a login from GET /api/economy/rules:
#
#   shop_price_multiplier   the general store's prices, times an item's value
#   shop_sell_multiplier    what it pays for one, times its value
#   trade_tax_rate          the kingdom's share of a trade
#   trade_tax_minimum       the smallest tax a taxed trade pays
#
# UNTIL THE SERVER HAS SAID, AND WHEN IT CANNOT, the catalogue's own numbers -
# the general store's ShopData and GameConstants' tax - which are exactly what
# the server uses while the owner has set nothing. A server from before 0.74.0
# answers 404 and the game goes on with those, as it always did.
#
# NOTHING HERE DECIDES A PRICE THAT IS PAID. The till, the buy-back and the tax
# are the server's, from its own table; the shop window still draws the prices
# /api/shop/<id> sends. What this is for is the words around them - what share
# the shop pays, whether today's prices are the usual ones - and a price for a
# row an answer left out, worked out the way the server works it.
extends Node


signal changed()

const PATH := "/api/economy/rules"
const GENERAL_STORE := "res://data/shops/generalstore.tres"
# The four, and the bounds the server allows each (economyrules/services.py,
# RULES): a number outside them is not believed, it is somebody else's answer.
const BOUNDS := {
	"shop_price_multiplier": [0.25, 4.0],
	"shop_sell_multiplier": [0.0, 0.5],
	"trade_tax_rate": [0.0, 0.5],
	"trade_tax_minimum": [1.0, 10000.0],
}

# Where the read goes; a seam for the suite.
var fetch: Callable = Callable(Api, "get_json")
# What the server said, checked: only the keys it sent and this believes.
var numbers: Dictionary = {}
# The login the numbers were read for, so a login reads them once.
var _read_for: String = ""
var _asking: bool = false
# The catalogue's numbers, read once.
var _usual: Dictionary = {}


func _ready() -> void:
	# ONCE A LOGIN: a new name on Api is a login (or a sign-out). A login
	# remembered from last time does not change the name, so the shop also
	# asks ensure() when it opens - whichever comes first reads them.
	if not Api.identity_changed.is_connected(_on_identity_changed):
		Api.identity_changed.connect(_on_identity_changed)


func _on_identity_changed(new_username: String, _new_role: String) -> void:
	if new_username == "":
		forget()
	elif Api.token != "" and Api.token != _read_for:
		refresh()


# =============================================================================
# THE NUMBERS
# =============================================================================

func number(key: String) -> float:
	"""The number in force for `key`: the server's, or the catalogue's."""
	if numbers.has(key):
		return float(numbers[key])
	return float(usual().get(key, 0.0))


func usual() -> Dictionary:
	"""The catalogue's four: what the game shipped with."""
	if _usual.is_empty():
		_usual = catalogue_numbers()
	return _usual


func differs(key: String) -> bool:
	"""Whether the owner has `key` at something other than the usual."""
	return not is_equal_approx(number(key), float(usual().get(key, 0.0)))


func buy_price(value: int) -> int:
	"""What the general store charges for something worth `value`."""
	return price_for(value, number("shop_price_multiplier"))


func sell_price(value: int) -> int:
	"""What it pays for one, before the cap at what it charges."""
	return pays_for(value, number("shop_sell_multiplier"))


func trade_tax(value: int) -> int:
	"""The kingdom's tax on receiving `value` worth of goods and gold."""
	return tax_for(value, number("trade_tax_rate"), roundi(number("trade_tax_minimum")))


static func catalogue_numbers() -> Dictionary:
	"""The four as the catalogue has them: the general store's ShopData and
	GameConstants' kingdom tax."""
	var store: ShopData = load(GENERAL_STORE) as ShopData
	return {
		"shop_price_multiplier": float(store.price_multiplier) if store != null else 1.0,
		"shop_sell_multiplier": float(store.sell_multiplier) if store != null else 0.05,
		"trade_tax_rate": float(GameConstants.KINGDOM_TAX_RATE),
		"trade_tax_minimum": float(GameConstants.KINGDOM_TAX_MINIMUM),
	}


static func checked(said: Variant) -> Dictionary:
	"""The numbers in `said` that this believes: a known key, a number, inside
	its bounds. Pure, so the suite can hand it anything."""
	var out: Dictionary = {}
	if not (said is Dictionary):
		return out
	for key in BOUNDS:
		var raw: Variant = (said as Dictionary).get(key)
		if not (raw is float or raw is int):
			continue
		var value: float = float(raw)
		if is_nan(value) or is_inf(value) or value < float(BOUNDS[key][0]) or value > float(BOUNDS[key][1]):
			continue
		out[key] = value
	return out


# THE SERVER'S ARITHMETIC (gamedata.py): up for a price, down for what is
# paid, at least 1 for a price; and the float's dust taken off first, so 1.1
# of 100 is 110 and not 111.
static func price_for(value: int, multiplier: float) -> int:
	return maxi(1, ceili(snappedf(float(value) * multiplier, 0.000000001)))


static func pays_for(value: int, multiplier: float) -> int:
	return floori(snappedf(float(value) * multiplier, 0.000000001))


static func tax_for(value: int, rate: float, minimum: int) -> int:
	if value <= 0:
		return 0
	return maxi(minimum, ceili(snappedf(float(value) * rate, 0.000000001)))


static func percent_text(multiplier: float) -> String:
	"""0.05 -> '5%', 1.5 -> '150%', 0.125 -> '12.5%'."""
	var text: String = "%.1f" % (multiplier * 100.0)
	return text.trim_suffix(".0") + "%"


# =============================================================================
# THE SERVER
# =============================================================================

func refresh() -> bool:
	"""Read them from the server. True when it answered with numbers; on
	anything else the ones held stay (the catalogue's, until a read works)."""
	if _asking:
		return false
	_asking = true
	var asked_for: String = Api.token
	var res: Dictionary = await fetch.call(PATH)
	_asking = false
	# A SERVER THAT ANSWERED HAS BEEN ASKED, whatever it said: one from
	# before 0.74.0 says 404 every time, and asking it again at every shop is
	# a request for the same 404. Unreachable (0) is asked again next time.
	if int(res.get("status", 0)) != 0:
		_read_for = asked_for
	if not res.get("ok", false) or not (res.get("data") is Dictionary):
		return false
	var said: Variant = (res.get("data") as Dictionary).get("rules")
	if not (said is Dictionary):
		return false
	adopt(said)
	return true


func ensure() -> void:
	"""Read them if this login has not yet. Not awaited: whoever asks draws
	with what is held now and hears `changed` when the server has said."""
	if Api.token != "" and Api.token != _read_for and not _asking:
		refresh()


func adopt(said: Variant) -> void:
	"""Numbers the server sent - its rules answer, or the multipliers a shop
	answer carries, which are the same rules read a moment ago."""
	var believed: Dictionary = checked(said)
	if believed.is_empty():
		return
	var was: Dictionary = numbers.duplicate()
	for key in believed:
		numbers[key] = believed[key]
	if numbers != was:
		changed.emit()


func note_shop(answer: Dictionary) -> void:
	"""The general store's answer carries the two shop numbers in force."""
	var said: Dictionary = {}
	if answer.has("price_multiplier"):
		said["shop_price_multiplier"] = answer.get("price_multiplier")
	if answer.has("sell_multiplier"):
		said["shop_sell_multiplier"] = answer.get("sell_multiplier")
	adopt(said)


func forget() -> void:
	"""Signed out: back to the catalogue's numbers, read again next login."""
	var had: bool = not numbers.is_empty()
	numbers = {}
	_read_for = ""
	if had:
		changed.emit()
