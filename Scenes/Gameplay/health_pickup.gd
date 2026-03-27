## Health recovery pickup item.
##
## Heals the player when collected. Can rotate and bob up and down.
extends Node3D


# ==============================================================================
# Export variables
# ==============================================================================

@export var heal_amount: float = 10.0
@export var enable_rotation: bool = true
@export var rotation_speed: float = 2.0
@export var bob_speed: float = 2.0
@export var bob_height: float = 0.3
@export var use_billboard: bool = false


# ==============================================================================
# Member variables
# ==============================================================================

var _time_passed: float = 0.0
var _start_y: float = 0.0
var _collected: bool = false


# ==============================================================================
# Onready variables
# ==============================================================================

@onready var _sprite: Sprite3D = $Sprite3D
@onready var _area: Area3D = $Area3D


# ==============================================================================
# Built-in methods
# ==============================================================================

func _ready() -> void:
	_start_y = global_position.y
	
	if _sprite and use_billboard:
		_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_sprite.pixel_size = 0.01
	
	if _area:
		_area.monitoring = true
		_area.monitorable = true
		
		if not _area.body_entered.is_connected(_on_body_entered):
			_area.body_entered.connect(_on_body_entered)
	else:
		push_error("No se encontró Area3D!")
		return


func _process(delta: float) -> void:
	if _collected:
		return
	
	_time_passed += delta
	
	if enable_rotation:
		rotate_y(rotation_speed * delta)
	
	var new_y: float = _start_y + sin(_time_passed * bob_speed) * bob_height
	global_position.y = new_y


# ==============================================================================
# Private methods
# ==============================================================================

func _on_body_entered(body: Node) -> void:
	if _collected:
		return
	
	if not body.is_in_group("player"):
		return
	
	if not body.has_method("heal"):
		push_warning("❤️ HealthPickup: El player no tiene el método heal()")
		return
	
	if body.current_health >= body.max_health:
		if body.has_method("show_notification"):
			body.show_notification("¡Ya tienes la vida completa!")
		return
	
	_collected = true
	body.heal(heal_amount)
	
	_play_collect_effect()


func _play_collect_effect() -> void:
	set_process(false)
	
	if _area:
		_area.set_deferred("monitoring", false)
	
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(
		self,
		"global_position:y",
		global_position.y + 1.0,
		0.5
	)
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.5)
	
	if _sprite:
		tween.tween_property(_sprite, "modulate:a", 0.0, 0.5)
	
	tween.finished.connect(func() -> void:
		queue_free()
	)
