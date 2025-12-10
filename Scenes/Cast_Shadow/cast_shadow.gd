class_name CastShadow extends Node3D

@onready var ray_cast_3d: RayCast3D = $RayCast3D
@onready var sprite_3d: Sprite3D = $Sprite3D

var ray_collision_point: Vector3 = Vector3.ZERO

# Este pequeño valor eleva la sombra para evitar el Z-Fighting (tiling)
const SHADOW_BIAS: float = 0.02 

func _physics_process(_delta: float) -> void:
	# 1. Detectar la coordenada de colisión del suelo
	if ray_cast_3d.is_colliding():
		ray_collision_point = ray_cast_3d.get_collision_point()
	else:
		ray_collision_point = ray_cast_3d.global_position + ray_cast_3d.target_position
		
	# 2. Actualizar la posición de la sombra
	# Aquí sumamos el SHADOW_BIAS para que la sombra flote un milímetro sobre el suelo
	sprite_3d.global_position.y = ray_collision_point.y + SHADOW_BIAS
	
	# 3. Calcular opacidad según la distancia
	var distance_to_ground = ray_cast_3d.global_position.y - ray_collision_point.y
	sprite_3d.modulate.a = clamp(1.0 - distance_to_ground / 10.0, 0.0, 1.0)
