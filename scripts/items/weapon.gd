## Weapon item type - extends Item with combat stats
extends Item
class_name Weapon

@export var damage: int = 0
@export var attack_speed: float = 1.0
@export var attack_range: int = 1
@export var element: GameState.Element = GameState.Element.NONE

