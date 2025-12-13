extends Node # <-- CAMBIAR: Ya no extiende Area3D, ahora extiende Node (Autoload/Singleton)

# ==============================================================================
# GAME OVER HANDLER - Secuencia de muerte y reinicio
# ==============================================================================

@export var death_message: String = "¡Has muerto! Inténtalo de nuevo."
@export var show_message: bool = true
@export var fade_duration: float = 1.0
@export var restart_delay: float = 1.5 # Más tiempo para leer el mensaje

var has_triggered: bool = false
var player_ref = null # Para guardar la referencia del jugador que muere

# Eliminar _ready, body_entered, area_entered, _trigger_death
# y dejar solo _start_death_sequence y _restart_game

# -------------------------------------------------------------
# FUNCIÓN PÚBLICA (El jugador llama a esta función al morir)
# -------------------------------------------------------------

func handle_player_death(player):
	if has_triggered:
		return
		
	has_triggered = true
	player_ref = player
	
	print("💀 GameOverHandler: Jugador murió, iniciando secuencia.")
	
	# Detener al jugador (usa call_deferred para evitar problemas de _physics_process)
	player.call_deferred("set_physics_process", false)
	player.call_deferred("set_process", false)
	player.velocity = Vector3.ZERO
	
	# Mostrar mensaje
	if show_message and player.has_method("show_immediate_notification"):
		player.show_immediate_notification(death_message)
	
	_start_death_sequence()


func _start_death_sequence():
	# ... (El resto de esta función es igual al original de DeathZone.gd)
	
	# Crear fade a negro
	var fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.modulate.a = 0
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.z_index = 1000
	get_tree().root.add_child(fade)
	
	# Fade out
	var tween = create_tween()
	tween.tween_property(fade, "modulate:a", 1.0, fade_duration)
	await tween.finished
	
	# Esperar un momento
	await get_tree().create_timer(restart_delay).timeout
	
	# Reiniciar el juego
	_restart_game()
	
	# Limpiar fade
	fade.queue_free()

func _restart_game():
	print("🔄 GameOverHandler: Reiniciando juego...")
	
	# Resetear el estado del jugador
	GameState.reset_player_state()
	
	# Recargar la escena actual
	get_tree().call_deferred("reload_current_scene")
