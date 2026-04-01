extends RefCounted
class_name EdgeHopController

var _cooldown_left: float = 0.0


func tick(delta: float) -> void:
	_cooldown_left = max(_cooldown_left - delta, 0.0)


func setup_raycast(
		player: CharacterBody3D,
		raycast: RayCast3D,
		raycast_name: StringName,
		probe_height: float,
		probe_depth: float
) -> RayCast3D:
	if raycast == null:
		raycast = RayCast3D.new()
		raycast.name = raycast_name
		player.add_child(raycast)

	raycast.enabled = true
	raycast.collide_with_areas = false
	raycast.collide_with_bodies = true
	raycast.position = Vector3(0.0, probe_height, 0.0)
	raycast.target_position = Vector3(0.0, -probe_depth, 0.0)
	return raycast


func try_edge_hop(
		player: CharacterBody3D,
		raycast: RayCast3D,
		config: PlayerConfig,
		was_on_floor_last_frame: bool,
		current_state: int,
		normal_state: int,
		is_jumping: bool,
		move_speed: float,
		damage_knockback_timer: Timer,
		fallback_direction: Vector3
) -> bool:
	if not config.edge_hop_enabled:
		return false

	if not was_on_floor_last_frame:
		return false

	if player.is_on_floor():
		return false

	if player.velocity.y > 0.0:
		return false

	if current_state != normal_state:
		return false

	if is_jumping:
		return false

	if _cooldown_left > 0.0:
		return false

	if not damage_knockback_timer.is_stopped():
		return false

	var input_dir: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)
	if input_dir == Vector2.ZERO:
		return false

	var move_direction: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y).normalized()
	if move_direction.length_squared() <= 0.0:
		return false

	if raycast != null:
		var probe_direction: Vector3 = move_direction
		if probe_direction.length_squared() <= 0.0 and fallback_direction.length_squared() > 0.0:
			probe_direction = fallback_direction.normalized()

		if probe_direction.length_squared() > 0.0:
			raycast.position = Vector3(
				probe_direction.x * config.edge_hop_forward_distance,
				config.edge_hop_probe_height,
				probe_direction.z * config.edge_hop_forward_distance
			)
			raycast.target_position = Vector3(0.0, -config.edge_hop_probe_depth, 0.0)
			raycast.force_raycast_update()

			if raycast.is_colliding():
				var hit_local: Vector3 = player.to_local(raycast.get_collision_point())
				var step_down_height: float = raycast.position.y - hit_local.y
				if step_down_height <= config.edge_hop_step_down_threshold:
					return false

	player.velocity.x = move_direction.x * max(move_speed, config.edge_hop_forward_boost)
	player.velocity.z = move_direction.z * max(move_speed, config.edge_hop_forward_boost)
	player.velocity.y = max(player.velocity.y, config.edge_hop_vertical_boost)
	_cooldown_left = config.edge_hop_cooldown
	return true
