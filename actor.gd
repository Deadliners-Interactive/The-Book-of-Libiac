# Actor.gd

extends CharacterBody3D

# ================================
# CONFIGURACIÓN
# ================================
@export var move_speed: float = 2.0
@export var run_animation: String = "run"
@export var idle_animation: String = "idle"

# ================================
# REFERENCIAS
# ================================
@onready var animated_sprite: AnimatedSprite3D = null

# ================================
# VARIABLES INTERNAS
# ================================
var is_moving: bool = false
var target_position: Vector3 = Vector3.ZERO

# ================================
# SEÑALES
# ================================
signal movement_finished

# ==============================================================================
# INICIALIZACIÓN
# ==============================================================================
func _ready() -> void:
	add_to_group("enemy")

	# Buscar AnimatedSprite3D
	animated_sprite = _find_animated_sprite(self)
	if not animated_sprite:
		push_warning("⚠️ ActorThief: No se encontró AnimatedSprite3D")
	else:
		if animated_sprite.sprite_frames.has_animation(idle_animation):
			animated_sprite.play(idle_animation)

# ==============================================================================
# UTILIDADES
# ==============================================================================

func _find_animated_sprite(node: Node) -> AnimatedSprite3D:
	if node is AnimatedSprite3D:
		return node

	for child in node.get_children():
		if child is AnimatedSprite3D:
			return child

		var result = _find_animated_sprite(child)
		if result:
			return result

	return null

# ==============================================================================
# MOVIMIENTO
# ==============================================================================
func _physics_process(delta: float) -> void:
	if not is_moving:
		return

	var direction: Vector3 = (target_position - global_position).normalized()

	if global_position.distance_to(target_position) > 0.1:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed

		if animated_sprite and abs(direction.x) > 0.1:
			animated_sprite.flip_h = direction.x < 0

		move_and_slide()
	else:
		# Llegó al destino
		is_moving = false
		velocity = Vector3.ZERO

		if animated_sprite and animated_sprite.sprite_frames.has_animation(idle_animation):
			animated_sprite.play(idle_animation)

		movement_finished.emit()

# ==============================================================================
# API PÚBLICA
# ==============================================================================

func move_to_position(target: Vector3) -> void:
	target_position = Vector3(target.x, global_position.y, target.z)
	is_moving = true

	if animated_sprite and animated_sprite.sprite_frames.has_animation(run_animation):
		animated_sprite.play(run_animation)

	print("🏃 ActorThief: Moviéndose hacia ", target_position)

func stop_moving() -> void:
	is_moving = false
	velocity = Vector3.ZERO

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
