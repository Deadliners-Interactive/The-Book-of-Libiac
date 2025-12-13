# IntroGameCinematic.gd
# Cinemática inicial del juego
# Extiende Node

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
	# Conectar con el CinematicManager
	if not cinematic_manager:
		push_error("❌ IntroGameCinematic: No se encuentra CinematicManager")
		return

	# Conectar señal de fin de cinemática
	cinematic_manager.dialogue_finished.connect(_on_cinematic_finished)

	# Esperar un frame para inicializar todo correctamente
	call_deferred("_start_intro")

# ==============================================================================
# SECUENCIA DE INTRO
# ==============================================================================
func _start_intro() -> void:
	if has_played:
		return

	has_played = true

	# PASO 1: Mover actor hacia el waypoint
	if actor:
		await _move_actor_to_waypoint()

	# PASO 2: Esperar antes del diálogo
	await get_tree().create_timer(1.5).timeout

	# PASO 3: Mostrar diálogo
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
# LÓGICA DEL ACTOR (LADRÓN)
# ==============================================================================

# Función asíncrona que espera a que el actor termine de moverse
func _move_actor_to_waypoint() -> void:
	if not actor or not waypoint_path:
		return

	var waypoint = get_node(waypoint_path)
	if not waypoint:
		push_warning("⚠️ IntroGameCinematic: No se encuentra el waypoint")
		return

	if actor.has_method("move_to_position"):
		# Iniciar movimiento
		actor.move_to_position(waypoint.global_position)

		# Esperar a que termine
		await actor.movement_finished

		# Fade out al finalizar
		if actor.has_method("fade_out_and_disappear"):
			actor.fade_out_and_disappear(0.5)
		else:
			actor.queue_free()
	else:
		push_error("❌ El actor no tiene la función 'move_to_position'. ¿Tiene Actor.gd?")

# ==============================================================================
# CALLBACKS
# ==============================================================================
func _on_intro_dialogue_finished() -> void:
	print("✅ IntroGameCinematic: Diálogo de introducción completado")

func _on_cinematic_finished() -> void:
	print("🎬 IntroGameCinematic: Cinemática finalizada, el juego puede continuar")
