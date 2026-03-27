## Door that opens when player uses a key.
##
## Shakes when opening, then descends below the scene.
extends Node3D


# ==============================================================================
# Export variables
# ==============================================================================

@export var open_distance: float = 2.0
@export var open_speed: float = 1.5
@export var shake_duration: float = 1.0
@export var shake_intensity: float = 0.05


# ==============================================================================
# Member variables
# ==============================================================================

var _is_open: bool = false
var _is_opening: bool = false
var _player_nearby: bool = false
var _last_notification_time: float = 0.0
var _notification_cooldown: float = 2.0

var _start_pos: Vector3
var _target_pos: Vector3


# ==============================================================================
# Onready variables
# ==============================================================================

@onready var _area: Area3D = %Area3D
@onready var _animatable_body: AnimatableBody3D = %AnimatableBody3D


# ==============================================================================
# Built-in methods
# ==============================================================================

func _ready() -> void:
	if not _animatable_body:
		push_error("No se encontró AnimatableBody3D!")
		return
	
	if not _area:
		push_error("No se encontró Area3D!")
		return
	
	_animatable_body.sync_to_physics = false
	
	_area.monitoring = true
	_area.monitorable = true
	
	_start_pos = global_position
	_target_pos = _start_pos - Vector3(0, open_distance, 0)
	
	if not _area.body_entered.is_connected(_on_body_entered):
		_area.body_entered.connect(_on_body_entered)
	
	if not _area.body_exited.is_connected(_on_body_exited):
		_area.body_exited.connect(_on_body_exited)


# ==============================================================================
# Private methods - Collision detection
# ==============================================================================

func _on_body_entered(body: Node) -> void:
	if _is_open or _is_opening:
		return
	
	if not body.is_in_group("player"):
		return
	
	_player_nearby = true
	
	if not body.has_method("use_key"):
		return
	
	if body.use_key():
		_is_opening = true
		
		if body.has_method("show_notification"):
			body.show_notification("Puerta abierta! (usaste una llave)")
		
		_shake_and_open()
	else:
		var current_time: float = Time.get_unix_time_from_system()
		
		if current_time - _last_notification_time >= _notification_cooldown:
			_last_notification_time = current_time
			
			if body.has_method("show_notification"):
				body.show_notification("Necesitas una llave!")


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_nearby = false


# ==============================================================================
# Private methods - Opening sequence
# ==============================================================================

func _shake_and_open() -> void:
	_area.set_deferred("monitoring", false)
	
	var mesh_instance: MeshInstance3D = (
			_animatable_body.get_node_or_null("MeshInstance3D")
	)
	if not mesh_instance:
		for child in _animatable_body.get_children():
			if child is MeshInstance3D:
				mesh_instance = child
				break
	
	if mesh_instance:
		var original_mesh_pos: Vector3 = mesh_instance.position
		var shake_count: int = int(shake_duration * 15)
		for i in range(shake_count):
			var offset_x: float = randf_range(
					-shake_intensity,
					shake_intensity
			)
			var offset_z: float = randf_range(
					-shake_intensity,
					shake_intensity
			)
			var offset_rot: float = randf_range(-0.03, 0.03)
			
			mesh_instance.position = (
					original_mesh_pos + Vector3(offset_x, 0, offset_z)
			)
			mesh_instance.rotation.y = offset_rot
			
			await get_tree().create_timer(
					shake_duration / shake_count
			).timeout
		
		mesh_instance.position = original_mesh_pos
		mesh_instance.rotation = Vector3.ZERO
	else:
		await get_tree().create_timer(shake_duration).timeout
	
	if _animatable_body:
		_animatable_body.collision_layer = 0
		_animatable_body.collision_mask = 0
	
	var open_tween: Tween = create_tween()
	open_tween.set_ease(Tween.EASE_IN)
	open_tween.set_trans(Tween.TRANS_CUBIC)
	
	open_tween.tween_property(
		self,
		"global_position:y",
		_target_pos.y,
		open_distance / open_speed
	)
	
	open_tween.finished.connect(func() -> void:
		_is_open = true
		_is_opening = false
		_fade_and_free()
	)


func _fade_and_free() -> void:
	visible = false
	
	await get_tree().process_frame
	
	queue_free()
