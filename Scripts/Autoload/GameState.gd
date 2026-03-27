## Global game state manager.
##
## Persists and manages player state across scene transitions.
## Must be configured as an Autoload in Project Settings.
extends Node


# ==============================================================================
# Member variables
# ==============================================================================

var player_health: float = 30.0
var player_max_health: float = 30.0
var player_key_count: int = 0
var player_position: Vector3 = Vector3.ZERO

var current_level: String = ""
var spawn_point_name: String = "default"


# ==============================================================================
# Public methods
# ==============================================================================

func save_player_state(player: CharacterBody3D) -> void:
	"""Saves the current player state."""
	player_health = player.current_health
	player_max_health = player.max_health
	player_key_count = player.key_count
	player_position = player.global_position


func load_player_state(player: CharacterBody3D) -> void:
	"""Loads the saved player state."""
	player.current_health = player_health
	player.max_health = player_max_health
	player.key_count = player_key_count

	if player.has_method("refresh_ui_state"):
		player.refresh_ui_state()


func reset_player_state() -> void:
	"""Resets the player state to default values."""
	player_health = 30.0
	player_max_health = 30.0
	player_key_count = 0
	player_position = Vector3.ZERO
	spawn_point_name = "default"
