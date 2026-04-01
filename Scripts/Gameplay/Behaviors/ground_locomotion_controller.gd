extends RefCounted
class_name GroundLocomotionController


func setup_terrain_motion(character: CharacterBody3D, config: PlayerConfig) -> void:
	character.up_direction = Vector3.UP
	character.floor_snap_length = config.ground_snap_length
	character.floor_max_angle = deg_to_rad(config.max_floor_angle_degrees)
	character.floor_stop_on_slope = config.floor_stop_on_slope
	character.floor_constant_speed = config.floor_constant_speed
	character.safe_margin = config.collision_safe_margin
	character.floor_block_on_wall = false


func apply_move(
		character: CharacterBody3D,
		input_dir: Vector2,
		move_speed: float,
		damage_knockback_timer: Timer,
		basis: Basis
) -> bool:
	if not damage_knockback_timer.is_stopped():
		return false

	var direction: Vector3 = (basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if direction != Vector3.ZERO:
		character.velocity.x = direction.x * move_speed
		character.velocity.z = direction.z * move_speed
		return true

	character.velocity.x = move_toward(character.velocity.x, 0.0, move_speed)
	character.velocity.z = move_toward(character.velocity.z, 0.0, move_speed)
	return false


func apply_roll_physics(
		character: CharacterBody3D,
		is_rolling: bool,
		roll_speed: float,
		last_facing_direction: Vector3
) -> void:
	if not is_rolling:
		return

	var current_vel_xz: float = Vector3(character.velocity.x, 0.0, character.velocity.z).length()
	var min_roll_motion_speed: float = max(roll_speed * 0.08, 0.06)

	if current_vel_xz < min_roll_motion_speed:
		character.velocity.x = last_facing_direction.x * roll_speed
		character.velocity.z = last_facing_direction.z * roll_speed
		return

	var roll_dir_xz: Vector3 = Vector3(character.velocity.x, 0.0, character.velocity.z).normalized()
	character.velocity.x = roll_dir_xz.x * roll_speed
	character.velocity.z = roll_dir_xz.z * roll_speed


func apply_terrain_adhesion(character: CharacterBody3D) -> void:
	if not character.is_on_floor():
		return

	var horizontal_velocity: Vector3 = Vector3(character.velocity.x, 0.0, character.velocity.z)
	if horizontal_velocity.length_squared() <= 0.0:
		return

	var adjusted_velocity: Vector3 = horizontal_velocity.slide(character.get_floor_normal())
	character.velocity.x = adjusted_velocity.x
	character.velocity.z = adjusted_velocity.z


func resolve_slope_edge_block(character: CharacterBody3D) -> bool:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir == Vector2.ZERO:
		return false

	var horizontal_velocity: Vector3 = Vector3(character.velocity.x, 0.0, character.velocity.z)
	if horizontal_velocity.length_squared() <= 0.0:
		return false

	for i: int in character.get_slide_collision_count():
		var collision: KinematicCollision3D = character.get_slide_collision(i)
		if collision == null:
			continue

		var normal: Vector3 = collision.get_normal()
		if normal.y > 0.05 and normal.y < 0.95:
			var adjusted_velocity: Vector3 = horizontal_velocity.slide(normal)
			character.velocity.x = adjusted_velocity.x
			character.velocity.z = adjusted_velocity.z
			if character.velocity.y < 0.1:
				character.velocity.y = 0.1
			return true

	if character.is_on_floor() and character.is_on_wall():
		for i: int in character.get_slide_collision_count():
			var collision: KinematicCollision3D = character.get_slide_collision(i)
			if collision == null:
				continue

			var normal: Vector3 = collision.get_normal()
			if normal.y < 0.1:
				var adjusted_velocity: Vector3 = horizontal_velocity.slide(normal)
				character.velocity.x = adjusted_velocity.x
				character.velocity.z = adjusted_velocity.z
				return true

	return false


func get_horizontal_move_direction_3d(
		input_dir: Vector2,
		velocity: Vector3,
		last_facing_direction: Vector3
) -> Vector3:
	if input_dir != Vector2.ZERO:
		return Vector3(input_dir.x, 0.0, input_dir.y).normalized()

	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length_squared() > 0.001:
		return horizontal_velocity.normalized()

	return last_facing_direction


func get_last_facing_direction_3d(last_move_input: Vector2, is_facing_right: bool) -> Vector3:
	if last_move_input.length_squared() > 0.0:
		return Vector3(last_move_input.x, 0.0, last_move_input.y).normalized()

	var side_direction: float = 1.0 if is_facing_right else -1.0
	return Vector3(side_direction, 0.0, 0.0)
