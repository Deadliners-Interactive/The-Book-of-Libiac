## Cast shadow that projects character shadow on ground using raycast.
## Updates position and opacity based on distance from ground.
class_name CastShadow
extends Node3D

# ==============================================================================
# Constants
# ==============================================================================

const SHADOW_BIAS: float = 0.02

# ==============================================================================
# Onready Variables
# ==============================================================================

@onready var _ray_cast_3d: RayCast3D = $RayCast3D
@onready var _sprite_3d: Sprite3D = $Sprite3D

# ==============================================================================
# Member Variables
# ==============================================================================

var _ray_collision_point: Vector3 = Vector3.ZERO


# ==============================================================================
# Lifecycle
# ==============================================================================

func _physics_process(_delta: float) -> void:
	# Get ground collision point from raycast
	if _ray_cast_3d.is_colliding():
		_ray_collision_point = _ray_cast_3d.get_collision_point()
	else:
		_ray_collision_point = _ray_cast_3d.global_position + _ray_cast_3d.target_position

	# Update shadow position with bias to avoid z-fighting
	_sprite_3d.global_position.y = _ray_collision_point.y + SHADOW_BIAS

	# Update opacity based on distance from ground
	var distance_to_ground: float = _ray_cast_3d.global_position.y - _ray_collision_point.y
	_sprite_3d.modulate.a = clamp(1.0 - distance_to_ground / 10.0, 0.0, 1.0)
