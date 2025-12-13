extends Node

# ================================
# REFERENCIAS
# ================================
@export var actor_path: NodePath  # Path al Actor (el ladrón del pescado)
@export var waypoint_path: NodePath  # Path al waypoint donde desaparece

@onready var cinematic_manager = get_node("/root/Main/CinematicManager")
@onready var actor = get_node(actor_path) if actor_path else null

var has_played: bool = false

# ==============================================================================
# INICIALIZACIÓN
# ==============================================================================
func _ready():
	# Conectar con el CinematicManager
	if not cinematic_manager:
		push_error("❌ IntroGameCinematic: No se encuentra CinematicManager")
		return
	
	# Conectar señal de fin de cinemática
	cinematic_manager.dialogue_finished.connect(_on_cinematic_finished)
	
	# Esperar un frame para que todo esté inicializado
	call_deferred("_start_intro")

func _start_intro():
	if has_played:
		return
	
	has_played = true
	
	# PASO 1: El actor se mueve hacia el waypoint
	if actor:
		_move_actor_to_waypoint()
	
	# PASO 2: Esperar un momento antes de mostrar el diálogo
	await get_tree().create_timer(1.5).timeout
	
	# PASO 3: Mostrar el diálogo de Rupicola
	var intro_dialogue = [
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

func _move_actor_to_waypoint():
	if not actor or not waypoint_path:
		return
	
	var waypoint = get_node(waypoint_path)
	if not waypoint:
		push_warning("⚠️ IntroGameCinematic: No se encuentra el waypoint")
		return
	
	# Aquí implementas el movimiento del actor
	# Si tu Actor tiene un script de IA, puedes llamar a su función de movimiento
	# Por ejemplo:
	if actor.has_method("move_to_position"):
		actor.move_to_position(waypoint.global_position)
	
	# O usar un Tween para moverlo manualmente
	var tween = create_tween()
	tween.tween_property(actor, "global_position", waypoint.global_position, 2.0)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	# Cuando llegue al waypoint, hacerlo desaparecer
	tween.finished.connect(func():
		actor.queue_free()
	)

# ==============================================================================
# CALLBACKS
# ==============================================================================

func _on_intro_dialogue_finished():
	print("✅ IntroGameCinematic: Diálogo de introducción completado")
	# Aquí puedes añadir lógica adicional, como:
	# - Activar objetivos del juego
	# - Mostrar un tutorial
	# - etc.

func _on_cinematic_finished():
	print("🎬 IntroGameCinematic: Cinemática finalizada, el juego puede continuar")
