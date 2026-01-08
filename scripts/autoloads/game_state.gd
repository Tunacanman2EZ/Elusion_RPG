extends Node

## Global game state - persists across scenes

var player_position := Vector2()
var logged_in_username := ""

## Element types for magic/damage system
enum Element {
	NONE,
	DARK,
	LIGHT,
	ICE,
	WIND,
	EARTH,
	FIRE,
	WATER
}

