extends RefCounted
class_name DirectionAnimationController


func update_facing_from_input(
		animated_sprite: AnimatedSprite3D,
		attack_area: Node3D,
		input_dir: Vector2,
		last_move_input: Vector2,
		is_facing_right: bool,
		move_side_animation: StringName,
		move_up_animation: StringName,
		move_down_animation: StringName
) -> Dictionary:
	var result: Dictionary = {
		"last_move_input": last_move_input,
		"is_facing_right": is_facing_right,
		"last_move_animation": move_side_animation,
	}

	if input_dir == Vector2.ZERO:
		return result

	var normalized_input: Vector2 = input_dir.normalized()
	result["last_move_input"] = normalized_input

	if abs(input_dir.x) >= abs(input_dir.y):
		result["last_move_animation"] = move_side_animation
		result["is_facing_right"] = input_dir.x > 0.0
		animated_sprite.flip_h = not result["is_facing_right"]
		attack_area.scale.x = 1.0 if result["is_facing_right"] else -1.0
		return result

	if input_dir.y < 0.0:
		result["last_move_animation"] = move_up_animation
	else:
		result["last_move_animation"] = move_down_animation

	animated_sprite.flip_h = false
	return result


func get_last_facing_direction_3d(last_move_input: Vector2, is_facing_right: bool) -> Vector3:
	if last_move_input.length_squared() > 0.0:
		return Vector3(last_move_input.x, 0.0, last_move_input.y).normalized()

	var side_direction: float = 1.0 if is_facing_right else -1.0
	return Vector3(side_direction, 0.0, 0.0)


func get_move_animation_name(direction: Vector3, move_side_animation: StringName, move_up_animation: StringName, move_down_animation: StringName) -> StringName:
	var horizontal: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if horizontal.length_squared() <= 0.0001:
		return move_side_animation

	if abs(horizontal.z) > abs(horizontal.x):
		if horizontal.z < 0.0:
			return move_up_animation
		return move_down_animation

	return move_side_animation


func get_roll_animation_name(
		direction: Vector3,
		last_move_animation: StringName,
		roll_side_animation: StringName,
		roll_up_animation: StringName,
		roll_down_animation: StringName,
		move_side_animation: StringName,
		move_up_animation: StringName,
		move_down_animation: StringName
) -> StringName:
	var horizontal: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if horizontal.length_squared() <= 0.0001:
		match last_move_animation:
			roll_up_animation, move_up_animation:
				return roll_up_animation
			roll_down_animation, move_down_animation:
				return roll_down_animation
			roll_side_animation, move_side_animation:
				return roll_side_animation
			_:
				return roll_side_animation

	if abs(horizontal.z) > abs(horizontal.x):
		if horizontal.z < 0.0:
			return roll_up_animation
		return roll_down_animation

	return roll_side_animation


func get_jump_animation_name(
		last_move_animation: StringName,
		move_side_animation: StringName,
		move_up_animation: StringName,
		move_down_animation: StringName,
		jump_side_animation: StringName,
		jump_up_animation: StringName,
		jump_down_animation: StringName
) -> StringName:
	match last_move_animation:
		move_up_animation, jump_up_animation:
			return jump_up_animation
		move_down_animation, jump_down_animation:
			return jump_down_animation
		move_side_animation, jump_side_animation:
			return jump_side_animation
		_:
			return jump_side_animation


func play_animation_with_fallback(animated_sprite: AnimatedSprite3D, preferred: StringName, fallback: StringName) -> bool:
	if animated_sprite.sprite_frames.has_animation(preferred):
		animated_sprite.play(preferred)
		return true

	if animated_sprite.sprite_frames.has_animation(fallback):
		animated_sprite.play(fallback)
		return true

	return false


func play_idle_from_last_direction(animated_sprite: AnimatedSprite3D, last_move_animation: StringName, move_side_animation: StringName) -> void:
	if play_animation_with_fallback(animated_sprite, last_move_animation, move_side_animation):
		animated_sprite.stop()
		animated_sprite.frame = 0
