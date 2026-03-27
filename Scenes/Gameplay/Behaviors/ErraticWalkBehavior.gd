## Erratic walk behavior with smooth direction changes.
## Character randomly changes direction after traveling a short distance or bouncing on walls.
extends Node
class_name ErraticWalkBehavior

# ==============================================================================
# Exports
# ==============================================================================

@export_group("Erratic Settings")
@export var _speed: float = 0.5
@export_range(0, 180, 1) var _turn_angle_range_degrees: float = 90.0
@export_range(0.02, 800, 0.01) var _travel_distance: float = 0.02
@export_range(0.1, 1.0, 0.1) var _direction_weight: float = 0.5

# ==============================================================================
# Member Variables
# ==============================================================================

var _character: CharacterBody3D
var _is_paused: bool = false
var _direction: Vector3 = Vector3.ZERO
var _distance_traveled: float = 0.0

# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	if get_parent() is CharacterBody3D:
		_character = get_parent() as CharacterBody3D
	else:
		push_error("ErraticWalkBehavior must be direct child of CharacterBody3D")
		set_physics_process(false)
		return

	_update_direction(true)


func _physics_process(delta: float) -> void:
	if _is_paused or not _character:
		if _character:
			_character.velocity = Vector3.ZERO
		return

	var current_velocity_magnitude: float = _character.velocity.length()

	if _check_collision_and_bounce():
		# Reset distance on wall bounce
		_distance_traveled = 0.0
	else:
		# Accumulate traveled distance
		_distance_traveled += current_velocity_magnitude * delta

		# Force new direction after travel threshold
		if _distance_traveled >= _travel_distance:
			_update_direction()

	# Smooth velocity transition using lerp
	var target_velocity: Vector3 = _direction * _speed
	_character.velocity = _character.velocity.lerp(target_velocity, _direction_weight)

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

func _update_direction(initial: bool = false) -> void:
	if initial:
		var angle: float = randf_range(0, TAU)
		_direction = Vector3(cos(angle), 0, sin(angle)).normalized()
	else:
		# Apply random turn
		var angle_degrees: float = randf_range(-_turn_angle_range_degrees, _turn_angle_range_degrees)
		var angle_radians: float = deg_to_rad(angle_degrees)

		# Rotate in XZ plane
		_direction = _direction.rotated(Vector3.UP, angle_radians)

		_direction.y = 0
		_direction = _direction.normalized()

	_distance_traveled = 0.0


func _check_collision_and_bounce() -> bool:
	if _character.is_on_wall():
		var wall_normal: Vector3 = _character.get_wall_normal()

		# Bounce off wall
		_direction = _direction.bounce(wall_normal)

		_direction.y = 0
		_direction = _direction.normalized()

		return true
	return false
	
func resume():
	is_paused = false
	set_physics_process(true)
	
func stop():
	set_physics_process(false)
