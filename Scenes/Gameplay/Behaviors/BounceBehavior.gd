## Simple bounce walk behavior that moves character in a line and bounces on walls.
## Keeps entity within a defined radius from spawn point.
extends Node
class_name BounceWalkBehavior

# ==============================================================================
# Exports
# ==============================================================================

@export_group("Bounce Settings")
@export var _speed: float = 0.5
@export_range(0, 360, 1) var _initial_angle_degrees: float = 45.0
@export var _bounce_limit_radius: float = 10.0

# ==============================================================================
# Member Variables
# ==============================================================================

var _character: CharacterBody3D
var _is_paused: bool = false
var _start_position: Vector3 = Vector3.ZERO
var _direction: Vector3 = Vector3.ZERO

# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	# Get reference to parent CharacterBody3D
	if get_parent() is CharacterBody3D:
		_character = get_parent() as CharacterBody3D
	else:
		push_error("BounceWalkBehavior must be direct child of CharacterBody3D")
		set_physics_process(false)
		return

	# Store initial position for radius calculation
	_start_position = _character.global_position
	_start_position.y = 0

	_set_initial_direction()


func _physics_process(_delta: float) -> void:
	if _is_paused or not _character:
		if _character:
			_character.velocity = Vector3.ZERO
		return

	_update_direction_on_wall()

	# Enforce radius limit
	if _is_outside_limit():
		_force_direction_back()

	# Apply velocity to parent CharacterBody3D
	_character.velocity.x = _direction.x * _speed
	_character.velocity.z = _direction.z * _speed

	# Notify parent of direction for sprite flip and animation
	if _character.has_method("flip_sprite"):
		_character.flip_sprite(_direction.x > 0)
	if _character.has_method("_play_default_animation"):
		_character.call("_play_default_animation")

# ==============================================================================
# Public Methods
# ==============================================================================

func pause() -> void:
	_is_paused = true
	set_physics_process(false)

# ==============================================================================
# Private Methods
# ==============================================================================

func _set_initial_direction() -> void:
	var angle_radians: float = deg_to_rad(_initial_angle_degrees)
	_direction = Vector3(cos(angle_radians), 0, sin(angle_radians)).normalized()


func _is_outside_limit() -> bool:
	var current_pos_flat: Vector3 = _character.global_position
	current_pos_flat.y = 0

	var distance: float = _start_position.distance_to(current_pos_flat)

	return distance > _bounce_limit_radius


func _force_direction_back() -> void:
	var vector_to_center: Vector3 = _start_position - _character.global_position
	vector_to_center.y = 0

	_direction = vector_to_center.normalized()


func _update_direction_on_wall() -> void:
	if _character.is_on_wall():
		var wall_normal: Vector3 = _character.get_wall_normal()
		_direction = _direction.bounce(wall_normal)

		# Keep direction in XZ plane
		_direction.y = 0
		_direction = _direction.normalized()
	
func resume():
	is_paused = false
	set_physics_process(true)
	
func stop():
	set_physics_process(false)
