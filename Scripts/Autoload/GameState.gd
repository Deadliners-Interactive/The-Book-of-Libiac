extends Node

# Datos persistentes del jugador
var player_health: float = 30.0
var player_max_health: float = 30.0
var player_key_count: int = 0
var player_position: Vector3 = Vector3.ZERO

# Información del nivel actual
var current_level: String = ""
var spawn_point_name: String = "default"

func save_player_state(player: CharacterBody3D):
	"""Guarda el estado actual del jugador"""
	player_health = player.current_health
	player_max_health = player.max_health
	player_key_count = player.key_count
	player_position = player.global_position
	print("💾 GameState: Estado guardado - HP:", player_health, "Llaves:", player_key_count)

func load_player_state(player: CharacterBody3D):
	"""Carga el estado guardado al jugador"""
	player.current_health = player_health
	player.max_health = player_max_health
	player.key_count = player_key_count
	print("📂 GameState: Estado cargado - HP:", player_health, "Llaves:", player_key_count)
	
	# Actualizar UI si existe
	if player.ui_ref:
		if player.ui_ref.has_method("update_hearts_display"):
			player.ui_ref.update_hearts_display()
		if player.ui_ref.has_method("update_keys_display"):
			player.ui_ref.update_keys_display()

func reset_player_state():
	"""Reinicia el estado a valores por defecto"""
	player_health = 30.0
	player_max_health = 30.0
	player_key_count = 0
	player_position = Vector3.ZERO
	spawn_point_name = "default"
	print("🔄 GameState: Estado reiniciado a valores por defecto")
