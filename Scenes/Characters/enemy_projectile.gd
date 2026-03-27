## Enemy projectile fired by floating enemies.
## Travels in a direction, damages player on impact, expires after max_lifetime.
extends Area3D

# ==============================================================================
# Member Variables
# ==============================================================================

var _direction: Vector3 = Vector3.FORWARD
var _speed: float = 8.0
var _damage: float = 5.0
var _max_lifetime: float = 3.0
var _shooter_ref: Node3D = null

# ==============================================================================
# Lifecycle
# ==============================================================================

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(_max_lifetime).timeout.connect(queue_free)


func _process(delta: float) -> void:
	global_position += _direction * _speed * delta

# ==============================================================================
# Public Methods
# ==============================================================================

func initialize(dir: Vector3, spd: float, dmg: float, shooter: Node3D) -> void:
	_direction = dir.normalized()
	_speed = spd
	_damage = dmg
	_shooter_ref = shooter
	look_at(global_position + _direction)

# ==============================================================================
# Private Methods - Signal Handlers
# ==============================================================================

func _on_body_entered(body: Node3D) -> void:
	# Ignore the shooter
	if body == _shooter_ref:
		return

	# Hit player: apply damage and knockback
	if body.is_in_group("player"):
		if body.has_method("take_damage_hearts_with_knockback"):
			var knockback_force: float = 0.05
			body.take_damage_hearts_with_knockback(_damage, _direction, knockback_force)

		queue_free()

	# Hit environment: disappear
	if not body.is_in_group("player") and not body.is_in_group("enemy"):
		queue_free()
