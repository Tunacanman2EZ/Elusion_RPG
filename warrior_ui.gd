extends Control

var player: Node = null

func setup(player_ref):
	player = player_ref
	update_stats()
	$AttackButton.connect("pressed", Callable(self, "_on_AttackButton_pressed"))

func update_stats():
	if player == null:
		return
	$HPBar.max_value = player.max_hp
	$HPBar.value = player.hp
	$HPLabel.text = "HP: %d/%d" % [player.hp, player.max_hp]
	$StaminaBar.max_value = 100  # Adjust as needed for cap
	$StaminaBar.value = player.stamina if "stamina" in player else 100
	$StaminaLabel.text = "Stamina: %d/100" % [$StaminaBar.value]

func _on_AttackButton_pressed():
	if player:
		player.attack_action()  # Calls player's universal attack logic
