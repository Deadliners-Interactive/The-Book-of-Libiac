extends Node
class_name ErraticWalkBehavior

## Implementa un movimiento errático y suave. El enemigo cambia de dirección
## después de recorrer una distancia muy corta (0.02) o al rebotar en una pared.

@export_group("Erratic Settings")
@export var speed: float = 0.5
@export_range(0, 180, 1) var turn_angle_range_degrees: float = 90.0
@export_range(0.02, 800, 0.01) var travel_distance: float = 0.02 # <--- Valor optimizado: 0.02
@export_range(0.1, 1.0, 0.1) var direction_weight: float = 0.5

# Referencia al CharacterBody3D padre (Enemy.gd)
var character: CharacterBody3D
var is_paused: bool = false
var direction: Vector3 = Vector3.ZERO
var distance_traveled: float = 0.0


func _ready() -> void:
	if get_parent() is CharacterBody3D:
		character = get_parent() as CharacterBody3D
	else:
		push_error("ErraticWalkBehavior debe ser hijo directo de un CharacterBody3D (el enemigo).")
		set_physics_process(false)
		return

	_update_direction(true)


# Actualiza la dirección del vector. Si no es inicial, aplica una rotación aleatoria.
func _update_direction(initial: bool = false) -> void:
	if initial:
		var angle = randf_range(0, TAU)
		direction = Vector3(cos(angle), 0, sin(angle)).normalized()
	else:
		# Calcular y aplicar el giro aleatorio
		var angle_degrees = randf_range(-turn_angle_range_degrees, turn_angle_range_degrees)
		var angle_radians = deg_to_rad(angle_degrees)
		
		# Rotar el vector 3D en el plano XZ usando Vector3.rotated()
		direction = direction.rotated(Vector3.UP, angle_radians)
		
		direction.y = 0
		direction = direction.normalized()

	distance_traveled = 0.0


# Se llama en _physics_process
func _check_collision_and_bounce() -> bool:
	if character.is_on_wall():
		var wall_normal = character.get_wall_normal()
		
		# Rebote: Cambiar la dirección reflejándola
		direction = direction.bounce(wall_normal)
		
		direction.y = 0
		direction = direction.normalized()
		
		return true
	return false


func _physics_process(delta: float) -> void:
	if is_paused or not character:
		if character:
			character.velocity = Vector3.ZERO
		return
		
	var current_velocity_magnitude = character.velocity.length()
	
	if _check_collision_and_bounce():
		# Si rebota, reseteamos la distancia inmediatamente
		distance_traveled = 0.0
	else:
		# Acumular distancia recorrida
		distance_traveled += current_velocity_magnitude * delta 
		
		# Si la distancia alcanza el umbral de 0.02, forzar un nuevo giro aleatorio
		if distance_traveled >= travel_distance:
			_update_direction()

	# Mover el CharacterBody3D usando LERP para suavizar el cambio de velocidad/dirección
	var target_velocity = direction * speed
	character.velocity = character.velocity.lerp(target_velocity, direction_weight)
	
	# Notificar al padre para voltear el sprite y animar
	if character.has_method("flip_sprite"):
		character.flip_sprite(direction.x > 0)
	if character.has_method("_play_default_animation"):
		character._play_default_animation()


# --- MÉTODOS DE COMUNICACIÓN (Para que Enemy.gd pueda Pausar/Reanudar) ---

func pause():
	is_paused = true
	set_physics_process(false)
	
func resume():
	is_paused = false
	set_physics_process(true)
	
func stop():
	set_physics_process(false)
