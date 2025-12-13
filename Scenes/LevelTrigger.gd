extends Area3D

# ==============================================================================
# LEVEL TRIGGER - Detecta al jugador y cambia de nivel
# ==============================================================================

@export_file("*.tscn") var target_level: String = ""
@export var spawn_point_id: String = "default"
@export var show_prompt: bool = true
@export var auto_trigger: bool = false
@export var require_key: bool = false

var player_inside: bool = false
var player_ref = null
var has_triggered: bool = false

func _ready():
	add_to_group("level_trigger")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)

func _process(_delta):
	if not auto_trigger and player_inside and not has_triggered:
		if Input.is_action_just_pressed("ui_accept"):
			trigger_level_change(player_ref)

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_inside = true
		player_ref = body
		
		if show_prompt:
			_show_prompt(body)
		
		if auto_trigger and not has_triggered:
			trigger_level_change(body)

func _on_area_entered(area):
	# Detectar si el Area3D hijo del player (DetectionArea) entró
	if area.get_parent() and area.get_parent().is_in_group("player"):
		var body = area.get_parent()
		player_inside = true
		player_ref = body
		
		if show_prompt:
			_show_prompt(body)
		
		if auto_trigger and not has_triggered:
			trigger_level_change(body)

func _on_body_exited(body):
	if body.is_in_group("player"):
		player_inside = false
		player_ref = null
		_hide_prompt(body)

func trigger_level_change(player):
	if has_triggered:
		return
	
	if target_level.is_empty():
		push_warning("⚠️ LevelTrigger: No se especificó nivel de destino")
		return
	
	# Verificar si requiere llave
	if require_key:
		if not player.has_method("use_key") or not player.use_key():
			if player.has_method("show_notification"):
				player.show_notification("Necesitas una llave para continuar!")
			return
	
	has_triggered = true
	
	# Guardar estado del jugador
	GameState.save_player_state(player)
	
	print("🚪 LevelTrigger: Cambiando a nivel:", target_level)
	
	# Usar TransitionManager para cambiar de escena
	TransitionManager.transition_to_scene(target_level, spawn_point_id)

func _show_prompt(player):
	if player.has_method("show_immediate_notification") and not auto_trigger:
		var message = "Presiona ESPACIO para continuar"
		if require_key:
			message = "Presiona ESPACIO (Requiere llave)"
		player.show_immediate_notification(message)

func _hide_prompt(player):
	# Limpiar notificación si es necesario
	pass
