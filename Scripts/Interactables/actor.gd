## Simple actor (NPC) character that can be commanded to move to positions.
extends CharacterBody3D

# ==============================================================================
# Signals
# ==============================================================================

signal movement_finished

# ==============================================================================
# Exports - Configuration
# ==============================================================================

@export var move_speed: float = 2.0
@export var run_animation: String = "run"
@export var idle_animation: String = "idle"

# ==============================================================================
# Member Variables
# ==============================================================================

var _is_moving: bool = false
var _target_position: Vector3 = Vector3.ZERO

# ==============================================================================
# Onready Variables
# ==============================================================================

@onready var _animated_sprite: AnimatedSprite3D = _find_animated_sprite(self)


# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	add_to_group("enemy")

	if not _animated_sprite:
		return

	if _animated_sprite.sprite_frames.has_animation(idle_animation):
		_animated_sprite.play(idle_animation)


func _physics_process(delta: float) -> void:
	if not _is_moving:
		return

	var direction: Vector3 = (_target_position - global_position).normalized()

	if global_position.distance_to(_target_position) > 0.1:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed

		if _animated_sprite and abs(direction.x) > 0.1:
			_animated_sprite.flip_h = direction.x < 0

		move_and_slide()
	else:
		# Reached destination
		_is_moving = false
		velocity = Vector3.ZERO

		if _animated_sprite and _animated_sprite.sprite_frames.has_animation(idle_animation):
			_animated_sprite.play(idle_animation)

		movement_finished.emit()


# ==============================================================================
# Public Methods
# ==============================================================================

func move_to_position(target: Vector3) -> void:
	_target_position = Vector3(target.x, global_position.y, target.z)
	_is_moving = true

	if _animated_sprite and _animated_sprite.sprite_frames.has_animation(run_animation):
		_animated_sprite.play(run_animation)


func stop_moving() -> void:
	_is_moving = false
	velocity = Vector3.ZERO


# ==============================================================================
# Private Methods
# ==============================================================================

func _find_animated_sprite(node: Node) -> AnimatedSprite3D:
	if node is AnimatedSprite3D:
		return node

	for child in node.get_children():
		if child is AnimatedSprite3D:
			return child

		var result: AnimatedSprite3D = _find_animated_sprite(child)
		if result:
			return result

	return null

	if animated_sprite and animated_sprite.sprite_frames.has_animation(idle_animation):
		animated_sprite.play(idle_animation)

func fade_out_and_disappear(duration: float = 0.5) -> void:
	if animated_sprite:
		var tween = create_tween()
		tween.tween_property(animated_sprite, "modulate:a", 0.0, duration)
		tween.finished.connect(func():
			queue_free()
		)
	else:
		queue_free()
