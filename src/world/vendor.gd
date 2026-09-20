# vendor.gd — the shopkeeper behind the counter.
#
# Structurally bankchest.gd without the animation: walk into the area, press
# interact, a panel opens. The differences are deliberate and both come from
# the vendor being a person rather than furniture — there is no open/close
# animation to wait on, so the panel appears on the press, and walking away
# closes the shop rather than shutting a lid.
#
# WHAT THIS DOES NOT DO: grant items or spend gold. See ShopData.gd's header.
# The panel asks the server and renders the answer; this file only decides when
# the panel is on screen.
extends Area2D


# Matches bankchest.gd and firepit.gd. Stops a shop opening on the interact key
# the player was already holding when the scene loaded — which, arriving into a
# building through a door, is more common here than anywhere else.
const SPAWN_GRACE_PERIOD := 1.0

# The panel finds its vendor through this group rather than a stored reference,
# so closing the panel can hand control back without the two nodes holding
# pointers at each other across a scene change.
const OPEN_VENDOR_GROUP := &"openvendor"

# EVERY vendor, for its whole life — which is what makes it different from
# OPEN_VENDOR_GROUP above. That one is joined only while a shop is open, so the
# panel's lookup finds at most one and never has to guess. This one answers
# "is there a shop here at all", which is the question the HUD's Shop button
# has to ask before it can do anything useful.
const VENDOR_GROUP := &"vendors"


# The catalogue this vendor sells. Assign in the Inspector.
#
# Typed as ShopData rather than Resource so a wrong .tres is a parse-time error
# in the editor instead of a null property access when a player walks up.
@export var shop_data: ShopData = null


var _player_nearby: Node = null
var _is_open: bool = false
var _spawn_timer: float = 0.0


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_spawn_timer = SPAWN_GRACE_PERIOD

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	add_to_group(VENDOR_GROUP)

	# LOUD, EARLY, AND ONLY IN A DEBUG BUILD. A vendor with no catalogue is a
	# shop that cannot sell anything, and the symptom later would be an empty
	# panel with no explanation. Checked on load rather than at interact time so
	# it surfaces when the scene opens rather than whenever someone walks up.
	if OS.is_debug_build() and shop_data == null:
		push_warning("Vendor (%s): no shop_data assigned — this shop has nothing to sell" % name)


func _process(delta: float) -> void:
	if _spawn_timer > 0.0:
		_spawn_timer -= delta
		return

	if _player_nearby == null:
		return
	if _is_open:
		return
	if not Input.is_action_just_pressed("interact"):
		return

	_open_shop()


# =============================================================================
# PROXIMITY
# =============================================================================

func _on_body_entered(body: Node) -> void:
	if body != null and (body.name == "Player" or body.is_in_group("player")):
		_player_nearby = body


func _on_body_exited(body: Node) -> void:
	if body == null or not (body.name == "Player" or body.is_in_group("player")):
		return

	_player_nearby = null

	# WALKING AWAY CLOSES THE SHOP. Without this the panel stays up while the
	# player runs off, and because _process() swallows every interact press
	# while _is_open, they could never open it again either — the same trap
	# bankchest.gd documents at _close_chest_on_walk_away().
	if _is_open:
		_close_shop()


# =============================================================================
# OPEN / CLOSE
# =============================================================================

# PUBLIC, for the HUD's Shop button. Walking up and pressing interact is the
# primary way in and always will be — this is the second door, for a player who
# is standing at the counter and reaches for the button instead.
#
# It answers rather than acts when there is nobody here, so the button can tell
# the player why nothing happened. A button that silently does nothing is the
# bug this whole handler was filed under.
func can_open_for_player() -> bool:
	return (_player_nearby != null
		and not _is_open
		and shop_data != null
		and shop_data.shop_id != "")


func open_for_player() -> void:
	if can_open_for_player():
		_open_shop()


func _open_shop() -> void:
	if shop_data == null or shop_data.shop_id == "":
		# Nothing to show. Said out loud rather than opening an empty panel,
		# because an empty shop and a misconfigured one look identical to a
		# player and only one of them is worth reporting.
		push_warning("Vendor (%s): interact ignored — no shop_data" % name)
		return

	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null:
		push_error("Vendor: CRITICAL — no node in the 'hud' group found")
		return
	if not hud.has_method("open_shop"):
		push_error("Vendor: the HUD has no open_shop() — is characterhud.gd current?")
		return

	_is_open = true
	# Joined only while open, so the panel's lookup finds AT MOST one vendor
	# and never has to guess which of several it belongs to.
	add_to_group(OPEN_VENDOR_GROUP)

	hud.open_shop(shop_data.shop_id, _player_nearby)


func _close_shop() -> void:
	_is_open = false
	if is_in_group(OPEN_VENDOR_GROUP):
		remove_from_group(OPEN_VENDOR_GROUP)

	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("close_shop"):
		hud.close_shop()


func notify_panel_closed() -> void:
	# Called BY the panel when the player closes it with the X. Only clears
	# this node's state — calling back into the HUD here would close the panel
	# that is already closing, which is how a close handler ends up recursing.
	_is_open = false
	if is_in_group(OPEN_VENDOR_GROUP):
		remove_from_group(OPEN_VENDOR_GROUP)


func _exit_tree() -> void:
	# A scene change frees this node while it may still be in the group, and a
	# freed node left in a group is exactly the dangling reference the panel's
	# is_instance_valid() checks exist to survive. Cheaper to not leave one.
	if is_in_group(OPEN_VENDOR_GROUP):
		remove_from_group(OPEN_VENDOR_GROUP)
