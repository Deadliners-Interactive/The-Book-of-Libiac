extends Area3D

# ==============================================================================
# DEATH ZONE - Detecta al jugador y reinicia el juego
# ==============================================================================
# Úsalo para abismos, lava, trampas letales, etc.

@export var death_message: String = "¡Has caído al vacío!"
@export var show_message: bool = true
@export var fade_duration: float = 1.0
@export var restart_delay: float = 0.5  # Tiempo antes de reiniciar después del fade

var has_triggered: bool = false

func _ready():
	add_to_group("death_zone")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _on_body_entered(body):
	if body.is_in_group("player") and not has_triggered:
		_trigger_death(body)

func _on_area_entered(area):
	# Detectar si el Area3D hijo del player (DetectionArea) entró
	if area.get_parent() and area.get_parent().is_in_group("player") and not has_triggered:
		var player = area.get_parent()
		_trigger_death(player)

func _trigger_death(player):
	if has_triggered:
		return
	
	has_triggered = true
	
	print("💀 DeathZone: Jugador entró en zona de muerte")
	
	# Detener al jugador
	player.set_physics_process(false)
	player.set_process(false)
	player.velocity = Vector3.ZERO
	
	# Mostrar mensaje si está habilitado
	if show_message and player.has_method("show_immediate_notification"):
		player.show_immediate_notification(death_message)
	
	# Iniciar secuencia de muerte
	_start_death_sequence()

func _start_death_sequence():
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
	print("🔄 DeathZone: Reiniciando juego...")
	
	# Resetear el estado del jugador
	GameState.reset_player_state()
	
	# Recargar la escena actual
	get_tree().call_deferred("reload_current_scene")
