## Player spawn point marker.
## Positions player at this location when transitioning from GameState.spawn_point_name.
extends Node3D

# ==============================================================================
# Exports
# ==============================================================================

@export var _spawn_id: String = "default"

# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	add_to_group("spawn_point")

	# Position player at this spawn point if it matches the GameState spawn ID
	if GameState.spawn_point_name == _spawn_id:
		call_deferred("_position_player")

# ==============================================================================
# Private Methods
# ==============================================================================

func _position_player() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = global_position
