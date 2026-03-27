extends Node
class_name BounceWalkBehavior

## Comportamiento simple de movimiento: Mueve al enemigo en línea recta,
## rebota en paredes y se mantiene dentro de un radio definido.

@export_group("Bounce Settings")
@export var speed: float = 0.5
@export_range(0, 360, 1) var initial_angle_degrees: float = 45.0
@export var bounce_limit_radius: float = 10.0

# Referencia al CharacterBody3D padre (Enemy.gd)
var character: CharacterBody3D 
var is_paused: bool = false
var start_position: Vector3 = Vector3.ZERO # Posición inicial para el límite

# La dirección se almacena como Vector3 (plano XZ)
var direction: Vector3 = Vector3.ZERO


func _ready() -> void:
	# 1. Obtener la referencia al CharacterBody3D padre
	if get_parent() is CharacterBody3D:
		character = get_parent() as CharacterBody3D
	else:
		push_error("BounceWalkBehavior debe ser hijo directo de un CharacterBody3D (el enemigo).")
		set_physics_process(false)
		return
	
	# 2. ALMACENAR LA POSICIÓN INICIAL (CORRECCIÓN DE SINTAXIS)
	# Copiamos la posición global y luego forzamos Y a 0 para el cálculo de distancia plana.
	start_position = character.global_position
	start_position.y = 0 # <--- Forma segura y compatible de aplanar el vector
	
	_set_initial_direction()


func _set_initial_direction() -> void:
	var angle_radians = deg_to_rad(initial_angle_degrees)
	direction = Vector3(cos(angle_radians), 0, sin(angle_radians)).normalized()


func _physics_process(_delta: float) -> void:
	if is_paused or not character:
		if character:
			character.velocity = Vector3.ZERO
		return
		
	_update_direction_on_wall()
	
	# 1. Controlar el Límite de Radio
	if _is_outside_limit():
		_force_direction_back()
		
	# 2. Aplicar la velocidad al CharacterBody3D del padre
	character.velocity.x = direction.x * speed
	character.velocity.z = direction.z * speed
	
	# 3. Notificar al padre Enemy para voltear el sprite y animar
	if character.has_method("flip_sprite"):
		character.flip_sprite(direction.x > 0)
	if character.has_method("_play_default_animation"):
		character._play_default_animation()


func _is_outside_limit() -> bool:
	# 1. Obtener la posición actual aplanada (CORRECCIÓN DE SINTAXIS)
	var current_pos_flat = character.global_position
	current_pos_flat.y = 0 # <--- Forma segura de aplanar
	
	var distance = start_position.distance_to(current_pos_flat)
	
	return distance > bounce_limit_radius


func _force_direction_back() -> void:
	# Calcula el vector que apunta desde la posición actual de vuelta a la posición inicial
	var vector_to_center = start_position - character.global_position
	vector_to_center.y = 0 # <--- Asegurar que el vector sea plano
	
	# Establece la nueva dirección hacia el centro
	direction = vector_to_center.normalized()


func _update_direction_on_wall() -> void:
	if character.is_on_wall():
		var wall_normal = character.get_wall_normal()
		direction = direction.bounce(wall_normal)
		
		# Asegurarse de que la dirección permanezca en el plano XZ
		direction.y = 0
		direction = direction.normalized()


# --- MÉTODOS DE COMUNICACIÓN (Respuesta a _notify_behaviors en Enemy.gd) ---

func pause():
	is_paused = true
	set_physics_process(false)
	
func resume():
	is_paused = false
	set_physics_process(true)
	
func stop():
	set_physics_process(false)
