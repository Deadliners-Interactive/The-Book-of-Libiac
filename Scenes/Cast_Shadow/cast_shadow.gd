class_name CastShadow extends Node3D

@onready var ray_cast_3d: RayCast3D = $RayCast3D
@onready var sprite_3d: Sprite3D = $Sprite3D

var ray_collision_point: Vector3 = Vector3.ZERO

func _physics_process(_delta: float) -> void:
	# Detectar la coordenada de colisión del suelo para el raycast
	if ray_cast_3d.is_colliding():
		ray_collision_point = ray_cast_3d.get_collision_point()
	else:
		ray_collision_point = ray_cast_3d.global_position + ray_cast_3d.target_position
		
	#Actualizar la posicion de la sombra con la coordenada y
	sprite_3d.global_position.y = ray_collision_point.y	
	var distance_to_ground = ray_cast_3d.global_position.y - ray_collision_point.y
	sprite_3d.modulate.a = clamp(1.0 - distance_to_ground / 10.0, 0.0, 1.0)
	
	
	
