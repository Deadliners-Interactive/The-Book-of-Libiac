extends BaseEnemyBehavior
class_name PatrolBehavior

enum PatrolType {
	PING_PONG, # Moverse entre puntos A y B
	RANDOM,    # Moverse a un punto aleatorio en un radio
	CIRCULAR   # Patrullar puntos formando un ciclo
}

@export_group("Patrol Settings")
@export var patrol_type: PatrolType = PatrolType.PING_PONG
@export var points: Array[Node3D] # Array de nodos Node3D en el mapa
@export var speed: float = 3.0
@export var acceptance_radius: float = 0.5 # Distancia para considerar el punto alcanzado

@export_group("Random Mode")
@export var random_radius: float = 10.0 # Radio máximo para movimiento aleatorio

var current_point_index: int = 0
var direction_forward: bool = true # Usado para PING_PONG
var target_position: Vector3 = Vector3.ZERO

func _ready():
	super._ready()
	
	# Inicializar la posición objetivo al comienzo
	if character and is_active:
		if patrol_type == PatrolType.RANDOM:
			_set_random_target()
		elif points.size() > 0:
			target_position = points[current_point_index].global_position

func _physics_process(delta):
	if not is_active or is_paused or not character:
		# Si está pausado/inactivo, forzar velocidad cero
		if character:
			character.velocity.x = 0
			character.velocity.z = 0
		return
		
	_handle_patrol_logic(delta)
	_move(delta)

func _handle_patrol_logic(_delta: float): # Corregida advertencia de delta
	# Calcular la distancia plana (ignorando Y)
	var dist_sq = (target_position.x - character.global_position.x)**2 + (target_position.z - character.global_position.z)**2

	if dist_sq < acceptance_radius * acceptance_radius:
		# Se alcanzó el objetivo, cambiar al siguiente objetivo
		match patrol_type:
			PatrolType.PING_PONG:
				_next_ping_pong_point()
			PatrolType.RANDOM:
				_set_random_target()
			PatrolType.CIRCULAR:
				_next_circular_point()

func _move(_delta: float): # Corregida advertencia de delta
	# 1. Aplanar las posiciones a X/Z (CORRECCIÓN DE SINTAXIS)
	# Crear una copia de las posiciones y establecer Y a 0
	var char_pos_flat = character.global_position
	char_pos_flat.y = 0
	
	var target_pos_flat = target_position
	target_pos_flat.y = 0
	
	# 2. Calcular la dirección plana hacia el objetivo
	var direction = (target_pos_flat - char_pos_flat).normalized()
	
	# Aplicar la velocidad al CharacterBody3D del padre
	character.velocity.x = direction.x * speed
	character.velocity.z = direction.z * speed
	
	# Voltear el sprite usando la función auxiliar del enemigo principal
	if character.has_method("flip_sprite"):
		var facing_right = direction.x > 0
		character.flip_sprite(facing_right)
		
	# Notificar al enemigo principal que siga la animación de movimiento
	if character.has_method("_play_default_animation"):
		character._play_default_animation()

# --- LÓGICA DE PATRONES ---

func _next_ping_pong_point():
	if points.size() < 2: 
		target_position = character.global_position
		return
	
	if direction_forward:
		current_point_index += 1
		if current_point_index >= points.size():
			direction_forward = false
			current_point_index = points.size() - 2
	else:
		current_point_index -= 1
		if current_point_index < 0:
			direction_forward = true
			current_point_index = 1
			
	target_position = points[current_point_index].global_position

func _next_circular_point():
	if points.size() < 2: 
		target_position = character.global_position
		return
		
	current_point_index = (current_point_index + 1) % points.size()
	target_position = points[current_point_index].global_position

func _set_random_target():
	if not character: return

	# Generar un punto aleatorio dentro del radio
	var random_angle = randf() * TAU
	var random_dist = randf_range(acceptance_radius, random_radius)
	
	var offset = Vector3(
		cos(random_angle) * random_dist,
		0, 
		sin(random_angle) * random_dist
	)
	
	target_position = character.global_position + offset
