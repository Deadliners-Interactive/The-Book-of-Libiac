extends RefCounted
class_name CombatController

var enemies_hit: Array = []
var is_invulnerable: bool = false


func start_attack(animated_sprite: AnimatedSprite3D, attack_animation: StringName) -> void:
	enemies_hit.clear()
	animated_sprite.speed_scale = 2.0
	animated_sprite.play(attack_animation)


func activate_attack_hitbox(player: Node, attack_collision: CollisionShape3D, attack_state: int) -> void:
	if player.current_state != attack_state:
		return

	attack_collision.set_deferred("disabled", false)
	player.get_tree().create_timer(0.15).timeout.connect(func() -> void:
		if player.current_state == attack_state:
			attack_collision.set_deferred("disabled", true)
	)


func handle_attack_hit(player: Node3D, body: Node3D, attack_collision: CollisionShape3D, attack_damage: int) -> void:
	if attack_collision.disabled:
		return

	if body.has_method("take_damage") and body != player and body not in enemies_hit:
		enemies_hit.append(body)
		body.take_damage(attack_damage)


func start_damage(animated_sprite: AnimatedSprite3D, damage_visual_timer: Timer, invulnerability_time: float, damage_visual_time: float) -> void:
	is_invulnerable = true
	damage_visual_timer.start(invulnerability_time)
	animated_sprite.modulate = Color(1, 0.5, 0.5, 1)
	animated_sprite.get_tree().create_timer(damage_visual_time).timeout.connect(func() -> void:
		if is_invulnerable:
			animated_sprite.modulate = Color.WHITE
	)


func clear_invulnerability(animated_sprite: AnimatedSprite3D) -> void:
	is_invulnerable = false
	animated_sprite.modulate = Color.WHITE
