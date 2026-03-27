extends Node3D

@export var spawn_id: String = "default"

func _ready():
	add_to_group("spawn_point")
	
	# Si este es el punto de spawn correcto, teleportar al jugador aquí
	if GameState.spawn_point_name == spawn_id:
		call_deferred("_position_player")

func _position_player():
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = global_position
		print("📍 SpawnPoint: Jugador posicionado en:", spawn_id)
