## Floating damage number display above entities.
## Displays damage amount as floating text that rises, scales, and fades out.
extends Label3D

# ==============================================================================
# Exports
# ==============================================================================

@export var _float_speed: Vector3 = Vector3(0, 1.5, 0)
@export var _duration: float = 0.8

# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	# Animate upward movement
	var tween: Tween = create_tween()
	tween.tween_property(self, "position", position + _float_speed, _duration)

	# Animate fade out
	var tween_fade: Tween = create_tween()
	tween_fade.tween_property(
		self, "modulate:a", 0.0, _duration
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

	# Scale pop effect
	scale = Vector3.ZERO
	var tween_scale: Tween = create_tween()
	tween_scale.tween_property(
		self, "scale", Vector3(1.5, 1.5, 1.5), 0.15
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween_scale.tween_property(self, "scale", Vector3.ONE, 0.1)

	# Remove when finished
	await get_tree().create_timer(_duration).timeout
	queue_free()

# ==============================================================================
# Public Methods
# ==============================================================================

func set_damage(amount: int) -> void:
	text = str(amount)
