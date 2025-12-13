# IntroGameCinematic.gd
# MODIFICADO: Diálogo y movimiento simultáneos

extends Node

# ================================
# REFERENCIAS
# ================================
@export var actor_path: NodePath                     # Path al Actor (ladrón del pescado)
@export var waypoint_path: NodePath                  # Path al waypoint donde desaparece
@export var actor_walk_animation: String = "run"     # Animación de caminar
@export var actor_idle_animation: String = "idle"    # Animación idle

@onready var cinematic_manager = get_node("/root/Main/CinematicManager")
@onready var actor = get_node(actor_path) if actor_path else null

var has_played: bool = false

# ==============================================================================
# INICIALIZACIÓN
# ==============================================================================
func _ready() -> void:
	if not cinematic_manager:
		push_error("❌ IntroGameCinematic: No se encuentra CinematicManager")
		return

	cinematic_manager.dialogue_finished.connect(_on_cinematic_finished)
	call_deferred("_start_intro")

# ==============================================================================
# SECUENCIA DE INTRO (MODIFICADO)
# ==============================================================================
func _start_intro() -> void:
	if has_played:
		return

	has_played = true
	
	# PASO 1: Iniciar movimiento del actor (pero NO esperar a que termine)
	if actor:
		# Iniciar movimiento sin esperar
		_move_actor_to_waypoint()
	
	# PASO 2: Iniciar diálogo INMEDIATAMENTE (sin esperar)
	# Solo un pequeño delay visual para que el actor dé el primer paso
	await get_tree().create_timer(0.3).timeout
	
	var intro_dialogue: Array = [
		{
			"speaker": "Rupicola",
			"text": "Hey! Ese es mi pescado!"
		},
		{
			"speaker": "Rupicola",
			"text": "El viejo Taita se enojará si llego sin la cena... ¡chesumaquina!"
		}
	]
	
	cinematic_manager.play_cinematic(intro_dialogue, _on_intro_dialogue_finished)

# ==============================================================================
# LÓGICA DEL ACTOR (MODIFICADO)
# ==============================================================================

func _move_actor_to_waypoint() -> void:
	if not actor or not waypoint_path:
		return

	var waypoint = get_node(waypoint_path)
	if not waypoint:
		push_warning("⚠️ IntroGameCinematic: No se encuentra el waypoint")
		return

	if actor.has_method("move_to_position"):
		# IMPORTANTE: No usar 'await' aquí para que no espere
		# Guardamos la conexión para limpiar después
		var movement_completed = false
		
		# Conectar señal para saber cuándo terminó
		var on_movement_finished = func():
			movement_completed = true
			if actor.has_method("fade_out_and_disappear"):
				actor.fade_out_and_disappear(0.5)
			else:
				actor.queue_free()
		
		# Conectar la señal
		if actor.movement_finished.is_connected(on_movement_finished):
			actor.movement_finished.disconnect(on_movement_finished)
		actor.movement_finished.connect(on_movement_finished)
		
		# Iniciar movimiento (continúa en background)
		actor.move_to_position(waypoint.global_position)
		
		# Opcional: Esperar hasta que termine, pero en paralelo con diálogo
		# Esto se ejecutará en paralelo si no usamos 'await'
		
	else:
		push_error("❌ El actor no tiene la función 'move_to_position'. ¿Tiene Actor.gd?")

# ==============================================================================
# CALLBACKS
# ==============================================================================
func _on_intro_dialogue_finished() -> void:
	print("✅ IntroGameCinematic: Diálogo de introducción completado")
	# El actor podría seguir moviéndose o ya haber terminado

func _on_cinematic_finished() -> void:
	print("🎬 IntroGameCinematic: Cinemática finalizada, el juego puede continuar")
